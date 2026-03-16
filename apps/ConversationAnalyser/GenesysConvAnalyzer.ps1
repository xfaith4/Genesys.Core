#Requires -Version 5.1
<#
.SYNOPSIS
    GenesysConvAnalyzer.ps1 - Conversation Detail Analysis Tool for Genesys Cloud

.DESCRIPTION
    Purpose-built WPF application for deep conversation analytics using the async
    job pattern (/api/v2/analytics/conversations/details/jobs). Designed for orgs
    with high conversation volume where engineers need to:

    - Set up targeted async queries across any filter dimension
    - Collect and page through large result sets with live progress
    - Inspect conversations with full participant/segment/attribute detail
    - Export flattened rows (CSV) or full conversation objects (JSONL) for downstream tools

    The workflow is:
        Query Builder → Submit Job → Poll Status → Collect Results → Analyze / Export

.NOTES
    Requirements : Windows, PowerShell 5.1+, Genesys Cloud OAuth client credentials
    Depends on   : Genesys.Core module (src/ps-module/Genesys.Core)
    Reuses       : Auth + config patterns from GenesysCore-GUI.ps1

.EXAMPLE
    .\GenesysConvAnalyzer.ps1

.EXAMPLE
    .\GenesysConvAnalyzer.ps1 -DefaultRegion 'usw2.pure.cloud'
#>

[CmdletBinding()]
param(
    [string]$DefaultRegion = 'usw2.pure.cloud',
    [string]$ModulePath    = "$PSScriptRoot/src/ps-module/Genesys.Core/Genesys.Core.psd1",
    [string]$ConfigPath
)

if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    throw "This tool requires Windows (WPF is Windows-only)."
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ─────────────────────────────────────────────────────────────────────────────
# Config / Auth  (shared pattern with GenesysCore-GUI.ps1)
# ─────────────────────────────────────────────────────────────────────────────

function Resolve-UIConfigPath {
    param([string]$ExplicitPath)
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) { $candidates.Add($ExplicitPath) | Out-Null }
    $candidates.Add('GenesysCore-GUI.config.json') | Out-Null
    $candidates.Add('genesys.env.json') | Out-Null
    foreach ($c in @($candidates)) {
        $r = if ([System.IO.Path]::IsPathRooted($c)) { $c } else { Join-Path $PSScriptRoot $c }
        if (Test-Path $r -PathType Leaf) { return (Resolve-Path $r).Path }
    }
    return (Join-Path $PSScriptRoot 'GenesysCore-GUI.config.json')
}

$script:configPath = Resolve-UIConfigPath -ExplicitPath $ConfigPath

function Read-GenesysEnvConfig {
    if (-not (Test-Path $script:configPath)) { return $null }
    try { return Get-Content $script:configPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { return $null }
}

function Save-GenesysEnvConfig {
    param([string]$Region, [string]$ClientId)
    $cfg = [ordered]@{ region = $Region.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($ClientId)) { $cfg['clientId'] = $ClientId.Trim() }
    try { ($cfg | ConvertTo-Json -Depth 5) | Set-Content $script:configPath -Encoding utf8 } catch {}
}

function Get-ConfigString {
    param([object]$ConfigObject, [string[]]$PropertyNames)
    if ($null -eq $ConfigObject) { return $null }
    foreach ($n in $PropertyNames) {
        if ($ConfigObject.PSObject.Properties.Name -contains $n) {
            $v = [string]$ConfigObject.$n
            if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
        }
    }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
# Script state
# ─────────────────────────────────────────────────────────────────────────────

$script:accessToken       = $null
$script:headers           = @{}
$script:baseUri           = "https://api.$DefaultRegion"
$script:currentJobId      = $null
$script:pollTimer         = $null
$script:pollCount         = 0
$script:jobSubmitTime     = $null
$script:allConversations  = [System.Collections.Generic.List[object]]::new()
$script:selectedAttrCols  = [System.Collections.Generic.List[string]]::new()
$script:convFilterRows    = [System.Collections.Generic.List[pscustomobject]]::new()
$script:segFilterRows     = [System.Collections.Generic.List[pscustomobject]]::new()

# ─────────────────────────────────────────────────────────────────────────────
# API helpers
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-GcApiRequest {
    param(
        [string]$Method,
        [string]$Path,
        [string]$Body,
        [hashtable]$QueryParams
    )
    $uri = "$($script:baseUri)$Path"
    if ($QueryParams -and $QueryParams.Count -gt 0) {
        $qs = ($QueryParams.GetEnumerator() |
               ForEach-Object { "$($_.Key)=$([Uri]::EscapeDataString([string]$_.Value))" }) -join '&'
        $uri = "$uri?$qs"
    }
    $p = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $script:headers
        ErrorAction = 'Stop'
        TimeoutSec  = 120
    }
    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $p.Body        = $Body
        $p.ContentType = 'application/json'
    }
    return Invoke-RestMethod @p
}

function Submit-AnalyticsJob   { param([string]$JsonBody) Invoke-GcApiRequest -Method 'POST' -Path '/api/v2/analytics/conversations/details/jobs' -Body $JsonBody }
function Get-AnalyticsJobStatus{ param([string]$JobId)    Invoke-GcApiRequest -Method 'GET'  -Path "/api/v2/analytics/conversations/details/jobs/$JobId" }
function Remove-AnalyticsJob   { param([string]$JobId)    try { Invoke-GcApiRequest -Method 'DELETE' -Path "/api/v2/analytics/conversations/details/jobs/$JobId" } catch {} }

function Get-AnalyticsJobResults {
    param([string]$JobId, [int]$PageSize = 1000, [string]$Cursor)
    $q = @{ pageSize = [string]$PageSize }
    if (-not [string]::IsNullOrWhiteSpace($Cursor)) { $q['cursor'] = $Cursor }
    Invoke-GcApiRequest -Method 'GET' -Path "/api/v2/analytics/conversations/details/jobs/$JobId/results" -QueryParams $q
}

# ─────────────────────────────────────────────────────────────────────────────
# Data transformation
# ─────────────────────────────────────────────────────────────────────────────

function Get-ParticipantByPurpose {
    param([object]$Conv, [string]$Purpose)
    return @($Conv.participants | Where-Object { $_.purpose -eq $Purpose }) | Select-Object -First 1
}

