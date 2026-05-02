# Production-Readiness Gate

> Version: 1.0 — 2026-04-29
>
> Purpose: Single verifiable checklist of exit criteria for **broad automation**
> use of Genesys.Core + Genesys.Ops. Every criterion must reach ✅ GREEN before
> Release 1.0 is declared production-ready.
>
> Scope reviewed: auth, dataset execution, paging, retry, redaction, artifact
> contract, workflow / CI, live validation, and Track B gate (Agent
> Investigation).

---

## How to use this checklist

Each criterion has:

- **Status** — ✅ GREEN (met) / ⚠️ PARTIAL (conditionally met) / ❌ NOT MET /
  🔒 BLOCKED (blocked by another criterion)
- **Evidence Level Required** — exact validation evidence label from
  `docs/TEST_EVIDENCE_LEVELS.md`, where applicable.
- **Verifiable by** — the action a reviewer can take to confirm the criterion.

When a criterion is met or promoted, update its status here and commit the
change together with the evidence (test output, artifact, or PR link).

---

## 1. Authentication and Credential Management

| # | Criterion | Status | Verifiable by |
|---|-----------|--------|---------------|
| A-01 | Client-credentials flow exchanges `client_id` / `client_secret` for a bearer token and stores it in module state. | ✅ GREEN | `Connect-GenesysCloudApp` test in `Genesys.Auth.psm1`; unit asserts token returned. |
| A-02 | Bearer-token flow (`Connect-GenesysCloud`) stores the caller-supplied token and returns a stable `AuthContext`. | ✅ GREEN | Verified in `Genesys.Auth.psm1` implementation; used by ConversationAnalyser app. |
| A-03 | PKCE flow (`Connect-GenesysCloudPkce`) completes the full loopback redirect cycle and returns an `AuthContext`. | ✅ GREEN | Implemented in `Genesys.Auth.psm1`. |
| A-04 | GitHub Actions workflow uses repository secrets (`GENESYS_CLIENT_ID`, `GENESYS_CLIENT_SECRET`, `GENESYS_REGION`) for live runs, distinct from the CI mock run. | ✅ GREEN | `.github/workflows/dataset.on-demand.yml`; validates secrets present before authentication step. |
| A-05 | No credential value is written to `events.jsonl`, `manifest.json`, or `summary.json`. | ✅ GREEN | `Security.Redaction.Tests.ps1` — request-logging redaction test confirms Authorization header is `[REDACTED]`. |

---

## 2. Dataset Execution

| # | Criterion | Status | Verifiable by |
|---|-----------|--------|---------------|
| B-01 | `Invoke-Dataset` executes any catalog dataset and writes the standard artifact set (`manifest.json`, `events.jsonl`, `summary.json`, `data/*.jsonl`). | ✅ GREEN | `RunContract.Tests.ps1`; `DatasetRuntime.Tests.ps1`. |
| B-02 | Curated dataset handlers exist for `audit-logs`, `analytics-conversation-details`, `users`, `routing-queues`. | ✅ GREEN | `Get-DatasetRegistry` in `Datasets.ps1`; all four tested. |
| B-03 | Non-curated datasets are executed via `Invoke-SimpleCollectionDataset` without requiring a bespoke handler. | ✅ GREEN | `AdditionalDatasets.Tests.ps1`; `Phase4Endpoints.Tests.ps1`. |
| B-04 | Catalog is resolved from `catalog/genesys.catalog.json` only; the deprecated stub and legacy fallback are removed. | ✅ GREEN | Mirror-catalog cutover landed 2026-04-29; `CatalogResolution.Tests.ps1` confirms canonical-only behaviour. |

---

## 3. Paging

