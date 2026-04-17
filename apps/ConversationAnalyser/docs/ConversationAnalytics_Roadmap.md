# Hardening Roadmap

## Purpose

This roadmap turns **Conversation Analyzer** into the reference implementation for a Core-backed Genesys desktop investigation tool.

The application is intended to be a **fast operator frontend** for pivoting through large amounts of conversation data over the course of an investigation, not a second API client and not a second normalization engine.

The target architecture is:

- **`Genesys.Core`** performs all Genesys Cloud extraction, async job handling, paging, retry, normalization, run manifests, and reusable analysis primitives.
- **A local embedded case database** stores structured Core outputs plus analyst-added investigative state for fast multi-day workflows.
- **The WPF frontend** drives acquisition, loads the local case database, enables rapid pivots, and produces exports and summaries.

## Non-Negotiable Architecture Guardrails

Scope: these guardrails apply to every session below and must be treated as acceptance criteria for the project, not optional design preferences.

Task: all conversation dataset extraction must flow through **`Genesys.Core`** public entry points such as `Invoke-Dataset` and related reusable module primitives.

Task: the WPF application must not own or duplicate direct Genesys Cloud extraction logic for conversation datasets, including async job submission, polling, paging, or retry behavior.

Task: reusable transformation or normalization logic discovered during this project must be implemented in `Genesys.Core`, not only in the frontend.

Task: the frontend may own only app-specific ingestion, local indexing, case workflow state, saved views, notes, findings, reporting, and UX-specific derived projections.

Task: all local storage must be retention-aware, purgeable, and attributable to a case and a Core run provenance record.

Validation: before each session is considered complete, confirm its implementation does not introduce a new script-local extraction path or duplicate canonical module logic.

Documentation: every repo document must describe the application as a **Core-backed frontend with a local case store**, not as an independent API analyzer.

## Current-State Reality Check

Scope: establish the factual starting point so the roadmap measures forward progress against reality rather than wishful thinking.

Task: treat the current script-local REST flow in `GenesysConvAnalyzer.ps1` as technical debt to be removed or isolated, not as the long-term foundation.

Task: treat the existing `Genesys.Core` module structure, dataset handlers, normalization pipeline, manifests, and event outputs as the canonical platform base to extend.

Task: treat the existing normalized JSONL outputs and analysis artifacts under `out-test*` as evidence that the module-first pattern is already partially present and should now be promoted into the frontend architecture.

Validation: capture a short current-state note in the repo describing what is still script-local today, what already exists in `Genesys.Core`, and what the first migration seam will be.

Documentation: update any stale wording that currently implies the script depends on `Genesys.Core` while still performing its own acquisition path.

## Session 1: Core-First Architecture Lock — **COMPLETE**

> **What was delivered:** `App.CoreAdapter.psm1` is the sole module that imports `Genesys.Core`, calls
> `Assert-Catalog`, and calls `Invoke-Dataset`. Gate A (startup), Gate B (run invocation), Gate D (import
> boundary), and Gate E (auth boundary) are all enforced. The compliance suite and architecture test suite
> (~92 checks total) verify these invariants on every run. No script-local extraction path exists.

Scope: establish the final architectural direction immediately so no further work hardens the wrong layer.

Task: rewrite the hardening target for the repo so the application is explicitly defined as a **frontend UX over `Genesys.Core` plus a local case database**.

Task: identify and document the exact script-local functions that currently duplicate module responsibilities and mark them as migration targets.

Task: define the first end-to-end module-backed path that must replace the current script-local acquisition flow.

Task: make `ModulePath` a real validated dependency at startup or remove any implication that it is already active.

Validation: confirm the repo contains an explicit statement that conversation extraction belongs to `Genesys.Core` and that no future session depends on expanding script-local extraction logic.

Documentation: update roadmap, repo notes, and inline commentary so they all reflect the same architecture with no mixed messaging.

## Session 2: Core Output Contract for Conversation Data — **COMPLETE**

> **What was delivered:** `App.CoreAdapter.psm1` formalizes the contract with `Get-RunManifest`,
> `Get-RunSummary`, `Get-RunEvents`, `Get-RunStatus`, and `Get-RecentRunFolders`. Two dataset keys are
> locked: preview (`analytics-conversation-details-query`) and full (`analytics-conversation-details`).
> The index module (`App.Index.psm1`) extracts the stable conversation entity shape
> (id, direction, mediaType, queue, disconnect, hasMos, hasHold, segmentCount, participantCount, durationSec)
> from Core-produced JSONL. Architecture tests ARCH-10 through ARCH-12 and ARCH-25 through ARCH-28 guard
> the artifact contract.

Scope: define the stable contract between `Genesys.Core` and Conversation Analyzer before more UI or storage work is added.

Task: document the expected `Invoke-Dataset` contract for the conversation dataset used by this application, including required inputs, output folder layout, manifest shape, summary shape, event files, and entity files.

Task: define the minimum stable conversation entities the frontend depends on, including conversations, participants, sessions, segments, metrics, and attributes.

Task: include provenance and compatibility fields such as `run_id`, dataset key, extraction window, schema version, normalization version, environment or org identifier, and generation timestamp.

Task: define how the frontend will detect and reject incompatible schema or normalization versions.

Validation: confirm a sample Core run can be validated against the documented contract using the existing normalized output artifacts already present in the repo.

Documentation: add a concise contract document and ensure the roadmap references that contract as the source of truth for importer and UI assumptions.

## Session 3: Module-Backed Acquisition Replaces Script-Local REST — **COMPLETE**

> **What was delivered:** `App.UI.ps1` starts preview and full runs by launching a background runspace
> that re-initializes `App.CoreAdapter.psm1` and calls `Start-PreviewRun` / `Start-FullRun`. The UI
> owns only parameter collection, progress polling (2-second DispatcherTimer), cancellation, and result
> loading. No direct `Invoke-RestMethod` calls exist for conversation data. Architecture tests ARCH-06
> through ARCH-09 enforce this boundary. The Run Console tab displays live events from `events.jsonl`
> during a run and the full diagnostics dump on completion.

