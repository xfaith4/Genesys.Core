<#
.SYNOPSIS
    Queries Genesys Cloud conversation details and writes run artifacts for
    use with apps/ConversationAnalysis/index.html.

.DESCRIPTION
    Demonstrates the recommended pattern for calling Genesys.Core to pull
    conversation analytics data.  Authentication and pagination are handled
    entirely by Genesys.Auth and Genesys.Core respectively — this script only
    needs to supply the filter parameters and an output location.

    Authentication precedence (first match wins):
        1. -AccessToken parameter
        2. GENESYS_BEARER_TOKEN environment variable
        3. GENESYS_CLIENT_ID / GENESYS_CLIENT_SECRET environment variables
           (OAuth 2.0 client-credentials flow via Genesys.Auth)

    After the run completes, open apps/ConversationAnalysis/index.html in a
    browser and load the conversation JSONL file(s) from the printed data folder.

.PARAMETER Region
    Genesys Cloud region API hostname suffix (e.g. usw2.pure.cloud, mypurecloud.com).

.PARAMETER Interval
    ISO-8601 interval string for the query window.
    Format: <start>/<end>  e.g. '2026-03-01T00:00:00Z/2026-03-01T23:59:59Z'
    Omit to default to the last 24 hours.

.PARAMETER LookbackHours
    Number of past hours to query when -Interval is not specified.
    Valid range: 1–720 (default: 24).

.PARAMETER QueueId
    One or more queue GUIDs to filter results to conversations that touched
    those queues.  Accepts a single ID or a comma-separated list.
    Example: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

.PARAMETER ConversationId
    A single conversation GUID to retrieve details for that conversation only.

.PARAMETER DivisionId
    One or more division GUIDs to filter results to conversations belonging to
    those divisions.  Accepts a single ID or a comma-separated list.

.PARAMETER OutputRoot
    Root folder where Core writes run artifacts.
    Default: $env:LOCALAPPDATA\GenesysCore\runs

.PARAMETER CatalogPath
    Path to genesys.catalog.json.  Defaults to the catalog bundled with this
    repository.

.PARAMETER AccessToken
    Pre-obtained bearer token.  Overrides all environment-variable auth.

.EXAMPLE
    # Last 24 hours — all conversations
    .\Get-ConversationAnalysis.ps1 -Region 'usw2.pure.cloud'

.EXAMPLE
    # Specific date range
    .\Get-ConversationAnalysis.ps1 -Region 'usw2.pure.cloud' `
        -Interval '2026-03-05T00:00:00Z/2026-03-05T23:59:59Z'

.EXAMPLE
    # Filter to one or more queues
    .\Get-ConversationAnalysis.ps1 -Region 'usw2.pure.cloud' `
        -Interval '2026-03-05T00:00:00Z/2026-03-05T23:59:59Z' `
        -QueueId  'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

.EXAMPLE
    # Retrieve a single conversation by ID
    .\Get-ConversationAnalysis.ps1 -Region 'usw2.pure.cloud' `
        -ConversationId 'cccccccc-dddd-eeee-ffff-000000000000'

.EXAMPLE
    # Filter by division
    .\Get-ConversationAnalysis.ps1 -Region 'usw2.pure.cloud' `
        -Interval '2026-03-05T00:00:00Z/2026-03-05T23:59:59Z' `
        -DivisionId 'dddddddd-eeee-ffff-0000-111111111111'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Region,

    [string]$Interval,

    [ValidateRange(1, 720)]
    [int]$LookbackHours = 24,

    [string]$QueueId,

    [string]$ConversationId,

    [string]$DivisionId,

    [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'GenesysCore\runs'),

    [string]$CatalogPath = (Join-Path $PSScriptRoot '..\catalog\genesys.catalog.json'),

    [string]$AccessToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Module paths ─────────────────────────────────────────────────────────────
$authModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\modules\Genesys.Auth\Genesys.Auth.psd1'))
$coreModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\modules\Genesys.Core\Genesys.Core.psd1'))

