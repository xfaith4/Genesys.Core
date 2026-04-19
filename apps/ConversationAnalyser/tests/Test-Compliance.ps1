#Requires -Version 5.1

<#
.SYNOPSIS
    Gate D / Gate E – Static compliance checks for Genesys Conversation Analysis.
.DESCRIPTION
    Performs pass/fail checks on source files without executing them:
      - Required file structure
      - No direct REST calls in app files (auth delegated to Genesys.Auth in sibling repo)
      - No /api/v2/ literals
      - Genesys.Core import isolation (only in App.CoreAdapter.psm1)
      - Invoke-Dataset and Assert-Catalog only in App.CoreAdapter.psm1
      - No vendored Genesys.Core module
      - DPAPI usage in Genesys.Auth (sibling Core repo)
      - Auth targets only login.{region} endpoints
      - Indexing implementation signals
      - Export streaming signals
    Returns exit code 0 on all-pass, 1 on any failure.
#>

param(
    [string]$AppRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest

# ── Test infrastructure ───────────────────────────────────────────────────────

$script:Results = [System.Collections.Generic.List[pscustomobject]]::new()
$script:AllPass = $true

function Pass {
    param([string]$Id, [string]$Check)
    $script:Results.Add([pscustomobject]@{ ID = $Id; Check = $Check; Result = 'PASS'; Detail = '' })
    Write-Host "  [PASS] $Id  $Check" -ForegroundColor Green
}

function Fail {
    param([string]$Id, [string]$Check, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ ID = $Id; Check = $Check; Result = 'FAIL'; Detail = $Detail })
    Write-Host "  [FAIL] $Id  $Check" -ForegroundColor Red
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkRed }
    $script:AllPass = $false
}

function Check {
    param([string]$Id, [string]$Description, [scriptblock]$Test)
    try {
        $result = & $Test
        if ($result -eq $true) { Pass $Id $Description }
        else                   { Fail $Id $Description -Detail "Returned: $result" }
    } catch {
        Fail $Id $Description -Detail "Exception: $_"
    }
}

function FileExists {
    param([string]$RelPath)
    $normalized = $RelPath -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    return [System.IO.File]::Exists([System.IO.Path]::Combine($AppRoot, $normalized))
}

function ReadFile {
    param([string]$RelPath)
    $normalized = $RelPath -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::Combine($AppRoot, $normalized)
    if (-not [System.IO.File]::Exists($full)) { return '' }
    return [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
}

function AllAppFiles {
    # Returns content of all app files EXCEPT tests/
    $files = @('App.ps1','scripts\App.UI.ps1','modules\App.CoreAdapter.psm1',
               'modules\App.Config.psm1','modules\App.Index.psm1','modules\App.Export.psm1','modules\App.Reporting.psm1','modules\App.Database.psm1')
    $content = foreach ($f in $files) { ReadFile $f }
    return $content -join "`n"
}

function FilesExcluding {
    param([string[]]$Exclude)
    $allFiles = @('App.ps1','scripts\App.UI.ps1','modules\App.CoreAdapter.psm1',
                  'modules\App.Config.psm1','modules\App.Index.psm1','modules\App.Export.psm1','modules\App.Reporting.psm1','modules\App.Database.psm1',
                  'resources\MainWindow.xaml',
                  'tests\Test-Compliance.ps1','tests\Invoke-AllTests.ps1')
    $filtered = $allFiles | Where-Object { $_ -notin $Exclude }
    return ($filtered | ForEach-Object { ReadFile $_ }) -join "`n"
}

# Genesys.Auth content from the parent repo's modules/ folder (Gate E)
$script:GenesysAuthPath = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($AppRoot, '..', '..', 'modules', 'Genesys.Auth', 'Genesys.Auth.psm1'))
$script:GenesysAuthContent = if ([System.IO.File]::Exists($script:GenesysAuthPath)) {
    [System.IO.File]::ReadAllText($script:GenesysAuthPath, [System.Text.Encoding]::UTF8)
} else { '' }

# ── STRUCTURE CHECKS (STR) ────────────────────────────────────────────────────

Write-Host "`n=== STRUCTURE ===" -ForegroundColor Cyan

