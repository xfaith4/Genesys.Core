function Get-TransactionRetryProfile {
    [CmdletBinding()]
    param(
        [psobject]$EndpointSpec
    )

    $profileName = 'standard'
    $maxRetries = 3
    $allowRetryOnPost = $false

    if ($null -eq $EndpointSpec) {
        return [pscustomobject]@{
            profile = $profileName
            maxRetries = $maxRetries
            allowRetryOnPost = $allowRetryOnPost
        }
    }

    if ($EndpointSpec.PSObject.Properties.Name -contains 'retry' -and $null -ne $EndpointSpec.retry) {
        $retrySpec = $EndpointSpec.retry

        if ($retrySpec.PSObject.Properties.Name -contains 'profile' -and [string]::IsNullOrWhiteSpace([string]$retrySpec.profile) -eq $false) {
            $profileName = [string]$retrySpec.profile
        }

        if ($retrySpec.PSObject.Properties.Name -contains 'mode' -and [string]::IsNullOrWhiteSpace([string]$retrySpec.mode) -eq $false) {
            $profileName = [string]$retrySpec.mode
        }

        if ($retrySpec.PSObject.Properties.Name -contains 'maxRetries') {
            $maxRetries = [int]$retrySpec.maxRetries
        }

        if ($retrySpec.PSObject.Properties.Name -contains 'allowRetryOnPost') {
            $allowRetryOnPost = [bool]$retrySpec.allowRetryOnPost
        }

        if ($retrySpec.PSObject.Properties.Name -contains 'retryOnMethods' -and $allowRetryOnPost -eq $false) {
            foreach ($method in @($retrySpec.retryOnMethods)) {
                if ([string]::Equals([string]$method, 'POST', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $allowRetryOnPost = $true
                    break
                }
            }
        }
    }

    if ($profileName -ieq 'rateLimitAware' -and ($null -eq $EndpointSpec.retry -or $EndpointSpec.retry.PSObject.Properties.Name -notcontains 'maxRetries')) {
        $maxRetries = 4
    }

    return [pscustomobject]@{
        profile = $profileName
        maxRetries = $maxRetries
        allowRetryOnPost = $allowRetryOnPost
    }
}

function Join-TransactionEndpointUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUri,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [hashtable]$RouteValues
    )

    $resolvedPath = $Path
    if ($null -ne $RouteValues) {
        foreach ($key in $RouteValues.Keys) {
            $resolvedPath = $resolvedPath.Replace("{$($key)}", [string]$RouteValues[$key])
        }
    }

    if ($resolvedPath.StartsWith('http://') -or $resolvedPath.StartsWith('https://')) {
        return $resolvedPath
    }

    $trimmedBase = $BaseUri.TrimEnd('/')
    if ($resolvedPath.StartsWith('/')) {
        return "$($trimmedBase)$($resolvedPath)"
    }

    return "$($trimmedBase)/$($resolvedPath)"
}

function Get-TransactionRouteParameterName {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Fallback = 'transactionId'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Fallback
    }

    $match = [System.Text.RegularExpressions.Regex]::Match($Path, '\{([^}/]+)\}')
    if ($match.Success) {
        return [string]$match.Groups[1].Value
    }

    return $Fallback
}

