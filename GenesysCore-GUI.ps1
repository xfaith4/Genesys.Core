<#
.SYNOPSIS
    Genesys.Core WPF GUI for dataset execution with authentication

.DESCRIPTION
    A Windows Presentation Foundation (WPF) GUI that provides:
    - OAuth authentication flow for Genesys Cloud
    - Category/Dataset selection
    - Real-time execution progress
    - Output inspection
    
    This GUI is a client of the Genesys.Core PowerShell module and does not
    reimplement core functionality.

.NOTES
    Requirements:
    - Windows operating system (WPF is Windows-only)
    - PowerShell 5.1 or PowerShell 7+
    - Genesys Cloud OAuth credentials

.EXAMPLE
    # Run the GUI
    .\GenesysCore-GUI.ps1
    
.EXAMPLE
    # Run with pre-configured region
    .\GenesysCore-GUI.ps1 -DefaultRegion 'mypurecloud.com'
#>

[CmdletBinding()]
param(
    [string]$DefaultRegion = 'mypurecloud.com',
    [string]$ModulePath = "$PSScriptRoot/modules/Genesys.Core/Genesys.Core.psd1",
    [string]$ConfigPath
)

# Verify Windows platform
if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    throw "This GUI requires Windows. WPF is not available on non-Windows platforms."
}

# Import the Genesys.Core module
Import-Module $ModulePath -Force

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# ---------------------------------------------------------------------------
# Persistent config (JSON next to this script, not committed)
# ---------------------------------------------------------------------------
function Resolve-UIConfigPath {
    param([string]$ExplicitPath)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace([string]$ExplicitPath) -eq $false) {
        $candidates.Add([string]$ExplicitPath) | Out-Null
    }

    $candidates.Add('GenesysCore-GUI.config.json') | Out-Null
    $candidates.Add('genesys.env.json') | Out-Null

    foreach ($candidate in @($candidates)) {
        $resolvedCandidate = $candidate
        if ([System.IO.Path]::IsPathRooted([string]$candidate) -eq $false) {
            $resolvedCandidate = Join-Path -Path $PSScriptRoot -ChildPath $candidate
        }

        if (Test-Path -Path $resolvedCandidate -PathType Leaf) {
            return (Resolve-Path -Path $resolvedCandidate).Path
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$ExplicitPath) -eq $false) {
        if ([System.IO.Path]::IsPathRooted([string]$ExplicitPath)) {
            return $ExplicitPath
        }

        return (Join-Path -Path $PSScriptRoot -ChildPath $ExplicitPath)
    }

    return (Join-Path -Path $PSScriptRoot -ChildPath 'GenesysCore-GUI.config.json')
}

$script:configPath = Resolve-UIConfigPath -ExplicitPath $ConfigPath

function Read-GenesysEnvConfig {
    if (-not (Test-Path -Path $script:configPath)) {
        return $null
    }

    try {
        return Get-Content -Path $script:configPath -Raw -Encoding utf8 | ConvertFrom-Json
    }
    catch {
        Write-Warning "Failed to read Genesys env config '$($script:configPath)': $($_.Exception.Message)"
        return $null
    }
}

function Save-GenesysEnvConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Region,

        [string]$ClientId
    )

    $config = [ordered]@{
        '_notes' = [ordered]@{
            description = "Genesys Core persistent configuration. Region and client ID are persisted here. clientSecret may be provided for startup auto-authentication, but environment variables are recommended."
            envVars     = [ordered]@{
                GENESYS_CLIENT_ID     = "Your Genesys Cloud OAuth Client ID (Client Credentials grant). Set this env var so it does not need to be stored in this file."
                GENESYS_CLIENT_SECRET = "Your Genesys Cloud OAuth Client Secret. Preferred over file storage for security."
                GENESYS_BEARER_TOKEN  = "Optional: pre-obtained bearer token. Bypasses the OAuth flow when set."
            }
        }
        region = $Region.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($ClientId)) {
        $config['clientId'] = $ClientId.Trim()
    }

    try {
        ($config | ConvertTo-Json -Depth 10) | Set-Content -Path $script:configPath -Encoding utf8
    }
    catch {
        Write-Warning "Failed to save Genesys env config '$($script:configPath)': $($_.Exception.Message)"
    }
}

