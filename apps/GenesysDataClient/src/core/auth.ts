/**
 * Authentication: OAuth 2.0 Authorization Code with PKCE.
 *
 * This mirrors `modules/Genesys.Auth/Genesys.Auth.psm1`, which is Genesys.Core's authority on how
 * this repository talks to Genesys Cloud. The verifier is 32 random bytes as base64url, the
 * challenge is BASE64URL(SHA256(ASCII(verifier))), the authorize URL is
 * `https://login.{region}/oauth/authorize` and the exchange is a form-encoded POST to
 * `https://login.{region}/oauth/token`. Keeping the two implementations aligned matters: an app
 * should be able to move between the PowerShell and browser consumers without the org's OAuth
 * client needing different configuration.
 *
 * The demo environment points the same flow at Genesys.MockServer, which implements PKCE for
 * real - it verifies the S256 challenge and rejects a wrong verifier. Demo mode therefore
 * exercises this code, rather than bypassing it.
 *
 * Public client, so there is no client secret anywhere in here. That is the point of PKCE.
 */

// ─── Environments ────────────────────────────────────────────────────────────

export interface GenesysEnvironment {
  id: string;
  label: string;
  /** Region suffix, e.g. `usw2.pure.cloud`. Empty for the demo server. */
  region: string;
  /** Base for `/api/v2/...`. Empty string means same-origin, which the demo server is. */
  apiBase: string;
  /** Base for `/oauth/...`. */
  loginBase: string;
  isDemo: boolean;
}

export const MOCK_ENVIRONMENT: GenesysEnvironment = {
  id: 'mock',
  label: 'Demo — Genesys.MockServer (offline)',
  region: '',
  apiBase: '',
  loginBase: '',
  isDemo: true,
};

/**
 * Genesys Cloud regions. The list is a convenience, not a constraint: "Custom region" lets any
 * suffix be entered, so a region missing here never blocks a sign-in.
 */
const REGION_SUFFIXES: { region: string; label: string }[] = [
  { region: 'mypurecloud.com', label: 'US East (us-east-1)' },
  { region: 'usw2.pure.cloud', label: 'US West (us-west-2)' },
  { region: 'cac1.pure.cloud', label: 'Canada (ca-central-1)' },
  { region: 'mypurecloud.ie', label: 'EU West (eu-west-1)' },
  { region: 'euw2.pure.cloud', label: 'EU West (eu-west-2)' },
  { region: 'mypurecloud.de', label: 'EU Central (eu-central-1)' },
  { region: 'euc2.pure.cloud', label: 'EU Central (eu-central-2)' },
  { region: 'mypurecloud.jp', label: 'Asia Pacific (ap-northeast-1)' },
  { region: 'apne2.pure.cloud', label: 'Asia Pacific (ap-northeast-2)' },
  { region: 'mypurecloud.com.au', label: 'Asia Pacific (ap-southeast-2)' },
  { region: 'aps1.pure.cloud', label: 'Asia Pacific (ap-south-1)' },
  { region: 'sae1.pure.cloud', label: 'South America (sa-east-1)' },
  { region: 'mec1.pure.cloud', label: 'Middle East (me-central-1)' },
  { region: 'use2.us-gov-pure.cloud', label: 'US East FedRAMP (us-gov-east-1)' },
];

export const environmentForRegion = (region: string): GenesysEnvironment => ({
  id: region,
  label: REGION_SUFFIXES.find((r) => r.region === region)?.label ?? region,
  region,
  apiBase: `https://api.${region}`,
  loginBase: `https://login.${region}`,
  isDemo: false,
});

export const GENESYS_ENVIRONMENTS: GenesysEnvironment[] = [
  MOCK_ENVIRONMENT,
  ...REGION_SUFFIXES.map((r) => environmentForRegion(r.region)),
];

export const environmentById = (id: string): GenesysEnvironment =>
  id === MOCK_ENVIRONMENT.id ? MOCK_ENVIRONMENT : environmentForRegion(id);

/** Client id used against the demo server. It is not a secret and authorizes nothing real. */
export const DEMO_CLIENT_ID = 'genesys-data-client-demo';

