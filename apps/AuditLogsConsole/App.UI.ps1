#Requires -Version 5.1
Set-StrictMode -Version Latest

function _Ctrl {
    param([string]$Name)
    return $script:Window.FindName($Name)
}

$script:CmbRegion             = _Ctrl 'CmbRegion'
$script:PwdAccessToken        = _Ctrl 'PwdAccessToken'
$script:BtnConnect            = _Ctrl 'BtnConnect'
$script:TxtStartupState       = _Ctrl 'TxtStartupState'
$script:TxtAuthState          = _Ctrl 'TxtAuthState'
$script:TxtStatusMain         = _Ctrl 'TxtStatusMain'
$script:TxtStatusRight        = _Ctrl 'TxtStatusRight'
$script:CmbDataset            = _Ctrl 'CmbDataset'
$script:CmbTimePreset         = _Ctrl 'CmbTimePreset'
$script:DtpStartDate          = _Ctrl 'DtpStartDate'
$script:TxtStartTime          = _Ctrl 'TxtStartTime'
$script:DtpEndDate            = _Ctrl 'DtpEndDate'
$script:TxtEndTime            = _Ctrl 'TxtEndTime'
$script:CmbService            = _Ctrl 'CmbService'
$script:CmbAction             = _Ctrl 'CmbAction'
$script:TxtActor              = _Ctrl 'TxtActor'
$script:TxtEntity             = _Ctrl 'TxtEntity'
$script:TxtKeyword            = _Ctrl 'TxtKeyword'
$script:TxtPreviewLimit       = _Ctrl 'TxtPreviewLimit'
$script:BtnPreviewRun         = _Ctrl 'BtnPreviewRun'
$script:BtnFullRun            = _Ctrl 'BtnFullRun'
$script:LstRecentRuns         = _Ctrl 'LstRecentRuns'
$script:BtnLoadSelectedRun    = _Ctrl 'BtnLoadSelectedRun'
$script:BtnRefreshRuns        = _Ctrl 'BtnRefreshRuns'
$script:BtnOpenRunFolder      = _Ctrl 'BtnOpenRunFolder'
$script:TxtCurrentRunFolder   = _Ctrl 'TxtCurrentRunFolder'
$script:TxtCurrentRunStatus   = _Ctrl 'TxtCurrentRunStatus'
$script:TxtSummaryCounts      = _Ctrl 'TxtSummaryCounts'
$script:TxtCurrentViewMode    = _Ctrl 'TxtCurrentViewMode'
$script:BtnApplyFilters       = _Ctrl 'BtnApplyFilters'
$script:BtnResetFilters       = _Ctrl 'BtnResetFilters'
$script:BtnExportFilteredCsv  = _Ctrl 'BtnExportFilteredCsv'
$script:BtnExportFullCsv      = _Ctrl 'BtnExportFullCsv'
$script:BtnExportFilteredHtml = _Ctrl 'BtnExportFilteredHtml'
$script:BtnExportFullHtml     = _Ctrl 'BtnExportFullHtml'
$script:DgAuditResults        = _Ctrl 'DgAuditResults'
$script:BtnPrevPage           = _Ctrl 'BtnPrevPage'
$script:BtnNextPage           = _Ctrl 'BtnNextPage'
$script:TxtPageInfo           = _Ctrl 'TxtPageInfo'
$script:TxtSelectedRecord     = _Ctrl 'TxtSelectedRecord'
$script:TxtDetailSummary      = _Ctrl 'TxtDetailSummary'
$script:DgChangedProperties   = _Ctrl 'DgChangedProperties'
$script:TxtRawJson            = _Ctrl 'TxtRawJson'
$script:BtnCopyDetailSummary  = _Ctrl 'BtnCopyDetailSummary'
$script:BtnCopyRawJson        = _Ctrl 'BtnCopyRawJson'
$script:TxtConsoleState       = _Ctrl 'TxtConsoleState'
$script:TxtConsoleError       = _Ctrl 'TxtConsoleError'
$script:LstRunEvents          = _Ctrl 'LstRunEvents'
$script:BtnCopyDiagnostics    = _Ctrl 'BtnCopyDiagnostics'
$script:TxtDiagnosticsPreview = _Ctrl 'TxtDiagnosticsPreview'

