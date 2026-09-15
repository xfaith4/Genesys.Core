#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]] $RunFolder,

    [string] $DestinationRoot,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$opsManifest = Join-Path $repoRoot 'modules\Genesys.Ops\Genesys.Ops.psd1'
Import-Module -Name $opsManifest -Force

$results = foreach ($folder in @($RunFolder)) {
    $resolvedRunFolder = (Resolve-Path -Path $folder -ErrorAction Stop).Path
    $manifestPath = Join-Path $resolvedRunFolder 'manifest.json'
    if (-not (Test-Path $manifestPath)) {
        throw "Run folder does not contain manifest.json: $resolvedRunFolder"
    }

    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $outputDirectory = if ($DestinationRoot) {
        $key = [string]$manifest.investigationKey
        $runId = [string]$manifest.runId
        Join-Path (Join-Path $DestinationRoot $key) $runId
    } else {
        Join-Path $resolvedRunFolder 'package'
    }

    Export-GenesysInvestigationPackage -RunFolder $resolvedRunFolder -OutputDirectory $outputDirectory -Force:$Force
}

return @($results)
