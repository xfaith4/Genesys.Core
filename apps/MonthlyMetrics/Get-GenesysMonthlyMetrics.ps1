<#
.SYNOPSIS
    Extracts a comprehensive monthly operational and platform-utilization report from
    Genesys Cloud, covering conversation quality, agent performance, queue efficiency,
    IVR containment, digital channels, and API usage.  Exports a formatted, chart-
    embedded Excel workbook ready for executive review or pivot analysis.

.DESCRIPTION
    Authenticates via OAuth2 Client Credentials, fans out across twelve Genesys Cloud
    endpoint groups, normalises nested aggregate response shapes into flat rows, derives
    calculated KPIs (containment rate, occupancy, service level, abandon segmentation,
    seat utilisation, etc.), and writes a multi-sheet .xlsx workbook with embedded
    charts and a management Dashboard tab.

    Endpoint groups:
      Analytics
        POST /api/v2/analytics/conversations/aggregates/query   (volume, routing, wrap-up)
        POST /api/v2/analytics/users/aggregates/query           (agent occupancy & status)
        POST /api/v2/analytics/queues/aggregates/query          (service level, overflow)
        POST /api/v2/analytics/flows/aggregates/query           (IVR containment)
        POST /api/v2/analytics/flowexecutions/aggregates/query  (flow execution detail)
        POST /api/v2/analytics/actions/aggregates/query         (data action health)
        POST /api/v2/analytics/bots/aggregates/query            (bot containment)
      Roster
        GET  /api/v2/users                                      (seat count + name map)
        GET  /api/v2/routing/queues                             (queue name map)
      Usage
        GET  /api/v2/usage/events/definitions
        POST /api/v2/usage/events/aggregates/query
        POST /api/v2/usage/aggregates/query/jobs               (async, org-wide)
        POST /api/v2/usage/client/{clientId}/aggregates/query/jobs  (async, optional)

.PARAMETER ClientId
    Genesys Cloud OAuth2 Client ID (Client Credentials grant).

.PARAMETER ClientSecret
    Genesys Cloud OAuth2 Client Secret.  Accepts [SecureString].

.PARAMETER Year
    Target year (default: previous calendar month's year).

.PARAMETER Month
    Target month 1-12 (default: previous month).

.PARAMETER Region
    API region base URL.  Default: usw2.pure.cloud

.PARAMETER OutputPath
    Directory for the output .xlsx file.  Default: current directory.

.PARAMETER UsageClientId
    Optional OAuth Client ID to scope the per-client usage job endpoint.
    Omit to skip that sheet.

.PARAMETER ServiceLevelThresholdSec
    Answer-within threshold in seconds for service level calculation.
    Default: 20  (80/20 standard).

.PARAMETER OccupancyWarningPct
    Occupancy % above which an agent is flagged HIGH.  Default: 88.

.PARAMETER ShortAbandonSec
    Contacts abandoned within this many seconds are classified as short/erroneous.
    Default: 5.

.PARAMETER ConcurrencyGranularity
    Granularity used for the voice concurrent-call peak scan. Default: PT15M.

.PARAMETER JobPollIntervalSec
    Seconds between async job status polls.  Default: 5.

.PARAMETER JobTimeoutSec
    Maximum seconds to wait for an async job.  Default: 300.

.EXAMPLE
    .\Get-GenesysMonthlyMetrics.ps1 `
        -ClientId     "abc123" `
        -ClientSecret (Read-Host -AsSecureString "Secret") `
        -Year 2025 -Month 6

.NOTES
    Requires: ImportExcel module  (Install-Module ImportExcel -Scope CurrentUser)
    Permissions: analytics:*, routing:view, users:view, usage:*
    Rate limits: all calls use exponential back-off on HTTP 429 / 5xx.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]   $ClientId,
    [Parameter(Mandatory)][System.Security.SecureString] $ClientSecret,
    [ValidateRange(2000,2099)][int]  $Year                     = (Get-Date).AddMonths(-1).Year,
    [ValidateRange(1,12)]    [int]   $Month                    = (Get-Date).AddMonths(-1).Month,
    [string] $Region                   = 'usw2.pure.cloud',
    [string] $OutputPath               = '.',
    [string] $UsageClientId            = '',
    [int]    $ServiceLevelThresholdSec = 20,
    [int]    $OccupancyWarningPct      = 88,
    [int]    $ShortAbandonSec          = 5,
    [ValidatePattern('^P(?:\d+D|\d+M|T\d+[HMS])$')]
    [string] $ConcurrencyGranularity   = 'PT15M',
    [int]    $JobPollIntervalSec       = 5,
    [int]    $JobTimeoutSec            = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Dependency check ────────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    throw "ImportExcel module not found.  Run: Install-Module ImportExcel -Scope CurrentUser"
}
Import-Module ImportExcel -ErrorAction Stop
#endregion

#region ── Helper functions ────────────────────────────────────────────────────

function ConvertFrom-SecureStringPlain([System.Security.SecureString]$ss) {
    [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = @{ INFO='Cyan'; WARN='Yellow'; ERROR='Red'; OK='Green' }[$Level]
    Write-Host "[$ts][$Level] $Message" -ForegroundColor ($color ?? 'White')
}

function Get-ObjectPropertyValue {
    param($InputObject, [string]$Name, $Default = $null)
    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($Name)) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($Name)) {
        $value = $InputObject[$Name]
        if ($null -ne $value) { return $value }
        return $Default
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property -and $null -ne $property.Value) { return $property.Value }
    return $Default
}

function Get-ResponseResults {
    param($Response)
    return @(Get-ObjectPropertyValue $Response 'results' @())
}

function Get-IntervalStartText {
    param($InputObject)
    $interval = [string](Get-ObjectPropertyValue $InputObject 'Interval' '')
    if ([string]::IsNullOrWhiteSpace($interval)) { return '' }
    $start = @($interval -split '/', 2)[0]
    if ($start.Length -ge 10) { return $start.Substring(0, 10) }
    return $start
}

function Invoke-GenesysApi {
    param(
        [string]    $Uri,
        [string]    $Method     = 'GET',
        [hashtable] $Headers,
        [string]    $Body       = $null,
        [int]       $MaxRetries = 5
    )
    $attempt = 0
    do {
        $attempt++
        try {
            $p = @{
                Uri         = $Uri
                Method      = $Method
                Headers     = $Headers
                ContentType = 'application/json'
                ErrorAction = 'Stop'
            }
            if ($Body) { $p.Body = $Body }
            return Invoke-RestMethod @p
        }
        catch {
            $status = $_.Exception.Response?.StatusCode.value__
            if ($status -eq 429 -or ($status -ge 500 -and $status -lt 600)) {
                $wait = [math]::Pow(2, $attempt)
                Write-Log "HTTP $status — retry $attempt in ${wait}s" 'WARN'
                Start-Sleep -Seconds $wait
            }
            elseif ($attempt -ge $MaxRetries) { throw }
            else { throw }
        }
    } while ($attempt -le $MaxRetries)
}

function Get-PagedResults {
    param([string]$Uri, [hashtable]$Headers)
    $all  = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    do {
        $page = Invoke-GenesysApi -Uri $next -Headers $Headers
        foreach ($entity in @((Get-ObjectPropertyValue $page 'entities' @()))) {
            if ($null -ne $entity) { $all.Add($entity) }
        }
        $next = Get-ObjectPropertyValue $page 'nextUri' $null
        if (-not $next) {
            $pageLinks = Get-ObjectPropertyValue $page 'pageLinks' $null
            $next = Get-ObjectPropertyValue $pageLinks 'nextUri' $null
        }
    } while ($next)
    return $all
}

function Wait-GenesysJob {
    param([string]$JobStatusUri, [hashtable]$Headers)
    $deadline = (Get-Date).AddSeconds($JobTimeoutSec)
    do {
        Start-Sleep -Seconds $JobPollIntervalSec
        $job = Invoke-GenesysApi -Uri $JobStatusUri -Headers $Headers
        $state = Get-ObjectPropertyValue $job 'state' ''
        Write-Log "  Job status: $state" 'INFO'
        if ($state -eq 'FAILED') {
            $errorInfo = Get-ObjectPropertyValue $job 'error' $null
            $errorMessage = Get-ObjectPropertyValue $errorInfo 'message' 'no error message returned'
            throw "Async job failed: $errorMessage"
        }
    } while ($state -ne 'COMPLETED' -and (Get-Date) -lt $deadline)
    if ($state -ne 'COMPLETED') { throw "Job timed out after ${JobTimeoutSec}s" }
    return $job
}

function Expand-MetricStats {
    param($Results, [string]$Source)
    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($r in @($Results)) {
        if ($null -eq $r) { continue }
        $gp = @{}
        $group = Get-ObjectPropertyValue $r 'group' $null
        if ($group) {
            $group.PSObject.Properties | ForEach-Object { $gp[$_.Name] = $_.Value }
        }
        foreach ($d in @((Get-ObjectPropertyValue $r 'data' @()))) {
            if ($null -eq $d) { continue }
            foreach ($m in @((Get-ObjectPropertyValue $d 'metrics' @()))) {
                if ($null -eq $m) { continue }
                $stats = Get-ObjectPropertyValue $m 'stats' ([PSCustomObject]@{})
                $count = Get-ObjectPropertyValue $stats 'count' 0
                $sum   = Get-ObjectPropertyValue $stats 'sum' 0
                $row = [ordered]@{ Source = $Source; Interval = (Get-ObjectPropertyValue $d 'interval' '') }
                foreach ($k in $gp.Keys) { $row[$k] = $gp[$k] }
                $row['Metric'] = Get-ObjectPropertyValue $m 'metric' ''
                $row['Count']  = $count
                $row['Sum']    = $sum
                $row['Min']    = Get-ObjectPropertyValue $stats 'min' 0
                $row['Max']    = Get-ObjectPropertyValue $stats 'max' 0
                $row['Avg_ms'] = if ($count -gt 0) {
                    [math]::Round($sum / $count, 0) } else { 0 }
                $rows.Add([PSCustomObject]$row)
            }
        }
    }
    return $rows
}

function Get-MetricSum {
    param($Rows, [string]$Metric, [string]$Column = 'Count')
    ($Rows | Where-Object Metric -eq $Metric | Measure-Object $Column -Sum).Sum ?? 0
}

function Get-MetricPeakValue {
    param($Row)
    $max = [double](Get-ObjectPropertyValue $Row 'Max' 0)
    if ($max -gt 0) { return $max }
    $count = [double](Get-ObjectPropertyValue $Row 'Count' 0)
    if ($count -gt 0) { return $count }
    return [double](Get-ObjectPropertyValue $Row 'Sum' 0)
}

#endregion

#region ── Date range ──────────────────────────────────────────────────────────
$startDt    = [datetime]::new($Year, $Month, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
$endDt      = $startDt.AddMonths(1)
$interval   = "$($startDt.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))/$($endDt.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))"
$monthLabel = $startDt.ToString('yyyy-MM')

Write-Log "Target month : $monthLabel  |  Interval : $interval"
Write-Log "Config — SL: ${ServiceLevelThresholdSec}s  ShortAbandon: ${ShortAbandonSec}s  OccWarn: ${OccupancyWarningPct}%"
#endregion

#region ── Authentication ──────────────────────────────────────────────────────
Write-Log "Authenticating to $Region ..."
$plainSecret = ConvertFrom-SecureStringPlain $ClientSecret
$b64 = [System.Convert]::ToBase64String(
    [System.Text.Encoding]::UTF8.GetBytes("${ClientId}:${plainSecret}"))

$tokenResp = Invoke-RestMethod `
    -Uri         "https://login.$Region/oauth/token" `
    -Method      POST `
    -Headers     @{ Authorization = "Basic $b64" } `
    -Body        'grant_type=client_credentials' `
    -ContentType 'application/x-www-form-urlencoded'

$authHeaders = @{
    Authorization  = "Bearer $($tokenResp.access_token)"
    'Content-Type' = 'application/json'
}
$apiBase = "https://api.$Region/api/v2"
Write-Log "Authenticated — token valid for $($tokenResp.expires_in)s" 'OK'
#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 1 — ROSTER LOOKUPS
#══════════════════════════════════════════════════════════════════════════════

Write-Log "Fetching queue catalog ..."
$queueEntities = Get-PagedResults -Uri "$apiBase/routing/queues?pageSize=100" -Headers $authHeaders
$queueMap = @{}
$queueEntities | ForEach-Object { $queueMap[$_.id] = $_.name }
Write-Log "  Queues: $($queueMap.Count)" 'OK'

Write-Log "Fetching active user roster ..."
$userEntities      = Get-PagedResults -Uri "$apiBase/users?pageSize=500&state=active" -Headers $authHeaders
$userMap           = @{}
$userEntities | ForEach-Object { $userMap[$_.id] = $_.name }
$totalLicensedSeats = $userEntities.Count
Write-Log "  Active users (licensed seats): $totalLicensedSeats" 'OK'

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 2 — CONVERSATION AGGREGATES  (three targeted queries)
#══════════════════════════════════════════════════════════════════════════════

# ── 2a  Volume + Handle Time ─────────────────────────────────────────────────
Write-Log "Querying conversation volume + handle time ..."
$convVolumeRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/conversations/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1D'
        groupBy     = @('queueId','mediaType','originatingDirection')
        metrics     = @(
            'nOffered','nAnswered','nAbandonedPhase',
            'tHandle','tTalk','tAcw','tHeld',
            'tAnswered','tAbandoned',
            'nTransferred','nOutbound','nOutboundAttempted','nOutboundConnected'
        )
    } | ConvertTo-Json -Depth 5)

