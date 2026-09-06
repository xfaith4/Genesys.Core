/**
 * Genesys Data Client - reusable primitives.
 *
 * These contracts are the foundation described in docs/GenesysDataClient.md. Everything the
 * application can do is expressed as one of them, which is what lets feature modules stay thin
 * and lets the existing purpose-built apps donate capabilities without hard-coding screens.
 *
 *   DataSource -> QueryDefinition -> ViewDefinition -> ReportDefinition
 *                                                   -> DashboardDefinition
 *                                                   -> ExportDefinition
 *
 * Nothing in this file knows about React, and only `DataSource` knows about Genesys.
 */

// ─── Records and fields ──────────────────────────────────────────────────────

/** A single flattened row. Sources normalize nested Genesys payloads into these. */
export type DataRecord = Record<string, unknown>;

export type FieldType = 'string' | 'number' | 'boolean' | 'date' | 'duration' | 'json';

/** Describes one addressable column of a data source. */
export interface FieldDefinition {
  /** Property name on the flattened record. */
  key: string;
  label: string;
  type: FieldType;
  description?: string;
  /** Hidden by default but still filterable, sortable and exportable. */
  hiddenByDefault?: boolean;
  /** Offer a distinct-value picker for this field. */
  facetable?: boolean;
  width?: number;
  align?: 'left' | 'right' | 'center';
}

// ─── QueryDefinition ─────────────────────────────────────────────────────────

export type FilterOperator =
  | 'eq'
  | 'ne'
  | 'contains'
  | 'notContains'
  | 'startsWith'
  | 'endsWith'
  | 'gt'
  | 'gte'
  | 'lt'
  | 'lte'
  | 'in'
  | 'isEmpty'
  | 'isNotEmpty';

export interface FilterClause {
  id: string;
  field: string;
  operator: FilterOperator;
  value?: unknown;
  enabled: boolean;
}

export type SortDirection = 'asc' | 'desc';

export interface SortClause {
  field: string;
  direction: SortDirection;
}

/**
 * What to retrieve and how to shape it.
 *
 * `params` are passed to the source and may reach the API (an interval, a page size).
 * `filters`, `sort` and `search` are applied by the engine after retrieval, so every column is
 * filterable and sortable regardless of what the underlying Genesys endpoint supports.
 */
export interface QueryDefinition {
  sourceId: string;
  params: Record<string, unknown>;
  search: string;
  filters: FilterClause[];
  sort: SortClause[];
  groupBy: string[];
  limit?: number;
}

export const emptyQuery = (sourceId: string): QueryDefinition => ({
  sourceId,
  params: {},
  search: '',
  filters: [],
  sort: [],
  groupBy: [],
});

// ─── DataSource ──────────────────────────────────────────────────────────────

/** One HTTP call a source made, surfaced so the UI can show what was exercised. */
export interface RequestTrace {
  method: string;
  url: string;
  status: number;
  durationMs: number;
  /** Catalog endpoint key, tying the call back to the server's /__meta outline. */
  endpointKey?: string;
  note?: string;
}

export interface DataSetMeta {
  sourceId: string;
  fetchedAt: string;
  durationMs: number;
  requests: RequestTrace[];
  warnings: string[];
}

export interface DataSet {
  records: DataRecord[];
  fields: FieldDefinition[];
  meta: DataSetMeta;
}

export interface FetchContext {
  signal?: AbortSignal;
}

/**
 * A named, retrievable collection of Genesys records.
 *
 * This is the only layer that knows Genesys semantics. Adding a new explorer to the application
 * means adding a DataSource, not a screen.
 */
export interface DataSource {
  id: string;
  name: string;
  group: string;
  description: string;
  /** Catalog endpoint keys this source exercises, used to cross-link the endpoint outline. */
  endpointKeys: string[];
  fields: FieldDefinition[];
  defaultQuery?: Partial<QueryDefinition>;
  fetch(ctx: FetchContext, query: QueryDefinition): Promise<DataSet>;
}

