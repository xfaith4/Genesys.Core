# Genesys Core — Roadmap

## Vision
Build a catalog-driven Genesys Cloud Core that executes governed datasets via GitHub Actions and produces deterministic, auditable artifacts. UIs consume Core artifacts and must not reimplement Core pagination/retry/runtime logic.

## Phase 0 — Bootstrap (Current)
### Delivered in this scaffold
- Catalog placeholder at `catalog/genesys-core.catalog.json`
- Draft schema at `catalog/schema/genesys-core.catalog.schema.json`
- PowerShell module scaffold under `src/ps-module/Genesys.Core/`
- Pester scaffolding under `tests/`
- CI workflow to run Pester on pull requests
- Scheduled audit logs workflow stub that writes deterministic output files under `out/<datasetKey>/<runId>/...`

### Acceptance targets
- `pwsh -File ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 -Dataset audit-logs -WhatIf` prints what would happen and exits with code 0.
- Catalog and schema are present and parseable.
- CI executes Pester on pull requests.

## Phase 1 — Core Runtime Foundations
- Implement request/retry runtime with deterministic 429 handling and bounded jitter.
- Add pluggable paging strategies (`nextUri`, `pageNumber`, `cursor`, `bodyPaging`, `transactionResults`).
- Emit run events for retries, paging progress, and async state transitions.

## Phase 2 — Audit Logs Dataset
- Implement submit/poll/results flow for audit logs.
- Normalize/redact output records.
- Produce `manifest.json`, `events.jsonl`, and `summary.json` under run folder.

## Phase 3 — Additional Datasets
- Add operational event dataset support using catalog-driven endpoint definitions.
- Expand test coverage for schema constraints, retry parsing, and paging termination.
