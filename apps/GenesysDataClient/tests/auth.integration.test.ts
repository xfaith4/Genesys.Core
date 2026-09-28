/**
 * The client's own PKCE code, run against the demo authorization server.
 *
 * This is the test that matters for the claim "demo mode exercises the real flow": it uses
 * `createPkceChallenge`, `buildAuthorizeUrl` and `exchangeAuthorizationCode` from src/core/auth.ts
 * unchanged, and only the base URL differs from a live org. If the client's S256 derivation were
 * wrong, the server would reject the exchange here.
 */

import { describe, expect, it } from 'vitest';
import {
  buildAuthorizeUrl,
  createPkceChallenge,
  exchangeAuthorizationCode,
  refreshSession,
  type AuthConfig,
  type GenesysEnvironment,
} from '../src/core/auth';
import { CoreClient } from '../src/core/client';

const BASE_URL = process.env.GDC_MOCK_SERVER ?? 'http://localhost:7777';

const serverUp = await (async () => {
  try {
    const response = await fetch(`${BASE_URL}/health`, { signal: AbortSignal.timeout(2500) });
    return response.ok;
  } catch {
    return false;
  }
})();

if (!serverUp) console.warn(`\n  SKIPPING PKCE integration tests: no demo server at ${BASE_URL}\n`);

/** The demo server, addressed absolutely so it is reachable from Node. */
const environment: GenesysEnvironment = {
  id: 'mock-absolute',
  label: 'Demo (absolute)',
  region: '',
  apiBase: BASE_URL,
  loginBase: BASE_URL,
  isDemo: true,
};

const config: AuthConfig = {
  environmentId: environment.id,
  clientId: 'genesys-data-client-demo',
  redirectUri: `${BASE_URL}/`,
  scopes: [],
};

/** Drives the consent screen the way a browser would, returning the redirect Location. */
const approve = async (challenge: string, state: string): Promise<URL> => {
  const response = await fetch(`${BASE_URL}/oauth/authorize`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: config.clientId,
      redirect_uri: config.redirectUri,
      code_challenge: challenge,
      state,
      decision: 'approve',
    }).toString(),
    redirect: 'manual',
  });
  return new URL(response.headers.get('location') as string);
};

