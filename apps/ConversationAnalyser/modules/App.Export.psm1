#Requires -Version 5.1
Set-StrictMode -Version Latest

# ── Export module ─────────────────────────────────────────────────────────────
# Export-RunToCsv streams file-by-file, line-by-line using StreamReader.
# No full dataset is loaded into memory.
# ─────────────────────────────────────────────────────────────────────────────

function Get-ConversationDisplayRow {
    <#
    .SYNOPSIS
        Returns a lightweight display object from an index entry (used for DataGrid binding).
    #>
    param(
        [Parameter(Mandatory)][object]$IndexEntry
    )
    return [pscustomobject]@{
        ConversationId   = $IndexEntry.id
        Direction        = $IndexEntry.direction
        MediaType        = $IndexEntry.mediaType
        Queue            = $IndexEntry.queue
        Disconnect       = $IndexEntry.disconnect
        DurationSec      = $IndexEntry.durationSec
        HasHold          = $IndexEntry.hasHold
        HasMos           = $IndexEntry.hasMos
        SegmentCount     = $IndexEntry.segmentCount
        ParticipantCount = $IndexEntry.participantCount
    }
}

function _GetAttributeColumnNamesFromRecord {
    param([Parameter(Mandatory)][object]$Record)

    if (-not $Record.PSObject.Properties['attributes']) { return @() }
    $attrs = $Record.attributes
    if ($null -eq $attrs) { return @() }

    return @($attrs.PSObject.Properties |
        ForEach-Object { "attr_$($_.Name)" } |
        Sort-Object -Unique)
}

