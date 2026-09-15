#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ClientId = $env:GENESYS_CLIENT_ID,

    [Alias('ClientSecret', 'Password')]
    [string]$ClientPassword,

    [string]$BearerToken = $env:GENESYS_BEARER_TOKEN,

    [string]$Region = 'usw2.pure.cloud',

    [string]$CatalogPath = (Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'),

    [string]$OutputRoot = (Join-Path -Path $PSScriptRoot -ChildPath '../../out/live-catalog-pass'),

    [string[]]$Dataset,

    [string]$ParameterJson,

    [ValidateRange(1, 168)]
    [int]$LookbackHours = 1,

    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 30,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AllowedStatuses = @('Working', 'Empty', 'Unsupported', 'Needs Parameters', 'Shape Mismatch')

function Get-MapValue {
    param(
        [object]$Map,
        [string]$Name
    )

    if ($null -eq $Map -or [string]::IsNullOrWhiteSpace($Name)) {
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

function Get-MapKeys {
    param([object]$Map)

    if ($null -eq $Map) {
        return @()
    }

    if ($Map -is [System.Collections.IDictionary]) {
        return @($Map.Keys)
    }

    return @($Map.PSObject.Properties.Name)
}

function Test-MapKey {
    param(
        [object]$Map,
        [string]$Name
    )

    if ($null -eq $Map -or [string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    if ($Map -is [System.Collections.IDictionary]) {
        return $Map.Contains($Name)
    }

    return @($Map.PSObject.Properties.Name) -contains $Name
}

function ConvertTo-PlainHashtable {
    param([object]$InputObject)

    $result = [ordered]@{}
    foreach ($key in Get-MapKeys -Map $InputObject) {
        $result[[string]$key] = Get-MapValue -Map $InputObject -Name ([string]$key)
    }

    return $result
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

function ConvertTo-QueryText {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [array]) {
        return [string]::Join(',', @($Value | ForEach-Object { [string]$_ }))
    }

    return [string]$Value
}

function Add-QueryValue {
    param(
        [string]$Uri,
        [string]$Name,
        [object]$Value
    )

    $text = ConvertTo-QueryText -Value $Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Uri
    }

    $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
    return "$Uri$separator$([System.Uri]::EscapeDataString($Name))=$([System.Uri]::EscapeDataString($text))"
}

function Get-JsonPathValue {
    param(
        [object]$InputObject,
        [string]$Path
    )

    if ($null -eq $InputObject) {
        return [pscustomobject]@{ Found = $false; Value = $null }
    }

    $normalized = [string]$Path
    if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq '$' -or $normalized -eq '$.') {
        return [pscustomobject]@{ Found = $true; Value = $InputObject }
    }

    if ($normalized.StartsWith('$.')) {
        $normalized = $normalized.Substring(2)
    }

    $target = $InputObject
    foreach ($segment in ($normalized -split '\.')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        if ($null -eq $target) {
            return [pscustomobject]@{ Found = $false; Value = $null }
        }

        if ($target -is [System.Collections.IDictionary]) {
            if (-not $target.Contains($segment)) {
                return [pscustomobject]@{ Found = $false; Value = $null }
            }

            $target = $target[$segment]
            continue
        }

        if ($target.PSObject.Properties.Name -contains $segment) {
            $target = $target.$segment
            continue
        }

        return [pscustomobject]@{ Found = $false; Value = $null }
    }

    return [pscustomobject]@{ Found = $true; Value = $target }
}

function Get-ItemCount {
    param([object]$Value)

    if ($null -eq $Value) {
        return 0
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return 0
        }

        return 1
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) {
        return @($Value).Count
    }

    return 1
}

function Resolve-LiveInterval {
    param([int]$Hours)

    $endUtc = [DateTime]::UtcNow
    $startUtc = $endUtc.AddHours(-1 * $Hours)
    return "$($startUtc.ToString('o'))/$($endUtc.ToString('o'))"
}

function New-LiveProbeBody {
    param(
        [string]$DatasetKey,
        [object]$Endpoint,
        [int]$Hours
    )

    if (Test-MapKey -Map $Endpoint -Name 'defaultBody') {
        $defaultBody = Get-MapValue -Map $Endpoint -Name 'defaultBody'
        if ($null -ne $defaultBody) {
            return $defaultBody
        }
    }

    $path = [string](Get-MapValue -Map $Endpoint -Name 'path')
    $interval = Resolve-LiveInterval -Hours $Hours

    if ($path -eq '/api/v2/analytics/conversations/details/query') {
        return [ordered]@{
            interval = $interval
            order = 'desc'
            orderBy = 'conversationStart'
            paging = [ordered]@{ pageSize = 1; pageNumber = 1 }
        }
    }

    if ($path -eq '/api/v2/analytics/users/details/query') {
        return [ordered]@{
            interval = $interval
            paging = [ordered]@{ pageSize = 1; pageNumber = 1 }
        }
    }

    if ($path -eq '/api/v2/analytics/conversations/aggregates/query') {
        return [ordered]@{
            interval = $interval
            granularity = 'PT1H'
            metrics = @('nOffered')
        }
    }

    if ($path -eq '/api/v2/analytics/users/aggregates/query') {
        return [ordered]@{
            interval = $interval
            granularity = 'PT1H'
            metrics = @('tSystemPresence')
        }
    }

    if ($path -eq '/api/v2/analytics/flows/aggregates/query') {
        return [ordered]@{
            interval = $interval
            granularity = 'PT1H'
            metrics = @('nFlow')
        }
    }

    if ($path -like '/api/v2/analytics/*/observations/query') {
        return [ordered]@{}
    }

    if ($path -like '/api/v2/analytics/*/aggregates/query') {
        return [ordered]@{
            interval = $interval
            granularity = 'PT1H'
        }
    }

    return $null
}

function Get-LiveCatalogAccessToken {
    param(
        [string]$Token,
        [string]$Id,
        [string]$Secret,
        [string]$CloudRegion
    )

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        return $Token
    }

    if ([string]::IsNullOrWhiteSpace($Secret)) {
        if (-not [string]::IsNullOrWhiteSpace($env:GENESYS_CLIENT_SECRET)) {
            $Secret = $env:GENESYS_CLIENT_SECRET
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:GENESYS_CLIENT_PASSWORD)) {
            $Secret = $env:GENESYS_CLIENT_PASSWORD
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:GENESYS_PASSWORD)) {
            $Secret = $env:GENESYS_PASSWORD
        }
    }

    if ([string]::IsNullOrWhiteSpace($Id) -or [string]::IsNullOrWhiteSpace($Secret)) {
        throw 'Live catalog pass requires GENESYS_BEARER_TOKEN or OAuth client credentials. Pass -ClientId and -ClientPassword, or set GENESYS_CLIENT_ID and GENESYS_CLIENT_SECRET.'
    }

    $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($Id):$($Secret)"))
    $headers = @{ Authorization = "Basic $encoded" }
    $response = Invoke-RestMethod -Method Post -Uri "https://login.$CloudRegion/oauth/token" -Headers $headers -ContentType 'application/x-www-form-urlencoded' -Body 'grant_type=client_credentials' -TimeoutSec 30
    if ($null -eq $response -or [string]::IsNullOrWhiteSpace([string]$response.access_token)) {
        throw 'OAuth token response did not include access_token.'
    }

    return [string]$response.access_token
}

