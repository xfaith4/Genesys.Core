#Requires -Version 5.1
Set-StrictMode -Version Latest

# ── App.UI.ps1 ────────────────────────────────────────────────────────────────
# Dot-sourced by App.ps1 after XAML is loaded.
# All WPF control references are resolved here from $script:Window.
# ─────────────────────────────────────────────────────────────────────────────

# ── Control map ──────────────────────────────────────────────────────────────

function _Ctrl { param([string]$Name) $script:Window.FindName($Name) }

# Header
$script:TabWorkspace           = _Ctrl 'TabWorkspace'
$script:TabDrilldownWorkspace  = _Ctrl 'TabDrilldownWorkspace'
$script:ElpConnStatus          = _Ctrl 'ElpConnStatus'
$script:LblConnectionStatus    = _Ctrl 'LblConnectionStatus'
$script:BtnConnect             = _Ctrl 'BtnConnect'
$script:BtnSettings            = _Ctrl 'BtnSettings'

# Left panel
$script:DtpStartDate           = _Ctrl 'DtpStartDate'
$script:TxtStartTime           = _Ctrl 'TxtStartTime'
$script:DtpEndDate             = _Ctrl 'DtpEndDate'
$script:TxtEndTime             = _Ctrl 'TxtEndTime'
$script:CmbDirection           = _Ctrl 'CmbDirection'
$script:CmbMediaType           = _Ctrl 'CmbMediaType'
$script:TxtQueue               = _Ctrl 'TxtQueue'
$script:TxtConversationId      = _Ctrl 'TxtConversationId'
$script:TxtFilterUserId        = _Ctrl 'TxtFilterUserId'
$script:TxtFilterDivisionId    = _Ctrl 'TxtFilterDivisionId'
$script:ChkExternalTagExists   = _Ctrl 'ChkExternalTagExists'
$script:TxtFlowName            = _Ctrl 'TxtFlowName'
$script:CmbMessageType         = _Ctrl 'CmbMessageType'
$script:TxtPreviewPageSize     = _Ctrl 'TxtPreviewPageSize'
$script:BtnPreviewRun          = _Ctrl 'BtnPreviewRun'
$script:BtnRun                 = _Ctrl 'BtnRun'
$script:BtnCancelRun           = _Ctrl 'BtnCancelRun'
$script:TxtRunStatus           = _Ctrl 'TxtRunStatus'
$script:PrgRun                 = _Ctrl 'PrgRun'
$script:TxtRunProgress         = _Ctrl 'TxtRunProgress'
$script:LstRecentRuns          = _Ctrl 'LstRecentRuns'
$script:BtnOpenRun             = _Ctrl 'BtnOpenRun'
$script:LblActiveCase          = _Ctrl 'LblActiveCase'
$script:BtnManageCase          = _Ctrl 'BtnManageCase'
$script:BtnImportRun           = _Ctrl 'BtnImportRun'
$script:BtnRefreshRefData      = _Ctrl 'BtnRefreshRefData'
$script:BtnGenerateReport      = _Ctrl 'BtnGenerateReport'
$script:BtnSaveReportSnapshot  = _Ctrl 'BtnSaveReportSnapshot'

# Queue Performance tab
$script:BtnPullQueuePerfReport  = _Ctrl 'BtnPullQueuePerfReport'
$script:CmbQueuePerfDivision    = _Ctrl 'CmbQueuePerfDivision'
$script:DgQueuePerf             = _Ctrl 'DgQueuePerf'
$script:LblQPerfQueues          = _Ctrl 'LblQPerfQueues'
$script:LblQPerfOffered         = _Ctrl 'LblQPerfOffered'
$script:LblQPerfAbandoned       = _Ctrl 'LblQPerfAbandoned'
$script:LblQPerfAbandonPct      = _Ctrl 'LblQPerfAbandonPct'
$script:LblQPerfSLAPct          = _Ctrl 'LblQPerfSLAPct'
$script:LblQPerfHandle          = _Ctrl 'LblQPerfHandle'

# Agent Performance tab
$script:BtnPullAgentPerfReport  = _Ctrl 'BtnPullAgentPerfReport'
$script:CmbAgentPerfDivision    = _Ctrl 'CmbAgentPerfDivision'
$script:DgAgentPerf             = _Ctrl 'DgAgentPerf'
$script:LblAPerfAgents          = _Ctrl 'LblAPerfAgents'
$script:LblAPerfConnected       = _Ctrl 'LblAPerfConnected'
$script:LblAPerfHandle          = _Ctrl 'LblAPerfHandle'
$script:LblAPerfTalkPct         = _Ctrl 'LblAPerfTalkPct'
$script:LblAPerfAcwPct          = _Ctrl 'LblAPerfAcwPct'
$script:LblAPerfIdlePct         = _Ctrl 'LblAPerfIdlePct'

# Transfer & Escalation tab
$script:BtnPullTransferReport   = _Ctrl 'BtnPullTransferReport'
$script:CmbTransferType         = _Ctrl 'CmbTransferType'
$script:DgTransferFlows         = _Ctrl 'DgTransferFlows'
$script:DgTransferDestinations  = _Ctrl 'DgTransferDestinations'
$script:DgTransferChains        = _Ctrl 'DgTransferChains'
$script:LblXferFlows            = _Ctrl 'LblXferFlows'
$script:LblXferTransfers        = _Ctrl 'LblXferTransfers'
$script:LblXferBlind            = _Ctrl 'LblXferBlind'
$script:LblXferConsult          = _Ctrl 'LblXferConsult'
$script:LblXferBlindPct         = _Ctrl 'LblXferBlindPct'
$script:LblXferMultiHop         = _Ctrl 'LblXferMultiHop'

# Flow & IVR tab
$script:BtnPullFlowContainmentReport = _Ctrl 'BtnPullFlowContainmentReport'
$script:CmbFlowType                  = _Ctrl 'CmbFlowType'
$script:DgFlowPerf                   = _Ctrl 'DgFlowPerf'
$script:DgFlowMilestones             = _Ctrl 'DgFlowMilestones'
$script:DgFlowQueues                 = _Ctrl 'DgFlowQueues'
$script:LblFlowTotal                 = _Ctrl 'LblFlowTotal'
$script:LblFlowEntries               = _Ctrl 'LblFlowEntries'
$script:LblFlowContainment           = _Ctrl 'LblFlowContainment'
$script:LblFlowFailures              = _Ctrl 'LblFlowFailures'
$script:LblFlowLowContainment        = _Ctrl 'LblFlowLowContainment'

# Contact Reasons tab
$script:BtnPullWrapupReport          = _Ctrl 'BtnPullWrapupReport'
$script:DgWrapupCodes                = _Ctrl 'DgWrapupCodes'
$script:DgWrapupByQueue              = _Ctrl 'DgWrapupByQueue'
$script:DgWrapupByHour               = _Ctrl 'DgWrapupByHour'
$script:DgWrapupInsights             = _Ctrl 'DgWrapupInsights'
$script:DgWrapupCrossRef             = _Ctrl 'DgWrapupCrossRef'
$script:LblWrapupCodes               = _Ctrl 'LblWrapupCodes'
$script:LblWrapupConnected           = _Ctrl 'LblWrapupConnected'
$script:LblWrapupQueues              = _Ctrl 'LblWrapupQueues'
$script:LblWrapupTopReason           = _Ctrl 'LblWrapupTopReason'

# Quality tab
$script:BtnPullQualityReport         = _Ctrl 'BtnPullQualityReport'
$script:DgQualityAgentScores         = _Ctrl 'DgQualityAgentScores'
$script:DgQualityQueues              = _Ctrl 'DgQualityQueues'
$script:DgLowScoreConversations      = _Ctrl 'DgLowScoreConversations'
$script:DgLowScoreTopics             = _Ctrl 'DgLowScoreTopics'
$script:LblQualityEvaluations        = _Ctrl 'LblQualityEvaluations'
$script:LblQualitySurveys            = _Ctrl 'LblQualitySurveys'
$script:LblQualityAvgScore           = _Ctrl 'LblQualityAvgScore'
$script:LblQualityAvgCsat            = _Ctrl 'LblQualityAvgCsat'
$script:LblQualityLowConvs           = _Ctrl 'LblQualityLowConvs'
$script:TxtQualityCorrelation        = _Ctrl 'TxtQualityCorrelation'

# Conversations tab
$script:TxtSearch              = _Ctrl 'TxtSearch'
$script:BtnSearch              = _Ctrl 'BtnSearch'
$script:CmbFilterDirection     = _Ctrl 'CmbFilterDirection'
$script:CmbFilterMedia         = _Ctrl 'CmbFilterMedia'
$script:CmbFilterDisconnect    = _Ctrl 'CmbFilterDisconnect'
$script:TxtFilterAgent         = _Ctrl 'TxtFilterAgent'
$script:DgConversations        = _Ctrl 'DgConversations'
$script:BtnPrevPage            = _Ctrl 'BtnPrevPage'
$script:BtnNextPage            = _Ctrl 'BtnNextPage'
$script:TxtPageInfo            = _Ctrl 'TxtPageInfo'
$script:BtnExportPageCsv       = _Ctrl 'BtnExportPageCsv'
$script:BtnExportRunCsv        = _Ctrl 'BtnExportRunCsv'

# Drilldown tab
$script:LblSelectedConversation = _Ctrl 'LblSelectedConversation'
$script:TxtDrillSummary        = _Ctrl 'TxtDrillSummary'
$script:DgParticipants         = _Ctrl 'DgParticipants'
$script:DgSegments             = _Ctrl 'DgSegments'
$script:TxtAttributeSearch     = _Ctrl 'TxtAttributeSearch'
$script:DgAttributes           = _Ctrl 'DgAttributes'
$script:TxtMosQuality          = _Ctrl 'TxtMosQuality'
$script:TxtRawJson             = _Ctrl 'TxtRawJson'
$script:BtnExpandJson          = _Ctrl 'BtnExpandJson'

# Run Console tab
$script:TxtConsoleStatus       = _Ctrl 'TxtConsoleStatus'
$script:DgRunEvents            = _Ctrl 'DgRunEvents'
$script:BtnCopyDiagnostics     = _Ctrl 'BtnCopyDiagnostics'
$script:TxtDiagnostics         = _Ctrl 'TxtDiagnostics'

# Footer
$script:TxtStatusMain          = _Ctrl 'TxtStatusMain'
$script:TxtStatusRight         = _Ctrl 'TxtStatusRight'

# Query Templates section
$script:CmbQueryTemplate       = _Ctrl 'CmbQueryTemplate'
$script:LblTemplateQueueGroup  = _Ctrl 'LblTemplateQueueGroup'
$script:TxtTemplateQueueGroup  = _Ctrl 'TxtTemplateQueueGroup'
$script:TxtTemplateNote        = _Ctrl 'TxtTemplateNote'
$script:TxtQueryBody           = _Ctrl 'TxtQueryBody'
$script:BtnClearQueryBody      = _Ctrl 'BtnClearQueryBody'

# ── Application state bag ─────────────────────────────────────────────────────

$script:State = @{
    CurrentRunFolder    = $null
    CurrentIndex        = @()          # filtered index entries for current view
    CurrentPage         = 1
    PageSize            = 50
    TotalPages          = 0
    SearchText          = ''
    FilterDirection     = ''
    FilterMedia         = ''
    FilterDisconnect    = ''           # disconnect-type pivot filter (DB mode only)
    FilterAgent         = ''           # agent user-ID filter (DB mode only)
    FilterUserId        = ''           # user/agent GUID pre-query filter (SHAPE SIGNAL)
    FilterDivisionId    = ''           # division GUID pre-query filter (SHAPE SIGNAL)
    DataSource          = 'index'      # 'index' (JSONL) | 'database' (SQLite case store)
    DbConversationCount = 0            # total filtered count in DB mode
    BackgroundRunJob    = $null        # PSDataCollection / runspace handle
    BackgroundRunspace  = $null
    BackgroundRunDataset = ''
    BackgroundRunOutputRoot = ''
    BackgroundRunStartedUtc = $null
    PollingTimer        = $null
    DiagnosticsContext  = $null        # last run folder for diagnostics
    IsRunning           = $false
    RunCancelled        = $false
    PkceCancel          = $null        # CancellationTokenSource for PKCE
    ActiveCaseId        = ''
    ActiveCaseName      = ''
    CurrentImpactReport = $null
    SortColumn          = ''       # SortMemberPath of active sort column ('' = default)
    SortAscending       = $true
    ColumnFilters       = @{}      # SortMemberPath → filter text
    RefreshRefJob       = $null    # PSDataCollection for reference-data background refresh
    RefreshRefRunspace  = $null
    RefreshRefTimer     = $null
    RefreshRefCaseId    = ''       # case targeted by in-progress reference refresh
    QueuePerfJob        = $null    # PSDataCollection for queue-performance background pull
    QueuePerfRunspace   = $null
    QueuePerfTimer      = $null
    QueuePerfCaseId     = ''       # case targeted by in-progress queue-perf pull
    AgentPerfJob        = $null    # PSDataCollection for agent-performance background pull
    AgentPerfRunspace   = $null
    AgentPerfTimer      = $null
    AgentPerfCaseId     = ''       # case targeted by in-progress agent-perf pull
    TransferJob         = $null    # PSDataCollection for transfer report background pull
    TransferRunspace    = $null
    TransferTimer       = $null
    TransferCaseId      = ''       # case targeted by in-progress transfer pull
    FlowContainmentJob      = $null    # PSDataCollection for flow-containment background pull
    FlowContainmentRunspace = $null
    FlowContainmentTimer    = $null
    FlowContainmentCaseId   = ''       # case targeted by in-progress flow-containment pull
    WrapupJob               = $null    # PSDataCollection for wrapup distribution background pull
    WrapupRunspace          = $null
    WrapupTimer             = $null
    WrapupCaseId            = ''       # case targeted by in-progress wrapup pull
    QualityJob              = $null    # PSDataCollection for quality overlay background pull
    QualityRunspace         = $null
    QualityTimer            = $null
    QualityCaseId           = ''       # case targeted by in-progress quality pull
    SuppressConversationSelectionOpen = $false
    PendingRunConversationId = ''
    AutoImportJob      = $null  # background Import-RunFolderToCase job
    AutoImportRunspace = $null
    AutoImportTimer    = $null
}

# Maps display-row property names (SortMemberPath) → index entry property names
$script:_IndexPropMap = @{
    ConversationId   = 'id'
    Direction        = 'direction'
    MediaType        = 'mediaType'
    Queue            = 'queue'
    AgentNames       = 'agentNames'
    DurationSec      = 'durationSec'
    Disconnect       = 'disconnectType'
    HasHold          = 'hasHold'
    HasMos           = 'hasMos'
    SegmentCount     = 'segmentCount'
    ParticipantCount = 'participantCount'
}

# Maps display-row property names (SortMemberPath) → SQLite column names
$script:_DbColMap = @{
    ConversationId   = 'conversation_id'
    Direction        = 'direction'
    MediaType        = 'media_type'
    Queue            = 'queue_name'
    AgentNames       = 'agent_names'
    DurationSec      = 'duration_sec'
    Disconnect       = 'disconnect_type'
    HasHold          = 'has_hold'
    HasMos           = 'has_mos'
    SegmentCount     = 'segment_count'
    ParticipantCount = 'participant_count'
}

# Capture app directory at dot-source time for use inside background runspaces.
# $PSScriptRoot is unreliable inside WPF event-handler closures (not executing a
# script file), so we snapshot it here while a script IS being processed.
# App.UI.ps1 lives in scripts/ — one level below the app root — so step up one
# directory to get the app root where the modules/ folder actually lives.
$script:UIAppDir = if ($PSScriptRoot) {
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..'))
} else {
    $AppDir
}

# ── Dispatcher helper ─────────────────────────────────────────────────────────

function _Dispatch {
    param([scriptblock]$Action)
    if ($script:Window.Dispatcher.CheckAccess()) {
        & $Action
        return
    }

    $script:Window.Dispatcher.Invoke([System.Action]$Action)
}

# ── Visual-tree helper ────────────────────────────────────────────────────────

function _FindVisualChildren {
    # Iterative BFS — avoids PowerShell's recursive-return unwrapping bugs
    # (single-item list → bare object; empty list → $null) that break AddRange.
    param([System.Windows.DependencyObject]$Parent, [type]$ChildType)
    $queue = [System.Collections.Generic.Queue[System.Windows.DependencyObject]]::new()
    $queue.Enqueue($Parent)
    while ($queue.Count -gt 0) {
        $node  = $queue.Dequeue()
        $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($node)
        for ($i = 0; $i -lt $count; $i++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($node, $i)
            if ($child -is $ChildType) { Write-Output $child }
            $queue.Enqueue($child)
        }
    }
}

# ── Column filter boxes ───────────────────────────────────────────────────────
# Called once after DgConversations is rendered.  Finds each ColFilterBox TextBox
# inside the column header template, tags it with the column's SortMemberPath,
# then wires TextChanged to update ColumnFilters and re-render.

function _WireColumnFilterBoxes {
    $headersPresenter = (_FindVisualChildren `
        -Parent    $script:DgConversations `
        -ChildType ([System.Windows.Controls.Primitives.DataGridColumnHeadersPresenter])) |
        Select-Object -First 1
    if ($null -eq $headersPresenter) { return }

    $headers = _FindVisualChildren `
        -Parent    $headersPresenter `
        -ChildType ([System.Windows.Controls.Primitives.DataGridColumnHeader])

    foreach ($hdr in $headers) {
        if ($null -eq $hdr.Column) { continue }          # filler / row-header column
        $bindPath = $hdr.Column.SortMemberPath
        if (-not $bindPath) { continue }

        $filterBox = $hdr.Template.FindName('ColFilterBox', $hdr)
        if ($null -eq $filterBox) { continue }

        $filterBox.Tag = $bindPath
        $filterBox.Add_TextChanged({
            param($tbSender, $tbE)
            $path = [string]$tbSender.Tag
            $val  = $tbSender.Text.Trim()
            if ($val) {
                $script:State.ColumnFilters[$path] = $val
            } else {
                [void]$script:State.ColumnFilters.Remove($path)
            }
            $script:State.CurrentPage = 1
            _ApplyFiltersAndRefresh
        })
    }
}

# ── Status helpers ─────────────────────────────────────────────────────────────

function _SetStatus {
    param([string]$Text, [string]$Right = '')
    _Dispatch {
        $script:TxtStatusMain.Text  = $Text
        $script:TxtStatusRight.Text = $Right
    }
}

function _UpdateConnectionStatus {
    $info = Get-ConnectionInfo
    _Dispatch {
        if ($null -ne $info) {
            $exp = $info.ExpiresAt.ToString('HH:mm:ss') + ' UTC'
            $script:LblConnectionStatus.Text = "$($info.Region)  |  $($info.Flow)  |  expires $exp"
            $script:ElpConnStatus.Fill       = [System.Windows.Media.Brushes]::LightGreen
        } else {
            $script:LblConnectionStatus.Text = 'Not connected'
            $script:ElpConnStatus.Fill       = [System.Windows.Media.Brushes]::Salmon
        }
    }
}

# ── Recent runs ───────────────────────────────────────────────────────────────

function _RefreshRecentRuns {
    $cfg         = Get-AppConfig
    $fromConfig  = @(Get-RecentRuns)
    $fromDisk    = @(Get-RecentRunFolders -OutputRoot $cfg.OutputRoot -Max $cfg.MaxRecentRuns)
    # Merge and deduplicate; config list takes precedence for ordering.
    # Use OrdinalIgnoreCase so C:\Foo and c:\foo are treated as the same path
    # (Select-Object -Unique does a case-sensitive comparison on Windows).
    $seen     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $combined = ($fromConfig + $fromDisk) | Where-Object {
        if ([string]::IsNullOrWhiteSpace([string]$_)) { return $false }
        try   { $key = [System.IO.Path]::GetFullPath([string]$_) }
        catch { $key = [string]$_ }
        $seen.Add($key)
    }
    _Dispatch {
        $script:LstRecentRuns.Items.Clear()
        foreach ($f in $combined) {
            $label = [System.IO.Path]::GetFileName($f)
            $script:LstRecentRuns.Items.Add([pscustomobject]@{ Display = $label; FullPath = $f })
        }
        $script:LstRecentRuns.DisplayMemberPath = 'Display'
    }
}

function _GetActiveCase {
    if (-not (Test-DatabaseInitialized)) { return $null }
    $cfg = Get-AppConfig
    if (-not $cfg.ActiveCaseId) { return $null }
    try {
        return (Get-Case -CaseId $cfg.ActiveCaseId)
    } catch {
        return $null
    }
}

function _RefreshActiveCaseStatus {
    if (-not (Test-DatabaseInitialized)) {
        $script:State.ActiveCaseId   = ''
        $script:State.ActiveCaseName = ''
        _Dispatch {
            $script:LblActiveCase.Text = '(case store offline)'
            $script:BtnManageCase.IsEnabled    = $false
            $script:BtnImportRun.IsEnabled     = $false
            $script:BtnRefreshRefData.IsEnabled = $false
            _ClearTransferGrid
            _ClearFlowContainmentGrid
            _ClearWrapupGrid
            _ClearQualityGrid
        }
        return
    }

    $case = _GetActiveCase
    if ($null -eq $case) {
        $script:State.ActiveCaseId   = ''
        $script:State.ActiveCaseName = ''
        _Dispatch {
            $script:LblActiveCase.Text = '(none selected)'
            $script:BtnManageCase.IsEnabled    = $true
            $script:BtnImportRun.IsEnabled     = $true
            $script:BtnRefreshRefData.IsEnabled = $true
            _ClearTransferGrid
            _ClearFlowContainmentGrid
            _ClearWrapupGrid
            _ClearQualityGrid
        }
        return
    }

    $script:State.ActiveCaseId   = $case.case_id
    $script:State.ActiveCaseName = $case.name
    _Dispatch {
        $retention = if ($case.PSObject.Properties['retention_status']) { $case.retention_status } else { $case.state }
        $suffix = if ($retention -and $retention -ne 'active') { " [$retention]" } else { '' }
        $script:LblActiveCase.Text = "$($case.name)$suffix"
        $script:BtnManageCase.IsEnabled    = $true
        $script:BtnImportRun.IsEnabled     = $true
        $script:BtnRefreshRefData.IsEnabled = $true
        _PopulateQueuePerfDivisionFilter
        _RenderQueuePerfGrid
        _PopulateAgentPerfDivisionFilter
        _RenderAgentPerfGrid
        _RenderTransferGrid
        _RenderFlowContainmentGrid
        _RenderWrapupGrid
        _RenderQualityGrid
    }
}

function _RefreshCoreState {
    # Enables/disables Run buttons based on whether CoreAdapter is initialized.
    # Call after Initialize-CoreAdapter succeeds (or fails) in Settings.
    $ok = Test-CoreInitialized
    _Dispatch {
        if (-not $ok) {
            $script:BtnRun.IsEnabled        = $false
            $script:BtnPreviewRun.IsEnabled = $false
            $script:TxtStatusRight.Text     = 'Core offline'
        } elseif (-not $script:State.IsRunning) {
            $script:BtnRun.IsEnabled        = $true
            $script:BtnPreviewRun.IsEnabled = $true
        }
    }
}

function _ParseTimeText {
    param(
        [string]$Text,
        [System.TimeSpan]$DefaultTime,
        [string]$FieldName
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $DefaultTime
    }

    $trimmed = $Text.Trim()
    $match = [regex]::Match($trimmed, '^(?<hour>\d{1,2}):(?<minute>\d{2})(:(?<second>\d{2}))?$')
    if (-not $match.Success) {
        throw "Invalid $FieldName time '$trimmed'. Use HH:mm or HH:mm:ss."
    }

    $hour   = [int]$match.Groups['hour'].Value
    $minute = [int]$match.Groups['minute'].Value
    $second = if ($match.Groups['second'].Success) { [int]$match.Groups['second'].Value } else { 0 }
    if ($hour -gt 23 -or $minute -gt 59 -or $second -gt 59) {
        throw "Invalid $FieldName time '$trimmed'. Hours must be 00-23 and minutes/seconds 00-59."
    }

    return (New-Object -TypeName System.TimeSpan -ArgumentList $hour, $minute, $second)
}

function _GetSelectedDateTime {
    param(
        [Parameter(Mandatory)]$DatePicker,
        [string]$TimeText,
        [System.TimeSpan]$DefaultTime,
        [string]$FieldName
    )

    if (-not $DatePicker.SelectedDate) {
        return $null
    }

    $date = $DatePicker.SelectedDate.Date
    $time = _ParseTimeText -Text $TimeText -DefaultTime $DefaultTime -FieldName $FieldName
    return $date.Add($time)
}

function _GetQueryBoundaryDateTimes {
    $start = _GetSelectedDateTime -DatePicker $script:DtpStartDate -TimeText $script:TxtStartTime.Text -DefaultTime ([System.TimeSpan]::Zero) -FieldName 'start'
    $end   = _GetSelectedDateTime -DatePicker $script:DtpEndDate   -TimeText $script:TxtEndTime.Text   -DefaultTime (New-Object -TypeName System.TimeSpan -ArgumentList 23, 59, 59) -FieldName 'end'

    if ($null -ne $start -and $null -ne $end -and $start -gt $end) {
        throw 'Start date/time must be earlier than or equal to end date/time.'
    }

    return [ordered]@{
        Start = $start
        End   = $end
    }
}

function _ResolveImportRunFolder {
    if ($script:State.CurrentRunFolder -and [System.IO.Directory]::Exists($script:State.CurrentRunFolder)) {
        return $script:State.CurrentRunFolder
    }
    $sel = $script:LstRecentRuns.SelectedItem
    if ($null -ne $sel -and $sel.FullPath -and [System.IO.Directory]::Exists($sel.FullPath)) {
        return $sel.FullPath
    }
    return ''
}

function _AppendRunDiagnostic {
    param(
        [string]$Stage,
        [string]$Message,
        [object]$Exception = $null,
        [string]$RunFolder = '',
        [string]$DataSource = '',
        [string]$CaseId = '',
        [string]$ConversationId = ''
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("[$([datetime]::UtcNow.ToString('o'))] $Stage") | Out-Null
    if ($Message) { $lines.Add("Message        : $Message") | Out-Null }
    if ($RunFolder) { $lines.Add("Run folder     : $RunFolder") | Out-Null }
    if ($DataSource) { $lines.Add("Data source    : $DataSource") | Out-Null }
    if ($CaseId) { $lines.Add("Case id        : $CaseId") | Out-Null }
    if ($ConversationId) { $lines.Add("Conversation id: $ConversationId") | Out-Null }
    if ($null -ne $Exception) {
        $lines.Add("Exception      : $($Exception.Exception.Message)") | Out-Null
        if ($Exception.ScriptStackTrace) {
            $lines.Add('Script stack   :') | Out-Null
            $lines.Add($Exception.ScriptStackTrace) | Out-Null
        }
    }

    $text = ($lines.ToArray() -join [Environment]::NewLine)
    _Dispatch {
        if ($null -ne $script:TxtDiagnostics) {
            if ([string]::IsNullOrWhiteSpace($script:TxtDiagnostics.Text)) {
                $script:TxtDiagnostics.Text = $text
            } else {
                $script:TxtDiagnostics.AppendText([Environment]::NewLine + [Environment]::NewLine + $text)
            }
            try { $script:TxtDiagnostics.ScrollToEnd() } catch { }
        }
    }
}

function _SetDrilldownDiagnostic {
    param(
        [string]$Title,
        [string]$Message,
        [string]$ConversationId = '',
        [string]$Stage = ''
    )

    _Dispatch {
        if ($null -ne $script:LblSelectedConversation) {
            $script:LblSelectedConversation.Text = if ([string]::IsNullOrWhiteSpace($ConversationId)) { $Title } else { $ConversationId }
        }
        if ($null -ne $script:TxtDrillSummary) {
            $script:TxtDrillSummary.Text = @(
                $Title
                ''
                $Message
                ''
                "Stage            : $Stage"
                "Run folder       : $($script:State.CurrentRunFolder)"
                "Data source      : $($script:State.DataSource)"
                "Active case id   : $($script:State.ActiveCaseId)"
                "Conversation id  : $ConversationId"
            ) -join [Environment]::NewLine
        }
    }
}

function _TestCompletedRunFolder {
    param([string]$RunFolder)

    $manifestPath = if ($RunFolder) { [System.IO.Path]::Combine($RunFolder, 'manifest.json') } else { '' }
    $summaryPath = if ($RunFolder) { [System.IO.Path]::Combine($RunFolder, 'summary.json') } else { '' }
    $dataDir = if ($RunFolder) { [System.IO.Path]::Combine($RunFolder, 'data') } else { '' }
    $dataFiles = @()
    if ($dataDir -and [System.IO.Directory]::Exists($dataDir)) {
        $dataFiles = @([System.IO.Directory]::GetFiles($dataDir, '*.jsonl'))
    }

    return [pscustomobject]@{
        RunFolder = $RunFolder
        RunFolderExists = (-not [string]::IsNullOrWhiteSpace($RunFolder) -and [System.IO.Directory]::Exists($RunFolder))
        ManifestExists = ($manifestPath -and [System.IO.File]::Exists($manifestPath))
        SummaryExists = ($summaryPath -and [System.IO.File]::Exists($summaryPath))
        DataDirectoryExists = ($dataDir -and [System.IO.Directory]::Exists($dataDir))
        DataFileCount = $dataFiles.Count
        IsComplete = (-not [string]::IsNullOrWhiteSpace($RunFolder) -and [System.IO.Directory]::Exists($RunFolder) -and [System.IO.File]::Exists($manifestPath) -and [System.IO.File]::Exists($summaryPath) -and $dataFiles.Count -gt 0)
    }
}

function _ResolveRunFolderFromResult {
    param([object]$RunResult)

    if ($null -eq $RunResult) { return $null }

    $propertyNames = @('runFolder','RunFolder','outputFolder','OutputFolder','runPath','RunPath','path','Path','folder','Folder')
    $candidates = @($RunResult) | ForEach-Object {
        if ($_ -is [string]) {
            $_
        } elseif ($null -ne $_) {
            foreach ($name in $propertyNames) {
                $prop = $_.PSObject.Properties[$name]
                if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                    [string]$prop.Value
                }
            }
        }
    }

    foreach ($candidate in @($candidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        $check = _TestCompletedRunFolder -RunFolder ([string]$candidate)
        if ($check.IsComplete) { return [string]$candidate }
    }

    return $null
}

function _FindCompletedRunFolder {
    param(
        [string]$OutputRoot,
        [string]$DatasetKey,
        [Nullable[datetime]]$StartedAfterUtc
    )

    if ([string]::IsNullOrWhiteSpace($OutputRoot) -or -not [System.IO.Directory]::Exists($OutputRoot)) {
        return $null
    }

    $threshold = $null
    if ($null -ne $StartedAfterUtc) {
        $threshold = ([datetime]$StartedAfterUtc).ToUniversalTime().AddMinutes(-2)
    }

    $roots = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($DatasetKey)) {
        $datasetRoot = [System.IO.Path]::Combine($OutputRoot, $DatasetKey)
        if ([System.IO.Directory]::Exists($datasetRoot)) { $roots.Add($datasetRoot) | Out-Null }
    }
    $roots.Add($OutputRoot) | Out-Null

    $seen = @{}
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($root in $roots.ToArray()) {
        foreach ($dir in [System.IO.Directory]::GetDirectories($root)) {
            if ($seen.ContainsKey($dir)) { continue }
            $seen[$dir] = $true
            if ($null -ne $threshold) {
                $created = [System.IO.Directory]::GetCreationTimeUtc($dir)
                $written = [System.IO.Directory]::GetLastWriteTimeUtc($dir)
                if ($created -lt $threshold -and $written -lt $threshold) { continue }
            }
            $check = _TestCompletedRunFolder -RunFolder $dir
            if ($check.IsComplete) { $candidates.Add($dir) | Out-Null }
        }
    }

    return @($candidates.ToArray() | Sort-Object { [System.IO.Directory]::GetLastWriteTimeUtc($_) } -Descending | Select-Object -First 1)
}

