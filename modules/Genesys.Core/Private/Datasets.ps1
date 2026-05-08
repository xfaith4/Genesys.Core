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

function ConvertTo-DatasetRequestBodyJson {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$BodyValue,

        [hashtable]$DatasetParameters
    )

    if ($null -eq $BodyValue) {
        return $null
    }

    $bodyObject = $null
    if ($BodyValue -is [string]) {
        if ([string]::IsNullOrWhiteSpace($BodyValue)) {
            return $BodyValue
        }

        try {
            $bodyObject = $BodyValue | ConvertFrom-Json
        } catch {
            return $BodyValue
        }
    } else {
        $bodyObject = $BodyValue
    }

    if ($null -ne $DatasetParameters -and (
            $DatasetParameters.ContainsKey('Interval') -or
            $DatasetParameters.ContainsKey('StartUtc') -or
            $DatasetParameters.ContainsKey('EndUtc') -or
            $DatasetParameters.ContainsKey('LookbackHours'))) {
        $interval = Resolve-DatasetInterval -DatasetParameters $DatasetParameters -DefaultLookbackHours 24
        if ($bodyObject -is [System.Collections.IDictionary]) {
            $bodyObject['interval'] = $interval
        } else {
            $intervalProp = $bodyObject.PSObject.Properties['interval']
            if ($intervalProp) {
                $intervalProp.Value = $interval
            } else {
                $bodyObject | Add-Member -NotePropertyName 'interval' -NotePropertyValue $interval -Force
            }
        }
    }

    return ($bodyObject | ConvertTo-Json -Depth 100)
}