function Get-ConfigString {
    param(
        [object]$ConfigObject,
        [string[]]$PropertyNames
    )

    if ($null -eq $ConfigObject) {
        return $null
    }

    foreach ($name in @($PropertyNames)) {
        if ($ConfigObject.PSObject.Properties.Name -contains $name) {
            $value = [string]$ConfigObject.$name
            if ([string]::IsNullOrWhiteSpace($value) -eq $false) {
                return $value
            }
        }
    }

    return $null
}

# XAML definition for the GUI
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Genesys.Core Dataset Runner" Height="600" Width="800"
        WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Authentication Section -->
        <GroupBox Grid.Row="0" Header="Authentication" Padding="10" Margin="0,0,0,10">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="120"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="100"/>
                </Grid.ColumnDefinitions>
                
                <Label Grid.Row="0" Grid.Column="0" Content="Region:"/>
                <ComboBox Grid.Row="0" Grid.Column="1" Name="RegionComboBox" IsEditable="True">
                    <ComboBoxItem Content="mypurecloud.com" IsSelected="True"/>
                    <ComboBoxItem Content="mypurecloud.com.au"/>
                    <ComboBoxItem Content="mypurecloud.de"/>
                    <ComboBoxItem Content="mypurecloud.ie"/>
                    <ComboBoxItem Content="mypurecloud.jp"/>
                </ComboBox>
                
                <Label Grid.Row="1" Grid.Column="0" Content="Client ID:"/>
                <TextBox Grid.Row="1" Grid.Column="1" Name="ClientIdTextBox" Margin="0,5,0,0"/>
                
                <Label Grid.Row="2" Grid.Column="0" Content="Client Secret:"/>
                <PasswordBox Grid.Row="2" Grid.Column="1" Name="ClientSecretBox" Margin="0,5,0,0"/>
                
                <Button Grid.Row="3" Grid.Column="1" Name="AuthButton" Content="Authenticate" 
                        HorizontalAlignment="Left" Margin="0,10,0,0" Width="120" Height="30"/>
                <Label Grid.Row="3" Grid.Column="1" Name="AuthStatusLabel" Content="" 
                       HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,10,0,0"/>
            </Grid>
        </GroupBox>
        
        <!-- Dataset Selection -->
        <GroupBox Grid.Row="1" Header="Dataset Selection" Padding="10" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                
                <GroupBox Grid.Column="0" Header="Datasets" Margin="0,0,10,0">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="180">
                        <StackPanel Name="DatasetCheckBoxPanel"/>
                    </ScrollViewer>
                </GroupBox>
                
                <StackPanel Grid.Column="1" Orientation="Vertical">
                    <Label Content="Output Directory:"/>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="80"/>
                        </Grid.ColumnDefinitions>
                        <TextBox Grid.Column="0" Name="OutputDirTextBox" Text="./out" VerticalAlignment="Center"/>
                        <Button Grid.Column="1" Name="BrowseButton" Content="Browse..." Margin="5,0,0,0"/>
                    </Grid>
                </StackPanel>
            </Grid>
        </GroupBox>
        
        <!-- Execution Controls -->
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,10">
            <Button Name="RunButton" Content="Run Selected" Width="120" Height="35" Margin="0,0,10,0" IsEnabled="False"/>
            <Button Name="DryRunButton" Content="Dry Run (WhatIf)" Width="120" Height="35" Margin="0,0,10,0"/>
            <Button Name="ClearLogButton" Content="Clear Log" Width="100" Height="35"/>
        </StackPanel>
        
        <!-- Log Output -->
        <GroupBox Grid.Row="3" Header="Execution Log" Padding="5">
            <TextBox Name="LogTextBox" IsReadOnly="True" VerticalScrollBarVisibility="Auto" 
                     FontFamily="Consolas" FontSize="11" TextWrapping="Wrap"/>
        </GroupBox>
        
        <!-- Status Bar -->
        <StatusBar Grid.Row="4" Height="25">
            <StatusBarItem>
                <TextBlock Name="StatusTextBlock" Text="Ready"/>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