$convVolumeRows = Expand-MetricStats -Results (Get-ResponseResults $convVolumeRaw) -Source 'Conv_Volume'
$convVolumeRows | ForEach-Object {
    $queueId = Get-ObjectPropertyValue $_ 'queueId' ''
    $_ | Add-Member -NotePropertyName 'QueueName' `
        -NotePropertyValue ($queueMap[$queueId] ?? $queueId) -Force
}
Write-Log "  Volume rows: $($convVolumeRows.Count)" 'OK'

# ── 2b  Wrap-up code distribution ────────────────────────────────────────────
Write-Log "Querying wrap-up code distribution ..."
$convWrapRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/conversations/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1M'
        groupBy     = @('wrapUpCode','queueId','mediaType')
        metrics     = @('nWrappedPhase')
    } | ConvertTo-Json -Depth 5)

$convWrapRows = Expand-MetricStats -Results (Get-ResponseResults $convWrapRaw) -Source 'Conv_WrapUp'
$convWrapRows | ForEach-Object {
    $queueId = Get-ObjectPropertyValue $_ 'queueId' ''
    $_ | Add-Member -NotePropertyName 'QueueName' `
        -NotePropertyValue ($queueMap[$queueId] ?? $queueId) -Force
}
Write-Log "  Wrap-up rows: $($convWrapRows.Count)" 'OK'

# ── 2c  Transfer breakdown ────────────────────────────────────────────────────
Write-Log "Querying transfer analysis ..."
$convXferRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/conversations/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1D'
        groupBy     = @('queueId','mediaType')
        metrics     = @('nTransferred','nBlindTransferred','nConsultTransferred',
                        'nOffered','nAnswered')
    } | ConvertTo-Json -Depth 5)

$convXferRows = Expand-MetricStats -Results (Get-ResponseResults $convXferRaw) -Source 'Conv_Transfer'
$convXferRows | ForEach-Object {
    $queueId = Get-ObjectPropertyValue $_ 'queueId' ''
    $_ | Add-Member -NotePropertyName 'QueueName' `
        -NotePropertyValue ($queueMap[$queueId] ?? $queueId) -Force
}
Write-Log "  Transfer rows: $($convXferRows.Count)" 'OK'

# ── 2d  Reporting totals by direction, media, message type ──────────────────
Write-Log "Querying monthly reporting totals by originating direction, mediaType, and messageType ..."
$monthlyTotalsRows = @()
$monthlyTotalsIncludeMessageType = $true
try {
    $monthlyTotalsRaw = Invoke-GenesysApi `
        -Uri    "$apiBase/analytics/conversations/aggregates/query" `
        -Method POST -Headers $authHeaders `
        -Body   (@{
            interval    = $interval
            granularity = 'P1M'
            groupBy     = @('originatingDirection','mediaType','messageType')
            metrics     = @('nOffered','nAnswered','nConnected','nOutbound','nAbandoned','nAbandonedPhase')
        } | ConvertTo-Json -Depth 5)

    $monthlyTotalsRows = @(Expand-MetricStats -Results (Get-ResponseResults $monthlyTotalsRaw) -Source 'Monthly_Totals')
}
catch {
    $monthlyTotalsIncludeMessageType = $false
    Write-Log "  messageType monthly aggregate unavailable; retrying totals without messageType. ($_)" 'WARN'
    $monthlyTotalsRaw = Invoke-GenesysApi `
        -Uri    "$apiBase/analytics/conversations/aggregates/query" `
        -Method POST -Headers $authHeaders `
        -Body   (@{
            interval    = $interval
            granularity = 'P1M'
            groupBy     = @('originatingDirection','mediaType')
            metrics     = @('nOffered','nAnswered','nConnected','nOutbound','nAbandoned','nAbandonedPhase')
        } | ConvertTo-Json -Depth 5)

    $monthlyTotalsRows = @(Expand-MetricStats -Results (Get-ResponseResults $monthlyTotalsRaw) -Source 'Monthly_Totals')
}
Write-Log "  Monthly total metric rows: $($monthlyTotalsRows.Count)" 'OK'

# ── 2e  Peak concurrent voice, inbound/outbound ─────────────────────────────
Write-Log "Querying peak concurrent voice inbound/outbound ($ConcurrencyGranularity buckets) ..."
$voiceConcurrentRows = @()
try {
    $voiceConcurrentRaw = Invoke-GenesysApi `
        -Uri    "$apiBase/analytics/conversations/aggregates/query" `
        -Method POST -Headers $authHeaders `
        -Body   (@{
            interval    = $interval
            granularity = $ConcurrencyGranularity
            groupBy     = @('originatingDirection','mediaType')
            metrics     = @('oConcurrent')
            filter      = @{
                type = 'and'
                predicates = @(
                    @{ type = 'dimension'; dimension = 'mediaType'; operator = 'matches'; value = 'voice' }
                )
            }
        } | ConvertTo-Json -Depth 8)

    $voiceConcurrentRows = @(Expand-MetricStats -Results (Get-ResponseResults $voiceConcurrentRaw) -Source 'Voice_Concurrent')
}
catch {
    Write-Log "  Peak concurrent voice aggregate unavailable; continuing without concurrency sheet. ($_)" 'WARN'
}
Write-Log "  Voice concurrent metric rows: $($voiceConcurrentRows.Count)" 'OK'

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 3 — QUEUE SERVICE LEVEL
#══════════════════════════════════════════════════════════════════════════════

