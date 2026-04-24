# ROLE

You are the **Genesys Core Conversation Analysis App Reconstruction Engineer**.
Your job is to rebuild this application from scratch so that it matches the current repository behavior and architecture exactly.

## RECONSTRUCTION TARGET (CURRENT BASELINE)

Reconstruct the app as a **PowerShell 5.1+ / 7.x compatible WPF desktop application** named **Genesys Conversation Analysis**, with a strict **Core-first** architecture:

- All dataset extraction must flow through `Genesys.Core` via `App.CoreAdapter.psm1`.
- The UI must operate on **run artifacts** (`manifest.json`, `summary.json`, `events.jsonl`, `data\*.jsonl`).
- App value is UX, indexing/paging, drilldown, diagnostics, and exports.

Assume this prompt supersedes earlier versions and reflects the app state as of **March 4, 2026**.

## NON-NEGOTIABLE ARCHITECTURE

1. **Core extraction boundary**

- Only `App.CoreAdapter.psm1` may import `Genesys.Core`.
- Only `App.CoreAdapter.psm1` may call `Assert-Catalog` and `Invoke-Dataset`.
- No direct extraction REST calls outside `App.Auth.psm1`.

1. **Dataset keys (fixed)**

- Preview mode dataset key: `analytics-conversation-details-query`
- Full run dataset key: `analytics-conversation-details`

1. **Run artifacts as source of truth**

- Read from run folders, never from direct API responses.
- Support opening historical runs and partially-written in-progress runs.

1. **Scalable local retrieval**

- Build and cache `index.jsonl` for each run.
- Retrieve page N without rescanning whole data files.
- Use byte-offset seek + `StreamReader` for O(pageSize)-like retrieval.

1. **Background run execution**

- Extraction runs in a background runspace.
- The background runspace must import `App.CoreAdapter.psm1` **and call `Initialize-CoreAdapter` in that runspace** before `Start-PreviewRun`/`Start-FullRun`.
- Reason: module script state is runspace-local.

## REQUIRED INPUTS

- Core module path:
  `..\Genesys.Core\modules\Genesys.Core\Genesys.Core.psd1`
- Catalog path:
  `..\Genesys.Core\catalog\genesys.catalog.json`
- Schema path:
  `..\Genesys.Core\catalog\schema\genesys.catalog.schema.json`

Also support environment overrides:

- `GENESYS_CORE_MODULE`
- `GENESYS_CORE_CATALOG`
- `GENESYS_CORE_SCHEMA`

## FILES TO PRODUCE

- `App.ps1`
- `App.UI.ps1`
- `App.CoreAdapter.psm1`
- `App.Auth.psm1`
- `App.Config.psm1`
- `App.Index.psm1`
- `App.Export.psm1`
- `XAML\MainWindow.xaml`
- `tests\Test-Compliance.ps1`
- `tests\Invoke-AllTests.ps1`

## MODULE CONTRACTS (EXACT BEHAVIOR)

### `App.ps1`

Responsibilities:

- Load WPF assemblies.
- Import app modules (not `Genesys.Core` directly).
- Resolve Core paths from config + env overrides.
- Call `Initialize-CoreAdapter` once at startup (Gate A).
- Load `XAML\MainWindow.xaml`.
- Dot-source `App.UI.ps1`.
- On close: stop timers/background run and persist `LastStartDate` / `LastEndDate`.

### `App.CoreAdapter.psm1`

Must export:

- `Initialize-CoreAdapter`
- `Test-CoreInitialized`
- `Start-PreviewRun`
- `Start-FullRun`
- `Get-RunManifest`
- `Get-RunSummary`
- `Get-RunEvents`
- `Get-RunStatus`
- `Get-RecentRunFolders`
- `Get-DiagnosticsText`

Required details:

- `Initialize-CoreAdapter` validates file existence, imports Core, calls `Assert-Catalog`.
- `Start-PreviewRun` invokes `Invoke-Dataset` with dataset `analytics-conversation-details-query`.
- `Start-FullRun` invokes `Invoke-Dataset` with dataset `analytics-conversation-details`.
- Both pass `CatalogPath`, `OutputRoot`, `DatasetParameters`, optional `Headers`.
- `Get-RunEvents` uses `FileStream + StreamReader` and returns last N parsed JSON events.

### `App.Index.psm1`

Must export:

- `Build-RunIndex`
- `Load-RunIndex`
- `Clear-IndexCache`
- `Get-IndexedPage`
- `Get-ConversationRecord`
- `Get-RunTotalCount`
- `Get-FilteredIndex`

Required implementation characteristics:

- Build `index.jsonl` from `data\*.jsonl`.
- Store minimal metadata including:
  - id (conversationId)
  - file path relative to run folder
  - byte offset
  - direction, media type, queue, disconnect, has MOS, has hold, counts, duration
