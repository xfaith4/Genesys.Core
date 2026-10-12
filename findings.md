# ConversationAnalyser Reporting Findings

## Current Session

- No prior task_plan.md, progress.md, or findings.md existed in the repo root.
- Worktree already contains many modified files; changes must stay scoped to the requested phase.
- `apps/AuditLogsConsole/App.Database.psm1` does not exist; the Session 15/16 report pattern is in `apps/ConversationAnalyser/modules/App.Database.psm1` and companion ConversationAnalyser files.
- `apps/ConversationAnalyser/modules/App.Database.psm1` already has `$script:SchemaVersion = 7`, v7 `report_transfer_flows` and `report_transfer_chains` DDL/indexes, `Import-TransferReport`, `Get-TransferFlowRows`, `Get-TransferChainRows`, `Get-TransferSummary`, and exports.
- `apps/ConversationAnalyser/modules/App.CoreAdapter.psm1` already has `Get-TransferReport` following the Session 14/15 report folder-map pattern.
- Catalog `analytics.query.conversation.aggregates.transfer.metrics` emits `nTransferred`, `nBlindTransferred`, `nConsultTransferred`, and `nConnected`; the import denominator now prefers `nOffered` when available, then `nConnected`, then `nTransferred`.
- Hardening review found name-only transfer touches could collapse into one flow bucket because aggregation row keys used only queue IDs. Flow aggregation now keys by queue ID when present, otherwise by the stable sequence key (`name:<queueName>`).
- Session 16 UI follows Session 14/15 report patterns: background CoreAdapter pull, main-runspace database import, grid render from public database accessors, and no direct `Invoke-Dataset` call from UI.
- Multi-hop transfer chain clicks force database drilldown mode and select the existing drilldown tab so operators land on the stored conversation segment view.
- Code review found stale report-tab state when the case store goes offline or no active case exists; Transfer and Flow report grids now clear in those paths.
- Session 17 follows the same report architecture: CoreAdapter owns dataset pulls, Database owns schema/import/accessors/correlation, UI owns background job orchestration and rendering only.
- Flow containment summary rates should be weighted by `n_flow` entries rather than an unweighted average of per-flow percentages; the summary accessor now computes weighted containment and failure rates.
- Flow-to-queue correlation needs to tolerate flow IDs/names appearing at participant, session, or segment level in stored conversation details; the accessor now checks all three levels before counting reached queues.
- The environment still lacks the native SQLite `e_sqlite3` library, so database runtime smoke remains skipped while static/database code paths are covered by parse and architecture tests.
- Conversation display output path: `Invoke-Dataset` writes runs under `<OutputRoot>/<DatasetKey>/<RunId>/`, with details data in `data/*.jsonl`, diagnostics in `events.jsonl`, and API call logs in `api-calls.log`.
- The persisted config at `%LOCALAPPDATA%\GenesysConversationAnalysis\config.json` contained Windows absolute paths and backslash relative paths. In the WSL/Linux runtime, `[System.IO.Path]::IsPathRooted('C:\...')` returned false, so the app built malformed app-relative paths like `<app>/C:\Users\...`.
- The UI polling path could discover a completed older run while the new run was still executing, then keep that folder for display because completion only recovered `.runFolder` when `CurrentRunFolder` was null. Completed runs now override with the returned run context folder.
- The full conversation-details run uses the async analytics job path. Async state comparison was case-sensitive and the dataset-specific profile ignored the longer catalog-style polling window; both were hardened to reduce false timeouts before result retrieval.
- Local artifact search found no real run folders under the local `GenesysConversationAnalysis` data directory; only `config.json` and `cases.sqlite` were present, so the no-display symptom could not be reproduced from existing run artifacts.

## Product-Purpose Reorientation Findings

- Existing planning files are from reporting sessions; this work extends them for the investigation-workbench reorientation.
- `App.Reporting.psm1` currently builds `New-ImpactReport` from an object array named `FilteredIndex`, which is appropriate for index mode but not sufficient for DB mode full-population reporting.
- `_GenerateImpactReport` in `App.UI.ps1` currently calls `New-ImpactReport -FilteredIndex @($script:State.CurrentIndex)`, so DB-mode reports can be page/buffer dependent rather than full filtered SQL result dependent.
- `_SaveImpactReportSnapshot` saves only the report content; it does not explicitly wrap the exact canonical filter state used for generation.
- DB grid path currently calls `Get-ConversationsPage` and then applies `ColumnFilters` locally in UI after fetching the page. This can make count/page count/visible rows disagree.
- DB drilldown currently reconstructs primary detail from `participants_json`; there is no separate canonical raw conversation payload column or lineage/version table visible in the current schema search.