function Get-MetricValue {
    param([object[]]$Sessions, [string]$Name)
    foreach ($s in @($Sessions)) {
        $m = @($s.metrics | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
        if ($null -ne $m) { return $m.value }
    }
    return $null
}

function Get-QueueIdFromSessions {
    param([object[]]$Sessions)
    foreach ($s in @($Sessions)) {
        $seg = @($s.segments | Where-Object { $_.segmentType -eq 'interact' -and $null -ne $_.queueId }) | Select-Object -First 1
        if ($null -ne $seg) { return [string]$seg.queueId }
    }
    return ''
}

function Get-AttrValue {
    param([object]$Attrs, [string]$Key)
    if ($null -eq $Attrs) { return '' }
    if ($Attrs -is [System.Collections.IDictionary]) {
        return if ($Attrs.Contains($Key)) { [string]$Attrs[$Key] } else { '' }
    }
    return if ($Attrs.PSObject.Properties.Name -contains $Key) { [string]$Attrs.$Key } else { '' }
}

function Get-AllAttributeKeys {
    $keys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($conv in @($script:allConversations)) {
        $cust = Get-ParticipantByPurpose -Conv $conv -Purpose 'customer'
        if ($null -eq $cust -or $null -eq $cust.attributes) { continue }
        $attrs = $cust.attributes
        if ($attrs -is [System.Collections.IDictionary]) {
            foreach ($k in $attrs.Keys) { $keys.Add([string]$k) | Out-Null }
        } else {
            foreach ($p in $attrs.PSObject.Properties) { $keys.Add($p.Name) | Out-Null }
        }
    }
    return @($keys | Sort-Object)
}

function ConvertTo-FlatRow {
    param([object]$Conv, [string[]]$AttrCols)

    $agent  = Get-ParticipantByPurpose -Conv $Conv -Purpose 'agent'
    $cust   = Get-ParticipantByPurpose -Conv $Conv -Purpose 'customer'

    $sessions = if ($null -ne $agent -and $null -ne $agent.sessions) { @($agent.sessions) } else { @() }
    $mediaType = if ($sessions.Count -gt 0) { [string]$sessions[0].mediaType } else { '' }
    $queueId   = Get-QueueIdFromSessions -Sessions $sessions

    $startDt = $null; $endDt = $null; $durSec = ''
    try {
        if (-not [string]::IsNullOrWhiteSpace($Conv.conversationStart)) {
            $startDt = [DateTime]::Parse($Conv.conversationStart).ToLocalTime()
        }
        if (-not [string]::IsNullOrWhiteSpace($Conv.conversationEnd)) {
            $endDt = [DateTime]::Parse($Conv.conversationEnd).ToLocalTime()
        }
        if ($null -ne $startDt -and $null -ne $endDt) {
            $durSec = [int]($endDt - $startDt).TotalSeconds
        }
    } catch {}

    # Metrics are stored in milliseconds; convert to seconds
    $msToSec = { param($v) if ($null -ne $v) { [int]($v / 1000) } else { '' } }
    $tHandle = & $msToSec (Get-MetricValue -Sessions $sessions -Name 'tHandle')
    $tTalk   = & $msToSec (Get-MetricValue -Sessions $sessions -Name 'tTalk')
    $tAcw    = & $msToSec (Get-MetricValue -Sessions $sessions -Name 'tAcw')
    $tHeld   = & $msToSec (Get-MetricValue -Sessions $sessions -Name 'tHeld')
    $nConn   = Get-MetricValue -Sessions $sessions -Name 'nConnected'

    $row = [ordered]@{
        ConversationId = [string]$Conv.conversationId
        Start          = if ($null -ne $startDt) { $startDt.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
        End            = if ($null -ne $endDt)   { $endDt.ToString('yyyy-MM-dd HH:mm:ss')   } else { '' }
        DurationSec    = [string]$durSec
        Direction      = [string]$Conv.originatingDirection
        MediaType      = $mediaType
        QueueId        = $queueId
        AgentName      = if ($null -ne $agent) { [string]$agent.participantName } else { '' }
        AgentUserId    = if ($null -ne $agent) { [string]$agent.userId }          else { '' }
        tHandleSec     = [string]$tHandle
        tTalkSec       = [string]$tTalk
        tAcwSec        = [string]$tAcw
        tHeldSec       = [string]$tHeld
        nConnected     = if ($null -ne $nConn) { [string]$nConn } else { '' }
    }

    $attrs = if ($null -ne $cust) { $cust.attributes } else { $null }
    foreach ($col in @($AttrCols)) {
        $row["A:$col"] = Get-AttrValue -Attrs $attrs -Key $col
    }

    return [pscustomobject]$row
}

# ─────────────────────────────────────────────────────────────────────────────
# XAML
# ─────────────────────────────────────────────────────────────────────────────

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Genesys Conversation Analyzer" Height="820" Width="1100"
        WindowStartupLocation="CenterScreen" FontSize="12">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding"  Value="8,3"/>
      <Setter Property="Margin"   Value="2"/>
    </Style>
    <Style TargetType="GroupBox">
      <Setter Property="Padding" Value="6"/>
      <Setter Property="Margin"  Value="0,0,0,8"/>
    </Style>
    <Style TargetType="Label">
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Padding" Value="2"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Margin" Value="2"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Margin" Value="2"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>

  <Grid Margin="8">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- ── Auth ─────────────────────────────────────────────────── -->
    <GroupBox Grid.Row="0" Header="Authentication">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="70"/>
          <ColumnDefinition Width="180"/>
          <ColumnDefinition Width="70"/>
          <ColumnDefinition Width="200"/>
          <ColumnDefinition Width="70"/>
          <ColumnDefinition Width="180"/>
          <ColumnDefinition Width="110"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Label   Grid.Column="0" Content="Region:"/>
        <ComboBox Grid.Column="1" Name="RegionComboBox" IsEditable="True">
          <ComboBoxItem Content="mypurecloud.com" IsSelected="False"/>
            <ComboBoxItem Content="usw2.pure.cloud" IsSelected="True"/>
        </ComboBox>
        <Label   Grid.Column="2" Content="Client ID:"/>
        <TextBox Grid.Column="3" Name="ClientIdBox"/>
        <Label   Grid.Column="4" Content="Secret:"/>
        <PasswordBox Grid.Column="5" Name="ClientSecretBox" VerticalAlignment="Center" Margin="2"/>
        <Button  Grid.Column="6" Name="AuthButton" Content="Authenticate" Margin="6,2,2,2"/>
        <TextBlock Grid.Column="7" Name="AuthStatusLabel" VerticalAlignment="Center" Margin="6,0,0,0" FontWeight="Bold"/>
      </Grid>
    </GroupBox>

    <!-- ── Main Tabs ─────────────────────────────────────────────── -->
    <TabControl Grid.Row="1" Name="MainTabControl">

      <!-- ══ Tab 1: Query Builder ══ -->
      <TabItem Header=" 🔍 Query Builder ">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="6">

            <!-- Date range -->
            <GroupBox Header="Interval">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <!-- Quick presets row -->
                <Label   Grid.Row="0" Grid.Column="0" Content="Preset:"/>
                <Button  Grid.Row="0" Grid.Column="1" Name="PresetToday"     Content="Today"/>
                <Button  Grid.Row="0" Grid.Column="2" Name="PresetYesterday" Content="Yesterday"/>
                <Button  Grid.Row="0" Grid.Column="3" Name="PresetLast7"     Content="Last 7 Days"/>
                <Button  Grid.Row="0" Grid.Column="4" Name="PresetLast30"    Content="Last 30 Days"/>
                <Button  Grid.Row="0" Grid.Column="5" Name="PresetThisMonth" Content="This Month"/>
                <Button  Grid.Row="0" Grid.Column="6" Name="PresetLastMonth" Content="Last Month"/>
                <!-- Date picker row -->
                <Label       Grid.Row="1" Grid.Column="0" Content="From:"/>
                <DatePicker  Grid.Row="1" Grid.Column="1" Name="StartDatePicker" Width="130" Margin="2"/>
                <Label       Grid.Row="1" Grid.Column="2" Content="To:"/>
                <DatePicker  Grid.Row="1" Grid.Column="3" Name="EndDatePicker"   Width="130" Margin="2"/>
              </Grid>
            </GroupBox>

            <!-- Quick filter row -->
            <GroupBox Header="Quick Filters">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="80"/>
                  <ColumnDefinition Width="140"/>
                  <ColumnDefinition Width="80"/>
                  <ColumnDefinition Width="140"/>
                  <ColumnDefinition Width="80"/>
                  <ColumnDefinition Width="140"/>
                  <ColumnDefinition Width="80"/>
                  <ColumnDefinition Width="140"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Label    Grid.Column="0" Content="Direction:"/>
                <ComboBox Grid.Column="1" Name="DirectionCombo" SelectedIndex="0">
                  <ComboBoxItem Content="(any)"/>
                  <ComboBoxItem Content="inbound"/>
                  <ComboBoxItem Content="outbound"/>
                </ComboBox>
                <Label    Grid.Column="2" Content="Media Type:"/>
                <ComboBox Grid.Column="3" Name="MediaTypeCombo" SelectedIndex="0">
                  <ComboBoxItem Content="(any)"/>
                  <ComboBoxItem Content="voice"/>
                  <ComboBoxItem Content="chat"/>
                  <ComboBoxItem Content="email"/>
                  <ComboBoxItem Content="callback"/>
                  <ComboBoxItem Content="message"/>
                  <ComboBoxItem Content="cobrowse"/>
                  <ComboBoxItem Content="video"/>
                </ComboBox>
                <Label    Grid.Column="4" Content="Order By:"/>
                <ComboBox Grid.Column="5" Name="OrderByCombo" SelectedIndex="0">
                  <ComboBoxItem Content="conversationStart"/>
                  <ComboBoxItem Content="conversationEnd"/>
                </ComboBox>
                <Label    Grid.Column="6" Content="Order:"/>
                <ComboBox Grid.Column="7" Name="OrderCombo" SelectedIndex="0">
                  <ComboBoxItem Content="asc"/>
                  <ComboBoxItem Content="desc"/>
                </ComboBox>
              </Grid>
            </GroupBox>

            <!-- Conversation filters -->
            <GroupBox Header="Conversation Filters  (one predicate per row → each becomes its own filter group)">
              <StackPanel>
                <StackPanel Name="ConvFilterPanel"/>
                <Button Name="AddConvFilterBtn" Content="+ Add Conversation Filter"
                        HorizontalAlignment="Left" Width="200" Margin="0,4,0,0"/>
              </StackPanel>
            </GroupBox>

            <!-- Segment filters -->
            <GroupBox Header="Segment Filters">
              <StackPanel>
                <StackPanel Name="SegFilterPanel"/>
                <Button Name="AddSegFilterBtn" Content="+ Add Segment Filter"
                        HorizontalAlignment="Left" Width="200" Margin="0,4,0,0"/>
              </StackPanel>
            </GroupBox>

            <!-- JSON preview -->
            <GroupBox Header="Query JSON Preview">
              <StackPanel>
                <TextBox Name="QueryPreviewBox" IsReadOnly="True" MaxHeight="180"
                         TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                         FontFamily="Consolas" FontSize="11" Background="#F8F8F8"/>
                <WrapPanel Margin="0,4,0,0">
                  <Button Name="PreviewBtn"  Content="Preview JSON"/>
                  <Button Name="ClearFiltersBtn" Content="Clear All Filters"/>
                </WrapPanel>
              </StackPanel>
            </GroupBox>

            <!-- Submit -->
            <Button Name="SubmitJobBtn" Content="▶  Submit Async Job"
                    FontSize="13" FontWeight="Bold" Height="38"
                    Background="#005A9C" Foreground="White"
                    HorizontalContentAlignment="Center"/>

          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ══ Tab 2: Job Monitor ══ -->
      <TabItem Header=" ⏱ Job Monitor " Name="JobMonitorTab">
        <Grid Margin="6">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <!-- Job status panel -->
          <GroupBox Grid.Row="0" Header="Current Job">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="70"/>
                <ColumnDefinition Width="280"/>
                <ColumnDefinition Width="70"/>
                <ColumnDefinition Width="100"/>
                <ColumnDefinition Width="60"/>
                <ColumnDefinition Width="50"/>
                <ColumnDefinition Width="70"/>
                <ColumnDefinition Width="80"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Label   Grid.Column="0" Content="Job ID:"/>
              <TextBox Grid.Column="1" Name="JobIdBox" IsReadOnly="True" Background="#F0F0F0" FontFamily="Consolas"/>
              <Label   Grid.Column="2" Content="State:"/>
              <TextBlock Grid.Column="3" Name="JobStateLabel" VerticalAlignment="Center" FontWeight="Bold" Margin="4,0,0,0"/>
              <Label   Grid.Column="4" Content="Polls:"/>
              <TextBlock Grid.Column="5" Name="JobPollLabel" VerticalAlignment="Center" Margin="4,0,0,0"/>
              <Label   Grid.Column="6" Content="Elapsed:"/>
              <TextBlock Grid.Column="7" Name="JobElapsedLabel" VerticalAlignment="Center" Margin="4,0,0,0"/>
              <Button  Grid.Column="8" Name="CancelJobBtn" Content="Cancel / Delete Job"
                       HorizontalAlignment="Left" Margin="10,2,2,2" Background="#C0392B" Foreground="White" IsEnabled="False"/>
            </Grid>
          </GroupBox>

          <!-- Activity log -->
          <GroupBox Grid.Row="1" Header="Activity Log">
            <TextBox Name="JobLogBox" IsReadOnly="True" TextWrapping="NoWrap"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                     FontFamily="Consolas" FontSize="11" Background="#1E1E1E" Foreground="#D4D4D4"/>
          </GroupBox>

          <!-- Collect bar -->
          <Border Grid.Row="2" Background="#E8F4E8" BorderBrush="#4CAF50" BorderThickness="1" Padding="8,6" Margin="0,4,0,0">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock Grid.Column="0" Name="CollectStatusText"
                         Text="Submit a job above. When it reaches FULFILLED, click Collect to page through results."
                         VerticalAlignment="Center" TextWrapping="Wrap"/>
              <Button Grid.Column="1" Name="CollectResultsBtn"
                      Content="Collect All Results  →" FontWeight="Bold"
                      Background="#27AE60" Foreground="White"
                      IsEnabled="False" Width="180" Height="34"/>
            </Grid>
          </Border>
        </Grid>
      </TabItem>

      <!-- ══ Tab 3: Results ══ -->
      <TabItem Header=" 📊 Results " Name="ResultsTab">
        <Grid Margin="6">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="220"/>
          </Grid.RowDefinitions>

          <!-- Summary -->
          <Border Grid.Row="0" Background="#EBF5FB" BorderBrush="#2980B9" BorderThickness="1" Padding="6,4" Margin="0,0,0,6">
            <TextBlock Name="SummaryText" FontWeight="Bold" TextWrapping="Wrap"
                       Text="No results loaded. Submit and collect a job first."/>
          </Border>

          <!-- Toolbar -->
          <WrapPanel Grid.Row="1" Margin="0,0,0,4">
            <Button Name="ColumnSelectorBtn" Content="Column Selector…"/>
            <Button Name="ExportCsvBtn"      Content="Export CSV"/>
            <Button Name="ExportJsonlBtn"    Content="Export JSONL (full)"/>
            <Button Name="LoadJsonlBtn"      Content="Load from JSONL…"/>
            <Button Name="ClearResultsBtn"   Content="Clear Results"/>
          </WrapPanel>

          <!-- Results DataGrid -->
          <DataGrid Grid.Row="2" Name="ResultsGrid"
                    IsReadOnly="True" AutoGenerateColumns="False"
                    SelectionMode="Single" CanUserSortColumns="True"
                    GridLinesVisibility="Horizontal" AlternatingRowBackground="#F9F9F9"
                    EnableRowVirtualization="True" VirtualizingStackPanel.IsVirtualizing="True"
                    VirtualizingStackPanel.VirtualizationMode="Recycling"/>

          <!-- Detail panel -->
          <GroupBox Grid.Row="3" Header="Conversation Detail  (select a row above)">
            <TabControl Name="DetailTabControl">
              <TabItem Header="Overview">
                <ScrollViewer HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto">
                  <WrapPanel Name="OverviewPanel" Margin="4" Orientation="Horizontal"/>
                </ScrollViewer>
              </TabItem>
              <TabItem Header="Call Attributes">
                <DataGrid Name="AttributesGrid" IsReadOnly="True" AutoGenerateColumns="False"
                          GridLinesVisibility="Horizontal" AlternatingRowBackground="#FAFAFA">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="Attribute Key" Binding="{Binding Key}"   Width="220" FontFamily="Consolas"/>
                    <DataGridTextColumn Header="Value"         Binding="{Binding Value}" Width="*"/>
                  </DataGrid.Columns>
                </DataGrid>
              </TabItem>
              <TabItem Header="Participants">
                <DataGrid Name="ParticipantsGrid" IsReadOnly="True" AutoGenerateColumns="False"
                          GridLinesVisibility="Horizontal">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="Purpose"   Binding="{Binding Purpose}"  Width="90"/>
                    <DataGridTextColumn Header="Name"      Binding="{Binding Name}"     Width="160"/>
                    <DataGridTextColumn Header="User ID"   Binding="{Binding UserId}"   Width="280" FontFamily="Consolas" FontSize="11"/>
                    <DataGridTextColumn Header="Sessions"  Binding="{Binding Sessions}" Width="70"/>
                    <DataGridTextColumn Header="Ext Contact" Binding="{Binding ExtContactId}" Width="*" FontFamily="Consolas" FontSize="11"/>
                  </DataGrid.Columns>
                </DataGrid>
              </TabItem>
              <TabItem Header="Segment Timeline">
                <DataGrid Name="SegmentsGrid" IsReadOnly="True" AutoGenerateColumns="False"
                          GridLinesVisibility="Horizontal" AlternatingRowBackground="#FAFAFA">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="Purpose"    Binding="{Binding Purpose}"    Width="80"/>
                    <DataGridTextColumn Header="Type"       Binding="{Binding Type}"       Width="90"/>
                    <DataGridTextColumn Header="Start"      Binding="{Binding Start}"      Width="160"/>
                    <DataGridTextColumn Header="End"        Binding="{Binding End}"        Width="160"/>
                    <DataGridTextColumn Header="Dur (s)"    Binding="{Binding DurSec}"     Width="60"/>
                    <DataGridTextColumn Header="Queue ID"   Binding="{Binding QueueId}"    Width="280" FontFamily="Consolas" FontSize="11"/>
                    <DataGridTextColumn Header="Disconnect" Binding="{Binding Disconnect}" Width="*"/>
                  </DataGrid.Columns>
                </DataGrid>
              </TabItem>
              <TabItem Header="Raw JSON">
                <TextBox Name="RawJsonBox" IsReadOnly="True" TextWrapping="NoWrap"
                         HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"
                         FontFamily="Consolas" FontSize="10" Background="#1E1E1E" Foreground="#D4D4D4"/>
              </TabItem>
            </TabControl>
          </GroupBox>

        </Grid>
      </TabItem>
    </TabControl>

    <!-- ── Status bar ──────────────────────────────────────────── -->
    <Border Grid.Row="2" Background="#F0F0F0" BorderBrush="#CCCCCC" BorderThickness="0,1,0,0" Padding="4,2">
      <TextBlock Name="StatusText" Text="Ready — authenticate and build a query to begin."/>
    </Border>

  </Grid>
</Window>
'@

# ─────────────────────────────────────────────────────────────────────────────
# Build WPF window from XAML
# ─────────────────────────────────────────────────────────────────────────────

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Named controls
function Get-Control { param([string]$Name) $window.FindName($Name) }

$regionComboBox    = Get-Control 'RegionComboBox'
$clientIdBox       = Get-Control 'ClientIdBox'
$clientSecretBox   = Get-Control 'ClientSecretBox'
$authButton        = Get-Control 'AuthButton'
$authStatusLabel   = Get-Control 'AuthStatusLabel'

$startDatePicker   = Get-Control 'StartDatePicker'
$endDatePicker     = Get-Control 'EndDatePicker'
$directionCombo    = Get-Control 'DirectionCombo'
$mediaTypeCombo    = Get-Control 'MediaTypeCombo'
$orderByCombo      = Get-Control 'OrderByCombo'
$orderCombo        = Get-Control 'OrderCombo'

$convFilterPanel   = Get-Control 'ConvFilterPanel'
$segFilterPanel    = Get-Control 'SegFilterPanel'
$addConvFilterBtn  = Get-Control 'AddConvFilterBtn'
$addSegFilterBtn   = Get-Control 'AddSegFilterBtn'
$queryPreviewBox   = Get-Control 'QueryPreviewBox'
$previewBtn        = Get-Control 'PreviewBtn'
$clearFiltersBtn   = Get-Control 'ClearFiltersBtn'
$submitJobBtn      = Get-Control 'SubmitJobBtn'

$mainTabControl    = Get-Control 'MainTabControl'
$jobIdBox          = Get-Control 'JobIdBox'
$jobStateLabel     = Get-Control 'JobStateLabel'
$jobPollLabel      = Get-Control 'JobPollLabel'
$jobElapsedLabel   = Get-Control 'JobElapsedLabel'
$cancelJobBtn      = Get-Control 'CancelJobBtn'
$jobLogBox         = Get-Control 'JobLogBox'
$collectStatusText = Get-Control 'CollectStatusText'
$collectResultsBtn = Get-Control 'CollectResultsBtn'

$summaryText       = Get-Control 'SummaryText'
$columnSelectorBtn = Get-Control 'ColumnSelectorBtn'
$exportCsvBtn      = Get-Control 'ExportCsvBtn'
$exportJsonlBtn    = Get-Control 'ExportJsonlBtn'
$loadJsonlBtn      = Get-Control 'LoadJsonlBtn'
$clearResultsBtn   = Get-Control 'ClearResultsBtn'
$resultsGrid       = Get-Control 'ResultsGrid'
$overviewPanel     = Get-Control 'OverviewPanel'
$attributesGrid    = Get-Control 'AttributesGrid'
$participantsGrid  = Get-Control 'ParticipantsGrid'
$segmentsGrid      = Get-Control 'SegmentsGrid'
$rawJsonBox        = Get-Control 'RawJsonBox'
$statusText        = Get-Control 'StatusText'

$detailTabControl  = Get-Control 'DetailTabControl'

$startDatePicker.ToolTip = 'Optional. Leave both dates empty to query the last 24 hours.'
$endDatePicker.ToolTip   = 'Optional. Leave both dates empty to query the last 24 hours.'

# ─────────────────────────────────────────────────────────────────────────────
# Helpers used from event handlers
# ─────────────────────────────────────────────────────────────────────────────

function Set-Status { param([string]$Msg) $statusText.Text = $Msg }

function Get-ComboValue {
    param([AllowNull()][object]$Control)

    if ($null -eq $Control) {
        return ''
    }

    if ($Control -is [string]) {
        return [string]$Control
    }

    if ($Control.PSObject.Properties.Name -contains 'Text' -and -not [string]::IsNullOrWhiteSpace([string]$Control.Text)) {
        return [string]$Control.Text
    }

    if ($Control.PSObject.Properties.Name -contains 'SelectedItem' -and $null -ne $Control.SelectedItem) {
        $selected = $Control.SelectedItem
        if ($selected -is [string]) {
            return [string]$selected
        }
        if ($selected.PSObject.Properties.Name -contains 'Content' -and $null -ne $selected.Content) {
            return [string]$selected.Content
        }
        return [string]$selected
    }

    if ($Control.PSObject.Properties.Name -contains 'Content' -and $null -ne $Control.Content) {
        return [string]$Control.Content
    }

    return [string]$Control
}

function Append-JobLog {
    param([string]$Line)
    $ts = [DateTime]::Now.ToString('HH:mm:ss')
    $jobLogBox.AppendText("[$ts] $Line`n")
    $jobLogBox.ScrollToEnd()
}

function New-FilterRow {
    param([string]$Type, [System.Windows.Controls.StackPanel]$Panel)

    $dims = if ($Type -eq 'conversation') {
        @('mediaType','originatingDirection','queueId','userId','conversationId','divisionId','flowId','isEnded','flaggedReason')
    } else {
        @('purpose','segmentType','queueId','userId','flowId','disconnectType','edgeId')
    }

    $border = New-Object System.Windows.Controls.Border
    $border.BorderBrush     = [System.Windows.Media.Brushes]::LightGray
    $border.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
    $border.Margin          = [System.Windows.Thickness]::new(0,1,0,1)

    $grid = New-Object System.Windows.Controls.Grid
    @(70, 150, 110, 1, 28) | ForEach-Object {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($_ -eq 1) {
            $cd.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        } else {
            $cd.Width = [System.Windows.GridLength]::new($_)
        }
        $grid.ColumnDefinitions.Add($cd) | Out-Null
    }
    $border.Child = $grid

    $logicCb = New-Object System.Windows.Controls.ComboBox
    $logicCb.Margin = [System.Windows.Thickness]::new(1)
    @('and','or') | ForEach-Object { $logicCb.Items.Add($_) | Out-Null }
    $logicCb.SelectedIndex = 0
    [System.Windows.Controls.Grid]::SetColumn($logicCb, 0); $grid.Children.Add($logicCb) | Out-Null

    $dimCb = New-Object System.Windows.Controls.ComboBox
    $dimCb.Margin = [System.Windows.Thickness]::new(1); $dimCb.IsEditable = $true
    $dims | ForEach-Object { $dimCb.Items.Add($_) | Out-Null }
    $dimCb.SelectedIndex = 0
    [System.Windows.Controls.Grid]::SetColumn($dimCb, 1); $grid.Children.Add($dimCb) | Out-Null

    $opCb = New-Object System.Windows.Controls.ComboBox
    $opCb.Margin = [System.Windows.Thickness]::new(1)
    @('matches','notMatches','lt','lte','gt','gte') | ForEach-Object { $opCb.Items.Add($_) | Out-Null }
    $opCb.SelectedIndex = 0
    [System.Windows.Controls.Grid]::SetColumn($opCb, 2); $grid.Children.Add($opCb) | Out-Null

    $valTb = New-Object System.Windows.Controls.TextBox
    $valTb.Margin = [System.Windows.Thickness]::new(1)
    [System.Windows.Controls.Grid]::SetColumn($valTb, 3); $grid.Children.Add($valTb) | Out-Null

    $remBtn = New-Object System.Windows.Controls.Button
    $remBtn.Content = '✕'; $remBtn.Margin = [System.Windows.Thickness]::new(1); $remBtn.Padding = [System.Windows.Thickness]::new(2,0,2,0)
    $remBtn.ToolTip = 'Remove filter'
    $capturedBorder = $border; $capturedPanel = $Panel
    $remBtn.Add_Click({
        $capturedPanel.Children.Remove($capturedBorder)
        Update-QueryPreview
    }.GetNewClosure())
    [System.Windows.Controls.Grid]::SetColumn($remBtn, 4); $grid.Children.Add($remBtn) | Out-Null

    $logicCb.Add_SelectionChanged({ Update-QueryPreview })
    $dimCb.Add_SelectionChanged({ Update-QueryPreview })
    $dimCb.Add_LostFocus({ Update-QueryPreview })
    $opCb.Add_SelectionChanged({ Update-QueryPreview })
    $valTb.Add_TextChanged({ Update-QueryPreview })

    $Panel.Children.Add($border) | Out-Null

    return [pscustomobject]@{ Border = $border; Logic = $logicCb; Dimension = $dimCb; Operator = $opCb; Value = $valTb }
}

function Collect-FilterRows {
    param([System.Windows.Controls.StackPanel]$Panel)
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($child in @($Panel.Children)) {
        if ($child -isnot [System.Windows.Controls.Border]) { continue }
        $g = $child.Child
        if ($null -eq $g) { continue }
        $items = @($g.Children)
        $rows.Add([pscustomobject]@{
            logic     = if ($items[0].SelectedItem) { Get-ComboValue -Control $items[0] } else { 'and' }
            dimension = if ($items[1].Text) { [string]$items[1].Text } else { '' }
            operator  = if ($items[2].SelectedItem) { Get-ComboValue -Control $items[2] } else { 'matches' }
            value     = [string]$items[3].Text
        }) | Out-Null
    }
    return @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.dimension) -and -not [string]::IsNullOrWhiteSpace($_.value) })
}