| # | Criterion | Status | Verifiable by |
|---|-----------|--------|---------------|
| C-01 | `nextUri`, `pageNumber`, `cursor`, `bodyPaging`, `none`, and `transactionResults` paging profiles are all exercised. | ✅ GREEN | `Paging.Tests.ps1`. |
| C-02 | Paging terminates safely when the API returns an empty page or omits the nextUri field. | ✅ GREEN | `Paging.Tests.ps1` — empty-page and missing-nextUri cases. |
| C-03 | Paging guard (max-page circuit breaker) is present to prevent infinite loops on malformed API responses. | ✅ GREEN | `Invoke-PagingNextUri` reads `paging.maxPages` (default 1000) and emits `paging.terminated.maxPages` when the ceiling is hit, alongside the existing duplicate-URI guard. Verified by `Paging.Tests.ps1` "terminates nextUri paging at the configured max-page ceiling". `Invoke-PagingPageNumber` and `Invoke-PagingCursor` already enforced the same ceiling. |

---

## 4. Retry

| # | Criterion | Status | Verifiable by |
|---|-----------|--------|---------------|
| D-01 | HTTP 429 responses are retried using the `Retry-After` header (or message-parsed interval) with bounded jitter. | ✅ GREEN | `Retry.Tests.ps1` — 429 retry test. |
| D-02 | HTTP 500/502/503/504 responses are retried up to `maxRetries` with exponential back-off. | ✅ GREEN | `Retry.Tests.ps1`. |
| D-03 | Non-retryable errors (4xx except 429) surface immediately without retry. | ✅ GREEN | `Retry.Tests.ps1`. |

---

## 5. Redaction

| # | Criterion | Status | Verifiable by |
|---|-----------|--------|---------------|
| E-01 | Heuristic field-name redaction removes token, secret, password, authorization, apiKey, email, phone, userId, employeeId, JWT fields from record payloads. | ✅ GREEN | `Security.Redaction.Tests.ps1` — heuristic and payload tests. |
| E-02 | Profile-driven redaction (`removeFields` list per dataset) removes additional fields not covered by the heuristic. | ✅ GREEN | `Security.Redaction.Tests.ps1` — profile-driven tests. `Resolve-DatasetRedactionProfile` resolves a named profile from the catalog. |
| E-03 | Each of the seven Agent Investigation datasets declares a `redactionProfile` in the catalog. | ✅ GREEN | `catalog/genesys.catalog.json` — `users`, `users.division.analysis.get.users.with.division.info`, `routing.get.all.routing.skills`, `routing-queues`, `users.get.bulk.user.presences`, `analytics.query.user.details.activity.report`, `analytics-conversation-details-query` all carry `redactionProfile`. |
| E-04 | Authorization headers are never logged in `events.jsonl`. | ✅ GREEN | Request-event redaction test in `Security.Redaction.Tests.ps1`. |
| E-05 | Redaction profiles are applied across all three dataset execution paths (audit-logs, analytics-conversation-details, generic). | ✅ GREEN | All three `Protect-RecordData` call sites in `Datasets.ps1` now resolve and pass the catalog profile. |
| E-06 | Full profile-by-dataset redaction sweep (free-text / transcripts / evaluation comments) for Conversation Investigation. | 🔒 BLOCKED | Deferred to Release 1.1 with the Conversation flagship, where free-text fields make it load-bearing. |

---

## 6. Artifact Contract

| # | Criterion | Status | Verifiable by |
|---|-----------|--------|---------------|
| F-01 | Every run produces `manifest.json`, `events.jsonl`, `summary.json`, and at least one `data/*.jsonl`. | ✅ GREEN | `RunContract.Tests.ps1`. |
| F-02 | `manifest.json` contains `datasetKey`, `runId`, `startedAtUtc`, `endedAtUtc`, and `counts`. | ✅ GREEN | `RunContract.Tests.ps1`. |
| F-03 | Two consecutive runs over the same fixture produce byte-equivalent `summary.json` (timestamps and runId excluded). | ✅ GREEN | `RunContract.Tests.ps1` "produces byte-equivalent run artifacts across two consecutive fixture runs" runs `Invoke-Dataset` twice over the same mock invoker and asserts (a) normalised `summary.json` is identical after stripping `runId` and ISO-8601 timestamp fields, and (b) every `data/*.jsonl` file matches by SHA-256. The test runs in CI on every PR via `ci.yml`. |
| F-04 | The `data/*.jsonl` filename is derived from the dataset key and is stable across runs. | ✅ GREEN | `ConvertTo-DatasetDataFileName` in `Datasets.ps1`. |

