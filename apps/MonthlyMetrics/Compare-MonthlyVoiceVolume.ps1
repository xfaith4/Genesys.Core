#Requires -Version 5.1
<#
.SYNOPSIS
Thin launcher for the shared Genesys.Ops monthly voice-volume investigation.
.DESCRIPTION
Connect-GenesysCloud must already have been called in this PowerShell session.
Use -OpenReport to open the generated report in the default browser.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Year,
    [Parameter(Mandatory)][int]$Month,
    [string]$TimeZoneId = 'UTC',
    [string[]]$DivisionId,
    [string[]]$QueueId,
    [string]$OrganizationId,
    [string]$OutputRoot = 'out',
    [switch]$OpenReport
)
if (-not (Get-Module Genesys.Ops)) {
    Import-Module (Join-Path $PSScriptRoot '../../modules/Genesys.Ops/Genesys.Ops.psd1') -ErrorAction Stop
}
$arguments = @{}
foreach ($key in $PSBoundParameters.Keys) {
    if ($key -ne 'OpenReport') { $arguments[$key] = $PSBoundParameters[$key] }
}
$report = Compare-GenesysMonthlyVoiceVolume @arguments
if ($OpenReport) { Invoke-Item (Join-Path $report.runFolder 'report.html') }
$report
