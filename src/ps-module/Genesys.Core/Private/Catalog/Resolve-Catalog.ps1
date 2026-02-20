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

function ConvertTo-ShallowHashtable {
    [CmdletBinding()]
    param(
        [object]$InputObject
    )

    $result = [ordered]@{}
    if ($null -eq $InputObject) {
        return $result
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = $InputObject[$key]
        }

        return $result
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }

    return $result
}

function Merge-ShallowObjects {
    [CmdletBinding()]
    param(
        [object]$BaseObject,

        [object]$OverrideObject
    )

    $merged = ConvertTo-ShallowHashtable -InputObject $BaseObject
    $override = ConvertTo-ShallowHashtable -InputObject $OverrideObject

    foreach ($key in $override.Keys) {
        $merged[$key] = $override[$key]
    }

    return [pscustomobject]$merged
}

function Get-CatalogValueByName {
    [CmdletBinding()]
    param(
        [object]$Container,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $Container) {
        return $null
    }

    if ($Container -is [System.Collections.IDictionary]) {
        if ($Container.Contains($Name)) {
            return $Container[$Name]
        }

        if ($Container -is [hashtable] -and $Container.ContainsKey($Name)) {
            return $Container[$Name]
        }
    }

    if ($Container.PSObject.Properties.Name -contains $Name) {
        return $Container.$Name
    }

    return $null
}

function Get-CatalogEntries {
    [CmdletBinding()]
    param(
        [object]$Container
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Container) {
        return @()
    }

    if ($Container -is [System.Collections.IDictionary]) {
        foreach ($key in $Container.Keys) {
            $entries.Add([pscustomobject]@{
                Name = [string]$key
                Value = $Container[$key]
            }) | Out-Null
        }

        return @($entries)
    }

    foreach ($property in $Container.PSObject.Properties) {
        $entries.Add([pscustomobject]@{
            Name = $property.Name
            Value = $property.Value
        }) | Out-Null
    }

    return @($entries)
}

function Resolve-CatalogProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateSet('paging', 'retry', 'transaction')]
        [string]$Category,

        [string]$ProfileName
    )

    if ([string]::IsNullOrWhiteSpace([string]$ProfileName)) {
        return $null
    }

    $categoryProfiles = Get-CatalogValueByName -Container $Catalog.profiles -Name $Category
    if ($null -eq $categoryProfiles) {
        return $null
    }

    $exact = Get-CatalogValueByName -Container $categoryProfiles -Name $ProfileName
    if ($null -ne $exact) {
        return $exact
    }

    if ($Category -eq 'retry') {
        foreach ($entry in (Get-CatalogEntries -Container $categoryProfiles)) {
            $candidate = $entry.Value
            if ($null -ne $candidate -and $candidate.PSObject.Properties.Name -contains 'mode' -and ([string]$candidate.mode).ToLowerInvariant() -eq ([string]$ProfileName).ToLowerInvariant()) {
                return $candidate
            }
        }
    }

    if ($Category -eq 'paging') {
        foreach ($entry in (Get-CatalogEntries -Container $categoryProfiles)) {
            $candidate = $entry.Value
            if ($null -ne $candidate -and $candidate.PSObject.Properties.Name -contains 'type' -and ([string]$candidate.type).ToLowerInvariant() -eq ([string]$ProfileName).ToLowerInvariant()) {
                return $candidate
            }
        }
    }

    return $null
}

