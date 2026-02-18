[CmdletBinding()]
param(
    [string]$SwaggerPath,
    [string]$SwaggerUrl = 'https://api.mypurecloud.com/api/v2/docs/swagger',
    [string]$OutputPath = 'generated/swagger/swagger.json'
)

if ([string]::IsNullOrWhiteSpace([string]$SwaggerPath) -and [string]::IsNullOrWhiteSpace([string]$SwaggerUrl)) {
    throw 'Specify either -SwaggerPath or -SwaggerUrl.'
}

$targetDirectory = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace([string]$targetDirectory) -eq $false -and -not (Test-Path -Path $targetDirectory)) {
    New-Item -Path $targetDirectory -ItemType Directory -Force | Out-Null
}

$sourceValue = $null
if ([string]::IsNullOrWhiteSpace([string]$SwaggerPath) -eq $false) {
    if (-not (Test-Path -Path $SwaggerPath)) {
        throw "SwaggerPath not found: $($SwaggerPath)"
    }

    $resolvedSwaggerPath = (Resolve-Path -Path $SwaggerPath).Path
    Copy-Item -Path $resolvedSwaggerPath -Destination $OutputPath -Force
    $sourceValue = $resolvedSwaggerPath
}
else {
    $sourceValue = $SwaggerUrl
    Invoke-WebRequest -Uri $SwaggerUrl -UseBasicParsing -OutFile $OutputPath
}

$resolvedOutputPath = (Resolve-Path -Path $OutputPath).Path
$item = Get-Item -Path $resolvedOutputPath

$metadataPath = Join-Path -Path (Split-Path -Path $resolvedOutputPath -Parent) -ChildPath 'swagger.metadata.json'
$metadata = [ordered]@{
    downloadedAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceUrl = $sourceValue
    bytes = [int64]$item.Length
}

$metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath -Encoding UTF8

return $resolvedOutputPath