// ─── ViewDefinition ──────────────────────────────────────────────────────────

export interface ColumnState {
  key: string;
  visible: boolean;
  width?: number;
}

export type Density = 'comfortable' | 'cozy' | 'compact';

/** A saved way of looking at one source: its query plus column layout. */
export interface ViewDefinition {
  id: string;
  name: string;
  sourceId: string;
  query: QueryDefinition;
  /** Ordered. Order in this array is the column order on screen. */
  columns: ColumnState[];
  density: Density;
  createdAt: string;
  updatedAt: string;
  /** Shipped with the app and not user-deletable. */
  builtIn?: boolean;
}

// ─── ReportDefinition ────────────────────────────────────────────────────────

export type AggregateFn = 'count' | 'countDistinct' | 'sum' | 'avg' | 'min' | 'max';

export interface ReportMetric {
  id: string;
  field: string;
  fn: AggregateFn;
  label?: string;
}

/**
 * An ad-hoc aggregation over a source: group by zero or more fields, compute metrics.
 * With no groupBy this is a single summary row.
 */
export interface ReportDefinition {
  id: string;
  name: string;
  sourceId: string;
  query: QueryDefinition;
  groupBy: string[];
  metrics: ReportMetric[];
  createdAt: string;
  updatedAt: string;
}

export interface ReportRow {
  key: string;
  groups: Record<string, unknown>;
  metrics: Record<string, number | null>;
  count: number;
}

export interface ReportResult {
  rows: ReportRow[];
  groupBy: string[];
  metrics: ReportMetric[];
  totalRecords: number;
}

// ─── DashboardDefinition ─────────────────────────────────────────────────────

export type TileKind = 'table' | 'report' | 'metric' | 'bar';

export interface DashboardTile {
  id: string;
  title: string;
  kind: TileKind;
  /** References a saved view or report by id, depending on kind. */
  refId: string;
  /** Grid width in twelfths. */
  span: number;
}

export interface DashboardDefinition {
  id: string;
  name: string;
  tiles: DashboardTile[];
  createdAt: string;
  updatedAt: string;
}

// ─── ExportDefinition ────────────────────────────────────────────────────────

export type ExportFormat = 'csv' | 'json' | 'ndjson' | 'markdown';

export interface ExportDefinition {
  format: ExportFormat;
  /** Field keys to include, in order. Empty means every visible column. */
  columns: string[];
  scope: 'visible' | 'all';
  filename?: string;
  /** Prepend a provenance header describing where the data came from. */
  includeProvenance: boolean;
}

export const defaultExport = (): ExportDefinition => ({
  format: 'csv',
  columns: [],
  scope: 'visible',
  includeProvenance: true,
});

// ─── Workspace ───────────────────────────────────────────────────────────────

export type SkinId = 'genesys' | 'atlas';
export type ThemeMode = 'light' | 'dark' | 'system';

/** Everything the user has personalized, persisted between sessions. */
export interface Workspace {
  version: number;
  skin: SkinId;
  theme: ThemeMode;
  accent: string;
  density: Density;
  views: ViewDefinition[];
  reports: ReportDefinition[];
  dashboards: DashboardDefinition[];
  /** Ordered panel ids per feature page, driving the movable layout. */
  panelOrder: Record<string, string[]>;
  collapsedPanels: string[];
}

export const WORKSPACE_VERSION = 1;

export const emptyWorkspace = (): Workspace => ({
  version: WORKSPACE_VERSION,
  skin: 'genesys',
  theme: 'system',
  accent: '#ff4f1f',
  density: 'cozy',
  views: [],
  reports: [],
  dashboards: [],
  panelOrder: {},
  collapsedPanels: [],
});

/** Short random id for user-created objects. */
export const newId = (prefix: string): string =>
  `${prefix}-${Math.random().toString(36).slice(2, 9)}`;
