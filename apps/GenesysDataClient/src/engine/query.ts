/**
 * The query engine: filtering, sorting, grouping and aggregation over flattened records.
 *
 * This is the "knows how to work with data" layer. It has no knowledge of Genesys, which is what
 * makes every column of every source filterable and sortable without per-screen code.
 */

import type {
  AggregateFn,
  DataRecord,
  FieldDefinition,
  FieldType,
  FilterClause,
  FilterOperator,
  QueryDefinition,
  ReportDefinition,
  ReportResult,
  ReportRow,
  SortClause,
} from '../core/contracts';

// ─── Value access and coercion ───────────────────────────────────────────────

/** Reads a possibly dotted path out of a record. */
export const getValue = (record: DataRecord, key: string): unknown => {
  if (key in record) return record[key];
  if (!key.includes('.')) return undefined;

  let current: unknown = record;
  for (const part of key.split('.')) {
    if (current === null || current === undefined) return undefined;
    if (typeof current !== 'object') return undefined;
    current = (current as Record<string, unknown>)[part];
  }
  return current;
};

export const isBlank = (value: unknown): boolean =>
  value === null ||
  value === undefined ||
  value === '' ||
  (Array.isArray(value) && value.length === 0);

const toNumber = (value: unknown): number | null => {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'boolean') return value ? 1 : 0;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
};

const toTime = (value: unknown): number | null => {
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
};

/** Stable text form used for search, string comparison and CSV output. */
export const toText = (value: unknown): string => {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (Array.isArray(value)) return value.map(toText).join(', ');
  if (value instanceof Date) return value.toISOString();
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
};

/** Comparable key for a value, respecting the declared field type. */
const comparableOf = (value: unknown, type: FieldType): number | string | null => {
  if (isBlank(value)) return null;
  switch (type) {
    case 'number':
    case 'duration':
      return toNumber(value);
    case 'date':
      return toTime(value);
    case 'boolean':
      return value ? 1 : 0;
    default:
      return toText(value).toLowerCase();
  }
};

// ─── Filtering ───────────────────────────────────────────────────────────────

