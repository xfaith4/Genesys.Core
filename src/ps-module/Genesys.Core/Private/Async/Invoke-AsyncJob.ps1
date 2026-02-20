function Get-AsyncValueFromResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response,

        [string]$Path = '$'
    )

    if ($null -eq $Response) {
        return $null
    }

    $normalizedPath = [string]$Path
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        return $Response
    }

    if ($normalizedPath -eq '$' -or $normalizedPath -eq '$.') {
        return $Response
    }

    if ($normalizedPath.StartsWith('$.')) {
        $normalizedPath = $normalizedPath.Substring(2)
    }

    $target = $Response
    foreach ($segment in ($normalizedPath -split '\.')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        if ($null -eq $target) {
            return $null
        }

        if ($target -is [System.Collections.IDictionary]) {
            $target = $target[$segment]
            continue
        }

        if ($target.PSObject.Properties.Name -contains $segment) {
            $target = $target.$segment
            continue
        }

        return $null
    }

    return $target
}

function Resolve-AsyncJobRouteValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$JobId,

        [object]$RouteValues
    )

    $resolved = @{}
    foreach ($match in [regex]::Matches($Path, '\{([^{}]+)\}')) {
        $resolved[$match.Groups[1].Value] = $JobId
    }

    if ($null -eq $RouteValues) {
        return $resolved
    }

    $entries = @()
    if ($RouteValues -is [System.Collections.IDictionary]) {
        foreach ($key in $RouteValues.Keys) {
            $entries += [pscustomobject]@{
                Name = [string]$key
                Value = $RouteValues[$key]
            }
        }
    }
    else {
        foreach ($property in $RouteValues.PSObject.Properties) {
            $entries += [pscustomobject]@{
                Name = $property.Name
                Value = $property.Value
            }
        }
    }

    foreach ($entry in $entries) {
        $value = [string]$entry.Value
        if ($value -eq '{jobId}' -or $value -eq '{transactionId}') {
            $resolved[$entry.Name] = $JobId
        }
        else {
            $resolved[$entry.Name] = $entry.Value
        }
    }

    return $resolved
}

function Submit-AsyncJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SubmitEndpointSpec,

        [psobject]$AsyncProfile,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [object]$SubmitBody,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $submitBodyValue = $SubmitBody
    if ($null -ne $SubmitBody -and $SubmitBody -isnot [string]) {
        $submitBodyValue = $SubmitBody | ConvertTo-Json -Depth 50
    }

    $submitResult = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $SubmitEndpointSpec.key
        method = $SubmitEndpointSpec.method
        itemsPath = '$'
        paging = [pscustomobject]@{ profile = 'none' }
        retry = $SubmitEndpointSpec.retry
    }) -InitialUri (Join-EndpointUri -BaseUri $BaseUri -Path $SubmitEndpointSpec.path) -InitialBody $submitBodyValue -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker

    $submitEnvelope = @($submitResult.Items) | Select-Object -First 1
    $jobIdPath = '$.transactionId'
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'transactionIdPath' -and [string]::IsNullOrWhiteSpace([string]$AsyncProfile.transactionIdPath) -eq $false) {
        $jobIdPath = [string]$AsyncProfile.transactionIdPath
    }

    $jobIdValue = Get-AsyncValueFromResponse -Response $submitEnvelope -Path $jobIdPath
    $jobId = [string]$jobIdValue
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        throw "Async job submit did not return id at path '$($jobIdPath)'."
    }

    $submittedEventType = 'async.job.submitted'
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'submittedEventType' -and [string]::IsNullOrWhiteSpace([string]$AsyncProfile.submittedEventType) -eq $false) {
        $submittedEventType = [string]$AsyncProfile.submittedEventType
    }

    $RunEvents.Add([pscustomobject]@{
        eventType = $submittedEventType
        jobId = $jobId
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    })

    return [pscustomobject]@{
        JobId = $jobId
        Envelope = $submitEnvelope
    }
}

function Get-AsyncJobStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$StatusEndpointSpec,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$JobId,

        [psobject]$AsyncProfile,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $statusRouteValues = $null
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'statusRouteValues') {
        $statusRouteValues = $AsyncProfile.statusRouteValues
    }

    $statusUri = Join-EndpointUri -BaseUri $BaseUri -Path $StatusEndpointSpec.path -RouteValues (Resolve-AsyncJobRouteValues -Path $StatusEndpointSpec.path -JobId $JobId -RouteValues $statusRouteValues)
    $statusResult = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $StatusEndpointSpec.key
        method = $StatusEndpointSpec.method
        itemsPath = '$'
        paging = [pscustomobject]@{ profile = 'none' }
        retry = $StatusEndpointSpec.retry
    }) -InitialUri $statusUri -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker

    $statusEnvelope = @($statusResult.Items) | Select-Object -First 1
    $statePath = '$.state'
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'statePath' -and [string]::IsNullOrWhiteSpace([string]$AsyncProfile.statePath) -eq $false) {
        $statePath = [string]$AsyncProfile.statePath
    }

    $terminalStatesPath = $null
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'terminalStatesPath' -and [string]::IsNullOrWhiteSpace([string]$AsyncProfile.terminalStatesPath) -eq $false) {
        $terminalStatesPath = [string]$AsyncProfile.terminalStatesPath
    }

    $terminalStates = @('FULFILLED', 'FAILED', 'CANCELLED')
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'terminalStates' -and $null -ne $AsyncProfile.terminalStates) {
        $terminalStates = @($AsyncProfile.terminalStates | ForEach-Object { [string]$_ } | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) -eq $false })
    }

    if ([string]::IsNullOrWhiteSpace([string]$terminalStatesPath) -eq $false) {
        $dynamicTerminalStates = @(Get-AsyncValueFromResponse -Response $statusEnvelope -Path $terminalStatesPath)
        if ($dynamicTerminalStates.Count -gt 0) {
            $terminalStates = @($dynamicTerminalStates | ForEach-Object { [string]$_ } | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) -eq $false })
        }
    }

    $successStates = @('FULFILLED')
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'successStates' -and $null -ne $AsyncProfile.successStates) {
        $successStates = @($AsyncProfile.successStates | ForEach-Object { [string]$_ } | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) -eq $false })
    }

    $state = [string](Get-AsyncValueFromResponse -Response $statusEnvelope -Path $statePath)
    $isTerminal = $terminalStates -contains $state
    $isSuccess = $successStates -contains $state

    return [pscustomobject]@{
        JobId = $JobId
        State = $state
        IsTerminal = $isTerminal
        IsSuccess = $isSuccess
        TerminalStates = @($terminalStates)
        SuccessStates = @($successStates)
        Envelope = $statusEnvelope
    }
}

