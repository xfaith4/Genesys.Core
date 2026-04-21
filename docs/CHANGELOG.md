# Changelog

## 2026-04-21

### Added

- **ConversationAnalyser Session 19 — Quality and Voice-of-Customer Overlay:**
  - `Get-QualityOverlayReport` added to `App.CoreAdapter.psm1` — pulls `quality.get.evaluations.query` (fan-out by case agent), `quality.get.surveys`, `speechandtextanalytics.get.topics`, and `analytics.post.transcripts.aggregates.query` into a `report-quality-<timestamp>` folder map.
  - Schema bumped to **v11** with `report_evaluations`, `report_surveys`, and `report_quality_topics` plus supporting indexes.
  - `Get-CaseAgentUserIds`, `Import-QualityOverlayReport`, `Get-QualitySummary`, `Get-QualityAgentScoreRows`, `Get-QualitySurveyQueueRows`, `Get-LowScoreConversationRows`, `Get-QualityCorrelationSummary`, and `Get-LowScoreTopicRows` added to `App.Database.psm1`.
  - Evaluation scores normalize to a 0–100 scale from available form totals; survey import extracts NPS, CSAT-style totals, and free-text verbatim answers; transcript topic overlays stay optional and local to the case store.
  - **"Quality" tab** added to `MainWindow.xaml`: Pull Report button, KPI summary bar, agent score distribution grid, queue survey grid, low-score conversation grid, correlation panel, and low-score topic grid.
  - `_StartQualityOverlayReportJob`, `_RenderQualityGrid`, and `_OpenLowScoreConversation` added to `App.UI.ps1`; low-score conversations drill into the existing conversation detail workspace.
  - Quality-specific compliance and architecture checks added to the ConversationAnalyser test runner.

## 2026-04-17

### Added

- **ConversationAnalyser Session 17 — IVR and Flow Containment Report:**
  - `Get-FlowContainmentReport` added to `App.CoreAdapter.psm1` — pulls `analytics.query.flow.aggregates.execution.metrics`, `flows.get.all.flows`, `flows.get.flow.outcomes`, and `flows.get.flow.milestones` into a report folder map.
  - Schema bumped to **v8** with `report_flow_perf` and `report_flow_milestone_distribution` plus supporting indexes.
  - `Import-FlowContainmentReport`, `Get-FlowPerfRows`, `Get-FlowMilestoneRows`, `Get-FlowContainmentSummary`, and `Get-FlowQueueRouteRows` added to `App.Database.psm1`.
  - Containment and failure summaries are weighted by flow entries; queue correlation reads already-imported conversation detail data without adding a frontend API path.
  - **"Flow & IVR" tab** added to `MainWindow.xaml`: Pull Report button, flow-type filter, summary bar, flow performance grid, milestone grid, and queues-reached grid.
  - `_StartFlowContainmentReportJob`, `_RenderFlowContainmentGrid`, and `_RenderSelectedFlowDetail` added to `App.UI.ps1`; Transfer and Flow tabs now clear stale rows when the case store is offline or no active case is selected.
  - Flow-specific compliance and architecture checks added to the ConversationAnalyser test runner.

- **ConversationAnalyser Session 16 — Transfer and Escalation Chain Intel:**
  - Schema bumped to **v7** with `report_transfer_flows` and `report_transfer_chains` plus supporting indexes.
  - `Import-TransferReport` added to `App.Database.psm1` — imports the transfer aggregate run folder, derives transfer chains from stored `participants_json`, classifies blind versus consult transfers, and upserts flow and chain rows.
  - `Get-TransferFlowRows`, `Get-TransferChainRows`, and `Get-TransferSummary` added for grid reads and summary roll-ups.
  - Transfer import denominator handling now matches the catalog-backed metrics: it supports `nOffered` when present, otherwise falls back to `nConnected`, then `nTransferred`, then local hop totals.
  - Hardened transfer flow aggregation so name-only queue touches use stable `name:<queueName>` row keys instead of collapsing into one empty-ID bucket.
  - **"Transfer & Escalation" tab** added to `MainWindow.xaml`: Pull Report button, blind/consult filter, summary bar, flow grid, top destination grid, and multi-hop conversation grid.
  - `_StartTransferReportJob`, `_RenderTransferGrid`, and `_OpenTransferChainConversation` added to `App.UI.ps1`; selecting a multi-hop conversation opens the existing drilldown view.
  - Transfer-specific compliance and architecture checks added to the ConversationAnalyser test runner.

