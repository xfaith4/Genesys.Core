/**
 * PKCE correctness.
 *
 * The S256 assertions use the worked example from RFC 7636 Appendix B, so a regression in the
 * challenge derivation fails here rather than at a real org's token endpoint.
 */

import { describe, expect, it } from 'vitest';
import {
  buildAuthorizeUrl,
  createPkceChallenge,
  deriveChallenge,
  environmentById,
  environmentForRegion,
  GENESYS_ENVIRONMENTS,
  MOCK_ENVIRONMENT,
  readRedirectResult,
  type AuthConfig,
} from '../src/core/auth';

// RFC 7636 Appendix B.
const RFC_VERIFIER = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
const RFC_CHALLENGE = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

const config: AuthConfig = {
  environmentId: 'usw2.pure.cloud',
  clientId: 'client-123',
  redirectUri: 'http://localhost:7777/',
  scopes: [],
};

describe('S256 challenge derivation', () => {
  it('matches the RFC 7636 worked example', async () => {
    expect(await deriveChallenge(RFC_VERIFIER)).toBe(RFC_CHALLENGE);
  });

  it('produces base64url without padding or unsafe characters', async () => {
    const challenge = await deriveChallenge('some-other-verifier');
    expect(challenge).not.toContain('=');
    expect(challenge).not.toContain('+');
    expect(challenge).not.toContain('/');
    expect(challenge).toMatch(/^[A-Za-z0-9\-_]+$/);
  });
});

describe('challenge generation', () => {
  it('creates a 32-byte verifier as 43 base64url characters, matching Genesys.Auth', async () => {
    const pkce = await createPkceChallenge();
    expect(pkce.verifier).toHaveLength(43);
    expect(pkce.verifier).toMatch(/^[A-Za-z0-9\-_]+$/);
  });

  it('derives the challenge from its own verifier', async () => {
    const pkce = await createPkceChallenge();
    expect(pkce.challenge).toBe(await deriveChallenge(pkce.verifier));
  });

  it('never repeats a verifier or a state', async () => {
    const generated = await Promise.all(Array.from({ length: 25 }, () => createPkceChallenge()));
    expect(new Set(generated.map((p) => p.verifier)).size).toBe(25);
    expect(new Set(generated.map((p) => p.state)).size).toBe(25);
  });
});

describe('authorize URL', () => {
  it('matches the shape Get-GenesysPkceAuthorizeUrl builds', async () => {
    const pkce = await createPkceChallenge();
    const url = new URL(buildAuthorizeUrl(environmentById('usw2.pure.cloud'), config, pkce));

    expect(url.origin).toBe('https://login.usw2.pure.cloud');
    expect(url.pathname).toBe('/oauth/authorize');
    expect(url.searchParams.get('response_type')).toBe('code');
    expect(url.searchParams.get('client_id')).toBe('client-123');
    expect(url.searchParams.get('redirect_uri')).toBe('http://localhost:7777/');
    expect(url.searchParams.get('code_challenge')).toBe(pkce.challenge);
    expect(url.searchParams.get('code_challenge_method')).toBe('S256');
    expect(url.searchParams.get('state')).toBe(pkce.state);
  });

  it('never carries the verifier or a client secret', async () => {
    const pkce = await createPkceChallenge();
    const url = buildAuthorizeUrl(environmentById('usw2.pure.cloud'), config, pkce);
    expect(url).not.toContain(pkce.verifier);
    expect(url).not.toContain('client_secret');
  });

  it('omits scope when none is requested and includes it when it is', async () => {
    const pkce = await createPkceChallenge();
    const withoutScope = new URL(buildAuthorizeUrl(environmentById('usw2.pure.cloud'), config, pkce));
    expect(withoutScope.searchParams.has('scope')).toBe(false);

    const withScope = new URL(
      buildAuthorizeUrl(environmentById('usw2.pure.cloud'), { ...config, scopes: ['a', 'b'] }, pkce),
    );
    expect(withScope.searchParams.get('scope')).toBe('a b');
  });

  it('targets the demo server on its own origin', async () => {
    const pkce = await createPkceChallenge();
    const url = buildAuthorizeUrl(MOCK_ENVIRONMENT, { ...config, environmentId: 'mock' }, pkce);
    expect(url.startsWith('/oauth/authorize?')).toBe(true);
  });
});

describe('environments', () => {
  it('derives Genesys hosts from the region suffix', () => {
    const env = environmentForRegion('mypurecloud.ie');
    expect(env.loginBase).toBe('https://login.mypurecloud.ie');
    expect(env.apiBase).toBe('https://api.mypurecloud.ie');
    expect(env.isDemo).toBe(false);
  });

  it('accepts a region that is not in the built-in list', () => {
    const env = environmentById('some-new.pure.cloud');
    expect(env.loginBase).toBe('https://login.some-new.pure.cloud');
  });

  it('offers the demo environment first', () => {
    expect(GENESYS_ENVIRONMENTS[0]?.id).toBe('mock');
    expect(GENESYS_ENVIRONMENTS.filter((e) => e.isDemo)).toHaveLength(1);
  });
});

describe('redirect parsing', () => {
  it('reads a code and state from the query', () => {
    expect(readRedirectResult('http://localhost:7777/?code=abc&state=xyz')).toEqual({
      kind: 'code',
      code: 'abc',
      state: 'xyz',
    });
  });

  it('reads a code from the fragment as well', () => {
    expect(readRedirectResult('http://localhost:7777/#code=abc&state=xyz')).toEqual({
      kind: 'code',
      code: 'abc',
      state: 'xyz',
    });
  });

  it('reports an authorization error', () => {
    const result = readRedirectResult(
      'http://localhost:7777/?error=access_denied&error_description=Denied&state=xyz',
    );
    expect(result).toEqual({
      kind: 'error',
      error: 'access_denied',
      description: 'Denied',
      state: 'xyz',
    });
  });

  it('returns null for an ordinary URL, so it is safe to call on every load', () => {
    expect(readRedirectResult('http://localhost:7777/#/explore/conversations')).toBeNull();
  });
});
