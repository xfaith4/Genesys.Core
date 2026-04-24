#Requires -Version 5.1

<#
.SYNOPSIS
    Master test runner for Genesys Conversation Analysis.
.DESCRIPTION
    Runs:
      1. Test-Compliance.ps1  – full static Gate D/E compliance suite
      2. Architecture checks  – additional targeted architecture invariants
    Exits 0 on all-pass, 1 on any failure.
    Output is colour-coded and machine-readable.
.EXAMPLE
    pwsh -NoProfile -File .\tests\Invoke-AllTests.ps1
    pwsh -NoProfile -File .\tests\Invoke-AllTests.ps1 -AppRoot 'C:\MyApp'
#>

param(
    [string]$AppRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ───────────────────────────────────────────────────────────────────

$script:TotalPass = 0
$script:TotalFail = 0
$script:TotalSkip = 0

function ReadFile {
    param([string]$RelPath)
    $normalized = $RelPath -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::Combine($AppRoot, $normalized)
    if (-not [System.IO.File]::Exists($full)) { return '' }
    return [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
}

function ArchCheck {
    param([string]$Id, [string]$Description, [scriptblock]$Test)
    try {
        $result = & $Test
        if ($result -eq $true) {
            Write-Host "  [PASS] $Id  $Description" -ForegroundColor Green
            $script:TotalPass++
        } else {
            Write-Host "  [FAIL] $Id  $Description  (got: $result)" -ForegroundColor Red
            $script:TotalFail++
        }
    } catch {
        Write-Host "  [FAIL] $Id  $Description  (exception: $_)" -ForegroundColor Red
        $script:TotalFail++
    }
}

# ── Suite 1: Compliance suite ─────────────────────────────────────────────────

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Suite 1 – Static Compliance (Test-Compliance)  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

$complianceScript = [System.IO.Path]::Combine($PSScriptRoot, 'Test-Compliance.ps1')
if (-not [System.IO.File]::Exists($complianceScript)) {
    Write-Host "[ERROR] Test-Compliance.ps1 not found at: $complianceScript" -ForegroundColor Red
    exit 1
}

$complianceResults = & $complianceScript -AppRoot $AppRoot

# Accumulate compliance results
$cPass = @($complianceResults | Where-Object { $_.Result -eq 'PASS' }).Count
$cFail = @($complianceResults | Where-Object { $_.Result -eq 'FAIL' }).Count
$script:TotalPass += $cPass
$script:TotalFail += $cFail

# ── Suite 2: Architecture invariants ─────────────────────────────────────────

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Suite 2 – Architecture Invariants              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

$appPs      = ReadFile 'App.ps1'
$uiPs       = ReadFile 'scripts\App.UI.ps1'
$adapter    = ReadFile 'modules\App.CoreAdapter.psm1'
$index      = ReadFile 'modules\App.Index.psm1'
$export     = ReadFile 'modules\App.Export.psm1'
$reporting  = ReadFile 'modules\App.Reporting.psm1'
$database   = ReadFile 'modules\App.Database.psm1'
$config     = ReadFile 'modules\App.Config.psm1'
# Genesys.Auth lives in the parent repo's modules/ folder (Gate E)
$genesysAuthPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($AppRoot, '..', '..', 'modules', 'Genesys.Auth', 'Genesys.Auth.psm1'))
$genesysAuth = if ([System.IO.File]::Exists($genesysAuthPath)) {
    [System.IO.File]::ReadAllText($genesysAuthPath, [System.Text.Encoding]::UTF8)
} else { '' }
$xaml       = ReadFile 'resources\MainWindow.xaml'

# ── Architecture: startup path ────────────────────────────────────────────────
Write-Host "`n--- Startup path ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-01' 'App.ps1 calls Initialize-CoreAdapter at startup (Gate A)' {
    $appPs -match 'Initialize-CoreAdapter'
}

ArchCheck 'ARCH-02' 'App.ps1 does not import Genesys.Core directly' {
    $appPs -notmatch "Import-Module.*Genesys\.Core"
}

ArchCheck 'ARCH-03' 'App.ps1 dot-sources App.UI.ps1' {
    $appPs -match '\. .*App\.UI\.ps1'
}

ArchCheck 'ARCH-04' 'App.ps1 loads XAML from XAML\MainWindow.xaml' {
    $appPs -match 'MainWindow\.xaml'
}

