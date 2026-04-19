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

## Case-Driven Pivot Workflow

All interactive analysis runs against a **local SQLite case store** (`cases.sqlite`), not by re-querying Genesys Cloud on every pivot. The store ships pre-built (`lib/cases.seed.sqlite`) and is copied into `%LOCALAPPDATA%\GenesysConversationAnalysis\` on first launch. The store is the investigation substrate: latest-state browsing stays simple, while import lineage remains queryable.

### 1. First launch — zero ceremony

The app creates a default case named **Research** on first launch and sets it active. Run a conversation-detail job and every result is auto-imported into that case. You can keep accumulating multiple job runs. Latest browsing is keyed by `case_id + conversation_id`; historical lineage is preserved in `conversation_versions` with `import_id`, `run_id`, source file, source offset, import timestamp, payload hash, and raw JSON.

To start a separate investigation, open the Case Manager and click **New Case**. Name it, and it becomes the active case.

### 2. Import a Core run

Runs triggered from the app are auto-imported into the active case. To import a historical run, select a completed `Genesys.Core` run folder from the Recent Runs list and click **Import to Case**. Progress appears in the status bar; details go to the Run Console tab.

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