function ConvertTo-FlatRow {
    <#
    .SYNOPSIS
        Converts a full Genesys conversation detail record to a flat hashtable.
        Optionally includes conversation attributes as attr_* columns.
    #>
    param(
        [Parameter(Mandatory)][object]$Record,
        [switch]$IncludeAttributes,
        [string[]]$AttributeColumns = @()
    )

    $row = [ordered]@{}

    # Core identity + timing
    $row['conversationId']    = if ($Record.PSObject.Properties['conversationId'])    { $Record.conversationId }    else { '' }
    $row['conversationStart'] = if ($Record.PSObject.Properties['conversationStart']) { $Record.conversationStart } else { '' }
    $row['conversationEnd']   = if ($Record.PSObject.Properties['conversationEnd'])   { $Record.conversationEnd }   else { '' }

    $durationSec = 0
    if ($Record.PSObject.Properties['conversationStart'] -and
        $Record.PSObject.Properties['conversationEnd']) {
        try {
            $s = [datetime]::Parse($Record.conversationStart)
            $e = [datetime]::Parse($Record.conversationEnd)
            $durationSec = [int]($e - $s).TotalSeconds
        } catch { }
    }
    $row['durationSec'] = $durationSec

    # Rollup fields
    $direction    = ''
    $mediaType    = ''
    $queue        = ''
    $queueId      = ''
    $disconnect   = ''
    $agentCount   = 0
    $holdCount    = 0
    $holdDurSec   = 0
    $transferCount = 0
    $mosMin       = $null
    $mosMax       = $null
    $mosSum       = 0.0
    $mosSamples   = 0
    $partCount    = 0

    if ($Record.PSObject.Properties['participants']) {
        $parts     = @($Record.participants)
        $partCount = $parts.Count
        foreach ($p in $parts) {
            $isCustomer = ($p.PSObject.Properties['purpose'] -and $p.purpose -eq 'customer')
            $isAgent    = ($p.PSObject.Properties['purpose'] -and $p.purpose -eq 'agent')
            if ($isAgent) { $agentCount++ }

            if (-not $p.PSObject.Properties['sessions']) { continue }
            foreach ($s in @($p.sessions)) {
                if (-not $mediaType -and $s.PSObject.Properties['mediaType']) {
                    $mediaType = $s.mediaType
                }
                if ($isCustomer -and -not $direction -and $s.PSObject.Properties['direction']) {
                    $direction = $s.direction
                }
                # MOS metrics
                if ($s.PSObject.Properties['metrics']) {
                    foreach ($m in @($s.metrics)) {
                        if ($m.PSObject.Properties['name'] -and $m.PSObject.Properties['stats']) {
                            if ($m.name -like '*mos*' -or $m.name -like '*Mos*') {
                                $st = $m.stats
                                if ($st.PSObject.Properties['min']) {
                                    $v = [double]$st.min
                                    if ($null -eq $mosMin -or $v -lt $mosMin) { $mosMin = $v }
                                }
                                if ($st.PSObject.Properties['max']) {
                                    $v = [double]$st.max
                                    if ($null -eq $mosMax -or $v -gt $mosMax) { $mosMax = $v }
                                }
                                if ($st.PSObject.Properties['sum'] -and $st.PSObject.Properties['count']) {
                                    $mosSum     += [double]$st.sum
                                    $mosSamples += [int]$st.count
                                }
                            }
                        }
                    }
                }
                if (-not $s.PSObject.Properties['segments']) { continue }
                foreach ($seg in @($s.segments)) {
                    if ($seg.PSObject.Properties['disconnectType'] -and -not $disconnect) {
                        $disconnect = $seg.disconnectType
                    }
                    if ($seg.PSObject.Properties['queueName'] -and -not $queue) {
                        $queue = $seg.queueName
                    }
                    if ($seg.PSObject.Properties['queueId'] -and -not $queueId) {
                        $queueId = $seg.queueId
                    }
                    if ($seg.PSObject.Properties['segmentType']) {
                        if ($seg.segmentType -eq 'hold') {
                            $holdCount++
                            if ($seg.PSObject.Properties['segmentStart'] -and
                                $seg.PSObject.Properties['segmentEnd']) {
                                try {
                                    $hs = [datetime]::Parse($seg.segmentStart)
                                    $he = [datetime]::Parse($seg.segmentEnd)
                                    $holdDurSec += [int]($he - $hs).TotalSeconds
                                } catch { }
                            }
                        }
                        if ($seg.segmentType -eq 'transfer') { $transferCount++ }
                    }
                }
            }
        }
    }

    $row['direction']       = $direction
    $row['mediaType']       = $mediaType
    $row['queueId']         = $queueId
    $row['queueName']       = $queue
    $row['disconnectType']  = $disconnect
    $row['participantCount'] = $partCount
    $row['agentCount']      = $agentCount
    $row['holdCount']       = $holdCount
    $row['holdDurationSec'] = $holdDurSec
    $row['transferCount']   = $transferCount
    $row['mosMin']          = if ($null -ne $mosMin) { [math]::Round($mosMin, 3) } else { '' }
    $row['mosMax']          = if ($null -ne $mosMax) { [math]::Round($mosMax, 3) } else { '' }
    $row['mosMean']         = if ($mosSamples -gt 0) { [math]::Round($mosSum / $mosSamples, 3) } else { '' }

    # Optional attribute flattening
    if ($IncludeAttributes) {
        $attributeMap = @{}
        if ($Record.PSObject.Properties['attributes']) {
            $attrs = $Record.attributes
            if ($null -ne $attrs) {
                foreach ($prop in $attrs.PSObject.Properties) {
                    $attributeMap["attr_$($prop.Name)"] = $prop.Value
                }
            }
        }

        $columns = @($AttributeColumns)
        if ($columns.Count -eq 0) {
            $columns = @($attributeMap.Keys | Sort-Object)
        }

        foreach ($column in $columns) {
            if ($attributeMap.ContainsKey($column)) {
                $row[$column] = $attributeMap[$column]
            } else {
                $row[$column] = ''
            }
        }
    }

    return $row
}

function Export-PageToCsv {
    <#
    .SYNOPSIS
        Exports an array of conversation records (already retrieved from index) to a CSV file.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Records,
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$IncludeAttributes
    )

    $attributeColumns = @()
    if ($IncludeAttributes) {
        $attributeColumns = @($Records |
            ForEach-Object { _GetAttributeColumnNamesFromRecord -Record $_ } |
            Sort-Object -Unique)
    }

    $rows = foreach ($r in $Records) {
        [pscustomobject](ConvertTo-FlatRow -Record $r -IncludeAttributes:$IncludeAttributes -AttributeColumns $attributeColumns)
    }
    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
}

