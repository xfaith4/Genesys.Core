[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Dataset,

    [string]$Region = 'usw2.pure.cloud',

    [string]$OutputRoot = 'out',

    [string]$CatalogPath,

    [hashtable]$DatasetParameters,

    [string]$AccessToken,

    [switch]$StrictCatalog,

    [switch]$NoRedact,

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-CoreModulePath {
    [CmdletBinding()]
    param()

    $path = Join-Path $PSScriptRoot '..\modules\Genesys.Core\Genesys.Core.psd1'
    return [System.IO.Path]::GetFullPath($path)
}

function Resolve-BaseUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Region
    )

    if ($Region -match '^https?://') {
        return $Region.TrimEnd('/')
    }

    return "https://api.$Region"
}

try {
    $coreModulePath = Resolve-CoreModulePath
    if (-not (Test-Path $coreModulePath)) {
        throw "Genesys.Core module not found at '$coreModulePath'."
    }

    Import-Module $coreModulePath -Force -ErrorAction Stop

    $baseUri = Resolve-BaseUri -Region $Region

    $headers = $null
    if (-not [string]::IsNullOrWhiteSpace($AccessToken)) {
        $headers = @{ Authorization = "Bearer $AccessToken" }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:GENESYS_BEARER_TOKEN)) {
        $headers = @{ Authorization = "Bearer $($env:GENESYS_BEARER_TOKEN)" }
    }

    $invokeParams = @{
        Dataset           = $Dataset
        OutputRoot        = $OutputRoot
        BaseUri           = $baseUri
        StrictCatalog     = $StrictCatalog
        NoRedact          = $NoRedact
        WhatIf            = $WhatIf
        WarningAction     = 'SilentlyContinue'
        InformationAction = 'Ignore'
        ErrorAction       = 'Stop'
    }

    if ($CatalogPath) { $invokeParams.CatalogPath = $CatalogPath }
    if ($DatasetParameters) { $invokeParams.DatasetParameters = $DatasetParameters }
    if ($headers) { $invokeParams.Headers = $headers }

    $run = Invoke-Dataset @invokeParams 3>$null 4>$null 5>$null 6>$null

    $result = [ordered]@{
        ok           = $true
        dataset      = $Dataset
        baseUri      = $baseUri
        whatIf       = [bool]$WhatIf
        runId        = $run.runId
        runFolder    = $run.runFolder
        summaryPath  = $run.summaryPath
        manifestPath = $run.manifestPath
        eventsPath   = $run.eventsPath
        apiLogPath   = $run.apiLogPath
        dataFolder   = $run.dataFolder
    }

    if ((-not $WhatIf) -and $run.summaryPath -and (Test-Path $run.summaryPath)) {
        try {
            $result.summary = Get-Content -Raw $run.summaryPath | ConvertFrom-Json
        }
        catch {
            $result.summaryReadError = $_.Exception.Message
        }
    }

    $result | ConvertTo-Json -Depth 12
}
catch {
    $errorResult = [ordered]@{
        ok      = $false
        dataset = $Dataset
        message = $_.Exception.Message
    }

    $errorResult | ConvertTo-Json -Depth 8
    exit 1
}
