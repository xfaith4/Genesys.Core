#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $appRoot 'App.Settings.psd1'
if (-not (Test-Path $settingsPath)) { throw "App.Settings.psd1 not found at $settingsPath" }
$settings = Import-PowerShellDataFile -Path $settingsPath

$corePath    = [System.IO.Path]::GetFullPath((Join-Path $appRoot $settings.CoreModuleRelativePath))
$authPath    = [System.IO.Path]::GetFullPath((Join-Path $appRoot $settings.AuthModuleRelativePath))
$catalogPath = [System.IO.Path]::GetFullPath((Join-Path $appRoot $settings.CatalogRelativePath))
$schemaPath  = [System.IO.Path]::GetFullPath((Join-Path $appRoot $settings.SchemaRelativePath))
$outputRoot  = [System.IO.Path]::GetFullPath((Join-Path $appRoot $settings.OutputRelativePath))

Import-Module (Join-Path $appRoot 'App.CoreAdapter.psm1') -Force

$initResult = Initialize-CoreIntegration `
    -CoreModulePath $corePath `
    -AuthModulePath $authPath `
    -CatalogPath $catalogPath `
    -SchemaPath $schemaPath `
    -OutputRoot $outputRoot

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Genesys Interrogator"
        Height="820" Width="1340"
        WindowStartupLocation="CenterScreen"
        Background="#F8FAFC">
  <DockPanel>

    <Border DockPanel.Dock="Top" Padding="12,10" Background="#0F1B2D">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="GENESYS INTERROGATOR" Foreground="#E2E8F0" FontWeight="Bold" FontSize="14" VerticalAlignment="Center" Margin="0,0,20,0"/>
        <TextBlock Text="Region" Foreground="#94A3B8" Margin="0,0,6,0" VerticalAlignment="Center"/>
        <ComboBox Name="CmbRegion" Width="170" IsEditable="True" Height="26" Margin="0,0,10,0"/>
        <TextBlock Text="Bearer token" Foreground="#94A3B8" Margin="0,0,6,0" VerticalAlignment="Center"/>
        <PasswordBox Name="TxtToken" Width="300" Height="26" Margin="0,0,10,0" VerticalContentAlignment="Center"/>
        <Button Name="BtnConnect" Content="Bearer" Width="80" Height="26" Margin="0,0,14,0"/>
        <TextBlock Text="PKCE client ID" Foreground="#94A3B8" Margin="0,0,6,0" VerticalAlignment="Center"/>
        <TextBox Name="TxtPkceClientId" Width="230" Height="26" Margin="0,0,10,0" VerticalContentAlignment="Center"/>
        <Button Name="BtnPkceLogin" Content="Browser PKCE" Width="110" Height="26" Margin="0,0,8,0"/>
        <Button Name="BtnCancelPkce" Content="Cancel" Width="70" Height="26" IsEnabled="False"/>
        <TextBlock Name="TxtConn" Foreground="#94A3B8" Margin="14,0,0,0" VerticalAlignment="Center" Text="Not connected."/>
      </StackPanel>
    </Border>

    <Border DockPanel.Dock="Bottom" Padding="10,6" Background="#0F1B2D">
      <TextBlock Name="TxtStatus" Foreground="#94A3B8" Text="Ready."/>
    </Border>

    <Grid DockPanel.Dock="Left" Width="360" Margin="10">
      <TabControl Name="TabSidebar">
        <TabItem Header="Datasets" Name="TabSideDatasets">
          <Grid Margin="4,8,4,4">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Name="TxtCatalogCount" Foreground="#64748B" Margin="0,0,0,6" Text=""/>
            <TextBox Grid.Row="1" Name="TxtFilter" Height="26" Margin="0,0,0,8" VerticalContentAlignment="Center" ToolTip="Filter by key, group, endpoint, or description"/>
            <ListBox Grid.Row="2" Name="LstDatasets" DisplayMemberPath="Display"/>
          </Grid>
        </TabItem>
        <TabItem Header="Reports" Name="TabSideReports">
          <Grid Margin="4,8,4,4">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Foreground="#64748B" Margin="0,0,0,8" TextWrapping="Wrap"
                       Text="Composed investigations across multiple datasets. Each report runs an Ops cmdlet that joins data the API can't filter natively."/>
            <ListBox Grid.Row="1" Name="LstReports" DisplayMemberPath="Display"/>
          </Grid>
        </TabItem>
      </TabControl>
    </Grid>

    <Grid Margin="10">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="220"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <TextBlock Grid.Row="0" Name="TxtDatasetTitle" FontWeight="Bold" FontSize="15" Text="Select a dataset to begin"/>
      <TextBlock Grid.Row="1" Name="TxtDatasetMeta" Foreground="#475569" Margin="0,4,0,10" TextWrapping="Wrap"/>

      <Grid Grid.Row="2">
        <GroupBox Name="GrpDatasetParams" Header="Dataset parameters (JSON)">
          <TextBox Name="TxtParams" AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                   VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                   FontFamily="Consolas" FontSize="12" Padding="6"/>
        </GroupBox>
        <GroupBox Name="GrpReportParams" Header="Report parameters" Visibility="Collapsed">
          <Grid Margin="10,8,10,8">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="200"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Row="0" Grid.Column="0" Text="Window (days back)" VerticalAlignment="Center" Margin="0,4,0,4"/>
            <TextBox   Grid.Row="0" Grid.Column="1" Name="TxtNrDays" Text="14" Width="80" HorizontalAlignment="Left" Margin="0,4,0,4"/>
            <TextBlock Grid.Row="1" Grid.Column="0" Text="Min transitions per active day" VerticalAlignment="Center" Margin="0,4,0,4"
                       ToolTip="Flag agents whose transitions/active-day exceeds this value"/>
            <TextBox   Grid.Row="1" Grid.Column="1" Name="TxtNrThreshold" Text="1.0" Width="80" HorizontalAlignment="Left" Margin="0,4,0,4"/>
            <TextBlock Grid.Row="2" Grid.Column="0" Text="Top N users" VerticalAlignment="Center" Margin="0,4,0,4"/>
            <TextBox   Grid.Row="2" Grid.Column="1" Name="TxtNrTopN" Text="25" Width="80" HorizontalAlignment="Left" Margin="0,4,0,4"/>
            <CheckBox  Grid.Row="3" Grid.ColumnSpan="2" Name="ChkNrIncludeConv" Margin="0,8,0,4"
                       Content="Include conversation context (pulls a conversation-details job for top-N users; adds 30s–2min)"/>
            <TextBlock Grid.Row="4" Grid.ColumnSpan="2" Foreground="#64748B" TextWrapping="Wrap" Margin="0,8,0,0"
                       Text="Submits an async user-details job filtered to NOT_RESPONDING transitions, then aggregates per-user counts, durations, and daily breakdown. With conversation context, joins on userId to surface affected conversations."/>
          </Grid>
        </GroupBox>
      </Grid>

      <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,10">
        <Button Name="BtnRun" Content="Run dataset" Width="140" Height="30" FontWeight="Bold"/>
        <Button Name="BtnCancel" Content="Cancel run" Width="140" Height="30" Margin="10,0,0,0" IsEnabled="False"/>
        <Button Name="BtnReset" Content="Reset parameters" Width="160" Height="30" Margin="10,0,0,0"/>
        <Button Name="BtnOpenRun" Content="Open run folder" Width="160" Height="30" Margin="10,0,0,0" IsEnabled="False"/>
        <TextBlock Name="TxtProgress" Foreground="#475569" Margin="16,0,0,0" VerticalAlignment="Center" Text=""/>
      </StackPanel>

      <TabControl Grid.Row="4" Name="TabResults">
        <TabItem Header="Live events" Name="TabLive">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Foreground="#64748B" Margin="6,4" Text="Newest first. Tail of events.jsonl produced by Genesys.Core during the run."/>
            <ListBox Grid.Row="1" Name="LstEvents" FontFamily="Consolas" FontSize="12"/>
          </Grid>
        </TabItem>
        <TabItem Header="Rows" Name="TabRows">
          <DataGrid Name="GridResults"
                    AutoGenerateColumns="True"
                    IsReadOnly="True"
                    HeadersVisibility="All"
                    CanUserAddRows="False"
                    CanUserDeleteRows="False"
                    AlternatingRowBackground="#F1F5F9"
                    GridLinesVisibility="Horizontal"/>
        </TabItem>
        <TabItem Header="Summary &amp; manifest">
          <TextBox Name="TxtSummary" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                   TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
        </TabItem>
        <TabItem Header="Raw JSON (first rows)">
          <TextBox Name="TxtRaw" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                   TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
        </TabItem>
      </TabControl>
    </Grid>

  </DockPanel>
</Window>
'@

[xml]$xml = $xaml
$reader = New-Object System.Xml.XmlNodeReader $xml
$window = [Windows.Markup.XamlReader]::Load($reader)

$controls = @{}
foreach ($n in 'CmbRegion','TxtToken','BtnConnect','TxtPkceClientId','BtnPkceLogin','BtnCancelPkce','TxtConn','TxtStatus',
               'TabSidebar','TabSideDatasets','TabSideReports',
               'TxtCatalogCount','TxtFilter','LstDatasets','LstReports',
               'TxtDatasetTitle','TxtDatasetMeta',
               'GrpDatasetParams','TxtParams',
               'GrpReportParams','TxtNrDays','TxtNrThreshold','TxtNrTopN','ChkNrIncludeConv',
               'BtnRun','BtnCancel','BtnReset','BtnOpenRun','TxtProgress',
               'TabResults','TabLive','TabRows',
               'GridResults','TxtSummary','TxtRaw','LstEvents') {
    $controls[$n] = $window.FindName($n)
}

foreach ($r in $settings.Ui.Regions) { [void]$controls.CmbRegion.Items.Add($r) }
$controls.CmbRegion.Text = $settings.Ui.DefaultRegion
$controls.TxtPkceClientId.Text = if ([string]::IsNullOrWhiteSpace($env:GENESYS_PKCE_CLIENT_ID)) { [string]$settings.OAuth.PkceClientId } else { $env:GENESYS_PKCE_CLIENT_ID }

$script:AllDatasets     = @(Get-CatalogDatasets)
$script:SelectedDataset = $null
$script:SelectedReport  = $null
$script:RunMode         = 'dataset'   # 'dataset' | 'report'
$script:LastRunFolder   = $null
$script:ActiveRun       = $null
$script:ActiveAuth      = $null
$script:PendingResultsJob = $null

foreach ($d in $script:AllDatasets) {
    $display = ("[{0}] {1}" -f $d.Group, $d.Key)
    $d | Add-Member -NotePropertyName Display -NotePropertyValue $display -Force
}

# Available reports — composed Ops cmdlets that join multiple datasets.
$script:AvailableReports = @(
    [pscustomobject]@{
        Key         = 'not-responding'
        Name        = 'Not-Responding patterns'
        Display     = '[Investigation] Not-Responding patterns'
        Description = 'Submits an async user-details job filtered to NOT_RESPONDING and (optionally) a conversation-details job filtered by the top-N user IDs. Aggregates per-user transition count, total/avg NR seconds, daily breakdown, and flags agents above the transitions-per-day threshold.'
        Cmdlet      = 'Invoke-GenesysNotRespondingReport'
        Datasets    = @('analytics.post.users.details.jobs', 'analytics-conversation-details')
    }
)
foreach ($r in $script:AvailableReports) { [void]$controls.LstReports.Items.Add($r) }

function Set-DatasetList {
    param([object[]]$Items)
    $controls.LstDatasets.Items.Clear()
    foreach ($d in $Items) { [void]$controls.LstDatasets.Items.Add($d) }
    $controls.TxtCatalogCount.Text = "$($Items.Count) of $($script:AllDatasets.Count) datasets"
}

Set-DatasetList -Items $script:AllDatasets

function Set-Status {
    param([string]$Message, [string]$Color = '#94A3B8')
    $controls.TxtStatus.Text = $Message
    $controls.TxtStatus.Foreground = $Color
}

function Set-Progress {
    param([string]$Message)
    $controls.TxtProgress.Text = $Message
}

function Set-AuthActionState {
    $authBusy = $null -ne $script:ActiveAuth -and -not $script:ActiveAuth.AsyncResult.IsCompleted
    $runBusy = $null -ne $script:ActiveRun
    $controls.BtnConnect.IsEnabled = -not $authBusy -and -not $runBusy
    $controls.BtnPkceLogin.IsEnabled = -not $authBusy -and -not $runBusy
    $controls.BtnCancelPkce.IsEnabled = $authBusy
}

Set-Status "Catalog loaded. $($script:AllDatasets.Count) datasets. Connect a session to run." '#94A3B8'
Set-AuthActionState

$controls.TxtFilter.Add_TextChanged({
    $q = $controls.TxtFilter.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($q)) {
        Set-DatasetList -Items $script:AllDatasets
        return
    }
    $filtered = @($script:AllDatasets | Where-Object {
        $_.Key         -like "*$q*" -or
        $_.Group       -like "*$q*" -or
        $_.Description -like "*$q*" -or
        $_.Endpoint    -like "*$q*" -or
        $_.Path        -like "*$q*"
    })
    Set-DatasetList -Items $filtered
})

$controls.LstDatasets.Add_SelectionChanged({
    $sel = $controls.LstDatasets.SelectedItem
    if ($null -eq $sel) { return }
    $script:SelectedDataset = $sel

    $controls.TxtDatasetTitle.Text = $sel.Key
    $meta = "{0} {1}" -f $sel.Method, $sel.Path
    $meta += "`n$($sel.Description)"
    $meta += "`nGroup: $($sel.Group)  |  Endpoint: $($sel.Endpoint)"
    $meta += "`nPaging: $($sel.PagingProfile)  |  Retry: $($sel.RetryProfile)  |  ItemsPath: $($sel.ItemsPath)"
    if (-not [string]::IsNullOrWhiteSpace($sel.Transaction)) {
        $meta += "  |  Transaction: $($sel.Transaction)"
    }
    $controls.TxtDatasetMeta.Text = $meta

    $defaults = Get-DefaultDatasetParameters -Endpoint $sel.EndpointDef
    if ($defaults -and $defaults.Keys.Count -gt 0) {
        $controls.TxtParams.Text = ($defaults | ConvertTo-Json -Depth 12)
    } else {
        $controls.TxtParams.Text = '{}'
    }
})

