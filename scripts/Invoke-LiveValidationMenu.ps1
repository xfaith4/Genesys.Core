#Requires -Version 7.0
<#
.SYNOPSIS
    Interactive live-validation menu for Genesys.Core.
.DESCRIPTION
    Offers operator-run live validation options with explicit evidence levels:

    - Live catalog probe completed
    - Live Invoke-Dataset acceptance passed

    This script is intentionally not part of normal CI. It may touch a live
    Genesys Cloud org. Share only the generated shareable reports, not raw
    dataset artifacts under out/.
#>
[CmdletBinding()]
param(
    [string]$Region = $(if ($env:GENESYS_REGION) { $env:GENESYS_REGION } else { 'usw2.pure.cloud' }),

    [string]$OutputRoot = './out/live-validation-menu',

    [string]$CatalogPath = './catalog/genesys.catalog.json',

    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Release10Datasets = @(
    'users',
    'users.division.analysis.get.users.with.division.info',
    'routing.get.all.routing.skills',
    'routing-queues',
    'users.get.bulk.user.presences',
    'analytics.query.user.details.activity.report',
    'analytics-conversation-details-query'
)

function Write-MenuHeader {
    param([string]$Text)

    Write-Host ''
    Write-Host ('=' * ($Text.Length + 4)) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * ($Text.Length + 4)) -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor White
}

function Write-WarnLine {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Yellow
}

function Write-OkLine {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Green
}

function Get-RepoRoot {
    $scriptPath = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = (Get-Location).Path
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $scriptPath -ChildPath '..'))
}

function Resolve-RepoPath {
    param(
        [string]$RepoRoot,
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRoot -ChildPath $Path))
}

function ConvertTo-PlainMap {
    param([object]$InputObject)

    $result = [ordered]@{}
    if ($null -eq $InputObject) {
        return $result
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = $InputObject[$key]
        }

        return $result
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $result[[string]$property.Name] = $property.Value
    }

    return $result
}

function Get-MapValue {
    param(
        [object]$Map,
        [string]$Name
    )

    if ($null -eq $Map) {
        return $null
    }

    if ($Map -is [System.Collections.IDictionary]) {
        if ($Map.Contains($Name)) {
            return $Map[$Name]
        }

        return $null
    }

    if ($Map.PSObject.Properties.Name -contains $Name) {
        return $Map.$Name
    }

    return $null
}

function Test-PlaceholderValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return $true
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $true
    }

    return ($text -match '^\{.+\}$' -or
        $text -match '^<.+>$' -or
        $text -match '(?i)^(your-|sample-|example-)' -or
        $text -match '(?i)(conversation|communication|transaction|execution|client|user)-id(-\d+)?' -or
        $text -match '(?i)placeholder')
}

function Read-SecretText {
    param([string]$Prompt)

    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-LiveAuthHeaders {
    param([string]$CloudRegion)

    if (-not [string]::IsNullOrWhiteSpace($env:GENESYS_BEARER_TOKEN)) {
        return [pscustomobject]@{
            Headers = @{ Authorization = "Bearer $($env:GENESYS_BEARER_TOKEN)" }
            Source = 'GENESYS_BEARER_TOKEN'
            Token = $env:GENESYS_BEARER_TOKEN
        }
    }

    $clientId = $env:GENESYS_CLIENT_ID
    $clientSecret = $env:GENESYS_CLIENT_SECRET

    if ([string]::IsNullOrWhiteSpace($clientId)) {
        $clientId = Read-Host -Prompt 'OAuth client id'
    }

    if ([string]::IsNullOrWhiteSpace($clientSecret)) {
        $clientSecret = Read-SecretText -Prompt 'OAuth client secret'
    }

    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)) {
        throw 'Live validation requires GENESYS_BEARER_TOKEN or OAuth client credentials.'
    }

    $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($clientId):$($clientSecret)"))
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "https://login.$CloudRegion/oauth/token" `
        -Headers @{ Authorization = "Basic $encoded" } `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body 'grant_type=client_credentials' `
        -TimeoutSec 30 `
        -ErrorAction Stop

    if ($null -eq $response -or [string]::IsNullOrWhiteSpace([string]$response.access_token)) {
        throw 'OAuth response did not include access_token.'
    }

    return [pscustomobject]@{
        Headers = @{ Authorization = "Bearer $($response.access_token)" }
        Source = 'client_credentials'
        Token = [string]$response.access_token
    }
}

