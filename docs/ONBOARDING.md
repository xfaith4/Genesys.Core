# Genesys.Core Onboarding

This guide describes how to run the repository as it exists today.

## What you get today

- PowerShell module execution via `Invoke-Dataset`.
- Catalog-driven dataset routing from `genesys-core.catalog.json`.
- Deterministic outputs under `out/<datasetKey>/<runId>/`.
- Windows GUI client (`GenesysCore-GUI.ps1`) for interactive use.

This repo is not a packaged MCP server today.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+.
- Network access to Genesys Cloud API for live runs.
- OAuth client credentials with permissions for the endpoints your datasets use.

## 1. Open the repo

```powershell
Set-Location <path-to-Genesys.Core>
```

## 2. Import the module

```powershell
Import-Module ./src/ps-module/Genesys.Core/Genesys.Core.psd1 -Force
Get-Command -Module Genesys.Core
```

Expected exported commands:

- `Invoke-Dataset`
- `Assert-Catalog`

## 3. Inspect available dataset keys

```powershell
$catalog = Get-Content -Raw ./genesys-core.catalog.json | ConvertFrom-Json
$catalog.datasets.PSObject.Properties.Name | Sort-Object
```

## 4. Validate catalog before first run

```powershell
Assert-Catalog -SchemaPath ./catalog/schema/genesys-core.catalog.schema.json
```

## 5. Acquire OAuth token (client credentials)

```powershell
$region = 'usw2.pure.cloud'
$authUrl = "https://login.$region/oauth/token"
$baseUri = "https://api.$region"

$clientId = '<client-id>'
$clientSecret = '<client-secret>'

$authResponse = Invoke-RestMethod -Uri $authUrl -Method POST -Body @{
    grant_type = 'client_credentials'
    client_id = $clientId
    client_secret = $clientSecret
} -ContentType 'application/x-www-form-urlencoded'

$headers = @{
    Authorization = "Bearer $($authResponse.access_token)"
}
```

## 6. Do a dry run first

```powershell
Invoke-Dataset -Dataset 'audit-logs' -WhatIf
```

## 7. Execute a dataset

```powershell
Invoke-Dataset -Dataset 'users' -OutputRoot './out' -BaseUri $baseUri -Headers $headers
```

## 8. Inspect run output

```powershell
$datasetKey = 'users'
$runFolder = Get-ChildItem -Path "./out/$datasetKey" -Directory | Sort-Object Name -Descending | Select-Object -First 1

Get-Content (Join-Path $runFolder.FullName 'manifest.json') -Raw | ConvertFrom-Json
Get-Content (Join-Path $runFolder.FullName 'summary.json') -Raw | ConvertFrom-Json
Get-Content (Join-Path $runFolder.FullName 'events.jsonl')
```

## Optional: Windows GUI flow

```powershell
.\GenesysCore-GUI.ps1
```

GUI behavior:

- Authenticates using region/client ID/client secret.
- Lists dataset keys from the catalog.
- Runs selected datasets through `Invoke-Dataset`.

## Important current limitations

- Script-level invocation supports `-BaseUri`, `-Headers`, and `-DatasetParameters` for automation scenarios.
- Included GitHub workflows are currently scoped to `audit-logs` and require environment-specific auth wiring before production operation.
