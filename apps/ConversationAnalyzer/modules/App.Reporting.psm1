#Requires -Version 5.1
Set-StrictMode -Version Latest

function _GetReportRowValues {
    param(
        [Parameter(Mandatory)][object]$Row,
        [Parameter(Mandatory)][string[]]$Names,
        [string]$Separator = '|'
    )

    foreach ($name in $Names) {
        $prop = $Row.PSObject.Properties[$name]
        if ($null -eq $prop) { continue }
        $value = $prop.Value
        if ($null -eq $value) { continue }

        if ($value -is [System.Array] -or $value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            return @($value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }

        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text.Contains($Separator)) {
            return @($text.Split($Separator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        return @($text)
    }

    return @()
}

function _GetReportRowScalar {
    param(
        [Parameter(Mandatory)][object]$Row,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        $prop = $Row.PSObject.Properties[$name]
        if ($null -eq $prop) { continue }
        $value = $prop.Value
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return $value
        }
    }

    return $null
}

function New-ImpactReport {
    <#
    .SYNOPSIS
        Generates aggregate impact rollups for the currently filtered run index.
    #>
    param(
        [Parameter(Mandatory)][object[]]$FilteredIndex,
        [string]$ReportTitle = 'Conversation Impact Report'
    )

    if ($null -eq $FilteredIndex) { $FilteredIndex = @() }
    $rows = @($FilteredIndex)
    $generatedAt = [datetime]::UtcNow.ToString('o')

    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            ReportTitle         = $ReportTitle
            GeneratedAt         = $generatedAt
            TotalConversations  = 0
            Message             = 'No conversations found in the current filter to generate a report.'
            TimeWindow          = $null
            ImpactByDivision    = @()
            ImpactByQueue       = @()
            AffectedAgents      = @()
            DirectionBreakdown  = @()
            MediaTypeBreakdown  = @()
        }
    }

    # Guard every property that may be absent on older index entries (pre-v2 index.jsonl
    # files do not contain divisionIds / queueIds / userIds / conversationStart).
    # With Set-StrictMode -Version Latest, accessing a missing property throws;
    # the PSObject.Properties check prevents that.

    $impactByDivision = $rows |
        ForEach-Object { @(_GetReportRowValues -Row $_ -Names @('divisionIds','division_ids')) } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Group-Object |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                DivisionId = $_.Name
                Count      = $_.Count
            }
        }

    $impactByQueue = $rows |
        ForEach-Object { @(_GetReportRowValues -Row $_ -Names @('queueIds','queue_name','primary_queue','final_queue')) } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Group-Object |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                QueueId = $_.Name
                Count   = $_.Count
            }
        }

    $affectedAgents = $rows |
        ForEach-Object { @(_GetReportRowValues -Row $_ -Names @('userIds','agent_names')) } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Group-Object |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                AgentId = $_.Name
                Count   = $_.Count
            }
        }

    $directionBreakdown = $rows |
        ForEach-Object {
            $direction = _GetReportRowScalar -Row $_ -Names @('direction')
            if ($null -ne $direction) { [pscustomobject]@{ Direction = [string]$direction } }
        } |
        Group-Object Direction |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                Direction = $_.Name
                Count     = $_.Count
            }
        }

    $mediaTypeBreakdown = $rows |
        ForEach-Object {
            $mediaType = _GetReportRowScalar -Row $_ -Names @('mediaType','media_type')
            if ($null -ne $mediaType) { [pscustomobject]@{ MediaType = [string]$mediaType } }
        } |
        Group-Object MediaType |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                MediaType = $_.Name
                Count     = $_.Count
            }
        }

    $conversationStarts = @($rows |
        ForEach-Object {
            $value = _GetReportRowScalar -Row $_ -Names @('conversationStart','conversation_start')
            if ($null -eq $value) { return $null }
            try {
                if ($value -is [datetimeoffset]) {
                    return $value.ToUniversalTime()
                }
                if ($value -is [datetime]) {
                    if ($value.Kind -eq [System.DateTimeKind]::Utc) {
                        return [datetimeoffset]::new($value, [System.TimeSpan]::Zero)
                    }
                    if ($value.Kind -eq [System.DateTimeKind]::Local) {
                        return [datetimeoffset]$value
                    }
                }
                return [datetimeoffset]::Parse([string]$value)
            } catch {
                return $null
            }
        } |
        Where-Object { $null -ne $_ } |
        Sort-Object)

    $timeWindow = $null
    if ($conversationStarts.Count -gt 0) {
        $timeWindow = [pscustomobject]@{
            Start = $conversationStarts[0].UtcDateTime.ToString('o')
            End   = $conversationStarts[$conversationStarts.Count - 1].UtcDateTime.ToString('o')
        }
    }

    return [pscustomobject]@{
        ReportTitle         = $ReportTitle
        GeneratedAt         = $generatedAt
        TotalConversations  = $rows.Count
        TimeWindow          = $timeWindow
        ImpactByDivision    = @($impactByDivision)
        ImpactByQueue       = @($impactByQueue)
        AffectedAgents      = @($affectedAgents)
        DirectionBreakdown  = @($directionBreakdown)
        MediaTypeBreakdown  = @($mediaTypeBreakdown)
    }
}

