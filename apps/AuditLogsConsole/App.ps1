#Requires -Version 5.1
Set-StrictMode -Version Latest

$appRoot = $PSScriptRoot
if (-not $appRoot) {
    $appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Web

Import-Module (Join-Path $appRoot 'App.CoreAdapter.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $appRoot 'App.RunData.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $appRoot 'App.Export.psm1') -Force -ErrorAction Stop

function Resolve-AppPath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$RelativePath
    )

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $RelativePath))
}

$settingsPath = Join-Path $appRoot 'App.Settings.psd1'
if (-not [System.IO.File]::Exists($settingsPath)) {
    throw "Settings file not found: $settingsPath"
}

$settings = Import-PowerShellDataFile -Path $settingsPath
$resolvedSettings = [ordered]@{
    AppRoot        = $appRoot
    CoreModulePath = Resolve-AppPath -BasePath $appRoot -RelativePath $settings.CoreModuleRelativePath
    AuthModulePath = Resolve-AppPath -BasePath $appRoot -RelativePath $settings.AuthModuleRelativePath
    CatalogPath    = Resolve-AppPath -BasePath $appRoot -RelativePath $settings.CatalogRelativePath
    SchemaPath     = Resolve-AppPath -BasePath $appRoot -RelativePath $settings.SchemaRelativePath
    OutputRoot     = Resolve-AppPath -BasePath $appRoot -RelativePath $settings.OutputRelativePath
    DatasetKeys    = $settings.DatasetKeys
    Preview        = $settings.Preview
    Ui             = $settings.Ui
}

$script:AppContext = [ordered]@{
    Settings          = [pscustomobject]$resolvedSettings
    StartupValidation = [pscustomobject]@{
        Ready   = $false
        Message = 'Startup validation has not completed.'
        Error   = $null
    }
}

try {
    Initialize-CoreIntegration `
        -CoreModulePath $resolvedSettings.CoreModulePath `
        -AuthModulePath $resolvedSettings.AuthModulePath `
        -CatalogPath    $resolvedSettings.CatalogPath `
        -SchemaPath     $resolvedSettings.SchemaPath `
        -OutputRoot     $resolvedSettings.OutputRoot `
        -DatasetKeys    $resolvedSettings.DatasetKeys `
        -PreviewConfig  $resolvedSettings.Preview | Out-Null

    $script:AppContext.StartupValidation = [pscustomobject]@{
        Ready   = $true
        Message = 'Genesys.Core imported and catalog validated successfully.'
        Error   = $null
    }
}
catch {
    $script:AppContext.StartupValidation = [pscustomobject]@{
        Ready   = $false
        Message = 'Startup validation failed. Run actions are disabled until the Core paths and catalog are fixed.'
        Error   = $_.Exception.Message
    }
}

$xamlPath = Join-Path $appRoot 'XAML\MainWindow.xaml'
$xamlContent = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
$reader = New-Object System.IO.StringReader($xamlContent)
$xmlReader = [System.Xml.XmlReader]::Create($reader)
try {
    $script:Window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
}
finally {
    $xmlReader.Dispose()
    $reader.Dispose()
}

. (Join-Path $appRoot 'App.UI.ps1')

$script:Window.Add_Closing({
    if ($null -ne $script:State.PollTimer) {
        try { $script:State.PollTimer.Stop() } catch { }
    }
    if ($null -ne $script:State.RunPowerShell) {
        try { $script:State.RunPowerShell.Dispose() } catch { }
    }
})

$script:Window.ShowDialog() | Out-Null
