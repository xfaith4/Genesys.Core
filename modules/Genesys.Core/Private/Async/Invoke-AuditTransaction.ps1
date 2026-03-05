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

    $transactionProfile = $null
    if ($SubmitEndpointSpec.PSObject.Properties.Name -contains 'transaction' -and $null -ne $SubmitEndpointSpec.transaction) {
        $transactionProfile = $SubmitEndpointSpec.transaction
    }

    $resolvedMaxPolls = $MaxPolls
    if (-not $PSBoundParameters.ContainsKey('MaxPolls') -and $null -ne $transactionProfile -and $transactionProfile.PSObject.Properties.Name -contains 'maxPolls' -and $null -ne $transactionProfile.maxPolls) {
        $resolvedMaxPolls = [int]$transactionProfile.maxPolls
    }

    $resolvedPollIntervalSeconds = $PollIntervalSeconds
    if (-not $PSBoundParameters.ContainsKey('PollIntervalSeconds') -and $null -ne $transactionProfile -and $transactionProfile.PSObject.Properties.Name -contains 'pollIntervalSeconds' -and $null -ne $transactionProfile.pollIntervalSeconds) {
        $resolvedPollIntervalSeconds = [int]$transactionProfile.pollIntervalSeconds
    }

    $asyncProfile = [ordered]@{
        transactionIdPath = '$.transactionId'
        statePath = '$.state'
        terminalStates = @('FULFILLED', 'FAILED', 'CANCELLED')
        successStates = @('FULFILLED')
        statusRouteValues = @{ transactionId = '{jobId}'; jobId = '{jobId}' }
        resultsRouteValues = @{ transactionId = '{jobId}'; jobId = '{jobId}' }
        submittedEventType = 'audit.transaction.submitted'
        pollEventType = 'audit.transaction.poll'
        jobLabel = 'Audit transaction'
        maxPolls = $resolvedMaxPolls
        pollIntervalSeconds = $resolvedPollIntervalSeconds
    }

    if ($null -ne $transactionProfile) {
        foreach ($property in $transactionProfile.PSObject.Properties) {
            $asyncProfile[$property.Name] = $property.Value
        }
    }

    $result = Invoke-AsyncJob -SubmitEndpointSpec $SubmitEndpointSpec -StatusEndpointSpec $StatusEndpointSpec -ResultsEndpointSpec $ResultsEndpointSpec -AsyncProfile ([pscustomobject]$asyncProfile) -BaseUri $BaseUri -Headers $Headers -SubmitBody $SubmitBody -MaxPolls $resolvedMaxPolls -PollIntervalSeconds $resolvedPollIntervalSeconds -RunEvents $RunEvents -SleepAction $SleepAction -RequestInvoker $RequestInvoker

    return [pscustomobject]@{
        TransactionId = $result.JobId
        Items = @($result.Items)
        RunEvents = $RunEvents
    }
}
