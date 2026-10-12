import { describe, expect, it } from 'vitest';
import { parseHash, toHash } from '../src/app/route';
import { buildNavigation, titleFor } from '../src/skins';

describe('hash routing', () => {
  it('defaults to home for an empty or unknown hash', () => {
    expect(parseHash('')).toEqual({ page: 'home' });
    expect(parseHash('#/')).toEqual({ page: 'home' });
    expect(parseHash('#/nonsense')).toEqual({ page: 'home' });
  });

  it('parses the simple pages', () => {
    expect(parseHash('#/investigation')).toEqual({ page: 'investigation' });
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
      { page: 'investigation' as const },
      { page: 'endpoints' as const },
      { page: 'explore' as const, sourceId: 'conversation-segments' },
    ]) {
      expect(parseHash(toHash(route))).toEqual(route);
    }
  });
});


describe('investigation navigation', () => {
  it('exposes a titled destination through the shared navigation used by both skins', () => {
    const destination = buildNavigation().flatMap(section => section.items)
      .find(item => item.page === 'investigation');
    expect(destination?.label).toBe('Conversation investigation');
    expect(titleFor('investigation', undefined)).toBe(destination?.label);
    expect(parseHash(toHash({ page: 'investigation' }))).toEqual({ page: 'investigation' });
  });
});
