#Requires -Version 5.1
Set-StrictMode -Version Latest

# ── App.UI.ps1 ────────────────────────────────────────────────────────────────
# Dot-sourced by App.ps1 after XAML is loaded.
# All WPF control references are resolved here from $script:Window.
# ─────────────────────────────────────────────────────────────────────────────

# ── Control map ──────────────────────────────────────────────────────────────

function _Ctrl { param([string]$Name) $script:Window.FindName($Name) }

# Header
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
$script:BtnGenerateReport      = _Ctrl 'BtnGenerateReport'
$script:BtnSaveReportSnapshot  = _Ctrl 'BtnSaveReportSnapshot'

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
    DataSource          = 'index'      # 'index' (JSONL) | 'database' (SQLite) | 'convstore' (PostgreSQL)
    DbConversationCount = 0            # total filtered count in DB / convstore mode
    ConvStoreCaseKey    = ''           # case_key used in convstore mode
    ConvStoreIncidentKey = ''
    BackgroundRunJob    = $null        # PSDataCollection / runspace handle
    BackgroundRunspace  = $null
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

# Maps display-row property names (SortMemberPath) → PostgreSQL conversation_grid column names
$script:_CsColMap = @{
    ConversationId   = 'conversation_id'
    Direction        = 'originating_direction'
    MediaType        = 'media_types'
    Queue            = 'queue_names'
    AgentNames       = 'agent_ids'
    DurationSec      = 'duration_ms'
    Disconnect       = 'disconnect_types'
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
            $script:BtnManageCase.IsEnabled = $false
            $script:BtnImportRun.IsEnabled  = $false
        }
        return
    }

    $case = _GetActiveCase
    if ($null -eq $case) {
        $script:State.ActiveCaseId   = ''
        $script:State.ActiveCaseName = ''
        _Dispatch {
            $script:LblActiveCase.Text = '(none selected)'
            $script:BtnManageCase.IsEnabled = $true
            $script:BtnImportRun.IsEnabled  = $true
        }
        return
    }

    $script:State.ActiveCaseId   = $case.case_id
    $script:State.ActiveCaseName = $case.name
    _Dispatch {
        $retention = if ($case.PSObject.Properties['retention_status']) { $case.retention_status } else { $case.state }
        $suffix = if ($retention -and $retention -ne 'active') { " [$retention]" } else { '' }
        $script:LblActiveCase.Text = "$($case.name)$suffix"
        $script:BtnManageCase.IsEnabled = $true
        $script:BtnImportRun.IsEnabled  = $true
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

function _GetCurrentViewSnapshot {
    $range = _GetQueryBoundaryDateTimes
    return [ordered]@{
        captured_utc      = [datetime]::UtcNow.ToString('o')
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

    try {
        $report = New-ImpactReport -FilteredIndex $current -ReportTitle (_GetCurrentImpactReportTitle)
        $script:State.CurrentImpactReport = $report
        _Dispatch {
            $script:TxtDrillSummary.Text = $report | ConvertTo-Json -Depth 8
        }
        _RefreshReportButtons
        _SetStatus "Generated impact report for $($report.TotalConversations) conversations"
    } catch {
        _SetStatus 'Impact report generation failed'
        [System.Windows.MessageBox]::Show("Failed to generate impact report: $_", 'Impact Report')
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

    try {
        $snapshotName = "{0} [{1}]" -f $script:State.CurrentImpactReport.ReportTitle, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        New-ReportSnapshot -CaseId $case.case_id -Name $snapshotName -Format 'json' -Content $script:State.CurrentImpactReport | Out-Null
        _SetStatus "Saved impact report snapshot to case '$($case.name)'"
        [System.Windows.MessageBox]::Show("Saved impact report snapshot to case '$($case.name)'.", 'Impact Report')
    } catch {
        _SetStatus 'Failed to save report snapshot'
        [System.Windows.MessageBox]::Show("Failed to save impact report snapshot: $_", 'Impact Report')
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

    try {
        _SetStatus "Importing run into case '$($case.name)' …"
        $result = Import-RunFolderToCase -CaseId $case.case_id -RunFolder $runFolder
        $summary = "Imported $($result.RecordCount) conversations into case '$($result.CaseName)'."
        if ($result.SkippedCount -gt 0 -or $result.FailedCount -gt 0) {
            $summary += "`nSkipped: $($result.SkippedCount)  Failed: $($result.FailedCount)"
        }
        _Dispatch {
            $script:TxtDiagnostics.Text = @"
=== Case Import ===
Case        : $($result.CaseName)
Run Folder  : $($result.RunFolder)
Run Id      : $($result.RunId)
Dataset     : $($result.DatasetKey)
Imported    : $($result.RecordCount)
Skipped     : $($result.SkippedCount)
Failed      : $($result.FailedCount)
"@
        }
        _SetStatus "Imported $($result.RecordCount) conversations into $($result.CaseName)"
        [System.Windows.MessageBox]::Show($summary, 'Import Complete')
        # Automatically switch the grid to DB mode to show the freshly imported data
        _SwitchToDbMode
    } catch {
        _SetStatus 'Import failed'
        [System.Windows.MessageBox]::Show("Import failed: $_", 'Import Run')
    }
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
        return
    }

    $dir    = $script:State.FilterDirection
    $media  = $script:State.FilterMedia
    $disc   = $script:State.FilterDisconnect
    $agent  = $script:State.FilterAgent
    $srch   = $script:State.SearchText
    $divId  = $script:TxtFilterDivisionId.Text.Trim()
    # Conversation ID entered in SHAPE SIGNAL acts as a SearchText override when no
    # explicit grid search is active (DB SearchText already does LIKE on conversation_id).
    $convId = $script:TxtConversationId.Text.Trim()
    if ($convId -and -not $srch) { $srch = $convId }

    # Resolve date/time range – silently skip if pickers are unset or invalid
    $startDt = ''
    $endDt   = ''
    try {
        $range = _GetQueryBoundaryDateTimes
        if ($null -ne $range.Start) { $startDt = $range.Start.ToUniversalTime().ToString('o') }
        if ($null -ne $range.End)   { $endDt   = $range.End.ToUniversalTime().ToString('o')   }
    } catch { }

    try {
        $count = Get-ConversationCount `
            -CaseId         $caseId `
            -Direction      $dir `
            -MediaType      $media `
            -SearchText     $srch `
            -DisconnectType $disc `
            -AgentName      $agent `
            -DivisionId     $divId `
            -StartDateTime  $startDt `
            -EndDateTime    $endDt

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
            -Direction      $dir `
            -MediaType      $media `
            -SearchText     $srch `
            -DisconnectType $disc `
            -AgentName      $agent `
            -DivisionId     $divId `
            -StartDateTime  $startDt `
            -EndDateTime    $endDt `
            -SortBy         $sortBy `
            -SortDir        $sortDir)

        $displayRows = @($rows | ForEach-Object { Get-DbConversationDisplayRow -DbRow $_ })

        # Apply per-column text filters in memory (post-fetch)
        if ($script:State.ColumnFilters.Count -gt 0) {
            foreach ($bindPath in @($script:State.ColumnFilters.Keys)) {
                $val = $script:State.ColumnFilters[$bindPath]
                if (-not $val) { continue }
                $lo = $val.ToLowerInvariant()
                $displayRows = @($displayRows | Where-Object {
                    $propVal = $_.PSObject.Properties[$bindPath]
                    $null -ne $propVal -and [string]$propVal.Value -like "*$lo*"
                })
            }
        }
        $page  = $script:State.CurrentPage
        $pages = $script:State.TotalPages

        _Dispatch {
            $script:DgConversations.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($displayRows)
            $script:TxtPageInfo.Text = "Page $page of $pages  |  $count records  [case]"
            $script:BtnPrevPage.IsEnabled = ($page -gt 1)
            $script:BtnNextPage.IsEnabled = ($page -lt $pages)
        }

        # Mirror into CurrentIndex so impact reports keep working (index-compatible subset)
        $script:State.CurrentIndex = @($rows)
        _RefreshReportButtons
    } catch {
        _SetStatus "Case grid error: $_"
    }
}

function _SwitchToDbMode {
    <#
    .SYNOPSIS
        Switches the conversations grid to DB mode for the active case.
        Called after a successful import or when the user selects a case that already has data.
    #>
    if ([string]::IsNullOrEmpty($script:State.ActiveCaseId) -or -not (Test-DatabaseInitialized)) { return }
    $script:State.DataSource   = 'database'
    $script:State.CurrentPage  = 1
    $script:State.CurrentImpactReport = $null
    _SetStatus "Case store view: $($script:State.ActiveCaseName)"
    _RefreshGridFromDb
}

function _RefreshGridFromConvStore {
    <#
    .SYNOPSIS
        Queries convo.conversation_grid for the current page and filter state,
        then pushes rows to DgConversations via Dispatcher.
        Used when State.DataSource = 'convstore'.
    #>
    if (-not (Test-ConvStoreReady)) {
        _SetStatus 'Conversation store not available – configure PostgreSQL connection in Settings'
        return
    }

    $caseKey = $script:State.ConvStoreCaseKey
    $dir     = $script:State.FilterDirection
    $media   = $script:State.FilterMedia
    $disc    = $script:State.FilterDisconnect
    $agent   = $script:State.FilterAgent
    $srch    = $script:State.SearchText
    $divId   = $script:TxtFilterDivisionId.Text.Trim()
    $convId  = $script:TxtConversationId.Text.Trim()
    if ($convId -and -not $srch) { $srch = $convId }

    $startDt = ''; $endDt = ''
    try {
        $range = _GetQueryBoundaryDateTimes
        if ($null -ne $range.Start) { $startDt = $range.Start.ToUniversalTime().ToString('o') }
        if ($null -ne $range.End)   { $endDt   = $range.End.ToUniversalTime().ToString('o')   }
    } catch { }

    try {
        $count = Get-ConvStoreConversationCount `
            -CaseKey        $caseKey `
            -Direction      $dir `
            -MediaType      $media `
            -SearchText     $srch `
            -DisconnectType $disc `
            -AgentId        $agent `
            -DivisionId     $divId `
            -StartDateTime  $startDt `
            -EndDateTime    $endDt

        $script:State.DbConversationCount = $count
        $script:State.TotalPages = [math]::Max(1, [math]::Ceiling($count / $script:State.PageSize))
        if ($script:State.CurrentPage -gt $script:State.TotalPages) {
            $script:State.CurrentPage = $script:State.TotalPages
        }

        $sortBy  = if ($script:State.SortColumn -and $script:_CsColMap.ContainsKey($script:State.SortColumn)) {
            $script:_CsColMap[$script:State.SortColumn]
        } else { 'conversation_start_utc' }
        $sortDir = if ($script:State.SortAscending) { 'ASC' } else { 'DESC' }

        $rows = @(Get-ConvStoreConversationsPage `
            -CaseKey        $caseKey `
            -PageNumber     $script:State.CurrentPage `
            -PageSize       $script:State.PageSize `
            -Direction      $dir `
            -MediaType      $media `
            -SearchText     $srch `
            -DisconnectType $disc `
            -AgentId        $agent `
            -DivisionId     $divId `
            -StartDateTime  $startDt `
            -EndDateTime    $endDt `
            -SortBy         $sortBy `
            -SortDir        $sortDir)

        $displayRows = @($rows | ForEach-Object { Get-ConvStoreDisplayRow -GridRow $_ })

        # Apply per-column text filters in memory (post-fetch)
        if ($script:State.ColumnFilters.Count -gt 0) {
            foreach ($bindPath in @($script:State.ColumnFilters.Keys)) {
                $val = $script:State.ColumnFilters[$bindPath]
                if (-not $val) { continue }
                $lo = $val.ToLowerInvariant()
                $displayRows = @($displayRows | Where-Object {
                    $propVal = $_.PSObject.Properties[$bindPath]
                    $null -ne $propVal -and [string]$propVal.Value -like "*$lo*"
                })
            }
        }

        $page  = $script:State.CurrentPage
        $pages = $script:State.TotalPages
        $ck    = if ($caseKey) { " [$caseKey]" } else { ' [all]' }

        _Dispatch {
            $script:DgConversations.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($displayRows)
            $script:TxtPageInfo.Text = "Page $page of $pages  |  $count records  [convstore$ck]"
            $script:BtnPrevPage.IsEnabled = ($page -gt 1)
            $script:BtnNextPage.IsEnabled = ($page -lt $pages)
        }

        $script:State.CurrentIndex = @($rows)
        _RefreshReportButtons
    } catch {
        _SetStatus "Conversation store grid error: $_"
    }
}

function _SwitchToConvStoreMode {
    <#
    .SYNOPSIS
        Switches the conversations grid to convstore (PostgreSQL) mode.
    #>
    param(
        [string]$CaseKey     = '',
        [string]$IncidentKey = ''
    )
    if (-not (Test-ConvStoreReady)) {
        _SetStatus 'Conversation store not available – configure PostgreSQL connection in Settings'
        return
    }
    $script:State.DataSource          = 'convstore'
    $script:State.ConvStoreCaseKey    = $CaseKey
    $script:State.ConvStoreIncidentKey = $IncidentKey
    $script:State.CurrentPage         = 1
    $script:State.CurrentImpactReport = $null
    $label = if ($CaseKey) { "convstore [$CaseKey]" } else { 'convstore [all]' }
    _SetStatus "Conversation store view: $label"
    _RefreshGridFromConvStore
}

# ── Index / paging ────────────────────────────────────────────────────────────

function _LoadRunAndRefreshGrid {
    param([string]$RunFolder)
    if ([string]::IsNullOrEmpty($RunFolder)) { return }
    _SetStatus "Loading index: $([System.IO.Path]::GetFileName($RunFolder)) …"

    $script:State.CurrentRunFolder  = $RunFolder
    $script:State.DiagnosticsContext = $RunFolder

    # Clear run-specific ID filters – stale values from a prior run would silently
    # filter the newly-loaded data and confuse the user.
    $script:TxtConversationId.Text = ''
    if ($null -ne $script:TxtFilterUserId)     { $script:TxtFilterUserId.Text     = '' }
    if ($null -ne $script:TxtFilterDivisionId) { $script:TxtFilterDivisionId.Text = '' }

    # Load or build index (may take a moment for large runs)
    $allIdx = Load-RunIndex -RunFolder $RunFolder
    $script:State.CurrentPage = 1
    _ApplyFiltersAndRefresh -AllIndex $allIdx
    _SetStatus "Loaded $($allIdx.Count) records from $([System.IO.Path]::GetFileName($RunFolder))"
    $script:TxtStatusRight.Text = [datetime]::Now.ToString('HH:mm:ss')
}

function _ApplyFiltersAndRefresh {
    param([object[]]$AllIndex = $null)

    # DB / convstore mode: delegate entirely to the server-side paging path
    if ($script:State.DataSource -eq 'database') {
        _RefreshGridFromDb
        return
    }
    if ($script:State.DataSource -eq 'convstore') {
        _RefreshGridFromConvStore
        return
    }

    if ($null -eq $AllIndex) {
        if ($null -eq $script:State.CurrentRunFolder) { return }
        $AllIndex = Load-RunIndex -RunFolder $script:State.CurrentRunFolder
    }

    $dir    = $script:State.FilterDirection
    $media  = $script:State.FilterMedia
    $search = $script:State.SearchText
    $convId = $script:TxtConversationId.Text.Trim()
    $userId = $script:TxtFilterUserId.Text.Trim()
    $divId  = $script:TxtFilterDivisionId.Text.Trim()

    $filtered = $AllIndex | Where-Object {
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
    }

    # Apply per-column text filters (post-query LIKE on index properties)
    if ($script:State.ColumnFilters.Count -gt 0) {
        foreach ($bindPath in @($script:State.ColumnFilters.Keys)) {
            $val = $script:State.ColumnFilters[$bindPath]
            if (-not $val) { continue }
            $idxProp = if ($script:_IndexPropMap.ContainsKey($bindPath)) { $script:_IndexPropMap[$bindPath] } else { $bindPath }
            $lo = $val.ToLowerInvariant()
            $filtered = $filtered | Where-Object {
                $propVal = $_.PSObject.Properties[$idxProp]
                $null -ne $propVal -and [string]$propVal.Value -like "*$lo*"
            }
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

    $script:State.CurrentIndex = @($filtered)
    $script:State.TotalPages   = [math]::Max(1, [math]::Ceiling($filtered.Count / $script:State.PageSize))
    $script:State.CurrentImpactReport = $null
    if ($script:State.CurrentPage -gt $script:State.TotalPages) {
        $script:State.CurrentPage = $script:State.TotalPages
    }
    _RenderCurrentPage
    _RefreshReportButtons
}

function _RenderCurrentPage {
    # In DB / convstore mode the grid is always rendered via a live server-side query
    if ($script:State.DataSource -eq 'database') {
        _RefreshGridFromDb
        return
    }
    if ($script:State.DataSource -eq 'convstore') {
        _RefreshGridFromConvStore
        return
    }

    $idx      = $script:State.CurrentIndex
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

    $pageEntries = $idx[$startIdx..$endIdx]
    $displayRows = $pageEntries | ForEach-Object { Get-ConversationDisplayRow -IndexEntry $_ }

    _Dispatch {
        $script:DgConversations.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]($displayRows)
        $script:TxtPageInfo.Text = "Page $page of $pages  |  $total records"
        $script:BtnPrevPage.IsEnabled = ($page -gt 1)
        $script:BtnNextPage.IsEnabled = ($page -lt $pages)
    }
}

# ── Drilldown ─────────────────────────────────────────────────────────────────

function _LoadDrilldown {
    param([string]$ConversationId)

    # Require either a run folder (index mode) or an active case (DB mode)
    if ($null -eq $script:State.CurrentRunFolder -and
        [string]::IsNullOrEmpty($script:State.ActiveCaseId)) { return }

    $script:State.CurrentImpactReport = $null
    _RefreshReportButtons
    _SetStatus "Loading drilldown: $ConversationId …"

    $record = $null

    # ── DB path: reconstruct record from participants_json stored in the case ──
    if ($script:State.DataSource -eq 'database' -and
        -not [string]::IsNullOrEmpty($script:State.ActiveCaseId)) {
        try {
            $dbRow = Get-ConversationById -CaseId $script:State.ActiveCaseId `
                                          -ConversationId $ConversationId
            if ($null -ne $dbRow) {
                $ptjsonProp = $dbRow.PSObject.Properties['participants_json']
                $ptjson     = if ($null -ne $ptjsonProp) { $ptjsonProp.Value } else { $null }
                if (-not [string]::IsNullOrWhiteSpace($ptjson)) {
                    $participants = $ptjson | ConvertFrom-Json
                    $record = [pscustomobject]@{
                        conversationId    = $ConversationId
                        conversationStart = if ($dbRow.PSObject.Properties['conversation_start']) { $dbRow.conversation_start } else { '' }
                        conversationEnd   = if ($dbRow.PSObject.Properties['conversation_end'])   { $dbRow.conversation_end   } else { '' }
                        participants      = $participants
                    }
                    $atjsonProp = $dbRow.PSObject.Properties['attributes_json']
                    $atjson     = if ($null -ne $atjsonProp) { $atjsonProp.Value } else { $null }
                    if (-not [string]::IsNullOrWhiteSpace($atjson)) {
                        $record | Add-Member -NotePropertyName 'attributes' `
                                             -NotePropertyValue ($atjson | ConvertFrom-Json) -Force
                    }
                }
            }
        } catch { $record = $null }
    }

    # ── ConvStore path: reconstruct from payload_json stored in conversation_grid ──
    if ($null -eq $record -and $script:State.DataSource -eq 'convstore') {
        try {
            $csRow = Get-ConvStoreConversationById -ConversationId $ConversationId
            if ($null -ne $csRow) {
                $pjProp = $csRow.PSObject.Properties['payload_json']
                $pj     = if ($null -ne $pjProp) { $pjProp.Value } else { $null }
                if (-not [string]::IsNullOrWhiteSpace($pj)) {
                    $record = $pj | ConvertFrom-Json
                }
            }
        } catch { $record = $null }
    }

    # ── JSONL fallback: seek the source run folder ─────────────────────────────
    if ($null -eq $record -and $null -ne $script:State.CurrentRunFolder) {
        $record = Get-ConversationRecord -RunFolder $script:State.CurrentRunFolder `
                                         -ConversationId $ConversationId
    }

    if ($null -eq $record) {
        _Dispatch {
            $script:LblSelectedConversation.Text = "(not found)"
            $script:TxtDrillSummary.Text = "Record not found for conversation ID: $ConversationId"
        }
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
        $script:TxtRawJson.Text = $record | ConvertTo-Json -Depth 20
    }
    _SetStatus "Drilldown loaded: $ConversationId"
}

# ── Run orchestration ─────────────────────────────────────────────────────────

function _GetDatasetParameters {
    $params = @{}
    $range  = _GetQueryBoundaryDateTimes

    if ($null -ne $range.Start) {
        # Convert to UTC – WPF DatePicker yields DateTimeKind.Unspecified (treated as
        # local by ToUniversalTime).  The Genesys API expects UTC ISO-8601 timestamps.
        $params['StartDateTime'] = $range.Start.ToUniversalTime().ToString('o')
    }
    if ($null -ne $range.End) {
        $params['EndDateTime'] = $range.End.ToUniversalTime().ToString('o')
    }

    $selDir = $script:CmbDirection.SelectedItem
    if ($selDir -and $selDir.Content -ne '(all)') {
        $params['Direction'] = $selDir.Content
    }

    $selMedia = $script:CmbMediaType.SelectedItem
    if ($selMedia -and $selMedia.Content -ne '(all)') {
        $params['MediaType'] = $selMedia.Content
    }

    $q = $script:TxtQueue.Text.Trim()
    if ($q) { $params['Queue'] = $q }

    $convId = $script:TxtConversationId.Text.Trim()
    if ($convId) { $params['ConversationId'] = $convId }

    $userId = $script:TxtFilterUserId.Text.Trim()
    if ($userId) { $params['UserId'] = $userId }

    $divId = $script:TxtFilterDivisionId.Text.Trim()
    if ($divId) { $params['DivisionId'] = $divId }

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

    $script:State.RunCancelled = $false
    # Clear any stale run folder so _PollBackgroundRun discovers the new one
    $script:State.CurrentRunFolder   = $null
    $script:State.DiagnosticsContext = $null
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
        param($AppDir, $CorePath, $CatalogPath, $SchemaPath, $OutputRoot, $RunType, $DatasetParams, $Headers)
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
        & $t "Headers     : $(if ($null -ne $Headers -and $Headers.Count -gt 0) { "$($Headers.Count) key(s): $($Headers.Keys -join ', ')" } else { '(none — no auth token!)' })"

        try {
            # Import-Module inside [PowerShell]::Create() runspaces scopes functions
            # to the module namespace, not the calling scriptblock — use dot-source
            # instead so function definitions land directly in the current scope.
            # Export-ModuleMember in the psm1 will produce a non-terminating error
            # (not valid outside a module scope) which is safely ignored here.
            . (Join-Path $AppDir 'modules\App.CoreAdapter.psm1')
            & $t "App.CoreAdapter.psm1 dot-sourced (Initialize-CoreAdapter=$(if (Get-Command Initialize-CoreAdapter -ErrorAction SilentlyContinue) { 'FOUND' } else { 'MISSING' }))"

            Initialize-CoreAdapter -CoreModulePath $CorePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot
            & $t "Initialize-CoreAdapter OK"

            if ($RunType -eq 'preview') {
                & $t "Calling Start-PreviewRun..."
                $result = Start-PreviewRun -DatasetParameters $DatasetParams -Headers $Headers
                & $t "Start-PreviewRun returned  runFolder=$($result.runFolder)"
                $result
            } else {
                & $t "Calling Start-FullRun..."
                $result = Start-FullRun -DatasetParameters $DatasetParams -Headers $Headers
                & $t "Start-FullRun returned  runFolder=$($result.runFolder)"
                $result
            }
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

    $asyncResult = $ps.BeginInvoke()

    $script:State.BackgroundRunspace = $rs
    $script:State.BackgroundRunJob   = @{ Ps = $ps; Async = $asyncResult }

    # Start polling timer
    $timer           = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval  = [System.TimeSpan]::FromSeconds(2)
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
        # Try to find the run folder that was just created
        $cfg     = Get-AppConfig
        $folders = @(Get-RecentRunFolders -OutputRoot $cfg.OutputRoot -Max 1)
        if ($folders.Count -gt 0) {
            $script:State.CurrentRunFolder   = $folders[0]
            $script:State.DiagnosticsContext = $folders[0]
        }
    }

    # Show run status
    $statusText = if ($script:State.RunCancelled) { 'Cancelling…' } else { 'Running…' }
    _Dispatch {
        $script:TxtRunStatus.Text     = $statusText
        $script:TxtConsoleStatus.Text = $statusText
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

    # If polling didn't detect the new run folder, recover from the Start-*Run result.
    # Invoke-Dataset returns a $runContext PSCustomObject (.runFolder), not a bare string.
    if ($null -eq $script:State.CurrentRunFolder -and $null -ne $runResult) {
        $resultFolder = @($runResult) | ForEach-Object {
            if ($_ -is [string]) { $_ }
            elseif ($null -ne $_ -and $_.PSObject.Properties.Name -contains 'runFolder') { $_.runFolder }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and [System.IO.Directory]::Exists($_) } | Select-Object -First 1
        if ($resultFolder) {
            $script:State.CurrentRunFolder   = $resultFolder
            $script:State.DiagnosticsContext = $resultFolder
        }
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
        return
    }

    # Load run results
    if ($null -ne $script:State.CurrentRunFolder) {
        Add-RecentRun -RunFolder $script:State.CurrentRunFolder
        _RefreshRecentRuns
        _LoadRunAndRefreshGrid -RunFolder $script:State.CurrentRunFolder

        # Auto-import to ConvStore if it is ready
        if (Test-ConvStoreReady) {
            try {
                $cfg3 = Get-AppConfig
                Import-RunFolderToConvStore `
                    -RunFolder      $script:State.CurrentRunFolder `
                    -CaseKey        $script:State.ConvStoreCaseKey `
                    -IncidentKey    $script:State.ConvStoreIncidentKey `
                    -RetentionDays  $cfg3.ConvStoreRetentionDays | Out-Null
            } catch {
                Write-Warning "ConvStore auto-import failed: $_"
            }
        }
    }

    $diagText = if ($null -ne $script:State.DiagnosticsContext) {
        Get-DiagnosticsText -RunFolder $script:State.DiagnosticsContext
    } else { '(no run folder found — check trace above)' }
    if ($traceText) { $diagText = $traceText + "`n" + $diagText }
    _Dispatch {
        $script:TxtRunStatus.Text     = 'Run complete'
        $script:TxtConsoleStatus.Text = 'Complete'
        $script:TxtDiagnostics.Text   = $diagText
    }
    _SetStatus 'Run complete'
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

    # ── Conversation Store (PostgreSQL) ───────────────────────────────────────
    _SectionHead 'Conversation Store (PostgreSQL)'
    $tbCsConnStr      = _Row 'Connection string'  $cfg.ConvStoreConnStr
    $tbCsRetention    = _Row 'Retention (days)'   $cfg.ConvStoreRetentionDays
    $tbCsNpgsqlDll    = _Row 'Npgsql DLL path'    $cfg.ConvStoreNpgsqlDllPath

    # Test Connection button
    $pnlCsTest = New-Object System.Windows.Controls.StackPanel
    $pnlCsTest.Orientation = 'Horizontal'
    $pnlCsTest.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)

    $btnCsTest = New-Object System.Windows.Controls.Button
    $btnCsTest.Content = 'Test Connection'; $btnCsTest.Width = 120; $btnCsTest.Height = 26
    $btnCsTest.Margin  = [System.Windows.Thickness]::new(0, 0, 8, 0)

    $btnCsDeploy = New-Object System.Windows.Controls.Button
    $btnCsDeploy.Content = 'Deploy Schema'; $btnCsDeploy.Width = 110; $btnCsDeploy.Height = 26
    $btnCsDeploy.Margin  = [System.Windows.Thickness]::new(0, 0, 8, 0)

    $btnCsView = New-Object System.Windows.Controls.Button
    $btnCsView.Content = 'Browse Store'; $btnCsView.Width = 100; $btnCsView.Height = 26

    $lblCsStatus = New-Object System.Windows.Controls.TextBlock
    $lblCsStatus.Margin      = [System.Windows.Thickness]::new(0, 6, 0, 0)
    $lblCsStatus.TextWrapping = 'Wrap'
    if (Test-ConvStoreReady) {
        $lblCsStatus.Text       = 'Conversation store is connected.'
        $lblCsStatus.Foreground = [System.Windows.Media.Brushes]::DarkGreen
    } else {
        $lblCsStatus.Text       = 'Conversation store not connected. Enter a connection string and click Test.'
        $lblCsStatus.Foreground = [System.Windows.Media.Brushes]::Gray
    }

    $pnlCsTest.Children.Add($btnCsTest)   | Out-Null
    $pnlCsTest.Children.Add($btnCsDeploy) | Out-Null
    $pnlCsTest.Children.Add($btnCsView)   | Out-Null
    $sp.Children.Add($pnlCsTest)           | Out-Null
    $sp.Children.Add($lblCsStatus)         | Out-Null

    $btnCsTest.Add_Click({
        try {
            Initialize-ConvStore `
                -ConnStr       $tbCsConnStr.Text.Trim() `
                -NpgsqlDllPath $tbCsNpgsqlDll.Text.Trim() `
                -AppDir        $AppDir
            $lblCsStatus.Text       = 'Connection successful.'
            $lblCsStatus.Foreground = [System.Windows.Media.Brushes]::DarkGreen
            $script:ConvStoreWarning = ''
        } catch {
            $lblCsStatus.Text       = "Connection failed: $_"
            $lblCsStatus.Foreground = [System.Windows.Media.Brushes]::Firebrick
        }
    })

    $btnCsDeploy.Add_Click({
        try {
            if (-not (Test-ConvStoreReady)) {
                Initialize-ConvStore `
                    -ConnStr       $tbCsConnStr.Text.Trim() `
                    -NpgsqlDllPath $tbCsNpgsqlDll.Text.Trim() `
                    -AppDir        $AppDir
            }
            $schemaFile = [System.IO.Path]::Combine($AppDir, 'lib', 'conversations_schema_v2.sql')
            Deploy-ConvStoreSchema -SchemaFilePath $schemaFile
            $lblCsStatus.Text       = 'Schema deployed successfully.'
            $lblCsStatus.Foreground = [System.Windows.Media.Brushes]::DarkGreen
        } catch {
            $lblCsStatus.Text       = "Schema deploy failed: $_"
            $lblCsStatus.Foreground = [System.Windows.Media.Brushes]::Firebrick
        }
    })

    $btnCsView.Add_Click({
        $dialog.Close()
        _SwitchToConvStoreMode
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
            $cfg2 | Add-Member -NotePropertyName 'ConvStoreConnStr'       -NotePropertyValue $tbCsConnStr.Text.Trim()       -Force
            $cfg2 | Add-Member -NotePropertyName 'ConvStoreRetentionDays' -NotePropertyValue ([int]$tbCsRetention.Text)     -Force
            $cfg2 | Add-Member -NotePropertyName 'ConvStoreNpgsqlDllPath' -NotePropertyValue $tbCsNpgsqlDll.Text.Trim()     -Force
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

    $idx      = $script:State.CurrentIndex
    $page     = $script:State.CurrentPage
    $pageSize = $script:State.PageSize
    $startIdx = ($page - 1) * $pageSize
    $endIdx   = [math]::Min($startIdx + $pageSize - 1, $idx.Count - 1)
    if ($startIdx -gt $endIdx) { return }

    $entries  = $idx[$startIdx..$endIdx]
    $records  = Get-IndexedPage -RunFolder $script:State.CurrentRunFolder -IndexEntries $entries
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
    if ($script:State.DataSource -in @('database','convstore')) {
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    }
})

$script:DtpEndDate.Add_SelectedDateChanged({
    if ($script:State.DataSource -in @('database','convstore')) {
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    }
})

$script:TxtStartTime.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return -and $script:State.DataSource -in @('database','convstore')) {
        $script:State.CurrentPage = 1
        _ApplyFiltersAndRefresh
    }
})

$script:TxtEndTime.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Return -and $script:State.DataSource -in @('database','convstore')) {
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
    $sel = $script:DgConversations.SelectedItem
    if ($null -ne $sel) {
        $convId = $sel.ConversationId
        _LoadDrilldown -ConversationId $convId
        # Switch to Drilldown tab
        $tabCtrl = _Ctrl 'TabWorkspace'
        $tabCtrl.SelectedIndex = 1
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
} elseif ($script:ConvStoreWarning) {
    # ConvStore offline is informational only (connection string may simply not be configured yet)
    _SetStatus 'Ready  |  Conversation store not connected – configure in Settings to enable'
} else {
    if (Test-ConvStoreReady) {
        _SetStatus 'Ready  |  Conversation store connected'
        $script:TxtStatusRight.Text = 'ConvStore ready'
    } else {
        _SetStatus 'Ready'
    }
}
