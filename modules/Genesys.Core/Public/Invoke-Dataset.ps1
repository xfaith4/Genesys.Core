[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Dataset,
    [string]$CatalogPath,
    [string]$OutputRoot = 'out',
    [string]$BaseUri = 'https://api.mypurecloud.com',
    [hashtable]$Headers,
    [scriptblock]$RequestInvoker,
    [hashtable]$DatasetParameters,
    [switch]$StrictCatalog,
    [switch]$NoRedact
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

function Resolve-OutputRootPath {
    [CmdletBinding()]
    param(
        [string]$OutputRoot = 'out'
    )

    $effectiveOutputRoot = [string]$OutputRoot
    if ([string]::IsNullOrWhiteSpace($effectiveOutputRoot)) {
        $effectiveOutputRoot = 'out'
    }

    if ([System.IO.Path]::DirectorySeparatorChar -ne '\' -and $effectiveOutputRoot -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest  = ($Matches[2] -replace '\\', '/').TrimStart('/')
        $effectiveOutputRoot = "/mnt/$drive/$rest"
    } elseif ([System.IO.Path]::DirectorySeparatorChar -ne '\') {
        $effectiveOutputRoot = $effectiveOutputRoot -replace '\\', '/'
    }

    if ([System.IO.Path]::IsPathRooted($effectiveOutputRoot)) {
        return [System.IO.Path]::GetFullPath($effectiveOutputRoot)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $effectiveOutputRoot))
}

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

        [hashtable]$DatasetParameters,

        [switch]$StrictCatalog,

        [switch]$NoRedact
    )

    # $PSScriptRoot inside this function body reflects the module root (modules/Genesys.Core/),
    # NOT the Public/ subdirectory where this file lives.  Use the captured module root and
    # go two levels up to reach the repo root, then into catalog/schema/.
    $schemaRoot = if ($null -ne $script:GcModuleRoot) {
        [System.IO.Path]::GetFullPath((Join-Path -Path $script:GcModuleRoot -ChildPath '../..'))
    } else {
        [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../../..'))
    }
    $schemaPath = Join-Path -Path $schemaRoot -ChildPath 'catalog/schema/genesys.catalog.schema.json'
    $catalogResolution = Resolve-Catalog -CatalogPath $CatalogPath -SchemaPath $schemaPath -StrictCatalog:$StrictCatalog

    foreach ($warning in @($catalogResolution.warnings)) {
        Write-Warning $warning
    }

    $catalog = $catalogResolution.catalogObject
    $resolvedOutputRoot = Resolve-OutputRootPath -OutputRoot $OutputRoot

    if ($WhatIfPreference) {
        $plannedRunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
        $plannedRunFolder = Join-Path -Path $resolvedOutputRoot -ChildPath (Join-Path -Path $Dataset -ChildPath $plannedRunId)
        $plannedDataFolder = Join-Path -Path $plannedRunFolder -ChildPath 'data'
        $plannedContext = [pscustomobject]@{
            datasetKey = $Dataset
            runId = $plannedRunId
            outputRoot = $resolvedOutputRoot
            runFolder = $plannedRunFolder
            dataFolder = $plannedDataFolder
            manifestPath = (Join-Path -Path $plannedRunFolder -ChildPath 'manifest.json')
            eventsPath = (Join-Path -Path $plannedRunFolder -ChildPath 'events.jsonl')
            summaryPath = (Join-Path -Path $plannedRunFolder -ChildPath 'summary.json')
            apiLogPath = (Join-Path -Path $plannedRunFolder -ChildPath 'api-calls.log')
        }

        Write-Host "[WhatIf] Dataset '$($Dataset)' would run using catalog '$($catalogResolution.pathUsed)'."
        Write-Host "[WhatIf] Planned output root: '$($resolvedOutputRoot)'."
        Write-Host "[WhatIf] Would write outputs under '$($plannedContext.runFolder)' (manifest/events/summary/data plus api-calls.log)."
        Write-Host "[WhatIf] No files or directories were created."
        return $plannedContext
    }

    if ($PSCmdlet.ShouldProcess($Dataset, 'Invoke dataset run') -eq $false) {
        return
    }

    $runContext = New-RunContext -DatasetKey $Dataset -OutputRoot $resolvedOutputRoot
    Write-Host "[Genesys.Core] Starting dataset '$($Dataset)' run '$($runContext.runId)'."
    Write-Host "[Genesys.Core] Run folder: $($runContext.runFolder)"

    if (-not $PSBoundParameters.ContainsKey('Headers') -and -not [string]::IsNullOrWhiteSpace($env:GENESYS_BEARER_TOKEN)) {
        $Headers = @{ Authorization = "Bearer $($env:GENESYS_BEARER_TOKEN)" }
    }

    Write-RunEvent -RunContext $runContext -EventType 'run.started' -Payload @{ catalogPath = $catalogResolution.pathUsed } | Out-Null

    $previousRunContext = (Get-Variable -Name 'GcActiveRunContext' -Scope Script -ErrorAction SilentlyContinue).Value
    $script:GcActiveRunContext = $runContext

    try {
        Invoke-RegisteredDataset -Dataset $Dataset -RunContext $runContext -Catalog $catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -NoRedact:$NoRedact | Out-Null
        Write-Host "[Genesys.Core] Completed dataset '$($Dataset)' run '$($runContext.runId)'."
        return $runContext
    }
    catch {
        Write-Host "[Genesys.Core] Dataset '$($Dataset)' run '$($runContext.runId)' failed: $($_.Exception.Message)"
        Write-RunEvent -RunContext $runContext -EventType 'run.failed' -Payload @{ message = $_.Exception.Message } | Out-Null
        Write-Manifest -RunContext $runContext -Counts @{ itemCount = 0 } -Warnings @($_.Exception.Message) | Out-Null
        throw
    }
    finally {
        $script:GcActiveRunContext = $previousRunContext
    }
}

if ($PSBoundParameters.ContainsKey('Dataset')) {
    Invoke-Dataset -Dataset $Dataset -CatalogPath $CatalogPath -OutputRoot $OutputRoot -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -StrictCatalog:$StrictCatalog -NoRedact:$NoRedact -WhatIf:$WhatIfPreference
}