function New-LiveProbeRequest {
    param(
        [string]$DatasetKey,
        [object]$DatasetSpec,
        [object]$Endpoint,
        [string]$BaseUri,
        [hashtable]$Parameters,
        [int]$Hours
    )

    $method = ([string](Get-MapValue -Map $Endpoint -Name 'method')).ToUpperInvariant()
    $path = [string](Get-MapValue -Map $Endpoint -Name 'path')
    $queryValues = ConvertTo-PlainHashtable -InputObject (Get-MapValue -Map $Endpoint -Name 'defaultQueryParams')

    foreach ($key in @($Parameters.Keys)) {
        $queryValues[[string]$key] = $Parameters[$key]
    }

    $routeMatches = [regex]::Matches($path, '\{([^}]+)\}')
    foreach ($match in $routeMatches) {
        $name = [string]$match.Groups[1].Value
        $value = $queryValues[$name]
        if (Test-PlaceholderValue -Value $value) {
            return [pscustomobject]@{
                Status = 'Needs Parameters'
                Reason = "Route parameter '$name' is required."
            }
        }

        $path = $path.Replace("{$name}", [System.Uri]::EscapeDataString([string]$value))
        $queryValues.Remove($name)
    }

    foreach ($key in @($queryValues.Keys)) {
        $value = $queryValues[$key]
        if (Test-PlaceholderValue -Value $value) {
            if ($key -match '(?i)^(id|q64)$' -or $key -match '(?i)(conversation|communication|transaction|execution|client|user).*id') {
                return [pscustomobject]@{
                    Status = 'Needs Parameters'
                    Reason = "Query parameter '$key' is required."
                }
            }

            $queryValues.Remove($key)
        }
    }

    if ($Parameters.ContainsKey('pageSize')) {
        $queryValues['pageSize'] = $Parameters['pageSize']
    }
    else {
        $queryValues['pageSize'] = 1
    }

    if ($Parameters.ContainsKey('pageNumber')) {
        $queryValues['pageNumber'] = $Parameters['pageNumber']
    }
    else {
        $queryValues['pageNumber'] = 1
    }

    $uri = "$($BaseUri.TrimEnd('/'))$path"
    foreach ($key in @($queryValues.Keys)) {
        $uri = Add-QueryValue -Uri $uri -Name ([string]$key) -Value $queryValues[$key]
    }

    $body = $null
    if ($method -notin @('GET', 'POST')) {
        return [pscustomobject]@{
            Status = 'Unsupported'
            Reason = "HTTP method '$method' is not supported by the live catalog pass."
        }
    }

    if ($method -eq 'POST') {
        $isAsyncOrTransaction =
            (Test-MapKey -Map $Endpoint -Name 'transactionProfile') -or
            (Test-MapKey -Map $Endpoint -Name 'transaction') -or
            $path -like '*/jobs' -or
            $path -like '*/usage/query' -or
            $path -eq '/api/v2/audits/query'

        if ($isAsyncOrTransaction) {
            return [pscustomobject]@{
                Status = 'Unsupported'
                Reason = 'Async or transaction endpoint is not probed by the single-request live pass.'
            }
        }

        $body = New-LiveProbeBody -DatasetKey $DatasetKey -Endpoint $Endpoint -Hours $Hours
        if ($null -eq $body) {
            return [pscustomobject]@{
                Status = 'Needs Parameters'
                Reason = 'POST dataset has no defaultBody or built-in minimal probe body.'
            }
        }
    }

    return [pscustomobject]@{
        Status = $null
        Method = $method
        Uri = $uri
        Body = $body
        ItemsPath = [string](Get-MapValue -Map $DatasetSpec -Name 'itemsPath')
    }
}