## Core Contract Fixture Hardening Findings

- Core run artifacts are created by `modules/Genesys.Core/Private/RunArtifacts.ps1`: `New-RunContext` writes `out/<datasetKey>/<runId>/` with `manifest.json`, `events.jsonl`, `summary.json`, `api-calls.log`, and `data/`.
- Conversation details Core output writes `data/analytics-conversation-details.jsonl`; preview/query output writes `data/analytics-conversation-details-query.jsonl`.
- Core manifest shape is camelCase: `datasetKey`, `runId`, `startedAtUtc`, `endedAtUtc`, `counts.itemCount`, `warnings`. It does not currently emit `schema_version` or `normalization_version`.
- Core conversation summary shape includes `datasetKey`, `runId`, `totals.totalConversations`, and `generatedAtUtc` for conversation details.
- Current Analyzer importer tolerates missing schema/normalization version and accepts both snake_case and camelCase dataset/run fields, but it does not yet reconcile `manifest.counts.itemCount` or `summary.totals.totalConversations` against parsed/imported records.
- Existing Pester Core tests generate real Core-shaped run folders via `Invoke-Dataset` with `RequestInvoker`; these are better contract fixtures than the app-local `New-SmokeRunFolder` helper.

- `Invoke-SmokeTests.ps1` now creates a Core-produced `analytics-conversation-details-query` fixture through `Genesys.Core Invoke-Dataset` and a mocked request invoker, then validates Analyzer contract/index/display behavior against the actual Core artifact layout.
- Core fixture validation passes without SQLite: Analyzer validates `manifest.counts.itemCount`, `summary.totals.totalRecords`, `data/analytics-conversation-details-query.jsonl`, required `conversationId`, and can build/render index display rows from the Core-written JSONL.
- Database import runtime tests still skip in WSL due missing native `e_sqlite3`, but the new DB import test will import the Core-produced fixture and reconcile expected/data/imported counts when SQLite is available.

## Conversation Investigation Package Review

- `Export-GenesysConversationInvestigationPackage` builds the expected package set from an existing investigation run folder or by running `Get-GenesysConversationInvestigation` directly: HTML, timeline CSV, SIP trace CSV, findings CSV, XLSX, and package JSON.
- Initial sample review found a practical timeline clarity issue: conversation rows could appear out of chronological order because participant/session traversal order drove sequence, and SIP rows had blank `TimeUtc` values unless timestamps were recovered from the trace.
- The package hardening now parses common ISO/date-time prefixes from SIP message start lines, preserves `ObservedTimeUtc` and `RawTimestamp` in the SIP CSV, strips the timestamp before SIP method/response classification, normalizes conversation end details to UTC text, sorts the combined timeline by available UTC time, and renumbers sequence values after sorting.
- Live conversation packaging must not require a manually supplied SIP trace path. The current workflow now gets the seed conversation first through `conversations.get.specific.conversation.details`, derives `<start>/<end>` for the required analytics details query interval, then exports SIP metadata and a `.pcap` through the telephony SIP trace APIs.
- The package now records PCAP evidence explicitly: `.pcap`, `.pcap-metadata.csv`, workbook `PCAP Metadata` sheet, package JSON `pcapDownloadId`, warning list, PCAP file references, and counts for SIP metadata rows.
- PowerShell download hooks can emit byte arrays as enumerated byte objects. The binary save helper now writes both direct `[byte[]]` results and enumerated byte arrays so fixture/demo package generation does not fall through to the signed URL.

## 2026-09-15 Reconciliation findings

- HEAD 705a1d6 has one local commit; unfinished merge targets 77b1ad9. Fresh origin/main is 65e39c5.
- Semantic comparison against merge target shows no unique local application logic; differences are conflicted README/editor settings and generated mock build metadata. Most unstaged changes are CRLF-only.
- Latest GitHub adds React/TypeScript GenesysDataClient and mock OAuth/metadata capabilities absent locally. Root ROADMAP.md contains unrelated SereneHarmony boilerplate and requires correction.

### Source-backed review and validation