function Resolve-DatePickerDate {
    param(
        [System.Windows.Controls.DatePicker]$Picker,
        [string]$Label
    )

    if ($null -eq $Picker) {
        throw "$Label date picker was not found."
    }

    $selectedDate = $Picker.SelectedDate
    if ($null -ne $selectedDate) {
        return ([DateTime]$selectedDate).Date
    }

    $pickerText = [string]$Picker.Text
    if ([string]::IsNullOrWhiteSpace($pickerText)) {
        return $null
    }

    $parsedDate = [DateTime]::MinValue
    if (-not [DateTime]::TryParse($pickerText, [ref]$parsedDate)) {
        throw "$Label date '$pickerText' is not a valid date."
    }

    return $parsedDate.Date
}

function Resolve-QueryInterval {
    $startDate = Resolve-DatePickerDate -Picker $startDatePicker -Label 'Start'
    $endDate   = Resolve-DatePickerDate -Picker $endDatePicker -Label 'End'

    if ($null -eq $startDate -and $null -eq $endDate) {
        return [pscustomobject]@{
            StartUtc = [DateTime]::UtcNow.AddHours(-24)
            EndUtc   = [DateTime]::UtcNow
        }
    }

    if ($null -eq $startDate -or $null -eq $endDate) {
        throw 'Select both start and end dates, or leave both empty to use the last 24 hours.'
    }

    $startLocal = [DateTime]::SpecifyKind($startDate.Date, [System.DateTimeKind]::Local)
    $endLocal   = [DateTime]::SpecifyKind($endDate.Date.AddDays(1).AddTicks(-1), [System.DateTimeKind]::Local)
    $startUtc   = $startLocal.ToUniversalTime()
    $endUtc     = $endLocal.ToUniversalTime()

    if ($endUtc -le $startUtc) {
        throw 'End date must be after start date.'
    }

    return [pscustomobject]@{
        StartUtc = $startUtc
        EndUtc   = $endUtc
    }
}

