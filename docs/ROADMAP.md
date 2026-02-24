# Genesys Core — Roadmap

## Vision

Build a catalog-driven Genesys Cloud Core that executes governed datasets via GitHub Actions and produces deterministic, auditable artifacts. UIs consume Core artifacts and must not reimplement Core pagination/retry/runtime logic.

## Status snapshot (2026-02-22)

- **Implemented now**
  - Catalog + schema validation and profile resolution.
  - Runtime dataset dispatcher (`Invoke-Dataset`) with deterministic output contract.
  - Retry engine with bounded jitter and 429 handling (`Retry-After` + message parsing).
  - Paging strategy plugins: `none`, `nextUri`, `pageNumber`, `cursor`, `bodyPaging`, `transactionResults`.
  - Generic async job engine (`Submit-AsyncJob`, `Get-AsyncJobStatus`, `Get-AsyncJobResults`, `Invoke-AsyncJob`).
  - Curated dataset handlers: `audit-logs`, `analytics-conversation-details`, `users`, `routing-queues`.
  - Generic catalog-driven dataset execution for additional dataset keys.
  - Test coverage for catalog validation, retry, paging, async flows, redaction, run contract, and standalone bootstrap.
  - CI + audit-specific scheduled/on-demand workflow scaffolding.
- **In progress**
  - Catalog mirror retirement (root canonical catalog vs legacy mirror).
  - End-user workflow auth ergonomics for production-ready automation.
- **Recently hardened**
  - Expanded payload redaction to scrub embedded bearer/basic tokens, JWT-like values, and tokenized query fragments in string fields.

## Phase 0 — Bootstrap (Complete)

### Delivered

- Catalog placeholder at `catalog/genesys-core.catalog.json`
- Draft schema at `catalog/schema/genesys-core.catalog.schema.json`
- PowerShell module scaffold under `src/ps-module/Genesys.Core/`
- Pester scaffolding under `tests/`
- CI workflow to run Pester on pull requests
- Scheduled/on-demand audit logs workflows that write deterministic output files under `out/<datasetKey>/<runId>/...`

## Phase 1 — Core Runtime Foundations (Complete)

- Request/retry runtime with deterministic 429 behavior and bounded jitter.
- Pluggable paging strategies (`none`, `nextUri`, `pageNumber`, `cursor`, `bodyPaging`, `transactionResults`).
- Structured run events for retries, paging progress, and async state transitions.
- Request event redaction for sensitive headers and token-like query parameters.

## Phase 2 — Core Datasets (Complete)

- Implemented curated datasets:
  - `audit-logs`
  - `analytics-conversation-details`
  - `users`
  - `routing-queues`
- Generic catalog-backed execution is available for additional dataset keys defined in the catalog.

### Completed hardening

- Added runtime dataset parameter overrides (`-DatasetParameters`) for curated interval controls and generic endpoint query overrides.
- Added tests validating parameterized audit interval/action/service filters and generic query override behavior.
- Expanded redaction hardening to cover embedded token patterns in payload strings.

### Future enhancements

- Expand curated handlers where domain-specific normalization or orchestration is required.
- Continue redaction policy evolution (profile-driven controls and allow/deny field tuning).

## Phase 3 — Catalog and Delivery Hardening (Complete)

- Day-to-day runtime and tests now target canonical root catalog usage while keeping legacy mirror as optional compatibility fallback.
- Improved onboarding ergonomics with script-level invocation support for `-BaseUri`, `-Headers`, and `-DatasetParameters`.
- Hardened auth/runtime usage guidance to favor deterministic, redacted outputs.

## Phase 4 — Endpoint Expansion Backlog (In Progress)

Tracked endpoint additions for roadmap delivery:

1. `GET /api/v2/authorization/roles`
2. `GET /api/v2/conversations/{conversationId}/recordings`
3. `GET /api/v2/oauth/clients`
4. `POST /api/v2/oauth/clients/{clientId}/usage/query`
5. `GET /api/v2/oauth/clients/{clientId}/usage/query/results/{executionId}`
6. `GET /api/v2/speechandtextanalytics/topics`
7. `POST /api/v2/analytics/transcripts/aggregates/query`
8. `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/communications/{communicationId}/transcripturl`

Delivered in this phase increment:

- Added catalog endpoint and dataset definitions for all tracked Phase 4 endpoints.
- Added Phase 4 Pester coverage to assert dataset/endpoint wiring and profile resolution.

Remaining implementation tasks:

- Validate each Phase 4 endpoint against live API behavior to confirm `itemsPath` and paging strategy choices.
- Add curated handler(s) for OAuth usage submit/results orchestration if async transaction chaining is required in production.
- Add mock-based paging termination tests for newly introduced `pageNumber_default` and `nextUri_default` endpoint selections.

## External client readiness

The repository is ready for controlled external invocation of module command `Invoke-Dataset` when callers provide valid auth headers and consume output artifacts from `out/<datasetKey>/<runId>/`.

Before broad production automation, complete:

- workflow auth wiring and examples
- mirror-catalog consolidation
- redaction/profile hardening