ArchCheck 'ARCH-05' 'App.ps1 exits on Initialize-CoreAdapter failure (fail-safe)' {
    $appPs -match 'exit 1'
}

# ── Architecture: UI does not call Invoke-Dataset ─────────────────────────────
Write-Host "`n--- UI extraction boundary ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-06' 'App.UI.ps1 does not call Invoke-Dataset directly' {
    $uiPs -notmatch 'Invoke-Dataset'
}

ArchCheck 'ARCH-07' 'App.UI.ps1 delegates run to Start-PreviewRun/Start-FullRun via background runspace' {
    $uiPs -match 'Start-PreviewRun|Start-FullRun'
}

ArchCheck 'ARCH-08' 'App.UI.ps1 background runspace imports App.CoreAdapter.psm1' {
    $uiPs -match "Import-Module.*App\.CoreAdapter"
}

ArchCheck 'ARCH-09' 'App.UI.ps1 background runspace calls Initialize-CoreAdapter' {
    $uiPs -match 'Initialize-CoreAdapter'
}

# ── Architecture: dataset keys ────────────────────────────────────────────────
Write-Host "`n--- Dataset key model ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-10' 'Preview dataset key = analytics-conversation-details-query' {
    $adapter -match 'analytics-conversation-details-query'
}

ArchCheck 'ARCH-11' 'Full run dataset key = analytics-conversation-details (exact)' {
    $adapter -match "'analytics-conversation-details'"
}

ArchCheck 'ARCH-12' 'Two distinct dataset keys used (two-key model)' {
    ($adapter -match 'analytics-conversation-details-query') -and
    ($adapter -match "'analytics-conversation-details'")
}

# ── Architecture: indexing ────────────────────────────────────────────────────
Write-Host "`n--- Indexing and retrieval ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-13' 'App.Index.psm1 contains Build-RunIndex' {
    $index -match 'function Build-RunIndex'
}

ArchCheck 'ARCH-14' 'App.Index.psm1 contains Get-IndexedPage with Seek' {
    $index -match 'function Get-IndexedPage' -and $index -match '\.Seek\('
}

ArchCheck 'ARCH-15' 'App.Index.psm1 reads indexed records via byte offsets' {
    ($index -match '\.Seek\(') -and ($index -match '\.ReadByte\(')
}

ArchCheck 'ARCH-16' 'App.Index.psm1 writes index.jsonl' {
    $index -match 'index\.jsonl'
}

ArchCheck 'ARCH-17' 'App.Index.psm1 avoids Get-Content for large-file reads' {
    $index -notmatch 'Get-Content'
}

ArchCheck 'ARCH-18' 'App.Index.psm1 handles UTF-8 BOM' {
    $index -match '0xEF|BOM'
}

# ── Architecture: export streaming ────────────────────────────────────────────
Write-Host "`n--- Export streaming ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-19' 'App.Export.psm1 contains Export-RunToCsv' {
    $export -match 'function Export-RunToCsv'
}

ArchCheck 'ARCH-20' 'Export-RunToCsv uses StreamReader (streaming, not full load)' {
    $export -match 'StreamReader'
}

ArchCheck 'ARCH-21' 'Export-RunToCsv avoids Get-Content' {
    $export -notmatch 'Get-Content'
}

Write-Host "`n--- Reporting ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-22A' 'App.Reporting.psm1 contains New-ImpactReport' {
    $reporting -match 'function New-ImpactReport'
}

ArchCheck 'ARCH-22B' 'App.UI.ps1 can generate impact reports from filtered index state' {
    $uiPs -match 'New-ImpactReport'
}

ArchCheck 'ARCH-22C' 'DB-mode reports use full filtered population helpers, not the current page buffer' {
    $uiPs -match 'Get-ConversationPopulationRows' -and
    $uiPs -match 'New-PopulationReport' -and
    $uiPs -match 'exact_filter_state'
}

ArchCheck 'ARCH-22D' 'App.Database.psm1 exposes canonical SQL filter and analytics helpers' {
    $database -match 'function _GetConversationWhereClause' -and
    $database -match 'function Get-ConversationPopulationSummary' -and
    $database -match 'function Get-RepresentativeConversations'
}

ArchCheck 'ARCH-22E' 'Case store preserves raw payloads and lineage versions' {
    $database -match 'raw_json' -and
    $database -match 'payload_hash' -and
    $database -match 'CREATE TABLE IF NOT EXISTS conversation_versions'
}

