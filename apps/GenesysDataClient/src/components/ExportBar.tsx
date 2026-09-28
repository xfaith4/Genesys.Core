/** Export controls shared by the explorers and the report builder. */

import { useState } from 'react';
import type {
  DataSetMeta,
  ExportDefinition,
  ExportFormat,
  FieldDefinition,
  DataRecord,
  ReportResult,
} from '../core/contracts';
import { defaultExport } from '../core/contracts';
import { copyToClipboard, downloadText, exportRecords, exportReport, suggestFilename } from '../engine/export';
import { Button, Select, Toggle } from './primitives';

const FORMATS: { value: ExportFormat; label: string }[] = [
  { value: 'csv', label: 'CSV' },
  { value: 'json', label: 'JSON' },
  { value: 'ndjson', label: 'NDJSON' },
  { value: 'markdown', label: 'Markdown' },
];

export const ExportBar = ({
  sourceName,
  fields,
  records,
  report,
  visibleColumnKeys,
  meta,
  filterSummary,
}: {
  sourceName: string;
  fields: FieldDefinition[];
  /** Supply records for a row export, or a report for an aggregate export. */
  records?: DataRecord[];
  report?: ReportResult;
  visibleColumnKeys: string[];
  meta?: DataSetMeta;
  filterSummary?: string;
}) => {
  const [definition, setDefinition] = useState<ExportDefinition>(defaultExport);
  const [status, setStatus] = useState<string | null>(null);

  const rowCount = report ? report.rows.length : (records?.length ?? 0);

  const serialize = (): string => {
    const columns = definition.scope === 'visible' ? visibleColumnKeys : [];
    const withColumns = { ...definition, columns };
    const ctx = { sourceName, meta, filterSummary, recordCount: rowCount };
    if (report) return exportReport(report, fields, withColumns, ctx);
    return exportRecords(records ?? [], fields, withColumns, ctx);
  };

  const onDownload = () => {
    const content = serialize();
    downloadText(content, suggestFilename(sourceName, definition.format), definition.format);
    setStatus(`Exported ${rowCount} row${rowCount === 1 ? '' : 's'}.`);
  };

  const onCopy = async () => {
    const ok = await copyToClipboard(serialize());
    setStatus(ok ? 'Copied to clipboard.' : 'Clipboard is unavailable in this browser.');
  };

  return (
    <div className="export-bar">
      <Select
        label="Format"
        value={definition.format}
        onChange={(format) => setDefinition({ ...definition, format })}
        options={FORMATS}
      />
      {!report ? (
        <Select
          label="Columns"
          value={definition.scope}
          onChange={(scope) => setDefinition({ ...definition, scope })}
          options={[
            { value: 'visible', label: 'Visible only' },
            { value: 'all', label: 'All fields' },
          ]}
        />
      ) : null}
      <Toggle
        checked={definition.includeProvenance}
        onChange={(includeProvenance) => setDefinition({ ...definition, includeProvenance })}
        label="Include provenance"
      />
      <div className="export-bar__actions">
        <Button variant="primary" onClick={onDownload} disabled={rowCount === 0}>
          Download {rowCount} row{rowCount === 1 ? '' : 's'}
        </Button>
        <Button onClick={onCopy} disabled={rowCount === 0}>
          Copy
        </Button>
      </div>
      {status ? (
        <span className="export-bar__status" role="status">
          {status}
        </span>
      ) : null}
    </div>
  );
};
