#Requires -Version 5.1
Set-StrictMode -Version Latest

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
        Where-Object { $_.PSObject.Properties['divisionIds'] -and @($_.divisionIds).Count -gt 0 } |
        ForEach-Object { @($_.divisionIds) } |
        Group-Object |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                DivisionId = $_.Name
                Count      = $_.Count
            }
        }

    $impactByQueue = $rows |
        Where-Object { $_.PSObject.Properties['queueIds'] -and @($_.queueIds).Count -gt 0 } |
        ForEach-Object { @($_.queueIds) } |
        Group-Object |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                QueueId = $_.Name
                Count   = $_.Count
            }
        }

    $affectedAgents = $rows |
        Where-Object { $_.PSObject.Properties['userIds'] -and @($_.userIds).Count -gt 0 } |
        ForEach-Object { @($_.userIds) } |
        Group-Object |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                AgentId = $_.Name
                Count   = $_.Count
            }
        }

    $directionBreakdown = $rows |
        Where-Object { $_.PSObject.Properties['direction'] -and $_.direction } |
        Group-Object direction |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                Direction = $_.Name
                Count     = $_.Count
            }
        }

    $mediaTypeBreakdown = $rows |
        Where-Object { $_.PSObject.Properties['mediaType'] -and $_.mediaType } |
        Group-Object mediaType |
        Sort-Object @{Expression='Count';Descending=$true}, Name |
        ForEach-Object {
            [pscustomobject]@{
                MediaType = $_.Name
                Count     = $_.Count
            }
        }

    $conversationStarts = $rows |
        Where-Object { $_.PSObject.Properties['conversationStart'] -and $_.conversationStart } |
        ForEach-Object {
            $value = $_.conversationStart
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
        Sort-Object

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

Export-ModuleMember -Function New-ImpactReport