function Build-QueryBody {
    $resolvedInterval = Resolve-QueryInterval
    $startUtc = [DateTime]$resolvedInterval.StartUtc
    $endUtc   = [DateTime]$resolvedInterval.EndUtc

    $interval = "$($startUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))/$($endUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))"
    $body = [ordered]@{
        interval = $interval
        order    = Get-ComboValue -Control $orderCombo
        orderBy  = Get-ComboValue -Control $orderByCombo
    }

    # Quick filter: direction
    $dir = Get-ComboValue -Control $directionCombo
    if (-not [string]::IsNullOrWhiteSpace($dir) -and $dir -ne '(any)') {
        $body['conversationFilters'] = @(@{
            type       = 'and'
            predicates = @(@{ dimension = 'originatingDirection'; value = $dir })
        })
    }

    # Quick filter: media type → segment filter (purpose=agent + mediaType from session)
    $mt = Get-ComboValue -Control $mediaTypeCombo
    if (-not [string]::IsNullOrWhiteSpace($mt) -and $mt -ne '(any)') {
        $existing = if ($body.Contains('segmentFilters')) { [System.Collections.Generic.List[object]]$body['segmentFilters'] } else { [System.Collections.Generic.List[object]]::new() }
        $existing.Add(@{
            type       = 'and'
            predicates = @(@{ dimension = 'mediaType'; value = $mt })
        }) | Out-Null
        $body['segmentFilters'] = @($existing)
    }

    # Custom conversation filters
    $convRows = Collect-FilterRows -Panel $convFilterPanel
    if ($convRows.Count -gt 0) {
        $existingConv = if ($body.Contains('conversationFilters')) { [System.Collections.Generic.List[object]]($body['conversationFilters']) } else { [System.Collections.Generic.List[object]]::new() }
        foreach ($r in $convRows) {
            $pred = [ordered]@{ dimension = $r.dimension; value = $r.value }
            if ($r.operator -ne 'matches') { $pred['operator'] = $r.operator }
            $existingConv.Add([ordered]@{ type = $r.logic; predicates = @($pred) }) | Out-Null
        }
        $body['conversationFilters'] = @($existingConv)
    }

    # Custom segment filters
    $segRows = Collect-FilterRows -Panel $segFilterPanel
    if ($segRows.Count -gt 0) {
        $existingSeg = if ($body.Contains('segmentFilters')) { [System.Collections.Generic.List[object]]($body['segmentFilters']) } else { [System.Collections.Generic.List[object]]::new() }
        foreach ($r in $segRows) {
            $pred = [ordered]@{ dimension = $r.dimension; value = $r.value }
            if ($r.operator -ne 'matches') { $pred['operator'] = $r.operator }
            $existingSeg.Add([ordered]@{ type = $r.logic; predicates = @($pred) }) | Out-Null
        }
        $body['segmentFilters'] = @($existingSeg)
    }

    return $body
}