"@

# Load XAML
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get controls
$regionComboBox = $window.FindName('RegionComboBox')
$clientIdTextBox = $window.FindName('ClientIdTextBox')
$clientSecretBox = $window.FindName('ClientSecretBox')
$authButton = $window.FindName('AuthButton')
$authStatusLabel = $window.FindName('AuthStatusLabel')
$datasetCheckBoxPanel = $window.FindName('DatasetCheckBoxPanel')
$outputDirTextBox = $window.FindName('OutputDirTextBox')
$browseButton = $window.FindName('BrowseButton')
$runButton = $window.FindName('RunButton')
$dryRunButton = $window.FindName('DryRunButton')
$clearLogButton = $window.FindName('ClearLogButton')
$logTextBox = $window.FindName('LogTextBox')
$statusTextBlock = $window.FindName('StatusTextBlock')

# Set default region — overridden below if a saved config exists
$regionComboBox.Text = $DefaultRegion

# Global state
$script:accessToken = $null
$script:headers = $null
$script:baseUri = $null
$script:datasetCheckBoxes = @()

# Helper function to append to log
function Write-Log {
    param([string]$Message, [string]$Color = 'Black')
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logTextBox.AppendText("[$timestamp] $Message`r`n")
    $logTextBox.ScrollToEnd()
}

# Helper function to update status
function Update-Status {
    param([string]$Message)
    $statusTextBlock.Text = $Message
}

function Resolve-UICatalogPath {
    $candidates = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'catalog/genesys.catalog.json')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-AvailableDatasets {
    $catalogPath = Resolve-UICatalogPath
    if ([string]::IsNullOrWhiteSpace([string]$catalogPath)) {
        throw 'Unable to find catalog/genesys.catalog.json.'
    }

    $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
    $datasets = [System.Collections.Generic.List[object]]::new()

    foreach ($property in $catalog.datasets.PSObject.Properties) {
        $dataset = $property.Value
        $description = [string]$dataset.description
        if ([string]::IsNullOrWhiteSpace($description)) {
            $description = "Endpoint: $($dataset.endpoint)"
        }

        $datasets.Add([pscustomobject]@{
            key = [string]$property.Name
            endpoint = [string]$dataset.endpoint
            description = $description
        }) | Out-Null
    }

    return @($datasets | Sort-Object -Property key)
}

function Initialize-DatasetSelection {
    $datasetCheckBoxPanel.Children.Clear()
    $script:datasetCheckBoxes = @()

    $datasets = Get-AvailableDatasets
    foreach ($dataset in $datasets) {
        $checkBox = New-Object System.Windows.Controls.CheckBox
        $checkBox.Content = $dataset.key
        $checkBox.ToolTip = $dataset.description
        $checkBox.Tag = $dataset.key
        $checkBox.Margin = [System.Windows.Thickness]::new(5, 2, 5, 2)

        if (@('audit-logs', 'users', 'routing-queues') -contains $dataset.key) {
            $checkBox.IsChecked = $true
        }

        $datasetCheckBoxPanel.Children.Add($checkBox) | Out-Null
        $script:datasetCheckBoxes += $checkBox
    }
}

