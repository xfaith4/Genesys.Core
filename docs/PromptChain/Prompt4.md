Implement run output conventions.

Files:
- src/ps-module/Genesys.Core/Private/Run/New-RunContext.ps1
- src/ps-module/Genesys.Core/Private/Run/Write-RunEvent.ps1
- src/ps-module/Genesys.Core/Private/Run/Write-Manifest.ps1
- src/ps-module/Genesys.Core/Private/Run/Write-Jsonl.ps1
- tests/RunContract.Tests.ps1

Requirements:
- Writes to out/<datasetKey>/<runId>/
- manifest.json includes datasetKey, start/end, git sha env vars if present
- events.jsonl is newline-delimited JSON events

Acceptance:
- Local run produces the folder structure and files (with stub data).