function Resolve-EndpointSpecProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [psobject]$EndpointSpec,

        [psobject]$DatasetSpec
    )

    $resolved = ConvertTo-ShallowHashtable -InputObject $EndpointSpec

    if ($null -ne $DatasetSpec -and $DatasetSpec.PSObject.Properties.Name -contains 'itemsPath' -and [string]::IsNullOrWhiteSpace([string]$DatasetSpec.itemsPath) -eq $false) {
        $resolved['itemsPath'] = [string]$DatasetSpec.itemsPath
    }

    # Precedence order (highest->lowest): dataset inline overrides > endpoint inline overrides > named profile defaults.
    $datasetPaging = $null
    if ($null -ne $DatasetSpec -and $DatasetSpec.PSObject.Properties.Name -contains 'paging') {
        $datasetPaging = $DatasetSpec.paging
    }

    $endpointPaging = $null
    if ($EndpointSpec.PSObject.Properties.Name -contains 'paging') {
        $endpointPaging = $EndpointSpec.paging
    }

    $datasetPagingProfileName = $null
    if ($null -ne $datasetPaging -and $datasetPaging.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$datasetPaging.profile) -eq $false) {
        $datasetPagingProfileName = [string]$datasetPaging.profile
    }

    $endpointPagingProfileName = $null
    if ($null -ne $endpointPaging -and $endpointPaging.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$endpointPaging.profile) -eq $false) {
        $endpointPagingProfileName = [string]$endpointPaging.profile
    }

    $pagingProfileName = $datasetPagingProfileName
    if ([string]::IsNullOrWhiteSpace([string]$pagingProfileName)) {
        $pagingProfileName = $endpointPagingProfileName
    }

    $pagingProfile = Resolve-CatalogProfile -Catalog $Catalog -Category 'paging' -ProfileName $pagingProfileName
    if ($null -eq $pagingProfile -and [string]::IsNullOrWhiteSpace([string]$datasetPagingProfileName) -eq $false -and [string]::IsNullOrWhiteSpace([string]$endpointPagingProfileName) -eq $false -and $datasetPagingProfileName -ne $endpointPagingProfileName) {
        $pagingProfile = Resolve-CatalogProfile -Catalog $Catalog -Category 'paging' -ProfileName $endpointPagingProfileName
        if ($null -ne $pagingProfile) {
            $pagingProfileName = $endpointPagingProfileName
        }
    }

    $resolvedPaging = $pagingProfile
    if ($null -ne $endpointPaging) {
        $resolvedPaging = Merge-ShallowObjects -BaseObject $resolvedPaging -OverrideObject $endpointPaging
    }
    if ($null -ne $datasetPaging) {
        $resolvedPaging = Merge-ShallowObjects -BaseObject $resolvedPaging -OverrideObject $datasetPaging
    }

    if ($null -ne $resolvedPaging) {
        $effectivePagingProfile = $pagingProfileName
        if ($resolvedPaging.PSObject.Properties.Name -contains 'type' -and [string]::IsNullOrWhiteSpace([string]$resolvedPaging.type) -eq $false) {
            $effectivePagingProfile = [string]$resolvedPaging.type
        }
        elseif ($resolvedPaging.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$resolvedPaging.profile) -eq $false) {
            $effectivePagingProfile = [string]$resolvedPaging.profile
        }

        $resolvedPaging = Merge-ShallowObjects -BaseObject $resolvedPaging -OverrideObject ([pscustomobject]@{
            profile = $effectivePagingProfile
        })
        $resolved['paging'] = $resolvedPaging
    }

    $datasetRetry = $null
    if ($null -ne $DatasetSpec -and $DatasetSpec.PSObject.Properties.Name -contains 'retry') {
        $datasetRetry = $DatasetSpec.retry
    }

    $endpointRetry = $null
    if ($EndpointSpec.PSObject.Properties.Name -contains 'retry') {
        $endpointRetry = $EndpointSpec.retry
    }

    $datasetRetryProfileName = $null
    if ($null -ne $datasetRetry -and $datasetRetry.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$datasetRetry.profile) -eq $false) {
        $datasetRetryProfileName = [string]$datasetRetry.profile
    }

    $endpointRetryProfileName = $null
    if ($null -ne $endpointRetry -and $endpointRetry.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$endpointRetry.profile) -eq $false) {
        $endpointRetryProfileName = [string]$endpointRetry.profile
    }

    $retryProfileName = $datasetRetryProfileName
    if ([string]::IsNullOrWhiteSpace([string]$retryProfileName)) {
        $retryProfileName = $endpointRetryProfileName
    }

    $retryProfile = Resolve-CatalogProfile -Catalog $Catalog -Category 'retry' -ProfileName $retryProfileName
    if ($null -eq $retryProfile -and [string]::IsNullOrWhiteSpace([string]$datasetRetryProfileName) -eq $false -and [string]::IsNullOrWhiteSpace([string]$endpointRetryProfileName) -eq $false -and $datasetRetryProfileName -ne $endpointRetryProfileName) {
        $retryProfile = Resolve-CatalogProfile -Catalog $Catalog -Category 'retry' -ProfileName $endpointRetryProfileName
        if ($null -ne $retryProfile) {
            $retryProfileName = $endpointRetryProfileName
        }
    }

    $resolvedRetry = $retryProfile
    if ($null -ne $endpointRetry) {
        $resolvedRetry = Merge-ShallowObjects -BaseObject $resolvedRetry -OverrideObject $endpointRetry
    }
    if ($null -ne $datasetRetry) {
        $resolvedRetry = Merge-ShallowObjects -BaseObject $resolvedRetry -OverrideObject $datasetRetry
    }

    if ($null -ne $resolvedRetry) {
        $effectiveRetryProfile = $retryProfileName
        if ([string]::IsNullOrWhiteSpace([string]$effectiveRetryProfile) -and $resolvedRetry.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$resolvedRetry.profile) -eq $false) {
            $effectiveRetryProfile = [string]$resolvedRetry.profile
        }

        $resolvedRetry = Merge-ShallowObjects -BaseObject $resolvedRetry -OverrideObject ([pscustomobject]@{
            profile = $effectiveRetryProfile
        })
        $resolved['retry'] = $resolvedRetry
    }

    $datasetTransaction = $null
    if ($null -ne $DatasetSpec -and $DatasetSpec.PSObject.Properties.Name -contains 'transaction') {
        $datasetTransaction = $DatasetSpec.transaction
    }

    $endpointTransaction = $null
    if ($EndpointSpec.PSObject.Properties.Name -contains 'transaction') {
        $endpointTransaction = $EndpointSpec.transaction
    }

    $datasetTransactionProfileName = $null
    if ($null -ne $datasetTransaction -and $datasetTransaction.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$datasetTransaction.profile) -eq $false) {
        $datasetTransactionProfileName = [string]$datasetTransaction.profile
    }

    $endpointTransactionProfileName = $null
    if ($null -ne $endpointTransaction -and $endpointTransaction.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$endpointTransaction.profile) -eq $false) {
        $endpointTransactionProfileName = [string]$endpointTransaction.profile
    }

    $transactionProfileName = $datasetTransactionProfileName
    if ([string]::IsNullOrWhiteSpace([string]$transactionProfileName)) {
        $transactionProfileName = $endpointTransactionProfileName
    }

    $transactionProfile = Resolve-CatalogProfile -Catalog $Catalog -Category 'transaction' -ProfileName $transactionProfileName
    if ($null -eq $transactionProfile -and [string]::IsNullOrWhiteSpace([string]$datasetTransactionProfileName) -eq $false -and [string]::IsNullOrWhiteSpace([string]$endpointTransactionProfileName) -eq $false -and $datasetTransactionProfileName -ne $endpointTransactionProfileName) {
        $transactionProfile = Resolve-CatalogProfile -Catalog $Catalog -Category 'transaction' -ProfileName $endpointTransactionProfileName
        if ($null -ne $transactionProfile) {
            $transactionProfileName = $endpointTransactionProfileName
        }
    }

    $resolvedTransaction = $transactionProfile
    if ($null -ne $endpointTransaction) {
        $resolvedTransaction = Merge-ShallowObjects -BaseObject $resolvedTransaction -OverrideObject $endpointTransaction
    }
    if ($null -ne $datasetTransaction) {
        $resolvedTransaction = Merge-ShallowObjects -BaseObject $resolvedTransaction -OverrideObject $datasetTransaction
    }

    if ($null -ne $resolvedTransaction) {
        $effectiveTransactionProfile = $transactionProfileName
        if ([string]::IsNullOrWhiteSpace([string]$effectiveTransactionProfile) -and $resolvedTransaction.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$resolvedTransaction.profile) -eq $false) {
            $effectiveTransactionProfile = [string]$resolvedTransaction.profile
        }

        $resolvedTransaction = Merge-ShallowObjects -BaseObject $resolvedTransaction -OverrideObject ([pscustomobject]@{
            profile = $effectiveTransactionProfile
        })
        $resolved['transaction'] = $resolvedTransaction
    }

    return [pscustomobject]$resolved
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
