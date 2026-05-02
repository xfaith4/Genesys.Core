# Genesys.Core Repository Schematic

This is the v2 lane layout and canonical navigation map.

```text
Genesys.Core/
├── README.md
├── TESTING.md
├── GenesysCore-GUI.ps1                    # Windows WPF GUI client
├── genesys.env.json.example
├── modules/
│   ├── Genesys.Auth/
│   │   ├── Genesys.Auth.psd1
│   │   └── Genesys.Auth.psm1
│   ├── Genesys.Core/
│   │   ├── Genesys.Core.psd1
│   │   ├── Genesys.Core.psm1
│   │   ├── Public/
│   │   │   ├── Invoke-Dataset.ps1
│   │   │   └── Assert-Catalog.ps1
│   │   └── Private/
│   │       ├── Catalog.ps1       # Catalog resolution, profile merging, normalization
│   │       ├── Redaction.ps1     # PII/sensitive-field redaction
│   │       ├── RunArtifacts.ps1  # Run context, JSONL/manifest/event writers
│   │       ├── Transport.ps1     # URI construction, HTTP, retry engine
│   │       ├── Paging.ps1        # All paging strategies + core endpoint dispatcher
│   │       ├── Async.ps1         # Async job and audit transaction patterns
│   │       └── Datasets.ps1      # Dataset registry, invokers, output orchestration
│   └── Genesys.Ops/
│       ├── Genesys.Ops.psd1
│       └── Genesys.Ops.psm1
├── apps/
│   └── ConversationAnalysis/
│       ├── index.html                     # Self-contained SPA (no build required)
│       └── README.md
├── catalog/
│   ├── genesys.catalog.json               # Canonical catalog
│   └── schema/
│       └── genesys.catalog.schema.json    # Canonical schema
├── docs/
│   ├── ONBOARDING.md
│   ├── ENGINEER_INTEGRATIONS_AUTH.md
│   ├── ROADMAP.md
│   ├── INVESTIGATIONS.md                 # Investigation composer design (Release 1.0 Track B)
│   ├── TEST_EVIDENCE_LEVELS.md           # Validation claim vocabulary
│   ├── CHANGELOG.md
│   ├── READINESS_REVIEW.md
│   ├── REPO_SCHEMATIC.md
│   └── training/
│       ├── genesys-onboarding.html        # Canonical training page
│       └── Training.md
├── scripts/
│   ├── Invoke-Smoke.ps1
│   ├── Invoke-Tests.ps1
│   ├── Invoke-LiveValidationMenu.ps1      # Operator-run live validation menu
│   ├── Invoke-GenesysCoreBridge.ps1       # CLI bridge for non-PS wrappers
│   ├── Invoke-MockRun.ps1
│   ├── Update-CatalogFromSwagger.ps1
│   └── Sync-SwaggerEndpoints.ps1
└── tests/
    ├── PesterConfiguration.ps1
    ├── unit/
    │   └── *.Tests.ps1                    # 16 unit test files
    └── integration/
        └── workflow-simulation.ps1
```

## Lane Model

```text
Wrapper UI / App
  -> Genesys.Auth (token lifecycle + AuthContext)
  -> Genesys.Ops  (optional convenience cmdlets)
  -> Genesys.Core (catalog-driven runtime engine)
  -> output contract: out/<dataset>/<runId>/{manifest,events,summary,data}
```

## Validation Vocabulary

Evidence labels for tests, readiness claims, live probes, and production
workflow validation are defined in `docs/TEST_EVIDENCE_LEVELS.md`.

## Canonical Defaults

- Catalog: `catalog/genesys.catalog.json`
- Schema: `catalog/schema/genesys.catalog.schema.json`
- Training: `docs/training/genesys-onboarding.html`
- Module imports:
  - `./modules/Genesys.Auth/Genesys.Auth.psd1`
  - `./modules/Genesys.Core/Genesys.Core.psd1`
  - `./modules/Genesys.Ops/Genesys.Ops.psd1`
- Conversation Analysis app: `apps/ConversationAnalysis/index.html`

## Contribution Shortcut

- Runtime behavior: `catalog/genesys.catalog.json` + `modules/Genesys.Core/Private/*`
- Auth behavior: `modules/Genesys.Auth/*`
- Ops wrappers: `modules/Genesys.Ops/*`
- Quick check: `scripts/Invoke-Smoke.ps1`
- Full unit test run: `scripts/Invoke-Tests.ps1`
