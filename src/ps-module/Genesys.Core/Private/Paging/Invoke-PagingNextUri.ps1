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

    if ($null -eq $RequestInvoker) {
        $RequestInvoker = {
            param($Request)

            Invoke-GcRequest -Uri $Request.Uri -Method $Request.Method -Headers $Request.Headers -Body $Request.Body -MaxRetries $Request.MaxRetries -AllowRetryOnPost:$Request.AllowRetryOnPost -RunEvents $Request.RunEvents
        }
    }

    $method = 'GET'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'method' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.method) -eq $false) {
        $method = [string]$EndpointSpec.method
    }

    $itemsPath = '$.results'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'itemsPath' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.itemsPath) -eq $false) {
        $itemsPath = [string]$EndpointSpec.itemsPath
    }

    $maxRetries = 3
    if ($null -ne $RetryProfile -and $RetryProfile.PSObject.Properties.Name -contains 'maxRetries') {
        $maxRetries = [int]$RetryProfile.maxRetries
    }

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

        $responseEnvelope = & $RequestInvoker ([pscustomobject]@{
            Uri = $currentUri
            Method = $method
            Headers = $Headers
            Body = $currentBody
            MaxRetries = $maxRetries
            AllowRetryOnPost = $false
            RunEvents = $RunEvents
        })

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
