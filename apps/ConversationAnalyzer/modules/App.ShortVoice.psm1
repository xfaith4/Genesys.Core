#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-ShortVoicePercentile {
    [CmdletBinding()]
    param(
        [double[]]$Values,
        [double]$Percentile
    )

    $items = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if (@($items).Count -eq 0) { return 0.0 }

    if ($Percentile -le 0) { return [double]$items[0] }
    if ($Percentile -ge 100) { return [double]$items[@($items).Count - 1] }

    $rank = ($Percentile / 100.0) * (@($items).Count - 1)
    $low = [int][Math]::Floor($rank)
    $high = [int][Math]::Ceiling($rank)
    if ($low -eq $high) { return [double]$items[$low] }

    $weight = $rank - $low
    return ([double]$items[$low] * (1.0 - $weight)) + ([double]$items[$high] * $weight)
}

function ConvertTo-ShortVoiceDirection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Conversation)

    if ($Conversation.PSObject.Properties['originatingDirection'] -and -not [string]::IsNullOrWhiteSpace([string]$Conversation.originatingDirection)) {
        return ([string]$Conversation.originatingDirection).ToLowerInvariant()
    }

    foreach ($participant in @($Conversation.participants)) {
        foreach ($session in @($participant.sessions)) {
            if ($session.PSObject.Properties['direction'] -and -not [string]::IsNullOrWhiteSpace([string]$session.direction)) {
                return ([string]$session.direction).ToLowerInvariant()
            }
        }
    }

    return ''
}

function Get-ShortVoiceConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Key,
        $DefaultValue = $null
    )

    if ($null -eq $Config) { return $DefaultValue }

    if ($Config -is [System.Collections.IDictionary]) {
        if ($Config.Contains($Key)) { return $Config[$Key] }
        return $DefaultValue
    }

    if ($Config.PSObject.Properties[$Key]) {
        return $Config.PSObject.Properties[$Key].Value
    }

    return $DefaultValue
}

function Test-ShortVoiceMediaType {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Conversation)

    foreach ($participant in @($Conversation.participants)) {
        foreach ($session in @($participant.sessions)) {
            if ($session.PSObject.Properties['mediaType'] -and ([string]$session.mediaType).ToLowerInvariant() -eq 'voice') {
                return $true
            }
        }
    }

    if ($Conversation.PSObject.Properties['mediaType']) {
        return ([string]$Conversation.mediaType).ToLowerInvariant() -eq 'voice'
    }

    return $false
}

function Get-ShortVoiceDuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Conversation,
        [switch]$IncludeIncompleteConversations
    )

    $method = 'conversationStart-conversationEnd'
    $startRaw = if ($Conversation.PSObject.Properties['conversationStart']) { [string]$Conversation.conversationStart } else { '' }
    $endRaw = if ($Conversation.PSObject.Properties['conversationEnd']) { [string]$Conversation.conversationEnd } else { '' }

    if ([string]::IsNullOrWhiteSpace($startRaw) -or [string]::IsNullOrWhiteSpace($endRaw)) {
        if ($IncludeIncompleteConversations) {
            return [pscustomobject]@{
                IsValid = $false
                IsIncomplete = $true
                DurationSeconds = $null
                Method = $method
                Error = 'missing-start-or-end'
            }
        }

        return [pscustomobject]@{
            IsValid = $false
            IsIncomplete = $true
            DurationSeconds = $null
            Method = $method
            Error = 'missing-start-or-end'
        }
    }

    try {
        $start = [DateTimeOffset]::Parse($startRaw)
        $end = [DateTimeOffset]::Parse($endRaw)
        $duration = ($end - $start).TotalSeconds
        if ($duration -lt 0) {
            return [pscustomobject]@{
                IsValid = $false
                IsIncomplete = $false
                DurationSeconds = $null
                Method = $method
                Error = 'negative-duration'
            }
        }

        return [pscustomobject]@{
            IsValid = $true
            IsIncomplete = $false
            DurationSeconds = [math]::Round($duration, 3)
            Method = $method
            Error = ''
        }
    }
    catch {
        return [pscustomobject]@{
            IsValid = $false
            IsIncomplete = $false
            DurationSeconds = $null
            Method = $method
            Error = 'invalid-datetime'
        }
    }
}

