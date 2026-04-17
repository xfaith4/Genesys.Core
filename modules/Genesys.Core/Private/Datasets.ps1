function ConvertTo-PlainOrderedMap {
    [CmdletBinding()]
    param(
        [object]$InputObject
    )

    $result = [ordered]@{}
    if ($null -eq $InputObject) {
        return $result
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = $InputObject[$key]
        }

        return $result
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $result[[string]$property.Name] = $property.Value
    }

    return $result
}

function Resolve-DatasetInterval {
    [CmdletBinding()]
    param(
        [hashtable]$DatasetParameters,
        [ValidateRange(1, 720)]
        [int]$DefaultLookbackHours
    )

    $utcNow = [DateTime]::UtcNow

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('Interval')) {
        $interval = [string]$DatasetParameters['Interval']
        if (-not [string]::IsNullOrWhiteSpace($interval)) {
            return $interval
        }
    }

    $startUtc = $null
    $endUtc = $null

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('StartUtc')) {
        $startUtc = [DateTime]::Parse([string]$DatasetParameters['StartUtc']).ToUniversalTime()
    }

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('EndUtc')) {
        $endUtc = [DateTime]::Parse([string]$DatasetParameters['EndUtc']).ToUniversalTime()
    }

    if ($null -eq $startUtc -and $null -eq $endUtc) {
        $lookbackHours = $DefaultLookbackHours
        if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('LookbackHours')) {
            $lookbackHours = [int]$DatasetParameters['LookbackHours']
        }

        if ($lookbackHours -lt 1 -or $lookbackHours -gt 720) {
            throw "LookbackHours must be between 1 and 720. Received '$($lookbackHours)'."
        }

        $startUtc = $utcNow.AddHours(-1 * $lookbackHours)
        $endUtc = $utcNow
    }
    else {
        if ($null -eq $startUtc) {
            throw 'StartUtc is required when EndUtc is provided.'
        }

        if ($null -eq $endUtc) {
            throw 'EndUtc is required when StartUtc is provided.'
        }

        if ($startUtc -ge $endUtc) {
            throw "StartUtc must be earlier than EndUtc. Received StartUtc '$($startUtc.ToString('o'))' and EndUtc '$($endUtc.ToString('o'))'."
        }
    }

    return "$($startUtc.ToString('o'))/$($endUtc.ToString('o'))"
}

function Get-CatalogEndpointByKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [psobject]$DatasetSpec
    )

    foreach ($endpoint in @($Catalog.endpoints)) {
        if ($endpoint.key -eq $Key) {
            return Resolve-EndpointSpecProfiles -Catalog $Catalog -EndpointSpec $endpoint -DatasetSpec $DatasetSpec
        }
    }

    throw "Endpoint '$($Key)' was not found in catalog."
}

function Resolve-AuditTransactionEndpoints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [psobject]$SubmitEndpoint
    )

    if ($null -ne $SubmitEndpoint.transaction -and [string]::IsNullOrWhiteSpace([string]$SubmitEndpoint.transaction.statusEndpointRef) -eq $false -and [string]::IsNullOrWhiteSpace([string]$SubmitEndpoint.transaction.resultsEndpointRef) -eq $false) {
        return [pscustomobject]@{
            status = Get-CatalogEndpointByKey -Catalog $Catalog -Key ([string]$SubmitEndpoint.transaction.statusEndpointRef)
            results = Get-CatalogEndpointByKey -Catalog $Catalog -Key ([string]$SubmitEndpoint.transaction.resultsEndpointRef)
        }
    }

    if ($null -ne $SubmitEndpoint.transaction -and [string]::IsNullOrWhiteSpace([string]$SubmitEndpoint.transaction.profile) -eq $false) {
        $profileName = [string]$SubmitEndpoint.transaction.profile
        if ($null -ne $Catalog.profiles -and $null -ne $Catalog.profiles.transaction -and $Catalog.profiles.transaction.PSObject.Properties.Name -contains $profileName) {
            $profile = $Catalog.profiles.transaction.$profileName
            $statusEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key $profile.statusEndpointRef
            $resultsEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key $profile.resultsEndpointRef
            return [pscustomobject]@{ status = $statusEndpoint; results = $resultsEndpoint }
        }
    }

    return [pscustomobject]@{
        status = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.query.status'
        results = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.query.results'
    }
}

