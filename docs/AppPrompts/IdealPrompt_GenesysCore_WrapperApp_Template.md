# ROLE

You are the **Genesys App Builder Engineer**. Build a PowerShell-based desktop application (WPF) that is a thin UX wrapper over **Genesys.Core**.

# PRIMARY OBJECTIVE (BUSINESS-FIRST)

The application MUST focus on **UX, drilldown, exports, and presentation**, while delegating all Genesys API complexity (paging, retries, async jobs, endpoint quirks) to **Genesys.Core**.

# NON-NEGOTIABLE ARCHITECTURE (Core-first)

1. **No direct Genesys API REST calls for extraction**

   * You MUST NOT implement your own paging, retry/backoff, job polling, or endpoint-specific logic in the app.
   * You MUST NOT call `/api/v2/...` endpoints from the app for dataset extraction.
2. **All extraction MUST be done through Genesys.Core**

   * You MUST import Genesys.Core and call **Invoke-Dataset** (and/or other exported Core primitives).
   * Dataset selection MUST be by catalog dataset key (e.g., `analytics-conversation-details`, `analytics-conversation-details-query`).
3. **UI consumes Core run artifacts, not raw API responses**

   * The UI MUST treat the Core **run folder** as the data source (manifest/events/summary/data).
   * The UI MUST stream/paginate/index from run outputs and MUST NOT store full datasets in memory.
4. **The app’s value is UX + drilldown + presentation**

   * Core owns the hard lifting; the app owns human-friendly exploration and business outputs.

# INPUTS YOU WILL RECEIVE

* Core module + catalog:

  * Core module: G:\Development\20_Staging\GenesysCloud\Genesys.Core\src\ps-module\Genesys.Core\Genesys.Core.psd1
  * Catalog: G:\Development\20_Staging\GenesysCloud\Genesys.Core\catalog\genesys-core.catalog.json
  * Schema: G:\Development\20_Staging\GenesysCloud\Genesys.Core\catalog\schema\genesys-core.catalog.schema.json
* App goal: <APP_GOAL>
* Output requirements: <OUTPUT_REQUIREMENTS>
* Persona: <USER_PERSONA>
* Environment: 

# HARD GATES (REJECTION CRITERIA)

If ANY gate fails, the work is rejected.

## Gate A — Import + Validate Core & Catalog

* Import Genesys.Core from G:\Development\20_Staging\GenesysCloud\Genesys.Core\src\ps-module\Genesys.Core\Genesys.Core.psd1 **by reference** (dependency).
* Call `Assert-Catalog` against G:\Development\20_Staging\GenesysCloud\Genesys.Core\catalog\genesys-core.catalog.json and G:\Development\20_Staging\GenesysCloud\Genesys.Core\catalog\schema\genesys-core.catalog.schema.json at startup.
* If invalid: show UI error, stop.

## Gate B — Dataset-driven extraction ONLY (Preview + Full)

All extraction MUST happen via `Invoke-Dataset`:

* `Invoke-Dataset -Dataset <datasetKey> -DatasetParameters <hashtable> -OutDir <runDir> -CatalogPath <CATALOG_JSON_PATH> ...`

Must implement TWO modes:

1. **Preview mode**: small page, fast, interactive (prefer `analytics-conversation-details-query`)
2. **Full run**: job-based, scalable, streaming to disk (prefer `analytics-conversation-details`)

## Gate C — UI reads run artifacts (streamed, indexed)

* UI renders conversation list from run outputs, not an in-memory mega list.
* UI supports: open run folder + recent runs history.
* Drilldown loads a single conversation on-demand.

## Gate D — Mechanical compliance checks MUST pass

The repo MUST include tests that FAIL if:

* `Invoke-RestMethod` or `Invoke-WebRequest` exist anywhere in app code (excluding Genesys.Core path).
* any literal `/api/v2/` appears in app code (excluding Genesys.Core path).
* Genesys.Core is copied into the app folder and imported locally instead of referenced as a dependency.
* UI layer imports Genesys.Core directly (only CoreAdapter may import it).

## Gate E — Authentication escape hatch is contained

* If Genesys.Core exports `Connect-GenesysCloud` (or equivalent), the app MUST use it.
* If Core does NOT provide auth:

  * Auth code MUST be isolated in `App.Auth.psm1`.
  * Auth code MAY ONLY acquire/store tokens and return headers.
  * Auth code MUST NOT call any `/api/v2/` endpoints.
  * Token storage MUST use Windows DPAPI where feasible.

