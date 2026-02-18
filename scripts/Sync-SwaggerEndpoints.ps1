[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SwaggerPath,

    [string]$CatalogPath = './genesys-core.catalog.json',

    [switch]$WriteLegacyCopy
)

function ConvertTo-PlainHashtable {
    param([Parameter(Mandatory = $true)][object]$InputObject)

    $result = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }

    return $result
}

function Get-DenylistOperationIds {
    param([Parameter(Mandatory = $true)][string]$SwaggerDirectory)

    $denylistPath = Join-Path -Path $SwaggerDirectory -ChildPath 'denylist.operationIds.txt'
    if (-not (Test-Path -Path $denylistPath)) {
        return @{}
    }

    $ids = @{}
    foreach ($line in Get-Content -Path $denylistPath) {
        $trimmed = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }
        if ($trimmed.StartsWith('#')) {
            continue
        }

        $ids[$trimmed] = $true
    }

    return $ids
}

function Resolve-SwaggerSchema {
    param(
        [Parameter(Mandatory = $true)][object]$Schema,
        [Parameter(Mandatory = $true)][hashtable]$Definitions,
        [int]$Depth = 0
    )

    if ($null -eq $Schema -or $Depth -gt 8) {
        return $null
    }

    if ($Schema.PSObject.Properties.Name -contains '$ref') {
        $refValue = [string]$Schema.'$ref'
        if ($refValue.StartsWith('#/definitions/')) {
            $definitionKey = $refValue.Substring(14)
            if ($Definitions.ContainsKey($definitionKey)) {
                return Resolve-SwaggerSchema -Schema $Definitions[$definitionKey] -Definitions $Definitions -Depth ($Depth + 1)
            }
        }

        return $Schema
    }

    if ($Schema.PSObject.Properties.Name -contains 'allOf') {
        foreach ($entry in @($Schema.allOf)) {
            $resolved = Resolve-SwaggerSchema -Schema $entry -Definitions $Definitions -Depth ($Depth + 1)
            if ($null -ne $resolved -and $resolved.PSObject.Properties.Name -contains 'properties') {
                return $resolved
            }
        }
    }

    return $Schema
}

function Get-ItemsPathFromOperation {
    param(
        [Parameter(Mandatory = $true)][object]$Operation,
        [Parameter(Mandatory = $true)][hashtable]$Definitions
    )

    $responseCodes = @('200', '201', '202')
    foreach ($code in $responseCodes) {
        if ($Operation.responses.PSObject.Properties.Name -notcontains $code) {
            continue
        }

        $response = $Operation.responses.$code
        if ($null -eq $response -or $response.PSObject.Properties.Name -notcontains 'schema') {
            continue
        }

        $schema = Resolve-SwaggerSchema -Schema $response.schema -Definitions $Definitions
        if ($null -eq $schema) {
            continue
        }

        if ($schema.PSObject.Properties.Name -contains 'type' -and [string]$schema.type -eq 'array') {
            return '$'
        }

        if ($schema.PSObject.Properties.Name -contains 'properties') {
            $properties = $schema.properties
            foreach ($candidate in @('entities', 'results', 'items')) {
                if ($properties.PSObject.Properties.Name -contains $candidate) {
                    $propertyValue = $properties.$candidate
                    if ($propertyValue.PSObject.Properties.Name -contains 'type') {
                        if ([string]$propertyValue.type -eq 'array') {
                            return "$.$($candidate)"
                        }
                    }
                    elseif ($propertyValue.PSObject.Properties.Name -contains 'items') {
                        return "$.$($candidate)"
                    }
                }
            }
        }
    }

    return '$'
}

if (-not (Test-Path -Path $SwaggerPath)) {
    throw "Swagger file not found: $($SwaggerPath)"
}
if (-not (Test-Path -Path $CatalogPath)) {
    throw "Catalog file not found: $($CatalogPath)"
}

$resolvedSwaggerPath = (Resolve-Path -Path $SwaggerPath).Path
$resolvedCatalogPath = (Resolve-Path -Path $CatalogPath).Path

$swagger = Get-Content -Path $resolvedSwaggerPath -Raw | ConvertFrom-Json -Depth 100
if ($swagger.PSObject.Properties.Name -contains 'swagger') {
    if ([string]$swagger.swagger -ne '2.0') {
        Write-Warning "Swagger version '$($swagger.swagger)' detected; expected 2.0. Continuing best-effort parsing."
    }
}

