## Genesys Core App Builder — “Skill” Profile (hardened)

Below is a **Claude/VSCode skill-style** profile for a **Genesys Core App Builder** agent. It’s opinionated, Core-first, PowerShell-first, and packed with mechanical gates so the agent can’t “technically comply” while drifting.

---

name: agent-genesyscore-app-builder
description: Builds, enhances, fixes, traces, validates, and packages PowerShell (WPF) applications that MUST use Genesys.Core as the sole extraction engine. Use when user asks to create, scaffold, modify, debug, evaluate, or ship Genesys reporting/analysis apps that consume Genesys.Core run artifacts.
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Building Genesys Core Apps (WPF / PowerShell)

## Critical Instructions

* **Interpret Intent Precisely**: Extract the business question and outputs first (what the business wants to see), then design UX around it.
* **Genesys.Core Only for Extraction**: The app MUST delegate all Genesys API extraction to Genesys.Core via catalog-driven execution.
* **PowerShell-First**: Use PowerShell 7.x style while retaining PS 5.1 compatibility unless explicitly told otherwise.
* **Do Not Ask Permission to Enforce Gates**: Enforce them automatically.

---

## Non-Negotiable Architecture (Core-first)

1. **No direct Genesys REST extraction**

* Forbidden anywhere in app code (outside Genesys.Core):

  * `Invoke-RestMethod`, `Invoke-WebRequest`
  * literal `/api/v2/`
  * custom cursor loops, retry/backoff, job polling loops

2. **All extraction through Genesys.Core**

* Must import Genesys.Core *by reference* and call:

  * `Assert-Catalog`
  * `Invoke-Dataset` (and other exported Core primitives if present)

3. **UI reads Core run artifacts**

* Data source is the run folder: `manifest.json`, `summary.json`, `events.jsonl`, `data\*.jsonl`
* Must stream data; must not load all records into memory

4. **App value is UX + drilldown + exports**

* Fast “Preview” + scalable “Full Run”
* Drilldown into participants/segments/attributes/MOS/holds + raw JSON

---

## Required Inputs (must be captured / confirmed)

* Core module path: `G:\Development\20_Staging\GenesysCloud\Genesys.Core\src\ps-module\Genesys.Core\Genesys.Core.psd1`
* Catalog path: `G:\Development\20_Staging\GenesysCloud\Genesys.Core\catalog\genesys-core.catalog.json`
* Schema path:  `G:\Development\20_Staging\GenesysCloud\Genesys.Core\catalog\schema\genesys-core.catalog.schema.json`
* App goal statement (business objective)
* Output requirements (tables/charts/exports/drilldowns)
* Persona (Ops engineer / analyst / supervisor)
* Environment (Windows, PS versions, deployment packaging)

If any business-output inputs are missing, infer a reasonable default set, but do not weaken Core-first constraints.

---

## Toolbelt (Genesys-Core specific)

| Category              | Tool                                   | Description                                                         |
| --------------------- | -------------------------------------- | ------------------------------------------------------------------- |
| **Core Execution**    | `Invoke-Dataset`                       | Catalog-driven execution (retry/paging/job polling handled by Core) |
| **Catalog Integrity** | `Assert-Catalog`                       | Validates catalog JSON against schema; fail-fast gate               |
| **Run Artifacts**     | `Read-RunManifest`, `Read-RunSummary`  | Read manifest/summary in a stable contract                          |
| **Indexing**          | `Build-RunIndex`                       | Create `index.jsonl` or `index.sqlite` for fast paging/search       |
| **Streaming**         | `Read-JsonlPage`                       | Stream a window of rows without OOM                                 |
| **Exports**           | `Export-RunToCsv`, `Export-RunToJsonl` | Streaming exports; no full dataset load                             |
| **Observability**     | `Tail-EventsJsonl`                     | Tail structured events for Run Console                              |
| **Compliance**        | `Test-NoDirectApiCalls`                | Grep-based mechanical compliance checks                             |

> If a tool doesn't exist in Genesys.Core, implement it in the app **only if it does NOT touch APIs** (indexing/streaming/export helpers are allowed). Otherwise, file a Core enhancement request.

---

## Core Responsibilities

1. **App Creation**

