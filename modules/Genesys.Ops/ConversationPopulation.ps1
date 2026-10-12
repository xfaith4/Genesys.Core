#Requires -Version 5.1
# Adapted with provenance from the user-supplied ConversationAnalyser source.
# Source: F:/Development/20_Staging/GenesysCloud/ConversationAnalyser/src/analysis/ConversationAnalysis.ps1
# Get-ConversationProfile, inspected 2026-10-11. No runtime dependency on that checkout.
# Domain semantics live here in Ops; interfaces consume the sanitized profile below.
$script:gcProfileAgentPurposes = @{ agent = $true; user = $true }

# Agent-work metrics are only summed from agent/user participants so a same-named
# emission on another participant can never double count handle time.
$script:gcProfileAgentMetricNames = @{}
foreach ($name in @('tHandle', 'tTalk', 'tTalkComplete', 'tHeld', 'tHeldComplete', 'tAcw', 'tAlert',
        'tNotResponding', 'tDialing', 'tContacting', 'tAgentResponseTime', 'nTransferred',
        'nBlindTransferred', 'nConsultTransferred', 'nConsult', 'nConnected', 'nOutbound')) { $script:gcProfileAgentMetricNames[$name] = $true }

# Session-level metrics retained on the profile for queue and agent breakdowns.
# Kept to a whitelist so cached profiles stay small on large result sets.
$script:gcProfileSessionMetricNames = @{}
foreach ($name in @('nOffered', 'tAnswered', 'tAbandon', 'tShortAbandon', 'nOverSla', 'tAcd',
        'tHandle', 'tTalk', 'tHeld', 'tAcw', 'tAlert', 'tNotResponding', 'nTransferred', 'nOutbound')) { $script:gcProfileSessionMetricNames[$name] = $true }


function ConvertTo-GcProfileUtcDateTime {
    # Accepts DateTime (PS7 ConvertFrom-Json), DateTimeOffset, or ISO-8601 text (PS 5.1).
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
        if ($Value.Kind -eq [DateTimeKind]::Local) { return $Value.ToUniversalTime() }
        return [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc)
    }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.UtcDateTime
    }
    return $null
}

function Get-GcProfileIdsOrderedByTime {
    # $FirstSeen maps id -> earliest UTC DateTime; returns the ids in time order.
    param([hashtable]$FirstSeen)
    if ($null -eq $FirstSeen -or $FirstSeen.Count -eq 0) { return @() }
    $ids = [string[]]::new($FirstSeen.Count)
    $times = [DateTime[]]::new($FirstSeen.Count)
    $i = 0
    foreach ($key in $FirstSeen.Keys) {
        $ids[$i] = [string]$key
        $times[$i] = [DateTime]$FirstSeen[$key]
        $i++
    }
    [Array]::Sort($times, $ids)
    return $ids
}