Scope: remove the application's current role as a bespoke API client for conversation extraction.

Task: replace the existing script-local acquisition flow in `GenesysConvAnalyzer.ps1` with a module-backed call path using `Invoke-Dataset` and any required public module helpers.

Task: remove or isolate direct REST helpers related to conversation extraction so they cannot remain the default operational path.

Task: make the UI drive dataset input collection, request preview, submission intent, and job status display without owning the underlying transport behavior.

Task: preserve engineer visibility into what is being requested by exposing Core input parameters and emitted run metadata rather than raw duplicated request code.

Validation: run the same conversation query through the new module-backed path and confirm the produced run artifacts and record counts match expected Core behavior.

Documentation: update script synopsis, comments, and repo notes to state exactly which acquisition path is now active and what legacy code remains only as temporary migration scaffolding.

## Session 4: Local Embedded Case Database Foundation — **COMPLETE**

> **What was delivered:** `App.Database.psm1` now owns all SQLite interaction, DLL resolution,
> schema creation, case lifecycle primitives, Core run registration, import tracking, and conversation
> storage. `App.ps1` initializes the case store at startup (Gate F), and the UI surfaces case-store
> availability and active-case selection. SQLite is the default local case database and the schema can be
> recreated from scratch on a clean machine.

Scope: introduce the app's durable local workflow layer so investigators can work from structured data over multiple days without re-querying.

Task: adopt **SQLite** as the default embedded database for the application unless a proven technical blocker appears.

Task: define the initial schema around **cases**, **Core runs**, **dataset imports**, and the imported conversation entities needed for fast pivots.

Task: model the case lifecycle explicitly, including case creation, active investigation, refresh, export, closure, archive or purge, and expiry handling.

Task: ensure the database is treated as a **case-oriented analytical cache** rather than a source-of-truth warehouse.

Validation: create a schema v1 that can persist at least one imported normalized conversation run plus a case record and can be recreated from scratch on a clean machine.

Documentation: add a database design note describing why SQLite was chosen, what the case scope means, and what the database is intentionally not.

## Session 5: Core-to-Database Importer Pipeline — **COMPLETE**

> **What was delivered:** `Import-RunFolderToCase` validates the Core artifact contract
> (`manifest.json`, `summary.json`, `data/*.jsonl`), enforces supported dataset keys, rejects explicit
> schema/normalization major versions other than `1`, registers or refreshes the `core_runs` provenance
> row, and imports conversation rows into SQLite in batches within a single transaction. Re-importing the
> same case/run marks prior completed imports as `superseded`, deletes prior conversation rows for that
> case/run, and replaces them with the current snapshot. The UI exposes active-case management plus an
> `Import Loaded Run` action, and the importer behavior is documented in repo notes.

Scope: build a real importer rather than a loose file loader so the local store is trustworthy and repeatable.

Task: implement an importer that reads Core-produced manifest and JSONL outputs, validates compatibility, and writes records into SQLite within a controlled transaction boundary.

Task: record provenance for every import, including Core run id, dataset key, import time, source window, record counts, and any schema or normalization versions.

Task: decide and implement initial import semantics for duplicate records, incremental refreshes, superseded imports, and import rollback on failure.

Task: surface import warnings and failures clearly in a structured operation log so engineers can trust what has and has not been loaded.

Validation: import an existing normalized conversation run from the repo fixtures into a new local database and verify entity counts, indexes, and provenance rows are correct.

Documentation: add importer behavior notes that explain supported artifact shapes, compatibility checks, and failure semantics.

## Session 6: Case Workflow State and Retention Controls — **COMPLETE**

> **What was delivered:** schema v2 adds case-workflow tables for tags, bookmarks, findings, saved views,
> report snapshots, and audit history. The database layer now exposes retention-aware case operations for
> expiry updates, close, archive, purge-ready, and purge. Archive clears imported Core data while
> preserving analyst work product; purge clears imported data plus workflow state while retaining the case
> shell and audit trail. The case-management dialog now supports notes, tags, saved views, and lifecycle
> actions with audit visibility.

Scope: preserve investigative momentum across days while keeping data hygiene strict and explicit.

Task: add database support for analyst-created value such as notes, tags, bookmarks, findings, saved views, and report snapshots tied to a case.

Task: define retention fields and rules for active, expiring, archived, and purge-ready cases.

Task: add purge and optional archive workflows that clear local data at case close or after expiry according to policy.

Task: ensure purge and archive actions are auditable inside the application so users understand what was removed and when.

Validation: create a case, import data, add notes and saved views, then close and purge the case and verify data removal and purge audit behavior work as designed.

Documentation: add a case lifecycle and retention note that explains the intended multi-day incident workflow and the flush-clean expectation at case end.

## Session 7: High-Volume Pivot UX Over the Local Store

> **Pre-work completed:** The existing JSONL index (byte-offset seek, 64 KB buffered reader, UTF-8 BOM
> handling) and in-memory paging in `App.Index.psm1` / `App.UI.ps1` deliver a functional pivot UX over
> Core run folders today. Filters for direction, media type, queue, and free-text search are wired. This
> work is superseded but not discarded — the index strategy informs the SQLite column selection. When
> SQLite is in place this session rebuilds the same UX paths against the database layer.

Scope: make the application fast and useful for real investigation work by driving the UI from the local database instead of large in-memory raw collections.

Task: refactor the main conversation grid and detail views to query the local database or efficient in-memory projections derived from it, rather than repeatedly traversing full raw collections.

Task: optimize the UI for the pivots investigators actually use, such as time range, queue, division, ANI, DNIS, agent, disconnect patterns, transfer behavior, participant structure, and selected metric summaries.

