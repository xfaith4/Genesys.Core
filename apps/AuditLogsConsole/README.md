# Genesys Audit Logs Console

PowerShell WPF operator console for Genesys Cloud Audit Logs.

## Run

Use Windows PowerShell 5.1:

```powershell
Set-Location <repo>\apps\AuditLogsConsole
.\App.ps1
```

## Configuration

Defaults live in `App.Settings.psd1`:

- `CoreModuleRelativePath`
- `AuthModuleRelativePath`
- `CatalogRelativePath`
- `SchemaRelativePath`
- `OutputRelativePath`
- preview tuning and dataset-key mapping

## Notes

- Extraction is delegated to `Genesys.Core` via `Invoke-Dataset`.
- The UI reads `manifest.json`, `summary.json`, `events.jsonl`, and `data/audit.jsonl`.
- Recent runs can be reopened without re-querying Genesys Cloud.
