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

function Get-AsyncDiagnosticPrefix {
    [CmdletBinding()]
    param(
        [psobject]$AsyncProfile
    )

    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'diagnosticPrefix' -and [string]::IsNullOrWhiteSpace([string]$AsyncProfile.diagnosticPrefix) -eq $false) {
        return [string]$AsyncProfile.diagnosticPrefix
    }

    return ''
}

function Get-AsyncEndpointPath {
    [CmdletBinding()]
    param(
        [psobject]$EndpointSpec
    )

    if ($null -ne $EndpointSpec -and $EndpointSpec.PSObject.Properties.Name -contains 'path') {
        return [string]$EndpointSpec.path
    }

    return ''
}

function Get-RunEventsSince {
    [CmdletBinding()]
    param(
        [AllowNull()][System.Collections.Generic.List[object]]$RunEvents,
        [int]$StartIndex = 0
    )

    if ($null -eq $RunEvents -or $RunEvents.Count -le $StartIndex) {
        return @()
    }

    $events = New-Object System.Collections.Generic.List[object]
    for ($i = $StartIndex; $i -lt $RunEvents.Count; $i++) {
        $events.Add($RunEvents[$i]) | Out-Null
    }

    return $events.ToArray()
}

function Get-LastAsyncRequestEvent {
    [CmdletBinding()]
    param(
        [AllowNull()][System.Collections.Generic.List[object]]$RunEvents,
        [string]$EndpointKey
    )

    if ($null -eq $RunEvents -or [string]::IsNullOrWhiteSpace([string]$EndpointKey)) {
        return $null
    }

    for ($i = $RunEvents.Count - 1; $i -ge 0; $i--) {
        $event = $RunEvents[$i]
        if ($null -eq $event) {
            continue
        }

        if ($event.PSObject.Properties.Name -contains 'eventType' -and
            $event.PSObject.Properties.Name -contains 'endpointKey' -and
            [string]$event.endpointKey -eq [string]$EndpointKey -and
            @('request.completed', 'request.failed') -contains [string]$event.eventType) {
            return $event
        }
    }

    return $null
}

