/**
 * The generic data grid.
 *
 * Every column of every source is sortable, filterable, hideable, reorderable and resizable
 * because the grid works from FieldDefinition metadata rather than per-screen markup.
 */

import { useCallback, useMemo, useRef, useState, type ReactNode } from 'react';
import type {
  ColumnState,
  DataRecord,
  FieldDefinition,
  FilterClause,
  FilterOperator,
  QueryDefinition,
} from '../core/contracts';
import { newId } from '../core/contracts';
import {
  distinctValues,
  formatValue,
  getValue,
  OPERATOR_LABELS,
  operatorsFor,
  toText,
} from '../engine/query';
import { Badge, Button, IconButton, JsonBlock } from './primitives';

// ─── Column ordering helpers ─────────────────────────────────────────────────

/** Resolves the ordered, visible columns paired with their field definitions. */
export const resolveColumns = (
  fields: FieldDefinition[],
  columns: ColumnState[],
): { column: ColumnState; field: FieldDefinition }[] => {
  const byKey = new Map(fields.map((f) => [f.key, f]));
  return columns
    .map((column) => {
      const field = byKey.get(column.key);
      return field ? { column, field } : null;
    })
    .filter((entry): entry is { column: ColumnState; field: FieldDefinition } => entry !== null);
};

/**
 * A React key that survives reordering. Records carry natural identifiers often enough that the
 * first id-shaped field is a good key; the row position is only a last resort.
 */
const ID_KEYS = ['id', 'conversationId', 'sessionId', 'participantId', 'key'];

const rowKeyOf = (record: DataRecord, fallbackIndex: number): string => {
  for (const key of ID_KEYS) {
    const value = record[key];
    if (typeof value === 'string' && value !== '') return value;
  }
  return String(fallbackIndex);
};

// ─── Filter editor ───────────────────────────────────────────────────────────

const FilterRow = ({
  clause,
  fields,
  records,
  onChange,
  onRemove,
}: {
  clause: FilterClause;
  fields: FieldDefinition[];
  records: DataRecord[];
  onChange: (clause: FilterClause) => void;
  onRemove: () => void;
}) => {
  const field = fields.find((f) => f.key === clause.field);
  const operators = operatorsFor(field?.type ?? 'string');
  const needsValue = clause.operator !== 'isEmpty' && clause.operator !== 'isNotEmpty';
  const facets = useMemo(
    () => (field?.facetable ? distinctValues(records, clause.field, 30) : []),
    [field, records, clause.field],
  );

  return (
    <div className={`filter-row${clause.enabled ? '' : ' filter-row--off'}`}>
      <input
        type="checkbox"
        checked={clause.enabled}
        onChange={(event) => onChange({ ...clause, enabled: event.target.checked })}
        aria-label={`Enable filter on ${field?.label ?? clause.field}`}
      />

      <select
        className="field__control"
        value={clause.field}
        onChange={(event) => onChange({ ...clause, field: event.target.value, value: '' })}
        aria-label="Filter field"
      >
        {fields.map((f) => (
          <option key={f.key} value={f.key}>
            {f.label}
          </option>
        ))}
      </select>

      <select
        className="field__control"
        value={clause.operator}
        onChange={(event) => onChange({ ...clause, operator: event.target.value as FilterOperator })}
        aria-label="Filter operator"
      >
        {operators.map((op) => (
          <option key={op} value={op}>
            {OPERATOR_LABELS[op]}
          </option>
        ))}
      </select>

      {needsValue ? (
        facets.length > 0 ? (
          <select
            className="field__control"
            value={toText(clause.value)}
            onChange={(event) => onChange({ ...clause, value: event.target.value })}
            aria-label="Filter value"
          >
            <option value="">(any)</option>
            {facets.map((facet) => (
              <option key={facet.value} value={facet.value}>
                {facet.value === '' ? '(blank)' : facet.value} ({facet.count})
              </option>
            ))}
          </select>
        ) : (
          <input
            className="field__control"
            type={field?.type === 'date' ? 'datetime-local' : field?.type === 'number' ? 'number' : 'text'}
            value={toText(clause.value)}
            onChange={(event) => onChange({ ...clause, value: event.target.value })}
            placeholder="value"
            aria-label="Filter value"
          />
        )
      ) : (
        <span className="filter-row__spacer" />
      )}

      <IconButton label="Remove filter" onClick={onRemove}>
        ×
      </IconButton>
    </div>
  );
};