Write-Log "Querying queue service level ..."
$queueSLRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/queues/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1D'
        groupBy     = @('queueId','mediaType')
        metrics     = @(
            'nOffered','nAnswered','nAbandonedPhase',
            'tAnswered','tAbandoned',
            'oServiceLevel',
            'nOverflowOut','nOverflowIn'
        )
    } | ConvertTo-Json -Depth 5)

$queueSLRows = Expand-MetricStats -Results (Get-ResponseResults $queueSLRaw) -Source 'Queue_SL'
$queueSLRows | ForEach-Object {
    $queueId = Get-ObjectPropertyValue $_ 'queueId' ''
    $_ | Add-Member -NotePropertyName 'QueueName' `
        -NotePropertyValue ($queueMap[$queueId] ?? $queueId) -Force
}
Write-Log "  Queue SL rows: $($queueSLRows.Count)" 'OK'

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 4 — AGENT AGGREGATES  (occupancy + status utilisation)
#══════════════════════════════════════════════════════════════════════════════

Write-Log "Querying agent occupancy ..."
$userAggRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/users/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1D'
        groupBy     = @('userId')
        metrics     = @(
            'tAgentRoutable',
            'tTalk','tAcw','tHeld',
            'tNotResponding','nNotResponding',
            'tOnQueueTime'
        )
    } | ConvertTo-Json -Depth 5)

$userAggRows = Expand-MetricStats -Results (Get-ResponseResults $userAggRaw) -Source 'Agent_Occ'
$userAggRows | ForEach-Object {
    $userId = Get-ObjectPropertyValue $_ 'userId' ''
    $_ | Add-Member -NotePropertyName 'AgentName' `
        -NotePropertyValue ($userMap[$userId] ?? $userId) -Force
}
Write-Log "  Agent occupancy rows: $($userAggRows.Count)" 'OK'

Write-Log "Querying agent status distribution ..."
$userStatusRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/users/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1M'
        groupBy     = @('userId','routingStatus')
        metrics     = @('tAgentRoutingStatuses')
    } | ConvertTo-Json -Depth 5)

$userStatusRows = Expand-MetricStats -Results (Get-ResponseResults $userStatusRaw) -Source 'Agent_Status'
$userStatusRows | ForEach-Object {
    $userId = Get-ObjectPropertyValue $_ 'userId' ''
    $_ | Add-Member -NotePropertyName 'AgentName' `
        -NotePropertyValue ($userMap[$userId] ?? $userId) -Force
}
Write-Log "  Agent status rows: $($userStatusRows.Count)" 'OK'

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 5 — IVR FLOW AGGREGATES  (containment)
#══════════════════════════════════════════════════════════════════════════════

Write-Log "Querying IVR flow containment ..."
$flowContainRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/flows/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1D'
        groupBy     = @('flowId','flowType','exitReason')
        metrics     = @(
            'nFlow','tFlow',
            'nFlowEntries','nFlowExits',
            'tFlowDisconnect','nFlowDisconnect',
            'nFlowOutcome'
        )
    } | ConvertTo-Json -Depth 5)

$flowContainRows = Expand-MetricStats -Results (Get-ResponseResults $flowContainRaw) -Source 'Flow_Contain'
Write-Log "  Flow containment rows: $($flowContainRows.Count)" 'OK'

Write-Log "Querying flow execution detail ..."
$flowExecRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/flowexecutions/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1D'
        groupBy     = @('flowId','flowType','exitReason')
        metrics     = @('tFlow','tFlowOutcome','nFlow')
    } | ConvertTo-Json -Depth 5)

$flowExecRows = Expand-MetricStats -Results (Get-ResponseResults $flowExecRaw) -Source 'Flow_Exec'
Write-Log "  Flow execution rows: $($flowExecRows.Count)" 'OK'

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 6 — BOT AGGREGATES  (digital/chat containment)
#══════════════════════════════════════════════════════════════════════════════

$botRows = [System.Collections.Generic.List[PSCustomObject]]::new()
Write-Log "Querying bot aggregates ..."
try {
    $botRaw = Invoke-GenesysApi `
        -Uri    "$apiBase/analytics/bots/aggregates/query" `
        -Method POST -Headers $authHeaders `
        -Body   (@{
            interval    = $interval
            granularity = 'P1D'
            groupBy     = @('botId','botVersion','finalIntent')
            metrics     = @(
                'nBotSessions','tBotSession',
                'nBotSessionTurns',
                'nBotIntentMatched','nBotIntentNotMatched',
                'nBotEscalated'
            )
        } | ConvertTo-Json -Depth 5)

    $botRows.AddRange((Expand-MetricStats -Results (Get-ResponseResults $botRaw) -Source 'Bot'))
    Write-Log "  Bot rows: $($botRows.Count)" 'OK'
}
catch {
    Write-Log "  Bot endpoint unavailable or no data — skipping. ($_)" 'WARN'
}

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 7 — DATA ACTIONS AGGREGATES
#══════════════════════════════════════════════════════════════════════════════

Write-Log "Querying data action aggregates ..."
$actionsRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/analytics/actions/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{
        interval    = $interval
        granularity = 'P1D'
        groupBy     = @('actionId','actionType')
        metrics     = @('tAction','nAction','nActionSuccess','nActionFailed')
    } | ConvertTo-Json -Depth 5)

$actionsRows = Expand-MetricStats -Results (Get-ResponseResults $actionsRaw) -Source 'Actions'
Write-Log "  Action rows: $($actionsRows.Count)" 'OK'

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 8 — USAGE ENDPOINTS
#══════════════════════════════════════════════════════════════════════════════

Write-Log "Fetching usage event definitions ..."
$eventDefs    = Invoke-GenesysApi -Uri "$apiBase/usage/events/definitions" -Headers $authHeaders
$eventDefRows = @((Get-ObjectPropertyValue $eventDefs 'entities' @())) | ForEach-Object {
    [PSCustomObject]@{
        EventDefinitionId = Get-ObjectPropertyValue $_ 'id' ''
        EventName         = Get-ObjectPropertyValue $_ 'name' ''
        Description       = Get-ObjectPropertyValue $_ 'description' ''
        Category          = Get-ObjectPropertyValue $_ 'category' ''
        IsUsageBased      = Get-ObjectPropertyValue $_ 'isUsageBased' $false
    }
}
Write-Log "  Event definitions: $($eventDefRows.Count)" 'OK'

