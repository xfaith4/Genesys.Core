function Invoke-AnalyticsConversationDetailsDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [string]$BaseUri = 'https://api.usw2.pure.cloud',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker,

        [hashtable]$DatasetParameters,

        [switch]$NoRedact
    )

    $submitEndpoint  = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'analytics.create.conversation.details.job.large.query'
    $statusEndpoint  = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'analytics.get.conversation.details.job.status'
    $resultsEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'analytics.get.conversation.details.job.results'

    $runEvents = [System.Collections.Generic.List[object]]::new()

    $body = [ordered]@{
        interval = Resolve-DatasetInterval -DatasetParameters $DatasetParameters -DefaultLookbackHours 24
        order    = 'asc'
        orderBy  = 'conversationStart'
    }

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('Order')) {
        $body.order = [string]$DatasetParameters['Order']
    }

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('OrderBy')) {
        $body.orderBy = [string]$DatasetParameters['OrderBy']
    }

    # Queue filter — segment-level attribute, passed as segmentFilters
    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('QueueIds')) {
        $rawQueueIds = $DatasetParameters['QueueIds']
        $queueIds = if ($rawQueueIds -is [array]) {
            @($rawQueueIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        } else {
            @([string]$rawQueueIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        }
        if ($queueIds.Count -gt 0) {
            $body.segmentFilters = @(
                [ordered]@{
                    type       = 'or'
                    predicates = @($queueIds | ForEach-Object {
                        [ordered]@{ type = 'dimension'; dimension = 'queueId'; operator = 'matches'; value = [string]$_ }
                    })
                }
            )
        }
    }

    # Conversation-level filters: conversationId and/or divisionIds
    $conversationFilters = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('ConversationId')) {
        $convId = [string]$DatasetParameters['ConversationId']
        if (-not [string]::IsNullOrWhiteSpace($convId)) {
            $conversationFilters.Add([ordered]@{
                type       = 'and'
                predicates = @([ordered]@{ type = 'dimension'; dimension = 'conversationId'; operator = 'matches'; value = $convId })
            })
        }
    }

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('DivisionIds')) {
        $rawDivisionIds = $DatasetParameters['DivisionIds']
        $divisionIds = if ($rawDivisionIds -is [array]) {
            @($rawDivisionIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        } else {
            @([string]$rawDivisionIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        }
        if ($divisionIds.Count -gt 0) {
            $conversationFilters.Add([ordered]@{
                type       = 'or'
                predicates = @($divisionIds | ForEach-Object {
                    [ordered]@{ type = 'dimension'; dimension = 'divisionId'; operator = 'matches'; value = [string]$_ }
                })
            })
        }
    }

    if ($conversationFilters.Count -gt 0) {
        $body.conversationFilters = $conversationFilters.ToArray()
    }

    $asyncProfile = [pscustomobject]@{
        transactionIdPath  = '$.jobId'
        statePath          = '$.state'
        terminalStates     = @('FULFILLED', 'FAILED', 'CANCELLED')
        successStates      = @('FULFILLED')
        submittedEventType = 'analytics.job.submitted'
        pollEventType      = 'analytics.job.poll'
        jobLabel           = 'Analytics conversation details job'
    }

    $jobResult = Invoke-AsyncJob `
        -SubmitEndpointSpec $submitEndpoint `
        -StatusEndpointSpec $statusEndpoint `
        -ResultsEndpointSpec $resultsEndpoint `
        -AsyncProfile $asyncProfile `
        -BaseUri $BaseUri `
        -Headers $Headers `
        -SubmitBody ($body | ConvertTo-Json -Depth 20) `
        -RunEvents $runEvents `
        -RequestInvoker $RequestInvoker

    $records = @($jobResult.Items)
    $sanitizedRecords = if ($NoRedact) {
        $records
    } else {
        @($records | ForEach-Object { Protect-RecordData -InputObject $_ })
    }

    $dataPath = Join-Path -Path $RunContext.dataFolder -ChildPath 'analytics-conversation-details.jsonl'
    foreach ($record in $sanitizedRecords) {
        Write-Jsonl -Path $dataPath -InputObject $record
    }

    foreach ($event in @($runEvents)) {
        Write-RunEvent -RunContext $RunContext -EventType $event.eventType -Payload $event | Out-Null
    }

    $summary = [ordered]@{
        datasetKey     = $RunContext.datasetKey
        runId          = $RunContext.runId
        totals         = [ordered]@{
            totalConversations = $sanitizedRecords.Count
        }
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    ($summary | ConvertTo-Json -Depth 100) | Set-Content -Path $RunContext.summaryPath -Encoding utf8

    Write-RunEvent -RunContext $RunContext -EventType 'run.completed' -Payload @{ itemCount = $sanitizedRecords.Count } | Out-Null
    Write-Manifest -RunContext $RunContext -Counts @{ itemCount = $sanitizedRecords.Count } | Out-Null

    return [pscustomobject]@{
        Items   = $sanitizedRecords
        Summary = $summary
    }
}
