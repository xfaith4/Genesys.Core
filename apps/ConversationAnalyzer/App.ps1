#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Genesys Conversation Analysis – entry point.
.DESCRIPTION
    1. Loads WPF assemblies.
    2. Imports app modules (never Genesys.Core directly – Gate D).
    3. Resolves Core paths from config + env overrides.
    4. Attempts Initialize-CoreAdapter (Gate A – non-fatal; user can fix via Settings).
    5. Loads XAML\MainWindow.xaml.
    6. Dot-sources App.UI.ps1.
    7. Wires Window.Closing to persist last date/time filters.
    8. Runs the WPF message loop.
#>

$AppDir = $PSScriptRoot
if (-not $AppDir) { $AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ── 1. WPF assemblies ─────────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName Microsoft.Win32.Primitives  -ErrorAction SilentlyContinue

# ── 2. Import app modules ─────────────────────────────────────────────────────
# Order matters: Config → CoreAdapter → Index → Export → Reporting → Database
# Authentication is handled by Genesys.Auth in the sibling Genesys.Core repo (Gate E below).
Import-Module (Join-Path $AppDir 'modules\App.Config.psm1')      -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'modules\App.CoreAdapter.psm1')  -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'modules\App.Index.psm1')        -Force -ErrorAction Stop -DisableNameChecking
Import-Module (Join-Path $AppDir 'modules\App.Export.psm1')       -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'modules\App.Reporting.psm1')    -Force -ErrorAction Stop
Import-Module (Join-Path $AppDir 'modules\App.Database.psm1')     -Force -ErrorAction Stop

# ── Bootstrap: auto-clone Genesys.Core if it has never been set up ───────────
#
# Clones from GitHub into the sibling directory, then updates $corePath /
# $catalogPath / $schemaPath via [ref] params and saves the resolved paths to
# config so the bootstrap never runs again on this machine.
#
# Falls back to a ZIP download when git is not installed.

function _InvokeCoreBootstrap {
    param(
        [string]$SiblingRoot,
        [string]$RepoUrl,
        [ref]$CorePath,
        [ref]$CatalogPath,
        [ref]$SchemaPath
    )

    $confirmMsg = "Genesys.Core was not found at the expected location.`n`n" +
                  "The app can clone it automatically from GitHub.`n`n" +
                  "  Repository : $RepoUrl`n" +
                  "  Destination: $SiblingRoot`n`n" +
                  "Clone now?"

    $r = [System.Windows.MessageBox]::Show(
        $confirmMsg, 'Genesys.Core – First-Time Setup',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return $false }

    # ── Progress window ───────────────────────────────────────────────────────
    $wnd = New-Object System.Windows.Window
    $wnd.Title  = 'Genesys.Core – Setting Up…'
    $wnd.Width  = 440; $wnd.Height = 110
    $wnd.WindowStartupLocation = 'CenterScreen'
    $wnd.ResizeMode  = 'NoResize'
    $wnd.WindowStyle = 'ToolWindow'

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.VerticalAlignment   = 'Center'
    $panel.HorizontalAlignment = 'Center'
    $panel.Margin = [System.Windows.Thickness]::new(20)

    $lbl1 = New-Object System.Windows.Controls.TextBlock
    $lbl1.Text = 'Cloning Genesys.Core from GitHub…  please wait.'
    $lbl1.HorizontalAlignment = 'Center'

    $lbl2 = New-Object System.Windows.Controls.TextBlock
    $lbl2.Text = $RepoUrl
    $lbl2.HorizontalAlignment = 'Center'
    $lbl2.FontSize  = 10
    $lbl2.Foreground = [System.Windows.Media.Brushes]::Gray
    $lbl2.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)

    $panel.Children.Add($lbl1) | Out-Null
    $panel.Children.Add($lbl2) | Out-Null
    $wnd.Content = $panel

    # ── Clone in a background runspace ────────────────────────────────────────
    $useGit = $null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    if ($useGit) {
        $ps.AddScript({
            param($url, $dest)
            $out = & git clone $url $dest 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out -join "`n") }
        }).AddArgument($RepoUrl).AddArgument($SiblingRoot) | Out-Null
    } else {
        $ps.AddScript({
            param($url, $dest)
            $zipUrl = ($url -replace '\.git$', '') + '/archive/refs/heads/main.zip'
            $tmpZip = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'GenesysCore_bootstrap.zip')
            $tmpDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'GenesysCore_extract')
            try {
                (New-Object System.Net.WebClient).DownloadFile($zipUrl, $tmpZip)
                if ([System.IO.Directory]::Exists($tmpDir)) { [System.IO.Directory]::Delete($tmpDir, $true) }
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory($tmpZip, $tmpDir)
                $dirs = [System.IO.Directory]::GetDirectories($tmpDir)
                if ($dirs.Count -eq 0) {
                    throw 'Archive appears empty – no subdirectory found after extraction.'
                }
                $extracted = $dirs[0]
                if ([System.IO.Directory]::Exists($dest)) { [System.IO.Directory]::Delete($dest, $true) }
                [System.IO.Directory]::Move($extracted, $dest)
                [pscustomobject]@{ ExitCode = 0; Output = 'Downloaded and extracted.' }
            } catch {
                [pscustomobject]@{ ExitCode = 1; Output = [string]$_ }
            } finally {
                Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
                Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }).AddArgument($RepoUrl).AddArgument($SiblingRoot) | Out-Null
    }

    $asyncJob = $ps.BeginInvoke()

    # DispatcherTimer closes the progress window when the job finishes.
    # ShowDialog() runs its own message loop so the timer fires correctly.
    # A 10-minute hard timeout prevents the dialog hanging if the network stalls.
    $script:_bootstrapResult = $null
    $capturedJob     = $asyncJob
    $capturedPs      = $ps
    $capturedWnd     = $wnd
    $capturedTimeout = [datetime]::UtcNow.AddMinutes(10)

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromMilliseconds(400)
    $timer.Add_Tick({
        if ([datetime]::UtcNow -gt $capturedTimeout) {
            $timer.Stop()
            $script:_bootstrapResult = [pscustomobject]@{
                ExitCode = 1
                Output   = 'Timed out after 10 minutes. Check your network connection.'
            }
            $capturedWnd.Close()
            return
        }
        if ($capturedJob.IsCompleted) {
            $timer.Stop()
            $script:_bootstrapResult = $capturedPs.EndInvoke($capturedJob)
            $capturedWnd.Close()
        }
    })
    $timer.Start()
    $wnd.ShowDialog() | Out-Null

    try { $rs.Close()   } catch { }
    try { $rs.Dispose() } catch { }
    try { $ps.Dispose() } catch { }
    $result = $script:_bootstrapResult
    $script:_bootstrapResult = $null

    if ($null -eq $result -or $result.ExitCode -ne 0) {
        $detail = if ($null -ne $result) { $result.Output } else { 'Unknown error.' }
        [System.Windows.MessageBox]::Show(
            "Could not set up Genesys.Core:`n`n$detail`n`nYou can configure paths manually via Settings.",
            'Genesys.Core Setup – Failed',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return $false
    }

    $CorePath.Value    = [System.IO.Path]::Combine($SiblingRoot, 'modules', 'Genesys.Core', 'Genesys.Core.psd1')
    $CatalogPath.Value = [System.IO.Path]::Combine($SiblingRoot, 'catalog', 'genesys.catalog.json')
    $SchemaPath.Value  = [System.IO.Path]::Combine($SiblingRoot, 'catalog', 'schema', 'genesys.catalog.schema.json')
    return $true
}

