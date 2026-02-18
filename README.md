# Genesys.Core

Catalog-driven PowerShell core for running governed Genesys Cloud datasets with deterministic retries, paging, async transaction polling, and auditable run artifacts.

## What this repository does

- Uses `genesys-core.catalog.json` (repo root) as the canonical runtime catalog source of truth.
- Keeps `catalog/genesys-core.catalog.json` as a compatibility mirror during migration.
- Executes datasets through a PowerShell module (`src/ps-module/Genesys.Core`).
- Produces deterministic run output under `out/<datasetKey>/<runId>/`:
  - `manifest.json`
  - `events.jsonl`
  - `summary.json`
  - `data/*.jsonl`

## Supported datasets

- `audit-logs`
  - Service mapping discovery (`GET /api/v2/audits/query/servicemapping`)
  - Async submit/poll/results flow
- `users`
  - Users list with presence/routing status normalization (`GET /api/v2/users`)
- `routing-queues`
  - Routing queue inventory normalization (`GET /api/v2/routing/queues`)

## Catalog unification behavior

`Resolve-Catalog` is the only loader used at runtime.

- Precedence: root `./genesys-core.catalog.json` is canonical when present.
- Fallback: `./catalog/genesys-core.catalog.json` is used only if root is missing.
- If both files exist and differ:
  - loader emits a warning with both file paths + size + modification metadata
  - strict mode (`-StrictCatalog`) fails validation/run

Migration helper: use `Copy-Item ./genesys-core.catalog.json ./catalog/genesys-core.catalog.json -Force` to reconcile the legacy mirror.

## Swagger-driven endpoint coverage

Use `scripts/Update-CatalogFromSwagger.ps1` to keep catalog endpoint coverage aligned with the Genesys Cloud swagger operations while preserving existing curated endpoint entries.

- Canonical catalog file: `./genesys-core.catalog.json`
- Legacy mirror (optional write): `./catalog/genesys-core.catalog.json`
- Default swagger URL: `https://api.mypurecloud.com/api/v2/docs/swagger`
- Local swagger snapshot path: `./generated/swagger/swagger.json`

```powershell
# One-command refresh from swagger + optional mirror update
pwsh -NoProfile -File ./scripts/Update-CatalogFromSwagger.ps1 -WriteLegacyCopy

# Use a pre-downloaded swagger file
pwsh -NoProfile -File ./scripts/Update-CatalogFromSwagger.ps1 -SwaggerPath ./my/swagger.json -WriteLegacyCopy
```

If root and legacy catalogs diverge, `Resolve-Catalog` warns by default and fails in strict mode (`-StrictCatalog`).

## Quick start (local)

```powershell
Import-Module ./src/ps-module/Genesys.Core/Genesys.Core.psd1 -Force

# Dry run planning
Invoke-Dataset -Dataset 'audit-logs' -WhatIf

# Real run (requires valid Genesys Cloud authorization headers)
$headers = @{ Authorization = 'Bearer <token>' }
Invoke-Dataset -Dataset 'users' -OutputRoot './out' -BaseUri 'https://api.mypurecloud.com' -Headers $headers
```

## Validation and smoke checks

```powershell
# Full tests
$config = . ./tests/PesterConfiguration.ps1
Invoke-Pester -Configuration $config

# Catalog validation + fixture-driven dry-run ingest for all datasets
pwsh -NoProfile -File ./scripts/Invoke-Smoke.ps1
```