describe.skipIf(!serverUp)('PKCE against the demo authorization server', () => {
  it('serves a consent screen that asks for no credentials', async () => {
    const pkce = await createPkceChallenge();
    const url = buildAuthorizeUrl(environment, config, pkce);
    const response = await fetch(url);
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain('Authorize');
    // A demo consent screen must never look like a credential prompt.
    expect(html).not.toContain('type="password"');
    expect(html.toLowerCase()).not.toContain('name="username"');
    expect(html).toContain('No credentials are requested or checked');
    // The challenge the client generated is what the server is about to bind the code to.
    expect(html).toContain(pkce.challenge);
  });

  it('completes the full round trip with the client own functions', async () => {
    const pkce = await createPkceChallenge();
    const redirect = await approve(pkce.challenge, pkce.state);

    expect(redirect.searchParams.get('state')).toBe(pkce.state);
    const code = redirect.searchParams.get('code') as string;
    expect(code).toBeTruthy();

    const session = await exchangeAuthorizationCode(environment, config, code, pkce.verifier);
    expect(session.accessToken).toBeTruthy();
    expect(session.flow).toBe('pkce');
    expect(session.refreshToken).toBeTruthy();
    expect(Date.parse(session.expiresAt)).toBeGreaterThan(Date.now());

    // The token the flow produced must actually authorize the API.
    const client = new CoreClient({ baseUrl: BASE_URL, token: session.accessToken });
    const users = await client.get<{ entities: unknown[] }>('/api/v2/users');
    expect(users.data.entities.length).toBeGreaterThan(0);
  });

  it('rejects an exchange that presents the wrong verifier', async () => {
    const pkce = await createPkceChallenge();
    const other = await createPkceChallenge();
    const redirect = await approve(pkce.challenge, pkce.state);
    const code = redirect.searchParams.get('code') as string;

    await expect(
      exchangeAuthorizationCode(environment, config, code, other.verifier),
    ).rejects.toThrow(/code_verifier does not match/i);
  });

  it('will not redeem an authorization code twice', async () => {
    const pkce = await createPkceChallenge();
    const redirect = await approve(pkce.challenge, pkce.state);
    const code = redirect.searchParams.get('code') as string;

    await exchangeAuthorizationCode(environment, config, code, pkce.verifier);
    await expect(
      exchangeAuthorizationCode(environment, config, code, pkce.verifier),
    ).rejects.toThrow(/unknown, already used, or expired/i);
  });

  it('rotates refresh tokens and refuses the spent one', async () => {
    const pkce = await createPkceChallenge();
    const redirect = await approve(pkce.challenge, pkce.state);
    const code = redirect.searchParams.get('code') as string;
    const first = await exchangeAuthorizationCode(environment, config, code, pkce.verifier);

    const second = await refreshSession(environment, config, first.refreshToken as string);
    expect(second.accessToken).not.toBe(first.accessToken);
    expect(second.refreshToken).not.toBe(first.refreshToken);

    await expect(refreshSession(environment, config, first.refreshToken as string)).rejects.toThrow(
      /unknown or already used/i,
    );
  });

  it('reports a denied authorization as an OAuth error on the redirect', async () => {
    const pkce = await createPkceChallenge();
    const response = await fetch(`${BASE_URL}/oauth/authorize`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: config.clientId,
        redirect_uri: config.redirectUri,
        code_challenge: pkce.challenge,
        state: pkce.state,
        decision: 'deny',
      }).toString(),
      redirect: 'manual',
    });

    const location = new URL(response.headers.get('location') as string);
    expect(location.searchParams.get('error')).toBe('access_denied');
    expect(location.searchParams.get('state')).toBe(pkce.state);
    expect(location.searchParams.has('code')).toBe(false);
  });

  it('refuses a non-PKCE authorization request', async () => {
    const url = new URL(`${BASE_URL}/oauth/authorize`);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('client_id', config.clientId);
    url.searchParams.set('redirect_uri', config.redirectUri);
    // No code_challenge at all.
    const response = await fetch(url, { redirect: 'manual' });
    const location = new URL(response.headers.get('location') as string);
    expect(location.searchParams.get('error')).toBe('invalid_request');
    expect(location.searchParams.get('error_description')).toMatch(/code_challenge is required/i);
  });

  it('refuses the plain challenge method', async () => {
    const pkce = await createPkceChallenge();
    const url = new URL(`${BASE_URL}/oauth/authorize`);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('client_id', config.clientId);
    url.searchParams.set('redirect_uri', config.redirectUri);
    url.searchParams.set('code_challenge', pkce.verifier);
    url.searchParams.set('code_challenge_method', 'plain');

    const response = await fetch(url, { redirect: 'manual' });
    const location = new URL(response.headers.get('location') as string);
    expect(location.searchParams.get('error')).toBe('invalid_request');
    expect(location.searchParams.get('error_description')).toMatch(/S256/);
  });

  it('does not redirect anywhere when the redirect_uri itself is untrustworthy', async () => {
    const url = new URL(`${BASE_URL}/oauth/authorize`);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('client_id', config.clientId);
    url.searchParams.set('redirect_uri', 'not-a-url');
    url.searchParams.set('code_challenge', 'x');
    url.searchParams.set('code_challenge_method', 'S256');

    const response = await fetch(url, { redirect: 'manual' });
    expect(response.status).toBe(400);
    expect(response.headers.get('location')).toBeNull();
  });

  it('resolves the token to the demo identity', async () => {
    const pkce = await createPkceChallenge();
    const redirect = await approve(pkce.challenge, pkce.state);
    const session = await exchangeAuthorizationCode(
      environment,
      config,
      redirect.searchParams.get('code') as string,
      pkce.verifier,
    );

    const response = await fetch(`${BASE_URL}/oauth/userinfo`, {
      headers: { Authorization: `Bearer ${session.accessToken}` },
    });
    const identity = (await response.json()) as { sub: string; email: string };
    expect(response.status).toBe(200);
    expect(identity.sub).toBe('demo-user-me-0001');
    expect(identity.email).toContain('@');
  });

  it('rejects API calls once a token is revoked', async () => {
    const pkce = await createPkceChallenge();
    const redirect = await approve(pkce.challenge, pkce.state);
    const session = await exchangeAuthorizationCode(
      environment,
      config,
      redirect.searchParams.get('code') as string,
      pkce.verifier,
    );

    const client = new CoreClient({ baseUrl: BASE_URL, token: session.accessToken });
    await expect(client.get('/api/v2/users')).resolves.toBeTruthy();

    await fetch(`${BASE_URL}/oauth/revoke`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ token: session.accessToken }).toString(),
    });

    await expect(client.get('/api/v2/users')).rejects.toThrow();
  });
});
