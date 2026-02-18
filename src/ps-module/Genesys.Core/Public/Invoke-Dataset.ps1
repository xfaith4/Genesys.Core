[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Dataset,
    [string]$CatalogPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..\catalog\genesys-core.catalog.json'),
    [string]$OutputRoot = 'out'
)

function Invoke-Dataset {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Dataset,

        [string]$CatalogPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..\catalog\genesys-core.catalog.json'),

        [string]$OutputRoot = 'out',

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker
    )

    if ($WhatIfPreference) {
        $datasetFolder = Join-Path -Path $OutputRoot -ChildPath $Dataset
        Write-Host "[WhatIf] Dataset '$($Dataset)' would run using catalog '$($CatalogPath)'."
        Write-Host "[WhatIf] Would write outputs under '$($datasetFolder)/<runId>' (manifest/events/summary/data)."
        return
    }

    $runContext = New-RunContext -DatasetKey $Dataset -OutputRoot $OutputRoot

    if ($PSCmdlet.ShouldProcess($Dataset, 'Invoke dataset run') -eq $false) {
        return
    }

    $rawCatalog = Get-Content -Path $CatalogPath -Raw | ConvertFrom-Json -Depth 100
    $catalog = Resolve-CoreCatalog -Catalog $rawCatalog

    Write-RunEvent -RunContext $runContext -EventType 'run.started' -Payload @{ catalogPath = $CatalogPath } | Out-Null

    try {
        $datasetExists = $false
        if ($null -ne $catalog.datasets) {
            foreach ($datasetProperty in $catalog.datasets.PSObject.Properties) {
                if ($datasetProperty.Name -ceq $Dataset) {
                    $datasetExists = $true
                    break
                }
            }
        }

        if ($datasetExists -eq $false) {
            throw "Unsupported dataset '$($Dataset)'."
        }

        switch ($Dataset) {
            'audit-logs' {
                Invoke-AuditLogsDataset -RunContext $runContext -Catalog $catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker | Out-Null
            }
            default {
                Invoke-CatalogDataset -RunContext $runContext -Catalog $catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker | Out-Null
            }
        }

        return $runContext
    }
    catch {
        Write-RunEvent -RunContext $runContext -EventType 'run.failed' -Payload @{ message = $_.Exception.Message } | Out-Null
        Write-Manifest -RunContext $runContext -Counts @{ itemCount = 0 } -Warnings @($_.Exception.Message) | Out-Null
        throw
    }
}

if ($PSBoundParameters.ContainsKey('Dataset')) {
    Invoke-Dataset -Dataset $Dataset -CatalogPath $CatalogPath -OutputRoot $OutputRoot -WhatIf:$WhatIfPreference
}
