/**
 * Panels and the board that arranges them.
 *
 * The board reads its order from the workspace, so a user can move sections around the page and
 * have that survive a reload. Skins decide whether to expose the move affordances at all: the
 * Genesys skin renders a fixed layout, Atlas lets the user rearrange it.
 */

import { useState, type ReactNode } from 'react';
import { useWorkspace } from '../engine/workspace';
import { IconButton } from './primitives';

export interface PanelSpec {
  id: string;
  title: string;
  /** Optional right-aligned header content, such as a count or an action. */
  actions?: ReactNode;
  render: () => ReactNode;
  /** Panels that should span the full board width regardless of layout. */
  wide?: boolean;
}

export const Panel = ({
  title,
  actions,
  children,
  collapsed,
  onToggleCollapsed,
  onMoveUp,
  onMoveDown,
  movable,
}: {
  title: string;
  actions?: ReactNode;
  children: ReactNode;
  collapsed?: boolean;
  onToggleCollapsed?: () => void;
  onMoveUp?: () => void;
  onMoveDown?: () => void;
  movable?: boolean;
}) => (
  <section className="panel" aria-label={title}>
    <header className="panel__header">
      <div className="panel__title-group">
        {onToggleCollapsed ? (
          <IconButton label={collapsed ? `Expand ${title}` : `Collapse ${title}`} onClick={onToggleCollapsed}>
            {collapsed ? '▸' : '▾'}
          </IconButton>
        ) : null}
        <h2 className="panel__title">{title}</h2>
      </div>
      <div className="panel__actions">
        {actions}
        {movable ? (
          <span className="panel__move">
            <IconButton label={`Move ${title} up`} onClick={onMoveUp} disabled={!onMoveUp}>
              ↑
            </IconButton>
            <IconButton label={`Move ${title} down`} onClick={onMoveDown} disabled={!onMoveDown}>
              ↓
            </IconButton>
          </span>
        ) : null}
      </div>
    </header>
    {collapsed ? null : <div className="panel__body">{children}</div>}
  </section>
);

/**
 * Renders panels in the user's saved order for this page.
 * `movable` is supplied by the skin, which is how the two skins differ in capability.
 */
export const PanelBoard = ({
  pageId,
  panels,
  movable = false,
}: {
  pageId: string;
  panels: PanelSpec[];
  movable?: boolean;
}) => {
  const { panelOrder, movePanel, togglePanelCollapsed, isPanelCollapsed } = useWorkspace();
  const fallback = panels.map((panel) => panel.id);
  const order = movable ? panelOrder(pageId, fallback) : fallback;
  const byId = new Map(panels.map((panel) => [panel.id, panel]));

  const ordered = order
    .map((id, index) => ({ panel: byId.get(id), index }))
    .filter((entry): entry is { panel: PanelSpec; index: number } => entry.panel !== undefined);

  // Panels vary a lot in height, so a plain grid leaves a hole under every short panel that sits
  // beside a tall one. Grouping consecutive normal panels into a run lets CSS multi-column
  // balance them, while wide panels stay full width. Reading order is preserved either way.
  type Run = { wide: true; entry: (typeof ordered)[number] } | { wide: false; entries: typeof ordered };
  const runs: Run[] = [];
  for (const entry of ordered) {
    if (entry.panel.wide) {
      runs.push({ wide: true, entry });
      continue;
    }
    const last = runs[runs.length - 1];
    if (last && !last.wide) last.entries.push(entry);
    else runs.push({ wide: false, entries: [entry] });
  }

  const renderPanel = ({ panel, index }: (typeof ordered)[number]) => {
    const panelKey = `${pageId}:${panel.id}`;
    return (
      <div key={panel.id} className="panel-slot">
        <Panel
          title={panel.title}
          actions={panel.actions}
          movable={movable}
          collapsed={isPanelCollapsed(panelKey)}
          onToggleCollapsed={() => togglePanelCollapsed(panelKey)}
          onMoveUp={movable && index > 0 ? () => movePanel(pageId, panel.id, -1, fallback) : undefined}
          onMoveDown={
            movable && index < order.length - 1 ? () => movePanel(pageId, panel.id, 1, fallback) : undefined
          }
        >
          {panel.render()}
        </Panel>
      </div>
    );
  };

  return (
    <div className="panel-board">
      {runs.map((run, runIndex) =>
        run.wide ? (
          <div key={`wide-${run.entry.panel.id}`} className="panel-run panel-run--wide">
            {renderPanel(run.entry)}
          </div>
        ) : (
          <div key={`run-${runIndex}`} className="panel-run panel-run--columns">
            {run.entries.map(renderPanel)}
          </div>
        ),
      )}
    </div>
  );
};

/** Simple disclosure used where a full panel would be too heavy. */
export const Disclosure = ({
  title,
  children,
  defaultOpen = false,
  count,
}: {
  title: string;
  children: ReactNode;
  defaultOpen?: boolean;
  count?: number;
}) => {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className={`disclosure${open ? ' disclosure--open' : ''}`}>
      <button type="button" className="disclosure__toggle" onClick={() => setOpen(!open)} aria-expanded={open}>
        <span>{open ? '▾' : '▸'}</span>
        <span>{title}</span>
        {count !== undefined ? <span className="disclosure__count">{count}</span> : null}
      </button>
      {open ? <div className="disclosure__body">{children}</div> : null}
    </div>
  );
};
