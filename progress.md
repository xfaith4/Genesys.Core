# ConversationAnalyser Reporting Progress

## 2026-04-17

- Initialized planning files for the Transfer Report final development phase.
- Started with Step 2: schema v7, Import-TransferReport, and accessors.
- Inspected report patterns in ConversationAnalyser; confirmed Step 2 code is present and now needs validation/fixup rather than duplicate implementation.
- Updated `Import-TransferReport` denominator handling to match the transfer metrics catalog (`nConnected`, `nTransferred`) while retaining `nOffered` support.
- Verified parser checks for `App.Database.psm1`, `App.CoreAdapter.psm1`, `App.UI.ps1`, and `MainWindow.xaml`.
- Ran `pwsh -NoProfile -File apps/ConversationAnalyser/tests/Invoke-AllTests.ps1`: 159 PASS, 0 FAIL, 1 SKIP (`e_sqlite3` native library absent for database smoke).
- Updated `docs/CHANGELOG.md` and `docs/ROADMAP.md` to record Session 16 database foundation progress.
- Ran `git diff --check` on touched files; output is dominated by existing CRLF/trailing-whitespace noise from large modified files, so it was not actionable for this scoped phase.
- Started review/hardening pass for recent Session 16 changes, followed by the next roadmap release slice: Transfer & Escalation UI wiring.
- Hardened `Import-TransferReport` flow aggregation so name-only queue touches do not collapse into the same empty-ID flow row.
- Added the ConversationAnalyser "Transfer & Escalation" tab with transfer type filter, summary labels, flow grid, top destination grid, and multi-hop chain grid.
- Added UI handlers `_StartTransferReportJob`, `_RenderTransferGrid`, and `_OpenTransferChainConversation`; multi-hop chain selection opens the existing drilldown tab.
- Added Transfer-specific compliance and architecture checks to `Test-Compliance.ps1` and `Invoke-AllTests.ps1`.
- Verified parser checks for changed PowerShell files and XML parse for `MainWindow.xaml`.
- Ran `pwsh -NoProfile -File apps/ConversationAnalyser/tests/Invoke-AllTests.ps1`: 179 PASS, 0 FAIL, 1 SKIP (`e_sqlite3` native library absent for database smoke).
- Updated `docs/CHANGELOG.md`, `docs/ROADMAP.md`, and `apps/ConversationAnalyser/docs/ConversationAnalytics_Roadmap.md`; Session 16 is now marked delivered.
- Reviewed the recent reporting changes and hardened stale-state handling so Transfer and Flow report grids clear when the case store is offline or no active case is selected.
- Added `Get-FlowContainmentReport` to `App.CoreAdapter.psm1` for flow aggregate and flow reference dataset pulls.
- Bumped database schema to v8 with `report_flow_perf` and `report_flow_milestone_distribution`.
- Added `Import-FlowContainmentReport`, flow row/milestone/summary accessors, and flow-to-queue correlation from stored conversation detail.
- Added the ConversationAnalyser "Flow & IVR" tab with Pull Report, flow-type filter, summary labels, flow performance grid, milestone grid, and queues-reached grid.
- Added UI handlers `_StartFlowContainmentReportJob`, `_RenderFlowContainmentGrid`, and `_RenderSelectedFlowDetail`.
- Added Flow-specific compliance and architecture checks to `Test-Compliance.ps1` and `Invoke-AllTests.ps1`.
- Verified parser checks for CoreAdapter, Database, UI, and tests; verified XML parse for `MainWindow.xaml`; `git diff --check` is clean on touched files.
- Ran `pwsh -NoProfile -File apps/ConversationAnalyser/tests/Invoke-AllTests.ps1`: 196 PASS, 0 FAIL, 1 SKIP (`e_sqlite3` native library absent for database smoke).
- Updated `docs/CHANGELOG.md`, `docs/ROADMAP.md`, and `apps/ConversationAnalyser/docs/ConversationAnalytics_Roadmap.md`; Session 17 is now marked delivered.
- Investigated the ConversationAnalyser run output path and found persisted Windows-style config paths were resolving incorrectly under WSL/Linux, e.g. `C:\Users\...` became app-relative instead of `/mnt/c/Users/...`.
- Hardened `App.Config.psm1` and `Invoke-Dataset.ps1` path normalization for Windows drive paths and backslash relative paths.
- Hardened `App.UI.ps1` background run polling so in-progress diagnostics use the new run folder and completed display always prefers the returned run context `.runFolder` over any folder discovered while polling.
- Hardened async job polling so terminal/success state comparisons are case-insensitive, and the analytics conversation-details job uses a longer 300-poll profile with common success-state aliases.
- Added smoke coverage for Windows-style persisted config paths and unit coverage for lower-case async terminal states.
- Verified current config now resolves OutputRoot to `/mnt/c/Users/benfu/AppData/Local/GenesysConversationAnalysis/runs` and the Core/catalog/schema paths to the repo paths.
- Verified parser checks, `Invoke-AllTests.ps1` (196 PASS, 0 FAIL, 1 SKIP), `Invoke-Pester tests/unit/AsyncJob.Engine.Tests.ps1` (3 PASS), and scoped `git diff --check`.