Task: design the interaction model around cases, saved views, findings, and evidence collection rather than only a one-time load-and-grid experience.

Task: keep the workflow centered on rapid pivoting of large datasets while preserving selection context and detail inspection.

Validation: load a realistically large local case dataset and verify common filter and selection paths remain responsive without re-querying Genesys Cloud.

Documentation: update usage notes to describe the case-driven pivot workflow and the fact that most interactive analysis now happens over the local case store.

## Session 8: Local Query Performance and Index Hardening

> **Pre-work completed:** The JSONL byte-offset index delivers O(pageSize) record retrieval without full
> dataset loads. StreamReader is used throughout; `Get-Content` is banned by architecture test ARCH-17/21.
> The buffered 64 KB chunk reader in `_ReadFileLines` handles large files efficiently. These patterns carry
> forward as the design rationale for SQLite index column selection.

Scope: harden the local analytical store so it remains swift under the size and repetition expected in real incident workflows.

Task: add practical indexes for the most common investigation paths, especially conversation id, time range, queue, division, ANI, DNIS, agent-related fields, and case membership.

Task: review schema design for columns that should remain normalized versus fields that should be materialized or side-car JSON for performance and simplicity.

Task: add importer-side batching and transaction strategies that keep large imports predictable.

Task: add user-visible counts and timings for imports and major query pivots so performance regressions are visible.

Validation: run repeated import and pivot tests against larger fixture data and verify query performance remains acceptable for day-to-day operator use.

Documentation: add a concise performance note describing the intended dataset scale, indexing strategy, and any still-known limits.

## Session 9: Structured Telemetry Across Core, Import, and UX

> **Pre-work completed:** The Run Console tab (`DgRunEvents`, `TxtDiagnostics`, `BtnCopyDiagnostics`) is
> wired and functional. Live polling reads `events.jsonl` during a run via `Get-RunEvents`. On completion
> `Get-DiagnosticsText` assembles manifest + summary + last 10 events. Error streams from the background
> runspace surface in `TxtDiagnostics`. This session extends that foundation to cover import, case
> actions, and export operations.

Scope: make the end-to-end workflow observable so engineers and maintainers can trust the tool when incidents are messy and time matters.

Task: unify the frontend operation log with structured event records for Core invocation, import, case actions, saves, exports, refreshes, and purge operations.

Task: preserve Core run metadata and events as first-class references inside the application so investigators can trace findings back to source runs.

Task: convert silent catches and ambiguous error text into explicit warning or error events with actionable context.

Task: emit counts and durations for retries, poll cycles, imported records, skipped records, failed rows, query timings, and export outcomes where appropriate.

Validation: execute an end-to-end flow from case creation through import, pivoting, export, and purge and inspect the resulting telemetry for completeness and clarity.

Documentation: add a telemetry note that states exactly what artifacts and local records are produced today and what fields are available for troubleshooting.

## Session 10: Export, Evidence Pack, and Report Workflow

> **Pre-work completed:** `App.Export.psm1` delivers streaming `Export-RunToCsv` (line-by-line,
> no full dataset load), `Export-PageToCsv` for the current grid page, and `Export-ConversationToJson`
> for a single record. All three are wired in `App.UI.ps1`. This session adds case-level exports, HTML
> output, and the evidence-pack concept.

Scope: make the application useful at the end of an investigation, not only during exploration.

Task: design exports around the case model so engineers can produce a coherent summary of findings, selected conversations, saved filters, counts, and analyst notes.

Task: support at least CSV and HTML outputs in a way that reflects the case state and selected evidence rather than dumping raw rows without context.

Task: preserve provenance in exports so management or incident partners can see what Core run and time window the report was based on.

Task: add a lightweight evidence-pack concept that groups the conversations, notes, and summary needed to hand off or brief others.

Validation: create a case report from a populated local case and confirm it includes enough context to support a real incident handoff or management summary.

Documentation: update repo documentation to describe supported export modes, what is included in them, and the provenance fields users should expect.

## Session 11: Automated Test Coverage for the Reference Pattern

> **Pre-work completed:** `tests\Test-Compliance.ps1` (~60 static Gate D/E checks) and
> `tests\Invoke-AllTests.ps1` (32 architecture invariants covering startup, extraction boundary,
> dataset keys, indexing, export streaming, auth containment, run artifacts, XAML nuances, config,
> and strict mode) are fully implemented and exit 0 or 1 cleanly. This session adds Pester coverage
> for the importer, case lifecycle, and database logic once those layers exist.

Scope: harden the application as the intended flagship pattern for future Core-backed frontend apps.

Task: add Pester coverage for the importer, case lifecycle logic, retention handling, query assembly into Core input parameters, schema validation, and export shaping.

Task: add module-side tests where new reusable logic was promoted into `Genesys.Core` during this roadmap.

Task: create fixture sets representing realistic normalized conversation runs, incremental refresh situations, malformed artifact cases, and purge scenarios.

Task: make test execution straightforward from the repo root and ensure failures clearly identify whether the break is in Core integration, import behavior, database logic, or UX-adjacent pure functions.

Validation: run the full Pester suite and confirm each major architectural layer has meaningful coverage, especially the Core-to-DB contract and case retention flows.

Documentation: add a test note that explains entry points, fixture locations, and what categories of behavior are currently covered.

## Session 12: Reference Implementation Cleanup and Blueprint Packaging

Scope: finish the project as a clean flagship that can be copied in pattern, not in accidental complexity.

Task: remove dead code and stale comments from the old script-local acquisition path once the module-backed flow is proven and stable.

Task: identify which pieces created during this work are reusable across future apps and promote them into explicit blueprint documentation.

Task: produce a concise reference architecture document describing the shared pattern of **Core extraction**, **local case database**, and **frontend investigation UX**.

Task: capture the rules for what belongs in `Genesys.Core` versus what remains app-specific so future smaller dataset apps do not reinvent the same logic in new corners.