Write-Log "Querying usage event aggregates ..."
$usageEventsRaw = Invoke-GenesysApi `
    -Uri    "$apiBase/usage/events/aggregates/query" `
    -Method POST -Headers $authHeaders `
    -Body   (@{ interval=$interval; groupBy=@('eventDefinitionId'); granularity='P1D' } | ConvertTo-Json -Depth 5)

$usageEventRows = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($r in (Get-ResponseResults $usageEventsRaw)) {
    $group = Get-ObjectPropertyValue $r 'group' $null
    $defId = Get-ObjectPropertyValue $group 'eventDefinitionId' ''
    $defName = ($eventDefRows | Where-Object EventDefinitionId -eq $defId).EventName
    foreach ($d in @((Get-ObjectPropertyValue $r 'data' @()))) {
        $usageEventRows.Add([PSCustomObject]@{
            Source='UsageEvents'; Interval=(Get-ObjectPropertyValue $d 'interval' '')
            EventDefinitionId=$defId; EventName=$defName; Count=(Get-ObjectPropertyValue $d 'count' 0)
        })
    }
}
Write-Log "  Usage event rows: $($usageEventRows.Count)" 'OK'

Write-Log "Submitting org-wide usage aggregates job ..."
$usageJobSubmit = Invoke-GenesysApi `
    -Uri    "$apiBase/usage/aggregates/query/jobs" `
    -Method POST -Headers $authHeaders `
    -Body   (@{ interval=$interval; groupBy=@('clientId','templateUri','httpMethod'); granularity='P1D' } | ConvertTo-Json -Depth 5)

$usageJobResult = Wait-GenesysJob `
    -JobStatusUri "$apiBase/usage/aggregates/query/jobs/$(Get-ObjectPropertyValue $usageJobSubmit 'id' '')" `
    -Headers $authHeaders

$usageApiRows = [System.Collections.Generic.List[PSCustomObject]]::new()
$pageUri = Get-ObjectPropertyValue $usageJobResult 'resultUri' $null
while ($pageUri) {
    $page = Invoke-GenesysApi -Uri $pageUri -Headers $authHeaders
    foreach ($r in (Get-ResponseResults $page)) {
        $group = Get-ObjectPropertyValue $r 'group' $null
        foreach ($d in @((Get-ObjectPropertyValue $r 'data' @()))) {
            $usageApiRows.Add([PSCustomObject]@{
                Source='UsageAggregates'; Interval=(Get-ObjectPropertyValue $d 'interval' '')
                ClientId=(Get-ObjectPropertyValue $group 'clientId' '')
                TemplateUri=(Get-ObjectPropertyValue $group 'templateUri' '')
                HttpMethod=(Get-ObjectPropertyValue $group 'httpMethod' '')
                Count=(Get-ObjectPropertyValue $d 'count' 0)
            })
        }
    }
    $pageUri = Get-ObjectPropertyValue $page 'nextUri' $null
}
Write-Log "  API usage rows: $($usageApiRows.Count)" 'OK'