## 2026-04-19

- Started product-purpose reorientation work for ConversationAnalyser as a Core-backed investigation workbench.
- Restored existing planning context and extended `task_plan.md` with a new P0/P1 foundation phase.
- Initial inspection found DB-mode impact reports still generated from the UI current index/page-shaped buffer, snapshots lacking explicit filter-state wrapping, DB column filters applied page-locally, and DB drilldown relying on reconstructed participant JSON rather than canonical raw payload storage.

- Implemented first v10 workbench foundation pass in `App.Database.psm1`: canonical SQL filter helper, raw payload/hash fields, conversation lineage, bridge-table DDL, derived analytic columns, SQL-backed column filters, population/facet/representative/cohort helpers.
- Updated UI/reporting path so DB-mode impact generation is a full filtered-population report with exact filter state instead of the current page buffer, and DB drilldown prefers canonical raw JSON.

- Added smoke/static coverage for page-independent DB reports, SQL-backed column filters, raw JSON drilldown storage, lineage preservation, saved-view filter restoration, and analytics helper responsiveness.
- Updated ConversationAnalyser README to describe the workbench purpose, Core boundary, canonical filters, lineage, and explicit report types.

- Final verification after saved-view restore and line-ending cleanup: `Invoke-AllTests.ps1` passed 222 PASS / 0 FAIL / 1 SKIP; DB runtime smoke remains skipped because native `e_sqlite3` is absent in this WSL environment. `git diff --check` is clean on touched files.

- Completed the product-purpose reorientation foundation phase in `task_plan.md`. Saved-view restore is now wired by double-clicking a saved view in Case Manager, applying its canonical filter state and refreshing the grid from that exact scope.

- Started Core contract fixture hardening phase. Session catchup script reported Codex session parsing is not implemented, so current plan/findings/progress plus git state are the source of continuity.

- Added Analyzer Core contract validation: manifest/summary identity checks, expected count reconciliation, JSONL parse checks, required conversationId validation, and pre-import/post-import enforcement. Added smoke fixture generation using `Genesys.Core Invoke-Dataset` with a mocked request invoker.

- Ran `Invoke-SmokeTests.ps1`: Core-produced fixture tests passed (`SMK-09A/B/C`); DB runtime section still skipped due missing native `e_sqlite3`.

- Ran full `apps/ConversationAnalyser/tests/Invoke-AllTests.ps1`: 228 PASS / 0 FAIL / 1 SKIP. The new Core-generated fixture tests pass; DB runtime still skips in WSL due missing native `e_sqlite3`.

- Cleaned importer doc line endings, reran parser checks for touched PowerShell files, and reran scoped `git diff --check`; both passed. Marked Core contract fixture hardening complete in `task_plan.md`.
