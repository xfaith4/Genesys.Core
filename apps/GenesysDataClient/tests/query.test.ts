import { describe, expect, it } from 'vitest';
import type { DataRecord, FieldDefinition, QueryDefinition } from '../src/core/contracts';
import { emptyQuery } from '../src/core/contracts';
import {
  applyQuery,
  buildReport,
  distinctValues,
  formatDuration,
  formatValue,
  getValue,
  matchesFilter,
} from '../src/engine/query';
import { exportRecords, exportReport } from '../src/engine/export';

const fields: FieldDefinition[] = [
  { key: 'name', label: 'Name', type: 'string' },
  { key: 'queue', label: 'Queue', type: 'string', facetable: true },
  { key: 'durationMs', label: 'Duration', type: 'duration' },
  { key: 'start', label: 'Start', type: 'date' },
  { key: 'answered', label: 'Answered', type: 'boolean' },
  { key: 'nested.value', label: 'Nested', type: 'number' },
];

const records: DataRecord[] = [
  { name: 'Alice', queue: 'Support', durationMs: 60_000, start: '2026-02-14T09:00:00Z', answered: true, nested: { value: 3 } },
  { name: 'Bob', queue: 'Sales', durationMs: 120_000, start: '2026-02-15T09:00:00Z', answered: false, nested: { value: 7 } },
  { name: 'Cara', queue: 'Support', durationMs: 30_000, start: '2026-02-13T09:00:00Z', answered: true, nested: { value: 1 } },
  { name: 'Dan', queue: '', durationMs: null, start: '', answered: false, nested: { value: 5 } },
];

const query = (patch: Partial<QueryDefinition> = {}): QueryDefinition => ({
  ...emptyQuery('test'),
  ...patch,
});

describe('getValue', () => {
  it('reads flat and dotted paths', () => {
    expect(getValue(records[0]!, 'name')).toBe('Alice');
    expect(getValue(records[0]!, 'nested.value')).toBe(3);
  });

  it('returns undefined for a missing path rather than throwing', () => {
    expect(getValue(records[0]!, 'missing.deep.path')).toBeUndefined();
  });
});

describe('filtering', () => {
  it('matches text operators case-insensitively', () => {
    const clause = { id: 'f1', field: 'name', operator: 'contains' as const, value: 'ali', enabled: true };
    expect(matchesFilter(records[0]!, clause, fields[0])).toBe(true);
    expect(matchesFilter(records[1]!, clause, fields[0])).toBe(false);
  });

  it('compares numerically for duration fields, not as text', () => {
    // As text "60000" > "120000"; numerically it is not.
    const clause = { id: 'f2', field: 'durationMs', operator: 'gt' as const, value: 100_000, enabled: true };
    expect(matchesFilter(records[0]!, clause, fields[2])).toBe(false);
    expect(matchesFilter(records[1]!, clause, fields[2])).toBe(true);
  });

  it('treats an unset comparison value as no constraint', () => {
    const clause = { id: 'f3', field: 'durationMs', operator: 'gt' as const, value: '', enabled: true };
    expect(records.every((r) => matchesFilter(r, clause, fields[2]))).toBe(true);
  });

  it('handles isEmpty and isNotEmpty', () => {
    const empty = { id: 'f4', field: 'queue', operator: 'isEmpty' as const, enabled: true };
    expect(matchesFilter(records[3]!, empty, fields[1])).toBe(true);
    expect(matchesFilter(records[0]!, empty, fields[1])).toBe(false);
  });

  it('ignores disabled clauses', () => {
    const result = applyQuery(records, fields, {
      ...query(),
      filters: [{ id: 'f5', field: 'name', operator: 'eq', value: 'nobody', enabled: false }],
    });
    expect(result.records).toHaveLength(4);
  });
});

describe('search', () => {
  it('searches across every field', () => {
    const result = applyQuery(records, fields, query({ search: 'sales' }));
    expect(result.records.map((r) => r.name)).toEqual(['Bob']);
  });

  it('reports the pre-filter total so the UI can show "n of m"', () => {
    const result = applyQuery(records, fields, query({ search: 'sales' }));
    expect(result.totalBeforeFilters).toBe(4);
  });
});

describe('sorting', () => {
  it('sorts durations numerically', () => {
    const result = applyQuery(records, fields, query({ sort: [{ field: 'durationMs', direction: 'asc' }] }));
    expect(result.records.map((r) => r.durationMs)).toEqual([30_000, 60_000, 120_000, null]);
  });

  it('sorts blanks last even when descending', () => {
    const result = applyQuery(records, fields, query({ sort: [{ field: 'durationMs', direction: 'desc' }] }));
    expect(result.records[result.records.length - 1]!.durationMs).toBeNull();
  });

  it('sorts dates chronologically, not lexically', () => {
    const result = applyQuery(records, fields, query({ sort: [{ field: 'start', direction: 'asc' }] }));
    const names = result.records.map((r) => r.name);
    expect(names.slice(0, 3)).toEqual(['Cara', 'Alice', 'Bob']);
  });

  it('applies a multi-column sort in order', () => {
    const result = applyQuery(records, fields, {
      ...query(),
      sort: [
        { field: 'queue', direction: 'asc' },
        { field: 'durationMs', direction: 'desc' },
      ],
    });
    // Sales before Support, blank queue last; within Support the longer call comes first.
    expect(result.records.map((r) => r.name)).toEqual(['Bob', 'Alice', 'Cara', 'Dan']);
  });
});

