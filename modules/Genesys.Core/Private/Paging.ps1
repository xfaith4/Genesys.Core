### BEGIN: InvokePagingNextUri
function Get-PagingItemsFromResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response,

        [string]$ItemsPath = '$.results'
    )

    if ($null -eq $Response) {
        return @()
    }

    $normalizedPath = [string]$ItemsPath
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        $normalizedPath = '$.results'
    }

    if ($normalizedPath -eq '$' -or $normalizedPath -eq '$.') {
        return @(,$Response)
    }

    if ($normalizedPath.StartsWith('$.')) {
        $normalizedPath = $normalizedPath.Substring(2)
    }

    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        if ($Response -is [System.Collections.IEnumerable] -and $Response -isnot [string]) {
            return @($Response)
        }

        return @($Response)
    }

    $target = $Response
    foreach ($segment in ($normalizedPath -split '\.')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        if ($null -eq $target) {
            return @()
        }

        if ($target -is [System.Collections.IDictionary]) {
            $target = $target[$segment]
            continue
        }

        if ($target.PSObject.Properties.Name -contains $segment) {
            $target = $target.$segment
            continue
        }

        return @()
    }

    if ($null -eq $target) {
        return @()
    }

    if ($target -is [string]) {
        return @($target)
    }

    if ($target -is [System.Collections.IEnumerable]) {
        return @($target)
    }

    return @($target)
}

function Get-PagingTotalHitsFromResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response
    )

    if ($null -eq $Response) {
        return $null
    }

    if ($Response.PSObject.Properties.Name -contains 'totalHits') {
        return $Response.totalHits
    }

    if ($Response.PSObject.Properties.Name -contains 'total') {
        return $Response.total
    }

    if ($Response.PSObject.Properties.Name -contains 'paging') {
        $paging = $Response.paging
        if ($null -ne $paging -and $paging.PSObject.Properties.Name -contains 'totalHits') {
            return $paging.totalHits
        }
    }

    return $null
}

function Get-PagingValueFromResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($null -eq $Response) {
        return $null
    }

    $normalizedPath = [string]$Path
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        return $null
    }

    if ($normalizedPath.StartsWith('$.')) {
        $normalizedPath = $normalizedPath.Substring(2)
    }

    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        return $Response
    }

    $target = $Response
    foreach ($segment in ($normalizedPath -split '\.')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        if ($null -eq $target) {
            return $null
        }

        if ($target -is [System.Collections.IDictionary]) {
            $target = $target[$segment]
            continue
        }

        if ($target.PSObject.Properties.Name -contains $segment) {
            $target = $target.$segment
            continue
        }

        return $null
    }

    return $target
}

function Resolve-PagingNextUri {
    [CmdletBinding()]
    param(
        [string]$NextUri,

        [string]$CurrentUri,

        [string]$InitialUri
    )

    if ([string]::IsNullOrWhiteSpace([string]$NextUri)) {
        return $null
    }

    $normalizedNextUri = [string]$NextUri

    $absoluteNextUri = $null
    if ([System.Uri]::TryCreate($normalizedNextUri, [System.UriKind]::Absolute, [ref]$absoluteNextUri) -and
        ($absoluteNextUri.Scheme -eq 'https' -or $absoluteNextUri.Scheme -eq 'http')) {
        return $absoluteNextUri.AbsoluteUri
    }

    foreach ($baseCandidate in @($CurrentUri, $InitialUri)) {
        if ([string]::IsNullOrWhiteSpace([string]$baseCandidate)) {
            continue
        }

        $baseUri = $null
        if ([System.Uri]::TryCreate([string]$baseCandidate, [System.UriKind]::Absolute, [ref]$baseUri) -eq $false) {
            continue
        }

        $combinedUri = $null
        if ([System.Uri]::TryCreate($baseUri, $normalizedNextUri, [ref]$combinedUri) -and
            ($combinedUri.Scheme -eq 'https' -or $combinedUri.Scheme -eq 'http')) {
            return $combinedUri.AbsoluteUri
        }
    }

    # Fallback: concatenate host with relative path
    if ($InitialUri -match '^(https?://[^/]+)') {
        $relativePath = if ($normalizedNextUri.StartsWith('/')) { $normalizedNextUri } else { "/$normalizedNextUri" }
        return "$($Matches[1])$relativePath"
    }

    return $normalizedNextUri
}

