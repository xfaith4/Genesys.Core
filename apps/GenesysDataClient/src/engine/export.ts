/**
 * Export engine: turns records or a report into a downloadable artifact.
 *
 * Every export carries optional provenance, because an exported extract that cannot be traced
 * back to its data window and source is not much use in an investigation.
 */

import type {
  DataRecord,
  DataSetMeta,
  ExportDefinition,
  FieldDefinition,
  ReportResult,
} from '../core/contracts';
import { formatForExport, formatValue, getValue } from './query';

export interface ExportContext {
  sourceName: string;
  meta?: DataSetMeta;
  filterSummary?: string;
  recordCount: number;
}

/**
 * Spreadsheets evaluate a cell beginning with =, +, - or @ as a formula, so exported Genesys
 * data - participant names, wrap-up notes, anything a person can type - could execute on open.
 * Prefixing with an apostrophe neutralizes it. Genuine numbers are left alone so that a negative
 * value stays a number rather than becoming text.
 */
const NEUTRALIZE = /^[=+\-@\t\r]/;

const isNumeric = (text: string): boolean => text.trim() !== '' && Number.isFinite(Number(text));

const csvCell = (raw: string): string => {
  const text = NEUTRALIZE.test(raw) && !isNumeric(raw) ? `'${raw}` : raw;
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
};

const provenanceLines = (ctx: ExportContext): string[] => {
  const lines = [
    `Genesys Data Client export`,
    `Source: ${ctx.sourceName}`,
    `Records: ${ctx.recordCount}`,
    `Generated: ${new Date().toISOString()}`,
    `Units: durations are in milliseconds; timestamps are ISO 8601 UTC.`,
  ];
  if (ctx.meta) {
    lines.push(`Retrieved: ${ctx.meta.fetchedAt} (${ctx.meta.durationMs} ms)`);
    if (ctx.meta.requests.length > 0) {
      lines.push(`Requests: ${ctx.meta.requests.map((r) => `${r.method} ${r.url} -> ${r.status}`).join(' | ')}`);
    }
  }
  if (ctx.filterSummary) lines.push(`Filters: ${ctx.filterSummary}`);
  return lines;
};

/** Serializes records to the requested format. */
export const exportRecords = (
  records: DataRecord[],
  fields: FieldDefinition[],
  definition: ExportDefinition,
  ctx: ExportContext,
): string => {
  const chosen =
    definition.columns.length > 0
      ? (definition.columns
          .map((key) => fields.find((f) => f.key === key))
          .filter((f): f is FieldDefinition => Boolean(f)))
      : fields;

  switch (definition.format) {
    case 'json': {
      const payload = {
        ...(definition.includeProvenance
          ? { provenance: { source: ctx.sourceName, generated: new Date().toISOString(), meta: ctx.meta } }
          : {}),
        records: records.map((record) => {
          const row: Record<string, unknown> = {};
          for (const field of chosen) row[field.key] = getValue(record, field.key);
          return row;
        }),
      };
      return JSON.stringify(payload, null, 2);
    }

    case 'ndjson':
      // One object per line, deliberately without a provenance wrapper so the file stays streamable.
      return records
        .map((record) => {
          const row: Record<string, unknown> = {};
          for (const field of chosen) row[field.key] = getValue(record, field.key);
          return JSON.stringify(row);
        })
        .join('\n');

    case 'markdown': {
      const header = `| ${chosen.map((f) => f.label).join(' | ')} |`;
      const divider = `| ${chosen.map(() => '---').join(' | ')} |`;
      const body = records.map(
        (record) =>
          `| ${chosen
            .map((f) => formatValue(getValue(record, f.key), f.type).replace(/\|/g, '\\|'))
            .join(' | ')} |`,
      );
      const preamble = definition.includeProvenance
        ? [`# ${ctx.sourceName}`, '', ...provenanceLines(ctx).map((l) => `- ${l}`), '']
        : [];
      return [...preamble, header, divider, ...body].join('\n');
    }

    case 'csv':
    default: {
      const lines: string[] = [];
      if (definition.includeProvenance) {
        for (const line of provenanceLines(ctx)) lines.push(`# ${line}`);
      }
      lines.push(chosen.map((f) => csvCell(f.label)).join(','));
      for (const record of records) {
        lines.push(chosen.map((f) => csvCell(formatForExport(getValue(record, f.key), f.type))).join(','));
      }
      return lines.join('\r\n');
    }
  }
};

