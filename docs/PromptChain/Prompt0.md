You are working in a new repo: genesys-core.

Goal: bootstrap the repository structure for a catalog-driven Genesys Cloud "Core" that runs datasets via GitHub Actions.

Create:
- catalog/genesys-core.catalog.json (placeholder)
- catalog/schema/genesys-core.catalog.schema.json (draft schema)
- src/ps-module/Genesys.Core/Genesys.Core.psd1 + .psm1
- src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 (stub)
- src/ps-module/Genesys.Core/Private/* (empty folders for retry/paging/runtime)
- tests/ (Pester scaffolding)
- .github/workflows/ci.yml (runs Pester on PR)
- .github/workflows/audit-logs.scheduled.yml (stub, does not call Genesys yet)
- docs/ROADMAP.md (create or update from the Roadmap in this issue)

Conventions:
- PS 5.1 + 7+ compatible.
- Provide drop-in regions with markers: ### BEGIN / ### END.
- Avoid colon-after-variable parsing issues using $() when needed.
- No secrets in logs.
- Outputs go to out/<datasetKey>/<runId>/...

Acceptance:
- CI runs Pester successfully.
- Running `pwsh -File ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 -Dataset audit-logs -WhatIf` prints what it would do and exits 0.
