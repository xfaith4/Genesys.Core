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
- Verified current config now resolves OutputRoot to the local `GenesysConversationAnalysis/runs` directory and the Core/catalog/schema paths to the repo paths.
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

## 2026-04-21

- Implemented Session 19 quality overlay in ConversationAnalyser.
- Added `Get-QualityOverlayReport` to the Core adapter with case-agent evaluation fan-out, survey pull, topic definitions, and transcript topic aggregates.
- Bumped the case-store schema to v11 with `report_evaluations`, `report_surveys`, and `report_quality_topics`.
- Added quality import/accessor helpers for KPI summary, per-agent score distribution, per-queue survey distribution, low-score conversation drillthrough, topic overlays, and correlation summaries.
- Added the new "Quality" tab and UI handlers for background pull, local rendering, and low-score conversation drillthrough.
- Updated compliance/architecture tests and reran `apps/ConversationAnalyser/tests/Invoke-AllTests.ps1`: 234 PASS / 0 FAIL / 1 SKIP. DB runtime still skips in WSL because native `e_sqlite3` is absent.

## 2026-04-30

- Evaluated the current roadmap and found the next logical phase is Release 1.0 Track B follow-up for Agent Investigation, not another ConversationAnalyser session.
- Ran `pwsh -NoProfile -File scripts/Invoke-Tests.ps1 -Path tests/unit -IncludeIntegration -Output Detailed`; unit tests passed but Agent Investigation integration initially failed on scalar/empty-array handling and the `-UserName` mock.
- Hardened `Invoke-Investigation` to preserve empty arrays after deterministic sorting, fixed scalar-safe queue/conversation subject filters, and corrected `joinPlan.leftSource` to identify the source step.
- Strengthened `tests/integration/AgentInvestigation.Tests.ps1` with a join-plan assertion and repaired the name-resolution mock.
- Updated `README.md`, `docs/ONBOARDING.md`, `docs/training/Training.md`, `docs/ROADMAP.md`, `docs/READINESS_REVIEW.md`, and `docs/CHANGELOG.md` after validation.
- Final validation passed: parser checks for `modules/Genesys.Ops/Genesys.Ops.psm1` and `tests/integration/AgentInvestigation.Tests.ps1`; `scripts/Invoke-Tests.ps1 -Path tests/unit -IncludeIntegration -Output Normal` passed 105 unit tests and 12 integration tests.

## 2026-05-07

- Reviewed the new conversation investigation package workflow and sample package artifacts.
- Hardened package generation so timestamped SIP trace messages contribute `ObservedTimeUtc` to the SIP CSV and chronological combined timeline; conversation timeline rows are now sorted and sequence-renumbered after combining with SIP evidence.
- Updated the package fixture test and demo script to use timestamped SIP traces, then regenerated `samples/demo-conversation-investigation`.
- Validation passed: parser checks for package-related PowerShell files; `Invoke-Pester -Path ./tests/integration/ConversationInvestigationPackage.Tests.ps1 -Output Normal` passed 6 tests; `pwsh -NoProfile -File scripts/Invoke-Tests.ps1` passed 142 tests and skipped live integration because no Genesys credentials were present.

- Hardened the live conversation package workflow so `Export-GenesysConversationInvestigationPackage` no longer needs `-SipTracePath` for live use. It now queries SIP metadata, requests the PCAP export, polls for the signed URL, writes the `.pcap`, and includes PCAP metadata in CSV/XLSX/JSON outputs.
- Updated `Get-GenesysConversationInvestigation` to run `conversations.get.specific.conversation.details` first and derive the required `analytics-conversation-details-query` interval from the conversation start/end times.
- Added `docs/CONVERSATION_INVESTIGATION_PACKAGE.md` with the exact live command, API sequence, package outputs, and telephony PCAP permissions.
- Regenerated `samples/demo-conversation-investigation` with `.pcap` and `.pcap-metadata.csv`; package JSON now shows `pcapDownloadId`, `PcapDownloaded = true`, 3 SIP messages, and 3 PCAP metadata rows.
- Validation passed: parser checks for package-related PowerShell files; `ConversationInvestigation.Tests.ps1` passed 17 tests; `ConversationInvestigationPackage.Tests.ps1` passed 7 tests; `pwsh -NoProfile -File scripts/Invoke-Tests.ps1` passed 142 tests.

## 2026-05-12

