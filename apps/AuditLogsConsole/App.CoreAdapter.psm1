#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:CoreState = [ordered]@{
    Initialized    = $false
    CoreModulePath = $null
    AuthModulePath = $null
    CatalogPath    = $null
    SchemaPath     = $null
    OutputRoot     = $null
    DatasetKeys    = $null
    PreviewConfig  = $null
}

function Initialize-CoreIntegration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CoreModulePath,
        [Parameter(Mandatory)][string]$AuthModulePath,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][hashtable]$DatasetKeys,
        [Parameter(Mandatory)][hashtable]$PreviewConfig
    )

    foreach ($path in @($CoreModulePath, $AuthModulePath, $CatalogPath, $SchemaPath)) {
        if (-not [System.IO.File]::Exists($path)) {
            throw "Required file was not found: $path"
        }
    }

    Import-Module $AuthModulePath -Force -ErrorAction Stop
    Import-Module $CoreModulePath -Force -ErrorAction Stop
    Assert-Catalog -CatalogPath $CatalogPath -SchemaPath $SchemaPath -ErrorAction Stop | Out-Null

    if (-not [System.IO.Directory]::Exists($OutputRoot)) {
        [System.IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
    }

    $script:CoreState.Initialized    = $true
    $script:CoreState.CoreModulePath = $CoreModulePath
    $script:CoreState.AuthModulePath = $AuthModulePath
    $script:CoreState.CatalogPath    = $CatalogPath
    $script:CoreState.SchemaPath     = $SchemaPath
    $script:CoreState.OutputRoot     = $OutputRoot
    $script:CoreState.DatasetKeys    = $DatasetKeys
    $script:CoreState.PreviewConfig  = $PreviewConfig

    return [pscustomobject]@{
        Ready        = $true
        CoreModule   = $CoreModulePath
        CatalogPath  = $CatalogPath
        SchemaPath   = $SchemaPath
        OutputRoot   = $OutputRoot
        DatasetKeys  = $DatasetKeys
    }
}

function Get-CoreIntegrationState {
    [CmdletBinding()]
    param()

    return [pscustomobject]$script:CoreState
}

function Test-CoreIntegrationReady {
    [CmdletBinding()]
    param()

    return [bool]$script:CoreState.Initialized
}

function _RequireInitialized {
    if (-not $script:CoreState.Initialized) {
        throw 'Core integration has not been initialized.'
    }
}

function Connect-AuditSession {
    [CmdletBinding()]
    param(
        [string]$AccessToken,
        [string]$Region = 'usw2.pure.cloud'
    )

    _RequireInitialized

    $effectiveToken = $AccessToken
    if ([string]::IsNullOrWhiteSpace($effectiveToken)) {
        $effectiveToken = $env:GENESYS_BEARER_TOKEN
    }

    if ([string]::IsNullOrWhiteSpace($effectiveToken)) {
        throw 'No bearer token was supplied. Enter a token or set GENESYS_BEARER_TOKEN.'
    }

    $effectiveRegion = [string]$Region
    if ($effectiveRegion -match '^https?://api\.') {
        $effectiveRegion = $effectiveRegion -replace '^https?://api\.', ''
    }
    elseif ($effectiveRegion -match '^api\.') {
        $effectiveRegion = $effectiveRegion -replace '^api\.', ''
    }

    return Connect-GenesysCloud -AccessToken $effectiveToken -Region $effectiveRegion
}

function Connect-AuditSessionPkce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [string]$Region = 'usw2.pure.cloud',
        [string]$RedirectUri = 'http://localhost:8085/callback',
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    _RequireInitialized

    $effectiveRegion = [string]$Region
    if ($effectiveRegion -match '^https?://api\.') {
        $effectiveRegion = $effectiveRegion -replace '^https?://api\.', ''
    }
    elseif ($effectiveRegion -match '^api\.') {
        $effectiveRegion = $effectiveRegion -replace '^api\.', ''
    }

    return Connect-GenesysCloudPkce -ClientId $ClientId -Region $effectiveRegion -RedirectUri $RedirectUri -CancellationToken $CancellationToken
}

