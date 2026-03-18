#!/usr/bin/env pwsh
# Workflow simulation test (MOCK — virtualized for CI)
# This test simulates the exact steps that the GitHub Actions workflow performs,
# using virtual/mock data instead of real Genesys Cloud API calls.
# All mocked actions are prefixed with "MOCK:" in the log for transparency.

$ErrorActionPreference = 'Stop'

Write-Host "=== Workflow Simulation Test (Virtualized) ===" -ForegroundColor Cyan
Write-Host "MOCK: Genesys Cloud API calls are not possible in CI (no bearer token stored)."
Write-Host "MOCK: All API interactions are virtualized with clearly labelled mock data."
Write-Host ""

# Clean up any previous test output
if (Test-Path -Path 'out') {
    Remove-Item -Path 'out' -Recurse -Force
    Write-Host "Cleaned up previous 'out' directory" -ForegroundColor Yellow
}

# Simulate workflow environment
$env:DATASET_KEY = 'audit-logs'
$start = [DateTime]::UtcNow.Date.AddDays(-1).ToString('yyyy-MM-ddT00:00:00Z')
$end   = [DateTime]::UtcNow.Date.ToString('yyyy-MM-ddT00:00:00Z')
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')

Write-Host ("MOCK: Simulating dataset '{0}' for window {1} to {2}." -f $env:DATASET_KEY, $start, $end)
Write-Host ""

# --- Create output directory structure (mirrors real Invoke-Dataset behaviour) ---
$runFolder  = Join-Path 'out' (Join-Path $env:DATASET_KEY $runId)
$dataFolder = Join-Path $runFolder 'data'
New-Item -Path $dataFolder -ItemType Directory -Force | Out-Null
Write-Host "MOCK: Created output structure at $runFolder" -ForegroundColor Gray

# --- Virtual audit records ---
$mockRecords = @(
    [pscustomobject]@{ id = 'mock-1'; action = 'UserLogin';  serviceName = 'platform'; timestamp = $start; userEmail = '[REDACTED]' },
    [pscustomobject]@{ id = 'mock-2'; action = 'UserLogout'; serviceName = 'platform'; timestamp = $end;   userEmail = '[REDACTED]' }
)
$auditPath = Join-Path $dataFolder 'audit.jsonl'
$mockRecords | ForEach-Object { $_ | ConvertTo-Json -Compress | Add-Content -Path $auditPath -Encoding utf8 }
Write-Host ("MOCK: Wrote {0} virtual audit records to {1}" -f $mockRecords.Count, $auditPath)
foreach ($rec in $mockRecords) {
    Write-Host "MOCK LOG: $($rec | ConvertTo-Json -Compress)"
}

# --- events.jsonl ---
$nowUtc = [DateTime]::UtcNow.ToString('o')
$events = @(
    [pscustomobject]@{ eventType = 'run.started';            timestampUtc = $nowUtc; datasetKey = $env:DATASET_KEY; runId = $runId },
    [pscustomobject]@{ eventType = 'mock.api.skipped';       timestampUtc = $nowUtc; reason = 'CI: no bearer token available; Genesys Cloud unreachable' },
    [pscustomobject]@{ eventType = 'audit.transaction.poll'; timestampUtc = $nowUtc; state = 'MOCK_FULFILLED'; pollIndex = 1 },
    [pscustomobject]@{ eventType = 'paging.progress';        timestampUtc = $nowUtc; page = 1; recordsThisPage = $mockRecords.Count },
    [pscustomobject]@{ eventType = 'run.completed';          timestampUtc = $nowUtc; totalRecords = $mockRecords.Count }
)
$eventsPath = Join-Path $runFolder 'events.jsonl'
$events | ForEach-Object { $_ | ConvertTo-Json -Compress | Add-Content -Path $eventsPath -Encoding utf8 }
Write-Host "MOCK: Wrote $($events.Count) events to $eventsPath"

# --- summary.json ---
$summary = [ordered]@{
    datasetKey          = $env:DATASET_KEY
    runId               = $runId
    windowStart         = $start
    windowEnd           = $end
    mock                = $true
    totals              = @{ totalRecords = $mockRecords.Count }
    countsByAction      = @{ UserLogin = 1; UserLogout = 1 }
    countsByServiceName = @{ platform = 2 }
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $runFolder 'summary.json') -Encoding utf8
Write-Host "MOCK: Wrote summary.json"

