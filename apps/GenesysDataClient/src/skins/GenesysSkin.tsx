/**
 * Genesys skin - a reproduction of the productized unified navigation experience.
 *
 * Modelled on the publicly documented behaviour of the new Genesys Cloud navigation: a unified
 * global menu that consolidates navigation across the platform, and a top bar carrying consistent
 * page titles, a back button, and relocated Collaborate, Inbox and User Avatar elements, with a
 * global search that returns menu pages alongside people and groups.
 *
 * Genesys has not published the visual specification, so the styling here is an approximation of
 * that described structure rather than a pixel-accurate copy.
 *
 * Deliberately, this skin exposes no layout, theme or density control. That constraint is the
 * baseline the Atlas skin is measured against.
 */

import { useEffect, useMemo, useState } from 'react';
import { useWorkspace } from '../engine/workspace';
import type { SkinDefinition, SkinShellProps } from './index';

const GenesysShell = ({
  sections,
  activePage,
  activeSourceId,
  title,
  onNavigate,
  children,
}: SkinShellProps) => {
  const { setSkin } = useWorkspace();
  const [menuOpen, setMenuOpen] = useState(true);
  const [search, setSearch] = useState('');
  const [onQueue, setOnQueue] = useState(false);

  // Navigation goes through the URL hash, so the browser already owns the history stack.
  // Keeping a private copy here would desync the moment someone used browser back or forward;
  // this only tracks how deep we are so the control can disable itself at the start.
  const [depth, setDepth] = useState(0);

  useEffect(() => {
    const onPop = () => setDepth((d) => Math.max(0, d - 1));
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  // Global search returns menu pages alongside everything else, as the announcement describes.
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
    const changed = page !== activePage || sourceId !== activeSourceId;
    if (changed) setDepth((d) => d + 1);
    onNavigate(page, sourceId);
    setSearch('');
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
              disabled={depth === 0}
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
              placeholder="Search people, groups, locations and pages"
              aria-label="Global search"
            />
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
            <button
              type="button"
              className={`gx-queue${onQueue ? ' gx-queue--on' : ''}`}
              onClick={() => setOnQueue(!onQueue)}
              aria-pressed={onQueue}
              title="Toggle queue status"
            >
              {onQueue ? 'On queue' : 'Off queue'}
            </button>
            <button type="button" className="gx-icon" title="Collaborate" aria-label="Collaborate">
              ◍
            </button>
            <button type="button" className="gx-icon" title="Inbox" aria-label="Inbox">
              ✉
            </button>
            <button type="button" className="gx-icon" title="Help" aria-label="Help">
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