function Get-AuditSession {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name Get-GenesysAuthContext -ErrorAction SilentlyContinue)) {
        return $null
    }

    return Get-GenesysAuthContext
}

function Get-AuditFilterOptions {
    [CmdletBinding()]
    param()

    _RequireInitialized

    $session = Get-AuditSession
    if ($null -eq $session) {
        throw 'No active Genesys session. Connect first.'
    }

    $mappings = @(Get-AuditServiceMapping -CatalogPath $script:CoreState.CatalogPath -BaseUri $session.BaseUri -Headers $session.Headers)
    $actionsByService = [ordered]@{}

    foreach ($mapping in $mappings) {
        $serviceName = [string]$mapping.ServiceName
        if ([string]::IsNullOrWhiteSpace($serviceName)) {
            continue
        }

        $actionsByService[$serviceName] = @($mapping.Actions | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    }

    return [pscustomobject]@{
        ServiceNames     = @($mappings | ForEach-Object { [string]$_.ServiceName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        Actions          = @($mappings | ForEach-Object { @($_.Actions) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        ActionsByService = $actionsByService
        ServiceMappings  = $mappings
    }
}

function _Split-FilterValues {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return @(([string]$Value) -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function New-AuditDatasetParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$QuerySpec,
        [Parameter(Mandatory)][ValidateSet('Preview', 'Full')][string]$Mode
    )

    _RequireInitialized

    if (-not $QuerySpec.ContainsKey('StartUtc') -or -not $QuerySpec.ContainsKey('EndUtc')) {
        throw 'QuerySpec must include StartUtc and EndUtc.'
    }

    $startUtc = [datetime]$QuerySpec.StartUtc
    $endUtc   = [datetime]$QuerySpec.EndUtc
    if ($endUtc -lt $startUtc) {
        throw 'End time must be greater than or equal to start time.'
    }

    $notes = New-Object System.Collections.Generic.List[string]
    if ($Mode -eq 'Preview') {
        $maxHours = [double]$script:CoreState.PreviewConfig.MaxWindowHours
        $windowHours = ($endUtc - $startUtc).TotalHours
        if ($windowHours -gt $maxHours) {
            $startUtc = $endUtc.AddHours(-1 * $maxHours)
            $notes.Add("Preview window clamped to the most recent $maxHours hours for faster operator feedback.")
        }
    }

    $datasetParameters = [ordered]@{
        StartUtc = $startUtc.ToString('o')
        EndUtc   = $endUtc.ToString('o')
    }

    $serviceNames = _Split-FilterValues -Value $QuerySpec.Service
    if ($serviceNames.Count -gt 0) {
        $datasetParameters.ServiceNames = $serviceNames
    }

    $actions = _Split-FilterValues -Value $QuerySpec.Action
    if ($actions.Count -gt 0) {
        $datasetParameters.Actions = $actions

        $entityTypes = _Split-FilterValues -Value $QuerySpec.Entity
        if ($entityTypes.Count -eq 0) {
            throw 'Action filtering requires the Entity field to contain a Genesys audit EntityType, such as Queue or Row. Leave Action blank to run a broader extract and filter locally after the run.'
        }

        $datasetParameters.EntityTypes = $entityTypes
    }

    return [pscustomobject]@{
        DatasetParameters = $datasetParameters
        EffectiveStartUtc = $startUtc
        EffectiveEndUtc   = $endUtc
        Notes             = $notes.ToArray()
    }
}

function _StartAuditRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$QuerySpec,
        [Parameter(Mandatory)][ValidateSet('Preview', 'Full')][string]$Mode
    )

    _RequireInitialized

    $session = Get-AuditSession
    if ($null -eq $session) {
        throw 'No active Genesys session. Connect first.'
    }

    $resolved = New-AuditDatasetParameters -QuerySpec $QuerySpec -Mode $Mode
    $datasetKey = if ($Mode -eq 'Preview') { $script:CoreState.DatasetKeys.Preview } else { $script:CoreState.DatasetKeys.Full }

    $invokeParams = @{
        Dataset           = $datasetKey
        CatalogPath       = $script:CoreState.CatalogPath
        OutputRoot        = $script:CoreState.OutputRoot
        BaseUri           = $session.BaseUri
        Headers           = $session.Headers
        DatasetParameters = $resolved.DatasetParameters
        ErrorAction       = 'Stop'
    }

    $runContext = Invoke-Dataset @invokeParams
    return [pscustomobject]@{
        RunContext = $runContext
        Request    = $QuerySpec
        Effective  = $resolved
        Mode       = $Mode
        DatasetKey = $datasetKey
    }
}

function Start-AuditPreviewRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$QuerySpec
    )

    return _StartAuditRun -QuerySpec $QuerySpec -Mode 'Preview'
}

function Start-AuditFullRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$QuerySpec
    )

    return _StartAuditRun -QuerySpec $QuerySpec -Mode 'Full'
}

