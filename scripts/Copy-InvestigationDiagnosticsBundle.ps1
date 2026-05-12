#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]] $RunFolder,

    [string] $OutputPath,

    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$opsManifest = Join-Path $repoRoot 'modules\Genesys.Ops\Genesys.Ops.psd1'
Import-Module -Name $opsManifest -Force

if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'out\investigation-diagnostics.json'
}

$result = Export-GenesysInvestigationDiagnosticsBundle -RunFolder $RunFolder -OutputPath $OutputPath -PassThru
$clipboardCopied = $false
if (Get-Command -Name Set-Clipboard -ErrorAction SilentlyContinue) {
    $result.Json | Set-Clipboard
    $clipboardCopied = $true
}

$output = [pscustomobject]@{
    OutputPath       = $result.OutputPath
    ClipboardCopied  = $clipboardCopied
    RunCount         = @($result.Bundle.runs).Count
}

if ($PassThru) {
    return [pscustomobject]@{
        OutputPath       = $result.OutputPath
        ClipboardCopied  = $clipboardCopied
        RunCount         = @($result.Bundle.runs).Count
        Json             = $result.Json
        Bundle           = $result.Bundle
    }
}

return $output