function Get-GcConversationProfileCore {
    # Single pass over participants/sessions/segments/metrics. Holds IDs, not names, so
    # the cached profile stays valid when name lookups are refreshed later.
    param([Parameter(Mandatory = $true)][object]$Conversation)

    # Optional analytics fields are expected; tolerate absent properties locally.
    Set-StrictMode -Off
    $conv = $Conversation
    $startUtc = ConvertTo-GcProfileUtcDateTime $conv.conversationStart
    $endUtc = ConvertTo-GcProfileUtcDateTime $conv.conversationEnd
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $utcStyles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $parsedTime = [DateTime]::MinValue
    $agentPurposes = $script:gcProfileAgentPurposes
    $agentMetricNames = $script:gcProfileAgentMetricNames
    $sessionMetricNames = $script:gcProfileSessionMetricNames

    $metricSums = @{}
    $metricCounts = @{}
    $sessionFacts = [System.Collections.ArrayList]::new()
    $queueFirstSeen = @{}
    $agentFirstSeen = @{}
    $agentNames = @{}
    $purposeCounts = [ordered]@{}
    $flowNames = [ordered]@{}   # ordered set: key order = first seen
    $firstFlow = $null
    $flowOutcomes = 0
    $flowOutcomeFailures = 0
    $finalWrapUp = $null
    $finalDisconnect = $null
    $fallbackDisconnect = $null
    $errorCodes = [ordered]@{}   # ordered set: key order = first seen
    $errorEvents = [System.Collections.Generic.List[object]]::new()   # one per segment carrying an errorCode
    $errorDisconnect = $false
    $hasErrorCodeProperty = $false
    $sipCodes = [ordered]@{}   # ordered set: key order = first seen
    $q850Codes = [ordered]@{}   # ordered set: key order = first seen
    $skillIds = [ordered]@{}   # ordered set: key order = first seen
    $languageIds = [ordered]@{}   # ordered set: key order = first seen
    $requestedRoutings = [ordered]@{}   # ordered set: key order = first seen
    $usedRouting = ''
    $codecs = [ordered]@{}   # ordered set: key order = first seen
    $maxLatencyMs = $null
    $sessionMinMos = $null
    $recorded = $false
    $holdCount = 0
    $voicemail = $false
    $agentConnected = $false
    $customer = $null
    $external = $null
    $firstMediaType = ''
    $participantCount = 0

    foreach ($p in $conv.participants) {
        $participantCount++
        $purpose = [string]$p.purpose
        if ($purposeCounts.Contains($purpose)) { $purposeCounts[$purpose]++ } else { $purposeCounts[$purpose] = 1 }
        if ($null -eq $customer -and $purpose -eq 'customer') { $customer = $p }
        if ($null -eq $external -and $purpose -eq 'external') { $external = $p }

        $isAgent = [bool]$agentPurposes[$purpose]
        $isAcd = ($purpose -eq 'acd')
        $userId = [string]$p.userId
        $participantName = [string]$p.participantName
        $agentKey = ''
        if ($isAgent) {
            $agentKey = $userId # Keep profile identity fields free of participant-name fallback.
            if ($agentKey -and $participantName -and -not $agentNames.ContainsKey($agentKey)) { $agentNames[$agentKey] = $participantName }
        }

        foreach ($s in $p.sessions) {
            $sessionMedia = [string]$s.mediaType
            if (-not $firstMediaType -and $sessionMedia) { $firstMediaType = $sessionMedia }
            if ($s.recording -eq $true) { $recorded = $true }
            foreach ($routing in $s.requestedRoutings) {
                $routingText = [string]$routing
                if ($routingText) { $requestedRoutings[$routingText] = $true }
            }
            if (-not $usedRouting -and $s.usedRouting) { $usedRouting = [string]$s.usedRouting }

            if ($null -ne $s.flow) {
                $flowName = [string]$s.flow.flowName
                if ($flowName) { $flowNames[$flowName] = $true }
                if ($null -eq $firstFlow) { $firstFlow = $s.flow }
                foreach ($outcome in $s.flow.outcomes) {
                    $flowOutcomes++
                    if ([string]$outcome.flowOutcomeValue -eq 'FAILURE') { $flowOutcomeFailures++ }
                }
            }

            foreach ($stat in $s.mediaEndpointStats) {
                foreach ($codec in $stat.codecs) {
                    $codecText = [string]$codec
                    if ($codecText) { $codecs[$codecText] = $true }
                }
                if ($null -ne $stat.maxLatencyMs -and ($null -eq $maxLatencyMs -or [double]$stat.maxLatencyMs -gt $maxLatencyMs)) { $maxLatencyMs = [double]$stat.maxLatencyMs }
                if ($null -ne $stat.minMos -and ($null -eq $sessionMinMos -or [double]$stat.minMos -lt $sessionMinMos)) { $sessionMinMos = [double]$stat.minMos }
            }

            $keepSession = ($isAgent -or $isAcd)
            $sessionMetrics = if ($keepSession) { @{} } else { $null }
            foreach ($m in $s.metrics) {
                $metricName = [string]$m.name
                if (-not $metricName -or $null -eq $m.value) { continue }
                $metricValue = [double]$m.value
                if ($keepSession -and $sessionMetricNames[$metricName]) {
                    if ($sessionMetrics.ContainsKey($metricName)) { $sessionMetrics[$metricName] += $metricValue } else { $sessionMetrics[$metricName] = $metricValue }
                }
                if ($isAgent -or -not $agentMetricNames[$metricName]) {
                    if ($metricSums.ContainsKey($metricName)) {
                        $metricSums[$metricName] += $metricValue
                        $metricCounts[$metricName]++
                    }
                    else {
                        $metricSums[$metricName] = $metricValue
                        $metricCounts[$metricName] = 1
                    }
                }
            }

            $sessionQueueId = ''
            foreach ($seg in $s.segments) {
                $segType = [string]$seg.segmentType
                # Inline conversion (a function call per segment is the dominant cost at scale).
                # PS7 JSON already yields DateTime; PS 5.1 yields ISO-8601 text.
                $segStart = $seg.segmentStart
                if ($null -ne $segStart -and $segStart -isnot [DateTime]) {
                    $segStart = if ([DateTime]::TryParse([string]$segStart, $invariant, $utcStyles, [ref]$parsedTime)) { $parsedTime } else { $null }
                }
                $segEnd = $seg.segmentEnd
                if ($null -ne $segEnd -and $segEnd -isnot [DateTime]) {
                    $segEnd = if ([DateTime]::TryParse([string]$segEnd, $invariant, $utcStyles, [ref]$parsedTime)) { $parsedTime } else { $null }
                }
                $orderKey = if ($null -ne $segStart) { $segStart } else { [DateTime]::MaxValue }
                $eventTime = if ($null -ne $segEnd) { $segEnd } else { $segStart }
                # Unknown timestamps must not outrank a known terminal event.
                $eventOrderKey = if ($null -ne $eventTime) { $eventTime } else { [DateTime]::MinValue }

                $queueId = [string]$seg.queueId
                if ($queueId) {
                    if (-not $sessionQueueId) { $sessionQueueId = $queueId }
                    if (-not $queueFirstSeen.ContainsKey($queueId) -or $orderKey -lt $queueFirstSeen[$queueId]) { $queueFirstSeen[$queueId] = $orderKey }
                }

                if ($isAgent) {
                    # Agents that were only alerted (never engaged) are not part of the agent path.
                    if ($agentKey -and $segType -ne 'alert') {
                        if (-not $agentFirstSeen.ContainsKey($agentKey) -or $orderKey -lt $agentFirstSeen[$agentKey]) { $agentFirstSeen[$agentKey] = $orderKey }
                    }
                    if ($segType -eq 'hold') { $holdCount++ }
                    elseif ($segType -eq 'interact') { $agentConnected = $true }
                }
                if ($segType -eq 'voicemail') { $voicemail = $true }

                $wrapCode = [string]$seg.wrapUpCode
                if ($wrapCode -and ($null -eq $finalWrapUp -or $eventOrderKey -ge $finalWrapUp.Time)) {
                    $finalWrapUp = @{ Code = $wrapCode; Note = [string]$seg.wrapUpNote; Time = $eventOrderKey }
                }

                # Conversation-ending disconnect: the latest non-peer, non-transfer disconnect
                # outside wrap-up. Early declined alerts or transfers therefore never win.
                $disconnectType = [string]$seg.disconnectType
                if ($disconnectType -and $segType -ne 'wrapup') {
                    $candidate = @{ Purpose = $purpose; Type = $disconnectType; Time = $eventOrderKey }
                    if ($null -eq $fallbackDisconnect -or $eventOrderKey -ge $fallbackDisconnect.Time) { $fallbackDisconnect = $candidate }
                    if ($disconnectType -ne 'peer' -and $disconnectType -notlike '*transfer*') {
                        if ($null -eq $finalDisconnect -or $eventOrderKey -ge $finalDisconnect.Time) { $finalDisconnect = $candidate }
                    }
                }

                if ($disconnectType -eq 'error') { $errorDisconnect = $true }
                if (($seg -is [System.Collections.IDictionary] -and $seg.Contains('errorCode')) -or $seg.PSObject.Properties.Name -contains 'errorCode') { $hasErrorCodeProperty = $true }
                $errorCode = [string]$seg.errorCode
                if ($errorCode) {
                    $errorCodes[$errorCode] = $true
                    # Kept per segment so the report can say who carried the error and how that leg ended.
                    $errorEvents.Add([pscustomobject]@{ Code = $errorCode; Purpose = $purpose; DisconnectType = $disconnectType; MediaType = $sessionMedia; SegmentType = $segType; Time = $eventTime }) | Out-Null
                }
                foreach ($code in $seg.sipResponseCodes) {
                    $codeText = [string]$code
                    if ($codeText) { $sipCodes[$codeText] = $true }
                }
                foreach ($code in $seg.q850ResponseCodes) {
                    $codeText = [string]$code
                    if ($codeText) { $q850Codes[$codeText] = $true }
                }
                foreach ($skillId in $seg.requestedRoutingSkillIds) {
                    $skillText = [string]$skillId
                    if ($skillText) { $skillIds[$skillText] = $true }
                }
                $languageId = [string]$seg.requestedLanguageId
                if ($languageId) { $languageIds[$languageId] = $true }
            }

            if ($keepSession) {
                $sessionFacts.Add(@{
                        Purpose   = $purpose
                        AgentKey  = $agentKey
                        QueueId   = $sessionQueueId
                        MediaType = $sessionMedia
                        Metrics   = $sessionMetrics
                    }) | Out-Null
            }
        }
    }

    # Wrap the whole if in @(): assigning an if-statement's output unrolls a 1-item array.
    $queueIds = @(if ($queueFirstSeen.Count -gt 1) { Get-GcProfileIdsOrderedByTime -FirstSeen $queueFirstSeen } else { $queueFirstSeen.Keys })
    $agentKeys = @(if ($agentFirstSeen.Count -gt 1) { Get-GcProfileIdsOrderedByTime -FirstSeen $agentFirstSeen } else { $agentFirstSeen.Keys })

    # Customer identity (outbound agent calls may only have an 'external' party)
    $party = if ($null -ne $customer) { $customer } else { $external }
    $ani = ''; $dnis = ''; $partyMedia = ''
    if ($null -ne $party) {
        foreach ($s in $party.sessions) {
            if (-not $partyMedia -and $s.mediaType) { $partyMedia = [string]$s.mediaType }
            if (-not $ani) { $ani = if ($s.ani) { [string]$s.ani } else { [string]$s.addressFrom } }
            if (-not $dnis) { $dnis = if ($s.dnis) { [string]$s.dnis } else { [string]$s.addressTo } }
        }
    }

    $offered = ($metricSums.ContainsKey('nOffered') -and $metricSums['nOffered'] -gt 0)
    $transferTotal = 0
    foreach ($name in @('nTransferred', 'nBlindTransferred', 'nConsultTransferred')) {
        if ($metricSums.ContainsKey($name)) { $transferTotal = [Math]::Max($transferTotal, [int]$metricSums[$name]) }
    }

    $selfServed = $false
    if ($conv.PSObject.Properties.Name -contains 'selfServed' -and $null -ne $conv.selfServed) {
        $selfServed = [bool]$conv.selfServed
    }
    else {
        $selfServed = ($flowNames.Count -gt 0 -and -not $offered -and $agentKeys.Count -eq 0 -and -not $voicemail)
    }

    $minMos = if ($null -ne $conv.mediaStatsMinConversationMos) { [double]$conv.mediaStatsMinConversationMos } elseif ($null -ne $sessionMinMos) { $sessionMinMos } else { $null }
    $minRFactor = if ($null -ne $conv.mediaStatsMinConversationRFactor) { [Math]::Round([double]$conv.mediaStatsMinConversationRFactor, 1) } else { $null }

    $evalCount = 0; $evalScoreSum = 0.0; $evalScoreCount = 0
    foreach ($evaluation in $conv.evaluations) {
        $evalCount++
        if ($null -ne $evaluation.oTotalScore) { $evalScoreSum += [double]$evaluation.oTotalScore; $evalScoreCount++ }
    }
    $surveyCount = 0; $surveyScoreSum = 0.0; $surveyScoreCount = 0; $npsSum = 0.0; $npsCount = 0
    foreach ($survey in $conv.surveys) {
        $surveyCount++
        if ($null -ne $survey.oSurveyTotalScore) { $surveyScoreSum += [double]$survey.oSurveyTotalScore; $surveyScoreCount++ }
        if ($null -ne $survey.surveyPromoterScore) { $npsSum += [double]$survey.surveyPromoterScore; $npsCount++ }
    }
    $resolutionCount = 0
    foreach ($resolution in $conv.resolutions) { if ($null -ne $resolution) { $resolutionCount++ } }

    $divisionIds = [System.Collections.ArrayList]::new()
    foreach ($divisionId in $conv.divisionIds) { if ($divisionId) { $divisionIds.Add([string]$divisionId) | Out-Null } }

    $durationSec = $null
    if ($null -ne $startUtc -and $null -ne $endUtc) { $durationSec = [int][Math]::Round(($endUtc - $startUtc).TotalSeconds, [MidpointRounding]::AwayFromZero) }

    $purposeParts = [System.Collections.ArrayList]::new()
    foreach ($entry in $purposeCounts.GetEnumerator()) { $purposeParts.Add(('{0}:{1}' -f $entry.Key, $entry.Value)) | Out-Null }
    $purposeSummary = $purposeParts -join ', '

    return [pscustomobject]@{
        ConversationId        = [string]$conv.conversationId
        StartUtc              = $startUtc
        EndUtc                = $endUtc
        StartLocal            = if ($null -ne $startUtc) { $startUtc.ToLocalTime() } else { $null }
        DurationSec           = $durationSec
        Direction             = [string]$conv.originatingDirection
        MediaType             = if ($partyMedia) { $partyMedia } else { $firstMediaType }
        Initiator             = [string]$conv.conversationInitiator
        CustomerParticipation = if ($null -ne $conv.customerParticipation) { [bool]$conv.customerParticipation } else { $null }
        ExternalTag           = [string]$conv.externalTag
        DivisionIds           = @($divisionIds)
        CustomerName          = if ($null -ne $party) { [string]$party.participantName } else { '' }
        Ani                   = $ani
        Dnis                  = $dnis
        ExternalContactId     = if ($null -ne $party) { [string]$party.externalContactId } else { '' }
        ParticipantCount      = $participantCount
        PurposeSummary        = $purposeSummary
        QueueIds              = $queueIds
        AgentKeys             = $agentKeys
        AgentNames            = $agentNames
        RequestedRoutings     = @($requestedRoutings.Keys)
        UsedRouting           = $usedRouting
        SkillIds              = @($skillIds.Keys)
        LanguageIds           = @($languageIds.Keys)
        FlowNames             = @($flowNames.Keys)
        FlowType              = if ($null -ne $firstFlow) { [string]$firstFlow.flowType } else { '' }
        FlowEntryReason       = if ($null -ne $firstFlow) { [string]$firstFlow.entryReason } else { '' }
        FlowExitReason        = if ($null -ne $firstFlow) { [string]$firstFlow.exitReason } else { '' }
        FlowOutcomes          = $flowOutcomes
        FlowOutcomeFailures   = $flowOutcomeFailures
        WrapUpCodeId          = if ($null -ne $finalWrapUp) { $finalWrapUp.Code } else { '' }
        WrapUpNote            = if ($null -ne $finalWrapUp) { $finalWrapUp.Note } else { '' }
        DisconnectPurpose     = if ($null -ne $finalDisconnect) { $finalDisconnect.Purpose } elseif ($null -ne $fallbackDisconnect) { $fallbackDisconnect.Purpose } else { '' }
        DisconnectType        = if ($null -ne $finalDisconnect) { $finalDisconnect.Type } elseif ($null -ne $fallbackDisconnect) { $fallbackDisconnect.Type } else { '' }
        MetricSums            = $metricSums
        MetricCounts          = $metricCounts
        Offered               = $offered
        Answered              = $metricCounts.ContainsKey('tAnswered')
        Abandoned             = $metricCounts.ContainsKey('tAbandon')
        ShortAbandon          = $metricCounts.ContainsKey('tShortAbandon')
        OverSla               = ($metricSums.ContainsKey('nOverSla') -and $metricSums['nOverSla'] -gt 0)
        AgentConnected        = $agentConnected
        TransferCount         = $transferTotal
        Transferred           = ($transferTotal -gt 0)
        HoldCount             = $holdCount
        Voicemail             = ($voicemail -or $metricCounts.ContainsKey('tVoicemail'))
        SelfServed            = $selfServed
        MinMos                = $minMos
        EndpointMinMos        = $sessionMinMos
        ConversationMinMos    = $conv.mediaStatsMinConversationMos
        HasErrorCodeProperty  = $hasErrorCodeProperty
        MinRFactor            = $minRFactor
        Codecs                = @($codecs.Keys)
        MaxLatencyMs          = $maxLatencyMs
        Recorded              = $recorded
        EvaluationCount       = $evalCount
        EvalScore             = if ($evalScoreCount -gt 0) { [Math]::Round($evalScoreSum / $evalScoreCount, 1) } else { $null }
        SurveyCount           = $surveyCount
        SurveyScore           = if ($surveyScoreCount -gt 0) { [Math]::Round($surveyScoreSum / $surveyScoreCount, 1) } else { $null }
        NpsScore              = if ($npsCount -gt 0) { [Math]::Round($npsSum / $npsCount, 1) } else { $null }
        ResolutionCount       = $resolutionCount
        ErrorCodes            = @($errorCodes.Keys)
        ErrorEvents           = @($errorEvents)
        ErrorSegmentCount     = $errorEvents.Count
        ErrorDisconnect       = $errorDisconnect
        SipCodes              = @($sipCodes.Keys)
        Q850Codes             = @($q850Codes.Keys)
        Sessions              = $sessionFacts
    }
}