function Get-RunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    $path = [System.IO.Path]::Combine($RunFolder, 'manifest.json')
    if (-not [System.IO.File]::Exists($path)) {
        return $null
    }

    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $raw | ConvertFrom-Json
}

function Get-RunSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    $path = [System.IO.Path]::Combine($RunFolder, 'summary.json')
    if (-not [System.IO.File]::Exists($path)) {
        return $null
    }

    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $raw | ConvertFrom-Json
}

function Get-RunRequestMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    $path = [System.IO.Path]::Combine($RunFolder, 'app.request.json')
    if (-not [System.IO.File]::Exists($path)) {
        return $null
    }

    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $raw | ConvertFrom-Json
}

function Save-RunRequestMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][hashtable]$QuerySpec,
        [Parameter(Mandatory)][ValidateSet('Preview', 'Full')][string]$Mode,
        [Parameter(Mandatory)][string]$DatasetKey,
        [AllowNull()][object]$Effective
    )

    $payload = [ordered]@{
        datasetKey    = $DatasetKey
        mode          = $Mode
        capturedAtUtc = [datetime]::UtcNow.ToString('o')
        query         = $QuerySpec
        effective     = $Effective
    }

    $path = [System.IO.Path]::Combine($RunFolder, 'app.request.json')
    $payload | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Get-RunEventTail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [int]$LastN = 50
    )

    $path = [System.IO.Path]::Combine($RunFolder, 'events.jsonl')
    if (-not [System.IO.File]::Exists($path)) {
        return @()
    }

    $events = New-Object System.Collections.Generic.List[object]
    $fs = [System.IO.FileStream]::new(
        $path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
    try {
        while (-not $sr.EndOfStream) {
            $line = $sr.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                $events.Add(($line | ConvertFrom-Json))
            }
            catch {
            }
        }
    }
    finally {
        $sr.Dispose()
        $fs.Dispose()
    }

    if ($events.Count -le $LastN) {
        return $events.ToArray()
    }

    return $events.GetRange($events.Count - $LastN, $LastN).ToArray()
}

function Get-RunStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    if (-not [System.IO.Directory]::Exists($RunFolder)) {
        return 'Queued'
    }

    $events = Get-RunEventTail -RunFolder $RunFolder -LastN 25
    if (@($events | Where-Object { $_.eventType -eq 'run.failed' }).Count -gt 0) {
        return 'Failed'
    }

    if (@($events | Where-Object { $_.eventType -eq 'run.completed' }).Count -gt 0) {
        return 'Completed'
    }

    if ($null -ne (Get-RunManifest -RunFolder $RunFolder)) {
        return 'Completed'
    }

    return 'Running'
}

function _GetRunFoldersForDataset {
    param(
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][string]$DatasetKey
    )

    $datasetRoot = [System.IO.Path]::Combine($OutputRoot, $DatasetKey)
    if (-not [System.IO.Directory]::Exists($datasetRoot)) {
        return @()
    }

    return [System.IO.Directory]::GetDirectories($datasetRoot)
}