$script:State = [ordered]@{
    CurrentRunFolder = $null
    CurrentRunMode   = ''
    CurrentQuerySpec = $null
    FilteredIndex    = @()
    CurrentPage      = 1
    PageSize         = [int]$script:AppContext.Settings.Ui.PageSize
    CurrentViewLimit = 0
    AuthContext      = $null
    RunPowerShell    = $null
    RunHandle        = $null
    RunStartedAtUtc  = $null
    RunLastError     = ''
    PollTimer        = $null
    CurrentSummary   = $null
    FilterCatalog    = [ordered]@{
        ServiceNames     = @()
        Actions          = @()
        ActionsByService = [ordered]@{}
    }
}

function _SetStatus {
    param(
        [string]$Main,
        [string]$Right = ''
    )

    $script:TxtStatusMain.Text = $Main
    $script:TxtStatusRight.Text = $Right
}

function _IsWindowsDesktop {
    return $PSVersionTable.PSEdition -eq 'Desktop' -or $env:OS -eq 'Windows_NT'
}

function _Format-DateTime {
    param([AllowNull()][datetime]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return $Value.ToUniversalTime().ToString('yyyy-MM-dd HH:mm')
}

function _Get-ComboText {
    param([AllowNull()][object]$Control)

    if ($null -eq $Control) {
        return ''
    }

    if ($Control.PSObject.Properties['Text']) {
        return [string]$Control.Text
    }

    if ($null -ne $Control.SelectedItem -and $Control.SelectedItem.PSObject.Properties['Content']) {
        return [string]$Control.SelectedItem.Content
    }

    return ''
}

function _Sort-UniqueTextArray {
    param([object[]]$Values)

    return @($Values | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function _New-FilterCatalog {
    return [pscustomobject]@{
        ServiceNames     = @()
        Actions          = @()
        ActionsByService = [ordered]@{}
    }
}

function _Add-FilterCatalog {
    param([AllowNull()][object]$Catalog)

    if ($null -eq $Catalog) {
        return
    }

    $script:State.FilterCatalog.ServiceNames = _Sort-UniqueTextArray -Values @($script:State.FilterCatalog.ServiceNames + @($Catalog.ServiceNames))
    $script:State.FilterCatalog.Actions = _Sort-UniqueTextArray -Values @($script:State.FilterCatalog.Actions + @($Catalog.Actions))

    foreach ($serviceName in @($Catalog.ActionsByService.Keys)) {
        $serviceActions = _Sort-UniqueTextArray -Values @($script:State.FilterCatalog.ActionsByService[$serviceName] + @($Catalog.ActionsByService[$serviceName]))
        $script:State.FilterCatalog.ActionsByService[$serviceName] = $serviceActions
        $script:State.FilterCatalog.ServiceNames = _Sort-UniqueTextArray -Values @($script:State.FilterCatalog.ServiceNames + $serviceName)
        $script:State.FilterCatalog.Actions = _Sort-UniqueTextArray -Values @($script:State.FilterCatalog.Actions + $serviceActions)
    }
}

function _Get-FilterActionsForService {
    param([string]$ServiceName)

    if ([string]::IsNullOrWhiteSpace($ServiceName)) {
        return @($script:State.FilterCatalog.Actions)
    }

    foreach ($entry in $script:State.FilterCatalog.ActionsByService.GetEnumerator()) {
        if ([string]$entry.Key -ieq $ServiceName) {
            return @($entry.Value)
        }
    }

    return @($script:State.FilterCatalog.Actions)
}

function _Set-ComboItems {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.ComboBox]$ComboBox,
        [object[]]$Items,
        [string]$CurrentText = ''
    )

    $ComboBox.ItemsSource = @($Items)
    $ComboBox.Text = $CurrentText
}

function _Apply-FilterCatalogToUi {
    $serviceText = _Get-ComboText -Control $script:CmbService
    $actionText = _Get-ComboText -Control $script:CmbAction

    _Set-ComboItems -ComboBox $script:CmbService -Items $script:State.FilterCatalog.ServiceNames -CurrentText $serviceText
    _Set-ComboItems -ComboBox $script:CmbAction -Items (_Get-FilterActionsForService -ServiceName $serviceText) -CurrentText $actionText
}

function _Build-FilterCatalogFromRunFolder {
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    $catalog = _New-FilterCatalog
    $indexEntries = @(Load-AuditIndex -RunFolder $RunFolder)

    $catalog.ServiceNames = @($indexEntries | ForEach-Object { [string]$_.service } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $catalog.Actions = @($indexEntries | ForEach-Object { [string]$_.action } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

    foreach ($entry in $indexEntries) {
        $serviceName = [string]$entry.service
        $actionName = [string]$entry.action
        if ([string]::IsNullOrWhiteSpace($serviceName) -or [string]::IsNullOrWhiteSpace($actionName)) {
            continue
        }

        $catalog.ActionsByService[$serviceName] = _Sort-UniqueTextArray -Values @($catalog.ActionsByService[$serviceName] + $actionName)
    }

    return $catalog
}

function _Seed-FilterCatalogFromRecentRuns {
    if (-not $script:AppContext.StartupValidation.Ready) {
        return
    }

    foreach ($run in @(Get-RecentRuns -Max $script:AppContext.Settings.Ui.MaxRecentRuns)) {
        if ([string]::IsNullOrWhiteSpace([string]$run.RunFolder) -or -not [System.IO.Directory]::Exists($run.RunFolder)) {
            continue
        }

        try {
            _Add-FilterCatalog -Catalog (_Build-FilterCatalogFromRunFolder -RunFolder $run.RunFolder)
        }
        catch {
        }
    }
}

function _Refresh-FilterCatalogFromLiveSession {
    if ($null -eq $script:State.AuthContext) {
        return
    }

    try {
        _Add-FilterCatalog -Catalog (Get-AuditFilterOptions)
        _Apply-FilterCatalogToUi
    }
    catch {
    }
}

function _Read-DateTimeUtc {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DatePicker]$DatePicker,
        [Parameter(Mandatory)][System.Windows.Controls.TextBox]$TimeBox,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $DatePicker.SelectedDate) {
        throw "$Label date is required."
    }

    $timeText = [string]$TimeBox.Text
    $timeValue = [timespan]::Zero
    if (-not [timespan]::TryParse($timeText, [ref]$timeValue)) {
        throw "$Label time must use HH:mm format."
    }

    $baseDate = [datetime]$DatePicker.SelectedDate
    return [datetime]::SpecifyKind($baseDate.Date.Add($timeValue), [System.DateTimeKind]::Utc)
}

function _Apply-TimePreset {
    $now = [datetime]::UtcNow
    $selected = _Get-ComboText -Control $script:CmbTimePreset
    switch ($selected) {
        'Last 1 hour' {
            $script:DtpStartDate.SelectedDate = $now.AddHours(-1).Date
            $script:TxtStartTime.Text = $now.AddHours(-1).ToString('HH:mm')
            $script:DtpEndDate.SelectedDate = $now.Date
            $script:TxtEndTime.Text = $now.ToString('HH:mm')
        }
        'Last 4 hours' {
            $script:DtpStartDate.SelectedDate = $now.AddHours(-4).Date
            $script:TxtStartTime.Text = $now.AddHours(-4).ToString('HH:mm')
            $script:DtpEndDate.SelectedDate = $now.Date
            $script:TxtEndTime.Text = $now.ToString('HH:mm')
        }
        'Last 24 hours' {
            $script:DtpStartDate.SelectedDate = $now.AddHours(-24).Date
            $script:TxtStartTime.Text = $now.AddHours(-24).ToString('HH:mm')
            $script:DtpEndDate.SelectedDate = $now.Date
            $script:TxtEndTime.Text = $now.ToString('HH:mm')
        }
        'Last 7 days' {
            $script:DtpStartDate.SelectedDate = $now.AddDays(-7).Date
            $script:TxtStartTime.Text = $now.AddDays(-7).ToString('HH:mm')
            $script:DtpEndDate.SelectedDate = $now.Date
            $script:TxtEndTime.Text = $now.ToString('HH:mm')
        }
        default {
        }
    }
}

function _Build-QuerySpec {
    $startUtc = _Read-DateTimeUtc -DatePicker $script:DtpStartDate -TimeBox $script:TxtStartTime -Label 'Start'
    $endUtc = _Read-DateTimeUtc -DatePicker $script:DtpEndDate -TimeBox $script:TxtEndTime -Label 'End'
    $previewLimit = 0
    if (-not [int]::TryParse([string]$script:TxtPreviewLimit.Text, [ref]$previewLimit)) {
        throw 'Preview result limit must be a whole number.'
    }

    return [ordered]@{
        DatasetKey    = [string]$script:CmbDataset.SelectedItem
        StartUtc      = $startUtc
        EndUtc        = $endUtc
        Service       = _Get-ComboText -Control $script:CmbService
        Action        = _Get-ComboText -Control $script:CmbAction
        Actor         = [string]$script:TxtActor.Text
        Entity        = [string]$script:TxtEntity.Text
        Keyword       = [string]$script:TxtKeyword.Text
        PreviewLimit  = $previewLimit
    }
}

function _Get-CurrentFilters {
    return @{
        Service = _Get-ComboText -Control $script:CmbService
        Action  = _Get-ComboText -Control $script:CmbAction
        Actor   = [string]$script:TxtActor.Text
        Entity  = [string]$script:TxtEntity.Text
        Keyword = [string]$script:TxtKeyword.Text
    }
}

function _Set-RunActionState {
    $startupReady = [bool]$script:AppContext.StartupValidation.Ready
    $hasSession = $null -ne $script:State.AuthContext
    $isBusy = $null -ne $script:State.RunHandle -and -not $script:State.RunHandle.IsCompleted
    $hasRun = -not [string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)

    $script:BtnPreviewRun.IsEnabled = $startupReady -and $hasSession -and -not $isBusy
    $script:BtnFullRun.IsEnabled = $startupReady -and $hasSession -and -not $isBusy
    $script:BtnApplyFilters.IsEnabled = $hasRun
    $script:BtnResetFilters.IsEnabled = $hasRun
    $script:BtnExportFilteredCsv.IsEnabled = $hasRun
    $script:BtnExportFullCsv.IsEnabled = $hasRun
    $script:BtnExportFilteredHtml.IsEnabled = $hasRun
    $script:BtnExportFullHtml.IsEnabled = $hasRun
    $script:BtnOpenRunFolder.IsEnabled = $hasRun
    $script:BtnLoadSelectedRun.IsEnabled = $null -ne $script:LstRecentRuns.SelectedItem
}

function _Update-StartupBanner {
    if ($script:AppContext.StartupValidation.Ready) {
        $script:TxtStartupState.Text = $script:AppContext.StartupValidation.Message
    }
    else {
        $script:TxtStartupState.Text = "$($script:AppContext.StartupValidation.Message) $($script:AppContext.StartupValidation.Error)"
    }
}

function _Update-AuthState {
    if ($null -eq $script:State.AuthContext) {
        $script:TxtAuthState.Text = 'Not connected'
    }
    else {
        $script:TxtAuthState.Text = "Connected: $($script:State.AuthContext.Region)  expires $($script:State.AuthContext.ExpiresAt.ToString('u'))"
    }
}

function _Refresh-RecentRuns {
    if (-not $script:AppContext.StartupValidation.Ready) {
        return
    }

    $runs = @(Get-RecentRuns -Max $script:AppContext.Settings.Ui.MaxRecentRuns)
    $script:LstRecentRuns.ItemsSource = @($runs | ForEach-Object {
        [pscustomobject]@{
            Display    = "$($_.RunId)  [$($_.Status)]  $($_.Mode)  $($_.TotalRecords) rows"
            RunFolder  = $_.RunFolder
            DatasetKey = $_.DatasetKey
            Mode       = $_.Mode
            Status     = $_.Status
        }
    })
    _Set-RunActionState
}

function _Populate-RunFilters {
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    $services = @(Get-AuditDistinctValues -RunFolder $RunFolder -Field service)
    $actions = @(Get-AuditDistinctValues -RunFolder $RunFolder -Field action)
    $actionsByService = (_Build-FilterCatalogFromRunFolder -RunFolder $RunFolder).ActionsByService
    _Add-FilterCatalog -Catalog ([pscustomobject]@{
        ServiceNames     = $services
        Actions          = $actions
        ActionsByService = $actionsByService
    })
    _Apply-FilterCatalogToUi
}

function _Refresh-CurrentRunSummary {
    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) {
        $script:TxtCurrentRunFolder.Text = '(none loaded)'
        $script:TxtCurrentRunStatus.Text = ''
        $script:TxtSummaryCounts.Text = ''
        $script:TxtCurrentViewMode.Text = ''
        return
    }

    $summaryInfo = Get-AuditRunSummary -RunFolder $script:State.CurrentRunFolder
    $script:State.CurrentSummary = $summaryInfo
    $summary = $summaryInfo.Summary
    $status = Get-RunStatus -RunFolder $script:State.CurrentRunFolder
    $script:TxtCurrentRunFolder.Text = $script:State.CurrentRunFolder
    $script:TxtCurrentRunStatus.Text = $status

    if ($null -ne $summary -and $summary.totals) {
        $script:TxtSummaryCounts.Text = "records=$($summary.totals.totalRecords), services=$($summary.totals.totalServices), actions=$($summary.totals.totalActions)"
    }
    else {
        $script:TxtSummaryCounts.Text = "indexed=$($summaryInfo.TotalCount)"
    }

    if ($null -ne $summaryInfo.Request) {
        $script:State.CurrentRunMode = [string]$summaryInfo.Request.mode
        $script:TxtCurrentViewMode.Text = "$($summaryInfo.Request.mode)  |  dataset $($summaryInfo.Request.datasetKey)"
    }
    else {
        $script:TxtCurrentViewMode.Text = 'Existing run'
    }
}

