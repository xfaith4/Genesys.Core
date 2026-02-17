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

    $runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $runFolder = Join-Path -Path $OutputRoot -ChildPath (Join-Path -Path $Dataset -ChildPath $runId)

    if ($WhatIfPreference) {
        Write-Host "[WhatIf] Dataset '$($Dataset)' would run using catalog '$($CatalogPath)'."
        Write-Host "[WhatIf] Would write outputs under '$($runFolder)' (manifest/events/summary/data)."
        return
    }

    if ($PSCmdlet.ShouldProcess($Dataset, 'Invoke dataset run')) {
        Write-Host "Invoking dataset '$($Dataset)' using catalog '$($CatalogPath)'."
        Write-Host "Output path: '$($runFolder)'."
    }
}
### END: InvokeDatasetStub

if ($PSBoundParameters.ContainsKey('Dataset')) {
    Invoke-Dataset -Dataset $Dataset -CatalogPath $CatalogPath -OutputRoot $OutputRoot -WhatIf:$WhatIfPreference
}