Check 'STR-01' 'App.ps1 exists'                    { FileExists 'App.ps1' }
Check 'STR-02' 'scripts\App.UI.ps1 exists'                 { FileExists 'scripts\App.UI.ps1' }
Check 'STR-03' 'modules\App.CoreAdapter.psm1 exists'       { FileExists 'modules\App.CoreAdapter.psm1' }
Check 'STR-04' 'Genesys.Auth module present in sibling Core repo' {
    [System.IO.File]::Exists($script:GenesysAuthPath)
}
Check 'STR-05' 'modules\App.Config.psm1 exists'            { FileExists 'modules\App.Config.psm1' }
Check 'STR-06' 'modules\App.Index.psm1 exists'             { FileExists 'modules\App.Index.psm1' }
Check 'STR-07' 'modules\App.Export.psm1 exists'            { FileExists 'modules\App.Export.psm1' }
Check 'STR-08' 'modules\App.Database.psm1 exists'          { FileExists 'modules\App.Database.psm1' }
Check 'STR-08A' 'modules\App.Reporting.psm1 exists'        { FileExists 'modules\App.Reporting.psm1' }
Check 'STR-09' 'resources\MainWindow.xaml exists'          { FileExists 'resources\MainWindow.xaml' }
Check 'STR-10' 'tests\Test-Compliance.ps1 exists'          { FileExists 'tests\Test-Compliance.ps1' }
Check 'STR-11' 'tests\Invoke-AllTests.ps1 exists'          { FileExists 'tests\Invoke-AllTests.ps1' }
Check 'STR-12' 'docs\Database_Design.md exists'            { FileExists 'docs\Database_Design.md' }
Check 'STR-13' 'docs\Case_Lifecycle_and_Retention.md exists' { FileExists 'docs\Case_Lifecycle_and_Retention.md' }

# ── REST CALL ISOLATION (REST) ────────────────────────────────────────────────

Write-Host "`n=== REST ISOLATION (Gate D) ===" -ForegroundColor Cyan

$nonTestContent = FilesExcluding -Exclude @('tests\Test-Compliance.ps1', 'tests\Invoke-AllTests.ps1')

Check 'REST-01' 'Invoke-RestMethod absent from all app files (auth delegated to Genesys.Core)' {
    -not ($nonTestContent -match 'Invoke-RestMethod')
}

Check 'REST-02' 'Invoke-WebRequest absent from all app files' {
    -not ($nonTestContent -match 'Invoke-WebRequest')
}

Check 'REST-03' 'No /api/v2/ literal in any app file' {
    -not ((AllAppFiles) -match '/api/v2/')
}

# Genesys.Auth (sibling) must NOT reach /api/v2/
Check 'REST-04' 'No /api/v2/ literal in Genesys.Auth (sibling Core repo)' {
    -not ($script:GenesysAuthContent -match '/api/v2/')
}

# ── CORE IMPORT ISOLATION (CORE) ─────────────────────────────────────────────

Write-Host "`n=== CORE IMPORT ISOLATION (Gate D) ===" -ForegroundColor Cyan

$nonAdapterContent = FilesExcluding -Exclude @('modules\App.CoreAdapter.psm1','tests\Test-Compliance.ps1','tests\Invoke-AllTests.ps1')

Check 'CORE-01' 'Genesys.Core Import-Module only in App.CoreAdapter.psm1' {
    -not ($nonAdapterContent -match "Import-Module.*Genesys\.Core")
}

Check 'CORE-02' 'Assert-Catalog only in App.CoreAdapter.psm1' {
    -not ($nonAdapterContent -match 'Assert-Catalog')
}

Check 'CORE-03' 'Invoke-Dataset only in App.CoreAdapter.psm1' {
    -not ($nonAdapterContent -match 'Invoke-Dataset')
}

# CoreAdapter itself must contain both Assert-Catalog and Invoke-Dataset
Check 'CORE-04' 'App.CoreAdapter.psm1 calls Assert-Catalog' {
    (ReadFile 'modules\App.CoreAdapter.psm1') -match 'Assert-Catalog'
}