Validation: review the repo at the end of the roadmap and confirm it reads like a coherent reference implementation rather than a partially migrated one-off.

Documentation: update all repo documentation so it accurately describes the application as a flagship Core-backed frontend pattern for conversation analysis and future dataset apps.

## Definition of Success

Scope: these are the end-state behaviors the roadmap is intended to achieve.

Task: an engineer can open a case, request conversation data through `Genesys.Core`, ingest the normalized output into a local SQLite case store, and begin pivoting immediately.

Task: the engineer can continue investigating over multiple days without re-querying the same large dataset, while adding notes, bookmarks, tags, findings, and saved views.

Task: the engineer can refresh the case with additional Core runs when needed without losing provenance or prior investigative work.

Task: the engineer can generate a coherent export or report with traceable run metadata and then archive or purge the case according to policy.

Validation: run a realistic incident workflow from start to finish and verify the application behaves as a trustworthy, fast, and maintainable frontend rather than as a custom API extractor.

Documentation: keep this definition of success visible in the repo so future roadmap changes are tested against it instead of drifting into convenience-led architecture.

---

## Reporting Enhancement Roadmap (Sessions 13–20)

> **Purpose:** These sessions build the intelligence layer on top of the Core-backed case store.
> Each session adds new datasets pulled exclusively through `Invoke-Dataset`, new SQLite reference
> tables or aggregate caches, new report views in the WPF UI, and new roll-up statistics designed
> to surface insight rather than raw row counts.
>
> **Core constraint:** every Genesys Cloud API call is made by `App.CoreAdapter.psm1` via
> `Invoke-Dataset`. No session may introduce a new direct REST path in the frontend.

### Dataset reference

The following catalog keys are available and are used across these sessions.
All calls are made with `Invoke-Dataset -Dataset <key> -CatalogPath $catalogPath ...`.

| Key | What it delivers |
| --- | --- |
| `analytics-conversation-details` | Full async conversation records — participants, sessions, segments, metrics |
| `analytics-conversation-details-query` | Synchronous preview query for the same shape |
| `analytics.query.conversation.aggregates.queue.performance` | nConnected, tHandle, tTalk, tAcw, tAnswered, nOffered by queue |
| `analytics.query.conversation.aggregates.agent.performance` | Per-agent handle, talk, ACW, connected counts |
| `analytics.query.conversation.aggregates.abandon.metrics` | nAbandoned, tAbandoned, nOffered by queue |
| `analytics.query.conversation.aggregates.transfer.metrics` | nTransferred, nBlindTransferred, nConsultTransferred by queue |
| `analytics.query.conversation.aggregates.wrapup.distribution` | nConnected by wrapUpCode and queueId |
| `analytics.query.conversation.aggregates.digital.channels` | nOffered, nConnected, nAbandoned by mediaType |
| `analytics.query.queue.aggregates.service.level` | nAnsweredIn20/30/60, tServiceLevel by queue |
| `analytics.query.user.aggregates.performance.metrics` | Agent nConnected, tHandle, tTalk, tAcw, nOffered, tAnswered |
| `analytics.query.user.aggregates.login.activity` | tOnQueueTime, tOffQueueTime, tIdleTime by userId |
| `analytics.query.user.details.activity.report` | Full agent presence and routing activity timeline |
| `analytics.query.flow.aggregates.execution.metrics` | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone |
| `analytics.post.transcripts.aggregates.query` | Transcript topic and sentiment aggregates |
| `routing-queues` | Queue definitions — name, division, skills, members |
| `users` | Users with presence and routing status — name, email, department, division, skills |
| `authorization.get.all.divisions` | Division definitions — name, home org flag |
| `routing.get.all.wrapup.codes` | Wrapup code definitions — name, id |
| `routing.get.all.routing.skills` | Routing skill definitions — name, id |
| `routing.get.all.languages` | Language skill definitions — name, id |
| `flows.get.all.flows` | Architect flow definitions — name, type, division |
| `flows.get.flow.outcomes` | Flow outcome label definitions |
| `flows.get.flow.milestones` | Flow milestone definitions |
| `quality.get.evaluations.query` | Evaluation scores, form names, agents, calibration status |
| `quality.get.surveys` | Post-call survey results — CSAT, NPS, customer verbatim |
| `speechandtextanalytics.get.topics` | Speech and text analytics topic definitions |

---

## Session 13: Reference Data Foundation — Names, Queues, Divisions, Skills — **COMPLETE**

> **What was delivered:** `Refresh-ReferenceData` added to `App.CoreAdapter.psm1` — calls
> `Invoke-Dataset` for all nine reference datasets in a background runspace and writes results
> to `ref-<timestamp>` run folders. `Import-ReferenceDataToCase` added to `App.Database.psm1`
> — upserts into eight new reference tables (`ref_queues`, `ref_users`, `ref_divisions`,
> `ref_wrapup_codes`, `ref_skills`, `ref_flows`, `ref_flow_outcomes`, `ref_flow_milestones`),
> all scoped by `case_id` with `refreshed_at` timestamps. `Get-ResolvedName` helper added for
> ID-to-name resolution via pure SQLite lookup with `-Type` / `-Id` parameters.
> "Refresh Reference Data" button added to the case management panel, wired to
> `_StartRefreshReferenceDataJob` which runs the reference fetch in a background runspace and
> calls `Import-ReferenceDataToCase` on completion. Status bar shows record counts for each
> reference type. Schema bumped to v4.

Scope: populate a local reference-data layer so every subsequent report can resolve IDs to human-readable names without re-querying the org during pivots.

Task: add `Refresh-ReferenceData` to `App.CoreAdapter.psm1`. It calls `Invoke-Dataset` for each reference dataset in order: `routing-queues`, `users`, `authorization.get.all.divisions`, `routing.get.all.wrapup.codes`, `routing.get.all.routing.skills`, `routing.get.all.languages`, `flows.get.all.flows`, `flows.get.flow.outcomes`, `flows.get.flow.milestones`. Each dataset writes to `data\*.jsonl` in a dedicated `ref-<timestamp>` run folder under `OutputRoot`.

