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
- Local artifact search found no real run folders under `/mnt/c/Users/benfu/AppData/Local/GenesysConversationAnalysis`; only `config.json` and `cases.sqlite` were present, so the no-display symptom could not be reproduced from existing run artifacts.

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