describe('facets', () => {
  it('returns distinct values ordered by frequency', () => {
    expect(distinctValues(records, 'queue')).toEqual([
      { value: 'Support', count: 2 },
      { value: '', count: 1 },
      { value: 'Sales', count: 1 },
    ]);
  });
});

describe('reports', () => {
  it('produces a single total row when nothing is grouped', () => {
    const result = buildReport(records, fields, { groupBy: [], metrics: [] });
    expect(result.rows).toHaveLength(1);
    expect(result.rows[0]!.count).toBe(4);
  });

  it('groups and aggregates', () => {
    const result = buildReport(records, fields, {
      groupBy: ['queue'],
      metrics: [
        { id: 'm1', field: 'durationMs', fn: 'sum' },
        { id: 'm2', field: 'durationMs', fn: 'avg' },
      ],
    });

    const support = result.rows.find((r) => r.groups.queue === 'Support');
    expect(support?.count).toBe(2);
    expect(support?.metrics.m1).toBe(90_000);
    expect(support?.metrics.m2).toBe(45_000);
  });

  it('returns null for an aggregate with no numeric values', () => {
    const result = buildReport(records, fields, {
      groupBy: [],
      metrics: [{ id: 'm1', field: 'name', fn: 'sum' }],
    });
    expect(result.rows[0]!.metrics.m1).toBeNull();
  });

  it('counts distinct values', () => {
    const result = buildReport(records, fields, {
      groupBy: [],
      metrics: [{ id: 'm1', field: 'queue', fn: 'countDistinct' }],
    });
    // Blank is not counted as a distinct value.
    expect(result.rows[0]!.metrics.m1).toBe(2);
  });
});

describe('formatting', () => {
  it('formats durations compactly', () => {
    expect(formatDuration(30_000)).toBe('30s');
    expect(formatDuration(90_000)).toBe('1m 30s');
    expect(formatDuration(3_930_000)).toBe('1h 05m 30s');
  });

  it('renders booleans as words', () => {
    expect(formatValue(true, 'boolean')).toBe('Yes');
    expect(formatValue(false, 'boolean')).toBe('No');
    // Genuinely absent values stay blank rather than rendering as "No".
    expect(formatValue(null, 'boolean')).toBe('');
  });
});

describe('export', () => {
  const ctx = { sourceName: 'Test', recordCount: records.length };

  it('quotes CSV cells containing separators', () => {
    const tricky: DataRecord[] = [{ name: 'Smith, John', queue: 'He said "hi"' }];
    const csv = exportRecords(
      tricky,
      fields,
      { format: 'csv', columns: ['name', 'queue'], scope: 'visible', includeProvenance: false },
      ctx,
    );
    expect(csv).toContain('"Smith, John"');
    expect(csv).toContain('"He said ""hi"""');
  });

  it('honours the selected column subset and order', () => {
    const csv = exportRecords(
      records,
      fields,
      { format: 'csv', columns: ['queue', 'name'], scope: 'visible', includeProvenance: false },
      ctx,
    );
    expect(csv.split('\r\n')[0]).toBe('Queue,Name');
  });

  it('emits one JSON object per line for ndjson', () => {
    const ndjson = exportRecords(
      records,
      fields,
      { format: 'ndjson', columns: ['name'], scope: 'visible', includeProvenance: true },
      ctx,
    );
    const lines = ndjson.split('\n');
    expect(lines).toHaveLength(4);
    expect(JSON.parse(lines[0]!)).toEqual({ name: 'Alice' });
  });

  it('includes provenance when asked', () => {
    const csv = exportRecords(
      records,
      fields,
      { format: 'csv', columns: ['name'], scope: 'visible', includeProvenance: true },
      ctx,
    );
    expect(csv).toContain('# Genesys Data Client export');
    expect(csv).toContain('# Records: 4');
  });

  it('exports a report with its group and metric headers', () => {
    const result = buildReport(records, fields, {
      groupBy: ['queue'],
      metrics: [{ id: 'm1', field: 'durationMs', fn: 'sum', label: 'Total talk' }],
    });
    const csv = exportReport(
      result,
      fields,
      { format: 'csv', columns: [], scope: 'visible', includeProvenance: false },
      ctx,
    );
    expect(csv.split('\r\n')[0]).toBe('Queue,Records,Total talk');
  });
});