---

## 7. Workflow and CI

| # | Criterion | Status | Verifiable by |
|---|-----------|--------|---------------|
| G-01 | CI (`ci.yml`) runs the full Pester suite on every pull request with no secrets required. | ✅ GREEN | `.github/workflows/ci.yml`; runs `Invoke-Pester` against `tests/`. |
| G-02 | A live-auth on-demand workflow (`dataset.on-demand.yml`) exists with documented secrets contract and is distinct from the CI mock run. | ✅ GREEN | `.github/workflows/dataset.on-demand.yml`. |
| G-03 | The scheduled audit-logs workflow (`audit-logs.scheduled.yml`) is documented as a mock/virtualized run until production secrets are wired. | ✅ GREEN | Workflow header clearly labels mock steps with `MOCK:` prefix. |

---

## 8. Live Validation

| # | Criterion | Status | Evidence Level Required | Verifiable by |
|---|-----------|--------|-------------------------|---------------|
| H-01 | `users` dataset: `itemsPath`, paging profile, retry behaviour confirmed against live Genesys Cloud. | ❌ NOT MET | `Live Invoke-Dataset acceptance passed` | Run `dataset.on-demand.yml` with `datasetKey=users` against a live org; inspect sanitized artifacts. |
| H-02 | `users.division.analysis.get.users.with.division.info` dataset: same verification. | ❌ NOT MET | `Live Invoke-Dataset acceptance passed` | As above. |
| H-03 | `routing.get.all.routing.skills` dataset: same verification. | ❌ NOT MET | `Live Invoke-Dataset acceptance passed` | As above. |
| H-04 | `routing-queues` dataset: same verification. | ❌ NOT MET | `Live Invoke-Dataset acceptance passed` | As above. |
| H-05 | `users.get.bulk.user.presences` dataset: same verification. | ❌ NOT MET | `Live Invoke-Dataset acceptance passed` | As above. |
| H-06 | `analytics.query.user.details.activity.report` dataset: same verification. | ❌ NOT MET | `Live Invoke-Dataset acceptance passed` | As above. |
| H-07 | `analytics-conversation-details-query` dataset: same verification. | ❌ NOT MET | `Live Invoke-Dataset acceptance passed` | As above. |
| H-08 | Each validated dataset has `validationStatus` updated from `"unvalidated"` to `"live-validated"` in `catalog/genesys.catalog.json`. | ❌ NOT MET | `Live Invoke-Dataset acceptance passed` for H-01 through H-07 | Inspect `catalog/genesys.catalog.json` for the seven Agent Investigation entries. |

---

## 9. Track B Gate — Agent Investigation