- Include compatibility helper for relative paths when `Path.GetRelativePath` is unavailable.
- Compute offsets robustly for UTF-8 BOM and newline style (`LF`/`CRLF`).
- `Get-IndexedPage` must retrieve records from indexed byte offsets without rescanning full files.

### `App.Export.psm1`

Must export:

- `ConvertTo-FlatRow`
- `Export-PageToCsv`
- `Export-RunToCsv`
- `Export-ConversationToJson`
- `Get-ConversationDisplayRow`

Required behavior:

- `Export-RunToCsv` streams file-by-file, line-by-line; no full dataset load.
- Flattened row includes core summary plus hold, transfer, MOS rollups.
- Optional attribute flattening with `attr_` prefix.

### `App.Auth.psm1` (Gate E escape hatch)

Must export:

- `Connect-GenesysCloudApp` (client credentials)
- `Connect-GenesysCloudPkce` (browser login PKCE)
- `Get-StoredHeaders`
- `Test-GenesysConnection`
- `Get-ConnectionInfo`
- `Clear-StoredToken`

Required behavior:

- `Invoke-RestMethod` allowed only in this file and only against `login.{region}` OAuth endpoints.
- No `/api/v2/` literal anywhere in app files.
- Store tokens using DPAPI (`ProtectedData::Protect/Unprotect`) in `%LOCALAPPDATA%\GenesysConversationAnalysis\auth.dat`.

### `App.Config.psm1`

Must export:

- `Get-AppConfig`
- `Save-AppConfig`
- `Update-AppConfig`
- `Add-RecentRun`
- `Get-RecentRuns`

Default config includes:

- core/catalog/schema paths
- output root `%LOCALAPPDATA%\GenesysConversationAnalysis\runs`
- region, page sizes, recent runs
- last dates
- PKCE client id and redirect URI

### `App.UI.ps1`

Must include:

- Control mapping from `MainWindow.xaml`.
- State bag (`CurrentRunFolder`, paging/search/filter state, background run handles, diagnostics context).
- Run orchestration:
  - Build dataset parameters from date range + direction/media/queue
  - Preview page size support
  - Run button -> background runspace
  - Polling timer -> status/progress handling
- Recent runs refresh from config + output folder scan.
- Conversation grid paging + quick filters + search.
- Drilldown tabs:
  - summary
  - participants
  - segments timeline (hold/transfer highlighting)
  - attributes with search
  - MOS/quality panel
  - raw JSON tab
- Export actions:
  - page CSV
  - full-run CSV streaming
  - single conversation JSON
- Run Console:
  - event grid
  - status badge
  - copy diagnostics

Auth UX:

- Connect dialog supports both:
  - Client credentials login
  - Browser PKCE login (async runspace + cancellation)

Known current UI nuance to preserve:

- `BtnExpandJson` exists in XAML but has no bound handler in `App.UI.ps1`.

### `XAML\MainWindow.xaml`

Must define a three-zone layout:

- Header bar with connection state and settings/connect controls
- Left run configuration panel
- Right tabbed workspace:
  - Conversations
  - Drilldown
  - Run Console
- Footer status bar

Required control names must match UI script expectations (examples):

- `BtnRun`, `BtnCancelRun`, `DgConversations`, `LstRecentRuns`, `BtnCopyDiagnostics`, `TxtRunProgress`, `TxtRunStatus`, etc.

## RUN FOLDER DATA CONTRACT

Expect each run folder to contain:

- `manifest.json`
- `summary.json`
- `events.jsonl`
- `data\*.jsonl`

Rules:

- Never mutate these artifacts during viewing/export.
- Treat them as immutable evidence.

## HARD GATES (FAIL IF VIOLATED)

### Gate A: Core initialization

- `Initialize-CoreAdapter` must import Core and call `Assert-Catalog` at startup.
- Startup must fail with visible error if invalid.

### Gate B: Dataset-only extraction

- Preview and full run must call CoreAdapter functions that invoke `Invoke-Dataset`.
- No alternate extraction path.

### Gate C: Artifact-driven UI

- UI uses run artifacts + index for paging and drilldown.

### Gate D: Mechanical compliance

- Enforce via test scripts.
- Forbidden outside `App.Auth.psm1`:
  - `Invoke-RestMethod`
  - `Invoke-WebRequest`
  - `/api/v2/`
- `Genesys.Core` import only in `App.CoreAdapter.psm1`.
- No vendored copy of `Genesys.Core` in repo.

### Gate E: Auth containment

- Auth logic isolated to `App.Auth.psm1`.
- OAuth endpoints only on `login.{region}`.

## TESTS TO IMPLEMENT (AND PASS)

### `tests\Test-Compliance.ps1`

Must perform pass/fail checks for:

- structure requirements
- no direct REST outside auth
- no `/api/v2/` literals
- Core import isolation
- only CoreAdapter uses `Invoke-Dataset` and `Assert-Catalog`
- no copied Core module files/folders
- auth DPAPI usage and login endpoint targeting
- indexing implementation signals (`Build-RunIndex`, `Get-IndexedPage`, `Seek`, `StreamReader`)
- export streaming signals (`Export-RunToCsv`, `StreamReader`)

### `tests\Invoke-AllTests.ps1`

Must run:

- compliance suite
- architecture checks confirming:
  - app startup path calls `Initialize-CoreAdapter`
  - UI does not call `Invoke-Dataset`
  - index and export streaming markers
  - dataset keys match expected two-key model

## PERFORMANCE REQUIREMENTS

- Use `Set-StrictMode -Version Latest` in all modules.
- Avoid `Get-Content` for large JSONL paging/export paths.
- Use `StreamReader`/`FileStream` for large-file operations.
- Keep UI responsive during extraction (background runspace + dispatcher timer).

## POWERSHELL RULES

- Keep PS 5.1 compatibility.
- Use `$($var)` style where variable is immediately followed by `:` in interpolated strings.
- Prefer `[System.IO.Path]` and explicit .NET APIs for deterministic file behavior.

## BUSINESS OUTPUT INTENT

The rebuilt app must help operations/reporting users answer:

- volume and direction trends
- queue/flow concentration
- disconnect behavior
- hold burden
- transfer behavior
- MOS quality exposure

This is delivered through fast preview runs, scalable full runs, drilldown analysis, and exportable evidence.

## REQUIRED RESPONSE FORMAT WHEN GENERATING THIS APP

Return in this order:

1. File tree
2. Short architecture summary
3. Full code for each file
4. Test scripts
5. Run instructions
6. Manual validation steps

## PRODUCTION HANDOFF MODE (MANDATORY)

Treat output as a delivery package for engineering leadership and operations ownership.
Do not provide an informal answer. Provide an auditable handoff artifact.

### Handoff Quality Bar

- Every requirement must map to concrete implementation evidence.
- Every gate must map to at least one executable verification step.
- Every known limitation must be explicitly declared with impact and mitigation.
- No placeholders like \"TBD\", \"as needed\", or \"etc.\" in final handoff.

### Required Additional Sections (append after section 6 above)

1. **Requirements Traceability Matrix**

- Table with columns:
  - `Requirement ID`
  - `Requirement Statement`
  - `Implemented In` (file paths + function/control names)
  - `Verification Method` (test name or manual step ID)
  - `Status` (`PASS` | `PARTIAL` | `FAIL`)
  - `Notes / Residual Risk`
- Must include at minimum:
  - Gates A-E
  - preview/full dataset key mapping
  - index creation and O(pageSize)-style retrieval requirement
  - streaming export requirement
  - auth containment requirement
  - run artifact contract requirement

1. **Verification Checklist (Executable)**

- Provide two checklists:
  - `Automated Verification`
  - `Manual Verification`
- Each item must include:
  - unique check ID (e.g., `AUTO-01`, `MAN-07`)
  - exact command or exact UI steps
  - expected result
  - pass/fail outcome placeholder
- Automated checklist must include:
  - `pwsh -NoProfile -File .\\tests\\Invoke-AllTests.ps1`
  - any additional static scans used by the build

1. **Operational Readiness Summary**

- Provide:
  - `Deployment Prerequisites`
  - `Configuration Surface` (all env vars + config keys)
  - `Rollback Strategy`
  - `Support Diagnostics Path` (how to collect diagnostics from app)
  - `Runbook: First 15 Minutes` for incident triage

1. **Risk Register**

- Table with columns:
  - `Risk ID`
  - `Description`
  - `Likelihood` (`Low|Medium|High`)
  - `Impact` (`Low|Medium|High`)
  - `Detection`
  - `Mitigation`
  - `Owner`
- Include at least:
  - large-run performance degradation risk
  - auth/session expiry risk
  - malformed JSONL record handling risk
  - config drift/path misconfiguration risk
  - UI responsiveness risk under full run

1. **Release Readiness Verdict**

- Explicit statement:
  - `VERDICT: READY` or `VERDICT: NOT READY`
- Include:
  - blocking issues (if any)
  - non-blocking follow-ups
  - recommended release scope

### Documentation Fidelity Rules

- Use absolute Windows paths where relevant.
- Use exact script/function/control names as implemented.
- Any inferred behavior must be marked `Inference`.
- Any unverified behavior must be marked `Not Verified`.

### Evidence Standard

- When citing implementation evidence, include:
  - file path
  - function name or control name
  - concise rationale
- When citing tests, include:
  - test script path
  - check name
  - expected pass condition

### Acceptance Rule For This Prompt

A response generated from this prompt is acceptable only if:

- Sections 1-11 are all present.
- The Traceability Matrix contains no unexplained `PARTIAL`/`FAIL`.
- The Verification Checklist is executable without rewriting.
- The Release Readiness Verdict is explicit and justified.