Task: add `Import-ReferenceDataToCase` to `App.Database.psm1`. It reads the reference run folder and upserts rows into five new tables: `ref_queues`, `ref_users`, `ref_divisions`, `ref_wrapup_codes`, `ref_skills`. Each table includes a `refreshed_at` column and a `case_id` foreign key so reference snapshots stay scoped to a case's org state at investigation time. Flow and milestone tables (`ref_flows`, `ref_flow_outcomes`, `ref_flow_milestones`) follow the same pattern.

Task: add a "Refresh Reference Data" button to the case management panel. Wire it to run `Refresh-ReferenceData` in the background runspace, then call `Import-ReferenceDataToCase` on completion. Show record counts for each reference type in the status bar (e.g., "Loaded 47 queues, 312 users, 18 divisions, 94 wrapup codes").

Task: add `Get-ResolvedName` as a pure SQLite helper in `App.Database.psm1` with a `-Type` parameter (`queue`, `user`, `division`, `wrapupCode`, `skill`) and an `-Id` parameter. All downstream report queries call this rather than embedding table JOINs directly in the report layer.

Validation: refresh reference data for a test org and confirm that conversation index entries for queue IDs, user IDs, and division IDs can each be resolved to a name without an API call.

Documentation: add a note describing the reference data model, the intended refresh cadence (per-case at open, on demand), and the fact that reference snapshots are retained as part of the case store until the case is archived.

---

## Session 14: Queue Performance Aggregate Report — **COMPLETE**

> **What was delivered:** `Get-QueuePerformanceReport` added to `App.CoreAdapter.psm1` — calls
> `Invoke-Dataset` for three aggregate datasets in sequence (`analytics.query.conversation.aggregates.queue.performance`,
> `analytics.query.conversation.aggregates.abandon.metrics`, `analytics.query.queue.aggregates.service.level`)
> using the case time window as the `Interval` `DatasetParameters` override; returns a hashtable with
> `QueuePerfFolder`, `AbandonFolder`, and `ServiceLevelFolder`.  `Import-QueuePerformanceReport` added
> to `App.Database.psm1` — parses all three JSONL outputs, merges by `queueId|intervalStart`, resolves
> queue names and division names from the ref tables, computes `abandon_rate_pct` (nAbandoned / nOffered × 100)
> and `service_level_pct` (nAnsweredIn30 / nOffered × 100), and upserts into the new `report_queue_perf`
> table (schema v5).  `Get-QueuePerfRows` and `Get-QueuePerfSummary` added for grid and summary-bar reads.
> "Queue Performance" `TabItem` added to `MainWindow.xaml` with header card, summary bar (Queues, Offered,
> Abandoned, Avg Abandon %, Avg SLA 30s %, Avg Handle), Division filter `ComboBox`, and 13-column
> `DgQueuePerf` `DataGrid`.  `_StartQueuePerfReportJob`, `_RenderQueuePerfGrid`, and
> `_PopulateQueuePerfDivisionFilter` added to `App.UI.ps1`; the division filter repopulates from the
> database after each import and on case activation.

Scope: deliver the first aggregate report: a per-queue view of volume, handling efficiency, and abandon risk across the current case's time window — with names resolved from the reference layer built in Session 13.

Task: add `Get-QueuePerformanceReport` to `App.CoreAdapter.psm1`. It calls `Invoke-Dataset` for three datasets simultaneously via parallel background runspaces (one each): `analytics.query.conversation.aggregates.queue.performance`, `analytics.query.conversation.aggregates.abandon.metrics`, and `analytics.query.queue.aggregates.service.level`. All three use the same `StartDateTime` / `EndDateTime` window as the active case. Results are written to `data\*.jsonl` in a `report-queue-perf-<timestamp>` run folder.

Task: add `Import-QueuePerformanceReport` to `App.Database.psm1`. It reads the three JSONL outputs and writes a normalized `report_queue_perf` table with one row per queue per granularity interval: `queue_id`, `queue_name` (resolved via `ref_queues`), `division_id`, `division_name`, `interval_start`, `n_offered`, `n_connected`, `n_abandoned`, `abandon_rate_pct`, `t_handle_avg_sec`, `t_talk_avg_sec`, `t_acw_avg_sec`, `n_answered_in_20`, `n_answered_in_30`, `n_answered_in_60`, `service_level_pct`.

Task: add a "Queue Performance" tab to the Reports section in the WPF UI (new `TabItem` in the existing reports panel). Wire a `DataGrid` bound to `report_queue_perf` with sortable columns. Color-code the `abandon_rate_pct` cell red when > 5 %, yellow when > 2 %. Color-code `service_level_pct` red when < 80 %, yellow when < 90 %.

Task: add a summary bar above the grid showing org-wide totals: total offered, total abandoned, overall abandon rate, overall service level, and median handle time. These roll up across all queues in the filtered set.

Task: add a "Filter by Division" dropdown that uses the `ref_divisions` table to constrain the grid without re-querying the API.

Validation: generate the queue performance report for a known test window, verify that queue names appear (not IDs), and confirm that the abandon rate and service level roll-ups match manual calculations from the raw aggregate data.

Documentation: add a report description to the UI tooltip and to repo notes explaining what each metric represents and which catalog dataset supplies it.

---

## Session 15: Agent Performance Report — Cross-Queue View — **COMPLETE**

