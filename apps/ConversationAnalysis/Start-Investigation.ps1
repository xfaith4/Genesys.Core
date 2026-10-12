#Requires -Version 5.1
<#
.SYNOPSIS
Thin launcher for the shared Ops conversation-population investigation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][datetimeoffset]$Since,
    [Parameter(Mandatory)][datetimeoffset]$Until,
    [string[]]$QueueId,
    [string[]]$UserId,
    [string[]]$DivisionId,
    [string[]]$MediaType,
    [string]$QueryFile,
    [string]$InputJsonl,
    [string]$OutputRoot = 'out',
    [switch]$ResolveEntityNames,
    [switch]$OpenReport
)
if (-not (Get-Module Genesys.Ops)) { Import-Module (Join-Path $PSScriptRoot '../../modules/Genesys.Ops/Genesys.Ops.psd1') }
$arguments = @{ Since = $Since; Until = $Until; OutputRoot = $OutputRoot; OpenReport = $OpenReport; ResolveEntityNames = $ResolveEntityNames }
if ($InputJsonl) {
    if ($QueryFile -or $QueueId -or $UserId -or $DivisionId -or $MediaType) { throw 'InputJsonl cannot be combined with collection filters.' }
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in [IO.File]::ReadLines((Resolve-Path $InputJsonl).Path)) { if ($line.Trim()) { $records.Add(($line | ConvertFrom-Json)) } }
    $arguments.InputObject = $records.ToArray()
}
else {
    foreach ($key in @('QueueId','UserId','DivisionId','MediaType')) { if ($PSBoundParameters.ContainsKey($key)) { $arguments[$key] = $PSBoundParameters[$key] } }
    if ($QueryFile) {
        $query = Get-Content $QueryFile -Raw | ConvertFrom-Json
        $body = @{}; foreach ($property in $query.PSObject.Properties) { $body[$property.Name] = $property.Value }
        $arguments.QueryBody = $body
    }
}
Get-GenesysConversationAnalysis @arguments