/** Scopes worth requesting for a read-only data workbench. */
export const DEFAULT_SCOPES = [
  'analytics:readonly',
  'users:readonly',
  'routing:readonly',
  'conversations:readonly',
];

export interface AuthConfig {
  environmentId: string;
  clientId: string;
  redirectUri: string;
  scopes: string[];
}

export const defaultRedirectUri = (): string =>
  typeof location === 'undefined' ? 'http://localhost:7777/' : `${location.origin}/`;

export const defaultAuthConfig = (): AuthConfig => ({
  environmentId: MOCK_ENVIRONMENT.id,
  clientId: DEMO_CLIENT_ID,
  redirectUri: defaultRedirectUri(),
  scopes: [],
});

// ─── PKCE ────────────────────────────────────────────────────────────────────

export interface PkceChallenge {
  verifier: string;
  challenge: string;
  state: string;
}

const base64Url = (bytes: Uint8Array): string => {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

const randomBase64Url = (byteLength: number): string =>
  base64Url(crypto.getRandomValues(new Uint8Array(byteLength)));

/** BASE64URL(SHA256(ASCII(verifier))), per RFC 7636 S256. */
export const deriveChallenge = async (verifier: string): Promise<string> => {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return base64Url(new Uint8Array(digest));
};

/** 32 random bytes, matching New-GenesysPkceChallenge. */
export const createPkceChallenge = async (verifierBytes = 32): Promise<PkceChallenge> => {
  const verifier = randomBase64Url(verifierBytes);
  return {
    verifier,
    challenge: await deriveChallenge(verifier),
    state: randomBase64Url(16),
  };
};

export const buildAuthorizeUrl = (
  environment: GenesysEnvironment,
  config: AuthConfig,
  pkce: PkceChallenge,
): string => {
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    code_challenge: pkce.challenge,
    code_challenge_method: 'S256',
    state: pkce.state,
  });
  if (config.scopes.length > 0) params.set('scope', config.scopes.join(' '));
  return `${environment.loginBase}/oauth/authorize?${params.toString()}`;
};

// ─── Sessions ────────────────────────────────────────────────────────────────

export type AuthFlow = 'pkce' | 'demo-token';

export interface AuthSession {
  accessToken: string;
  refreshToken?: string;
  tokenType: string;
  /** ISO timestamp, already reduced by a safety margin. */
  expiresAt: string;
  environmentId: string;
  apiBase: string;
  clientId: string;
  flow: AuthFlow;
  obtainedAt: string;
  scope?: string;
}

/** Matches the 30 second margin Genesys.Auth applies. */
const EXPIRY_MARGIN_SECONDS = 30;

interface TokenResponse {
  access_token?: string;
  refresh_token?: string;
  token_type?: string;
  expires_in?: number;
  scope?: string;
  error?: string;
  error_description?: string;
}

export class AuthError extends Error {
  constructor(
    message: string,
    readonly code: string,
  ) {
    super(message);
    this.name = 'AuthError';
  }
}

const postForm = async (url: string, body: Record<string, string>): Promise<TokenResponse> => {
  let response: Response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
      body: new URLSearchParams(body).toString(),
    });
  } catch (cause) {
    throw new AuthError(`Could not reach the token endpoint at ${url}. ${String(cause)}`, 'network_error');
  }

  const payload = (await response.json().catch(() => ({}))) as TokenResponse;
  if (!response.ok || payload.error) {
    throw new AuthError(
      payload.error_description ?? payload.error ?? `Token request failed with ${response.status}.`,
      payload.error ?? String(response.status),
    );
  }
  if (!payload.access_token) {
    throw new AuthError('Token response did not include an access_token.', 'invalid_response');
  }
  return payload;
};