> **What was delivered:** `Get-AgentPerformanceReport` added to `App.CoreAdapter.psm1` — calls
> `Invoke-Dataset` for three datasets in sequence (`analytics.query.conversation.aggregates.agent.performance`,
> `analytics.query.user.aggregates.performance.metrics`, `analytics.query.user.aggregates.login.activity`)
> using the case time window as the `Interval` `DatasetParameters` override; returns a hashtable with
> `AgentPerfFolder`, `UserPerfFolder`, and `LoginActivityFolder`. `Import-AgentPerformanceReport` added
> to `App.Database.psm1` — merges all three JSONL outputs by `userId`, resolves names from `ref_users`
> and division names from `ref_divisions`, resolves handled queue names via the conversations store,
> computes `talk_ratio_pct` (tTalk / tHandle × 100), `acw_ratio_pct` (tAcw / tHandle × 100), and
> `idle_ratio_pct` (tIdle / totalTime × 100), and upserts into the new `report_agent_perf` table
> (schema v6). `Get-AgentPerfRows` and `Get-AgentPerfSummary` added for grid and summary-bar reads.
> "Agent Performance" `TabItem` added to `MainWindow.xaml` with header card, summary bar (Agents,
> Connected, Avg Handle, Avg Talk %, Avg ACW %, Avg Idle %), Division filter `ComboBox`, and 16-column
> `DgAgentPerf` `DataGrid` with ⚠ flag column (talk < 50 % or ACW > 30 %).
> `_StartAgentPerfReportJob`, `_RenderAgentPerfGrid`, and `_PopulateAgentPerfDivisionFilter` added
> to `App.UI.ps1`; the division filter repopulates from the database after each import and on case activation.

Scope: expose per-agent handling efficiency, talk ratio, idle time, and queue distribution so supervisors can identify agents who are outliers without needing a separate Genesys reporting tool.

Task: add `Get-AgentPerformanceReport` to `App.CoreAdapter.psm1`. It calls `Invoke-Dataset` for `analytics.query.conversation.aggregates.agent.performance`, `analytics.query.user.aggregates.performance.metrics`, and `analytics.query.user.aggregates.login.activity` using the case time window. Results land in a `report-agent-perf-<timestamp>` run folder.

Task: add `Import-AgentPerformanceReport` to `App.Database.psm1`. It writes a `report_agent_perf` table: `user_id`, `user_name`, `user_email`, `department`, `division_id`, `division_name`, `queue_ids` (pipe-delimited resolved names), `n_connected`, `n_offered`, `t_handle_avg_sec`, `t_talk_avg_sec`, `t_acw_avg_sec`, `t_on_queue_sec`, `t_off_queue_sec`, `t_idle_sec`, `talk_ratio_pct` (tTalk / tHandle * 100), `acw_ratio_pct`, `idle_ratio_pct`.

Task: add an "Agent Performance" report tab in the WPF UI. Wire a `DataGrid` with sortable columns. Highlight `talk_ratio_pct` < 50 % as a potential concern (long ACW or idle pattern). Highlight `acw_ratio_pct` > 30 % similarly.

Task: add a per-agent drilldown panel: clicking an agent row opens a side panel showing the agent's queue breakdown (which queues they handled, volume per queue), top wrapup codes (from `analytics.query.conversation.aggregates.wrapup.distribution` filtered to that agent), and a list of their conversation IDs in the case store that can be clicked to open the existing drilldown view.

Task: add a division filter and a queue filter to the agent grid so supervisors can scope to a team or single queue.

Validation: run the agent performance report for a test window containing agents across at least two queues. Confirm names resolve, talk ratio and ACW ratio calculations are correct, and the drilldown panel correctly links to existing conversation records.

Documentation: document the `talk_ratio_pct` and `idle_ratio_pct` formulas and note which underlying aggregate metrics feed each column.

---

## Session 16: Transfer and Escalation Chain Intelligence — **COMPLETE**

Scope: surface transfer behavior so routing engineers can identify where conversations are bouncing, which queues transfer most frequently, and whether blind versus consult transfer patterns differ — all without building a custom segment parser outside Core.

Delivered:

> `Get-TransferReport` pulls `analytics.query.conversation.aggregates.transfer.metrics` for the case window.
> Schema v7 adds `report_transfer_flows` and `report_transfer_chains`; `Import-TransferReport`
> derives local queue-hop chains from stored conversation participants and writes flow and chain rows.
> "Transfer & Escalation" `TabItem` added to `MainWindow.xaml` with Pull Report, blind/consult filter,
> flow grid, top destination grid, summary split, and multi-hop conversation grid.
> `_StartTransferReportJob`, `_RenderTransferGrid`, and `_OpenTransferChainConversation` added to `App.UI.ps1`;
> selecting a multi-hop conversation opens the existing drilldown view.

Task: add `Get-TransferReport` to `App.CoreAdapter.psm1`. It calls `Invoke-Dataset` for `analytics.query.conversation.aggregates.transfer.metrics` for the case time window. It additionally issues a follow-on pass over the already-imported conversation detail records in the local case store (no new API call) to extract segment-level transfer chains: for each conversation that has a transfer segment, record source queue ID, target queue ID (or external), transfer type (`blind`, `consult`), and durationSec before the transfer.

Task: add `Import-TransferReport` to `App.Database.psm1`. Write a `report_transfer_flows` table: `queue_id_from`, `queue_name_from`, `queue_id_to`, `queue_name_to`, `transfer_type`, `n_transfers`, `pct_of_total_offered`. Also write a `report_transfer_chains` table: `conversation_id`, `transfer_sequence` (ordered pipe-delimited queue names), `hop_count`, `final_queue_name`, `final_disconnect_type`.

Task: add a "Transfer & Escalation" report tab. Show a flow summary grid (from → to, count, type). Add a "Top Transfer Destinations" ranking by n_transfers. Add a "Multi-Hop Conversations" sub-grid listing conversations with hop_count ≥ 2 — these are the ones most likely to represent routing failures.

Task: add a "Blind vs. Consult Split" chart summary panel (two numeric tiles with percentages) so routing engineers can immediately see whether agents are using consult properly.

Task: conversations in the multi-hop grid must be clickable, opening the existing drilldown view so the engineer can inspect the full segment sequence.

