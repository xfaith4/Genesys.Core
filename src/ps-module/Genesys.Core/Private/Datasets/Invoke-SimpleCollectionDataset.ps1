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

        [scriptblock]$RequestInvoker
    )

    $resolvedSpec = Resolve-DatasetEndpointSpec -Catalog $Catalog -DatasetKey $DatasetKey
    $dataset = $resolvedSpec.Dataset
    $endpoint = $resolvedSpec.Endpoint

    $runEvents = [System.Collections.Generic.List[object]]::new()
    $response = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
        key = $endpoint.key
        method = $endpoint.method
        path = $endpoint.path
        itemsPath = $dataset.itemsPath
        paging = $endpoint.paging
        retry = $endpoint.retry
        transaction = $endpoint.transaction
    }) -InitialUri (Join-EndpointUri -BaseUri $BaseUri -Path $endpoint.path) -Headers $Headers -RunEvents $runEvents -RequestInvoker $RequestInvoker

    $records = @($response.Items | ForEach-Object { & $Normalizer $_ })
    $sanitizedRecords = @($records | ForEach-Object { Protect-RecordData -InputObject $_ })

    $summary = [ordered]@{
        datasetKey = $RunContext.datasetKey
        runId = $RunContext.runId
        totals = [ordered]@{ totalRecords = $sanitizedRecords.Count }
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    Write-DatasetOutputs -RunContext $RunContext -RunEvents $runEvents -Records $sanitizedRecords -DataFileName $DataFileName -Summary $summary

    return [pscustomobject]@{ Items = $sanitizedRecords; Summary = $summary }
}