## 2026-04-15

### Added

- **ConversationAnalyser Session 15 — Agent Performance Aggregate Report:**
  - `Get-AgentPerformanceReport` added to `App.CoreAdapter.psm1` — pulls `analytics.query.conversation.aggregates.agent.performance`, `analytics.query.user.aggregates.performance.metrics`, and `analytics.query.user.aggregates.login.activity` for the case time window and returns an `{AgentPerfFolder, UserPerfFolder, LoginActivityFolder}` hashtable.
  - `Import-AgentPerformanceReport` added to `App.Database.psm1` — merges the three JSONL outputs by `userId`, resolves user names, emails, departments, and division names from ref tables, resolves handled queue names from the conversations store, computes `talk_ratio_pct` (tTalk / tHandle × 100), `acw_ratio_pct` (tAcw / tHandle × 100), and `idle_ratio_pct` (tIdle / totalTime × 100), and upserts into `report_agent_perf`.
  - `Get-AgentPerfRows` and `Get-AgentPerfSummary` added to `App.Database.psm1` for grid reads and summary-bar roll-ups.
  - Schema bumped to **v6** — adds `report_agent_perf` table with three indexes.
  - **"Agent Performance" tab** added to `MainWindow.xaml`: header card with Pull Report button and Division filter, summary bar (Agents, Connected, Avg Handle, Avg Talk %, Avg ACW %, Avg Idle %), 16-column `DgAgentPerf` DataGrid with ⚠ flag column (talk ratio < 50 % or ACW ratio > 30 %).
  - `_StartAgentPerfReportJob`, `_RenderAgentPerfGrid`, `_PopulateAgentPerfDivisionFilter` added to `App.UI.ps1`; division filter repopulates from the database after each import and on case activation.


### Added

- **ConversationAnalyser Session 14 — Queue Performance Aggregate Report:**
  - `Get-QueuePerformanceReport` added to `App.CoreAdapter.psm1` — pulls `analytics.query.conversation.aggregates.queue.performance`, `analytics.query.conversation.aggregates.abandon.metrics`, and `analytics.query.queue.aggregates.service.level` for the case time window and returns a `{QueuePerfFolder, AbandonFolder, ServiceLevelFolder}` hashtable.
  - `Import-QueuePerformanceReport` added to `App.Database.psm1` — merges the three JSONL outputs by `queueId|intervalStart`, resolves queue and division names from ref tables, computes `abandon_rate_pct` and `service_level_pct`, and upserts into `report_queue_perf`.
  - `Get-QueuePerfRows` and `Get-QueuePerfSummary` added to `App.Database.psm1` for grid reads and summary-bar roll-ups.
  - Schema bumped to **v5** — adds `report_queue_perf` table with four indexes.
  - **"Queue Performance" tab** added to `MainWindow.xaml`: header card with Pull Report button and Division filter, summary bar (Queues, Offered, Abandoned, Avg Abandon %, Avg SLA 30s %, Avg Handle), 13-column `DgQueuePerf` DataGrid.
  - `_StartQueuePerfReportJob`, `_RenderQueuePerfGrid`, `_PopulateQueuePerfDivisionFilter` added to `App.UI.ps1`; division filter repopulates from the database after each import and on case activation.



### Added

- **Genesys.Ops — Phase 5 Ideas 27–30:** Four new composite cmdlets completing the Phase 5 Visibility Dashboard roadmap:
  - `Get-GenesysPeakHourLoad` — ranks queue+media intervals by volume or handle time to surface WFM scheduling gaps (PT1H granularity; PT15M documented as future direct catalog body override).
  - `Get-GenesysChangeAuditFeed` — risk-classified (HIGH/MEDIUM/LOW) feed of admin configuration changes from the audit log; enriches each event with a human-readable `Summary` and `Risk` field.
  - `Get-GenesysOutboundCampaignPerformance` — per-campaign KPI snapshot combining campaign configuration with dialer event dispositions (ConnectRate, NoAnswerRate, TotalAttempts, etc.).
  - `Get-GenesysFlowOutcomeKpiCorrelation` — correlates Architect flow aggregate execution metrics with org-wide CSAT scores and queue handle time to identify IVR self-service drop-off candidates.

