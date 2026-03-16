# Audit Logs Console UX Spec

## Main Panes

- Header
  Region selector, bearer-token connect action, startup validation state, session state.
- Left Run Builder
  Dataset selector, time preset, start/end UTC controls, service/action filters, actor/entity/keyword filters, preview limit, Preview button, Full Extract button, recent runs list.
- Results tab
  Current run summary strip, main audit grid, paging controls, filtered/full export buttons.
- Drilldown tab
  Selected audit event summary, changed-property grid, raw JSON panel, copy actions.
- Run Console tab
  Current run state, last error, tailed `events.jsonl`, diagnostics preview, copy diagnostics button.

## Primary Operator Flow

1. Connect with a bearer token and region.
2. Pick a time preset or custom UTC range.
3. Optionally narrow by service/action before extraction.
4. Enter actor/entity/keyword filters if needed for post-run review.
5. Run Preview for a fast check or Full Extract for the full selected interval.
6. Review the grid, page through results, and click a row for drilldown.
7. Export the filtered view or the full run to CSV or HTML.

## Filter Controls

- Extraction-time narrowing
  Service / category and action are passed into `Invoke-Dataset` as dataset parameters.
- Review-time filtering
  Service, action, actor, entity, and keyword all filter the indexed run data in the UI.
- Preview result limit
  Caps the visible preview result set so operators can inspect a fast first slice.

## Preview vs Full Behavior

- Preview
  Optimized for speed, clamps oversized selected windows to a smaller recent window, then shows only the preview result cap in the grid.
- Full Extract
  Uses the full selected interval, retains the full run folder, and is the recommended source for export/reporting.

## Recent Runs

- Recent runs are loaded from the configured output root.
- Each row shows run id, status, mode, and row count.
- Selecting a recent run reloads its artifacts without re-querying Genesys Cloud.
- `Open Folder` opens the selected run directory for operator inspection.

## Drilldown

- Selecting a row loads the full event on demand from `data/audit.jsonl`.
- The detail pane shows:
  - flattened metadata summary
  - changed-property before/after rows when present
  - raw JSON
- Copy buttons support quick handoff into tickets or incident notes.

## Export

- `Export Filtered CSV`
  Current filtered result set only.
- `Export Full CSV`
  Entire selected run.
- `Export Filtered HTML`
  Current filtered result set with selected filters in the report header.
- `Export Full HTML`
  Entire selected run with summary metadata.

## Diagnostics / Run Console

- Shows `Queued`, `Running`, `Completed`, or `Failed`.
- Tails `events.jsonl` during live extraction.
- Surfaces the last known error message.
- `Copy Diagnostics` includes dataset key, run folder, selected filters, summary content, and the last 50 event lines.