Check 'CORE-05' 'App.CoreAdapter.psm1 calls Invoke-Dataset' {
    (ReadFile 'modules\App.CoreAdapter.psm1') -match 'Invoke-Dataset'
}

Check 'CORE-06' 'App.CoreAdapter.psm1 imports Genesys.Core' {
    (ReadFile 'modules\App.CoreAdapter.psm1') -match 'Import-Module'
}

# ── NO VENDORED CORE (VENDOR) ─────────────────────────────────────────────────

Write-Host "`n=== NO VENDORED CORE (Gate D) ===" -ForegroundColor Cyan

Check 'VENDOR-01' 'No Genesys.Core module folder vendored in repo' {
    $coreFolder = [System.IO.Path]::Combine($AppRoot, 'Genesys.Core')
    -not [System.IO.Directory]::Exists($coreFolder)
}

Check 'VENDOR-02' 'No Genesys.Core.psd1 file vendored in repo' {
    $psd = [System.IO.Directory]::GetFiles($AppRoot, 'Genesys.Core.psd1', [System.IO.SearchOption]::AllDirectories)
    $psd.Count -eq 0
}

# ── AUTH CONTAINMENT (Gate E – Genesys.Auth in sibling Core repo) ─────────────

Write-Host "`n=== AUTH CONTAINMENT (Gate E – Genesys.Auth) ===" -ForegroundColor Cyan

Check 'AUTH-01' 'Genesys.Auth uses ProtectedData::Protect (DPAPI)' {
    $script:GenesysAuthContent -match 'ProtectedData.*Protect'
}

Check 'AUTH-02' 'Genesys.Auth uses ProtectedData::Unprotect (DPAPI)' {
    $script:GenesysAuthContent -match 'ProtectedData.*Unprotect'
}

Check 'AUTH-03' 'Genesys.Auth targets login.{region} OAuth endpoints' {
    $script:GenesysAuthContent -match 'login\.\$\(.*\)/oauth'
}

Check 'AUTH-04' 'Genesys.Auth stores auth in LOCALAPPDATA' {
    $script:GenesysAuthContent -match 'LOCALAPPDATA'
}

Check 'AUTH-05' 'Genesys.Auth exports required functions' {
    $required = @('Connect-GenesysCloudApp','Connect-GenesysCloudPkce','Get-StoredHeaders',
                  'Test-GenesysConnection','Get-ConnectionInfo','Clear-StoredToken')
    $allPresent = $true
    foreach ($fn in $required) {
        if ($script:GenesysAuthContent -notmatch $fn) { $allPresent = $false; break }
    }
    $allPresent
}

# ── DATASET KEYS (DS) ─────────────────────────────────────────────────────────

Write-Host "`n=== DATASET KEYS ===" -ForegroundColor Cyan

$adapterContent = ReadFile 'modules\App.CoreAdapter.psm1'

Check 'DS-01' 'Preview dataset key analytics-conversation-details-query present' {
    $adapterContent -match 'analytics-conversation-details-query'
}

Check 'DS-02' 'Full run dataset key analytics-conversation-details present' {
    $adapterContent -match "'analytics-conversation-details'"
}

Check 'DS-03' 'Two distinct dataset keys (no collapse)' {
    $previewCount = ([regex]::Matches($adapterContent, 'analytics-conversation-details-query')).Count
    $fullCount    = ([regex]::Matches($adapterContent, "'analytics-conversation-details'")).Count
    $previewCount -ge 1 -and $fullCount -ge 1
}

# ── INDEXING IMPLEMENTATION (IDX) ────────────────────────────────────────────

Write-Host "`n=== INDEXING SIGNALS (Gate C) ===" -ForegroundColor Cyan

$indexContent = ReadFile 'modules\App.Index.psm1'

Check 'IDX-01' 'Build-RunIndex function present' {
    $indexContent -match 'function Build-RunIndex'
}

Check 'IDX-02' 'Get-IndexedPage function present' {
    $indexContent -match 'function Get-IndexedPage'
}

Check 'IDX-03' 'FileStream.Seek used in Get-IndexedPage' {
    $indexContent -match '\.Seek\('
}

Check 'IDX-04' 'Get-IndexedPage reads records from indexed byte offsets' {
    ($indexContent -match '\.Seek\(') -and ($indexContent -match '\.ReadByte\(')
}

