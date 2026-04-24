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
        Height="760" Width="1320"
        WindowStartupLocation="CenterScreen"
        Background="#F8FAFC">
  <DockPanel>

    <Border DockPanel.Dock="Top" Padding="12,10" Background="#0F1B2D">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="GENESYS INTERROGATOR" Foreground="#E2E8F0" FontWeight="Bold" FontSize="14" VerticalAlignment="Center" Margin="0,0,20,0"/>
        <TextBlock Text="Region" Foreground="#94A3B8" Margin="0,0,6,0" VerticalAlignment="Center"/>
        <ComboBox Name="CmbRegion" Width="170" IsEditable="True" Height="26" Margin="0,0,10,0"/>
        <TextBlock Text="Bearer token" Foreground="#94A3B8" Margin="0,0,6,0" VerticalAlignment="Center"/>
        <TextBox Name="TxtToken" Width="300" Height="26" Margin="0,0,10,0" VerticalContentAlignment="Center"/>
        <Button Name="BtnConnect" Content="Connect" Width="90" Height="26"/>
        <TextBlock Name="TxtConn" Foreground="#94A3B8" Margin="14,0,0,0" VerticalAlignment="Center" Text="Not connected."/>
      </StackPanel>
    </Border>

    <Border DockPanel.Dock="Bottom" Padding="10,6" Background="#0F1B2D">
      <TextBlock Name="TxtStatus" Foreground="#94A3B8" Text="Ready."/>
    </Border>

    <Grid DockPanel.Dock="Left" Width="360" Margin="10">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Text="Catalog datasets" FontWeight="Bold" FontSize="13" Margin="0,0,0,6"/>
      <TextBlock Grid.Row="1" Name="TxtCatalogCount" Foreground="#64748B" Margin="0,0,0,6" Text=""/>
      <TextBox Grid.Row="2" Name="TxtFilter" Height="26" Margin="0,0,0,8" VerticalContentAlignment="Center" ToolTip="Filter by key, group, endpoint, or description"/>
      <ListBox Grid.Row="3" Name="LstDatasets" DisplayMemberPath="Display"/>
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

      <GroupBox Grid.Row="2" Header="Dataset parameters (JSON)">
        <TextBox Name="TxtParams" AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="12" Padding="6"/>
      </GroupBox>

      <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,10">
        <Button Name="BtnRun" Content="Run dataset" Width="160" Height="30" FontWeight="Bold"/>
        <Button Name="BtnReset" Content="Reset parameters" Width="160" Height="30" Margin="10,0,0,0"/>
        <Button Name="BtnOpenRun" Content="Open run folder" Width="160" Height="30" Margin="10,0,0,0" IsEnabled="False"/>
      </StackPanel>

      <TabControl Grid.Row="4">
        <TabItem Header="Rows">
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
foreach ($n in 'CmbRegion','TxtToken','BtnConnect','TxtConn','TxtStatus',
               'TxtCatalogCount','TxtFilter','LstDatasets',
               'TxtDatasetTitle','TxtDatasetMeta','TxtParams',
               'BtnRun','BtnReset','BtnOpenRun',
               'GridResults','TxtSummary','TxtRaw') {
    $controls[$n] = $window.FindName($n)
}

foreach ($r in $settings.Ui.Regions) { [void]$controls.CmbRegion.Items.Add($r) }
$controls.CmbRegion.Text = $settings.Ui.DefaultRegion

$script:AllDatasets     = @(Get-CatalogDatasets)
$script:SelectedDataset = $null
$script:LastRunFolder   = $null

foreach ($d in $script:AllDatasets) {
    $display = ("[{0}] {1}" -f $d.Group, $d.Key)
    $d | Add-Member -NotePropertyName Display -NotePropertyValue $display -Force
}

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

Set-Status "Catalog loaded. $($script:AllDatasets.Count) datasets. Connect a session to run." '#94A3B8'

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
    if ($null -eq $script:SelectedDataset) { return }
    $defaults = Get-DefaultDatasetParameters -Endpoint $script:SelectedDataset.EndpointDef
    $controls.TxtParams.Text = if ($defaults -and $defaults.Keys.Count -gt 0) {
        ($defaults | ConvertTo-Json -Depth 12)
    } else { '{}' }
})

$controls.BtnConnect.Add_Click({
    try {
        $token = $controls.TxtToken.Text
        if ([string]::IsNullOrWhiteSpace($token)) { $token = $env:GENESYS_BEARER_TOKEN }
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'Enter a bearer token or set the GENESYS_BEARER_TOKEN environment variable.'
        }
        $region = $controls.CmbRegion.Text.Trim()
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

$controls.BtnRun.Add_Click({
    if ($null -eq $script:SelectedDataset) {
        Set-Status 'Select a dataset first.' '#FBBF24'
        return
    }

    $session = Get-InterrogatorSession
    if ($null -eq $session) {
        Set-Status 'Not connected. Click Connect first.' '#FBBF24'
        return
    }

    $params = $null
    try { $params = ConvertFrom-JsonToHashtable $controls.TxtParams.Text }
    catch {
        Set-Status ("Parameters JSON invalid: " + $_.Exception.Message) '#F87171'
        return
    }

    $controls.BtnRun.IsEnabled = $false
    $controls.BtnRun.Content = 'Running...'
    $controls.GridResults.ItemsSource = $null
    $controls.TxtSummary.Text = ''
    $controls.TxtRaw.Text = ''
    Set-Status ("Running '{0}'... the UI will stay frozen until the run completes." -f $script:SelectedDataset.Key) '#FBBF24'
    $controls.BtnRun.Dispatcher.Invoke([Action]{}, 'Background')

    try {
        $runCtx = Invoke-InterrogatorRun -DatasetKey $script:SelectedDataset.Key -DatasetParameters $params
        $script:LastRunFolder = $runCtx.runFolder
        $controls.BtnOpenRun.IsEnabled = $true

        $results = Get-RunResults -RunFolder $runCtx.runFolder -MaxRows $settings.Ui.PreviewRows
        $flat = ConvertTo-FlatRows -Rows $results.Rows
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
        Set-Status ("Completed '{0}'. Total records: {1}. Preview rows: {2}. Run folder: {3}" -f $script:SelectedDataset.Key, $total, $flat.Count, $runCtx.runFolder) '#34D399'
    }
    catch {
        $msg = $_.Exception.Message
        $body = $null
        if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            $body = $_.ErrorDetails.Message
        }
        $statusMsg = if ($body) { "Run failed: $msg | $body" } else { "Run failed: $msg" }
        Set-Status $statusMsg '#F87171'
        $details = "=== Exception ===`n$($_.Exception.ToString())"
        if ($body) { $details += "`n`n=== Response body ===`n$body" }
        $controls.TxtSummary.Text = $details
    }
    finally {
        $controls.BtnRun.IsEnabled = $true
        $controls.BtnRun.Content = 'Run dataset'
    }
})

$controls.BtnOpenRun.Add_Click({
    if ($script:LastRunFolder -and [System.IO.Directory]::Exists($script:LastRunFolder)) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $script:LastRunFolder
    }
})

[void]$window.ShowDialog()
