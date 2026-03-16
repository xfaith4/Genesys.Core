# Audit Logs Console Architecture

## Module / File Layout

- `App.ps1`
  Startup entrypoint. Loads WPF, resolves paths from `App.Settings.psd1`, imports app modules, runs startup validation, then loads `XAML/MainWindow.xaml`.
- `App.Settings.psd1`
  Holds the external Core/Auth/catalog paths, output root, UI defaults, and dataset key mapping.
- `App.CoreAdapter.psm1`
  The only module that imports `Genesys.Core` and `Genesys.Auth`, calls `Assert-Catalog`, and calls `Invoke-Dataset`.
- `App.RunData.psm1`
  Reads immutable Core run artifacts, builds a thin `audit.index.jsonl` sidecar, pages filtered views, and loads individual audit records on demand by byte offset.
- `App.Export.psm1`
  Writes filtered or full-run CSV/HTML exports from normalized run data.
- `App.UI.ps1`
  Wires the WPF shell, background run orchestration, paging, drilldown, recent runs, and diagnostics.
- `XAML/MainWindow.xaml`
  Visual shell for the operator workflow.

## Core Import + Validation

Startup calls:

1. `Initialize-CoreIntegration`
2. `Import-Module <AuthModulePath>`
3. `Import-Module <CoreModulePath>`
4. `Assert-Catalog -CatalogPath <CatalogPath> -SchemaPath <SchemaPath>`

If validation fails, the shell still loads so the error is visible in the header banner, but Preview / Full Extract remain disabled.

## Dataset Keys Used

- Preview button: `DatasetKeys.Preview`
- Full Extract button: `DatasetKeys.Full`
- Current default settings map both to `audit-logs`

The dataset mapping lives in `App.Settings.psd1`, so the UI does not need redesign if a different audit dataset key is introduced later.

## Startup Validation Flow

1. Resolve the configured `Genesys.Core` module path, `Genesys.Auth` module path, catalog path, and schema path.
2. Import `Genesys.Auth`.
3. Import `Genesys.Core`.
4. Validate the catalog with `Assert-Catalog`.
5. Create the configured output root if missing.
6. Surface success or failure in the banner and enable/disable run actions accordingly.

## Run Output Contract Read by the UI

Core artifacts treated as source of truth:

- `manifest.json`
- `summary.json`
- `events.jsonl`
- `data/audit.jsonl`

App-created sidecars for UX only:

- `audit.index.jsonl`
  Thin, normalized index with file path + byte offset for responsive paging.
- `app.request.json`
  Captures run mode and selected filters so recent runs can be reloaded with context.

The UI never reads raw HTTP responses. It reads the Core run folder and its own derived sidecars only.

## Preview vs Full Run

- Preview
  Calls `Invoke-Dataset` with the preview dataset key. The adapter clamps overly large selected windows to the most recent configured preview window (`MaxWindowHours`) and the results grid applies the operator-specified preview result cap.
- Full
  Calls `Invoke-Dataset` with the full dataset key. The full selected interval is passed through unchanged and the complete run artifacts are retained for export/reload.

Both modes still extract through `Invoke-Dataset`; the difference is parameter shaping and view limits, not alternate extraction code.

## Export Flow

- Filtered CSV / HTML
  Exports the current filtered result set from indexed run data.
- Full CSV / HTML
  Streams the complete `data/*.jsonl` payload from the selected run folder.

Exports flatten audit records into stable analysis-friendly columns and include run metadata plus selected filters for HTML reports.
