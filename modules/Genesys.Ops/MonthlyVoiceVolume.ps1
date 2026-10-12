#Requires -Version 5.1
# Shared investigation logic. Apps must call this command rather than collect APIs.
function Get-GcVolumeProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
    }
    elseif ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function Compare-GenesysMonthlyVoiceVolume {
    <#
    .SYNOPSIS
    Reconciles four independent analytics sources for one local calendar month.
    .DESCRIPTION
    Detail totals count distinct conversations containing a voice session. Aggregate
    metrics retain their original definitions; differences do not imply defects.
    Writes summary.json, report.html, comparison.csv and source evidence under a
    unique run folder. No raw conversation payloads are copied into the report.
    .PARAMETER DatasetInvoker
    Offline seam accepting Dataset, Body, OutputRoot. Returns Records, Events,
    Status (complete/partial), and optional EvidencePath. Cannot validate a tenant.
    .PARAMETER RequestInvoker
    Core HTTP seam for transport integration tests. Cannot validate a tenant.
    .EXAMPLE
    Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -TimeZoneId 'America/New_York'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(2000, 9998)][int]$Year,
        [Parameter(Mandatory)][ValidateRange(1, 12)][int]$Month,
        [string]$TimeZoneId = 'UTC',
        [string[]]$DivisionId = @(),
        [string[]]$QueueId = @(),
        [string]$OrganizationId,
        [string]$OutputRoot = 'out',
        [scriptblock]$DatasetInvoker,
        [scriptblock]$RequestInvoker
    )
    if (-not $DatasetInvoker -and -not $RequestInvoker) { Assert-GenesysConnected }
    $zone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
    $localStart = [datetime]::SpecifyKind([datetime]::new($Year, $Month, 1), [DateTimeKind]::Unspecified)
    $localEnd = $localStart.AddMonths(1)
    foreach ($boundary in @($localStart, $localEnd)) {
        if ($zone.IsInvalidTime($boundary) -or $zone.IsAmbiguousTime($boundary)) {
            throw 'Month boundary is invalid or ambiguous in this timezone; select an unambiguous reporting timezone.'
        }
    }
    $start = [TimeZoneInfo]::ConvertTimeToUtc($localStart, $zone)
    $end = [TimeZoneInfo]::ConvertTimeToUtc($localEnd, $zone)
    $interval = "$($start.ToString('o'))/$($end.ToString('o'))"
    $runId = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $folder = [IO.Path]::GetFullPath((Join-Path $OutputRoot "monthly-voice-volume/$runId"))
    $null = New-Item -ItemType Directory -Path $folder -Force
    $scope = [ordered]@{
        year = $Year; month = $Month; timeZoneId = $TimeZoneId; interval = $interval
        divisionIds = @($DivisionId); queueIds = @($QueueId); mediaType = 'voice'
        organizationId = $OrganizationId; organizationVerified = $false; baseUri = $script:GC.BaseUri
    }
    $segmentFilters = @(@{ type = 'and'; predicates = @(@{ type = 'dimension'; dimension = 'mediaType'; operator = 'matches'; value = 'voice' }) })
    $aggregateClauses = @(@{ type = 'and'; predicates = @(@{ type = 'dimension'; dimension = 'mediaType'; operator = 'matches'; value = 'voice' }) })
    $conversationFilters = @()
    foreach ($dimension in @('queueId', 'divisionId')) {
        $values = @(if ($dimension -eq 'queueId') { $QueueId } else { $DivisionId })
        if ($values.Count -eq 0) { continue }
        $clause = @{ type = 'or'; predicates = @($values | ForEach-Object { @{ type = 'dimension'; dimension = $dimension; operator = 'matches'; value = $_ } }) }
        $aggregateClauses += $clause
        if ($dimension -eq 'queueId') { $segmentFilters += $clause } else { $conversationFilters += $clause }
    }
    $detailBody = @{ interval = $interval; order = 'asc'; orderBy = 'conversationStart'; segmentFilters = $segmentFilters; conversationFilters = $conversationFilters }
    $queryBody = @{}; foreach ($key in $detailBody.Keys) { $queryBody[$key] = $detailBody[$key] }
    $queryBody.paging = @{ pageNumber = 1; pageSize = 100 }
    $metrics = @('nOffered', 'nConnected', 'nOutbound')
    $aggregateBody = @{ interval = $interval; groupBy = @('mediaType'); metrics = $metrics; filter = @{ type = 'and'; clauses = $aggregateClauses } }
    $definitions = @(
        @{ name = 'details-query'; dataset = 'analytics-conversation-details-query'; kind = 'details'; body = $queryBody },
        @{ name = 'details-jobs'; dataset = 'analytics-conversation-details'; kind = 'details'; body = $detailBody },
        @{ name = 'aggregates-query'; dataset = 'analytics.query.conversation.aggregates.queue.performance'; kind = 'aggregates'; body = $aggregateBody },
        @{ name = 'aggregates-jobs'; dataset = 'analytics-conversation-aggregates-jobs'; kind = 'aggregates'; body = $aggregateBody }
    )
    $sources = [System.Collections.Generic.List[object]]::new()
    $measures = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($definition in $definitions) {
        $sourceRoot = Join-Path $folder $definition.name
        $null = New-Item -ItemType Directory -Path $sourceRoot
        $definition.body | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $sourceRoot 'request.json') -Encoding utf8
        $started = [datetime]::UtcNow.ToString('o')
        $source = [ordered]@{
            source = $definition.name; dataset = $definition.dataset; kind = $definition.kind
            status = 'unavailable'; startedAtUtc = $started; endedAtUtc = $null
            requestPath = "$($definition.name)/request.json"; evidencePath = $null
            rowCount = $null; voiceRowCount = $null; distinctConversations = $null
            duplicateVoiceRows = $null; missingConversationIds = $null; pageCount = $null; requestCount = $null; jobIds = @()
            warnings = @(); conversationIds = @(); metricStatistics = @()
        }
        try {
            $records = @(); $events = @()
            if ($DatasetInvoker) {
                $result = & $DatasetInvoker -Dataset $definition.dataset -Body $definition.body -OutputRoot $sourceRoot
                $records = @(Get-GcVolumeProperty $result 'Records' @())
                $events = @(Get-GcVolumeProperty $result 'Events' @())
                $source.status = [string](Get-GcVolumeProperty $result 'Status' 'partial')
                if ($source.status -notin @('complete', 'partial')) { throw 'Invalid fixture coverage status.' }
                $source.evidencePath = Get-GcVolumeProperty $result 'EvidencePath'
            }
            else {
                $arguments = @{ Dataset = $definition.dataset; DatasetParameters = @{ Body = $definition.body }; OutputRoot = $sourceRoot; BaseUri = $script:GC.BaseUri; Headers = $script:GC.Headers }
                if ($script:GC.CatalogPath) { $arguments.CatalogPath = $script:GC.CatalogPath }
                if ($RequestInvoker) { $arguments.RequestInvoker = $RequestInvoker }
                $context = Invoke-Dataset @arguments
                $source.evidencePath = $context.runFolder
                $collected = [System.Collections.Generic.List[object]]::new()
                foreach ($file in @(Get-ChildItem $context.dataFolder -Filter '*.jsonl')) {
                    foreach ($line in [IO.File]::ReadLines($file.FullName)) {
                        if ($line.Trim()) { $collected.Add(($line | ConvertFrom-Json)) }
                    }
                }
                $records = $collected.ToArray()
                $source.evidencePath = $context.runFolder.Substring($folder.Length + 1).Replace('\', '/')
                $events = @(Get-Content $context.eventsPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
                $source.status = 'complete'
            }
            $events = @($events | ForEach-Object {
                $payload = Get-GcVolumeProperty $_ 'payload'
                if ($null -ne $payload -and $null -ne (Get-GcVolumeProperty $payload 'eventType')) { $payload } else { $_ }
            })
            $paging = @($events | Where-Object { (Get-GcVolumeProperty $_ 'eventType') -eq 'paging.progress' })
            $source.requestCount = @($events | Where-Object { (Get-GcVolumeProperty $_ 'eventType') -eq 'request.completed' }).Count
            $resultPages = @($paging)
            if ($definition.name -like '*-jobs') { $resultPages = @($paging | Where-Object { (Get-GcVolumeProperty $_ 'profile') -eq 'cursor' }) }
            $source.pageCount = if ($events.Count -gt 0) { $resultPages.Count } else { $null }
            $source.jobIds = @($events | ForEach-Object { Get-GcVolumeProperty $_ 'jobId' } | Where-Object { $_ } | Sort-Object -Unique)
            $termination = @($events | Where-Object { (Get-GcVolumeProperty $_ 'eventType' '') -like 'paging.terminated.*' })
            if ($termination.Count -gt 0) { $source.status = 'partial'; $source.warnings += 'Paging ended at a safety limit or repeated cursor.' }
            foreach ($page in $paging) {
                if ((Get-GcVolumeProperty $page 'itemCount' 0) -eq 0 -and (Get-GcVolumeProperty $page 'totalHits' 0) -gt $records.Count) {
                    $source.status = 'partial'; $source.warnings += 'Retrieval ended before reported totalHits.'
                }
            }
            $source.rowCount = $records.Count
            if ($definition.kind -eq 'details') {
                $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                $voiceRows = 0; $missingIds = 0
                foreach ($record in $records) {
                    $isVoice = $false
                    foreach ($participant in @(Get-GcVolumeProperty $record 'participants' @())) {
                        foreach ($session in @(Get-GcVolumeProperty $participant 'sessions' @())) {
                            if ((Get-GcVolumeProperty $session 'mediaType') -eq 'voice') { $isVoice = $true }
                        }
                    }
                    if (-not $isVoice) { continue }
                    $voiceRows++
                    $id = [string](Get-GcVolumeProperty $record 'conversationId' '')
                    if ([string]::IsNullOrWhiteSpace($id)) { $missingIds++ } else { $null = $ids.Add($id) }
                }
                $source.voiceRowCount = $voiceRows; $source.missingConversationIds = $missingIds
                $source.distinctConversations = $ids.Count
                $source.duplicateVoiceRows = $voiceRows - $missingIds - $ids.Count
                $source.conversationIds = @($ids | Sort-Object)
                if ($missingIds -gt 0) { $source.status = 'partial'; $source.warnings += 'Voice records without conversation IDs cannot be deduplicated.' }
                $measures.Add([pscustomobject]@{ source = $source.source; definition = 'distinctVoiceConversations'; value = $ids.Count; coverage = $source.status; unit = 'conversations' })
                $source.conversationIds | Set-Content (Join-Path $sourceRoot 'conversation-ids.txt') -Encoding utf8
            }
            else {
                $statistics = [System.Collections.Generic.List[object]]::new()
                foreach ($record in $records) {
                    $group = Get-GcVolumeProperty $record 'group'
                    foreach ($data in @(Get-GcVolumeProperty $record 'data' @())) {
                        foreach ($metric in @(Get-GcVolumeProperty $data 'metrics' @())) {
                            $statistics.Add([pscustomobject]@{ group = $group; interval = Get-GcVolumeProperty $data 'interval'; metric = Get-GcVolumeProperty $metric 'metric'; stats = Get-GcVolumeProperty $metric 'stats' })
                        }
                    }
                }
                $source.metricStatistics = @($statistics.ToArray())
                foreach ($metricName in $metrics) {
                    $matching = @($statistics | Where-Object { $_.metric -eq $metricName })
                    $value = $null
                    if ($matching.Count -eq 1) { $value = Get-GcVolumeProperty $matching[0].stats 'count' }
                    $coverage = $source.status
                    if ($null -eq $value) {
                        $coverage = 'unavailable'
                        $source.warnings += "No unambiguous $($metricName).count total returned; original statistics retained."
                    }
                    $measures.Add([pscustomobject]@{ source = $source.source; definition = "$($metricName).count"; value = $value; coverage = $coverage; unit = 'metric count' })
                }
            }
        }
        catch {
            # Error messages may contain request data; retain diagnostics only in Core artifacts.
            $source.status = 'unavailable'; $source.warnings += 'Collection failed. Inspect this source Core run artifacts for diagnostics.'
            $source.rowCount = $null; $source.distinctConversations = $null
            $names = if ($definition.kind -eq 'details') { @('distinctVoiceConversations') } else { @($metrics | ForEach-Object { "$($_).count" }) }
            foreach ($name in $names) { $measures.Add([pscustomobject]@{ source = $source.source; definition = $name; value = $null; coverage = 'unavailable'; unit = '' }) }
        }
        $source.endedAtUtc = [datetime]::UtcNow.ToString('o')
        foreach ($warning in $source.warnings) { $warnings.Add("$($source.source): $warning") }
        $sources.Add([pscustomobject]$source)
    }
    $comparisons = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $measures.Count; $i++) {
        for ($j = $i + 1; $j -lt $measures.Count; $j++) {
            $left = $measures[$i]; $right = $measures[$j]
            if ($left.source -eq $right.source) { continue }
            $equivalent = $left.definition -eq $right.definition
            if (-not $equivalent -and $left.definition -ne 'distinctVoiceConversations' -and $right.definition -ne 'distinctVoiceConversations') { continue }
            $difference = $null; $percent = $null; $status = 'unavailable'
            if ($null -ne $left.value -and $null -ne $right.value) {
                $difference = [double]$right.value - [double]$left.value
                if ([double]$left.value -ne 0) { $percent = 100 * $difference / [math]::Abs([double]$left.value) }
                $status = if ($difference -eq 0) { 'equal' } else { 'different' }
                if ($left.coverage -ne 'complete' -or $right.coverage -ne 'complete') { $status = 'partial' }
            }
            $comparisons.Add([pscustomobject]@{
                baselineSource = $left.source; baselineDefinition = $left.definition; baselineValue = $left.value
                comparedSource = $right.source; comparedDefinition = $right.definition; comparedValue = $right.value
                equivalentDefinition = $equivalent; difference = $difference; percentOfBaseline = $percent; status = $status
            })
        }
    }
    $detailSources = @($sources | Where-Object { $_.kind -eq 'details' })
    $leftIds = @($detailSources[0].conversationIds); $rightIds = @($detailSources[1].conversationIds)
    $rightSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $leftSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in $leftIds) { $null = $leftSet.Add($id) }; foreach ($id in $rightIds) { $null = $rightSet.Add($id) }
    $idComparison = [ordered]@{
        coverage = if ($detailSources[0].status -eq 'complete' -and $detailSources[1].status -eq 'complete') { 'complete' } else { 'partial' }
        onlyDetailsQuery = @($leftIds | Where-Object { -not $rightSet.Contains($_) })
        onlyDetailsJobs = @($rightIds | Where-Object { -not $leftSet.Contains($_) })
    }
    $warnings.Add('Distinct conversation counts and aggregate metric counts have different definitions. Agreement does not prove equivalence; differences do not establish defects.')
    $warnings.Add('Filters are expressed in source-specific request bodies. Equivalent scope and time attribution require live tenant verification.')
    $report = [pscustomobject]@{
        schemaVersion = 1; investigationKey = 'monthly-voice-volume'; runId = $runId
        generatedAtUtc = [datetime]::UtcNow.ToString('o'); scope = $scope
        evidenceMode = if ($DatasetInvoker -or $RequestInvoker) { 'synthetic' } else { 'platform-unverified' }
        sources = @($sources.ToArray()); measures = @($measures.ToArray()); comparisons = @($comparisons.ToArray())
        detailIdComparison = $idComparison; warnings = @($warnings.ToArray())
        runFolder = $folder
    }
    $report | ConvertTo-Json -Depth 60 | Set-Content (Join-Path $folder 'summary.json') -Encoding utf8
    $comparisons.ToArray() | Export-Csv (Join-Path $folder 'comparison.csv') -NoTypeInformation -Encoding utf8
    $manifest = @{ investigationKey = $report.investigationKey; runId = $runId; scope = $scope; evidenceMode = $report.evidenceMode; sourceStatuses = @($sources | Select-Object source, status); warnings = $report.warnings }
    $manifest | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $folder 'manifest.json') -Encoding utf8
    foreach ($source in $sources) {
        @{ eventType = 'source.completed'; source = $source.source; status = $source.status; timestampUtc = $source.endedAtUtc } | ConvertTo-Json -Compress | Add-Content (Join-Path $folder 'events.jsonl') -Encoding utf8
    }
    $measureTable = $report.measures | ConvertTo-Html -Fragment
    $comparisonDisplay = $report.comparisons | Select-Object @{n='Baseline';e={ "$($_.baselineSource) / $($_.baselineDefinition): $($_.baselineValue)" }},
        @{n='Compared';e={ "$($_.comparedSource) / $($_.comparedDefinition): $($_.comparedValue)" }},
        @{n='Difference';e={$_.difference}}, @{n='Change (%)';e={if ($null -ne $_.percentOfBaseline) { [math]::Round($_.percentOfBaseline, 2) }}},
        @{n='Definitions';e={if ($_.equivalentDefinition) { 'Same measure' } else { 'Different measures' }}}, @{n='Status';e={$_.status}}
    $comparisonTable = ($comparisonDisplay | ConvertTo-Html -Fragment) -replace '<td>different</td>', '<td class="difference">different</td>' -replace '<td>partial</td>', '<td class="difference">partial</td>'
    $idRows = @($idComparison.onlyDetailsQuery | ForEach-Object { [pscustomobject]@{ sourceOnly = 'details-query'; conversationId = $_ } }) + @($idComparison.onlyDetailsJobs | ForEach-Object { [pscustomobject]@{ sourceOnly = 'details-jobs'; conversationId = $_ } })
    $idTable = $idRows | ConvertTo-Html -Fragment
    $sourceTable = $report.sources | Select-Object source, status, rowCount, duplicateVoiceRows, pageCount, startedAtUtc, endedAtUtc | ConvertTo-Html -Fragment
    $warningHtml = ($report.warnings | ForEach-Object { '<li>' + [Net.WebUtility]::HtmlEncode($_) + '</li>' }) -join ''
    $title = [Net.WebUtility]::HtmlEncode("Monthly voice volume: $Year-$('{0:00}' -f $Month) ($TimeZoneId)")
    $scopeHtml = [Net.WebUtility]::HtmlEncode(($scope | ConvertTo-Json -Depth 10))
    @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>$title</title>