function _Render-Console {
    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) {
        $script:TxtConsoleState.Text = 'No run loaded.'
        $script:LstRunEvents.ItemsSource = @()
        return
    }

    $status = Get-RunStatus -RunFolder $script:State.CurrentRunFolder
    $events = @(Get-RunEventTail -RunFolder $script:State.CurrentRunFolder -LastN 50)
    $script:TxtConsoleState.Text = $status
    $script:TxtConsoleError.Text = $script:State.RunLastError
    $script:LstRunEvents.ItemsSource = @($events | ForEach-Object {
        $message = ''
        if ($_.payload -and $_.payload.PSObject.Properties['message']) {
            $message = $_.payload.message
        }
        elseif ($_.payload -and $_.payload.PSObject.Properties['state']) {
            $message = $_.payload.state
        }
        "$($_.timestampUtc)  $($_.eventType)  $message"
    })
    $script:TxtDiagnosticsPreview.Text = Get-RunDiagnosticsText -RunFolder $script:State.CurrentRunFolder
}

function _Load-Detail {
    param(
        [Parameter(Mandatory)][string]$RecordId
    )

    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) {
        return
    }

    $record = Get-AuditRecordById -RunFolder $script:State.CurrentRunFolder -RecordId $RecordId
    if ($null -eq $record) {
        return
    }

    $flat = ConvertTo-AuditFlatRow -Record $record
    $summaryLines = @()
    foreach ($key in $flat.Keys) {
        $summaryLines += "${key}: $($flat[$key])"
    }

    $changes = @()
    foreach ($path in @('changes', 'context.changes', 'changedProperties')) {
        $current = $record
        $resolved = $true
        foreach ($segment in ($path -split '\.')) {
            if ($null -eq $current -or -not $current.PSObject.Properties[$segment]) {
                $resolved = $false
                break
            }
            $current = $current.$segment
        }
        if ($resolved -and $null -ne $current) {
            $changes = @($current | ForEach-Object {
                [pscustomobject]@{
                    Field  = if ($_.PSObject.Properties['field']) { $_.field } elseif ($_.PSObject.Properties['name']) { $_.name } else { '' }
                    Before = if ($_.PSObject.Properties['before']) { $_.before } else { '' }
                    After  = if ($_.PSObject.Properties['after']) { $_.after } else { '' }
                }
            })
            break
        }
    }

    $script:TxtSelectedRecord.Text = "Record $RecordId"
    $script:TxtDetailSummary.Text = $summaryLines -join [Environment]::NewLine
    $script:DgChangedProperties.ItemsSource = $changes
    $script:TxtRawJson.Text = $record | ConvertTo-Json -Depth 100
}

