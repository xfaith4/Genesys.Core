### BEGIN: ResolveCatalog
function Copy-CoreObject {
    [CmdletBinding()]
    param(
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    return ($InputObject | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
}

function Get-CatalogDatasetByKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    if ($null -eq $Catalog.datasets) {
        throw "Catalog does not define datasets."
    }

    foreach ($property in $Catalog.datasets.PSObject.Properties) {
        if ($property.Name -ceq $Key) {
            return $property.Value
        }
    }

    throw "Dataset '$($Key)' was not found in catalog."
}

function Get-CatalogEndpointByKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    foreach ($endpoint in @($Catalog.endpoints)) {
        if ($endpoint.key -eq $Key) {
            return $endpoint
        }
    }

    throw "Endpoint '$($Key)' was not found in catalog."
}

function Test-CatalogEndpointExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    foreach ($endpoint in @($Catalog.endpoints)) {
        if ($endpoint.key -eq $Key) {
            return $true
        }
    }

    return $false
}

function Join-EndpointUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUri,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [hashtable]$RouteValues
    )

    $resolvedPath = $Path
    if ($null -ne $RouteValues) {
        foreach ($key in $RouteValues.Keys) {
            $resolvedPath = $resolvedPath.Replace("{$($key)}", [string]$RouteValues[$key])
        }
    }

    if ($resolvedPath.StartsWith('http://') -or $resolvedPath.StartsWith('https://')) {
        return $resolvedPath
    }

    $trimmedBase = $BaseUri.TrimEnd('/')
    if ($resolvedPath.StartsWith('/')) {
        return "$($trimmedBase)$($resolvedPath)"
    }

    return "$($trimmedBase)/$($resolvedPath)"
}