const OPERATORS_BY_TYPE: Record<FieldType, FilterOperator[]> = {
  string: ['contains', 'notContains', 'eq', 'ne', 'startsWith', 'endsWith', 'in', 'isEmpty', 'isNotEmpty'],
  json: ['contains', 'notContains', 'isEmpty', 'isNotEmpty'],
  number: ['eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'isEmpty', 'isNotEmpty'],
  duration: ['gt', 'gte', 'lt', 'lte', 'eq', 'ne', 'isEmpty', 'isNotEmpty'],
  date: ['gte', 'lte', 'gt', 'lt', 'eq', 'ne', 'isEmpty', 'isNotEmpty'],
  boolean: ['eq', 'ne', 'isEmpty', 'isNotEmpty'],
};

export const operatorsFor = (type: FieldType): FilterOperator[] => OPERATORS_BY_TYPE[type] ?? OPERATORS_BY_TYPE.string;

export const OPERATOR_LABELS: Record<FilterOperator, string> = {
  eq: 'is',
  ne: 'is not',
  contains: 'contains',
  notContains: 'does not contain',
  startsWith: 'starts with',
  endsWith: 'ends with',
  gt: 'greater than',
  gte: 'on or after',
  lt: 'less than',
  lte: 'on or before',
  in: 'is any of',
  isEmpty: 'is empty',
  isNotEmpty: 'is not empty',
};

/** True when a single record satisfies one filter clause. */
export const matchesFilter = (
  record: DataRecord,
  clause: FilterClause,
  field: FieldDefinition | undefined,
): boolean => {
  const raw = getValue(record, clause.field);
  const type = field?.type ?? 'string';

  if (clause.operator === 'isEmpty') return isBlank(raw);
  if (clause.operator === 'isNotEmpty') return !isBlank(raw);

  if (clause.operator === 'in') {
    const wanted = (Array.isArray(clause.value) ? clause.value : String(clause.value ?? '').split(','))
      .map((v) => toText(v).trim().toLowerCase())
      .filter((v) => v !== '');
    if (wanted.length === 0) return true;
    return wanted.includes(toText(raw).toLowerCase());
  }

  // Text operators always work on the rendered text, so they apply to any field type.
  if (
    clause.operator === 'contains' ||
    clause.operator === 'notContains' ||
    clause.operator === 'startsWith' ||
    clause.operator === 'endsWith'
  ) {
    const haystack = toText(raw).toLowerCase();
    const needle = toText(clause.value).toLowerCase();
    if (needle === '') return true;
    switch (clause.operator) {
      case 'contains':
        return haystack.includes(needle);
      case 'notContains':
        return !haystack.includes(needle);
      case 'startsWith':
        return haystack.startsWith(needle);
      case 'endsWith':
        return haystack.endsWith(needle);
    }
  }

  const left = comparableOf(raw, type);
  const right = comparableOf(clause.value, type);
  if (right === null) return true; // an unset comparison value is not a constraint
  if (left === null) return false;

  switch (clause.operator) {
    case 'eq':
      return left === right;
    case 'ne':
      return left !== right;
    case 'gt':
      return left > right;
    case 'gte':
      return left >= right;
    case 'lt':
      return left < right;
    case 'lte':
      return left <= right;
    default:
      return true;
  }
};

/** True when a record matches the free-text search across every provided field. */
export const matchesSearch = (record: DataRecord, fields: FieldDefinition[], search: string): boolean => {
  const needle = search.trim().toLowerCase();
  if (needle === '') return true;
  return fields.some((field) => toText(getValue(record, field.key)).toLowerCase().includes(needle));
};

// ─── Sorting ─────────────────────────────────────────────────────────────────

export const compareRecords = (
  a: DataRecord,
  b: DataRecord,
  sort: SortClause[],
  fieldsByKey: Map<string, FieldDefinition>,
): number => {
  for (const clause of sort) {
    const type = fieldsByKey.get(clause.field)?.type ?? 'string';
    const left = comparableOf(getValue(a, clause.field), type);
    const right = comparableOf(getValue(b, clause.field), type);

    // Blanks sort last regardless of direction, so a descending sort still surfaces real values.
    if (left === null && right === null) continue;
    if (left === null) return 1;
    if (right === null) return -1;
    if (left === right) continue;

    const order = left < right ? -1 : 1;
    return clause.direction === 'asc' ? order : -order;
  }
  return 0;
};

// ─── Applying a query ────────────────────────────────────────────────────────

export interface QueryOutcome {
  records: DataRecord[];
  totalBeforeFilters: number;
}

/** Applies search, filters, sort and limit. Grouping is handled by the report engine. */
export const applyQuery = (
  records: DataRecord[],
  fields: FieldDefinition[],
  query: QueryDefinition,
): QueryOutcome => {
  const fieldsByKey = new Map(fields.map((f) => [f.key, f]));
  const activeFilters = query.filters.filter((f) => f.enabled);

  let result = records;

  if (query.search.trim() !== '') {
    result = result.filter((r) => matchesSearch(r, fields, query.search));
  }

  if (activeFilters.length > 0) {
    result = result.filter((record) =>
      activeFilters.every((clause) => matchesFilter(record, clause, fieldsByKey.get(clause.field))),
    );
  }

  if (query.sort.length > 0) {
    result = [...result].sort((a, b) => compareRecords(a, b, query.sort, fieldsByKey));
  }

  const limited = query.limit && query.limit > 0 ? result.slice(0, query.limit) : result;

  return { records: limited, totalBeforeFilters: records.length };
};

/** Distinct values for a field, most frequent first. Powers the facet pickers. */
export const distinctValues = (
  records: DataRecord[],
  key: string,
  limit = 50,
): { value: string; count: number }[] => {
  const counts = new Map<string, number>();
  for (const record of records) {
    const text = toText(getValue(record, key));
    counts.set(text, (counts.get(text) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([value, count]) => ({ value, count }))
    .sort((a, b) => b.count - a.count || a.value.localeCompare(b.value))
    .slice(0, limit);
};

// ─── Aggregation and reports ─────────────────────────────────────────────────

export const AGGREGATE_LABELS: Record<AggregateFn, string> = {
  count: 'Count',
  countDistinct: 'Distinct',
  sum: 'Sum',
  avg: 'Average',
  min: 'Minimum',
  max: 'Maximum',
};

const aggregate = (values: unknown[], fn: AggregateFn, type: FieldType): number | null => {
  if (fn === 'count') return values.filter((v) => !isBlank(v)).length;
  if (fn === 'countDistinct') return new Set(values.filter((v) => !isBlank(v)).map(toText)).size;

  const numeric = values
    .map((v) => (type === 'date' ? toTime(v) : toNumber(v)))
    .filter((v): v is number => v !== null);

  if (numeric.length === 0) return null;

  switch (fn) {
    case 'sum':
      return numeric.reduce((a, b) => a + b, 0);
    case 'avg':
      return numeric.reduce((a, b) => a + b, 0) / numeric.length;
    case 'min':
      return Math.min(...numeric);
    case 'max':
      return Math.max(...numeric);
    default:
      return null;
  }
};

/**
 * Builds an ad-hoc report: group the records, then compute each metric per group.
 * With an empty groupBy this yields a single total row.
 */
export const buildReport = (
  records: DataRecord[],
  fields: FieldDefinition[],
  report: Pick<ReportDefinition, 'groupBy' | 'metrics'>,
): ReportResult => {
  const fieldsByKey = new Map(fields.map((f) => [f.key, f]));
  const buckets = new Map<string, { groups: Record<string, unknown>; rows: DataRecord[] }>();

  for (const record of records) {
    const groups: Record<string, unknown> = {};
    for (const key of report.groupBy) groups[key] = getValue(record, key);
    const bucketKey = report.groupBy.length === 0 ? '__total__' : report.groupBy.map((k) => toText(groups[k])).join(' │ ');

    let bucket = buckets.get(bucketKey);
    if (!bucket) {
      bucket = { groups, rows: [] };
      buckets.set(bucketKey, bucket);
    }
    bucket.rows.push(record);
  }

  const rows: ReportRow[] = [...buckets.entries()].map(([key, bucket]) => {
    const metrics: Record<string, number | null> = {};
    for (const metric of report.metrics) {
      const type = fieldsByKey.get(metric.field)?.type ?? 'string';
      metrics[metric.id] = aggregate(
        bucket.rows.map((r) => getValue(r, metric.field)),
        metric.fn,
        type,
      );
    }
    return { key, groups: bucket.groups, metrics, count: bucket.rows.length };
  });

  // Largest groups first is the useful default for an investigation.
  rows.sort((a, b) => b.count - a.count);

  return {
    rows,
    groupBy: report.groupBy,
    metrics: report.metrics,
    totalRecords: records.length,
  };
};

// ─── Display formatting ──────────────────────────────────────────────────────

/** Renders milliseconds as a compact human duration. */
export const formatDuration = (ms: number): string => {
  if (!Number.isFinite(ms)) return '';
  const totalSeconds = Math.round(Math.abs(ms) / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const sign = ms < 0 ? '-' : '';
  if (hours > 0) return `${sign}${hours}h ${String(minutes).padStart(2, '0')}m ${String(seconds).padStart(2, '0')}s`;
  if (minutes > 0) return `${sign}${minutes}m ${String(seconds).padStart(2, '0')}s`;
  return `${sign}${seconds}s`;
};

/**
 * Renders a value for machine reuse rather than for reading.
 *
 * Display formatting is wrong in an extract: a locale-formatted timestamp does not parse, a
 * thousands separator is not a number, and "14m 27s" does not aggregate. Exports that a user
 * will load into a spreadsheet or a notebook use this; Markdown, which is meant to be read,
 * uses `formatValue`.
 */
export const formatForExport = (value: unknown, type: FieldType): string => {
  if (isBlank(value)) return '';
  switch (type) {
    case 'date': {
      const time = toTime(value);
      return time === null ? toText(value) : new Date(time).toISOString();
    }
    case 'duration': {
      // Milliseconds, so the column sums and averages like any other number.
      const ms = toNumber(value);
      return ms === null ? toText(value) : String(ms);
    }
    case 'number': {
      const num = toNumber(value);
      return num === null ? toText(value) : String(num);
    }
    case 'boolean':
      return value ? 'true' : 'false';
    default:
      return toText(value);
  }
};

/** Renders a value for display according to its field type. */
export const formatValue = (value: unknown, type: FieldType): string => {
  if (isBlank(value)) return '';
  switch (type) {
    case 'duration': {
      const ms = toNumber(value);
      return ms === null ? toText(value) : formatDuration(ms);
    }
    case 'date': {
      const time = toTime(value);
      if (time === null) return toText(value);
      return new Date(time).toLocaleString(undefined, {
        year: 'numeric',
        month: 'short',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
      });
    }
    case 'number': {
      const num = toNumber(value);
      return num === null ? toText(value) : num.toLocaleString();
    }
    case 'boolean':
      return value ? 'Yes' : 'No';
    default:
      return toText(value);
  }
};