function Update-QueryPreview {
    try {
        $body = Build-QueryBody
        $queryPreviewBox.Text = ($body | ConvertTo-Json -Depth 10)
    }
    catch {
        $queryPreviewBox.Text = "Error: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Results grid population
# ─────────────────────────────────────────────────────────────────────────────

function Show-Results {
    $attrCols = @($script:selectedAttrCols)
    $dt       = New-Object System.Data.DataTable

    # Base columns (always shown)
    @('ConversationId','Start','End','DurationSec','Direction','MediaType','QueueId',
      'AgentName','AgentUserId','tHandleSec','tTalkSec','tAcwSec','tHeldSec','nConnected') |
        ForEach-Object { $dt.Columns.Add($_) | Out-Null }

    foreach ($col in $attrCols) { $dt.Columns.Add("A:$col") | Out-Null }

    foreach ($conv in @($script:allConversations)) {
        $flat   = ConvertTo-FlatRow -Conv $conv -AttrCols $attrCols
        $dtRow  = $dt.NewRow()
        foreach ($col in $dt.Columns) {
            $cn = $col.ColumnName
            $dtRow[$cn] = if ($flat.PSObject.Properties.Name -contains $cn -and $null -ne $flat.$cn) { [string]$flat.$cn } else { '' }
        }
        $dt.Rows.Add($dtRow) | Out-Null
    }

    # Rebuild DataGrid columns
    $resultsGrid.Columns.Clear()
    foreach ($col in $dt.Columns) {
        $dgc = New-Object System.Windows.Controls.DataGridTextColumn
        $dgc.Header  = $col.ColumnName
        $dgc.Binding = New-Object System.Windows.Data.Binding($col.ColumnName)
        if ($col.ColumnName -eq 'ConversationId') { $dgc.Width = 300 }
        $resultsGrid.Columns.Add($dgc) | Out-Null
    }

    $resultsGrid.ItemsSource = $dt.DefaultView

    # Summary stats
    $total    = $script:allConversations.Count
    $byMedia = $script:allConversations |
    Group-Object {
        $agent = $_.participants | Where-Object { $_.purpose -eq 'agent' } | Select-Object -First 1
        if ($null -ne $agent -and $null -ne $agent.sessions -and @($agent.sessions).Count -gt 0) {
            [string]$agent.sessions[0].mediaType
        }
        else {
            ''
        }
    } |
    Sort-Object Count -Descending |
    ForEach-Object { "$($_.Name): $($_.Count)" }
                    Sort-Object Count -Descending | ForEach-Object { "$($_.Name): $($_.Count)" }
    $inbound  = ($script:allConversations | Where-Object { $_.originatingDirection -eq 'inbound'  }).Count
    $outbound = ($script:allConversations | Where-Object { $_.originatingDirection -eq 'outbound' }).Count

    $summaryText.Text = "Loaded $total conversations  |  Inbound: $inbound  Outbound: $outbound  |  $($byMedia -join '  |  ')"
    Set-Status "Results loaded: $total conversations."
}

function Show-ConversationDetail {
    param([object]$Conv)

    # ── Overview
    $overviewPanel.Children.Clear()
    $fields = [ordered]@{
        'Conversation ID' = $Conv.conversationId
        'Start (UTC)'     = $Conv.conversationStart
        'End (UTC)'       = $Conv.conversationEnd
        'Direction'       = $Conv.originatingDirection
        'Division IDs'    = ($Conv.divisionIds -join ', ')
        'MOS (min)'       = $Conv.mediaStatsMinConversationMos
        'R-Factor (min)'  = $Conv.mediaStatsMinConversationRFactor
    }
    foreach ($f in $fields.GetEnumerator()) {
        $border = New-Object System.Windows.Controls.Border
        $border.Background     = [System.Windows.Media.Brushes]::WhiteSmoke
        $border.BorderBrush    = [System.Windows.Media.Brushes]::LightGray
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.Margin         = [System.Windows.Thickness]::new(4,2,4,2)
        $border.Padding        = [System.Windows.Thickness]::new(6,3,6,3)
        $border.CornerRadius   = [System.Windows.CornerRadius]::new(3)

        $sp = New-Object System.Windows.Controls.StackPanel
        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text       = $f.Key
        $label.FontSize   = 10
        $label.Foreground = [System.Windows.Media.Brushes]::Gray
        $value = New-Object System.Windows.Controls.TextBlock
        $value.Text       = if ($null -ne $f.Value) { [string]$f.Value } else { '—' }
        $value.FontWeight = [System.Windows.FontWeights]::SemiBold
        $value.TextWrapping = 'Wrap'
        $sp.Children.Add($label) | Out-Null
        $sp.Children.Add($value) | Out-Null
        $border.Child = $sp
        $overviewPanel.Children.Add($border) | Out-Null
    }

    # ── Attributes (customer participant)
    $cust  = Get-ParticipantByPurpose -Conv $Conv -Purpose 'customer'
    $attrs = if ($null -ne $cust) { $cust.attributes } else { $null }
    $attrList = [System.Collections.Generic.List[pscustomobject]]::new()
    if ($null -ne $attrs) {
        $entries = if ($attrs -is [System.Collections.IDictionary]) {
            $attrs.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ Key=$_; Value=[string]$attrs[$_] } }
        } else {
            $attrs.PSObject.Properties | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Key=$_.Name; Value=[string]$_.Value } }
        }
        foreach ($e in @($entries)) { $attrList.Add($e) | Out-Null }
    }
    $attributesGrid.ItemsSource = $attrList

    # ── Participants
    $partList = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($p in @($Conv.participants)) {
        $partList.Add([pscustomobject]@{
            Purpose      = [string]$p.purpose
            Name         = [string]$p.participantName
            UserId       = [string]$p.userId
            Sessions     = @($p.sessions).Count
            ExtContactId = [string]$p.externalContactId
        }) | Out-Null
    }
    $participantsGrid.ItemsSource = $partList

    # ── Segment timeline
    $segList = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($p in @($Conv.participants)) {
        foreach ($s in @($p.sessions)) {
            foreach ($seg in @($s.segments)) {
                $dur = ''
                try {
                    if ($seg.segmentStart -and $seg.segmentEnd) {
                        $dur = [int]([DateTime]::Parse($seg.segmentEnd) - [DateTime]::Parse($seg.segmentStart)).TotalSeconds
                    }
                } catch {}
                $segList.Add([pscustomobject]@{
                    Purpose    = [string]$p.purpose
                    Type       = [string]$seg.segmentType
                    Start      = [string]$seg.segmentStart
                    End        = [string]$seg.segmentEnd
                    DurSec     = [string]$dur
                    QueueId    = [string]$seg.queueId
                    Disconnect = [string]$seg.disconnectType
                }) | Out-Null
            }
        }
    }
    $segmentsGrid.ItemsSource = $segList

    # ── Raw JSON
    $rawJsonBox.Text = $Conv | ConvertTo-Json -Depth 20
}