function Get-ShortVoiceConversationFields {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Conversation)

    $queueId = ''
    $queueName = ''
    $divisionId = ''
    $divisionName = ''
    $disconnectType = ''
    $wrapUpCode = ''
    $wrapUpName = ''
    $ani = ''
    $dnis = ''
    $userId = ''
    $userName = ''
    $campaignId = ''
    $campaignName = ''
    $externalContactId = ''
    $participantSummary = New-Object System.Collections.Generic.List[string]

    foreach ($participant in @($Conversation.participants)) {
        $purpose = if ($participant.PSObject.Properties['purpose']) { [string]$participant.purpose } else { '' }
        $pid = if ($participant.PSObject.Properties['participantId']) { [string]$participant.participantId } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($purpose) -or -not [string]::IsNullOrWhiteSpace($pid)) {
            $participantSummary.Add(("{0}:{1}" -f $purpose, $pid)) | Out-Null
        }

        if ([string]::IsNullOrWhiteSpace($userId) -and $participant.PSObject.Properties['userId']) {
            $userId = [string]$participant.userId
        }
        if ([string]::IsNullOrWhiteSpace($userName) -and $participant.PSObject.Properties['userName']) {
            $userName = [string]$participant.userName
        }
        if ([string]::IsNullOrWhiteSpace($externalContactId) -and $participant.PSObject.Properties['externalContactId']) {
            $externalContactId = [string]$participant.externalContactId
        }
        if ([string]::IsNullOrWhiteSpace($campaignId) -and $participant.PSObject.Properties['campaignId']) {
            $campaignId = [string]$participant.campaignId
        }
        if ([string]::IsNullOrWhiteSpace($campaignName) -and $participant.PSObject.Properties['campaignName']) {
            $campaignName = [string]$participant.campaignName
        }

        foreach ($session in @($participant.sessions)) {
            if ([string]::IsNullOrWhiteSpace($ani) -and $session.PSObject.Properties['ani']) {
                $ani = [string]$session.ani
            }
            if ([string]::IsNullOrWhiteSpace($dnis) -and $session.PSObject.Properties['dnis']) {
                $dnis = [string]$session.dnis
            }

            foreach ($segment in @($session.segments)) {
                if ([string]::IsNullOrWhiteSpace($queueId) -and $segment.PSObject.Properties['queueId']) {
                    $queueId = [string]$segment.queueId
                }
                if ([string]::IsNullOrWhiteSpace($queueName) -and $segment.PSObject.Properties['queueName']) {
                    $queueName = [string]$segment.queueName
                }
                if ([string]::IsNullOrWhiteSpace($divisionId) -and $segment.PSObject.Properties['divisionId']) {
                    $divisionId = [string]$segment.divisionId
                }
                if ([string]::IsNullOrWhiteSpace($divisionName) -and $segment.PSObject.Properties['divisionName']) {
                    $divisionName = [string]$segment.divisionName
                }
                if ([string]::IsNullOrWhiteSpace($disconnectType) -and $segment.PSObject.Properties['disconnectType']) {
                    $disconnectType = [string]$segment.disconnectType
                }
                if ([string]::IsNullOrWhiteSpace($wrapUpCode) -and $segment.PSObject.Properties['wrapUpCode']) {
                    $wrapUpCode = [string]$segment.wrapUpCode
                }
                if ([string]::IsNullOrWhiteSpace($wrapUpName) -and $segment.PSObject.Properties['wrapUpName']) {
                    $wrapUpName = [string]$segment.wrapUpName
                }
            }
        }
    }

    return [pscustomobject]@{
        QueueId = $queueId
        QueueName = $queueName
        DivisionId = $divisionId
        DivisionName = $divisionName
        DisconnectType = $disconnectType
        WrapUpCode = $wrapUpCode
        WrapUpName = $wrapUpName
        Ani = $ani
        Dnis = $dnis
        UserId = $userId
        UserName = $userName
        CampaignId = $campaignId
        CampaignName = $campaignName
        ExternalContactId = $externalContactId
        ParticipantSummary = [string]::Join('; ', @($participantSummary.ToArray()))
    }
}

function Test-ShortVoiceRecordAgainstFilters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Record,
        [hashtable]$Filters
    )

    if ($null -eq $Filters) { return $true }

    if ($Filters.ContainsKey('Directions') -and @($Filters['Directions']).Count -gt 0) {
        $allowed = @($Filters['Directions'] | ForEach-Object { ([string]$_).ToLowerInvariant() })
        if ($allowed -notcontains ([string]$Record.Direction).ToLowerInvariant()) { return $false }
    }

    foreach ($pair in @(
        @{ K = 'Queue'; V = [string]$Record.QueueName },
        @{ K = 'Division'; V = [string]$Record.DivisionId },
        @{ K = 'User'; V = [string]$Record.UserId },
        @{ K = 'Campaign'; V = [string]$Record.CampaignId },
        @{ K = 'DisconnectType'; V = [string]$Record.DisconnectType },
        @{ K = 'WrapUpCode'; V = [string]$Record.WrapUpCode },
        @{ K = 'Ani'; V = [string]$Record.Ani },
        @{ K = 'Dnis'; V = [string]$Record.Dnis },
        @{ K = 'ExternalContact'; V = [string]$Record.ExternalContactId }
    )) {
        if ($Filters.ContainsKey($pair.K)) {
            $needle = [string]$Filters[$pair.K]
            if (-not [string]::IsNullOrWhiteSpace($needle)) {
                if ([string]::IsNullOrWhiteSpace($pair.V) -or $pair.V.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    return $false
                }
            }
        }
    }

    return $true
}