$controls.BtnReset.Add_Click({
    if ($script:RunMode -eq 'report') {
        $controls.TxtNrDays.Text         = '14'
        $controls.TxtNrThreshold.Text    = '1.0'
        $controls.TxtNrTopN.Text         = '25'
        $controls.ChkNrIncludeConv.IsChecked = $false
        return
    }
    if ($null -eq $script:SelectedDataset) { return }
    $defaults = Get-DefaultDatasetParameters -Endpoint $script:SelectedDataset.EndpointDef
    $controls.TxtParams.Text = if ($defaults -and $defaults.Keys.Count -gt 0) {
        ($defaults | ConvertTo-Json -Depth 12)
    } else { '{}' }
})

function Set-RunMode {
    param([ValidateSet('dataset','report')][string]$Mode)
    $script:RunMode = $Mode
    if ($Mode -eq 'report') {
        $controls.GrpDatasetParams.Visibility = 'Collapsed'
        $controls.GrpReportParams.Visibility  = 'Visible'
        $controls.BtnRun.Content = 'Run report'
    } else {
        $controls.GrpDatasetParams.Visibility = 'Visible'
        $controls.GrpReportParams.Visibility  = 'Collapsed'
        $controls.BtnRun.Content = 'Run dataset'
    }
}

$controls.TabSidebar.Add_SelectionChanged({
    # Only respond when the change is from the sidebar TabControl itself, not nested controls.
    if ($_.OriginalSource -ne $controls.TabSidebar) { return }
    if ($controls.TabSidebar.SelectedItem -eq $controls.TabSideReports) {
        Set-RunMode -Mode 'report'
        if ($null -eq $script:SelectedReport -and $controls.LstReports.Items.Count -gt 0) {
            $controls.LstReports.SelectedIndex = 0
        }
    } else {
        Set-RunMode -Mode 'dataset'
        if ($null -ne $script:SelectedDataset) {
            $controls.TxtDatasetTitle.Text = $script:SelectedDataset.Key
        }
    }
})

