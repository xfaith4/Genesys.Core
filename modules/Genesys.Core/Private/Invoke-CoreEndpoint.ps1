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
