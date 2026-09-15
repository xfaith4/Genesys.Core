# Get-GenesysMonthlyMetrics

> **PowerShell script that extracts a full month of operational and API-usage metrics from Genesys Cloud and exports a formatted, chart-embedded Excel workbook — ready for pivot analysis or executive reporting.**

[![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)](https://github.com/PowerShell/PowerShell)
[![Module](https://img.shields.io/badge/module-ImportExcel-green)](https://github.com/dfinke/ImportExcel)
[![API](https://img.shields.io/badge/Genesys%20Cloud-REST%20v2-orange)](https://developer.genesys.cloud/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Authentication Setup](#authentication-setup)
- [Usage](#usage)
  - [Parameters](#parameters)
  - [Examples](#examples)
- [Output Workbook](#output-workbook)
- [Covered Endpoints](#covered-endpoints)
- [Architecture](#architecture)
- [Permissions](#permissions)
- [Supported Regions](#supported-regions)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This script provides a single-command extraction of monthly metrics across Genesys Cloud's analytics, flow execution, conversation, and API usage planes. It authenticates via OAuth2 Client Credentials, fans out across seven endpoint families plus dedicated conversation reporting aggregates, normalises the nested aggregate response shape into flat, pivot-ready rows, and writes a multi-sheet `.xlsx` workbook with embedded charts.

**What you get in one run:**

| Metric Domain | KPIs Captured |
|---|---|
| Conversations | Offered, Answered, Abandoned, Handle Time, Talk Time, ACW, Transfers |
| Monthly Reporting Totals | Previous-month totals by originating direction, media type, and message type |
| Voice Concurrency | Peak concurrent inbound and outbound voice conversations |
| Flow Executions | Execution counts, time-in-flow, outcomes, exit reasons by flow type |
| Actions | Invocation counts and durations by action and action type |
| API Usage (org) | Daily call counts per endpoint template and HTTP method |
| API Usage (client) | Scoped view for a single OAuth client *(optional)* |
| Usage Events | Event counts mapped to the platform event definition catalog |

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|---|---|---|
| PowerShell | 7.2 | Required for null-coalescing `??` operator and `?.` member access |
| [ImportExcel](https://github.com/dfinke/ImportExcel) | 7.8 | Community module; no Excel installation required |
| Genesys Cloud tenant | Any edition | With API access enabled |
| OAuth2 Client | Client Credentials grant | See [Authentication Setup](#authentication-setup) |

> **Note:** PowerShell 5.1 (Windows) is **not** supported. The script uses null-conditional operators introduced in PowerShell 7.

---

## Installation

```powershell
# 1. Clone the repository
git clone https://github.com/<your-org>/Get-GenesysMonthlyMetrics.git
cd Get-GenesysMonthlyMetrics

# 2. Install the required module (current user, no admin required)
Install-Module ImportExcel -Scope CurrentUser -Force

# 3. Verify
Get-Module -ListAvailable ImportExcel
```

---

## Authentication Setup

The script uses the **OAuth2 Client Credentials** grant — no browser, no user login, suitable for scheduled/headless execution.

**In the Genesys Cloud Admin UI:**

1. Navigate to **Admin → Integrations → OAuth**
2. Click **Add Client**
3. Set **Grant Type** → `Client Credentials`
4. Assign the roles listed under [Permissions](#permissions)
5. Copy the **Client ID** and **Client Secret**

> ⚠️ The Client Secret is shown only once. Store it in a secrets manager (e.g., Windows Credential Manager, Azure Key Vault, HashiCorp Vault) rather than in plain text.

**Storing the secret securely for interactive use:**

```powershell
# Prompt without echo — stores as SecureString in memory only
$secret = Read-Host -AsSecureString "Genesys Client Secret"
```

**For scheduled/automated runs, retrieve from Windows Credential Manager:**

```powershell
$cred   = Get-StoredCredential -Target 'GenesysCloud'
$secret = $cred.Password  # Already a SecureString
```

---

## Usage

### Parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `ClientId` | `string` | ✅ | — | OAuth2 Client ID |
| `ClientSecret` | `SecureString` | ✅ | — | OAuth2 Client Secret |
| `Year` | `int` | | Current year | Target year (2000–2099) |
| `Month` | `int` | | Previous month | Target month (1–12) |
| `Region` | `string` | | `usw2.pure.cloud` | API region base URL |
| `OutputPath` | `string` | | `.` (current dir) | Directory for the output `.xlsx` file |
| `UsageClientId` | `string` | | *(empty)* | OAuth Client ID for per-client usage sheet. Omit to skip. |
| `JobPollIntervalSec` | `int` | | `5` | Seconds between async job status polls |
| `JobTimeoutSec` | `int` | | `300` | Maximum wait time for async jobs (seconds) |

### Examples

**Minimum — extract the previous calendar month:**

```powershell
.\Get-GenesysMonthlyMetrics.ps1 `
    -ClientId     "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
    -ClientSecret (Read-Host -AsSecureString "Client Secret")
```

**Specific month with custom output directory:**

```powershell
.\Get-GenesysMonthlyMetrics.ps1 `
    -ClientId     "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
    -ClientSecret (Read-Host -AsSecureString "Client Secret") `
    -Year         2025 `
    -Month        4 `
    -OutputPath   "C:\Reports\Genesys"
```

**Include per-client API usage sheet:**

```powershell
.\Get-GenesysMonthlyMetrics.ps1 `
    -ClientId       "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
    -ClientSecret   (Read-Host -AsSecureString "Client Secret") `
    -UsageClientId  "f9e8d7c6-b5a4-3210-fedc-ba9876543210"
```

**Non-US region (EU, Frankfurt):**

```powershell
.\Get-GenesysMonthlyMetrics.ps1 `
    -ClientId     "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
    -ClientSecret (Read-Host -AsSecureString "Client Secret") `
    -Region       "euw2.pure.cloud"
```

**Automated / scheduled run pulling credentials from Credential Manager:**

```powershell
$cred = Get-StoredCredential -Target 'GenesysCloud'
.\Get-GenesysMonthlyMetrics.ps1 `
    -ClientId     $cred.UserName `
    -ClientSecret $cred.Password `
    -OutputPath   "\\fileserver\reports\genesys"
```

**Verbose with extended async job timeout:**

```powershell
.\Get-GenesysMonthlyMetrics.ps1 `
    -ClientId            "a1b2c3d4-..." `
    -ClientSecret        (Read-Host -AsSecureString "Secret") `
    -JobPollIntervalSec  10 `
    -JobTimeoutSec       600 `
    -Verbose
```

---

## Output Workbook

The script writes a single file named `GenesysMetrics_YYYY-MM.xlsx` to the specified output directory.

### Sheet Reference

| Sheet | Table Name | Content | Chart |
|---|---|---|---|
| `Dashboard` | `tbl_KPIs` | KPI summary including monthly volume totals and peak concurrent inbound/outbound voice | — |
| `Monthly_Totals` | `tbl_MonthlyTotals` | Previous-month reporting totals by `originatingDirection`, `mediaType`, and `messageType` with normalized volume | — |
| `Voice_PeakConcurrent` | `tbl_VoicePeakConcurrent` | Peak `oConcurrent` voice values for inbound and outbound directions, with the source interval | — |
| `Conv_DailySummary` | `tbl_ConvDaily` | Daily totals by media type: Offered, Answered, Abandoned, Handle Time (ms) | 📈 Line — Offered vs Answered |
| `Conv_VolumeDetail` | `tbl_ConvVolumeDetail` | Full flattened metric rows with queue, originating direction, and media type dimensions | — |
| `FlowExecutions_Summary` | `tbl_FlowSummary` | Daily execution counts by flow type | 📊 Clustered column |
| `FlowExecutions_Detail` | `tbl_FlowDetail` | Raw metrics: `tFlow`, `tFlowOutcome`, `nFlow` with exit reason and flow ID | — |
| `Actions_Detail` | `tbl_ActionsDetail` | Action invocation stats (`tAction`, `nAction`) by action ID and type | — |
| `UsageEvent_Definitions` | `tbl_EventDefs` | Platform event catalog: ID, name, description, category, billing flag | — |
| `UsageEvents_Daily` | `tbl_UsageEvents` | Daily event counts mapped to definition names | — |
| `APIUsage_Daily` | `tbl_ApiUsageDaily` | Per-endpoint/method daily call volumes (org-wide async job) | — |
| `APIUsage_TopEndpoints` | `tbl_TopEndpoints` | Top 50 endpoints by total monthly call count | 📊 Horizontal bar |
| `ClientUsage_Daily` | `tbl_ClientUsage` | Per-client scoped usage *(only present when `-UsageClientId` is supplied)* | — |

### Working with the Data

All data lands in named Excel Tables (`tbl_*`). You can immediately insert PivotTables referencing those names without worrying about range drift:

1. Open the workbook → select any cell in a data table
2. **Insert → PivotTable → Use this table**
3. The table name auto-populates as the source

---

## Covered Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/v2/analytics/actions/aggregates/query` | Action invocation counts and durations |
| `POST` | `/api/v2/analytics/flowexecutions/aggregates/query` | IVR/bot flow execution metrics |
| `POST` | `/api/v2/analytics/conversations/aggregates/query` | Contact centre conversation KPIs |
| `GET` | `/api/v2/usage/events/definitions` | Platform usage event catalog |
| `POST` | `/api/v2/usage/events/aggregates/query` | Daily usage event counts |
| `POST` | `/api/v2/usage/aggregates/query/jobs` | Org-wide API usage (async) |
| `POST` | `/api/v2/usage/client/{clientId}/aggregates/query/jobs` | Per-client API usage (async, optional) |

Most analytics endpoints use `granularity: P1D` (daily buckets) over a full calendar-month interval in ISO 8601 format. The monthly reporting totals use `P1M`; peak concurrent voice uses `PT15M` by default through `-ConcurrencyGranularity`.

---

## Architecture

```
Get-GenesysMonthlyMetrics.ps1
│
├── ConvertFrom-SecureStringPlain   Safe plain-text extraction from SecureString
├── Write-Log                       Timestamped, colour-coded console output
├── Invoke-GenesysApi               Unified REST wrapper
│   └── Retry logic                 Exponential back-off on HTTP 429 and 5xx (max 5 attempts)
├── Wait-GenesysJob                 Async job poller with configurable interval and hard timeout
│   └── Pagination                  Follows nextUri through result pages
└── Expand-MetricStats              Flattens group → data[] → metrics[] → stats into flat rows
```

**Data flow:**

```
OAuth2 token
     │
     ▼
7× API calls ──► raw response objects
     │
     ▼
Expand-MetricStats / inline normalisers
     │
     ▼
Summary aggregation (Group-Object pipelines)
     │
     ▼
ImportExcel Export-Excel ──► GenesysMetrics_YYYY-MM.xlsx
                                 ├── Dashboard (KPIs)
                                 ├── *_Summary sheets + charts
                                 └── *_Detail sheets (pivot source)
```

**Resilience characteristics:**

- Exponential back-off: waits 2, 4, 8, 16, 32 seconds on successive failures
- Async job timeout is configurable; script throws a terminating error on breach rather than silently returning partial data
- `$ErrorActionPreference = 'Stop'` and `Set-StrictMode -Version Latest` ensure all errors are surfaced, not swallowed

---

## Permissions

The OAuth client requires the following Genesys Cloud permissions. Apply them via a custom role assigned to the OAuth client:

| Permission | Reason |
|---|---|
| `analytics:conversationAggregate:view` | Conversation aggregates endpoint |
| `analytics:flowExecutionAggregate:view` | Flow execution aggregates endpoint |
| `analytics:actionAggregate:view` | Actions aggregates endpoint |
| `usage:event:view` | Usage event definitions and aggregates |
| `usage:aggregate:view` | Org-wide and per-client usage job endpoints |

> Follow the principle of least privilege. Do not assign broad `admin` or `Master Admin` roles to a headless integration client.

---

## Supported Regions

Pass the region's base domain to `-Region`. Common values:

| Region | `-Region` value |
|---|---|
| US West 2 *(default)* | `usw2.pure.cloud` |
| US East | `use1.pure.cloud` |
| EU West (Ireland) | `euw1.pure.cloud` |
| EU West 2 (London) | `euw2.pure.cloud` |
| EU Central (Frankfurt) | `euc1.pure.cloud` |
| AP Southeast (Sydney) | `apse2.pure.cloud` |
| AP Northeast (Tokyo) | `apne1.pure.cloud` |
| CA Central | `cac1.pure.cloud` |

Full region list: [Genesys Cloud regions and AWS regions](https://help.mypurecloud.com/articles/aws-regions-for-genesys-cloud-deployment/)

---

## Troubleshooting

### `401 Unauthorized`
- Verify the Client ID and Secret are correct and have not been rotated
- Confirm the OAuth client uses the **Client Credentials** grant type
- Check the `-Region` matches the tenant's deployed region

### `403 Forbidden`
- The OAuth client's role is missing one or more required permissions (see [Permissions](#permissions))
- Some usage endpoints require the client to have been active in the target month

### Async job timeout (`Job timed out after Ns`)
- Increase `-JobTimeoutSec` (e.g., `-JobTimeoutSec 600`)
- Large organisations with high API volumes may need several minutes for usage jobs to complete

### `ImportExcel module not found`
```powershell
Install-Module ImportExcel -Scope CurrentUser -Force
```

### Empty sheets / no results
- Confirm the target `Year`/`Month` had activity in your org
- Check that the OAuth client has operated within that period (usage endpoints exclude clients with zero activity)
- Run with `-Verbose` to inspect the raw API responses

### Script fails on PowerShell 5.1
The script requires PowerShell 7.2+. Install from [github.com/PowerShell/PowerShell](https://github.com/PowerShell/PowerShell/releases).

---
Good — I have the full picture. Now I'll build the extended version. This is a significant rewrite — new collectors, new summary tables, new sheets, and an expanded dashboard — so I'll write it as a clean complete file.1,094 lines — here's a map of everything that changed and why each decision was made the way it was.

---

## What changed

### New parameters
Three new configurable thresholds so management can tune the report to their operation without touching code:
- `-ServiceLevelThresholdSec` (default 20) — drives the SL calculation and flags in the queue sheet
- `-OccupancyWarningPct` (default 88) — controls the HIGH/LOW/OK flag on every agent row
- `-ShortAbandonSec` (default 5) — classifies whether a queue's abandons are likely noise vs real service failures

### New helper functions
`Get-PagedResults` follows Genesys cursor pagination generically, used by both the queue and user roster calls. `Get-MetricSum` eliminates the repetitive one-liner pipelines in every summary block. `Write-Sheet` consolidates the Export-Excel + chart pattern into a single callable so the workbook section reads like a manifest rather than a wall of repeated formatting code.

### New API calls (5 additional)
| Endpoint | Purpose |
|---|---|
| `GET /api/v2/routing/queues` | Name resolution — every queue ID in the data maps to a readable name |
| `GET /api/v2/users` | Seat count + agent name map; active user count becomes the licensed seat denominator |
| `POST /api/v2/analytics/users/aggregates/query` (×2) | Occupancy metrics (`tAgentRoutable`, `tTalk`, `tAcw`) + status distribution by `routingStatus` |
| `POST /api/v2/analytics/queues/aggregates/query` | `oServiceLevel`, `nOverflowOut`, ASA per queue |
| `POST /api/v2/analytics/flows/aggregates/query` | `nFlowEntries`, `nFlowDisconnect` for containment rate |
| `POST /api/v2/analytics/bots/aggregates/query` | `nBotSessions`, `nBotEscalated`, intent match rate — wrapped in try/catch since bot licensing is optional |

The conversations query is now split into three targeted calls (volume, wrap-up, transfers) rather than one wide call, which keeps each query within Genesys's metric-per-request limits and makes the groupBy dimensions correct for each use case.

### New derived summary tables (9 additional sheets)
Each table computes what management actually reads rather than leaving raw stats for the recipient to process:
- **`Conv_AbandonDetail`** — flags whether a queue's average abandon wait is below the short-abandon threshold, separating IVR/misdial noise from genuine queue failures
- **`Queue_ServiceLevel`** — ASA, SL%, overflow rate per queue, `BelowTarget` boolean pre-sorted to the top so problem queues are row 1
- **`Conv_TransferAnalysis`** — blind vs consult split by queue, transfer rate as a percentage of answered
- **`Conv_WrapUpCodes`** — monthly disposition distribution, sorted by volume
- **`Agent_Occupancy`** — per-agent occupancy %, routable/talk/ACW hours, not-responding count, HIGH/LOW/OK flag
- **`Agent_StatusBreakdown`** — raw routing status time distribution for coaching conversations
- **`Platform_SeatUtil`** — daily active agent count vs licensed seats with utilisation %; `peakDayAgents` feeds the Dashboard
- **`IVR_Containment`** — per-flow containment rate with exit reason distribution in a single column
- **`Bot_Containment`** — session count, escalation rate, intent match rate per bot ID

### Dashboard expansion
The KPI table gained a `Category` column (Volume / Quality / Efficiency / Self-Service / Platform) and a `Note` field so the recipient sees context inline — "Target <5%", "Warn >88%", "80% in 20s" — without needing a separate legend. 21 KPIs across 5 categories, all computed from live data.

## Contributing

Contributions are welcome. Please follow these steps:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Commit your changes with a descriptive message: `git commit -m "Add queue-level breakdown to conversation summary"`
4. Push to your fork: `git push origin feature/your-feature-name`
5. Open a Pull Request against `main`

**Before submitting:**
- Test against at least one live Genesys Cloud tenant
- Ensure `-Verbose` output remains informative and timestamped
- Do not commit credentials, tokens, or tenant-specific data
- Update this README if you add or change parameters or output sheets

---

## License

MIT — see [LICENSE](LICENSE) for full terms.

---

*Built against the [Genesys Cloud REST API v2](https://developer.genesys.cloud/). Not affiliated with or endorsed by Genesys.*