function Convert-HttpFailureToStatus {
    param(
        [int]$StatusCode,
        [string]$Content
    )

    $message = [string]$Content

    if ($StatusCode -in @(401, 403, 404, 405)) {
        return [pscustomobject]@{ Status = 'Unsupported'; Reason = "HTTP $StatusCode indicated the endpoint was not reachable with this OAuth client or method." }
    }

    if ($StatusCode -eq 400 -or $message -match '(?i)(required|invalid|missing|parameter|body|filter|predicate|dimension)') {
        return [pscustomobject]@{ Status = 'Needs Parameters'; Reason = "HTTP $StatusCode indicated missing or invalid probe parameters." }
    }

    return [pscustomobject]@{ Status = 'Shape Mismatch'; Reason = "HTTP $StatusCode returned outside the expected success range." }
}

function ConvertTo-ShareableLiveResult {
    param([object]$Result)

    $itemSignal = if ($null -eq $Result.ItemCount) {
        'n/a'
    }
    elseif ([int]$Result.ItemCount -gt 0) {
        'present'
    }
    else {
        'empty'
    }

    return [pscustomobject]@{
        Dataset = [string]$Result.Dataset
        Endpoint = [string]$Result.Endpoint
        Method = [string]$Result.Method
        Status = [string]$Result.Status
        HttpStatus = $Result.HttpStatus
        ItemSignal = $itemSignal
        ItemsPath = [string]$Result.ItemsPath
        Reason = [string]$Result.Reason
    }
}

