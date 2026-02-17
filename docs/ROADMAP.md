# Genesys Core — Roadmap

## Vision

Build a catalog-driven Genesys Cloud Core that executes governed datasets via GitHub Actions and produces deterministic, auditable artifacts. UIs consume Core artifacts and must not reimplement Core pagination/retry/runtime logic.

## Status snapshot (updated)

- **Implemented now**
  - Catalog + schema scaffold with validation tests.
  - Module runtime scaffold with dataset dispatcher (`Invoke-Dataset`).
  - Retry engine with 429 handling (`Retry-After` and message parsing).
  - Paging strategy plugins for `none`, `nextUri`, and `pageNumber`.
  - Async audit transaction submit/poll/results flow.
  - Deterministic run output contract (`manifest.json`, `events.jsonl`, `summary.json`, `data/*.jsonl`).
  - CI + scheduled/on-demand audit workflow artifacts scoped to run folder.
- **In progress**
  - Broader dataset coverage from catalog profiles.
  - Stronger redaction/normalization profiles for payload fields.
  - Consolidation of duplicate catalog representations.

## Phase 0 — Bootstrap (Complete)

### Delivered

- Catalog placeholder at `catalog/genesys-core.catalog.json`
- Draft schema at `catalog/schema/genesys-core.catalog.schema.json`
- PowerShell module scaffold under `src/ps-module/Genesys.Core/`
- Pester scaffolding under `tests/`
- CI workflow to run Pester on pull requests
- Scheduled/on-demand audit logs workflows that write deterministic output files under `out/<datasetKey>/<runId>/...`

## Phase 1 — Core Runtime Foundations (Mostly complete)

- Request/retry runtime with deterministic 429 behavior and bounded jitter.
- Pluggable paging strategies (`nextUri`, `pageNumber`, `none`).
- Structured run events for retries, paging progress, and async state transitions.
- Request event redaction for sensitive headers and token-like query parameters.

### Remaining

- Add additional paging strategies declared in the long-form catalog (`cursor`, `bodyPaging`, `transactionResults` generalized profile mapping).
- Broaden retry profile wiring from catalog profile names to runtime parameters.

## Phase 2 — Audit Logs Dataset (Complete for baseline)

- Submit/poll/results flow implementation.
- Run artifacts (`manifest.json`, `events.jsonl`, `summary.json`, `data/audit.jsonl`).
- Test coverage for submit/poll/results and output contract.

### Remaining hardening

- Expand data-level redaction for record fields beyond transport/request telemetry.
- Add failure-path tests for failed/cancelled transaction terminal states.

## Phase 3 — Additional Datasets (Pending)

- Add operational event datasets using catalog-driven endpoint definitions.
- Expand test coverage for profile-to-runtime mapping and endpoint compatibility.

## External client readiness

The repository is ready for controlled external-client invocation of `Invoke-Dataset` for `audit-logs`, assuming clients pass valid auth headers and consume output artifacts from `out/<datasetKey>/<runId>/`.