Import-Module $authModulePath -Force -ErrorAction Stop
Import-Module $coreModulePath -Force -ErrorAction Stop

# ── Authentication ────────────────────────────────────────────────────────────
# The Auth module handles token storage, refresh, and DPAPI protection.
# This script only needs to establish the session — no token management here.

if (-not [string]::IsNullOrWhiteSpace($AccessToken)) {
    Connect-GenesysCloud -AccessToken $AccessToken -Region $Region | Out-Null
}
elseif (-not [string]::IsNullOrWhiteSpace($env:GENESYS_BEARER_TOKEN)) {
    Connect-GenesysCloud -AccessToken $env:GENESYS_BEARER_TOKEN -Region $Region | Out-Null
}
elseif (-not [string]::IsNullOrWhiteSpace($env:GENESYS_CLIENT_ID) -and
        -not [string]::IsNullOrWhiteSpace($env:GENESYS_CLIENT_SECRET)) {
    Connect-GenesysCloudApp `
        -ClientId     $env:GENESYS_CLIENT_ID `
        -ClientSecret $env:GENESYS_CLIENT_SECRET `
        -Region       $Region | Out-Null
}
else {
    throw 'No credentials found.  Set GENESYS_BEARER_TOKEN or GENESYS_CLIENT_ID + GENESYS_CLIENT_SECRET, or pass -AccessToken.'
}

$authCtx = Get-GenesysAuthContext

# ── Dataset parameters ────────────────────────────────────────────────────────
# Genesys.Core's Invoke-Dataset accepts a DatasetParameters hashtable.
# Interval, QueueIds, ConversationId, and DivisionIds are all recognised by
# the analytics-conversation-details dataset handler.

$datasetParams = @{}

if (-not [string]::IsNullOrWhiteSpace($Interval)) {
    $datasetParams['Interval'] = $Interval
}
else {
    $datasetParams['LookbackHours'] = $LookbackHours
}

if (-not [string]::IsNullOrWhiteSpace($QueueId)) {
    $datasetParams['QueueIds'] = $QueueId
}

if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
    $datasetParams['ConversationId'] = $ConversationId
}

if (-not [string]::IsNullOrWhiteSpace($DivisionId)) {
    $datasetParams['DivisionIds'] = $DivisionId
}

# ── Run ───────────────────────────────────────────────────────────────────────
# Invoke-Dataset handles pagination automatically.  For large result sets the
# analytics-conversation-details dataset uses an async job (submit → poll →
# fetch pages).  The analytics-conversation-details-query dataset is a faster
# synchronous alternative suited for shorter windows or preview runs.

Write-Host "Running analytics-conversation-details query against $($authCtx.BaseUri) ..."

$run = Invoke-Dataset `
    -Dataset           'analytics-conversation-details' `
    -CatalogPath       $CatalogPath `
    -OutputRoot        $OutputRoot `
    -BaseUri           $authCtx.BaseUri `
    -Headers           $authCtx.Headers `
    -DatasetParameters $datasetParams

# ── Results ───────────────────────────────────────────────────────────────────
$summary = if (Test-Path $run.summaryPath) {
    Get-Content -Raw $run.summaryPath | ConvertFrom-Json
} else { $null }

$totalConversations = if ($null -ne $summary) { $summary.totals.totalConversations } else { '?' }

Write-Host ''
Write-Host "Run complete."
Write-Host "  Conversations : $totalConversations"
Write-Host "  Run ID        : $($run.runId)"
Write-Host "  Run folder    : $($run.runFolder)"
Write-Host "  Data folder   : $($run.dataFolder)"
Write-Host "  Manifest      : $($run.manifestPath)"
Write-Host ''
Write-Host "Open apps/ConversationAnalysis/index.html in a browser, then load:"
Write-Host "  Required: data/*.jsonl from the data folder above"
Write-Host "  Optional: manifest.json from the run folder above"
Write-Host "Do not load events.jsonl or api-calls.log into the web page; those are diagnostics."

return $run
