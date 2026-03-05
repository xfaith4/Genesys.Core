#Requires -Version 5.1
<#
.SYNOPSIS
    Back-compatibility shim. This module has moved to modules/Genesys.Ops/Genesys.Ops.psm1.
.DESCRIPTION
    Importing GenesysOps from the repo root is still supported but deprecated.
    All cmdlets are proxied from the new modules/Genesys.Ops lane module.
    Update your imports to: Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1
#>

Write-Warning '[GenesysOps] The root GenesysOps module is a back-compat shim. ' +
    'Please update your import to: Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1'

$opsModulePath = Join-Path $PSScriptRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
if (-not (Test-Path $opsModulePath)) {
    throw "Genesys.Ops module not found at '$opsModulePath'. Repository structure may be incomplete."
}

Import-Module $opsModulePath -Global -Force -ErrorAction Stop
