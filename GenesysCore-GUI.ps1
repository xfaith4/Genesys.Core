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
    [string]$ModulePath = "$PSScriptRoot/src/ps-module/Genesys.Core/Genesys.Core.psd1"
)

# Verify Windows platform
if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    throw "This GUI requires Windows. WPF is not available on non-Windows platforms."
}

# Import the Genesys.Core module
Import-Module $ModulePath -Force

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

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

# Set default region
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
        (Join-Path -Path $PSScriptRoot -ChildPath 'genesys-core.catalog.json'),
        (Join-Path -Path $PSScriptRoot -ChildPath 'catalog/genesys-core.catalog.json')
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
        throw 'Unable to find genesys-core catalog file.'
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

# Authentication handler
$authButton.Add_Click({
    $clientId = $clientIdTextBox.Text
    $clientSecret = $clientSecretBox.Password
    $region = $regionComboBox.Text
    
    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)) {
        [System.Windows.MessageBox]::Show('Please enter both Client ID and Client Secret.', 'Validation Error', 'OK', 'Warning')
        return
    }
    
    Write-Log "Authenticating with region: $region..."
    Update-Status "Authenticating..."
    
    try {
        $authUrl = "https://login.$region/oauth/token"
        $script:baseUri = "https://api.$region"
        
        $body = @{
            grant_type = 'client_credentials'
            client_id = $clientId
            client_secret = $clientSecret
        }
        
        $authResponse = Invoke-RestMethod -Uri $authUrl -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'
        $script:accessToken = $authResponse.access_token
        $script:headers = @{
            Authorization = "Bearer $($script:accessToken)"
        }
        
        Write-Log "Authentication successful!" "Green"
        $authStatusLabel.Content = "✓ Authenticated"
        $authStatusLabel.Foreground = "Green"
        $runButton.IsEnabled = $true
        Update-Status "Authenticated successfully"
    }
    catch {
        Write-Log "Authentication failed: $($_.Exception.Message)" "Red"
        $authStatusLabel.Content = "✗ Failed"
        $authStatusLabel.Foreground = "Red"
        $runButton.IsEnabled = $false
        Update-Status "Authentication failed"
        [System.Windows.MessageBox]::Show("Authentication failed: $($_.Exception.Message)", 'Authentication Error', 'OK', 'Error')
    }
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
            Write-Log "Browse path '$($rawPath)' is invalid. Falling back to current directory." "Red"
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
        Write-Log "Unable to open folder picker: $($_.Exception.Message)" "Red"
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
    
    try {
        foreach ($dataset in $datasets) {
            Write-Log "Executing dataset: $dataset"
            
            try {
                $runContext = Invoke-Dataset -Dataset $dataset -OutputRoot $outputDir -BaseUri $script:baseUri -Headers $script:headers
                
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
                Write-Log "  ✗ $dataset failed: $($_.Exception.Message)" "Red"
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
    Write-Log "Dry run (WhatIf) for $($datasets.Count) dataset(s)..."
    Write-Log "Planned output root: $outputDir"
    
    foreach ($dataset in $datasets) {
        Write-Log "Would execute: $dataset"
        Invoke-Dataset -Dataset $dataset -OutputRoot $outputDir -WhatIf *>&1 | ForEach-Object {
            Write-Log "  $_"
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
    Write-Log "Failed to load datasets from catalog: $($_.Exception.Message)" "Red"
}

Write-Log "Genesys.Core GUI loaded"
Write-Log "Please authenticate to begin"
Update-Status "Ready - Please authenticate"

$window.ShowDialog() | Out-Null