function _FindInProgressRunFolder {
    param(
        [string]$OutputRoot,
        [string]$DatasetKey,
        [Nullable[datetime]]$StartedAfterUtc
    )

    if ([string]::IsNullOrWhiteSpace($OutputRoot) -or -not [System.IO.Directory]::Exists($OutputRoot)) {
        return $null
    }

    $searchRoot = $OutputRoot
    if (-not [string]::IsNullOrWhiteSpace($DatasetKey)) {
        $candidateRoot = [System.IO.Path]::Combine($OutputRoot, $DatasetKey)
        if ([System.IO.Directory]::Exists($candidateRoot)) {
            $searchRoot = $candidateRoot
        }
    }

    $threshold = $null
    if ($null -ne $StartedAfterUtc) {
        $threshold = ([datetime]$StartedAfterUtc).ToUniversalTime().AddMinutes(-2)
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in [System.IO.Directory]::GetDirectories($searchRoot)) {
        $apiLog = [System.IO.Path]::Combine($dir, 'api-calls.log')
        $events = [System.IO.Path]::Combine($dir, 'events.jsonl')
        if (-not ([System.IO.File]::Exists($apiLog) -or [System.IO.File]::Exists($events))) {
            continue
        }

        if ($null -ne $threshold) {
            $created = [System.IO.Directory]::GetCreationTimeUtc($dir)
            $written = [System.IO.Directory]::GetLastWriteTimeUtc($dir)
            if ($created -lt $threshold -and $written -lt $threshold) {
                continue
            }
        }

        $candidates.Add($dir)
    }

    return @($candidates.ToArray() | Sort-Object { [System.IO.Directory]::GetLastWriteTimeUtc($_) } -Descending | Select-Object -First 1)
}

function _GetCurrentViewSnapshot {
    $range = _GetQueryBoundaryDateTimes
    return [ordered]@{
        captured_utc      = [datetime]::UtcNow.ToString('o')
        canonical_filter  = (_GetCanonicalFilterState)
        run_folder        = $script:State.CurrentRunFolder
        search_text       = $script:TxtSearch.Text.Trim()
        grid_direction    = $script:State.FilterDirection
        grid_media        = $script:State.FilterMedia
        extract_direction = if ($script:CmbDirection.SelectedItem -and $script:CmbDirection.SelectedItem.Content -ne '(all)') { $script:CmbDirection.SelectedItem.Content } else { '' }
        extract_media     = if ($script:CmbMediaType.SelectedItem -and $script:CmbMediaType.SelectedItem.Content -ne '(all)') { $script:CmbMediaType.SelectedItem.Content } else { '' }
        queue_contains    = $script:TxtQueue.Text.Trim()
        external_tag_exists = ($script:ChkExternalTagExists.IsChecked -eq $true)
        flow_name           = $script:TxtFlowName.Text.Trim()
        msg_type            = if ($script:CmbMessageType.SelectedItem -and $script:CmbMessageType.SelectedItem.Content -ne '(all)') { $script:CmbMessageType.SelectedItem.Content } else { '' }
        start_date_utc    = if ($null -ne $range.Start) { $range.Start.ToUniversalTime().ToString('o') } else { '' }
        end_date_utc      = if ($null -ne $range.End)   { $range.End.ToUniversalTime().ToString('o')   } else { '' }
        page_size         = $script:State.PageSize
    }
}

function _GetCanonicalFilterState {
    $range = _GetQueryBoundaryDateTimes
    $sortBy = if ($script:State.SortColumn -and $script:_DbColMap.ContainsKey($script:State.SortColumn)) {
        $script:_DbColMap[$script:State.SortColumn]
    } elseif ($script:State.SortColumn) {
        $script:State.SortColumn
    } else {
        'conversation_start'
    }
    $sortDir = if ($script:State.SortAscending) { 'ASC' } else { 'DESC' }
    $columns = @{}
    foreach ($k in @($script:State.ColumnFilters.Keys)) {
        $v = [string]$script:State.ColumnFilters[$k]
        if (-not [string]::IsNullOrWhiteSpace($v)) { $columns[$k] = $v }
    }
    $extractDirection = if ($script:CmbDirection.SelectedItem -and $script:CmbDirection.SelectedItem.Content -ne '(all)') { [string]$script:CmbDirection.SelectedItem.Content } else { '' }
    $extractMedia = if ($script:CmbMediaType.SelectedItem -and $script:CmbMediaType.SelectedItem.Content -ne '(all)') { [string]$script:CmbMediaType.SelectedItem.Content } else { '' }
    return [pscustomobject][ordered]@{
        StartDateTimeUtc = if ($null -ne $range.Start) { $range.Start.ToUniversalTime().ToString('o') } else { '' }
        EndDateTimeUtc   = if ($null -ne $range.End)   { $range.End.ToUniversalTime().ToString('o')   } else { '' }
        Direction        = if ($script:State.FilterDirection) { [string]$script:State.FilterDirection } else { $extractDirection }
        MediaType        = if ($script:State.FilterMedia) { [string]$script:State.FilterMedia } else { $extractMedia }
        QueueText        = [string]$script:TxtQueue.Text.Trim()
        ConversationId   = [string]$script:TxtConversationId.Text.Trim()
        SearchText       = [string]$script:State.SearchText
        DisconnectType   = [string]$script:State.FilterDisconnect
        AgentName        = [string]$script:State.FilterAgent
        Ani              = ''
        DivisionId       = [string]$script:TxtFilterDivisionId.Text.Trim()
        ColumnFilters    = $columns
        SortBy           = $sortBy
        SortDirection    = $sortDir
    }
}

function _SelectComboContent {
    param($Combo, [string]$Content, [string]$DefaultContent = '')
    if ($null -eq $Combo) { return }
    $target = if ($Content) { $Content } else { $DefaultContent }
    foreach ($item in @($Combo.Items)) {
        $itemText = if ($item.PSObject.Properties['Content']) { [string]$item.Content } else { [string]$item }
        if ($itemText -eq $target) {
            $Combo.SelectedItem = $item
            return
        }
    }
    if ($Combo.Items.Count -gt 0 -and -not $Content) { $Combo.SelectedIndex = 0 }
}

function _SetDateTimeFilterControls {
    param(
        [string]$ValueUtc,
        $DatePicker,
        $TimeBox
    )
    if ($null -eq $DatePicker -or $null -eq $TimeBox) { return }
    if ([string]::IsNullOrWhiteSpace($ValueUtc)) {
        $DatePicker.SelectedDate = $null
        $TimeBox.Text = ''
        return
    }
    try {
        $dt = ([datetime]::Parse($ValueUtc)).ToLocalTime()
        $DatePicker.SelectedDate = $dt.Date
        $TimeBox.Text = $dt.ToString('HH:mm:ss')
    } catch { }
}

function _ApplyCanonicalFilterStateToUi {
    param([Parameter(Mandatory)][object]$FilterState)

    $get = {
        param([string]$Name)
        if ($FilterState -is [hashtable] -and $FilterState.ContainsKey($Name)) { return $FilterState[$Name] }
        $prop = $FilterState.PSObject.Properties[$Name]
        if ($null -ne $prop) { return $prop.Value }
        return ''
    }

    _SetDateTimeFilterControls -ValueUtc ([string](& $get 'StartDateTimeUtc')) -DatePicker $script:DtpStartDate -TimeBox $script:TxtStartTime
    _SetDateTimeFilterControls -ValueUtc ([string](& $get 'EndDateTimeUtc')) -DatePicker $script:DtpEndDate -TimeBox $script:TxtEndTime

    $script:State.FilterDirection  = [string](& $get 'Direction')
    $script:State.FilterMedia      = [string](& $get 'MediaType')
    $script:State.FilterDisconnect = [string](& $get 'DisconnectType')
    $script:State.FilterAgent      = [string](& $get 'AgentName')
    $script:State.SearchText       = [string](& $get 'SearchText')

    _SelectComboContent -Combo $script:CmbFilterDirection -Content $script:State.FilterDirection -DefaultContent 'All directions'
    _SelectComboContent -Combo $script:CmbFilterMedia -Content $script:State.FilterMedia -DefaultContent 'All media'
    _SelectComboContent -Combo $script:CmbFilterDisconnect -Content $script:State.FilterDisconnect -DefaultContent 'All disconnects'
    _SelectComboContent -Combo $script:CmbDirection -Content $script:State.FilterDirection -DefaultContent '(all)'
    _SelectComboContent -Combo $script:CmbMediaType -Content $script:State.FilterMedia -DefaultContent '(all)'

    if ($null -ne $script:TxtQueue)            { $script:TxtQueue.Text = [string](& $get 'QueueText') }
    if ($null -ne $script:TxtConversationId)   { $script:TxtConversationId.Text = [string](& $get 'ConversationId') }
    if ($null -ne $script:TxtSearch)           { $script:TxtSearch.Text = $script:State.SearchText }
    if ($null -ne $script:TxtFilterAgent)      { $script:TxtFilterAgent.Text = $script:State.FilterAgent }
    if ($null -ne $script:TxtFilterDivisionId) { $script:TxtFilterDivisionId.Text = [string](& $get 'DivisionId') }

    $script:State.ColumnFilters = @{}
    $cols = & $get 'ColumnFilters'
    if ($null -ne $cols) {
        if ($cols -is [hashtable]) {
            foreach ($k in @($cols.Keys)) { if ($cols[$k]) { $script:State.ColumnFilters[$k] = [string]$cols[$k] } }
        } else {
            foreach ($p in $cols.PSObject.Properties) { if ($p.Value) { $script:State.ColumnFilters[$p.Name] = [string]$p.Value } }
        }
    }

    $sortBy = [string](& $get 'SortBy')
    $script:State.SortColumn = ''
    foreach ($k in @($script:_DbColMap.Keys)) {
        if ($script:_DbColMap[$k] -eq $sortBy) { $script:State.SortColumn = $k; break }
    }
    if (-not $script:State.SortColumn) { $script:State.SortColumn = $sortBy }
    $script:State.SortAscending = ([string](& $get 'SortDirection')).ToUpperInvariant() -eq 'ASC'
    $script:State.CurrentPage = 1
    $script:State.CurrentImpactReport = $null

    _ApplyFiltersAndRefresh
    _SetStatus 'Saved view filter restored'
}

function _GetCurrentImpactReportTitle {
    $search = $script:State.SearchText
    if (-not [string]::IsNullOrWhiteSpace($search)) {
        return "Impact Report: $search"
    }
    return 'Impact Report: Current Filter'
}

function _RefreshReportButtons {
    $canGenerate = ($null -ne $script:State.CurrentIndex -and @($script:State.CurrentIndex).Count -gt 0)
    $canSave = $canGenerate -and ($null -ne $script:State.CurrentImpactReport) -and (Test-DatabaseInitialized)
    _Dispatch {
        if ($null -ne $script:BtnGenerateReport) {
            $script:BtnGenerateReport.IsEnabled = $canGenerate
        }
        if ($null -ne $script:BtnSaveReportSnapshot) {
            $script:BtnSaveReportSnapshot.IsEnabled = $canSave
        }
    }
}

function _GenerateImpactReport {
    $current = @($script:State.CurrentIndex)
    if ($current.Count -eq 0) {
        _SetStatus 'No filtered conversations available for reporting'
        [System.Windows.MessageBox]::Show('Load a run and apply filters before generating a report.', 'Impact Report')
        return
    }

    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        if ($script:State.DataSource -eq 'database' -and -not [string]::IsNullOrEmpty($script:State.ActiveCaseId) -and (Test-DatabaseInitialized)) {
            $filterState = _GetCanonicalFilterState
            $rows = @(Get-ConversationPopulationRows -CaseId $script:State.ActiveCaseId -FilterState $filterState)
            $summary = Get-ConversationPopulationSummary -CaseId $script:State.ActiveCaseId -FilterState $filterState
            $facets = Get-ConversationFacetCounts -CaseId $script:State.ActiveCaseId -FilterState $filterState
            $representatives = @(Get-RepresentativeConversations -CaseId $script:State.ActiveCaseId -FilterState $filterState -Top 10)
            $cohorts = @(Get-AnomalyRiskCohorts -CaseId $script:State.ActiveCaseId -FilterState $filterState)
            $provenance = [pscustomobject][ordered]@{
                CaseId     = $script:State.ActiveCaseId
                CaseName   = $script:State.ActiveCaseName
                DataSource = 'database'
                PageAtGeneration = $script:State.CurrentPage
                PageSize   = $script:State.PageSize
            }
            $report = New-PopulationReport `
                -Rows $rows `
                -FilterState $filterState `
                -Summary $summary `
                -Facets $facets `
                -Representatives $representatives `
                -Cohorts $cohorts `
                -Provenance $provenance `
                -ReportTitle (_GetCurrentImpactReportTitle)
        } else {
            $filterState = _GetCanonicalFilterState
            $report = New-ImpactReport -FilteredIndex $current -ReportTitle (_GetCurrentImpactReportTitle)
            $report | Add-Member -NotePropertyName 'ExactFilterState' -NotePropertyValue $filterState -Force
            $report | Add-Member -NotePropertyName 'ReportType' -NotePropertyValue 'Population' -Force
        }
        $script:State.CurrentImpactReport = $report
        _Dispatch {
            $script:TxtDrillSummary.Text = $report | ConvertTo-Json -Depth 8
        }
        _RefreshReportButtons
        _SetStatus "Generated impact report for $($report.TotalConversations) conversations"
    } catch {
        _SetStatus 'Impact report generation failed'
        [System.Windows.MessageBox]::Show("Failed to generate impact report: $_", 'Impact Report')
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
}

function _SaveImpactReportSnapshot {
    if (-not (Test-DatabaseInitialized)) {
        _SetStatus 'Case store offline'
        return
    }

    if ($null -eq $script:State.CurrentImpactReport) {
        _GenerateImpactReport
        if ($null -eq $script:State.CurrentImpactReport) { return }
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        $snapshotName = "{0} [{1}]" -f $script:State.CurrentImpactReport.ReportTitle, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        $snapshotContent = [pscustomobject][ordered]@{
            snapshot_type = 'report'
            exact_filter_state = (_GetCanonicalFilterState)
            report = $script:State.CurrentImpactReport
        }
        New-ReportSnapshot -CaseId $case.case_id -Name $snapshotName -Format 'json' -Content $snapshotContent | Out-Null
        _SetStatus "Saved impact report snapshot to case '$($case.name)'"
        [System.Windows.MessageBox]::Show("Saved impact report snapshot to case '$($case.name)'.", 'Impact Report')
    } catch {
        _SetStatus 'Failed to save report snapshot'
        [System.Windows.MessageBox]::Show("Failed to save impact report snapshot: $_", 'Impact Report')
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
}

function _ShowCaseDialog {
    if (-not (Test-DatabaseInitialized)) {
        [System.Windows.MessageBox]::Show('Case store is unavailable. Verify SQLite startup succeeded.', 'Case Store')
        return $null
    }

    $dialog = New-Object System.Windows.Window
    $dialog.Title   = 'Case Store'
    $dialog.Width   = 980
    $dialog.Height  = 720
    $dialog.Owner   = $script:Window
    $dialog.WindowStartupLocation = 'CenterOwner'

    $root = New-Object System.Windows.Controls.Grid
    $root.Margin = [System.Windows.Thickness]::new(16)
    $root.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(300) }))
    $root.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(16) }))
    $root.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))

    $left = New-Object System.Windows.Controls.Grid
    $left.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    $left.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(260) }))
    [System.Windows.Controls.Grid]::SetColumn($left, 0)
    $root.Children.Add($left) | Out-Null

    $lstCases = New-Object System.Windows.Controls.ListBox
    $lstCases.DisplayMemberPath = 'Display'
    $lstCases.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    [System.Windows.Controls.Grid]::SetRow($lstCases, 0)
    $left.Children.Add($lstCases) | Out-Null

    $createPanel = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetRow($createPanel, 1)
    $left.Children.Add($createPanel) | Out-Null

    function _AddCaseLabel {
        param([System.Windows.Controls.Panel]$Parent, [string]$Text)
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $Text
        $lbl.Margin = [System.Windows.Thickness]::new(0,4,0,2)
        $Parent.Children.Add($lbl) | Out-Null
    }
    function _AddCaseText {
        param([System.Windows.Controls.Panel]$Parent, [string]$Value = '', [int]$Height = 28)
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Height = $Height
        $tb.Text   = $Value
        $Parent.Children.Add($tb) | Out-Null
        return $tb
    }

    _AddCaseLabel $createPanel 'Create a new case'
    _AddCaseLabel $createPanel 'Name'
    $tbName = _AddCaseText $createPanel
    _AddCaseLabel $createPanel 'Description'
    $tbDesc = _AddCaseText $createPanel
    _AddCaseLabel $createPanel 'Expires UTC (optional, ISO-8601 or yyyy-MM-dd)'
    $tbExp  = _AddCaseText $createPanel

    $leftBtnPanel = New-Object System.Windows.Controls.WrapPanel
    $leftBtnPanel.Margin = [System.Windows.Thickness]::new(0,12,0,0)
    $leftBtnPanel.HorizontalAlignment = 'Left'
    $createPanel.Children.Add($leftBtnPanel) | Out-Null

    $btnUse    = New-Object System.Windows.Controls.Button -Property @{ Content = 'Use Selected'; Width = 110; Height = 30; Margin = [System.Windows.Thickness]::new(0,0,8,8) }
    $btnNew    = New-Object System.Windows.Controls.Button -Property @{ Content = 'Create New'; Width = 100; Height = 30; Margin = [System.Windows.Thickness]::new(0,0,8,8) }
    $btnRefresh = New-Object System.Windows.Controls.Button -Property @{ Content = 'Refresh'; Width = 80; Height = 30; Margin = [System.Windows.Thickness]::new(0,0,8,8) }
    $btnClose  = New-Object System.Windows.Controls.Button -Property @{ Content = 'Close'; Width = 80; Height = 30; Margin = [System.Windows.Thickness]::new(0,0,8,8) }
    $leftBtnPanel.Children.Add($btnUse) | Out-Null
    $leftBtnPanel.Children.Add($btnNew) | Out-Null
    $leftBtnPanel.Children.Add($btnRefresh) | Out-Null
    $leftBtnPanel.Children.Add($btnClose) | Out-Null

    $right = New-Object System.Windows.Controls.Grid
    $right.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(48) }))
    $right.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(92) }))
    $right.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(180) }))
    $right.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(130) }))
    $right.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    $right.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(44) }))
    [System.Windows.Controls.Grid]::SetColumn($right, 2)
    $root.Children.Add($right) | Out-Null

    $txtSummary = New-Object System.Windows.Controls.TextBlock
    $txtSummary.Text = '(no case selected)'
    $txtSummary.FontWeight = 'SemiBold'
    $txtSummary.TextWrapping = 'Wrap'
    [System.Windows.Controls.Grid]::SetRow($txtSummary, 0)
    $right.Children.Add($txtSummary) | Out-Null

    $metaGrid = New-Object System.Windows.Controls.Grid
    $metaGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(150) }))
    $metaGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    $metaGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(90) }))
    $metaGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(12) }))
    $metaGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    $metaGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(90) }))
    $metaGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(24) }))
    $metaGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(32) }))
    [System.Windows.Controls.Grid]::SetRow($metaGrid, 1)
    $right.Children.Add($metaGrid) | Out-Null

    $lblExpiry = New-Object System.Windows.Controls.TextBlock -Property @{ Text = 'Expiry'; VerticalAlignment = 'Center' }
    [System.Windows.Controls.Grid]::SetColumn($lblExpiry, 0)
    [System.Windows.Controls.Grid]::SetRow($lblExpiry, 0)
    $metaGrid.Children.Add($lblExpiry) | Out-Null
    $tbExpiryManage = New-Object System.Windows.Controls.TextBox -Property @{ Height = 28 }
    [System.Windows.Controls.Grid]::SetColumn($tbExpiryManage, 1)
    [System.Windows.Controls.Grid]::SetRow($tbExpiryManage, 1)
    $metaGrid.Children.Add($tbExpiryManage) | Out-Null
    $btnSaveExpiry = New-Object System.Windows.Controls.Button -Property @{ Content = 'Save'; Width = 80; Height = 28 }
    [System.Windows.Controls.Grid]::SetColumn($btnSaveExpiry, 2)
    [System.Windows.Controls.Grid]::SetRow($btnSaveExpiry, 1)
    $metaGrid.Children.Add($btnSaveExpiry) | Out-Null

    $lblTags = New-Object System.Windows.Controls.TextBlock -Property @{ Text = 'Tags (comma-separated)'; VerticalAlignment = 'Center' }
    [System.Windows.Controls.Grid]::SetColumn($lblTags, 4)
    [System.Windows.Controls.Grid]::SetRow($lblTags, 0)
    $metaGrid.Children.Add($lblTags) | Out-Null
    $tbTags = New-Object System.Windows.Controls.TextBox -Property @{ Height = 28 }
    [System.Windows.Controls.Grid]::SetColumn($tbTags, 4)
    [System.Windows.Controls.Grid]::SetRow($tbTags, 1)
    $metaGrid.Children.Add($tbTags) | Out-Null
    $btnSaveTags = New-Object System.Windows.Controls.Button -Property @{ Content = 'Save'; Width = 80; Height = 28 }
    [System.Windows.Controls.Grid]::SetColumn($btnSaveTags, 5)
    [System.Windows.Controls.Grid]::SetRow($btnSaveTags, 1)
    $metaGrid.Children.Add($btnSaveTags) | Out-Null

    $notesPanel = New-Object System.Windows.Controls.Grid
    $notesPanel.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(24) }))
    $notesPanel.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    $notesPanel.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(34) }))
    [System.Windows.Controls.Grid]::SetRow($notesPanel, 2)
    $right.Children.Add($notesPanel) | Out-Null

    $lblNotes = New-Object System.Windows.Controls.TextBlock -Property @{ Text = 'Case Notes'; VerticalAlignment = 'Center' }
    [System.Windows.Controls.Grid]::SetRow($lblNotes, 0)
    $notesPanel.Children.Add($lblNotes) | Out-Null
    $tbNotesManage = New-Object System.Windows.Controls.TextBox
    $tbNotesManage.AcceptsReturn = $true
    $tbNotesManage.TextWrapping  = 'Wrap'
    $tbNotesManage.VerticalScrollBarVisibility = 'Auto'
    [System.Windows.Controls.Grid]::SetRow($tbNotesManage, 1)
    $notesPanel.Children.Add($tbNotesManage) | Out-Null
    $notesBtnPanel = New-Object System.Windows.Controls.StackPanel
    $notesBtnPanel.Orientation = 'Horizontal'
    $notesBtnPanel.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetRow($notesBtnPanel, 2)
    $notesPanel.Children.Add($notesBtnPanel) | Out-Null
    $btnSaveNotes = New-Object System.Windows.Controls.Button -Property @{ Content = 'Save Notes'; Width = 110; Height = 30 }
    $notesBtnPanel.Children.Add($btnSaveNotes) | Out-Null

    $viewGrid = New-Object System.Windows.Controls.Grid
    $viewGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    $viewGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(160) }))
    $viewGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(24) }))
    $viewGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(32) }))
    $viewGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    [System.Windows.Controls.Grid]::SetRow($viewGrid, 3)
    $right.Children.Add($viewGrid) | Out-Null

    $lblViews = New-Object System.Windows.Controls.TextBlock -Property @{ Text = 'Saved Views'; VerticalAlignment = 'Center' }
    [System.Windows.Controls.Grid]::SetRow($lblViews, 0)
    [System.Windows.Controls.Grid]::SetColumnSpan($lblViews, 2)
    $viewGrid.Children.Add($lblViews) | Out-Null
    $tbViewName = New-Object System.Windows.Controls.TextBox -Property @{ Height = 28 }
    [System.Windows.Controls.Grid]::SetRow($tbViewName, 1)
    [System.Windows.Controls.Grid]::SetColumn($tbViewName, 0)
    $viewGrid.Children.Add($tbViewName) | Out-Null
    $viewBtnPanel = New-Object System.Windows.Controls.WrapPanel
    $viewBtnPanel.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetRow($viewBtnPanel, 1)
    [System.Windows.Controls.Grid]::SetColumn($viewBtnPanel, 1)
    $viewGrid.Children.Add($viewBtnPanel) | Out-Null
    $btnSaveView = New-Object System.Windows.Controls.Button -Property @{ Content = 'Save Current'; Width = 100; Height = 28; Margin = [System.Windows.Thickness]::new(0,0,8,0) }
    $btnDeleteView = New-Object System.Windows.Controls.Button -Property @{ Content = 'Delete'; Width = 70; Height = 28 }
    $viewBtnPanel.Children.Add($btnSaveView) | Out-Null
    $viewBtnPanel.Children.Add($btnDeleteView) | Out-Null
    $lstViews = New-Object System.Windows.Controls.ListBox
    $lstViews.DisplayMemberPath = 'Display'
    [System.Windows.Controls.Grid]::SetRow($lstViews, 2)
    [System.Windows.Controls.Grid]::SetColumnSpan($lstViews, 2)
    $viewGrid.Children.Add($lstViews) | Out-Null

    $auditPanel = New-Object System.Windows.Controls.Grid
    $auditPanel.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(24) }))
    $auditPanel.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    [System.Windows.Controls.Grid]::SetRow($auditPanel, 4)
    $right.Children.Add($auditPanel) | Out-Null
    $lblAudit = New-Object System.Windows.Controls.TextBlock -Property @{ Text = 'Audit Trail'; VerticalAlignment = 'Center' }
    [System.Windows.Controls.Grid]::SetRow($lblAudit, 0)
    $auditPanel.Children.Add($lblAudit) | Out-Null
    $lstAudit = New-Object System.Windows.Controls.ListBox
    $lstAudit.DisplayMemberPath = 'Display'
    [System.Windows.Controls.Grid]::SetRow($lstAudit, 1)
    $auditPanel.Children.Add($lstAudit) | Out-Null

    $actionPanel = New-Object System.Windows.Controls.WrapPanel
    $actionPanel.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetRow($actionPanel, 5)
    $right.Children.Add($actionPanel) | Out-Null
    $btnCloseCase = New-Object System.Windows.Controls.Button -Property @{ Content = 'Close Case'; Width = 96; Height = 30; Margin = [System.Windows.Thickness]::new(0,0,8,0) }
    $btnPurgeReady = New-Object System.Windows.Controls.Button -Property @{ Content = 'Mark Purge-Ready'; Width = 132; Height = 30; Margin = [System.Windows.Thickness]::new(0,0,8,0) }
    $btnArchive = New-Object System.Windows.Controls.Button -Property @{ Content = 'Archive Imported Data'; Width = 150; Height = 30; Margin = [System.Windows.Thickness]::new(0,0,8,0) }
    $btnPurge = New-Object System.Windows.Controls.Button -Property @{ Content = 'Purge Case'; Width = 96; Height = 30 }
    $actionPanel.Children.Add($btnCloseCase) | Out-Null
    $actionPanel.Children.Add($btnPurgeReady) | Out-Null
    $actionPanel.Children.Add($btnArchive) | Out-Null
    $actionPanel.Children.Add($btnPurge) | Out-Null

    $dialog.Content = $root
    $script:selectedCaseId = $null

    function _RefreshCaseListLocal {
        param([string]$PreferredCaseId = '')
        $cases = @(Get-Cases)
        $lstCases.Items.Clear()
        foreach ($case in $cases) {
            $label = "$($case.name) [$($case.retention_status)]  created $($case.created_utc)"
            $lstCases.Items.Add([pscustomobject]@{
                CaseId  = $case.case_id
                Display = $label
            }) | Out-Null
        }

        $targetId = if ($PreferredCaseId) { $PreferredCaseId } else { (Get-AppConfig).ActiveCaseId }
        if ($targetId) {
            foreach ($item in @($lstCases.Items)) {
                if ($item.CaseId -eq $targetId) {
                    $lstCases.SelectedItem = $item
                    return
                }
            }
        }
        if ($lstCases.Items.Count -gt 0) { $lstCases.SelectedIndex = 0 }
    }

    function _RenderSelectedCaseLocal {
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) {
            $txtSummary.Text       = '(no case selected)'
            $tbExpiryManage.Text   = ''
            $tbTags.Text           = ''
            $tbNotesManage.Text    = ''
            $lstViews.Items.Clear()
            $lstAudit.Items.Clear()
            return
        }

        $case = Get-Case -CaseId $sel.CaseId
        if ($null -eq $case) { return }

        $tagText = (@(Get-CaseTags -CaseId $case.case_id) -join ', ')
        $views   = @(Get-SavedViews -CaseId $case.case_id)
        $audit   = @(Get-CaseAudit -CaseId $case.case_id -LastN 50)
        $counts  = @{
            bookmarks  = @(Get-ConversationBookmarks -CaseId $case.case_id).Count
            findings   = @(Get-Findings -CaseId $case.case_id).Count
            snapshots  = @(Get-ReportSnapshots -CaseId $case.case_id).Count
            imports    = @(Get-Imports -CaseId $case.case_id).Count
        }

        $txtSummary.Text = "$($case.name)  [$($case.retention_status)]`nCase Id: $($case.case_id)`nImports: $($counts.imports)  Bookmarks: $($counts.bookmarks)  Findings: $($counts.findings)  Snapshots: $($counts.snapshots)"
        $tbExpiryManage.Text = [string]$case.expires_utc
        $tbTags.Text         = $tagText
        $tbNotesManage.Text  = [string]$case.notes

        $lstViews.Items.Clear()
        foreach ($view in $views) {
            $lstViews.Items.Add([pscustomobject]@{
                ViewId   = $view.view_id
                Display  = "$($view.name)  [$($view.created_utc)]"
                FilterJson = $view.filters_json
            }) | Out-Null
        }

        $lstAudit.Items.Clear()
        foreach ($entry in $audit) {
            $lstAudit.Items.Add([pscustomobject]@{
                Display = "$($entry.created_utc)  $($entry.event_type)  $($entry.detail_text)"
            }) | Out-Null
        }
    }

    _RefreshCaseListLocal

    $lstCases.Add_SelectionChanged({
        _RenderSelectedCaseLocal
    })

    $btnUse.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) {
            [System.Windows.MessageBox]::Show('Select a case first.', 'Case Store')
            return
        }
        $script:selectedCaseId = $sel.CaseId
        $dialog.DialogResult = $true
        $dialog.Close()
    })

    $btnNew.Add_Click({
        $name = $tbName.Text.Trim()
        if (-not $name) {
            [System.Windows.MessageBox]::Show('Case name is required.', 'Case Store')
            return
        }

        $expUtc = ''
        $expTxt = $tbExp.Text.Trim()
        if ($expTxt) {
            try {
                $expUtc = ([datetime]::Parse($expTxt)).ToUniversalTime().ToString('o')
            } catch {
                [System.Windows.MessageBox]::Show('Expiry must be a valid date.', 'Case Store')
                return
            }
        }

        try {
            $script:selectedCaseId = New-Case -Name $name -Description $tbDesc.Text.Trim() -ExpiresUtc $expUtc
            $dialog.DialogResult = $true
            $dialog.Close()
        } catch {
            [System.Windows.MessageBox]::Show("Failed to create case: $_", 'Case Store')
        }
    })

    $btnRefresh.Add_Click({
        $current = if ($lstCases.SelectedItem) { $lstCases.SelectedItem.CaseId } else { '' }
        _RefreshCaseListLocal -PreferredCaseId $current
        _RenderSelectedCaseLocal
    })

    $btnSaveExpiry.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) { return }
        $expUtc = ''
        $txt = $tbExpiryManage.Text.Trim()
        if ($txt) {
            try {
                $expUtc = ([datetime]::Parse($txt)).ToUniversalTime().ToString('o')
            } catch {
                [System.Windows.MessageBox]::Show('Expiry must be a valid date.', 'Case Store')
                return
            }
        }
        Set-CaseExpiry -CaseId $sel.CaseId -ExpiresUtc $expUtc
        _RefreshCaseListLocal -PreferredCaseId $sel.CaseId
        _RenderSelectedCaseLocal
    })

    $btnSaveTags.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) { return }
        $tags = @($tbTags.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Set-CaseTags -CaseId $sel.CaseId -Tags $tags
        _RenderSelectedCaseLocal
    })

    $btnSaveNotes.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) { return }
        Update-CaseNotes -CaseId $sel.CaseId -Notes $tbNotesManage.Text
        _RenderSelectedCaseLocal
    })

    $btnSaveView.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) { return }
        $name = $tbViewName.Text.Trim()
        if (-not $name) {
            [System.Windows.MessageBox]::Show('Enter a saved-view name first.', 'Case Store')
            return
        }
        try {
            New-SavedView -CaseId $sel.CaseId -Name $name -ViewDefinition (_GetCurrentViewSnapshot) | Out-Null
            $tbViewName.Text = ''
            _RenderSelectedCaseLocal
        } catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Validation')
        }
    })

    $btnDeleteView.Add_Click({
        $selCase = $lstCases.SelectedItem
        $selView = $lstViews.SelectedItem
        if ($null -eq $selCase -or $null -eq $selView) { return }
        Remove-SavedView -CaseId $selCase.CaseId -ViewId $selView.ViewId
        _RenderSelectedCaseLocal
    })

    $lstViews.Add_MouseDoubleClick({
        $selView = $lstViews.SelectedItem
        if ($null -eq $selView -or [string]::IsNullOrWhiteSpace([string]$selView.FilterJson)) { return }
        try {
            $viewDef = $selView.FilterJson | ConvertFrom-Json
            $filter = $null
            if ($viewDef.PSObject.Properties['canonical_filter']) {
                $filter = $viewDef.canonical_filter
            } else {
                $filter = $viewDef
            }
            _ApplyCanonicalFilterStateToUi -FilterState $filter
            $dialog.DialogResult = $true
            $dialog.Close()
        } catch {
            [System.Windows.MessageBox]::Show("Failed to restore saved view: $_", 'Saved View')
        }
    })

    $btnCloseCase.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) { return }
        Close-Case -CaseId $sel.CaseId
        _RefreshCaseListLocal -PreferredCaseId $sel.CaseId
        _RenderSelectedCaseLocal
        _RefreshActiveCaseStatus
    })

    $btnPurgeReady.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) { return }
        Mark-CasePurgeReady -CaseId $sel.CaseId
        _RefreshCaseListLocal -PreferredCaseId $sel.CaseId
        _RenderSelectedCaseLocal
        _RefreshActiveCaseStatus
    })

    $btnArchive.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) { return }
        $answer = [System.Windows.MessageBox]::Show(
            'Archive this case? Imported runs and conversations will be removed, but notes, findings, saved views, report snapshots, and audit history will remain.',
            'Archive Case',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
        Archive-Case -CaseId $sel.CaseId
        _RefreshCaseListLocal -PreferredCaseId $sel.CaseId
        _RenderSelectedCaseLocal
        _RefreshActiveCaseStatus
    })

    $btnPurge.Add_Click({
        $sel = $lstCases.SelectedItem
        if ($null -eq $sel) { return }
        $answer = [System.Windows.MessageBox]::Show(
            'Purge this case? Imported data, notes, tags, bookmarks, findings, saved views, and report snapshots will be removed. The case shell and audit history will remain.',
            'Purge Case',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
        Purge-Case -CaseId $sel.CaseId
        _RefreshCaseListLocal -PreferredCaseId $sel.CaseId
        _RenderSelectedCaseLocal
        _RefreshActiveCaseStatus
    })

    $btnClose.Add_Click({ $dialog.Close() })
    _RenderSelectedCaseLocal
    $dialog.ShowDialog() | Out-Null

    if (-not $script:selectedCaseId) {
        _RefreshActiveCaseStatus
        return (_GetActiveCase)
    }

    Update-AppConfig -Key 'ActiveCaseId' -Value $script:selectedCaseId
    _RefreshActiveCaseStatus
    return (_GetActiveCase)
}