function Select-DatasetKeys {
    param([string[]]$AllDatasetKeys)

    Write-Host ''
    Write-Info 'Enter dataset keys separated by commas, or ? to list all keys.'
    while ($true) {
        $value = Read-Host -Prompt 'Dataset keys'
        if ($value -eq '?') {
            $AllDatasetKeys | Sort-Object | ForEach-Object { Write-Host "  $_" }
            continue
        }

        $selected = @(
            $value -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -ne '' }
        )

        if ($selected.Count -eq 0) {
            Write-WarnLine 'No dataset keys supplied.'
            continue
        }

        $missing = @($selected | Where-Object { $AllDatasetKeys -notcontains $_ })
        if ($missing.Count -gt 0) {
            Write-WarnLine "Unknown dataset key(s): $($missing -join ', ')"
            continue
        }

        return $selected
    }
}

function Get-CatalogData {
    param([string]$ResolvedCatalogPath)

    $catalog = Get-Content -Path $ResolvedCatalogPath -Raw | ConvertFrom-Json -AsHashtable
    $datasets = Get-MapValue -Map $catalog -Name 'datasets'
    $endpoints = Get-MapValue -Map $catalog -Name 'endpoints'

    if ($null -eq $datasets -or $null -eq $endpoints) {
        throw "Catalog '$ResolvedCatalogPath' is missing datasets or endpoints."
    }

    return [pscustomobject]@{
        Catalog = $catalog
        Datasets = $datasets
        Endpoints = $endpoints
        DatasetKeys = @($datasets.Keys | Sort-Object)
    }
}

function Test-AcceptancePreflight {
    param(
        [string]$DatasetKey,
        [object]$DatasetSpec,
        [object]$EndpointSpec
    )

    if ($null -eq $DatasetSpec) {
        return [pscustomobject]@{ IsRunnable = $false; Reason = 'Dataset key was not present in catalog.' }
    }

    if ($null -eq $EndpointSpec) {
        return [pscustomobject]@{ IsRunnable = $false; Reason = 'Endpoint key was not present in catalog.' }
    }

    $method = ([string](Get-MapValue -Map $EndpointSpec -Name 'method')).ToUpperInvariant()
    $path = [string](Get-MapValue -Map $EndpointSpec -Name 'path')
    $defaults = ConvertTo-PlainMap -InputObject (Get-MapValue -Map $EndpointSpec -Name 'defaultQueryParams')

    if ($method -notin @('GET', 'POST')) {
        return [pscustomobject]@{ IsRunnable = $false; Reason = "HTTP method '$method' is outside the safe acceptance menu." }
    }

    if ((Get-MapValue -Map $EndpointSpec -Name 'transactionProfile') -or
        (Get-MapValue -Map $EndpointSpec -Name 'transaction') -or
        $path -like '*/jobs' -or
        $path -like '*/usage/query' -or
        $path -eq '/api/v2/audits/query') {
        return [pscustomobject]@{ IsRunnable = $false; Reason = 'Async or transaction endpoint requires a dedicated acceptance path.' }
    }

    foreach ($match in [regex]::Matches($path, '\{([^}]+)\}')) {
        $name = [string]$match.Groups[1].Value
        if (-not $defaults.Contains($name) -or (Test-PlaceholderValue -Value $defaults[$name])) {
            return [pscustomobject]@{ IsRunnable = $false; Reason = "Route parameter '$name' requires a live value." }
        }
    }

    foreach ($key in @($defaults.Keys)) {
        if (Test-PlaceholderValue -Value $defaults[$key]) {
            if ($key -match '(?i)^(id|q64)$' -or $key -match '(?i)(conversation|communication|transaction|execution|client|user).*id') {
                return [pscustomobject]@{ IsRunnable = $false; Reason = "Query parameter '$key' requires a live value." }
            }
        }
    }

    if ($method -eq 'POST' -and -not (Get-MapValue -Map $EndpointSpec -Name 'defaultBody')) {
        return [pscustomobject]@{ IsRunnable = $false; Reason = 'POST dataset has no defaultBody in the catalog.' }
    }

    return [pscustomobject]@{ IsRunnable = $true; Reason = 'Safe bounded acceptance candidate.' }
}