export const FilterPanel = ({
  query,
  fields,
  records,
  onChange,
}: {
  query: QueryDefinition;
  fields: FieldDefinition[];
  records: DataRecord[];
  onChange: (query: QueryDefinition) => void;
}) => {
  const addFilter = () => {
    const first = fields[0];
    if (!first) return;
    const clause: FilterClause = {
      id: newId('filter'),
      field: first.key,
      operator: operatorsFor(first.type)[0] ?? 'contains',
      value: '',
      enabled: true,
    };
    onChange({ ...query, filters: [...query.filters, clause] });
  };

  return (
    <div className="filter-panel">
      {query.filters.length === 0 ? (
        <p className="filter-panel__empty">No filters. Every column can be filtered.</p>
      ) : (
        query.filters.map((clause) => (
          <FilterRow
            key={clause.id}
            clause={clause}
            fields={fields}
            records={records}
            onChange={(next) =>
              onChange({ ...query, filters: query.filters.map((f) => (f.id === next.id ? next : f)) })
            }
            onRemove={() =>
              onChange({ ...query, filters: query.filters.filter((f) => f.id !== clause.id) })
            }
          />
        ))
      )}
      <div className="filter-panel__actions">
        <Button onClick={addFilter}>Add filter</Button>
        {query.filters.length > 0 ? (
          <Button variant="ghost" onClick={() => onChange({ ...query, filters: [] })}>
            Clear all
          </Button>
        ) : null}
      </div>
    </div>
  );
};

// ─── Column picker ───────────────────────────────────────────────────────────

