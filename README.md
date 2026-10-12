# Genesys.Core

> A catalog-driven PowerShell execution engine optimizing Genesys Cloud data collection for automation and audit.

[![CI](https://github.com/xfaith4/Genesys.Core/actions/workflows/ci.yml/badge.svg)](https://github.com/xfaith4/Genesys.Core/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE) [![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue)](https://github.com/PowerShell/PowerShell)

## Overview

Genesys.Core streamlines data extraction from Genesys Cloud REST API, handling pagination, rate limits, and ensuring data security. It operates via a JSON catalog, separating operational logic from scripts and enabling consistent, auditable output suitable for compliance and CI. Featured investigations include Agent, Conversation, and Queue analyses, providing comprehensive insights tailored to individual users or instances.

## Product direction

Start with [conversation investigation and evidence export](docs/CONVERSATION_INVESTIGATION_PACKAGE.md).
Use the [Genesys Data Client](apps/GenesysDataClient/README.md) for the modern web experience.
See the [roadmap](ROADMAP.md), [feature-value assessment](docs/PRODUCT_VALUE.md), and
[reconciliation report](docs/REPOSITORY_RECONCILIATION.md) for current priorities and proof boundaries.

## Features

- **Catalog-driven**: 111 datasets and 3,389 endpoint definitions, schema-validated.
- **Paging strategies**: Adjustable per endpoint, supporting six types.
- **Retry engine**: Configurable, with jitter and `Retry-After` parsing.
- **Async transactions**: Efficient logging and analytics job handling.
- **Output contract**: Consistent artifact generation per run.
- **Investigations**: Emissions of structured datasets for agents, conversations, and queues.
- **Integration**: GitHub Actions workflows, ready-made apps, operator dashboards.
- **Security**: Redaction of sensitive information from logs.
- **Accessibility**: Automated accessibility checks run in CI; manual conformance checks remain open.
- **Compatibility**: Supports Windows PowerShell 5.1 and PowerShell 7+.

## Quickstart

### 1. Setup

Import the module:

```powershell
Set-Location <path-to-Genesys.Core>
Import-Module ./modules/Genesys.Core/Genesys.Core.psd1 -Force
```

Acquire an OAuth token:

```powershell
$region = 'usw2.pure.cloud'
$authResponse = Invoke-RestMethod -Uri "https://login.$($region)/oauth/token" -Method POST -Body @{
    grant_type = 'client_credentials'
    client_id = '<your-client-id>'
    client_secret = '<your-client-secret>'
} -ContentType 'application/x-www-form-urlencoded'

$baseUri = "https://api.$($region)"
$headers = @{ Authorization = "Bearer $($authResponse.access_token)" }
```

### 2. Run

Execute a dataset run:

```powershell
Invoke-Dataset -Dataset 'users' -OutputRoot './out' -BaseUri "https://api.$($region)" -Headers $headers
```

For agent investigation:

```powershell
Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1 -Force
Connect-GenesysCloud -AccessToken $authResponse.access_token -Region $region
Get-GenesysAgentInvestigation -UserId '<genesys-user-guid>' -Since (Get-Date).AddDays(-7) -OutputRoot './out'
```

Inspect run output:

```powershell
$runFolder = Get-ChildItem './out/users' -Directory | Sort-Object Name -Descending | Select-Object -First 1
Get-Content (Join-Path $runFolder.FullName 'summary.json') | ConvertFrom-Json
```

## Local mock server

Use the mock server to try API requests and dataset runs with demo data, without
Genesys Cloud credentials. Install the **.NET 8 SDK** first; the PowerShell launcher
also requires PowerShell 7+ (`pwsh`). Run these commands from the repository root.

### Launch

Start the server in its own terminal:

```powershell
pwsh -NoProfile -File ./scripts/Start-MockServer.ps1
```

Or launch it directly with the .NET CLI:

```bash
dotnet run --project tools/Genesys.MockServer
```

The default address is `http://localhost:7777`. Keep the terminal open and press
**Ctrl+C** to stop the server. To use a different port, pass `-Port 8888` to the
PowerShell launcher and update the base URL in the requests below.

### Make requests with PowerShell

Open a second terminal. Health and discovery requests do not require authentication;
all `/api/**` requests require a bearer token. The fixed demo token below works
without obtaining an OAuth token first.

```powershell
$baseUri = 'http://localhost:7777'
$headers = @{ Authorization = 'Bearer demo-bearer-token-genesys-testplatform' }

# Check that the server is running.
Invoke-RestMethod -Uri "$baseUri/health"

# Read the demo identity and the first page of users.
Invoke-RestMethod -Uri "$baseUri/api/v2/users/me" -Headers $headers
$users = Invoke-RestMethod -Uri "$baseUri/api/v2/users?pageSize=25&pageNumber=1" -Headers $headers
$users.entities

# Follow the returned nextUri to retrieve the next page, when present.
if ($users.nextUri) {
    Invoke-RestMethod -Uri "$baseUri$($users.nextUri)" -Headers $headers
}

# Discover endpoints backed by demo data.
Invoke-RestMethod -Uri "$baseUri/__meta/endpoints?demoData=true&limit=10"

# Send a JSON POST request.
$body = @{ interval = '2026-01-01T00:00:00.000Z/2026-01-02T00:00:00.000Z' } | ConvertTo-Json
Invoke-RestMethod -Uri "$baseUri/api/v2/analytics/conversations/details/query" `
    -Method Post -Headers $headers -ContentType 'application/json' -Body $body
```

To exercise token acquisition, the mock token endpoint accepts this form request
and returns the fixed demo token; no real client credentials are needed:

```powershell
$authResponse = Invoke-RestMethod -Uri "$baseUri/oauth/token" -Method Post `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type = 'client_credentials' }
$headers = @{ Authorization = "Bearer $($authResponse.access_token)" }
```

Run a Genesys.Core dataset against the same server:

```powershell
Import-Module ./modules/Genesys.Core/Genesys.Core.psd1 -Force
Invoke-Dataset -Dataset 'users' -BaseUri $baseUri -Headers $headers -OutputRoot './out/mock'
```

### Make requests with curl

From Bash, or using `curl.exe` on Windows:

```bash
curl "http://localhost:7777/health"
curl -H "Authorization: Bearer demo-bearer-token-genesys-testplatform" "http://localhost:7777/api/v2/users?pageSize=25&pageNumber=1"
curl -X POST -d "grant_type=client_credentials" "http://localhost:7777/oauth/token"
```

The server returns fixture data for supported demo routes and empty generated
responses for other catalog routes. See the [mock server guide](tools/Genesys.MockServer/README.md)
for coverage, configuration, async jobs, and browser OAuth/PKCE details.

## Installation

**Requirements**:

| Requirement        | Version                  |
| ------------------ | ------------------------ |
| Windows PowerShell | 5.1                      |
| PowerShell         | 7+                       |
| Pester (tests)     | 5.x                      |
| Network            | Genesys Cloud API access |

**Steps**:

```powershell
git clone https://github.com/xfaith4/Genesys.Core.git
Set-Location Genesys.Core
Import-Module ./modules/Genesys.Core/Genesys.Core.psd1 -Force
```

## Usage

List available datasets:

```powershell
$catalog = Get-Content -Raw ./catalog/genesys.catalog.json | ConvertFrom-Json
$catalog.datasets.PSObject.Properties.Name | Sort-Object
```

Common datasets:

```powershell
Invoke-Dataset -Dataset 'audit-logs' -OutputRoot './out' -BaseUri $baseUri -Headers $headers
Invoke-Dataset -Dataset 'analytics-conversation-details' -OutputRoot './out' -BaseUri $baseUri -Headers $headers
```

## Configuration

### Environment Variables

| Name                   | Description                              |
| ---------------------- | ---------------------------------------- |
| `GENESYS_BEARER_TOKEN` | OAuth token for GitHub Actions workflows |

### Key Parameters

| Parameter     | Description                               |
| ------------- | ----------------------------------------- |
| `-Dataset`    | Catalog dataset key                       |
| `-OutputRoot` | Root folder for output (default: `./out`) |
| `-BaseUri`    | Genesys Cloud API base URI                |
| `-Headers`    | Authorization headers                     |
| `-WhatIf`     | Validates without API calls               |

### Adaptive rate-limit pacing

Core automatically learns from HTTP 429 responses. It tracks each server, HTTP
method, and catalog endpoint key, so later pages and resource IDs share the same
pacing history. The first 429 introduces a one-second minimum interval; further
429s double it up to 60 seconds. Twenty successful requests reduce the interval
by ten percent, with a 100 ms floor once an endpoint has been throttled.

Every 429 also sets a shared cooldown for that server. `Retry-After` (seconds or
HTTP date) is a minimum wait, even when it exceeds the retry profile's delay cap.
Core also recognizes the service message “Retry the request in [x] seconds”.
Existing retry counts and POST retry permissions still apply.

During `Invoke-Dataset`, observations are immediately written to
`out/<dataset>/<runId>/rate-limits.jsonl`, including when the run fails. Each record
contains the UTC timestamp, endpoint key, method, observed cooldown, learned
interval, and cumulative session 429 count. Buffered run events also include
`request.rateLimit.observed` and `request.rateLimit.wait` when those events are
flushed to `events.jsonl`.

Pacing history lasts for the loaded Core module session and is shared across its
dataset calls. It resets when the module is reloaded or the process restarts;
the journal is retained as evidence but is not automatically replayed. Separate
processes, runspaces, and browser clients do not coordinate their request budgets.
Adaptive pacing reduces repeated throttling; live tenant validation is still needed.

## Accessibility

The operator consoles, dataset browser, documentation pages, and generated
investigation reports have automated checks targeting **WCAG 2.1 Level AA** in CI.
A passing automated audit does not establish full conformance; rendered and manual
checks are tracked separately.

```powershell
pwsh -NoProfile -File ./scripts/Invoke-AccessibilityAudit.ps1
```

The analyzer in `tools/Genesys.Accessibility` is dependency-free PowerShell, so
the audit runs offline on Windows PowerShell 5.1 and PowerShell 7+ with no
Node/npm toolchain. See [docs/ACCESSIBILITY.md](./docs/ACCESSIBILITY.md) for the
conformance statement, the enforced rule set, and the manual checklist covering
criteria that require a rendered viewport.

## License

[MIT License](./LICENSE)
