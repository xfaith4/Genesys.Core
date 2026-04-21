# Genesys Ops Console

A single-file browser dashboard that surfaces the **Phase 5 Visibility Dashboard** features
delivered in `Genesys.Ops`. It consumes JSON artifacts exported from the Ops-layer cmdlets
and requires **no server, no build step, and no direct Genesys API access**.

---

## Quick start

1. Run the PowerShell export commands below to generate JSON files.
2. Open `index.html` in Chrome, Edge, Firefox, or Safari.
3. Click ** Demo Data** to preview all dashboards instantly with sample data, or drag-and-drop
   your JSON files onto the appropriate tab's load zone.

---

## Tabs and data sources

### 🏠 Overview — `ops-report.json`

Composite snapshot covering abandon rates, SLA compliance, edge/trunk health,
active alerts, and WebRTC disconnect errors.

```powershell
# Generate with Genesys.Ops
Invoke-GenesysOperationsReport -OutputPath "ops-report.json"
```

Shows:

- KPI strip: avg abandon rate, avg SLA 30 s %, edges online, trunks active, active alert count, WebRTC error count
- Service level status donut chart
- WebRTC disconnects by error code bar chart
- Edge & trunk health panel, contact centre status, organisation info
- Active alerts list

---

### 🏥 Queue Health — `queue-health.json`

Per-queue GREEN / AMBER / RED health snapshot combining real-time observations
with SLA performance.

```powershell
Get-GenesysQueueHealthSnapshot | ConvertTo-Json -Depth 5 | Set-Content "queue-health.json"
```

Shows:

- KPI strip: total queues, green/amber/red counts, average SLA
- SLA 30-second % bar chart (colour-coded green/amber/red per threshold)
- Searchable, filterable table with waiting, interacting, on-queue agents

---

### 📉 Abandon Rates — `abandon-dashboard.json`

Per-queue abandon rate dashboard combining historical aggregates with real-time
waiting counts.

```powershell
Get-GenesysAbandonRateDashboard | ConvertTo-Json -Depth 5 | Set-Content "abandon-dashboard.json"
```

Shows:

- KPI strip: total offered, total abandoned, avg abandon rate, queues above 10 %
- Horizontal bar chart sorted highest → lowest (red >10 %, amber 5–10 %, green <5 %)
- Detail table with offered, abandoned, rate, avg abandon time, real-time waiting

---

### 👤 Agent Quality — `agent-quality.json`

Per-agent KPI leaderboard for handle time, talk time, and ACW.

```powershell
Get-GenesysAgentQualitySnapshot | ConvertTo-Json -Depth 5 | Set-Content "agent-quality.json"
```

Shows:

- KPI strip: total agents, total conversations, avg handle/talk/ACW
- Top-12 handle time vs ACW grouped bar chart
- Sortable, searchable leaderboard table with rank badges

---

### 🌐 Edge & Trunks — `edge-health.json`

Edge appliance and SIP trunk health snapshot.

```powershell
Get-GenesysEdgeHealthSnapshot | ConvertTo-Json -Depth 5 | Set-Content "edge-health.json"
```

Shows:

- KPI strip: edges online/offline, trunks active/inactive, snapshot time
- Edge status donut chart (online vs offline)
- Trunk status donut chart (active vs inactive)
- Offline edge names list with warning callout

---

### 🔔 Change Audit — `change-audit.json`

Risk-classified feed of admin configuration changes.

```powershell
# All changes in the last hour (catalog default window)
Get-GenesysChangeAuditFeed | ConvertTo-Json -Depth 5 | Set-Content "change-audit.json"

# High-risk only
Get-GenesysChangeAuditFeed -Risk HIGH | ConvertTo-Json -Depth 5 | Set-Content "change-audit.json"

# Filter by entity type
Get-GenesysChangeAuditFeed -EntityType FLOW | ConvertTo-Json -Depth 5 | Set-Content "change-audit.json"
```

Shows:

- KPI strip: total events, high/medium/low risk counts
- Searchable, filterable table with timestamp, risk badge, entity type, action, actor, summary
- Risk filter chips (All / High / Medium / Low)

---

## Export all at once

```powershell
# Run all exports in a single session after connecting to Genesys Cloud

Invoke-GenesysOperationsReport -OutputPath "ops-report.json"

Get-GenesysQueueHealthSnapshot  | ConvertTo-Json -Depth 5 | Set-Content "queue-health.json"
Get-GenesysAbandonRateDashboard | ConvertTo-Json -Depth 5 | Set-Content "abandon-dashboard.json"
Get-GenesysAgentQualitySnapshot | ConvertTo-Json -Depth 5 | Set-Content "agent-quality.json"
Get-GenesysEdgeHealthSnapshot   | ConvertTo-Json -Depth 5 | Set-Content "edge-health.json"
Get-GenesysChangeAuditFeed      | ConvertTo-Json -Depth 5 | Set-Content "change-audit.json"
```

---

## Compliance

- No direct REST calls to `/api/v2/` — all data is pre-fetched via `Genesys.Ops` cmdlets
- No copy of `Genesys.Core` or `Genesys.Ops` modules included
- No server, framework, or build tool required — open `index.html` directly in a browser
- Only external dependency: **Chart.js 4.4.4** loaded via CDN (`cdn.jsdelivr.net`) for charts

## Browser support

Chrome 90+, Edge 90+, Firefox 90+, Safari 15.4+

> **Note:** These minimums are set by Chart.js 4.x's reliance on ES2020 features (optional
> chaining, nullish coalescing, `Promise.allSettled`) and the app's own use of ES2020+. Safari
> 14 and earlier lack reliable support for all required ES2020 built-ins.