function Add-AsyncDiagnosticEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EventType,

        [hashtable]$Payload = @{}
    )

    $event = [ordered]@{
        eventType = $EventType
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    }

    foreach ($key in $Payload.Keys) {
        $event[$key] = $Payload[$key]
    }

    $RunEvents.Add([pscustomobject]$event) | Out-Null
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
    if ($null -eq $jobIdValue -or [string]::IsNullOrWhiteSpace([string]$jobIdValue)) {
        foreach ($fallbackPath in @('$.id', '$.transactionId', '$.jobId')) {
            if ($fallbackPath -eq $jobIdPath) {
                continue
            }

            $jobIdValue = Get-AsyncValueFromResponse -Response $submitEnvelope -Path $fallbackPath
            if ($null -ne $jobIdValue -and -not [string]::IsNullOrWhiteSpace([string]$jobIdValue)) {
                $jobIdPath = $fallbackPath
                break
            }
        }
    }

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

    $diagnosticPrefix = Get-AsyncDiagnosticPrefix -AsyncProfile $AsyncProfile
    if (-not [string]::IsNullOrWhiteSpace($diagnosticPrefix)) {
        $requestEvent = Get-LastAsyncRequestEvent -RunEvents $RunEvents -EndpointKey $SubmitEndpointSpec.key
        Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.submitted" -Payload @{
            transactionId = $jobId
            endpointPath = Get-AsyncEndpointPath -EndpointSpec $SubmitEndpointSpec
            httpStatusCode = if ($null -ne $requestEvent) { $requestEvent.statusCode } else { $null }
            elapsedMs = if ($null -ne $requestEvent) { $requestEvent.durationMs } else { $null }
        }
        Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.transactionId.received" -Payload @{
            transactionId = $jobId
            transactionIdPath = $jobIdPath
            endpointPath = Get-AsyncEndpointPath -EndpointSpec $SubmitEndpointSpec
        }
    }

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
        $dynamicTerminalStates = @(
            Get-AsyncValueFromResponse -Response $statusEnvelope -Path $terminalStatesPath |
                ForEach-Object { [string]$_ } |
                Where-Object { [string]::IsNullOrWhiteSpace([string]$_) -eq $false }
        )
        if ($dynamicTerminalStates.Count -gt 0) {
            $terminalStates = @($dynamicTerminalStates)
        }
    }

    $successStates = @('FULFILLED')
    if ($null -ne $AsyncProfile -and $AsyncProfile.PSObject.Properties.Name -contains 'successStates' -and $null -ne $AsyncProfile.successStates) {
        $successStates = @($AsyncProfile.successStates | ForEach-Object { [string]$_ } | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) -eq $false })
    }

    $state = ([string](Get-AsyncValueFromResponse -Response $statusEnvelope -Path $statePath)).Trim()
    $isTerminal = @($terminalStates | Where-Object {
        [string]::Equals(([string]$_).Trim(), $state, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0
    $isSuccess = @($successStates | Where-Object {
        [string]::Equals(([string]$_).Trim(), $state, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0

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

    Write-GcProgressMessage -Message "$($jobLabel) submitted. Job id: $($jobId)"

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

        $diagnosticPrefix = Get-AsyncDiagnosticPrefix -AsyncProfile $AsyncProfile
        if (-not [string]::IsNullOrWhiteSpace($diagnosticPrefix)) {
            $requestEvent = Get-LastAsyncRequestEvent -RunEvents $RunEvents -EndpointKey $StatusEndpointSpec.key
            Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.status.poll" -Payload @{
                transactionId = $jobId
                status = $currentState
                pollCount = $poll
                endpointPath = Get-AsyncEndpointPath -EndpointSpec $StatusEndpointSpec
                httpStatusCode = if ($null -ne $requestEvent) { $requestEvent.statusCode } else { $null }
                elapsedMs = if ($null -ne $requestEvent) { $requestEvent.durationMs } else { $null }
            }
        }

        Write-GcProgressMessage -Message "$($jobLabel) poll $($poll)/$($MaxPolls): state '$($currentState)'."

        if ($latestStatus.IsTerminal) {
            break
        }

        & $SleepAction $PollIntervalSeconds
    }

    $diagnosticPrefix = Get-AsyncDiagnosticPrefix -AsyncProfile $AsyncProfile
    if (-not [string]::IsNullOrWhiteSpace($diagnosticPrefix) -and $null -ne $latestStatus -and $latestStatus.IsTerminal) {
        Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.status.complete" -Payload @{
            transactionId = $jobId
            status = $currentState
            isSuccess = [bool]$latestStatus.IsSuccess
            endpointPath = Get-AsyncEndpointPath -EndpointSpec $StatusEndpointSpec
        }
    }

    if ($null -ne $latestStatus -and $latestStatus.IsTerminal -and -not $latestStatus.IsSuccess) {
        if (-not [string]::IsNullOrWhiteSpace($diagnosticPrefix)) {
            Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.failed" -Payload @{
                transactionId = $jobId
                status = $currentState
                reason = "$($jobLabel) ended in state '$($currentState)'."
                endpointPath = Get-AsyncEndpointPath -EndpointSpec $StatusEndpointSpec
            }
        }
        throw "$($jobLabel) ended in state '$($currentState)'."
    }

    $successStateLabel = 'terminal success'
    if ($null -ne $latestStatus -and @($latestStatus.SuccessStates).Count -gt 0) {
        $successStateLabel = [string]::Join(', ', @($latestStatus.SuccessStates))
    }

    if ($null -eq $latestStatus -or -not $latestStatus.IsTerminal) {
        if (-not [string]::IsNullOrWhiteSpace($diagnosticPrefix)) {
            Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.failed" -Payload @{
                transactionId = $jobId
                status = $currentState
                reason = "$($jobLabel) did not reach terminal $($successStateLabel) state after $($MaxPolls) polls."
                endpointPath = Get-AsyncEndpointPath -EndpointSpec $StatusEndpointSpec
            }
        }
        throw "$($jobLabel) did not reach terminal $($successStateLabel) state after $($MaxPolls) polls."
    }

    $beforeResultsEventCount = $RunEvents.Count
    $results = Get-AsyncJobResults -ResultsEndpointSpec $ResultsEndpointSpec -JobId $jobId -AsyncProfile $AsyncProfile -BaseUri $BaseUri -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker
    if (-not [string]::IsNullOrWhiteSpace($diagnosticPrefix)) {
        $resultEvents = @(Get-RunEventsSince -RunEvents $RunEvents -StartIndex $beforeResultsEventCount)
        $requestEvents = @($resultEvents | Where-Object { $_.eventType -in @('request.completed', 'request.failed') -and $_.endpointKey -eq $ResultsEndpointSpec.key })
        $pagingEvents = @($resultEvents | Where-Object { $_.eventType -eq 'paging.progress' })

        for ($i = 0; $i -lt $requestEvents.Count; $i++) {
            Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.results.page.requested" -Payload @{
                transactionId = $jobId
                page = $i + 1
                endpointPath = Get-AsyncEndpointPath -EndpointSpec $ResultsEndpointSpec
                httpStatusCode = $requestEvents[$i].statusCode
                elapsedMs = $requestEvents[$i].durationMs
                pageSize = $null
            }
        }

        foreach ($pageEvent in $pagingEvents) {
            Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.results.page.written" -Payload @{
                transactionId = $jobId
                page = $pageEvent.page
                endpointPath = Get-AsyncEndpointPath -EndpointSpec $ResultsEndpointSpec
                recordsWritten = $pageEvent.itemCount
                cursorPresent = -not [string]::IsNullOrWhiteSpace([string]$pageEvent.cursor)
                nextUriPresent = -not [string]::IsNullOrWhiteSpace([string]$pageEvent.nextUri)
            }
        }

        $resultCount = @($results.Items).Count
        if ($resultCount -eq 0) {
            Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.no_results" -Payload @{
                transactionId = $jobId
                status = $currentState
                recordsWritten = 0
                reason = 'No matching audits were returned by the results endpoint.'
                endpointPath = Get-AsyncEndpointPath -EndpointSpec $ResultsEndpointSpec
            }
        }

        Add-AsyncDiagnosticEvent -RunEvents $RunEvents -EventType "$diagnosticPrefix.results.complete" -Payload @{
            transactionId = $jobId
            status = $currentState
            recordsWritten = $resultCount
            endpointPath = Get-AsyncEndpointPath -EndpointSpec $ResultsEndpointSpec
        }
    }
    Write-GcProgressMessage -Message "$($jobLabel) results received. Items: $(@($results.Items).Count)."

    return [pscustomobject]@{
        JobId = $jobId
        Items = @($results.Items)
        RunEvents = $RunEvents
        FinalState = $currentState
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
        diagnosticPrefix = 'audit.query'
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