function _Refresh-Results {
    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) {
        $script:DgAuditResults.ItemsSource = @()
        $script:TxtPageInfo.Text = 'Page 0 of 0'
        return
    }

    $filters = _Get-CurrentFilters
    $limit = 0
    if ($script:State.CurrentRunMode -eq 'Preview') {
        [void][int]::TryParse([string]$script:TxtPreviewLimit.Text, [ref]$limit)
    }

    $script:State.FilteredIndex = @(Search-AuditRun -RunFolder $script:State.CurrentRunFolder -Service $filters.Service -Action $filters.Action -Actor $filters.Actor -Entity $filters.Entity -Keyword $filters.Keyword -Limit $limit)
    $page = Get-AuditResultPage -RunFolder $script:State.CurrentRunFolder -IndexEntries $script:State.FilteredIndex -PageNumber $script:State.CurrentPage -PageSize $script:State.PageSize
    $script:DgAuditResults.ItemsSource = $page.Rows
    $script:TxtPageInfo.Text = "Page $($page.PageNumber) of $($page.TotalPages)  |  $($page.TotalCount) records"
    $script:BtnPrevPage.IsEnabled = $page.PageNumber -gt 1
    $script:BtnNextPage.IsEnabled = $page.PageNumber -lt $page.TotalPages
    $script:TxtCurrentRunStatus.Text = Get-RunStatus -RunFolder $script:State.CurrentRunFolder
}