/** Serializes an aggregated report. */
export const exportReport = (
  result: ReportResult,
  fields: FieldDefinition[],
  definition: ExportDefinition,
  ctx: ExportContext,
): string => {
  const labelOf = (key: string) => fields.find((f) => f.key === key)?.label ?? key;
  const headers = [
    ...result.groupBy.map(labelOf),
    'Records',
    ...result.metrics.map((m) => m.label ?? `${m.fn}(${labelOf(m.field)})`),
  ];

  const typeOf = (key: string) => fields.find((f) => f.key === key)?.type ?? 'string';

  const rows = result.rows.map((row) => [
    ...result.groupBy.map((key) => formatForExport(row.groups[key], typeOf(key))),
    String(row.count),
    ...result.metrics.map((m) => {
      const value = row.metrics[m.id];
      if (value === null || value === undefined) return '';
      // An aggregate keeps the field's type unless the aggregate is itself a plain tally, so
      // min/max of a timestamp exports as a timestamp rather than as epoch milliseconds.
      const counting = m.fn === 'count' || m.fn === 'countDistinct';
      const type = counting ? 'number' : typeOf(m.field);
      return formatForExport(type === 'date' ? new Date(value).toISOString() : value, type);
    }),
  ]);

  switch (definition.format) {
    case 'json':
      return JSON.stringify(
        {
          ...(definition.includeProvenance
            ? { provenance: { source: ctx.sourceName, generated: new Date().toISOString() } }
            : {}),
          groupBy: result.groupBy,
          rows: result.rows,
        },
        null,
        2,
      );

    case 'ndjson':
      return result.rows.map((row) => JSON.stringify(row)).join('\n');

    case 'markdown': {
      const preamble = definition.includeProvenance
        ? [`# ${ctx.sourceName} report`, '', ...provenanceLines(ctx).map((l) => `- ${l}`), '']
        : [];
      return [
        ...preamble,
        `| ${headers.join(' | ')} |`,
        `| ${headers.map(() => '---').join(' | ')} |`,
        ...rows.map((r) => `| ${r.map((c) => c.replace(/\|/g, '\\|')).join(' | ')} |`),
      ].join('\n');
    }

    case 'csv':
    default: {
      const lines: string[] = [];
      if (definition.includeProvenance) {
        for (const line of provenanceLines(ctx)) lines.push(`# ${line}`);
      }
      lines.push(headers.map(csvCell).join(','));
      for (const row of rows) lines.push(row.map(csvCell).join(','));
      return lines.join('\r\n');
    }
  }
};

const MIME: Record<ExportDefinition['format'], string> = {
  csv: 'text/csv;charset=utf-8',
  json: 'application/json;charset=utf-8',
  ndjson: 'application/x-ndjson;charset=utf-8',
  markdown: 'text/markdown;charset=utf-8',
};

const EXTENSION: Record<ExportDefinition['format'], string> = {
  csv: 'csv',
  json: 'json',
  ndjson: 'ndjson',
  markdown: 'md',
};

export const suggestFilename = (base: string, format: ExportDefinition['format']): string => {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const safe = base.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return `${safe || 'export'}-${stamp}.${EXTENSION[format]}`;
};

/** Triggers a browser download for already-serialized content. */
export const downloadText = (content: string, filename: string, format: ExportDefinition['format']): void => {
  const blob = new Blob([content], { type: MIME[format] });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  // Revoking immediately can cancel the download in some browsers; defer a tick.
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};

export const copyToClipboard = async (content: string): Promise<boolean> => {
  try {
    await navigator.clipboard.writeText(content);
    return true;
  } catch {
    return false;
  }
};
