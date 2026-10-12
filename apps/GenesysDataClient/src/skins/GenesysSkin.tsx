/**
 * Genesys skin - a reproduction of the productized unified navigation experience.
 *
 * Provides a unified global menu, page search, browser-backed navigation and Help.
 * It is an approximation of the navigation structure; agent workflow controls do not
 * belong in this data client.
 *
 * Deliberately, this skin exposes no layout, theme or density control. That constraint is the
 * baseline the Atlas skin is measured against.
 */

import { useMemo, useState } from 'react';
import { useWorkspace } from '../engine/workspace';
import type { SkinDefinition, SkinShellProps } from './index';

const GenesysShell = ({
  sections,
  activePage,
  activeSourceId,
  title,
  onNavigate,
  canGoBack,
  children,
}: SkinShellProps) => {
  const { setSkin } = useWorkspace();
  const [menuOpen, setMenuOpen] = useState(() => !window.matchMedia('(max-width: 860px)').matches);
  const [search, setSearch] = useState('');
  // Search the destinations that this client can actually open.
  const searchResults = useMemo(() => {
    const needle = search.trim().toLowerCase();
    if (needle === '') return [];
    return sections
      .flatMap((section) => section.items.map((item) => ({ section, item })))
      .filter(
        ({ section, item }) =>
          item.label.toLowerCase().includes(needle) || section.label.toLowerCase().includes(needle),
      )
      .slice(0, 8);
  }, [search, sections]);

  const navigate = (page: typeof activePage, sourceId?: string) => {
    onNavigate(page, sourceId);
    setSearch('');
    if (window.matchMedia('(max-width: 860px)').matches) setMenuOpen(false);
  };

  const goBack = () => window.history.back();

  return (
    <div className="gx">
      <nav className={`gx-menu${menuOpen ? '' : ' gx-menu--collapsed'}`} aria-label="Global menu">
        <div className="gx-menu__brand">
          <button
            type="button"
            className="gx-menu__burger"
            onClick={() => setMenuOpen(!menuOpen)}
            aria-label={menuOpen ? 'Collapse global menu' : 'Expand global menu'}
            aria-expanded={menuOpen}
          >
            <span />
            <span />
            <span />
          </button>
          {menuOpen ? <span className="gx-menu__wordmark">Genesys Data Client</span> : null}
        </div>

        <div className="gx-menu__scroll">
          {sections.map((section) => (
            <div key={section.id} className="gx-menu__section">
              {menuOpen ? <p className="gx-menu__section-label">{section.label}</p> : null}
              <ul className="gx-menu__list">
                {section.items.map((item) => {
                  const active =
                    activePage === item.page &&
                    (item.page !== 'explore' || activeSourceId === item.sourceId);
                  return (
                    <li key={item.id}>
                      <button
                        type="button"
                        className={`gx-menu__item${active ? ' gx-menu__item--active' : ''}`}
                        onClick={() => navigate(item.page, item.sourceId)}
                        title={item.label}
                        aria-label={item.label}
                        aria-current={active ? 'page' : undefined}
                      >
                        <span className="gx-menu__dot" aria-hidden="true" />
                        {menuOpen ? <span className="gx-menu__label">{item.label}</span> : null}
                      </button>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </div>
      </nav>

      <div className="gx-main">
        <header className="gx-topbar">
          <div className="gx-topbar__left">
            <button
              type="button"
              className="gx-topbar__back"
              onClick={goBack}
              disabled={!canGoBack}
              aria-label="Back"
              title="Back"
            >
              ‹
            </button>
            <h1 className="gx-topbar__title">{title}</h1>
          </div>

          <div className="gx-topbar__search">
            <input
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search pages"
              aria-label="Search pages"
            />
            {search.trim() !== '' && searchResults.length === 0 ? (
              <div className="gx-topbar__results" role="status">No pages match “{search.trim()}”.</div>
            ) : null}
            {searchResults.length > 0 ? (
              <ul className="gx-topbar__results">
                {searchResults.map(({ section, item }) => (
                  <li key={item.id}>
                    <button type="button" onClick={() => navigate(item.page, item.sourceId)}>
                      <span className="gx-result__label">{item.label}</span>
                      <span className="gx-result__section">{section.label}</span>
                    </button>
                  </li>
                ))}
              </ul>
            ) : null}
          </div>

          <div className="gx-topbar__right">
            <button type="button" className="gx-icon" title="Help" aria-label="Help" onClick={() => navigate('home')}>
              ?
            </button>
            <button
              type="button"
              className="gx-avatar"
              title="Switch to the Atlas skin"
              aria-label="Switch to the Atlas skin"
              onClick={() => setSkin('atlas')}
            >
              DA
            </button>
          </div>
        </header>

        <div className="gx-banner">
          <span>
            This skin reproduces the productized navigation, including its fixed layout and light-only theme.
          </span>
          <button type="button" onClick={() => setSkin('atlas')}>
            Try the Atlas skin →
          </button>
        </div>

        <main className="gx-content">{children}</main>
      </div>
    </div>
  );
};

export const genesysSkin: SkinDefinition = {
  id: 'genesys',
  name: 'Genesys',
  tagline: 'The productized unified navigation experience',
  capabilities: {
    customizableLayout: false,
    themeControl: false,
    densityControl: false,
    accentControl: false,
  },
  Shell: GenesysShell,
};
