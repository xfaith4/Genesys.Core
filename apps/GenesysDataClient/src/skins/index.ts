/**
 * Skin contract.
 *
 * A skin owns the application chrome - navigation, header, and which personalization controls
 * exist at all. It never owns the feature screens, which is what lets both skins render exactly
 * the same data with the same engine underneath.
 */

import type { ReactNode } from 'react';
import type { SkinId } from '../core/contracts';
import { DATA_SOURCES } from '../core/sources';

export type PageId = 'home' | 'endpoints' | 'explore';

export interface NavItem {
  id: string;
  label: string;
  page: PageId;
  sourceId?: string;
  description?: string;
}

export interface NavSection {
  id: string;
  label: string;
  items: NavItem[];
}

/** What a skin permits the user to change. This is the substantive difference between the two. */
export interface SkinCapabilities {
  /** Panels can be reordered and collapsed, and the full toolkit is exposed. */
  customizableLayout: boolean;
  /** Light/dark/system switching. */
  themeControl: boolean;
  /** Row density switching. */
  densityControl: boolean;
  /** Accent colour switching. */
  accentControl: boolean;
}

export interface SkinShellProps {
  sections: NavSection[];
  activePage: PageId;
  activeSourceId?: string;
  title: string;
  onNavigate: (page: PageId, sourceId?: string) => void;
  children: ReactNode;
}

export interface SkinDefinition {
  id: SkinId;
  name: string;
  tagline: string;
  capabilities: SkinCapabilities;
  Shell: (props: SkinShellProps) => ReactNode;
}

/**
 * Navigation is derived from the registered data sources, so a new source appears in both skins
 * without either skin being edited.
 */
export const buildNavigation = (): NavSection[] => {
  const byGroup = new Map<string, NavItem[]>();

  for (const source of DATA_SOURCES) {
    const items = byGroup.get(source.group) ?? [];
    items.push({
      id: `explore:${source.id}`,
      label: source.name,
      page: 'explore',
      sourceId: source.id,
      description: source.description,
    });
    byGroup.set(source.group, items);
  }

  const dataSections: NavSection[] = [...byGroup.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([group, items]) => ({
      id: `group:${group}`,
      label: group,
      items: items.sort((a, b) => a.label.localeCompare(b.label)),
    }));

  return [
    {
      id: 'start',
      label: 'Start',
      items: [
        { id: 'home', label: 'Getting started', page: 'home' },
        { id: 'endpoints', label: 'Endpoint explorer', page: 'endpoints' },
      ],
    },
    ...dataSections,
  ];
};

/** Resolves the page title shown in the header. */
export const titleFor = (page: PageId, sourceId: string | undefined): string => {
  if (page === 'home') return 'Getting started';
  if (page === 'endpoints') return 'Endpoint explorer';
  const source = DATA_SOURCES.find((s) => s.id === sourceId);
  return source ? source.name : 'Explore';
};