$definitions = @{}
if ($swagger.PSObject.Properties.Name -contains 'definitions' -and $null -ne $swagger.definitions) {
    foreach ($property in $swagger.definitions.PSObject.Properties) {
        $definitions[$property.Name] = $property.Value
    }
}

$denylist = Get-DenylistOperationIds -SwaggerDirectory (Split-Path -Path $resolvedSwaggerPath -Parent)
$generatedEndpoints = @{}
$totalSwaggerOps = 0

$allowedMethods = @('get', 'post', 'put', 'patch', 'delete')
foreach ($pathProperty in $swagger.paths.PSObject.Properties) {
    $pathValue = $pathProperty.Value
    foreach ($methodProperty in $pathValue.PSObject.Properties) {
        $methodLower = ([string]$methodProperty.Name).ToLowerInvariant()
        if ($allowedMethods -notcontains $methodLower) {
            continue
        }

        $operation = $methodProperty.Value
        $operationId = [string]$operation.operationId
        if ([string]::IsNullOrWhiteSpace($operationId)) {
            continue
        }

        if ($denylist.ContainsKey($operationId)) {
            continue
        }

        $totalSwaggerOps += 1
        $itemsPath = Get-ItemsPathFromOperation -Operation $operation -Definitions $definitions

        $endpoint = [ordered]@{
            method = $methodLower.ToUpperInvariant()
            path = [string]$pathProperty.Name
            itemsPath = $itemsPath
            pagingProfile = 'none'
            retryProfile = 'default'
            operationId = $operationId
        }

        if ($operation.PSObject.Properties.Name -contains 'tags') {
            $endpoint.tags = @($operation.tags)
        }
        if ($operation.PSObject.Properties.Name -contains 'summary' -and [string]::IsNullOrWhiteSpace([string]$operation.summary) -eq $false) {
            $endpoint.summary = [string]$operation.summary
        }
        if ($operation.PSObject.Properties.Name -contains 'description' -and [string]::IsNullOrWhiteSpace([string]$operation.description) -eq $false) {
            $endpoint.description = [string]$operation.description
        }

        $generatedEndpoints[$operationId] = $endpoint
    }
}

$catalog = Get-Content -Path $resolvedCatalogPath -Raw | ConvertFrom-Json -Depth 100
if ($null -eq $catalog.endpoints) {
    $catalog | Add-Member -MemberType NoteProperty -Name endpoints -Value ([ordered]@{})
}

$catalogEndpoints = ConvertTo-PlainHashtable -InputObject $catalog.endpoints
$addedCount = 0
$skippedExistingCount = 0
foreach ($operationId in $generatedEndpoints.Keys) {
    if ($catalogEndpoints.ContainsKey($operationId)) {
        $skippedExistingCount += 1
        continue
    }

    $catalogEndpoints[$operationId] = $generatedEndpoints[$operationId]
    $addedCount += 1
}

$missingAfterMergeCount = 0
foreach ($operationId in $generatedEndpoints.Keys) {
    if (-not $catalogEndpoints.ContainsKey($operationId)) {
        $missingAfterMergeCount += 1
    }
}

$totalCatalogEndpoints = $catalogEndpoints.Keys.Count
$report = [pscustomobject]@{
    totalSwaggerOps = $totalSwaggerOps
    totalCatalogEndpoints = $totalCatalogEndpoints
    addedCount = $addedCount
    skippedExistingCount = $skippedExistingCount
    missingAfterMergeCount = $missingAfterMergeCount
}

if ($PSCmdlet.ShouldProcess($resolvedCatalogPath, 'Sync swagger operations into catalog endpoints')) {
    $catalog.endpoints = [pscustomobject]$catalogEndpoints
    $catalog.generatedAt = [DateTime]::UtcNow.ToString('o')

    $catalogJson = $catalog | ConvertTo-Json -Depth 100
    Set-Content -Path $resolvedCatalogPath -Value $catalogJson -Encoding UTF8

    if ($WriteLegacyCopy) {
        $legacyPath = Join-Path -Path (Split-Path -Path $resolvedCatalogPath -Parent) -ChildPath 'catalog/genesys-core.catalog.json'
        $legacyDir = Split-Path -Path $legacyPath -Parent
        if (-not (Test-Path -Path $legacyDir)) {
            New-Item -Path $legacyDir -ItemType Directory -Force | Out-Null
        }

        Set-Content -Path $legacyPath -Value $catalogJson -Encoding UTF8
    }
}

return $report