function Add-ShortVoiceRollupCount {
    param(
        [hashtable]$Map,
        [string]$Key,
        [double]$Duration
    )

    $id = if ([string]::IsNullOrWhiteSpace($Key)) { '(unknown)' } else { $Key }
    if (-not $Map.ContainsKey($id)) {
        $Map[$id] = [pscustomobject]@{
            Key = $id
            Count = 0
            Durations = New-Object System.Collections.Generic.List[double]
        }
    }

    $item = $Map[$id]
    $item.Count = [int]$item.Count + 1
    $item.Durations.Add([double]$Duration) | Out-Null
}

function ConvertTo-ShortVoiceRollupRows {
    [CmdletBinding()]
    param(
        [hashtable]$Map,
        [int]$Total
    )

    $rows = foreach ($key in @($Map.Keys)) {
        $item = $Map[$key]
        $vals = @($item.Durations)
        [pscustomobject]@{
            Key = $item.Key
            Count = [int]$item.Count
            Rate = if ($Total -gt 0) { [math]::Round(($item.Count / $Total) * 100.0, 3) } else { 0.0 }
            AverageDurationSeconds = if (@($vals).Count -gt 0) { [math]::Round((@($vals) | Measure-Object -Average).Average, 3) } else { 0.0 }
            MedianDurationSeconds = [math]::Round((Get-ShortVoicePercentile -Values $vals -Percentile 50), 3)
            P95DurationSeconds = [math]::Round((Get-ShortVoicePercentile -Values $vals -Percentile 95), 3)
        }
    }

    return @($rows | Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Key'; Descending = $false })
}

function Write-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object
    )

    ($Object | ConvertTo-Json -Depth 100) | Set-Content -Path $Path -Encoding utf8
}

function New-ShortVoiceMarkdownReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Summary,
        [Parameter(Mandatory = $true)]$Rollup,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$GeneratedAtUtc,
        [Parameter(Mandatory = $true)]$Parameters,
        [int]$TopN = 100
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Short Voice Conversation Report')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## 1. Report parameters')
    [void]$sb.AppendLine("- interval: $($Parameters.Interval)")
    [void]$sb.AppendLine("- threshold seconds: $($Parameters.ThresholdSeconds)")
    [void]$sb.AppendLine("- direction filter: $($Parameters.Directions -join ', ')")
    [void]$sb.AppendLine("- queue/division/user/campaign filters: queue='$($Parameters.Queue)' division='$($Parameters.Division)' user='$($Parameters.User)' campaign='$($Parameters.Campaign)'")
    [void]$sb.AppendLine("- generated timestamp: $GeneratedAtUtc")
    [void]$sb.AppendLine("- run ID: $RunId")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## 2. Executive summary')
    [void]$sb.AppendLine("- total scanned: $($Summary.TotalVoiceConversationsScanned)")
    [void]$sb.AppendLine("- total short: $($Summary.TotalShortVoiceConversations)")
    [void]$sb.AppendLine("- short rate: $($Summary.ShortConversationRatePercent)%")
    [void]$sb.AppendLine("- inbound/outbound breakdown: inbound=$($Summary.InboundShortCount), outbound=$($Summary.OutboundShortCount)")
    [void]$sb.AppendLine("- strongest signals/anomalies: top queue=$($Summary.TopAffectedQueues -join ', '); top disconnect=$($Summary.TopDisconnectTypes -join ', ')")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## 3. Metric rollups')

    foreach ($section in @(
        @{ Name = 'by direction'; Rows = $Rollup.ByDirection },
        @{ Name = 'by queue'; Rows = $Rollup.ByQueue },
        @{ Name = 'by division'; Rows = $Rollup.ByDivision },
        @{ Name = 'by disconnect type'; Rows = $Rollup.ByDisconnectType },
        @{ Name = 'by hour'; Rows = $Rollup.ByHour },
        @{ Name = 'by agent/user'; Rows = $Rollup.ByAgent },
        @{ Name = 'by campaign'; Rows = $Rollup.ByCampaign }
    )) {
        [void]$sb.AppendLine("### $($section.Name)")
        [void]$sb.AppendLine('| Key | Count | Rate% | Avg(s) | Median(s) | P95(s) |')
        [void]$sb.AppendLine('|---|---:|---:|---:|---:|---:|')
        foreach ($row in @($section.Rows)) {
            [void]$sb.AppendLine(("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $row.Key, $row.Count, $row.Rate, $row.AverageDurationSeconds, $row.MedianDurationSeconds, $row.P95DurationSeconds))
        }
        [void]$sb.AppendLine()
    }

    [void]$sb.AppendLine('## 4. Investigation table')
    [void]$sb.AppendLine("Top $TopN examples are available in short-voice-conversations-detail.jsonl and export files.")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## 5. Data quality notes')
    [void]$sb.AppendLine("- missing end times: $($Summary.MissingEndTimeCount)")
    [void]$sb.AppendLine("- missing queue/division/user fields: queue=$($Summary.MissingQueueCount), division=$($Summary.MissingDivisionCount), user=$($Summary.MissingUserCount)")
    [void]$sb.AppendLine("- incomplete conversations excluded: $($Summary.ExcludedIncompleteConversationCount)")
    [void]$sb.AppendLine("- duration calculation method: $($Summary.DurationCalculationMethod)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## 6. Next-step recommendations')
    [void]$sb.AppendLine('- Inspect queue routing and overflow behavior on top-affected queues.')
    [void]$sb.AppendLine('- Check outbound campaign dialing config and contact list quality for short outbound calls.')
    [void]$sb.AppendLine('- Review disconnect patterns for carrier/SIP failures, transfer loops, and IVR/bot exits.')

    return $sb.ToString()
}

function Get-ShortVoiceDeterministicId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$DocumentType,
        [Parameter(Mandatory = $true)][string]$DimensionKey
    )

    $text = "{0}|{1}|{2}" -f $RunId, $DocumentType, $DimensionKey
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hash) { [void]$sb.Append($b.ToString('x2')) }
        return $sb.ToString()
    }
    finally {
        $sha.Dispose()
    }
}