function Invoke-PagingNextUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EndpointSpec,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InitialUri,

        [object]$InitialBody,

        [hashtable]$Headers,

        [psobject]$RetryProfile,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $method = 'GET'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'method' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.method) -eq $false) {
        $method = [string]$EndpointSpec.method
    }

    $itemsPath = '$.results'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'itemsPath' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.itemsPath) -eq $false) {
        $itemsPath = [string]$EndpointSpec.itemsPath
    }

    $retrySettings = Resolve-RetryRuntimeSettings -RetryProfile $RetryProfile

    $telemetry = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()
    $visitedUris = New-Object System.Collections.Generic.HashSet[string]

    $pageNumber = 1
    $currentUri = $InitialUri
    $currentBody = $InitialBody

    while ([string]::IsNullOrWhiteSpace($currentUri) -eq $false) {
        if ($visitedUris.Contains($currentUri)) {
            $RunEvents.Add([pscustomobject]@{
                eventType = 'paging.terminated.duplicateUri'
                page = $pageNumber
                uri = $currentUri
                timestampUtc = [DateTime]::UtcNow.ToString('o')
            })
            break
        }

        $visitedUris.Add($currentUri) | Out-Null

        $responseEnvelope = Invoke-RequestWithRetry -Request ([pscustomobject]@{
            Uri = $currentUri
            Method = $method
            Headers = $Headers
            Body = $currentBody
        }) -RetrySettings $retrySettings -RequestInvoker $RequestInvoker -RunEvents $RunEvents

        $response = $responseEnvelope
        if ($null -ne $responseEnvelope -and $responseEnvelope.PSObject.Properties.Name -contains 'Result') {
            $response = $responseEnvelope.Result
        }

        $pageItems = Get-PagingItemsFromResponse -Response $response -ItemsPath $itemsPath
        foreach ($item in $pageItems) {
            $items.Add($item) | Out-Null
        }

        $nextUri = $null
        if ($null -ne $response -and $response.PSObject.Properties.Name -contains 'nextUri') {
            $nextUri = Resolve-PagingNextUri -NextUri ([string]$response.nextUri) -CurrentUri $currentUri -InitialUri $InitialUri
        }

        $totalHits = Get-PagingTotalHitsFromResponse -Response $response

        $progressEvent = [pscustomobject]@{
            eventType = 'paging.progress'
            profile = 'nextUri'
            page = $pageNumber
            nextUri = $nextUri
            totalHits = $totalHits
            itemCount = $pageItems.Count
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        }

        $RunEvents.Add($progressEvent)
        $telemetry.Add($progressEvent) | Out-Null

        if ([string]::IsNullOrWhiteSpace($nextUri)) {
            break
        }

        $currentUri = $nextUri
        $currentBody = $null
        $pageNumber++
    }

    return [pscustomobject]@{
        Items = $items
        PagingTelemetry = $telemetry
        RunEvents = $RunEvents
    }
}
### END: InvokePagingNextUri

### BEGIN: InvokePagingPageNumber
function Add-PagingQueryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $builder = [System.UriBuilder]::new($Uri)
    $queryPairs = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($builder.Query) -eq $false) {
        $rawQuery = $builder.Query.TrimStart('?')
        foreach ($pair in ($rawQuery -split '&')) {
            if ([string]::IsNullOrWhiteSpace($pair)) {
                continue
            }

            $nameValue = $pair -split '=', 2
            if ($nameValue[0] -ceq $Name) {
                continue
            }

            $queryPairs.Add($pair) | Out-Null
        }
    }

    $encodedName = [System.Uri]::EscapeDataString($Name)
    $encodedValue = [System.Uri]::EscapeDataString([string]$Value)
    $queryPairs.Add("$($encodedName)=$($encodedValue)") | Out-Null

    $builder.Query = [string]::Join('&', $queryPairs.ToArray())
    return $builder.Uri.AbsoluteUri
}