function Invoke-AuditLogsDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker,

        [hashtable]$DatasetParameters,

        [switch]$NoRedact
    )

    $datasetSpec = $Catalog.datasets['audit-logs']
    $mappingEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.get.service.mapping'
    $submitEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.query.submit' -DatasetSpec $datasetSpec
    $transactionEndpoints = Resolve-AuditTransactionEndpoints -Catalog $Catalog -SubmitEndpoint $submitEndpoint
    $statusEndpoint = $transactionEndpoints.status
    $resultsEndpoint = $transactionEndpoints.results

    $runEvents = [System.Collections.Generic.List[object]]::new()

    $mappingResponse = Invoke-CoreEndpoint -EndpointSpec $mappingEndpoint -InitialUri (Join-EndpointUri -BaseUri $BaseUri -Path $mappingEndpoint.path) -Headers $Headers -RunEvents $runEvents -RequestInvoker $RequestInvoker
    $serviceMappings = @($mappingResponse.Items)

    $body = [ordered]@{
        interval = Resolve-DatasetInterval -DatasetParameters $DatasetParameters -DefaultLookbackHours 1
        serviceName = @()
        action = @()
    }

    if ($serviceMappings.Count -gt 0) {
        $body.serviceName = @($serviceMappings | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.PSObject.Properties.Name -contains 'serviceName') { $_.serviceName } } | Where-Object { $_ })
    }

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('ServiceNames')) {
        $body.serviceName = @($DatasetParameters['ServiceNames'])
    }

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('Actions')) {
        $body.action = @($DatasetParameters['Actions'])
    }

    $transactionResult = Invoke-AuditTransaction -SubmitEndpointSpec $submitEndpoint -StatusEndpointSpec $statusEndpoint -ResultsEndpointSpec $resultsEndpoint -BaseUri $BaseUri -Headers $Headers -SubmitBody $body -RunEvents $runEvents -RequestInvoker $RequestInvoker

    $records = @($transactionResult.Items)
    $sanitizedRecords = if ($NoRedact) {
        $records
    } else {
        @($records | ForEach-Object { Protect-RecordData -InputObject $_ })
    }

    $dataPath = Join-Path -Path $RunContext.dataFolder -ChildPath 'audit.jsonl'
    foreach ($record in $sanitizedRecords) {
        Write-Jsonl -Path $dataPath -InputObject $record
    }

    foreach ($event in @($runEvents)) {
        Write-RunEvent -RunContext $RunContext -EventType $event.eventType -Payload $event | Out-Null
    }

    $summary = [ordered]@{
        datasetKey = $RunContext.datasetKey
        runId = $RunContext.runId
        totals = [ordered]@{
            totalRecords = $sanitizedRecords.Count
            totalServices = (@($sanitizedRecords | ForEach-Object { $_.serviceName } | Where-Object { $_ } | Select-Object -Unique)).Count
            totalActions = (@($sanitizedRecords | ForEach-Object { $_.action } | Where-Object { $_ } | Select-Object -Unique)).Count
        }
        countsByAction = [ordered]@{}
        countsByServiceName = [ordered]@{}
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    foreach ($group in ($sanitizedRecords | Group-Object -Property action)) {
        if ([string]::IsNullOrWhiteSpace([string]$group.Name)) {
            continue
        }

        $summary.countsByAction[$group.Name] = $group.Count
    }

    foreach ($group in ($sanitizedRecords | Group-Object -Property serviceName)) {
        if ([string]::IsNullOrWhiteSpace([string]$group.Name)) {
            continue
        }

        $summary.countsByServiceName[$group.Name] = $group.Count
    }

    $summary | ConvertTo-Json -Depth 100 | Set-Content -Path $RunContext.summaryPath -Encoding utf8

    Write-RunEvent -RunContext $RunContext -EventType 'run.completed' -Payload @{ itemCount = $sanitizedRecords.Count } | Out-Null
    Write-Manifest -RunContext $RunContext -Counts @{ itemCount = $sanitizedRecords.Count } | Out-Null
    Write-GcProgressMessage -Message "Wrote $($sanitizedRecords.Count) audit record(s) to $($dataPath)."
    Write-GcProgressMessage -Message "API call log: $($RunContext.apiLogPath)"

    return [pscustomobject]@{
        Items = $sanitizedRecords
        Summary = $summary
    }
}

function Get-DatasetRegistry {
    [CmdletBinding()]
    param()

    return @{
        'audit-logs'                        = 'Invoke-AuditLogsDataset'
        'analytics-conversation-details'    = 'Invoke-AnalyticsConversationDetailsDataset'
        'users'                             = 'Invoke-UsersDataset'
        'routing-queues'                    = 'Invoke-RoutingQueuesDataset'
    }
}