# ─────────────────────────────────────────────────────────────────────────────
# DispatcherTimer (job polling — runs on UI thread, no runspace needed)
# ─────────────────────────────────────────────────────────────────────────────

$script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pollTimer.Interval = [TimeSpan]::FromSeconds(3)

$script:pollTimer.Add_Tick({
    try {
        $status = Get-AnalyticsJobStatus -JobId $script:currentJobId
        $state  = [string]$status.state

        $script:pollCount++
        $jobStateLabel.Text = $state
        $jobPollLabel.Text  = [string]$script:pollCount
        $elapsed = [DateTime]::UtcNow - $script:jobSubmitTime
        $jobElapsedLabel.Text = $elapsed.ToString('mm\:ss')

        Append-JobLog "Poll $($script:pollCount): state=$state"

        if ($state -in @('FULFILLED', 'FAILED', 'CANCELLED')) {
            $script:pollTimer.Stop()
            $cancelJobBtn.IsEnabled = $false

            if ($state -eq 'FULFILLED') {
                $jobStateLabel.Foreground = [System.Windows.Media.Brushes]::DarkGreen
                $collectResultsBtn.IsEnabled = $true
                $collectStatusText.Text = "Job FULFILLED! Click 'Collect All Results' to page through and load all conversations."
                Append-JobLog "Job complete. Ready to collect results."
                Set-Status "Job $($script:currentJobId) fulfilled — click Collect."
            } else {
                $jobStateLabel.Foreground = [System.Windows.Media.Brushes]::DarkRed
                $collectStatusText.Text = "Job ended in state: $state. Submit a new job."
                Append-JobLog "Job ended with non-success state: $state"
                Set-Status "Job $state — check log."
            }
        } else {
            $jobStateLabel.Foreground = [System.Windows.Media.Brushes]::DarkOrange
        }
    } catch {
        Append-JobLog "Poll error: $($_.Exception.Message)"
    }
})

# ─────────────────────────────────────────────────────────────────────────────
# Event handlers
# ─────────────────────────────────────────────────────────────────────────────

# ── Auth ──────────────────────────────────────────────────────────────────────

$authButton.Add_Click({
    $region = [string]$regionComboBox.Text
    if ([string]::IsNullOrWhiteSpace($region)) { $region = $DefaultRegion }
    $script:baseUri = "https://api.$region"

    $clientId     = [string]$clientIdBox.Text
    $clientSecret = [string]$clientSecretBox.Password

    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)) {
        [System.Windows.MessageBox]::Show('Enter Client ID and Secret.', 'Authentication', 'OK', 'Warning') | Out-Null
        return
    }

    $authButton.IsEnabled = $false
    Set-Status 'Authenticating...'
    $authStatusLabel.Text = 'Authenticating...'
    $authStatusLabel.Foreground = [System.Windows.Media.Brushes]::DarkOrange

    try {
        $pair       = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${clientId}:${clientSecret}"))
        $authResult = Invoke-RestMethod -Uri "https://login.$region/oauth/token" -Method POST `
            -Headers @{ Authorization = "Basic $pair" } `
            -Body @{ grant_type = 'client_credentials' } -ErrorAction Stop

        $script:accessToken = $authResult.access_token
        $script:headers     = @{ Authorization = "Bearer $($script:accessToken)" }

        $authStatusLabel.Text       = "✓ Authenticated"
        $authStatusLabel.Foreground = [System.Windows.Media.Brushes]::DarkGreen
        Save-GenesysEnvConfig -Region $region -ClientId $clientId
        Set-Status "Authenticated — $region."
        Append-JobLog "Authenticated to $region."
    }
    catch {
        $authStatusLabel.Text       = "✗ Failed"
        $authStatusLabel.Foreground = [System.Windows.Media.Brushes]::DarkRed
        Set-Status "Authentication failed."
        [System.Windows.MessageBox]::Show("Authentication failed:`n$($_.Exception.Message)", 'Auth Error', 'OK', 'Error') | Out-Null
    }
    finally {
        $authButton.IsEnabled = $true
    }
})

# ── Date presets ──────────────────────────────────────────────────────────────

function Set-DatePreset {
    param([DateTime]$Start, [DateTime]$End)
    $startDatePicker.SelectedDate = $Start
    $endDatePicker.SelectedDate   = $End
    Update-QueryPreview
}