$controls.LstReports.Add_SelectionChanged({
    $sel = $controls.LstReports.SelectedItem
    if ($null -eq $sel) { return }
    $script:SelectedReport = $sel
    $controls.TxtDatasetTitle.Text = $sel.Name
    $meta  = $sel.Description
    $meta += "`nCmdlet: $($sel.Cmdlet)"
    $meta += "`nUnderlying datasets: $($sel.Datasets -join ', ')"
    $controls.TxtDatasetMeta.Text = $meta
    Set-RunMode -Mode 'report'
})

$controls.BtnConnect.Add_Click({
    try {
        $token = $controls.TxtToken.Password
        if ([string]::IsNullOrWhiteSpace($token)) { $token = $env:GENESYS_BEARER_TOKEN }
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'Enter a bearer token or set the GENESYS_BEARER_TOKEN environment variable.'
        }
        $token = $token.Trim()
        $region = $controls.CmbRegion.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($region)) {
            throw 'Select a Genesys Cloud region (e.g. usw2.pure.cloud).'
        }
        $ctx = Connect-InterrogatorSession -AccessToken $token -Region $region
        $controls.TxtConn.Text = "Connected to $($ctx.Region) (expires $($ctx.ExpiresAt.ToString('u')))"
        $controls.TxtConn.Foreground = '#34D399'
        Set-Status "Connected to $($ctx.Region). Ready to run datasets." '#34D399'
    } catch {
        $controls.TxtConn.Text = "Connect failed"
        $controls.TxtConn.Foreground = '#F87171'
        Set-Status ("Connect failed: " + $_.Exception.Message) '#F87171'
    }
})

