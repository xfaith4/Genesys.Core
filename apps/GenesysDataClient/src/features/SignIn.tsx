/**
 * Sign-in.
 *
 * One flow, two destinations. Choosing the demo environment runs the identical PKCE exchange
 * against Genesys.MockServer; choosing a region runs it against a real org. The screen shows the
 * parameters it is about to send, because the point of the demo is to make the flow legible.
 */

import { useMemo, useState } from 'react';
import {
  DEFAULT_SCOPES,
  DEMO_CLIENT_ID,
  GENESYS_ENVIRONMENTS,
  MOCK_ENVIRONMENT,
  environmentById,
  type AuthConfig,
} from '../core/auth';
import { DEMO_TOKEN } from '../core/client';
import { useAuth } from '../app/AuthProvider';
import { Badge, Button, DetailRow, Select, TextInput, Toggle } from '../components/primitives';

const CUSTOM = '__custom__';

export const SignIn = () => {
  const { config, status, error, signIn, signInWithDemoToken, dismissError } = useAuth();

  const [environmentId, setEnvironmentId] = useState(config.environmentId);
  const [customRegion, setCustomRegion] = useState('');
  const [clientId, setClientId] = useState(config.clientId);
  const [requestScopes, setRequestScopes] = useState(config.scopes.length > 0);

  const isCustom = environmentId === CUSTOM;
  const isDemo = environmentId === MOCK_ENVIRONMENT.id;
  const resolvedId = isCustom ? customRegion.trim() : environmentId;
  const environment = useMemo(
    () => (resolvedId ? environmentById(resolvedId) : MOCK_ENVIRONMENT),
    [resolvedId],
  );

  const effective: AuthConfig = {
    environmentId: resolvedId,
    clientId: clientId.trim(),
    redirectUri: config.redirectUri,
    scopes: requestScopes ? DEFAULT_SCOPES : [],
  };

  const ready = effective.clientId !== '' && resolvedId !== '';
  const busy = status === 'authorizing';

  // Switching between demo and a real org should not leave the demo client id behind.
  const onEnvironmentChange = (next: string) => {
    setEnvironmentId(next);
    if (next === MOCK_ENVIRONMENT.id) {
      setClientId(DEMO_CLIENT_ID);
      setRequestScopes(false);
    } else if (clientId === DEMO_CLIENT_ID) {
      setClientId('');
      setRequestScopes(true);
    }
  };

  return (
    <div className="signin">
      <main className="signin__card">
        <header className="signin__head">
          <h1>Genesys Data Client</h1>
          <p className="signin__sub">
            Sign in with OAuth 2.0 Authorization Code + PKCE. No client secret is used or stored.
          </p>
        </header>

        {error ? (
          <div className="signin__error" role="alert">
            <span>{error}</span>
            <Button variant="ghost" onClick={dismissError}>
              Dismiss
            </Button>
          </div>
        ) : null}

        <div className="signin__body">
          <Select
            id="signin-env"
            label="Environment"
            value={environmentId}
            onChange={onEnvironmentChange}
            options={[
              ...GENESYS_ENVIRONMENTS.map((env) => ({ value: env.id, label: env.label })),
              { value: CUSTOM, label: 'Custom region…' },
            ]}
          />

          {isCustom ? (
            <TextInput
              id="signin-region"
              label="Region suffix"
              value={customRegion}
              onChange={setCustomRegion}
              placeholder="e.g. usw2.pure.cloud"
            />
          ) : null}

          <TextInput
            id="signin-client"
            label="OAuth client id"
            value={clientId}
            onChange={setClientId}
            placeholder={isDemo ? DEMO_CLIENT_ID : 'the client id of your PKCE OAuth app'}
          />

          {!isDemo ? (
            <Toggle
              checked={requestScopes}
              onChange={setRequestScopes}
              label={`Request read-only scopes (${DEFAULT_SCOPES.length})`}
            />
          ) : null}

          <div className="signin__preview">
            <DetailRow label="Authorize">
              <code className="inline-code">{environment.loginBase || '(this server)'}/oauth/authorize</code>
            </DetailRow>
            <DetailRow label="Token">
              <code className="inline-code">{environment.loginBase || '(this server)'}/oauth/token</code>
            </DetailRow>
            <DetailRow label="API">
              <code className="inline-code">{environment.apiBase || '(this server)'}/api/v2</code>
            </DetailRow>
            <DetailRow label="Redirect URI">
              <code className="inline-code">{config.redirectUri}</code>
            </DetailRow>
            <DetailRow label="Challenge">
              <Badge tone="good">S256</Badge>
            </DetailRow>
          </div>

          <Button variant="primary" onClick={() => void signIn(effective)} disabled={!ready || busy}>
            {busy ? 'Redirecting…' : isDemo ? 'Continue with the demo authorization server' : 'Sign in to Genesys Cloud'}
          </Button>

          {isDemo ? (
            <p className="signin__note">
              The demo server implements PKCE for real: it verifies the S256 challenge and rejects a
              mismatched verifier. The identity is fixed and no credentials are requested.
            </p>
          ) : (
            <p className="signin__note">
              Your OAuth client must be a <strong>Token Implicit Grant (Code)</strong> app with PKCE
              enabled, and <code className="inline-code">{config.redirectUri}</code> registered as an
              authorized redirect URI.
            </p>
          )}
        </div>

        {isDemo ? (
          <footer className="signin__foot">
            <span>Skip the flow and use the fixed demo bearer instead:</span>
            <Button onClick={() => signInWithDemoToken(DEMO_TOKEN)} disabled={busy}>
              Use demo token
            </Button>
          </footer>
        ) : null}
      </main>
    </div>
  );
};
