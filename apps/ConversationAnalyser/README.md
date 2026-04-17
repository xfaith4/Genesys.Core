# Genesys Conversation Analysis

Desktop analytics workbench for **Genesys Cloud conversation detail analysis** built in PowerShell/WPF. The root of this repository is the only supported app layout and entrypoint.

## Repo Layout

```text
Genesys.Core.ConversationAnalytics_v2/
├── App.ps1
├── App.Config.psm1
├── App.Auth.psm1
├── App.CoreAdapter.psm1
├── App.Index.psm1
├── App.Export.psm1
├── App.Reporting.psm1
├── App.Database.psm1
├── App.UI.ps1
├── XAML/
│   └── MainWindow.xaml
├── tests/
│   ├── Invoke-AllTests.ps1
│   └── Test-Compliance.ps1
├── lib/
│   └── System.Data.SQLite.dll
└── *.md
```

## Canonical Entrypoint

Launch the app from the repo root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ./App.ps1
```

`App.ps1` imports the root modules, initializes the Core adapter, initializes the optional SQLite-backed case store, loads `XAML/MainWindow.xaml`, and dot-sources `App.UI.ps1`.

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
- Indexed paging and drilldown without re-querying the API
- Page, run, and single-conversation export paths
- SQLite-backed case management for imports, notes, findings, bookmarks, tags, saved views, and report snapshots
- Impact-report generation over the currently filtered conversation set

## Case-Driven Pivot Workflow

All interactive analysis runs against a **local SQLite case store** (`cases.sqlite`), not by re-querying Genesys Cloud on every pivot. The store ships pre-built (`lib/cases.seed.sqlite`) and is copied into `%LOCALAPPDATA%\GenesysConversationAnalysis\` on first launch — no schema-bootstrap step, no external database, no connection string.

### 1. First launch — zero ceremony

The app creates a default case named **Research** on first launch and sets it active. Run a conversation-detail job and every result is auto-imported into that case. You can keep accumulating multiple job runs — dedupe is handled by primary key, and each run's provenance is preserved in the `imports` / `core_runs` tables.

To start a separate investigation, open the Case Manager and click **New Case**. Name it, and it becomes the active case.

### 2. Import a Core run

Runs triggered from the app are auto-imported into the active case. To import a historical run, select a completed `Genesys.Core` run folder from the Recent Runs list and click **Import to Case**. Progress appears in the status bar; details go to the Run Console tab.

### 3. Pivot without re-querying Genesys Cloud

Once imported, the grid switches to **case-store mode**. All filter and page operations execute SQL queries against the local database — no Genesys Cloud calls are made. Use the filter bar to narrow results:

| Control | Filter |
| --- | --- |
| Date/time pickers | `conversation_start` range (apply date with picker; apply custom time with Enter) |
| Direction | inbound / outbound |
| Media type | voice / chat / email / … |
| Queue | substring match |
| Disconnect type | exact match |
| Agent | substring match on agent names |
| Search box | conversation ID, queue name, or agent name |

### 4. Save views and create findings

When you have a useful filter combination, click **Save View** in the Case Manager to persist the filter snapshot. Named views are listed per case and can be revisited across sessions.

Use **New Finding** to record a conclusion, severity, status, and supporting evidence_json. Findings are stored in the case and persist independently of the filter state.

Bookmark individual conversations via the drilldown panel for quick reference.

### 5. Generate and save reports

Click **Impact Report** to generate an aggregate summary over the currently filtered set. Use **Save Snapshot** to persist the report HTML/CSV inside the case for later reference or handoff.

### 6. Refresh with additional runs

Import a second Core run into the same case to extend coverage. Each import is recorded with its source run folder; provenance is preserved across refreshes.

### 7. Close, archive, or purge

When the investigation is complete, use the Case Manager to:

- **Close** — mark the case as resolved; data is retained.
- **Archive** — move to archived state; data is retained for long-term reference.
- **Mark Purge-Ready** → **Purge** — permanently remove all case data from the local store when retention policy requires it.

The case audit trail records every state transition with a timestamp.

---

## Tests

Run the full repo guardrail suite from the root:

```powershell
pwsh -NoProfile -File ./tests/Invoke-AllTests.ps1
```

That runner executes:

- Static compliance checks in `tests/Test-Compliance.ps1`
- Architecture/layout invariants for startup, boundaries, indexing, export, reporting, and case-store design

## Design Intent

- `App.CoreAdapter.psm1` is the only module allowed to interact with `Genesys.Core`
- `App.Auth.psm1` contains all direct OAuth calls
- `App.Index.psm1` and `App.Export.psm1` are streaming-oriented and avoid large full-file reads
- `App.Database.psm1` owns the case-store schema and persistence
- `App.Reporting.psm1` computes filtered aggregate reports without re-reading raw data files