$clientUsageRows = [System.Collections.Generic.List[PSCustomObject]]::new()
if ($UsageClientId) {
    Write-Log "Submitting per-client usage job: $UsageClientId ..."
    $cjSubmit = Invoke-GenesysApi `
        -Uri    "$apiBase/usage/client/$UsageClientId/aggregates/query/jobs" `
        -Method POST -Headers $authHeaders `
        -Body   (@{ interval=$interval; groupBy=@('templateUri','httpMethod'); granularity='P1D' } | ConvertTo-Json -Depth 5)

    $cjResult = Wait-GenesysJob `
        -JobStatusUri "$apiBase/usage/client/$UsageClientId/aggregates/query/jobs/$(Get-ObjectPropertyValue $cjSubmit 'id' '')" `
        -Headers $authHeaders

    $pageUri = Get-ObjectPropertyValue $cjResult 'resultUri' $null
    while ($pageUri) {
        $page = Invoke-GenesysApi -Uri $pageUri -Headers $authHeaders
        foreach ($r in (Get-ResponseResults $page)) {
            $group = Get-ObjectPropertyValue $r 'group' $null
            foreach ($d in @((Get-ObjectPropertyValue $r 'data' @()))) {
                $clientUsageRows.Add([PSCustomObject]@{
                    Source='ClientUsage'; Interval=(Get-ObjectPropertyValue $d 'interval' ''); ClientId=$UsageClientId
                    TemplateUri=(Get-ObjectPropertyValue $group 'templateUri' '')
                    HttpMethod=(Get-ObjectPropertyValue $group 'httpMethod' '')
                    Count=(Get-ObjectPropertyValue $d 'count' 0)
                })
            }
        }
        $pageUri = Get-ObjectPropertyValue $page 'nextUri' $null
    }
    Write-Log "  Per-client rows: $($clientUsageRows.Count)" 'OK'
}

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 9 — DERIVED SUMMARY TABLES
#══════════════════════════════════════════════════════════════════════════════

Write-Log "Building derived summary tables ..."

# ── 9a  Monthly reporting totals ─────────────────────────────────────────────
$monthlyReportingTotals = $monthlyTotalsRows |
    Where-Object { $_.Metric -in @('nOffered','nAnswered','nConnected','nOutbound','nAbandoned','nAbandonedPhase') } |
    Group-Object originatingDirection, mediaType, messageType |
    ForEach-Object {
        $g = $_.Group
        $direction = [string](Get-ObjectPropertyValue $g[0] 'originatingDirection' '')
        $media = [string](Get-ObjectPropertyValue $g[0] 'mediaType' '')
        $message = [string](Get-ObjectPropertyValue $g[0] 'messageType' '')
        if ([string]::IsNullOrWhiteSpace($direction)) { $direction = '(not returned)' }
        if ([string]::IsNullOrWhiteSpace($media)) { $media = '(not returned)' }
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = if ($monthlyTotalsIncludeMessageType) { '(blank)' } else { '(not returned)' }
        }

        $offered = Get-MetricSum $g 'nOffered'
        $answered = Get-MetricSum $g 'nAnswered'
        $connected = Get-MetricSum $g 'nConnected'
        $outbound = Get-MetricSum $g 'nOutbound'
        $abandoned = Get-MetricSum $g 'nAbandoned'
        $abandonedPhase = Get-MetricSum $g 'nAbandonedPhase'
        if ($abandoned -eq 0 -and $abandonedPhase -gt 0) { $abandoned = $abandonedPhase }
        $volume = if ($direction -eq 'outbound' -and $outbound -gt 0) {
            $outbound
        } elseif ($offered -gt 0) {
            $offered
        } elseif ($connected -gt 0) {
            $connected
        } else {
            $answered
        }

        [PSCustomObject]@{
            Month                = $monthLabel
            OriginatingDirection = $direction
            MediaType            = $media
            MessageType          = $message
            Volume               = $volume
            Offered              = $offered
            Answered             = $answered
            Connected            = $connected
            Outbound             = $outbound
            Abandoned            = $abandoned
            AbandonRate_Pct      = [math]::Round($(if($offered -gt 0){$abandoned/$offered*100}else{0}),1)
            MessageTypeStatus    = if ($monthlyTotalsIncludeMessageType) { 'returned' } else { 'fallback-no-messageType' }
        }
    } | Sort-Object OriginatingDirection, MediaType, MessageType

# ── 9b  Peak concurrent voice summary ───────────────────────────────────────
$voicePeakConcurrentSummary = foreach ($direction in @('inbound','outbound')) {
    $directionRows = @($voiceConcurrentRows | Where-Object {
        $_.Metric -eq 'oConcurrent' -and
        [string](Get-ObjectPropertyValue $_ 'mediaType' '') -eq 'voice' -and
        [string](Get-ObjectPropertyValue $_ 'originatingDirection' '') -eq $direction
    })

    $peakRow = $null
    $peakValue = 0
    foreach ($row in $directionRows) {
        $value = Get-MetricPeakValue $row
        if ($null -eq $peakRow -or $value -gt $peakValue) {
            $peakRow = $row
            $peakValue = $value
        }
    }

    $peakInterval = ''
    if ($null -ne $peakRow) {
        $peakInterval = [string](Get-ObjectPropertyValue $peakRow 'Interval' '')
    }
    $peakStart = if (-not [string]::IsNullOrWhiteSpace($peakInterval)) {
        @($peakInterval -split '/', 2)[0]
    } else {
        ''
    }

    [PSCustomObject]@{
        Month                = $monthLabel
        OriginatingDirection = $direction
        MediaType            = 'voice'
        Metric               = 'oConcurrent'
        PeakConcurrentVoice  = [math]::Round($peakValue, 0)
        PeakIntervalStartUtc = $peakStart
        PeakInterval         = $peakInterval
        Granularity          = $ConcurrencyGranularity
        Samples              = $directionRows.Count
    }
}

# ── 9a  Conversation daily summary ───────────────────────────────────────────
$convDailySummary = $convVolumeRows |
    Where-Object { $_.Metric -in @('nOffered','nAnswered','nAbandonedPhase',
                                    'tHandle','tTalk','tAcw','nTransferred') } |
    Group-Object Interval, mediaType |
    ForEach-Object {
        $g        = $_.Group
        $offered  = Get-MetricSum $g 'nOffered'
        $answered = Get-MetricSum $g 'nAnswered'
        $aband    = Get-MetricSum $g 'nAbandonedPhase'
        $tHandle  = Get-MetricSum $g 'tHandle' 'Sum'
        $tTalk    = Get-MetricSum $g 'tTalk'   'Sum'
        $tAcw     = Get-MetricSum $g 'tAcw'    'Sum'
        $xferred  = Get-MetricSum $g 'nTransferred'
        [PSCustomObject]@{
            Date             = Get-IntervalStartText $g[0]
            MediaType        = Get-ObjectPropertyValue $g[0] 'mediaType' ''
            Offered          = $offered
            Answered         = $answered
            Abandoned        = $aband
            Transferred      = $xferred
            AnswerRate_Pct   = [math]::Round($(if($offered  -gt 0){$answered/$offered*100}  else{0}),1)
            AbandonRate_Pct  = [math]::Round($(if($offered  -gt 0){$aband/$offered*100}     else{0}),1)
            TransferRate_Pct = [math]::Round($(if($answered -gt 0){$xferred/$answered*100}  else{0}),1)
            AHT_sec          = [math]::Round($(if($answered -gt 0){$tHandle/$answered/1000} else{0}),1)
            AvgTalkTime_sec  = [math]::Round($(if($answered -gt 0){$tTalk/$answered/1000}   else{0}),1)
            AvgAcwTime_sec   = [math]::Round($(if($answered -gt 0){$tAcw/$answered/1000}    else{0}),1)
        }
    } | Sort-Object Date, MediaType

# ── 9b  Abandon segmentation ──────────────────────────────────────────────────
$abandonSummary = $convVolumeRows |
    Where-Object { $_.Metric -in @('nAbandonedPhase','tAbandoned') } |
    Group-Object Interval, queueId |
    ForEach-Object {
        $g         = $_.Group
        $n         = Get-MetricSum $g 'nAbandonedPhase'
        $tSum      = Get-MetricSum $g 'tAbandoned' 'Sum'
        $tMin      = ($g | Where-Object Metric -eq 'tAbandoned' | Measure-Object Min -Minimum).Minimum ?? 0
        $avgWait_s = if ($n -gt 0) { [math]::Round($tSum/$n/1000,1) } else { 0 }
        $queueId   = Get-ObjectPropertyValue $g[0] 'queueId' ''
        [PSCustomObject]@{
            Date                      = Get-IntervalStartText $g[0]
            QueueId                   = $queueId
            QueueName                 = ($queueMap[$queueId] ?? $queueId)
            TotalAbandoned            = $n
            AvgWaitBeforeAbandon_sec  = $avgWait_s
            MinWaitBeforeAbandon_sec  = [math]::Round($tMin/1000,1)
            ShortAbandonThreshold_sec = $ShortAbandonSec
            ClassifiedShortAbandon    = $avgWait_s -le $ShortAbandonSec -and $n -gt 0
        }
    } | Sort-Object Date, QueueName

# ── 9c  Queue service level summary ──────────────────────────────────────────
$queueSLSummary = $queueSLRows |
    Where-Object { $_.Metric -in @('nOffered','nAnswered','nAbandonedPhase',
                                    'tAnswered','oServiceLevel','nOverflowOut') } |
    Group-Object queueId, mediaType |
    ForEach-Object {
        $g        = $_.Group
        $offered  = Get-MetricSum $g 'nOffered'
        $answered = Get-MetricSum $g 'nAnswered'
        $osl      = Get-MetricSum $g 'oServiceLevel' 'Sum'
        $overflow = Get-MetricSum $g 'nOverflowOut'
        $tAns_sum = Get-MetricSum $g 'tAnswered' 'Sum'
        $avgAns_s = if ($answered -gt 0) { $tAns_sum/$answered/1000 } else { 999 }
        $slPct    = if ($osl -gt 0) { [math]::Round($osl,1) }
                    elseif ($offered -gt 0) {
                        [math]::Round($(if($avgAns_s -le $ServiceLevelThresholdSec){$answered/$offered*100}else{0}),1)
                    } else { 0 }
        $queueId  = Get-ObjectPropertyValue $g[0] 'queueId' ''
        [PSCustomObject]@{
            QueueId              = $queueId
            QueueName            = ($queueMap[$queueId] ?? $queueId)
            MediaType            = Get-ObjectPropertyValue $g[0] 'mediaType' ''
            TotalOffered         = $offered
            TotalAnswered        = $answered
            OverflowOut          = $overflow
            OverflowRate_Pct     = [math]::Round($(if($offered -gt 0){$overflow/$offered*100}else{0}),1)
            AvgSpeedAnswer_sec   = [math]::Round($avgAns_s,1)
            ServiceLevel_Pct     = $slPct
            SL_Target_sec        = $ServiceLevelThresholdSec
            BelowTarget          = $slPct -lt 80
        }
    } | Sort-Object -Property @{ Expression = 'BelowTarget'; Descending = $true }, 'QueueName'

# ── 9d  Agent occupancy summary ───────────────────────────────────────────────
$agentOccupancySummary = $userAggRows |
    Where-Object { $_.Metric -in @('tAgentRoutable','tTalk','tAcw','tNotResponding','nNotResponding') } |
    Group-Object userId |
    ForEach-Object {
        $g        = $_.Group
        $routable = Get-MetricSum $g 'tAgentRoutable' 'Sum'
        $talk     = Get-MetricSum $g 'tTalk'          'Sum'
        $acw      = Get-MetricSum $g 'tAcw'           'Sum'
        $notResp  = Get-MetricSum $g 'tNotResponding'  'Sum'
        $notRespN = Get-MetricSum $g 'nNotResponding'
        $handling = $talk + $acw
        $occ      = if ($routable -gt 0) { [math]::Round($handling/$routable*100,1) } else { 0 }
        $userId   = Get-ObjectPropertyValue $g[0] 'userId' ''
        [PSCustomObject]@{
            AgentId              = $userId
            AgentName            = ($userMap[$userId] ?? $userId)
            RoutableTime_hr      = [math]::Round($routable/3600000,2)
            TalkTime_hr          = [math]::Round($talk/3600000,2)
            AcwTime_hr           = [math]::Round($acw/3600000,2)
            HandlingTime_hr      = [math]::Round($handling/3600000,2)
            NotRespondingTime_hr = [math]::Round($notResp/3600000,2)
            NotRespondingCount   = $notRespN
            Occupancy_Pct        = $occ
            OccupancyFlag        = if ($occ -gt $OccupancyWarningPct) {'HIGH'} elseif ($occ -lt 50) {'LOW'} else {'OK'}
        }
    } | Sort-Object Occupancy_Pct -Descending

# ── 9e  IVR containment by flow ───────────────────────────────────────────────
$ivrContainSummary = $flowContainRows |
    Where-Object { $_.Metric -in @('nFlowEntries','nFlowDisconnect','nFlow') } |
    Group-Object flowId, flowType |
    ForEach-Object {
        $g        = $_.Group
        $entries  = Get-MetricSum $g 'nFlowEntries'
        $disconn  = Get-MetricSum $g 'nFlowDisconnect'
        $total    = Get-MetricSum $g 'nFlow'
        $base     = if ($entries -gt 0) { $entries } else { $total }
        $rate     = if ($base -gt 0) { [math]::Round($disconn/$base*100,1) } else { 0 }
        $exits    = ($g | Where-Object { Get-ObjectPropertyValue $_ 'exitReason' '' } |
                     Group-Object exitReason |
                     ForEach-Object { "$($_.Name):$($_.Count)" }) -join ' | '
        [PSCustomObject]@{
            FlowId          = Get-ObjectPropertyValue $g[0] 'flowId' ''
            FlowType        = Get-ObjectPropertyValue $g[0] 'flowType' ''
            TotalEntries    = $base
            Contained       = $disconn
            ContainRate_Pct = $rate
            TopExitReasons  = $exits
        }
    } | Sort-Object ContainRate_Pct

# ── 9f  Bot containment summary ───────────────────────────────────────────────
$botSummary = @()
if ($botRows.Count -gt 0) {
    $botSummary = $botRows |
        Where-Object { $_.Metric -in @('nBotSessions','nBotEscalated',
                                        'nBotIntentMatched','nBotIntentNotMatched') } |
        Group-Object botId |
        ForEach-Object {
            $g        = $_.Group
            $sessions = Get-MetricSum $g 'nBotSessions'
            $esc      = Get-MetricSum $g 'nBotEscalated'
            $matched  = Get-MetricSum $g 'nBotIntentMatched'
            $noMatch  = Get-MetricSum $g 'nBotIntentNotMatched'
            [PSCustomObject]@{
                BotId               = Get-ObjectPropertyValue $g[0] 'botId' ''
                BotVersion          = Get-ObjectPropertyValue $g[0] 'botVersion' ''
                TotalSessions       = $sessions
                Escalated           = $esc
                ContainRate_Pct     = [math]::Round($(if($sessions -gt 0){($sessions-$esc)/$sessions*100}else{0}),1)
                IntentMatchRate_Pct = [math]::Round($(if(($matched+$noMatch) -gt 0){$matched/($matched+$noMatch)*100}else{0}),1)
                IntentNotMatched    = $noMatch
            }
        } | Sort-Object ContainRate_Pct
}

# ── 9g  Wrap-up distribution ──────────────────────────────────────────────────
$wrapSummary = $convWrapRows |
    Group-Object wrapUpCode, QueueName |
    ForEach-Object {
        $g = $_.Group
        [PSCustomObject]@{
            WrapUpCode   = Get-ObjectPropertyValue $g[0] 'wrapUpCode' ''
            QueueName    = Get-ObjectPropertyValue $g[0] 'QueueName' ''
            MediaType    = Get-ObjectPropertyValue $g[0] 'mediaType' ''
            TotalWrapped = Get-MetricSum $g 'nWrappedPhase'
        }
    } | Sort-Object TotalWrapped -Descending

# ── 9h  Transfer rate by queue ────────────────────────────────────────────────
$transferSummary = $convXferRows |
    Where-Object { $_.Metric -in @('nTransferred','nBlindTransferred',
                                    'nConsultTransferred','nAnswered') } |
    Group-Object queueId, mediaType |
    ForEach-Object {
        $g       = $_.Group
        $xfer    = Get-MetricSum $g 'nTransferred'
        $blind   = Get-MetricSum $g 'nBlindTransferred'
        $consult = Get-MetricSum $g 'nConsultTransferred'
        $ans     = Get-MetricSum $g 'nAnswered'
        $queueId = Get-ObjectPropertyValue $g[0] 'queueId' ''
        [PSCustomObject]@{
            QueueName        = ($queueMap[$queueId] ?? $queueId)
            MediaType        = Get-ObjectPropertyValue $g[0] 'mediaType' ''
            TotalAnswered    = $ans
            TotalTransferred = $xfer
            BlindTransfers   = $blind
            ConsultTransfers = $consult
            TransferRate_Pct = [math]::Round($(if($ans -gt 0){$xfer/$ans*100}else{0}),1)
        }
    } | Sort-Object TransferRate_Pct -Descending

# ── 9i  Data action health ─────────────────────────────────────────────────────
$actionHealthSummary = $actionsRows |
    Where-Object { $_.Metric -in @('nAction','nActionSuccess','nActionFailed') } |
    Group-Object actionId, actionType |
    ForEach-Object {
        $g       = $_.Group
        $total   = Get-MetricSum $g 'nAction'
        $success = Get-MetricSum $g 'nActionSuccess'
        $failed  = Get-MetricSum $g 'nActionFailed'
        [PSCustomObject]@{
            ActionId         = Get-ObjectPropertyValue $g[0] 'actionId' ''
            ActionType       = Get-ObjectPropertyValue $g[0] 'actionType' ''
            TotalInvocations = $total
            Successes        = $success
            Failures         = $failed
            ErrorRate_Pct    = [math]::Round($(if($total -gt 0){$failed/$total*100}else{0}),1)
            Flag_HighError   = ($total -gt 0 -and ($failed/$total) -gt 0.05)
        }
    } | Sort-Object ErrorRate_Pct -Descending

# ── 9j  Channel mix ───────────────────────────────────────────────────────────
$channelMixSummary = $convVolumeRows |
    Where-Object Metric -eq 'nOffered' |
    Group-Object mediaType |
    ForEach-Object {
        [PSCustomObject]@{
            MediaType    = Get-ObjectPropertyValue $_.Group[0] 'mediaType' ''
            TotalOffered = ($_.Group | Measure-Object Count -Sum).Sum
        }
    } | Sort-Object TotalOffered -Descending

$allChannelTotal = ($channelMixSummary | Measure-Object TotalOffered -Sum).Sum
$channelMixSummary | ForEach-Object {
    $_ | Add-Member -NotePropertyName 'ChannelShare_Pct' `
        -NotePropertyValue ([math]::Round($(if($allChannelTotal -gt 0){$_.TotalOffered/$allChannelTotal*100}else{0}),1)) -Force
}