function _EnsureActiveCase {
    $case = _GetActiveCase
    if ($null -ne $case) { return $case }
    return (_ShowCaseDialog)
}

function _StartRefreshReferenceDataJob {
    <#
        Pulls reference datasets (queues, users, divisions, skills, flows, wrapup codes)
        from the Genesys Cloud org in a background runspace, then imports the results
        into the active case's reference tables.
    #>
    if (-not (Test-DatabaseInitialized)) {
        [System.Windows.MessageBox]::Show('Case store is offline.', 'Reference Data')
        return
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    if (-not (Test-CoreInitialized)) {
        [System.Windows.MessageBox]::Show('Genesys Core is not initialized. Check Settings.', 'Reference Data')
        return
    }

    $headers = Get-StoredHeaders
    if ($null -eq $headers -or $headers.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Connect to Genesys Cloud before refreshing reference data.', 'Not Connected')
        return
    }

    $cfg         = Get-AppConfig
    $corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
    $catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
    $schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
    $outputRoot  = $cfg.OutputRoot
    $connInfo    = Get-ConnectionInfo
    $region      = if ($null -ne $connInfo -and $connInfo.Region) { $connInfo.Region } else { $cfg.Region }
    $baseUri     = "https://api.$region"
    $caseId      = $case.case_id
    $caseName    = $case.name

    _SetStatus 'Refreshing reference data…'
    $script:BtnRefreshRefData.IsEnabled = $false
    $script:State.RefreshRefCaseId = $caseId

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $appDir = $script:UIAppDir

    [void]$ps.AddScript({
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $Headers, $BaseUri)
        Set-StrictMode -Version Latest

        Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')) -Force -ErrorAction Stop
        Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
        return (Refresh-ReferenceData -Headers $Headers -BaseUri $BaseUri)
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($headers)
    [void]$ps.AddArgument($baseUri)

    $asyncResult = $ps.BeginInvoke()

    $script:State.RefreshRefJob      = @{ Ps = $ps; Async = $asyncResult; CaseId = $caseId; CaseName = $caseName }
    $script:State.RefreshRefRunspace = $rs

    $timer          = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(2)
    $script:State.RefreshRefTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        $job = $script:State.RefreshRefJob
        if ($null -eq $job) { $script:State.RefreshRefTimer.Stop(); return }
        if (-not $job.Async.IsCompleted) { return }

        $script:State.RefreshRefTimer.Stop()
        $script:State.RefreshRefTimer = $null

        $folderMap  = $null
        $endFailure = $null
        try {
            $results   = $job.Ps.EndInvoke($job.Async)
            $folderMap = $results | Select-Object -Last 1
        } catch {
            $endFailure = $_
        } finally {
            try { $job.Ps.Dispose() }                              catch {}
            try { $script:State.RefreshRefRunspace.Close() }      catch {}
            try { $script:State.RefreshRefRunspace.Dispose() }    catch {}
            $script:State.RefreshRefJob      = $null
            $script:State.RefreshRefRunspace = $null
            $script:State.RefreshRefCaseId   = ''
        }

        if ($null -ne $endFailure) {
            _SetStatus 'Reference data refresh failed'
            _Dispatch { $script:BtnRefreshRefData.IsEnabled = $true }
            [System.Windows.MessageBox]::Show("Refresh failed: $endFailure", 'Reference Data')
            return
        }

        if ($null -ne $folderMap) {
            try {
                $counts  = Import-ReferenceDataToCase -CaseId $job.CaseId -FolderMap $folderMap
                $parts   = $counts.GetEnumerator() |
                               Where-Object { $_.Value -gt 0 } |
                               ForEach-Object { "$($_.Value) $($_.Key)" }
                $summary = 'Loaded ' + ($parts -join ', ')
                _SetStatus $summary
                [System.Windows.MessageBox]::Show($summary, 'Reference Data Refreshed')
            } catch {
                _SetStatus 'Reference data import failed'
                [System.Windows.MessageBox]::Show("Import failed: $_", 'Reference Data')
            }
        } else {
            _SetStatus 'Reference data refresh completed'
        }

        _Dispatch { $script:BtnRefreshRefData.IsEnabled = $true }
    })

    $timer.Start()
}

function _StartQueuePerfReportJob {
    <#
        Pulls queue-performance aggregate datasets (queue perf, abandon metrics,
        service level) in a background runspace for the current case time window,
        then imports the results into report_queue_perf and refreshes the grid.
    #>
    if (-not (Test-DatabaseInitialized)) {
        [System.Windows.MessageBox]::Show('Case store is offline.', 'Queue Performance')
        return
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    if (-not (Test-CoreInitialized)) {
        [System.Windows.MessageBox]::Show('Genesys Core is not initialized. Check Settings.', 'Queue Performance')
        return
    }

    $headers = Get-StoredHeaders
    if ($null -eq $headers -or $headers.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Connect to Genesys Cloud before pulling queue performance data.', 'Not Connected')
        return
    }

    $range = $null
    try { $range = _GetQueryBoundaryDateTimes } catch {
        [System.Windows.MessageBox]::Show("Invalid date range: $_", 'Queue Performance')
        return
    }
    if ($null -eq $range.Start -or $null -eq $range.End) {
        [System.Windows.MessageBox]::Show('Set a start and end date/time before pulling queue performance data.', 'Queue Performance')
        return
    }

    $startDt   = $range.Start.ToUniversalTime().ToString('o')
    $endDt     = $range.End.ToUniversalTime().ToString('o')

    $cfg         = Get-AppConfig
    $corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
    $catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
    $schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
    $outputRoot  = $cfg.OutputRoot
    $connInfo    = Get-ConnectionInfo
    $region      = if ($null -ne $connInfo -and $connInfo.Region) { $connInfo.Region } else { $cfg.Region }
    $baseUri     = "https://api.$region"
    $caseId      = $case.case_id
    $caseName    = $case.name

    _SetStatus 'Pulling queue performance report…'
    $script:BtnPullQueuePerfReport.IsEnabled = $false
    $script:State.QueuePerfCaseId = $caseId

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $appDir = $script:UIAppDir

    [void]$ps.AddScript({
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $Headers, $BaseUri, $StartDt, $EndDt)
        Set-StrictMode -Version Latest

        Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')) -Force -ErrorAction Stop
        Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
        return (Get-QueuePerformanceReport -StartDateTime $StartDt -EndDateTime $EndDt -Headers $Headers -BaseUri $BaseUri)
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($headers)
    [void]$ps.AddArgument($baseUri)
    [void]$ps.AddArgument($startDt)
    [void]$ps.AddArgument($endDt)

    $asyncResult = $ps.BeginInvoke()

    $script:State.QueuePerfJob      = @{ Ps = $ps; Async = $asyncResult; CaseId = $caseId; CaseName = $caseName }
    $script:State.QueuePerfRunspace = $rs

    $timer          = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(2)
    $script:State.QueuePerfTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        $job = $script:State.QueuePerfJob
        if ($null -eq $job) { $script:State.QueuePerfTimer.Stop(); return }
        if (-not $job.Async.IsCompleted) { return }

        $script:State.QueuePerfTimer.Stop()
        $script:State.QueuePerfTimer = $null

        $folderMap  = $null
        $endFailure = $null
        try {
            $results   = $job.Ps.EndInvoke($job.Async)
            $folderMap = $results | Select-Object -Last 1
        } catch {
            $endFailure = $_
        } finally {
            try { $job.Ps.Dispose() }                               catch {}
            try { $script:State.QueuePerfRunspace.Close() }        catch {}
            try { $script:State.QueuePerfRunspace.Dispose() }      catch {}
            $script:State.QueuePerfJob      = $null
            $script:State.QueuePerfRunspace = $null
            $script:State.QueuePerfCaseId   = ''
        }

        if ($null -ne $endFailure) {
            _SetStatus 'Queue performance pull failed'
            _Dispatch { $script:BtnPullQueuePerfReport.IsEnabled = $true }
            [System.Windows.MessageBox]::Show("Pull failed: $endFailure", 'Queue Performance')
            return
        }

        if ($null -ne $folderMap) {
            try {
                $importStats = Import-QueuePerformanceReport -CaseId $job.CaseId -FolderMap $folderMap
                $summary     = "Loaded $($importStats.RecordCount) queue-interval rows"
                if ($importStats.SkippedCount -gt 0) { $summary += " ($($importStats.SkippedCount) skipped)" }
                if ($folderMap.PartialFailure) { $summary += ' — WARNING: one or more datasets failed to pull; data may be incomplete.' }
                _SetStatus $summary
                _PopulateQueuePerfDivisionFilter
                _RenderQueuePerfGrid
                [System.Windows.MessageBox]::Show($summary, 'Queue Performance Report')
            } catch {
                _SetStatus 'Queue performance import failed'
                [System.Windows.MessageBox]::Show("Import failed: $_", 'Queue Performance')
            }
        } else {
            _SetStatus 'Queue performance pull completed (no data returned)'
        }

        _Dispatch { $script:BtnPullQueuePerfReport.IsEnabled = $true }
    })

    $timer.Start()
}

function _PopulateQueuePerfDivisionFilter {
    <#
        Populates CmbQueuePerfDivision with divisions from ref_divisions for the
        active case.  Preserves the current selection if still valid.
    #>
    if ($null -eq $script:CmbQueuePerfDivision) { return }
    if (-not (Test-DatabaseInitialized))        { return }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId))       { return }

    # Read divisions from the reference table
    $divRows = @()
    try {
        # Re-use the DB helper via Get-ResolvedName — but we need the full list.
        # Query directly via the public Get-QueuePerfRows unique divisions.
        $rows    = @(Get-QueuePerfRows -CaseId $caseId)
        $divRows = $rows |
            Where-Object { $_.division_id -and $_.division_name } |
            Select-Object @{n='DivisionId';e={$_.division_id}}, @{n='Name';e={$_.division_name}} |
            Sort-Object Name -Unique
    } catch {}

    $prevSel = $null
    if ($null -ne $script:CmbQueuePerfDivision.SelectedItem) {
        $prevSel = $script:CmbQueuePerfDivision.SelectedItem.DivisionId
    }

    $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $items.Add([pscustomobject]@{ DivisionId = ''; Name = '(All divisions)' })
    foreach ($d in $divRows) { $items.Add($d) }

    $script:CmbQueuePerfDivision.ItemsSource   = $items
    $script:CmbQueuePerfDivision.DisplayMemberPath = 'Name'
    $script:CmbQueuePerfDivision.SelectedIndex = 0

    # Re-select previously chosen division if still present
    if ($prevSel) {
        for ($i = 1; $i -lt $items.Count; $i++) {
            if ($items[$i].DivisionId -eq $prevSel) {
                $script:CmbQueuePerfDivision.SelectedIndex = $i
                break
            }
        }
    }
}

function _RenderQueuePerfGrid {
    <#
        Reads report_queue_perf rows for the active case (with optional division filter),
        populates the DgQueuePerf DataGrid, and updates the summary bar labels.
    #>
    if (-not (Test-DatabaseInitialized)) { return }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId)) { return }

    # Resolve selected division filter
    $divisionId = ''
    if ($null -ne $script:CmbQueuePerfDivision) {
        $sel = $script:CmbQueuePerfDivision.SelectedItem
        if ($null -ne $sel -and $sel.DivisionId) {
            $divisionId = [string]$sel.DivisionId
        }
    }

    try {
        $rows    = @(Get-QueuePerfRows -CaseId $caseId -DivisionId $divisionId)
        $summary = Get-QueuePerfSummary -CaseId $caseId -DivisionId $divisionId
    } catch {
        _SetStatus "Queue perf read failed: $_"
        return
    }

    # Build observable collection for binding
    $displayRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($r in $rows) {
        $displayRows.Add([pscustomobject]@{
            QueueName       = [string]($r.queue_name)
            DivisionName    = [string]($r.division_name)
            IntervalStart   = [string]($r.interval_start)
            NOffered        = [int]   ($r.n_offered)
            NConnected      = [int]   ($r.n_connected)
            NAbandoned      = [int]   ($r.n_abandoned)
            AbandonRatePct  = [string]("{0:F1}" -f [double]($r.abandon_rate_pct))
            THandleAvgSec   = [string]("{0:F1}" -f [double]($r.t_handle_avg_sec))
            TTalkAvgSec     = [string]("{0:F1}" -f [double]($r.t_talk_avg_sec))
            TAcwAvgSec      = [string]("{0:F1}" -f [double]($r.t_acw_avg_sec))
            NAnsweredIn20   = [int]   ($r.n_answered_in_20)
            NAnsweredIn30   = [int]   ($r.n_answered_in_30)
            ServiceLevelPct = [string]("{0:F1}" -f [double]($r.service_level_pct))
        })
    }
    $script:DgQueuePerf.ItemsSource = $displayRows

    # Update summary bar
    $script:LblQPerfQueues.Text     = [string]($summary.TotalQueues)
    $script:LblQPerfOffered.Text    = [string]($summary.TotalOffered)
    $script:LblQPerfAbandoned.Text  = [string]($summary.TotalAbandoned)
    $script:LblQPerfAbandonPct.Text = "{0:F1}%" -f $summary.AvgAbandonPct
    $script:LblQPerfSLAPct.Text     = "{0:F1}%" -f $summary.AvgSL30sPct
    $script:LblQPerfHandle.Text     = "{0:F1}" -f $summary.AvgHandleSec
}

function _StartAgentPerfReportJob {
    <#
        Pulls agent-performance aggregate datasets in a background runspace for the
        current case time window, then imports the results into report_agent_perf
        and refreshes the grid.
    #>
    if (-not (Test-DatabaseInitialized)) {
        [System.Windows.MessageBox]::Show('Case store is offline.', 'Agent Performance')
        return
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    if (-not (Test-CoreInitialized)) {
        [System.Windows.MessageBox]::Show('Genesys Core is not initialized. Check Settings.', 'Agent Performance')
        return
    }

    $headers = Get-StoredHeaders
    if ($null -eq $headers -or $headers.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Connect to Genesys Cloud before pulling agent performance data.', 'Not Connected')
        return
    }

    $range = $null
    try { $range = _GetQueryBoundaryDateTimes } catch {
        [System.Windows.MessageBox]::Show("Invalid date range: $_", 'Agent Performance')
        return
    }
    if ($null -eq $range.Start -or $null -eq $range.End) {
        [System.Windows.MessageBox]::Show('Set a start and end date/time before pulling agent performance data.', 'Agent Performance')
        return
    }

    $startDt   = $range.Start.ToUniversalTime().ToString('o')
    $endDt     = $range.End.ToUniversalTime().ToString('o')

    $cfg         = Get-AppConfig
    $corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
    $catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
    $schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
    $outputRoot  = $cfg.OutputRoot
    $connInfo    = Get-ConnectionInfo
    $region      = if ($null -ne $connInfo -and $connInfo.Region) { $connInfo.Region } else { $cfg.Region }
    $baseUri     = "https://api.$region"
    $caseId      = $case.case_id
    $caseName    = $case.name

    _SetStatus 'Pulling agent performance report…'
    $script:BtnPullAgentPerfReport.IsEnabled = $false
    $script:State.AgentPerfCaseId = $caseId

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $appDir = $script:UIAppDir

    [void]$ps.AddScript({
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $Headers, $BaseUri, $StartDt, $EndDt)
        Set-StrictMode -Version Latest

        Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')) -Force -ErrorAction Stop
        Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
        return (Get-AgentPerformanceReport -StartDateTime $StartDt -EndDateTime $EndDt -Headers $Headers -BaseUri $BaseUri)
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($headers)
    [void]$ps.AddArgument($baseUri)
    [void]$ps.AddArgument($startDt)
    [void]$ps.AddArgument($endDt)

    $asyncResult = $ps.BeginInvoke()

    $script:State.AgentPerfJob      = @{ Ps = $ps; Async = $asyncResult; CaseId = $caseId; CaseName = $caseName }
    $script:State.AgentPerfRunspace = $rs

    $timer          = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(2)
    $script:State.AgentPerfTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        $job = $script:State.AgentPerfJob
        if ($null -eq $job) { $script:State.AgentPerfTimer.Stop(); return }
        if (-not $job.Async.IsCompleted) { return }

        $script:State.AgentPerfTimer.Stop()
        $script:State.AgentPerfTimer = $null

        $folderMap  = $null
        $endFailure = $null
        try {
            $results   = $job.Ps.EndInvoke($job.Async)
            $folderMap = $results | Select-Object -Last 1
        } catch {
            $endFailure = $_
        } finally {
            try { $job.Ps.Dispose() }                                catch {}
            try { $script:State.AgentPerfRunspace.Close() }         catch {}
            try { $script:State.AgentPerfRunspace.Dispose() }       catch {}
            $script:State.AgentPerfJob      = $null
            $script:State.AgentPerfRunspace = $null
            $script:State.AgentPerfCaseId   = ''
        }

        if ($null -ne $endFailure) {
            _SetStatus 'Agent performance pull failed'
            _Dispatch { $script:BtnPullAgentPerfReport.IsEnabled = $true }
            [System.Windows.MessageBox]::Show("Pull failed: $endFailure", 'Agent Performance')
            return
        }

        if ($null -ne $folderMap) {
            try {
                $importStats = Import-AgentPerformanceReport -CaseId $job.CaseId -FolderMap $folderMap
                $summary     = "Loaded $($importStats.RecordCount) agent rows"
                if ($importStats.SkippedCount -gt 0) { $summary += " ($($importStats.SkippedCount) skipped)" }
                if ($folderMap.PartialFailure) { $summary += ' — WARNING: one or more datasets failed to pull; data may be incomplete.' }
                _SetStatus $summary
                _PopulateAgentPerfDivisionFilter
                _RenderAgentPerfGrid
                [System.Windows.MessageBox]::Show($summary, 'Agent Performance Report')
            } catch {
                _SetStatus 'Agent performance import failed'
                [System.Windows.MessageBox]::Show("Import failed: $_", 'Agent Performance')
            }
        } else {
            _SetStatus 'Agent performance pull completed (no data returned)'
        }

        _Dispatch { $script:BtnPullAgentPerfReport.IsEnabled = $true }
    })

    $timer.Start()
}

function _PopulateAgentPerfDivisionFilter {
    <#
        Populates CmbAgentPerfDivision with divisions from report_agent_perf for the
        active case.  Preserves the current selection if still valid.
    #>
    if ($null -eq $script:CmbAgentPerfDivision) { return }
    if (-not (Test-DatabaseInitialized))         { return }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId))        { return }

    $divRows = @()
    try {
        $rows    = @(Get-AgentPerfRows -CaseId $caseId)
        $divRows = $rows |
            Where-Object { $_.division_id -and $_.division_name } |
            Select-Object @{n='DivisionId';e={$_.division_id}}, @{n='Name';e={$_.division_name}} |
            Sort-Object Name -Unique
    } catch {}

    $prevSel = $null
    if ($null -ne $script:CmbAgentPerfDivision.SelectedItem) {
        $prevSel = $script:CmbAgentPerfDivision.SelectedItem.DivisionId
    }

    $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $items.Add([pscustomobject]@{ DivisionId = ''; Name = '(All divisions)' })
    foreach ($d in $divRows) { $items.Add($d) }

    $script:CmbAgentPerfDivision.ItemsSource       = $items
    $script:CmbAgentPerfDivision.DisplayMemberPath = 'Name'
    $script:CmbAgentPerfDivision.SelectedIndex     = 0

    if ($prevSel) {
        for ($i = 1; $i -lt $items.Count; $i++) {
            if ($items[$i].DivisionId -eq $prevSel) {
                $script:CmbAgentPerfDivision.SelectedIndex = $i
                break
            }
        }
    }
}