function New-PopulationReport {
    <#
    .SYNOPSIS
        Generates a defensible full-population report from a SQL-filtered
        conversation population, including exact filter state and provenance.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][object]$FilterState,
        [object]$Summary = $null,
        [object]$Facets = $null,
        [object[]]$Representatives = @(),
        [object[]]$Cohorts = @(),
        [object]$Provenance = $null,
        [string]$ReportTitle = 'Conversation Population Report'
    )

    $rows = @($Rows)
    $impact = New-ImpactReport -FilteredIndex $rows -ReportTitle $ReportTitle

    $topQueues = @()
    if ($Facets -and $Facets.PSObject.Properties['queue']) {
        $topQueues = @($Facets.queue)
    } else {
        $topQueues = @($rows |
            Where-Object { $_.PSObject.Properties['queue_name'] -and $_.queue_name } |
            Group-Object queue_name |
            Sort-Object @{Expression='Count';Descending=$true}, Name |
            Select-Object -First 20 |
            ForEach-Object { [pscustomobject]@{ value = $_.Name; count = $_.Count } })
    }

    $topSignatures = @()
    if ($Facets -and $Facets.PSObject.Properties['conversation_signature']) {
        $topSignatures = @($Facets.conversation_signature)
    } else {
        $topSignatures = @($rows |
            Where-Object { $_.PSObject.Properties['conversation_signature'] -and $_.conversation_signature } |
            Group-Object conversation_signature |
            Sort-Object @{Expression='Count';Descending=$true}, Name |
            Select-Object -First 20 |
            ForEach-Object { [pscustomobject]@{ value = $_.Name; count = $_.Count } })
    }

    return [pscustomobject][ordered]@{
        ReportType          = 'Population'
        ReportTitle         = $ReportTitle
        GeneratedAt         = [datetime]::UtcNow.ToString('o')
        ExactFilterState    = $FilterState
        Provenance          = $Provenance
        TotalConversations  = $impact.TotalConversations
        TimeWindow          = $impact.TimeWindow
        Summary             = $Summary
        Facets              = $Facets
        Cohorts             = @($Cohorts)
        RepresentativeConversations = @($Representatives | ForEach-Object {
            [pscustomobject]@{
                conversation_id = if ($_.PSObject.Properties['conversation_id']) { $_.conversation_id } else { '' }
                conversation_start = if ($_.PSObject.Properties['conversation_start']) { $_.conversation_start } else { '' }
                direction = if ($_.PSObject.Properties['direction']) { $_.direction } else { '' }
                media_type = if ($_.PSObject.Properties['media_type']) { $_.media_type } else { '' }
                queue_name = if ($_.PSObject.Properties['queue_name']) { $_.queue_name } else { '' }
                duration_sec = if ($_.PSObject.Properties['duration_sec']) { $_.duration_sec } else { 0 }
                transfer_count = if ($_.PSObject.Properties['transfer_count']) { $_.transfer_count } else { 0 }
                hold_duration_sec = if ($_.PSObject.Properties['hold_duration_sec']) { $_.hold_duration_sec } else { 0 }
                risk_score = if ($_.PSObject.Properties['risk_score']) { $_.risk_score } else { 0 }
                anomaly_flags = if ($_.PSObject.Properties['anomaly_flags']) { $_.anomaly_flags } else { '' }
            }
        })
        TopQueues           = @($topQueues)
        TopConversationSignatures = @($topSignatures)
        DirectionBreakdown  = $impact.DirectionBreakdown
        MediaTypeBreakdown  = $impact.MediaTypeBreakdown
        LegacyImpactRollup  = $impact
    }
}

function New-ConversationDossier {
    <#
    .SYNOPSIS
        Generates a single-conversation dossier with canonical raw payload and derived detail.
    #>
    param(
        [Parameter(Mandatory)][object]$ConversationRow,
        [object[]]$Versions = @(),
        [string]$ReportTitle = 'Conversation Dossier'
    )

    return [pscustomobject][ordered]@{
        ReportType = 'ConversationDossier'
        ReportTitle = $ReportTitle
        GeneratedAt = [datetime]::UtcNow.ToString('o')
        ConversationId = if ($ConversationRow.PSObject.Properties['conversation_id']) { $ConversationRow.conversation_id } else { '' }
        Derived = $ConversationRow
        CanonicalRawJson = if ($ConversationRow.PSObject.Properties['raw_json']) { $ConversationRow.raw_json } else { $null }
        Versions = @($Versions)
    }
}

Export-ModuleMember -Function New-ImpactReport, New-PopulationReport, New-ConversationDossier
