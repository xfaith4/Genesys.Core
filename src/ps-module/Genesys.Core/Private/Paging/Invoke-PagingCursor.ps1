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
