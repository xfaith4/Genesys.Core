#Requires -Version 5.1
Set-StrictMode -Version Latest

# ── Gate B + Gate D boundary ──────────────────────────────────────────────────
# ONLY this module may:
#   - Import-Module Genesys.Core
#   - Call Assert-Catalog
#   - Call Invoke-Dataset
#
# Dataset keys (fixed by spec):
#   Preview : analytics-conversation-details-query
#   Full run: analytics-conversation-details
# ─────────────────────────────────────────────────────────────────────────────

$script:Initialized  = $false
$script:CoreModPath  = $null
$script:CatalogPath  = $null
$script:SchemaPath   = $null
$script:OutputRoot   = $null

function Initialize-CoreAdapter {
    <#
    .SYNOPSIS
        Gate A – imports Genesys.Core and validates the catalog.
        Must be called once at startup (and again inside every background runspace).
    #>
    param(
        [Parameter(Mandatory)][string]$CoreModulePath,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][string]$OutputRoot,
        [string]$SchemaPath = ''
    )

    if (-not [System.IO.File]::Exists($CoreModulePath)) {
        throw "Genesys.Core module not found at: $CoreModulePath"
    }
    if (-not [System.IO.File]::Exists($CatalogPath)) {
        throw "Catalog file not found at: $CatalogPath"
    }
    if ($SchemaPath -and -not [System.IO.File]::Exists($SchemaPath)) {
        throw "Schema file not found at: $SchemaPath"
    }

    Import-Module $CoreModulePath -Force -ErrorAction Stop
    $assertParams = @{ CatalogPath = $CatalogPath }
    if ($SchemaPath) { $assertParams['SchemaPath'] = $SchemaPath }
    Assert-Catalog @assertParams -ErrorAction Stop

    if (-not [System.IO.Directory]::Exists($OutputRoot)) {
        [System.IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
    }

    $script:Initialized = $true
    $script:CoreModPath = $CoreModulePath
    $script:CatalogPath = $CatalogPath
    $script:SchemaPath  = $SchemaPath
    $script:OutputRoot  = $OutputRoot
}

function Test-CoreInitialized {
    <#
    .SYNOPSIS
        Returns $true if Initialize-CoreAdapter has completed successfully in this runspace.
    #>
    return $script:Initialized
}

function _RequireInitialized {
    if (-not $script:Initialized) {
        throw 'CoreAdapter is not initialized. Call Initialize-CoreAdapter before invoking dataset operations.'
    }
}

function Start-PreviewRun {
    <#
    .SYNOPSIS
        Gate B – invokes the preview dataset (analytics-conversation-details-query).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$DatasetParameters,
        [hashtable]$Headers = $null
    )
    _RequireInitialized

    $invokeParams = @{
        Dataset           = 'analytics-conversation-details-query'
        CatalogPath       = $script:CatalogPath
        OutputRoot        = $script:OutputRoot
        DatasetParameters = $DatasetParameters
    }
    if ($null -ne $Headers) { $invokeParams['Headers'] = $Headers }

    return Invoke-Dataset @invokeParams
}

function Start-FullRun {
    <#
    .SYNOPSIS
        Gate B – invokes the full dataset (analytics-conversation-details).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$DatasetParameters,
        [hashtable]$Headers = $null
    )
    _RequireInitialized

    $invokeParams = @{
        Dataset           = 'analytics-conversation-details'
        CatalogPath       = $script:CatalogPath
        OutputRoot        = $script:OutputRoot
        DatasetParameters = $DatasetParameters
    }
    if ($null -ne $Headers) { $invokeParams['Headers'] = $Headers }

    return Invoke-Dataset @invokeParams
}