- **ConversationAnalyser Session 13 — Reference Data Foundation:**
  - `Refresh-ReferenceData` added to `App.CoreAdapter.psm1` — invokes `Invoke-Dataset` for all nine reference datasets (`routing-queues`, `users`, `authorization.get.all.divisions`, `routing.get.all.wrapup.codes`, `routing.get.all.routing.skills`, `routing.get.all.languages`, `flows.get.all.flows`, `flows.get.flow.outcomes`, `flows.get.flow.milestones`) and returns a folder map.
  - `Import-ReferenceDataToCase` added to `App.Database.psm1` — upserts reference records into eight new reference tables scoped by `case_id` with `refreshed_at` timestamps; audits the refresh event.
  - `Get-ResolvedName` helper added to `App.Database.psm1` — pure SQLite ID→name lookup with `-Type` (queue, user, division, wrapupCode, skill, flow, flowOutcome, flowMilestone) and `-Id` parameters.
  - Schema v4 adds eight reference tables and their indexes to the SQLite case store.
  - "Refresh Reference Data" button added to the case management panel in `MainWindow.xaml`; wired via `_StartRefreshReferenceDataJob` in `App.UI.ps1` which runs the fetch in a background runspace and shows record counts in the status bar on completion.

### Changed

- `ROADMAP.md` — Phase 5 Ideas 27–30 marked ✅ Delivered with cmdlet names and notes.
- `ConversationAnalytics_Roadmap.md` — Session 13 marked **COMPLETE** with delivery summary.



### Changed

- Documentation modernization pass (Batch 1):
  - Updated `README.md` repository layout to match actual structure (added `Genesys.Auth`, `Genesys.Ops`, `apps/ConversationAnalysis`; corrected test paths to `tests/unit/`); removed non-doc "Topics to Add on GitHub" and "Alternative Names" sections; added cross-link to `TESTING.md`; fixed `AGENTS.md` reference path.
  - Updated `TESTING.md` test file paths from `tests/` to `tests/unit/`; corrected stale caveat about script-level parameter exposure; fixed `AGENTS.md` link.
  - Updated `docs/ONBOARDING.md` with Table of Contents and a new Conversation Analysis app section.
  - Rewrote `docs/REPO_SCHEMATIC.md` tree to match actual repository structure (removed phantom root shims, added `apps/`, `Public/Assert-Catalog.ps1`, `Http/`; added Conversation Analysis to Canonical Defaults).
  - Updated `docs/READINESS_REVIEW.md` to correct stale caveat about script-level `-Headers`/`-BaseUri` exposure.



### Changed

- Reconciled repository documentation with current runtime behavior and catalog coverage.
- Updated `README.md` to reflect current dataset/endpoint counts and clarified that the repo is a Core runtime (not a packaged MCP server).
- Added explicit onboarding guide at `docs/ONBOARDING.md` with authenticated module-first usage.
- Updated readiness review to reflect current implemented scope and current operational caveats.
- Updated roadmap status and added planned endpoint backlog:
  - `GET /api/v2/authorization/roles`
  - `GET /api/v2/conversations/{conversationId}/recordings`
  - `GET /api/v2/oauth/clients`
  - `POST /api/v2/oauth/clients/{clientId}/usage/query`
  - `GET /api/v2/oauth/clients/{clientId}/usage/query/results/{executionId}`
  - `GET /api/v2/speechandtextanalytics/topics`
  - `POST /api/v2/analytics/transcripts/aggregates/query`
  - `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/communications/{communicationId}/transcripturl`
- Updated testing documentation with onboarding references and current workflow/artifact/auth caveats.

## 2026-02-18

### Added

- Added dataset implementations for `users` and `routing-queues` with catalog registration, paging-aware ingestion, normalization, and tests.
- Added smoke script `scripts/Invoke-Smoke.ps1` to run catalog validation and fixture-backed dataset ingests.

### Changed

- Introduced unified catalog loader (`Resolve-Catalog`) and canonical in-memory normalization.
- Canonical runtime precedence is now `catalog/genesys.catalog.json`.
- Added strict catalog mode (`-StrictCatalog`) to fail when canonical catalog is missing.

### Migration notes

- Ensure the canonical catalog is present:
  - `catalog/genesys.catalog.json`
- Existing callers passing `-CatalogPath` remain supported.