(Get-Control 'PresetToday').Add_Click({
    $t = [DateTime]::Today; Set-DatePreset -Start $t -End $t
})
(Get-Control 'PresetYesterday').Add_Click({
    $y = [DateTime]::Today.AddDays(-1); Set-DatePreset -Start $y -End $y
})
(Get-Control 'PresetLast7').Add_Click({
    Set-DatePreset -Start ([DateTime]::Today.AddDays(-6)) -End [DateTime]::Today
})
(Get-Control 'PresetLast30').Add_Click({
    Set-DatePreset -Start ([DateTime]::Today.AddDays(-29)) -End [DateTime]::Today
})
(Get-Control 'PresetThisMonth').Add_Click({
    $now = [DateTime]::Today
    $s = [DateTime]::new($now.Year, $now.Month, 1)
    Set-DatePreset -Start $s -End $now
})
(Get-Control 'PresetLastMonth').Add_Click({
    $now = [DateTime]::Today
    $s = [DateTime]::new($now.Year, $now.Month, 1).AddMonths(-1)
    $e = [DateTime]::new($now.Year, $now.Month, 1).AddDays(-1)
    Set-DatePreset -Start $s -End $e
})

$startDatePicker.Add_SelectedDateChanged({ Update-QueryPreview })
$startDatePicker.Add_LostFocus({ Update-QueryPreview })
$endDatePicker.Add_SelectedDateChanged({ Update-QueryPreview })
$endDatePicker.Add_LostFocus({ Update-QueryPreview })
$directionCombo.Add_SelectionChanged({ Update-QueryPreview })
$mediaTypeCombo.Add_SelectionChanged({ Update-QueryPreview })
$orderByCombo.Add_SelectionChanged({ Update-QueryPreview })
$orderCombo.Add_SelectionChanged({ Update-QueryPreview })

# ── Filter rows ───────────────────────────────────────────────────────────────

$addConvFilterBtn.Add_Click({
    New-FilterRow -Type 'conversation' -Panel $convFilterPanel | Out-Null
    Update-QueryPreview
})
$addSegFilterBtn.Add_Click({
    New-FilterRow -Type 'segment' -Panel $segFilterPanel | Out-Null
    Update-QueryPreview
})

$clearFiltersBtn.Add_Click({
    $convFilterPanel.Children.Clear()
    $segFilterPanel.Children.Clear()
    $directionCombo.SelectedIndex  = 0
    $mediaTypeCombo.SelectedIndex  = 0
    Update-QueryPreview
})

# ── Preview JSON ──────────────────────────────────────────────────────────────

$previewBtn.Add_Click({
    Update-QueryPreview
})

# ── Submit job ────────────────────────────────────────────────────────────────

$submitJobBtn.Add_Click({
    if ([string]::IsNullOrWhiteSpace($script:accessToken)) {
        [System.Windows.MessageBox]::Show('Please authenticate first.', 'Not Authenticated', 'OK', 'Warning') | Out-Null
        return
    }

    try {
        $body    = Build-QueryBody
        $jsonBody = $body | ConvertTo-Json -Depth 10

        Append-JobLog "Submitting job..."
        Append-JobLog "Body: $jsonBody"
        Set-Status 'Submitting job...'

        $result = Submit-AnalyticsJob -JsonBody $jsonBody
        $jobId  = [string]$result.jobId

        if ([string]::IsNullOrWhiteSpace($jobId)) { throw "No jobId in response." }

        $script:currentJobId   = $jobId
        $script:pollCount      = 0
        $script:jobSubmitTime  = [DateTime]::UtcNow

        $jobIdBox.Text         = $jobId
        $jobStateLabel.Text    = [string]$result.state
        $jobStateLabel.Foreground = [System.Windows.Media.Brushes]::DarkOrange
        $jobPollLabel.Text     = '0'
        $jobElapsedLabel.Text  = '00:00'
        $cancelJobBtn.IsEnabled   = $true
        $collectResultsBtn.IsEnabled = $false
        $collectStatusText.Text = 'Job submitted. Polling for completion...'

        Append-JobLog "Job submitted: $jobId  (initial state: $($result.state))"
        Set-Status "Job $jobId submitted — polling..."

        # Switch to Job Monitor tab
        $mainTabControl.SelectedIndex = 1

        $script:pollTimer.Start()
    }
    catch {
        [System.Windows.MessageBox]::Show("Submit failed:`n$($_.Exception.Message)", 'Submit Error', 'OK', 'Error') | Out-Null
        Set-Status "Job submit failed."
        Append-JobLog "Submit error: $($_.Exception.Message)"
    }
})

# ── Cancel job ────────────────────────────────────────────────────────────────

$cancelJobBtn.Add_Click({
    if ([string]::IsNullOrWhiteSpace($script:currentJobId)) { return }
    $r = [System.Windows.MessageBox]::Show(
        "Delete/cancel job $($script:currentJobId)?", 'Confirm Cancel', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }

    $script:pollTimer.Stop()
    Remove-AnalyticsJob -JobId $script:currentJobId
    Append-JobLog "Job $($script:currentJobId) cancelled/deleted."
    $jobStateLabel.Text       = 'CANCELLED'
    $jobStateLabel.Foreground = [System.Windows.Media.Brushes]::DarkRed
    $cancelJobBtn.IsEnabled   = $false
    $collectResultsBtn.IsEnabled = $false
    $collectStatusText.Text   = 'Job cancelled. Submit a new job.'
    Set-Status 'Job cancelled.'
})

# ── Collect results ───────────────────────────────────────────────────────────