function Invoke-PagingPageNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EndpointSpec,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InitialUri,

        [object]$InitialBody,

        [hashtable]$Headers,

        [psobject]$RetryProfile,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $method = 'GET'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'method' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.method) -eq $false) {
        $method = [string]$EndpointSpec.method
    }

    $itemsPath = '$.results'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'itemsPath' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.itemsPath) -eq $false) {
        $itemsPath = [string]$EndpointSpec.itemsPath
    }

    $pagingProfile = $null
    if ($EndpointSpec.PSObject.Properties.Name -contains 'paging') {
        $pagingProfile = $EndpointSpec.paging
    }

    $pageParam = 'pageNumber'
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'pageParam' -and [string]::IsNullOrWhiteSpace([string]$pagingProfile.pageParam) -eq $false) {
        $pageParam = [string]$pagingProfile.pageParam
    }

    $maxPages = 1000
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'maxPages') {
        $maxPages = [int]$pagingProfile.maxPages
    }

    $pageCountPath = $null
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'pageCountPath' -and [string]::IsNullOrWhiteSpace([string]$pagingProfile.pageCountPath) -eq $false) {
        $pageCountPath = [string]$pagingProfile.pageCountPath
    }

    $retrySettings = Resolve-RetryRuntimeSettings -RetryProfile $RetryProfile

    $telemetry = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()

    $pageNumber = 1
    $collectedCount = 0

    while ($pageNumber -le $maxPages) {
        $pageUri = Add-PagingQueryValue -Uri $InitialUri -Name $pageParam -Value $pageNumber

        $responseEnvelope = Invoke-RequestWithRetry -Request ([pscustomobject]@{
            Uri = $pageUri
            Method = $method
            Headers = $Headers
            Body = $InitialBody
        }) -RetrySettings $retrySettings -RequestInvoker $RequestInvoker -RunEvents $RunEvents

        $response = $responseEnvelope
        if ($null -ne $responseEnvelope -and $responseEnvelope.PSObject.Properties.Name -contains 'Result') {
            $response = $responseEnvelope.Result
        }

        $pageItems = Get-PagingItemsFromResponse -Response $response -ItemsPath $itemsPath
        foreach ($item in $pageItems) {
            $items.Add($item) | Out-Null
        }

        $collectedCount += $pageItems.Count
        $totalHits = Get-PagingTotalHitsFromResponse -Response $response

        $nextUri = Add-PagingQueryValue -Uri $InitialUri -Name $pageParam -Value ($pageNumber + 1)
        if ($pageItems.Count -eq 0) {
            $nextUri = $null
        }

        if ($null -ne $totalHits -and $collectedCount -ge [int]$totalHits) {
            $nextUri = $null
        }

        if ($null -ne $pageCountPath) {
            $pageCount = Get-PagingValueFromResponse -Response $response -Path $pageCountPath
            if ($null -ne $pageCount -and $pageNumber -ge [int]$pageCount) {
                $nextUri = $null
            }
        }

        $progressEvent = [pscustomobject]@{
            eventType = 'paging.progress'
            profile = 'pageNumber'
            page = $pageNumber
            nextUri = $nextUri
            totalHits = $totalHits
            itemCount = $pageItems.Count
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        }

        $RunEvents.Add($progressEvent)
        $telemetry.Add($progressEvent) | Out-Null

        if ($null -eq $nextUri) {
            break
        }

        $pageNumber++
    }

    return [pscustomobject]@{
        Items = $items
        PagingTelemetry = $telemetry
        RunEvents = $RunEvents
    }
}
### END: InvokePagingPageNumber