function Invoke-LiveDatasetProbe {
    param(
        [string]$DatasetKey,
        [object]$DatasetSpec,
        [object]$Endpoint,
        [string]$BaseUri,
        [hashtable]$Headers,
        [hashtable]$Parameters,
        [int]$Hours,
        [int]$Timeout
    )

    $endpointKey = [string](Get-MapValue -Map $DatasetSpec -Name 'endpoint')
    $request = New-LiveProbeRequest -DatasetKey $DatasetKey -DatasetSpec $DatasetSpec -Endpoint $Endpoint -BaseUri $BaseUri -Parameters $Parameters -Hours $Hours

    if (-not [string]::IsNullOrWhiteSpace([string]$request.Status)) {
        return [pscustomobject]@{
            Dataset = $DatasetKey
            Endpoint = $endpointKey
            Method = [string](Get-MapValue -Map $Endpoint -Name 'method')
            Uri = $null
            Status = [string]$request.Status
            HttpStatus = $null
            ItemCount = $null
            ItemsPath = [string](Get-MapValue -Map $DatasetSpec -Name 'itemsPath')
            Reason = [string]$request.Reason
        }
    }

    try {
        $webParams = @{
            Method = $request.Method
            Uri = $request.Uri
            Headers = $Headers
            TimeoutSec = $Timeout
            SkipHttpErrorCheck = $true
        }

        if ($null -ne $request.Body) {
            $webParams['ContentType'] = 'application/json'
            $webParams['Body'] = if ($request.Body -is [string]) { $request.Body } else { $request.Body | ConvertTo-Json -Depth 50 }
        }

        $response = Invoke-WebRequest @webParams
        $httpStatus = [int]$response.StatusCode
        $content = [string]$response.Content

        if ($httpStatus -lt 200 -or $httpStatus -gt 299) {
            $failure = Convert-HttpFailureToStatus -StatusCode $httpStatus -Content $content
            return [pscustomobject]@{
                Dataset = $DatasetKey
                Endpoint = $endpointKey
                Method = $request.Method
                Uri = $request.Uri
                Status = $failure.Status
                HttpStatus = $httpStatus
                ItemCount = $null
                ItemsPath = $request.ItemsPath
                Reason = $failure.Reason
            }
        }

        $json = if ([string]::IsNullOrWhiteSpace($content)) { $null } else { $content | ConvertFrom-Json }
        $pathValue = Get-JsonPathValue -InputObject $json -Path $request.ItemsPath
        if (-not $pathValue.Found) {
            return [pscustomobject]@{
                Dataset = $DatasetKey
                Endpoint = $endpointKey
                Method = $request.Method
                Uri = $request.Uri
                Status = 'Shape Mismatch'
                HttpStatus = $httpStatus
                ItemCount = $null
                ItemsPath = $request.ItemsPath
                Reason = "Response did not contain expected itemsPath '$($request.ItemsPath)'."
            }
        }

        $itemCount = Get-ItemCount -Value $pathValue.Value
        $status = if ($itemCount -gt 0) { 'Working' } else { 'Empty' }
        return [pscustomobject]@{
            Dataset = $DatasetKey
            Endpoint = $endpointKey
            Method = $request.Method
            Uri = $request.Uri
            Status = $status
            HttpStatus = $httpStatus
            ItemCount = $itemCount
            ItemsPath = $request.ItemsPath
            Reason = if ($status -eq 'Empty') { 'Expected shape was present but contained no items.' } else { 'Expected shape was present.' }
        }
    }
    catch {
        Write-Verbose "Probe for '$DatasetKey' failed locally: $($_.Exception.Message)"
        return [pscustomobject]@{
            Dataset = $DatasetKey
            Endpoint = $endpointKey
            Method = [string]$request.Method
            Uri = $null
            Status = 'Shape Mismatch'
            HttpStatus = $null
            ItemCount = $null
            ItemsPath = [string]$request.ItemsPath
            Reason = 'Probe raised an exception; raw exception details were not written to the report.'
        }
    }
}

