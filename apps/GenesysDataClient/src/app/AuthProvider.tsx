/**
 * Authentication state for the application.
 *
 * Owns the session, completes the redirect leg of the PKCE flow on load, and keeps the token
 * fresh. The rest of the app never touches tokens: it reads `status` and lets the CoreClient
 * carry the bearer.
 */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import {
  AuthError,
  beginSignIn,
  cleanRedirectUrl,
  clearSession,
  completeSignIn,
  environmentById,
  isExpired,
  loadAuthConfig,
  loadSession,
  refreshSession,
  saveSession,
  secondsUntilExpiry,
  signOut as revokeAndClear,
  useDemoToken,
  type AuthConfig,
  type AuthSession,
} from '../core/auth';

export type AuthStatus = 'restoring' | 'signed-out' | 'authorizing' | 'signed-in' | 'error';

export interface AuthApi {
  status: AuthStatus;
  session: AuthSession | null;
  config: AuthConfig;
  error: string | null;
  /** Seconds until the access token expires; recomputed on a timer while signed in. */
  expiresIn: number;
  signIn: (config: AuthConfig) => Promise<void>;
  signInWithDemoToken: (token: string) => void;
  signOut: () => Promise<void>;
  refreshNow: () => Promise<void>;
  dismissError: () => void;
}

const AuthContext = createContext<AuthApi | null>(null);

/** Refresh once the token is inside this window, provided a refresh token exists. */
const REFRESH_WINDOW_SECONDS = 120;

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [status, setStatus] = useState<AuthStatus>('restoring');
  const [session, setSession] = useState<AuthSession | null>(null);
  const [config, setConfig] = useState<AuthConfig>(() => loadAuthConfig());
  const [error, setError] = useState<string | null>(null);
  const [expiresIn, setExpiresIn] = useState(0);
  const completing = useRef(false);

  // Complete a redirect, or restore an existing session. Runs once.
  useEffect(() => {
    if (completing.current) return;
    completing.current = true;

    (async () => {
      try {
        const completed = await completeSignIn(location.href);
        if (completed) {
          cleanRedirectUrl();
          setSession(completed);
          setConfig(loadAuthConfig());
          setStatus('signed-in');
          return;
        }
      } catch (cause) {
        cleanRedirectUrl();
        setError(cause instanceof AuthError ? cause.message : String(cause));
        setStatus('error');
        return;
      }

      const restored = loadSession();
      if (restored && !isExpired(restored)) {
        setSession(restored);
        setStatus('signed-in');
      } else if (restored?.refreshToken) {
        try {
          const refreshed = await refreshSession(
            environmentById(restored.environmentId),
            { ...loadAuthConfig(), environmentId: restored.environmentId, clientId: restored.clientId },
            restored.refreshToken,
          );
          saveSession(refreshed);
          setSession(refreshed);
          setStatus('signed-in');
        } catch {
          clearSession();
          setStatus('signed-out');
        }
      } else {
        setStatus('signed-out');
      }
    })();
  }, []);

  // Countdown, and a refresh when the token is close to expiring.
  useEffect(() => {
    if (status !== 'signed-in' || !session) return;

    const tick = async () => {
      const remaining = secondsUntilExpiry(session);
      setExpiresIn(remaining);

      if (remaining > REFRESH_WINDOW_SECONDS) return;

      if (!session.refreshToken) {
        if (remaining <= 0) {
          clearSession();
          setSession(null);
          setStatus('signed-out');
          setError('The session expired. Sign in again to continue.');
        }
        return;
      }

      try {
        const refreshed = await refreshSession(
          environmentById(session.environmentId),
          { ...config, environmentId: session.environmentId, clientId: session.clientId },
          session.refreshToken,
        );
        saveSession(refreshed);
        setSession(refreshed);
      } catch {
        clearSession();
        setSession(null);
        setStatus('signed-out');
        setError('The session could not be refreshed. Sign in again to continue.');
      }
    };

    void tick();
    const handle = setInterval(() => void tick(), 15_000);
    return () => clearInterval(handle);
  }, [status, session, config]);

  const signIn = useCallback(async (next: AuthConfig) => {
    setError(null);
    setConfig(next);
    setStatus('authorizing');
    try {
      await beginSignIn(next);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
      setStatus('error');
    }
  }, []);

  const signInWithDemoToken = useCallback((token: string) => {
    setError(null);
    setSession(useDemoToken(token));
    setStatus('signed-in');
  }, []);

  const doSignOut = useCallback(async () => {
    const current = session;
    setSession(null);
    setStatus('signed-out');
    setError(null);
    await revokeAndClear(current);
  }, [session]);

  const refreshNow = useCallback(async () => {
    if (!session?.refreshToken) return;
    try {
      const refreshed = await refreshSession(
        environmentById(session.environmentId),
        { ...config, environmentId: session.environmentId, clientId: session.clientId },
        session.refreshToken,
      );
      saveSession(refreshed);
      setSession(refreshed);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    }
  }, [session, config]);

  const api = useMemo<AuthApi>(
    () => ({
      status,
      session,
      config,
      error,
      expiresIn,
      signIn,
      signInWithDemoToken,
      signOut: doSignOut,
      refreshNow,
      dismissError: () => setError(null),
    }),
    [status, session, config, error, expiresIn, signIn, signInWithDemoToken, doSignOut, refreshNow],
  );

  return <AuthContext.Provider value={api}>{children}</AuthContext.Provider>;
};

export const useAuth = (): AuthApi => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside an AuthProvider');
  return ctx;
};
