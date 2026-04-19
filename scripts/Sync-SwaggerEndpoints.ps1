[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SwaggerPath,

    [string]$CatalogPath = './catalog/genesys.catalog.json',

    [switch]$WriteLegacyCopy
)

function ConvertTo-PlainHashtable {
    param([Parameter(Mandatory = $true)][object]$InputObject)

    $result = New-StringDictionary -CaseInsensitive
    foreach ($entry in Get-JsonMapEntries -InputObject $InputObject) {
        if ($result.ContainsKey($entry.Name)) {
            $existingKey = Get-MatchingDictionaryKey -Dictionary $result -Key $entry.Name
            if ($existingKey -cne $entry.Name) {
                throw "Catalog endpoint keys '$existingKey' and '$($entry.Name)' differ only by case. The runtime catalog must remain loadable by case-insensitive PowerShell JSON readers."
            }
        }

        $result[$entry.Name] = $entry.Value
    }

    return $result
}

function New-StringDictionary {
    param([switch]$CaseInsensitive)

    $comparer = [System.StringComparer]::Ordinal
    if ($CaseInsensitive) {
        $comparer = [System.StringComparer]::OrdinalIgnoreCase
    }

    return [System.Collections.Generic.Dictionary[string, object]]::new($comparer)
}

function Get-MatchingDictionaryKey {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Dictionary,
        [Parameter(Mandatory = $true)][string]$Key
    )

    foreach ($existingKey in $Dictionary.Keys) {
        if ([string]$existingKey -ieq $Key) {
            return [string]$existingKey
        }
    }

    return $null
}

function ConvertFrom-JsonFilePreservingCase {
    param([Parameter(Mandatory = $true)][string]$Path)

    $convertCommand = Get-Command -Name ConvertFrom-Json
    if (-not $convertCommand.Parameters.ContainsKey('AsHashTable')) {
        throw 'Sync-SwaggerEndpoints.ps1 requires PowerShell 7+ because the Genesys swagger contains JSON keys that differ only by case. ConvertFrom-Json -AsHashTable is required to preserve those keys.'
    }

    return Get-Content -Path $Path -Raw | ConvertFrom-Json -Depth 100 -AsHashTable
}

function Test-JsonMapKey {
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if ($null -eq $InputObject) {
        return $false
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject.Contains($Key)
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.Name -ceq $Key) {
            return $true
        }
    }

    return $false
}

function Get-JsonMapValue {
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Key)) {
            return $InputObject[$Key]
        }

        return $null
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.Name -ceq $Key) {
            return $property.Value
        }
    }

    return $null
}

function Set-JsonMapValue {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        $InputObject[$Key] = $Value
        return
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.Name -ceq $Key) {
            $property.Value = $Value
            return
        }
    }

    $InputObject | Add-Member -MemberType NoteProperty -Name $Key -Value $Value
}

function Get-JsonMapEntries {
    param([Parameter(Mandatory = $true)][AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) {
        return
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            [pscustomobject]@{
                Name = [string]$key
                Value = $InputObject[$key]
            }
        }

        return
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        [pscustomobject]@{
            Name = $property.Name
            Value = $property.Value
        }
    }
}

function Get-DenylistOperationIds {
    param([Parameter(Mandatory = $true)][string]$SwaggerDirectory)

    $denylistPath = Join-Path -Path $SwaggerDirectory -ChildPath 'denylist.operationIds.txt'
    if (-not (Test-Path -Path $denylistPath)) {
        return (New-StringDictionary)
    }

    $ids = New-StringDictionary
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
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Definitions,
        [int]$Depth = 0
    )

    if ($null -eq $Schema -or $Depth -gt 8) {
        return $null
    }

    if (Test-JsonMapKey -InputObject $Schema -Key '$ref') {
        $refValue = [string](Get-JsonMapValue -InputObject $Schema -Key '$ref')
        if ($refValue.StartsWith('#/definitions/')) {
            $definitionKey = $refValue.Substring(14)
            if ($Definitions.ContainsKey($definitionKey)) {
                return Resolve-SwaggerSchema -Schema $Definitions[$definitionKey] -Definitions $Definitions -Depth ($Depth + 1)
            }
        }

        return $Schema
    }

    if (Test-JsonMapKey -InputObject $Schema -Key 'allOf') {
        foreach ($entry in @((Get-JsonMapValue -InputObject $Schema -Key 'allOf'))) {
            $resolved = Resolve-SwaggerSchema -Schema $entry -Definitions $Definitions -Depth ($Depth + 1)
            if ($null -ne $resolved -and (Test-JsonMapKey -InputObject $resolved -Key 'properties')) {
                return $resolved
            }
        }
    }

    return $Schema
}

