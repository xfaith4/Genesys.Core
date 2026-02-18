[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SwaggerPath,
    [string]$SwaggerUrl = 'https://api.mypurecloud.com/api/v2/docs/swagger',
    [string]$CatalogPath = './genesys-core.catalog.json',
    [switch]$WriteLegacyCopy,
    [switch]$RunValidation
)

$repoRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
$getScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-GenesysSwagger.ps1'
$syncScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Sync-SwaggerEndpoints.ps1'

$swaggerParams = @{}
if ([string]::IsNullOrWhiteSpace([string]$SwaggerPath) -eq $false) {
    $swaggerParams.SwaggerPath = $SwaggerPath
}
else {
    $swaggerParams.SwaggerUrl = $SwaggerUrl
}

$swaggerLocalPath = & $getScriptPath @swaggerParams

$syncParams = @{
    SwaggerPath = $swaggerLocalPath
    CatalogPath = $CatalogPath
    WriteLegacyCopy = $WriteLegacyCopy
}

if ($WhatIfPreference) {
    $syncParams.WhatIf = $true
}

$report = & $syncScriptPath @syncParams

Write-Host "Swagger sync report: totalSwaggerOps=$($report.totalSwaggerOps); totalCatalogEndpoints=$($report.totalCatalogEndpoints); addedCount=$($report.addedCount); skippedExistingCount=$($report.skippedExistingCount); missingAfterMergeCount=$($report.missingAfterMergeCount)"

if ($RunValidation) {
    Import-Module (Join-Path -Path $repoRoot -ChildPath 'src/ps-module/Genesys.Core/Genesys.Core.psd1') -Force
    $schemaPath = Join-Path -Path $repoRoot -ChildPath 'catalog/schema/genesys-core.catalog.schema.json'

    Assert-Catalog -CatalogPath $CatalogPath -SchemaPath $schemaPath | Out-Null

    $coveragePath = Join-Path -Path $repoRoot -ChildPath 'tests/SwaggerCoverage.Tests.ps1'
    Invoke-Pester -Path $coveragePath | Out-Null
}

return $report