function _RenderAgentPerfGrid {
    <#
        Reads report_agent_perf rows for the active case (with optional division filter),
        populates the DgAgentPerf DataGrid, and updates the summary bar labels.
        Rows with talk_ratio_pct < 50 % or acw_ratio_pct > 30 % are flagged with ⚠.
    #>
    if (-not (Test-DatabaseInitialized)) { return }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId)) { return }

    $divisionId = ''
    if ($null -ne $script:CmbAgentPerfDivision) {
        $sel = $script:CmbAgentPerfDivision.SelectedItem
        if ($null -ne $sel -and $sel.DivisionId) {
            $divisionId = [string]$sel.DivisionId
        }
    }

    try {
        $rows    = @(Get-AgentPerfRows    -CaseId $caseId -DivisionId $divisionId)
        $summary = Get-AgentPerfSummary   -CaseId $caseId -DivisionId $divisionId
    } catch {
        _SetStatus "Agent perf read failed: $_"
        return
    }

    $displayRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($r in $rows) {
        $talkPct = [double]($r.talk_ratio_pct)
        $acwPct  = [double]($r.acw_ratio_pct)
        # ⚠ flag: talk ratio < 50 % suggests long ACW or idle time relative to handle time;
        # ACW ratio > 30 % suggests after-call work is consuming an unusually large share of handle time.
        $flag    = if ($talkPct -lt 50 -or $acwPct -gt 30) { '⚠' } else { '' }
        $displayRows.Add([pscustomobject]@{
            Flag          = $flag
            UserName      = [string]($r.user_name)
            DivisionName  = [string]($r.division_name)
            Department    = [string]($r.department)
            QueueIds      = [string]($r.queue_ids)
            NConnected    = [int]   ($r.n_connected)
            NOffered      = [int]   ($r.n_offered)
            THandleAvgSec = [string]("{0:F1}" -f [double]($r.t_handle_avg_sec))
            TTalkAvgSec   = [string]("{0:F1}" -f [double]($r.t_talk_avg_sec))
            TAcwAvgSec    = [string]("{0:F1}" -f [double]($r.t_acw_avg_sec))
            TOnQueueSec   = [string]("{0:F1}" -f [double]($r.t_on_queue_sec))
            TOffQueueSec  = [string]("{0:F1}" -f [double]($r.t_off_queue_sec))
            TIdleSec      = [string]("{0:F1}" -f [double]($r.t_idle_sec))
            TalkRatioPct  = [string]("{0:F1}" -f $talkPct)
            AcwRatioPct   = [string]("{0:F1}" -f $acwPct)
            IdleRatioPct  = [string]("{0:F1}" -f [double]($r.idle_ratio_pct))
        })
    }
    $script:DgAgentPerf.ItemsSource = $displayRows

    # Update summary bar
    $script:LblAPerfAgents.Text    = [string]($summary.TotalAgents)
    $script:LblAPerfConnected.Text = [string]($summary.TotalConnected)
    $script:LblAPerfHandle.Text    = "{0:F1}" -f $summary.AvgHandleSec
    $script:LblAPerfTalkPct.Text   = "{0:F1}%" -f $summary.AvgTalkPct
    $script:LblAPerfAcwPct.Text    = "{0:F1}%" -f $summary.AvgAcwPct
    $script:LblAPerfIdlePct.Text   = "{0:F1}%" -f $summary.AvgIdlePct
}

function _EnsureTransferTypeFilter {
    if ($null -eq $script:CmbTransferType) { return }
    if ($null -ne $script:CmbTransferType.ItemsSource) { return }

    $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $items.Add([pscustomobject]@{ TransferType = '';        Name = '(All types)' })
    $items.Add([pscustomobject]@{ TransferType = 'blind';   Name = 'Blind' })
    $items.Add([pscustomobject]@{ TransferType = 'consult'; Name = 'Consult' })

    $script:CmbTransferType.ItemsSource       = $items
    $script:CmbTransferType.DisplayMemberPath = 'Name'
    $script:CmbTransferType.SelectedIndex     = 0
}

function _ClearTransferGrid {
    $empty = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    if ($null -ne $script:DgTransferFlows)        { $script:DgTransferFlows.ItemsSource = $empty }
    if ($null -ne $script:DgTransferDestinations) { $script:DgTransferDestinations.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgTransferChains)       { $script:DgTransferChains.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:LblXferFlows)           { $script:LblXferFlows.Text = '—' }
    if ($null -ne $script:LblXferTransfers)       { $script:LblXferTransfers.Text = '—' }
    if ($null -ne $script:LblXferBlind)           { $script:LblXferBlind.Text = '—' }
    if ($null -ne $script:LblXferConsult)         { $script:LblXferConsult.Text = '—' }
    if ($null -ne $script:LblXferBlindPct)        { $script:LblXferBlindPct.Text = '—' }
    if ($null -ne $script:LblXferMultiHop)        { $script:LblXferMultiHop.Text = '—' }
}

function _StartTransferReportJob {
    <#
        Pulls transfer aggregate data in a background runspace for the current
        case time window, then imports local chain intelligence from the case
        store and refreshes the Transfer & Escalation tab.
    #>
    if (-not (Test-DatabaseInitialized)) {
        [System.Windows.MessageBox]::Show('Case store is offline.', 'Transfer & Escalation')
        return
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    if (-not (Test-CoreInitialized)) {
        [System.Windows.MessageBox]::Show('Genesys Core is not initialized. Check Settings.', 'Transfer & Escalation')
        return
    }

    $headers = Get-StoredHeaders
    if ($null -eq $headers -or $headers.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Connect to Genesys Cloud before pulling transfer data.', 'Not Connected')
        return
    }

    $range = $null
    try { $range = _GetQueryBoundaryDateTimes } catch {
        [System.Windows.MessageBox]::Show("Invalid date range: $_", 'Transfer & Escalation')
        return
    }
    if ($null -eq $range.Start -or $null -eq $range.End) {
        [System.Windows.MessageBox]::Show('Set a start and end date/time before pulling transfer data.', 'Transfer & Escalation')
        return
    }

    $startDt   = $range.Start.ToUniversalTime().ToString('o')
    $endDt     = $range.End.ToUniversalTime().ToString('o')

    $cfg         = Get-AppConfig
    $corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
    $catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
    $schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
    $outputRoot  = $cfg.OutputRoot
    $connInfo    = Get-ConnectionInfo
    $region      = if ($null -ne $connInfo -and $connInfo.Region) { $connInfo.Region } else { $cfg.Region }
    $baseUri     = "https://api.$region"
    $caseId      = $case.case_id
    $caseName    = $case.name

    _SetStatus 'Pulling transfer report...'
    $script:BtnPullTransferReport.IsEnabled = $false
    $script:State.TransferCaseId = $caseId

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $appDir = $script:UIAppDir

    [void]$ps.AddScript({
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $Headers, $BaseUri, $StartDt, $EndDt)
        Set-StrictMode -Version Latest

        Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')) -Force -ErrorAction Stop
        Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
        return (Get-TransferReport -StartDateTime $StartDt -EndDateTime $EndDt -Headers $Headers -BaseUri $BaseUri)
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($headers)
    [void]$ps.AddArgument($baseUri)
    [void]$ps.AddArgument($startDt)
    [void]$ps.AddArgument($endDt)

    $asyncResult = $ps.BeginInvoke()

    $script:State.TransferJob      = @{ Ps = $ps; Async = $asyncResult; CaseId = $caseId; CaseName = $caseName }
    $script:State.TransferRunspace = $rs

    $timer          = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(2)
    $script:State.TransferTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        $job = $script:State.TransferJob
        if ($null -eq $job) { $script:State.TransferTimer.Stop(); return }
        if (-not $job.Async.IsCompleted) { return }

        $script:State.TransferTimer.Stop()
        $script:State.TransferTimer = $null

        $folderMap  = $null
        $endFailure = $null
        try {
            $results   = $job.Ps.EndInvoke($job.Async)
            $folderMap = $results | Select-Object -Last 1
        } catch {
            $endFailure = $_
        } finally {
            try { $job.Ps.Dispose() }                            catch {}
            try { $script:State.TransferRunspace.Close() }       catch {}
            try { $script:State.TransferRunspace.Dispose() }     catch {}
            $script:State.TransferJob      = $null
            $script:State.TransferRunspace = $null
            $script:State.TransferCaseId   = ''
        }

        if ($null -ne $endFailure) {
            _SetStatus 'Transfer report pull failed'
            _Dispatch { $script:BtnPullTransferReport.IsEnabled = $true }
            [System.Windows.MessageBox]::Show("Pull failed: $endFailure", 'Transfer & Escalation')
            return
        }

        if ($null -ne $folderMap) {
            try {
                $importStats = Import-TransferReport -CaseId $job.CaseId -FolderMap $folderMap
                $summary     = "Loaded $($importStats.RecordCount) transfer flow rows and $($importStats.ChainCount) chain rows"
                if ($importStats.SkippedCount -gt 0) { $summary += " ($($importStats.SkippedCount) skipped)" }
                if ($folderMap.PartialFailure) { $summary += ' - WARNING: aggregate dataset failed; percentages use local chain totals.' }
                _SetStatus $summary
                _RenderTransferGrid
                [System.Windows.MessageBox]::Show($summary, 'Transfer & Escalation Report')
            } catch {
                _SetStatus 'Transfer report import failed'
                [System.Windows.MessageBox]::Show("Import failed: $_", 'Transfer & Escalation')
            }
        } else {
            _SetStatus 'Transfer report pull completed (no data returned)'
        }

        _Dispatch { $script:BtnPullTransferReport.IsEnabled = $true }
    })

    $timer.Start()
}

function _RenderTransferGrid {
    <#
        Reads transfer flow and chain rows for the active case, applies the
        blind/consult filter to the flow grids, and updates summary labels.
    #>
    _EnsureTransferTypeFilter
    if (-not (Test-DatabaseInitialized)) { _ClearTransferGrid; return }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId)) { _ClearTransferGrid; return }

    $transferType = ''
    if ($null -ne $script:CmbTransferType) {
        $sel = $script:CmbTransferType.SelectedItem
        if ($null -ne $sel -and $sel.TransferType) {
            $transferType = [string]$sel.TransferType
        }
    }

    try {
        $flows  = @(Get-TransferFlowRows  -CaseId $caseId -TransferType $transferType)
        $chains = @(Get-TransferChainRows -CaseId $caseId -MinHops 2)
        $summary = Get-TransferSummary -CaseId $caseId
    } catch {
        _SetStatus "Transfer report read failed: $_"
        return
    }

    $flowRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($r in $flows) {
        $flowRows.Add([pscustomobject]@{
            QueueNameFrom     = [string]($r.queue_name_from)
            QueueNameTo       = [string]($r.queue_name_to)
            TransferType      = [string]($r.transfer_type)
            NTransfers        = [int]   ($r.n_transfers)
            PctOfTotalOffered = [string]("{0:F1}" -f [double]($r.pct_of_total_offered))
        })
    }
    $script:DgTransferFlows.ItemsSource = $flowRows

    $destAgg = @{}
    foreach ($r in $flows) {
        $dest = [string]($r.queue_name_to)
        if ([string]::IsNullOrWhiteSpace($dest)) { $dest = [string]($r.queue_id_to) }
        if ([string]::IsNullOrWhiteSpace($dest)) { $dest = '(unknown)' }
        if (-not $destAgg.ContainsKey($dest)) {
            $destAgg[$dest] = @{ Destination = $dest; Transfers = 0; Percent = 0.0 }
        }
        $destAgg[$dest].Transfers += [int]($r.n_transfers)
        $destAgg[$dest].Percent   += [double]($r.pct_of_total_offered)
    }

    $destRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($d in @($destAgg.Values | Sort-Object @{ Expression = { $_.Transfers }; Descending = $true }, Destination | Select-Object -First 10)) {
        $destRows.Add([pscustomobject]@{
            Destination       = [string]$d.Destination
            NTransfers        = [int]$d.Transfers
            PctOfTotalOffered = [string]("{0:F1}" -f [double]$d.Percent)
        })
    }
    $script:DgTransferDestinations.ItemsSource = $destRows

    $chainRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($c in $chains) {
        $chainRows.Add([pscustomobject]@{
            ConversationId       = [string]($c.conversation_id)
            TransferSequence     = [string]($c.transfer_sequence)
            HopCount             = [int]   ($c.hop_count)
            FinalQueueName       = [string]($c.final_queue_name)
            FinalDisconnectType  = [string]($c.final_disconnect_type)
            HasBlindTransfer     = if ([int]($c.has_blind_transfer) -eq 1) { 'Yes' } else { '' }
            HasConsultTransfer   = if ([int]($c.has_consult_transfer) -eq 1) { 'Yes' } else { '' }
        })
    }
    $script:DgTransferChains.ItemsSource = $chainRows

    $script:LblXferFlows.Text     = [string]($summary.TotalFlows)
    $script:LblXferTransfers.Text = [string]($summary.TotalTransfers)
    $script:LblXferBlind.Text     = [string]($summary.BlindTransfers)
    $script:LblXferConsult.Text   = [string]($summary.ConsultTransfers)
    $script:LblXferBlindPct.Text  = "{0:F1}%" -f $summary.BlindPct
    $script:LblXferMultiHop.Text  = [string]($summary.MultiHopChains)
}

function _OpenTransferChainConversation {
    if ($null -eq $script:DgTransferChains) { return }
    $sel = $script:DgTransferChains.SelectedItem
    if ($null -eq $sel) { return }
    $convId = [string]$sel.ConversationId
    if ([string]::IsNullOrWhiteSpace($convId)) { return }

    $script:State.DataSource = 'database'
    _LoadDrilldown -ConversationId $convId
    if ($null -ne $script:TabWorkspace -and $null -ne $script:TabDrilldownWorkspace) {
        $script:TabWorkspace.SelectedItem = $script:TabDrilldownWorkspace
    }
}

function _EnsureFlowTypeFilter {
    if ($null -eq $script:CmbFlowType) { return }
    if ($null -ne $script:CmbFlowType.ItemsSource) { return }

    $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $items.Add([pscustomobject]@{ FlowType = '';            Name = '(All flow types)' })
    $items.Add([pscustomobject]@{ FlowType = 'inboundcall'; Name = 'Inbound call' })
    $items.Add([pscustomobject]@{ FlowType = 'inqueuecall'; Name = 'In-queue call' })
    $items.Add([pscustomobject]@{ FlowType = 'bot';         Name = 'Bot' })
    $items.Add([pscustomobject]@{ FlowType = 'workflow';    Name = 'Workflow' })
    $items.Add([pscustomobject]@{ FlowType = 'outboundcall';Name = 'Outbound call' })
    $items.Add([pscustomobject]@{ FlowType = 'securecall';  Name = 'Secure call' })

    $script:CmbFlowType.ItemsSource       = $items
    $script:CmbFlowType.DisplayMemberPath = 'Name'
    $script:CmbFlowType.SelectedIndex     = 0
}

function _ClearFlowContainmentGrid {
    if ($null -ne $script:DgFlowPerf)       { $script:DgFlowPerf.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgFlowMilestones) { $script:DgFlowMilestones.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgFlowQueues)     { $script:DgFlowQueues.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:LblFlowTotal)     { $script:LblFlowTotal.Text = '—' }
    if ($null -ne $script:LblFlowEntries)   { $script:LblFlowEntries.Text = '—' }
    if ($null -ne $script:LblFlowContainment) { $script:LblFlowContainment.Text = '—' }
    if ($null -ne $script:LblFlowFailures)  { $script:LblFlowFailures.Text = '—' }
    if ($null -ne $script:LblFlowLowContainment) { $script:LblFlowLowContainment.Text = '—' }
}

function _StartFlowContainmentReportJob {
    <#
        Pulls flow aggregate and flow reference data in a background runspace,
        imports containment metrics into the case store, and refreshes the
        Flow & IVR tab.
    #>
    if (-not (Test-DatabaseInitialized)) {
        [System.Windows.MessageBox]::Show('Case store is offline.', 'Flow & IVR')
        return
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    if (-not (Test-CoreInitialized)) {
        [System.Windows.MessageBox]::Show('Genesys Core is not initialized. Check Settings.', 'Flow & IVR')
        return
    }

    $headers = Get-StoredHeaders
    if ($null -eq $headers -or $headers.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Connect to Genesys Cloud before pulling flow data.', 'Not Connected')
        return
    }

    $range = $null
    try { $range = _GetQueryBoundaryDateTimes } catch {
        [System.Windows.MessageBox]::Show("Invalid date range: $_", 'Flow & IVR')
        return
    }
    if ($null -eq $range.Start -or $null -eq $range.End) {
        [System.Windows.MessageBox]::Show('Set a start and end date/time before pulling flow data.', 'Flow & IVR')
        return
    }

    $startDt = $range.Start.ToUniversalTime().ToString('o')
    $endDt   = $range.End.ToUniversalTime().ToString('o')

    $cfg         = Get-AppConfig
    $corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
    $catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
    $schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
    $outputRoot  = $cfg.OutputRoot
    $connInfo    = Get-ConnectionInfo
    $region      = if ($null -ne $connInfo -and $connInfo.Region) { $connInfo.Region } else { $cfg.Region }
    $baseUri     = "https://api.$region"
    $caseId      = $case.case_id
    $caseName    = $case.name

    _SetStatus 'Pulling flow containment report...'
    if ($null -ne $script:BtnPullFlowContainmentReport) {
        $script:BtnPullFlowContainmentReport.IsEnabled = $false
    }
    $script:State.FlowContainmentCaseId = $caseId

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $appDir = $script:UIAppDir

    [void]$ps.AddScript({
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $Headers, $BaseUri, $StartDt, $EndDt)
        Set-StrictMode -Version Latest

        Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')) -Force -ErrorAction Stop
        Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
        return (Get-FlowContainmentReport -StartDateTime $StartDt -EndDateTime $EndDt -Headers $Headers -BaseUri $BaseUri)
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($headers)
    [void]$ps.AddArgument($baseUri)
    [void]$ps.AddArgument($startDt)
    [void]$ps.AddArgument($endDt)

    $asyncResult = $ps.BeginInvoke()

    $script:State.FlowContainmentJob      = @{ Ps = $ps; Async = $asyncResult; CaseId = $caseId; CaseName = $caseName }
    $script:State.FlowContainmentRunspace = $rs

    $timer          = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(2)
    $script:State.FlowContainmentTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        $job = $script:State.FlowContainmentJob
        if ($null -eq $job) { $script:State.FlowContainmentTimer.Stop(); return }
        if (-not $job.Async.IsCompleted) { return }

        $script:State.FlowContainmentTimer.Stop()
        $script:State.FlowContainmentTimer = $null

        $folderMap  = $null
        $endFailure = $null
        try {
            $results   = $job.Ps.EndInvoke($job.Async)
            $folderMap = $results | Select-Object -Last 1
        } catch {
            $endFailure = $_
        } finally {
            try { $job.Ps.Dispose() }                                  catch {}
            try { $script:State.FlowContainmentRunspace.Close() }       catch {}
            try { $script:State.FlowContainmentRunspace.Dispose() }     catch {}
            $script:State.FlowContainmentJob      = $null
            $script:State.FlowContainmentRunspace = $null
            $script:State.FlowContainmentCaseId   = ''
        }

        if ($null -ne $endFailure) {
            _SetStatus 'Flow containment report pull failed'
            _Dispatch { if ($null -ne $script:BtnPullFlowContainmentReport) { $script:BtnPullFlowContainmentReport.IsEnabled = $true } }
            [System.Windows.MessageBox]::Show("Pull failed: $endFailure", 'Flow & IVR')
            return
        }

        if ($null -ne $folderMap) {
            try {
                $importStats = Import-FlowContainmentReport -CaseId $job.CaseId -FolderMap $folderMap
                $summary     = "Loaded $($importStats.RecordCount) flow rows and $($importStats.MilestoneCount) milestone rows"
                if ($importStats.SkippedCount -gt 0) { $summary += " ($($importStats.SkippedCount) skipped)" }
                if ($folderMap.PartialFailure) { $summary += ' - WARNING: one or more flow datasets failed.' }
                _SetStatus $summary
                _RenderFlowContainmentGrid
                [System.Windows.MessageBox]::Show($summary, 'Flow & IVR Report')
            } catch {
                _SetStatus 'Flow containment report import failed'
                [System.Windows.MessageBox]::Show("Import failed: $_", 'Flow & IVR')
            }
        } else {
            _SetStatus 'Flow containment report pull completed (no data returned)'
        }

        _Dispatch { if ($null -ne $script:BtnPullFlowContainmentReport) { $script:BtnPullFlowContainmentReport.IsEnabled = $true } }
    })

    $timer.Start()
}

function _RenderFlowContainmentGrid {
    <#
        Reads flow containment rows for the active case, applies the flow-type
        filter, updates the summary bar, and refreshes selected-flow details.
    #>
    _EnsureFlowTypeFilter
    if (-not (Test-DatabaseInitialized)) { _ClearFlowContainmentGrid; return }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId)) { _ClearFlowContainmentGrid; return }

    $flowType = ''
    if ($null -ne $script:CmbFlowType) {
        $sel = $script:CmbFlowType.SelectedItem
        if ($null -ne $sel -and $sel.FlowType) {
            $flowType = [string]$sel.FlowType
        }
    }

    try {
        $rows    = @(Get-FlowPerfRows -CaseId $caseId -FlowType $flowType)
        $summary = Get-FlowContainmentSummary -CaseId $caseId
    } catch {
        _SetStatus "Flow containment read failed: $_"
        return
    }

    $previousFlowId = ''
    if ($null -ne $script:DgFlowPerf -and $null -ne $script:DgFlowPerf.SelectedItem) {
        $previousFlowId = [string]$script:DgFlowPerf.SelectedItem.FlowId
    }

    $displayRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($r in $rows) {
        $containPct = [double]($r.containment_rate_pct)
        $failPct    = [double]($r.failure_rate_pct)
        $displayRows.Add([pscustomobject]@{
            Flag               = if ($containPct -lt 50 -or $failPct -gt 25) { '!' } else { '' }
            FlowId             = [string]($r.flow_id)
            FlowName           = [string]($r.flow_name)
            FlowType           = [string]($r.flow_type)
            DivisionName       = [string]($r.division_name)
            NFlow              = [int]   ($r.n_flow)
            NSuccess           = [int]   ($r.n_flow_outcome_success)
            NFailed            = [int]   ($r.n_flow_outcome_failed)
            NMilestone         = [int]   ($r.n_flow_milestone_hit)
            ContainmentRatePct = [string]("{0:F1}" -f $containPct)
            FailureRatePct     = [string]("{0:F1}" -f $failPct)
        })
    }

    if ($null -ne $script:DgFlowPerf) {
        $script:DgFlowPerf.ItemsSource = $displayRows
        if ($displayRows.Count -gt 0) {
            $target = $displayRows[0]
            if ($previousFlowId) {
                foreach ($row in $displayRows) {
                    if ($row.FlowId -eq $previousFlowId) { $target = $row; break }
                }
            }
            $script:DgFlowPerf.SelectedItem = $target
            try { $script:DgFlowPerf.ScrollIntoView($target) } catch {}
        }
    }

    if ($null -ne $script:LblFlowTotal)          { $script:LblFlowTotal.Text = [string]($summary.TotalFlows) }
    if ($null -ne $script:LblFlowEntries)        { $script:LblFlowEntries.Text = [string]($summary.TotalEntries) }
    if ($null -ne $script:LblFlowContainment)    { $script:LblFlowContainment.Text = "{0:F1}%" -f $summary.AvgContainmentPct }
    if ($null -ne $script:LblFlowFailures)       { $script:LblFlowFailures.Text = "{0:F1}%" -f $summary.AvgFailurePct }
    if ($null -ne $script:LblFlowLowContainment) { $script:LblFlowLowContainment.Text = [string]($summary.LowContainmentFlows) }

    _RenderSelectedFlowDetail
}

