# Validation Checklist

## Core-First Compliance

- No direct REST extraction in the app
  Verified by static compliance test: no `Invoke-RestMethod`, no `Invoke-WebRequest`, no `/api/v2/` literals under `apps/AuditLogsConsole`.
- Exact `Genesys.Core` call sites
  `Initialize-CoreIntegration` imports `Genesys.Core` and calls `Assert-Catalog`.
  `Start-AuditPreviewRun` calls `Invoke-Dataset`.
  `Start-AuditFullRun` calls `Invoke-Dataset`.

## Startup Catalog Validation

- `App.ps1` resolves the configured Core/catalog/schema paths.
- `Initialize-CoreIntegration` runs `Assert-Catalog`.
- On failure, the header banner shows the error and run actions stay disabled.

## Preview / Full Run Behavior

- Preview
  Uses `Start-AuditPreviewRun`.
  Adapter clamps overly wide windows to the preview max window.
  Grid respects the preview result cap.
- Full
  Uses `Start-AuditFullRun`.
  Keeps the full selected interval.
  Writes the full run folder to disk for reload/export.

## Export Behavior

- CSV
  Filtered export reads only the filtered indexed set.
  Full export streams all `data/*.jsonl` files.
- HTML
  Includes report title, generated timestamp, selected filters, summary counts, and a tabular result section.

## Manual Test Steps

1. Launch `apps/AuditLogsConsole/App.ps1` in Windows PowerShell 5.1.
2. Confirm the banner reports successful `Genesys.Core` import and catalog validation.
3. Connect with a valid bearer token and region.
4. Run Preview over `Last 1 hour` with a service filter.
5. Confirm the UI stays responsive and the Run Console tails `events.jsonl`.
6. Confirm grid results appear and row selection loads drilldown + raw JSON.
7. Run Full Extract over a larger interval.
8. Confirm a new run folder is written under `apps/AuditLogsConsole/out/audit-logs/<runId>/`.
9. Reload that run from Recent Runs.
10. Export filtered CSV and full HTML and confirm both files open cleanly.
