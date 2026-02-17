[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Dataset,
    [string]$CatalogPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..\catalog\genesys-core.catalog.json'),
    [string]$OutputRoot = 'out'
)

### BEGIN: InvokeDatasetStub
function Invoke-Dataset {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Dataset,

        [string]$CatalogPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..\catalog\genesys-core.catalog.json'),

        [string]$OutputRoot = 'out'
    )

    $runContext = New-RunContext -DatasetKey $Dataset -OutputRoot $OutputRoot

    if ($WhatIfPreference) {
        Write-Host "[WhatIf] Dataset '$($Dataset)' would run using catalog '$($CatalogPath)'."
        Write-Host "[WhatIf] Would write outputs under '$($runContext.runFolder)' (manifest/events/summary/data)."
        return
    }

    if ($PSCmdlet.ShouldProcess($Dataset, 'Invoke dataset run')) {
        Write-Host "Invoking dataset '$($Dataset)' using catalog '$($CatalogPath)'."
        Write-Host "Output path: '$($runContext.runFolder)'."

        Write-RunEvent -RunContext $runContext -EventType 'run.started' -Payload @{ catalogPath = $CatalogPath } | Out-Null

        $stubRecord = [ordered]@{ id = 'stub-1'; dataset = $Dataset; generatedAtUtc = [DateTime]::UtcNow.ToString('o') }
        Write-Jsonl -Path (Join-Path -Path $runContext.dataFolder -ChildPath 'records.jsonl') -InputObject $stubRecord

        $summary = [ordered]@{
            datasetKey = $Dataset
            runId = $runContext.runId
            itemCount = 1
            generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        $summary | ConvertTo-Json -Depth 100 | Set-Content -Path $runContext.summaryPath -Encoding utf8

        Write-RunEvent -RunContext $runContext -EventType 'run.completed' -Payload @{ itemCount = 1 } | Out-Null
        Write-Manifest -RunContext $runContext -Counts @{ itemCount = 1 } | Out-Null

        return $runContext
    }
}
### END: InvokeDatasetStub

if ($PSBoundParameters.ContainsKey('Dataset')) {
    Invoke-Dataset -Dataset $Dataset -CatalogPath $CatalogPath -OutputRoot $OutputRoot -WhatIf:$WhatIfPreference
}
