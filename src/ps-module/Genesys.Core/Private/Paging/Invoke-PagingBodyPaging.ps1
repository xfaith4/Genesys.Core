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

    if ($null -eq $RequestInvoker) {
        $RequestInvoker = {
            param($Request)

            Invoke-GcRequest -Uri $Request.Uri -Method $Request.Method -Headers $Request.Headers -Body $Request.Body -MaxRetries $Request.MaxRetries -AllowRetryOnPost:$Request.AllowRetryOnPost -RunEvents $Request.RunEvents
        }
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

    $maxRetries = 3
    if ($null -ne $RetryProfile -and $RetryProfile.PSObject.Properties.Name -contains 'maxRetries') {
        $maxRetries = [int]$RetryProfile.maxRetries
    }

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

        $responseEnvelope = & $RequestInvoker ([pscustomobject]@{
            Uri = $InitialUri
            Method = $method
            Headers = $Headers
            Body = $requestBodyJson
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