function Get-CatalogProfileByName {
    [CmdletBinding()]
    param(
        [psobject]$ProfilesRoot,
        [string]$Name
    )

    if ($null -eq $ProfilesRoot -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    foreach ($property in $ProfilesRoot.PSObject.Properties) {
        if ($property.Name -ceq $Name) {
            return $property.Value
        }
    }

    return $null
}

function Resolve-RetryProfile {
    [CmdletBinding()]
    param(
        [psobject]$RetrySpec
    )

    $resolved = [ordered]@{
        profile = 'standard'
        maxRetries = 3
        allowRetryOnPost = $false
    }

    if ($null -ne $RetrySpec) {
        if ($RetrySpec.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$RetrySpec.profile) -eq $false) {
            $resolved.profile = [string]$RetrySpec.profile
        }

        if ($RetrySpec.PSObject.Properties.Name -contains 'mode' -and [string]::IsNullOrWhiteSpace([string]$RetrySpec.mode) -eq $false) {
            $resolved.profile = [string]$RetrySpec.mode
        }

        if ($RetrySpec.PSObject.Properties.Name -contains 'maxRetries') {
            $resolved.maxRetries = [int]$RetrySpec.maxRetries
        }

        if ($RetrySpec.PSObject.Properties.Name -contains 'allowRetryOnPost') {
            $resolved.allowRetryOnPost = [bool]$RetrySpec.allowRetryOnPost
        }

        if ($RetrySpec.PSObject.Properties.Name -contains 'retryOnMethods' -and $resolved.allowRetryOnPost -eq $false) {
            foreach ($method in @($RetrySpec.retryOnMethods)) {
                if ([string]::Equals([string]$method, 'POST', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $resolved.allowRetryOnPost = $true
                    break
                }
            }
        }
    }

    if ([string]::Equals([string]$resolved.profile, 'rateLimitAware', [System.StringComparison]::OrdinalIgnoreCase) -and ($null -eq $RetrySpec -or $RetrySpec.PSObject.Properties.Name -notcontains 'maxRetries')) {
        $resolved.maxRetries = 4
    }

    return [pscustomobject]$resolved
}

function Resolve-PagingProfile {
    [CmdletBinding()]
    param(
        [psobject]$PagingSpec
    )

    if ($null -eq $PagingSpec) {
        return [pscustomobject]@{ profile = 'none' }
    }

    $resolved = [ordered]@{}
    foreach ($property in $PagingSpec.PSObject.Properties) {
        $resolved[$property.Name] = $property.Value
    }

    if ($resolved.Contains('type') -and $resolved.Contains('profile') -eq $false) {
        $resolved.profile = [string]$resolved.type
    }

    if ($resolved.Contains('profile') -eq $false -or [string]::IsNullOrWhiteSpace([string]$resolved.profile)) {
        $resolved.profile = 'none'
    }

    $profileName = [string]$resolved.profile
    switch ($profileName.ToLowerInvariant()) {
        'nexturi' {
            $resolved.profile = 'nextUri'
        }
        'pagenumber' {
            $resolved.profile = 'pageNumber'
            if ($resolved.Contains('pageNumberParam') -and $resolved.Contains('pageParam') -eq $false) {
                $resolved.pageParam = [string]$resolved.pageNumberParam
            }
        }
        'bodypaging' {
            $resolved.profile = 'bodyPaging'
            if ($resolved.Contains('pageNumberParam') -and $resolved.Contains('pageParam') -eq $false) {
                $resolved.pageParam = [string]$resolved.pageNumberParam
            }
        }
        'transactionresults' {
            $resolved.profile = 'transactionResults'
        }
        default {
        }
    }

    return [pscustomobject]$resolved
}

function Resolve-LongFormEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [psobject]$EndpointEntry,

        [psobject]$Profiles
    )

    $pagingProfile = $null
    if ($EndpointEntry.PSObject.Properties.Name -contains 'pagingProfile') {
        $pagingProfile = Get-CatalogProfileByName -ProfilesRoot $Profiles.paging -Name ([string]$EndpointEntry.pagingProfile)
    }

    $retryProfile = $null
    if ($EndpointEntry.PSObject.Properties.Name -contains 'retryProfile') {
        $retryProfile = Get-CatalogProfileByName -ProfilesRoot $Profiles.retry -Name ([string]$EndpointEntry.retryProfile)
    }

    $transactionProfile = $null
    if ($EndpointEntry.PSObject.Properties.Name -contains 'transactionProfile') {
        $transactionProfile = Get-CatalogProfileByName -ProfilesRoot $Profiles.transaction -Name ([string]$EndpointEntry.transactionProfile)
    }

    $transactionSpec = $null
    if ($null -ne $transactionProfile) {
        $transactionSpec = [ordered]@{
            profile = [string]$EndpointEntry.transactionProfile
            statusEndpointKey = $transactionProfile.statusEndpointRef
            resultsEndpointKey = $transactionProfile.resultsEndpointRef
            pollIntervalSeconds = $transactionProfile.pollIntervalSeconds
            maxPolls = $transactionProfile.maxPolls
            statePath = $transactionProfile.statePath
            terminalStates = $transactionProfile.terminalStates
        }

        if ([string]::Equals([string]$EndpointEntry.transactionProfile, 'auditTransaction', [System.StringComparison]::OrdinalIgnoreCase)) {
            $transactionSpec.eventPrefix = 'audit.transaction'
        }
    }

    $resolvedEndpoint = [ordered]@{
        key = $Key
        method = [string]$EndpointEntry.method
        path = [string]$EndpointEntry.path
        itemsPath = [string]$EndpointEntry.itemsPath
        paging = (Resolve-PagingProfile -PagingSpec $pagingProfile)
        retry = (Resolve-RetryProfile -RetrySpec $retryProfile)
    }

    if ($null -ne $transactionSpec) {
        $resolvedEndpoint.transaction = [pscustomobject]$transactionSpec
    }

    if ($resolvedEndpoint.paging.PSObject.Properties.Name -contains 'transactionIdPath' -and $null -ne $resolvedEndpoint.transaction) {
        $resolvedEndpoint.transaction | Add-Member -MemberType NoteProperty -Name transactionIdPath -Value $resolvedEndpoint.paging.transactionIdPath -Force
    }

    return [pscustomobject]$resolvedEndpoint
}

