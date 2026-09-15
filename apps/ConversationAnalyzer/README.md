# Genesys Conversation Analyzer

PowerShell/WPF investigation workbench for **Genesys Cloud conversation populations**. The app is designed for engineers who need to understand several thousand filtered conversations quickly, inspect representative examples, preserve findings, and export defensible results with provenance.

The app does not extract directly from Genesys Cloud. `Genesys.Core` remains the only extraction engine, and `App.CoreAdapter.psm1` remains the only app module that invokes Core datasets.

## Repo Layout

```text
genesys.core/
└── apps/
    └── ConversationAnalyser/
├── App.ps1
├── modules/
│   ├── App.Config.psm1
│   ├── App.CoreAdapter.psm1
│   ├── App.Database.psm1
│   ├── App.Export.psm1
│   ├── App.Index.psm1
│   └── App.Reporting.psm1
├── scripts/
│   └── App.UI.ps1
├── resources/
│   └── MainWindow.xaml
├── tests/
│   ├── Invoke-AllTests.ps1
│   ├── Invoke-SmokeTests.ps1
│   └── Test-Compliance.ps1
├── lib/
│   └── System.Data.SQLite.dll
└── docs/
```

## Canonical Entrypoint

Launch the app from this application folder:

```powershell
cd ./apps/ConversationAnalyser
pwsh -NoProfile -ExecutionPolicy Bypass -File ./App.ps1
```

`App.ps1` imports the app modules, initializes the Core adapter, initializes the SQLite-backed case store, loads `resources/MainWindow.xaml`, and dot-sources `scripts/App.UI.ps1`.

## Prerequisites

- Windows 10 or 11
- PowerShell 7.2+
- A sibling `Genesys.Core` checkout or equivalent paths configured in app settings
- Genesys Cloud OAuth credentials for interactive use

Expected sibling layout:

```text
<workspace>/
├── Genesys.Core/
└── Genesys.Core.ConversationAnalytics_v2/
```

## Configuration

The app persists user configuration under `%LOCALAPPDATA%\GenesysConversationAnalysis\config.json`.

Important settings:

- `CoreModulePath`
- `CatalogPath`
- `SchemaPath`
- `OutputRoot`
- `DatabasePath`
- `SqliteDllPath`
- `Region`
- `PkceClientId`
- `PkceRedirectUri`

Environment variables override the persisted Core paths at runtime:

- `GENESYS_CORE_MODULE`
- `GENESYS_CORE_CATALOG`
- `GENESYS_CORE_SCHEMA`

## Main Capabilities

- Preview and full conversation-detail runs via `Genesys.Core`
- Case-store imports with run/import provenance, canonical raw conversation JSON, payload hashes, and preserved lineage versions
- SQL-backed filtering, paging, facets, population summaries, representative examples, and cohort queries
- Faithful DB drilldown from canonical raw JSON, with flattened columns retained for fast analysis
- Page, run, population-report, and single-conversation export paths
- SQLite-backed case management for imports, notes, findings, bookmarks, tags, saved views, and report snapshots
- Investigation report tabs for queue performance, agent performance, transfer chains, flow containment, wrapup intelligence, quality overlay, trend comparison, and timeline analysis

## Short Voice Conversation Analyzer

The app includes a dedicated short-call workflow that stays Core-first:

- Data collection still runs through `Invoke-Dataset` (conversation-details query).
- Post-processing reads run artifacts from the active Core run folder.
- Output is written back into the same run folder for traceability.

Generated artifacts:

- `short-voice-conversations-summary.json`
- `short-voice-conversations-rollup.json`
- `short-voice-conversations-detail.jsonl`
- `short-voice-conversations-report.md`
- Optional exports: `short-voice-conversations.csv`, `short-voice-conversations.xlsx`
- Optional Elastic bulk payload: `short-voice-elastic-bulk.ndjson`

### Desktop Workflow (WPF Tab)

1. Open the **Short Voice Conversations** tab.
2. Set threshold (seconds), interval, and optional filters (direction, queue, division, user, campaign, ANI, DNIS, wrap-up, disconnect).
3. Run query from the tab. The app starts a Core dataset run.
4. After run completion, post-processing executes and fills summary, rollups, and detail preview.
5. Use export buttons for Markdown/JSON/CSV/XLSX and optional Elastic publish.

