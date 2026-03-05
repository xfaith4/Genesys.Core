[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Dataset,
    [string]$CatalogPath,
    [string]$OutputRoot = 'out',
    [string]$BaseUri = 'https://api.mypurecloud.com',
    [hashtable]$Headers,
    [scriptblock]$RequestInvoker,
    [hashtable]$DatasetParameters,
    [switch]$StrictCatalog,
    [switch]$NoRedact
)

Write-Warning '[Genesys.Core] src/ps-module/Public/Invoke-Dataset.ps1 is deprecated. Use modules/Genesys.Core/Public/Invoke-Dataset.ps1.'
$target = Join-Path $PSScriptRoot '../../../../modules/Genesys.Core/Public/Invoke-Dataset.ps1'
if (-not (Test-Path $target)) {
    throw "Canonical Invoke-Dataset script not found at '$target'."
}

if ($PSBoundParameters.ContainsKey('Dataset')) {
    & $target -Dataset $Dataset -CatalogPath $CatalogPath -OutputRoot $OutputRoot -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -StrictCatalog:$StrictCatalog -NoRedact:$NoRedact -WhatIf:$WhatIfPreference
}