function _RenderSelectedFlowDetail {
    if (-not (Test-DatabaseInitialized)) {
        if ($null -ne $script:DgFlowMilestones) { $script:DgFlowMilestones.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        if ($null -ne $script:DgFlowQueues)     { $script:DgFlowQueues.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        return
    }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId)) {
        if ($null -ne $script:DgFlowMilestones) { $script:DgFlowMilestones.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        if ($null -ne $script:DgFlowQueues)     { $script:DgFlowQueues.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        return
    }
    if ($null -eq $script:DgFlowPerf -or $null -eq $script:DgFlowPerf.SelectedItem) {
        if ($null -ne $script:DgFlowMilestones) { $script:DgFlowMilestones.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        if ($null -ne $script:DgFlowQueues)     { $script:DgFlowQueues.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        return
    }

    $sel      = $script:DgFlowPerf.SelectedItem
    $flowId   = [string]$sel.FlowId
    $flowName = [string]$sel.FlowName

    try {
        $milestones = @(Get-FlowMilestoneRows -CaseId $caseId -FlowId $flowId)
        $queues     = @(Get-FlowQueueRouteRows -CaseId $caseId -FlowId $flowId -FlowName $flowName)
    } catch {
        _SetStatus "Flow detail read failed: $_"
        return
    }

    $milestoneRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($m in $milestones) {
        $milestoneRows.Add([pscustomobject]@{
            MilestoneName = [string]($m.milestone_name)
            NHit          = [int]   ($m.n_hit)
            PctOfEntries  = [string]("{0:F1}" -f [double]($m.pct_of_entries))
        })
    }
    if ($null -ne $script:DgFlowMilestones) { $script:DgFlowMilestones.ItemsSource = $milestoneRows }

    $queueRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($q in $queues) {
        $queueRows.Add([pscustomobject]@{
            QueueName         = [string]($q.QueueName)
            ConversationCount = [int]   ($q.ConversationCount)
        })
    }
    if ($null -ne $script:DgFlowQueues) { $script:DgFlowQueues.ItemsSource = $queueRows }
}

function _ClearWrapupGrid {
    if ($null -ne $script:DgWrapupCodes)    { $script:DgWrapupCodes.ItemsSource    = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgWrapupByQueue)  { $script:DgWrapupByQueue.ItemsSource  = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgWrapupByHour)   { $script:DgWrapupByHour.ItemsSource   = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgWrapupInsights) { $script:DgWrapupInsights.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgWrapupCrossRef) { $script:DgWrapupCrossRef.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:LblWrapupCodes)     { $script:LblWrapupCodes.Text     = '-' }
    if ($null -ne $script:LblWrapupConnected) { $script:LblWrapupConnected.Text = '-' }
    if ($null -ne $script:LblWrapupQueues)    { $script:LblWrapupQueues.Text    = '-' }
    if ($null -ne $script:LblWrapupTopReason) { $script:LblWrapupTopReason.Text = '-' }
}

function _StartWrapupDistributionReportJob {
    <#
        Pulls hourly wrapup-code distribution data in a background runspace,
        imports it into the case store, and refreshes the Contact Reasons tab.
    #>
    if (-not (Test-DatabaseInitialized)) {
        [System.Windows.MessageBox]::Show('Case store is offline.', 'Contact Reasons')
        return
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    if (-not (Test-CoreInitialized)) {
        [System.Windows.MessageBox]::Show('Genesys Core is not initialized. Check Settings.', 'Contact Reasons')
        return
    }

    $headers = Get-StoredHeaders
    if ($null -eq $headers -or $headers.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Connect to Genesys Cloud before pulling wrapup distribution data.', 'Not Connected')
        return
    }

    $range = $null
    try { $range = _GetQueryBoundaryDateTimes } catch {
        [System.Windows.MessageBox]::Show("Invalid date range: $_", 'Contact Reasons')
        return
    }
    if ($null -eq $range.Start -or $null -eq $range.End) {
        [System.Windows.MessageBox]::Show('Set a start and end date/time before pulling wrapup distribution data.', 'Contact Reasons')
        return
    }

    $startDt = $range.Start.ToUniversalTime().ToString('o')
    $endDt   = $range.End.ToUniversalTime().ToString('o')

    $cfg         = Get-AppConfig
    $corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
    $catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
    $schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
    $outputRoot  = $cfg.OutputRoot
    $connInfo    = Get-ConnectionInfo
    $region      = if ($null -ne $connInfo -and $connInfo.Region) { $connInfo.Region } else { $cfg.Region }
    $baseUri     = "https://api.$region"
    $caseId      = $case.case_id
    $caseName    = $case.name

    _SetStatus 'Pulling wrapup distribution report...'
    if ($null -ne $script:BtnPullWrapupReport) {
        $script:BtnPullWrapupReport.IsEnabled = $false
    }
    $script:State.WrapupCaseId = $caseId

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $appDir = $script:UIAppDir

    [void]$ps.AddScript({
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $Headers, $BaseUri, $StartDt, $EndDt)
        Set-StrictMode -Version Latest

        Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')) -Force -ErrorAction Stop
        Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
        return (Get-WrapupDistributionReport -StartDateTime $StartDt -EndDateTime $EndDt -Headers $Headers -BaseUri $BaseUri)
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($headers)
    [void]$ps.AddArgument($baseUri)
    [void]$ps.AddArgument($startDt)
    [void]$ps.AddArgument($endDt)

    $asyncResult = $ps.BeginInvoke()

    $script:State.WrapupJob      = @{ Ps = $ps; Async = $asyncResult; CaseId = $caseId; CaseName = $caseName }
    $script:State.WrapupRunspace = $rs

    $timer          = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(2)
    $script:State.WrapupTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        $job = $script:State.WrapupJob
        if ($null -eq $job) { $script:State.WrapupTimer.Stop(); return }
        if (-not $job.Async.IsCompleted) { return }

        $script:State.WrapupTimer.Stop()
        $script:State.WrapupTimer = $null

        $folderMap  = $null
        $endFailure = $null
        try {
            $results   = $job.Ps.EndInvoke($job.Async)
            $folderMap = $results | Select-Object -Last 1
        } catch {
            $endFailure = $_
        } finally {
            try { $job.Ps.Dispose() }                         catch {}
            try { $script:State.WrapupRunspace.Close() }       catch {}
            try { $script:State.WrapupRunspace.Dispose() }     catch {}
            $script:State.WrapupJob      = $null
            $script:State.WrapupRunspace = $null
            $script:State.WrapupCaseId   = ''
        }

        if ($null -ne $endFailure) {
            _SetStatus 'Wrapup distribution report pull failed'
            _Dispatch { if ($null -ne $script:BtnPullWrapupReport) { $script:BtnPullWrapupReport.IsEnabled = $true } }
            [System.Windows.MessageBox]::Show("Pull failed: $endFailure", 'Contact Reasons')
            return
        }

        if ($null -ne $folderMap) {
            try {
                $importStats = Import-WrapupDistributionReport -CaseId $job.CaseId -FolderMap $folderMap
                $summary     = "Loaded $($importStats.RecordCount) wrapup rows and $($importStats.HourRecordCount) hourly rows"
                if ($importStats.SkippedCount -gt 0) { $summary += " ($($importStats.SkippedCount) skipped)" }
                if ($folderMap.PartialFailure) { $summary += ' - WARNING: one or more wrapup datasets failed.' }
                _SetStatus $summary
                _RenderWrapupGrid
                [System.Windows.MessageBox]::Show($summary, 'Contact Reasons Report')
            } catch {
                _SetStatus 'Wrapup distribution report import failed'
                [System.Windows.MessageBox]::Show("Import failed: $_", 'Contact Reasons')
            }
        } else {
            _SetStatus 'Wrapup distribution report pull completed (no data returned)'
        }

        _Dispatch { if ($null -ne $script:BtnPullWrapupReport) { $script:BtnPullWrapupReport.IsEnabled = $true } }
    })

    $timer.Start()
}

function _GetWrapupHeatBrush {
    param([int]$Value, [int]$Max)
    if ($Value -le 0 -or $Max -le 0) { return '#0F161B' }
    $ratio = $Value / [double]$Max
    if ($ratio -lt 0.25) { return '#173238' }
    if ($ratio -lt 0.50) { return '#1E5361' }
    if ($ratio -lt 0.75) { return '#2B7A78' }
    return '#D6A33D'
}

function _RenderWrapupGrid {
    <#
        Reads contact reason rows for the active case, updates summary KPIs,
        renders the hourly heat-map table, and refreshes selected-code detail.
    #>
    if (-not (Test-DatabaseInitialized)) { _ClearWrapupGrid; return }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId)) { _ClearWrapupGrid; return }

    try {
        $rows     = @(Get-WrapupCodeRows -CaseId $caseId)
        $summary  = Get-WrapupSummary -CaseId $caseId
        $hourRows = @(Get-WrapupByHourRows -CaseId $caseId -TopCodes 10)
        $insights = @(Get-WrapupConcentrationInsights -CaseId $caseId -Top 5)
        $crossRef = @(Get-WrapupHandleTimeCrossRef -CaseId $caseId -TopCodes 10)
    } catch {
        _SetStatus "Wrapup report read failed: $_"
        return
    }

    $previousCodeId = ''
    if ($null -ne $script:DgWrapupCodes -and $null -ne $script:DgWrapupCodes.SelectedItem) {
        $previousCodeId = [string]$script:DgWrapupCodes.SelectedItem.WrapupCodeId
    }

    $displayRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($r in $rows) {
        $displayRows.Add([pscustomobject]@{
            WrapupCodeId    = [string]($r.wrapup_code_id)
            WrapupCodeName  = [string]($r.wrapup_code_name)
            NConnected      = [int]   ($r.n_connected)
            QueueCount      = [int]   ($r.queue_count)
            PctOfOrgTotal   = [string]("{0:F1}" -f [double]($r.pct_of_org_total))
        })
    }

    if ($null -ne $script:DgWrapupCodes) {
        $script:DgWrapupCodes.ItemsSource = $displayRows
        if ($displayRows.Count -gt 0) {
            $target = $displayRows[0]
            if ($previousCodeId) {
                foreach ($row in $displayRows) {
                    if ($row.WrapupCodeId -eq $previousCodeId) { $target = $row; break }
                }
            }
            $script:DgWrapupCodes.SelectedItem = $target
            try { $script:DgWrapupCodes.ScrollIntoView($target) } catch {}
        }
    }

    if ($null -ne $script:LblWrapupCodes)     { $script:LblWrapupCodes.Text     = [string]($summary.TotalCodes) }
    if ($null -ne $script:LblWrapupConnected) { $script:LblWrapupConnected.Text = [string]($summary.TotalConnected) }
    if ($null -ne $script:LblWrapupQueues)    { $script:LblWrapupQueues.Text    = [string]($summary.TotalQueues) }
    if ($null -ne $script:LblWrapupTopReason) {
        $script:LblWrapupTopReason.Text = if ($summary.TopReasonName) {
            "$($summary.TopReasonName) ($($summary.TopReasonCount))"
        } else { '-' }
    }

    $byCode = @{}
    $maxHourValue = 0
    foreach ($h in $hourRows) {
        $codeId = [string]($h.wrapup_code_id)
        if (-not $byCode.ContainsKey($codeId)) {
            $entry = [ordered]@{
                WrapupCodeId   = $codeId
                WrapupCodeName = [string]($h.wrapup_code_name)
                Total          = 0
            }
            for ($i = 0; $i -lt 24; $i++) {
                $entry[('Hour{0:D2}' -f $i)] = 0
                $entry[('Hour{0:D2}Brush' -f $i)] = '#0F161B'
            }
            $byCode[$codeId] = $entry
        }
        $hour = [int]($h.hour_of_day)
        if ($hour -lt 0 -or $hour -gt 23) { continue }
        $n = [int]($h.n_connected)
        $byCode[$codeId][('Hour{0:D2}' -f $hour)] = $n
        $byCode[$codeId]['Total'] += $n
        if ($n -gt $maxHourValue) { $maxHourValue = $n }
    }

    $hourDisplay = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($entry in @($byCode.Values | Sort-Object @{ Expression = { $_['Total'] }; Descending = $true }, WrapupCodeName)) {
        for ($i = 0; $i -lt 24; $i++) {
            $hourName = 'Hour{0:D2}' -f $i
            $entry["$($hourName)Brush"] = _GetWrapupHeatBrush -Value ([int]$entry[$hourName]) -Max $maxHourValue
        }
        $hourDisplay.Add([pscustomobject]$entry)
    }
    if ($null -ne $script:DgWrapupByHour) { $script:DgWrapupByHour.ItemsSource = $hourDisplay }

    $insightRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($i in $insights) {
        $insightRows.Add([pscustomobject]@{
            WrapupCodeName     = [string]($i.WrapupCodeName)
            TopQueueName       = [string]($i.TopQueueName)
            ConcentrationIndex = [string]("{0:F2}" -f [double]($i.ConcentrationIndex))
            NConnectedTotal    = [int]   ($i.NConnectedTotal)
        })
    }
    if ($null -ne $script:DgWrapupInsights) { $script:DgWrapupInsights.ItemsSource = $insightRows }

    $crossRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($c in $crossRef) {
        $crossRows.Add([pscustomobject]@{
            WrapupCodeName     = [string]($c.WrapupCodeName)
            ConversationCount  = [int]   ($c.ConversationCount)
            MedianHandleSec    = [string]("{0:F1}" -f [double]($c.MedianHandleSec))
            MedianSegmentCount = [string]("{0:F1}" -f [double]($c.MedianSegmentCount))
        })
    }
    if ($null -ne $script:DgWrapupCrossRef) { $script:DgWrapupCrossRef.ItemsSource = $crossRows }

    _RenderSelectedWrapupDetail
}

function _RenderSelectedWrapupDetail {
    if (-not (Test-DatabaseInitialized)) {
        if ($null -ne $script:DgWrapupByQueue) { $script:DgWrapupByQueue.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        return
    }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId)) {
        if ($null -ne $script:DgWrapupByQueue) { $script:DgWrapupByQueue.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        return
    }
    if ($null -eq $script:DgWrapupCodes -or $null -eq $script:DgWrapupCodes.SelectedItem) {
        if ($null -ne $script:DgWrapupByQueue) { $script:DgWrapupByQueue.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        return
    }

    $wrapupCodeId = [string]$script:DgWrapupCodes.SelectedItem.WrapupCodeId
    if ([string]::IsNullOrWhiteSpace($wrapupCodeId)) {
        if ($null -ne $script:DgWrapupByQueue) { $script:DgWrapupByQueue.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
        return
    }

    try {
        $queues = @(Get-WrapupByQueueRows -CaseId $caseId -WrapupCodeId $wrapupCodeId)
    } catch {
        _SetStatus "Wrapup queue detail read failed: $_"
        return
    }

    $queueRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($q in $queues) {
        $queueRows.Add([pscustomobject]@{
            QueueName       = [string]($q.queue_name)
            NConnected      = [int]   ($q.n_connected)
            PctOfQueueTotal = [string]("{0:F1}" -f [double]($q.pct_of_queue_total))
            PctOfOrgTotal   = [string]("{0:F1}" -f [double]($q.pct_of_org_total))
        })
    }
    if ($null -ne $script:DgWrapupByQueue) { $script:DgWrapupByQueue.ItemsSource = $queueRows }
}

function _ClearQualityGrid {
    if ($null -ne $script:DgQualityAgentScores)    { $script:DgQualityAgentScores.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgQualityQueues)         { $script:DgQualityQueues.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgLowScoreConversations) { $script:DgLowScoreConversations.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:DgLowScoreTopics)        { $script:DgLowScoreTopics.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new() }
    if ($null -ne $script:LblQualityEvaluations)   { $script:LblQualityEvaluations.Text = '-' }
    if ($null -ne $script:LblQualitySurveys)       { $script:LblQualitySurveys.Text = '-' }
    if ($null -ne $script:LblQualityAvgScore)      { $script:LblQualityAvgScore.Text = '-' }
    if ($null -ne $script:LblQualityAvgCsat)       { $script:LblQualityAvgCsat.Text = '-' }
    if ($null -ne $script:LblQualityLowConvs)      { $script:LblQualityLowConvs.Text = '-' }
    if ($null -ne $script:TxtQualityCorrelation)   { $script:TxtQualityCorrelation.Text = '' }
}

function _StartQualityOverlayReportJob {
    if (-not (Test-DatabaseInitialized)) {
        [System.Windows.MessageBox]::Show('Case store is offline.', 'Quality')
        return
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    if (-not (Test-CoreInitialized)) {
        [System.Windows.MessageBox]::Show('Genesys Core is not initialized. Check Settings.', 'Quality')
        return
    }

    $headers = Get-StoredHeaders
    if ($null -eq $headers -or $headers.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Connect to Genesys Cloud before pulling quality data.', 'Not Connected')
        return
    }

    $range = $null
    try { $range = _GetQueryBoundaryDateTimes } catch {
        [System.Windows.MessageBox]::Show("Invalid date range: $_", 'Quality')
        return
    }
    if ($null -eq $range.Start -or $null -eq $range.End) {
        [System.Windows.MessageBox]::Show('Set a start and end date/time before pulling quality data.', 'Quality')
        return
    }

    $agentUserIds = @(Get-CaseAgentUserIds -CaseId $case.case_id)
    $startDt = $range.Start.ToUniversalTime().ToString('o')
    $endDt   = $range.End.ToUniversalTime().ToString('o')

    $cfg         = Get-AppConfig
    $corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
    $catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
    $schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
    $outputRoot  = $cfg.OutputRoot
    $connInfo    = Get-ConnectionInfo
    $region      = if ($null -ne $connInfo -and $connInfo.Region) { $connInfo.Region } else { $cfg.Region }
    $baseUri     = "https://api.$region"

    _SetStatus 'Pulling quality overlay report...'
    if ($null -ne $script:BtnPullQualityReport) {
        $script:BtnPullQualityReport.IsEnabled = $false
    }
    $script:State.QualityCaseId = $case.case_id

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $appDir = $script:UIAppDir

    [void]$ps.AddScript({
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $Headers, $BaseUri, $StartDt, $EndDt, $AgentUserIds)
        Set-StrictMode -Version Latest

        Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')) -Force -ErrorAction Stop
        Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
        return (Get-QualityOverlayReport -StartDateTime $StartDt -EndDateTime $EndDt -AgentUserIds $AgentUserIds -Headers $Headers -BaseUri $BaseUri)
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($headers)
    [void]$ps.AddArgument($baseUri)
    [void]$ps.AddArgument($startDt)
    [void]$ps.AddArgument($endDt)
    [void]$ps.AddArgument($agentUserIds)

    $asyncResult = $ps.BeginInvoke()

    $script:State.QualityJob      = @{ Ps = $ps; Async = $asyncResult; CaseId = $case.case_id; StartDt = $startDt; EndDt = $endDt }
    $script:State.QualityRunspace = $rs

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(2)
    $script:State.QualityTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        $job = $script:State.QualityJob
        if ($null -eq $job) { $script:State.QualityTimer.Stop(); return }
        if (-not $job.Async.IsCompleted) { return }

        $script:State.QualityTimer.Stop()
        $script:State.QualityTimer = $null

        $folderMap  = $null
        $endFailure = $null
        try {
            $results   = $job.Ps.EndInvoke($job.Async)
            $folderMap = $results | Select-Object -Last 1
        } catch {
            $endFailure = $_
        } finally {
            try { $job.Ps.Dispose() }                         catch {}
            try { $script:State.QualityRunspace.Close() }    catch {}
            try { $script:State.QualityRunspace.Dispose() }  catch {}
            $script:State.QualityJob      = $null
            $script:State.QualityRunspace = $null
            $script:State.QualityCaseId   = ''
        }

        if ($null -ne $endFailure) {
            _SetStatus 'Quality overlay report pull failed'
            _Dispatch { if ($null -ne $script:BtnPullQualityReport) { $script:BtnPullQualityReport.IsEnabled = $true } }
            [System.Windows.MessageBox]::Show("Pull failed: $endFailure", 'Quality')
            return
        }

        if ($null -ne $folderMap) {
            try {
                $importStats = Import-QualityOverlayReport -CaseId $job.CaseId -FolderMap $folderMap -StartDateTime $job.StartDt -EndDateTime $job.EndDt
                $summary = "Loaded $($importStats.EvaluationCount) evaluations, $($importStats.SurveyCount) surveys, and $($importStats.TopicCount) topic rows"
                if ($importStats.SkippedCount -gt 0) { $summary += " ($($importStats.SkippedCount) skipped)" }
                if ($folderMap.PartialFailure) { $summary += ' - WARNING: one or more quality datasets failed.' }
                _SetStatus $summary
                _RenderQualityGrid
                [System.Windows.MessageBox]::Show($summary, 'Quality Report')
            } catch {
                _SetStatus 'Quality overlay report import failed'
                [System.Windows.MessageBox]::Show("Import failed: $_", 'Quality')
            }
        } else {
            _SetStatus 'Quality overlay report pull completed (no data returned)'
        }

        _Dispatch { if ($null -ne $script:BtnPullQualityReport) { $script:BtnPullQualityReport.IsEnabled = $true } }
    })

    $timer.Start()
}

function _RenderQualityGrid {
    if (-not (Test-DatabaseInitialized)) { _ClearQualityGrid; return }
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId)) { _ClearQualityGrid; return }

    try {
        $summary      = Get-QualitySummary -CaseId $caseId
        $agentRows    = @(Get-QualityAgentScoreRows -CaseId $caseId)
        $queueRows    = @(Get-QualitySurveyQueueRows -CaseId $caseId)
        $lowRows      = @(Get-LowScoreConversationRows -CaseId $caseId)
        $corr         = Get-QualityCorrelationSummary -CaseId $caseId
        $topicRows    = @(Get-LowScoreTopicRows -CaseId $caseId -Top 5)
    } catch {
        _SetStatus "Quality report read failed: $_"
        return
    }

    if ($null -ne $script:LblQualityEvaluations) { $script:LblQualityEvaluations.Text = [string]($summary.EvaluationCount) }
    if ($null -ne $script:LblQualitySurveys)     { $script:LblQualitySurveys.Text     = [string]($summary.SurveyCount) }
    if ($null -ne $script:LblQualityAvgScore) {
        $script:LblQualityAvgScore.Text = if ($null -ne $summary.AvgEvaluationScore) { [string]("{0:F1}" -f [double]$summary.AvgEvaluationScore) } else { '-' }
    }
    if ($null -ne $script:LblQualityAvgCsat) {
        $script:LblQualityAvgCsat.Text = if ($null -ne $summary.AvgCsat) { [string]("{0:F2}" -f [double]$summary.AvgCsat) } else { '-' }
    }
    if ($null -ne $script:LblQualityLowConvs) { $script:LblQualityLowConvs.Text = [string]($summary.LowConversationCount) }

    $corrLines = @()
    $corrLines += "Paired conversations: $($corr.ConversationCount)"
    $corrLines += "Handle time / score r: $(if ($null -ne $corr.HandleScoreCorrelation) { '{0:F3}' -f [double]$corr.HandleScoreCorrelation } else { '-' })"
    $corrLines += "Wrapup / score r: $(if ($null -ne $corr.WrapupScoreCorrelation) { '{0:F3}' -f [double]$corr.WrapupScoreCorrelation } else { '-' })"
    $corrLines += $corr.WrapupOrdinalNote
    if ($null -ne $script:TxtQualityCorrelation) { $script:TxtQualityCorrelation.Text = ($corrLines -join "`r`n") }

    $agentDisplay = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($row in $agentRows) {
        $agentDisplay.Add([pscustomobject]@{
            AgentName        = [string]$row.AgentName
            EvaluationCount  = [int]   $row.EvaluationCount
            MinScore         = [string]("{0:F1}" -f [double]$row.MinScore)
            P25Score         = [string]("{0:F1}" -f [double]$row.P25Score)
            MedianScore      = [string]("{0:F1}" -f [double]$row.MedianScore)
            P75Score         = [string]("{0:F1}" -f [double]$row.P75Score)
            MaxScore         = [string]("{0:F1}" -f [double]$row.MaxScore)
            AvgScore         = [string]("{0:F1}" -f [double]$row.AvgScore)
        })
    }
    if ($null -ne $script:DgQualityAgentScores) { $script:DgQualityAgentScores.ItemsSource = $agentDisplay }

    $queueDisplay = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($row in $queueRows) {
        $queueDisplay.Add([pscustomobject]@{
            QueueName       = [string]$row.QueueName
            SurveyCount     = [int]   $row.SurveyCount
            AvgNps          = if ($null -ne $row.AvgNps) { [string]("{0:F1}" -f [double]$row.AvgNps) } else { '-' }
            MedianNps       = if ($null -ne $row.MedianNps) { [string]("{0:F1}" -f [double]$row.MedianNps) } else { '-' }
            AvgCsat         = if ($null -ne $row.AvgCsat) { [string]("{0:F2}" -f [double]$row.AvgCsat) } else { '-' }
            MedianCsat      = if ($null -ne $row.MedianCsat) { [string]("{0:F2}" -f [double]$row.MedianCsat) } else { '-' }
            DetractorCount  = [int]   $row.DetractorCount
        })
    }
    if ($null -ne $script:DgQualityQueues) { $script:DgQualityQueues.ItemsSource = $queueDisplay }

    $lowDisplay = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($row in $lowRows) {
        $lowDisplay.Add([pscustomobject]@{
            ConversationId  = [string]$row.ConversationId
            QueueName       = [string]$row.QueueName
            AgentName       = [string]$row.AgentName
            EvaluationScore = if ($null -ne $row.EvaluationScore) { [string]("{0:F1}" -f [double]$row.EvaluationScore) } else { '-' }
            NpsScore        = if ($null -ne $row.NpsScore) { [string]$row.NpsScore } else { '-' }
            CsatScore       = if ($null -ne $row.CsatScore) { [string]("{0:F2}" -f [double]$row.CsatScore) } else { '-' }
            Issues          = [string]$row.Issues
            CompletedAt     = [string]$row.CompletedAt
        })
    }
    if ($null -ne $script:DgLowScoreConversations) { $script:DgLowScoreConversations.ItemsSource = $lowDisplay }

    $topicDisplay = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($row in $topicRows) {
        $topicDisplay.Add([pscustomobject]@{
            TopicName         = [string]$row.TopicName
            TopicHits         = [int]   $row.TopicHits
            ConversationCount = [int]   $row.ConversationCount
        })
    }
    if ($null -ne $script:DgLowScoreTopics) { $script:DgLowScoreTopics.ItemsSource = $topicDisplay }
}

function _OpenLowScoreConversation {
    if ($null -eq $script:DgLowScoreConversations -or $null -eq $script:DgLowScoreConversations.SelectedItem) { return }
    $convId = [string]$script:DgLowScoreConversations.SelectedItem.ConversationId
    if ([string]::IsNullOrWhiteSpace($convId)) { return }
    _Dispatch {
        if ($null -ne $script:TabWorkspace) {
            $script:TabWorkspace.SelectedIndex = 0
        }
        if ($null -ne $script:TabDrilldownWorkspace) {
            $script:TabDrilldownWorkspace.SelectedIndex = 1
        }
    }
    _LoadDrilldown -ConversationId $convId
}

function _ImportCurrentRunToCase {
    if (-not (Test-DatabaseInitialized)) {
        _SetStatus 'Case store offline'
        return
    }

    $runFolder = _ResolveImportRunFolder
    if (-not $runFolder) {
        [System.Windows.MessageBox]::Show('Load a run or select one from Recent Runs first.', 'Import Run')
        return
    }

    $case = _EnsureActiveCase
    if ($null -eq $case) { return }

    # Delegate to the background import so the UI thread stays responsive.
    _StartAutoImportInBackground `
        -CaseId    $case.case_id `
        -CaseName  $case.name `
        -RunFolder $runFolder `
        -FromButton
}

function _StartAutoImportInBackground {
    <#
    .SYNOPSIS
        Runs Import-RunFolderToCase in a dedicated runspace so the UI thread
        remains responsive (IsActive = true) during the SQLite write.
    .PARAMETER FromButton
        When set, shows a MessageBox on completion/failure (manual import).
        Omit for silent auto-import triggered after a run completes.
    #>
    param(
        [string]$CaseId,
        [string]$CaseName,
        [string]$RunFolder,
        [string]$PreferredConversationId = '',
        [pscustomobject]$RunLoadResult   = $null,
        [switch]$FromButton
    )

    if (-not (Test-DatabaseInitialized) -or [string]::IsNullOrEmpty($CaseId) -or [string]::IsNullOrWhiteSpace($RunFolder)) {
        return
    }

    # Prevent double-start; the Import button is disabled during the job.
    if ($null -ne $script:State.AutoImportJob) { return }

    $cfg        = Get-AppConfig
    $dbPath     = $cfg.DatabasePath
    $sqliteDll  = $cfg.SqliteDllPath
    $appDir     = $script:UIAppDir
    $fromButton = [bool]$FromButton

    _SetStatus "Importing conversations into case '$CaseName'…"
    _Dispatch { if ($null -ne $script:BtnImportRun) { $script:BtnImportRun.IsEnabled = $false } }

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
        param($AppDir, $CaseId, $RunFolder, $DatabasePath, $SqliteDllPath)
        Set-StrictMode -Version Latest
        Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.Database.psm1')) -Force -ErrorAction Stop
        Initialize-Database -DatabasePath $DatabasePath -SqliteDllPath $SqliteDllPath -AppDir $AppDir -ErrorAction Stop | Out-Null
        return (Import-RunFolderToCase -CaseId $CaseId -RunFolder $RunFolder)
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($CaseId)
    [void]$ps.AddArgument($RunFolder)
    [void]$ps.AddArgument($dbPath)
    [void]$ps.AddArgument($sqliteDll)

    $asyncResult = $ps.BeginInvoke()

    $script:State.AutoImportJob = @{
        Ps                     = $ps
        Async                  = $asyncResult
        CaseId                 = $CaseId
        CaseName               = $CaseName
        RunFolder              = $RunFolder
        PreferredConversationId = $PreferredConversationId
        RunLoadResult          = $RunLoadResult
        FromButton             = $fromButton
    }
    $script:State.AutoImportRunspace = $rs

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(1)
    $script:State.AutoImportTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        $job = $script:State.AutoImportJob
        if ($null -eq $job) { $script:State.AutoImportTimer.Stop(); return }
        if (-not $job.Async.IsCompleted) { return }

        $script:State.AutoImportTimer.Stop()
        $script:State.AutoImportTimer = $null

        $importResult = $null
        $endFailure   = $null
        try {
            $results      = $job.Ps.EndInvoke($job.Async)
            $importResult = $results | Select-Object -Last 1
        } catch {
            $endFailure = $_
        } finally {
            try { $job.Ps.Dispose() }                          catch {}
            try { $script:State.AutoImportRunspace.Close()   } catch {}
            try { $script:State.AutoImportRunspace.Dispose() } catch {}
            $script:State.AutoImportJob      = $null
            $script:State.AutoImportRunspace = $null
        }

        _Dispatch { if ($null -ne $script:BtnImportRun) { $script:BtnImportRun.IsEnabled = $true } }

        if ($null -ne $endFailure) {
            _AppendRunDiagnostic `
                -Stage 'Case import failed' `
                -Message 'Import-RunFolderToCase failed in background runspace.' `
                -Exception $endFailure `
                -RunFolder $job.RunFolder `
                -DataSource 'index' `
                -CaseId $job.CaseId
            _SetStatus "Import failed: $($endFailure.Exception.Message)"
            if ($job.FromButton) {
                [System.Windows.MessageBox]::Show("Import failed: $endFailure", 'Import Run')
            }
            return
        }

        $imported = if ($null -ne $importResult -and $importResult.PSObject.Properties['RecordCount']) { [int]$importResult.RecordCount } else { 0 }
        $skipped  = if ($null -ne $importResult -and $importResult.PSObject.Properties['SkippedCount']) { [int]$importResult.SkippedCount } else { 0 }
        $failed   = if ($null -ne $importResult -and $importResult.PSObject.Properties['FailedCount'])  { [int]$importResult.FailedCount  } else { 0 }
        $runId    = if ($null -ne $importResult -and $importResult.PSObject.Properties['RunId'])        { [string]$importResult.RunId      } else { '' }
        $dataset  = if ($null -ne $importResult -and $importResult.PSObject.Properties['DatasetKey'])   { [string]$importResult.DatasetKey } else { '' }
        $convWord = if ($imported -eq 1) { 'conversation' } else { 'conversations' }
        $summary  = "Imported $imported $convWord into case '$($job.CaseName)'"
        if ($skipped -gt 0 -or $failed -gt 0) { $summary += " (skipped: $skipped, failed: $failed)" }

        if ($job.FromButton) {
            _Dispatch {
                $script:TxtDiagnostics.Text = @"
=== Case Import ===
Case        : $($job.CaseName)
Run Folder  : $($job.RunFolder)
Run Id      : $runId
Dataset     : $dataset
Imported    : $imported
Skipped     : $skipped
Failed      : $failed
"@
            }
        }

        if ($null -ne $importResult) {
            $filterState    = _GetCanonicalFilterState
            $dbDisplayCount = 0
            try { $dbDisplayCount = Get-ConversationCount -CaseId $job.CaseId -FilterState $filterState } catch {}
            if ($dbDisplayCount -gt 0 -or $imported -eq 0) {
                $switchResult = _SwitchToDbMode
                if ($null -eq $switchResult -or -not $switchResult.Succeeded -or ($imported -gt 0 -and $switchResult.RowCount -eq 0)) {
                    _AppendRunDiagnostic `
                        -Stage 'Case-store display fallback' `
                        -Message 'Import completed, but the DB grid refresh did not produce display rows. Keeping run-artifact rows visible.' `
                        -RunFolder $job.RunFolder `
                        -DataSource 'index' `
                        -CaseId $job.CaseId
                    $rl = $job.RunLoadResult
                    if ($null -ne $rl -and $rl.PSObject.Properties['IndexRecordCount'] -and $rl.IndexRecordCount -gt 0) {
                        _LoadRunAndRefreshGrid -RunFolder $job.RunFolder -PreferredConversationId $job.PreferredConversationId -PreserveRunFilters | Out-Null
                    }
                }
            } else {
                _AppendRunDiagnostic `
                    -Stage 'Case-store display fallback' `
                    -Message 'Import completed, but the current case-store filters returned 0 rows. Keeping run-artifact rows visible.' `
                    -RunFolder $job.RunFolder `
                    -DataSource 'index' `
                    -CaseId $job.CaseId
            }
        }

        _SetStatus $summary
        if ($job.FromButton) {
            [System.Windows.MessageBox]::Show($summary, 'Import Complete')
        }
    })

    $timer.Start()
}

# ── Database-backed grid ──────────────────────────────────────────────────────

function _RefreshGridFromDb {
    <#
    .SYNOPSIS
        Queries the SQLite case store for the current page and filter state,
        then pushes rows to DgConversations via Dispatcher.
        Used when State.DataSource = 'database'.
    #>
    $caseId = $script:State.ActiveCaseId
    if ([string]::IsNullOrEmpty($caseId) -or -not (Test-DatabaseInitialized)) {
        _SetStatus 'No active case — import a run to a case to enable case-store view'
        return [pscustomobject]@{ Succeeded = $false; RowCount = 0; Error = 'No active case or database is not initialized.' }
    }

    $filterState = _GetCanonicalFilterState

    try {
        $count = Get-ConversationCount `
            -CaseId         $caseId `
            -FilterState    $filterState

        $script:State.DbConversationCount = $count
        $script:State.TotalPages = [math]::Max(1, [math]::Ceiling($count / $script:State.PageSize))
        if ($script:State.CurrentPage -gt $script:State.TotalPages) {
            $script:State.CurrentPage = $script:State.TotalPages
        }

        # Resolve sort column for DB query
        $sortBy  = if ($script:State.SortColumn -and $script:_DbColMap.ContainsKey($script:State.SortColumn)) {
            $script:_DbColMap[$script:State.SortColumn]
        } else { 'conversation_start' }
        $sortDir = if ($script:State.SortAscending) { 'ASC' } else { 'DESC' }

        $rows = @(Get-ConversationsPage `
            -CaseId         $caseId `
            -PageNumber     $script:State.CurrentPage `
            -PageSize       $script:State.PageSize `
            -FilterState    $filterState `
            -SortBy         $sortBy `
            -SortDir        $sortDir)

        $displayRows = @($rows | ForEach-Object { Get-DbConversationDisplayRow -DbRow $_ })
        $page  = $script:State.CurrentPage
        $pages = $script:State.TotalPages
        $preferredConversationId = [string]$filterState.ConversationId

        _Dispatch {
            $script:DgConversations.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($displayRows)
            $script:TxtPageInfo.Text = "Page $page of $pages  |  $count records  [case]"
            $script:BtnPrevPage.IsEnabled = ($page -gt 1)
            $script:BtnNextPage.IsEnabled = ($page -lt $pages)
            _AutoOpenConversationFromRows -Rows $displayRows -PreferredConversationId $preferredConversationId -RunRecordCount $count
        }

        # Mirror into CurrentIndex so impact reports keep working (index-compatible subset)
        $script:State.CurrentIndex = @($rows)
        _RefreshReportButtons
        return [pscustomobject]@{ Succeeded = $true; RowCount = $displayRows.Count; Error = '' }
    } catch {
        _AppendRunDiagnostic `
            -Stage 'DB grid refresh failed' `
            -Message 'The case-store grid could not be refreshed. Preserving the previous grid contents.' `
            -Exception $_ `
            -RunFolder $script:State.CurrentRunFolder `
            -DataSource $script:State.DataSource `
            -CaseId $caseId
        _Dispatch {
            $script:TxtPageInfo.Text = 'Case grid error - see Run Console'
        }
        _SetStatus "Case grid error: $($_.Exception.Message)"
        return [pscustomobject]@{ Succeeded = $false; RowCount = 0; Error = $_.Exception.Message }
    }
}

function _SwitchToDbMode {
    <#
    .SYNOPSIS
        Switches the conversations grid to DB mode for the active case.
        Called after a successful import or when the user selects a case that already has data.
    #>
    if ([string]::IsNullOrEmpty($script:State.ActiveCaseId) -or -not (Test-DatabaseInitialized)) {
        return [pscustomobject]@{ Succeeded = $false; RowCount = 0; Error = 'No active case or database is not initialized.' }
    }
    $previousDataSource = $script:State.DataSource
    $script:State.DataSource   = 'database'
    $script:State.CurrentPage  = 1
    $script:State.CurrentImpactReport = $null
    _SetStatus "Case store view: $($script:State.ActiveCaseName)"
    $result = _RefreshGridFromDb
    if ($null -eq $result -or -not $result.Succeeded) {
        $script:State.DataSource = $previousDataSource
    }
    return $result
}

# ── Index / paging ────────────────────────────────────────────────────────────

function _LoadRunAndRefreshGrid {
    param(
        [string]$RunFolder,
        [string]$PreferredConversationId = '',
        [switch]$PreserveRunFilters
    )
    if ([string]::IsNullOrEmpty($RunFolder)) { return }
    _SetStatus "Loading index: $([System.IO.Path]::GetFileName($RunFolder)) …"

    $script:State.CurrentRunFolder  = $RunFolder
    $script:State.DiagnosticsContext = $RunFolder
    $script:State.DataSource = 'index'

    # Clear stale run-specific filters for manually-loaded runs, but preserve the
    # filter that just produced a completed run so its detail pane can open.
    if ($PreserveRunFilters) {
        if (-not [string]::IsNullOrWhiteSpace($PreferredConversationId) -and $null -ne $script:TxtConversationId) {
            $script:TxtConversationId.Text = $PreferredConversationId
        }
    } else {
        $script:TxtConversationId.Text = ''
        if ($null -ne $script:TxtFilterUserId)     { $script:TxtFilterUserId.Text     = '' }
        if ($null -ne $script:TxtFilterDivisionId) { $script:TxtFilterDivisionId.Text = '' }
    }

    $contract = $null
    if (Get-Command Test-CoreRunArtifactContract -ErrorAction SilentlyContinue) {
        try {
            $contract = Test-CoreRunArtifactContract -RunFolder $RunFolder
            if (-not $contract.IsValid) {
                _AppendRunDiagnostic `
                    -Stage 'Artifact contract validation failed' `
                    -Message ($contract.Errors -join '; ') `
                    -RunFolder $RunFolder `
                    -DataSource 'index'
            } elseif ($contract.Warnings.Count -gt 0) {
                _AppendRunDiagnostic `
                    -Stage 'Artifact contract validation warnings' `
                    -Message ($contract.Warnings -join '; ') `
                    -RunFolder $RunFolder `
                    -DataSource 'index'
            }
        } catch {
            _AppendRunDiagnostic `
                -Stage 'Artifact contract validation threw' `
                -Message 'Validation could not complete before indexing.' `
                -Exception $_ `
                -RunFolder $RunFolder `
                -DataSource 'index'
        }
    }

    try {
        # Load or build index (may take a moment for large runs)
        $allIdx = @(Load-RunIndex -RunFolder $RunFolder)
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh -AllIndex $allIdx
        _SetStatus "Loaded $($allIdx.Count) records from $([System.IO.Path]::GetFileName($RunFolder))"
        $script:TxtStatusRight.Text = [datetime]::Now.ToString('HH:mm:ss')
        return [pscustomobject]@{
            Succeeded = $true
            IndexRecordCount = $allIdx.Count
            DisplayRecordCount = @($script:State.CurrentIndex).Count
            Contract = $contract
            Error = ''
        }
    } catch {
        _AppendRunDiagnostic `
            -Stage 'Run index load failed' `
            -Message 'The Core run folder was found, but index loading/rendering failed.' `
            -Exception $_ `
            -RunFolder $RunFolder `
            -DataSource 'index'
        _SetStatus "Index load failed: $($_.Exception.Message)"
        return [pscustomobject]@{
            Succeeded = $false
            IndexRecordCount = 0
            DisplayRecordCount = 0
            Contract = $contract
            Error = $_.Exception.Message
        }
    }
}

function Test-ConversationDisplayPipeline {
    param(
        [string]$RunFolder,
        [string]$CaseId = '',
        [string]$PreferredConversationId = ''
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $check = _TestCompletedRunFolder -RunFolder $RunFolder
    $dataRecordCount = 0
    $indexRecordCount = 0
    $firstConversationId = ''
    $caseImportAttempted = (-not [string]::IsNullOrWhiteSpace($CaseId) -and (Test-DatabaseInitialized))
    $caseConversationCount = 0
    $dbPageRowCount = 0
    $drilldownResolvable = $false

    if ($check.DataDirectoryExists) {
        try {
            foreach ($file in [System.IO.Directory]::GetFiles(([System.IO.Path]::Combine($RunFolder, 'data')), '*.jsonl')) {
                $reader = [System.IO.StreamReader]::new($file, [System.Text.Encoding]::UTF8, $true)
                try {
                    while (($line = $reader.ReadLine()) -ne $null) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) { $dataRecordCount++ }
                    }
                } finally {
                    $reader.Close()
                    $reader.Dispose()
                }
            }
        } catch {
            $errors.Add("Data record count failed: $($_.Exception.Message)") | Out-Null
        }
    }

    if ($check.IsComplete) {
        try {
            $idx = @(Load-RunIndex -RunFolder $RunFolder)
            $indexRecordCount = $idx.Count
            if ($idx.Count -gt 0) { $firstConversationId = [string]$idx[0].id }
        } catch {
            $errors.Add("Index load failed: $($_.Exception.Message)") | Out-Null
        }
    } else {
        $errors.Add('Run folder does not satisfy completed artifact contract: manifest.json, summary.json, and data/*.jsonl are required.') | Out-Null
    }

    if ($caseImportAttempted) {
        try {
            $caseConversationCount = Get-ConversationCount -CaseId $CaseId
            $pageRows = @(Get-ConversationsPage -CaseId $CaseId -PageNumber 1 -PageSize $script:State.PageSize)
            $dbPageRowCount = $pageRows.Count
        } catch {
            $warnings.Add("Case-store display check failed: $($_.Exception.Message)") | Out-Null
        }
    }

    $probeId = if (-not [string]::IsNullOrWhiteSpace($PreferredConversationId)) { $PreferredConversationId } else { $firstConversationId }
    if (-not [string]::IsNullOrWhiteSpace($probeId)) {
        try {
            $resolved = Resolve-ConversationDrilldownRecord -CaseId $CaseId -RunFolder $RunFolder -ConversationId $probeId
            $drilldownResolvable = ($null -ne $resolved -and $resolved.Found)
            if ($null -ne $resolved) {
                foreach ($err in @($resolved.Errors)) { $errors.Add($err) | Out-Null }
                foreach ($warn in @($resolved.Warnings)) { $warnings.Add($warn) | Out-Null }
            }
        } catch {
            $errors.Add("Drilldown resolver check failed: $($_.Exception.Message)") | Out-Null
        }
    }

    return [pscustomobject]@{
        RunFolderExists = $check.RunFolderExists
        ManifestExists = $check.ManifestExists
        SummaryExists = $check.SummaryExists
        DataDirectoryExists = $check.DataDirectoryExists
        DataFileCount = $check.DataFileCount
        DataRecordCount = $dataRecordCount
        IndexRecordCount = $indexRecordCount
        FirstConversationId = $firstConversationId
        CaseImportAttempted = $caseImportAttempted
        CaseConversationCount = $caseConversationCount
        DbPageRowCount = $dbPageRowCount
        DrilldownResolvable = $drilldownResolvable
        Errors = $errors.ToArray()
        Warnings = $warnings.ToArray()
    }
}

function _ApplyFiltersAndRefresh {
    param([object[]]$AllIndex = $null)

    # DB mode: delegate entirely to the server-side paging path
    if ($script:State.DataSource -eq 'database') {
        _RefreshGridFromDb
        return
    }

    if ($null -eq $AllIndex) {
        if ($null -eq $script:State.CurrentRunFolder) { return }
        $AllIndex = @(Load-RunIndex -RunFolder $script:State.CurrentRunFolder)
    }

    $dir    = $script:State.FilterDirection
    $media  = $script:State.FilterMedia
    $search = $script:State.SearchText
    $convId = $script:TxtConversationId.Text.Trim()

    $userId = $script:TxtFilterUserId.Text.Trim()
    $divId  = $script:TxtFilterDivisionId.Text.Trim()

    $filtered = @($AllIndex | Where-Object {
        $ok = $true
        if ($dir    -and $_.direction -ne $dir)   { $ok = $false }
        if ($media  -and $_.mediaType -ne $media) { $ok = $false }
        if ($convId -and $_.id -ne $convId)       { $ok = $false }
        if ($search) {
            $lo = $search.ToLowerInvariant()
            if ($_.id    -notlike "*$lo*" -and
                $_.queue -notlike "*$lo*") { $ok = $false }
        }
        if ($userId -and -not (@($_.userIds)     -contains $userId)) { $ok = $false }
        if ($divId  -and -not (@($_.divisionIds) -contains $divId))  { $ok = $false }
        $ok
    })

    # Apply per-column text filters (post-query LIKE on index properties)
    if ($script:State.ColumnFilters.Count -gt 0) {
        foreach ($bindPath in @($script:State.ColumnFilters.Keys)) {
            $val = $script:State.ColumnFilters[$bindPath]
            if (-not $val) { continue }
            $idxProp = if ($script:_IndexPropMap.ContainsKey($bindPath)) { $script:_IndexPropMap[$bindPath] } else { $bindPath }
            $lo = $val.ToLowerInvariant()
            $filtered = @($filtered | Where-Object {
                $propVal = $_.PSObject.Properties[$idxProp]
                $null -ne $propVal -and [string]$propVal.Value -like "*$lo*"
            })
        }
    }

    # Apply column sort
    if ($script:State.SortColumn) {
        $idxProp = if ($script:_IndexPropMap.ContainsKey($script:State.SortColumn)) {
            $script:_IndexPropMap[$script:State.SortColumn]
        } else { $script:State.SortColumn }
        $filtered = if ($script:State.SortAscending) {
            @($filtered | Sort-Object { $_.$idxProp })
        } else {
            @($filtered | Sort-Object { $_.$idxProp } -Descending)
        }
    }

    $filteredRows = @($filtered)
    $script:State.CurrentIndex = $filteredRows
    $script:State.TotalPages   = [math]::Max(1, [math]::Ceiling($filteredRows.Count / $script:State.PageSize))
    $script:State.CurrentImpactReport = $null
    if ($script:State.CurrentPage -gt $script:State.TotalPages) {
        $script:State.CurrentPage = $script:State.TotalPages
    }
    _RenderCurrentPage
    _RefreshReportButtons
}

function _RenderCurrentPage {
    # In DB mode the grid is always rendered via a live server-side query
    if ($script:State.DataSource -eq 'database') {
        _RefreshGridFromDb
        return
    }

    $idx      = @($script:State.CurrentIndex)
    $page     = $script:State.CurrentPage
    $pageSize = $script:State.PageSize
    $total    = $idx.Count
    $pages    = $script:State.TotalPages

    $startIdx = ($page - 1) * $pageSize
    $endIdx   = [math]::Min($startIdx + $pageSize - 1, $total - 1)

    if ($startIdx -gt $endIdx -or $total -eq 0) {
        _Dispatch {
            $script:DgConversations.ItemsSource = $null
            $script:TxtPageInfo.Text = 'Page 0 of 0  |  0 records'
        }
        return
    }

    $pageEntries = @($idx[$startIdx..$endIdx])
    $displayRows = @($pageEntries | ForEach-Object { Get-ConversationDisplayRow -IndexEntry $_ })
    $preferredConversationId = ''
    if ($null -ne $script:TxtConversationId) {
        $preferredConversationId = [string]$script:TxtConversationId.Text.Trim()
    }

    _Dispatch {
        $script:DgConversations.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($displayRows)
        $script:TxtPageInfo.Text = "Page $page of $pages  |  $total records"
        $script:BtnPrevPage.IsEnabled = ($page -gt 1)
        $script:BtnNextPage.IsEnabled = ($page -lt $pages)
        _AutoOpenConversationFromRows -Rows $displayRows -PreferredConversationId $preferredConversationId -RunRecordCount $total
    }
}

# ── Drilldown ─────────────────────────────────────────────────────────────────

function _SelectDrilldownWorkspace {
    $tabCtrl = _Ctrl 'TabWorkspace'
    if ($null -eq $tabCtrl) { return }

    if ($null -ne $script:TabDrilldownWorkspace) {
        $tabCtrl.SelectedItem = $script:TabDrilldownWorkspace
    } else {
        $tabCtrl.SelectedIndex = 1
    }
}

function _GetConversationIdFromGridRow {
    param([object]$Row)

    if ($null -eq $Row) { return '' }
    if ($Row -is [string]) { return ([string]$Row).Trim() }

    foreach ($name in @('ConversationId', 'conversationId', 'conversation_id', 'id')) {
        $value = $null
        if ($Row -is [hashtable] -and $Row.ContainsKey($name)) {
            $value = $Row[$name]
        } else {
            $prop = $Row.PSObject.Properties[$name]
            if ($null -ne $prop) { $value = $prop.Value }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return ([string]$value).Trim()
        }
    }

    return ''
}

function _OpenConversationGridRow {
    param(
        [object]$Row,
        [bool]$SwitchToDrilldown = $true
    )

    $convId = _GetConversationIdFromGridRow -Row $Row
    if ([string]::IsNullOrWhiteSpace($convId)) {
        _SetStatus 'Drilldown: selected row has no conversation ID'
        return
    }

    _LoadDrilldown -ConversationId $convId

    if ($SwitchToDrilldown) {
        _SelectDrilldownWorkspace
    }
}

function _ShowConversationLookupMiss {
    param(
        [string]$ConversationId,
        [string]$Reason,
        [int]$RunRecordCount = 0
    )

    if ([string]::IsNullOrWhiteSpace($Reason)) {
        $Reason = 'The run completed, but no matching conversation detail row was available to open.'
    }

    _Dispatch {
        $script:LblSelectedConversation.Text = if ([string]::IsNullOrWhiteSpace($ConversationId)) { '(not found)' } else { $ConversationId }
        $script:TxtDrillSummary.Text = @(
            $Reason
            ''
            "Conversation ID : $ConversationId"
            "Run folder      : $($script:State.CurrentRunFolder)"
            "Run record count: $RunRecordCount"
            "Data source     : $($script:State.DataSource)"
            ''
            'Check the selected date interval, division/user permissions, and Run Console diagnostics for the API result count.'
        ) -join [Environment]::NewLine
        _SelectDrilldownWorkspace
    }
}

function _AutoOpenConversationFromRows {
    param(
        [object[]]$Rows,
        [string]$PreferredConversationId = '',
        [int]$RunRecordCount = 0
    )

    $rowList = @($Rows)
    if ($rowList.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($PreferredConversationId)) {
            _ShowConversationLookupMiss `
                -ConversationId $PreferredConversationId `
                -Reason 'The run completed, but the active Conversation ID filter produced 0 display rows.' `
                -RunRecordCount $RunRecordCount
        } else {
            _SetDrilldownDiagnostic `
                -Title 'No conversations displayed' `
                -Message 'The run completed, but the active filters produced no display rows. Check the Run Console display health summary.' `
                -Stage 'display.empty'
        }
        return
    }

    $target = $null
    if (-not [string]::IsNullOrWhiteSpace($PreferredConversationId)) {
        $target = $rowList |
            Where-Object { (_GetConversationIdFromGridRow -Row $_) -eq $PreferredConversationId } |
            Select-Object -First 1
    }

    if ($null -eq $target -and $rowList.Count -eq 1) {
        $target = $rowList[0]
    }

    if ($null -eq $target) {
        if (-not [string]::IsNullOrWhiteSpace($PreferredConversationId)) {
            _ShowConversationLookupMiss `
                -ConversationId $PreferredConversationId `
                -Reason 'The run completed, but the requested Conversation ID was not present in the current display rows.' `
                -RunRecordCount $RunRecordCount
        } else {
            _SetDrilldownDiagnostic `
                -Title 'Select a row to view details' `
                -Message 'The run returned multiple conversations. Select any conversation row to load Summary, Participants, Segments, Attributes, MOS / Quality, and Raw JSON.' `
                -Stage 'display.ready'
        }
        return
    }

    $script:State.SuppressConversationSelectionOpen = $true
    try {
        $script:DgConversations.SelectedItem = $target
        try { $script:DgConversations.ScrollIntoView($target) } catch { }
    } finally {
        $script:State.SuppressConversationSelectionOpen = $false
    }

    _OpenConversationGridRow -Row $target -SwitchToDrilldown $true
}