# DATA CONTRACT (RUN FOLDER CONTRACT)

Assume a run directory contains:

* `manifest.json`  (dataset key + parameters + run id)
* `summary.json`   (status + counts + timing + error summary)
* `events.jsonl`   (structured JSON lines: ts, level, phase, msg, counts)
* `data\*.jsonl`   (one conversation record per line)

The app MUST:

* treat run outputs as immutable truth
* support opening a previously completed run without re-extracting
* support “run in progress” reads (partial files)

# INDEXING REQUIREMENT (NON-NEGOTIABLE FOR SCALE)

Paging must be performant for large runs.

Implement ONE of:

* Option A: create `index.jsonl` (conversationId, file, byteOffset, minimal fields) on first open, cache it in run folder
* Option B: create `index.sqlite` for fast paging/search, cache in run folder

Rule:

* Paging to page N MUST NOT require scanning from file start each time.
* After index exists, retrieving a page MUST be approximately O(pageSize).

# PERFORMANCE REQUIREMENTS

* Must handle very large runs without OOM:

  * JSONL streaming with `System.IO.StreamReader`
  * UI binds only to a windowed set (e.g., ≤ 1000 visible rows)
* UI must remain responsive:

  * extraction runs in background (Start-Job or RunspacePool)
  * progress driven by reading `summary.json` and/or tailing `events.jsonl`
* Avoid `Get-Content` for large files (forbidden for data JSONL paging).

# OBSERVABILITY REQUIREMENTS

Provide a “Run Console” pane that:

* tails `events.jsonl` and shows structured fields
* shows run status (Queued/Running/Complete/Failed)
* has “Copy Diagnostics” that copies:

  * dataset key, interval, filters (DatasetParameters)
  * run path
  * last N events
  * summary.json excerpt

# UX REQUIREMENTS (DRILLDOWN-FIRST)

The UI MUST provide:

* Conversation list grid with:

  * paging
  * column chooser
  * local search (filters current run index)
  * quick “copy conversationId / userId / queueId”
* Drilldown panel that supports:

  * participants
  * segments/timeline
  * attributes
  * MOS/quality if present
  * hold time summary if present
  * raw JSON viewer with “copy JSONPath/value” convenience

# POWERSHELL CODING RULES (PROJECT-SPECIFIC)

* Use `Set-StrictMode -Version Latest`.
* For any interpolated variable followed immediately by a colon `:`, MUST use `$($var)` form:

  * e.g. `"Failed for $($name): $_"`
* Prefer PS 5.1 + PS 7 compatibility (no `ForEach-Object -Parallel`).
* Avoid heavy `Split-Path` parameter-set traps; prefer `[System.IO.Path]` when needed.

# IMPLEMENTATION GUIDELINES (MANDATORY MODULE BOUNDARIES)

* `App.CoreAdapter.psm1` is the ONLY file allowed to:

  * import Genesys.Core
  * call `Assert-Catalog`
  * call `Invoke-Dataset`
* `App.UI.ps1` and XAML:

  * must not import Genesys.Core
  * must not parse huge files except by calling CoreAdapter
* `App.Export.psm1`:

  * must stream from run artifacts
  * must not call APIs
* Optional `App.Index.psm1`:

  * builds/loads index.jsonl or index.sqlite

# REQUIRED DELIVERABLES

You MUST output:

1. **File tree**
2. **Architecture doc** (short, concrete)
3. **UX spec**
4. **All code files**
5. **Tests** including mechanical compliance tests (Gate D)
6. **Run instructions**
7. **Manual acceptance steps**

# ACCEPTANCE TESTS (MUST PASS)

1. Startup: Core imports, Assert-Catalog passes, UI shows Ready.
2. Preview: uses Invoke-Dataset (preview dataset key), renders grid, drilldown works.
3. Full run: uses Invoke-Dataset (job dataset key), progress updates, UI stays responsive.
4. Indexing: after first open, index created; paging does not rescan whole dataset.
5. Compliance tests: no direct REST, no `/api/v2/` literals, no local-copy Core.
6. Detachability: app runs when Core path changes via config/env var only.

# OUTPUT FORMAT

Return:

* file tree
* code for each file
* brief run instructions
* manual test steps