### BEGIN: InvokePagingBodyPaging
function Invoke-PagingBodyPaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EndpointSpec,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InitialUri,

        [object]$InitialBody,

        [hashtable]$Headers,

        [psobject]$RetryProfile,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $method = 'POST'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'method' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.method) -eq $false) {
        $method = [string]$EndpointSpec.method
    }

    $itemsPath = '$.results'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'itemsPath' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.itemsPath) -eq $false) {
        $itemsPath = [string]$EndpointSpec.itemsPath
    }

    $pagingProfile = $null
    if ($EndpointSpec.PSObject.Properties.Name -contains 'paging') {
        $pagingProfile = $EndpointSpec.paging
    }

    $pageParam = 'pageNumber'
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'pageParam' -and [string]::IsNullOrWhiteSpace([string]$pagingProfile.pageParam) -eq $false) {
        $pageParam = [string]$pagingProfile.pageParam
    }

    $maxPages = 1000
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'maxPages') {
        $maxPages = [int]$pagingProfile.maxPages
    }

    $totalHitsPath = '$.totalHits'
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'totalHitsPath' -and [string]::IsNullOrWhiteSpace([string]$pagingProfile.totalHitsPath) -eq $false) {
        $totalHitsPath = [string]$pagingProfile.totalHitsPath
    }

    $retrySettings = Resolve-RetryRuntimeSettings -RetryProfile $RetryProfile

    $baseBodyObject = @{}
    if ($null -ne $InitialBody -and [string]::IsNullOrWhiteSpace([string]$InitialBody) -eq $false) {
        $baseBodyObject = ConvertFrom-Json -InputObject $InitialBody -Depth 100 -AsHashtable
    }

    $telemetry = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()

    $pageNumber = 1
    $collectedCount = 0

    while ($pageNumber -le $maxPages) {
        $requestBody = @{}
        foreach ($key in $baseBodyObject.Keys) {
            $requestBody[$key] = $baseBodyObject[$key]
        }

        $requestBody[$pageParam] = $pageNumber
        $requestBodyJson = $requestBody | ConvertTo-Json -Depth 100

        $responseEnvelope = Invoke-RequestWithRetry -Request ([pscustomobject]@{
            Uri = $InitialUri
            Method = $method
            Headers = $Headers
            Body = $requestBodyJson
        }) -RetrySettings $retrySettings -RequestInvoker $RequestInvoker -RunEvents $RunEvents

        $response = $responseEnvelope
        if ($null -ne $responseEnvelope -and $responseEnvelope.PSObject.Properties.Name -contains 'Result') {
            $response = $responseEnvelope.Result
        }

        $pageItems = Get-PagingItemsFromResponse -Response $response -ItemsPath $itemsPath
        foreach ($item in $pageItems) {
            $items.Add($item) | Out-Null
        }

        $collectedCount += $pageItems.Count
        $totalHits = Get-PagingValueFromResponse -Response $response -Path $totalHitsPath

        $nextUri = "$($InitialUri)#$($pageParam)=$($pageNumber + 1)"
        if ($pageItems.Count -eq 0) {
            $nextUri = $null
        }

        if ($null -ne $totalHits -and $collectedCount -ge [int]$totalHits) {
            $nextUri = $null
        }

        $progressEvent = [pscustomobject]@{
            eventType = 'paging.progress'
            profile = 'bodyPaging'
            page = $pageNumber
            nextUri = $nextUri
            totalHits = $totalHits
            itemCount = $pageItems.Count
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        }

        $RunEvents.Add($progressEvent)
        $telemetry.Add($progressEvent) | Out-Null

        if ($null -eq $nextUri) {
            break
        }

        $pageNumber++
    }

    return [pscustomobject]@{
        Items = $items
        PagingTelemetry = $telemetry
        RunEvents = $RunEvents
    }
}
### END: InvokePagingBodyPaging

### BEGIN: InvokePagingCursor
function Add-CursorQueryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $builder = [System.UriBuilder]::new($Uri)
    $queryPairs = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($builder.Query) -eq $false) {
        $rawQuery = $builder.Query.TrimStart('?')
        foreach ($pair in ($rawQuery -split '&')) {
            if ([string]::IsNullOrWhiteSpace($pair)) {
                continue
            }

            $nameValue = $pair -split '=', 2
            if ($nameValue[0] -ceq $Name) {
                continue
            }

            $queryPairs.Add($pair) | Out-Null
        }
    }

    $encodedName = [System.Uri]::EscapeDataString($Name)
    $encodedValue = [System.Uri]::EscapeDataString([string]$Value)
    $queryPairs.Add("$($encodedName)=$($encodedValue)") | Out-Null

    $builder.Query = [string]::Join('&', $queryPairs.ToArray())
    return $builder.Uri.AbsoluteUri
}