function _Load-Run {
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [string]$Mode = ''
    )

    if (-not [System.IO.Directory]::Exists($RunFolder)) {
        throw "Run folder not found: $RunFolder"
    }

    $script:State.CurrentRunFolder = $RunFolder
    if (-not [string]::IsNullOrWhiteSpace($Mode)) {
        $script:State.CurrentRunMode = $Mode
    }
    else {
        $request = Get-RunRequestMetadata -RunFolder $RunFolder
        if ($null -ne $request) {
            $script:State.CurrentRunMode = [string]$request.mode
        }
    }

    Clear-AuditIndexCache -RunFolder $RunFolder
    Load-AuditIndex -RunFolder $RunFolder | Out-Null
    _Populate-RunFilters -RunFolder $RunFolder
    _Refresh-CurrentRunSummary
    $script:State.CurrentPage = 1
    _Refresh-Results
    _Render-Console
    _Set-RunActionState
    _SetStatus -Main "Loaded run $([System.IO.Path]::GetFileName($RunFolder))" -Right ([datetime]::Now.ToString('HH:mm:ss'))
}

function _Open-RunFolder {
    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) {
        return
    }

    if (_IsWindowsDesktop) {
        Start-Process explorer.exe $script:State.CurrentRunFolder | Out-Null
    }
}