function Start-InterrogatorPkceLogin {
    if ($null -ne $script:ActiveAuth -and -not $script:ActiveAuth.AsyncResult.IsCompleted) { return }

    $clientId = [string]$controls.TxtPkceClientId.Text
    if ([string]::IsNullOrWhiteSpace($clientId) -and -not [string]::IsNullOrWhiteSpace($env:GENESYS_PKCE_CLIENT_ID)) {
        $clientId = $env:GENESYS_PKCE_CLIENT_ID
    }
    $clientId = $clientId.Trim()
    if ([string]::IsNullOrWhiteSpace($clientId)) {
        Set-Status 'Enter a PKCE OAuth client ID or set GENESYS_PKCE_CLIENT_ID.' '#FBBF24'
        return
    }

    $region = $controls.CmbRegion.Text.Trim()
    $redirectUri = if ($settings.OAuth.PkceRedirectUri) { [string]$settings.OAuth.PkceRedirectUri } else { 'http://localhost:8080/callback' }
    $cts = [System.Threading.CancellationTokenSource]::new()

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
        param($AppRoot, $CoreModulePath, $AuthModulePath, $CatalogPath, $SchemaPath, $OutputRoot, $ClientId, $Region, $RedirectUri, $CancelToken)
        Import-Module (Join-Path $AppRoot 'App.CoreAdapter.psm1') -Force -ErrorAction Stop
        Initialize-CoreIntegration -CoreModulePath $CoreModulePath -AuthModulePath $AuthModulePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath -OutputRoot $OutputRoot | Out-Null
        Connect-InterrogatorSessionPkce -ClientId $ClientId -Region $Region -RedirectUri $RedirectUri -CancellationToken $CancelToken
    })
    [void]$ps.AddArgument($appRoot)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($authPath)
    [void]$ps.AddArgument($catalogPath)
    [void]$ps.AddArgument($schemaPath)
    [void]$ps.AddArgument($outputRoot)
    [void]$ps.AddArgument($clientId)
    [void]$ps.AddArgument($region)
    [void]$ps.AddArgument($redirectUri)
    [void]$ps.AddArgument($cts.Token)

    $async = $ps.BeginInvoke()
    $script:ActiveAuth = @{
        PsInstance  = $ps
        Runspace    = $runspace
        AsyncResult = $async
        Cancel      = $cts
        Timer       = $null
        Region      = $region
    }

    $controls.TxtConn.Text = 'PKCE login in progress...'
    $controls.TxtConn.Foreground = '#FBBF24'
    Set-Status 'PKCE login started. Complete the browser sign-in.' '#FBBF24'
    Set-AuthActionState

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        $auth = $script:ActiveAuth
        if ($null -eq $auth -or -not $auth.AsyncResult.IsCompleted) { return }
        try { $auth.Timer.Stop() } catch {}

        try {
            $result = $auth.PsInstance.EndInvoke($auth.AsyncResult)
            $ctx = $result | Select-Object -Last 1
            if ($null -eq $ctx) { throw 'PKCE login completed without an auth context.' }

            Connect-InterrogatorSession -AccessToken ([string]$ctx.Token) -Region ([string]$ctx.Region) | Out-Null
            $controls.TxtConn.Text = "Connected to $($ctx.Region) via PKCE (expires $($ctx.ExpiresAt.ToString('u')))"
            $controls.TxtConn.Foreground = '#34D399'
            Set-Status "Connected to $($ctx.Region) via PKCE. Ready to run datasets." '#34D399'
        }
        catch {
            $controls.TxtConn.Text = 'PKCE login failed'
            $controls.TxtConn.Foreground = '#F87171'
            Set-Status ("PKCE login failed: " + $_.Exception.Message) '#F87171'
        }
        finally {
            try { $auth.PsInstance.Dispose() } catch {}
            try { $auth.Runspace.Close(); $auth.Runspace.Dispose() } catch {}
            try { $auth.Cancel.Dispose() } catch {}
            $script:ActiveAuth = $null
            Set-AuthActionState
        }
    })
    $script:ActiveAuth.Timer = $timer
    $timer.Start()
}

$controls.BtnPkceLogin.Add_Click({ Start-InterrogatorPkceLogin })
$controls.BtnCancelPkce.Add_Click({
    if ($null -eq $script:ActiveAuth) { return }
    try { $script:ActiveAuth.Cancel.Cancel() } catch {}
    Set-Status 'Cancelling PKCE login...' '#FBBF24'
    $controls.BtnCancelPkce.IsEnabled = $false
})

function ConvertFrom-JsonToHashtable {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return @{} }
    $obj = $Json | ConvertFrom-Json
    if ($null -eq $obj) { return @{} }
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
        return $h
    }
    throw 'Parameters JSON must be an object.'
}

function Add-LiveEvent {
    param([string]$Line, [string]$Color = '#0F172A')
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Content = $Line
    $item.Foreground = $Color
    [void]$controls.LstEvents.Items.Insert(0, $item)
    while ($controls.LstEvents.Items.Count -gt 600) {
        $controls.LstEvents.Items.RemoveAt($controls.LstEvents.Items.Count - 1)
    }
}

function Format-EventForDisplay {
    param([psobject]$Event)
    $ts = ''
    if ($Event.PSObject.Properties['timestampUtc']) {
        try { $ts = ([datetime]$Event.timestampUtc).ToLocalTime().ToString('HH:mm:ss.fff') } catch { $ts = [string]$Event.timestampUtc }
    }
    $type = if ($Event.PSObject.Properties['eventType']) { [string]$Event.eventType } else { '' }
    $parts = @($ts, $type)

    switch -Wildcard ($type) {
        'request.invoked' {
            if ($Event.PSObject.Properties['method']) { $parts += [string]$Event.method }
            if ($Event.PSObject.Properties['uri'])    { $parts += [string]$Event.uri }
        }
        'request.completed' {
            if ($Event.PSObject.Properties['statusCode']) { $parts += "$($Event.statusCode)" }
            if ($Event.PSObject.Properties['durationMs']) { $parts += "$($Event.durationMs)ms" }
            if ($Event.PSObject.Properties['responseItemCount'] -and $null -ne $Event.responseItemCount) {
                $parts += "items=$($Event.responseItemCount)"
            }
            if ($Event.PSObject.Properties['attempts'] -and $null -ne $Event.attempts) {
                $parts += "attempts=$($Event.attempts)"
            }
        }
        'request.failed' {
            if ($Event.PSObject.Properties['statusCode']) { $parts += "$($Event.statusCode)" }
            if ($Event.PSObject.Properties['errorMessage']) { $parts += [string]$Event.errorMessage }
        }
        'request.attempt.failed' {
            if ($Event.PSObject.Properties['statusCode']) { $parts += "$($Event.statusCode)" }
            if ($Event.PSObject.Properties['message'])    { $parts += [string]$Event.message }
        }
        'request.retry.scheduled' {
            if ($Event.PSObject.Properties['retryAfterSeconds']) { $parts += "retry in $($Event.retryAfterSeconds)s" }
        }
        'paging.progress' {
            if ($Event.PSObject.Properties['profile']) { $parts += "profile=$($Event.profile)" }
            if ($Event.PSObject.Properties['page'])    { $parts += "page=$($Event.page)" }
            if ($Event.PSObject.Properties['totalHits']) { $parts += "totalHits=$($Event.totalHits)" }
        }
        'paging.terminated.*' {
            if ($Event.PSObject.Properties['page']) { $parts += "page=$($Event.page)" }
        }
        default {}
    }

    return ($parts -join ' | ')
}

function Get-EventColor {
    param([string]$EventType)
    switch -Wildcard ($EventType) {
        'run.started'        { return '#0369A1' }
        'run.completed'      { return '#047857' }
        'run.failed'         { return '#B91C1C' }
        'request.invoked'    { return '#0F172A' }
        'request.completed'  { return '#0F172A' }
        'request.failed'     { return '#B91C1C' }
        'request.attempt.failed' { return '#B45309' }
        'request.retry.scheduled' { return '#B45309' }
        'paging.progress'    { return '#5B21B6' }
        'paging.terminated.*' { return '#B45309' }
        default              { return '#334155' }
    }
}

function Read-NewEventLines {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][ref]$LinesSeen)

    $newLines = New-Object System.Collections.Generic.List[string]
    try {
        $fs = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        try {
            $idx = 0
            while (-not $sr.EndOfStream) {
                $line = $sr.ReadLine()
                if ($idx -ge $LinesSeen.Value -and -not [string]::IsNullOrWhiteSpace($line)) {
                    [void]$newLines.Add($line)
                }
                $idx++
            }
            $LinesSeen.Value = $idx
        }
        finally {
            $sr.Dispose(); $fs.Dispose()
        }
    }
    catch [System.IO.IOException] {
        return @()
    }
    return $newLines.ToArray()
}