function Get-GenesysConversationProfile {
    <#
    .SYNOPSIS
    Creates a non-PII investigation profile from a conversation detail record.
    .DESCRIPTION
    Adapted from the supplied Get-ConversationProfile reference. Metric values are
    nullable when absent. t* fields are seconds; MaxLatencyMs remains milliseconds.
    All segment error events are retained, across every participant/media type.
    MinMos prefers conversation summary MOS, then the lowest endpoint minimum.
    EndpointMinMos exposes the literal mediaEndpointStats.minMos minimum separately.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][object]$InputObject)
    process {
        $profile = Get-GcConversationProfileCore -Conversation $InputObject
        $row = [ordered]@{}
        $fields = @('ConversationId','StartUtc','EndUtc','DurationSec','Direction','Initiator','CustomerParticipation',
            'DivisionIds','ParticipantCount','PurposeSummary','QueueIds','AgentKeys','RequestedRoutings','UsedRouting',
            'SkillIds','LanguageIds','FlowNames','FlowType','FlowEntryReason','FlowExitReason','FlowOutcomes','FlowOutcomeFailures',
            'WrapUpCodeId','DisconnectPurpose','DisconnectType','Offered','Answered','Abandoned','ShortAbandon','OverSla',
            'AgentConnected','TransferCount','Transferred','HoldCount','Voicemail','SelfServed','MinMos','EndpointMinMos',
            'ConversationMinMos','HasErrorCodeProperty','MinRFactor','Codecs','MaxLatencyMs','Recorded','EvaluationCount',
            'EvalScore','SurveyCount','SurveyScore','NpsScore','ResolutionCount','ErrorCodes','ErrorEvents','ErrorSegmentCount',
            'ErrorDisconnect','SipCodes','Q850Codes','Sessions')
        foreach ($field in $fields) { $row[$field] = $profile.$field }
        $media = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $timeline = [System.Collections.Generic.List[object]]::new()
        $endpointStats = [System.Collections.Generic.List[object]]::new()
        $flowIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $users = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($participant in @(Get-GcVolumeProperty $InputObject 'participants' @())) {
            $userId = [string](Get-GcVolumeProperty $participant 'userId' '')
            if ($userId) { $null = $users.Add($userId) }
            foreach ($session in @(Get-GcVolumeProperty $participant 'sessions' @())) {
                $flow = Get-GcVolumeProperty $session 'flow'
                $flowId = [string](Get-GcVolumeProperty $flow 'flowId' '')
                if ($flowId) { $null=$flowIds.Add($flowId) }
                foreach ($stat in @(Get-GcVolumeProperty $session 'mediaEndpointStats' @())) {
                    $endpointStats.Add([pscustomobject]@{
                        SessionId=Get-GcVolumeProperty $session 'sessionId'; UserId=Get-GcVolumeProperty $participant 'userId'
                        Purpose=Get-GcVolumeProperty $participant 'purpose'; EventTime=Get-GcVolumeProperty $stat 'eventTime'
                        DiscardedPackets=Get-GcVolumeProperty $stat 'discardedPackets'; ReceivedPackets=Get-GcVolumeProperty $stat 'receivedPackets'
                        DuplicatePackets=Get-GcVolumeProperty $stat 'duplicatePackets'; InvalidPackets=Get-GcVolumeProperty $stat 'invalidPackets'
                        OverrunPackets=Get-GcVolumeProperty $stat 'overrunPackets'; UnderrunPackets=Get-GcVolumeProperty $stat 'underrunPackets'
                    })
                }
                $type = [string](Get-GcVolumeProperty $session 'mediaType' '')
                if ($type) { $null = $media.Add($type) }
                foreach ($segment in @(Get-GcVolumeProperty $session 'segments' @())) {
                    $timeline.Add([pscustomobject]@{
                        StartUtc = ConvertTo-GcProfileUtcDateTime (Get-GcVolumeProperty $segment 'segmentStart')
                        EndUtc = ConvertTo-GcProfileUtcDateTime (Get-GcVolumeProperty $segment 'segmentEnd')
                        Purpose = Get-GcVolumeProperty $participant 'purpose'; UserId = Get-GcVolumeProperty $participant 'userId'
                        ParticipantId = Get-GcVolumeProperty $participant 'participantId'; SessionId = Get-GcVolumeProperty $session 'sessionId'
                        MediaType = $type; QueueId = Get-GcVolumeProperty $segment 'queueId'; SegmentType = Get-GcVolumeProperty $segment 'segmentType'
                        DisconnectType = Get-GcVolumeProperty $segment 'disconnectType'; ErrorCode = Get-GcVolumeProperty $segment 'errorCode'
                        WrapUpCodeId = Get-GcVolumeProperty $segment 'wrapUpCode'; SipCodes = @(Get-GcVolumeProperty $segment 'sipResponseCodes' @())
                        Q850Codes = @(Get-GcVolumeProperty $segment 'q850ResponseCodes' @())
                    })
                }
            }
        }
        $row.EndpointStats = @($endpointStats.ToArray())
        $row.FlowIds = @($flowIds | Sort-Object)
        $discarded = @($endpointStats | ForEach-Object { if ($null -ne $_.DiscardedPackets) { [double]$_.DiscardedPackets } })
        $row.DiscardedPacketSamples = $discarded.Count
        $packetMeasurement = $discarded | Measure-Object -Average -Maximum
        $row.AvgDiscardedPackets = $packetMeasurement.Average
        $row.MaxDiscardedPackets = $packetMeasurement.Maximum
        $row.MediaTypes = @($media | Sort-Object)
        $row.UserIds = @($users | Sort-Object)
        $row.UserCount = $users.Count
        $row.SelfServedSource = if ($null -ne (Get-GcVolumeProperty $InputObject 'selfServed')) { 'platform flag' } else { 'flow-only heuristic' }
        $row.Timeline = @($timeline | Sort-Object @{Expression={if ($null -ne $_.StartUtc) {$_.StartUtc} else {[datetime]::MaxValue}}})
        foreach ($name in @('tAnswered','tAbandon','tShortAbandon','tAcd','tWait','tIvr','tFlow','tAlert','tNotResponding',
            'tDialing','tContacting','tTalk','tHeld','tAcw','tHandle','tVoicemail')) {
            $row["$($name)Sec"] = if ($profile.MetricSums.ContainsKey($name)) { [double]$profile.MetricSums[$name] / 1000.0 } else { $null }
        }
        foreach ($name in @('nConnected','nOffered','nOverSla','nOutbound','nError','nTransferred','nBlindTransferred','nConsultTransferred','nConsult')) {
            $row[$name] = if ($profile.MetricSums.ContainsKey($name)) { $profile.MetricSums[$name] } else { $null }
        }
        foreach ($name in @('tUserResponseTime','tAgentResponseTime')) {
            $key = if ($name -eq 'tUserResponseTime') { 'AvgUserResponseSec' } else { 'AvgAgentResponseSec' }
            $row[$key] = if ($profile.MetricCounts.ContainsKey($name) -and $profile.MetricCounts[$name] -gt 0) { $profile.MetricSums[$name] / $profile.MetricCounts[$name] / 1000.0 } else { $null }
        }
        $row.QueueCount = @($profile.QueueIds).Count
        $row.AgentCount = @($profile.AgentKeys).Count
        $row.MosSource = if ($null -ne $profile.ConversationMinMos) { 'conversation summary' } elseif ($null -ne $profile.EndpointMinMos) { 'endpoint minimum' } else { 'unavailable' }
        [pscustomobject]$row
    }
}

