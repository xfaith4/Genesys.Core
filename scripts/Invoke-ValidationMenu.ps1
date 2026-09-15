#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive terminal menu for validating Genesys.Core dataset runs.
.DESCRIPTION
    Loads Genesys.Core directly (bypassing Genesys.Ops), reads credentials from
    environment variables, then presents a numbered dataset menu.  Useful for
    confirming module load, catalog resolution, and API connectivity before any
    frontend is built.

    Auth environment variables (at least one required):
        GENESYS_BEARER_TOKEN   — pre-obtained bearer token (fastest)
        GENESYS_CLIENT_ID  +
        GENESYS_CLIENT_SECRET  — client credentials OAuth flow

    Region (optional, defaults to usw2.pure.cloud):
        GENESYS_REGION         — e.g. mypurecloud.com

.EXAMPLE
    # From repo root, any directory works:
    $env:GENESYS_BEARER_TOKEN = '<token>'
    pwsh .\scripts\Invoke-ValidationMenu.ps1
#>
[CmdletBinding()]
param(
    [string]$Region,
    [string]$OutputRoot = (Join-Path $env:TEMP 'GenesysValidation'),
    [int]$PreviewRows = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Header {
    param([string]$Text)
    $line = '─' * ($Text.Length + 4)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host "  │ $Text │" -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "  >> $Text" -ForegroundColor DarkGray
}

function Write-OK {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [FAIL] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor White
}

function Prompt-Choice {
    param([string]$Prompt)
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor Yellow -NoNewline
    $choice = Read-Host " "
    return $choice.Trim()
}

# ── Step 1: Load Genesys.Core ─────────────────────────────────────────────────

Write-Header 'Genesys.Core Validation Menu'

$moduleRoot = Join-Path $PSScriptRoot '..' | Resolve-Path
$corePsd1   = Join-Path $moduleRoot 'modules/Genesys.Core/Genesys.Core.psd1'

Write-Step "Loading Genesys.Core from: $corePsd1"
if (-not (Test-Path $corePsd1)) {
    Write-Fail "Module manifest not found at: $corePsd1"
    exit 1
}

try {
    Import-Module $corePsd1 -Force -ErrorAction Stop
    Write-OK 'Genesys.Core loaded'
} catch {
    Write-Fail "Failed to import Genesys.Core: $_"
    exit 1
}

# ── Step 2: Resolve auth ──────────────────────────────────────────────────────

Write-Step 'Resolving credentials...'

$effectiveRegion = if ($Region)                        { $Region }
                   elseif ($env:GENESYS_REGION)        { $env:GENESYS_REGION }
                   else                                { 'usw2.pure.cloud' }

$baseUri = "https://api.$effectiveRegion"

$authHeaders = $null
$authSource  = 'none'

if ($env:GENESYS_BEARER_TOKEN) {
    $authHeaders = @{ Authorization = "Bearer $($env:GENESYS_BEARER_TOKEN)" }
    $authSource  = 'GENESYS_BEARER_TOKEN env var'
}
elseif ($env:GENESYS_CLIENT_ID -and $env:GENESYS_CLIENT_SECRET) {
    Write-Step 'Obtaining token via client credentials...'
    try {
        $loginUrl = "https://login.$effectiveRegion/oauth/token"
        $encoded  = [System.Convert]::ToBase64String(
            [System.Text.Encoding]::ASCII.GetBytes("$($env:GENESYS_CLIENT_ID):$($env:GENESYS_CLIENT_SECRET)"))
        $response = Invoke-RestMethod -Uri $loginUrl -Method Post -ErrorAction Stop `
            -Headers @{ Authorization = "Basic $encoded"; 'Content-Type' = 'application/x-www-form-urlencoded' } `
            -Body 'grant_type=client_credentials'
        $authHeaders = @{ Authorization = "Bearer $($response.access_token)" }
        $authSource  = 'client credentials (GENESYS_CLIENT_ID / GENESYS_CLIENT_SECRET)'
    } catch {
        Write-Fail "Client credentials exchange failed: $_"
        exit 1
    }
}

if ($null -eq $authHeaders) {
    Write-Fail 'No credentials found.  Set GENESYS_BEARER_TOKEN or GENESYS_CLIENT_ID + GENESYS_CLIENT_SECRET.'
    exit 1
}

Write-OK "Auth: $authSource"
Write-OK "Region: $effectiveRegion  ($baseUri)"

# ── Step 3: Load catalog dataset list ────────────────────────────────────────

Write-Step 'Reading catalog...'

$catalogPath = Join-Path $moduleRoot 'catalog/genesys.catalog.json'
if (-not (Test-Path $catalogPath)) {
    Write-Fail "Catalog not found: $catalogPath"
    exit 1
}

$catalogJson = Get-Content $catalogPath -Raw | ConvertFrom-Json -Depth 100

# Collect dataset keys from catalog
$datasetKeys = if ($catalogJson.datasets -is [System.Collections.IDictionary]) {
    @($catalogJson.datasets.Keys | Sort-Object)
} else {
    @($catalogJson.datasets.PSObject.Properties.Name | Sort-Object)
}

Write-OK "$($datasetKeys.Count) datasets found in catalog"

# Group by category prefix for display
$categories = [ordered]@{}
foreach ($key in $datasetKeys) {
    $prefix = if ($key -match '^([a-z]+)[-.]') { $Matches[1] } else { $key }
    if (-not $categories.Contains($prefix)) { $categories[$prefix] = [System.Collections.Generic.List[string]]::new() }
    $categories[$prefix].Add($key)
}

# ── Step 4: Main menu loop ────────────────────────────────────────────────────

:mainLoop while ($true) {

    Write-Header 'Select a Category'

    $catList = @($categories.Keys)
    for ($i = 0; $i -lt $catList.Count; $i++) {
        $label = $catList[$i].PadRight(20)
        $count = $categories[$catList[$i]].Count
        Write-Host ("  {0,2}. {1} ({2} dataset{3})" -f ($i+1), $label, $count, $(if ($count -ne 1) {'s'})) -ForegroundColor White
    }
    Write-Host ""
    Write-Host "   Q. Quit" -ForegroundColor DarkGray

    $catChoice = Prompt-Choice 'Category number'
    if ($catChoice -match '^[qQ]$') { break mainLoop }

    $catIndex = 0
    if (-not ([int]::TryParse($catChoice, [ref]$catIndex)) -or $catIndex -lt 1 -or $catIndex -gt $catList.Count) {
        Write-Host '  Invalid choice.' -ForegroundColor Red
        continue
    }

    $selectedCategory = $catList[$catIndex - 1]
    $datasetsInCategory = @($categories[$selectedCategory])

    :datasetLoop while ($true) {

        Write-Header "Category: $selectedCategory"

        for ($i = 0; $i -lt $datasetsInCategory.Count; $i++) {
            Write-Host ("  {0,2}. {1}" -f ($i+1), $datasetsInCategory[$i]) -ForegroundColor White
        }
        Write-Host ""
        Write-Host "   B. Back   Q. Quit" -ForegroundColor DarkGray

        $dsChoice = Prompt-Choice 'Dataset number'
        if ($dsChoice -match '^[qQ]$') { break mainLoop }
        if ($dsChoice -match '^[bB]$') { break datasetLoop }

        $dsIndex = 0
        if (-not ([int]::TryParse($dsChoice, [ref]$dsIndex)) -or $dsIndex -lt 1 -or $dsIndex -gt $datasetsInCategory.Count) {
            Write-Host '  Invalid choice.' -ForegroundColor Red
            continue
        }

        $selectedDataset = $datasetsInCategory[$dsIndex - 1]

        # ── Run ──────────────────────────────────────────────────────────────

        Write-Header "Running: $selectedDataset"
        Write-Info "BaseUri : $baseUri"
        Write-Info "Output  : $OutputRoot"
        Write-Host ""

        $runStart = [DateTime]::UtcNow
        $runContext = $null
        $error_msg  = $null

        try {
            $runContext = Invoke-Dataset `
                -Dataset $selectedDataset `
                -OutputRoot $OutputRoot `
                -BaseUri $baseUri `
                -Headers $authHeaders `
                -ErrorAction Stop
        } catch {
            $error_msg = "$_"
        }

        $elapsed = ([DateTime]::UtcNow - $runStart).TotalSeconds

        if ($error_msg) {
            Write-Fail "Dataset run failed after $([Math]::Round($elapsed,1))s"
            Write-Host ""
            Write-Host $error_msg -ForegroundColor Red
        } else {
            Write-OK "Completed in $([Math]::Round($elapsed,1))s"

            # Show summary if it exists
            $summaryPath = $runContext.summaryPath
            if ($summaryPath -and (Test-Path $summaryPath)) {
                $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json -Depth 20
                Write-Host ""
                Write-Host '  ── Summary ──────────────────────────────────────' -ForegroundColor Cyan
                $summary | Format-List | Out-String | ForEach-Object { Write-Host "  $_" }
            }

            # Show first N records
            $dataDir = Get-ChildItem (Join-Path $OutputRoot $selectedDataset) `
                -Recurse -Directory -Filter 'data' -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($dataDir) {
                $jsonlFiles = @(Get-ChildItem $dataDir.FullName -Filter '*.jsonl' -ErrorAction SilentlyContinue)
                if ($jsonlFiles.Count -gt 0) {
                    $records = [System.Collections.Generic.List[object]]::new()
                    foreach ($f in $jsonlFiles) {
                        Get-Content $f.FullName | Where-Object { $_.Trim() } | ForEach-Object {
                            if ($records.Count -lt $PreviewRows) {
                                $records.Add(($_ | ConvertFrom-Json))
                            }
                        }
                    }

                    if ($records.Count -gt 0) {
                        Write-Host "  ── First $([Math]::Min($PreviewRows, $records.Count)) record(s) ──────────────────────────────" -ForegroundColor Cyan
                        $records | Select-Object -First $PreviewRows | Format-List | Out-String -Width 120 |
                            ForEach-Object { Write-Host "  $_" }
                    } else {
                        Write-Info '  (No records returned)'
                    }
                }
            }
        }

        $null = Prompt-Choice 'Press Enter to continue'
    }
}

Write-Host ""
Write-OK 'Done.'
Write-Host ""