function Write-LiveChecklistReport {
    param(
        [object[]]$Results,
        [string]$Directory,
        [string]$CloudRegion,
        [string]$CatalogFile
    )

    if (-not (Test-Path -Path $Directory)) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }

    $generatedAt = [DateTime]::UtcNow.ToString('o')
    $jsonPath = Join-Path -Path $Directory -ChildPath 'live-catalog-shareable-report.json'
    $csvPath = Join-Path -Path $Directory -ChildPath 'live-catalog-shareable-report.csv'
    $markdownPath = Join-Path -Path $Directory -ChildPath 'live-catalog-shareable-report.md'

    $summary = [ordered]@{}
    foreach ($status in $AllowedStatuses) {
        $summary[$status] = @($Results | Where-Object { $_.Status -eq $status }).Count
    }

    $shareableResults = @($Results | ForEach-Object { ConvertTo-ShareableLiveResult -Result $_ })
    $methodSummary = @(
        $shareableResults |
            Group-Object -Property Method |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject]@{
                    Method = $_.Name
                    Count = $_.Count
                }
            }
    )

    [ordered]@{
        generatedAtUtc = $generatedAt
        region = $CloudRegion
        catalogFileName = [System.IO.Path]::GetFileName($CatalogFile)
        datasetCount = @($Results).Count
        summary = $summary
        methods = $methodSummary
        results = $shareableResults
    } | ConvertTo-Json -Depth 100 | Set-Content -Path $jsonPath -Encoding utf8

    $shareableResults | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Live Catalog Dataset Shareable Checklist')
    $lines.Add('')
    $lines.Add("Generated: $generatedAt")
    $lines.Add("Region: $CloudRegion")
    $lines.Add("Catalog file: $([System.IO.Path]::GetFileName($CatalogFile))")
    $lines.Add("Dataset count: $(@($Results).Count)")
    $lines.Add('')
    $lines.Add('This report intentionally omits OAuth tokens, request URLs, supplied parameter values, response bodies, and raw exception text.')
    $lines.Add('')
    $lines.Add('## Summary')
    foreach ($status in $AllowedStatuses) {
        $lines.Add("- ${status}: $($summary[$status])")
    }

    $lines.Add('')
    $lines.Add('## Methods')
    foreach ($method in $methodSummary) {
        $lines.Add("- $($method.Method): $($method.Count)")
    }

    $lines.Add('')
    $lines.Add('## Checklist')
    foreach ($result in $shareableResults) {
        $mark = if ($result.Status -eq 'Working') { 'x' } else { ' ' }
        $http = if ($null -eq $result.HttpStatus) { 'n/a' } else { [string]$result.HttpStatus }
        $lines.Add("- [$mark] ``$($result.Dataset)`` - $($result.Status) - HTTP $http - item signal $($result.ItemSignal) - $($result.Reason)")
    }

    $lines | Set-Content -Path $markdownPath -Encoding utf8

    return [pscustomobject]@{
        Json = $jsonPath
        Csv = $csvPath
        Markdown = $markdownPath
        Summary = $summary
    }
}