Validation: import a test run known to contain transferred conversations. Confirm the from/to queue table shows correct counts, hop count is correct for multi-transfer conversations, and clicking a multi-hop conversation loads the drilldown correctly.

Documentation: define what constitutes a "transfer hop" in the context of the Genesys segment model and document how `queue_id_to` is inferred from segment data when the aggregate dataset does not carry the destination queue directly.

---

## Session 17: IVR and Flow Containment Report

Scope: identify which Architect flows are self-serving successfully, which are routing callers to agents unnecessarily, and where callers are disconnecting in-flow — enabling IVR optimization without requiring access to the Architect editor.

Task: add `Get-FlowContainmentReport` to `App.CoreAdapter.psm1`. It calls `Invoke-Dataset` for `analytics.query.flow.aggregates.execution.metrics`, `flows.get.all.flows`, `flows.get.flow.outcomes`, and `flows.get.flow.milestones` using the case time window. Results land in a `report-flow-containment-<timestamp>` run folder.

Task: add `Import-FlowContainmentReport` to `App.Database.psm1`. Write `report_flow_perf`: `flow_id`, `flow_name`, `flow_type`, `division_name`, `n_flow` (entries), `n_flow_outcome_success`, `n_flow_outcome_failed`, `n_flow_milestone_hit`, `containment_rate_pct` (outcomes not routed to agent / total entries * 100), `failure_rate_pct`. Write `report_flow_milestone_distribution`: `flow_id`, `milestone_id`, `milestone_name`, `n_hit`, `pct_of_entries` — shows how far callers progress through a flow before exiting.

Task: add a "Flow & IVR" report tab. Show the flow performance grid (sortable by containment rate). Add a milestone distribution sub-panel for the selected flow row: a simple ranked bar chart (milestone name vs. hit count) showing the dropout funnel — where in the flow callers stop completing milestones.

Task: add a "Flows Routing to Queues" correlation view: for any flow with low containment, show which queues receive its overflow traffic using the conversation detail segments already in the case store.

Validation: run the flow report for a test window containing IVR traffic. Confirm containment rate calculation matches manual count, milestone distribution shows meaningful funnel shape, and the "Flows Routing to Queues" view correctly identifies receiving queues.

Documentation: define containment rate precisely (self-service completions / entries, excluding transfers to agent). Note which flow types (inbound, bot, in-queue) the dataset covers and any flow types that produce no segment-level data.

---

## Session 18: Wrapup Code Distribution and Contact Reason Intelligence

Scope: decode why customers are calling by turning wrapup code distributions into ranked contact reason reports, then cross-reference them with queue, agent, and time-of-day dimensions to find where volume concentrates and what's driving repeat contacts.

Task: add `Get-WrapupDistributionReport` to `App.CoreAdapter.psm1`. It calls `Invoke-Dataset` for `analytics.query.conversation.aggregates.wrapup.distribution` and `routing.get.all.wrapup.codes` for the case time window. Results land in `report-wrapup-<timestamp>`.

Task: add `Import-WrapupDistributionReport` to `App.Database.psm1`. Write `report_wrapup_distribution`: `queue_id`, `queue_name`, `wrapup_code_id`, `wrapup_code_name`, `n_connected`, `pct_of_queue_total`, `pct_of_org_total`. Write `report_wrapup_by_hour`: `hour_of_day` (0–23), `wrapup_code_name`, `n_connected` — enables contact reason heat maps by time of day.

Task: add a "Contact Reasons" report tab. Show a ranked grid of wrapup codes org-wide (by n_connected descending). Add a "By Queue" breakdown sub-grid for the selected code showing which queues are handling that contact reason most. Add a "By Hour" heat-map panel: rows are wrapup codes (top 10), columns are hours 0–23, cells are color-scaled by n_connected.

Task: compute a "concentration index" for each wrapup code: the ratio of the top queue's share to the average queue's share. A high index means the contact reason is heavily concentrated in one queue. Surface the top 5 concentrated codes with a brief label ("Concentrated in: [queue name]") as an insights panel.

Task: cross-reference the wrapup distribution with the conversation detail records already in the case store: for each of the top 10 wrapup codes, show the median handle time and median segment count of conversations carrying that code, sourced from the local SQLite case store without a new API call.

Validation: run the wrapup distribution report and confirm code names resolve, the concentration index calculation is correct, and the median handle time cross-reference matches hand-counted values from known fixture conversations.

Documentation: define the concentration index formula and note that wrapup codes are set by agents at wrap-up — they may be absent on conversations that disconnected before wrap-up completion.

---

## Session 19: Quality and Voice-of-Customer Overlay

Scope: link quality evaluation scores and post-call survey results to the conversation, agent, and queue dimensions already in the case store, creating a unified quality picture that connects operational data (handle time, transfer rate) with outcome data (evaluation score, CSAT).

Task: add `Get-QualityOverlayReport` to `App.CoreAdapter.psm1`. It calls `Invoke-Dataset` for `quality.get.evaluations.query` and `quality.get.surveys` using the case time window. Results land in `report-quality-<timestamp>`.

Task: add `Import-QualityOverlayReport` to `App.Database.psm1`. Write `report_evaluations`: `evaluation_id`, `conversation_id`, `evaluator_user_id`, `evaluator_name`, `evaluated_user_id`, `agent_name`, `queue_id`, `queue_name`, `form_name`, `score_pct`, `calibrated`, `completed_at`. Write `report_surveys`: `survey_id`, `conversation_id`, `agent_user_id`, `agent_name`, `queue_id`, `queue_name`, `nps_score`, `csat_score`, `completed_at`, `verbatim_text`.

Task: add a "Quality" report tab. Show per-agent evaluation score distribution (box plot summary: min, p25, median, p75, max). Add a per-queue CSAT/NPS distribution panel. Add a "Low Score Conversations" grid: conversations with evaluation score < 70 % or NPS detractor (0–6) — these are immediately clickable to open the drilldown view.

