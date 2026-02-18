# Genesys.Core

Catalog-driven PowerShell core for running governed Genesys Cloud datasets with deterministic retries, paging, async transaction polling, and auditable run artifacts.

## What this repository does

- Uses `catalog/genesys-core.catalog.json` as the dataset + endpoint source of truth.
- Executes datasets through a PowerShell module (`src/ps-module/Genesys.Core`).
- Produces deterministic run output under `out/<datasetKey>/<runId>/`:
  - `manifest.json`
  - `events.jsonl`
  - `summary.json`
  - `data/*.jsonl`
- Supports scheduled and on-demand GitHub Actions workflows for `audit-logs`.

## Current supported datasets

- `audit-logs`
  - Service mapping discovery (`GET /api/v2/audits/query/servicemapping`)
  - Async submit/poll/results flow:
    - submit (`POST /api/v2/audits/query`)
    - status polling (`GET /api/v2/audits/query/{transactionId}`)
    - results pagination (`GET /api/v2/audits/query/{transactionId}/results`)
- `audit-service-mapping`
  - Service mapping lookup (`GET /api/v2/audits/query/servicemapping`)
- `analytics-conversation-details`
  - Body-paged details query (`POST /api/v2/analytics/conversations/details/query`)

## Runtime guarantees

- Deterministic 429 handling with bounded retries and jitter (`Invoke-WithRetry`).
- Paging strategy plugins (`none`, `nextUri`, `pageNumber`, `cursor`, `bodyPaging`) selected by catalog profile.
- Generalized `transactionResults` flow (submit -> poll -> fetch paged results) driven by catalog metadata.
- Structured event telemetry (`events.jsonl`) for retries, paging, and transaction state.
- Request logging redacts sensitive headers and token-like query parameters.

## Prerequisites

- PowerShell 5.1+ (module manifest is pinned to `PowerShellVersion = '5.1'`).
- For tests: Pester 5.x.

## Quick start (local)

```powershell
Import-Module ./src/ps-module/Genesys.Core/Genesys.Core.psd1 -Force

# Dry run
Invoke-Dataset -Dataset 'audit-logs' -CatalogPath './catalog/genesys-core.catalog.json' -OutputRoot './out' -WhatIf

# Real run (requires valid Genesys Cloud authorization headers)
$headers = @{
  Authorization = 'Bearer <token>'
}
Invoke-Dataset -Dataset 'audit-logs' -CatalogPath './catalog/genesys-core.catalog.json' -OutputRoot './out' -BaseUri 'https://api.mypurecloud.com' -Headers $headers
```

## External client integration

External clients should call the module entrypoint and provide:

- `-Dataset` (`audit-logs`, `audit-service-mapping`, `analytics-conversation-details`)
- `-CatalogPath`
- `-OutputRoot`
- `-BaseUri` (optional, defaults to `https://api.mypurecloud.com`)
- `-Headers` (typically bearer auth)

For testing or orchestration bridges, clients may inject `-RequestInvoker` to mock or route HTTP calls while still using the core retry/paging contract.

## GitHub Actions usage

- CI: `.github/workflows/ci.yml` runs Pester.
- On-demand: `.github/workflows/audit-logs.on-demand.yml`
- Scheduled: `.github/workflows/audit-logs.scheduled.yml`

Both dataset workflows upload only the run folder:
`out/audit-logs/<runId>/`
with short retention controls.

## Testing

```powershell
$config = . ./tests/PesterConfiguration.ps1
Invoke-Pester -Configuration $config
```

## Readiness status for external request clients

Ready for controlled external consumption for `audit-logs` with the following conditions:

- Catalog + schema validation in tests.
- Retry parsing and paging termination test coverage.
- Deterministic output contract tests.
- Secrets redaction tests for request event logging.

Known gaps before broader production rollout:

- Additional dataset implementations beyond current baseline set.
- Full catalog/profile unification between root `genesys-core.catalog.json` and `catalog/genesys-core.catalog.json`.
- Optional stronger payload redaction policies for dataset record fields.