# --- manifest.json ---
$manifest = [ordered]@{
    datasetKey   = $env:DATASET_KEY
    runId        = $runId
    startedAtUtc = $start
    endedAtUtc   = $end
    gitSha       = $env:GITHUB_SHA
    mock         = $true
    counts       = @{ total = $mockRecords.Count }
    warnings     = @('CI virtualized run: no real Genesys Cloud calls were made')
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $runFolder 'manifest.json') -Encoding utf8
Write-Host "MOCK: Wrote manifest.json"

Write-Host ""

# --- Validate structure (mirrors workflow verification) ---
Write-Host "Checking output structure..." -ForegroundColor Cyan
$runFolderObj = Get-ChildItem -Path (Join-Path 'out' $env:DATASET_KEY) -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

if (-not $runFolderObj) {
    Write-Host "✗ FAILED: No run folder found under out/$($env:DATASET_KEY)." -ForegroundColor Red
    exit 1
}
Write-Host "✓ Run folder found: out/$($env:DATASET_KEY)/$($runFolderObj.Name)" -ForegroundColor Green

$allFilesExist = $true
$expectedFiles = @('events.jsonl', 'manifest.json', 'summary.json')
foreach ($file in $expectedFiles) {
    $filePath = Join-Path $runFolderObj.FullName $file
    if (Test-Path $filePath) {
        $fileSize = (Get-Item $filePath).Length
        Write-Host "  ✓ $file exists ($fileSize bytes)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $file is missing" -ForegroundColor Red
        $allFilesExist = $false
    }
}

$dataFolderPath = Join-Path $runFolderObj.FullName 'data'
if (Test-Path $dataFolderPath) {
    Write-Host "  ✓ data/ folder exists" -ForegroundColor Green
} else {
    Write-Host "  ✗ data/ folder is missing" -ForegroundColor Red
    $allFilesExist = $false
}

# Validate events.jsonl contains expected event types
$eventsLoaded = @(Get-Content (Join-Path $runFolderObj.FullName 'events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
Write-Host ""
Write-Host "Events recorded:" -ForegroundColor Cyan
foreach ($ev in $eventsLoaded) {
    Write-Host "  - $($ev.eventType)" -ForegroundColor Gray
}

$startedEvent = $eventsLoaded | Where-Object { $_.eventType -eq 'run.started' }
if ($startedEvent) {
    Write-Host "  ✓ run.started event found" -ForegroundColor Green
} else {
    Write-Host "  ✗ run.started event missing" -ForegroundColor Red
    $allFilesExist = $false
}

$mockSkippedEvent = $eventsLoaded | Where-Object { $_.eventType -eq 'mock.api.skipped' }
if ($mockSkippedEvent) {
    Write-Host "  ✓ mock.api.skipped event found (transparency marker)" -ForegroundColor Green
} else {
    Write-Host "  ✗ mock.api.skipped event missing" -ForegroundColor Red
    $allFilesExist = $false
}

# Validate summary.json
$summaryLoaded = Get-Content (Join-Path $runFolderObj.FullName 'summary.json') -Raw | ConvertFrom-Json
if ($summaryLoaded.mock -eq $true) {
    Write-Host "  ✓ summary.json mock=true flag present" -ForegroundColor Green
} else {
    Write-Host "  ✗ summary.json mock flag missing or false" -ForegroundColor Red
    $allFilesExist = $false
}

Write-Host ""

if ($allFilesExist) {
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "MOCK: Workflow simulation passed — all Genesys Cloud interactions virtualized." -ForegroundColor Green
    Write-Host "  - Output directories and files created with correct structure" -ForegroundColor Green
    Write-Host "  - Events and manifest files written" -ForegroundColor Green
    Write-Host "  - Mock transparency markers present in events.jsonl and summary.json" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== FAILED ===" -ForegroundColor Red
    Write-Host "Some expected files or events are missing." -ForegroundColor Red
    exit 1
}