Check 'IDX-05' 'Byte-offset tracking present (line offset)' {
    $indexContent -match 'offset'
}

Check 'IDX-06' 'UTF-8 BOM handling present' {
    $indexContent -match '0xEF.*0xBB.*0xBF|BOM'
}

Check 'IDX-07' 'index.jsonl written' {
    $indexContent -match 'index\.jsonl'
}

Check 'IDX-08' 'Export-ModuleMember lists required index functions' {
    $required = @('Build-RunIndex','Load-RunIndex','Clear-IndexCache',
                  'Get-IndexedPage','Get-ConversationRecord','Get-RunTotalCount','Get-FilteredIndex')
    $allPresent = $true
    foreach ($fn in $required) {
        if ($indexContent -notmatch $fn) { $allPresent = $false; break }
    }
    $allPresent
}

# ── EXPORT STREAMING (EXP) ────────────────────────────────────────────────────

Write-Host "`n=== EXPORT STREAMING ===" -ForegroundColor Cyan

$exportContent = ReadFile 'modules\App.Export.psm1'

Check 'EXP-01' 'Export-RunToCsv function present' {
    $exportContent -match 'function Export-RunToCsv'
}

Check 'EXP-02' 'Export-RunToCsv uses StreamReader (no full load)' {
    $exportContent -match 'StreamReader'
}

Check 'EXP-03' 'Export-RunToCsv iterates file-by-file' {
    $exportContent -match 'foreach.*dataFile'
}

Check 'EXP-04' 'No Get-Content in Export-RunToCsv path' {
    # Get-Content should not be used in the export streaming path
    $exportContent -notmatch 'Get-Content'
}

Check 'EXP-05' 'ConvertTo-FlatRow present' {
    $exportContent -match 'function ConvertTo-FlatRow'
}

Check 'EXP-06' 'Export-ModuleMember lists required export functions' {
    $required = @('ConvertTo-FlatRow','Export-PageToCsv','Export-RunToCsv',
                  'Export-ConversationToJson','Get-ConversationDisplayRow')
    $allPresent = $true
    foreach ($fn in $required) {
        if ($exportContent -notmatch $fn) { $allPresent = $false; break }
    }
    $allPresent
}

# ── REPORTING (RPT) ───────────────────────────────────────────────────────────

Write-Host "`n=== REPORTING ===" -ForegroundColor Cyan

$reportingContent = ReadFile 'modules\App.Reporting.psm1'

Check 'RPT-01' 'App.Reporting.psm1 defines New-ImpactReport' {
    $reportingContent -match 'function New-ImpactReport'
}

Check 'RPT-02' 'App.Reporting.psm1 exports New-ImpactReport' {
    $reportingContent -match 'Export-ModuleMember -Function New-ImpactReport'
}

Check 'RPT-03' 'App.UI.ps1 wires BtnGenerateReport' {
    (ReadFile 'scripts\App.UI.ps1') -match 'BtnGenerateReport'
}

# ── GATE A: STARTUP INIT (INIT) ───────────────────────────────────────────────

Write-Host "`n=== GATE A: STARTUP INIT ===" -ForegroundColor Cyan

$appPsContent = ReadFile 'App.ps1'

Check 'INIT-01' 'App.ps1 calls Initialize-CoreAdapter' {
    $appPsContent -match 'Initialize-CoreAdapter'
}

Check 'INIT-02' 'App.ps1 imports App.CoreAdapter.psm1 (not Genesys.Core directly)' {
    $appPsContent -match "Import-Module.*App\.CoreAdapter" -and
    ($appPsContent -notmatch "Import-Module.*Genesys\.Core")
}

Check 'INIT-03' 'App.ps1 loads XAML\MainWindow.xaml' {
    $appPsContent -match 'MainWindow\.xaml'
}

Check 'INIT-04' 'App.ps1 dot-sources App.UI.ps1' {
    $appPsContent -match '\. .*App\.UI\.ps1'
}

Check 'INIT-05' 'App.ps1 persists last date/time filters on close' {
    $appPsContent -match 'LastStartDate' -and
    $appPsContent -match 'LastEndDate' -and
    $appPsContent -match 'LastStartTime' -and
    $appPsContent -match 'LastEndTime'
}

