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

    $maxRetries = 3
    if ($null -ne $RetryProfile -and $RetryProfile.PSObject.Properties.Name -contains 'maxRetries') {
        $maxRetries = [int]$RetryProfile.maxRetries
    }

    $allowRetryOnPost = $false
    if ($null -ne $RetryProfile -and $RetryProfile.PSObject.Properties.Name -contains 'allowRetryOnPost') {
        $allowRetryOnPost = [bool]$RetryProfile.allowRetryOnPost
    }

    $pagingProfile = 'none'
    if ($EndpointSpec.PSObject.Properties.Name -contains 'paging' -and $null -ne $EndpointSpec.paging) {
        if ($EndpointSpec.paging.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.paging.profile) -eq $false) {
            $pagingProfile = [string]$EndpointSpec.paging.profile
        }
    }

    $normalizedProfile = $pagingProfile.ToLowerInvariant()

    switch ($normalizedProfile) {
        'nexturi' {
            return Invoke-PagingNextUri -EndpointSpec $EndpointSpec -InitialUri $InitialUri -InitialBody $InitialBody -Headers $Headers -RetryProfile $RetryProfile -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'pagenumber' {
            return Invoke-PagingPageNumber -EndpointSpec $EndpointSpec -InitialUri $InitialUri -InitialBody $InitialBody -Headers $Headers -RetryProfile $RetryProfile -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'transactionresults' {
            if ($null -eq $EndpointSpec.PSObject.Properties['transaction']) {
                throw "transactionResults paging requires EndpointSpec.transaction metadata."
            }

            $transactionSpec = $EndpointSpec.transaction
            $submitEndpoint = $transactionSpec.submit
            if ($null -eq $submitEndpoint) {
                $submitEndpoint = [pscustomobject]@{
                    key = $EndpointSpec.key
                    method = $EndpointSpec.method
                    path = $EndpointSpec.path
                    itemsPath = '$'
                    retry = $EndpointSpec.retry
                }
            }

            if ($null -eq $transactionSpec.status -or $null -eq $transactionSpec.results) {
                throw "transactionResults paging requires transaction.status and transaction.results endpoint specs."
            }

            $transactionIdPath = '$.transactionId'
            if ($EndpointSpec.PSObject.Properties.Name -contains 'paging' -and $null -ne $EndpointSpec.paging -and $EndpointSpec.paging.PSObject.Properties.Name -contains 'transactionIdPath' -and [string]::IsNullOrWhiteSpace([string]$EndpointSpec.paging.transactionIdPath) -eq $false) {
                $transactionIdPath = [string]$EndpointSpec.paging.transactionIdPath
            }
            if ($transactionSpec.PSObject.Properties.Name -contains 'transactionIdPath' -and [string]::IsNullOrWhiteSpace([string]$transactionSpec.transactionIdPath) -eq $false) {
                $transactionIdPath = [string]$transactionSpec.transactionIdPath
            }

            $statePath = '$.state'
            if ($transactionSpec.PSObject.Properties.Name -contains 'statePath' -and [string]::IsNullOrWhiteSpace([string]$transactionSpec.statePath) -eq $false) {
                $statePath = [string]$transactionSpec.statePath
            }

            $terminalStates = @('FULFILLED', 'FAILED', 'CANCELLED')
            if ($transactionSpec.PSObject.Properties.Name -contains 'terminalStates' -and $null -ne $transactionSpec.terminalStates -and @($transactionSpec.terminalStates).Count -gt 0) {
                $terminalStates = @($transactionSpec.terminalStates)
            }

            $fulfilledState = 'FULFILLED'
            if ($transactionSpec.PSObject.Properties.Name -contains 'fulfilledState' -and [string]::IsNullOrWhiteSpace([string]$transactionSpec.fulfilledState) -eq $false) {
                $fulfilledState = [string]$transactionSpec.fulfilledState
            }

            $maxPolls = 60
            if ($transactionSpec.PSObject.Properties.Name -contains 'maxPolls') {
                $maxPolls = [int]$transactionSpec.maxPolls
            }

            $pollIntervalSeconds = 2
            if ($transactionSpec.PSObject.Properties.Name -contains 'pollIntervalSeconds') {
                $pollIntervalSeconds = [int]$transactionSpec.pollIntervalSeconds
            }

            $eventPrefix = 'transaction'
            if ($transactionSpec.PSObject.Properties.Name -contains 'eventPrefix' -and [string]::IsNullOrWhiteSpace([string]$transactionSpec.eventPrefix) -eq $false) {
                $eventPrefix = [string]$transactionSpec.eventPrefix
            }
            elseif ($transactionSpec.PSObject.Properties.Name -contains 'profile' -and [string]::Equals([string]$transactionSpec.profile, 'auditTransaction', [System.StringComparison]::OrdinalIgnoreCase)) {
                $eventPrefix = 'audit.transaction'
            }

            $routeParamName = $null
            if ($transactionSpec.PSObject.Properties.Name -contains 'routeParamName' -and [string]::IsNullOrWhiteSpace([string]$transactionSpec.routeParamName) -eq $false) {
                $routeParamName = [string]$transactionSpec.routeParamName
            }

            $baseUri = 'https://api.mypurecloud.com'
            if ($transactionSpec.PSObject.Properties.Name -contains 'baseUri' -and [string]::IsNullOrWhiteSpace([string]$transactionSpec.baseUri) -eq $false) {
                $baseUri = [string]$transactionSpec.baseUri
            }

            return Invoke-TransactionResults -SubmitEndpointSpec $submitEndpoint -StatusEndpointSpec $transactionSpec.status -ResultsEndpointSpec $transactionSpec.results -BaseUri $baseUri -Headers $Headers -SubmitBody $InitialBody -TransactionIdPath $transactionIdPath -StatePath $statePath -TerminalStates $terminalStates -FulfilledState $fulfilledState -RouteParamName $routeParamName -MaxPolls $maxPolls -PollIntervalSeconds $pollIntervalSeconds -EventPrefix $eventPrefix -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'bodypaging' {
            return Invoke-PagingBodyPaging -EndpointSpec $EndpointSpec -InitialUri $InitialUri -InitialBody $InitialBody -Headers $Headers -RetryProfile $RetryProfile -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'cursor' {
            return Invoke-PagingCursor -EndpointSpec $EndpointSpec -InitialUri $InitialUri -InitialBody $InitialBody -Headers $Headers -RetryProfile $RetryProfile -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        }
        'none' {
            $singleEndpointSpec = [pscustomobject]@{
                method = $EndpointSpec.method
                itemsPath = $EndpointSpec.itemsPath
            }

            $request = {
                param($Request)
                if ($null -ne $RequestInvoker) {
                    return & $RequestInvoker $Request
                }

                return Invoke-GcRequest -Uri $Request.Uri -Method $Request.Method -Headers $Request.Headers -Body $Request.Body -MaxRetries $Request.MaxRetries -AllowRetryOnPost:$Request.AllowRetryOnPost -RunEvents $Request.RunEvents
            }

            $responseEnvelope = & $request ([pscustomobject]@{
                Uri = $InitialUri
                Method = $EndpointSpec.method
                Headers = $Headers
                Body = $InitialBody
                MaxRetries = $maxRetries
                AllowRetryOnPost = $allowRetryOnPost
                RunEvents = $RunEvents
            })

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
