/**
 * The generic explorer.
 *
 * Every data source gets this screen. Nothing here is source-specific: columns, filters, sorting,
 * grouping and export all come from the source's FieldDefinitions, which is why adding a source
 * adds a fully-featured explorer for free.
 */

import { useEffect, useMemo, useState } from 'react';
import type { ColumnState, DataRecord, QueryDefinition, ViewDefinition } from '../core/contracts';
import { emptyQuery } from '../core/contracts';
import { defaultColumns, reconcileColumns, sourceById } from '../core/sources';
import { applyQuery, OPERATOR_LABELS, toText } from '../engine/query';
import { useDataSource } from '../engine/useDataSource';
import { useWorkspace, viewFromState } from '../engine/workspace';
import { ColumnPicker, DataGrid, DefaultRowDetail, FilterPanel } from '../components/DataGrid';
import { ExportBar } from '../components/ExportBar';
import { PanelBoard, type PanelSpec } from '../components/Panel';
import {
  Badge,
  Button,
  DetailRow,
  ErrorState,
  MethodBadge,
  Spinner,
  TextInput,
} from '../components/primitives';
import { ReportBuilder } from './ReportBuilder';
import type { SkinCapabilities } from '../skins';

/** Human-readable description of the active filters, used in export provenance. */
const summarizeFilters = (query: QueryDefinition): string => {
  const active = query.filters.filter((f) => f.enabled);
  const parts = active.map((f) => `${f.field} ${OPERATOR_LABELS[f.operator]} ${toText(f.value)}`.trim());
  if (query.search.trim() !== '') parts.unshift(`search "${query.search.trim()}"`);
  return parts.join('; ');
};

