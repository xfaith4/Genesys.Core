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
            $nextUri = [string]$response.nextUri
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