function Find-NewestRunFolder {
    param([string]$DatasetRoot, [datetime]$SinceUtc)
    if (-not [System.IO.Directory]::Exists($DatasetRoot)) { return $null }
    $latest = $null
    foreach ($d in [System.IO.Directory]::GetDirectories($DatasetRoot)) {
        $ct = [System.IO.Directory]::GetCreationTimeUtc($d)
        if ($ct -lt $SinceUtc) { continue }
        if ($null -eq $latest -or $ct -gt $latest.CreationTimeUtc) {
            $latest = [pscustomobject]@{ Path = $d; CreationTimeUtc = $ct }
        }
    }
    if ($null -eq $latest) { return $null }
    return $latest.Path
}

function Complete-Run {
    param([bool]$Cancelled = $false)

    $run = $script:ActiveRun
    if ($null -eq $run) { return }

    if ($run.Timer) {
        try { $run.Timer.Stop() } catch {}
    }

    $output = $null
    $errorRecord = $null
    try {
        if ($run.AsyncResult.IsCompleted -or $Cancelled) {
            $output = $run.PsInstance.EndInvoke($run.AsyncResult)
        }
        if ($run.PsInstance.HadErrors) {
            $errorRecord = $run.PsInstance.Streams.Error | Select-Object -First 1
        }
    }
    catch {
        $errorRecord = $_
    }
    finally {
        try { $run.PsInstance.Dispose() } catch {}
        try { $run.Runspace.Close(); $run.Runspace.Dispose() } catch {}
    }

    $runFolder = $run.RunFolder
    if (-not $runFolder -and $null -ne $output) {
        try { $runFolder = [string]$output.runFolder } catch {}
    }

    if ($Cancelled) {
        Set-Status "Run cancelled by user." '#FBBF24'
        $controls.TxtSummary.Text = "Run was cancelled. Run folder: $runFolder"
    }
    elseif ($null -ne $errorRecord) {
        $ex = $errorRecord.Exception
        $msg = if ($ex) { $ex.Message } else { [string]$errorRecord }
        $body = $null
        if ($errorRecord.PSObject.Properties['ErrorDetails'] -and $null -ne $errorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($errorRecord.ErrorDetails.Message)) {
            $body = $errorRecord.ErrorDetails.Message
        }
        $statusMsg = if ($body) { "Run failed: $msg | $body" } else { "Run failed: $msg" }
        Set-Status $statusMsg '#F87171'
        $details = "=== Error ===`n$msg"
        if ($ex) { $details += "`n`n=== Exception ===`n$($ex.ToString())" }
        if ($body) { $details += "`n`n=== Response body ===`n$body" }
        if ($runFolder) { $details += "`n`n=== Run folder ===`n$runFolder" }
        $controls.TxtSummary.Text = $details
    }
    else {
        if ($runFolder) {
            $script:LastRunFolder = $runFolder
            $controls.BtnOpenRun.IsEnabled = $true

            # Load results in a background runspace so the UI thread stays responsive.
            Set-Status ("Completed '{0}'. Loading results…" -f $run.DatasetKey) '#34D399'
            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

            $capturedRunFolder  = $runFolder
            $capturedDatasetKey = $run.DatasetKey
            $capturedMaxRows    = $settings.Ui.PreviewRows
            $capturedCorePath   = $corePath

            $rsRes = [runspacefactory]::CreateRunspace()
            $rsRes.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
            $rsRes.Open()
            $psRes = [powershell]::Create()
            $psRes.Runspace = $rsRes
            [void]$psRes.AddScript({
                param($CoreModulePath, $RunFolder, $MaxRows)
                Import-Module $CoreModulePath -Force -ErrorAction Stop
                $results = Get-RunResults -RunFolder $RunFolder -MaxRows $MaxRows
                $flat    = ConvertTo-FlatRows -Rows $results.Rows
                return [pscustomobject]@{ Results = $results; FlatRows = $flat }
            })
            [void]$psRes.AddArgument($capturedCorePath)
            [void]$psRes.AddArgument($capturedRunFolder)
            [void]$psRes.AddArgument($capturedMaxRows)
            $asyncRes = $psRes.BeginInvoke()

            $script:PendingResultsJob = @{
                PsInstance   = $psRes
                Runspace     = $rsRes
                AsyncResult  = $asyncRes
                RunFolder    = $capturedRunFolder
                DatasetKey   = $capturedDatasetKey
                Timer        = $null
            }

            $resultTimer = New-Object System.Windows.Threading.DispatcherTimer
            $resultTimer.Interval = [TimeSpan]::FromMilliseconds(200)
            $resultTimer.Add_Tick({
                $job = $script:PendingResultsJob
                if ($null -eq $job) { $resultTimer.Stop(); return }
                if (-not $job.AsyncResult.IsCompleted) { return }

                $resultTimer.Stop()
                [System.Windows.Input.Mouse]::OverrideCursor = $null

                try {
                    $output = $job.PsInstance.EndInvoke($job.AsyncResult)
                    $loaded  = $output | Select-Object -Last 1
                    $results = $loaded.Results
                    $flat    = $loaded.FlatRows

                    $controls.GridResults.ItemsSource = $flat

                    $summaryText  = if ($null -ne $results.Summary)  { ($results.Summary  | ConvertTo-Json -Depth 10) } else { '(no summary.json)' }
                    $manifestText = if ($null -ne $results.Manifest) { ($results.Manifest | ConvertTo-Json -Depth 10) } else { '(no manifest.json)' }
                    $controls.TxtSummary.Text = "=== summary.json ===`n$summaryText`n`n=== manifest.json ===`n$manifestText"

                    $sb = New-Object System.Text.StringBuilder
                    $previewCount = [Math]::Min($results.Rows.Count, 50)
                    for ($i = 0; $i -lt $previewCount; $i++) {
                        [void]$sb.AppendLine(($results.Rows[$i] | ConvertTo-Json -Depth 10 -Compress))
                    }
                    if ($results.Rows.Count -gt $previewCount) {
                        [void]$sb.AppendLine("...")
                        [void]$sb.AppendLine("($($results.Rows.Count - $previewCount) more rows truncated in this view; full JSONL is in $($results.DataDir))")
                    }
                    $controls.TxtRaw.Text = $sb.ToString()

                    $total = $results.Rows.Count
                    if ($null -ne $results.Summary -and $results.Summary.PSObject.Properties['totals'] -and $null -ne $results.Summary.totals -and $results.Summary.totals.PSObject.Properties['totalRecords']) {
                        $total = [int]$results.Summary.totals.totalRecords
                    }
                    Set-Status ("Completed '{0}'. Total records: {1}. Preview rows: {2}. Run folder: {3}" -f $job.DatasetKey, $total, $flat.Count, $job.RunFolder) '#34D399'
                    $controls.TabResults.SelectedItem = $controls.TabRows
                }
                catch {
                    [System.Windows.Input.Mouse]::OverrideCursor = $null
                    Set-Status "Run completed but results could not be loaded: $($_.Exception.Message)" '#F87171'
                    $controls.TxtSummary.Text = $_.Exception.ToString()
                }
                finally {
                    try { $job.PsInstance.Dispose() } catch {}
                    try { $job.Runspace.Close(); $job.Runspace.Dispose() } catch {}
                    $script:PendingResultsJob = $null
                }
            }.GetNewClosure())
            $script:PendingResultsJob.Timer = $resultTimer
            $resultTimer.Start()
        }
        else {
            Set-Status "Run completed but no run folder was detected." '#FBBF24'
        }
    }

    $script:ActiveRun = $null
    $controls.BtnRun.IsEnabled = $true
    $controls.BtnCancel.IsEnabled = $false
    $controls.BtnRun.Content = 'Run dataset'
    Set-AuthActionState
    Set-Progress ''
}

