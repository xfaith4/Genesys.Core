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