function Invoke-PagingCursor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EndpointSpec,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InitialUri,

        [object]$InitialBody,

        [hashtable]$Headers,

        [psobject]$RetryProfile,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $method = 'GET'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'method' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.method) -eq $false) {
        $method = [string]$EndpointSpec.method
    }

    $itemsPath = '$.results'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'itemsPath' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.itemsPath) -eq $false) {
        $itemsPath = [string]$EndpointSpec.itemsPath
    }

    $pagingProfile = $null
    if ($EndpointSpec.PSObject.Properties.Name -contains 'paging') {
        $pagingProfile = $EndpointSpec.paging
    }

    $cursorParam = 'cursor'
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'cursorParam' -and [string]::IsNullOrWhiteSpace([string]$pagingProfile.cursorParam) -eq $false) {
        $cursorParam = [string]$pagingProfile.cursorParam
    }

    $cursorPath = '$.cursor'
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'cursorPath' -and [string]::IsNullOrWhiteSpace([string]$pagingProfile.cursorPath) -eq $false) {
        $cursorPath = [string]$pagingProfile.cursorPath
    }

    $maxPages = 1000
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'maxPages') {
        $maxPages = [int]$pagingProfile.maxPages
    }

    $retrySettings = Resolve-RetryRuntimeSettings -RetryProfile $RetryProfile

    $telemetry = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()
    $visitedCursors = New-Object System.Collections.Generic.HashSet[string]

    $currentUri = $InitialUri
    $pageNumber = 1

    while ([string]::IsNullOrWhiteSpace($currentUri) -eq $false -and $pageNumber -le $maxPages) {
        $responseEnvelope = Invoke-RequestWithRetry -Request ([pscustomobject]@{
            Uri = $currentUri
            Method = $method
            Headers = $Headers
            Body = $InitialBody
        }) -RetrySettings $retrySettings -RequestInvoker $RequestInvoker -RunEvents $RunEvents

        $response = $responseEnvelope
        if ($null -ne $responseEnvelope -and $responseEnvelope.PSObject.Properties.Name -contains 'Result') {
            $response = $responseEnvelope.Result
        }

        $pageItems = Get-PagingItemsFromResponse -Response $response -ItemsPath $itemsPath
        foreach ($item in $pageItems) {
            $items.Add($item) | Out-Null
        }

        $cursorValue = [string](Get-PagingValueFromResponse -Response $response -Path $cursorPath)
        $nextUri = $null

        if ([string]::IsNullOrWhiteSpace($cursorValue) -eq $false) {
            if ($visitedCursors.Contains($cursorValue)) {
                $RunEvents.Add([pscustomobject]@{
                    eventType = 'paging.terminated.duplicateCursor'
                    page = $pageNumber
                    cursor = $cursorValue
                    timestampUtc = [DateTime]::UtcNow.ToString('o')
                })
            }
            else {
                $visitedCursors.Add($cursorValue) | Out-Null
                $nextUri = Add-CursorQueryValue -Uri $InitialUri -Name $cursorParam -Value $cursorValue
            }
        }

        if ($pageItems.Count -eq 0) {
            $nextUri = $null
        }

        $progressEvent = [pscustomobject]@{
            eventType = 'paging.progress'
            profile = 'cursor'
            page = $pageNumber
            nextUri = $nextUri
            cursor = $cursorValue
            totalHits = $null
            itemCount = $pageItems.Count
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        }

        $RunEvents.Add($progressEvent)
        $telemetry.Add($progressEvent) | Out-Null

        if ([string]::IsNullOrWhiteSpace($nextUri)) {
            break
        }

        $currentUri = $nextUri
        $pageNumber++
    }

    return [pscustomobject]@{
        Items = $items
        PagingTelemetry = $telemetry
        RunEvents = $RunEvents
    }
}
### END: InvokePagingCursor

