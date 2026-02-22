# Genesys.Core

Catalog-driven PowerShell Core for governed Genesys Cloud dataset execution with deterministic retry/paging behavior and auditable run artifacts.

## Current state (2026-02-22)

- Canonical catalog source: `./genesys-core.catalog.json`.
- Compatibility mirror: `./catalog/genesys-core.catalog.json` (still supported, not canonical).
- Runtime entrypoint: PowerShell module `Invoke-Dataset` (`src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1`).
- Exported module functions: `Invoke-Dataset`, `Assert-Catalog`.
- Catalog snapshot in this repo currently contains:
  - `31` dataset keys
  - `74` endpoint definitions
  - `4` curated dataset handlers (`audit-logs`, `analytics-conversation-details`, `users`, `routing-queues`)
  - `27` additional dataset keys executed through generic catalog-driven dispatch
- Run output contract under `out/<datasetKey>/<runId>/`:
  - `manifest.json`
  - `events.jsonl`
  - `summary.json`
  - `data/*.jsonl`

## What this repo is and is not

- It is a governed Core runtime and dataset execution engine.
- It is not a packaged MCP server today. There is no stdio/http MCP server entrypoint in this repository.
- UIs (including `GenesysCore-GUI.ps1`) are clients of this Core runtime.

## Coverage today

Curated handlers with explicit normalization/flow logic:

- `audit-logs` (audit async transaction flow)
- `analytics-conversation-details` (analytics async job flow)
- `users` (normalized user projection)
- `routing-queues` (normalized queue projection)

All other dataset keys in the catalog run via generic catalog-driven collection execution (`Invoke-SimpleCollectionDataset`) when endpoint metadata is present.

To inspect dataset keys in your local catalog:

```powershell
$catalog = Get-Content -Raw ./genesys-core.catalog.json | ConvertFrom-Json
$catalog.datasets.PSObject.Properties.Name | Sort-Object
```

## End-user onboarding

Detailed onboarding is documented in [docs/ONBOARDING.md](docs/ONBOARDING.md). The short version is:

1. Acquire a Genesys Cloud OAuth token (client credentials).
2. Import module.
3. Run `Invoke-Dataset` with `-Headers @{ Authorization = "Bearer <token>" }`.
4. Inspect outputs in `out/<datasetKey>/<runId>/`.

### Quick start (authenticated module usage)

```powershell
Import-Module ./src/ps-module/Genesys.Core/Genesys.Core.psd1 -Force

$region = 'usw2.pure.cloud'
$baseUri = "https://api.$region"
$authUrl = "https://login.$region/oauth/token"

$clientId = '<client-id>'
$clientSecret = '<client-secret>'

$authResponse = Invoke-RestMethod -Uri $authUrl -Method POST -Body @{
    grant_type = 'client_credentials'
    client_id = $clientId
    client_secret = $clientSecret
} -ContentType 'application/x-www-form-urlencoded'

$headers = @{
    "Authorization" = "Bearer $($authResponse.access_token)"
    "Content-Type"  = "application/json"
}

Invoke-Dataset -Dataset 'users' -OutputRoot './out' -BaseUri $baseUri -Headers $headers
```

### Standalone script invocation (current limitation)

`src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1` can be called directly and bootstraps private functions, but its script-level parameters do not currently expose `-Headers` or `-BaseUri`.

- Good fit today: dry runs, local bootstrap, and script bootstrap tests.
- For authenticated live API runs: import module and call `Invoke-Dataset` function directly.

```powershell
pwsh -NoProfile -File ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 -Dataset audit-logs -WhatIf
```

## Catalog loading and strict mode

`Resolve-Catalog` enforces loader precedence:

- Root `./genesys-core.catalog.json` is canonical when present.
- Fallback is `./catalog/genesys-core.catalog.json` only when root is missing.
- If both files exist and differ:
  - warning emitted by default
  - `-StrictCatalog` fails run/validation

Migration helper:

```powershell
Copy-Item ./genesys-core.catalog.json ./catalog/genesys-core.catalog.json -Force
```

## Swagger sync

Use `scripts/Update-CatalogFromSwagger.ps1` to refresh endpoint coverage while preserving curated entries.

```powershell
pwsh -NoProfile -File ./scripts/Update-CatalogFromSwagger.ps1 -WriteLegacyCopy
pwsh -NoProfile -File ./scripts/Update-CatalogFromSwagger.ps1 -SwaggerPath ./my/swagger.json -WriteLegacyCopy
```

## Validation and smoke checks

```powershell
$config = . ./tests/PesterConfiguration.ps1
Invoke-Pester -Configuration $config

pwsh -NoProfile -File ./scripts/Invoke-Smoke.ps1
```

## GitHub workflows in this repo

Current workflows are scoped to `audit-logs`:

- `.github/workflows/audit-logs.on-demand.yml`
- `.github/workflows/audit-logs.scheduled.yml`

Artifacts are uploaded per run folder (`out/audit-logs/<runId>/`).

Note: workflow auth setup still requires environment-specific wiring before production use.

## GUI (Windows)

`GenesysCore-GUI.ps1` provides:

- OAuth client-credentials auth flow
- dataset selection from catalog
- run and what-if execution
- output folder selection and execution log view

WPF is Windows-only.