function Start-ReportRun {
    if ($null -ne $script:ActiveRun) { return }
    if ($null -eq $script:SelectedReport) {
        Set-Status 'Select a report first.' '#FBBF24'
        return
    }

    $session = Get-InterrogatorSession
    if ($null -eq $session) {
        Set-Status 'Not connected. Click Connect first.' '#FBBF24'
        return
    }

    $days = 0; $threshold = 0.0; $topN = 0
    if (-not [int]::TryParse($controls.TxtNrDays.Text.Trim(), [ref]$days) -or $days -le 0 -or $days -gt 90) {
        Set-Status 'Window (days back) must be a positive integer between 1 and 90.' '#F87171'; return
    }
    if (-not [double]::TryParse($controls.TxtNrThreshold.Text.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$threshold) -or $threshold -lt 0 -or $threshold -gt 1000) {
        Set-Status 'Min transitions/day must be a non-negative number no greater than 1000.' '#F87171'; return
    }
    if (-not [int]::TryParse($controls.TxtNrTopN.Text.Trim(), [ref]$topN) -or $topN -le 0 -or $topN -gt 1000) {
        Set-Status 'Top N must be a positive integer between 1 and 1000.' '#F87171'; return
    }
    $includeConv = [bool]$controls.ChkNrIncludeConv.IsChecked

    $reportKey  = $script:SelectedReport.Key
    $cmdlet     = $script:SelectedReport.Cmdlet
    $runId      = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $reportRoot = [System.IO.Path]::Combine($outputRoot, '_reports', $reportKey, $runId)
    [void][System.IO.Directory]::CreateDirectory($reportRoot)
    $reportPath = [System.IO.Path]::Combine($reportRoot, 'report.json')

    $controls.BtnRun.IsEnabled = $false
    $controls.BtnCancel.IsEnabled = $true
    $controls.BtnRun.Content = 'Running...'
    Set-AuthActionState
    $controls.GridResults.ItemsSource = $null
    $controls.TxtSummary.Text = ''
    $controls.TxtRaw.Text = ''
    $controls.LstEvents.Items.Clear()
    $controls.TabResults.SelectedItem = $controls.TabLive
    Set-Status ("Started report '{0}' over the last {1} day(s)..." -f $script:SelectedReport.Name, $days) '#FBBF24'
    Set-Progress 'submitting jobs...'
    Add-LiveEvent -Line ("{0} | report.started | {1}" -f (Get-Date -f 'HH:mm:ss.fff'), $cmdlet) -Color '#0369A1'
    if ($includeConv) {
        Add-LiveEvent -Line 'note: -IncludeConversations adds a conversation-details job (slower)' -Color '#5B21B6'
    }

    $authPathLocal    = $authPath
    $opsPathCandidate = [System.IO.Path]::GetFullPath((Join-Path $appRoot '../../modules/Genesys.Ops/Genesys.Ops.psd1'))

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
        param($AuthModulePath, $CoreModulePath, $OpsModulePath, $AccessToken, $Region,
              $Cmdlet, $Days, $Threshold, $TopN, $IncludeConv, $OutputPath)

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        Import-Module $AuthModulePath -Force -ErrorAction Stop
        Import-Module $CoreModulePath -Force -ErrorAction Stop
        Import-Module $OpsModulePath  -Force -ErrorAction Stop

        # Use the Ops Connect-GenesysCloud (most-recent import wins) to set $script:GC state.
        Connect-GenesysCloud -AccessToken $AccessToken -Region $Region | Out-Null

        $until = [datetime]::UtcNow
        $since = $until.AddDays(-1 * $Days)

        $params = @{
            Since                = $since
            Until                = $until
            MinTransitionsPerDay = $Threshold
            TopN                 = $TopN
            OutputPath           = $OutputPath
            PassThru             = $true
        }
        if ($IncludeConv) { $params.IncludeConversations = $true }

        & $Cmdlet @params
    })
    [void]$ps.AddArgument($authPathLocal)
    [void]$ps.AddArgument($corePath)
    [void]$ps.AddArgument($opsPathCandidate)
    [void]$ps.AddArgument([string]$session.Token)
    [void]$ps.AddArgument([string]$session.Region)
    [void]$ps.AddArgument($cmdlet)
    [void]$ps.AddArgument($days)
    [void]$ps.AddArgument($threshold)
    [void]$ps.AddArgument($topN)
    [void]$ps.AddArgument($includeConv)
    [void]$ps.AddArgument($reportPath)

    $async = $ps.BeginInvoke()

    $script:ActiveRun = @{
        Mode         = 'report'
        PsInstance   = $ps
        Runspace     = $runspace
        AsyncResult  = $async
        ReportKey    = $reportKey
        ReportPath   = $reportPath
        RunFolder    = $reportRoot
        StartUtc     = [datetime]::UtcNow
        Timer        = $null
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $timer.Add_Tick({
        $run = $script:ActiveRun
        if ($null -eq $run) { return }
        $elapsed = ([datetime]::UtcNow - $run.StartUtc).ToString('hh\:mm\:ss')
        Set-Progress $elapsed
        if ($run.AsyncResult.IsCompleted) { Complete-ReportRun }
    })
    $script:ActiveRun.Timer = $timer
    $timer.Start()
}