Task: add a cross-metric correlation panel: for the set of conversations in the case store that have both an evaluation score AND a handle time, compute and display the Pearson correlation coefficient between handle time and score, and between wrapup code and score. Long handle time does not always mean quality; this panel makes that visible.

Task: integrate with the speech analytics datasets if `speechandtextanalytics.get.topics` returns data: show the top 5 topics associated with low-score conversations. This requires `analytics.post.transcripts.aggregates.query` filtered to the same time window, grouped by topic.

Validation: import a test run that includes evaluations and surveys. Confirm score distribution is correct, low-score conversations link to drilldown correctly, and the correlation panel displays a reasonable coefficient.

Documentation: note that surveys require a post-call survey program configured in the org and that evaluation scores are normalized to a 0–100 % scale regardless of the form's raw point total.

---

## Session 20: Temporal Trend, Comparative Analysis, and Composite Roll-Ups

Scope: enable time-series analysis and before/after comparisons so investigators can answer "did this change after the incident?" and supervisors can answer "is this week better or worse than last week?" — both entirely from data already in the case store or from a targeted second pull through Core.

Task: add `Get-TrendReport` to `App.CoreAdapter.psm1`. It accepts two time windows (`-WindowA` and `-WindowB`, each a `{Start, End}` pair) and calls `Invoke-Dataset` for `analytics.query.conversation.aggregates.queue.performance`, `analytics.query.conversation.aggregates.abandon.metrics`, and `analytics.query.queue.aggregates.service.level` for each window in parallel background runspaces. Results land in `report-trend-A-<timestamp>` and `report-trend-B-<timestamp>` folders.

Task: add `Import-TrendReport` to `App.Database.psm1`. Write `report_trend_comparison`: one row per queue per window label (A or B) with all queue performance metrics. Add a computed `delta_*` view that calculates the absolute and percentage change for each metric between window A and window B.

Task: add a "Trend" report tab. Show a side-by-side comparison grid: queue name, Window A values, Window B values, delta (color-coded green for improvement, red for regression). Add a "Biggest Regressions" panel ranking queues by worst abandon rate delta. Add a "Biggest Improvements" panel for the opposite direction.

Task: add an "Hourly Volume" sub-view: pull hourly granularity from the aggregate datasets for both windows and render a dual-line chart overlay (Window A vs. Window B) for selected queues, showing volume and handle time across the day. Use WPF `Canvas` or a simple `Grid`-based bar chart rather than a charting library dependency.

Task: add a composite "Incident Impact Summary" that assembles data already in the case store: total conversations in the case window, impacted queues ranked by volume, top 3 wrapup codes in the window, worst service level, and whether quality evaluation scores shifted between windows. This summary should be exportable as a single-page text report suitable for management briefing.

Validation: pull two windows around a known configuration change in a test org and verify the delta calculations are correct, the regression ranking identifies the expected queues, and the Incident Impact Summary exports cleanly.

Documentation: document the two-window model, explain that Window A is typically the baseline and Window B is the incident or post-change window, and describe how to configure the windows from the case date range controls.

---

## Cross-Session: Enrichment Join Architecture

These are the standing rules that govern how cross-entity joins are performed across Sessions 13–20.
They must be treated as acceptance criteria for every session that joins datasets.

Rule: joins between conversation records and aggregate metrics must use `conversationId` or `queueId`/`userId` keys that are already present in both the conversation detail JSONL and the aggregate JSONL as produced by Core. No join may assume undocumented fields.

Rule: all name resolution (`queueId` → name, `userId` → name, `divisionId` → name, `wrapupCodeId` → name) must go through the reference tables populated in Session 13. No session may embed a hard-coded name or duplicate a reference pull.

Rule: when a conversation in the case store has no matching row in an aggregate dataset (e.g., short conversations that don't appear in aggregates), the conversation row must still be included in reports with `null` aggregate values rather than being silently dropped.

Rule: when an aggregate dataset returns a queue or user ID that has no matching row in the reference tables, the report must display the raw ID with a "(unresolved)" suffix rather than failing or hiding the row. This handles orgs where reference data was not refreshed after a queue rename.

Rule: `App.CoreAdapter.psm1` must not pass raw conversation IDs as filter parameters into aggregate dataset calls unless the catalog explicitly supports an `id[]` filter for that endpoint. Aggregate calls use time-window + dimension filters only.

Rule: all multi-dataset report pulls must use the same `StartDateTime` / `EndDateTime` values derived from the active case. These are passed as UTC ISO-8601 strings. The `.ToUniversalTime()` conversion established in Session 3 applies here without exception.

---

## Reporting Enhancement — Definition of Success

Scope: end-state behaviors specific to the reporting sessions.

Task: a supervisor can open a case, pull reference data and aggregate metrics via one-click report generation, and within five minutes have a queue performance table with abandon rates, service levels, and agent handle time breakdowns — all with human-readable names instead of raw IDs.

Task: a routing engineer can identify the top three queues contributing transfer hops, the IVR flows with containment rates below a threshold, and the wrapup code distribution pattern across queues — without leaving the application or re-querying Genesys Cloud interactively.

Task: an incident investigator can compare two time windows side-by-side, see which queues regressed on service level and abandon rate during the incident window, and export a one-page summary with enough context for a management briefing.

Task: a quality supervisor can see evaluation score distributions by agent and queue, click into any low-score conversation to review the raw detail, and correlate evaluation outcomes with speech analytics topic trends — all from a single populated case.

Validation: run a complete reporting workflow from case creation through reference data refresh, report generation for all six report types, and export of an Incident Impact Summary. Verify that no direct Genesys Cloud API calls are made from the UI layer and that all data flows through `Invoke-Dataset` via `App.CoreAdapter.psm1`.

Documentation: update the application's README and this roadmap to reflect the full reporting capability, naming each report type and the catalog datasets that feed it.
