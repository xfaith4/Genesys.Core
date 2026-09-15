/**
 * Atlas skin - the same application when the user is in control.
 *
 * Everything the Genesys skin fixes, this one exposes: theme, accent, density, navigation
 * placement, pinned destinations and per-page panel arrangement. The feature screens are
 * identical; only the chrome and the declared capabilities differ.
 */

import { useMemo, useState } from 'react';
import { useWorkspace } from '../engine/workspace';
import type { ThemeMode, Density } from '../core/contracts';
import { ACCENTS } from '../core/accents';
import type { SkinDefinition, SkinShellProps } from './index';

const THEMES: { value: ThemeMode; label: string }[] = [
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'system', label: 'System' },
];

const DENSITIES: { value: Density; label: string }[] = [
  { value: 'comfortable', label: 'Comfortable' },
  { value: 'cozy', label: 'Cozy' },
  { value: 'compact', label: 'Compact' },
];

const AtlasShell = ({
  sections,
  activePage,
  activeSourceId,
  title,
  onNavigate,
  children,
}: SkinShellProps) => {
  const { workspace, setSkin, setTheme, setAccent, setDensity, resetWorkspace } = useWorkspace();
  const [railOpen, setRailOpen] = useState(true);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [filter, setFilter] = useState('');

  // Filtering the navigation itself matters once a deployment has many sources.
  const visibleSections = useMemo(() => {
    const needle = filter.trim().toLowerCase();
    if (needle === '') return sections;
    return sections
      .map((section) => ({
        ...section,
        items: section.items.filter(
          (item) =>
            item.label.toLowerCase().includes(needle) || section.label.toLowerCase().includes(needle),
        ),
      }))
      .filter((section) => section.items.length > 0);
  }, [sections, filter]);

  return (
    <div className={`ax${railOpen ? '' : ' ax--rail-collapsed'}`}>
      <aside className="ax-rail" aria-label="Navigation">
        <div className="ax-rail__head">
          <button
            type="button"
            className="ax-rail__toggle"
            onClick={() => setRailOpen(!railOpen)}
            aria-label={railOpen ? 'Collapse navigation' : 'Expand navigation'}
            aria-expanded={railOpen}
          >
            {railOpen ? '⟨' : '⟩'}
          </button>
          {railOpen ? <span className="ax-rail__brand">Atlas</span> : null}
        </div>

        {railOpen ? (
          <div className="ax-rail__filter">
            <input
              type="search"
              value={filter}
              onChange={(event) => setFilter(event.target.value)}
              placeholder="Filter navigation"
              aria-label="Filter navigation"
            />
          </div>
        ) : null}

        <nav className="ax-rail__scroll">
          {visibleSections.map((section) => (
            <div key={section.id} className="ax-rail__section">
              {railOpen ? <p className="ax-rail__section-label">{section.label}</p> : null}
              <ul>
                {section.items.map((item) => {
                  const active =
                    activePage === item.page &&
                    (item.page !== 'explore' || activeSourceId === item.sourceId);
                  return (
                    <li key={item.id}>
                      <button
                        type="button"
                        className={`ax-rail__item${active ? ' ax-rail__item--active' : ''}`}
                        onClick={() => onNavigate(item.page, item.sourceId)}
                        title={item.description ?? item.label}
                        aria-current={active ? 'page' : undefined}
                      >
                        <span className="ax-rail__marker" aria-hidden="true" />
                        {railOpen ? <span>{item.label}</span> : null}
                      </button>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </nav>
      </aside>

      <div className="ax-main">
        <header className="ax-header">
          <div className="ax-header__title">
            <h1>{title}</h1>
            <p className="ax-header__sub">Genesys Data Client · Atlas</p>
          </div>

          <div className="ax-header__controls">
            <div className="ax-seg" role="group" aria-label="Theme">
              {THEMES.map((theme) => (
                <button
                  key={theme.value}
                  type="button"
                  className={workspace.theme === theme.value ? 'ax-seg__btn ax-seg__btn--on' : 'ax-seg__btn'}
                  onClick={() => setTheme(theme.value)}
                  aria-pressed={workspace.theme === theme.value}
                >
                  {theme.label}
                </button>
              ))}
            </div>

            <button
              type="button"
              className="ax-gear"
              onClick={() => setSettingsOpen(!settingsOpen)}
              aria-expanded={settingsOpen}
              aria-label="Interface settings"
              title="Interface settings"
            >
              ⚙
            </button>

            <button
              type="button"
              className="ax-skin-switch"
              onClick={() => setSkin('genesys')}
              title="Switch to the Genesys skin"
            >
              Genesys skin
            </button>
          </div>
        </header>

        {settingsOpen ? (
          <div className="ax-settings" role="region" aria-label="Interface settings">
            <div className="ax-settings__group">
              <span className="ax-settings__label">Accent</span>
              <div className="ax-swatches">
                {ACCENTS.map((accent) => (
                  <button
                    key={accent.base}
                    type="button"
                    className={`ax-swatch${workspace.accent === accent.base ? ' ax-swatch--on' : ''}`}
                    style={{ background: accent.base }}
                    onClick={() => setAccent(accent.base)}
                    aria-label={accent.label}
                    aria-pressed={workspace.accent === accent.base}
                    title={accent.label}
                  />
                ))}
              </div>
            </div>

            <div className="ax-settings__group">
              <span className="ax-settings__label">Density</span>
              <div className="ax-seg">
                {DENSITIES.map((density) => (
                  <button
                    key={density.value}
                    type="button"
                    className={
                      workspace.density === density.value ? 'ax-seg__btn ax-seg__btn--on' : 'ax-seg__btn'
                    }
                    onClick={() => setDensity(density.value)}
                    aria-pressed={workspace.density === density.value}
                  >
                    {density.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="ax-settings__group">
              <span className="ax-settings__label">Workspace</span>
              <button type="button" className="ax-reset" onClick={resetWorkspace}>
                Reset views, layout and preferences
              </button>
            </div>

            <p className="ax-settings__note">
              Panel order, collapsed sections, saved views and these preferences persist in this browser.
            </p>
          </div>
        ) : null}

        <main className="ax-content">{children}</main>
      </div>
    </div>
  );
};

export const atlasSkin: SkinDefinition = {
  id: 'atlas',
  name: 'Atlas',
  tagline: 'The same data, with the interface under your control',
  capabilities: {
    customizableLayout: true,
    themeControl: true,
    densityControl: true,
    accentControl: true,
  },
  Shell: AtlasShell,
};
