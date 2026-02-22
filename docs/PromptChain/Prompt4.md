Maintain and harden run artifact contract and redaction guarantees.

Files:
- `src/ps-module/Genesys.Core/Private/Run/New-RunContext.ps1`
- `src/ps-module/Genesys.Core/Private/Run/Write-RunEvent.ps1`
- `src/ps-module/Genesys.Core/Private/Run/Write-Manifest.ps1`
- `src/ps-module/Genesys.Core/Private/Run/Write-Jsonl.ps1`
- `src/ps-module/Genesys.Core/Private/Redaction/Protect-RecordData.ps1`
- `tests/RunContract.Tests.ps1`
- `tests/Security.Redaction.Tests.ps1`

Requirements:
- Preserve artifact structure:
  - `out/<datasetKey>/<runId>/manifest.json`
  - `out/<datasetKey>/<runId>/events.jsonl`
  - `out/<datasetKey>/<runId>/summary.json`
  - `out/<datasetKey>/<runId>/data/*.jsonl`
- Ensure manifest remains deterministic and includes git/environment metadata when available.
- Ensure events are structured JSONL and safe for operational troubleshooting.
- Ensure redaction protects known sensitive fields and token-like values in outputs/events.

Acceptance:
- Run contract tests pass.
- Redaction tests pass with no secret/token leakage in persisted artifacts.
