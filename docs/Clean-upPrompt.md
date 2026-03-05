ROLE
You are my Repo Standardization agent. Your objective is to refactor this repository to match the new standard: three primary PowerShell modules in separate lanes (Genesys.Auth, Genesys.Core, Genesys.Ops), plus canonical catalog, tests, scripts, docs, and training paths.

SUCCESS GATE (must be true before you stop)

1. Repo tree matches the target layout described in docs/REPO_SCHEMATIC.md (v2).
2. All docs reflect Auth/Core/Ops ownership accurately and contain no stale paths.
3. `scripts/Invoke-Smoke.ps1` and `scripts/Invoke-Tests.ps1` run successfully locally (offline mode with mocks) and in CI.
4. Back-compat preserved:

   * Core still supports -Headers and GENESYS_BEARER_TOKEN env var for auth.
   * Existing Ops cmdlets still work, but now obtain auth via Genesys.Auth.
5. The interactive onboarding HTML still works and reflects the new model.

CONSTRAINTS

* Do not change dataset semantics or output artifact formats unless required for the new module boundaries.
* Avoid circular module dependencies.
* Keep changes minimal but complete; prefer moving/rewiring over rewriting logic.

INPUTS

* Current repo contains Genesys.Core engine, GenesysOps wrapper, catalog JSON, scripts, tests, and docs.
* Current auth ownership is split: Core consumes headers/env token; Ops provides Connect-GenesysCloud session convenience.

TARGET ARCHITECTURE
A) modules/

* modules/Genesys.Auth (new)
* modules/Genesys.Core (moved from modules/Genesys.Core)
* modules/Genesys.Ops (rename/move from GenesysOps.* to Genesys.Ops.*)

B) catalog/

* catalog/genesys.catalog.json (canonical, single source of truth)
* catalog/schema/genesys.catalog.schema.json

C) docs/

* Update docs/ONBOARDING.md, docs/REPO_SCHEMATIC.md
* Create docs/AUTH.md
* Ensure Training.md points to docs/training/genesys-onboarding.html
* Update the onboarding HTML content to describe Genesys.Auth ownership

D) tests/

* Organize into tests/unit and tests/integration
* Keep scripts/Invoke-Smoke.ps1 and scripts/Invoke-Tests.ps1 as entrypoints
* CI should run unit tests by default; integration tests only when env vars/secrets exist

IMPLEMENTATION STEPS (do in order)

1. Inventory current structure and identify all references to:

   * modules/Genesys.Core
   * modules/Genesys.Ops/Genesys.Ops.psm1/psd1
   * genesys.catalog.json (root and catalog mirror)
   * docs/training/genesys-onboarding.html
2. Create modules/Genesys.Auth:

   * Add Connect-GenesysCloud / Disconnect-GenesysCloud
   * Implement ClientCredentials flow (client_id/client_secret) and support PKCE helpers (protocol logic; UI listener may remain external)
   * Expose AuthContext object with AccessToken, ExpiresAtUtc, Region/BaseUri, and a method to produce headers
3. Move Genesys.Core module into modules/Genesys.Core:

   * Update internal paths and module manifests
   * Update Core to accept -AuthContext (preferred), while preserving -Headers and env token fallback
4. Move/rename GenesysOps into modules/Genesys.Ops:

   * Update module name, manifest, exports
   * Replace any internal session token state with dependency on Genesys.Auth (AuthContext)
5. Canonicalize catalog:

   * Move to catalog/genesys.catalog.json
   * Update all code/doc references to use the new path
   * Keep a small compatibility shim if needed (e.g., a stub file or redirect logic), but prefer removing duplicates
6. Update scripts:

   * Update any script paths that import modules or read the catalog
   * Ensure bridge script (scripts/Invoke-GenesysBridge.ps1) works for wrappers and returns stable JSON results
7. Re-organize tests:

   * Move unit tests to tests/unit (mocked HTTP, token)
   * Move integration tests to tests/integration (gated by env vars)
   * Update CI workflow(s) accordingly
8. Update documentation:

   * Rewrite docs/REPO_SCHEMATIC.md to reflect v2 layout and ownership
   * Rewrite docs/ONBOARDING.md to use Genesys.Auth + AuthContext path
   * Create/refresh docs/AUTH.md with integration patterns
   * Update Training.md and the onboarding HTML copy and footer “source anchors”
9. Validate:

   * Run smoke tests
   * Run full tests
   * Ensure docs have no stale references

DELIVERABLES

* A single PR-style change set including file moves, module creation, updated scripts/tests, and updated docs.
* A “migration notes” section in docs/ONBOARDING.md explaining old paths -> new paths.

STOP CONDITION
Stop only when SUCCESS GATE is satisfied.

