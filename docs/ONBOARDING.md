# Genesys.Core Onboarding

This guide describes how to run the repository under the Auth/Core/Ops lane standard.

## What you get

- **Genesys.Auth** — OAuth flows, DPAPI token store, `Connect-GenesysCloud`, `AuthContext`.
- **Genesys.Core** — Catalog-driven `Invoke-Dataset` engine. Deterministic outputs.
- **Genesys.Ops** — IT-Operations convenience layer (`Get-GenesysQueue`, health reports, etc.).
- Canonical catalog at `catalog/genesys.catalog.json`.
- Windows GUI client (`GenesysCore-GUI.ps1`) for interactive use.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+.
- Network access to Genesys Cloud API for live runs.
- OAuth client credentials with permissions for the endpoints your datasets use.

## 1. Open the repo

```powershell
Set-Location <path-to-Genesys.Core>
```

## 2. Import modules

```powershell
# Auth lane — owns token lifecycle
Import-Module ./modules/Genesys.Auth/Genesys.Auth.psd1 -Force

# Core lane — dataset engine
Import-Module ./modules/Genesys.Core/Genesys.Core.psd1 -Force

# (Optional) Ops lane — convenience cmdlets
Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1 -Force
```

## 3. Inspect available dataset keys

```powershell
$catalog = Get-Content -Raw ./catalog/genesys.catalog.json | ConvertFrom-Json
$catalog.datasets.PSObject.Properties.Name | Sort-Object
```

## 4. Validate catalog before first run

```powershell
Assert-Catalog -SchemaPath ./catalog/schema/genesys.catalog.schema.json
```

## 5. Authenticate (Auth lane — recommended)

```powershell
# Option A: client credentials OAuth flow (Auth lane does the HTTP call)
$authCtx = Connect-GenesysCloudApp `
    -ClientId     $env:GENESYS_CLIENT_ID `
    -ClientSecret $env:GENESYS_CLIENT_SECRET `
    -Region       'usw2.pure.cloud'

# $authCtx contains: Token, ExpiresAt, Region, BaseUri, Headers
$baseUri = $authCtx.BaseUri
$headers = $authCtx.Headers
```

```powershell
# Option B: pre-existing bearer token (also Auth lane)
$authCtx = Connect-GenesysCloud -AccessToken $env:GENESYS_BEARER_TOKEN -Region 'usw2.pure.cloud'
$baseUri  = $authCtx.BaseUri
$headers  = $authCtx.Headers
```

```powershell
# Option C: env var only (Core consumes directly — no Auth import required)
$env:GENESYS_BEARER_TOKEN = '<token>'
$baseUri = 'https://api.usw2.pure.cloud'
# headers omitted; Core falls back to GENESYS_BEARER_TOKEN automatically
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

## Optional: Ops layer session

```powershell
Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1 -Force
Connect-GenesysCloud -AccessToken $env:GENESYS_BEARER_TOKEN -Region 'usw2.pure.cloud'

Get-GenesysQueue | Where-Object { $_.memberCount -eq 0 } | Format-Table name, id
Invoke-GenesysDailyHealthReport -OutputPath '.\health.json'

Disconnect-GenesysCloud
```

## Optional: Windows GUI flow

```powershell
.\GenesysCore-GUI.ps1
```

## Back-compat note

Root shim entrypoints are still available for one deprecation cycle, but new automation should import only from `./modules/*`.

## Quick validation

```powershell
# Smoke test (offline mock — no credentials required)
./scripts/Invoke-Smoke.ps1

# Unit tests
./scripts/Invoke-Tests.ps1
```