function Set-PagingLimitSignal {
    param([object]$Response)

    if ($null -eq $Response) {
        return $Response
    }

    $propertyNames = @($Response.PSObject.Properties.Name)
    if ($propertyNames -contains 'nextUri') {
        $Response.nextUri = $null
    }
    else {
        $Response | Add-Member -MemberType NoteProperty -Name 'nextUri' -Value $null -Force
    }

    if ($propertyNames -contains 'cursor') {
        $Response.cursor = $null
    }

    if ($propertyNames -contains 'nextCursor') {
        $Response.nextCursor = $null
    }

    $Response | Add-Member -MemberType NoteProperty -Name 'totalHits' -Value 0 -Force
    $Response | Add-Member -MemberType NoteProperty -Name 'pageCount' -Value 1 -Force

    return $Response
}

function New-BoundedLiveRequestInvoker {
    param(
        [int]$Timeout,
        [int]$MaxRequests
    )

    $state = [pscustomobject]@{ Count = 0; Max = $MaxRequests; Timeout = $Timeout }

    return {
        param($request)

        $state.Count++
        if ($state.Count -gt $state.Max) {
            throw 'Live acceptance request cap reached.'
        }

        $invokeParams = @{
            Uri = [string]$request.Uri
            Method = [string]$request.Method
            TimeoutSec = $state.Timeout
            ErrorAction = 'Stop'
        }

        if ($request.PSObject.Properties.Name -contains 'Headers' -and $null -ne $request.Headers) {
            $invokeParams['Headers'] = $request.Headers
        }

        if ($request.PSObject.Properties.Name -contains 'Body' -and $null -ne $request.Body) {
            $invokeParams['Body'] = $request.Body
            $bodyText = [string]$request.Body
            if ($bodyText.TrimStart().StartsWith('{') -or $bodyText.TrimStart().StartsWith('[')) {
                $invokeParams['ContentType'] = 'application/json'
            }
        }

        $result = Invoke-RestMethod @invokeParams
        $result = Set-PagingLimitSignal -Response $result
        return [pscustomobject]@{ Result = $result }
    }.GetNewClosure()
}

