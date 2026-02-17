function Get-CatalogEndpointByKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    foreach ($endpoint in @($Catalog.endpoints)) {
        if ($endpoint.key -eq $Key) {
            return $endpoint
        }
    }

    throw "Endpoint '$($Key)' was not found in catalog."
}

function Join-EndpointUri {
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

    $mappingEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.get.service.mapping'
    $submitEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.query.submit'
    $statusEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.query.status'
    $resultsEndpoint = Get-CatalogEndpointByKey -Catalog $Catalog -Key 'audits.query.results'

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