function _LoadDrilldown {
    param([string]$ConversationId)

    # Require either a run folder (index mode) or an active case (DB mode)
    if ($null -eq $script:State.CurrentRunFolder -and
        [string]::IsNullOrEmpty($script:State.ActiveCaseId)) { return }

    $script:State.CurrentImpactReport = $null
    _RefreshReportButtons
    _SetStatus "Loading drilldown: $ConversationId …"

    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    $resolution = $null
    try {
        try {
            $resolution = Resolve-ConversationDrilldownRecord `
                -CaseId $script:State.ActiveCaseId `
                -RunFolder $script:State.CurrentRunFolder `
                -ConversationId $ConversationId
        } catch {
            _AppendRunDiagnostic `
                -Stage 'Drilldown resolver failed' `
                -Message 'The DB/run-folder drilldown resolver threw before returning a structured result.' `
                -Exception $_ `
                -RunFolder $script:State.CurrentRunFolder `
                -DataSource $script:State.DataSource `
                -CaseId $script:State.ActiveCaseId `
                -ConversationId $ConversationId
            _SetDrilldownDiagnostic `
                -Title 'Drilldown resolver failed' `
                -Message $_.Exception.Message `
                -ConversationId $ConversationId `
                -Stage 'drilldown.resolve'
            _SetStatus 'Drilldown resolver failed'
            return
        }

        $record = if ($null -ne $resolution) { $resolution.Record } else { $null }
        $rawJsonText = if ($null -ne $resolution) { $resolution.RawJsonText } else { '' }

        if ($null -ne $resolution -and ($resolution.Errors.Count -gt 0 -or $resolution.Warnings.Count -gt 0)) {
            $messages = @($resolution.Errors + $resolution.Warnings) -join '; '
            _AppendRunDiagnostic `
                -Stage 'Drilldown resolver diagnostics' `
                -Message $messages `
                -RunFolder $script:State.CurrentRunFolder `
                -DataSource $script:State.DataSource `
                -CaseId $script:State.ActiveCaseId `
                -ConversationId $ConversationId
        }

        if ($null -eq $record) {
            $errors = if ($null -ne $resolution -and $resolution.Errors.Count -gt 0) { $resolution.Errors -join [Environment]::NewLine } else { '(no resolver error text)' }
            $warnings = if ($null -ne $resolution -and $resolution.Warnings.Count -gt 0) { $resolution.Warnings -join [Environment]::NewLine } else { '' }
            $indexCount = if ($null -ne $resolution) { $resolution.IndexRecordCount } else { 0 }
            $indexHasId = if ($null -ne $resolution) { $resolution.IndexContainsConversationId } else { $false }
            $dbRowExists = if ($null -ne $resolution) { $resolution.DbRowExists } else { $false }
            _SetDrilldownDiagnostic `
                -Title 'Record not found' `
                -Message (@(
                    'The row was selected, but the app could not resolve the full JSON conversation record from the active case store or run JSONL fallback.'
                    ''
                    "Index record count      : $indexCount"
                    "Conversation in index  : $indexHasId"
                    "DB row exists          : $dbRowExists"
                    "Errors                 : $errors"
                    "Warnings               : $warnings"
                ) -join [Environment]::NewLine) `
                -ConversationId $ConversationId `
                -Stage 'drilldown.not_found'
            _SelectDrilldownWorkspace
            _SetStatus "Drilldown: record not found"
            return
        }

        _Dispatch {
            $script:LblSelectedConversation.Text = $ConversationId

            # ── Summary tab ──
            $flat = ConvertTo-FlatRow -Record $record -IncludeAttributes
            $sb   = New-Object System.Text.StringBuilder
            foreach ($k in $flat.Keys) {
                [void]$sb.AppendLine("$($k): $($flat[$k])")
            }
            $script:TxtDrillSummary.Text = $sb.ToString()

            # ── Participants tab ──
            $parts = @()
            if ($record.PSObject.Properties['participants']) { $parts = @($record.participants) }
            $script:DgParticipants.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($parts)

            # ── Segments tab ──
            $segRows = New-Object System.Collections.Generic.List[object]
            foreach ($p in $parts) {
                if (-not $p.PSObject.Properties['sessions']) { continue }
                foreach ($s in @($p.sessions)) {
                    if (-not $s.PSObject.Properties['segments']) { continue }
                    foreach ($seg in @($s.segments)) {
                        $durSec = 0
                        if ($seg.PSObject.Properties['segmentStart'] -and $seg.PSObject.Properties['segmentEnd']) {
                            try {
                                $ss = [datetime]::Parse($seg.segmentStart)
                                $se = [datetime]::Parse($seg.segmentEnd)
                                $durSec = [int]($se - $ss).TotalSeconds
                            } catch { }
                        }
                        $segRows.Add([pscustomobject]@{
                            Purpose       = if ($p.PSObject.Properties['purpose']) { $p.purpose } else { '' }
                            SegmentType   = if ($seg.PSObject.Properties['segmentType'])   { $seg.segmentType }   else { '' }
                            SegmentStart  = if ($seg.PSObject.Properties['segmentStart'])  { $seg.segmentStart }  else { '' }
                            SegmentEnd    = if ($seg.PSObject.Properties['segmentEnd'])    { $seg.segmentEnd }    else { '' }
                            DurationSec   = $durSec
                            QueueName     = if ($seg.PSObject.Properties['queueName'])     { $seg.queueName }     else { '' }
                            DisconnectType = if ($seg.PSObject.Properties['disconnectType']) { $seg.disconnectType } else { '' }
                        })
                    }
                }
            }
            $script:DgSegments.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($segRows.ToArray())

            # ── Attributes tab ──
            $attrRows = New-Object System.Collections.Generic.List[object]
            if ($record.PSObject.Properties['attributes'] -and $null -ne $record.attributes) {
                foreach ($prop in $record.attributes.PSObject.Properties) {
                    $attrRows.Add([pscustomobject]@{ Name = $prop.Name; Value = $prop.Value })
                }
            }
            $attrArray = $attrRows.ToArray()
            $script:DgAttributes.Tag = $attrArray
            $script:DgAttributes.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($attrArray)

            # ── MOS / Quality tab ──
            $mosSb = New-Object System.Text.StringBuilder
            foreach ($p in $parts) {
                if (-not $p.PSObject.Properties['sessions']) { continue }
                foreach ($s in @($p.sessions)) {
                    if (-not $s.PSObject.Properties['metrics']) { continue }
                    foreach ($m in @($s.metrics)) {
                        if ($m.PSObject.Properties['name'] -and ($m.name -like '*mos*' -or $m.name -like '*Mos*')) {
                            [void]$mosSb.AppendLine("Metric : $($m.name)")
                            if ($m.PSObject.Properties['stats']) {
                                $st = $m.stats
                                [void]$mosSb.AppendLine("  Stats: $($st | ConvertTo-Json -Compress)")
                            }
                            [void]$mosSb.AppendLine()
                        }
                    }
                }
            }
            $script:TxtMosQuality.Text = if ($mosSb.Length -eq 0) { '(no MOS metrics)' } else { $mosSb.ToString() }

            # ── Raw JSON tab ──
            $script:TxtRawJson.Text = if (-not [string]::IsNullOrWhiteSpace($rawJsonText)) {
                $rawJsonText
            } else {
                $record | ConvertTo-Json -Depth 20
            }
        }
        _SetStatus "Drilldown loaded: $ConversationId"
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
}

# ── Run orchestration ─────────────────────────────────────────────────────────

# ── Query template builder ────────────────────────────────────────────────────

function _BuildQueryTemplateBody {
    <#
    .SYNOPSIS
        Returns a JSON string for the Genesys analytics query body for the given template name.
        The interval is set to yesterday (local midnight → 23:59:59.999 UTC).
    #>
    param(
        [string]$TemplateName,
        [string]$QueueGroupText = ''
    )

    $yesterday = [DateTime]::Today.AddDays(-1)
    $yStartUtc = $yesterday.ToUniversalTime().ToString('o')
    $yEndUtc   = $yesterday.AddDays(1).AddMilliseconds(-1).ToUniversalTime().ToString('o')
    $interval  = "$yStartUtc/$yEndUtc"

    $body = switch ($TemplateName) {

        'Degraded Conversations (MOS < 3.5)' {
            # Returns all voice conversations where the minimum MOS score across any
            # session was below 3.5 (the standard "Good" threshold).
            [ordered]@{
                interval  = $interval
                order     = 'asc'
                orderBy   = 'conversationStart'
                segmentFilters = @(
                    [ordered]@{
                        type       = 'and'
                        predicates = @(
                            [ordered]@{ type = 'dimension'; dimension = 'mediaType'; value = 'voice' }
                        )
                    }
                )
                metricFilters = @(
                    [ordered]@{
                        type    = 'and'
                        metrics = @(
                            [ordered]@{ metric = 'minMos'; range = [ordered]@{ lt = 3.5 } }
                        )
                    }
                )
            }
        }

        '480 Disconnect' {
            # Returns conversations where a segment ended with SIP error code 480
            # (Temporarily Unavailable) — typically agent or trunk unavailability.
            [ordered]@{
                interval  = $interval
                order     = 'asc'
                orderBy   = 'conversationStart'
                segmentFilters = @(
                    [ordered]@{
                        type       = 'and'
                        predicates = @(
                            [ordered]@{ type = 'dimension'; dimension = 'errorCode'; value = '480' }
                        )
                    }
                )
            }
        }

        '10+ Hold Segments' {
            # Returns conversations that contain at least one hold segment.
            # Post-filter locally for conversations with 10 or more hold segments.
            [ordered]@{
                interval  = $interval
                order     = 'asc'
                orderBy   = 'conversationStart'
                segmentFilters = @(
                    [ordered]@{
                        type       = 'and'
                        predicates = @(
                            [ordered]@{ type = 'dimension'; dimension = 'segmentType'; value = 'hold' }
                        )
                    }
                )
            }
        }

        'Queue Group Filter' {
            # Returns conversations where an ACD segment was served by a queue whose name
            # contains the specified text fragment.  Replace the value below with the
            # queue name fragment provided by the end user.
            $qValue = if (-not [string]::IsNullOrWhiteSpace($QueueGroupText)) {
                $QueueGroupText
            } else {
                'REPLACE_WITH_QUEUE_NAME_FRAGMENT'
            }
            [ordered]@{
                interval  = $interval
                order     = 'asc'
                orderBy   = 'conversationStart'
                segmentFilters = @(
                    [ordered]@{
                        type       = 'and'
                        predicates = @(
                            [ordered]@{ type = 'dimension'; dimension = 'queueName'; operator = 'contains'; value = $qValue }
                        )
                    }
                )
            }
        }

        'Abandoned Conversations' {
            # Returns conversations where the customer disconnected while waiting in an
            # ACD alert segment (i.e., before being connected to an agent).
            [ordered]@{
                interval  = $interval
                order     = 'asc'
                orderBy   = 'conversationStart'
                segmentFilters = @(
                    [ordered]@{
                        type       = 'and'
                        predicates = @(
                            [ordered]@{ type = 'dimension'; dimension = 'purpose';        value = 'acd'    }
                            [ordered]@{ type = 'dimension'; dimension = 'segmentType';    value = 'alert'  }
                            [ordered]@{ type = 'dimension'; dimension = 'disconnectType'; value = 'client' }
                        )
                    }
                )
            }
        }

        default { return '' }
    }

    return $body | ConvertTo-Json -Depth 20
}

function _ApplyQueryTemplate {
    <#
    .SYNOPSIS
        Reads the selected template from CmbQueryTemplate, builds the body JSON,
        sets the date pickers to yesterday, and populates TxtQueryBody.
    #>
    if ($null -eq $script:CmbQueryTemplate) { return }

    $sel = $script:CmbQueryTemplate.SelectedItem
    if ($null -eq $sel) { return }
    $name = [string]$sel.Content

    # Show / hide Queue Group input
    $isQueueGroup = $name -eq 'Queue Group Filter'
    $queueVis = if ($isQueueGroup) { 'Visible' } else { 'Collapsed' }
    $script:LblTemplateQueueGroup.Visibility = [System.Windows.Visibility]::$queueVis
    $script:TxtTemplateQueueGroup.Visibility = [System.Windows.Visibility]::$queueVis

    # Show / hide contextual note
    $noteText = switch ($name) {
        '10+ Hold Segments' {
            '⚠ The API returns all conversations with any hold segment. After loading, use the Conversations tab HasHold filter and manually count hold segments to find 10+.'
        }
        'Degraded Conversations (MOS < 3.5)' {
            '⚠ MOS metric filtering requires the Genesys Analytics API to support metricFilters. If results are unexpected, review voice conversations locally using the MOS Quality tab.'
        }
        default { '' }
    }
    if ($noteText) {
        $script:TxtTemplateNote.Text       = $noteText
        $script:TxtTemplateNote.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $script:TxtTemplateNote.Text       = ''
        $script:TxtTemplateNote.Visibility = [System.Windows.Visibility]::Collapsed
    }

    # Clear body and set date pickers if a real template was chosen
    if ($name -eq '(none — use form filters)') {
        $script:TxtQueryBody.Text = ''
        return
    }

    # Set date pickers to yesterday so the full-run date display is consistent
    $yesterday = [DateTime]::Today.AddDays(-1)
    $script:DtpStartDate.SelectedDate = $yesterday
    $script:DtpEndDate.SelectedDate   = $yesterday
    $script:TxtStartTime.Text = '00:00:00'
    $script:TxtEndTime.Text   = '23:59:59'

    $queueText = if ($isQueueGroup -and $null -ne $script:TxtTemplateQueueGroup) {
        $script:TxtTemplateQueueGroup.Text.Trim()
    } else { '' }

    $json = _BuildQueryTemplateBody -TemplateName $name -QueueGroupText $queueText
    $script:TxtQueryBody.Text = $json
}


function _GetDatasetParameters {
    # Body override — when TxtQueryBody contains JSON, use it directly and skip
    # all form-filter processing.  This supports both preview and full runs.
    if ($null -ne $script:TxtQueryBody) {
        $bodyText = $script:TxtQueryBody.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($bodyText)) {
            return @{ Body = $bodyText }
        }
    }

    $params = @{}
    $filterState = _GetCanonicalFilterState
    $range  = _GetQueryBoundaryDateTimes
    $startUtc = $null
    $endUtc = $null

    if ($null -ne $range.Start) {
        # Convert to UTC – WPF DatePicker yields DateTimeKind.Unspecified (treated as
        # local by ToUniversalTime).  The Genesys API expects UTC ISO-8601 timestamps.
        $startUtc = $range.Start.ToUniversalTime().ToString('o')
        $params['StartUtc'] = $startUtc
    }
    if ($null -ne $range.End) {
        $endUtc = $range.End.ToUniversalTime().ToString('o')
        $params['EndUtc'] = $endUtc
    }

    $selDir = $script:CmbDirection.SelectedItem
    if ($selDir -and $selDir.Content -ne '(all)') {
        $params['Direction'] = $selDir.Content
    }

    $selMedia = $script:CmbMediaType.SelectedItem
    if ($selMedia -and $selMedia.Content -ne '(all)') {
        $params['MediaType'] = $selMedia.Content
    }

    $q = $filterState.QueueText
    if ($q) { $params['Queue'] = $q }

    $convId = $filterState.ConversationId
    if ($convId) { $params['ConversationId'] = $convId }

    $userId = $script:TxtFilterUserId.Text.Trim()
    if ($userId) { $params['UserId'] = $userId }

    $divId = $filterState.DivisionId
    if ($divId) { $params['DivisionIds'] = @($divId) }

    if ($script:ChkExternalTagExists.IsChecked -eq $true) {
        $params['ConversationFilters'] = @(@{
            predicates = @(@{ dimension = 'externalTag'; operator = 'exists' })
        })
    }

    # ── Segment-level filters (flowName, messageType) ─────────────────────────
    $segPredicates = [System.Collections.Generic.List[hashtable]]::new()

    $flowName = $script:TxtFlowName.Text.Trim()
    if ($flowName) {
        $segPredicates.Add(@{ type = 'dimension'; dimension = 'flowName'; value = $flowName })
    }

    $selMsgType = $script:CmbMessageType.SelectedItem
    if ($selMsgType -and $selMsgType.Content -ne '(all)') {
        $segPredicates.Add(@{ type = 'dimension'; dimension = 'messageType'; value = $selMsgType.Content })
    }

    if ($segPredicates.Count -gt 0) {
        $params['SegmentFilters'] = @(@{ type = 'and'; predicates = $segPredicates.ToArray() })
    }

    $body = [ordered]@{
        order   = 'asc'
        orderBy = 'conversationStart'
    }

    if ($startUtc -and $endUtc) {
        $body.interval = "$startUtc/$endUtc"
    }

    $conversationPredicates = [System.Collections.Generic.List[object]]::new()
    if ($convId) {
        $conversationPredicates.Add([ordered]@{
            type      = 'dimension'
            dimension = 'conversationId'
            operator  = 'matches'
            value     = $convId
        }) | Out-Null
    }
    if ($divId) {
        $conversationPredicates.Add([ordered]@{
            type      = 'dimension'
            dimension = 'divisionId'
            operator  = 'matches'
            value     = $divId
        }) | Out-Null
    }
    if ($conversationPredicates.Count -gt 0) {
        $body.conversationFilters = @([ordered]@{
            type       = 'and'
            predicates = @($conversationPredicates.ToArray())
        })
    }

    if ($params.ContainsKey('SegmentFilters')) {
        $body.segmentFilters = $params['SegmentFilters']
    }

    $params['Body'] = $body

    return $params
}

