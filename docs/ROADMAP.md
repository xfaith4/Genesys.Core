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
  - Stronger profile-driven redaction and normalization policy depth.
  - End-user workflow auth ergonomics for production-ready automation.

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

## Phase 2 — Core Datasets (In progress)

- Implemented curated datasets:
  - `audit-logs`
  - `analytics-conversation-details`
  - `users`
  - `routing-queues`
- Generic catalog-backed execution is available for additional dataset keys defined in the catalog.

### Remaining

- Expand curated handlers where domain-specific normalization or orchestration is required.
- Improve dataset-level parameterization controls (for example, time windows currently embedded in curated handlers).
- Continue redaction hardening beyond current heuristic policy.

## Phase 3 — Catalog and Delivery Hardening (In progress)

- Fully retire duplicate catalog mirror usage in day-to-day operation.
- Improve onboarding ergonomics for non-developer and CI users.
- Harden production workflow auth patterns and examples.

## Phase 4 — Endpoint Expansion Backlog (Planned)

Upcoming endpoint additions requested for roadmap tracking:

1. `GET /api/v2/authorization/roles`
2. `GET /api/v2/conversations/{conversationId}/recordings`
3. `GET /api/v2/oauth/clients`
4. `POST /api/v2/oauth/clients/{clientId}/usage/query`
5. `GET /api/v2/oauth/clients/{clientId}/usage/query/results/{executionId}`
6. `GET /api/v2/speechandtextanalytics/topics`
7. `POST /api/v2/analytics/transcripts/aggregates/query`
8. `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/communications/{communicationId}/transcripturl`

Implementation intent:

- Add endpoint definitions to canonical catalog with schema-valid paging/retry metadata.
- Add dataset keys or curated handlers where orchestration requires multi-step logic.
- Add Pester coverage for endpoint profile mapping and termination safety.

## External client readiness

The repository is ready for controlled external invocation of module command `Invoke-Dataset` when callers provide valid auth headers and consume output artifacts from `out/<datasetKey>/<runId>/`.

Before broad production automation, complete:

- workflow auth wiring and examples
- mirror-catalog consolidation
- redaction/profile hardening
