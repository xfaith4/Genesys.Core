# Genesys.Core Repository Schematic

This is the v2 lane layout and canonical navigation map.

```text
Genesys.Core/
|-- README.md
|-- TESTING.md
|-- App.Auth.psm1                            # legacy shim -> modules/Genesys.Auth
|-- GenesysOps.psd1                          # legacy shim manifest -> modules/Genesys.Ops
|-- GenesysOps.psm1                          # legacy shim -> modules/Genesys.Ops
|-- GenesysCore-GUI.ps1
|-- GenesysConvAnalyzer.ps1
|-- genesys.env.json.example
|-- modules/
|   |-- Genesys.Auth/
|   |   |-- Genesys.Auth.psd1
|   |   `-- Genesys.Auth.psm1
|   |-- Genesys.Core/
|   |   |-- Genesys.Core.psd1
|   |   |-- Genesys.Core.psm1
|   |   |-- Public/Invoke-Dataset.ps1
|   |   `-- Private/
|   |       |-- Catalog/
|   |       |-- Datasets/
|   |       |-- Retry/
|   |       |-- Paging/
|   |       |-- Async/
|   |       |-- Redaction/
|   |       `-- Run/
|   `-- Genesys.Ops/
|       |-- Genesys.Ops.psd1
|       `-- Genesys.Ops.psm1
|-- catalog/
|   |-- genesys.catalog.json                 # canonical catalog
|   `-- schema/
|       `-- genesys.catalog.schema.json      # canonical schema
|-- docs/
|   |-- ONBOARDING.md
|   |-- ENGINEER_INTEGRATIONS_AUTH.md
|   |-- REPO_SCHEMATIC.md
|   `-- training/
|       |-- genesys-onboarding.html          # canonical training page
|       `-- Training.md
|-- scripts/
|   |-- Invoke-Smoke.ps1
|   |-- Invoke-Tests.ps1
|   |-- Invoke-GenesysCoreBridge.ps1
|   |-- Invoke-MockRun.ps1
|   |-- Update-CatalogFromSwagger.ps1
|   `-- Sync-SwaggerEndpoints.ps1
`-- tests/
    |-- unit/
    |   `-- *.Tests.ps1
    `-- integration/
        `-- workflow-simulation.ps1
```

## Lane Model

```text
Wrapper UI / App
  -> Genesys.Auth (token lifecycle + AuthContext)
  -> Genesys.Ops  (optional convenience cmdlets)
  -> Genesys.Core (catalog-driven runtime engine)
  -> output contract: out/<dataset>/<runId>/{manifest,events,summary,data}
```

## Canonical Defaults

- Catalog: `catalog/genesys.catalog.json`
- Schema: `catalog/schema/genesys.catalog.schema.json`
- Training: `docs/training/genesys-onboarding.html`
- Module imports:
  - `./modules/Genesys.Auth/Genesys.Auth.psd1`
  - `./modules/Genesys.Core/Genesys.Core.psd1`
  - `./modules/Genesys.Ops/Genesys.Ops.psd1`

## Contribution Shortcut

- Runtime behavior: `catalog/genesys.catalog.json` + `modules/Genesys.Core/Private/*`
- Auth behavior: `modules/Genesys.Auth/*`
- Ops wrappers: `modules/Genesys.Ops/*`
- Quick check: `scripts/Invoke-Smoke.ps1`
- Full unit test run: `scripts/Invoke-Tests.ps1`
