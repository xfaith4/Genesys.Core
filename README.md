# Genesys.Core

> A catalog-driven PowerShell execution engine optimizing Genesys Cloud data collection for automation and audit.

[![CI](https://github.com/xfaith4/Genesys.Core/actions/workflows/ci.yml/badge.svg)](https://github.com/xfaith4/Genesys.Core/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE) [![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue)](https://github.com/PowerShell/PowerShell)


## Overview

Genesys.Core streamlines data extraction from Genesys Cloud REST API, handling pagination, rate limits, and ensuring data security. It operates via a JSON catalog, separating operational logic from scripts and enabling consistent, auditable output suitable for compliance and CI. Featured investigations include Agent, Conversation, and Queue analyses, providing comprehensive insights tailored to individual users or instances.

## Features

- **Catalog-driven**: 31 datasets and 74 endpoint definitions, schema-validated.
- **Paging strategies**: Adjustable per endpoint, supporting six types.
- **Retry engine**: Configurable, with jitter and `Retry-After` parsing.
- **Async transactions**: Efficient logging and analytics job handling.
- **Output contract**: Consistent artifact generation per run.
- **Investigations**: Emissions of structured datasets for agents, conversations, and queues.
- **Integration**: GitHub Actions workflows, ready-made apps, operator dashboards.
- **Security**: Redaction of sensitive information from logs.
- **Accessibility**: All shipped HTML surfaces conform to WCAG 2.1 Level AA, gated in CI.
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

## Installation

**Requirements**:

| Requirement       | Version |
| ----------------- | ------- |
| Windows PowerShell| 5.1     |
| PowerShell        | 7+      |
| Pester (tests)    | 5.x     |
| Network           | Genesys Cloud API access |

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

| Name                  | Description                                      |
| --------------------- | ------------------------------------------------ |
| `GENESYS_BEARER_TOKEN`| OAuth token for GitHub Actions workflows         |

### Key Parameters

| Parameter         | Description                       |
| ----------------- | --------------------------------- |
| `-Dataset`        | Catalog dataset key               |
| `-OutputRoot`     | Root folder for output (default: `./out`) |
| `-BaseUri`        | Genesys Cloud API base URI        |
| `-Headers`        | Authorization headers             |
| `-WhatIf`         | Validates without API calls       |

## Accessibility

The operator consoles, dataset browser, documentation pages, and generated
investigation reports are held to **WCAG 2.1 Level AA**. Conformance is enforced
on every pull request by the `accessibility` CI job.

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