### BEGIN: InvokeCoreEndpoint
function Invoke-CoreEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EndpointSpec,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InitialUri,

        [object]$InitialBody,

        [hashtable]$Headers,

        [psobject]$RetryProfile,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    # Extract retry profile from EndpointSpec if not provided as parameter
    $effectiveRetryProfile = $RetryProfile
    if ($null -eq $effectiveRetryProfile -and $EndpointSpec.PSObject.Properties.Name -contains 'retry' -and $null -ne $EndpointSpec.retry) {
        $effectiveRetryProfile = $EndpointSpec.retry
    }

    # Support both nested paging.profile and flat pagingProfile for backwards compatibility
    $pagingProfile = 'none'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'pagingProfile' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.pagingProfile) -eq $false) {
        $pagingProfile = [string]$EndpointSpec.pagingProfile
    }
    elseif ($EndpointSpec.PSObject.Properties.Name -contains 'paging' -and $null -ne $EndpointSpec.paging) {
        if ($EndpointSpec.paging.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.paging.profile) -eq $false) {
            $pagingProfile = [string]$EndpointSpec.paging.profile
        }
    }

    # Normalize paging profile: strip variant suffixes (e.g., nextUri_auditResults -> nexturi)
    $normalizedProfile = $pagingProfile.ToLowerInvariant()
    if ($normalizedProfile -notin @('nexturi', 'pagenumber', 'transactionresults', 'bodypaging', 'cursor', 'none') -and $EndpointSpec.PSObject.Properties.Name -contains 'paging' -and $null -ne $EndpointSpec.paging) {
        if ($EndpointSpec.paging.PSObject.Properties.Name -contains 'type' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.paging.type) -eq $false) {
            $normalizedProfile = ([string]$EndpointSpec.paging.type).ToLowerInvariant()
        }
    }

    if ($normalizedProfile -match '^(nexturi|pagenumber|bodypaging|cursor)_') {
        $normalizedProfile = $Matches[1]
    }

    switch ($normalizedProfile) {
        'nexturi' {
            return Invoke-PagingNextUri -EndpointSpec $EndpointSpec -InitialUri $InitialUri -InitialBody $InitialBody -Headers $Headers -RetryProfile $effectiveRetryProfile -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'pagenumber' {
            return Invoke-PagingPageNumber -EndpointSpec $EndpointSpec -InitialUri $InitialUri -InitialBody $InitialBody -Headers $Headers -RetryProfile $effectiveRetryProfile -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'transactionresults' {
            if ($null -eq $EndpointSpec.PSObject.Properties['transaction']) {
                throw "transactionResults paging requires EndpointSpec.transaction metadata."
            }

            $transactionBaseUri = $null
            if ($EndpointSpec.transaction.PSObject.Properties.Name -contains 'baseUri' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.transaction.baseUri) -eq $false) {
                $transactionBaseUri = [string]$EndpointSpec.transaction.baseUri
            }
            else {
                $initialUriObject = [Uri]$InitialUri
                $transactionBaseUri = "$($initialUriObject.Scheme)://$($initialUriObject.Authority)"
            }

            return Invoke-AsyncJob -SubmitEndpointSpec $EndpointSpec.transaction.submit -StatusEndpointSpec $EndpointSpec.transaction.status -ResultsEndpointSpec $EndpointSpec.transaction.results -AsyncProfile $EndpointSpec.transaction -BaseUri $transactionBaseUri -Headers $Headers -SubmitBody $InitialBody -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'bodypaging' {
            return Invoke-PagingBodyPaging -EndpointSpec $EndpointSpec -InitialUri $InitialUri -InitialBody $InitialBody -Headers $Headers -RetryProfile $effectiveRetryProfile -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'cursor' {
            return Invoke-PagingCursor -EndpointSpec $EndpointSpec -InitialUri $InitialUri -InitialBody $InitialBody -Headers $Headers -RetryProfile $effectiveRetryProfile -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'none' {
            $retrySettings = Resolve-RetryRuntimeSettings -RetryProfile $effectiveRetryProfile
            $singleEndpointSpec = [pscustomobject]@{
                method = $EndpointSpec.method
                itemsPath = $EndpointSpec.itemsPath
            }

            $responseEnvelope = Invoke-RequestWithRetry -Request ([pscustomobject]@{
                Uri = $InitialUri
                Method = $EndpointSpec.method
                Headers = $Headers
                Body = $InitialBody
            }) -RetrySettings $retrySettings -RequestInvoker $RequestInvoker -RunEvents $RunEvents

            $response = $responseEnvelope
            if ($null -ne $responseEnvelope -and $responseEnvelope.PSObject.Properties.Name -contains 'Result') {
                $response = $responseEnvelope.Result
            }

            $pageItems = Get-PagingItemsFromResponse -Response $response -ItemsPath $singleEndpointSpec.itemsPath
            $telemetry = [System.Collections.Generic.List[object]]::new()
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $pageItems) {
                $items.Add($item) | Out-Null
            }

            $progressEvent = [pscustomobject]@{
                eventType = 'paging.progress'
                profile = 'none'
                page = 1
                nextUri = $null
                totalHits = Get-PagingTotalHitsFromResponse -Response $response
                itemCount = $pageItems.Count
                timestampUtc = [DateTime]::UtcNow.ToString('o')
            }

            $RunEvents.Add($progressEvent)
            $telemetry.Add($progressEvent) | Out-Null

            return [pscustomobject]@{
                Items = $items
                PagingTelemetry = $telemetry
                RunEvents = $RunEvents
            }
        }
        default {
            throw "Unsupported paging profile '$($pagingProfile)' for endpoint '$($EndpointSpec.key)'."
        }
    }
}
### END: InvokeCoreEndpoint
