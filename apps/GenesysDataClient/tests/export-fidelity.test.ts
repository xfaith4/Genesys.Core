/**
 * Export fidelity.
 *
 * A CSV from a data workbench is a machine-reuse artifact: it gets opened in Excel, loaded into
 * a notebook, joined against other extracts. Display formatting that is right on screen is wrong
 * in that file - a locale-formatted date does not parse, and "21m 40s" does not aggregate.
 * Markdown is the human-readable format and keeps the friendly rendering.
 */

import { describe, expect, it } from 'vitest';
import type { DataRecord, FieldDefinition } from '../src/core/contracts';
import { buildReport } from '../src/engine/query';
import { exportRecords, exportReport } from '../src/engine/export';

const fields: FieldDefinition[] = [
  { key: 'name', label: 'Name', type: 'string' },
  { key: 'start', label: 'Start', type: 'date' },
  { key: 'durationMs', label: 'Duration', type: 'duration' },
  { key: 'count', label: 'Count', type: 'number' },
  { key: 'answered', label: 'Answered', type: 'boolean' },
];

const records: DataRecord[] = [
  { name: 'Alice', start: '2026-02-14T09:00:00.000Z', durationMs: 867_000, count: 1234567, answered: true },
  { name: 'Bob', start: '2026-02-15T10:30:00.000Z', durationMs: 120_000, count: 42, answered: false },
];

const ctx = { sourceName: 'Conversations', recordCount: records.length };
const def = (format: 'csv' | 'markdown') => ({
  format,
  columns: [] as string[],
  scope: 'visible' as const,
  includeProvenance: false,
});

const dataRows = (csv: string) => csv.split('\r\n').filter((l) => !l.startsWith('#'));

describe('CSV is machine-reusable', () => {
  it('emits ISO 8601 timestamps, not locale strings', () => {
    const rows = dataRows(exportRecords(records, fields, def('csv'), ctx));
    expect(rows[1]).toContain('2026-02-14T09:00:00.000Z');
    // A locale rendering would contain a month name or a slash-separated date.
    expect(rows[1]).not.toMatch(/Feb|\d\/\d/);
  });

  it('emits durations as raw milliseconds so they aggregate', () => {
    const rows = dataRows(exportRecords(records, fields, def('csv'), ctx));
    expect(rows[1]).toContain('867000');
    expect(rows[1]).not.toContain('14m');
  });

  it('emits numbers without thousands separators', () => {
    const rows = dataRows(exportRecords(records, fields, def('csv'), ctx));
    expect(rows[1]).toContain('1234567');
    expect(rows[1]).not.toContain('1,234,567');
  });

  it('emits booleans as true/false', () => {
    const rows = dataRows(exportRecords(records, fields, def('csv'), ctx));
    expect(rows[1]).toMatch(/(^|,)true(,|$)/);
    expect(rows[2]).toMatch(/(^|,)false(,|$)/);
  });

  it('states units and timestamp format in the provenance header', () => {
    const csv = exportRecords(
      records,
      fields,
      { ...def('csv'), includeProvenance: true },
      ctx,
    );
    expect(csv).toMatch(/# .*millisecond/i);
    expect(csv).toMatch(/# .*ISO 8601/i);
  });
});

describe('CSV formula injection', () => {
  const risky: DataRecord[] = [
    { name: '=1+1', start: '', durationMs: null, count: 0, answered: false },
    { name: '+44 20 7946 0000', start: '', durationMs: null, count: 0, answered: false },
    { name: '@SUM(A1:A9)', start: '', durationMs: null, count: 0, answered: false },
    { name: '-5 credit', start: '', durationMs: null, count: 0, answered: false },
  ];

  it('neutralizes cells a spreadsheet would evaluate as a formula', () => {
    const rows = dataRows(exportRecords(risky, fields, def('csv'), ctx));
    for (const row of rows.slice(1)) {
      // Every risky leading character must be defused with a leading apostrophe.
      expect(row).toMatch(/^("?')/);
    }
  });

  it('leaves genuine negative numbers alone', () => {
    const negatives: DataRecord[] = [{ name: 'x', start: '', durationMs: -1500, count: -42, answered: false }];
    const rows = dataRows(exportRecords(negatives, fields, def('csv'), ctx));
    expect(rows[1]).toContain('-1500');
    expect(rows[1]).toContain('-42');
    expect(rows[1]).not.toContain("'-42");
  });
});

describe('Markdown stays human-readable', () => {
  it('keeps friendly durations and dates', () => {
    const md = exportRecords(records, fields, def('markdown'), ctx);
    expect(md).toContain('14m 27s');
    expect(md).not.toContain('867000');
  });
});

describe('report exports', () => {
  it('renders min/max of a date field as a date, not epoch milliseconds', () => {
    const result = buildReport(records, fields, {
      groupBy: [],
      metrics: [{ id: 'm1', field: 'start', fn: 'min' }],
    });
    const csv = exportReport(result, fields, def('csv'), ctx);
    const row = dataRows(csv)[1] ?? '';
    expect(row).toContain('2026-02-14T09:00:00.000Z');
    expect(row).not.toContain('1771059600000');
  });

  it('renders duration aggregates as milliseconds in CSV', () => {
    const result = buildReport(records, fields, {
      groupBy: [],
      metrics: [{ id: 'm1', field: 'durationMs', fn: 'sum' }],
    });
    const csv = exportReport(result, fields, def('csv'), ctx);
    expect(dataRows(csv)[1]).toContain('987000');
  });
});
