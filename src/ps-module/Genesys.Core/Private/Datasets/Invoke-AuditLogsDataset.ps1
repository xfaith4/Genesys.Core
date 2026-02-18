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

    $mappingEndpoint = Resolve-EndpointSpecForExecution -Catalog $Catalog -EndpointKey 'audits.get.service.mapping'
    $submitEndpoint = Resolve-DatasetEndpointSpec -Catalog $Catalog -DatasetKey 'audit-logs'

    $runEvents = [System.Collections.Generic.List[object]]::new()

    $mappingResponse = Invoke-CoreEndpoint -EndpointSpec $mappingEndpoint -InitialUri (Join-EndpointUri -BaseUri $BaseUri -Path $mappingEndpoint.path) -Headers $Headers -RetryProfile $mappingEndpoint.retry -RunEvents $runEvents -RequestInvoker $RequestInvoker
    $serviceMappings = @($mappingResponse.Items)

    $body = [ordered]@{
        interval = "$(([DateTime]::UtcNow.AddHours(-1).ToString('o')))/$(([DateTime]::UtcNow.ToString('o')))"
        serviceName = @()
        action = @()
    }

    if ($serviceMappings.Count -gt 0) {
        $body.serviceName = @($serviceMappings | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.PSObject.Properties.Name -contains 'serviceName') { $_.serviceName } } | Where-Object { $_ })
    }

    $submitEndpoint.transaction | Add-Member -MemberType NoteProperty -Name baseUri -Value $BaseUri -Force
    $transactionResult = Invoke-CoreEndpoint -EndpointSpec $submitEndpoint -InitialUri (Join-EndpointUri -BaseUri $BaseUri -Path $submitEndpoint.path) -InitialBody ($body | ConvertTo-Json -Depth 100) -Headers $Headers -RetryProfile $submitEndpoint.retry -RunEvents $runEvents -RequestInvoker $RequestInvoker

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