function Get-RecentRuns {
    [CmdletBinding()]
    param(
        [int]$Max = 20
    )

    _RequireInitialized

    $runEntries = New-Object System.Collections.Generic.List[object]
    $datasetKeys = @(
        [string]$script:CoreState.DatasetKeys.Default
        [string]$script:CoreState.DatasetKeys.Preview
        [string]$script:CoreState.DatasetKeys.Full
    ) | Select-Object -Unique

    foreach ($datasetKey in $datasetKeys) {
        foreach ($runFolder in @(_GetRunFoldersForDataset -OutputRoot $script:CoreState.OutputRoot -DatasetKey $datasetKey)) {
            $manifest = Get-RunManifest -RunFolder $runFolder
            $summary  = Get-RunSummary -RunFolder $runFolder
            $request  = Get-RunRequestMetadata -RunFolder $runFolder
            $runEntries.Add([pscustomobject]@{
                DatasetKey   = $datasetKey
                RunFolder    = $runFolder
                RunId        = [System.IO.Path]::GetFileName($runFolder)
                StartedAtUtc = if ($null -ne $manifest) { $manifest.startedAtUtc } else { [System.IO.Directory]::GetCreationTimeUtc($runFolder).ToString('o') }
                Status       = Get-RunStatus -RunFolder $runFolder
                Mode         = if ($null -ne $request) { [string]$request.mode } else { '' }
                TotalRecords = if ($null -ne $summary -and $summary.totals) { [int]$summary.totals.totalRecords } else { 0 }
            })
        }
    }

    $sorted = @($runEntries.ToArray() | Sort-Object {
        try { [datetime]$_.StartedAtUtc } catch { [datetime]::MinValue }
    } -Descending)

    if ($sorted.Count -le $Max) {
        return $sorted
    }

    return $sorted[0..($Max - 1)]
}

function Get-RunDiagnosticsText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [int]$EventCount = 50
    )

    $manifest = Get-RunManifest -RunFolder $RunFolder
    $summary  = Get-RunSummary -RunFolder $RunFolder
    $request  = Get-RunRequestMetadata -RunFolder $RunFolder
    $events   = Get-RunEventTail -RunFolder $RunFolder -LastN $EventCount

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Genesys Audit Logs Console Diagnostics')
    [void]$sb.AppendLine("Run folder : $RunFolder")
    [void]$sb.AppendLine("Status     : $(Get-RunStatus -RunFolder $RunFolder)")
    if ($null -ne $manifest) {
        [void]$sb.AppendLine("Dataset    : $($manifest.datasetKey)")
        [void]$sb.AppendLine("Run id     : $($manifest.runId)")
    }

    if ($null -ne $request) {
        [void]$sb.AppendLine("Mode       : $($request.mode)")
        [void]$sb.AppendLine("Filters    : $($request.query | ConvertTo-Json -Compress -Depth 8)")
    }

    if ($null -ne $summary) {
        [void]$sb.AppendLine("Summary    : $($summary | ConvertTo-Json -Compress -Depth 8)")
    }

    [void]$sb.AppendLine('Events:')
    foreach ($event in $events) {
        [void]$sb.AppendLine(($event | ConvertTo-Json -Compress -Depth 8))
    }

    return $sb.ToString()
}

Export-ModuleMember -Function `
    Initialize-CoreIntegration, Get-CoreIntegrationState, Test-CoreIntegrationReady, `
    Connect-AuditSession, Connect-AuditSessionPkce, Get-AuditSession, Get-AuditFilterOptions, New-AuditDatasetParameters, `
    Start-AuditPreviewRun, Start-AuditFullRun, `
    Get-RecentRuns, Get-RunManifest, Get-RunSummary, Get-RunRequestMetadata, Save-RunRequestMetadata, `
    Get-RunEventTail, Get-RunStatus, Get-RunDiagnosticsText