function Get-RelativeDisplayPath {
    param(
        [string]$RepoRoot,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($fullPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return ($fullPath.Substring($root.Length) -replace '\\', '/')
    }

    return $fullPath
}

function Get-ArtifactSummary {
    param(
        [string]$RepoRoot,
        [object]$RunContext
    )

    $runFolder = if ($null -ne $RunContext -and $RunContext.PSObject.Properties.Name -contains 'runFolder') { [string]$RunContext.runFolder } else { $null }
    $manifestPath = if ($null -ne $RunContext -and $RunContext.PSObject.Properties.Name -contains 'manifestPath') { [string]$RunContext.manifestPath } else { $null }
    $eventsPath = if ($null -ne $RunContext -and $RunContext.PSObject.Properties.Name -contains 'eventsPath') { [string]$RunContext.eventsPath } else { $null }
    $summaryPath = if ($null -ne $RunContext -and $RunContext.PSObject.Properties.Name -contains 'summaryPath') { [string]$RunContext.summaryPath } else { $null }
    $dataFolder = if ($null -ne $RunContext -and $RunContext.PSObject.Properties.Name -contains 'dataFolder') { [string]$RunContext.dataFolder } else { $null }

    $dataFiles = if (-not [string]::IsNullOrWhiteSpace($dataFolder) -and (Test-Path -Path $dataFolder)) {
        @(Get-ChildItem -Path $dataFolder -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
    }
    else {
        @()
    }

    $recordCount = 0
    foreach ($file in $dataFiles) {
        $recordCount += @(
            Get-Content -Path $file.FullName -ErrorAction SilentlyContinue |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        ).Count
    }

    return [pscustomobject]@{
        ArtifactRoot = Get-RelativeDisplayPath -RepoRoot $RepoRoot -Path $runFolder
        ManifestPresent = (-not [string]::IsNullOrWhiteSpace($manifestPath) -and (Test-Path -Path $manifestPath))
        EventsPresent = (-not [string]::IsNullOrWhiteSpace($eventsPath) -and (Test-Path -Path $eventsPath))
        SummaryPresent = (-not [string]::IsNullOrWhiteSpace($summaryPath) -and (Test-Path -Path $summaryPath))
        DataJsonlPresent = ($dataFiles.Count -gt 0)
        SanitizedRecordCount = $recordCount
    }
}

function New-AcceptanceResult {
    param(
        [string]$DatasetKey,
        [string]$Region,
        [string]$CommandRun,
        [string]$Status,
        [string]$Reason,
        [object]$Artifacts
    )

    if ($null -eq $Artifacts) {
        $Artifacts = [pscustomobject]@{
            ArtifactRoot = $null
            ManifestPresent = $false
            EventsPresent = $false
            SummaryPresent = $false
            DataJsonlPresent = $false
            SanitizedRecordCount = 0
        }
    }

    return [pscustomobject]@{
        DatasetKey = $DatasetKey
        CommandRun = $CommandRun
        UtcTimestamp = [DateTime]::UtcNow.ToString('o')
        Region = $Region
        EvidenceLevel = 'Live Invoke-Dataset acceptance passed'
        Status = $Status
        ArtifactRoot = $Artifacts.ArtifactRoot
        ManifestPresent = $Artifacts.ManifestPresent
        EventsPresent = $Artifacts.EventsPresent
        SummaryPresent = $Artifacts.SummaryPresent
        DataJsonlPresent = $Artifacts.DataJsonlPresent
        SanitizedRecordCount = $Artifacts.SanitizedRecordCount
        Reason = $Reason
    }
}

function Write-AcceptanceReport {
    param(
        [object[]]$Results,
        [string]$Directory
    )

    if (-not (Test-Path -Path $Directory)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }

    $jsonPath = Join-Path -Path $Directory -ChildPath 'live-invoke-dataset-acceptance-shareable-report.json'
    $csvPath = Join-Path -Path $Directory -ChildPath 'live-invoke-dataset-acceptance-shareable-report.csv'
    $markdownPath = Join-Path -Path $Directory -ChildPath 'live-invoke-dataset-acceptance-shareable-report.md'

    $summary = [ordered]@{}
    foreach ($status in @('passed', 'failed', 'skipped')) {
        $summary[$status] = @($Results | Where-Object { $_.Status -eq $status }).Count
    }

    [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        evidenceLevel = 'Live Invoke-Dataset acceptance passed'
        summary = $summary
        results = $Results
    } | ConvertTo-Json -Depth 100 | Set-Content -Path $jsonPath -Encoding utf8

    $Results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Live Invoke-Dataset Acceptance Shareable Report')
    $lines.Add('')
    $lines.Add('This report intentionally omits OAuth tokens, request URLs with live values, supplied parameter values, response bodies, JSONL records, raw exception text, and org-specific identifiers.')
    $lines.Add('')
    $lines.Add('## Summary')
    foreach ($key in $summary.Keys) {
        $lines.Add("- ${key}: $($summary[$key])")
    }
    $lines.Add('')
    $lines.Add('## Results')
    foreach ($result in $Results) {
        $lines.Add("- ``$($result.DatasetKey)`` - $($result.Status) - records $($result.SanitizedRecordCount) - artifact $($result.ArtifactRoot) - $($result.Reason)")
    }

    $lines | Set-Content -Path $markdownPath -Encoding utf8

    return [pscustomobject]@{
        Json = $jsonPath
        Csv = $csvPath
        Markdown = $markdownPath
        Summary = $summary
    }
}

function Invoke-LiveProbeMenuRun {
    param(
        [string[]]$Datasets,
        [string]$RepoRoot,
        [string]$OutputDirectory,
        [string]$CloudRegion,
        [string]$BearerToken
    )

    $probeScript = Join-Path -Path $RepoRoot -ChildPath 'tests/integration/Invoke-LiveCatalogDatasetPass.ps1'
    if (-not (Test-Path -Path $probeScript)) {
        throw "Live catalog probe script not found: $probeScript"
    }

    $previousToken = $env:GENESYS_BEARER_TOKEN
    try {
        if (-not [string]::IsNullOrWhiteSpace($BearerToken)) {
            $env:GENESYS_BEARER_TOKEN = $BearerToken
        }

        $params = @{
            Region = $CloudRegion
            OutputRoot = $OutputDirectory
        }

        if ($null -ne $Datasets -and $Datasets.Count -gt 0) {
            $params['Dataset'] = $Datasets
        }

        & $probeScript @params
    }
    finally {
        $env:GENESYS_BEARER_TOKEN = $previousToken
    }
}

function Invoke-LiveAcceptanceRun {
    param(
        [string[]]$Datasets,
        [object]$CatalogData,
        [string]$RepoRoot,
        [string]$ResolvedCatalogPath,
        [string]$OutputDirectory,
        [string]$CloudRegion,
        [hashtable]$Headers,
        [int]$Timeout
    )

    $coreModule = Join-Path -Path $RepoRoot -ChildPath 'modules/Genesys.Core/Genesys.Core.psd1'
    Import-Module $coreModule -Force

    $baseUri = "https://api.$CloudRegion"
    $acceptanceOutputRoot = Join-Path -Path $OutputDirectory -ChildPath 'invoke-dataset-artifacts'
    $reportOutputRoot = Join-Path -Path $OutputDirectory -ChildPath 'reports'
    $commandRun = 'Invoke-Dataset via scripts/Invoke-LiveValidationMenu.ps1'
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($datasetKey in $Datasets) {
        Write-Host ''
        Write-Host "  Accepting $datasetKey..." -ForegroundColor DarkCyan

        $datasetSpec = Get-MapValue -Map $CatalogData.Datasets -Name $datasetKey
        $endpointKey = [string](Get-MapValue -Map $datasetSpec -Name 'endpoint')
        $endpointSpec = Get-MapValue -Map $CatalogData.Endpoints -Name $endpointKey
        $preflight = Test-AcceptancePreflight -DatasetKey $datasetKey -DatasetSpec $datasetSpec -EndpointSpec $endpointSpec

        if (-not $preflight.IsRunnable) {
            $results.Add((New-AcceptanceResult -DatasetKey $datasetKey -Region $CloudRegion -CommandRun $commandRun -Status 'skipped' -Reason $preflight.Reason -Artifacts $null)) | Out-Null
            Write-WarnLine "Skipped: $($preflight.Reason)"
            continue
        }

        $requestInvoker = New-BoundedLiveRequestInvoker -Timeout $Timeout -MaxRequests 5
        $runContext = $null
        try {
            $runContext = Invoke-Dataset `
                -Dataset $datasetKey `
                -CatalogPath $ResolvedCatalogPath `
                -OutputRoot $acceptanceOutputRoot `
                -BaseUri $baseUri `
                -Headers $Headers `
                -DatasetParameters @{ Query = @{ pageSize = 1; pageNumber = 1 } } `
                -RequestInvoker $requestInvoker `
                -ErrorAction Stop

            $artifacts = Get-ArtifactSummary -RepoRoot $RepoRoot -RunContext $runContext
            $requiredArtifactsPresent = $artifacts.ManifestPresent -and $artifacts.EventsPresent -and $artifacts.SummaryPresent -and $artifacts.DataJsonlPresent
            if ($requiredArtifactsPresent) {
                $results.Add((New-AcceptanceResult -DatasetKey $datasetKey -Region $CloudRegion -CommandRun $commandRun -Status 'passed' -Reason 'Sanitized run artifacts were produced.' -Artifacts $artifacts)) | Out-Null
                Write-OkLine 'Passed: sanitized artifact contract present.'
            }
            else {
                $results.Add((New-AcceptanceResult -DatasetKey $datasetKey -Region $CloudRegion -CommandRun $commandRun -Status 'failed' -Reason 'Run completed but required artifact files were missing.' -Artifacts $artifacts)) | Out-Null
                Write-WarnLine 'Failed: run completed but required artifact files were missing.'
            }
        }
        catch {
            Write-Verbose "Live acceptance for '$datasetKey' failed locally: $($_.Exception.Message)"
            $artifacts = Get-ArtifactSummary -RepoRoot $RepoRoot -RunContext $runContext
            $results.Add((New-AcceptanceResult -DatasetKey $datasetKey -Region $CloudRegion -CommandRun $commandRun -Status 'failed' -Reason 'Invoke-Dataset raised an exception; raw exception details were not written to the report.' -Artifacts $artifacts)) | Out-Null
            Write-WarnLine 'Failed: Invoke-Dataset raised an exception. Raw details omitted from report.'
        }
    }

    $report = Write-AcceptanceReport -Results @($results.ToArray()) -Directory $reportOutputRoot
    Write-Host ''
    Write-OkLine "Acceptance report: $($report.Markdown)"
    foreach ($status in $report.Summary.Keys) {
        Write-Info "${status}: $($report.Summary[$status])"
    }
}

$repoRoot = Get-RepoRoot
$resolvedCatalogPath = Resolve-RepoPath -RepoRoot $repoRoot -Path $CatalogPath
$resolvedOutputRoot = Resolve-RepoPath -RepoRoot $repoRoot -Path $OutputRoot

if (-not (Test-Path -Path $resolvedCatalogPath)) {
    throw "Catalog not found: $resolvedCatalogPath"
}

$catalogData = Get-CatalogData -ResolvedCatalogPath $resolvedCatalogPath

Write-MenuHeader 'Genesys.Core Live Validation Menu'
Write-Info "Region: $Region"
Write-Info "Catalog: $resolvedCatalogPath"
Write-Info "Output: $resolvedOutputRoot"
Write-WarnLine 'Live data stays local under out/. Share only the generated shareable reports.'

$auth = Get-LiveAuthHeaders -CloudRegion $Region
Write-OkLine "Auth resolved from $($auth.Source)."

:menuLoop while ($true) {
    Write-MenuHeader 'Select validation action'
    Write-Host '  1. Live catalog probe - all catalog datasets' -ForegroundColor White
    Write-Host '  2. Live catalog probe - selected datasets' -ForegroundColor White
    Write-Host '  3. Live Invoke-Dataset acceptance - all safe catalog datasets' -ForegroundColor White
    Write-Host '  4. Live Invoke-Dataset acceptance - selected datasets' -ForegroundColor White
    Write-Host '  5. Live Invoke-Dataset acceptance - Release 1.0 Agent Investigation datasets' -ForegroundColor White
    Write-Host '  Q. Quit' -ForegroundColor DarkGray
    Write-Host ''

    $choice = (Read-Host -Prompt 'Choice').Trim()
    switch -Regex ($choice) {
        '^[qQ]$' {
            break menuLoop
        }
        '^1$' {
            Invoke-LiveProbeMenuRun -Datasets @() -RepoRoot $repoRoot -OutputDirectory (Join-Path $resolvedOutputRoot 'catalog-probe') -CloudRegion $Region -BearerToken $auth.Token
        }
        '^2$' {
            $selected = Select-DatasetKeys -AllDatasetKeys $catalogData.DatasetKeys
            Invoke-LiveProbeMenuRun -Datasets $selected -RepoRoot $repoRoot -OutputDirectory (Join-Path $resolvedOutputRoot 'catalog-probe') -CloudRegion $Region -BearerToken $auth.Token
        }
        '^3$' {
            Invoke-LiveAcceptanceRun -Datasets $catalogData.DatasetKeys -CatalogData $catalogData -RepoRoot $repoRoot -ResolvedCatalogPath $resolvedCatalogPath -OutputDirectory $resolvedOutputRoot -CloudRegion $Region -Headers $auth.Headers -Timeout $TimeoutSeconds
        }
        '^4$' {
            $selected = Select-DatasetKeys -AllDatasetKeys $catalogData.DatasetKeys
            Invoke-LiveAcceptanceRun -Datasets $selected -CatalogData $catalogData -RepoRoot $repoRoot -ResolvedCatalogPath $resolvedCatalogPath -OutputDirectory $resolvedOutputRoot -CloudRegion $Region -Headers $auth.Headers -Timeout $TimeoutSeconds
        }
        '^5$' {
            Invoke-LiveAcceptanceRun -Datasets $Release10Datasets -CatalogData $catalogData -RepoRoot $repoRoot -ResolvedCatalogPath $resolvedCatalogPath -OutputDirectory $resolvedOutputRoot -CloudRegion $Region -Headers $auth.Headers -Timeout $TimeoutSeconds
        }
        default {
            Write-WarnLine 'Invalid choice.'
        }
    }
}
