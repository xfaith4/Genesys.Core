import { describe, expect, it } from 'vitest';
import { parseHash, toHash } from '../src/app/route';

describe('hash routing', () => {
  it('defaults to home for an empty or unknown hash', () => {
    expect(parseHash('')).toEqual({ page: 'home' });
    expect(parseHash('#/')).toEqual({ page: 'home' });
    expect(parseHash('#/nonsense')).toEqual({ page: 'home' });
  });

  it('parses the simple pages', () => {
    expect(parseHash('#/home')).toEqual({ page: 'home' });
    expect(parseHash('#/endpoints')).toEqual({ page: 'endpoints' });
  });

  it('parses an explorer route with its source', () => {
    expect(parseHash('#/explore/conversations')).toEqual({
      page: 'explore',
      sourceId: 'conversations',
    });
  });

  it('falls back to home when an explore route names no source', () => {
    expect(parseHash('#/explore')).toEqual({ page: 'home' });
  });

  it('round-trips every route through the hash', () => {
    for (const route of [
      { page: 'home' as const },
      { page: 'endpoints' as const },
      { page: 'explore' as const, sourceId: 'conversation-segments' },
    ]) {
      expect(parseHash(toHash(route))).toEqual(route);
    }
  });
});