# ── BACKGROUND RUNSPACE (BG) ─────────────────────────────────────────────────

Write-Host "`n=== BACKGROUND RUNSPACE ===" -ForegroundColor Cyan

$uiContent = ReadFile 'scripts\App.UI.ps1'

Check 'BG-01' 'App.UI.ps1 creates background runspace for run' {
    $uiContent -match 'CreateRunspace'
}

Check 'BG-02' 'Background runspace calls Initialize-CoreAdapter' {
    $uiContent -match 'Initialize-CoreAdapter'
}

Check 'BG-03' 'Background runspace imports App.CoreAdapter.psm1' {
    $uiContent -match "Import-Module.*App\.CoreAdapter"
}

Check 'BG-04' 'App.UI.ps1 does NOT call Invoke-Dataset directly' {
    $uiContent -notmatch 'Invoke-Dataset'
}

Check 'BG-05' 'Polling DispatcherTimer used for status updates' {
    $uiContent -match 'DispatcherTimer'
}

# ── XAML CONTROLS (XAML) ─────────────────────────────────────────────────────

Write-Host "`n=== XAML CONTROLS ===" -ForegroundColor Cyan

$xamlContent = ReadFile 'resources\MainWindow.xaml'

$requiredControls = @(
    'BtnRun','BtnCancelRun','BtnPreviewRun',
    'DgConversations','LstRecentRuns',
    'BtnCopyDiagnostics','TxtRunProgress','TxtRunStatus',
    'LblActiveCase','BtnManageCase','BtnImportRun',
    'BtnExpandJson',
    'DtpStartDate','TxtStartTime','DtpEndDate','TxtEndTime',
    'CmbDirection','CmbMediaType','TxtQueue',
    'TxtSearch','BtnSearch',
    'CmbFilterDirection','CmbFilterMedia',
    'BtnPrevPage','BtnNextPage','TxtPageInfo',
    'BtnExportPageCsv','BtnExportRunCsv',
    'LblSelectedConversation',
    'TxtDrillSummary','DgParticipants','DgSegments',
    'TxtAttributeSearch','DgAttributes',
    'TxtMosQuality','TxtRawJson',
    'TxtConsoleStatus','DgRunEvents','TxtDiagnostics',
    'TxtStatusMain',
    'TabWorkspace','TabDrilldownWorkspace',
    'BtnPullTransferReport','CmbTransferType',
    'DgTransferFlows','DgTransferDestinations','DgTransferChains',
    'LblXferFlows','LblXferTransfers','LblXferBlind',
    'LblXferConsult','LblXferBlindPct','LblXferMultiHop',
    'BtnPullFlowContainmentReport','CmbFlowType',
    'DgFlowPerf','DgFlowMilestones','DgFlowQueues',
    'LblFlowTotal','LblFlowEntries','LblFlowContainment',
    'LblFlowFailures','LblFlowLowContainment',
    'BtnPullWrapupReport',
    'DgWrapupCodes','DgWrapupByQueue','DgWrapupByHour',
    'DgWrapupInsights','DgWrapupCrossRef',
    'LblWrapupCodes','LblWrapupConnected','LblWrapupQueues',
    'LblWrapupTopReason'
)

foreach ($ctrl in $requiredControls) {
    Check "XAML-$ctrl" "XAML contains x:Name='$ctrl'" {
        $xamlContent -match "x:Name=""$ctrl"""
    }
}

# ── STRICT MODE (STRICT) ─────────────────────────────────────────────────────

Write-Host "`n=== STRICT MODE ===" -ForegroundColor Cyan

$modulesToCheck = @('modules\App.CoreAdapter.psm1','modules\App.Config.psm1',
                    'modules\App.Index.psm1','modules\App.Export.psm1','modules\App.Database.psm1')
foreach ($m in $modulesToCheck) {
    Check "STRICT-$m" "$m uses Set-StrictMode -Version Latest" {
        (ReadFile $m) -match 'Set-StrictMode.*Latest'
    }
}

# ── CASE WORKFLOW / RETENTION (CASE) ─────────────────────────────────────────