$collectResultsBtn.Add_Click({
    $collectResultsBtn.IsEnabled = $false
    $script:allConversations.Clear()
    $cursor = $null
    $page   = 0

    Append-JobLog "Collecting results from job $($script:currentJobId)..."
    Set-Status 'Collecting results...'

    try {
        do {
            $page++
            Append-JobLog "  Page $page — cursor: $(if ($cursor) { $cursor.Substring(0, [Math]::Min(20,$cursor.Length)) + '...' } else { '(first)' })"

            $result = Get-AnalyticsJobResults -JobId $script:currentJobId -PageSize 1000 -Cursor $cursor
            $batch  = @($result.conversations)
            foreach ($c in $batch) { $script:allConversations.Add($c) | Out-Null }
            $cursor = [string]$result.cursor
            Append-JobLog "  Got $($batch.Count) — total so far: $($script:allConversations.Count)"
            Set-Status "Collecting… $($script:allConversations.Count) conversations so far."

            # Let the UI breathe between pages
            [System.Windows.Forms.Application]::DoEvents()
        } while (-not [string]::IsNullOrWhiteSpace($cursor))

        Append-JobLog "Collection complete. $($script:allConversations.Count) total conversations."
        Set-Status "Collection complete: $($script:allConversations.Count) conversations."

        Show-Results
        $mainTabControl.SelectedIndex = 2
    }
    catch {
        Append-JobLog "Collection error: $($_.Exception.Message)"
        Set-Status 'Collection error — see log.'
        [System.Windows.MessageBox]::Show("Collection failed:`n$($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
    }
    finally {
        $collectResultsBtn.IsEnabled = $true
    }
})

# ── Results grid selection ────────────────────────────────────────────────────

$resultsGrid.Add_SelectionChanged({
    $row = $resultsGrid.SelectedItem
    if ($null -eq $row) { return }
    $convId = [string]($row['ConversationId'])
    $conv   = @($script:allConversations | Where-Object { [string]$_.conversationId -eq $convId }) | Select-Object -First 1
    if ($null -eq $conv) { return }
    Show-ConversationDetail -Conv $conv
})

# ── Column selector ───────────────────────────────────────────────────────────

$columnSelectorBtn.Add_Click({
    $allKeys = Get-AllAttributeKeys
    if ($allKeys.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No attribute keys found. Load results first.', 'Column Selector', 'OK', 'Information') | Out-Null
        return
    }

    $popup = New-Object System.Windows.Window
    $popup.Title  = 'Select Attribute Columns to Include'
    $popup.Width  = 420; $popup.Height = 540
    $popup.WindowStartupLocation = 'CenterOwner'; $popup.Owner = $window
    $popup.ResizeMode = 'NoResize'

    $outerGrid = New-Object System.Windows.Controls.Grid
    $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = [System.Windows.GridLength]::Star
    $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = [System.Windows.GridLength]::Auto
    $outerGrid.RowDefinitions.Add($r0); $outerGrid.RowDefinitions.Add($r1)
    $popup.Content = $outerGrid

    $scroll = New-Object System.Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'
    $inner  = New-Object System.Windows.Controls.StackPanel; $inner.Margin = [System.Windows.Thickness]::new(10)
    $scroll.Content = $inner
    [System.Windows.Controls.Grid]::SetRow($scroll, 0); $outerGrid.Children.Add($scroll) | Out-Null

    # Search box
    $searchBox = New-Object System.Windows.Controls.TextBox
    $searchBox.Margin = [System.Windows.Thickness]::new(0,0,0,6)
    $searchBox.ToolTip = 'Filter attribute list'
    $inner.Children.Add($searchBox) | Out-Null

    $cbList = [System.Collections.Generic.List[System.Windows.Controls.CheckBox]]::new()

    function Render-AttrList {
        param([string]$Filter = '')
        $inner.Children.Clear()
        $inner.Children.Add($searchBox) | Out-Null
        $cbList.Clear()
        foreach ($k in $allKeys) {
            if ($Filter -and $k -notlike "*$Filter*") { continue }
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content   = $k; $cb.Tag = $k
            $cb.Margin    = [System.Windows.Thickness]::new(0,1,0,1)
            $cb.IsChecked = $script:selectedAttrCols -contains $k
            $inner.Children.Add($cb) | Out-Null
            $cbList.Add($cb) | Out-Null
        }
    }

    Render-AttrList

    $searchBox.Add_TextChanged({ Render-AttrList -Filter $searchBox.Text }.GetNewClosure())

    $btnRow = New-Object System.Windows.Controls.StackPanel
    $btnRow.Orientation = 'Horizontal'; $btnRow.HorizontalAlignment = 'Right'
    $btnRow.Margin = [System.Windows.Thickness]::new(6)
    [System.Windows.Controls.Grid]::SetRow($btnRow, 1); $outerGrid.Children.Add($btnRow) | Out-Null

    $applyBtn = New-Object System.Windows.Controls.Button; $applyBtn.Content = 'Apply & Refresh'; $applyBtn.Width = 110
    $applyBtn.Add_Click({
        $script:selectedAttrCols.Clear()
        foreach ($cb in @($cbList)) {
            if ($cb.IsChecked) { $script:selectedAttrCols.Add([string]$cb.Tag) | Out-Null }
        }
        $popup.Close()
        if ($script:allConversations.Count -gt 0) { Show-Results }
    }.GetNewClosure())
    $btnRow.Children.Add($applyBtn) | Out-Null

    $cancelBtn = New-Object System.Windows.Controls.Button; $cancelBtn.Content = 'Cancel'; $cancelBtn.Width = 70; $cancelBtn.Margin = [System.Windows.Thickness]::new(4,0,0,0)
    $cancelBtn.Add_Click({ $popup.Close() })
    $btnRow.Children.Add($cancelBtn) | Out-Null

    $popup.ShowDialog() | Out-Null
})

# ── Export CSV ────────────────────────────────────────────────────────────────

$exportCsvBtn.Add_Click({
    if ($script:allConversations.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No results to export.', 'Export', 'OK', 'Information') | Out-Null; return
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter   = 'CSV files (*.csv)|*.csv'
    $dlg.FileName = "conversations-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    if ($dlg.ShowDialog() -ne 'OK') { return }

    try {
        $attrCols = @($script:selectedAttrCols)
        $rows = @($script:allConversations | ForEach-Object { ConvertTo-FlatRow -Conv $_ -AttrCols $attrCols })
        $rows | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
        Set-Status "Exported $($rows.Count) rows to $($dlg.FileName)"
        [System.Windows.MessageBox]::Show("Exported $($rows.Count) conversations to:`n$($dlg.FileName)", 'Export Complete', 'OK', 'Information') | Out-Null
    }
    catch {
        [System.Windows.MessageBox]::Show("Export failed:`n$($_.Exception.Message)", 'Export Error', 'OK', 'Error') | Out-Null
    }
})

# ── Export JSONL ──────────────────────────────────────────────────────────────

$exportJsonlBtn.Add_Click({
    if ($script:allConversations.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No results to export.', 'Export', 'OK', 'Information') | Out-Null; return
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter   = 'JSONL files (*.jsonl)|*.jsonl|JSON files (*.json)|*.json'
    $dlg.FileName = "conversations-$(Get-Date -Format 'yyyyMMdd-HHmmss').jsonl"
    if ($dlg.ShowDialog() -ne 'OK') { return }

    try {
        $sw = [System.IO.StreamWriter]::new($dlg.FileName, $false, [System.Text.Encoding]::UTF8)
        foreach ($conv in @($script:allConversations)) {
            $sw.WriteLine(($conv | ConvertTo-Json -Depth 20 -Compress))
        }
        $sw.Close()
        Set-Status "Exported $($script:allConversations.Count) conversations (JSONL) to $($dlg.FileName)"
        [System.Windows.MessageBox]::Show("Exported $($script:allConversations.Count) conversations to:`n$($dlg.FileName)", 'Export Complete', 'OK', 'Information') | Out-Null
    }
    catch {
        [System.Windows.MessageBox]::Show("Export failed:`n$($_.Exception.Message)", 'Export Error', 'OK', 'Error') | Out-Null
    }
})

# ── Load from JSONL ───────────────────────────────────────────────────────────

$loadJsonlBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'JSONL files (*.jsonl)|*.jsonl|JSON files (*.json)|*.json|All files (*.*)|*.*'
    $dlg.Title  = 'Load Conversation JSONL'
    if ($dlg.ShowDialog() -ne 'OK') { return }

    try {
        $script:allConversations.Clear()
        Set-Status "Loading $($dlg.FileName)..."

        $lines = [System.IO.File]::ReadAllLines($dlg.FileName)
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            $obj = $trimmed | ConvertFrom-Json
            # Support both top-level array and JSONL objects
            if ($obj -is [System.Object[]] -or ($obj.PSObject.Properties.Name -contains 'conversations')) {
                $convList = if ($obj.PSObject.Properties.Name -contains 'conversations') { $obj.conversations } else { $obj }
                foreach ($c in @($convList)) { $script:allConversations.Add($c) | Out-Null }
            } else {
                $script:allConversations.Add($obj) | Out-Null
            }
        }

        Show-Results
        $mainTabControl.SelectedIndex = 2
        Set-Status "Loaded $($script:allConversations.Count) conversations from file."
    }
    catch {
        [System.Windows.MessageBox]::Show("Load failed:`n$($_.Exception.Message)", 'Load Error', 'OK', 'Error') | Out-Null
        Set-Status 'Load failed.'
    }
})

# ── Clear results ─────────────────────────────────────────────────────────────

$clearResultsBtn.Add_Click({
    $script:allConversations.Clear()
    $resultsGrid.ItemsSource = $null
    $resultsGrid.Columns.Clear()
    $summaryText.Text = 'Results cleared.'
    $overviewPanel.Children.Clear()
    $attributesGrid.ItemsSource   = $null
    $participantsGrid.ItemsSource = $null
    $segmentsGrid.ItemsSource     = $null
    $rawJsonBox.Text = ''
    Set-Status 'Results cleared.'
})

# ─────────────────────────────────────────────────────────────────────────────
# Startup: load persisted config + auto-auth
# ─────────────────────────────────────────────────────────────────────────────

$startDatePicker.SelectedDate = $null
$endDatePicker.SelectedDate   = $null
Update-QueryPreview

$cfg = Read-GenesysEnvConfig
if ($null -ne $cfg) {
    $cfgRegion = Get-ConfigString -ConfigObject $cfg -PropertyNames @('region')
    if (-not [string]::IsNullOrWhiteSpace($cfgRegion)) { $regionComboBox.Text = $cfgRegion }

    $cfgClientId = Get-ConfigString -ConfigObject $cfg -PropertyNames @('clientId','client_id')
    if (-not [string]::IsNullOrWhiteSpace($cfgClientId)) { $clientIdBox.Text = $cfgClientId }
}

# Env vars override config
if (-not [string]::IsNullOrWhiteSpace($env:GENESYS_CLIENT_ID))     { $clientIdBox.Text       = $env:GENESYS_CLIENT_ID }
if (-not [string]::IsNullOrWhiteSpace($env:GENESYS_CLIENT_SECRET)) { $clientSecretBox.Password = $env:GENESYS_CLIENT_SECRET }

if (-not [string]::IsNullOrWhiteSpace([string]$clientIdBox.Text) -and -not [string]::IsNullOrWhiteSpace([string]$clientSecretBox.Password)) {
    $authButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
}

# ─────────────────────────────────────────────────────────────────────────────
# Show
# ─────────────────────────────────────────────────────────────────────────────

$window.ShowDialog() | Out-Null