function Invoke-UIAuthentication {
    param([switch]$Interactive)

    $clientId = $clientIdTextBox.Text.Trim()
    $clientSecret = $clientSecretBox.Password
    $region = $regionComboBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)) {
        if ($Interactive) {
            [System.Windows.MessageBox]::Show('Please enter both Client ID and Client Secret.', 'Validation Error', 'OK', 'Warning') | Out-Null
        }

        return $false
    }

    if ([string]::IsNullOrWhiteSpace($region)) {
        if ($Interactive) {
            [System.Windows.MessageBox]::Show('Please select or enter a region.', 'Validation Error', 'OK', 'Warning') | Out-Null
        }

        return $false
    }

    Write-Log "Authenticating with region: $($region)..."
    Update-Status "Authenticating..."

    try {
        $authUrl = "https://login.$($region)/oauth/token"
        $script:baseUri = "https://api.$($region)"

        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $clientId
            client_secret = $clientSecret
        }

        Write-Log "[API] POST $($authUrl) (grant_type=client_credentials, client_id=$($clientId))"
        $authResponse = Invoke-RestMethod -Uri $authUrl -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'
        $script:accessToken = $authResponse.access_token
        $script:headers = @{
            Authorization = "Bearer $($script:accessToken)"
        }

        # Persist region (and client ID if the user provided one in the GUI)
        Save-GenesysEnvConfig -Region $region -ClientId $clientId
        Write-Log "Config saved: region='$($region)'"

        Write-Log "Authentication successful!"
        $authStatusLabel.Content = "✓ Authenticated"
        $authStatusLabel.Foreground = "Green"
        $runButton.IsEnabled = $true
        Update-Status "Authenticated successfully"
        return $true
    }
    catch {
        Write-Log "Authentication failed: $($_.Exception.Message)"
        $authStatusLabel.Content = "✗ Failed"
        $authStatusLabel.Foreground = "Red"
        $runButton.IsEnabled = $false
        Update-Status "Authentication failed"

        if ($Interactive) {
            [System.Windows.MessageBox]::Show("Authentication failed: $($_.Exception.Message)", 'Authentication Error', 'OK', 'Error') | Out-Null
        }

        return $false
    }
}

# Authentication handler
$authButton.Add_Click({
    Invoke-UIAuthentication -Interactive | Out-Null
})

# Browse button handler
$browseButton.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select output directory"
    $folderBrowser.ShowNewFolderButton = $true

    $rawPath = [string]$outputDirTextBox.Text
    $initialPath = $null

    if ([string]::IsNullOrWhiteSpace($rawPath) -eq $false) {
        try {
            if ([System.IO.Path]::IsPathRooted($rawPath)) {
                $candidatePath = [System.IO.Path]::GetFullPath($rawPath)
            }
            else {
                $candidatePath = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $rawPath))
            }

            if (Test-Path -Path $candidatePath -PathType Container) {
                $initialPath = $candidatePath
            }
        }
        catch {
            Write-Log "Browse path '$($rawPath)' is invalid. Falling back to current directory."
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$initialPath)) {
        $initialPath = (Get-Location).Path
    }

    $folderBrowser.SelectedPath = $initialPath

    try {
        $dialogResult = $folderBrowser.ShowDialog()
        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK -and [string]::IsNullOrWhiteSpace([string]$folderBrowser.SelectedPath) -eq $false) {
            $outputDirTextBox.Text = $folderBrowser.SelectedPath
        }
    }
    catch {
        Write-Log "Unable to open folder picker: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Unable to open folder picker: $($_.Exception.Message)", 'Browse Error', 'OK', 'Error') | Out-Null
    }
    finally {
        $folderBrowser.Dispose()
    }
})

# Get selected datasets
function Get-SelectedDatasets {
    $datasets = @()
    foreach ($checkBox in @($script:datasetCheckBoxes)) {
        if ($checkBox.IsChecked -eq $true) {
            $datasets += [string]$checkBox.Tag
        }
    }

    return $datasets
}

