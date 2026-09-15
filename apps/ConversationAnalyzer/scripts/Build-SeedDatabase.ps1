#Requires -Version 5.1
<#
.SYNOPSIS
    Generates lib\cases.seed.sqlite — the pre-built SQLite case store shipped
    with the Conversation Analyzer.

.DESCRIPTION
    On first launch, the app copies this file to the user's LOCALAPPDATA DB path
    instead of executing the full schema DDL at runtime. Initialize-Database then
    runs its idempotent _ApplySchema pass to apply any newer migrations.

    Re-run this script whenever the schema changes so the committed seed stays
    in sync with $script:SchemaVersion inside App.Database.psm1.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-SeedDatabase.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppDir  = Split-Path -Parent $PSScriptRoot
$LibDir  = Join-Path $AppDir 'lib'
$Seed    = Join-Path $LibDir 'cases.seed.sqlite'

Import-Module (Join-Path $AppDir 'modules\App.Database.psm1') -Force

if ([System.IO.File]::Exists($Seed)) {
    Remove-Item $Seed -Force
}

Initialize-Database -DatabasePath $Seed -AppDir $AppDir

$bytes = (Get-Item $Seed).Length
Write-Host "Wrote $Seed ($bytes bytes)"