function _Get-ExportPath {
    param(
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$Title
    )

    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = $Filter
    $dialog.Title = $Title
    if ($dialog.ShowDialog()) {
        return $dialog.FileName
    }

    return $null
}

function _Start-Run {
    param(
        [Parameter(Mandatory)][ValidateSet('Preview', 'Full')][string]$Mode
    )

    try {
        $querySpec = _Build-QuerySpec
    }
    catch {
        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            'Invalid Run Parameters',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $script:State.CurrentRunMode = $Mode
    $script:State.CurrentQuerySpec = $querySpec
    $script:State.RunLastError = ''
    $script:State.CurrentRunFolder = $null
    $script:State.RunStartedAtUtc = [datetime]::UtcNow
    $script:TxtConsoleError.Text = ''
    $script:TxtConsoleState.Text = 'Queued'
    $script:LstRunEvents.ItemsSource = @()
    $script:TxtDiagnosticsPreview.Text = ''

    $scriptText = @'
param($appRoot, $settings, $mode, $querySpec, $accessToken, $region)
Import-Module (Join-Path $appRoot 'App.CoreAdapter.psm1') -Force
Initialize-CoreIntegration -CoreModulePath $settings.CoreModulePath -AuthModulePath $settings.AuthModulePath -CatalogPath $settings.CatalogPath -SchemaPath $settings.SchemaPath -OutputRoot $settings.OutputRoot -DatasetKeys $settings.DatasetKeys -PreviewConfig $settings.Preview | Out-Null
Connect-AuditSession -AccessToken $accessToken -Region $region | Out-Null
if ($mode -eq 'Preview') {
    Start-AuditPreviewRun -QuerySpec $querySpec
}
else {
    Start-AuditFullRun -QuerySpec $querySpec
}
'@

    $ps = [powershell]::Create()
    [void]$ps.AddScript($scriptText)
    [void]$ps.AddArgument($script:AppContext.Settings.AppRoot)
    [void]$ps.AddArgument($script:AppContext.Settings)
    [void]$ps.AddArgument($Mode)
    [void]$ps.AddArgument($querySpec)
    [void]$ps.AddArgument(($script:PwdAccessToken.Password))
    [void]$ps.AddArgument($script:CmbRegion.Text)

    $script:State.RunPowerShell = $ps
    $script:State.RunHandle = $ps.BeginInvoke()
    _Set-RunActionState
    _SetStatus -Main "$Mode run started..." -Right ([datetime]::Now.ToString('HH:mm:ss'))
}

function _Poll-BackgroundRun {
    if ($null -eq $script:State.RunHandle) {
        return
    }

    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder) -and $script:AppContext.StartupValidation.Ready) {
        $datasetRoot = Join-Path $script:AppContext.Settings.OutputRoot $script:AppContext.Settings.DatasetKeys.Default
        if ([System.IO.Directory]::Exists($datasetRoot)) {
            $candidates = Get-ChildItem -Path $datasetRoot -Directory | Sort-Object CreationTimeUtc -Descending
            foreach ($candidate in $candidates) {
                if ($candidate.CreationTimeUtc -ge $script:State.RunStartedAtUtc.AddMinutes(-1)) {
                    $script:State.CurrentRunFolder = $candidate.FullName
                    break
                }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) {
        _Refresh-CurrentRunSummary
        _Render-Console
    }

    if (-not $script:State.RunHandle.IsCompleted) {
        return
    }

    try {
        $result = $script:State.RunPowerShell.EndInvoke($script:State.RunHandle)
        $finalResult = $result | Select-Object -Last 1
        if ($null -ne $finalResult -and $finalResult.RunContext -and $finalResult.RunContext.runFolder) {
            $script:State.CurrentRunFolder = [string]$finalResult.RunContext.runFolder
            Save-RunRequestMetadata -RunFolder $script:State.CurrentRunFolder -QuerySpec $script:State.CurrentQuerySpec -Mode $script:State.CurrentRunMode -DatasetKey $finalResult.DatasetKey -Effective $finalResult.Effective | Out-Null
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) {
            _Load-Run -RunFolder $script:State.CurrentRunFolder -Mode $script:State.CurrentRunMode
        }
    }
    catch {
        $script:State.RunLastError = $_.Exception.Message
        $script:TxtConsoleError.Text = $_.Exception.Message
        _Render-Console
        _SetStatus -Main 'Run failed.' -Right ([datetime]::Now.ToString('HH:mm:ss'))
    }
    finally {
        try { $script:State.RunPowerShell.Dispose() } catch { }
        $script:State.RunPowerShell = $null
        $script:State.RunHandle = $null
        _Refresh-RecentRuns
        _Set-RunActionState
    }
}

function _Try-AutoConnect {
    if (-not $script:AppContext.StartupValidation.Ready) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($env:GENESYS_BEARER_TOKEN)) {
        return
    }

    try {
        $script:State.AuthContext = Connect-AuditSession -AccessToken $env:GENESYS_BEARER_TOKEN -Region $script:CmbRegion.Text
        _Update-AuthState
        _Refresh-FilterCatalogFromLiveSession
        _Set-RunActionState
    }
    catch {
    }
}