function New-ShortVoiceElasticDocuments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Summary,
        [Parameter(Mandatory = $true)]$Rollup,
        [Parameter(Mandatory = $true)]$Context
    )

    $docs = New-Object System.Collections.Generic.List[object]

    $base = [ordered]@{
        '@timestamp' = $Context.Timestamp
        orgName = $Context.OrgName
        orgId = $Context.OrgId
        region = $Context.Region
        runId = $Context.RunId
        intervalStart = $Context.IntervalStart
        intervalEnd = $Context.IntervalEnd
        thresholdSeconds = $Summary.ShortConversationThresholdSeconds
        durationMethod = $Summary.DurationCalculationMethod
        totalScanned = $Summary.TotalVoiceConversationsScanned
        totalShort = $Summary.TotalShortVoiceConversations
        shortRate = $Summary.ShortConversationRatePercent
        averageDurationSeconds = $Summary.AverageShortDurationSeconds
        medianDurationSeconds = $Summary.MedianShortDurationSeconds
        p95DurationSeconds = $Summary.P95ShortDurationSeconds
        missingFieldCounts = $Summary.MissingFieldCounts
        sourceArtifactPath = $Context.SourceArtifactPath
        appVersion = $Context.AppVersion
        moduleVersion = $Context.ModuleVersion
    }

    $summaryDoc = [ordered]@{} + $base
    $summaryDoc.documentType = 'run_summary'
    $summaryDoc.metricCount = $Summary.TotalShortVoiceConversations
    $summaryDoc.metricRate = $Summary.ShortConversationRatePercent
    $summaryDoc._id = Get-ShortVoiceDeterministicId -RunId $Context.RunId -DocumentType 'run_summary' -DimensionKey 'all'
    $docs.Add($summaryDoc) | Out-Null

    foreach ($pair in @(
        @{ Type='direction_rollup'; Items=$Rollup.ByDirection; Field='direction' },
        @{ Type='queue_rollup'; Items=$Rollup.ByQueue; Field='queueName' },
        @{ Type='division_rollup'; Items=$Rollup.ByDivision; Field='divisionName' },
        @{ Type='disconnect_type_rollup'; Items=$Rollup.ByDisconnectType; Field='disconnectType' },
        @{ Type='hourly_rollup'; Items=$Rollup.ByHour; Field='hour' },
        @{ Type='agent_rollup'; Items=$Rollup.ByAgent; Field='userName' },
        @{ Type='campaign_rollup'; Items=$Rollup.ByCampaign; Field='campaignName' }
    )) {
        foreach ($item in @($pair.Items)) {
            $doc = [ordered]@{} + $base
            $doc.documentType = $pair.Type
            $doc.metricCount = $item.Count
            $doc.metricRate = $item.Rate
            $doc.averageDurationSeconds = $item.AverageDurationSeconds
            $doc.medianDurationSeconds = $item.MedianDurationSeconds
            $doc.p95DurationSeconds = $item.P95DurationSeconds
            $doc[$pair.Field] = $item.Key
            $doc._id = Get-ShortVoiceDeterministicId -RunId $Context.RunId -DocumentType $pair.Type -DimensionKey ([string]$item.Key)
            $docs.Add($doc) | Out-Null
        }
    }

    $dqDoc = [ordered]@{} + $base
    $dqDoc.documentType = 'data_quality_summary'
    $dqDoc.metricCount = $Summary.ExcludedIncompleteConversationCount
    $dqDoc.metricRate = 0.0
    $dqDoc._id = Get-ShortVoiceDeterministicId -RunId $Context.RunId -DocumentType 'data_quality_summary' -DimensionKey 'all'
    $docs.Add($dqDoc) | Out-Null

    return @($docs.ToArray())
}