$resolvedCatalogPath = [System.IO.Path]::GetFullPath($CatalogPath)
if (-not (Test-Path -Path $resolvedCatalogPath)) {
    throw "Catalog file was not found: $resolvedCatalogPath"
}

$parameterValues = @{}
if (-not [string]::IsNullOrWhiteSpace($ParameterJson)) {
    $parameterObject = $ParameterJson | ConvertFrom-Json
    foreach ($key in Get-MapKeys -Map $parameterObject) {
        $parameterValues[[string]$key] = Get-MapValue -Map $parameterObject -Name ([string]$key)
    }
}

$catalog = Get-Content -Raw -Path $resolvedCatalogPath | ConvertFrom-Json -AsHashtable
$datasetsNode = Get-MapValue -Map $catalog -Name 'datasets'
$endpointsNode = Get-MapValue -Map $catalog -Name 'endpoints'
if ($null -eq $datasetsNode -or $null -eq $endpointsNode) {
    throw "Catalog '$resolvedCatalogPath' must contain datasets and endpoints."
}

$token = Get-LiveCatalogAccessToken -Token $BearerToken -Id $ClientId -Secret $ClientPassword -CloudRegion $Region
$headers = @{ Authorization = "Bearer $token" }
$baseUri = "https://api.$Region"

$datasetKeys = if ($null -ne $Dataset -and $Dataset.Count -gt 0) {
    @($Dataset)
} else {
    @(Get-MapKeys -Map $datasetsNode | Sort-Object)
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($datasetKey in $datasetKeys) {
    $datasetSpec = Get-MapValue -Map $datasetsNode -Name $datasetKey
    if ($null -eq $datasetSpec) {
        $results.Add([pscustomobject]@{
            Dataset = $datasetKey
            Endpoint = $null
            Method = $null
            Uri = $null
            Status = 'Unsupported'
            HttpStatus = $null
            ItemCount = $null
            ItemsPath = $null
            Reason = 'Dataset key was not present in catalog.'
        }) | Out-Null
        continue
    }

    $endpointKey = [string](Get-MapValue -Map $datasetSpec -Name 'endpoint')
    $endpoint = Get-MapValue -Map $endpointsNode -Name $endpointKey
    if ($null -eq $endpoint) {
        $results.Add([pscustomobject]@{
            Dataset = $datasetKey
            Endpoint = $endpointKey
            Method = $null
            Uri = $null
            Status = 'Unsupported'
            HttpStatus = $null
            ItemCount = $null
            ItemsPath = [string](Get-MapValue -Map $datasetSpec -Name 'itemsPath')
            Reason = "Endpoint '$endpointKey' was not present in catalog."
        }) | Out-Null
        continue
    }

    Write-Host "Probing $datasetKey..." -ForegroundColor DarkCyan
    $result = Invoke-LiveDatasetProbe -DatasetKey $datasetKey -DatasetSpec $datasetSpec -Endpoint $endpoint -BaseUri $baseUri -Headers $headers -Parameters $parameterValues -Hours $LookbackHours -Timeout $TimeoutSeconds
    if ($AllowedStatuses -notcontains $result.Status) {
        $result.Status = 'Shape Mismatch'
        $result.Reason = "Probe returned an invalid status. $($result.Reason)"
    }

    $results.Add($result) | Out-Null
}

$report = Write-LiveChecklistReport -Results @($results.ToArray()) -Directory $OutputRoot -CloudRegion $Region -CatalogFile $resolvedCatalogPath
Write-Host "Live catalog report written to $($report.Markdown)" -ForegroundColor Cyan
foreach ($status in $AllowedStatuses) {
    Write-Host ("{0}: {1}" -f $status, $report.Summary[$status])
}

if ($PassThru) {
    @($results.ToArray() | ForEach-Object { ConvertTo-ShareableLiveResult -Result $_ })
}