function Complete-ReportRun {
    $run = $script:ActiveRun
    if ($null -eq $run) { return }
    if ($run.Timer) { try { $run.Timer.Stop() } catch {} }

    $errorRecord = $null
    try {
        $output = $run.PsInstance.EndInvoke($run.AsyncResult)
        if ($run.PsInstance.HadErrors) {
            $errorRecord = $run.PsInstance.Streams.Error | Select-Object -First 1
        }
    } catch {
        $errorRecord = $_
    } finally {
        try { $run.PsInstance.Dispose() } catch {}
        try { $run.Runspace.Close(); $run.Runspace.Dispose() } catch {}
    }

    if ($null -ne $errorRecord) {
        $msg = if ($errorRecord.Exception) { $errorRecord.Exception.Message } else { [string]$errorRecord }
        Set-Status "Report failed: $msg" '#F87171'
        $controls.TxtSummary.Text = "=== Error ===`n$msg`n`n$($errorRecord | Out-String)"
    }
    elseif (-not [System.IO.File]::Exists($run.ReportPath)) {
        Set-Status 'Report completed but no report.json was produced.' '#FBBF24'
    }
    else {
        $script:LastRunFolder = $run.RunFolder
        $controls.BtnOpenRun.IsEnabled = $true
        try {
            $report = Get-Content -Path $run.ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $controls.GridResults.ItemsSource = @($report.TopUsers | ForEach-Object {
                [pscustomobject]@{
                    UserId                  = $_.UserId
                    Name                    = $_.Name
                    Division                = $_.Division
                    TransitionCount         = $_.TransitionCount
                    ActiveDays              = $_.ActiveDays
                    TransitionsPerActiveDay = $_.TransitionsPerActiveDay
                    TotalNrSeconds          = $_.TotalNrSeconds
                    AvgNrSeconds            = $_.AvgNrSeconds
                    Flag                    = $_.Flag
                    DailyBreakdown          = (@($_.DailyBreakdown) | ForEach-Object { "$($_.Date)x$($_.Count)" }) -join ' '
                    Conversations           = (@($_.ConversationIds).Count)
                }
            })

            $headerLines = @(
                "Report: $($script:SelectedReport.Name)"
                "Window: $($report.Window.Since)  ->  $($report.Window.Until)  ($($report.Window.Days) day(s))"
                "Threshold: >= $($report.Threshold.MinTransitionsPerDay) transitions/active-day"
                "Users with NR transitions: $($report.UsersWithNotResponding)"
                "Users flagged Consistent: $($report.UsersFlaggedConsistent)"
                "Total NR transitions: $($report.TotalNrTransitions)"
                "Generated: $($report.GeneratedAt)"
            )
            $controls.TxtSummary.Text = ($headerLines -join "`n") + "`n`n=== Full report (JSON) ===`n" + ($report | ConvertTo-Json -Depth 8)

            $sb = New-Object System.Text.StringBuilder
            foreach ($u in @($report.AllUsers | Select-Object -First 50)) {
                [void]$sb.AppendLine(($u | ConvertTo-Json -Depth 6 -Compress))
            }
            if (@($report.AllUsers).Count -gt 50) {
                [void]$sb.AppendLine("... ($(@($report.AllUsers).Count - 50) more users in report.json)")
            }
            $controls.TxtRaw.Text = $sb.ToString()

            Set-Status ("Report complete. {0} users with NR ({1} flagged). File: {2}" -f $report.UsersWithNotResponding, $report.UsersFlaggedConsistent, $run.ReportPath) '#34D399'
            $controls.TabResults.SelectedItem = $controls.TabRows
            Add-LiveEvent -Line ("{0} | report.completed | {1} users / {2} flagged" -f (Get-Date -f 'HH:mm:ss.fff'), $report.UsersWithNotResponding, $report.UsersFlaggedConsistent) -Color '#047857'
        } catch {
            Set-Status "Report ran but the result could not be loaded: $($_.Exception.Message)" '#F87171'
            $controls.TxtSummary.Text = $_.Exception.ToString()
        }
    }

    $script:ActiveRun = $null
    $controls.BtnRun.IsEnabled = $true
    $controls.BtnCancel.IsEnabled = $false
    $controls.BtnRun.Content = if ($script:RunMode -eq 'report') { 'Run report' } else { 'Run dataset' }
    Set-AuthActionState
    Set-Progress ''
}