# ── 9k  API top endpoints ─────────────────────────────────────────────────────
$apiTopEndpoints = $usageApiRows |
    Group-Object TemplateUri, HttpMethod |
    ForEach-Object {
        [PSCustomObject]@{
            TemplateUri = Get-ObjectPropertyValue $_.Group[0] 'TemplateUri' '(unknown)'
            HttpMethod  = Get-ObjectPropertyValue $_.Group[0] 'HttpMethod' ''
            TotalCalls  = ($_.Group | Measure-Object Count -Sum).Sum
        }
    } | Sort-Object TotalCalls -Descending | Select-Object -First 50

# ── 9l  Seat utilisation daily ────────────────────────────────────────────────
$activeDailyAgents = $userAggRows |
    Where-Object { $_.Metric -eq 'tAgentRoutable' -and $_.Sum -gt 0 } |
    Group-Object Interval |
    ForEach-Object {
        $uniqueCount = ($_.Group | Select-Object -ExpandProperty userId -Unique).Count
        [PSCustomObject]@{
            Date            = Get-IntervalStartText $_.Group[0]
            ActiveAgents    = $uniqueCount
            LicensedSeats   = $totalLicensedSeats
            Utilisation_Pct = [math]::Round($(if($totalLicensedSeats -gt 0){$uniqueCount/$totalLicensedSeats*100}else{0}),1)
        }
    } | Sort-Object Date

$peakDayAgents = ($activeDailyAgents | Measure-Object ActiveAgents -Maximum).Maximum ?? 0
$avgDayAgents  = [math]::Round(($activeDailyAgents | Measure-Object ActiveAgents -Average).Average ?? 0, 0)
$seatUtil_Pct  = [math]::Round($(if($totalLicensedSeats -gt 0){$peakDayAgents/$totalLicensedSeats*100}else{0}),1)

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 10 — DASHBOARD KPI TABLE
#══════════════════════════════════════════════════════════════════════════════

$totalOffered   = Get-MetricSum $convVolumeRows 'nOffered'
$totalAnswered  = Get-MetricSum $convVolumeRows 'nAnswered'
$totalAbandoned = Get-MetricSum $convVolumeRows 'nAbandonedPhase'
$totalXferred   = Get-MetricSum $convVolumeRows 'nTransferred'
$totalFlows     = Get-MetricSum $flowContainRows 'nFlow'
$totalApiCalls  = ($usageApiRows | Measure-Object Count -Sum).Sum

$monthlyInboundVolume = ($monthlyReportingTotals | Where-Object OriginatingDirection -eq 'inbound' | Measure-Object Volume -Sum).Sum ?? 0
$monthlyOutboundVolume = ($monthlyReportingTotals | Where-Object OriginatingDirection -eq 'outbound' | Measure-Object Volume -Sum).Sum ?? 0
$monthlyMessageVolume = ($monthlyReportingTotals | Where-Object MediaType -eq 'message' | Measure-Object Volume -Sum).Sum ?? 0
$peakVoiceInboundRow = $voicePeakConcurrentSummary | Where-Object OriginatingDirection -eq 'inbound' | Select-Object -First 1
$peakVoiceOutboundRow = $voicePeakConcurrentSummary | Where-Object OriginatingDirection -eq 'outbound' | Select-Object -First 1
$peakVoiceInbound = Get-ObjectPropertyValue $peakVoiceInboundRow 'PeakConcurrentVoice' 0
$peakVoiceOutbound = Get-ObjectPropertyValue $peakVoiceOutboundRow 'PeakConcurrentVoice' 0

$answerRate    = [math]::Round($(if($totalOffered  -gt 0){$totalAnswered/$totalOffered*100}   else{0}),1)
$abandonRate   = [math]::Round($(if($totalOffered  -gt 0){$totalAbandoned/$totalOffered*100}  else{0}),1)
$transferRate  = [math]::Round($(if($totalAnswered -gt 0){$totalXferred/$totalAnswered*100}   else{0}),1)
$tHandle_sum   = Get-MetricSum $convVolumeRows 'tHandle' 'Sum'
$avgHandle_s   = [math]::Round($(if($totalAnswered -gt 0){$tHandle_sum/$totalAnswered/1000}else{0}),1)

