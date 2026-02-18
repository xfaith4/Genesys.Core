function ConvertTo-CanonicalCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $normalizedDatasets = @{}
    if ($null -ne $Catalog.datasets) {
        if ($Catalog.datasets -is [System.Collections.IDictionary]) {
            foreach ($key in $Catalog.datasets.Keys) {
                $normalizedDatasets[$key] = $Catalog.datasets[$key]
            }
        }
        elseif ($Catalog.datasets.PSObject.Properties.Count -gt 0) {
            foreach ($property in $Catalog.datasets.PSObject.Properties) {
                $normalizedDatasets[$property.Name] = $property.Value
            }
        }
    }

    $normalizedEndpoints = @()
    if ($Catalog.endpoints -is [System.Collections.IEnumerable] -and $Catalog.endpoints -isnot [string] -and $Catalog.endpoints -isnot [System.Collections.IDictionary]) {
        $normalizedEndpoints = @($Catalog.endpoints)
    }
    elseif ($Catalog.endpoints -is [System.Collections.IDictionary]) {
        foreach ($key in $Catalog.endpoints.Keys) {
            $value = $Catalog.endpoints[$key]
            $normalizedEndpoints += [pscustomobject]@{
                key = $key
                method = $value.method
                path = $value.path
                itemsPath = $value.itemsPath
                paging = [pscustomobject]@{ profile = $(if ($null -ne $value.paging -and $value.paging.PSObject.Properties.Name -contains 'profile') { $value.paging.profile } else { $value.pagingProfile }) }
                retry = [pscustomobject]@{ profile = $(if ($null -ne $value.retry -and $value.retry.PSObject.Properties.Name -contains 'profile') { $value.retry.profile } else { $value.retryProfile }) }
                transaction = $(if ($null -ne $value.transaction -or $null -ne $value.transactionProfile) { [pscustomobject]@{ profile = $(if ($null -ne $value.transaction -and $value.transaction.PSObject.Properties.Name -contains 'profile') { $value.transaction.profile } else { $value.transactionProfile }) } } else { $null })
            }
        }
    }
    elseif ($Catalog.endpoints.PSObject.Properties.Count -gt 0) {
        foreach ($property in $Catalog.endpoints.PSObject.Properties) {
            $key = $property.Name
            $value = $property.Value
            $normalizedEndpoints += [pscustomobject]@{
                key = $key
                method = $value.method
                path = $value.path
                itemsPath = $value.itemsPath
                paging = [pscustomobject]@{ profile = $(if ($null -ne $value.paging -and $value.paging.PSObject.Properties.Name -contains 'profile') { $value.paging.profile } else { $value.pagingProfile }) }
                retry = [pscustomobject]@{ profile = $(if ($null -ne $value.retry -and $value.retry.PSObject.Properties.Name -contains 'profile') { $value.retry.profile } else { $value.retryProfile }) }
                transaction = $(if ($null -ne $value.transaction -or $null -ne $value.transactionProfile) { [pscustomobject]@{ profile = $(if ($null -ne $value.transaction -and $value.transaction.PSObject.Properties.Name -contains 'profile') { $value.transaction.profile } else { $value.transactionProfile }) } } else { $null })
            }
        }
    }

    return [pscustomobject]@{
        version = $Catalog.version
        profiles = $Catalog.profiles
        datasets = $normalizedDatasets
        endpoints = $normalizedEndpoints
        sourcePath = $SourcePath
    }
}

function Get-CatalogFileMetadata {
    [CmdletBinding()]
    param([string]$Path)

    $item = Get-Item -Path $Path
    return [pscustomobject]@{
        path = (Resolve-Path -Path $Path).Path
        length = [int64]$item.Length
        lastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
    }
}

function Resolve-Catalog {
    [CmdletBinding()]
    param(
        [string]$CatalogPath,
        [switch]$StrictCatalog,
        [string]$SchemaPath
    )

    $rootCandidate = Join-Path -Path (Get-Location) -ChildPath 'genesys-core.catalog.json'
    $legacyCandidate = Join-Path -Path (Get-Location) -ChildPath 'catalog/genesys-core.catalog.json'

    $rootExists = Test-Path -Path $rootCandidate
    $legacyExists = Test-Path -Path $legacyCandidate

    if ($PSBoundParameters.ContainsKey('CatalogPath') -and [string]::IsNullOrWhiteSpace([string]$CatalogPath) -eq $false) {
        if (-not (Test-Path -Path $CatalogPath)) {
            throw "Catalog file not found: $($CatalogPath)"
        }

        $selectedPath = (Resolve-Path -Path $CatalogPath).Path
    }
    elseif ($rootExists) {
        $selectedPath = (Resolve-Path -Path $rootCandidate).Path
    }
    elseif ($legacyExists) {
        $selectedPath = (Resolve-Path -Path $legacyCandidate).Path
    }
    else {
        throw "Catalog file not found. Checked '$($rootCandidate)' and '$($legacyCandidate)'."
    }

    $warnings = [System.Collections.Generic.List[string]]::new()

    if ($rootExists -and $legacyExists) {
        $rootRaw = Get-Content -Path $rootCandidate -Raw
        $legacyRaw = Get-Content -Path $legacyCandidate -Raw
        if ($rootRaw -ne $legacyRaw) {
            $rootInfo = Get-CatalogFileMetadata -Path $rootCandidate
            $legacyInfo = Get-CatalogFileMetadata -Path $legacyCandidate
            $message = "Catalog mismatch detected. root=$($rootInfo.path) (bytes=$($rootInfo.length), modifiedUtc=$($rootInfo.lastWriteUtc)); catalog=$($legacyInfo.path) (bytes=$($legacyInfo.length), modifiedUtc=$($legacyInfo.lastWriteUtc)). Canonical precedence uses root file when present."
            $warnings.Add($message) | Out-Null
            if ($StrictCatalog) {
                throw "$($message) Re-run without -StrictCatalog to proceed."
            }
        }
    }

    $catalogRaw = Get-Content -Path $selectedPath -Raw
    $catalogObject = $catalogRaw | ConvertFrom-Json -Depth 100

    if ($PSBoundParameters.ContainsKey('SchemaPath') -and [string]::IsNullOrWhiteSpace([string]$SchemaPath) -eq $false -and (Test-Path -Path $SchemaPath)) {
        $testJsonCommand = Get-Command -Name Test-Json -ErrorAction SilentlyContinue
        if ($null -ne $testJsonCommand) {
            $schemaRaw = Get-Content -Path $SchemaPath -Raw
            $isValid = $catalogRaw | Test-Json -Schema $schemaRaw -ErrorAction SilentlyContinue
            if (-not $isValid) {
                throw "Catalog schema validation failed for '$($selectedPath)'."
            }
        }
    }

    $canonicalCatalog = ConvertTo-CanonicalCatalog -Catalog $catalogObject -SourcePath $selectedPath

    return [pscustomobject]@{
        pathUsed = $selectedPath
        catalogObject = $canonicalCatalog
        warnings = @($warnings)
    }
}
