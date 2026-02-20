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