Write-Host "`n=== CASE WORKFLOW / RETENTION ===" -ForegroundColor Cyan

$dbContent = ReadFile 'modules\App.Database.psm1'

Check 'CASE-01' 'App.Database.psm1 defines case workflow tables' {
    $dbContent -match 'CREATE TABLE IF NOT EXISTS case_audit' -and
    $dbContent -match 'CREATE TABLE IF NOT EXISTS saved_views' -and
    $dbContent -match 'CREATE TABLE IF NOT EXISTS findings'
}

Check 'CASE-02' 'App.Database.psm1 exports retention and case workflow functions' {
    $required = @('Get-CaseAudit','Set-CaseTags','New-SavedView','Archive-Case','Purge-Case')
    $allPresent = $true
    foreach ($fn in $required) {
        if ($dbContent -notmatch $fn) { $allPresent = $false; break }
    }
    $allPresent
}

Check 'CASE-03' 'App.UI.ps1 case dialog uses notes, tags, saved views, archive, and purge actions' {
    $uiContent -match 'Update-CaseNotes' -and
    $uiContent -match 'Set-CaseTags' -and
    $uiContent -match 'New-SavedView' -and
    $uiContent -match 'Archive-Case' -and
    $uiContent -match 'Purge-Case'
}

# ── TRANSFER REPORTING (XFER) ────────────────────────────────────────────────

Write-Host "`n=== TRANSFER REPORTING ===" -ForegroundColor Cyan

Check 'XFER-01' 'App.CoreAdapter.psm1 exposes Get-TransferReport dataset pull' {
    $adapterContent -match 'function Get-TransferReport' -and
    $adapterContent -match 'analytics\.query\.conversation\.aggregates\.transfer\.metrics'
}

Check 'XFER-02' 'App.Database.psm1 defines schema v7+ transfer tables' {
    $schemaMatch = [regex]::Match($dbContent, '\$script:SchemaVersion\s*=\s*(\d+)')
    $schemaMatch.Success -and [int]$schemaMatch.Groups[1].Value -ge 7 -and
    $dbContent -match 'CREATE TABLE IF NOT EXISTS report_transfer_flows' -and
    $dbContent -match 'CREATE TABLE IF NOT EXISTS report_transfer_chains'
}

Check 'XFER-03' 'App.Database.psm1 exports transfer import and accessors' {
    $required = @('Import-TransferReport','Get-TransferFlowRows','Get-TransferChainRows','Get-TransferSummary')
    $allPresent = $true
    foreach ($fn in $required) {
        if ($dbContent -notmatch $fn) { $allPresent = $false; break }
    }
    $allPresent
}

Check 'XFER-04' 'App.UI.ps1 wires Transfer & Escalation pull, render, and drilldown handlers' {
    $uiContent -match 'function _StartTransferReportJob' -and
    $uiContent -match 'function _RenderTransferGrid' -and
    $uiContent -match 'function _OpenTransferChainConversation' -and
    $uiContent -match 'BtnPullTransferReport\.Add_Click' -and
    $uiContent -match 'DgTransferChains\.Add_SelectionChanged'
}

# ── FLOW / IVR REPORTING (FLOW) ────────────────────────────────────────────────

Write-Host "`n=== FLOW / IVR REPORTING ===" -ForegroundColor Cyan

Check 'FLOW-01' 'App.CoreAdapter.psm1 exposes Get-FlowContainmentReport dataset pulls' {
    $adapterContent -match 'function Get-FlowContainmentReport' -and
    $adapterContent -match 'analytics\.query\.flow\.aggregates\.execution\.metrics' -and
    $adapterContent -match 'flows\.get\.all\.flows' -and
    $adapterContent -match 'flows\.get\.flow\.milestones'
}

Check 'FLOW-02' 'App.Database.psm1 defines schema v8 flow containment tables' {
    $schemaMatch = [regex]::Match($dbContent, '\$script:SchemaVersion\s*=\s*(\d+)')
    $schemaMatch.Success -and [int]$schemaMatch.Groups[1].Value -ge 8 -and
    $dbContent -match 'CREATE TABLE IF NOT EXISTS report_flow_perf' -and
    $dbContent -match 'CREATE TABLE IF NOT EXISTS report_flow_milestone_distribution'
}

