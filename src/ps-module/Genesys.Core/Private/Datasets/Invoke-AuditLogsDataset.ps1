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

        [scriptblock]$RequestInvoker
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
        interval = "$(([DateTime]::UtcNow.AddHours(-1).ToString('o')))/$(([DateTime]::UtcNow.ToString('o')))"
        serviceName = @()
        action = @()
    }

    if ($serviceMappings.Count -gt 0) {
        $body.serviceName = @($serviceMappings | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.PSObject.Properties.Name -contains 'serviceName') { $_.serviceName } } | Where-Object { $_ })
    }

    $transactionResult = Invoke-AuditTransaction -SubmitEndpointSpec $submitEndpoint -StatusEndpointSpec $statusEndpoint -ResultsEndpointSpec $resultsEndpoint -BaseUri $BaseUri -Headers $Headers -SubmitBody $body -RunEvents $runEvents -RequestInvoker $RequestInvoker

    $records = @($transactionResult.Items)
    $sanitizedRecords = @($records | ForEach-Object { Protect-RecordData -InputObject $_ })

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

    return [pscustomobject]@{
        Items = $sanitizedRecords
        Summary = $summary
    }
}
