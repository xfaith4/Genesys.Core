#Requires -Version 5.1

param(
    [string]$AppRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Results = New-Object System.Collections.Generic.List[object]

function Read-Text {
    param([string]$RelativePath)
    $fullPath = Join-Path $AppRoot $RelativePath
    if (-not (Test-Path $fullPath)) { return '' }
    return [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
}

function Add-Result {
    param(
        [string]$Id,
        [string]$Description,
        [bool]$Passed,
        [string]$Detail = ''
    )

    $result = if ($Passed) { 'PASS' } else { 'FAIL' }
    $color = if ($Passed) { 'Green' } else { 'Red' }
    $suffix = if ($Passed -or [string]::IsNullOrWhiteSpace($Detail)) { '' } else { "  ($Detail)" }
    Write-Host "  [$result] $Id  $Description$suffix" -ForegroundColor $color
    $script:Results.Add([pscustomobject]@{
        Id = $Id
        Description = $Description
        Result = $result
        Detail = $Detail
    }) | Out-Null
}

function Check {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$Test
    )

    try {
        $passed = [bool](& $Test)
        Add-Result -Id $Id -Description $Description -Passed $passed
    } catch {
        Add-Result -Id $Id -Description $Description -Passed $false -Detail $_.Exception.Message
    }
}

$appPs = Read-Text 'App.ps1'
$adapterPs = Read-Text 'App.CoreAdapter.psm1'
$settingsPs = Read-Text 'App.Settings.psd1'
$readme = Read-Text 'README.md'

Write-Host "`n=== STRUCTURE ===" -ForegroundColor Cyan
Check 'STR-01' 'App.ps1 exists' { Test-Path (Join-Path $AppRoot 'App.ps1') }
Check 'STR-02' 'App.CoreAdapter.psm1 exists' { Test-Path (Join-Path $AppRoot 'App.CoreAdapter.psm1') }
Check 'STR-03' 'App.Settings.psd1 exists' { Test-Path (Join-Path $AppRoot 'App.Settings.psd1') }
Check 'STR-04' 'README.md exists' { Test-Path (Join-Path $AppRoot 'README.md') }

Write-Host "`n=== STARTUP / BOUNDARY ===" -ForegroundColor Cyan
Check 'INIT-01' 'App.ps1 imports App.CoreAdapter.psm1' {
    $appPs -match 'Import-Module .*App\.CoreAdapter\.psm1'
}
Check 'INIT-02' 'App.ps1 initializes Core integration at startup' {
    $appPs -match 'Initialize-CoreIntegration'
}
Check 'INIT-03' 'App.ps1 does not import Genesys.Core directly' {
    $appPs -notmatch 'Import-Module.*Genesys\.Core'
}
Check 'INIT-04' 'App.ps1 does not import Genesys.Auth directly' {
    $appPs -notmatch 'Import-Module.*Genesys\.Auth'
}
Check 'INIT-05' 'App.CoreAdapter imports Genesys.Core and Genesys.Auth' {
    ($adapterPs -match 'Import-Module \$AuthModulePath') -and
    ($adapterPs -match 'Import-Module \$CoreModulePath')
}
Check 'INIT-06' 'Settings define core, auth, catalog, schema, and output paths' {
    ($settingsPs -match 'CoreModuleRelativePath') -and
    ($settingsPs -match 'AuthModuleRelativePath') -and
    ($settingsPs -match 'CatalogRelativePath') -and
    ($settingsPs -match 'SchemaRelativePath') -and
    ($settingsPs -match 'OutputRelativePath')
}

Write-Host "`n=== RUN MODE ===" -ForegroundColor Cyan
Check 'RUN-01' 'Dataset and report execution use background runspaces with BeginInvoke' {
    (@([regex]::Matches($appPs, 'CreateRunspace\(')).Count -ge 2) -and
    (@([regex]::Matches($appPs, 'BeginInvoke\(')).Count -ge 3)
}
Check 'RUN-02' 'Run progress is polled with DispatcherTimer' {
    (@([regex]::Matches($appPs, 'DispatcherTimer')).Count -ge 2) -and
    ($appPs -match 'Add_Tick')
}
Check 'RUN-03' 'Run cancellation is wired through BtnCancel and BeginStop' {
    ($appPs -match 'BtnCancel\.Add_Click') -and
    ($appPs -match 'BeginStop\(')
}
Check 'RUN-04' 'Live events UI is present and tails events.jsonl' {
    ($appPs -match 'TabItem Header="Live events"') -and
    ($appPs -match 'events\.jsonl') -and
    ($appPs -match 'Add-LiveEvent')
}
Check 'RUN-05' 'Run results load in a background pass after completion' {
    ($appPs -match 'PendingResultsJob') -and
    ($appPs -match 'Completed .*Loading results')
}

Write-Host "`n=== UX CONTRACT ===" -ForegroundColor Cyan
Check 'UX-01' 'First dataset is auto-selected when the catalog loads' {
    $appPs -match 'LstDatasets\.SelectedIndex = 0'
}
Check 'UX-02' 'Environment bearer-token hint is surfaced at startup' {
    $appPs -match 'GENESYS_BEARER_TOKEN' -and
    $appPs -match 'Bearer token available from GENESYS_BEARER_TOKEN'
}
Check 'UX-03' 'README documents background runspace, live events, and cancel support' {
    ($readme -match 'background runspace') -and
    ($readme -match 'Live events') -and
    ($readme -match 'Cancel run')
}

$passCount = @($script:Results | Where-Object { $_.Result -eq 'PASS' }).Count
$failCount = @($script:Results | Where-Object { $_.Result -eq 'FAIL' }).Count

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "Results: $passCount PASS  /  $failCount FAIL  /  $($script:Results.Count) total" -ForegroundColor Cyan

return $script:Results.ToArray()