# Run button handler
$runButton.Add_Click({
    $datasets = Get-SelectedDatasets

    if ($datasets.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Please select at least one dataset.', 'Validation Error', 'OK', 'Warning')
        return
    }

    $outputDir = $outputDirTextBox.Text

    Write-Log "========================================"
    Write-Log "Starting execution of $($datasets.Count) dataset(s)..."
    Update-Status "Running datasets..."

    $runButton.IsEnabled = $false
    $authButton.IsEnabled = $false

    # RequestInvoker that logs every API call (method + URI, query params visible, auth header hidden)
    $guiRequestInvoker = {
        param($request)

        $safeUri = [string]$request.Uri
        $method  = ([string]$request.Method).ToUpperInvariant()

        # Build a sanitized display of the headers (omit Authorization/Token values)
        $safeHeaders = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $request.Headers) {
            foreach ($key in $request.Headers.Keys) {
                if ($key -match '(?i)Authorization|Token|Secret') {
                    $safeHeaders.Add("$($key): [REDACTED]") | Out-Null
                }
                else {
                    $safeHeaders.Add("$($key): $($request.Headers[$key])") | Out-Null
                }
            }
        }

        $headerNote = if ($safeHeaders.Count -gt 0) { " | Headers: $([string]::Join(', ', $safeHeaders))" } else { '' }
        Write-Log "[API] $($method) $($safeUri)$($headerNote)"

        # Execute the actual HTTP request
        $invokeParams = @{
            Uri         = $request.Uri
            Method      = $request.Method
            TimeoutSec  = if ($request.PSObject.Properties.Name -contains 'TimeoutSec') { $request.TimeoutSec } else { 120 }
            ErrorAction = 'Stop'
        }

        if ($null -ne $request.Headers) {
            $invokeParams.Headers = $request.Headers
        }

        if ($null -ne $request.Body) {
            $invokeParams.Body = $request.Body

            $hasContentTypeHeader = $false
            if ($null -ne $request.Headers) {
                foreach ($headerKey in $request.Headers.Keys) {
                    if ([string]$headerKey -match '^(?i)content-type$') {
                        $hasContentTypeHeader = $true
                        break
                    }
                }
            }

            if (-not $hasContentTypeHeader) {
                if ($method -in @('POST', 'PUT', 'PATCH')) {
                    $bodyText = [string]$request.Body
                    $trimmedBody = $bodyText.TrimStart()
                    if ($trimmedBody.StartsWith('{') -or $trimmedBody.StartsWith('[')) {
                        $invokeParams.ContentType = 'application/json'
                    }
                }
            }
        }

        Invoke-RestMethod @invokeParams
    }.GetNewClosure()

    try {
        foreach ($dataset in $datasets) {
            Write-Log "Executing dataset: $dataset"

            try {
                $runContext = Invoke-Dataset -Dataset $dataset -OutputRoot $outputDir -BaseUri $script:baseUri -Headers $script:headers -RequestInvoker $guiRequestInvoker

                Write-Log "  ✓ $dataset completed successfully"
                Write-Log "    Run ID: $($runContext.runId)"
                Write-Log "    Output: $($runContext.runFolder)"

                # Show summary
                $summaryPath = Join-Path -Path $runContext.runFolder -ChildPath 'summary.json'
                if (Test-Path $summaryPath) {
                    $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json
                    Write-Log "    Total records: $($summary.totals.totalRecords)"
                }
            }
            catch {
                Write-Log "  ✗ $dataset failed: $($_.Exception.Message)"
            }
        }

        Write-Log "All datasets completed!"
        Write-Log "Output directory: $outputDir"
        Update-Status "Execution completed"

        [System.Windows.MessageBox]::Show("Dataset execution completed!`nOutput: $outputDir", 'Success', 'OK', 'Information')
    }
    finally {
        $runButton.IsEnabled = $true
        $authButton.IsEnabled = $true
    }
})

# Dry run button handler
$dryRunButton.Add_Click({
    $datasets = Get-SelectedDatasets
    
    if ($datasets.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Please select at least one dataset.', 'Validation Error', 'OK', 'Warning')
        return
    }

    $outputDir = [string]$outputDirTextBox.Text

    Write-Log "========================================"
    Write-Log "Dry run for $($datasets.Count) dataset(s)..."
    Write-Log "Planned output root: $outputDir"

    $mockScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts/Invoke-MockRun.ps1'
    $mockSupportedDatasets = @(
        'audit-logs'
        'analytics-conversation-details'
        'analytics-conversation-details-query'
        'users'
        'routing-queues'
    )

    $mockDatasets = @($datasets | Where-Object { $mockSupportedDatasets -contains $_ })
    $whatIfDatasets = @($datasets | Where-Object { $mockSupportedDatasets -notcontains $_ })

    if ((Test-Path -Path $mockScriptPath) -and $mockDatasets.Count -gt 0) {
        Write-Log "Running mock dry-run datasets with scripts/Invoke-MockRun.ps1..."
        $mockOutput = & pwsh -NoProfile -File $mockScriptPath -OutputRoot $outputDir -Datasets $mockDatasets -NoReport *>&1
        $mockExitCode = $LASTEXITCODE
        @($mockOutput) | ForEach-Object {
            Write-Log "  $_"
        }

        if ($mockExitCode -ne 0) {
            Write-Log "Mock dry-run script exited with code $mockExitCode. Falling back to WhatIf for those datasets."
            $whatIfDatasets = @($whatIfDatasets + $mockDatasets)
        }
    }
    elseif ($mockDatasets.Count -gt 0) {
        Write-Log "Mock script not found at '$mockScriptPath'. Falling back to WhatIf for mock-supported datasets."
        $whatIfDatasets = @($whatIfDatasets + $mockDatasets)
    }

    if ($whatIfDatasets.Count -gt 0) {
        Write-Log "Running WhatIf for datasets without mock coverage..."
        foreach ($dataset in $whatIfDatasets) {
            Write-Log "Would execute: $dataset"
            Invoke-Dataset -Dataset $dataset -OutputRoot $outputDir -WhatIf *>&1 | ForEach-Object {
                Write-Log "  $_"
            }
        }
    }
    
    Write-Log "Dry run completed"
    Update-Status "Dry run completed"
})