function Resolve-DatasetParameterValues {
    [CmdletBinding()]
    param(
        [hashtable]$DatasetParameters,
        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )

    if ($null -eq $DatasetParameters -or -not $DatasetParameters.ContainsKey($ParameterName)) {
        return @()
    }

    $rawValues = $DatasetParameters[$ParameterName]
    if ($rawValues -is [array]) {
        return @($rawValues | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    return @([string]$rawValues -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Resolve-SingleAuditFilterValue {
    [CmdletBinding()]
    param(
        [hashtable]$DatasetParameters,
        [Parameter(Mandatory = $true)]
        [string]$ParameterName,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    if ($null -eq $DatasetParameters -or -not $DatasetParameters.ContainsKey($ParameterName)) {
        return $null
    }

    $values = @(
        @($DatasetParameters[$ParameterName]) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($values.Count -gt 1) {
        throw "Genesys Audit API supports only one $DisplayName filter per request. Received $($values.Count)."
    }

    if ($values.Count -eq 0) {
        return $null
    }

    return $values[0]
}

function Add-AuditBodyFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Filters,
        [Parameter(Mandatory = $true)]
        [string]$Property,
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $Filters.Add([ordered]@{
        property = $Property
        value = $Value
    }) | Out-Null
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

function Write-AuditDatasetRunEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [AllowNull()]
        [System.Collections.Generic.List[object]]$RunEvents
    )

    if ($null -eq $RunEvents) {
        return
    }

    foreach ($event in @($RunEvents)) {
        if ($null -eq $event -or -not ($event.PSObject.Properties.Name -contains 'eventType')) {
            continue
        }

        Write-RunEvent -RunContext $RunContext -EventType $event.eventType -Payload $event | Out-Null
    }
}

function Invoke-AuditServiceMappingStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$RequestInvoker
    )

    $mappingEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'getAuditsQueryServicemapping'
    $mappingUri = Join-EndpointUri -BaseUri $BaseUri -Path $mappingEndpoint.path

    $mappingResult = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $mappingEndpoint.key
        method = $mappingEndpoint.method
        itemsPath = $mappingEndpoint.itemsPath
        paging = $mappingEndpoint.paging
        retry = $mappingEndpoint.retry
    }) -InitialUri $mappingUri -Headers $Headers -RunEvents $RunEvents -RequestInvoker $RequestInvoker

    $requestEvent = $null
    for ($i = $RunEvents.Count - 1; $i -ge 0; $i--) {
        $candidate = $RunEvents[$i]
        if ($candidate.PSObject.Properties.Name -contains 'eventType' -and
            $candidate.PSObject.Properties.Name -contains 'endpointKey' -and
            $candidate.eventType -eq 'request.completed' -and
            $candidate.endpointKey -eq $mappingEndpoint.key) {
            $requestEvent = $candidate
            break
        }
    }

    $RunEvents.Add([pscustomobject]@{
        eventType = 'audit.servicemapping.loaded'
        datasetKey = 'audit-logs'
        endpointPath = [string]$mappingEndpoint.path
        serviceCount = @($mappingResult.Items).Count
        httpStatusCode = if ($null -ne $requestEvent) { $requestEvent.statusCode } else { $null }
        elapsedMs = if ($null -ne $requestEvent) { $requestEvent.durationMs } else { $null }
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null

    return $mappingResult
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
    $submitEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.query.submit' -DatasetSpec $datasetSpec
    $transactionEndpoints = Resolve-AuditTransactionEndpoints -Catalog $Catalog -SubmitEndpoint $submitEndpoint
    $statusEndpoint = $transactionEndpoints.status
    $resultsEndpoint = $transactionEndpoints.results

    $runEvents = [System.Collections.Generic.List[object]]::new()

    $body = [ordered]@{
        interval = Resolve-DatasetInterval -DatasetParameters $DatasetParameters -DefaultLookbackHours 1
        filters = @()
        sort = @(
            [ordered]@{
                name = 'Timestamp'
                sortOrder = 'descending'
            }
        )
    }

    $serviceName = Resolve-SingleAuditFilterValue -DatasetParameters $DatasetParameters -ParameterName 'ServiceNames' -DisplayName 'serviceName'
    if (-not [string]::IsNullOrWhiteSpace($serviceName)) {
        $body.serviceName = $serviceName
    }

    $action = Resolve-SingleAuditFilterValue -DatasetParameters $DatasetParameters -ParameterName 'Actions' -DisplayName 'Action'
    $entityType = Resolve-SingleAuditFilterValue -DatasetParameters $DatasetParameters -ParameterName 'EntityTypes' -DisplayName 'EntityType'
    $entityId = Resolve-SingleAuditFilterValue -DatasetParameters $DatasetParameters -ParameterName 'EntityIds' -DisplayName 'EntityId'
    $userId = Resolve-SingleAuditFilterValue -DatasetParameters $DatasetParameters -ParameterName 'UserIds' -DisplayName 'UserId'
    if (-not [string]::IsNullOrWhiteSpace($action) -and [string]::IsNullOrWhiteSpace($entityType)) {
        throw 'Genesys Audit API requires an EntityType filter when Action is supplied.'
    }

    $filters = [System.Collections.Generic.List[object]]::new()
    Add-AuditBodyFilter -Filters $filters -Property 'EntityType' -Value $entityType
    Add-AuditBodyFilter -Filters $filters -Property 'Action' -Value $action
    Add-AuditBodyFilter -Filters $filters -Property 'EntityId' -Value $entityId
    Add-AuditBodyFilter -Filters $filters -Property 'UserId' -Value $userId
    $body.filters = @($filters.ToArray())

    try {
        Invoke-AuditServiceMappingStep -Catalog $Catalog -BaseUri $BaseUri -Headers $Headers -RunEvents $runEvents -RequestInvoker $RequestInvoker | Out-Null
        $transactionResult = Invoke-AuditTransaction -SubmitEndpointSpec $submitEndpoint -StatusEndpointSpec $statusEndpoint -ResultsEndpointSpec $resultsEndpoint -BaseUri $BaseUri -Headers $Headers -SubmitBody $body -RunEvents $runEvents -RequestInvoker $RequestInvoker
    }
    catch {
        $runEvents.Add([pscustomobject]@{
            eventType = 'audit.query.failed'
            datasetKey = $RunContext.datasetKey
            endpointPath = '/api/v2/audits/query'
            reason = $_.Exception.Message
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        }) | Out-Null
        Write-AuditDatasetRunEvents -RunContext $RunContext -RunEvents $runEvents
        throw
    }

    $records = @($transactionResult.Items)
    $sanitizedRecords = if ($NoRedact) {
        $records
    } else {
        $redactionProfile = Resolve-DatasetRedactionProfile -Catalog $Catalog -DatasetKey 'audit-logs'
        @($records | ForEach-Object { Protect-RecordData -InputObject $_ -Profile $redactionProfile })
    }

    $dataPath = Join-Path -Path $RunContext.dataFolder -ChildPath 'audit.jsonl'
    foreach ($record in $sanitizedRecords) {
        Write-Jsonl -Path $dataPath -InputObject $record
    }

    Write-AuditDatasetRunEvents -RunContext $RunContext -RunEvents $runEvents

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
        'audit-logs'                                    = 'Invoke-AuditLogsDataset'
        'analytics-conversation-details'                = 'Invoke-AnalyticsConversationDetailsDataset'
        'analytics-conversation-timeline-analysis'      = 'Invoke-ConversationTimelineAnalysisDataset'
        'users'                                         = 'Invoke-UsersDataset'
        'routing-queues'                                = 'Invoke-RoutingQueuesDataset'
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
    $initialBody = $null
    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('Body')) {
        $initialBody = ConvertTo-DatasetRequestBodyJson -BodyValue $DatasetParameters['Body'] -DatasetParameters $DatasetParameters
    }
    elseif ($endpoint.PSObject.Properties.Name -contains 'defaultBody' -and $null -ne $endpoint.defaultBody) {
        $initialBody = ConvertTo-DatasetRequestBodyJson -BodyValue $endpoint.defaultBody -DatasetParameters $DatasetParameters
    }

    $response = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $endpoint.key
        method = $endpoint.method
        path = $endpoint.path
        itemsPath = $dataset.itemsPath
        paging = $endpoint.paging
        retry = $endpoint.retry
        transaction = $endpoint.transaction
    }) -InitialUri $initialUri -InitialBody $initialBody -Headers $Headers -RunEvents $runEvents -RequestInvoker $RequestInvoker

    $records = @($response.Items | ForEach-Object { & $Normalizer $_ })
    $sanitizedRecords = if ($NoRedact) {
        $records
    } else {
        $redactionProfile = Resolve-DatasetRedactionProfile -Catalog $Catalog -DatasetKey $DatasetKey
        @($records | ForEach-Object { Protect-RecordData -InputObject $_ -Profile $redactionProfile })
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

    $segmentFilters = [System.Collections.Generic.List[object]]::new()

    $queueIds = @(Resolve-DatasetParameterValues -DatasetParameters $DatasetParameters -ParameterName 'QueueIds')
    if ($queueIds.Count -gt 0) {
        $segmentFilters.Add([ordered]@{
            type       = 'or'
            predicates = @($queueIds | ForEach-Object {
                [ordered]@{ type = 'dimension'; dimension = 'queueId'; operator = 'matches'; value = [string]$_ }
            })
        })
    }

    $userIds = @(Resolve-DatasetParameterValues -DatasetParameters $DatasetParameters -ParameterName 'UserIds')
    if ($userIds.Count -gt 0) {
        $segmentFilters.Add([ordered]@{
            type       = 'or'
            predicates = @($userIds | ForEach-Object {
                [ordered]@{ type = 'dimension'; dimension = 'userId'; operator = 'matches'; value = [string]$_ }
            })
        })
    }

    if ($segmentFilters.Count -gt 0) {
        $body.segmentFilters = $segmentFilters.ToArray()
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

    $divisionIds = @(Resolve-DatasetParameterValues -DatasetParameters $DatasetParameters -ParameterName 'DivisionIds')
    if ($divisionIds.Count -gt 0) {
        $conversationFilters.Add([ordered]@{
            type       = 'or'
            predicates = @($divisionIds | ForEach-Object {
                [ordered]@{ type = 'dimension'; dimension = 'divisionId'; operator = 'matches'; value = [string]$_ }
            })
        })
    }

    $mediaTypes = @(Resolve-DatasetParameterValues -DatasetParameters $DatasetParameters -ParameterName 'MediaTypes')
    if ($mediaTypes.Count -gt 0) {
        $conversationFilters.Add([ordered]@{
            type       = 'or'
            predicates = @($mediaTypes | ForEach-Object {
                [ordered]@{ type = 'dimension'; dimension = 'mediaType'; operator = 'matches'; value = [string]$_ }
            })
        })
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

    # Body override — when a pre-built JSON body is supplied by the caller (e.g., from a
    # query template), use it directly instead of the body assembled from named parameters.
    $submitBodyJson = if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('Body')) {
        $bodyValue = $DatasetParameters['Body']
        if ($bodyValue -is [string]) { $bodyValue } else { $bodyValue | ConvertTo-Json -Depth 100 }
    } else {
        $body | ConvertTo-Json -Depth 20
    }

    $jobResult = Invoke-AsyncJob `
        -SubmitEndpointSpec $submitEndpoint `
        -StatusEndpointSpec $statusEndpoint `
        -ResultsEndpointSpec $resultsEndpoint `
        -AsyncProfile $asyncProfile `
        -BaseUri $BaseUri `
        -Headers $Headers `
        -SubmitBody $submitBodyJson `
        -RunEvents $runEvents `
        -RequestInvoker $RequestInvoker

    $records = @($jobResult.Items)
    $sanitizedRecords = if ($NoRedact) {
        $records
    } else {
        $redactionProfile = Resolve-DatasetRedactionProfile -Catalog $Catalog -DatasetKey 'analytics-conversation-details'
        @($records | ForEach-Object { Protect-RecordData -InputObject $_ -Profile $redactionProfile })
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

# ─────────────────────────────────────────────────────────────────────────────
# Conversation Timeline Analysis — compound dataset handler
# Dataset key : analytics-conversation-timeline-analysis
# Design doc  : genesys_conversation_timeline_analysis_technical_design.md
#
# Phases:
#   1. Analytics extraction (async job or sync preview query)
#   2. Build conversation index → timeline-index.json
#   3. Per-conversation enrichment fan-out (non-fatal individual failures)
#   4. Timeline event normalization → timeline-events.jsonl
#   5. Aggregate outputs (conversations.jsonl, summary.json, errors.jsonl)
# ─────────────────────────────────────────────────────────────────────────────

function _Get-BoolParam {
    param([hashtable]$Params, [string]$Key, [bool]$Default)
    if ($null -ne $Params -and $Params.ContainsKey($Key)) {
        $v = $Params[$Key]
        if ($v -is [bool]) { return $v }
        return [System.Convert]::ToBoolean([string]$v)
    }
    return $Default
}

function _Invoke-EnrichmentGet {
    <#
    .SYNOPSIS
        Calls a single GET enrichment endpoint and returns the parsed response or $null on failure.
        Failures are non-fatal; they write to the errors list.
    #>
    param(
        [Parameter(Mandatory)][string]$EndpointKey,
        [Parameter(Mandatory)][string]$ConversationId,
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][scriptblock]$RequestInvoker,
        [Parameter(Mandatory)][psobject]$Catalog,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$ErrorList,
        [string]$ExtraRouteKey = '',
        [string]$ExtraRouteValue = ''
    )

    try {
        $ep = Get-CatalogEndpointByKey -Catalog $Catalog -Key $EndpointKey
        $path = [string]$ep.path -replace '\{conversationId\}', $ConversationId
        if (-not [string]::IsNullOrWhiteSpace($ExtraRouteKey) -and -not [string]::IsNullOrWhiteSpace($ExtraRouteValue)) {
            $path = $path -replace "\{$ExtraRouteKey\}", $ExtraRouteValue
        }
        $uri = Join-EndpointUri -BaseUri $BaseUri -Path $path
        $runEvents = [System.Collections.Generic.List[object]]::new()
        $result = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key        = $ep.key
            method     = $ep.method
            path       = $path
            itemsPath  = '.$'
            paging     = [pscustomobject]@{ profile = 'none' }
            retry      = $ep.retry
            transaction = $null
        }) -InitialUri $uri -Headers $Headers -RunEvents $runEvents -RequestInvoker $RequestInvoker
        return $result.Items
    }
    catch {
        $ErrorList.Add([ordered]@{
            conversationId = $ConversationId
            sourceEndpoint = $EndpointKey
            status         = 'failed'
            message        = $_.Exception.Message
        }) | Out-Null
        return $null
    }
}

function _New-TimelineEvent {
    param(
        [string]$ConversationId,
        [string]$EventTime,
        [string]$EventType,
        [string]$Source,
        [string]$ParticipantId = $null,
        [string]$SessionId = $null,
        [string]$CommunicationId = $null,
        [int]$Sequence = 50,
        [string]$Label,
        [object]$Details = $null,
        [object]$RawRef = $null
    )
    return [ordered]@{
        conversationId  = $ConversationId
        eventTime       = $EventTime
        eventType       = $EventType
        source          = $Source
        participantId   = $ParticipantId
        sessionId       = $SessionId
        communicationId = $CommunicationId
        sequence        = $Sequence
        label           = $Label
        details         = $Details
        rawRef          = $RawRef
    }
}

function _Get-EventPriority {
    param([string]$EventType)
    switch -Wildcard ($EventType) {
        'conversation.*'     { return 10 }
        'participant.*'      { return 20 }
        'session.*'          { return 20 }
        'segment.ivr'        { return 30 }
        'segment.flow'       { return 30 }
        'segment.routing'    { return 30 }
        'segment.alert'      { return 40 }
        'segment.talk'       { return 40 }
        'segment.hold'       { return 40 }
        'segment.acw'        { return 40 }
        'segment.transfer'   { return 50 }
        'segment.consult'    { return 50 }
        'segment.conference' { return 50 }
        'attribute.*'        { return 60 }
        'suggestion.*'       { return 70 }
        'speech.*'           { return 80 }
        'recording.*'        { return 90 }
        'disconnect.*'       { return 100 }
        'enrichment.warning' { return 900 }
        default              { return 50 }
    }
}

function _ConvertTo-AnalyticsTimelineEvents {
    param(
        [Parameter(Mandatory)][object]$Conversation
    )

    $events = [System.Collections.Generic.List[object]]::new()
    $convId = [string]$Conversation.conversationId
    $convStart = [string]$Conversation.conversationStart
    $convEnd = [string]$Conversation.conversationEnd

    if (-not [string]::IsNullOrWhiteSpace($convStart)) {
        $events.Add((_New-TimelineEvent -ConversationId $convId -EventTime $convStart `
            -EventType 'conversation.start' -Source 'analytics.details' -Sequence 10 `
            -Label 'Conversation started' `
            -Details ([ordered]@{
                originatingDirection = [string]$Conversation.originatingDirection
                mediaType = if ($null -ne $Conversation.participants) {
                    @($Conversation.participants | ForEach-Object { $_.sessions } | Where-Object { $_ } |
                      ForEach-Object { $_.mediaType } | Where-Object { $_ } | Select-Object -Unique) -join ','
                } else { $null }
            }))) | Out-Null
    }

    $seq = 20
    foreach ($participant in @($Conversation.participants | Where-Object { $_ })) {
        $pId = [string]$participant.participantId
        $purpose = [string]$participant.purpose

        foreach ($session in @($participant.sessions | Where-Object { $_ })) {
            $sId = [string]$session.sessionId

            foreach ($segment in @($session.segments | Where-Object { $_ })) {
                $segStart = [string]$segment.segmentStart
                $segEnd   = [string]$segment.segmentEnd
                $segType  = [string]$segment.segmentType

                $eventType = switch ($segType) {
                    'ivr'       { 'segment.ivr' }
                    'alert'     { 'segment.alert' }
                    'interact'  { 'segment.talk' }
                    'hold'      { 'segment.hold' }
                    'wrapup'    { 'segment.acw' }
                    'transfer'  { 'segment.transfer' }
                    'consult'   { 'segment.consult' }
                    'conference'{ 'segment.conference' }
                    default     { "segment.$($segType.ToLower())" }
                }

                $label = switch ($segType) {
                    'ivr'       { "IVR segment ($purpose)" }
                    'alert'     { "Agent alerting ($purpose)" }
                    'interact'  { "Talk segment ($purpose)" }
                    'hold'      { "Hold segment ($purpose)" }
                    'wrapup'    { "ACW segment ($purpose)" }
                    'transfer'  { "Transfer segment ($purpose)" }
                    default     { "$segType segment ($purpose)" }
                }

                $durationMs = $null
                if (-not [string]::IsNullOrWhiteSpace($segStart) -and -not [string]::IsNullOrWhiteSpace($segEnd)) {
                    try {
                        $durationMs = [long]([datetime]::Parse($segEnd) - [datetime]::Parse($segStart)).TotalMilliseconds
                    } catch { }
                }

                $seq++
                $events.Add((_New-TimelineEvent -ConversationId $convId `
                    -EventTime (if ([string]::IsNullOrWhiteSpace($segStart)) { $convStart } else { $segStart }) `
                    -EventType $eventType -Source 'analytics.details' `
                    -ParticipantId $pId -SessionId $sId -Sequence $seq `
                    -Label $label `
                    -Details ([ordered]@{
                        segmentType  = $segType
                        purpose      = $purpose
                        userId       = [string]$participant.userId
                        queueId      = [string]$session.routingData.queueId
                        durationMs   = $durationMs
                        disconnectType = [string]$segment.disconnectType
                        wrapUpCode   = [string]$segment.wrapUpCode
                    }))) | Out-Null
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($convEnd)) {
        $seq++
        $events.Add((_New-TimelineEvent -ConversationId $convId -EventTime $convEnd `
            -EventType 'conversation.end' -Source 'analytics.details' -Sequence $seq `
            -Label 'Conversation ended' `
            -Details ([ordered]@{
                disconnectType = @($Conversation.participants | Where-Object { $_ } |
                    ForEach-Object { $_.sessions } | Where-Object { $_ } |
                    ForEach-Object { $_.segments } | Where-Object { $_ } |
                    ForEach-Object { [string]$_.disconnectType } | Where-Object { $_ } |
                    Select-Object -Last 1)
            }))) | Out-Null
    }

    return $events.ToArray()
}

function _ConvertTo-RecordingTimelineEvents {
    param([Parameter(Mandatory)][string]$ConversationId, [object]$RawData)
    $events = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $RawData) { return $events.ToArray() }
    foreach ($rec in @($RawData | Where-Object { $_ })) {
        $recId = [string]$rec.id
        if ([string]::IsNullOrWhiteSpace($recId)) { continue }
        $events.Add((_New-TimelineEvent -ConversationId $ConversationId `
            -EventTime ([datetime]::UtcNow.ToString('o')) `
            -EventType 'recording.available' -Source 'recordingmetadata' -Sequence 90 `
            -Label 'Recording metadata available' `
            -Details ([ordered]@{
                recordingId  = $recId
                mediaType    = [string]$rec.mediaType
                fileState    = [string]$rec.fileState
            }))) | Out-Null
    }
    return $events.ToArray()
}

