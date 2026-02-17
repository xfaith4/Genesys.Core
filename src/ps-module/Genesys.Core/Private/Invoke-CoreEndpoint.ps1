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
                MaxRetries = 3
                AllowRetryOnPost = $false
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