function Get-ItemsPathFromOperation {
    param(
        [Parameter(Mandatory = $true)][object]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Definitions
    )

    $responses = Get-JsonMapValue -InputObject $Operation -Key 'responses'
    $responseCodes = @('200', '201', '202')
    foreach ($code in $responseCodes) {
        if (-not (Test-JsonMapKey -InputObject $responses -Key $code)) {
            continue
        }

        $response = Get-JsonMapValue -InputObject $responses -Key $code
        if ($null -eq $response -or -not (Test-JsonMapKey -InputObject $response -Key 'schema')) {
            continue
        }

        $schema = Resolve-SwaggerSchema -Schema (Get-JsonMapValue -InputObject $response -Key 'schema') -Definitions $Definitions
        if ($null -eq $schema) {
            continue
        }

        if ((Test-JsonMapKey -InputObject $schema -Key 'type') -and [string](Get-JsonMapValue -InputObject $schema -Key 'type') -eq 'array') {
            return '$'
        }

        if (Test-JsonMapKey -InputObject $schema -Key 'properties') {
            $properties = Get-JsonMapValue -InputObject $schema -Key 'properties'
            foreach ($candidate in @('entities', 'results', 'items')) {
                if (Test-JsonMapKey -InputObject $properties -Key $candidate) {
                    $propertyValue = Get-JsonMapValue -InputObject $properties -Key $candidate
                    if (Test-JsonMapKey -InputObject $propertyValue -Key 'type') {
                        if ([string](Get-JsonMapValue -InputObject $propertyValue -Key 'type') -eq 'array') {
                            return "$.$($candidate)"
                        }
                    }
                    elseif (Test-JsonMapKey -InputObject $propertyValue -Key 'items') {
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

$swagger = ConvertFrom-JsonFilePreservingCase -Path $resolvedSwaggerPath
if (Test-JsonMapKey -InputObject $swagger -Key 'swagger') {
    $swaggerVersion = [string](Get-JsonMapValue -InputObject $swagger -Key 'swagger')
    if ($swaggerVersion -ne '2.0') {
        Write-Warning "Swagger version '$swaggerVersion' detected; expected 2.0. Continuing best-effort parsing."
    }
}

$definitions = New-StringDictionary
$swaggerDefinitions = Get-JsonMapValue -InputObject $swagger -Key 'definitions'
if ($null -ne $swaggerDefinitions) {
    foreach ($entry in Get-JsonMapEntries -InputObject $swaggerDefinitions) {
        $definitions[$entry.Name] = $entry.Value
    }
}

$denylist = Get-DenylistOperationIds -SwaggerDirectory (Split-Path -Path $resolvedSwaggerPath -Parent)
$generatedEndpoints = New-StringDictionary -CaseInsensitive
$totalSwaggerOps = 0
$caseCollisionSkippedCount = 0

$allowedMethods = @('get', 'post', 'put', 'patch', 'delete')
foreach ($pathProperty in Get-JsonMapEntries -InputObject (Get-JsonMapValue -InputObject $swagger -Key 'paths')) {
    $pathValue = $pathProperty.Value
    foreach ($methodProperty in Get-JsonMapEntries -InputObject $pathValue) {
        $methodLower = ([string]$methodProperty.Name).ToLowerInvariant()
        if ($allowedMethods -notcontains $methodLower) {
            continue
        }

        $operation = $methodProperty.Value
        $operationId = [string](Get-JsonMapValue -InputObject $operation -Key 'operationId')
        if ([string]::IsNullOrWhiteSpace($operationId)) {
            continue
        }

        if ($denylist.ContainsKey($operationId)) {
            continue
        }

        $totalSwaggerOps += 1
        $itemsPath = Get-ItemsPathFromOperation -Operation $operation -Definitions $definitions

        if ($generatedEndpoints.ContainsKey($operationId)) {
            $existingOperationId = Get-MatchingDictionaryKey -Dictionary $generatedEndpoints -Key $operationId
            if ($existingOperationId -cne $operationId) {
                $caseCollisionSkippedCount += 1
                Write-Warning "Skipping swagger operationId '$operationId' because it differs only by case from '$existingOperationId'. The catalog endpoint map is kept case-insensitive for existing Core compatibility."
                continue
            }
        }

        $endpoint = [ordered]@{
            method = $methodLower.ToUpperInvariant()
            path = [string]$pathProperty.Name
            itemsPath = $itemsPath
            pagingProfile = 'none'
            retryProfile = 'default'
            operationId = $operationId
        }

        if (Test-JsonMapKey -InputObject $operation -Key 'tags') {
            $endpoint.tags = @((Get-JsonMapValue -InputObject $operation -Key 'tags'))
        }
        if ((Test-JsonMapKey -InputObject $operation -Key 'summary') -and [string]::IsNullOrWhiteSpace([string](Get-JsonMapValue -InputObject $operation -Key 'summary')) -eq $false) {
            $endpoint.summary = [string](Get-JsonMapValue -InputObject $operation -Key 'summary')
        }
        if ((Test-JsonMapKey -InputObject $operation -Key 'description') -and [string]::IsNullOrWhiteSpace([string](Get-JsonMapValue -InputObject $operation -Key 'description')) -eq $false) {
            $endpoint.description = [string](Get-JsonMapValue -InputObject $operation -Key 'description')
        }

        $generatedEndpoints[$operationId] = $endpoint
    }
}

$catalog = ConvertFrom-JsonFilePreservingCase -Path $resolvedCatalogPath
if (-not (Test-JsonMapKey -InputObject $catalog -Key 'endpoints') -or $null -eq (Get-JsonMapValue -InputObject $catalog -Key 'endpoints')) {
    Set-JsonMapValue -InputObject $catalog -Key 'endpoints' -Value ([ordered]@{})
}

$catalogEndpoints = ConvertTo-PlainHashtable -InputObject (Get-JsonMapValue -InputObject $catalog -Key 'endpoints')
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
    caseCollisionSkippedCount = $caseCollisionSkippedCount
    missingAfterMergeCount = $missingAfterMergeCount
}

if ($PSCmdlet.ShouldProcess($resolvedCatalogPath, 'Sync swagger operations into catalog endpoints')) {
    Set-JsonMapValue -InputObject $catalog -Key 'endpoints' -Value $catalogEndpoints
    Set-JsonMapValue -InputObject $catalog -Key 'generatedAt' -Value ([DateTime]::UtcNow.ToString('o'))

    $catalogJson = $catalog | ConvertTo-Json -Depth 100
    Set-Content -Path $resolvedCatalogPath -Value $catalogJson -Encoding UTF8

    if ($WriteLegacyCopy) {
        Write-Warning '-WriteLegacyCopy is deprecated and ignored in v2. Canonical output remains catalog/genesys.catalog.json.'
    }
}

return $report


