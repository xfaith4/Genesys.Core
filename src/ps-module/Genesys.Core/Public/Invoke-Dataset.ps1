[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Dataset,
    [string]$CatalogPath,
    [string]$OutputRoot = 'out',
    [switch]$StrictCatalog
)

### BEGIN: StandaloneBootstrap
# When invoked via 'pwsh -File', module functions are not available.
# Bootstrap by dot-sourcing required Private functions if not already loaded.
if (-not (Get-Command -Name 'Write-RunEvent' -ErrorAction SilentlyContinue)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..'
    $privatePath = Join-Path -Path $modulePath -ChildPath 'Private'
    
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}
### END: StandaloneBootstrap

function Invoke-Dataset {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Dataset,

        [string]$CatalogPath,

        [string]$OutputRoot = 'out',

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker,

        [switch]$StrictCatalog
    )

    $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..\catalog\schema\genesys-core.catalog.schema.json'
    $catalogResolution = Resolve-Catalog -CatalogPath $CatalogPath -SchemaPath $schemaPath -StrictCatalog:$StrictCatalog

    foreach ($warning in @($catalogResolution.warnings)) {
        Write-Warning $warning
    }

    $catalog = $catalogResolution.catalogObject
    $runContext = New-RunContext -DatasetKey $Dataset -OutputRoot $OutputRoot

    if ($WhatIfPreference) {
        Write-Host "[WhatIf] Dataset '$($Dataset)' would run using catalog '$($catalogResolution.pathUsed)'."
        Write-Host "[WhatIf] Would write outputs under '$($runContext.runFolder)' (manifest/events/summary/data)."
        return
    }

    if ($PSCmdlet.ShouldProcess($Dataset, 'Invoke dataset run') -eq $false) {
        return
    }

    if (-not $PSBoundParameters.ContainsKey('Headers') -and -not [string]::IsNullOrWhiteSpace($env:GENESYS_BEARER_TOKEN)) {
        $Headers = @{ Authorization = "Bearer $($env:GENESYS_BEARER_TOKEN)" }
    }

    Write-RunEvent -RunContext $runContext -EventType 'run.started' -Payload @{ catalogPath = $catalogResolution.pathUsed } | Out-Null

    try {
        Invoke-RegisteredDataset -Dataset $Dataset -RunContext $runContext -Catalog $catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker | Out-Null
        return $runContext
    }
    catch {
        Write-RunEvent -RunContext $runContext -EventType 'run.failed' -Payload @{ message = $_.Exception.Message } | Out-Null
        Write-Manifest -RunContext $runContext -Counts @{ itemCount = 0 } -Warnings @($_.Exception.Message) | Out-Null
        throw
    }
}

if ($PSBoundParameters.ContainsKey('Dataset')) {
    Invoke-Dataset -Dataset $Dataset -CatalogPath $CatalogPath -OutputRoot $OutputRoot -StrictCatalog:$StrictCatalog -WhatIf:$WhatIfPreference
}