ArchCheck 'ARCH-22F' 'Analyzer validates Core artifact contract before database import' {
    $database -match 'function Test-CoreRunArtifactContract' -and
    $database -match 'Test-CoreRunArtifactContract -RunFolder \$RunFolder -ThrowOnError' -and
    $database -match 'Import reconciliation failed'
}

# ── Architecture: auth containment ────────────────────────────────────────────
Write-Host "`n--- Auth containment (Genesys.Auth – sibling Core repo) ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-22' 'Genesys.Auth uses DPAPI Protect' {
    $genesysAuth -match 'ProtectedData.*Protect'
}

ArchCheck 'ARCH-23' 'Genesys.Auth targets login.{region} only (no /api/v2/)' {
    $genesysAuth -match 'login\.' -and ($genesysAuth -notmatch '/api/v2/')
}

ArchCheck 'ARCH-24' 'Auth token stored in LOCALAPPDATA path' {
    $genesysAuth -match 'LOCALAPPDATA'
}

# ── Architecture: run artifact contract ───────────────────────────────────────
Write-Host "`n--- Run artifact contract ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-25' 'Get-RunManifest reads manifest.json (not direct API)' {
    $adapter -match 'manifest\.json'
}

ArchCheck 'ARCH-26' 'Get-RunSummary reads summary.json' {
    $adapter -match 'summary\.json'
}

ArchCheck 'ARCH-27' 'Get-RunEvents uses FileStream for events.jsonl' {
    $adapter -match 'events\.jsonl' -and $adapter -match 'FileStream'
}

ArchCheck 'ARCH-28' 'Data files sourced from data\*.jsonl pattern' {
    $index -match 'data\\.*\.jsonl|data/.*\.jsonl|\*.jsonl'
}

# ── Architecture: XAML nuance ─────────────────────────────────────────────────
Write-Host "`n--- XAML nuance ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-29' 'BtnExpandJson exists in XAML (no handler required)' {
    $xaml -match "x:Name=""BtnExpandJson"""
}

ArchCheck 'ARCH-30' 'App.UI.ps1 does NOT bind a Click handler to BtnExpandJson' {
    $uiPs -notmatch "BtnExpandJson.*Add_Click|Add_Click.*BtnExpandJson"
}

Write-Host "`n--- Case store importer ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-31' 'App.ps1 imports App.Database.psm1' {
    $appPs -match "Import-Module.*App\.Database"
}

ArchCheck 'ARCH-32' 'App.Database.psm1 exports Import-RunFolderToCase' {
    $database -match 'function Import-RunFolderToCase' -and $database -match 'Import-RunFolderToCase,'
}

ArchCheck 'ARCH-33' 'App.Database.psm1 owns SQLite loading and connections' {
    $database -match 'System\.Data\.SQLite' -and $database -match 'SQLiteConnection'
}

ArchCheck 'ARCH-34' 'App.UI.ps1 uses Import-RunFolderToCase without opening SQLite directly' {
    ($uiPs -match 'Import-RunFolderToCase') -and ($uiPs -notmatch 'SQLiteConnection')
}

Write-Host "`n--- Case workflow and retention ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-35' 'App.Database.psm1 defines audit and saved-view tables' {
    $database -match 'CREATE TABLE IF NOT EXISTS case_audit' -and
    $database -match 'CREATE TABLE IF NOT EXISTS saved_views'
}

ArchCheck 'ARCH-36' 'App.Database.psm1 exposes archive and purge functions' {
    $database -match 'function Archive-Case' -and
    $database -match 'function Purge-Case' -and
    $database -match 'function Get-CaseAudit'
}

ArchCheck 'ARCH-37' 'App.UI.ps1 case dialog can save notes, tags, and current views' {
    $uiPs -match 'Update-CaseNotes' -and
    $uiPs -match 'Set-CaseTags' -and
    $uiPs -match 'New-SavedView'
}

Write-Host "`n--- Transfer and escalation reporting ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-40' 'CoreAdapter exposes transfer aggregate pull without UI direct dataset access' {
    $adapter -match 'function Get-TransferReport' -and
    $adapter -match 'analytics\.query\.conversation\.aggregates\.transfer\.metrics' -and
    $uiPs -notmatch 'Invoke-Dataset'
}