Check 'FLOW-03' 'App.Database.psm1 exports flow import and accessors' {
    $required = @('Import-FlowContainmentReport','Get-FlowPerfRows','Get-FlowMilestoneRows','Get-FlowContainmentSummary','Get-FlowQueueRouteRows')
    $allPresent = $true
    foreach ($fn in $required) {
        if ($dbContent -notmatch $fn) { $allPresent = $false; break }
    }
    $allPresent
}

Check 'FLOW-04' 'App.UI.ps1 wires Flow & IVR pull, render, and selection handlers' {
    $uiContent -match 'function _StartFlowContainmentReportJob' -and
    $uiContent -match 'function _RenderFlowContainmentGrid' -and
    $uiContent -match 'function _RenderSelectedFlowDetail' -and
    $uiContent -match 'BtnPullFlowContainmentReport\.Add_Click' -and
    $uiContent -match 'DgFlowPerf\.Add_SelectionChanged'
}

# ── WRAPUP / CONTACT REASONS REPORTING (WRAP) ─────────────────────────────────

Write-Host "`n=== WRAPUP / CONTACT REASONS REPORTING ===" -ForegroundColor Cyan

Check 'WRAP-01' 'App.CoreAdapter.psm1 exposes Get-WrapupDistributionReport dataset pulls' {
    $adapterContent -match 'function Get-WrapupDistributionReport' -and
    $adapterContent -match 'analytics\.query\.conversation\.aggregates\.wrapup\.distribution' -and
    $adapterContent -match 'routing\.get\.all\.wrapup\.codes'
}

Check 'WRAP-02' 'App.Database.psm1 defines schema v9 wrapup tables' {
    $schemaMatch = [regex]::Match($dbContent, '\$script:SchemaVersion\s*=\s*(\d+)')
    $schemaMatch.Success -and [int]$schemaMatch.Groups[1].Value -ge 9 -and
    $dbContent -match 'CREATE TABLE IF NOT EXISTS report_wrapup_distribution' -and
    $dbContent -match 'CREATE TABLE IF NOT EXISTS report_wrapup_by_hour'
}

Check 'WRAP-03' 'App.Database.psm1 exports wrapup import and accessors' {
    $required = @('Import-WrapupDistributionReport','Get-WrapupCodeRows','Get-WrapupByQueueRows',
                  'Get-WrapupByHourRows','Get-WrapupSummary','Get-WrapupConcentrationInsights',
                  'Get-WrapupHandleTimeCrossRef')
    $allPresent = $true
    foreach ($fn in $required) {
        if ($dbContent -notmatch $fn) { $allPresent = $false; break }
    }
    $allPresent
}

Check 'WRAP-04' 'App.UI.ps1 wires Contact Reasons pull, render, and selection handlers' {
    $uiContent -match 'function _StartWrapupDistributionReportJob' -and
    $uiContent -match 'function _RenderWrapupGrid' -and
    $uiContent -match 'function _RenderSelectedWrapupDetail' -and
    $uiContent -match 'BtnPullWrapupReport\.Add_Click' -and
    $uiContent -match 'DgWrapupCodes\.Add_SelectionChanged'
}

# ── SUMMARY ────────────────────────────────────────────────────────────────────

Write-Host "`n============================================" -ForegroundColor Cyan
$pass  = @($script:Results | Where-Object { $_.Result -eq 'PASS' }).Count
$fail  = @($script:Results | Where-Object { $_.Result -eq 'FAIL' }).Count
$total = $script:Results.Count

Write-Host "Results: $pass PASS  /  $fail FAIL  /  $total total" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

if ($fail -gt 0) {
    Write-Host "`nFailed checks:" -ForegroundColor Red
    $script:Results | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
        Write-Host "  [$($_.ID)] $($_.Check)" -ForegroundColor Red
        if ($_.Detail) { Write-Host "      $($_.Detail)" -ForegroundColor DarkRed }
    }
}

# Return structured results for use by Invoke-AllTests.ps1
return $script:Results

exit $(if ($script:AllPass) { 0 } else { 1 })
