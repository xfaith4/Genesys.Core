function Get-DatasetDataFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatasetKey,

        [psobject]$DatasetSpec
    )

    if ($null -ne $DatasetSpec -and $DatasetSpec.PSObject.Properties.Name -contains 'outputFile' -and [string]::IsNullOrWhiteSpace([string]$DatasetSpec.outputFile) -eq $false) {
        return [string]$DatasetSpec.outputFile
    }

    $normalized = $DatasetKey -replace '[^a-zA-Z0-9\-_]', '-'
    return "$($normalized).jsonl"
}

function Invoke-CatalogDataset {
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

    $datasetSpec = Get-CatalogDatasetByKey -Catalog $Catalog -Key $RunContext.datasetKey
    $endpointSpec = Resolve-DatasetEndpointSpec -Catalog $Catalog -DatasetKey $RunContext.datasetKey
    if ($endpointSpec.PSObject.Properties.Name -contains 'transaction' -and $null -ne $endpointSpec.transaction) {
        $endpointSpec.transaction | Add-Member -MemberType NoteProperty -Name baseUri -Value $BaseUri -Force
    }

    $runEvents = [System.Collections.Generic.List[object]]::new()
    $requestBody = $null
    if ($datasetSpec.PSObject.Properties.Name -contains 'requestBody' -and $null -ne $datasetSpec.requestBody) {
        if ($datasetSpec.requestBody -is [string]) {
            $requestBody = [string]$datasetSpec.requestBody
        }
        else {
            $requestBody = $datasetSpec.requestBody | ConvertTo-Json -Depth 100
        }
    }

    $result = Invoke-CoreEndpoint -EndpointSpec $endpointSpec -InitialUri (Join-EndpointUri -BaseUri $BaseUri -Path $endpointSpec.path) -InitialBody $requestBody -Headers $Headers -RetryProfile $endpointSpec.retry -RunEvents $runEvents -RequestInvoker $RequestInvoker
    $records = @($result.Items)
    $sanitizedRecords = @($records | ForEach-Object { Protect-RecordData -InputObject $_ })

    $dataPath = Join-Path -Path $RunContext.dataFolder -ChildPath (Get-DatasetDataFileName -DatasetKey $RunContext.datasetKey -DatasetSpec $datasetSpec)
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
        }
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    $summary | ConvertTo-Json -Depth 100 | Set-Content -Path $RunContext.summaryPath -Encoding utf8

    Write-RunEvent -RunContext $RunContext -EventType 'run.completed' -Payload @{ itemCount = $sanitizedRecords.Count } | Out-Null
    Write-Manifest -RunContext $RunContext -Counts @{ itemCount = $sanitizedRecords.Count } | Out-Null

    return [pscustomobject]@{
        Items = $sanitizedRecords
        Summary = $summary
    }
}