function _ConvertTo-SpeechAnalyticsTimelineEvents {
    param([Parameter(Mandatory)][string]$ConversationId, [object]$RawData, [string]$ConvStart)
    $events = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $RawData) { return $events.ToArray() }
    $data = if ($RawData -is [array]) { $RawData[0] } else { $RawData }
    if ($null -eq $data) { return $events.ToArray() }

    foreach ($comm in @($data.communications | Where-Object { $_ })) {
        foreach ($sentiment in @($comm.sentiment | Where-Object { $_ })) {
            $anchor = if (-not [string]::IsNullOrWhiteSpace([string]$sentiment.startTime)) { [string]$sentiment.startTime } else { $ConvStart }
            $events.Add((_New-TimelineEvent -ConversationId $ConversationId -EventTime $anchor `
                -EventType 'speech.sentiment' -Source 'speech-text-analytics' -Sequence 80 `
                -Label "Sentiment: $([string]$sentiment.sentiment)" `
                -Details ([ordered]@{
                    sentiment  = [string]$sentiment.sentiment
                    score      = $sentiment.score
                }))) | Out-Null
        }
        foreach ($topic in @($comm.topics | Where-Object { $_ })) {
            $anchor = if (-not [string]::IsNullOrWhiteSpace([string]$topic.startTime)) { [string]$topic.startTime } else { $ConvStart }
            $events.Add((_New-TimelineEvent -ConversationId $ConversationId -EventTime $anchor `
                -EventType 'speech.topic' -Source 'speech-text-analytics' -Sequence 80 `
                -Label "Topic: $([string]$topic.name)" `
                -Details ([ordered]@{
                    topic      = [string]$topic.name
                    confidence = $topic.confidence
                }))) | Out-Null
        }
    }
    return $events.ToArray()
}