function Resolve-ShortVoiceElasticSecrets {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$ElasticConfig)

    $authMode = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'AuthMode' -DefaultValue 'ApiKey')
    $result = [ordered]@{ AuthMode = $authMode; ApiKey = ''; Username = ''; Password = '' }

    if ($authMode -ieq 'ApiKey') {
        $varName = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'ApiKeyEnvironmentVariable' -DefaultValue 'GENESYS_SHORT_CALLS_ELASTIC_API_KEY')
        $result.ApiKey = [string][Environment]::GetEnvironmentVariable($varName)
    }
    elseif ($authMode -ieq 'Basic') {
        $uVar = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'UsernameEnvironmentVariable' -DefaultValue 'GENESYS_SHORT_CALLS_ELASTIC_USERNAME')
        $pVar = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'PasswordEnvironmentVariable' -DefaultValue 'GENESYS_SHORT_CALLS_ELASTIC_PASSWORD')
        $result.Username = [string][Environment]::GetEnvironmentVariable($uVar)
        $result.Password = [string][Environment]::GetEnvironmentVariable($pVar)
    }

    return [pscustomobject]$result
}

function Publish-ShortVoiceElasticRollups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunFolder,
        [Parameter(Mandatory = $true)]$ElasticConfig,
        [Parameter(Mandatory = $true)][object[]]$Documents,
        [switch]$DryRun
    )

    $bulkSize = [int](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'BulkBatchSize' -DefaultValue 500)
    if ($bulkSize -lt 1) { $bulkSize = 500 }

    $indexName = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'IndexName' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($indexName)) {
        $indexName = 'genesys-short-voice-conversations-rollup'
    }

    if ((Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'UseDailyIndexSuffix' -DefaultValue $false) -eq $true) {
        $suffix = [DateTime]::UtcNow.ToString('yyyy.MM.dd')
        $indexName = "{0}-{1}" -f $indexName, $suffix
    }

    $payloadPath = [System.IO.Path]::Combine($RunFolder, 'short-voice-elastic-bulk.ndjson')
    $sw = New-Object System.IO.StreamWriter($payloadPath, $false, [System.Text.Encoding]::UTF8)
    try {
        foreach ($doc in @($Documents)) {
            $meta = [ordered]@{ index = [ordered]@{ _index = $indexName; _id = [string]$doc._id } }
            $sw.WriteLine(($meta | ConvertTo-Json -Compress -Depth 10))
            $sw.WriteLine(($doc | ConvertTo-Json -Compress -Depth 50))
        }
    }
    finally {
        $sw.Dispose()
    }

    if ($DryRun -or (Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'DryRun' -DefaultValue $false) -eq $true) {
        return [pscustomobject]@{
            Sent = $false
            DryRun = $true
            DocumentCount = @($Documents).Count
            BulkPayloadPath = $payloadPath
            IndexName = $indexName
        }
    }

    $uri = ([string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'Uri' -DefaultValue '')).TrimEnd('/') + '/_bulk'
    $secrets = Resolve-ShortVoiceElasticSecrets -ElasticConfig $ElasticConfig
    $headers = @{ 'Content-Type' = 'application/x-ndjson' }
    if ($secrets.AuthMode -ieq 'ApiKey' -and -not [string]::IsNullOrWhiteSpace($secrets.ApiKey)) {
        $headers['Authorization'] = "ApiKey $($secrets.ApiKey)"
    }
    elseif ($secrets.AuthMode -ieq 'Basic') {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $secrets.Username, $secrets.Password))
        $headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String($bytes)
    }

    $allLines = [System.IO.File]::ReadAllLines($payloadPath)
    $maxRetry = 3
    $delayMs = 1000
    $batchDocs = New-Object System.Collections.Generic.List[string]
    $sentCount = 0

    for ($i = 0; $i -lt @($allLines).Count; $i += 2) {
        $batchDocs.Add($allLines[$i]) | Out-Null
        if ($i + 1 -lt @($allLines).Count) { $batchDocs.Add($allLines[$i + 1]) | Out-Null }

        if ((@($batchDocs).Count / 2) -ge $bulkSize -or ($i + 2) -ge @($allLines).Count) {
            $body = [string]::Join("`n", @($batchDocs.ToArray())) + "`n"
            $attempt = 0
            while ($true) {
                try {
                    $invokeParams = @{
                        Uri = $uri
                        Method = 'Post'
                        Headers = $headers
                        Body = $body
                        ErrorAction = 'Stop'
                    }

                    if ($PSVersionTable.PSVersion.Major -ge 7) {
                        if ((Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'ValidateTls' -DefaultValue $true) -eq $false) {
                            $invokeParams['SkipCertificateCheck'] = $true
                        }
                    }

                    $response = Invoke-RestMethod @invokeParams
                    if ($response.errors -eq $true) {
                        throw 'Elastic bulk API reported item errors.'
                    }

                    $sentCount += (@($batchDocs).Count / 2)
                    break
                }
                catch {
                    $attempt++
                    if ($attempt -ge $maxRetry) { throw }
                    Start-Sleep -Milliseconds $delayMs
                    $delayMs = [Math]::Min($delayMs * 2, 10000)
                }
            }

            $batchDocs.Clear()
        }
    }

    return [pscustomobject]@{
        Sent = $true
        DryRun = $false
        DocumentCount = $sentCount
        BulkPayloadPath = $payloadPath
        IndexName = $indexName
    }
}

function Invoke-ShortVoiceConversationPostProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunFolder,
        [double]$ThresholdSeconds = 5.0,
        [string[]]$Directions = @('inbound', 'outbound'),
        [switch]$IncludeIncompleteConversations,
        [string]$Queue = '',
        [string]$Division = '',
        [string]$User = '',
        [string]$Campaign = '',
        [string]$DisconnectType = '',
        [string]$WrapUpCode = '',
        [string]$Ani = '',
        [string]$Dnis = '',
        [string]$ExternalContact = '',
        [switch]$ExportMarkdown,
        [switch]$ExportJson,
        [switch]$ExportCsv,
        [switch]$ExportExcel,
        [switch]$ElasticEnabled,
        [hashtable]$ElasticConfig
    )

    $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
    if (-not [System.IO.Directory]::Exists($dataDir)) {
        throw "Run folder does not contain a data directory: $RunFolder"
    }

    $inputFiles = [System.IO.Directory]::GetFiles($dataDir, '*.jsonl')
    if (@($inputFiles).Count -eq 0) {
        throw "Run folder has no JSONL data files: $RunFolder"
    }

    $summaryPath = [System.IO.Path]::Combine($RunFolder, 'short-voice-conversations-summary.json')
    $rollupPath = [System.IO.Path]::Combine($RunFolder, 'short-voice-conversations-rollup.json')
    $detailPath = [System.IO.Path]::Combine($RunFolder, 'short-voice-conversations-detail.jsonl')
    $markdownPath = [System.IO.Path]::Combine($RunFolder, 'short-voice-conversations-report.md')
    $csvPath = [System.IO.Path]::Combine($RunFolder, 'short-voice-conversations.csv')
    $xlsxPath = [System.IO.Path]::Combine($RunFolder, 'short-voice-conversations.xlsx')

    $filters = @{
        Directions = @($Directions)
        Queue = $Queue
        Division = $Division
        User = $User
        Campaign = $Campaign
        DisconnectType = $DisconnectType
        WrapUpCode = $WrapUpCode
        Ani = $Ani
        Dnis = $Dnis
        ExternalContact = $ExternalContact
    }

    $countScanned = 0
    $countShort = 0
    $countInboundShort = 0
    $countOutboundShort = 0
    $missingEnd = 0
    $excludedIncomplete = 0
    $missingQueue = 0
    $missingDivision = 0
    $missingUser = 0

    $durations = New-Object System.Collections.Generic.List[double]
    $byDirection = @{}
    $byQueue = @{}
    $byDivision = @{}
    $byDisconnect = @{}
    $byHour = @{}
    $byAgent = @{}
    $byCampaign = @{}
    $byAni = @{}
    $byDnis = @{}

    $detailWriter = New-Object System.IO.StreamWriter($detailPath, $false, [System.Text.Encoding]::UTF8)
    $previewDetails = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($file in @($inputFiles)) {
            $sr = New-Object System.IO.StreamReader($file, [System.Text.Encoding]::UTF8)
            try {
                while (-not $sr.EndOfStream) {
                    $line = $sr.ReadLine()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }

                    $conversation = $null
                    try { $conversation = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }

                    $countScanned++

                    if (-not (Test-ShortVoiceMediaType -Conversation $conversation)) { continue }

                    $direction = ConvertTo-ShortVoiceDirection -Conversation $conversation
                    $fields = Get-ShortVoiceConversationFields -Conversation $conversation

                    $durationInfo = Get-ShortVoiceDuration -Conversation $conversation -IncludeIncompleteConversations:$IncludeIncompleteConversations
                    if (-not $durationInfo.IsValid) {
                        if ($durationInfo.IsIncomplete) {
                            $missingEnd++
                            if (-not $IncludeIncompleteConversations) { $excludedIncomplete++ }
                        }
                        if (-not $IncludeIncompleteConversations) {
                            $countScanned--
                            continue
                        }
                    }

                    $record = [ordered]@{
                        ConversationId = if ($conversation.PSObject.Properties['conversationId']) { [string]$conversation.conversationId } else { '' }
                        Direction = $direction
                        ConversationStart = if ($conversation.PSObject.Properties['conversationStart']) { [string]$conversation.conversationStart } else { '' }
                        ConversationEnd = if ($conversation.PSObject.Properties['conversationEnd']) { [string]$conversation.conversationEnd } else { '' }
                        DurationSeconds = if ($durationInfo.IsValid) { [double]$durationInfo.DurationSeconds } else { $null }
                        QueueName = $fields.QueueName
                        QueueId = $fields.QueueId
                        DivisionName = $fields.DivisionName
                        DivisionId = $fields.DivisionId
                        UserName = $fields.UserName
                        UserId = $fields.UserId
                        DisconnectType = $fields.DisconnectType
                        WrapUpCode = $fields.WrapUpCode
                        WrapUpName = $fields.WrapUpName
                        Ani = $fields.Ani
                        Dnis = $fields.Dnis
                        CampaignId = $fields.CampaignId
                        CampaignName = $fields.CampaignName
                        ExternalContactId = $fields.ExternalContactId
                        ParticipantSummary = $fields.ParticipantSummary
                        SourceRunId = [System.IO.Path]::GetFileName($RunFolder)
                        SourceArtifactPath = $RunFolder
                    }

                    if (-not (Test-ShortVoiceRecordAgainstFilters -Record $record -Filters $filters)) { continue }

                    if ([string]::IsNullOrWhiteSpace($record.QueueName)) { $missingQueue++ }
                    if ([string]::IsNullOrWhiteSpace($record.DivisionId)) { $missingDivision++ }
                    if ([string]::IsNullOrWhiteSpace($record.UserId)) { $missingUser++ }

                    if ($durationInfo.IsValid -and [double]$record.DurationSeconds -lt [double]$ThresholdSeconds) {
                        $countShort++
                        if ($direction -eq 'inbound') { $countInboundShort++ }
                        if ($direction -eq 'outbound') { $countOutboundShort++ }

                        $durations.Add([double]$record.DurationSeconds) | Out-Null
                        $queueKey = if ($record.QueueName) { $record.QueueName } else { $record.QueueId }
                        $divisionKey = if ($record.DivisionName) { $record.DivisionName } else { $record.DivisionId }
                        $agentKey = if ($record.UserName) { $record.UserName } else { $record.UserId }
                        $campaignKey = if ($record.CampaignName) { $record.CampaignName } else { $record.CampaignId }
                        Add-ShortVoiceRollupCount -Map $byDirection -Key $record.Direction -Duration $record.DurationSeconds
                        Add-ShortVoiceRollupCount -Map $byQueue -Key $queueKey -Duration $record.DurationSeconds
                        Add-ShortVoiceRollupCount -Map $byDivision -Key $divisionKey -Duration $record.DurationSeconds
                        Add-ShortVoiceRollupCount -Map $byDisconnect -Key $record.DisconnectType -Duration $record.DurationSeconds
                        Add-ShortVoiceRollupCount -Map $byAgent -Key $agentKey -Duration $record.DurationSeconds
                        Add-ShortVoiceRollupCount -Map $byCampaign -Key $campaignKey -Duration $record.DurationSeconds
                        Add-ShortVoiceRollupCount -Map $byAni -Key $record.Ani -Duration $record.DurationSeconds
                        Add-ShortVoiceRollupCount -Map $byDnis -Key $record.Dnis -Duration $record.DurationSeconds

                        $hour = ''
                        if (-not [string]::IsNullOrWhiteSpace($record.ConversationStart)) {
                            try { $hour = ([DateTimeOffset]::Parse($record.ConversationStart)).UtcDateTime.ToString('HH') } catch { $hour = '' }
                        }
                        Add-ShortVoiceRollupCount -Map $byHour -Key $hour -Duration $record.DurationSeconds

                        $json = $record | ConvertTo-Json -Compress -Depth 20
                        $detailWriter.WriteLine($json)
                        if ($previewDetails.Count -lt 1000) {
                            $detailObject = New-Object psobject
                            foreach ($key in @($record.Keys)) {
                                $detailObject | Add-Member -NotePropertyName $key -NotePropertyValue $record[$key] -Force
                            }
                            $previewDetails.Add($detailObject) | Out-Null
                        }
                    }
                }
            }
            finally {
                $sr.Dispose()
            }
        }
    }
    finally {
        $detailWriter.Dispose()
    }

    $avg = if (@($durations).Count -gt 0) { [math]::Round((@($durations) | Measure-Object -Average).Average, 3) } else { 0.0 }
    $median = [math]::Round((Get-ShortVoicePercentile -Values @($durations) -Percentile 50), 3)
    $p95 = [math]::Round((Get-ShortVoicePercentile -Values @($durations) -Percentile 95), 3)

    $rollup = [ordered]@{
        ByDirection = @(ConvertTo-ShortVoiceRollupRows -Map $byDirection -Total $countShort)
        ByQueue = @(ConvertTo-ShortVoiceRollupRows -Map $byQueue -Total $countShort)
        ByDivision = @(ConvertTo-ShortVoiceRollupRows -Map $byDivision -Total $countShort)
        ByDisconnectType = @(ConvertTo-ShortVoiceRollupRows -Map $byDisconnect -Total $countShort)
        ByHour = @(ConvertTo-ShortVoiceRollupRows -Map $byHour -Total $countShort)
        ByAgent = @(ConvertTo-ShortVoiceRollupRows -Map $byAgent -Total $countShort)
        ByCampaign = @(ConvertTo-ShortVoiceRollupRows -Map $byCampaign -Total $countShort)
        ByAni = @(ConvertTo-ShortVoiceRollupRows -Map $byAni -Total $countShort)
        ByDnis = @(ConvertTo-ShortVoiceRollupRows -Map $byDnis -Total $countShort)
    }

    $summary = [ordered]@{
        TotalVoiceConversationsScanned = $countScanned
        TotalShortVoiceConversations = $countShort
        ShortConversationRatePercent = if ($countScanned -gt 0) { [math]::Round(($countShort / $countScanned) * 100.0, 3) } else { 0.0 }
        InboundShortCount = $countInboundShort
        OutboundShortCount = $countOutboundShort
        AverageShortDurationSeconds = $avg
        MedianShortDurationSeconds = $median
        P95ShortDurationSeconds = $p95
        ShortConversationThresholdSeconds = [double]$ThresholdSeconds
        DurationCalculationMethod = 'conversationStart-conversationEnd'
        MissingEndTimeCount = $missingEnd
        ExcludedIncompleteConversationCount = $excludedIncomplete
        MissingQueueCount = $missingQueue
        MissingDivisionCount = $missingDivision
        MissingUserCount = $missingUser
        MissingFieldCounts = [ordered]@{
            missingQueue = $missingQueue
            missingDivision = $missingDivision
            missingUser = $missingUser
            missingEndTime = $missingEnd
        }
        TopAffectedQueues = @($rollup.ByQueue | Select-Object -First 5 | ForEach-Object { $_.Key })
        TopAffectedAgents = @($rollup.ByAgent | Select-Object -First 5 | ForEach-Object { $_.Key })
        TopDisconnectTypes = @($rollup.ByDisconnectType | Select-Object -First 5 | ForEach-Object { $_.Key })
        TopAniPatterns = @($rollup.ByAni | Select-Object -First 5 | ForEach-Object { $_.Key })
        TopDnisPatterns = @($rollup.ByDnis | Select-Object -First 5 | ForEach-Object { $_.Key })
        GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    if ($ExportJson -or -not ($ExportMarkdown -or $ExportCsv -or $ExportExcel)) {
        Write-JsonFile -Path $summaryPath -Object $summary
        Write-JsonFile -Path $rollupPath -Object $rollup
    }

    $parameters = [ordered]@{
        Interval = ''
        ThresholdSeconds = $ThresholdSeconds
        Directions = @($Directions)
        Queue = $Queue
        Division = $Division
        User = $User
        Campaign = $Campaign
    }

    if ($ExportMarkdown -or -not ($ExportJson -or $ExportCsv -or $ExportExcel)) {
        $markdown = New-ShortVoiceMarkdownReport -Summary $summary -Rollup $rollup -RunId ([System.IO.Path]::GetFileName($RunFolder)) -GeneratedAtUtc ([DateTime]::UtcNow.ToString('o')) -Parameters $parameters -TopN 100
        Set-Content -Path $markdownPath -Value $markdown -Encoding utf8
    }

    if ($ExportCsv) {
        $rows = $previewDetails.ToArray()
        if ($rows.Count -gt 0) {
            $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        } else {
            '' | Set-Content -Path $csvPath -Encoding utf8
        }
    }

    if ($ExportExcel) {
        $importExcelAvailable = $null -ne (Get-Command -Name Export-Excel -ErrorAction SilentlyContinue)
        if ($importExcelAvailable) {
            $previewDetails.ToArray() | Export-Excel -Path $xlsxPath -WorksheetName 'ShortVoice' -AutoSize -AutoFilter
        }
    }

    $elasticResult = $null
    $elasticDocs = @()
    if ($ElasticEnabled -and $null -ne $ElasticConfig) {
        $context = [ordered]@{
            Timestamp = [DateTime]::UtcNow.ToString('o')
            OrgName = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'OrgName' -DefaultValue '')
            OrgId = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'OrgId' -DefaultValue '')
            Region = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'Region' -DefaultValue '')
            RunId = [System.IO.Path]::GetFileName($RunFolder)
            IntervalStart = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'IntervalStart' -DefaultValue '')
            IntervalEnd = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'IntervalEnd' -DefaultValue '')
            SourceArtifactPath = $RunFolder
            AppVersion = [string](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'AppVersion' -DefaultValue '')
            ModuleVersion = '1.0.0'
        }
        $elasticDocs = New-ShortVoiceElasticDocuments -Summary $summary -Rollup $rollup -Context $context
        $elasticResult = Publish-ShortVoiceElasticRollups -RunFolder $RunFolder -ElasticConfig $ElasticConfig -Documents $elasticDocs -DryRun:([bool](Get-ShortVoiceConfigValue -Config $ElasticConfig -Key 'DryRun' -DefaultValue $false))
    }

    return [pscustomobject]@{
        RunFolder = $RunFolder
        Summary = [pscustomobject]$summary
        Rollup = [pscustomobject]$rollup
        DetailPath = $detailPath
        SummaryPath = $summaryPath
        RollupPath = $rollupPath
        MarkdownPath = $markdownPath
        CsvPath = $csvPath
        XlsxPath = $xlsxPath
        PreviewDetails = $previewDetails.ToArray()
        ElasticDocuments = @($elasticDocs)
        ElasticPublish = $elasticResult
    }
}

Export-ModuleMember -Function `
    Get-ShortVoicePercentile, `
    Get-ShortVoiceDuration, `
    ConvertTo-ShortVoiceDirection, `
    Invoke-ShortVoiceConversationPostProcess, `
    New-ShortVoiceElasticDocuments, `
    Get-ShortVoiceDeterministicId, `
    Publish-ShortVoiceElasticRollups
