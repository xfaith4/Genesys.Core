# Changelog

## 2026-04-14

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

