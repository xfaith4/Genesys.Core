#!/usr/bin/env pwsh
# Workflow simulation test
# This test simulates the exact steps that the GitHub Actions workflow performs

$ErrorActionPreference = 'Stop'

Write-Host "=== Workflow Simulation Test ===" -ForegroundColor Cyan
Write-Host ""

# Clean up any previous test output
if (Test-Path -Path 'out') {
    Remove-Item -Path 'out' -Recurse -Force
    Write-Host "Cleaned up previous 'out' directory" -ForegroundColor Yellow
}

# Simulate workflow environment
$env:DATASET_KEY = 'audit-logs'
$start = [DateTime]::UtcNow.Date.AddDays(-1).ToString('yyyy-MM-ddT00:00:00Z')
$end = [DateTime]::UtcNow.Date.ToString('yyyy-MM-ddT00:00:00Z')

Write-Host "Running dataset '$($env:DATASET_KEY)' for window $start to $end."
Write-Host ""

# Run the exact command from the workflow
Write-Host "Executing: pwsh -NoProfile -File ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 -Dataset $env:DATASET_KEY -OutputRoot out" -ForegroundColor Gray
Write-Host ""

try {
    & pwsh -NoProfile -File ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 -Dataset $env:DATASET_KEY -OutputRoot out 2>&1 | Out-Null
} catch {
    # Expected to fail on network call, not on missing functions
    Write-Host "Script execution stopped (expected): $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# Verify the output structure exists (exactly as the workflow does)
Write-Host "Checking output structure..." -ForegroundColor Cyan
$runFolder = Get-ChildItem -Path (Join-Path -Path 'out' -ChildPath $env:DATASET_KEY) -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

if (-not $runFolder) {
    Write-Host "✗ FAILED: No run folder found under out/$($env:DATASET_KEY)." -ForegroundColor Red
    Write-Host ""
    Write-Host "This means the script failed before creating the run context." -ForegroundColor Red
    Write-Host "The original error would have been:" -ForegroundColor Red
    Write-Host "  - 'Resolve-Catalog' is not recognized" -ForegroundColor Red
    Write-Host "  - 'New-RunContext' is not recognized" -ForegroundColor Red
    Write-Host "  - 'Write-RunEvent' is not recognized" -ForegroundColor Red
    exit 1
}

$runId = $runFolder.Name
Write-Host "✓ Run folder found: out/$($env:DATASET_KEY)/$runId" -ForegroundColor Green

# Check expected files
$expectedFiles = @('events.jsonl', 'manifest.json')
$allFilesExist = $true

foreach ($file in $expectedFiles) {
    $filePath = Join-Path -Path $runFolder.FullName -ChildPath $file
    if (Test-Path -Path $filePath) {
        $fileSize = (Get-Item -Path $filePath).Length
        Write-Host "  ✓ $file exists ($fileSize bytes)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $file is missing" -ForegroundColor Red
        $allFilesExist = $false
    }
}

# Check data folder
$dataFolder = Join-Path -Path $runFolder.FullName -ChildPath 'data'
if (Test-Path -Path $dataFolder) {
    Write-Host "  ✓ data/ folder exists" -ForegroundColor Green
} else {
    Write-Host "  ✗ data/ folder is missing" -ForegroundColor Red
    $allFilesExist = $false
}

Write-Host ""

# Verify events.jsonl contains expected events
$eventsPath = Join-Path -Path $runFolder.FullName -ChildPath 'events.jsonl'
if (Test-Path -Path $eventsPath) {
    $events = Get-Content -Path $eventsPath | ConvertFrom-Json
    Write-Host "Events recorded:" -ForegroundColor Cyan
    foreach ($event in $events) {
        Write-Host "  - $($event.eventType) at $($event.timestampUtc)" -ForegroundColor Gray
    }
    
    # Check for run.started event
    $startedEvent = $events | Where-Object { $_.eventType -eq 'run.started' }
    if ($startedEvent) {
        Write-Host "  ✓ run.started event found" -ForegroundColor Green
    } else {
        Write-Host "  ✗ run.started event missing (Write-RunEvent was not called)" -ForegroundColor Red
        $allFilesExist = $false
    }
}

Write-Host ""

if ($allFilesExist) {
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "The workflow simulation passed!" -ForegroundColor Green
    Write-Host "  - Functions loaded correctly (no 'not recognized' errors)" -ForegroundColor Green
    Write-Host "  - Output directories created" -ForegroundColor Green
    Write-Host "  - Events and manifest files written" -ForegroundColor Green
    Write-Host ""
    Write-Host "The GitHub Actions workflow should now work correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== FAILED ===" -ForegroundColor Red
    Write-Host "Some expected files or events are missing." -ForegroundColor Red
    exit 1
}