$totalHandling = (Get-MetricSum $userAggRows 'tTalk' 'Sum') + (Get-MetricSum $userAggRows 'tAcw' 'Sum')
$totalRoutable = Get-MetricSum $userAggRows 'tAgentRoutable' 'Sum'
$avgOcc_Pct    = [math]::Round($(if($totalRoutable -gt 0){$totalHandling/$totalRoutable*100}else{0}),1)

$totalBotSess  = Get-MetricSum $botRows 'nBotSessions'
$totalBotEsc   = Get-MetricSum $botRows 'nBotEscalated'
$botContain    = [math]::Round($(if($totalBotSess -gt 0){($totalBotSess-$totalBotEsc)/$totalBotSess*100}else{0}),1)

$ivrContain    = if ($ivrContainSummary.Count -gt 0) {
    $e = ($ivrContainSummary | Measure-Object TotalEntries -Sum).Sum
    $c = ($ivrContainSummary | Measure-Object Contained    -Sum).Sum
    [math]::Round($(if($e -gt 0){$c/$e*100}else{0}),1)
} else { 0 }

$queuesBelowSL  = ($queueSLSummary    | Where-Object BelowTarget).Count
$agentsHighOcc  = ($agentOccupancySummary | Where-Object OccupancyFlag -eq 'HIGH').Count
$actionsInError = ($actionHealthSummary   | Where-Object Flag_HighError).Count

$kpiTable = @(
    [PSCustomObject]@{ Category='Volume';      KPI='Month';                       Value=$monthLabel;       Unit='';              Note='' }
    [PSCustomObject]@{ Category='Volume';      KPI='Total Offered';               Value=$totalOffered;     Unit='conversations'; Note='' }
    [PSCustomObject]@{ Category='Volume';      KPI='Total Answered';              Value=$totalAnswered;    Unit='conversations'; Note='' }
    [PSCustomObject]@{ Category='Volume';      KPI='Total Abandoned';             Value=$totalAbandoned;   Unit='conversations'; Note='' }
    [PSCustomObject]@{ Category='Volume';      KPI='Total Transferred';           Value=$totalXferred;     Unit='conversations'; Note='' }
    [PSCustomObject]@{ Category='Reporting';   KPI='Inbound Monthly Volume';      Value=$monthlyInboundVolume;  Unit='normalized volume'; Note='from Monthly_Totals' }
    [PSCustomObject]@{ Category='Reporting';   KPI='Outbound Monthly Volume';     Value=$monthlyOutboundVolume; Unit='normalized volume'; Note='from Monthly_Totals' }
    [PSCustomObject]@{ Category='Reporting';   KPI='Message Monthly Volume';      Value=$monthlyMessageVolume;  Unit='normalized volume'; Note='mediaType=message' }
    [PSCustomObject]@{ Category='Reporting';   KPI='Peak Concurrent Voice Inbound';  Value=$peakVoiceInbound;  Unit='conversations'; Note=$ConcurrencyGranularity }
    [PSCustomObject]@{ Category='Reporting';   KPI='Peak Concurrent Voice Outbound'; Value=$peakVoiceOutbound; Unit='conversations'; Note=$ConcurrencyGranularity }
    [PSCustomObject]@{ Category='Quality';     KPI='Answer Rate';                 Value=$answerRate;       Unit='%';             Note='' }
    [PSCustomObject]@{ Category='Quality';     KPI='Abandon Rate';                Value=$abandonRate;      Unit='%';             Note='Target <5%' }
    [PSCustomObject]@{ Category='Quality';     KPI='Transfer Rate';               Value=$transferRate;     Unit='%';             Note='' }
    [PSCustomObject]@{ Category='Quality';     KPI='Avg Handle Time';             Value=$avgHandle_s;      Unit='seconds';       Note='' }
    [PSCustomObject]@{ Category='Quality';     KPI='Queues Below SL Target';      Value=$queuesBelowSL;    Unit='queues';        Note="Target: 80% in ${ServiceLevelThresholdSec}s" }
    [PSCustomObject]@{ Category='Efficiency';  KPI='Avg Agent Occupancy';         Value=$avgOcc_Pct;       Unit='%';             Note="Warn >$OccupancyWarningPct%" }
    [PSCustomObject]@{ Category='Efficiency';  KPI='Agents Flagged HIGH Occ';     Value=$agentsHighOcc;    Unit='agents';        Note='' }
    [PSCustomObject]@{ Category='Efficiency';  KPI='Seat Utilisation (Peak Day)'; Value=$seatUtil_Pct;     Unit='%';             Note="$peakDayAgents of $totalLicensedSeats seats" }
    [PSCustomObject]@{ Category='Efficiency';  KPI='Avg Daily Active Agents';     Value=$avgDayAgents;     Unit='agents';        Note='' }
    [PSCustomObject]@{ Category='Self-Service';KPI='IVR Containment Rate';        Value=$ivrContain;       Unit='%';             Note='' }
    [PSCustomObject]@{ Category='Self-Service';KPI='Bot Containment Rate';        Value=$botContain;       Unit='%';             Note='' }
    [PSCustomObject]@{ Category='Self-Service';KPI='Total Flow Executions';       Value=$totalFlows;       Unit='flows';         Note='' }
    [PSCustomObject]@{ Category='Self-Service';KPI='Total Bot Sessions';          Value=$totalBotSess;     Unit='sessions';      Note='' }
    [PSCustomObject]@{ Category='Platform';    KPI='Data Actions >5% Error Rate'; Value=$actionsInError;   Unit='actions';       Note='' }
    [PSCustomObject]@{ Category='Platform';    KPI='Total API Calls';             Value=$totalApiCalls;    Unit='requests';      Note='' }
    [PSCustomObject]@{ Category='Platform';    KPI='Licensed Seats';              Value=$totalLicensedSeats; Unit='users';       Note='' }
)

#endregion

#region ══════════════════════════════════════════════════════════════════════
#  SECTION 11 — WRITE EXCEL WORKBOOK
#══════════════════════════════════════════════════════════════════════════════

$fileName   = "GenesysMetrics_${monthLabel}.xlsx"
$outputFile = Join-Path (Resolve-Path $OutputPath) $fileName
if (Test-Path $outputFile) { Remove-Item $outputFile -Force }
Write-Log "Writing workbook: $outputFile ..."

$headerStyle = New-ExcelStyle `
    -BackgroundColor ([System.Drawing.Color]::FromArgb(31,73,125)) `
    -FontColor White -Bold -HorizontalAlignment Center

# Helper: write a sheet + optional chart, return nothing (keeps main flow clean)
function Write-Sheet {
    param(
        $Data, [string]$Sheet, [string]$Table, [string]$TableStyle = 'Medium2',
        $ChartDef = $null
    )
    if (-not $Data -or @($Data).Count -eq 0) {
        Write-Log "  Skipping empty sheet: $Sheet" 'WARN'; return
    }
    if ($ChartDef) {
        $pkg = $Data | Export-Excel -Path $outputFile -WorksheetName $Sheet `
            -TableName $Table -TableStyle $TableStyle `
            -Style $headerStyle -AutoSize -FreezeTopRow -AutoFilter -PassThru
        Export-Excel -ExcelPackage $pkg -WorksheetName $Sheet `
            -ExcelChartDefinition $ChartDef -Show:$false
    } else {
        $Data | Export-Excel -Path $outputFile -WorksheetName $Sheet `
            -TableName $Table -TableStyle $TableStyle `
            -Style $headerStyle -AutoSize -FreezeTopRow -AutoFilter -Append
    }
    Write-Log "  Sheet: $Sheet  ($(@($Data).Count) rows)" 'OK'
}

# ── TAB 1 : Dashboard ─────────────────────────────────────────────────────────
Write-Sheet -Data $kpiTable -Sheet 'Dashboard' -Table 'tbl_KPIs' -TableStyle 'Medium2'

# ── TAB 2 : Monthly Reporting Totals ─────────────────────────────────────────
Write-Sheet -Data $monthlyReportingTotals -Sheet 'Monthly_Totals' -Table 'tbl_MonthlyTotals' -TableStyle 'Medium4'

# ── TAB 3 : Peak Concurrent Voice ────────────────────────────────────────────
Write-Sheet -Data $voicePeakConcurrentSummary -Sheet 'Voice_PeakConcurrent' -Table 'tbl_VoicePeakConcurrent' -TableStyle 'Medium9'

# ── TAB 4 : Conversation Daily Summary ───────────────────────────────────────
if ($convDailySummary.Count -gt 0) {
    $n = $convDailySummary.Count + 1
    Write-Sheet -Data $convDailySummary -Sheet 'Conv_DailySummary' -Table 'tbl_ConvDaily' `
        -TableStyle 'Medium6' `
        -ChartDef (New-ExcelChartDefinition `
            -ChartType LineMarkers -Title "Daily Volume by Channel — $monthLabel" `
            -SeriesHeader 'Offered','Answered','Abandoned' `
            -XRange "Conv_DailySummary!A2:A$n" `
            -YRange "Conv_DailySummary!C2:C$n",
                    "Conv_DailySummary!D2:D$n",
                    "Conv_DailySummary!E2:E$n" `
            -Column 13 -Row 2 -Width 640 -Height 320)
}

