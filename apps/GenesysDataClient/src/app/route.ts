/**
 * Hash routing.
 *
 * A data workbench has to survive a reload and be shareable: a filtered explorer that reverts to
 * the home page on refresh is not much use. The hash is deliberately the whole router - no
 * dependency, and it works identically under the Vite dev server and when the demo server hosts
 * the built files.
 *
 *   #/home
 *   #/endpoints
 *   #/explore/conversations
 */

import type { PageId } from '../skins';

export interface Route {
  page: PageId;
  sourceId?: string;
}

const PAGES: PageId[] = ['home', 'endpoints', 'explore'];

export const parseHash = (hash: string): Route => {
  const parts = hash.replace(/^#\/?/, '').split('/').filter(Boolean);
  const [page, sourceId] = parts;

  if (!page || !PAGES.includes(page as PageId)) return { page: 'home' };
  if (page === 'explore') {
    return sourceId ? { page: 'explore', sourceId } : { page: 'home' };
  }
  return { page: page as PageId };
};

export const toHash = (route: Route): string =>
  route.page === 'explore' && route.sourceId ? `#/explore/${route.sourceId}` : `#/${route.page}`;

export const currentRoute = (): Route =>
  parseHash(typeof location === 'undefined' ? '' : location.hash);