$controls.BtnRun.Add_Click({
    if ($null -ne $script:ActiveRun) { return }

    if ($script:RunMode -eq 'report') {
        Start-ReportRun
        return
    }

    if ($null -eq $script:SelectedDataset) {
        Set-Status 'Select a dataset first.' '#FBBF24'
        return
    }

    $session = Get-InterrogatorSession
    if ($null -eq $session) {
        Set-Status 'Not connected. Click Connect first.' '#FBBF24'
        return
    }

    $datasetKey = [string]$script:SelectedDataset.Key
    if ([string]::IsNullOrWhiteSpace($datasetKey)) {
        Set-Status 'Dataset key is empty. Select a dataset from the catalog list.' '#F87171'
        return
    }
    if (-not ($script:AllDatasets | Where-Object { $_.Key -eq $datasetKey })) {
        Set-Status ("Dataset '{0}' is not in the loaded catalog." -f $datasetKey) '#F87171'
        return
    }

    $paramsText = [string]$controls.TxtParams.Text
    if ($paramsText.Length -gt 65536) {
        Set-Status 'Parameters JSON is too large (max 64 KB).' '#F87171'
        return
    }
    $params = $null
    try { $params = ConvertFrom-JsonToHashtable $paramsText }
    catch {
        Set-Status ("Parameters JSON invalid: " + $_.Exception.Message) '#F87171'
        return
    }

    $controls.BtnRun.IsEnabled = $false
    $controls.BtnCancel.IsEnabled = $true
    $controls.BtnRun.Content = 'Running...'
    Set-AuthActionState
    $controls.GridResults.ItemsSource = $null
    $controls.TxtSummary.Text = ''
    $controls.TxtRaw.Text = ''
    $controls.LstEvents.Items.Clear()
    $controls.TabResults.SelectedItem = $controls.TabLive
    Set-Status ("Started '{0}'. Waiting for Genesys.Core to open the run folder..." -f $script:SelectedDataset.Key) '#FBBF24'
    Set-Progress "page 0"

    $datasetKey = $script:SelectedDataset.Key
    $startUtc   = [datetime]::UtcNow.AddSeconds(-2)

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
        param($CoreModulePath, $CatalogPath, $OutputRoot, $BaseUri, $Headers, $DatasetKey, $DatasetParameters)
        Import-Module $CoreModulePath -Force -ErrorAction Stop
        $invokeParams = @{
            Dataset     = $DatasetKey
            CatalogPath = $CatalogPath
            OutputRoot  = $OutputRoot
            BaseUri     = $BaseUri
            Headers     = $Headers
            ErrorAction = 'Stop'
        }
        if ($null -ne $DatasetParameters -and $DatasetParameters.Count -gt 0) {
            $invokeParams.DatasetParameters = $DatasetParameters
        }
        Invoke-Dataset @invokeParams
    })
    [void]$ps.AddParameter('CoreModulePath',    $corePath)
    [void]$ps.AddParameter('CatalogPath',       $catalogPath)
    [void]$ps.AddParameter('OutputRoot',        $outputRoot)
    [void]$ps.AddParameter('BaseUri',           $session.BaseUri)
    [void]$ps.AddParameter('Headers',           $session.Headers)
    [void]$ps.AddParameter('DatasetKey',        $datasetKey)
    [void]$ps.AddParameter('DatasetParameters', $params)

    $async = $ps.BeginInvoke()

    $script:ActiveRun = @{
        PsInstance   = $ps
        Runspace     = $runspace
        AsyncResult  = $async
        DatasetKey   = $datasetKey
        DatasetRoot  = [System.IO.Path]::Combine($outputRoot, $datasetKey)
        StartUtc     = $startUtc
        RunFolder    = $null
        EventsSeen   = 0
        LastPage     = 0
        LastItems    = 0
        Timer        = $null
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $timer.Add_Tick({
        $run = $script:ActiveRun
        if ($null -eq $run) { return }

        if ($null -eq $run.RunFolder) {
            $found = Find-NewestRunFolder -DatasetRoot $run.DatasetRoot -SinceUtc $run.StartUtc
            if ($found) {
                $run.RunFolder = $found
                Set-Status ("Run folder: {0}" -f $found) '#FBBF24'
            }
        }

        # Show elapsed time alongside any paging progress
        $elapsed = ([datetime]::UtcNow - $run.StartUtc).ToString('hh\:mm\:ss')
        if ($run.LastPage -gt 0) {
            $tot = if ($run.LastItems -gt 0) { " items=$($run.LastItems)" } else { '' }
            Set-Progress ("page $($run.LastPage)$tot  [$elapsed]")
        } else {
            Set-Progress $elapsed
        }

        if ($null -ne $run.RunFolder) {
            $eventsPath = [System.IO.Path]::Combine($run.RunFolder, 'events.jsonl')
            if ([System.IO.File]::Exists($eventsPath)) {
                $seenRef = [ref]$run.EventsSeen
                $newLines = Read-NewEventLines -Path $eventsPath -LinesSeen $seenRef
                $run.EventsSeen = $seenRef.Value
                foreach ($line in $newLines) {
                    try {
                        $evt = $line | ConvertFrom-Json
                    } catch { continue }
                    $display = Format-EventForDisplay -Event $evt
                    $color   = Get-EventColor -EventType ([string]$evt.eventType)
                    Add-LiveEvent -Line $display -Color $color

                    if ($evt.PSObject.Properties['eventType'] -and [string]$evt.eventType -eq 'paging.progress') {
                        if ($evt.PSObject.Properties['page']) { $run.LastPage = [int]$evt.page }
                        $tot = ''
                        if ($evt.PSObject.Properties['totalHits'] -and $null -ne $evt.totalHits) { $tot = " / total=$($evt.totalHits)" }
                        Set-Status ("Running '{0}': page {1}{2}" -f $run.DatasetKey, $run.LastPage, $tot) '#FBBF24'
                    }
                    elseif ($evt.PSObject.Properties['eventType'] -and [string]$evt.eventType -eq 'request.completed') {
                        if ($evt.PSObject.Properties['responseItemCount'] -and $null -ne $evt.responseItemCount) {
                            $run.LastItems = [int]$evt.responseItemCount
                        }
                    }
                }
            }
        }

        if ($run.AsyncResult.IsCompleted) {
            Complete-Run -Cancelled:$false
        }
    })
    $script:ActiveRun.Timer = $timer
    $timer.Start()
})

$controls.BtnCancel.Add_Click({
    $run = $script:ActiveRun
    if ($null -eq $run) { return }
    Set-Status "Cancelling run..." '#FBBF24'
    $controls.BtnCancel.IsEnabled = $false
    try { [void]$run.PsInstance.BeginStop($null, $null) } catch {}
    $isReport = ($run.PSObject.Properties['Mode'] -and $run.Mode -eq 'report')
    if ($isReport) {
        if ($run.Timer) { try { $run.Timer.Stop() } catch {} }
        try { $run.PsInstance.Dispose() } catch {}
        try { $run.Runspace.Close(); $run.Runspace.Dispose() } catch {}
        $script:ActiveRun = $null
        $controls.BtnRun.IsEnabled = $true
        $controls.BtnCancel.IsEnabled = $false
        $controls.BtnRun.Content = if ($script:RunMode -eq 'report') { 'Run report' } else { 'Run dataset' }
        Set-AuthActionState
        Set-Progress ''
        Set-Status 'Report cancelled.' '#FBBF24'
    } else {
        Complete-Run -Cancelled:$true
    }
})

$controls.BtnOpenRun.Add_Click({
    if ($script:LastRunFolder -and [System.IO.Directory]::Exists($script:LastRunFolder)) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $script:LastRunFolder
    }
})

$window.Add_Closing({
    if ($null -ne $script:ActiveAuth) {
        try { $script:ActiveAuth.Cancel.Cancel() } catch {}
        try { $script:ActiveAuth.Timer.Stop() } catch {}
        try { $script:ActiveAuth.PsInstance.Dispose() } catch {}
        try { $script:ActiveAuth.Runspace.Close(); $script:ActiveAuth.Runspace.Dispose() } catch {}
        $script:ActiveAuth = $null
    }
    if ($null -ne $script:ActiveRun) {
        try { [void]$script:ActiveRun.PsInstance.BeginStop($null, $null) } catch {}
        try { $script:ActiveRun.Timer.Stop() } catch {}
        try { $script:ActiveRun.PsInstance.Dispose() } catch {}
        try { $script:ActiveRun.Runspace.Close(); $script:ActiveRun.Runspace.Dispose() } catch {}
        $script:ActiveRun = $null
    }
    if ($null -ne $script:PendingResultsJob) {
        try { $script:PendingResultsJob.Timer.Stop() } catch {}
        try { $script:PendingResultsJob.PsInstance.Dispose() } catch {}
        try { $script:PendingResultsJob.Runspace.Close(); $script:PendingResultsJob.Runspace.Dispose() } catch {}
        $script:PendingResultsJob = $null
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
})

[void]$window.ShowDialog()