| # | Criterion | Status | Verifiable by |
|---|-----------|--------|---------------|
| I-01 | All seven Agent Investigation datasets are live-validated (H-01 through H-07 are ✅ GREEN). | 🔒 BLOCKED | Live validation must complete first. |
| I-02 | `Invoke-Investigation` private composer helper exists in `Genesys.Ops` with table-driven fixture coverage. | ✅ GREEN | `modules/Genesys.Ops/Genesys.Ops.psm1`; `tests/integration/AgentInvestigation.Tests.ps1` covers required/optional step semantics, manifest join plan, and deterministic output. |
| I-03 | `Get-GenesysAgentInvestigation` public cmdlet exists and produces the standard artifact set under `out/agent-investigation/<runId>/`. | ✅ GREEN | `tests/integration/AgentInvestigation.Tests.ps1` happy-path fixture asserts `manifest.json`, `events.jsonl`, `summary.json`, and `data/*.jsonl`. |
| I-04 | `manifest.json` for Agent Investigation conforms to the Investigation Manifest schema at `catalog/schema/investigation.manifest.schema.json`. | ✅ GREEN | `tests/integration/AgentInvestigation.Tests.ps1` validates emitted manifest JSON against `catalog/schema/investigation.manifest.schema.json`. |
| I-05 | Fixture-driven integration test for Agent Investigation asserts manifest shape, join shape, and determinism. | ✅ GREEN | `tests/integration/AgentInvestigation.Tests.ps1`; `scripts/Invoke-Tests.ps1 -IncludeIntegration` passed 105 unit / 12 integration tests on 2026-04-30. |
| I-06 | `README.md` and `ONBOARDING.md` describe investigations as first-class alongside datasets. | ✅ GREEN | `README.md`, `docs/ONBOARDING.md`, `docs/training/Training.md`, and `docs/INVESTIGATIONS.md` are cross-linked. |

---

## Overall Release 1.0 Gate

Release 1.0 is **not ready** until every criterion above is ✅ GREEN. The
current blocking items are:

1. **H-01 → H-08**: Live validation of all seven Agent Investigation datasets.
   Once completed, update `validationStatus` in the catalog and promote the
   criteria.

`C-03` (explicit paging guard) and `F-03` (CI determinism assertion) were
resolved in the 2026-05-01 corrective refactor and are now ✅ GREEN.

---

## Change log

| Date | Change |
|------|--------|
| 2026-05-01 | Promoted `C-03` (paging max-page ceiling on `Invoke-PagingNextUri`) and `F-03` (CI determinism assertion in `RunContract.Tests.ps1`) to ✅ GREEN. Live-validation gates `H-01` through `H-08` remain blocking. |
| 2026-04-30 | Promoted Agent Investigation Track B implementation gates I-02 through I-06 after fixture integration validation. Live validation H-01 through H-08 remains blocking. |
| 2026-04-29 | Rewrote as formal verifiable checklist for Release 1.0 (Track A deliverable). Previous narrative review archived below. |
| 2026-02-22 | Initial readiness review written. |

---

## Archived narrative review (2026-02-22)

> The content below is the original informal review for historical reference.
> The formal checklist above supersedes it.

### Scope reviewed

- Dataset entrypoint and routing behavior
- Retry and rate-limit behavior
- Paging strategy behavior and termination safeguards
- Async transaction/job behavior
- Output artifact contract
- Redaction behavior
- End-user onboarding and workflow usability

### Ready now (as of 2026-02-22)

- `Invoke-Dataset` is functional for catalog-backed dataset execution and
  writes deterministic run artifacts (`manifest.json`, `events.jsonl`,
  `summary.json`, `data/*.jsonl`).
- Runtime supports paging profiles `none`, `nextUri`, `pageNumber`, `cursor`,
  `bodyPaging`, and `transactionResults` via profile-driven dispatch.
- Retry behavior handles HTTP 429 using `Retry-After` header and message
  parsing (`Retry the request in [x] seconds`) with bounded retries and jitter.
- Async submit/poll/results flows are implemented and exercised for audit and
  analytics job patterns.
- Request and record redaction exists for common sensitive fields/token-like
  values.

### Partially ready / operational caveats (as of 2026-02-22)

- This repository is a Core runtime, not a packaged MCP server today.
- Included GitHub workflows were scoped to `audit-logs` and required
  environment-specific auth wiring before production use.
- Legacy catalog shims still existed for one deprecation cycle (now retired
  as of 2026-04-29).
- Redaction policy was heuristic and not yet fully profile-driven by
  dataset/endpoint sensitivity class (now addressed by criterion E-02/E-03).

