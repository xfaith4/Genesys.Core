# Genesys Conversation Analysis — Web Tool

A self-contained, single-file HTML web application for exploring, filtering, and
drilling down into Genesys Cloud conversation analytics data produced by
**Genesys.Core**'s `Invoke-Dataset` command.

---

## Purpose

This tool provides an analyst-friendly UX layer over Core run artifacts —
the same JSONL data files written by `Invoke-Dataset` under
`out/<datasetKey>/<runId>/data/`.  It requires **no server**, no build step,
and no additional dependencies beyond a modern web browser.

---

## Quick Start

### 1 — Run an extraction with Genesys.Core

```powershell
# Preview run (synchronous POST query, fast feedback)
Invoke-Dataset `
  -Dataset 'analytics-conversation-details-query' `
  -CatalogPath  '.\catalog\genesys.catalog.json' `
  -OutputRoot   "$env:LOCALAPPDATA\GenesysCore\runs" `
  -BaseUri      'https://api.mypurecloud.com' `
  -Headers      @{ Authorization = "Bearer $env:GENESYS_BEARER_TOKEN" } `
  -DatasetParameters @{ interval = '2026-03-05T00:00:00Z/2026-03-05T23:59:59Z' }

# Full run (async job — handles 100k+ conversations)
Invoke-Dataset `
  -Dataset 'analytics-conversation-details' `
  -CatalogPath  '.\catalog\genesys.catalog.json' `
  -OutputRoot   "$env:LOCALAPPDATA\GenesysCore\runs" `
  -BaseUri      'https://api.mypurecloud.com' `
  -Headers      @{ Authorization = "Bearer $env:GENESYS_BEARER_TOKEN" } `
  -DatasetParameters @{ interval = '2026-03-01T00:00:00Z/2026-03-05T23:59:59Z' }
```

### 2 — Open the web tool

```
apps/ConversationAnalysis/index.html
```

Open in any modern browser (Chrome, Edge, Firefox, Safari).

### 3 — Load the run data

- Click **📂 Load Run** (or the drop zone)
- Navigate to `out/analytics-conversation-details/<runId>/data/`
- Select **all `*.jsonl` files** (Ctrl+A) and click Open
- Optionally also select `manifest.json` from the run folder root

The tool indexes and renders results immediately — no server round-trip.

---

## Features

### Dashboard

| Section | Details |
|---------|---------|
| **KPI Strip** | Total conversations, Avg Handle Time, Avg Talk Time, Inbound Rate, Voice %, Holds %, Avg MOS, Unique Queues |
| **Volume by Hour** | Bar chart of conversation start times across 24-hour window |
| **Media Type Distribution** | Donut chart: voice, chat, email, message, etc. |
| **Top Queues by Volume** | Horizontal bar chart of busiest 12 queues |
| **Disconnect Reasons** | Donut chart of all disconnect type codes |
| **Handle Time Distribution** | Histogram: bucket conversations by duration |

### Conversation Grid

| Feature | Details |
|---------|---------|
| **Default Columns** | Conv ID · Start Time · Duration · Direction · Media · Queue · **Flow Name** · Disconnect · MOS · Participants · **Divisions** · **Agent Name** |
| **Optional Columns** | End Time · Trunk/Provider · Error Code · Agent User ID (via ⚙ Columns picker) |
| **Paging** | 25 / 50 / 100 / 250 per page with First/Prev/Next/Last + page buttons |
| **Sorting** | Click any column header; toggle asc/desc |
| **Search** | Fuzzy match on conv ID, queue name, participant name, direction, disconnect type |
| **Quick Filters** | Inbound · Outbound · Voice Only · Has MOS · Has Holds · Disconnected |
| **Context Menu** | Copy Conversation ID · Copy Key Fields · Open Drilldown · Export as JSON |
| **Keyboard** | `←` / `→` navigate pages; `Esc` closes drilldown |

### Conversation Drilldown Panel

Slide-in panel with 7 tabs:

| Tab | Content |
|-----|---------|
| **Summary** | Key timestamps, duration, direction, queue, flow name, agent names, hold time, division IDs · **📊 View Timeline** button |
| **Participants** | Purpose, name, userId, ANI/DNIS, media type, session count |
| **Segments** | Chronological timeline — type, participant, queue, duration, disconnect, wrap-up |
| **🕐 Timeline** | **3D visual conversation timeline** — per-participant lanes, color-coded segment bars, MOS/latency badges, problem area highlighting |
| **Attributes** | Custom key/value attribute pairs on the conversation |
| **MOS / Quality** | Per-session MOS bar meters + sentiment/quality signals if present |
| **Raw JSON** | Full pretty-printed JSON viewer with one-click Copy |

#### Timeline View Features

The **🕐 Timeline** tab renders a rich interactive visualization of the full conversation:

- **Per-participant lanes** — each participant (customer, agent, ACD, etc.) gets its own horizontal lane with a color-coded left border
- **3D segment bars** — colored, raised bars representing each segment type (Talk/Hold/Routing/Wrap-up/Alert/Dialing/Contacting) positioned proportionally on a time axis with hover tooltips
- **Problem highlighting** — lanes with low MOS (< 3.5), high latency (> 150 ms), or error codes get a hatched red overlay and warning badges
- **Quality badges** — each lane shows MOS score (green if ≥ 3.5, red if < 3.5), latency (⚡ if > 150 ms), and error codes
- **Footer stats** — total duration, participant count, min MOS, max latency, error count

### Exports

| Export | Details |
|--------|---------|
| **Export Page** | Current page rows → CSV |
| **Export Filtered → CSV** | All filtered conversations as flat CSV (nav button) |
| **Export All → JSON** | All filtered conversations as JSON array |
| **Export Single** | Right-click a row → Export as JSON (one conversation) |

---

## Architecture

```
apps/ConversationAnalysis/
└── index.html          # Self-contained SPA — HTML + CSS + JS (no build required)
                        # Single external dependency: Chart.js 4.x via CDN
```

### Module Boundaries (Core-first)

```
Genesys.Core (Invoke-Dataset)
    └── writes → out/<datasetKey>/<runId>/data/*.jsonl
                     ↓  (file-picker / drag-drop)
          index.html  (browser FileReader API)
              ├── Indexes records in memory (lightweight key fields only)
              ├── Renders KPI cards + 5 Chart.js charts
              ├── Renders paged, filterable, sortable grid
              └── Renders drilldown panel on row click
```

**No direct Genesys API calls are made by this tool.**
All data comes from Core run artifact files.

---

## Performance Notes

- **Indexing**: on load, a lightweight index (key fields only) is built from all records.
  Paging and filtering operate on the index (~O(n) scan once, then O(pageSize) per page).
- **Memory**: full record objects are kept in `State.allRecords`; the index holds only
  scalar fields needed for the grid and filters.
- **Large runs**: For runs > 200 MB, consider splitting `data/*.jsonl` into batches and
  loading the tool multiple times, or run the PowerShell indexer helper first.
- **Charts** aggregate from the index (not the full records) for speed.

---

## Compliance

The tool satisfies all Genesys.Core App Compliance Gates:

| Gate | Status |
|------|--------|
| **Gate A** — No direct REST calls in app code | ✅ Browser FileReader only |
| **Gate B** — No `/api/v2/` literals in app code | ✅ Verified by `ConversationAnalysis.Compliance.Tests.ps1` |
| **Gate C** — No local copy of Genesys.Core | ✅ Not included in app folder |
| **Gate D** — Mechanical compliance tests | ✅ `tests/unit/ConversationAnalysis.Compliance.Tests.ps1` |

---

## Browser Requirements

| Browser | Minimum Version |
|---------|-----------------|
| Chrome / Edge | 90+ |
| Firefox | 88+ |
| Safari | 14+ |

Requires: `FileReader API`, `Blob/URL.createObjectURL`, `navigator.clipboard` (with HTTPS or localhost).