function Invoke-TransactionResults {
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

        [string]$TransactionIdPath = '$.transactionId',

        [string]$StatePath = '$.state',

        [string[]]$TerminalStates = @('FULFILLED', 'FAILED', 'CANCELLED'),

        [string]$FulfilledState = 'FULFILLED',

        [string]$RouteParamName,

        [int]$MaxPolls = 60,

        [int]$PollIntervalSeconds = 2,

        [string]$EventPrefix = 'transaction',

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$SleepAction = { param([int]$Seconds) Start-Sleep -Seconds $Seconds },

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $submitBodyPayload = $SubmitBody
    if ($null -ne $submitBodyPayload -and $submitBodyPayload -isnot [string]) {
        $submitBodyPayload = $submitBodyPayload | ConvertTo-Json -Depth 100
    }

    $submitResult = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $SubmitEndpointSpec.key
        method = $SubmitEndpointSpec.method
        itemsPath = '$'
        paging = [pscustomobject]@{ profile = 'none' }
        retry = $SubmitEndpointSpec.retry
    }) -InitialUri (Join-TransactionEndpointUri -BaseUri $BaseUri -Path $SubmitEndpointSpec.path) -InitialBody $submitBodyPayload -Headers $Headers -RetryProfile (Get-TransactionRetryProfile -EndpointSpec $SubmitEndpointSpec) -RunEvents $RunEvents -RequestInvoker $RequestInvoker

    $submitEnvelope = @($submitResult.Items) | Select-Object -First 1
    $transactionId = [string](Get-PagingValueFromResponse -Response $submitEnvelope -Path $TransactionIdPath)
    if ([string]::IsNullOrWhiteSpace($transactionId) -and $null -ne $submitEnvelope -and $submitEnvelope.PSObject.Properties.Name -contains 'transactionId') {
        $transactionId = [string]$submitEnvelope.transactionId
    }

    if ([string]::IsNullOrWhiteSpace($transactionId)) {
        throw "Transaction submit did not return an id at '$($TransactionIdPath)'."
    }

    $routeKey = $RouteParamName
    if ([string]::IsNullOrWhiteSpace($routeKey)) {
        $routeKey = Get-TransactionRouteParameterName -Path $StatusEndpointSpec.path -Fallback 'transactionId'
    }

    $RunEvents.Add([pscustomobject]@{
        eventType = "$($EventPrefix).submitted"
        transactionId = $transactionId
        routeParam = $routeKey
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    })

    $normalizedTerminalStates = @($TerminalStates | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) -eq $false })
    $currentState = $null

    for ($poll = 1; $poll -le $MaxPolls; $poll++) {
        $statusUri = Join-TransactionEndpointUri -BaseUri $BaseUri -Path $StatusEndpointSpec.path -RouteValues @{ $routeKey = $transactionId }
        $statusResult = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = $StatusEndpointSpec.key
            method = $StatusEndpointSpec.method
            itemsPath = '$'
            paging = [pscustomobject]@{ profile = 'none' }
            retry = $StatusEndpointSpec.retry
        }) -InitialUri $statusUri -Headers $Headers -RetryProfile (Get-TransactionRetryProfile -EndpointSpec $StatusEndpointSpec) -RunEvents $RunEvents -RequestInvoker $RequestInvoker

        $statusEnvelope = @($statusResult.Items) | Select-Object -First 1
        $currentState = [string](Get-PagingValueFromResponse -Response $statusEnvelope -Path $StatePath)
        if ([string]::IsNullOrWhiteSpace($currentState) -and $null -ne $statusEnvelope -and $statusEnvelope.PSObject.Properties.Name -contains 'state') {
            $currentState = [string]$statusEnvelope.state
        }

        $RunEvents.Add([pscustomobject]@{
            eventType = "$($EventPrefix).poll"
            transactionId = $transactionId
            pollCount = $poll
            state = $currentState
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        })

        if ($normalizedTerminalStates -contains $currentState) {
            break
        }

        & $SleepAction $PollIntervalSeconds
    }

    $transactionLabel = 'Transaction'
    if ($EventPrefix -ceq 'audit.transaction') {
        $transactionLabel = 'Audit transaction'
    }

    if ($normalizedTerminalStates -contains $currentState -and [string]::Equals($currentState, $FulfilledState, [System.StringComparison]::OrdinalIgnoreCase) -eq $false) {
        throw "$($transactionLabel) ended in state '$($currentState)'."
    }

    if ([string]::Equals($currentState, $FulfilledState, [System.StringComparison]::OrdinalIgnoreCase) -eq $false) {
        throw "$($transactionLabel) did not reach terminal '$($FulfilledState)' state after $($MaxPolls) polls."
    }

    $resultsRouteKey = $RouteParamName
    if ([string]::IsNullOrWhiteSpace($resultsRouteKey)) {
        $resultsRouteKey = Get-TransactionRouteParameterName -Path $ResultsEndpointSpec.path -Fallback $routeKey
    }

    $resultsUri = Join-TransactionEndpointUri -BaseUri $BaseUri -Path $ResultsEndpointSpec.path -RouteValues @{ $resultsRouteKey = $transactionId }
    $results = Invoke-CoreEndpoint -EndpointSpec $ResultsEndpointSpec -InitialUri $resultsUri -Headers $Headers -RetryProfile (Get-TransactionRetryProfile -EndpointSpec $ResultsEndpointSpec) -RunEvents $RunEvents -RequestInvoker $RequestInvoker

    $RunEvents.Add([pscustomobject]@{
        eventType = "$($EventPrefix).completed"
        transactionId = $transactionId
        itemCount = (@($results.Items)).Count
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    })

    return [pscustomobject]@{
        TransactionId = $transactionId
        Items = @($results.Items)
        RunEvents = $RunEvents
    }
}

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

    return Invoke-TransactionResults -SubmitEndpointSpec $SubmitEndpointSpec -StatusEndpointSpec $StatusEndpointSpec -ResultsEndpointSpec $ResultsEndpointSpec -BaseUri $BaseUri -Headers $Headers -SubmitBody $SubmitBody -MaxPolls $MaxPolls -PollIntervalSeconds $PollIntervalSeconds -RunEvents $RunEvents -SleepAction $SleepAction -RequestInvoker $RequestInvoker -EventPrefix 'audit.transaction' -TransactionIdPath '$.transactionId'
}