Notes:

- Threshold logic is strict less-than (`duration < threshold`).
- Incomplete conversations are excluded by default from short-call counting.

### Headless Workflow (Scheduled Telemetry)

Use `scripts/Start-ShortVoiceConversationRollupJob.ps1` to run the same Core + post-process pipeline without UI.

Example:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Start-ShortVoiceConversationRollupJob.ps1 -ConfigPath ./config/short-voice-conversation-rollup.json
```

Register a Windows Scheduled Task with `scripts/Register-ShortVoiceConversationRollupScheduledTask.ps1`.

Example:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/Register-ShortVoiceConversationRollupScheduledTask.ps1 -ConfigPath ./config/short-voice-conversation-rollup.json -DailyAt '06:00'
```

Config baseline: `config/short-voice-conversation-rollup.example.json`.

### Elastic Publishing

Short voice rollups can be sent to Elastic bulk API with deterministic `_id` values per run/document type/dimension key.

Supported settings in config:

- `Elastic.Enabled`
- `Elastic.Uri`
- `Elastic.IndexName`
- `Elastic.UseDailyIndexSuffix`
- `Elastic.AuthMode` (`ApiKey` or `Basic`)
- `Elastic.ApiKeyEnvironmentVariable` or Basic auth env var names
- `Elastic.BulkBatchSize`
- `Elastic.DryRun`
- `Elastic.ValidateTls`

When `DryRun = true`, the NDJSON payload is produced but not sent.

### Troubleshooting

- No output files created:
    Ensure the Core run folder has `manifest.json`, `summary.json`, and `data/*.jsonl` with conversation details rows.
- Short-call count appears low:
    Confirm threshold is in seconds and strict less-than; exactly equal durations are excluded.
- Missing-end conversations not counted:
    This is expected unless `IncludeIncompleteConversations` is enabled.
- Elastic publish fails:
    Validate `Elastic.Uri`, auth env vars, index permissions, and TLS policy (`ValidateTls`).
- Empty rollups with non-empty source:
    Check active filters (queue/division/user/campaign/ANI/DNIS/wrap-up/disconnect).

### Known Limitations

- Duration derivation currently prefers `conversationStart` / `conversationEnd`.
- XLSX export requires `ImportExcel` module availability.
- Rollups are run-folder scoped and do not merge across multiple runs automatically.
- Elastic error handling retries transient failures, but does not yet inspect per-item failure reasons for selective replay.

## Case-Driven Pivot Workflow

