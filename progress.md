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