function Get-RunManifest {
    <#
    .SYNOPSIS
        Reads and parses manifest.json from a run folder.  Returns $null if absent.
    #>
    param([Parameter(Mandatory)][string]$RunFolder)
    $path = [System.IO.Path]::Combine($RunFolder, 'manifest.json')
    if (-not [System.IO.File]::Exists($path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $raw | ConvertFrom-Json
}

function Get-RunSummary {
    <#
    .SYNOPSIS
        Reads and parses summary.json from a run folder.  Returns $null if absent.
    #>
    param([Parameter(Mandatory)][string]$RunFolder)
    $path = [System.IO.Path]::Combine($RunFolder, 'summary.json')
    if (-not [System.IO.File]::Exists($path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $raw | ConvertFrom-Json
}

function Get-RunEvents {
    <#
    .SYNOPSIS
        Returns the last N events from events.jsonl using FileStream + StreamReader
        (supports in-progress/shared-write files via FileShare.ReadWrite).
    #>
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [int]$LastN = 50
    )
    $path = [System.IO.Path]::Combine($RunFolder, 'events.jsonl')
    if (-not [System.IO.File]::Exists($path)) { return @() }

    $allEvents = New-Object System.Collections.Generic.List[object]
    $fs = [System.IO.FileStream]::new(
        $path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
    try {
        while (-not $sr.EndOfStream) {
            $line = $sr.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $allEvents.Add(($line | ConvertFrom-Json))
            } catch { <# skip malformed event lines #> }
        }
    } finally {
        $sr.Dispose()
        $fs.Dispose()
    }

    if ($allEvents.Count -le $LastN) { return $allEvents.ToArray() }
    return $allEvents.GetRange($allEvents.Count - $LastN, $LastN).ToArray()
}

function Get-RunStatus {
    <#
    .SYNOPSIS
        Returns the 'status' string from manifest.json, or 'Unknown'.
    #>
    param([Parameter(Mandatory)][string]$RunFolder)
    $manifest = Get-RunManifest -RunFolder $RunFolder
    if ($null -eq $manifest) { return 'Unknown' }
    if ($manifest.PSObject.Properties['status']) { return $manifest.status }
    return 'Unknown'
}

function Get-RecentRunFolders {
    <#
    .SYNOPSIS
        Returns up to $Max run folders under $OutputRoot, sorted newest first.
        A folder qualifies if it contains manifest.json.
    #>
    param(
        [Parameter(Mandatory)][string]$OutputRoot,
        [int]$Max = 20
    )
    if (-not [System.IO.Directory]::Exists($OutputRoot)) { return @() }

    # Invoke-Dataset writes to OutputRoot\DatasetKey\RunId\ (2 levels deep).
    # Also support flat OutputRoot\RunId\ layout for backwards compatibility.
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($child in [System.IO.Directory]::GetDirectories($OutputRoot)) {
        if ([System.IO.File]::Exists([System.IO.Path]::Combine($child, 'manifest.json'))) {
            $candidates.Add($child)
        } else {
            foreach ($grandchild in [System.IO.Directory]::GetDirectories($child)) {
                if ([System.IO.File]::Exists([System.IO.Path]::Combine($grandchild, 'manifest.json'))) {
                    $candidates.Add($grandchild)
                }
            }
        }
    }

    # Wrap in @() so an empty or single-item result is always an array,
    # not $null (PS 5.1 Sort-Object returns $null for empty input).
    $dirs = @($candidates.ToArray() |
              Sort-Object { [System.IO.Directory]::GetCreationTimeUtc($_) } -Descending)

    if ($dirs.Count -le $Max) { return $dirs }
    return $dirs[0..($Max - 1)]
}

function Get-DiagnosticsText {
    <#
    .SYNOPSIS
        Assembles a diagnostics dump string for a run folder (manifest + summary + last 10 events).
    #>
    param([Parameter(Mandatory)][string]$RunFolder)

    $sb       = New-Object System.Text.StringBuilder
    $manifest = Get-RunManifest -RunFolder $RunFolder
    $summary  = Get-RunSummary  -RunFolder $RunFolder

    [void]$sb.AppendLine('=== Genesys Conversation Analysis – Run Diagnostics ===')
    [void]$sb.AppendLine("Folder    : $RunFolder")
    [void]$sb.AppendLine("Timestamp : $([datetime]::UtcNow.ToString('o'))")

    if ($null -ne $manifest) {
        [void]$sb.AppendLine("Manifest  : $($manifest | ConvertTo-Json -Compress -Depth 5)")
    } else {
        [void]$sb.AppendLine('Manifest  : (not found)')
    }

    if ($null -ne $summary) {
        [void]$sb.AppendLine("Summary   : $($summary | ConvertTo-Json -Compress -Depth 5)")
    } else {
        [void]$sb.AppendLine('Summary   : (not found)')
    }

    [void]$sb.AppendLine('--- Last 10 Events ---')
    $events = Get-RunEvents -RunFolder $RunFolder -LastN 10
    if ($events.Count -eq 0) {
        [void]$sb.AppendLine('  (no events)')
    } else {
        foreach ($e in $events) {
            [void]$sb.AppendLine("  $($e | ConvertTo-Json -Compress)")
        }
    }

    return $sb.ToString()
}

function Refresh-ReferenceData {
    <#
    .SYNOPSIS
        Gate B – pulls all reference datasets and writes them to a dated run folder.
    .DESCRIPTION
        Invokes Invoke-Dataset for each reference dataset in dependency order and
        writes the results under OutputRoot\ref-<timestamp>\.  Returns a hashtable
        keyed by dataset key, each value being the run folder path for that dataset.

        Reference datasets fetched (in order):
            routing-queues
            users
            authorization.get.all.divisions
            routing.get.all.wrapup.codes
            routing.get.all.routing.skills
            routing.get.all.languages
            flows.get.all.flows
            flows.get.flow.outcomes
            flows.get.flow.milestones

        The caller is responsible for passing the returned folder map to
        Import-ReferenceDataToCase in App.Database.psm1.
    .PARAMETER Headers
        Auth headers hashtable.  Optional — uses the last-stored headers if omitted.
    #>
    param(
        [hashtable]$Headers = $null
    )
    _RequireInitialized

    $stamp    = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $refRoot  = [System.IO.Path]::Combine($script:OutputRoot, "ref-$stamp")
    [System.IO.Directory]::CreateDirectory($refRoot) | Out-Null

    $datasetKeys = @(
        'routing-queues',
        'users',
        'authorization.get.all.divisions',
        'routing.get.all.wrapup.codes',
        'routing.get.all.routing.skills',
        'routing.get.all.languages',
        'flows.get.all.flows',
        'flows.get.flow.outcomes',
        'flows.get.flow.milestones'
    )

    $folderMap = @{}

    foreach ($key in $datasetKeys) {
        $dsRoot = [System.IO.Path]::Combine($refRoot, $key)
        [System.IO.Directory]::CreateDirectory($dsRoot) | Out-Null

        $invokeParams = @{
            Dataset     = $key
            CatalogPath = $script:CatalogPath
            OutputRoot  = $dsRoot
        }
        if ($script:SchemaPath) { $invokeParams['SchemaPath'] = $script:SchemaPath }
        if ($null -ne $Headers) { $invokeParams['Headers']    = $Headers }

        try {
            Invoke-Dataset @invokeParams | Out-Null
        } catch {
            Write-Warning "Refresh-ReferenceData: dataset '$key' failed — $($_.Exception.Message)"
        }

        # Locate the run folder (OutputRoot\DatasetKey\RunId\)
        $runFolder = $null
        foreach ($child in [System.IO.Directory]::GetDirectories($dsRoot)) {
            foreach ($grandchild in [System.IO.Directory]::GetDirectories($child)) {
                if ([System.IO.File]::Exists([System.IO.Path]::Combine($grandchild, 'manifest.json'))) {
                    $runFolder = $grandchild
                    break
                }
            }
            if ($runFolder) { break }
        }

        $folderMap[$key] = $runFolder
    }

    return $folderMap
}

function Get-QueuePerformanceReport {
    <#
    .SYNOPSIS
        Session 14 — pulls three queue-performance aggregate datasets and returns
        their run folder paths for import into the case store.
    .DESCRIPTION
        Calls Invoke-Dataset for:
          - analytics.query.conversation.aggregates.queue.performance
          - analytics.query.conversation.aggregates.abandon.metrics
          - analytics.query.queue.aggregates.service.level

        All three calls use the same StartDateTime / EndDateTime window so the
        data aligns on interval boundaries.  Results are written under
        OutputRoot\report-queue-perf-<timestamp>\.

        Returns a hashtable with keys:
          QueuePerfFolder     — run folder for the queue-performance dataset
          AbandonFolder       — run folder for the abandon-metrics dataset
          ServiceLevelFolder  — run folder for the service-level dataset
    .PARAMETER StartDateTime
        UTC ISO-8601 start of the report interval (e.g. "2026-03-01T00:00:00.000Z").
    .PARAMETER EndDateTime
        UTC ISO-8601 end of the report interval   (e.g. "2026-03-31T23:59:59.999Z").
    .PARAMETER Headers
        Auth headers hashtable.  Optional — uses the last-stored headers if omitted.
    #>
    param(
        [Parameter(Mandatory)][string] $StartDateTime,
        [Parameter(Mandatory)][string] $EndDateTime,
        [hashtable] $Headers = $null
    )
    _RequireInitialized

    $stamp   = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $repRoot = [System.IO.Path]::Combine($script:OutputRoot, "report-queue-perf-$stamp")
    [System.IO.Directory]::CreateDirectory($repRoot) | Out-Null

    # Shared DatasetParameters body override — supply interval so all three
    # queries share the same window.
    $interval = "$StartDateTime/$EndDateTime"

    $datasetKeys = @(
        'analytics.query.conversation.aggregates.queue.performance',
        'analytics.query.conversation.aggregates.abandon.metrics',
        'analytics.query.queue.aggregates.service.level'
    )

    $folderMap = @{}

    foreach ($key in $datasetKeys) {
        $dsRoot = [System.IO.Path]::Combine($repRoot, $key)
        [System.IO.Directory]::CreateDirectory($dsRoot) | Out-Null

        $invokeParams = @{
            Dataset            = $key
            CatalogPath        = $script:CatalogPath
            OutputRoot         = $dsRoot
            DatasetParameters  = @{ Interval = $interval }
        }
        if ($script:SchemaPath) { $invokeParams['SchemaPath'] = $script:SchemaPath }
        if ($null -ne $Headers) { $invokeParams['Headers']    = $Headers }

        try {
            Invoke-Dataset @invokeParams | Out-Null
        } catch {
            Write-Warning "Get-QueuePerformanceReport: dataset '$key' failed — $($_.Exception.Message)"
        }

        # Locate the run folder (OutputRoot\DatasetKey\RunId\)
        $runFolder = $null
        foreach ($child in [System.IO.Directory]::GetDirectories($dsRoot)) {
            foreach ($grandchild in [System.IO.Directory]::GetDirectories($child)) {
                if ([System.IO.File]::Exists([System.IO.Path]::Combine($grandchild, 'manifest.json'))) {
                    $runFolder = $grandchild
                    break
                }
            }
            if ($runFolder) { break }
        }
        $folderMap[$key] = $runFolder
    }

    return @{
        QueuePerfFolder    = $folderMap['analytics.query.conversation.aggregates.queue.performance']
        AbandonFolder      = $folderMap['analytics.query.conversation.aggregates.abandon.metrics']
        ServiceLevelFolder = $folderMap['analytics.query.queue.aggregates.service.level']
        PartialFailure     = ($folderMap.Values | Where-Object { $null -eq $_ }).Count -gt 0
    }
}

function Get-AgentPerformanceReport {
    <#
    .SYNOPSIS
        Session 15 — pulls three agent-performance aggregate datasets and returns
        their run folder paths for import into the case store.
    .DESCRIPTION
        Calls Invoke-Dataset for:
          - analytics.query.conversation.aggregates.agent.performance
          - analytics.query.user.aggregates.performance.metrics
          - analytics.query.user.aggregates.login.activity

        All three calls use the same StartDateTime / EndDateTime window so the
        data aligns on interval boundaries.  Results are written under
        OutputRoot\report-agent-perf-<timestamp>\.

        Returns a hashtable with keys:
          AgentPerfFolder  — run folder for the agent-performance dataset
          UserPerfFolder   — run folder for the user-performance-metrics dataset
          LoginFolder      — run folder for the login-activity dataset
          PartialFailure   — $true if any dataset folder is null
    .PARAMETER StartDateTime
        UTC ISO-8601 start of the report interval (e.g. "2026-03-01T00:00:00.000Z").
    .PARAMETER EndDateTime
        UTC ISO-8601 end of the report interval   (e.g. "2026-03-31T23:59:59.999Z").
    .PARAMETER Headers
        Auth headers hashtable.  Optional — uses the last-stored headers if omitted.
    #>
    param(
        [Parameter(Mandatory)][string] $StartDateTime,
        [Parameter(Mandatory)][string] $EndDateTime,
        [hashtable] $Headers = $null
    )
    _RequireInitialized

    $stamp   = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $repRoot = [System.IO.Path]::Combine($script:OutputRoot, "report-agent-perf-$stamp")
    [System.IO.Directory]::CreateDirectory($repRoot) | Out-Null

    $interval = "$StartDateTime/$EndDateTime"

    $datasetKeys = @(
        'analytics.query.conversation.aggregates.agent.performance',
        'analytics.query.user.aggregates.performance.metrics',
        'analytics.query.user.aggregates.login.activity'
    )

    $folderMap = @{}

    foreach ($key in $datasetKeys) {
        $dsRoot = [System.IO.Path]::Combine($repRoot, $key)
        [System.IO.Directory]::CreateDirectory($dsRoot) | Out-Null

        $invokeParams = @{
            Dataset            = $key
            CatalogPath        = $script:CatalogPath
            OutputRoot         = $dsRoot
            DatasetParameters  = @{ Interval = $interval }
        }
        if ($script:SchemaPath) { $invokeParams['SchemaPath'] = $script:SchemaPath }
        if ($null -ne $Headers) { $invokeParams['Headers']    = $Headers }

        try {
            Invoke-Dataset @invokeParams | Out-Null
        } catch {
            Write-Warning "Get-AgentPerformanceReport: dataset '$key' failed — $($_.Exception.Message)"
        }

        $runFolder = $null
        foreach ($child in [System.IO.Directory]::GetDirectories($dsRoot)) {
            foreach ($grandchild in [System.IO.Directory]::GetDirectories($child)) {
                if ([System.IO.File]::Exists([System.IO.Path]::Combine($grandchild, 'manifest.json'))) {
                    $runFolder = $grandchild
                    break
                }
            }
            if ($runFolder) { break }
        }
        $folderMap[$key] = $runFolder
    }

    return @{
        AgentPerfFolder = $folderMap['analytics.query.conversation.aggregates.agent.performance']
        UserPerfFolder  = $folderMap['analytics.query.user.aggregates.performance.metrics']
        LoginFolder     = $folderMap['analytics.query.user.aggregates.login.activity']
        PartialFailure  = ($folderMap.Values | Where-Object { $null -eq $_ }).Count -gt 0
    }
}

Export-ModuleMember -Function `
    Initialize-CoreAdapter, Test-CoreInitialized, `
    Start-PreviewRun, Start-FullRun, `
    Get-RunManifest, Get-RunSummary, Get-RunEvents, Get-RunStatus, `
    Get-RecentRunFolders, Get-DiagnosticsText, `
    Refresh-ReferenceData, Get-QueuePerformanceReport, Get-AgentPerformanceReport