All interactive analysis runs against a **local SQLite case store** (`cases.sqlite`), not by re-querying Genesys Cloud on every pivot. The store ships pre-built (`lib/cases.seed.sqlite`) and is copied into `%LOCALAPPDATA%\GenesysConversationAnalysis\` on first launch. The store is the investigation substrate: latest-state browsing stays simple, while import lineage remains queryable.

### 1. First launch — zero ceremony

The app creates a default case named **Research** on first launch and sets it active. Run a conversation-detail job and every result is auto-imported into that case. You can keep accumulating multiple job runs. Latest browsing is keyed by `case_id + conversation_id`; historical lineage is preserved in `conversation_versions` with `import_id`, `run_id`, source file, source offset, import timestamp, payload hash, and raw JSON.

To start a separate investigation, open the Case Manager and click **New Case**. Name it, and it becomes the active case.

### 2. Import a Core run

Runs triggered from the app are auto-imported into the active case. To import a historical run, select a completed `Genesys.Core` run folder from the Recent Runs list and click **Import to Case**. Progress appears in the status bar; details go to the Run Console tab.

Before import, the app validates the Core artifact contract: supported dataset key, consistent manifest/summary run identity, reconciled expected counts, parseable `data/*.jsonl`, and required `conversationId` on every conversation record. Contract failures stop the import before case-store mutation.

### 3. Pivot without re-querying Genesys Cloud

Once imported, the grid switches to **case-store mode**. Filter, count, page, report, and saved-view operations use the same canonical filter state and SQL-backed WHERE builder. Column filters are not page-local in DB mode, so record count, page count, and visible rows agree.

| Control | Filter |
| --- | --- |
| Date/time pickers | `conversation_start` range (apply date with picker; apply custom time with Enter) |
| Direction | inbound / outbound |
| Media type | voice / chat / email / … |
| Queue | substring match |
| Disconnect type | exact match |
| Agent | substring match on agent names |
| Search box | conversation ID, queue name, agent name, ANI, DNIS, or conversation signature |
| Column filters | SQL-backed text filters over mapped grid columns |

### 4. Understand the filtered population

The case store persists derived investigation columns at import time, including primary/final queue, queue/agent counts, transfer counts, hold count and hold duration, MOS min/max/average, wrapup code/name, flow id/name, disconnect booleans, callback/voicemail flags, conversation signature, anomaly flags, and risk score.

Normalized bridge tables support exact future pivots across agents, queues, divisions, flows, and wrapups. Analytics helpers expose population summaries, facet counts, representative conversations, and anomaly/risk cohorts without putting SQL or business logic in the UI script.

### 5. Save views and create findings

When you have a useful filter combination, click **Save View** in the Case Manager to persist the exact canonical filter snapshot. Named views are listed per case and can be revisited across sessions.

Use **New Finding** to record a conclusion, severity, status, and supporting evidence_json. Findings are stored in the case and persist independently of the filter state.

Bookmark individual conversations via the drilldown panel for quick reference.

### 6. Generate and save reports

Click **Impact Report** in DB mode to generate a population report over the full filtered SQL result set, not the current page. Saved report snapshots wrap the report with the exact filter state used at generation time.

Report types:

- **Population report**: full filtered-set summary, facets, risk cohorts, representative examples, provenance, and exact filter state.
- **Conversation dossier**: single-conversation export shape with canonical raw JSON, derived detail, and version lineage.

### Trend Comparison

The **Trend** tab compares two time windows at hourly granularity using the case store as the read model after import.

- Configure **Window A** and **Window B** with the four date pickers on the tab, then click **Pull Report**.
- The app fetches queue performance, abandon metrics, and service-level aggregates for both windows through `App.CoreAdapter.psm1`, imports them into the local SQLite store, and renders a side-by-side delta grid.
- The right-hand panels rank the biggest regressions and improvements, draw an hourly offered-volume overlay, and summarize impacted queues, wrapup codes, service-level degradation, and quality shift.
- **Export Summary** writes the current Incident Impact Summary to a one-page text file suitable for management briefings.

This tab does not call Genesys Cloud directly from the UI. As with the rest of the app, all extraction flows through `Invoke-Dataset` via `App.CoreAdapter.psm1`.

### 7. Drill down faithfully

DB drilldown uses the canonical `raw_json` payload stored at import time for the primary detail and Raw JSON tab. Flattened columns remain for fast analysis, but reconstructed participant JSON is only a compatibility fallback for older stores that lack `raw_json`.

### 8. Refresh with additional runs

Import additional Core runs into the same case to extend coverage. Each conversation-detail job completes, auto-imports, refreshes latest-state rows, and preserves a lineage version. You can run many queries against different time ranges or queues and keep accumulating into one store for research.

### 9. Close, archive, or purge

When the investigation is complete, use the Case Manager to:

- **Close** — mark the case as resolved; data is retained.
- **Archive** — move to archived state; data is retained for long-term reference.
- **Mark Purge-Ready** → **Purge** — permanently remove all case data from the local store when retention policy requires it.

The case audit trail records every state transition with a timestamp.

---

## Tests

Run the full repo guardrail suite from the root:

```powershell
pwsh -NoProfile -File ./apps/ConversationAnalyser/tests/Invoke-AllTests.ps1
```

That runner executes:

- Static compliance checks in `apps/ConversationAnalyser/tests/Test-Compliance.ps1`
- Runtime smoke checks in `apps/ConversationAnalyser/tests/Invoke-SmokeTests.ps1`
- Architecture/layout invariants for startup, boundaries, indexing, export, reporting, and case-store design

## Design Intent

- `App.CoreAdapter.psm1` is the only module allowed to interact with `Genesys.Core`
- `App.Index.psm1` and `App.Export.psm1` are streaming-oriented and avoid large full-file reads
- `App.Database.psm1` owns SQLite schema, canonical filters, lineage, derived columns, bridge tables, and analytics queries
- `App.Reporting.psm1` shapes population reports and conversation dossiers from database/index data without re-querying Genesys Cloud
- `App.UI.ps1` orchestrates and renders; database/reporting modules own filtering semantics and report scope