# ── 3. Resolve Core paths (env overrides take precedence) ────────────────────
$cfg = Get-AppConfig

$corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $cfg.CoreModulePath }
$catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $cfg.CatalogPath    }
$schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $cfg.SchemaPath     }
$outputRoot  = $cfg.OutputRoot

# ── 3b. Bootstrap: clone Genesys.Core if module file is missing ──────────────
# Triggers only when: (a) the resolved module file does not exist AND
#                     (b) the sibling Genesys.Core directory does not exist.
# If the sibling already exists but the path is wrong, Gate A will fail and
# the user can fix via Settings → Browse.
if (-not [System.IO.File]::Exists($corePath)) {
    $siblingRoot = Get-CoreSiblingRoot
    if (-not [System.IO.Directory]::Exists($siblingRoot)) {
        $bootstrapped = _InvokeCoreBootstrap `
            -SiblingRoot $siblingRoot `
            -RepoUrl     'https://github.com/your-org/Genesys.Core.git' `
            -CorePath    ([ref]$corePath) `
            -CatalogPath ([ref]$catalogPath) `
            -SchemaPath  ([ref]$schemaPath)

        if ($bootstrapped) {
            # Persist the resolved paths so this never runs again on this machine
            $cfgB = Get-AppConfig
            $cfgB | Add-Member -NotePropertyName 'CoreModulePath' -NotePropertyValue $corePath    -Force
            $cfgB | Add-Member -NotePropertyName 'CatalogPath'    -NotePropertyValue $catalogPath -Force
            $cfgB | Add-Member -NotePropertyName 'SchemaPath'     -NotePropertyValue $schemaPath  -Force
            Save-AppConfig -Config $cfgB
        }
    }
}

# ── 4. Gate E: Import Genesys.Auth from sibling Core repo (non-fatal) ────────
$script:AuthModuleWarning = ''
$authModPath = [System.IO.Path]::Combine((Get-CoreSiblingRoot), 'modules', 'Genesys.Auth', 'Genesys.Auth.psm1')
try {
    Import-Module $authModPath -Force -ErrorAction Stop
} catch {
    $script:AuthModuleWarning = "Auth module unavailable: $_"
    Write-Warning $script:AuthModuleWarning
}

# ── 4b. Gate A: Initialize CoreAdapter (non-fatal – user can fix via Settings) ─
$script:CoreInitError = ''
try {
    Initialize-CoreAdapter `
        -CoreModulePath $corePath `
        -CatalogPath    $catalogPath `
        -OutputRoot     $outputRoot `
        -SchemaPath     $schemaPath
} catch {
    $script:CoreInitError = [string]$_
    Write-Warning "Gate A – CoreAdapter init failed: $script:CoreInitError"
}

# ── 4c. Gate F: Initialize Database (non-fatal – missing DLL shown in status bar) ──
$script:DatabaseWarning = ''
try {
    Initialize-Database `
        -DatabasePath  $cfg.DatabasePath `
        -SqliteDllPath $cfg.SqliteDllPath `
        -AppDir        $AppDir

    # First-launch convenience: create a default case and activate it so
    # conversation-detail runs accumulate in one place without the user having
    # to open Case Manager first.
    $defaultCaseId = New-DefaultCaseIfEmpty
    if ($defaultCaseId) {
        $cfg | Add-Member -NotePropertyName 'ActiveCaseId' -NotePropertyValue $defaultCaseId -Force
        Save-AppConfig -Config $cfg
    }
} catch {
    $script:DatabaseWarning = "Case store unavailable: $_"
    Write-Warning $script:DatabaseWarning
}

# ── 5. Load XAML ──────────────────────────────────────────────────────────────
$xamlPath = Join-Path $AppDir 'resources\MainWindow.xaml'
if (-not [System.IO.File]::Exists($xamlPath)) {
    [System.Windows.MessageBox]::Show(
        "XAML file not found: $xamlPath",
        'Startup Error') | Out-Null
    exit 1
}

$xamlContent = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
# Remove x:Class attribute so WPF doesn't try to find a compiled backing class
$xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''

$reader = New-Object System.IO.StringReader($xamlContent)
$xmlReader = [System.Xml.XmlReader]::Create($reader)
try {
    $script:Window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
} catch {
    [System.Windows.MessageBox]::Show(
        "Failed to load XAML: $_",
        'Startup Error') | Out-Null
    exit 1
} finally {
    $xmlReader.Dispose()
    $reader.Dispose()
}

# ── 6. Dot-source App.UI.ps1 ─────────────────────────────────────────────────
. (Join-Path $AppDir 'scripts\App.UI.ps1')

# ── 7. Wire Window.Closing – persist dates and stop background run ────────────
$script:Window.Add_Closing({
    param($sender, $e)

    # Stop polling timer
    if ($null -ne $script:State.PollingTimer) {
        try { $script:State.PollingTimer.Stop() } catch { }
    }

    # Cancel any in-progress PKCE auth flow
    if ($null -ne $script:State.PkceCancel) {
        try { $script:State.PkceCancel.Cancel()  } catch { }
        try { $script:State.PkceCancel.Dispose() } catch { }
        $script:State.PkceCancel = $null
    }

    # Stop background runspace
    if ($null -ne $script:State.BackgroundRunJob) {
        try { $script:State.BackgroundRunJob.Ps.Stop() } catch { }
    }
    if ($null -ne $script:State.BackgroundRunspace) {
        try { $script:State.BackgroundRunspace.Close() } catch { }
    }

    # Stop any in-progress background import
    if ($null -ne $script:State.AutoImportTimer) {
        try { $script:State.AutoImportTimer.Stop() } catch { }
        $script:State.AutoImportTimer = $null
    }
    if ($null -ne $script:State.AutoImportJob) {
        try { $script:State.AutoImportJob.Ps.Stop() } catch { }
        $script:State.AutoImportJob = $null
    }
    if ($null -ne $script:State.AutoImportRunspace) {
        try { $script:State.AutoImportRunspace.Close()   } catch { }
        try { $script:State.AutoImportRunspace.Dispose() } catch { }
        $script:State.AutoImportRunspace = $null
    }

    # Persist last query range
    try {
        $startDate = $script:DtpStartDate.SelectedDate
        $endDate   = $script:DtpEndDate.SelectedDate
        $cfg2 = Get-AppConfig
        if ($null -ne $startDate) {
            $cfg2 | Add-Member -NotePropertyName 'LastStartDate' -NotePropertyValue $startDate.ToString('o') -Force
        }
        if ($null -ne $endDate) {
            $cfg2 | Add-Member -NotePropertyName 'LastEndDate' -NotePropertyValue $endDate.ToString('o') -Force
        }
        $cfg2 | Add-Member -NotePropertyName 'LastStartTime' -NotePropertyValue $script:TxtStartTime.Text.Trim() -Force
        $cfg2 | Add-Member -NotePropertyName 'LastEndTime' -NotePropertyValue $script:TxtEndTime.Text.Trim() -Force
        Save-AppConfig -Config $cfg2
    } catch { <# non-fatal #> }
})

# ── 8. Run WPF message loop ───────────────────────────────────────────────────
$script:Window.ShowDialog() | Out-Null