function Export-RunToCsv {
    <#
    .SYNOPSIS
        Streams all data\*.jsonl files in the run folder line-by-line and writes a CSV.
        Never loads the full dataset into memory.
    #>
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$IncludeAttributes
    )
    $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
    if (-not [System.IO.Directory]::Exists($dataDir)) {
        throw "No data directory found at: $dataDir"
    }

    $dataFiles = [System.IO.Directory]::GetFiles($dataDir, '*.jsonl') | Sort-Object

    $outFs = [System.IO.FileStream]::new(
        $OutputPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    $outSw = [System.IO.StreamWriter]::new(
        $outFs,
        (New-Object System.Text.UTF8Encoding($true)))  # UTF-8 with BOM for Excel compat

    $attributeColumns = @()
    if ($IncludeAttributes) {
        $attrSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($dataFile in $dataFiles) {
            $scanFs = [System.IO.FileStream]::new(
                $dataFile,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read)
            $scanSr = [System.IO.StreamReader]::new($scanFs, [System.Text.Encoding]::UTF8)
            try {
                while (-not $scanSr.EndOfStream) {
                    $line = $scanSr.ReadLine()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    try {
                        $record = $line | ConvertFrom-Json
                        foreach ($column in @(_GetAttributeColumnNamesFromRecord -Record $record)) {
                            $attrSet.Add($column) | Out-Null
                        }
                    } catch { }
                }
            } finally {
                $scanSr.Dispose()
                $scanFs.Dispose()
            }
        }
        $attributeColumns = @($attrSet.GetEnumerator() | ForEach-Object { $_ } | Sort-Object)
    }

    $headerWritten = $false
    try {
        foreach ($dataFile in $dataFiles) {
            $inFs = [System.IO.FileStream]::new(
                $dataFile,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read)
            $inSr = [System.IO.StreamReader]::new($inFs, [System.Text.Encoding]::UTF8)
            try {
                while (-not $inSr.EndOfStream) {
                    $line = $inSr.ReadLine()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    try {
                        $record = $line | ConvertFrom-Json
                        $row    = ConvertTo-FlatRow -Record $record -IncludeAttributes:$IncludeAttributes -AttributeColumns $attributeColumns

                        if (-not $headerWritten) {
                            $header = ($row.Keys | ForEach-Object { _QuoteCsvField $_ }) -join ','
                            $outSw.WriteLine($header)
                            $headerWritten = $true
                        }

                        $csvLine = ($row.Values | ForEach-Object { _QuoteCsvField ([string]$_) }) -join ','
                        $outSw.WriteLine($csvLine)
                    } catch { <# skip malformed records #> }
                }
            } finally {
                $inSr.Dispose()
                $inFs.Dispose()
            }
        }
    } finally {
        $outSw.Dispose()
        $outFs.Dispose()
    }
}

function _QuoteCsvField {
    param([string]$Value)
    if ($Value -match '[,"\r\n]') {
        return '"' + $Value.Replace('"', '""') + '"'
    }
    return $Value
}

function Export-ConversationToJson {
    <#
    .SYNOPSIS
        Serializes a single conversation record to a JSON file.
    #>
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][string]$OutputPath
    )
    $json = $Record | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)
}

function Get-DbConversationDisplayRow {
    <#
    .SYNOPSIS
        Returns a lightweight display object from a SQLite conversations-table row (DataGrid binding).
        Maps snake_case DB column names to the same PascalCase shape as Get-ConversationDisplayRow.
    #>
    param([Parameter(Mandatory)][object]$DbRow)

    $get = {
        param([string]$k, $d = '')
        if ($DbRow -is [hashtable]) {
            $v = $DbRow[$k]
        } else {
            $prop = $DbRow.PSObject.Properties[$k]
            $v    = if ($null -ne $prop) { $prop.Value } else { $null }
        }
        if ($null -eq $v) { return $d } else { return $v }
    }

    return [pscustomobject]@{
        ConversationId    = (& $get 'conversation_id'    '')
        Direction         = (& $get 'direction'          '')
        MediaType         = (& $get 'media_type'         '')
        Queue             = (& $get 'queue_name'         '')
        Disconnect        = (& $get 'disconnect_type'    '')
        DurationSec       = [int]  (& $get 'duration_sec'      0)
        HasHold           = [bool] ([int](& $get 'has_hold'     0))
        HasMos            = [bool] ([int](& $get 'has_mos'      0))
        SegmentCount      = [int]  (& $get 'segment_count'      0)
        ParticipantCount  = [int]  (& $get 'participant_count'  0)
        AgentNames        = (& $get 'agent_names'        '')
        ConversationStart = (& $get 'conversation_start' '')
    }
}

Export-ModuleMember -Function `
    ConvertTo-FlatRow, Export-PageToCsv, Export-RunToCsv, `
    Export-ConversationToJson, Get-ConversationDisplayRow, Get-DbConversationDisplayRow