ArchCheck 'ARCH-41' 'Database owns transfer report schema, import, and accessors' {
    $database -match 'CREATE TABLE IF NOT EXISTS report_transfer_flows' -and
    $database -match 'CREATE TABLE IF NOT EXISTS report_transfer_chains' -and
    $database -match 'function Import-TransferReport' -and
    $database -match 'function Get-TransferFlowRows' -and
    $database -match 'function Get-TransferChainRows' -and
    $database -match 'function Get-TransferSummary'
}

ArchCheck 'ARCH-42' 'Transfer tab controls and handlers are wired' {
    $xaml -match 'BtnPullTransferReport' -and
    $xaml -match 'DgTransferFlows' -and
    $xaml -match 'DgTransferChains' -and
    $uiPs -match 'function _StartTransferReportJob' -and
    $uiPs -match 'function _RenderTransferGrid' -and
    $uiPs -match 'function _OpenTransferChainConversation'
}

Write-Host "`n--- Flow and IVR containment reporting ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-43' 'CoreAdapter exposes flow containment pulls without UI direct dataset access' {
    $adapter -match 'function Get-FlowContainmentReport' -and
    $adapter -match 'analytics\.query\.flow\.aggregates\.execution\.metrics' -and
    $adapter -match 'flows\.get\.all\.flows' -and
    $uiPs -notmatch 'Invoke-Dataset'
}

ArchCheck 'ARCH-44' 'Database owns flow containment schema, import, accessors, and queue correlation' {
    $database -match 'CREATE TABLE IF NOT EXISTS report_flow_perf' -and
    $database -match 'CREATE TABLE IF NOT EXISTS report_flow_milestone_distribution' -and
    $database -match 'function Import-FlowContainmentReport' -and
    $database -match 'function Get-FlowPerfRows' -and
    $database -match 'function Get-FlowMilestoneRows' -and
    $database -match 'function Get-FlowContainmentSummary' -and
    $database -match 'function Get-FlowQueueRouteRows'
}

ArchCheck 'ARCH-45' 'Flow & IVR tab controls and handlers are wired' {
    $xaml -match 'BtnPullFlowContainmentReport' -and
    $xaml -match 'DgFlowPerf' -and
    $xaml -match 'DgFlowMilestones' -and
    $xaml -match 'DgFlowQueues' -and
    $uiPs -match 'function _StartFlowContainmentReportJob' -and
    $uiPs -match 'function _RenderFlowContainmentGrid' -and
    $uiPs -match 'function _RenderSelectedFlowDetail'
}

Write-Host "`n--- Contact Reasons reporting ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-46' 'CoreAdapter exposes wrapup distribution pull without UI direct dataset access' {
    $adapter -match 'function Get-WrapupDistributionReport' -and
    $adapter -match 'analytics\.query\.conversation\.aggregates\.wrapup\.distribution' -and
    $adapter -match 'routing\.get\.all\.wrapup\.codes' -and
    $uiPs -notmatch 'Invoke-Dataset'
}

ArchCheck 'ARCH-47' 'Database owns wrapup schema, import, accessors, and insight helpers' {
    $schemaMatch = [regex]::Match($database, '\$script:SchemaVersion\s*=\s*(\d+)')
    $schemaMatch.Success -and [int]$schemaMatch.Groups[1].Value -ge 9 -and
    $database -match 'CREATE TABLE IF NOT EXISTS report_wrapup_distribution' -and
    $database -match 'CREATE TABLE IF NOT EXISTS report_wrapup_by_hour' -and
    $database -match 'function Import-WrapupDistributionReport' -and
    $database -match 'function Get-WrapupCodeRows' -and
    $database -match 'function Get-WrapupByQueueRows' -and
    $database -match 'function Get-WrapupByHourRows' -and
    $database -match 'function Get-WrapupConcentrationInsights' -and
    $database -match 'function Get-WrapupHandleTimeCrossRef'
}

ArchCheck 'ARCH-48' 'Contact Reasons tab controls and handlers are wired' {
    $xaml -match 'BtnPullWrapupReport' -and
    $xaml -match 'DgWrapupCodes' -and
    $xaml -match 'DgWrapupByQueue' -and
    $xaml -match 'DgWrapupByHour' -and
    $xaml -match 'DgWrapupInsights' -and
    $xaml -match 'DgWrapupCrossRef' -and
    $uiPs -match 'function _StartWrapupDistributionReportJob' -and
    $uiPs -match 'function _RenderWrapupGrid' -and
    $uiPs -match 'function _RenderSelectedWrapupDetail'
}