- Consolidated 25 recent reference recipe updates, held 9 updates with unresolved catalog references, and preserved original deltas. Recipes explicitly remain reference-only. No new unvalidated runtime datasets enabled.
- Confirmed official Open Messaging deprecation notice removes catch-all inbound endpoint on 2026-10-05; corrected active guidance and unverified provider-call injection claims.
- Unit baseline: 204 passed / 1 skipped (swagger unavailable); integrations after Linux portability fix: 74 passed / 1 live skip; .NET mock server 38 passed; Analyzer 272 passed / 2 SQLite skips.
- npm major upgrade initially failed against the old lock; regenerated the lock from the aligned Node 24/Vite 8/Vitest 5/plugin-react 6 package manifest without peer overrides.
- New combination reference guard identified the pre-existing literal (derived) placeholder; explicitly excluded that non-endpoint marker.

## Adaptive pacing findings

Core retries individual calls but retains no pacing history. Both HTTP and injected invokers converge on Invoke-WithRetry. Catalog endpoint keys are carried through pagination. Existing Retry-After is capped and can be shortened by jitter; correct this to a minimum wait. Learn within the loaded module session; run events retain durable 429 evidence. Shared server cooldown conservatively accounts for broader limits.

Adaptive policy: method/catalog key/server identity; exponential endpoint interval (1–60s); 10% recovery after 20 successes; shared server cooldown. Retry-After honored without cap/negative jitter. Immediate per-run rate-limits.jsonl preserves observations on failed runs. State remains session-only; no process/runspace/browser coordination.

## Browser demo audit

Node 24.11.1 is installed under ~/.nvm; default Node is 20.20.2. Native Windows .NET SDK 8.0.425 is available; Linux dotnet is absent from PATH. Browser artifacts will use output/playwright/.

Demo startup: Windows mock server is running; WSL localhost cannot reach Windows loopback. Linux Vite startup failed because node_modules contains Windows rolldown bindings; native Windows Node 24.13.1 starts Vite successfully. Establishing browser connectivity without replacing the existing dependency tree.

Windows Vite on port 5174 is reachable from WSL via 172.31.144.1. A temporary TCP forward exposes it at WSL localhost:5173 (including websockets) to preserve secure-context PKCE behavior. Browser uses installed Chromium 1243 in headed mode. These are local environment adaptations, not product modifications.

Browser observations: PKCE sign-in/consent succeeds; Users retrieves 10 records over two pages and local Alice search filters correctly. Favicon returns 404. Genesys header search advertises people/groups but only searches page navigation; Alice yields no feedback. Help, Collaborate and Inbox buttons have no actions; queue toggle changes only local presentation. Default skin hides reports/exports; investigating Atlas flow before deciding scope.

Additional reproduced issues: report metric default Average on Skills #, switched field to Name; dropdown displays Count but report header remains Average of Name and its cell is empty. At 390px, CSS permanently hides both skins’ navigation labels regardless of expansion control. Atlas has no page overflow, but an unlabeled marker-only rail cannot be visibly expanded. The skin switch also remounts reports.

Endpoint discovery normal path: filtering to /api/v2/users/me, opening details, and Run request succeeds with HTTP 200. Injected HTTP 503 on discovery list: changing search to routing/queues silently leaves users/me results and old count displayed, without an error or retry affordance. Request detail remains stale too. This is a controlled browser fault injection, not a real server outage.

Downloaded JSON exposed another evidence defect: filtered record JSON omits filter summary; report JSON omits collection metadata/warnings, active filters, metric definitions and filtered population. Corrected JSON serialization and added three meaningful export-fidelity regressions. Existing first Data Client run passed all 75 tests against the running mock.

Standalone conversation investigation HTML opened through localhost:8787 and visually inspected: summary, findings, chronological conversation/SIP timeline, SIP breakdown, evidence sections render. The temporary generic Python sample server requests an absent /favicon.ico (cosmetic server-only 404); the corrected Data Client itself has no favicon error.

Standalone report issue: the 25-column SIP breakdown and long evidence JSON force page-level horizontal overflow even at desktop width. Corrected the report generator and the supplied example with named, keyboard-focusable table scrolling regions; retained all sample data and timestamps. Added modest narrow-screen padding and header wrapping.

## Monthly volume reconciliation findings

Four endpoint families are cataloged. Aggregate job submission/results currently lack async/cursor profiles. Detail body paging writes a top-level pageNumber despite the catalog's nested paging request, risking duplicate pages. These need collection-level regression tests before monthly totals are trusted. Existing worktree changes are preserved.

Core integration revealed the queue-performance aggregate dataset incorrectly used detail body paging: it repeated the same aggregate request until the 1000-page cap. Corrected that dataset and endpoint to single-response paging; other aggregate aliases require a separate catalog audit. Async submit/status requests also emit paging.progress, so report page counts now select result cursor pages rather than counting job-control responses as result pages. Fixed PowerShell empty-array unrolling in optional scope filters after focused tests caught it.