function ConvertTo-DatasetDataFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Dataset
    )

    $safeName = [System.Text.RegularExpressions.Regex]::Replace($Dataset, '[^A-Za-z0-9._-]', '-')
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'dataset'
    }

    return "$($safeName).jsonl"
}

function ConvertTo-IdentityRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    return $InputObject
}

function Invoke-RegisteredDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Dataset,

        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker,

        [hashtable]$DatasetParameters,

        [switch]$NoRedact
    )

    $registry = Get-DatasetRegistry
    if ($registry.ContainsKey($Dataset)) {
        $commandName = $registry[$Dataset]
        & $commandName -RunContext $RunContext -Catalog $Catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -NoRedact:$NoRedact
        return
    }

    if ($null -ne $Catalog.datasets -and $Catalog.datasets.ContainsKey($Dataset)) {
        $dataFileName = ConvertTo-DatasetDataFileName -Dataset $Dataset
        Invoke-SimpleCollectionDataset -RunContext $RunContext -Catalog $Catalog -DatasetKey $Dataset -DataFileName $dataFileName -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -Normalizer ${function:ConvertTo-IdentityRecord} -NoRedact:$NoRedact
        return
    }

    throw "Unsupported dataset '$($Dataset)'. Available datasets: $([string]::Join(', ', $registry.Keys))."
}

function Resolve-DatasetEndpointSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [string]$DatasetKey
    )

    if ($null -eq $Catalog.datasets -or -not $Catalog.datasets.ContainsKey($DatasetKey)) {
        throw "Dataset '$($DatasetKey)' was not found in catalog datasets."
    }

    $dataset = $Catalog.datasets[$DatasetKey]
    $endpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key $dataset.endpoint
    $endpoint = Resolve-EndpointSpecProfiles -Catalog $Catalog -EndpointSpec $endpoint -DatasetSpec $dataset

    return [pscustomobject]@{
        Dataset = $dataset
        Endpoint = $endpoint
    }
}

function ConvertTo-EndpointDefaultParameters {
    [CmdletBinding()]
    param(
        [object]$DefaultQueryParams
    )

    $result = [ordered]@{}
    if ($null -eq $DefaultQueryParams) {
        return $result
    }

    if ($DefaultQueryParams -is [System.Collections.IDictionary]) {
        foreach ($key in $DefaultQueryParams.Keys) {
            $result[[string]$key] = $DefaultQueryParams[$key]
        }

        return $result
    }

    foreach ($property in $DefaultQueryParams.PSObject.Properties) {
        $result[[string]$property.Name] = $property.Value
    }

    return $result
}

function Resolve-EndpointInitialUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUri,

        [Parameter(Mandatory = $true)]
        [psobject]$Endpoint,

        [hashtable]$DatasetParameters
    )

    $routeValues = [ordered]@{}
    $queryValues = [ordered]@{}
    $defaultParams = ConvertTo-EndpointDefaultParameters -DefaultQueryParams $Endpoint.defaultQueryParams
    $overrideQueryParams = [ordered]@{}
    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('Query')) {
        $overrideQueryParams = ConvertTo-PlainOrderedMap -InputObject $DatasetParameters['Query']
    }


    foreach ($queryKey in $overrideQueryParams.Keys) {
        $defaultParams[$queryKey] = $overrideQueryParams[$queryKey]
    }

    foreach ($paramName in $defaultParams.Keys) {
        $token = "{$($paramName)}"
        if ([string]$Endpoint.path -like "*$($token)*") {
            $routeValues[$paramName] = $defaultParams[$paramName]
            continue
        }

        $queryValues[$paramName] = $defaultParams[$paramName]
    }

    $uri = Join-EndpointUri -BaseUri $BaseUri -Path $Endpoint.path -RouteValues $routeValues
    foreach ($queryName in $queryValues.Keys) {
        $uri = Add-PagingQueryValue -Uri $uri -Name $queryName -Value $queryValues[$queryName]
    }

    return $uri
}

function Write-DatasetOutputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[object]]$RunEvents,

        [Parameter(Mandatory = $true)]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [string]$DataFileName,

        [Parameter(Mandatory = $true)]
        [hashtable]$Summary
    )

    $dataPath = Join-Path -Path $RunContext.dataFolder -ChildPath $DataFileName
    foreach ($record in $Records) {
        Write-Jsonl -Path $dataPath -InputObject $record
    }

    foreach ($event in @($RunEvents)) {
        Write-RunEvent -RunContext $RunContext -EventType $event.eventType -Payload $event | Out-Null
    }

    ($Summary | ConvertTo-Json -Depth 100) | Set-Content -Path $RunContext.summaryPath -Encoding utf8

    Write-RunEvent -RunContext $RunContext -EventType 'run.completed' -Payload @{ itemCount = $Records.Count } | Out-Null
    Write-Manifest -RunContext $RunContext -Counts @{ itemCount = $Records.Count } | Out-Null
    Write-GcProgressMessage -Message "Wrote $($Records.Count) record(s) to $($dataPath)."
    Write-GcProgressMessage -Message "API call log: $($RunContext.apiLogPath)"
}

