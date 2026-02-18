### BEGIN: InvokePagingBodyPaging
function ConvertTo-BodyPagingHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return @{}
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $value = $InputObject[$key]
            if ($value -is [System.Collections.IDictionary] -or $value -is [pscustomobject]) {
                $result[[string]$key] = ConvertTo-BodyPagingHashtable -InputObject $value
                continue
            }

            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $items = @()
                foreach ($item in $value) {
                    if ($item -is [System.Collections.IDictionary] -or $item -is [pscustomobject]) {
                        $items += ,(ConvertTo-BodyPagingHashtable -InputObject $item)
                    }
                    else {
                        $items += ,$item
                    }
                }

                $result[[string]$key] = $items
                continue
            }

            $result[[string]$key] = $value
        }

        return $result
    }

    if ($InputObject -is [pscustomobject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $value = $property.Value
            if ($value -is [System.Collections.IDictionary] -or $value -is [pscustomobject]) {
                $result[[string]$property.Name] = ConvertTo-BodyPagingHashtable -InputObject $value
                continue
            }

            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $items = @()
                foreach ($item in $value) {
                    if ($item -is [System.Collections.IDictionary] -or $item -is [pscustomobject]) {
                        $items += ,(ConvertTo-BodyPagingHashtable -InputObject $item)
                    }
                    else {
                        $items += ,$item
                    }
                }

                $result[[string]$property.Name] = $items
                continue
            }

            $result[[string]$property.Name] = $value
        }

        return $result
    }

    return @{}
}

function Set-BodyPagingValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $normalizedPath = [string]$Path
    if ($normalizedPath.StartsWith('$.')) {
        $normalizedPath = $normalizedPath.Substring(2)
    }

    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        throw 'Body paging page path cannot be empty.'
    }

    $segments = @($normalizedPath -split '\.' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false })
    if ($segments.Count -eq 0) {
        throw 'Body paging page path cannot be empty.'
    }

    $cursor = $Target
    for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
        $segment = [string]$segments[$i]
        $existing = $null
        if ($cursor.ContainsKey($segment)) {
            $existing = $cursor[$segment]
        }

        if ($null -eq $existing) {
            $cursor[$segment] = @{}
            $cursor = $cursor[$segment]
            continue
        }

        if ($existing -is [System.Collections.IDictionary]) {
            $cursor[$segment] = ConvertTo-BodyPagingHashtable -InputObject $existing
            $cursor = $cursor[$segment]
            continue
        }

        if ($existing -is [pscustomobject]) {
            $cursor[$segment] = ConvertTo-BodyPagingHashtable -InputObject $existing
            $cursor = $cursor[$segment]
            continue
        }

        $cursor[$segment] = @{}
        $cursor = $cursor[$segment]
    }

    $cursor[[string]$segments[$segments.Count - 1]] = $Value
}

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

    $pagePath = $pageParam
    if ($null -ne $pagingProfile -and $pagingProfile.PSObject.Properties.Name -contains 'pagePath' -and [string]::IsNullOrWhiteSpace([string]$pagingProfile.pagePath) -eq $false) {
        $pagePath = [string]$pagingProfile.pagePath
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

    $allowRetryOnPost = $false
    if ($null -ne $RetryProfile -and $RetryProfile.PSObject.Properties.Name -contains 'allowRetryOnPost') {
        $allowRetryOnPost = [bool]$RetryProfile.allowRetryOnPost
    }

    $baseBodyObject = @{}
    if ($null -ne $InitialBody) {
        if ($InitialBody -is [string] -and [string]::IsNullOrWhiteSpace($InitialBody) -eq $false) {
            $baseBodyObject = ConvertTo-BodyPagingHashtable -InputObject (ConvertFrom-Json -InputObject $InitialBody -Depth 100)
        }
        elseif ($InitialBody -is [System.Collections.IDictionary] -or $InitialBody -is [pscustomobject]) {
            $baseBodyObject = ConvertTo-BodyPagingHashtable -InputObject $InitialBody
        }
    }

    $telemetry = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()

    $pageNumber = 1
    $collectedCount = 0

    while ($pageNumber -le $maxPages) {
        $requestBody = ConvertTo-BodyPagingHashtable -InputObject $baseBodyObject

        Set-BodyPagingValue -Target $requestBody -Path $pagePath -Value $pageNumber
        $requestBodyJson = $requestBody | ConvertTo-Json -Depth 100

        $responseEnvelope = & $RequestInvoker ([pscustomobject]@{
            Uri = $InitialUri
            Method = $method
            Headers = $Headers
            Body = $requestBodyJson
            MaxRetries = $maxRetries
            AllowRetryOnPost = $allowRetryOnPost
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

        $nextUri = "$($InitialUri)#$($pagePath)=$($pageNumber + 1)"
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

    if ($pageNumber -gt $maxPages) {
        $RunEvents.Add([pscustomobject]@{
            eventType = 'paging.terminated.maxPages'
            profile = 'bodyPaging'
            page = $pageNumber
            maxPages = $maxPages
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        })
    }

    return [pscustomobject]@{
        Items = $items
        PagingTelemetry = $telemetry
        RunEvents = $RunEvents
    }
}
### END: InvokePagingBodyPaging