## Supplied ConversationAnalysis.ps1 reference

Inspected /mnt/f/Development/20_Staging/GenesysCloud/ConversationAnalyser/src/analysis/ConversationAnalysis.ps1, especially Get-ConversationProfile, constants, flat columns and report aggregation. Pure PS5.1-compatible extraction captures chronological queue/engaged-agent paths, all segment errors, SIP/Q850, routing/skills/languages/flows, media endpoint minimum MOS/maximum latency/codecs, work metric sums with agent-only ownership, outcome flags and quality/survey fields. It assumes absent properties are null (not StrictMode-safe). Adapt into Ops with local property tolerance, remove exported PII fields by default, preserve nullable absent metrics and source provenance. Current Ops Get-GenesysConversationDetail already has interval/queue/user/Division filters; web client must consume Ops results, not copy collection logic. Existing ConversationAnalysis app supports raw JSONL but has narrower profile calculations; new focused workbench will consume versioned Ops population artifacts.

Browser validation verified 120-conversation full-population mean handle time 60.5 seconds and max 120; filtering >100 seconds gives 20 conversations and mean 110.5. Downloaded JSON and CSV both contain all 20 filtered records with original scope/coverage and filter metadata. Error drill-through selects 30 conversations while counting 60 error segments. Initial mobile test found CSS grid minimum-content sizing overflow; changed the breakdown grid to minmax(0,1fr) and child min-width:0. Static analyzer does not recognize implicit wrapping labels, so explicit label-for associations were added for consistent static and runtime accessibility checks.

Data Client route reuses the portable template and engine via Vite raw imports. Browser caught sandbox form submission blocked without allow-forms; enabled forms while keeping opaque origin and no parent session access. Snapshot bridge captures renderGrid to include pagination/columns as well as filters. Linux build lacked optional rolldown native dependency; use native Windows Node 24 against existing Windows dependencies. First build invoked npm at repo root and a later edit used app cwd with root-relative path; both corrected without collateral edits. Windows npm shim also exited silently; invoke native Node tool entrypoints directly.

Final browser verification confirmed full filtered-population statistics remain faithful inside the client. State survives route unmounts and both skin remounts; the data bundle is posted only when changed rather than copied on every filter update. Production bundle includes the shared frontend through raw imports; no copied profiler, HTTP collector, or extra server was introduced. Extended CI-rendered accessibility covers both shell and opaque frame directly, synthetic loaded profiles, dialog, mobile and navigation/skin persistence. Full gate: 21 surfaces, zero violations.

Entity labels and scale: log rules now exempt curated samples/** and tests/fixtures/** logs; tracked evidence is not removed. Implemented run-scoped entity lookup for queue/user/Division/wrap-up/skill/language catalog datasets, one traversal per referenced family, stable IDs plus labels, duplicate-name ID grouping, explicit unresolved/partial/access-denied coverage. Core test exposed conversation userId heuristic redaction preventing directory joins; added opt-in catalog identity profile preserving only userId identifiers while keeping contact/secret redaction. No NoRedact bypass. Names remain current directory labels, not historical identity proof. 50k baseline engine repeated search 282ms; cached version 14.8ms, heap 99 to108MiB on this machine. First search still pays index creation. Capped initial breakdown DOM to100 with show-more; exports remain complete. Six family lookups and dictionary joins avoid per-conversation HTTP. Profile JSONL now uses one StreamWriter rather than reopening the file for every record.


User clarified Data Client is the operations culmination of OpsConsole/GenesysInterrogator/ConversationAnalyzer, with composed datasets and evidence-based NOC findings taking priority over raw endpoint calls. Updated onboarding, navigation and roadmap accordingly. Current directory membership is now joined separately as UserDivisionIds/AgentDivisionIds with independent missing-member coverage; it is not historical membership. Added FlowIds and sanitized endpoint packet observations with sample counts and explicit aggregation grain; official SDK documents discarded includes overrun/underrun, so no invented loss percentage or double addition. Mass-disconnect composer, incident/baseline queue joins, historical NOT_RESPONDING and audit changes remain open in docs/NOC_INCIDENT_INVESTIGATIONS.md. Performance evidence covers50k15-field browser rows and20k99-field full Ops rows;100k was engine-only. Initial search, in-memory parsing and4.6s large-skin restore remain disclosed limits. Demo/fixture logs can be committed; existing tracked logs were preserved.