# ── TAB 3 : Abandon Segmentation ─────────────────────────────────────────────
Write-Sheet -Data $abandonSummary -Sheet 'Conv_AbandonDetail' -Table 'tbl_Abandon' -TableStyle 'Medium9'

# ── TAB 4 : Queue Service Level ───────────────────────────────────────────────
if ($queueSLSummary.Count -gt 0) {
    $n = $queueSLSummary.Count + 1
    Write-Sheet -Data $queueSLSummary -Sheet 'Queue_ServiceLevel' -Table 'tbl_QueueSL' `
        -ChartDef (New-ExcelChartDefinition `
            -ChartType BarClustered -Title "Service Level % by Queue — $monthLabel" `
            -XRange "Queue_ServiceLevel!B2:B$n" -YRange "Queue_ServiceLevel!J2:J$n" `
            -SeriesHeader 'SL %' -Column 13 -Row 2 -Width 640 -Height 400)
}

# ── TAB 5 : Transfer Analysis ─────────────────────────────────────────────────
Write-Sheet -Data $transferSummary -Sheet 'Conv_TransferAnalysis' -Table 'tbl_Transfer' -TableStyle 'Medium4'

# ── TAB 6 : Wrap-Up Distribution ─────────────────────────────────────────────
if ($wrapSummary.Count -gt 0) {
    $n = [math]::Min(21, $wrapSummary.Count + 1)
    Write-Sheet -Data $wrapSummary -Sheet 'Conv_WrapUpCodes' -Table 'tbl_WrapUp' `
        -TableStyle 'Medium15' `
        -ChartDef (New-ExcelChartDefinition `
            -ChartType BarClustered -Title "Top Wrap-Up Codes — $monthLabel" `
            -XRange "Conv_WrapUpCodes!A2:A$n" -YRange "Conv_WrapUpCodes!D2:D$n" `
            -SeriesHeader 'Count' -Column 6 -Row 2 -Width 560 -Height 400)
}

# ── TAB 7 : Agent Occupancy ───────────────────────────────────────────────────
if ($agentOccupancySummary.Count -gt 0) {
    $n = [math]::Min(26, $agentOccupancySummary.Count + 1)
    Write-Sheet -Data $agentOccupancySummary -Sheet 'Agent_Occupancy' -Table 'tbl_Occupancy' `
        -TableStyle 'Medium6' `
        -ChartDef (New-ExcelChartDefinition `
            -ChartType BarClustered -Title "Agent Occupancy % (Top 25) — $monthLabel" `
            -XRange "Agent_Occupancy!B2:B$n" -YRange "Agent_Occupancy!I2:I$n" `
            -SeriesHeader 'Occupancy %' -Column 12 -Row 2 -Width 600 -Height 440)
}

# ── TAB 8 : Agent Status Breakdown ───────────────────────────────────────────
Write-Sheet -Data $userStatusRows -Sheet 'Agent_StatusBreakdown' -Table 'tbl_AgentStatus' -TableStyle 'Medium4'

# ── TAB 9 : Seat Utilisation ──────────────────────────────────────────────────
if ($activeDailyAgents.Count -gt 0) {
    $n = $activeDailyAgents.Count + 1
    Write-Sheet -Data $activeDailyAgents -Sheet 'Platform_SeatUtil' -Table 'tbl_SeatUtil' `
        -ChartDef (New-ExcelChartDefinition `
            -ChartType LineMarkers -Title "Daily Active Agents vs Licensed Seats — $monthLabel" `
            -SeriesHeader 'Active Agents','Licensed Seats' `
            -XRange "Platform_SeatUtil!A2:A$n" `
            -YRange "Platform_SeatUtil!B2:B$n","Platform_SeatUtil!C2:C$n" `
            -Column 6 -Row 2 -Width 580 -Height 300)
}

# ── TAB 10 : IVR Containment ──────────────────────────────────────────────────
if ($ivrContainSummary.Count -gt 0) {
    $n = $ivrContainSummary.Count + 1
    Write-Sheet -Data $ivrContainSummary -Sheet 'IVR_Containment' -Table 'tbl_IVRContain' `
        -TableStyle 'Medium9' `
        -ChartDef (New-ExcelChartDefinition `
            -ChartType BarClustered -Title "IVR Containment Rate by Flow — $monthLabel" `
            -XRange "IVR_Containment!A2:A$n" -YRange "IVR_Containment!D2:D$n" `
            -SeriesHeader 'Contain %' -Column 8 -Row 2 -Width 560 -Height 340)
}

# ── TAB 11 : Bot Containment ──────────────────────────────────────────────────
Write-Sheet -Data $botSummary -Sheet 'Bot_Containment' -Table 'tbl_BotContain' -TableStyle 'Medium15'

# ── TAB 12 : Channel Mix ──────────────────────────────────────────────────────
if ($channelMixSummary.Count -gt 0) {
    $n = $channelMixSummary.Count + 1
    Write-Sheet -Data $channelMixSummary -Sheet 'Conv_ChannelMix' -Table 'tbl_ChannelMix' `
        -ChartDef (New-ExcelChartDefinition `
            -ChartType Pie -Title "Contact Channel Distribution — $monthLabel" `
            -XRange "Conv_ChannelMix!A2:A$n" -YRange "Conv_ChannelMix!B2:B$n" `
            -SeriesHeader 'Volume' -Column 5 -Row 2 -Width 400 -Height 300)
}

# ── TAB 13 : Data Action Health ───────────────────────────────────────────────
Write-Sheet -Data $actionHealthSummary -Sheet 'Platform_ActionHealth' -Table 'tbl_ActionHealth' -TableStyle 'Medium9'

# ── TAB 14 : API Top Endpoints ────────────────────────────────────────────────
if ($apiTopEndpoints.Count -gt 0) {
    $n = [math]::Min(21, $apiTopEndpoints.Count + 1)
    Write-Sheet -Data $apiTopEndpoints -Sheet 'Platform_TopEndpoints' -Table 'tbl_TopEndpoints' `
        -ChartDef (New-ExcelChartDefinition `
            -ChartType BarClustered -Title "Top API Endpoints by Call Volume — $monthLabel" `
            -XRange "Platform_TopEndpoints!A2:A$n" -YRange "Platform_TopEndpoints!C2:C$n" `
            -SeriesHeader 'Total Calls' -Column 4 -Row 2 -Width 700 -Height 420)
}

# ── TAB 15 : Usage Events ─────────────────────────────────────────────────────
Write-Sheet -Data $usageEventRows -Sheet 'Platform_UsageEvents' -Table 'tbl_UsageEvents' -TableStyle 'Light1'

# ── TAB 16 : Flow Execution Detail  (pivot source) ───────────────────────────
Write-Sheet -Data $flowExecRows -Sheet 'Flow_ExecDetail' -Table 'tbl_FlowExec' -TableStyle 'Medium4'

# ── TAB 17 : Conversation Volume Detail  (pivot source) ──────────────────────
Write-Sheet -Data $convVolumeRows -Sheet 'Conv_VolumeDetail' -Table 'tbl_ConvVolumeDetail' -TableStyle 'Medium6'

# ── TAB 18 : Per-Client API Usage  (conditional) ─────────────────────────────
if ($clientUsageRows.Count -gt 0) {
    Write-Sheet -Data $clientUsageRows -Sheet 'Platform_ClientUsage' -Table 'tbl_ClientUsage' -TableStyle 'Medium9'
}

Write-Log "Workbook complete: $outputFile" 'OK'
#endregion

#region ── Console summary ─────────────────────────────────────────────────────
$bar = '━' * 62
Write-Host "`n$bar" -ForegroundColor Cyan
Write-Host "  GENESYS CLOUD MONTHLY REPORT — $monthLabel" -ForegroundColor White
Write-Host $bar -ForegroundColor Cyan
$kpiTable | Format-Table Category, KPI, Value, Unit, Note -AutoSize
Write-Host "  Output : $outputFile" -ForegroundColor Green
Write-Host "$bar`n" -ForegroundColor Cyan
#endregion