function _SetRunning {
    param([bool]$IsRunning)
    $script:State.IsRunning = $IsRunning
    _Dispatch {
        $coreReady = Test-CoreInitialized
        $script:BtnRun.IsEnabled        = $coreReady -and (-not $IsRunning)
        $script:BtnPreviewRun.IsEnabled = $coreReady -and (-not $IsRunning)
        $script:BtnCancelRun.IsEnabled  = $IsRunning
        if (-not $IsRunning) {
            $script:PrgRun.Value = 0
        }
    }
}

function _StartRunInBackground {
    param(
        [string]$RunType,   # 'preview' | 'full'
        [hashtable]$DatasetParameters
    )
    if ($script:State.IsRunning) { return }

    $cfg     = Get-AppConfig
    $headers = Get-StoredHeaders
    if ($null -eq $headers -or $headers.Count -eq 0) {
        _SetStatus 'Not connected'
        [System.Windows.MessageBox]::Show('Connect to Genesys Cloud before starting a preview or full run.', 'Not Connected')
        return
    }

    # Resolve env-overridden paths (same logic as App.ps1)
    $corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
    $catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
    $schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
    $outputRoot  = $cfg.OutputRoot

    # Derive BaseUri from the stored connection (most accurate) else fall back to config region
    $connInfo = Get-ConnectionInfo
    $region   = if ($null -ne $connInfo -and $connInfo.Region) { $connInfo.Region } else { $cfg.Region }
    $baseUri  = "https://api.$region"
    $datasetKey = if ($RunType -eq 'preview') { 'analytics-conversation-details-query' } else { 'analytics-conversation-details' }

    $script:State.RunCancelled = $false
    # Clear any stale run folder so _PollBackgroundRun discovers the new one
    $script:State.CurrentRunFolder   = $null
    $script:State.DiagnosticsContext = $null
    $script:State.BackgroundRunDataset = $datasetKey
    $script:State.BackgroundRunOutputRoot = $outputRoot
    $script:State.BackgroundRunStartedUtc = [DateTime]::UtcNow
    $script:State.PendingRunConversationId = if ($DatasetParameters.ContainsKey('ConversationId')) {
        [string]$DatasetParameters['ConversationId']
    } else {
        ''
    }
    _SetRunning $true
    _Dispatch {
        $script:TxtRunStatus.Text   = "Starting $RunType run…"
        $script:TxtConsoleStatus.Text = 'Running'
        $script:TxtRunProgress.Text  = ''
        $script:DgRunEvents.ItemsSource = $null
        $script:TxtDiagnostics.Text  = ''
    }

    # Create runspace – must re-initialize CoreAdapter (module state is runspace-local)
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    $appDir = $script:UIAppDir

    [void]$ps.AddScript({
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $RunType, $DatasetParams, $Headers, $BaseUri)
        Set-StrictMode -Version Latest

        # Trace log — always written to $env:TEMP so it's readable even when
        # OutputRoot is misconfigured.  Each run overwrites the previous file.
        $traceFile = [System.IO.Path]::Combine($env:TEMP, 'genesys-run-trace.log')
        [System.IO.File]::WriteAllText($traceFile,
            "=== Genesys Run Trace  $([DateTime]::UtcNow.ToString('o')) ===`n",
            [System.Text.Encoding]::UTF8)
        $t = { param($m)
            [System.IO.File]::AppendAllText($traceFile,
                "[$(([DateTime]::UtcNow).ToString('HH:mm:ss.fff'))] $m`n",
                [System.Text.Encoding]::UTF8) }

        & $t "RunType     : $RunType"
        & $t "AppDir      : $AppDir"
        & $t "CorePath    : $CorePath"
        & $t "CatalogPath : $CatalogPath"
        & $t "SchemaPath  : $SchemaPath"
        & $t "OutputRoot  : $OutputRoot"
        & $t "BaseUri     : $BaseUri"
        & $t "Headers     : $(if ($null -ne $Headers -and $Headers.Count -gt 0) { "$($Headers.Count) key(s): $($Headers.Keys -join ', ')" } else { '(none — no auth token!)' })"

        try {
            $adapterPath = [System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')
            if (-not [System.IO.File]::Exists($adapterPath)) { throw "Core adapter not found at: $adapterPath" }
            & $t "Path checks OK"

            Import-Module ([System.IO.Path]::Combine($AppDir, 'modules', 'App.CoreAdapter.psm1')) -Force -ErrorAction Stop
            & $t "Core adapter imported"

            Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
            & $t "Core adapter initialized"

            if ($RunType -eq 'preview') {
                & $t "Calling Start-PreviewRun..."
                $result = Start-PreviewRun -DatasetParameters $DatasetParams -Headers $Headers -BaseUri $BaseUri
            } else {
                & $t "Calling Start-FullRun..."
                $result = Start-FullRun -DatasetParameters $DatasetParams -Headers $Headers -BaseUri $BaseUri
            }
            & $t "Core run returned"
            $result
        } catch {
            & $t "EXCEPTION : $_"
            & $t "StackTrace :`n$($_.ScriptStackTrace)"
            throw
        }
    })
    [void]$ps.AddArgument($appDir)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($RunType)
    [void]$ps.AddArgument($DatasetParameters)
    [void]$ps.AddArgument($headers)
    [void]$ps.AddArgument($baseUri)

    $asyncResult = $ps.BeginInvoke()

    $script:State.BackgroundRunspace = $rs
    $script:State.BackgroundRunJob   = @{ Ps = $ps; Async = $asyncResult }

    # Start polling timer
    $timer           = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval  = [System.TimeSpan]::FromMilliseconds(500)
    $script:State.PollingTimer = $timer

    $timer.Add_Tick({
        param($sender, $e)
        _PollBackgroundRun
    })
    $timer.Start()
}

function _PollBackgroundRun {
    $job  = $script:State.BackgroundRunJob
    if ($null -eq $job) { return }

    $ps    = $job.Ps
    $async = $job.Async

    # Update events display
    if ($null -ne $script:State.CurrentRunFolder) {
        $events = Get-RunEvents -RunFolder $script:State.CurrentRunFolder -LastN 50
        if ($events.Count -gt 0) {
            _Dispatch {
                $script:DgRunEvents.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($events)
            }
        }
    } else {
        $folder = _FindInProgressRunFolder `
            -OutputRoot $script:State.BackgroundRunOutputRoot `
            -DatasetKey $script:State.BackgroundRunDataset `
            -StartedAfterUtc $script:State.BackgroundRunStartedUtc
        if ($folder) {
            $script:State.CurrentRunFolder   = $folder
            $script:State.DiagnosticsContext = $folder
        }
    }

    # Show run status and elapsed time
    $statusText = if ($script:State.RunCancelled) { 'Cancelling…' } else { 'Running…' }
    $elapsed = if ($null -ne $script:State.BackgroundRunStartedUtc) {
        ([datetime]::UtcNow - $script:State.BackgroundRunStartedUtc).ToString('hh\:mm\:ss')
    } else { '' }
    _Dispatch {
        $script:TxtRunStatus.Text     = $statusText
        $script:TxtConsoleStatus.Text = $statusText
        if ($elapsed) { $script:TxtStatusRight.Text = $elapsed }
    }

    if (-not $async.IsCompleted) { return }

    # Run finished
    if ($null -ne $script:State.PollingTimer) {
        $script:State.PollingTimer.Stop()
        $script:State.PollingTimer = $null
    }

    $errors = $ps.Streams.Error
    $endInvokeFailure = $null
    $runResult = $null
    try {
        $runResult = $ps.EndInvoke($async)
    } catch {
        $endInvokeFailure = $_
    } finally {
        try { $ps.Dispose() } catch { }
        if ($null -ne $script:State.BackgroundRunspace) {
            try { $script:State.BackgroundRunspace.Close() } catch { }
        }
        $script:State.BackgroundRunJob   = $null
        $script:State.BackgroundRunspace = $null
    }

    _SetRunning $false

    # Prefer the completed run's actual output folder over any in-progress folder
    # discovered while polling.
    $resultFolder = _ResolveRunFolderFromResult -RunResult $runResult
    if (-not $resultFolder) {
        $resultFolder = _FindCompletedRunFolder `
            -OutputRoot $script:State.BackgroundRunOutputRoot `
            -DatasetKey $script:State.BackgroundRunDataset `
            -StartedAfterUtc $script:State.BackgroundRunStartedUtc
    }
    if ($resultFolder) {
        $script:State.CurrentRunFolder   = $resultFolder
        $script:State.DiagnosticsContext = $resultFolder
    }

    # Read trace log written by the background script (always in $env:TEMP).
    $traceText = ''
    $traceLogPath = [System.IO.Path]::Combine($env:TEMP, 'genesys-run-trace.log')
    if ([System.IO.File]::Exists($traceLogPath)) {
        try { $traceText = [System.IO.File]::ReadAllText($traceLogPath, [System.Text.Encoding]::UTF8) } catch { }
    }

    if ($null -ne $endInvokeFailure -or $errors.Count -gt 0) {
        $errParts = @()
        if ($null -ne $endInvokeFailure) { $errParts += $endInvokeFailure.ToString() }
        if ($errors.Count -gt 0) { $errParts += ($errors | ForEach-Object { $_.ToString() }) }
        $errText = ($errParts | Where-Object { $_ }) -join "`n"
        if ($traceText) { $errText = $traceText + "`n--- Error Stream ---`n" + $errText }
        _Dispatch {
            $script:TxtRunStatus.Text     = "Run failed"
            $script:TxtConsoleStatus.Text = "Failed"
            $script:TxtDiagnostics.Text   = $errText
        }
        $topError = if ($null -ne $endInvokeFailure) { $endInvokeFailure } elseif ($errors.Count -gt 0) { $errors[0] } else { 'Unknown background run failure' }
        _SetStatus "Run failed: $topError"
        $script:State.BackgroundRunDataset = ''
        $script:State.BackgroundRunOutputRoot = ''
        $script:State.BackgroundRunStartedUtc = $null
        $script:State.PendingRunConversationId = ''
        return
    }

    # Load run results
    $preferredConversationId = [string]$script:State.PendingRunConversationId
    $runLoadResult = $null
    if ($null -ne $script:State.CurrentRunFolder) {
        Add-RecentRun -RunFolder $script:State.CurrentRunFolder
        _RefreshRecentRuns
        $runLoadResult = _LoadRunAndRefreshGrid `
            -RunFolder $script:State.CurrentRunFolder `
            -PreferredConversationId $preferredConversationId `
            -PreserveRunFilters

        # Auto-import into the active case in the background so the UI stays responsive.
        if ((Test-DatabaseInitialized) -and -not [string]::IsNullOrEmpty($script:State.ActiveCaseId)) {
            _StartAutoImportInBackground `
                -CaseId                  $script:State.ActiveCaseId `
                -CaseName                $script:State.ActiveCaseName `
                -RunFolder               $script:State.CurrentRunFolder `
                -PreferredConversationId $preferredConversationId `
                -RunLoadResult           $runLoadResult
        }
    }

    $healthText = ''
    if ($null -ne $script:State.CurrentRunFolder) {
        try {
            $health = Test-ConversationDisplayPipeline `
                -RunFolder $script:State.CurrentRunFolder `
                -CaseId $script:State.ActiveCaseId `
                -PreferredConversationId $preferredConversationId
            $healthText = @(
                '=== Post-Run Display Health ==='
                "RunFolderExists       : $($health.RunFolderExists)"
                "ManifestExists        : $($health.ManifestExists)"
                "SummaryExists         : $($health.SummaryExists)"
                "DataDirectoryExists   : $($health.DataDirectoryExists)"
                "DataFileCount         : $($health.DataFileCount)"
                "DataRecordCount       : $($health.DataRecordCount)"
                "IndexRecordCount      : $($health.IndexRecordCount)"
                "FirstConversationId   : $($health.FirstConversationId)"
                "CaseImportAttempted   : $($health.CaseImportAttempted)"
                "CaseConversationCount : $($health.CaseConversationCount)"
                "DbPageRowCount        : $($health.DbPageRowCount)"
                "DrilldownResolvable   : $($health.DrilldownResolvable)"
                "Errors                : $(if ($health.Errors.Count -gt 0) { $health.Errors -join '; ' } else { '' })"
                "Warnings              : $(if ($health.Warnings.Count -gt 0) { $health.Warnings -join '; ' } else { '' })"
            ) -join [Environment]::NewLine
        } catch {
            $healthText = "=== Post-Run Display Health ===`nHealth check failed: $($_.Exception.Message)"
        }
    }

    $diagText = if ($null -ne $script:State.DiagnosticsContext) {
        Get-DiagnosticsText -RunFolder $script:State.DiagnosticsContext
    } else { '(no run folder found — check trace above)' }
    if ($traceText) { $diagText = $traceText + "`n" + $diagText }
    if ($healthText) { $diagText = $diagText + "`n`n" + $healthText }
    $uiDiagnosticText = if ($null -ne $script:TxtDiagnostics) { [string]$script:TxtDiagnostics.Text } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($uiDiagnosticText) -and $diagText -notlike "*$uiDiagnosticText*") {
        $diagText = $diagText + "`n`n=== UI Display Diagnostics ===`n" + $uiDiagnosticText
    }
    _Dispatch {
        $script:TxtRunStatus.Text     = 'Run complete'
        $script:TxtConsoleStatus.Text = 'Complete'
        $script:TxtDiagnostics.Text   = $diagText
    }
    _SetStatus 'Run complete'

    $script:State.BackgroundRunDataset = ''
    $script:State.BackgroundRunOutputRoot = ''
    $script:State.BackgroundRunStartedUtc = $null
    $script:State.PendingRunConversationId = ''
}

function _CancelBackgroundRun {
    if (-not $script:State.IsRunning) { return }
    $script:State.RunCancelled = $true

    $job = $script:State.BackgroundRunJob
    if ($null -ne $job) {
        try { $job.Ps.Stop()    } catch { }
        try { $job.Ps.Dispose() } catch { }
    }
    if ($null -ne $script:State.BackgroundRunspace) {
        try { $script:State.BackgroundRunspace.Close()   } catch { }
        try { $script:State.BackgroundRunspace.Dispose() } catch { }
    }
    $script:State.BackgroundRunJob   = $null
    $script:State.BackgroundRunspace = $null
    $script:State.BackgroundRunDataset = ''
    $script:State.BackgroundRunOutputRoot = ''
    $script:State.BackgroundRunStartedUtc = $null

    if ($null -ne $script:State.PollingTimer) {
        try { $script:State.PollingTimer.Stop() } catch { }
        $script:State.PollingTimer = $null
    }
    _SetRunning $false
    _Dispatch {
        $script:TxtRunStatus.Text     = 'Run cancelled'
        $script:TxtConsoleStatus.Text = 'Cancelled'
    }
    _SetStatus 'Run cancelled'
}

# ── Connect dialog ─────────────────────────────────────────────────────────────