function _ConvertTo-SuggestionTimelineEvents {
    param([Parameter(Mandatory)][string]$ConversationId, [object]$RawData, [string]$ConvStart)
    $events = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $RawData) { return $events.ToArray() }
    foreach ($sug in @($RawData | Where-Object { $_ })) {
        $anchor = if (-not [string]::IsNullOrWhiteSpace([string]$sug.dateCreated)) { [string]$sug.dateCreated } else { $ConvStart }
        $events.Add((_New-TimelineEvent -ConversationId $ConversationId -EventTime $anchor `
            -EventType 'suggestion.offered' -Source 'conversation.suggestions' -Sequence 70 `
            -Label "Suggestion offered: $([string]$sug.type)" `
            -Details ([ordered]@{
                suggestionId = [string]$sug.id
                type         = [string]$sug.type
                state        = [string]$sug.state
            }))) | Out-Null
    }
    return $events.ToArray()
}

function _ConvertTo-CustomAttributeTimelineEvents {
    param([Parameter(Mandatory)][string]$ConversationId, [object]$RawData, [string]$ConvStart)
    $events = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $RawData) { return $events.ToArray() }
    $attrs = if ($RawData.PSObject.Properties['attributes']) { $RawData.attributes } else { $RawData }
    foreach ($prop in @($attrs.PSObject.Properties | Where-Object { $_ })) {
        $events.Add((_New-TimelineEvent -ConversationId $ConversationId -EventTime $ConvStart `
            -EventType 'attribute.custom' -Source 'customattributes' -Sequence 60 `
            -Label "Custom attribute: $($prop.Name)" `
            -Details ([ordered]@{
                name  = $prop.Name
                value = [string]$prop.Value
            }))) | Out-Null
    }
    return $events.ToArray()
}

