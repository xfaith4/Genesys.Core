# Genesys Core — Roadmap

## Vision
Genesys Core is a governed, catalog-driven data engine that executes Genesys Cloud API workflows via GitHub Actions.
It produces versioned, auditable datasets (artifacts) that UIs and downstream tools can consume without reimplementing:
- pagination
- async transactions/jobs
- rate limiting / retries
- normalization + redaction
- dataset manifests + summaries

Frontends are clients of the Core, not co-authors of the Core.

---

## Guiding Principles
- **Catalog is the source of truth.** No endpoint-specific logic in UI repos.
- **No surprises:** pagination and retry behavior must be deterministic and tested.
- **Security-first outputs:** redaction before persistence; raw payloads are opt-in and gated.
- **Observable runs:** every run emits structured run-events + a manifest + summary.
- **Composable datasets:** scheduled + on-demand runs share the same runner and contracts.

---

## Phase 0 — Repo Bootstrap (Day 1)
### Deliverables
- Repo structure with module + workflows + catalog
- Pester scaffolding
- Basic CI

### Acceptance
- `pwsh -File ./scripts/Invoke-Dataset.ps1 -Dataset audit-logs -WhatIf` works
- `catalog/genesys-core.catalog.json` validates against schema
- CI runs tests on PR

---

## Phase 1 — Core Runtime Foundations (Week 1)
### 1.1 Catalog + Schema
- Define catalog schema:
  - endpoints (method/path/region)
  - auth profile
  - pagination profile
  - async/transaction profile
  - itemsPath (entities/results/records)
  - redaction policy
  - retry policy
- Add schema validation tests (Pester)

**Acceptance**
- Every endpoint entry must include `itemsPath` + a known paging strategy or explicit `none`

### 1.2 HTTP + Retry Engine
- `Invoke-GcRequest` with:
  - 429 backoff support (Retry-After + “Retry the request in [x] seconds”)
  - bounded retries + jitter
  - structured event emission for each attempt

**Acceptance**
- Unit tests cover:
  - 429 parsing
  - retry cap behavior
  - idempotency rules for GET vs POST

### 1.3 Pagination Strategy Plugins
- Implement paging strategies:
  - `nextUri`
  - `pageNumber`
  - `cursor` (future-ready)
  - `bodyPaging/totalHits` (analytics-style)
- All strategies share a common interface + emit progress events

**Acceptance**
- Strategy unit tests with canned responses

### 1.4 Run Contract + Outputs
- Standard output layout:
  - `out/<datasetKey>/<runId>/manifest.json`
  - `out/.../events.jsonl`
  - `out/.../summary.json`
  - `out/.../data/*.jsonl(.gz)`
- Artifact upload uses `actions/upload-artifact@v4` with retention and safe file selection

**Acceptance**
- A workflow run produces artifacts with expected names and retention settings

---

## Phase 2 — Dataset #1: Audit Logs (Week 2)
### APIs
- GET  `/api/v2/audits/query/servicemapping`
- POST `/api/v2/audits/query`
- GET  `/api/v2/audits/query/{transactionId}`
- GET  `/api/v2/audits/query/{transactionId}/results`

### Work
- Implement async transaction runner:
  - submit query -> transactionId
  - poll status until terminal
  - fetch results with configured pagination
- Normalize + redact fields
- Produce `summary.json`:
  - counts by action/service/user/app/day
  - top N categories
  - anomalies (rate limit hits, partial windows)

### Workflows
- `audit-logs.scheduled.yml` (nightly window = previous day)
- `audit-logs.on-demand.yml` (`workflow_dispatch` params: start/end, filters, summary-only)

**Acceptance**
- Nightly scheduled run completes successfully
- On-demand run with a small window completes under defined SLA
- Re-run is deterministic (same inputs -> same outputs except timestamps/runId)

---

## Phase 3 — Dataset #2: Operational Event Logs (Week 3)
### APIs
- POST `/api/v2/usage/events/query`
- GET  `/api/v2/usage/events/definitions`
- POST `/api/v2/usage/events/aggregates/query`

### Work
- Add catalog entries + dataset runner
- Definitions cached (daily/weekly) with diff reporting
- Aggregates normalized into summary metrics

**Acceptance**
- Operational events dataset runs scheduled and on-demand

---

## Phase 4 — Consumer UX Hooks (Week 4+)
- Add a lightweight "dataset index" artifact:
  - list latest successful runs per datasetKey
- Add optional publishing targets:
  - GitHub Release assets
  - (future) storage bucket

**Acceptance**
- UIs can discover latest datasets without scraping Actions run lists

---

## Milestones
- M0: Bootstrap repo + schema validation
- M1: Retry + paging plugins + run contract
- M2: Audit Logs end-to-end (scheduled + on-demand)
- M3: Operational Events end-to-end
- M4: Dataset index + consumer-friendly access patterns
