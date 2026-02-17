function Invoke-AuditTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SubmitEndpointSpec,

        [Parameter(Mandatory = $true)]
        [psobject]$StatusEndpointSpec,

        [Parameter(Mandatory = $true)]
        [psobject]$ResultsEndpointSpec,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [object]$SubmitBody,

        [int]$MaxPolls = 60,

        [int]$PollIntervalSeconds = 2,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$SleepAction = { param([int]$Seconds) Start-Sleep -Seconds $Seconds },

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $submitResult = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $SubmitEndpointSpec.key
        method = $SubmitEndpointSpec.method
        itemsPath = '$'
        paging = [pscustomobject]@{ profile = 'none' }
    }) -InitialUri (Join-EndpointUri -BaseUri $BaseUri -Path $SubmitEndpointSpec.path) -InitialBody ($SubmitBody | ConvertTo-Json -Depth 50) -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker

    $submitEnvelope = @($submitResult.Items) | Select-Object -First 1
    if ($null -eq $submitEnvelope -or [string]::IsNullOrWhiteSpace([string]$submitEnvelope.transactionId)) {
        throw 'Audit transaction submit did not return transactionId.'
    }

    $transactionId = [string]$submitEnvelope.transactionId
    $RunEvents.Add([pscustomobject]@{
        eventType = 'audit.transaction.submitted'
        transactionId = $transactionId
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    })

    $terminalStates = @('FULFILLED', 'FAILED', 'CANCELLED')
    $currentState = $null

    for ($poll = 1; $poll -le $MaxPolls; $poll++) {
        $statusUri = Join-EndpointUri -BaseUri $BaseUri -Path $StatusEndpointSpec.path -RouteValues @{ transactionId = $transactionId }
        $statusResult = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = $StatusEndpointSpec.key
            method = $StatusEndpointSpec.method
            itemsPath = '$'
            paging = [pscustomobject]@{ profile = 'none' }
        }) -InitialUri $statusUri -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker

        $statusEnvelope = @($statusResult.Items) | Select-Object -First 1
        $currentState = [string]$statusEnvelope.state

        $RunEvents.Add([pscustomobject]@{
            eventType = 'audit.transaction.poll'
            transactionId = $transactionId
            pollCount = $poll
            state = $currentState
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        })

        if ($terminalStates -contains $currentState) {
            break
        }

        & $SleepAction $PollIntervalSeconds
    }

    if ($terminalStates -contains $currentState -and $currentState -ne 'FULFILLED') {
        throw "Audit transaction ended in state '$($currentState)'."
    }

    if ($currentState -ne 'FULFILLED') {
        throw "Audit transaction did not reach terminal FULFILLED state after $($MaxPolls) polls."
    }

    $resultsUri = Join-EndpointUri -BaseUri $BaseUri -Path $ResultsEndpointSpec.path -RouteValues @{ transactionId = $transactionId }
    $resultsPagingProfile = 'nextUri'
    if ($ResultsEndpointSpec.PSObject.Properties.Name -contains 'paging' -and $ResultsEndpointSpec.paging.PSObject.Properties.Name -contains 'profile') {
        $resultsPagingProfile = [string]$ResultsEndpointSpec.paging.profile
    }

    $results = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $ResultsEndpointSpec.key
        method = $ResultsEndpointSpec.method
        itemsPath = $ResultsEndpointSpec.itemsPath
        paging = [pscustomobject]@{ profile = $resultsPagingProfile }
    }) -InitialUri $resultsUri -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker

    return [pscustomobject]@{
        TransactionId = $transactionId
        Items = @($results.Items)
        RunEvents = $RunEvents
    }
}