# Clear log button handler
$clearLogButton.Add_Click({
    $logTextBox.Clear()
    Write-Log "Log cleared"
})

# Show window
try {
    Initialize-DatasetSelection
}
catch {
    Write-Log "Failed to load datasets from catalog: $($_.Exception.Message)"
}

# Apply persisted config
$persistedConfig = Read-GenesysEnvConfig
if ($null -ne $persistedConfig) {
    Write-Log "Loaded config file: $($script:configPath)"
}
else {
    Write-Log "Config file not found: $($script:configPath)"
}

$configRegion = Get-ConfigString -ConfigObject $persistedConfig -PropertyNames @('region')
if (-not [string]::IsNullOrWhiteSpace($configRegion)) {
    $regionComboBox.Text = $configRegion
    Write-Log "Loaded saved region: $configRegion"
}

# Client ID: GENESYS_CLIENT_ID env var takes precedence over saved config
$envClientId = [string]$env:GENESYS_CLIENT_ID
if (-not [string]::IsNullOrWhiteSpace($envClientId)) {
    $clientIdTextBox.Text = $envClientId
    Write-Log "Client ID loaded from GENESYS_CLIENT_ID environment variable."
}
else {
    $configClientId = Get-ConfigString -ConfigObject $persistedConfig -PropertyNames @('clientId', 'client_id')
    if (-not [string]::IsNullOrWhiteSpace($configClientId)) {
        $clientIdTextBox.Text = $configClientId
        Write-Log "Client ID loaded from config."
    }
}

# Client Secret: GENESYS_CLIENT_SECRET env var takes precedence over saved config
$envClientSecret = [string]$env:GENESYS_CLIENT_SECRET
if (-not [string]::IsNullOrWhiteSpace($envClientSecret)) {
    $clientSecretBox.Password = $envClientSecret
    Write-Log "Client Secret loaded from GENESYS_CLIENT_SECRET environment variable."
}
else {
    $configClientSecret = Get-ConfigString -ConfigObject $persistedConfig -PropertyNames @('clientSecret', 'client_secret')
    if (-not [string]::IsNullOrWhiteSpace($configClientSecret)) {
        $clientSecretBox.Password = $configClientSecret
        Write-Log "Client Secret loaded from config."
    }
}

Write-Log "Genesys.Core GUI loaded"

$hasStartupCredentials = -not [string]::IsNullOrWhiteSpace([string]$clientIdTextBox.Text) -and -not [string]::IsNullOrWhiteSpace([string]$clientSecretBox.Password)
if ($hasStartupCredentials) {
    Write-Log "Credentials detected at startup. Attempting automatic authentication..."
    if (-not (Invoke-UIAuthentication)) {
        Write-Log "Automatic authentication failed. Please review credentials and authenticate manually."
        Update-Status "Ready - Authentication required"
    }
}
else {
    Write-Log "Tip: Set GENESYS_CLIENT_ID and GENESYS_CLIENT_SECRET environment variables, or provide clientId/clientSecret in $($script:configPath)."
    Write-Log "Please authenticate to begin"
    Update-Status "Ready - Please authenticate"
}

$window.ShowDialog() | Out-Null