export const ColumnPicker = ({
  fields,
  columns,
  onChange,
}: {
  fields: FieldDefinition[];
  columns: ColumnState[];
  onChange: (columns: ColumnState[]) => void;
}) => {
  const resolved = resolveColumns(fields, columns);

  const move = (index: number, direction: -1 | 1) => {
    const target = index + direction;
    if (target < 0 || target >= columns.length) return;
    const next = [...columns];
    const [moved] = next.splice(index, 1);
    next.splice(target, 0, moved as ColumnState);
    onChange(next);
  };

  return (
    <div className="column-picker">
      <div className="column-picker__actions">
        <Button variant="ghost" onClick={() => onChange(columns.map((c) => ({ ...c, visible: true })))}>
          Show all
        </Button>
        <Button
          variant="ghost"
          onClick={() =>
            onChange(
              columns.map((c) => ({
                ...c,
                visible: !fields.find((f) => f.key === c.key)?.hiddenByDefault,
              })),
            )
          }
        >
          Reset
        </Button>
      </div>
      <ul className="column-picker__list">
        {resolved.map(({ column, field }, index) => (
          <li key={column.key} className="column-picker__item">
            <label>
              <input
                type="checkbox"
                checked={column.visible}
                onChange={(event) =>
                  onChange(
                    columns.map((c) => (c.key === column.key ? { ...c, visible: event.target.checked } : c)),
                  )
                }
              />
              <span>{field.label}</span>
            </label>
            <span className="column-picker__type">{field.type}</span>
            <span className="column-picker__move">
              <IconButton label={`Move ${field.label} earlier`} onClick={() => move(index, -1)}>
                ↑
              </IconButton>
              <IconButton label={`Move ${field.label} later`} onClick={() => move(index, 1)}>
                ↓
              </IconButton>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
};

// ─── Grid ────────────────────────────────────────────────────────────────────

export interface DataGridProps {
  fields: FieldDefinition[];
  records: DataRecord[];
  columns: ColumnState[];
  query: QueryDefinition;
  onColumnsChange: (columns: ColumnState[]) => void;
  onQueryChange: (query: QueryDefinition) => void;
  /** Rendered in an expansion row when a row is opened. */
  renderExpanded?: (record: DataRecord) => ReactNode;
  emptyMessage?: string;
  maxHeight?: number;
}

export const DataGrid = ({
  fields,
  records,
  columns,
  query,
  onColumnsChange,
  onQueryChange,
  renderExpanded,
  emptyMessage = 'No rows match the current filters.',
  maxHeight,
}: DataGridProps) => {
  // Expansion tracks the record itself, not its position. Sorting and filtering reorder rows
  // without cloning them, so an index would keep the disclosure open on whichever record happened
  // to land in that slot and show the wrong detail.
  const [expanded, setExpanded] = useState<DataRecord | null>(null);
  const dragKey = useRef<string | null>(null);
  const resizing = useRef<{ key: string; startX: number; startWidth: number } | null>(null);

  const visible = useMemo(
    () => resolveColumns(fields, columns).filter(({ column }) => column.visible),
    [fields, columns],
  );

  const sortFor = useCallback(
    (key: string) => query.sort.find((clause) => clause.field === key),
    [query.sort],
  );

  /** Click cycles asc -> desc -> off. Shift-click appends to a multi-column sort. */
  const toggleSort = (key: string, additive: boolean) => {
    const existing = query.sort.find((clause) => clause.field === key);
    let nextSort = [...query.sort];

    if (!existing) {
      const clause = { field: key, direction: 'asc' as const };
      nextSort = additive ? [...nextSort, clause] : [clause];
    } else if (existing.direction === 'asc') {
      nextSort = nextSort.map((c) => (c.field === key ? { ...c, direction: 'desc' as const } : c));
      if (!additive) nextSort = nextSort.filter((c) => c.field === key);
    } else {
      nextSort = nextSort.filter((c) => c.field !== key);
    }

    onQueryChange({ ...query, sort: nextSort });
  };

  // ── Column reordering by dragging a header ──
  const onDragStart = (key: string) => {
    dragKey.current = key;
  };

  const onDropOn = (targetKey: string) => {
    const sourceKey = dragKey.current;
    dragKey.current = null;
    if (!sourceKey || sourceKey === targetKey) return;

    const next = [...columns];
    const from = next.findIndex((c) => c.key === sourceKey);
    const to = next.findIndex((c) => c.key === targetKey);
    if (from < 0 || to < 0) return;
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved as ColumnState);
    onColumnsChange(next);
  };

  // ── Column resizing ──
  const startResize = (key: string, startX: number, startWidth: number) => {
    resizing.current = { key, startX, startWidth };

    const onMove = (event: MouseEvent) => {
      const state = resizing.current;
      if (!state) return;
      const width = Math.max(70, state.startWidth + (event.clientX - state.startX));
      onColumnsChange(columns.map((c) => (c.key === state.key ? { ...c, width } : c)));
    };

    const onUp = () => {
      resizing.current = null;
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };

    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  };

  if (visible.length === 0) {
    return <div className="grid-empty">Every column is hidden. Use the Columns panel to show one.</div>;
  }

  return (
    <div className="grid-wrap" style={maxHeight ? { maxHeight, overflowY: 'auto' } : undefined}>
      <table className="grid">
        <thead>
          <tr>
            {renderExpanded ? <th className="grid__expander" aria-label="Expand" /> : null}
            {visible.map(({ column, field }) => {
              const sort = sortFor(field.key);
              const index = query.sort.findIndex((c) => c.field === field.key);
              return (
                <th
                  key={field.key}
                  style={{ width: column.width, minWidth: column.width }}
                  className={`grid__th grid__th--${field.align ?? 'left'}`}
                  draggable
                  onDragStart={() => onDragStart(field.key)}
                  onDragOver={(event) => event.preventDefault()}
                  onDrop={() => onDropOn(field.key)}
                  aria-sort={sort ? (sort.direction === 'asc' ? 'ascending' : 'descending') : 'none'}
                >
                  <button
                    type="button"
                    className="grid__sort"
                    onClick={(event) => toggleSort(field.key, event.shiftKey)}
                    title={`Sort by ${field.label}. Shift-click to add to the sort.`}
                  >
                    <span className="grid__label">{field.label}</span>
                    {sort ? (
                      <span className="grid__sort-marker">
                        {sort.direction === 'asc' ? '▲' : '▼'}
                        {query.sort.length > 1 ? <sup>{index + 1}</sup> : null}
                      </span>
                    ) : null}
                  </button>
                  <span
                    className="grid__resize"
                    role="separator"
                    aria-orientation="vertical"
                    aria-label={`Resize ${field.label}`}
                    onMouseDown={(event) => {
                      event.preventDefault();
                      startResize(field.key, event.clientX, column.width ?? 150);
                    }}
                  />
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody>
          {records.length === 0 ? (
            <tr>
              <td className="grid__empty" colSpan={visible.length + (renderExpanded ? 1 : 0)}>
                {emptyMessage}
              </td>
            </tr>
          ) : (
            records.map((record, rowIndex) => (
              <FragmentRow
                key={rowKeyOf(record, rowIndex)}
                record={record}
                rowIndex={rowIndex}
                visible={visible}
                expanded={expanded === record}
                onToggle={() => setExpanded(expanded === record ? null : record)}
                renderExpanded={renderExpanded}
              />
            ))
          )}
        </tbody>
      </table>
    </div>
  );
};

const FragmentRow = ({
  record,
  rowIndex,
  visible,
  expanded,
  onToggle,
  renderExpanded,
}: {
  record: DataRecord;
  rowIndex: number;
  visible: { column: ColumnState; field: FieldDefinition }[];
  expanded: boolean;
  onToggle: () => void;
  renderExpanded?: (record: DataRecord) => ReactNode;
}) => (
  <>
    <tr className={rowIndex % 2 === 1 ? 'grid__row grid__row--alt' : 'grid__row'}>
      {renderExpanded ? (
        <td className="grid__expander">
          <IconButton label={expanded ? 'Collapse row' : 'Expand row'} onClick={onToggle}>
            {expanded ? '▾' : '▸'}
          </IconButton>
        </td>
      ) : null}
      {visible.map(({ column, field }) => {
        const raw = getValue(record, field.key);
        const text = formatValue(raw, field.type);
        return (
          <td
            key={field.key}
            className={`grid__td grid__td--${field.align ?? 'left'} grid__td--${field.type}`}
            style={{ width: column.width, maxWidth: column.width }}
            title={text}
          >
            {field.type === 'boolean' ? (
              <Badge tone={raw ? 'good' : 'muted'}>{text}</Badge>
            ) : (
              <span className="grid__cell">{text}</span>
            )}
          </td>
        );
      })}
    </tr>
    {expanded && renderExpanded ? (
      <tr className="grid__detail-row">
        <td colSpan={visible.length + 1}>{renderExpanded(record)}</td>
      </tr>
    ) : null}
  </>
);

/** Default row detail: the raw payload when a source kept one, otherwise every field. */
export const DefaultRowDetail = ({
  record,
  fields,
}: {
  record: DataRecord;
  fields: FieldDefinition[];
}) => {
  if ('raw' in record && record.raw) return <JsonBlock value={record.raw} />;
  const shown: Record<string, unknown> = {};
  for (const field of fields) shown[field.label] = getValue(record, field.key);
  return <JsonBlock value={shown} />;
};