export const Explorer = ({
  sourceId,
  capabilities,
}: {
  sourceId: string;
  capabilities: SkinCapabilities;
}) => {
  const source = sourceById(sourceId);
  const workspace = useWorkspace();
  const { status, dataSet, error, reload } = useDataSource(source);

  const [query, setQuery] = useState<QueryDefinition>(() => ({
    ...emptyQuery(sourceId),
    ...source?.defaultQuery,
  }));
  const [columns, setColumns] = useState<ColumnState[]>(() => (source ? defaultColumns(source) : []));
  const [viewName, setViewName] = useState('');

  // Switching source resets the on-screen state to that source's defaults.
  useEffect(() => {
    if (!source) return;
    setQuery({ ...emptyQuery(source.id), ...source.defaultQuery });
    setColumns(defaultColumns(source));
    setViewName('');
  }, [source]);

  const records = dataSet?.records ?? [];
  const fields = dataSet?.fields ?? source?.fields ?? [];

  const processed = useMemo(() => applyQuery(records, fields, query), [records, fields, query]);

  const visibleColumnKeys = useMemo(
    () => columns.filter((c) => c.visible).map((c) => c.key),
    [columns],
  );

  const savedViews = useMemo(
    () => workspace.workspace.views.filter((v) => v.sourceId === sourceId),
    [workspace.workspace.views, sourceId],
  );

  const applyView = (view: ViewDefinition) => {
    setQuery(structuredClone(view.query));
    // A view can predate fields the source has gained since; reconcile rather than freeze it.
    setColumns(reconcileColumns(structuredClone(view.columns), fields));
  };

  if (!source) {
    return <ErrorState message={`Unknown data source "${sourceId}".`} />;
  }

  if (status === 'loading' || status === 'idle') {
    return (
      <div className="page-state">
        <Spinner label={`Retrieving ${source.name.toLowerCase()} through Genesys.Core…`} />
      </div>
    );
  }

  if (status === 'error') {
    return <ErrorState message={error ?? 'Unknown error'} onRetry={reload} />;
  }

  const gridPanel: PanelSpec = {
    id: 'grid',
    title: source.name,
    wide: true,
    actions: (
      <span className="panel__meta">
        <Badge tone="accent">
          {processed.records.length} of {processed.totalBeforeFilters} rows
        </Badge>
        <Button variant="ghost" onClick={reload}>
          Refresh
        </Button>
      </span>
    ),
    render: () => (
      <>
        <div className="explorer__searchbar">
          <TextInput
            id={`search-${sourceId}`}
            label="Search all columns"
            value={query.search}
            onChange={(search) => setQuery({ ...query, search })}
            placeholder="Type to filter every column…"
          />
          {query.sort.length > 0 ? (
            <span className="explorer__sortnote">
              Sorted by {query.sort.map((s) => `${s.field} ${s.direction}`).join(', ')}
              <Button variant="ghost" onClick={() => setQuery({ ...query, sort: [] })}>
                Clear sort
              </Button>
            </span>
          ) : (
            <span className="explorer__sortnote explorer__sortnote--hint">
              Click a header to sort. Shift-click to sort by several columns. Drag a header to reorder.
            </span>
          )}
        </div>
        <DataGrid
          fields={fields}
          records={processed.records}
          columns={columns}
          query={query}
          onColumnsChange={setColumns}
          onQueryChange={setQuery}
          renderExpanded={(record: DataRecord) => <DefaultRowDetail record={record} fields={fields} />}
          maxHeight={560}
        />
      </>
    ),
  };

  const filterPanel: PanelSpec = {
    id: 'filters',
    title: 'Filters',
    actions: <Badge tone="muted">{query.filters.filter((f) => f.enabled).length} active</Badge>,
    render: () => <FilterPanel query={query} fields={fields} records={records} onChange={setQuery} />,
  };

  const columnsPanel: PanelSpec = {
    id: 'columns',
    title: 'Columns',
    actions: (
      <Badge tone="muted">
        {visibleColumnKeys.length} of {fields.length} shown
      </Badge>
    ),
    render: () => <ColumnPicker fields={fields} columns={columns} onChange={setColumns} />,
  };

  const exportPanel: PanelSpec = {
    id: 'export',
    title: 'Export',
    render: () => (
      <ExportBar
        sourceName={source.name}
        fields={fields}
        records={processed.records}
        visibleColumnKeys={visibleColumnKeys}
        meta={dataSet?.meta}
        filterSummary={summarizeFilters(query)}
      />
    ),
  };

  const reportPanel: PanelSpec = {
    id: 'report',
    title: 'Ad-hoc report',
    wide: true,
    render: () => (
      <ReportBuilder
        sourceName={source.name}
        fields={fields}
        records={processed.records}
        meta={dataSet?.meta}
      />
    ),
  };

  const provenancePanel: PanelSpec = {
    id: 'provenance',
    title: 'What was exercised',
    render: () => (
      <div className="provenance">
        <p className="provenance__intro">{source.description}</p>
        <DetailRow label="Retrieved">
          {dataSet ? `${new Date(dataSet.meta.fetchedAt).toLocaleString()} · ${dataSet.meta.durationMs} ms` : '—'}
        </DetailRow>
        <DetailRow label="Records">{records.length}</DetailRow>
        <ol className="trace-list">
          {(dataSet?.meta.requests ?? []).map((trace, index) => (
            <li key={index} className="trace-list__item">
              <MethodBadge method={trace.method} />
              <code className="trace-list__url">{trace.url.replace(/^https?:\/\/[^/]+/, '')}</code>
              <Badge tone={trace.status < 400 ? 'good' : 'bad'}>{trace.status}</Badge>
              <span className="trace-list__note">{trace.note}</span>
              <span className="trace-list__time">{trace.durationMs} ms</span>
            </li>
          ))}
        </ol>
        {(dataSet?.meta.warnings ?? []).map((warning, index) => (
          <p key={index} className="provenance__warning">
            {warning}
          </p>
        ))}
        <div className="provenance__endpoints">
          <span className="provenance__label">Catalog endpoints</span>
          {source.endpointKeys.map((key) => (
            // The catalog key itself, not a coverage claim. Coverage is the server's to report,
            // and the endpoint explorer shows it from /__meta rather than being asserted here.
            <Badge key={key} tone="muted" title={`Catalog endpoint key: ${key}`}>
              <code>{key}</code>
            </Badge>
          ))}
        </div>
      </div>
    ),
  };

  const viewsPanel: PanelSpec = {
    id: 'views',
    title: 'Saved views',
    actions: <Badge tone="muted">{savedViews.length}</Badge>,
    render: () => (
      <div className="views">
        <div className="views__save">
          <TextInput
            id={`viewname-${sourceId}`}
            label="Save current layout as"
            value={viewName}
            onChange={setViewName}
            placeholder="e.g. Abandoned voice calls"
          />
          <Button
            variant="primary"
            disabled={viewName.trim() === ''}
            onClick={() => {
              workspace.saveView(
                viewFromState(viewName.trim(), sourceId, query, columns, workspace.workspace.density),
              );
              setViewName('');
            }}
          >
            Save view
          </Button>
        </div>
        {savedViews.length === 0 ? (
          <p className="views__empty">
            No saved views yet. A view remembers the filters, sort order and column layout on screen.
          </p>
        ) : (
          <ul className="views__list">
            {savedViews.map((view) => (
              <li key={view.id} className="views__item">
                <button type="button" className="views__apply" onClick={() => applyView(view)}>
                  {view.name}
                </button>
                <span className="views__meta">
                  {view.query.filters.length} filter{view.query.filters.length === 1 ? '' : 's'}
                </span>
                <Button variant="ghost" onClick={() => workspace.deleteView(view.id)}>
                  Delete
                </Button>
              </li>
            ))}
          </ul>
        )}
      </div>
    ),
  };

  // The Genesys skin shows a fixed, product-like arrangement. Atlas exposes the full toolkit.
  const panels: PanelSpec[] = capabilities.customizableLayout
    ? [gridPanel, filterPanel, columnsPanel, reportPanel, exportPanel, viewsPanel, provenancePanel]
    : [gridPanel, filterPanel, provenancePanel];

  return (
    <div className="explorer">
      <PanelBoard pageId={`explorer:${sourceId}`} panels={panels} movable={capabilities.customizableLayout} />
    </div>
  );
};