function Get-GenesysConversationAnalysis {
    <#
    .SYNOPSIS
    Collects a conversation population through Core and exports an interactive Ops report.
    .DESCRIPTION
    Queue/User filters use segment predicates, Division uses conversation predicates.
    QueryBody accepts a custom analytics details body, without interval. It cannot be
    combined with named filters. Since/Until define the collection interval in UTC.
    InputObject imports offline records without claiming live completeness.
    DatasetInvoker is an offline seam returning Records, Events, Status and EvidencePath.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Collect')]
    param(
        [Parameter(Mandatory)][datetimeoffset]$Since,
        [Parameter(Mandatory)][datetimeoffset]$Until,
        [Parameter(ParameterSetName = 'Collect')][string[]]$QueueId = @(),
        [Parameter(ParameterSetName = 'Collect')][string[]]$UserId = @(),
        [Parameter(ParameterSetName = 'Collect')][string[]]$DivisionId = @(),
        [Parameter(ParameterSetName = 'Collect')][string[]]$MediaType = @(),
        [Parameter(ParameterSetName = 'Collect')][hashtable]$QueryBody,
        [Parameter(ParameterSetName = 'Offline', Mandatory)][AllowEmptyCollection()][object[]]$InputObject,
        [Parameter(ParameterSetName = 'Collect')][scriptblock]$DatasetInvoker,
        [Parameter(ParameterSetName = 'Collect')][scriptblock]$RequestInvoker,
        [switch]$ResolveEntityNames,
        [scriptblock]$EntityLookupInvoker,
        [string]$OutputRoot = 'out',
        [switch]$OpenReport
    )
    if ($ResolveEntityNames -and $PSCmdlet.ParameterSetName -eq 'Offline' -and -not $EntityLookupInvoker) { throw 'Offline name resolution requires EntityLookupInvoker; no live lookup is inferred.' }
    if ($ResolveEntityNames -and $DatasetInvoker -and -not $EntityLookupInvoker) { throw 'Synthetic collection with name resolution requires EntityLookupInvoker.' }
    if ($Until -le $Since) { throw 'Until must be later than Since.' }
    $QueueId = @($QueueId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $UserId = @($UserId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $DivisionId = @($DivisionId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $MediaType = @($MediaType | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $interval = "$($Since.UtcDateTime.ToString('o'))/$($Until.UtcDateTime.ToString('o'))"
    $body = @{ interval = $interval; order = 'asc'; orderBy = 'conversationStart' }
    if ($QueryBody) {
        if ($QueueId.Count -or $UserId.Count -or $DivisionId.Count -or $MediaType.Count) { throw 'QueryBody cannot be combined with named filters.' }
        if ($QueryBody.ContainsKey('interval')) { throw 'Omit interval from QueryBody; Since and Until define it.' }
        foreach ($key in $QueryBody.Keys) { $body[$key] = $QueryBody[$key] }
    }
    else {
        $segments = [System.Collections.Generic.List[object]]::new()
        $conversations = [System.Collections.Generic.List[object]]::new()
        foreach ($spec in @(@{ dimension = 'queueId'; values = $QueueId }, @{ dimension = 'userId'; values = $UserId },
            @{ dimension = 'mediaType'; values = $MediaType }, @{ dimension = 'divisionId'; values = $DivisionId })) {
            if (@($spec.values).Count -eq 0) { continue }
            $filter = @{ type = 'or'; predicates = @($spec.values | ForEach-Object { @{ type = 'dimension'; dimension = $spec.dimension; operator = 'matches'; value = $_ } }) }
            if ($spec.dimension -eq 'divisionId') { $conversations.Add($filter) } else { $segments.Add($filter) }
        }
        if ($segments.Count) { $body.segmentFilters = $segments.ToArray() }
        if ($conversations.Count) { $body.conversationFilters = $conversations.ToArray() }
    }
    $startedAtUtc = [datetime]::UtcNow.ToString('o')
    $gitSha = $null
    $runId = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $folder = [IO.Path]::GetFullPath((Join-Path $OutputRoot "conversation-analysis/$runId"))
    $null = New-Item -ItemType Directory -Path $folder -Force
    $warnings = [System.Collections.Generic.List[string]]::new()
    $phaseClock = [Diagnostics.Stopwatch]::StartNew(); $performance = [ordered]@{}
    $events = @(); $evidencePath = $null; $status = 'unverified'; $records = @()
    if ($PSCmdlet.ParameterSetName -eq 'Offline') {
        $records = $InputObject
        $warnings.Add('Imported records: collection completeness, permissions, and interval membership are unverified.')
    }
    elseif ($DatasetInvoker) {
        $result = & $DatasetInvoker -Dataset 'analytics-conversation-details' -Body $body -OutputRoot (Join-Path $folder 'core')
        $records = @(Get-GcVolumeProperty $result 'Records' @())
        $events = @(Get-GcVolumeProperty $result 'Events' @())
        $status = [string](Get-GcVolumeProperty $result 'Status' 'unverified')
        if ($status -notin @('complete','partial','unverified')) { throw 'Invalid fixture status.' }
        $evidencePath = Get-GcVolumeProperty $result 'EvidencePath'
    }
    else {
        if (-not $RequestInvoker) { Assert-GenesysConnected }
        $arguments = @{ Dataset = 'analytics-conversation-details'; DatasetParameters = @{ Body = $body; PreserveUserIds = [bool]$ResolveEntityNames }; OutputRoot = (Join-Path $folder 'core'); BaseUri = $script:GC.BaseUri; Headers = $script:GC.Headers }
        if ($script:GC.CatalogPath) { $arguments.CatalogPath = $script:GC.CatalogPath }
        if ($RequestInvoker) { $arguments.RequestInvoker = $RequestInvoker }
        $context = Invoke-Dataset @arguments
        $gitSha = Get-GcVolumeProperty (Get-Content $context.manifestPath -Raw | ConvertFrom-Json) 'gitSha'
        $evidencePath = $context.runFolder.Substring($folder.Length + 1).Replace('\', '/')
        $collected = [System.Collections.Generic.List[object]]::new()
        foreach ($file in @(Get-ChildItem $context.dataFolder -Filter '*.jsonl')) {
            foreach ($line in [IO.File]::ReadLines($file.FullName)) { if ($line.Trim()) { $collected.Add(($line | ConvertFrom-Json)) } }
        }
        $records = $collected.ToArray()
        $events = @(Get-Content $context.eventsPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
        $status = 'complete'
    }
    $events = @($events | ForEach-Object {
        $payload = Get-GcVolumeProperty $_ 'payload'
        if ($null -ne $payload -and $null -ne (Get-GcVolumeProperty $payload 'eventType')) { $payload } else { $_ }
    })
    if (@($events | Where-Object { (Get-GcVolumeProperty $_ 'eventType' '') -like 'paging.terminated.*' }).Count) {
        $status = 'partial'; $warnings.Add('Paging reached a safety limit or repeated cursor; results are partial.')
    }
    $performance.collectionMs = $phaseClock.ElapsedMilliseconds; $phaseClock.Restart()
    $rows = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $duplicates = 0; $missingIds = 0
    foreach ($record in $records) {
        $id = [string](Get-GcVolumeProperty $record 'conversationId' '')
        if ([string]::IsNullOrWhiteSpace($id)) { $missingIds++; continue }
        if (-not $ids.Add($id)) { $duplicates++; continue }
        $rows.Add((Get-GenesysConversationProfile -InputObject $record))
    }
    if ($missingIds) { $status = 'partial'; $warnings.Add("$missingIds record(s) lacked a conversation ID and were excluded.") }
    if ($duplicates) { $warnings.Add("$duplicates duplicate ID(s) excluded; first returned record retained. Duplicates may contain differing evidence.") }
    $performance.profilingMs = $phaseClock.ElapsedMilliseconds; $phaseClock.Restart()
    $resolution = Resolve-GcConversationEntities -Profiles $rows.ToArray() -OutputRoot (Join-Path $folder 'entities') -Enabled:$ResolveEntityNames -LookupInvoker $EntityLookupInvoker -RequestInvoker $RequestInvoker
    foreach ($warning in $resolution.warnings) { $warnings.Add($warning) }
    $performance.entityResolutionMs = $phaseClock.ElapsedMilliseconds; $phaseClock.Restart()
    $numericFields = @('AvgDiscardedPackets','MaxDiscardedPackets','DiscardedPacketSamples','DurationSec','MinMos','EndpointMinMos','ConversationMinMos','MinRFactor','MaxLatencyMs','TransferCount','QueueCount',
        'AgentCount','UserCount','HoldCount','ErrorSegmentCount','ParticipantCount','FlowOutcomes','FlowOutcomeFailures','EvaluationCount','EvalScore',
        'SurveyCount','SurveyScore','NpsScore','ResolutionCount','AvgUserResponseSec','AvgAgentResponseSec',
        'tAnsweredSec','tAbandonSec','tShortAbandonSec','tAcdSec','tWaitSec','tIvrSec','tFlowSec','tAlertSec','tNotRespondingSec',
        'tDialingSec','tContactingSec','tTalkSec','tHeldSec','tAcwSec','tHandleSec','tVoicemailSec',
        'nConnected','nOffered','nOverSla','nOutbound','nError','nTransferred','nBlindTransferred','nConsultTransferred','nConsult')
    $statistics = [ordered]@{}
    foreach ($field in $numericFields) {
        $values = @($rows | ForEach-Object { if ($null -ne $_.$field) { [double]$_.$field } })
        $measurement = $values | Measure-Object -Average -Minimum -Maximum -Sum
        $statistics[$field] = @{ validCount = $values.Count; missingCount = $rows.Count - $values.Count; average = $measurement.Average; min = $measurement.Minimum; max = $measurement.Maximum; sum = if ($values.Count) { $measurement.Sum } else { $null } }
    }
    $performance.statisticsMs = $phaseClock.ElapsedMilliseconds; $phaseClock.Stop()
    $scope = @{ sinceUtc = $Since.UtcDateTime.ToString('o'); untilUtc = $Until.UtcDateTime.ToString('o'); interval = $interval; queueIds = $QueueId; userIds = $UserId; divisionIds = $DivisionId; mediaTypes = $MediaType }
    $bundle = [pscustomobject]@{
        schemaVersion = 1; kind = 'genesys-conversation-analysis'; profileDefinitionVersion = 1
        runId = $runId; generatedAtUtc = [datetime]::UtcNow.ToString('o'); scope = $scope; request = $body
        coverage = @{ status = $status; evidenceMode = if ($PSCmdlet.ParameterSetName -eq 'Offline') { 'imported-unverified' } elseif ($DatasetInvoker -or $RequestInvoker) { 'synthetic' } else { 'platform-unverified' }; rawRows = @($records).Count; distinctConversations = $rows.Count; duplicateRows = $duplicates; missingIds = $missingIds; evidencePath = $evidencePath; pageCount = @($events | Where-Object { (Get-GcVolumeProperty $_ 'eventType') -eq 'paging.progress' -and (Get-GcVolumeProperty $_ 'profile') -eq 'cursor' }).Count }
        definitions = @{ numericFields = $numericFields; packets = 'AvgDiscardedPackets averages non-null endpoint-stat observations within each conversation. Population average is one such value per conversation; samples may overlap. Discarded is not network packet loss; overrun/underrun are already included and must not be added again.'; countUnit = 'distinct conversation IDs'; averageUnit = 'one non-null value per conversation'; nullPolicy = 'Exclude missing values from numeric calculations; retain valid and missing counts.'; mos = 'MinMos prefers conversation summary, falls back to endpoint minimum; EndpointMinMos uses mediaEndpointStats.minMos only.'; agentMetrics = 'Agent-work metrics are summed only from agent/user participants; seconds fields convert milliseconds.'; transferCount = 'Maximum of nTransferred, nBlindTransferred, nConsultTransferred sums, following supplied reference; components retained separately.'; errors = 'One event per segment with a non-empty errorCode. Conversation membership is deduplicated per code; occurrences are not.' }
        performance = $performance
        entityResolution = $resolution
        profiles = @($rows.ToArray()); statistics = $statistics; warnings = @($warnings.ToArray()); runFolder = $folder
    }
    $analysisJson = $bundle | ConvertTo-Json -Depth 60 -Compress
    $analysisJson | Set-Content (Join-Path $folder 'analysis.json') -Encoding utf8
    @{ datasetKey = 'conversation-analysis'; runId = $runId; startedAtUtc = $startedAtUtc; endedAtUtc = $bundle.generatedAtUtc; gitSha = $gitSha; scope = $scope; counts = @{ itemCount = $rows.Count }; coverage = $bundle.coverage; warnings = $bundle.warnings } | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $folder 'manifest.json') -Encoding utf8
    $dataFolder = Join-Path $folder 'data'; $null = New-Item -ItemType Directory -Path $dataFolder
    $writer = [IO.StreamWriter]::new((Join-Path $dataFolder 'profiles.jsonl'), $false, [Text.UTF8Encoding]::new($false))
    try { foreach ($row in $rows) { $writer.WriteLine(($row | ConvertTo-Json -Depth 40 -Compress)) } } finally { $writer.Dispose() }
    foreach ($event in $events) { $event | ConvertTo-Json -Depth 30 -Compress | Add-Content (Join-Path $folder 'events.jsonl') -Encoding utf8 }
    if (-not $events.Count) { Set-Content (Join-Path $folder 'events.jsonl') -Value '' -Encoding utf8 }
    $templatePath = Join-Path $PSScriptRoot '../../apps/ConversationAnalysis/Investigation.html'
    $template = Get-Content $templatePath -Raw
    $engine = Get-Content (Join-Path (Split-Path $templatePath -Parent) 'population.js') -Raw
    $template = $template.Replace('<script src="population.js"></script>', "<script>$engine</script>")
    $json = $analysisJson.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026')
    $template.Replace('/*__GC_ANALYSIS__*/null', $json) | Set-Content (Join-Path $folder 'report.html') -Encoding utf8
    $bundle | Select-Object schemaVersion, kind, runId, generatedAtUtc, scope, coverage, performance, entityResolution, definitions, statistics, warnings | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $folder 'summary.json') -Encoding utf8
    if ($OpenReport) { Invoke-Item (Join-Path $folder 'report.html') }
    return $bundle
}