function Get-AsyncJobResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$ResultsEndpointSpec,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$JobId,

        [psobject]$AsyncProfile,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $resultsRouteValues = $null
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'resultsRouteValues') {
        $resultsRouteValues = $AsyncProfile.resultsRouteValues
    }

    $resultsUri = Join-EndpointUri -BaseUri $BaseUri -Path $ResultsEndpointSpec.path -RouteValues (Resolve-AsyncJobRouteValues -Path $ResultsEndpointSpec.path -JobId $JobId -RouteValues $resultsRouteValues)
    $resultsPaging = [pscustomobject]@{ profile = 'nextUri' }
    if ($ResultsEndpointSpec.PSObject.Properties.Name -contains 'paging' -and $null -ne $ResultsEndpointSpec.paging) {
        $resultsPaging = $ResultsEndpointSpec.paging
    }

    return Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $ResultsEndpointSpec.key
        method = $ResultsEndpointSpec.method
        itemsPath = $ResultsEndpointSpec.itemsPath
        paging = $resultsPaging
        retry = $ResultsEndpointSpec.retry
    }) -InitialUri $resultsUri -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker
}

function Invoke-AsyncJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SubmitEndpointSpec,

        [Parameter(Mandatory = $true)]
        [psobject]$StatusEndpointSpec,

        [Parameter(Mandatory = $true)]
        [psobject]$ResultsEndpointSpec,

        [psobject]$AsyncProfile,

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

    if ($null -ne $AsyncProfile) {
        if (-not $PSBoundParameters.ContainsKey('MaxPolls') -and $AsyncProfile.PSObject.Properties.Name -contains 'maxPolls' -and $null -ne $AsyncProfile.maxPolls) {
            $MaxPolls = [int]$AsyncProfile.maxPolls
        }

        if (-not $PSBoundParameters.ContainsKey('PollIntervalSeconds') -and $AsyncProfile.PSObject.Properties.Name -contains 'pollIntervalSeconds' -and $null -ne $AsyncProfile.pollIntervalSeconds) {
            $PollIntervalSeconds = [int]$AsyncProfile.pollIntervalSeconds
        }
    }

    $submit = Submit-AsyncJob -SubmitEndpointSpec $SubmitEndpointSpec -AsyncProfile $AsyncProfile -BaseUri $BaseUri -Headers $Headers -SubmitBody $SubmitBody -RunEvents $RunEvents -RequestInvoker $RequestInvoker
    $jobId = [string]$submit.JobId

    $jobLabel = 'Async job'
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'jobLabel' -and [string]::IsNullOrWhiteSpace([string]$AsyncProfile.jobLabel) -eq $false) {
        $jobLabel = [string]$AsyncProfile.jobLabel
    }

    $pollEventType = 'async.job.poll'
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'pollEventType' -and [string]::IsNullOrWhiteSpace([string]$AsyncProfile.pollEventType) -eq $false) {
        $pollEventType = [string]$AsyncProfile.pollEventType
    }

    $currentState = $null
    $latestStatus = $null
    for ($poll = 1; $poll -le $MaxPolls; $poll++) {
        $latestStatus = Get-AsyncJobStatus -StatusEndpointSpec $StatusEndpointSpec -JobId $jobId -AsyncProfile $AsyncProfile -BaseUri $BaseUri -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker
        $currentState = [string]$latestStatus.State

        $RunEvents.Add([pscustomobject]@{
            eventType = $pollEventType
            jobId = $jobId
            pollCount = $poll
            state = $currentState
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        })

        if ($latestStatus.IsTerminal) {
            break
        }

        & $SleepAction $PollIntervalSeconds
    }

    if ($null -ne $latestStatus -and $latestStatus.IsTerminal -and -not $latestStatus.IsSuccess) {
        throw "$($jobLabel) ended in state '$($currentState)'."
    }

    $successStateLabel = 'terminal success'
    if ($null -ne $latestStatus -and @($latestStatus.SuccessStates).Count -gt 0) {
        $successStateLabel = [string]::Join(', ', @($latestStatus.SuccessStates))
    }

    if ($null -eq $latestStatus -or -not $latestStatus.IsTerminal) {
        throw "$($jobLabel) did not reach terminal $($successStateLabel) state after $($MaxPolls) polls."
    }

    $results = Get-AsyncJobResults -ResultsEndpointSpec $ResultsEndpointSpec -JobId $jobId -AsyncProfile $AsyncProfile -BaseUri $BaseUri -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker

    return [pscustomobject]@{
        JobId = $jobId
        Items = @($results.Items)
        RunEvents = $RunEvents
        FinalState = $currentState
    }
}