Write-Host "`n--- Quality and Voice-of-Customer reporting ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-49' 'CoreAdapter exposes quality overlay pulls without UI direct dataset access' {
    $adapter -match 'function Get-QualityOverlayReport' -and
    $adapter -match 'quality\.get\.evaluations\.query' -and
    $adapter -match 'quality\.get\.surveys' -and
    $adapter -match 'speechandtextanalytics\.get\.topics' -and
    $adapter -match 'analytics\.post\.transcripts\.aggregates\.query' -and
    $uiPs -notmatch 'Invoke-Dataset'
}

ArchCheck 'ARCH-50' 'Database and UI own quality schema, import, accessors, and drillthrough wiring' {
    $schemaMatch = [regex]::Match($database, '\$script:SchemaVersion\s*=\s*(\d+)')
    $schemaMatch.Success -and [int]$schemaMatch.Groups[1].Value -ge 11 -and
    $database -match 'CREATE TABLE IF NOT EXISTS report_evaluations' -and
    $database -match 'CREATE TABLE IF NOT EXISTS report_surveys' -and
    $database -match 'function Import-QualityOverlayReport' -and
    $database -match 'function Get-QualityAgentScoreRows' -and
    $database -match 'function Get-QualitySurveyQueueRows' -and
    $database -match 'function Get-LowScoreConversationRows' -and
    $database -match 'function Get-QualityCorrelationSummary' -and
    $database -match 'function Get-LowScoreTopicRows' -and
    $xaml -match 'BtnPullQualityReport' -and
    $xaml -match 'DgLowScoreConversations' -and
    $xaml -match 'TxtQualityCorrelation' -and
    $uiPs -match 'function _StartQualityOverlayReportJob' -and
    $uiPs -match 'function _RenderQualityGrid' -and
    $uiPs -match 'function _OpenLowScoreConversation'
}

# ── Architecture: config & strict mode ────────────────────────────────────────
Write-Host "`n--- Config and strict mode ---" -ForegroundColor DarkCyan

ArchCheck 'ARCH-38' 'App.Config.psm1 supports env overrides (GENESYS_CORE_MODULE/CATALOG/SCHEMA)' {
    $appPs -match 'GENESYS_CORE_MODULE' -and
    $appPs -match 'GENESYS_CORE_CATALOG'
}

ArchCheck 'ARCH-39' 'All .psm1 modules use Set-StrictMode -Version Latest' {
    $modules = @($adapter, $genesysAuth, $config, $index, $export, $database)
    @($modules | Where-Object { $_ -notmatch 'Set-StrictMode.*Latest' }).Count -eq 0
}

# ── Suite 3: Runtime smoke ────────────────────────────────────────────────────

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Suite 3 – Runtime Smoke                        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

$smokeScript = [System.IO.Path]::Combine($PSScriptRoot, 'Invoke-SmokeTests.ps1')
if (-not [System.IO.File]::Exists($smokeScript)) {
    Write-Host "[ERROR] Invoke-SmokeTests.ps1 not found at: $smokeScript" -ForegroundColor Red
    exit 1
}

$smokeResults = & $smokeScript -AppRoot $AppRoot
$sPass = @($smokeResults | Where-Object { $_.Result -eq 'PASS' }).Count
$sFail = @($smokeResults | Where-Object { $_.Result -eq 'FAIL' }).Count
$sSkip = @($smokeResults | Where-Object { $_.Result -eq 'SKIP' }).Count
$script:TotalPass += $sPass
$script:TotalFail += $sFail
$script:TotalSkip += $sSkip

# ── Final summary ─────────────────────────────────────────────────────────────

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  FINAL RESULTS                  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

$totalAll = $script:TotalPass + $script:TotalFail + $script:TotalSkip
$color    = if ($script:TotalFail -eq 0) { 'Green' } else { 'Red' }
Write-Host "  PASS: $($script:TotalPass)  FAIL: $($script:TotalFail)  SKIP: $($script:TotalSkip)  TOTAL: $totalAll" -ForegroundColor $color

if ($script:TotalFail -eq 0) {
    Write-Host "`n  ALL CHECKS PASSED. Application is compliant." -ForegroundColor Green
} else {
    Write-Host "`n  $($script:TotalFail) CHECK(S) FAILED. Review output above." -ForegroundColor Red
}

exit $(if ($script:TotalFail -eq 0) { 0 } else { 1 })