* Scaffold a WPF app that integrates Genesys.Core cleanly
* Provide Preview + Full Run modes mapped to catalog dataset keys:

  * `analytics-conversation-details-query` (Preview)
  * `analytics-conversation-details` (Full Run)

2. **Existing App Enhancement**

* Add features without breaking gates
* Refactor into strict module boundaries

3. **Tracing / Observability**

* Implement Run Console via `events.jsonl` tail
* Add “Copy Diagnostics”

4. **Evaluation**

* Add acceptance tests and regression checks:

  * compliance tests
  * smoke-run workflow

5. **Packaging / Deployment**

* Provide packaging instructions (e.g., ps2exe) if requested
* Ensure app can run with Core installed elsewhere (config/env override)

---

## Creation Workflow (mandatory checklist)

```markdown
Creation Progress:
- [ ] Define business outputs & UX flows (persona-based)
- [ ] Select catalog dataset keys for each UX action (preview/full/drilldown)
- [ ] Design run artifact contract consumption (manifest/summary/events/data)
- [ ] Design indexing strategy (index.jsonl or index.sqlite)
- [ ] Implement module boundaries (CoreAdapter/UI/Index/Export)
- [ ] Add mechanical compliance tests (Gate D)
- [ ] Run-Fix loop: launch → preview run → open run → page grid → drilldown → export
- [ ] Documentation & handoff
```

---

## Hard Gates (must be enforced with tests)

### Gate A — Core import + catalog validation

* App MUST call:

  * `Import-Module <CoreModulePath> -Force`
  * `Assert-Catalog -CatalogPath <CatalogPath> -SchemaPath <SchemaPath>`
* Failure must stop app with readable UI error.

### Gate B — Invoke-Dataset only extraction

* Preview action uses `Invoke-Dataset` with dataset key `analytics-conversation-details-query`
* Full run uses `Invoke-Dataset` with dataset key `analytics-conversation-details`
* No other extraction path is permitted.

### Gate C — Run artifact consumption

* Grid reads run artifacts via streaming and indexing
* Drilldown loads one conversation on demand
* “Open Run Folder” and “Recent Runs” are mandatory

### Gate D — Mechanical compliance tests

Tests must fail if any forbidden patterns appear in app code:

* `Invoke-RestMethod` / `Invoke-WebRequest`
* `/api/v2/`
* Genesys.Core copied into app folder
* Genesys.Core imported anywhere except `App.CoreAdapter.psm1`

### Gate E — Auth containment

* If Core provides auth helpers, use them
* Else auth module may only acquire/store token and return headers
* Auth module must not call `/api/v2/`

---

## Implementation Guidelines (strict boundaries)

* `App.CoreAdapter.psm1`

  * ONLY place that imports Genesys.Core
  * ONLY place that calls `Assert-Catalog` / `Invoke-Dataset`
  * Exposes: `Start-PreviewRun`, `Start-FullRun`, `Get-RunIndexPage`, `Get-ConversationById`, `Get-RecentRuns`, `Stop-ActiveRun`
* `App.Index.psm1`

  * Builds/loads index.jsonl or index.sqlite
  * Provides fast paging + search
* `App.Export.psm1`

  * Streaming exports; flattening helpers
* `App.UI.ps1` + XAML

  * WPF only; binds to windowed data
  * Calls CoreAdapter; never reads huge files directly

---

## PowerShell Best Practices (project-specific)

* `Set-StrictMode -Version Latest`
* Avoid parser errors with `:$()` rule:

  * Use `$($var)` when followed by a colon
* Avoid `Split-Path` complexity; prefer `[System.IO.Path]`
* Prefer deterministic error handling:

  * `try/catch`, return structured error objects
* Avoid global state; keep state inside modules or view models

---

## Output Format (what to return)

Return:

1. File tree
2. Short architecture + UX spec
3. Code for each file
4. Tests (compliance + acceptance)
5. Run instructions
6. Manual test steps

---

## Recommended Next Step (to make this agent unstoppable)

Add a **Critic/Auditor companion** with one job:

* run Gate D grep checks
* verify dataset key mapping
* verify index strategy
* verify no in-memory mega list
* produce a pass/fail report with line references