<style>body{font:16px system-ui;margin:2rem auto;padding:0 1rem;max-width:1200px;color:#172b3a}h1{font-size:1.8rem}table{border-collapse:collapse;width:100%;font-size:.9rem}th,td{padding:.6rem;text-align:left;border-bottom:1px solid #ccd7df;overflow-wrap:anywhere}th{background:#eef3f6}.difference{background:#fff0c2;font-weight:700}.scroll{overflow:auto}pre{white-space:pre-wrap}li{margin:.6rem 0}a{color:#075b8c}</style></head>
<body><h1>$title</h1><p>Evidence: $($report.evidenceMode). Differences are observations, not automatic failures.</p><h2>Scope</h2><pre>$scopeHtml</pre><h2>Source coverage</h2><div class="scroll" tabindex="0" role="region" aria-label="Source coverage">$sourceTable</div>
<h2>Independent totals</h2><div class="scroll" tabindex="0" role="region" aria-label="Independent totals">$measureTable</div>
<h2>Differences</h2><p>Difference = compared value minus baseline value. Percentage uses the absolute baseline; a zero baseline has no percentage. Different measures means the values use different counting definitions.</p><div class="scroll" tabindex="0" role="region" aria-label="Source differences">$comparisonTable</div>
<h2>Conversation ID differences</h2><p>Coverage: $($idComparison.coverage). These are observed set differences; incomplete retrieval can affect membership. Use Get-GenesysConversationInvestigation -ConversationId with an ID below to investigate.</p><div class="scroll" tabindex="0" role="region" aria-label="Conversation ID differences">$idTable</div><h2>Interpretation and warnings</h2><ul>$warningHtml</ul><p><a href="summary.json">Full comparison and conversation ID differences (JSON)</a> · <a href="comparison.csv">Comparison CSV</a></p></body></html>
"@ | Set-Content (Join-Path $folder 'report.html') -Encoding utf8
    return $report
}
