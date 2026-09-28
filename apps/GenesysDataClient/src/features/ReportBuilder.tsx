/**
 * Ad-hoc report builder.
 *
 * Group the currently filtered records by any field, aggregate any field, and export the result.
 * It operates on whatever the explorer has already filtered, so a report always reflects exactly
 * what is on screen.
 */

import { useMemo, useState } from 'react';
import type { AggregateFn, DataRecord, DataSetMeta, FieldDefinition, ReportMetric } from '../core/contracts';
import { newId } from '../core/contracts';
import { AGGREGATE_LABELS, buildReport, formatValue, toText } from '../engine/query';
import { ExportBar } from '../components/ExportBar';
import { Badge, Button, IconButton } from '../components/primitives';

const NUMERIC_ONLY: AggregateFn[] = ['sum', 'avg', 'min', 'max'];

export const ReportBuilder = ({
  sourceName,
  fields,
  records,
  meta,
}: {
  sourceName: string;
  fields: FieldDefinition[];
  records: DataRecord[];
  meta?: DataSetMeta;
}) => {
  const [groupBy, setGroupBy] = useState<string[]>([]);
  const [metrics, setMetrics] = useState<ReportMetric[]>([]);

  const groupable = useMemo(() => fields.filter((f) => f.type !== 'json'), [fields]);
  const result = useMemo(
    () => buildReport(records, fields, { groupBy, metrics }),
    [records, fields, groupBy, metrics],
  );

  const labelOf = (key: string) => fields.find((f) => f.key === key)?.label ?? key;

  const addMetric = () => {
    const numeric = fields.find((f) => f.type === 'number' || f.type === 'duration');
    const target = numeric ?? fields[0];
    if (!target) return;
    setMetrics([
      ...metrics,
      { id: newId('metric'), field: target.key, fn: numeric ? 'avg' : 'count' },
    ]);
  };

  const toggleGroup = (key: string) => {
    setGroupBy(groupBy.includes(key) ? groupBy.filter((g) => g !== key) : [...groupBy, key]);
  };

  // Report rows are exported through the same engine as record rows.
  const reportFieldsForExport: FieldDefinition[] = fields;

  return (
    <div className="report">
      <div className="report__controls">
        <div className="report__group">
          <h3 className="report__heading">Group by</h3>
          <div className="report__chips">
            {groupable.map((field) => (
              <button
                key={field.key}
                type="button"
                className={`chip${groupBy.includes(field.key) ? ' chip--on' : ''}`}
                onClick={() => toggleGroup(field.key)}
                aria-pressed={groupBy.includes(field.key)}
              >
                {field.label}
              </button>
            ))}
          </div>
          {groupBy.length === 0 ? (
            <p className="report__hint">
              No grouping selected — the report is a single total row. Pick one or more fields to break it down.
            </p>
          ) : (
            <p className="report__hint">
              Grouped by {groupBy.map(labelOf).join(' → ')}.
            </p>
          )}
        </div>

        <div className="report__group">
          <h3 className="report__heading">Metrics</h3>
          {metrics.length === 0 ? (
            <p className="report__hint">Row counts are always included. Add a metric to aggregate a field.</p>
          ) : (
            <ul className="report__metrics">
              {metrics.map((metric) => {
                const field = fields.find((f) => f.key === metric.field);
                const isNumeric = field?.type === 'number' || field?.type === 'duration' || field?.type === 'date';
                const available = (Object.keys(AGGREGATE_LABELS) as AggregateFn[]).filter(
                  (fn) => isNumeric || !NUMERIC_ONLY.includes(fn),
                );
                return (
                  <li key={metric.id} className="report__metric">
                    <select
                      className="field__control"
                      value={metric.fn}
                      onChange={(event) =>
                        setMetrics(
                          metrics.map((m) =>
                            m.id === metric.id ? { ...m, fn: event.target.value as AggregateFn } : m,
                          ),
                        )
                      }
                      aria-label="Aggregate function"
                    >
                      {available.map((fn) => (
                        <option key={fn} value={fn}>
                          {AGGREGATE_LABELS[fn]}
                        </option>
                      ))}
                    </select>
                    <select
                      className="field__control"
                      value={metric.field}
                      onChange={(event) =>
                        setMetrics(
                          metrics.map((m) => (m.id === metric.id ? { ...m, field: event.target.value } : m)),
                        )
                      }
                      aria-label="Metric field"
                    >
                      {fields.map((f) => (
                        <option key={f.key} value={f.key}>
                          {f.label}
                        </option>
                      ))}
                    </select>
                    <IconButton
                      label="Remove metric"
                      onClick={() => setMetrics(metrics.filter((m) => m.id !== metric.id))}
                    >
                      ×
                    </IconButton>
                  </li>
                );
              })}
            </ul>
          )}
          <div className="report__actions">
            <Button onClick={addMetric}>Add metric</Button>
            {(groupBy.length > 0 || metrics.length > 0) && (
              <Button
                variant="ghost"
                onClick={() => {
                  setGroupBy([]);
                  setMetrics([]);
                }}
              >
                Reset
              </Button>
            )}
          </div>
        </div>
      </div>

      <div className="report__result">
        <div className="report__summary">
          <Badge tone="accent">
            {result.rows.length} group{result.rows.length === 1 ? '' : 's'}
          </Badge>
          <Badge tone="muted">{result.totalRecords} records</Badge>
        </div>

        <div className="grid-wrap">
          <table className="grid">
            <thead>
              <tr>
                {groupBy.map((key) => (
                  <th key={key} className="grid__th">
                    <span className="grid__label">{labelOf(key)}</span>
                  </th>
                ))}
                <th className="grid__th grid__th--right">
                  <span className="grid__label">Records</span>
                </th>
                {metrics.map((metric) => (
                  <th key={metric.id} className="grid__th grid__th--right">
                    <span className="grid__label">
                      {AGGREGATE_LABELS[metric.fn]} of {labelOf(metric.field)}
                    </span>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {result.rows.length === 0 ? (
                <tr>
                  <td className="grid__empty" colSpan={groupBy.length + metrics.length + 1}>
                    Nothing to report — no records match the current filters.
                  </td>
                </tr>
              ) : (
                result.rows.map((row) => (
                  <tr key={row.key} className="grid__row">
                    {groupBy.map((key) => {
                      const field = fields.find((f) => f.key === key);
                      const text = field ? formatValue(row.groups[key], field.type) : toText(row.groups[key]);
                      return (
                        <td key={key} className="grid__td">
                          {text === '' ? <span className="grid__blank">(blank)</span> : text}
                        </td>
                      );
                    })}
                    <td className="grid__td grid__td--right">{row.count.toLocaleString()}</td>
                    {metrics.map((metric) => {
                      const value = row.metrics[metric.id];
                      const field = fields.find((f) => f.key === metric.field);
                      // An aggregate keeps its field's type unless it is a plain tally, so an
                      // average duration reads as a duration and the earliest timestamp reads as
                      // a date rather than as epoch milliseconds.
                      const counting = metric.fn === 'count' || metric.fn === 'countDistinct';
                      const type = counting ? 'number' : (field?.type ?? 'number');
                      return (
                        <td key={metric.id} className="grid__td grid__td--right">
                          {value === null || value === undefined
                            ? ''
                            : type === 'duration' || type === 'date'
                              ? formatValue(value, type)
                              : Math.round(value * 100) / 100}
                        </td>
                      );
                    })}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        <ExportBar
          sourceName={`${sourceName} report`}
          fields={reportFieldsForExport}
          report={result}
          visibleColumnKeys={[]}
          meta={meta}
          filterSummary={groupBy.length > 0 ? `grouped by ${groupBy.map(labelOf).join(', ')}` : 'ungrouped total'}
        />
      </div>
    </div>
  );
};