const sessionFrom = (
  payload: TokenResponse,
  environment: GenesysEnvironment,
  config: AuthConfig,
  flow: AuthFlow,
): AuthSession => {
  const lifetime = Math.max(0, (payload.expires_in ?? 3600) - EXPIRY_MARGIN_SECONDS);
  const session: AuthSession = {
    accessToken: payload.access_token as string,
    tokenType: payload.token_type ?? 'bearer',
    expiresAt: new Date(Date.now() + lifetime * 1000).toISOString(),
    environmentId: environment.id,
    apiBase: environment.apiBase,
    clientId: config.clientId,
    flow,
    obtainedAt: new Date().toISOString(),
  };
  if (payload.refresh_token) session.refreshToken = payload.refresh_token;
  if (payload.scope) session.scope = payload.scope;
  return session;
};

export const exchangeAuthorizationCode = async (
  environment: GenesysEnvironment,
  config: AuthConfig,
  code: string,
  verifier: string,
): Promise<AuthSession> => {
  const payload = await postForm(`${environment.loginBase}/oauth/token`, {
    grant_type: 'authorization_code',
    code,
    redirect_uri: config.redirectUri,
    client_id: config.clientId,
    code_verifier: verifier,
  });
  return sessionFrom(payload, environment, config, 'pkce');
};

export const refreshSession = async (
  environment: GenesysEnvironment,
  config: AuthConfig,
  refreshToken: string,
): Promise<AuthSession> => {
  const payload = await postForm(`${environment.loginBase}/oauth/token`, {
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: config.clientId,
  });
  return sessionFrom(payload, environment, config, 'pkce');
};

export const isExpired = (session: AuthSession): boolean =>
  Date.parse(session.expiresAt) <= Date.now();

export const secondsUntilExpiry = (session: AuthSession): number =>
  Math.max(0, Math.round((Date.parse(session.expiresAt) - Date.now()) / 1000));

// ─── Redirect handling ───────────────────────────────────────────────────────

export type RedirectResult =
  | { kind: 'code'; code: string; state: string }
  | { kind: 'error'; error: string; description: string; state: string }
  | null;

/** Reads an authorization result from the current URL, from either the query or the fragment. */
export const readRedirectResult = (url: string): RedirectResult => {
  const parsed = new URL(url);
  const fromQuery = parsed.searchParams;
  const fromHash = new URLSearchParams(parsed.hash.startsWith('#') ? parsed.hash.slice(1) : '');
  const pick = (key: string) => fromQuery.get(key) ?? fromHash.get(key) ?? '';

  const error = pick('error');
  if (error) {
    return { kind: 'error', error, description: pick('error_description'), state: pick('state') };
  }

  const code = pick('code');
  if (code) return { kind: 'code', code, state: pick('state') };

  return null;
};

// ─── Persistence ─────────────────────────────────────────────────────────────

const SESSION_KEY = 'genesys-data-client.session.v1';
const PENDING_KEY = 'genesys-data-client.pkce-pending.v1';
const CONFIG_KEY = 'genesys-data-client.auth-config.v1';

/**
 * Tokens live in sessionStorage, not localStorage: they are scoped to the tab and cleared when it
 * closes, which limits the blast radius compared with a value that persists across browser
 * restarts. The non-secret connection preferences are kept in localStorage so a sign-in does not
 * have to be reconfigured every time.
 */