function Invoke-SimpleCollectionDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [string]$DatasetKey,

        [Parameter(Mandatory = $true)]
        [string]$DataFileName,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Normalizer,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker,

        [hashtable]$DatasetParameters,

        [switch]$NoRedact
    )

    $resolvedSpec = Resolve-DatasetEndpointSpec -Catalog $Catalog -DatasetKey $DatasetKey
    $dataset = $resolvedSpec.Dataset
    $endpoint = $resolvedSpec.Endpoint

    $runEvents = [System.Collections.Generic.List[object]]::new()
    $initialUri = Resolve-EndpointInitialUri -BaseUri $BaseUri -Endpoint $endpoint -DatasetParameters $DatasetParameters

    $response = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $endpoint.key
        method = $endpoint.method
        path = $endpoint.path
        itemsPath = $dataset.itemsPath
        paging = $endpoint.paging
        retry = $endpoint.retry
        transaction = $endpoint.transaction
    }) -InitialUri $initialUri -Headers $Headers -RunEvents $runEvents -RequestInvoker $RequestInvoker

    $records = @($response.Items | ForEach-Object { & $Normalizer $_ })
    $sanitizedRecords = if ($NoRedact) {
        $records
    } else {
        @($records | ForEach-Object { Protect-RecordData -InputObject $_ })
    }

    $summary = [ordered]@{
        datasetKey = $RunContext.datasetKey
        runId = $RunContext.runId
        totals = [ordered]@{ totalRecords = $sanitizedRecords.Count }
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    Write-DatasetOutputs -RunContext $RunContext -RunEvents $runEvents -Records $sanitizedRecords -DataFileName $DataFileName -Summary $summary

    return [pscustomobject]@{ Items = $sanitizedRecords; Summary = $summary }
}

function ConvertTo-NormalizedUserRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$InputObject)

    return [ordered]@{
        recordType = 'user'
        id = $InputObject.id
        name = $InputObject.name
        email = $InputObject.email
        state = $InputObject.state
        presence = $(if ($null -ne $InputObject.presence) { $InputObject.presence.presenceDefinition.systemPresence } else { $null })
        routingStatus = $(if ($null -ne $InputObject.routingStatus) { $InputObject.routingStatus.status } else { $null })
    }
}

function Invoke-UsersDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker,

        [hashtable]$DatasetParameters,

        [switch]$NoRedact
    )

    Invoke-SimpleCollectionDataset -RunContext $RunContext -Catalog $Catalog -DatasetKey 'users' -DataFileName 'users.jsonl' -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -Normalizer ${function:ConvertTo-NormalizedUserRecord} -NoRedact:$NoRedact
}

function ConvertTo-NormalizedQueueRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$InputObject)

    return [ordered]@{
        recordType = 'routingQueue'
        id = $InputObject.id
        name = $InputObject.name
        divisionId = $(if ($null -ne $InputObject.division) { $InputObject.division.id } else { $null })
        memberCount = $InputObject.memberCount
        joined = $InputObject.joined
    }
}

function Invoke-RoutingQueuesDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker,

        [hashtable]$DatasetParameters,

        [switch]$NoRedact
    )

    Invoke-SimpleCollectionDataset -RunContext $RunContext -Catalog $Catalog -DatasetKey 'routing-queues' -DataFileName 'routing-queues.jsonl' -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -Normalizer ${function:ConvertTo-NormalizedQueueRecord} -NoRedact:$NoRedact
}

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
        terminalStates     = @('FULFILLED', 'COMPLETED', 'COMPLETE', 'SUCCEEDED', 'SUCCESS', 'FAILED', 'CANCELLED', 'CANCELED', 'EXPIRED')
        successStates      = @('FULFILLED', 'COMPLETED', 'COMPLETE', 'SUCCEEDED', 'SUCCESS')
        pollIntervalSeconds = 2
        maxPolls           = 300
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
    Write-GcProgressMessage -Message "Wrote $($sanitizedRecords.Count) conversation record(s) to $($dataPath)."
    Write-GcProgressMessage -Message "API call log: $($RunContext.apiLogPath)"
    return [pscustomobject]@{
        Items   = $sanitizedRecords
        Summary = $summary
    }
}