function _ShowConnectDialog {
    $cfg     = Get-AppConfig
    $dialog  = New-Object System.Windows.Window
    $dialog.Title   = 'Connect to Genesys Cloud'
    $dialog.Width   = 440
    $dialog.Height  = 360
    $dialog.Owner   = $script:Window
    $dialog.WindowStartupLocation = 'CenterOwner'
    $bc = [System.Windows.Media.BrushConverter]::new()
    $dialog.Background = $bc.ConvertFromString('#1E1E2E')
    $dialog.Foreground = $bc.ConvertFromString('#CDD6F4')

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = [System.Windows.Thickness]::new(16)

    function _AddLbl { param($t) $lbl = New-Object System.Windows.Controls.TextBlock; $lbl.Text = $t; $lbl.Margin = [System.Windows.Thickness]::new(0,6,0,2); $sp.Children.Add($lbl) | Out-Null }
    function _AddTxt { param($name,$ph) $tb = New-Object System.Windows.Controls.TextBox; $tb.Name=$name; $tb.Height=28; $tb.Tag=$ph; $sp.Children.Add($tb) | Out-Null; return $tb }
    function _AddPwd { $pw = New-Object System.Windows.Controls.PasswordBox; $pw.Height=28; $sp.Children.Add($pw) | Out-Null; return $pw }

    _AddLbl 'Region (e.g. mypurecloud.com)'
    $tbRegion = _AddTxt 'tbRegion' 'mypurecloud.com'
    $tbRegion.Text = $cfg.Region

    _AddLbl 'Client ID'
    $tbClientId = _AddTxt 'tbClientId' ''
    $tbClientId.Text = $cfg.PkceClientId

    _AddLbl 'Client Secret (leave empty for PKCE)'
    $pwSecret = _AddPwd

    $pnlBtns = New-Object System.Windows.Controls.StackPanel
    $pnlBtns.Orientation = 'Horizontal'
    $pnlBtns.HorizontalAlignment = 'Right'
    $pnlBtns.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)

    $btnPkce = New-Object System.Windows.Controls.Button
    $btnPkce.Content = 'Browser / PKCE'
    $btnPkce.Width   = 130; $btnPkce.Height = 30; $btnPkce.Margin = [System.Windows.Thickness]::new(0,0,8,0)

    $btnLogin = New-Object System.Windows.Controls.Button
    $btnLogin.Content = 'Login'
    $btnLogin.Width   = 80; $btnLogin.Height = 30; $btnLogin.Margin = [System.Windows.Thickness]::new(0,0,8,0)

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = 'Cancel'
    $btnCancel.Width   = 70; $btnCancel.Height = 30

    $pnlBtns.Children.Add($btnPkce)   | Out-Null
    $pnlBtns.Children.Add($btnLogin)  | Out-Null
    $pnlBtns.Children.Add($btnCancel) | Out-Null
    $sp.Children.Add($pnlBtns) | Out-Null

    $dialog.Content = $sp

    $btnLogin.Add_Click({
        $region   = $tbRegion.Text.Trim()
        $clientId = $tbClientId.Text.Trim()
        $secret   = $pwSecret.Password
        if (-not $region -or -not $clientId -or -not $secret) {
            [System.Windows.MessageBox]::Show('Region, Client ID, and Secret are required for client-credentials login.', 'Validation')
            return
        }
        try {
            Connect-GenesysCloudApp -ClientId $clientId -ClientSecret $secret -Region $region | Out-Null
            Update-AppConfig -Key 'Region' -Value $region
            _UpdateConnectionStatus
            _SetStatus "Connected ($region)"
            $dialog.Close()
        } catch {
            [System.Windows.MessageBox]::Show("Login failed: $_", 'Error')
        }
    })

    $btnPkce.Add_Click({
        $region   = $tbRegion.Text.Trim()
        $clientId = $tbClientId.Text.Trim()
        if (-not $region -or -not $clientId) {
            [System.Windows.MessageBox]::Show('Region and Client ID are required for PKCE login.', 'Validation')
            return
        }
        $cfg2       = Get-AppConfig
        $redirectUri = if ($cfg2.PkceRedirectUri) { $cfg2.PkceRedirectUri } else { 'http://localhost:8080/callback' }

        $dialog.Close()

        # Run PKCE in a separate runspace so it doesn't block the UI
        $cts = New-Object System.Threading.CancellationTokenSource
        $script:State.PkceCancel = $cts

        $rs2  = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace(); $rs2.Open()
        $ps2  = [System.Management.Automation.PowerShell]::Create(); $ps2.Runspace = $rs2
        $authModPath = [System.IO.Path]::Combine((Get-CoreSiblingRoot), 'modules', 'Genesys.Auth', 'Genesys.Auth.psm1')
        [void]$ps2.AddScript({
            param($AuthModPath, $ClientId, $Region, $RedirectUri, $CancelToken)
            Import-Module $AuthModPath -Force
            Connect-GenesysCloudPkce -ClientId $ClientId -Region $Region `
                -RedirectUri $RedirectUri -CancellationToken $CancelToken
        })
        [void]$ps2.AddArgument($authModPath)
        [void]$ps2.AddArgument($clientId)
        [void]$ps2.AddArgument($region)
        [void]$ps2.AddArgument($redirectUri)
        [void]$ps2.AddArgument($cts.Token)

        $ar2 = $ps2.BeginInvoke()

        # Poll for PKCE completion.
        # GetNewClosure captures local variables but breaks the scope chain for script-local
        # function lookups (_UpdateConnectionStatus, _SetStatus, _Dispatch). Fix: capture
        # the needed UI control references as local variables and inline the UI updates
        # directly — DispatcherTimer fires on the UI thread so no _Dispatch marshalling needed.
        $capturedState    = $script:State
        $capturedLblConn  = $script:LblConnectionStatus
        $capturedElpConn  = $script:ElpConnStatus
        $capturedTxtMain  = $script:TxtStatusMain
        $capturedTxtRight = $script:TxtStatusRight
        $pkceTimer = New-Object System.Windows.Threading.DispatcherTimer
        $pkceTimer.Interval = [System.TimeSpan]::FromSeconds(1)
        $pkceTimer.Add_Tick(({
            if (-not $ar2.IsCompleted) { return }
            $pkceTimer.Stop()
            try {
                $ps2.EndInvoke($ar2) | Out-Null
                $info = Get-ConnectionInfo
                if ($null -ne $info) {
                    $exp = $info.ExpiresAt.ToString('HH:mm:ss') + ' UTC'
                    $capturedLblConn.Text = "$($info.Region)  |  $($info.Flow)  |  expires $exp"
                    $capturedElpConn.Fill = [System.Windows.Media.Brushes]::LightGreen
                }
                Update-AppConfig -Key 'Region' -Value $region
                Update-AppConfig -Key 'PkceClientId' -Value $clientId
                $capturedTxtMain.Text  = "Connected via PKCE ($region)"
                $capturedTxtRight.Text = ''
            } catch {
                [System.Windows.MessageBox]::Show("PKCE login failed: $_", 'Error')
            } finally {
                try { $rs2.Close()   } catch { }
                try { $rs2.Dispose() } catch { }
                try { $ps2.Dispose() } catch { }
                try { $cts.Dispose() } catch { }
                $capturedState['PkceCancel'] = $null
            }
        }).GetNewClosure())
        $pkceTimer.Start()
    })

    $btnCancel.Add_Click({ $dialog.Close() })
    $dialog.ShowDialog() | Out-Null
}

# ── Settings dialog ─────────────────────────────────────────────────────────

function _ShowSettingsDialog {
    $cfg    = Get-AppConfig
    $dialog = New-Object System.Windows.Window
    $dialog.Title  = 'Settings'
    $dialog.Width  = 600; $dialog.Height = 580
    $dialog.Owner  = $script:Window
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.ResizeMode = 'NoResize'

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = [System.Windows.Thickness]::new(16)
    $scroll.Content = $sp

    # ── helpers ───────────────────────────────────────────────────────────────

    function _SectionHead { param($text)
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $text
        $tb.FontWeight = 'Bold'
        $tb.Margin = [System.Windows.Thickness]::new(0, 12, 0, 2)
        $sep = New-Object System.Windows.Controls.Separator
        $sep.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $sp.Children.Add($tb)  | Out-Null
        $sp.Children.Add($sep) | Out-Null
    }

    # Plain label + textbox row
    function _Row { param($label, $val)
        $g = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new(160)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
        $g.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
        $lbl = New-Object System.Windows.Controls.TextBlock; $lbl.Text = $label; $lbl.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
        $tb = New-Object System.Windows.Controls.TextBox; $tb.Text = $val; $tb.Height = 26
        [System.Windows.Controls.Grid]::SetColumn($tb, 1)
        $g.Children.Add($lbl) | Out-Null; $g.Children.Add($tb) | Out-Null
        $sp.Children.Add($g)  | Out-Null
        return $tb
    }

    # Label + textbox + Browse button row (for file paths)
    function _BrowseRow { param($label, $val, $filter)
        $g = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::new(160)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::new(70)
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)
        $g.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
        $lbl = New-Object System.Windows.Controls.TextBlock; $lbl.Text = $label; $lbl.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
        $tb = New-Object System.Windows.Controls.TextBox; $tb.Text = $val; $tb.Height = 26
        [System.Windows.Controls.Grid]::SetColumn($tb, 1)
        $btn = New-Object System.Windows.Controls.Button; $btn.Content = 'Browse…'; $btn.Height = 26; $btn.Margin = [System.Windows.Thickness]::new(4, 0, 0, 0)
        [System.Windows.Controls.Grid]::SetColumn($btn, 2)
        $capturedTb     = $tb
        $capturedFilter = $filter
        $btn.Add_Click({
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = $capturedFilter
            $dlg.Title  = "Select $label"
            $dlg.CheckFileExists = $true
            if ($dlg.ShowDialog()) { $capturedTb.Text = $dlg.FileName }
        }.GetNewClosure())
        $g.Children.Add($lbl) | Out-Null; $g.Children.Add($tb) | Out-Null; $g.Children.Add($btn) | Out-Null
        $sp.Children.Add($g)  | Out-Null
        return $tb
    }

    function _ResolveSettingsPath {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

        $trimmed = $Path.Trim()
        try {
            if ([System.IO.Path]::IsPathRooted($trimmed)) {
                return [System.IO.Path]::GetFullPath($trimmed)
            }
            return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($script:UIAppDir, $trimmed))
        } catch {
            return $trimmed
        }
    }

    function _GetCoreCompanionInfo {
        param([string]$CoreModulePath)

        $fullCorePath = _ResolveSettingsPath $CoreModulePath
        if ([string]::IsNullOrWhiteSpace($fullCorePath)) { return $null }

        $moduleDir = [System.IO.Path]::GetDirectoryName($fullCorePath)
        if ([string]::IsNullOrWhiteSpace($moduleDir)) { return $null }

        $modulesDir = [System.IO.Path]::GetDirectoryName($moduleDir)
        if ([string]::IsNullOrWhiteSpace($modulesDir)) { return $null }

        if ([System.IO.Path]::GetFileName($moduleDir) -ne 'Genesys.Core') { return $null }
        if ([System.IO.Path]::GetFileName($modulesDir) -ne 'modules') { return $null }

        $repoRoot = [System.IO.Path]::GetDirectoryName($modulesDir)
        if ([string]::IsNullOrWhiteSpace($repoRoot)) { return $null }

        $catalogPath = [System.IO.Path]::Combine($repoRoot, 'catalog', 'genesys.catalog.json')
        $schemaPath  = [System.IO.Path]::Combine($repoRoot, 'catalog', 'schema', 'genesys.catalog.schema.json')

        return [pscustomobject]@{
            RepoRoot    = $repoRoot
            CatalogPath = $catalogPath
            SchemaPath  = $schemaPath
            HasCatalog  = [System.IO.File]::Exists($catalogPath)
            HasSchema   = [System.IO.File]::Exists($schemaPath)
        }
    }

    function _GetRepoRootFromCatalogPath {
        param([string]$CatalogPath)

        $fullPath = _ResolveSettingsPath $CatalogPath
        if ([string]::IsNullOrWhiteSpace($fullPath)) { return $null }

        $catalogDir = [System.IO.Path]::GetDirectoryName($fullPath)
        if ([string]::IsNullOrWhiteSpace($catalogDir)) { return $null }

        if ([System.IO.Path]::GetFileName($fullPath) -ne 'genesys.catalog.json') { return $null }
        if ([System.IO.Path]::GetFileName($catalogDir) -ne 'catalog') { return $null }

        return [System.IO.Path]::GetDirectoryName($catalogDir)
    }

    function _GetRepoRootFromSchemaPath {
        param([string]$SchemaPath)

        $fullPath = _ResolveSettingsPath $SchemaPath
        if ([string]::IsNullOrWhiteSpace($fullPath)) { return $null }

        $schemaDir = [System.IO.Path]::GetDirectoryName($fullPath)
        if ([string]::IsNullOrWhiteSpace($schemaDir)) { return $null }
        $catalogDir = [System.IO.Path]::GetDirectoryName($schemaDir)
        if ([string]::IsNullOrWhiteSpace($catalogDir)) { return $null }

        if ([System.IO.Path]::GetFileName($fullPath) -ne 'genesys.catalog.schema.json') { return $null }
        if ([System.IO.Path]::GetFileName($schemaDir) -ne 'schema') { return $null }
        if ([System.IO.Path]::GetFileName($catalogDir) -ne 'catalog') { return $null }

        return [System.IO.Path]::GetDirectoryName($catalogDir)
    }

    function _SyncCoreCompanionPaths {
        param([switch]$UpdateStatus)

        $coreInfo = _GetCoreCompanionInfo -CoreModulePath $tbCorePath.Text
        if ($null -eq $coreInfo) { return $false }

        $updated = $false

        $catalogPath = _ResolveSettingsPath $tbCatalogPath.Text
        $catalogRoot = _GetRepoRootFromCatalogPath -CatalogPath $catalogPath
        $shouldSyncCatalog = $coreInfo.HasCatalog -and (
            [string]::IsNullOrWhiteSpace($catalogPath) -or
            -not [System.IO.File]::Exists($catalogPath) -or
            ($null -ne $catalogRoot -and -not $catalogRoot.Equals($coreInfo.RepoRoot, [System.StringComparison]::OrdinalIgnoreCase))
        )
        if ($shouldSyncCatalog -and -not $catalogPath.Equals($coreInfo.CatalogPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tbCatalogPath.Text = $coreInfo.CatalogPath
            $updated = $true
        }

        $schemaPath = _ResolveSettingsPath $tbSchemaPath.Text
        $schemaRoot = _GetRepoRootFromSchemaPath -SchemaPath $schemaPath
        $shouldSyncSchema = $coreInfo.HasSchema -and (
            [string]::IsNullOrWhiteSpace($schemaPath) -or
            -not [System.IO.File]::Exists($schemaPath) -or
            ($null -ne $schemaRoot -and -not $schemaRoot.Equals($coreInfo.RepoRoot, [System.StringComparison]::OrdinalIgnoreCase))
        )
        if ($shouldSyncSchema -and -not $schemaPath.Equals($coreInfo.SchemaPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tbSchemaPath.Text = $coreInfo.SchemaPath
            $updated = $true
        }

        if ($updated -and $UpdateStatus) {
            $lblCoreStatus.Text       = 'Catalog and schema matched to the selected Core module.'
            $lblCoreStatus.Foreground = [System.Windows.Media.Brushes]::DarkGoldenrod
        }

        return $updated
    }

    # ── General ───────────────────────────────────────────────────────────────
    _SectionHead 'General'
    $tbPageSize     = _Row 'Page size'          $cfg.PageSize
    $tbPrevPageSize = _Row 'Preview page size'  $cfg.PreviewPageSize
    $tbRegion       = _Row 'Region'             $cfg.Region

    # ── Storage ───────────────────────────────────────────────────────────────
    _SectionHead 'Storage'
    $tbOutputRoot   = _Row 'Output root'        $cfg.OutputRoot
    $tbDatabasePath = _Row 'Database path'      $cfg.DatabasePath
    $tbSqliteDll    = _Row 'SQLite DLL path'    $cfg.SqliteDllPath

    # ── Genesys.Core ──────────────────────────────────────────────────────────
    _SectionHead 'Genesys.Core'
    $tbCorePath    = _BrowseRow 'Core module (.psd1)'  $cfg.CoreModulePath  'PowerShell module (*.psd1)|*.psd1|All files (*.*)|*.*'
    $tbCatalogPath = _BrowseRow 'Catalog (.json)'      $cfg.CatalogPath     'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $tbSchemaPath  = _BrowseRow 'Schema (.json)'       $cfg.SchemaPath      'JSON files (*.json)|*.json|All files (*.*)|*.*'

    # Status label – shows result of re-init attempt on Save
    $lblCoreStatus = New-Object System.Windows.Controls.TextBlock
    $lblCoreStatus.Margin     = [System.Windows.Thickness]::new(0, 6, 0, 0)
    $lblCoreStatus.TextWrapping = 'Wrap'
    if (Test-CoreInitialized) {
        $lblCoreStatus.Text       = 'Core is initialized.'
        $lblCoreStatus.Foreground = [System.Windows.Media.Brushes]::DarkGreen
    } else {
        $lblCoreStatus.Text       = 'Core is NOT initialized – set paths above and click Save.'
        $lblCoreStatus.Foreground = [System.Windows.Media.Brushes]::Firebrick
    }
    $sp.Children.Add($lblCoreStatus) | Out-Null

    $tbCorePath.Add_TextChanged({
        [void](_SyncCoreCompanionPaths -UpdateStatus)
    })

    # ── Authentication ────────────────────────────────────────────────────────
    _SectionHead 'Authentication'
    $tbPkceClientId = _Row 'PKCE client ID'    $cfg.PkceClientId
    $tbPkceRedirect = _Row 'PKCE redirect URI' $cfg.PkceRedirectUri

    # ── Buttons ───────────────────────────────────────────────────────────────
    $pnlBtns = New-Object System.Windows.Controls.StackPanel
    $pnlBtns.Orientation = 'Horizontal'; $pnlBtns.HorizontalAlignment = 'Right'
    $pnlBtns.Margin = [System.Windows.Thickness]::new(0, 14, 0, 0)

    $btnSave    = New-Object System.Windows.Controls.Button; $btnSave.Content = 'Save';   $btnSave.Width = 80; $btnSave.Height = 30; $btnSave.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $btnCancelS = New-Object System.Windows.Controls.Button; $btnCancelS.Content = 'Cancel'; $btnCancelS.Width = 70; $btnCancelS.Height = 30
    $pnlBtns.Children.Add($btnSave)    | Out-Null
    $pnlBtns.Children.Add($btnCancelS) | Out-Null
    $sp.Children.Add($pnlBtns) | Out-Null

    $dialog.Content = $scroll

    # ── Save handler ──────────────────────────────────────────────────────────
    $btnSave.Add_Click({
        try {
            $tbCorePath.Text    = _ResolveSettingsPath $tbCorePath.Text
            $tbCatalogPath.Text = _ResolveSettingsPath $tbCatalogPath.Text
            $tbSchemaPath.Text  = _ResolveSettingsPath $tbSchemaPath.Text
            [void](_SyncCoreCompanionPaths -UpdateStatus)

            $cfg2 = Get-AppConfig
            $cfg2 | Add-Member -NotePropertyName 'PageSize'        -NotePropertyValue ([int]$tbPageSize.Text)      -Force
            $cfg2 | Add-Member -NotePropertyName 'PreviewPageSize' -NotePropertyValue ([int]$tbPrevPageSize.Text)  -Force
            $cfg2 | Add-Member -NotePropertyName 'Region'          -NotePropertyValue $tbRegion.Text.Trim()        -Force
            $cfg2 | Add-Member -NotePropertyName 'OutputRoot'      -NotePropertyValue $tbOutputRoot.Text.Trim()    -Force
            $cfg2 | Add-Member -NotePropertyName 'DatabasePath'    -NotePropertyValue $tbDatabasePath.Text.Trim()  -Force
            $cfg2 | Add-Member -NotePropertyName 'SqliteDllPath'   -NotePropertyValue $tbSqliteDll.Text.Trim()     -Force
            $cfg2 | Add-Member -NotePropertyName 'CoreModulePath'  -NotePropertyValue $tbCorePath.Text.Trim()      -Force
            $cfg2 | Add-Member -NotePropertyName 'CatalogPath'     -NotePropertyValue $tbCatalogPath.Text.Trim()   -Force
            $cfg2 | Add-Member -NotePropertyName 'SchemaPath'      -NotePropertyValue $tbSchemaPath.Text.Trim()    -Force
            $cfg2 | Add-Member -NotePropertyName 'PkceClientId'          -NotePropertyValue $tbPkceClientId.Text.Trim()     -Force
            $cfg2 | Add-Member -NotePropertyName 'PkceRedirectUri'       -NotePropertyValue $tbPkceRedirect.Text.Trim()     -Force
            Save-AppConfig -Config $cfg2
            $script:State.PageSize = [int]$tbPageSize.Text

            # Re-initialize Genesys.Core with the saved paths
            try {
                Initialize-CoreAdapter `
                    -CoreModulePath $tbCorePath.Text.Trim() `
                    -CatalogPath    $tbCatalogPath.Text.Trim() `
                    -OutputRoot     $cfg2.OutputRoot `
                    -SchemaPath     $tbSchemaPath.Text.Trim()
                $script:CoreInitError = ''
                $lblCoreStatus.Text       = 'Core initialized successfully.'
                $lblCoreStatus.Foreground = [System.Windows.Media.Brushes]::DarkGreen
                $dialog.Close()
                _RefreshCoreState
                _SetStatus 'Settings saved – Genesys.Core initialized'
            } catch {
                $script:CoreInitError     = [string]$_
                $lblCoreStatus.Text       = "Core init failed: $_"
                $lblCoreStatus.Foreground = [System.Windows.Media.Brushes]::Firebrick
                # Leave dialog open so the user can correct the paths
            }
        } catch {
            [System.Windows.MessageBox]::Show("Save failed: $_", 'Error')
        }
    })
    $btnCancelS.Add_Click({ $dialog.Close() })
    $dialog.ShowDialog() | Out-Null
}

# ── Export actions ────────────────────────────────────────────────────────────

function _ExportPageCsv {
    if ($null -eq $script:State.CurrentRunFolder) { _SetStatus 'No run loaded'; return }

    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title      = 'Export Page to CSV'
    $dlg.Filter     = 'CSV files (*.csv)|*.csv'
    $dlg.FileName   = "page_$($script:State.CurrentPage).csv"
    if (-not $dlg.ShowDialog()) { return }

    $idx      = @($script:State.CurrentIndex)
    $page     = $script:State.CurrentPage
    $pageSize = $script:State.PageSize
    $startIdx = ($page - 1) * $pageSize
    $endIdx   = [math]::Min($startIdx + $pageSize - 1, $idx.Count - 1)
    if ($startIdx -gt $endIdx) { return }

    $entries  = @($idx[$startIdx..$endIdx])
    $records  = @(Get-IndexedPage -RunFolder $script:State.CurrentRunFolder -IndexEntries $entries)
    Export-PageToCsv -Records $records -OutputPath $dlg.FileName
    _SetStatus "Exported page to $($dlg.FileName)"
}

function _ExportRunCsv {
    if ($null -eq $script:State.CurrentRunFolder) { _SetStatus 'No run loaded'; return }

    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title    = 'Export Full Run to CSV'
    $dlg.Filter   = 'CSV files (*.csv)|*.csv'
    $dlg.FileName = "run_export.csv"
    if (-not $dlg.ShowDialog()) { return }

    try {
        _SetStatus 'Exporting…'
        Export-RunToCsv -RunFolder $script:State.CurrentRunFolder -OutputPath $dlg.FileName
        _SetStatus "Exported full run to $($dlg.FileName)"
    } catch {
        [System.Windows.MessageBox]::Show("Export failed: $_", 'Error')
        _SetStatus 'Export failed'
    }
}

function _ExportConversationJson {
    if ($null -eq $script:State.CurrentRunFolder) { return }
    $convId = $script:LblSelectedConversation.Text
    if ($convId -eq '(none selected)' -or [string]::IsNullOrEmpty($convId)) { return }

    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title    = 'Export Conversation to JSON'
    $dlg.Filter   = 'JSON files (*.json)|*.json'
    $dlg.FileName = "$convId.json"
    if (-not $dlg.ShowDialog()) { return }

    $record = Get-ConversationRecord -RunFolder $script:State.CurrentRunFolder -ConversationId $convId
    if ($null -eq $record) { _SetStatus 'Conversation not found'; return }
    Export-ConversationToJson -Record $record -OutputPath $dlg.FileName
    _SetStatus "Exported conversation to $($dlg.FileName)"
}

# ── Attribute search filter ────────────────────────────────────────────────────

function _FilterAttributes {
    $search = $script:TxtAttributeSearch.Text.Trim().ToLowerInvariant()
    $all    = $script:DgAttributes.Tag   # stored on Tag
    if ($null -eq $all) { return }
    if (-not $search) {
        $script:DgAttributes.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($all)
        return
    }
    $filtered = @($all | Where-Object { $_.Name -like "*$search*" -or $_.Value -like "*$search*" })
    $script:DgAttributes.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($filtered)
}

# ── Event wire-up ─────────────────────────────────────────────────────────────

$script:BtnConnect.Add_Click({ _ShowConnectDialog })

$script:BtnSettings.Add_Click({ _ShowSettingsDialog })

$script:BtnManageCase.Add_Click({ _ShowCaseDialog | Out-Null })

$script:BtnImportRun.Add_Click({ _ImportCurrentRunToCase })

$script:BtnRefreshRefData.Add_Click({ _StartRefreshReferenceDataJob })

if ($null -ne $script:BtnPullQueuePerfReport) {
    $script:BtnPullQueuePerfReport.Add_Click({ _StartQueuePerfReportJob })
}

if ($null -ne $script:CmbQueuePerfDivision) {
    $script:CmbQueuePerfDivision.Add_SelectionChanged({ _RenderQueuePerfGrid })
}

if ($null -ne $script:BtnPullAgentPerfReport) {
    $script:BtnPullAgentPerfReport.Add_Click({ _StartAgentPerfReportJob })
}

if ($null -ne $script:CmbAgentPerfDivision) {
    $script:CmbAgentPerfDivision.Add_SelectionChanged({ _RenderAgentPerfGrid })
}

if ($null -ne $script:BtnPullTransferReport) {
    $script:BtnPullTransferReport.Add_Click({ _StartTransferReportJob })
}

if ($null -ne $script:CmbTransferType) {
    _EnsureTransferTypeFilter
    $script:CmbTransferType.Add_SelectionChanged({ _RenderTransferGrid })
}

if ($null -ne $script:DgTransferChains) {
    $script:DgTransferChains.Add_SelectionChanged({ _OpenTransferChainConversation })
}

if ($null -ne $script:BtnPullFlowContainmentReport) {
    $script:BtnPullFlowContainmentReport.Add_Click({ _StartFlowContainmentReportJob })
}

if ($null -ne $script:CmbFlowType) {
    _EnsureFlowTypeFilter
    $script:CmbFlowType.Add_SelectionChanged({ _RenderFlowContainmentGrid })
}

if ($null -ne $script:DgFlowPerf) {
    $script:DgFlowPerf.Add_SelectionChanged({ _RenderSelectedFlowDetail })
}

if ($null -ne $script:BtnPullWrapupReport) {
    $script:BtnPullWrapupReport.Add_Click({ _StartWrapupDistributionReportJob })
}

if ($null -ne $script:DgWrapupCodes) {
    $script:DgWrapupCodes.Add_SelectionChanged({ _RenderSelectedWrapupDetail })
}

if ($null -ne $script:BtnPullQualityReport) {
    $script:BtnPullQualityReport.Add_Click({ _StartQualityOverlayReportJob })
}

if ($null -ne $script:DgLowScoreConversations) {
    $script:DgLowScoreConversations.Add_SelectionChanged({ _OpenLowScoreConversation })
}

# ── Query Template event handlers ─────────────────────────────────────────────

if ($null -ne $script:CmbQueryTemplate) {
    $script:CmbQueryTemplate.Add_SelectionChanged({ _ApplyQueryTemplate })
}

if ($null -ne $script:TxtTemplateQueueGroup) {
    $script:TxtTemplateQueueGroup.Add_TextChanged({
        # Re-build body when queue group text changes while Queue Group Filter is selected
        $sel = $script:CmbQueryTemplate.SelectedItem
        if ($null -ne $sel -and [string]$sel.Content -eq 'Queue Group Filter') {
            $queueText = $script:TxtTemplateQueueGroup.Text.Trim()
            $json = _BuildQueryTemplateBody -TemplateName 'Queue Group Filter' -QueueGroupText $queueText
            $script:TxtQueryBody.Text = $json
        }
    })
}

if ($null -ne $script:BtnClearQueryBody) {
    $script:BtnClearQueryBody.Add_Click({
        $script:TxtQueryBody.Text = ''
        # Reset template selector to (none)
        if ($null -ne $script:CmbQueryTemplate -and $script:CmbQueryTemplate.Items.Count -gt 0) {
            $script:CmbQueryTemplate.SelectedIndex = 0
        }
    })
}

$script:BtnRun.Add_Click({
    try {
        $params = _GetDatasetParameters
        _StartRunInBackground -RunType 'full' -DatasetParameters $params
    } catch {
        _SetStatus 'Invalid date/time range'
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Validation')
    }
})

$script:BtnPreviewRun.Add_Click({
    $pageSizeText = $script:TxtPreviewPageSize.Text.Trim()
    $previewSize  = 25
    if ($pageSizeText -match '^\d+$') { $previewSize = [int]$pageSizeText }
    try {
        $params = _GetDatasetParameters
        $params['PageSize'] = $previewSize
        _StartRunInBackground -RunType 'preview' -DatasetParameters $params
    } catch {
        _SetStatus 'Invalid date/time range'
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Validation')
    }
})

$script:BtnCancelRun.Add_Click({ _CancelBackgroundRun })

$script:BtnSearch.Add_Click({
    $script:State.SearchText  = $script:TxtSearch.Text.Trim()
    if ($null -ne $script:TxtFilterAgent) {
        $script:State.FilterAgent = $script:TxtFilterAgent.Text.Trim()
    }
    $script:State.CurrentPage = 1
    _ApplyFiltersAndRefresh
})

$script:TxtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return) {
        $script:State.SearchText  = $script:TxtSearch.Text.Trim()
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    }
})

$script:CmbFilterDirection.Add_SelectionChanged({
    $sel = $script:CmbFilterDirection.SelectedItem
    $script:State.FilterDirection = if ($sel -and $sel.Content -ne 'All directions') { $sel.Content } else { '' }
    $script:State.CurrentPage     = 1
    _ApplyFiltersAndRefresh
})

$script:CmbFilterMedia.Add_SelectionChanged({
    $sel = $script:CmbFilterMedia.SelectedItem
    $script:State.FilterMedia = if ($sel -and $sel.Content -ne 'All media') { $sel.Content } else { '' }
    $script:State.CurrentPage = 1
    _ApplyFiltersAndRefresh
})

if ($null -ne $script:CmbFilterDisconnect) {
    $script:CmbFilterDisconnect.Add_SelectionChanged({
        $sel = $script:CmbFilterDisconnect.SelectedItem
        $script:State.FilterDisconnect = if ($sel -and $sel.Content -ne 'All disconnects') { $sel.Content } else { '' }
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    })
}

if ($null -ne $script:TxtFilterAgent) {
    $script:TxtFilterAgent.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) {
            $script:State.FilterAgent = $script:TxtFilterAgent.Text.Trim()
            $script:State.CurrentPage = 1
            _ApplyFiltersAndRefresh
        }
    })
}

# Date/time range pickers – refresh server-side grid when selection changes (no-op in index mode)
$script:DtpStartDate.Add_SelectedDateChanged({
    if ($script:State.DataSource -eq 'database') {
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    }
})

$script:DtpEndDate.Add_SelectedDateChanged({
    if ($script:State.DataSource -eq 'database') {
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    }
})

$script:TxtStartTime.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return -and $script:State.DataSource -eq 'database') {
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    }
})

$script:TxtEndTime.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return -and $script:State.DataSource -eq 'database') {
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    }
})

$script:BtnPrevPage.Add_Click({
    if ($script:State.CurrentPage -gt 1) {
        $script:State.CurrentPage--
        _RenderCurrentPage
    }
})

$script:BtnNextPage.Add_Click({
    if ($script:State.CurrentPage -lt $script:State.TotalPages) {
        $script:State.CurrentPage++
        _RenderCurrentPage
    }
})

# Wire filter boxes once the DataGrid visual tree has been built
$script:DgConversations.Add_Loaded({ _WireColumnFilterBoxes })

# Intercept column-header click to implement server/index-aware sort
$script:DgConversations.Add_Sorting({
    param($dgSender, $dgE)
    $dgE.Handled = $true   # prevent WPF's default (page-only) sort

    $bindPath = $dgE.Column.SortMemberPath
    if (-not $bindPath) { return }

    if ($script:State.SortColumn -eq $bindPath) {
        $script:State.SortAscending = -not $script:State.SortAscending
    } else {
        $script:State.SortColumn    = $bindPath
        $script:State.SortAscending = $true
    }

    # Update the visual sort-direction indicators
    foreach ($col in $script:DgConversations.Columns) {
        $col.SortDirection = if ($col.SortMemberPath -eq $bindPath) {
            if ($script:State.SortAscending) {
                [System.ComponentModel.ListSortDirection]::Ascending
            } else {
                [System.ComponentModel.ListSortDirection]::Descending
            }
        } else { $null }
    }

    $script:State.CurrentPage = 1
    _ApplyFiltersAndRefresh
})

$script:DgConversations.Add_SelectionChanged({
    if ($script:State.SuppressConversationSelectionOpen) { return }
    $sel = $script:DgConversations.SelectedItem
    if ($null -ne $sel) {
        _OpenConversationGridRow -Row $sel -SwitchToDrilldown $true
    }
})

$script:BtnOpenRun.Add_Click({
    $sel = $script:LstRecentRuns.SelectedItem
    if ($null -ne $sel -and $sel.FullPath) {
        _LoadRunAndRefreshGrid -RunFolder $sel.FullPath
    }
})

$script:LstRecentRuns.Add_MouseDoubleClick({
    $sel = $script:LstRecentRuns.SelectedItem
    if ($null -ne $sel -and $sel.FullPath) {
        _LoadRunAndRefreshGrid -RunFolder $sel.FullPath
    }
})

$script:BtnExportPageCsv.Add_Click({ _ExportPageCsv })

$script:BtnExportRunCsv.Add_Click({ _ExportRunCsv })

if ($null -ne $script:BtnGenerateReport) {
    $script:BtnGenerateReport.Add_Click({ _GenerateImpactReport })
}

if ($null -ne $script:BtnSaveReportSnapshot) {
    $script:BtnSaveReportSnapshot.Add_Click({ _SaveImpactReportSnapshot })
}

$script:BtnCopyDiagnostics.Add_Click({
    $diagText = $script:TxtDiagnostics.Text
    if (-not [string]::IsNullOrEmpty($diagText)) {
        [System.Windows.Clipboard]::SetText($diagText)
        _SetStatus 'Diagnostics copied to clipboard'
    } elseif ($null -ne $script:State.DiagnosticsContext) {
        $txt = Get-DiagnosticsText -RunFolder $script:State.DiagnosticsContext
        $script:TxtDiagnostics.Text = $txt
        [System.Windows.Clipboard]::SetText($txt)
        _SetStatus 'Diagnostics collected and copied'
    }
})

$script:TxtAttributeSearch.Add_TextChanged({
    _FilterAttributes
})

# ── Initialise UI state ────────────────────────────────────────────────────────

$cfg = Get-AppConfig
$script:State.PageSize = $cfg.PageSize

# Restore last dates
if ($cfg.LastStartDate) {
    try { $script:DtpStartDate.SelectedDate = [datetime]::Parse($cfg.LastStartDate) } catch { }
}
if ($cfg.LastEndDate) {
    try { $script:DtpEndDate.SelectedDate = [datetime]::Parse($cfg.LastEndDate) } catch { }
}
$script:TxtStartTime.Text = if ([string]::IsNullOrWhiteSpace([string]$cfg.LastStartTime)) { '00:00:00' } else { [string]$cfg.LastStartTime }
$script:TxtEndTime.Text   = if ([string]::IsNullOrWhiteSpace([string]$cfg.LastEndTime))   { '23:59:59' } else { [string]$cfg.LastEndTime }

_RefreshRecentRuns
_RefreshActiveCaseStatus
_UpdateConnectionStatus
_RefreshReportButtons
_RefreshCoreState

if ($script:CoreInitError) {
    _SetStatus 'Genesys.Core not initialized – open Settings to configure paths'
    $script:TxtStatusRight.Text = 'Core offline'
} elseif ($script:DatabaseWarning) {
    _SetStatus "WARNING: $script:DatabaseWarning"
    $script:TxtStatusRight.Text = 'Case store offline'
} else {
    _SetStatus 'Ready'
}