const readJson = <T,>(store: Storage, key: string): T | null => {
  try {
    const raw = store.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
};

const writeJson = (store: Storage, key: string, value: unknown): void => {
  try {
    store.setItem(key, JSON.stringify(value));
  } catch {
    // Private browsing and blocked site data are expected; the session simply will not persist.
  }
};

const remove = (store: Storage, key: string): void => {
  try {
    store.removeItem(key);
  } catch {
    /* nothing to do */
  }
};

export const loadSession = (): AuthSession | null => {
  const session = readJson<AuthSession>(sessionStorage, SESSION_KEY);
  if (!session) return null;
  if (isExpired(session) && !session.refreshToken) {
    remove(sessionStorage, SESSION_KEY);
    return null;
  }
  return session;
};

export const saveSession = (session: AuthSession): void => writeJson(sessionStorage, SESSION_KEY, session);
export const clearSession = (): void => remove(sessionStorage, SESSION_KEY);

export interface PendingAuthorization {
  pkce: PkceChallenge;
  config: AuthConfig;
  startedAt: string;
}

export const savePending = (pending: PendingAuthorization): void =>
  writeJson(sessionStorage, PENDING_KEY, pending);
export const loadPending = (): PendingAuthorization | null =>
  readJson<PendingAuthorization>(sessionStorage, PENDING_KEY);
export const clearPending = (): void => remove(sessionStorage, PENDING_KEY);

export const saveAuthConfig = (config: AuthConfig): void => writeJson(localStorage, CONFIG_KEY, config);
export const loadAuthConfig = (): AuthConfig => ({
  ...defaultAuthConfig(),
  ...(readJson<Partial<AuthConfig>>(localStorage, CONFIG_KEY) ?? {}),
  // The redirect URI must always describe where this app is actually running.
  redirectUri: defaultRedirectUri(),
});

// ─── Flow entry points ───────────────────────────────────────────────────────

/** Starts an authorization by storing the verifier and navigating to the authorize endpoint. */
export const beginSignIn = async (config: AuthConfig): Promise<void> => {
  const environment = environmentById(config.environmentId);
  const pkce = await createPkceChallenge();

  // The verifier must outlive the redirect, and must never travel in the URL.
  savePending({ pkce, config, startedAt: new Date().toISOString() });
  saveAuthConfig(config);

  location.assign(buildAuthorizeUrl(environment, config, pkce));
};

/**
 * Completes an authorization if the current URL carries one.
 * Returns null when there is nothing to complete, so it is safe to call on every load.
 */
export const completeSignIn = async (url: string): Promise<AuthSession | null> => {
  const result = readRedirectResult(url);
  if (!result) return null;

  const pending = loadPending();
  clearPending();

  if (result.kind === 'error') {
    throw new AuthError(result.description || result.error, result.error);
  }

  if (!pending) {
    throw new AuthError(
      'An authorization code arrived without a matching request in this tab. Start the sign-in again.',
      'missing_verifier',
    );
  }

  // Without this check a third party could feed us a code of their choosing.
  if (result.state !== pending.pkce.state) {
    throw new AuthError('Authorization state did not match the request. The sign-in was abandoned.', 'state_mismatch');
  }

  const environment = environmentById(pending.config.environmentId);
  const session = await exchangeAuthorizationCode(
    environment,
    pending.config,
    result.code,
    pending.pkce.verifier,
  );
  saveSession(session);
  return session;
};

/** Strips authorization parameters from the address bar without adding a history entry. */
export const cleanRedirectUrl = (): void => {
  const url = new URL(location.href);
  let touched = false;
  for (const key of ['code', 'state', 'error', 'error_description']) {
    if (url.searchParams.has(key)) {
      url.searchParams.delete(key);
      touched = true;
    }
  }
  if (touched) history.replaceState(null, '', `${url.pathname}${url.search}${url.hash}`);
};

/**
 * The demo shortcut: adopt the mock server's fixed bearer token without an OAuth round trip.
 * Only offered for the demo environment, and labelled as skipping the flow.
 */
export const useDemoToken = (token: string): AuthSession => {
  const session: AuthSession = {
    accessToken: token,
    tokenType: 'bearer',
    expiresAt: new Date(Date.now() + 86_400 * 1000).toISOString(),
    environmentId: MOCK_ENVIRONMENT.id,
    apiBase: MOCK_ENVIRONMENT.apiBase,
    clientId: DEMO_CLIENT_ID,
    flow: 'demo-token',
    obtainedAt: new Date().toISOString(),
  };
  saveSession(session);
  return session;
};

/** Best-effort revocation, then local teardown. Local state is cleared either way. */
export const signOut = async (session: AuthSession | null): Promise<void> => {
  if (session && environmentById(session.environmentId).isDemo) {
    try {
      await fetch(`${environmentById(session.environmentId).loginBase}/oauth/revoke`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ token: session.accessToken }).toString(),
      });
    } catch {
      // A revocation that cannot be delivered must not block signing out locally.
    }
  }
  clearSession();
  clearPending();
};