- Evaluated the roadmap after the conversation package work and chose the next actionable local phase: Session 20 backend foundation for ConversationAnalyzer trend reporting.
- Added `Get-TrendReport` to `App.CoreAdapter.psm1` so the app can pull queue-performance, abandon, and service-level aggregates for two comparison windows without breaking the Core boundary.
- Bumped the case-store schema to v12 and added `report_trend_windows`, `report_trend_comparison`, and the `report_trend_delta` view in `App.Database.psm1`.
- Added `Import-TrendReport`, `Get-TrendComparisonRows`, `Get-TrendChangeLeaders`, `Get-IncidentImpactSummary`, and `Export-IncidentImpactSummary` to establish the comparative-reporting/query/export layer before the WPF tab is wired.
- Extended `apps/ConversationAnalyzer/tests/Invoke-AllTests.ps1` with trend-report architecture checks.
- Validation passed for parser checks on `App.CoreAdapter.psm1` and `App.Database.psm1`, and the static/architecture portions of `apps/ConversationAnalyzer/tests/Invoke-AllTests.ps1` passed with the new trend checks.
- Full `Invoke-AllTests.ps1` currently still fails 11 existing DB runtime smoke checks (`SMK-11` through `SMK-19`); the new trend-report checks passed and the failing cases are outside this Session 20 backend slice.

## 2026-05-13

- Verified the existing Session 20 WPF Trend UI changes before advancing: `apps/ConversationAnalyzer/tests/Invoke-AllTests.ps1` passed 268 PASS / 0 FAIL / 2 SKIP. The skips are the local WSL `e_sqlite3` native-library blocker for database runtime smoke checks.
- Completed the next Release 1.3 roadmap slice: Edge Alarms & Event Feed.
- Added Edge log-job catalog datasets for create/status/upload-request flows and exported `Get-GenesysEdgeEvent` from `Genesys.Ops`.
- `Get-GenesysEdgeEvent` now returns a flat NOC feed over Edge offline/state concerns, trunk state concerns, active alerts, collector failures, and optional Edge log-job status via `telephony.get.edge.logs.job`.
- Added unit coverage for the NOC feed contract, Edge log-job parameter forwarding, and the required `EdgeId` guard for `-LogJobId`.
- Validation passed: catalog JSON parse, `Assert-Catalog`, parser checks for `Genesys.Ops.psm1` and `GenesysOps.Hardening.Tests.ps1`, `Invoke-Pester tests/unit/GenesysOps.Hardening.Tests.ps1` (40 PASS), and `scripts/Invoke-Tests.ps1 -Path tests/unit -IncludeIntegration -Output Normal` (157 unit PASS; 57 integration PASS / 1 SKIP for live catalog credentials).
- Reviewed and hardened MonthlyMetrics for the recurring previous-month reporting workflow.
- Added workbook outputs for monthly totals by `originatingDirection`, `mediaType`, and `messageType`, plus peak concurrent voice inbound/outbound from `oConcurrent` buckets.
- Fixed the previous-month default year for January runs, switched conversation detail grouping from `direction` to `originatingDirection`, added messageType fallback handling, and hardened optional API response/page property access under strict mode.
- Validation passed: parser checks for `apps/MonthlyMetrics/Get-GenesysMonthlyMetrics.ps1` and `tests/unit/MonthlyMetrics.Script.Tests.ps1`; `Invoke-Pester -Path ./tests/unit/MonthlyMetrics.Script.Tests.ps1 -Output Normal` passed 5 tests; `scripts/Invoke-Tests.ps1 -Path tests/unit -Output Normal` passed 162 tests and skipped integration because no live Genesys credentials were present.
- Investigated a ConversationAnalyzer post-run display issue. Confirmed saved conversation detail artifacts exist under `/mnt/c/Users/benfu/AppData/Local/GenesysConversationAnalysis/runs/.../data` and the newest demo run indexes to 3 conversations/display rows.
- Hardened the UI to show the exact run folder and data folder after run discovery/completion, and to clear stale conversation-grid filters when a completed run has indexed conversations but the current UI filters hide every row.
- Validation passed: parser checks for `App.UI.ps1`, `App.Index.psm1`, `Invoke-AllTests.ps1`, and `Test-Compliance.ps1`; `apps/ConversationAnalyzer/tests/Invoke-AllTests.ps1` passed 270 checks, 0 failed, 2 skipped for missing WSL `e_sqlite3`.