function Convert-DatasetArrayToObject {
    [CmdletBinding()]
    param(
        [object[]]$DatasetArray
    )

    $result = [ordered]@{}
    foreach ($dataset in @($DatasetArray)) {
        if ($null -eq $dataset -or [string]::IsNullOrWhiteSpace([string]$dataset.key)) {
            continue
        }

        $copy = Copy-CoreObject -InputObject $dataset
        $copy.PSObject.Properties.Remove('key')
        $result[[string]$dataset.key] = $copy
    }

    return [pscustomobject]$result
}

function Resolve-CoreCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog
    )

    $resolvedDatasets = [pscustomobject]@{}
    if ($null -ne $Catalog.datasets) {
        if ($Catalog.datasets -is [array]) {
            $resolvedDatasets = Convert-DatasetArrayToObject -DatasetArray @($Catalog.datasets)
        }
        else {
            $resolvedDatasets = Copy-CoreObject -InputObject $Catalog.datasets
        }
    }

    if ($Catalog.endpoints -is [array]) {
        $resolvedEndpoints = [System.Collections.Generic.List[object]]::new()
        foreach ($endpoint in @($Catalog.endpoints)) {
            $copy = Copy-CoreObject -InputObject $endpoint
            $copy.paging = Resolve-PagingProfile -PagingSpec $copy.paging
            $copy.retry = Resolve-RetryProfile -RetrySpec $copy.retry

            if ($copy.PSObject.Properties.Name -contains 'transaction' -and $null -ne $copy.transaction) {
                if ($copy.transaction.PSObject.Properties.Name -contains 'profile' -and [string]::Equals([string]$copy.transaction.profile, 'auditTransaction', [System.StringComparison]::OrdinalIgnoreCase)) {
                    if ($copy.transaction.PSObject.Properties.Name -notcontains 'eventPrefix') {
                        $copy.transaction | Add-Member -MemberType NoteProperty -Name eventPrefix -Value 'audit.transaction'
                    }
                }
            }

            $resolvedEndpoints.Add($copy) | Out-Null
        }

        return [pscustomobject]@{
            version = $Catalog.version
            datasets = $resolvedDatasets
            endpoints = $resolvedEndpoints
        }
    }

    $resolvedEndpoints = [System.Collections.Generic.List[object]]::new()
    foreach ($endpointProperty in $Catalog.endpoints.PSObject.Properties) {
        $resolvedEndpoints.Add((Resolve-LongFormEndpoint -Key $endpointProperty.Name -EndpointEntry $endpointProperty.Value -Profiles $Catalog.profiles)) | Out-Null
    }

    return [pscustomobject]@{
        version = $Catalog.version
        datasets = $resolvedDatasets
        endpoints = $resolvedEndpoints
    }
}