function _ConvertTo-ParticipantAttributeTimelineEvents {
    param([Parameter(Mandatory)][string]$ConversationId, [object]$RawData, [string]$ConvStart)
    $events = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $RawData) { return $events.ToArray() }
    foreach ($row in @($RawData | Where-Object { $_ })) {
        if ([string]$row.conversationId -ne $ConversationId) { continue }
        $pId = [string]$row.participantId
        $attrs = $row.attributes
        if ($null -eq $attrs) { continue }
        foreach ($prop in @($attrs.PSObject.Properties | Where-Object { $_ })) {
            $events.Add((_New-TimelineEvent -ConversationId $ConversationId -EventTime $ConvStart `
                -EventType 'attribute.participant' -Source 'participants.attributes.search' `
                -ParticipantId $pId -Sequence 60 `
                -Label "Participant attribute: $($prop.Name)" `
                -Details ([ordered]@{
                    name          = $prop.Name
                    value         = [string]$prop.Value
                    participantId = $pId
                }))) | Out-Null
        }
    }
    return $events.ToArray()
}

function Invoke-ConversationTimelineAnalysisDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$RunContext,
        [Parameter(Mandatory)][psobject]$Catalog,
        [string]$BaseUri = 'https://api.usw2.pure.cloud',
        [hashtable]$Headers,
        [scriptblock]$RequestInvoker,
        [hashtable]$DatasetParameters,
        [switch]$NoRedact
    )

    $previewMode   = _Get-BoolParam -Params $DatasetParameters -Key 'PreviewMode' -Default $false
    $inclConvObj   = _Get-BoolParam -Params $DatasetParameters -Key 'IncludeConversationObject' -Default $true
    $inclCustom    = _Get-BoolParam -Params $DatasetParameters -Key 'IncludeCustomAttributes' -Default $true
    $inclPart      = _Get-BoolParam -Params $DatasetParameters -Key 'IncludeParticipantAttributes' -Default $true
    $inclSug       = _Get-BoolParam -Params $DatasetParameters -Key 'IncludeSuggestions' -Default $true
    $inclRec       = _Get-BoolParam -Params $DatasetParameters -Key 'IncludeRecordingMetadata' -Default $true
    $inclSpeech    = _Get-BoolParam -Params $DatasetParameters -Key 'IncludeSpeechTextAnalytics' -Default $true

    $runEvents  = [System.Collections.Generic.List[object]]::new()
    $errorList  = [System.Collections.Generic.List[object]]::new()

    # ── Phase 1: Analytics extraction ────────────────────────────────────────
    Write-GcProgressMessage -Message '[Timeline] Phase 1 — Analytics extraction'
    Write-RunEvent -RunContext $RunContext -EventType 'timeline.phase.start' -Payload @{ phase = 1; label = 'Analytics extraction' } | Out-Null

    $analyticsRecords = @()
    $detailsDataFile  = if ($previewMode) { 'analytics-details-preview.jsonl' } else { 'analytics-details.jsonl' }
    $detailsDataPath  = Join-Path -Path $RunContext.dataFolder -ChildPath $detailsDataFile

    if ($previewMode) {
        $previewResult = Invoke-AnalyticsConversationDetailsDataset -RunContext $RunContext `
            -Catalog $Catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker `
            -DatasetParameters $DatasetParameters -NoRedact:$NoRedact
        $analyticsRecords = @($previewResult.Items)
    } else {
        $fullResult = Invoke-AnalyticsConversationDetailsDataset -RunContext $RunContext `
            -Catalog $Catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker `
            -DatasetParameters $DatasetParameters -NoRedact:$NoRedact
        $analyticsRecords = @($fullResult.Items)
    }

    foreach ($record in $analyticsRecords) {
        Write-Jsonl -Path $detailsDataPath -InputObject $record
    }

    Write-RunEvent -RunContext $RunContext -EventType 'timeline.phase.complete' `
        -Payload @{ phase = 1; conversationCount = $analyticsRecords.Count } | Out-Null

    if ($analyticsRecords.Count -eq 0) {
        Write-GcProgressMessage -Message '[Timeline] No conversations returned from analytics extraction.'
        ($([ordered]@{
            datasetKey = $RunContext.datasetKey; runId = $RunContext.runId
            conversationCount = 0; generatedAtUtc = [datetime]::UtcNow.ToString('o')
        }) | ConvertTo-Json -Depth 10) | Set-Content -Path $RunContext.summaryPath -Encoding utf8
        Write-Manifest -RunContext $RunContext -Counts @{ itemCount = 0 } | Out-Null
        Write-RunEvent -RunContext $RunContext -EventType 'run.completed' -Payload @{ itemCount = 0 } | Out-Null
        return [pscustomobject]@{ Items = @(); Summary = @{} }
    }

    # ── Phase 2: Conversation index ───────────────────────────────────────────
    Write-GcProgressMessage -Message '[Timeline] Phase 2 — Building conversation index'
    $indexPath = Join-Path -Path $RunContext.runFolder -ChildPath 'timeline-index.json'

    $conversationIndex = [ordered]@{}
    foreach ($conv in $analyticsRecords) {
        $cId = [string]$conv.conversationId
        if ([string]::IsNullOrWhiteSpace($cId)) { continue }
        $conversationIndex[$cId] = [ordered]@{
            conversationId    = $cId
            conversationStart = [string]$conv.conversationStart
            conversationEnd   = [string]$conv.conversationEnd
            needsEnrichment   = $true
            enrichmentStatus  = [ordered]@{
                conversationObject   = 'pending'
                customAttributes     = 'pending'
                participantAttributes = 'pending'
                suggestions          = 'pending'
                recordingMetadata    = 'pending'
                speechTextAnalytics  = 'pending'
            }
        }
    }

    ($conversationIndex | ConvertTo-Json -Depth 10) | Set-Content -Path $indexPath -Encoding utf8

    # ── Phase 3: Enrichment fan-out ───────────────────────────────────────────
    Write-GcProgressMessage -Message "[Timeline] Phase 3 — Enrichment fan-out for $($conversationIndex.Count) conversation(s)"
    Write-RunEvent -RunContext $RunContext -EventType 'timeline.phase.start' -Payload @{ phase = 3; label = 'Enrichment' } | Out-Null

    $convObjPath   = Join-Path -Path $RunContext.dataFolder -ChildPath 'conversation-objects.jsonl'
    $customAttrPath = Join-Path -Path $RunContext.dataFolder -ChildPath 'custom-attributes.jsonl'
    $partAttrPath  = Join-Path -Path $RunContext.dataFolder -ChildPath 'participant-attributes.jsonl'
    $sugPath       = Join-Path -Path $RunContext.dataFolder -ChildPath 'suggestions.jsonl'
    $recMetaPath   = Join-Path -Path $RunContext.dataFolder -ChildPath 'recording-metadata.jsonl'
    $speechPath    = Join-Path -Path $RunContext.dataFolder -ChildPath 'speech-text-analytics.jsonl'
    $jobStatusPath = Join-Path -Path $RunContext.dataFolder -ChildPath 'job-status.jsonl'

    $enrichedData = @{}

    foreach ($cId in $conversationIndex.Keys) {
        $idx = $conversationIndex[$cId]
        Write-GcProgressMessage -Message "[Timeline] Enriching $cId"

        # Conversation object
        if ($inclConvObj) {
            $convObj = _Invoke-EnrichmentGet -EndpointKey 'conversations.get.specific.conversation.details' `
                -ConversationId $cId -BaseUri $BaseUri -Headers $Headers `
                -RequestInvoker $RequestInvoker -Catalog $Catalog -ErrorList $errorList
            if ($null -ne $convObj) {
                $record = [ordered]@{ conversationId = $cId; sourceEndpoint = 'GET /api/v2/conversations/{conversationId}'; data = $convObj }
                Write-Jsonl -Path $convObjPath -InputObject $record
                $idx.enrichmentStatus.conversationObject = 'complete'
                $enrichedData["convobj:$cId"] = $convObj
            } else {
                $idx.enrichmentStatus.conversationObject = 'failed'
            }
        } else {
            $idx.enrichmentStatus.conversationObject = 'skipped'
        }

        # Custom attributes (per-conversation)
        if ($inclCustom) {
            $customAttrs = _Invoke-EnrichmentGet -EndpointKey 'getConversationCustomattributes' `
                -ConversationId $cId -BaseUri $BaseUri -Headers $Headers `
                -RequestInvoker $RequestInvoker -Catalog $Catalog -ErrorList $errorList
            if ($null -ne $customAttrs) {
                Write-Jsonl -Path $customAttrPath -InputObject ([ordered]@{ conversationId = $cId; sourceEndpoint = 'GET /api/v2/conversations/{conversationId}/customattributes'; attributes = $customAttrs })
                $idx.enrichmentStatus.customAttributes = 'complete'
                $enrichedData["custom:$cId"] = $customAttrs
            } else {
                $idx.enrichmentStatus.customAttributes = 'failed'
            }
        } else {
            $idx.enrichmentStatus.customAttributes = 'skipped'
        }

        # Recording metadata
        if ($inclRec) {
            $recMeta = _Invoke-EnrichmentGet -EndpointKey 'conversations.get.conversation.recording.metadata' `
                -ConversationId $cId -BaseUri $BaseUri -Headers $Headers `
                -RequestInvoker $RequestInvoker -Catalog $Catalog -ErrorList $errorList
            if ($null -ne $recMeta) {
                Write-Jsonl -Path $recMetaPath -InputObject ([ordered]@{ conversationId = $cId; sourceEndpoint = 'GET /api/v2/conversations/{conversationId}/recordingmetadata'; recordings = $recMeta })
                $idx.enrichmentStatus.recordingMetadata = 'complete'
                $enrichedData["rec:$cId"] = $recMeta
            } else {
                $idx.enrichmentStatus.recordingMetadata = 'failed'
            }
        } else {
            $idx.enrichmentStatus.recordingMetadata = 'skipped'
        }

        # Speech and text analytics
        if ($inclSpeech) {
            $speechData = _Invoke-EnrichmentGet -EndpointKey 'speech.and.text.analytics.get.speech.and.text.analytics.for.conversation' `
                -ConversationId $cId -BaseUri $BaseUri -Headers $Headers `
                -RequestInvoker $RequestInvoker -Catalog $Catalog -ErrorList $errorList
            if ($null -ne $speechData) {
                Write-Jsonl -Path $speechPath -InputObject ([ordered]@{ conversationId = $cId; sourceEndpoint = 'GET /api/v2/speechandtextanalytics/conversations/{conversationId}'; data = $speechData })
                $idx.enrichmentStatus.speechTextAnalytics = 'complete'
                $enrichedData["speech:$cId"] = $speechData
            } else {
                $idx.enrichmentStatus.speechTextAnalytics = 'failed'
            }
        } else {
            $idx.enrichmentStatus.speechTextAnalytics = 'skipped'
        }

        # Suggestions
        if ($inclSug) {
            $suggestions = _Invoke-EnrichmentGet -EndpointKey 'getConversationSuggestions' `
                -ConversationId $cId -BaseUri $BaseUri -Headers $Headers `
                -RequestInvoker $RequestInvoker -Catalog $Catalog -ErrorList $errorList
            if ($null -ne $suggestions) {
                Write-Jsonl -Path $sugPath -InputObject ([ordered]@{ conversationId = $cId; sourceEndpoint = 'GET /api/v2/conversations/{conversationId}/suggestions'; suggestions = $suggestions })
                $idx.enrichmentStatus.suggestions = 'complete'
                $enrichedData["sug:$cId"] = $suggestions
            } else {
                $idx.enrichmentStatus.suggestions = 'failed'
            }
        } else {
            $idx.enrichmentStatus.suggestions = 'skipped'
        }

        # Participant attributes — per-conversation note: bulk search preferred but per-conv fallback used here
        $idx.enrichmentStatus.participantAttributes = 'skipped'
    }

    # Persist updated index
    ($conversationIndex | ConvertTo-Json -Depth 10) | Set-Content -Path $indexPath -Encoding utf8

    Write-RunEvent -RunContext $RunContext -EventType 'timeline.phase.complete' `
        -Payload @{ phase = 3; enrichedCount = $conversationIndex.Count; errorCount = $errorList.Count } | Out-Null

    # ── Phase 4: Timeline event normalization ─────────────────────────────────
    Write-GcProgressMessage -Message '[Timeline] Phase 4 — Normalizing timeline events'
    Write-RunEvent -RunContext $RunContext -EventType 'timeline.phase.start' -Payload @{ phase = 4; label = 'Timeline normalization' } | Out-Null

    $timelineEventsPath = Join-Path -Path $RunContext.runFolder -ChildPath 'timeline-events.jsonl'
    $allEvents = [System.Collections.Generic.List[object]]::new()

    foreach ($conv in $analyticsRecords) {
        $cId       = [string]$conv.conversationId
        $convStart = [string]$conv.conversationStart

        foreach ($e in @(_ConvertTo-AnalyticsTimelineEvents -Conversation $conv)) {
            $allEvents.Add($e) | Out-Null
        }

        if ($inclRec -and $enrichedData.ContainsKey("rec:$cId")) {
            foreach ($e in @(_ConvertTo-RecordingTimelineEvents -ConversationId $cId -RawData $enrichedData["rec:$cId"])) {
                $allEvents.Add($e) | Out-Null
            }
        }

        if ($inclSpeech -and $enrichedData.ContainsKey("speech:$cId")) {
            foreach ($e in @(_ConvertTo-SpeechAnalyticsTimelineEvents -ConversationId $cId -RawData $enrichedData["speech:$cId"] -ConvStart $convStart)) {
                $allEvents.Add($e) | Out-Null
            }
        }

        if ($inclSug -and $enrichedData.ContainsKey("sug:$cId")) {
            foreach ($e in @(_ConvertTo-SuggestionTimelineEvents -ConversationId $cId -RawData $enrichedData["sug:$cId"] -ConvStart $convStart)) {
                $allEvents.Add($e) | Out-Null
            }
        }

        if ($inclCustom -and $enrichedData.ContainsKey("custom:$cId")) {
            foreach ($e in @(_ConvertTo-CustomAttributeTimelineEvents -ConversationId $cId -RawData $enrichedData["custom:$cId"] -ConvStart $convStart)) {
                $allEvents.Add($e) | Out-Null
            }
        }

        # Enrichment warnings for any failed enrichment
        foreach ($err in @($errorList | Where-Object { [string]$_.conversationId -eq $cId })) {
            $allEvents.Add((_New-TimelineEvent -ConversationId $cId -EventTime $convStart `
                -EventType 'enrichment.warning' -Source [string]$err.sourceEndpoint -Sequence 900 `
                -Label "Enrichment failed: $([string]$err.sourceEndpoint)" `
                -Details ([ordered]@{ message = [string]$err.message }))) | Out-Null
        }
    }

    # Sort: conversationId, then eventTime, then eventPriority
    $sortedEvents = @($allEvents |
        Sort-Object -Property @(
            @{ Expression = { [string]$_.conversationId } },
            @{ Expression = { try { [datetime]::Parse([string]$_.eventTime) } catch { [datetime]::MinValue } } },
            @{ Expression = { _Get-EventPriority -EventType [string]$_.eventType } },
            @{ Expression = { [int]$_.sequence } }
        ))

    foreach ($e in $sortedEvents) {
        Write-Jsonl -Path $timelineEventsPath -InputObject $e
    }

    Write-RunEvent -RunContext $RunContext -EventType 'timeline.phase.complete' `
        -Payload @{ phase = 4; eventCount = $sortedEvents.Count } | Out-Null

    # ── Phase 5: Aggregate outputs ────────────────────────────────────────────
    Write-GcProgressMessage -Message '[Timeline] Phase 5 — Writing aggregate outputs'

    $conversationsPath = Join-Path -Path $RunContext.runFolder -ChildPath 'conversations.jsonl'
    $errorsPath = Join-Path -Path $RunContext.runFolder -ChildPath 'errors.jsonl'

    $withRecording   = 0
    $withSpeech      = 0
    $withSuggestions = 0
    $withCustomAttrs = 0
    $partialCount    = 0
    $mediaTypeCounts = @{}
    $disconnectCounts = @{}

    foreach ($conv in $analyticsRecords) {
        $cId = [string]$conv.conversationId
        $idx = $conversationIndex[$cId]
        if ($null -eq $idx) { continue }

        $es = $idx.enrichmentStatus
        $hasRec  = $es.recordingMetadata -eq 'complete' -and $enrichedData.ContainsKey("rec:$cId") -and @($enrichedData["rec:$cId"]).Count -gt 0
        $hasSpeech = $es.speechTextAnalytics -eq 'complete'
        $hasSug  = $es.suggestions -eq 'complete' -and $enrichedData.ContainsKey("sug:$cId") -and @($enrichedData["sug:$cId"]).Count -gt 0
        $hasCustom = $es.customAttributes -eq 'complete'

        if ($hasRec) { $withRecording++ }
        if ($hasSpeech) { $withSpeech++ }
        if ($hasSug) { $withSuggestions++ }
        if ($hasCustom) { $withCustomAttrs++ }

        $statusValues = @($es.PSObject.Properties.Value | Where-Object { $_ -eq 'failed' })
        if ($statusValues.Count -gt 0) { $partialCount++ }

        # Media types (from segments)
        $mediaTypes = @($conv.participants | Where-Object { $_ } |
            ForEach-Object { $_.sessions } | Where-Object { $_ } |
            ForEach-Object { [string]$_.mediaType } | Where-Object { $_ } | Select-Object -Unique)
        foreach ($mt in $mediaTypes) {
            if (-not $mediaTypeCounts.ContainsKey($mt)) { $mediaTypeCounts[$mt] = 0 }
            $mediaTypeCounts[$mt]++
        }

        # Disconnect types (from last segment)
        $lastDisc = @($conv.participants | Where-Object { $_ } |
            ForEach-Object { $_.sessions } | Where-Object { $_ } |
            ForEach-Object { $_.segments } | Where-Object { $_ } |
            ForEach-Object { [string]$_.disconnectType } | Where-Object { $_ }) | Select-Object -Last 1
        if ($lastDisc) {
            if (-not $disconnectCounts.ContainsKey($lastDisc)) { $disconnectCounts[$lastDisc] = 0 }
            $disconnectCounts[$lastDisc]++
        }

        $convRow = [ordered]@{
            conversationId    = $cId
            conversationStart = [string]$conv.conversationStart
            conversationEnd   = [string]$conv.conversationEnd
            originatingDirection = [string]$conv.originatingDirection
            mediaTypes        = $mediaTypes
            agentIds          = @($conv.participants | Where-Object { $_ -and [string]$_.purpose -eq 'agent' } |
                                  ForEach-Object { [string]$_.userId } | Where-Object { $_ } | Select-Object -Unique)
            queueIds          = @($conv.participants | Where-Object { $_ } |
                                  ForEach-Object { $_.sessions } | Where-Object { $_ } |
                                  ForEach-Object { [string]$_.routingData.queueId } | Where-Object { $_ } | Select-Object -Unique)
            hasRecording      = $hasRec
            hasSpeechAnalytics = $hasSpeech
            hasSuggestions    = $hasSug
            hasCustomAttributes = $hasCustom
            enrichmentStatus  = $es
        }
        Write-Jsonl -Path $conversationsPath -InputObject $convRow
    }

    foreach ($err in $errorList) {
        Write-Jsonl -Path $errorsPath -InputObject $err
    }

    $summary = [ordered]@{
        datasetKey                    = $RunContext.datasetKey
        runId                         = $RunContext.runId
        conversationCount             = $analyticsRecords.Count
        timelineEventCount            = $sortedEvents.Count
        conversationsWithRecording    = $withRecording
        conversationsWithSpeechAnalytics = $withSpeech
        conversationsWithSuggestions  = $withSuggestions
        conversationsWithCustomAttributes = $withCustomAttrs
        partialEnrichmentCount        = $partialCount
        errorCount                    = $errorList.Count
        mediaTypes                    = $mediaTypeCounts
        disconnectTypes               = $disconnectCounts
        requestedEnrichments          = [ordered]@{
            conversationObject    = $inclConvObj
            customAttributes      = $inclCustom
            participantAttributes = $inclPart
            suggestions           = $inclSug
            recordingMetadata     = $inclRec
            speechTextAnalytics   = $inclSpeech
        }
        generatedAtUtc                = [datetime]::UtcNow.ToString('o')
    }

    ($summary | ConvertTo-Json -Depth 10) | Set-Content -Path $RunContext.summaryPath -Encoding utf8

    foreach ($e in @($runEvents)) {
        Write-RunEvent -RunContext $RunContext -EventType $e.eventType -Payload $e | Out-Null
    }

    Write-RunEvent -RunContext $RunContext -EventType 'run.completed' -Payload @{ itemCount = $analyticsRecords.Count } | Out-Null
    Write-Manifest -RunContext $RunContext -Counts @{ itemCount = $analyticsRecords.Count } | Out-Null

    Write-GcProgressMessage -Message "[Timeline] Complete. $($analyticsRecords.Count) conversations, $($sortedEvents.Count) events, $($errorList.Count) errors."

    return [pscustomobject]@{
        Items   = $analyticsRecords
        Summary = $summary
    }
}