$script:CmbRegion.ItemsSource = $script:AppContext.Settings.Ui.Regions
$script:CmbRegion.Text = $script:AppContext.Settings.Ui.DefaultRegion
$script:CmbDataset.ItemsSource = @($script:AppContext.Settings.DatasetKeys.Default)
$script:CmbDataset.SelectedIndex = 0
$script:CmbTimePreset.SelectedIndex = 0
_Seed-FilterCatalogFromRecentRuns
_Apply-FilterCatalogToUi
_Apply-TimePreset
_Update-StartupBanner
_Update-AuthState
_Set-RunActionState
_Refresh-RecentRuns
_Try-AutoConnect

$script:State.PollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:State.PollTimer.Interval = [TimeSpan]::FromSeconds(1.5)
$script:State.PollTimer.Add_Tick({ _Poll-BackgroundRun })
$script:State.PollTimer.Start()

$script:BtnConnect.Add_Click({
    try {
        $script:State.AuthContext = Connect-AuditSession -AccessToken $script:PwdAccessToken.Password -Region $script:CmbRegion.Text
        _Update-AuthState
        _Refresh-FilterCatalogFromLiveSession
        _SetStatus -Main 'Connected to Genesys Cloud session.' -Right ([datetime]::Now.ToString('HH:mm:ss'))
        _Set-RunActionState
    }
    catch {
        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            'Connection Error',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
})

$script:CmbTimePreset.Add_SelectionChanged({ _Apply-TimePreset })
$script:CmbService.Add_DropDownClosed({ _Apply-FilterCatalogToUi })
$script:CmbService.Add_LostFocus({ _Apply-FilterCatalogToUi })
$script:BtnPreviewRun.Add_Click({ _Start-Run -Mode 'Preview' })
$script:BtnFullRun.Add_Click({ _Start-Run -Mode 'Full' })
$script:BtnRefreshRuns.Add_Click({ _Refresh-RecentRuns })
$script:BtnLoadSelectedRun.Add_Click({
    if ($null -ne $script:LstRecentRuns.SelectedItem) {
        _Load-Run -RunFolder $script:LstRecentRuns.SelectedItem.RunFolder -Mode $script:LstRecentRuns.SelectedItem.Mode
    }
})
$script:LstRecentRuns.Add_SelectionChanged({ _Set-RunActionState })
$script:BtnOpenRunFolder.Add_Click({ _Open-RunFolder })
$script:BtnApplyFilters.Add_Click({
    $script:State.CurrentPage = 1
    _Refresh-Results
})
$script:BtnResetFilters.Add_Click({
    $script:CmbService.Text = ''
    $script:CmbAction.Text = ''
    $script:TxtActor.Text = ''
    $script:TxtEntity.Text = ''
    $script:TxtKeyword.Text = ''
    $script:State.CurrentPage = 1
    _Apply-FilterCatalogToUi
    _Refresh-Results
})
$script:BtnPrevPage.Add_Click({
    if ($script:State.CurrentPage -gt 1) {
        $script:State.CurrentPage--
        _Refresh-Results
    }
})
$script:BtnNextPage.Add_Click({
    $script:State.CurrentPage++
    _Refresh-Results
})
$script:DgAuditResults.Add_SelectionChanged({
    if ($null -ne $script:DgAuditResults.SelectedItem -and $script:DgAuditResults.SelectedItem.PSObject.Properties['RecordId']) {
        _Load-Detail -RecordId $script:DgAuditResults.SelectedItem.RecordId
    }
})
$script:BtnCopyDetailSummary.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:TxtDetailSummary.Text)) {
        [System.Windows.Clipboard]::SetText($script:TxtDetailSummary.Text)
    }
})
$script:BtnCopyRawJson.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:TxtRawJson.Text)) {
        [System.Windows.Clipboard]::SetText($script:TxtRawJson.Text)
    }
})
$script:BtnCopyDiagnostics.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) {
        $diagnostics = Get-RunDiagnosticsText -RunFolder $script:State.CurrentRunFolder
        [System.Windows.Clipboard]::SetText($diagnostics)
        _SetStatus -Main 'Diagnostics copied to clipboard.' -Right ([datetime]::Now.ToString('HH:mm:ss'))
    }
})
$script:BtnExportFilteredCsv.Add_Click({
    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) { return }
    $path = _Get-ExportPath -Filter 'CSV (*.csv)|*.csv' -Title 'Export Filtered Audit Rows to CSV'
    if ($path) {
        Export-AuditCsv -RunFolder $script:State.CurrentRunFolder -IndexEntries $script:State.FilteredIndex -OutputPath $path
        _SetStatus -Main "Filtered CSV exported to $path" -Right ([datetime]::Now.ToString('HH:mm:ss'))
    }
})
$script:BtnExportFullCsv.Add_Click({
    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) { return }
    $path = _Get-ExportPath -Filter 'CSV (*.csv)|*.csv' -Title 'Export Full Audit Run to CSV'
    if ($path) {
        Export-AuditCsv -RunFolder $script:State.CurrentRunFolder -OutputPath $path
        _SetStatus -Main "Full CSV exported to $path" -Right ([datetime]::Now.ToString('HH:mm:ss'))
    }
})
$script:BtnExportFilteredHtml.Add_Click({
    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) { return }
    $path = _Get-ExportPath -Filter 'HTML (*.html)|*.html' -Title 'Export Filtered Audit Rows to HTML'
    if ($path) {
        Export-AuditHtml -RunFolder $script:State.CurrentRunFolder -IndexEntries $script:State.FilteredIndex -OutputPath $path -Summary $script:State.CurrentSummary.Summary -Filters (_Get-CurrentFilters) -ViewMode 'Filtered View'
        _SetStatus -Main "Filtered HTML exported to $path" -Right ([datetime]::Now.ToString('HH:mm:ss'))
    }
})
$script:BtnExportFullHtml.Add_Click({
    if ([string]::IsNullOrWhiteSpace([string]$script:State.CurrentRunFolder)) { return }
    $path = _Get-ExportPath -Filter 'HTML (*.html)|*.html' -Title 'Export Full Audit Run to HTML'
    if ($path) {
        Export-AuditHtml -RunFolder $script:State.CurrentRunFolder -OutputPath $path -Summary $script:State.CurrentSummary.Summary -Filters (_Get-CurrentFilters) -ViewMode 'Full Run'
        _SetStatus -Main "Full HTML exported to $path" -Right ([datetime]::Now.ToString('HH:mm:ss'))
    }
})