function Resolve-EndpointSpecForExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointKey,

        [System.Collections.Generic.HashSet[string]]$ResolutionStack
    )

    if ($null -eq $ResolutionStack) {
        $ResolutionStack = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    if ($ResolutionStack.Contains($EndpointKey)) {
        throw "Circular endpoint resolution detected at '$($EndpointKey)'."
    }
    $ResolutionStack.Add($EndpointKey) | Out-Null

    $endpoint = Copy-CoreObject -InputObject (Get-CatalogEndpointByKey -Catalog $Catalog -Key $EndpointKey)
    $endpoint.retry = Resolve-RetryProfile -RetrySpec $endpoint.retry
    $endpoint.paging = Resolve-PagingProfile -PagingSpec $endpoint.paging

    if ([string]::Equals([string]$endpoint.paging.profile, 'transactionResults', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($null -eq $endpoint.transaction) {
            $endpoint | Add-Member -MemberType NoteProperty -Name transaction -Value ([pscustomobject]@{}) -Force
        }

        if ($endpoint.transaction.PSObject.Properties.Name -notcontains 'statusEndpointKey' -and (Test-CatalogEndpointExists -Catalog $Catalog -Key 'audits.query.status')) {
            $endpoint.transaction | Add-Member -MemberType NoteProperty -Name statusEndpointKey -Value 'audits.query.status' -Force
        }
        if ($endpoint.transaction.PSObject.Properties.Name -notcontains 'resultsEndpointKey' -and (Test-CatalogEndpointExists -Catalog $Catalog -Key 'audits.query.results')) {
            $endpoint.transaction | Add-Member -MemberType NoteProperty -Name resultsEndpointKey -Value 'audits.query.results' -Force
        }
        if ($endpoint.transaction.PSObject.Properties.Name -notcontains 'transactionIdPath' -and $endpoint.paging.PSObject.Properties.Name -contains 'transactionIdPath') {
            $endpoint.transaction | Add-Member -MemberType NoteProperty -Name transactionIdPath -Value $endpoint.paging.transactionIdPath -Force
        }
        if ($endpoint.transaction.PSObject.Properties.Name -notcontains 'eventPrefix') {
            if ($endpoint.transaction.PSObject.Properties.Name -contains 'profile' -and [string]::Equals([string]$endpoint.transaction.profile, 'auditTransaction', [System.StringComparison]::OrdinalIgnoreCase)) {
                $endpoint.transaction | Add-Member -MemberType NoteProperty -Name eventPrefix -Value 'audit.transaction' -Force
            }
            else {
                $endpoint.transaction | Add-Member -MemberType NoteProperty -Name eventPrefix -Value 'transaction' -Force
            }
        }

        if ($endpoint.transaction.PSObject.Properties.Name -contains 'statusEndpointKey' -and $endpoint.transaction.PSObject.Properties.Name -contains 'resultsEndpointKey') {
            $statusSpec = Resolve-EndpointSpecForExecution -Catalog $Catalog -EndpointKey ([string]$endpoint.transaction.statusEndpointKey) -ResolutionStack $ResolutionStack
            $resultsSpec = Resolve-EndpointSpecForExecution -Catalog $Catalog -EndpointKey ([string]$endpoint.transaction.resultsEndpointKey) -ResolutionStack $ResolutionStack

            $submitSpec = [pscustomobject]@{
                key = $endpoint.key
                method = $endpoint.method
                path = $endpoint.path
                itemsPath = '$'
                retry = $endpoint.retry
            }

            $endpoint.transaction | Add-Member -MemberType NoteProperty -Name submit -Value $submitSpec -Force
            $endpoint.transaction | Add-Member -MemberType NoteProperty -Name status -Value $statusSpec -Force
            $endpoint.transaction | Add-Member -MemberType NoteProperty -Name results -Value $resultsSpec -Force
        }
    }

    $null = $ResolutionStack.Remove($EndpointKey)
    return $endpoint
}

function Resolve-DatasetEndpointSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DatasetKey
    )

    $dataset = Get-CatalogDatasetByKey -Catalog $Catalog -Key $DatasetKey
    $endpointSpec = Resolve-EndpointSpecForExecution -Catalog $Catalog -EndpointKey ([string]$dataset.endpoint)

    if ($dataset.PSObject.Properties.Name -contains 'itemsPath' -and [string]::IsNullOrWhiteSpace([string]$dataset.itemsPath) -eq $false) {
        $endpointSpec.itemsPath = [string]$dataset.itemsPath
    }

    if ($dataset.PSObject.Properties.Name -contains 'retry' -and $null -ne $dataset.retry) {
        $mergedRetry = Copy-CoreObject -InputObject $endpointSpec.retry
        foreach ($property in $dataset.retry.PSObject.Properties) {
            $mergedRetry | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value -Force
        }

        $endpointSpec.retry = Resolve-RetryProfile -RetrySpec $mergedRetry
    }

    if ($dataset.PSObject.Properties.Name -contains 'paging' -and $null -ne $dataset.paging) {
        $mergedPaging = Copy-CoreObject -InputObject $endpointSpec.paging
        foreach ($property in $dataset.paging.PSObject.Properties) {
            $mergedPaging | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value -Force
        }

        $endpointSpec.paging = Resolve-PagingProfile -PagingSpec $mergedPaging
    }

    return $endpointSpec
}
### END: ResolveCatalog
