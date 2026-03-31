#Requires -Version 5.1
Set-StrictMode -Version Latest

# ── Gate F ────────────────────────────────────────────────────────────────────
# App.Database.psm1 owns ALL SQLite interaction for the application.
# Only this module may:
#   - Load System.Data.SQLite
#   - Open SQLiteConnection objects
#   - Create or alter the application schema
#   - Read or write case, run, import, and conversation rows
#
# DLL resolution order:
#   1. SqliteDllPath parameter (from config)
#   2. SQLITE_DLL environment variable
#   3. .\lib\System.Data.SQLite.dll  (repo-relative default)
#
# Schema version: 2
# Reserved future tables (not created here): participants, segments
# ─────────────────────────────────────────────────────────────────────────────

$script:DbInitialized = $false
$script:ConnStr       = $null
$script:SchemaVersion = 4

# ── Private: DLL resolution ───────────────────────────────────────────────────

function _ResolveSqliteDll {
    param(
        [string]$ConfigPath = '',
        [string]$AppDir     = ''
    )
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($ConfigPath)    { $candidates.Add($ConfigPath) }
    if ($env:SQLITE_DLL){ $candidates.Add($env:SQLITE_DLL) }
    if ($AppDir) {
        $candidates.Add([System.IO.Path]::Combine($AppDir, 'lib', 'System.Data.SQLite.dll'))
    }

    foreach ($c in $candidates) {
        if ([System.IO.File]::Exists($c)) { return $c }
    }

    $tried = ($candidates.ToArray() | ForEach-Object { "  - $_" }) -join "`n"
    throw (
        "System.Data.SQLite.dll not found. Paths attempted:`n$tried`n`n" +
        "Resolution: drop System.Data.SQLite.dll into .\lib\  OR  " +
        "set env:SQLITE_DLL  OR  set SqliteDllPath in Settings."
    )
}

function _EnsureAssemblyLoaded {
    param([string]$DllPath)
    $already = [System.AppDomain]::CurrentDomain.GetAssemblies() |
               Where-Object { $_.GetName().Name -eq 'System.Data.SQLite' }
    if (-not $already) {
        Add-Type -Path $DllPath -ErrorAction Stop
    }
}

# ── Private: ADO.NET helpers ──────────────────────────────────────────────────

function _Open {
    $c = New-Object System.Data.SQLite.SQLiteConnection($script:ConnStr)
    $c.Open()
    return $c
}

function _Cmd {
    param(
        [System.Data.SQLite.SQLiteConnection]$Conn,
        [string]$Sql,
        [hashtable]$P = @{}
    )
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Sql
    foreach ($kv in $P.GetEnumerator()) {
        # NOTE: variable named $param (not $p) to avoid colliding with the
        # [hashtable]$P parameter — PowerShell variable names are case-insensitive,
        # so $p and $P are the same variable; assigning a SQLiteParameter to a
        # typed [hashtable] variable throws "Cannot convert ... to Hashtable".
        $param              = $cmd.CreateParameter()
        $param.ParameterName = $kv.Key
        $param.Value         = if ($null -eq $kv.Value) { [System.DBNull]::Value } else { $kv.Value }
        $cmd.Parameters.Add($param) | Out-Null
    }
    return $cmd
}

function _NonQuery {
    param(
        [System.Data.SQLite.SQLiteConnection]$Conn,
        [string]$Sql,
        [hashtable]$P = @{}
    )
    $cmd = _Cmd -Conn $Conn -Sql $Sql -P $P
    try   { return $cmd.ExecuteNonQuery() }
    finally { $cmd.Dispose() }
}

function _Scalar {
    param(
        [System.Data.SQLite.SQLiteConnection]$Conn,
        [string]$Sql,
        [hashtable]$P = @{}
    )
    $cmd = _Cmd -Conn $Conn -Sql $Sql -P $P
    try   { return $cmd.ExecuteScalar() }
    finally { $cmd.Dispose() }
}

function _Query {
    param(
        [System.Data.SQLite.SQLiteConnection]$Conn,
        [string]$Sql,
        [hashtable]$P = @{}
    )
    $cmd  = _Cmd -Conn $Conn -Sql $Sql -P $P
    $list = New-Object System.Collections.Generic.List[hashtable]
    $rdr  = $cmd.ExecuteReader()
    try {
        while ($rdr.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $rdr.FieldCount; $i++) {
                $v = $rdr.GetValue($i)
                $row[$rdr.GetName($i)] = if ($v -is [System.DBNull]) { $null } else { $v }
            }
            $list.Add($row)
        }
    } finally {
        $rdr.Dispose()
        $cmd.Dispose()
    }
    return $list.ToArray()
}

# Row value accessor – works with both [hashtable] and [pscustomobject].
function _RowVal {
    param([object]$Row, [string]$Key, $Default = '')
    if ($Row -is [hashtable]) {
        $v = $Row[$Key]
    } else {
        $prop = $Row.PSObject.Properties[$Key]
        $v    = if ($null -ne $prop) { $prop.Value } else { $null }
    }
    if ($null -eq $v) { return $Default }
    return $v
}

function _ObjVal {
    param(
        [object]$InputObject,
        [string[]]$Names,
        $Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($InputObject -is [hashtable]) {
            if ($InputObject.ContainsKey($name)) {
                $value = $InputObject[$name]
                if ($null -ne $value -and "$value" -ne '') { return $value }
            }
            continue
        }
        $prop = $InputObject.PSObject.Properties[$name]
        if ($null -ne $prop) {
            $value = $prop.Value
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }
    return $Default
}

function _ToJsonOrNull {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    try {
        return ($Value | ConvertTo-Json -Compress -Depth 20)
    } catch {
        return $null
    }
}

function _ReadJsonFile {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function _ReadJsonText {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return '' }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function _GetRelativePath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$FullPath
    )
    $hasGetRelative = [System.IO.Path].GetMethods() |
        Where-Object { $_.Name -eq 'GetRelativePath' -and $_.IsStatic }
    if ($hasGetRelative) {
        return [System.IO.Path]::GetRelativePath($BasePath, $FullPath)
    }
    $base = $BasePath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $base = $base + [System.IO.Path]::DirectorySeparatorChar
    if ($FullPath.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($base.Length)
    }
    return $FullPath
}

function _AddColumnIfMissing {
    <#
    .SYNOPSIS
        Adds a column to an existing table if it does not already exist.
        SQLite throws "duplicate column name" when ALTER TABLE ADD COLUMN targets
        an existing column; this helper ignores that specific error.
    #>
    param(
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteConnection]$Conn,
        [Parameter(Mandatory)][string]$Table,
        [Parameter(Mandatory)][string]$ColDef   # e.g. "agent_names TEXT NOT NULL DEFAULT ''"
    )
    try {
        _NonQuery -Conn $Conn -Sql "ALTER TABLE $Table ADD COLUMN $ColDef" | Out-Null
    } catch {
        if ([string]$_.Exception.Message -notlike '*duplicate column*') { throw }
    }
}

function _AssertSupportedContractVersion {
    param(
        [string]$Label,
        [object]$Value
    )
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return }
    $text  = [string]$Value
    $match = [regex]::Match($text.Trim(), '^(?:v)?(\d+)(?:\..*)?$')
    if ($match.Success) {
        $major = [int]$match.Groups[1].Value
        if ($major -ne 1) {
            throw "Unsupported $Label '$text'. Supported major version: 1."
        }
    }
}

function _ResolveRunImportMetadata {
    param([Parameter(Mandatory)][string]$RunFolder)

    if (-not [System.IO.Directory]::Exists($RunFolder)) {
        throw "Run folder not found: $RunFolder"
    }

    $manifestPath = [System.IO.Path]::Combine($RunFolder, 'manifest.json')
    $summaryPath  = [System.IO.Path]::Combine($RunFolder, 'summary.json')
    $dataDir      = [System.IO.Path]::Combine($RunFolder, 'data')

    if (-not [System.IO.File]::Exists($manifestPath)) {
        throw "Run folder is missing manifest.json: $RunFolder"
    }
    if (-not [System.IO.File]::Exists($summaryPath)) {
        throw "Run folder is missing summary.json: $RunFolder"
    }
    if (-not [System.IO.Directory]::Exists($dataDir)) {
        throw "Run folder is missing data directory: $RunFolder"
    }

    $dataFiles = @([System.IO.Directory]::GetFiles($dataDir, '*.jsonl') | Sort-Object)
    if ($dataFiles.Count -eq 0) {
        throw "Run folder contains no data\\*.jsonl files: $RunFolder"
    }

    $manifest = _ReadJsonFile -Path $manifestPath
    $summary  = _ReadJsonFile -Path $summaryPath
    if ($null -eq $manifest) { throw "manifest.json is empty or invalid JSON: $manifestPath" }
    if ($null -eq $summary)  { throw "summary.json is empty or invalid JSON: $summaryPath" }

    $datasetKey = [string](_ObjVal $manifest @('dataset_key','datasetKey','dataset') `
                               (_ObjVal $summary @('dataset_key','datasetKey','dataset') ''))
    if (-not $datasetKey) {
        $parentName = Split-Path -Leaf (Split-Path -Parent $RunFolder)
        if ($parentName -in @('analytics-conversation-details-query', 'analytics-conversation-details')) {
            $datasetKey = $parentName
        }
    }
    if ($datasetKey -notin @('analytics-conversation-details-query', 'analytics-conversation-details')) {
        throw "Unsupported or missing dataset key '$datasetKey' in run folder: $RunFolder"
    }

    $runId = [string](_ObjVal $manifest @('run_id','runId','id') (_ObjVal $summary @('run_id','runId','id') ''))
    if (-not $runId) { $runId = [System.IO.Path]::GetFileName($RunFolder) }

    $status = [string](_ObjVal $manifest @('status') (_ObjVal $summary @('status') 'unknown'))
    if (-not $status) { $status = 'unknown' }

    $start = [string](_ObjVal $manifest @('extraction_start','extractionStart','startDateTime','windowStart','intervalStart') `
                         (_ObjVal $summary @('extraction_start','extractionStart','startDateTime','windowStart','intervalStart') ''))
    $end   = [string](_ObjVal $manifest @('extraction_end','extractionEnd','endDateTime','windowEnd','intervalEnd') `
                         (_ObjVal $summary @('extraction_end','extractionEnd','endDateTime','windowEnd','intervalEnd') ''))

    $schemaVersion = [string](_ObjVal $manifest @('schema_version','schemaVersion','artifactSchemaVersion') `
                                  (_ObjVal $summary @('schema_version','schemaVersion','artifactSchemaVersion') ''))
    $normalizationVersion = [string](_ObjVal $manifest @('normalization_version','normalizationVersion') `
                                          (_ObjVal $summary @('normalization_version','normalizationVersion') ''))
    _AssertSupportedContractVersion -Label 'schema version'        -Value $schemaVersion
    _AssertSupportedContractVersion -Label 'normalization version' -Value $normalizationVersion

    return [pscustomobject]@{
        RunFolder            = $RunFolder
        RunId                = $runId
        DatasetKey           = $datasetKey
        Status               = $status
        ExtractionStart      = $start
        ExtractionEnd        = $end
        SchemaVersion        = $schemaVersion
        NormalizationVersion = $normalizationVersion
        ManifestPath         = $manifestPath
        SummaryPath          = $summaryPath
        Manifest             = $manifest
        Summary              = $summary
        ManifestJson         = _ReadJsonText -Path $manifestPath
        SummaryJson          = _ReadJsonText -Path $summaryPath
        DataFiles            = $dataFiles
    }
}

function _ConvertConversationRecordToStoreRow {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][long]$ByteOffset
    )

    $convId = [string](_ObjVal $Record @('conversationId') '')
    if ([string]::IsNullOrWhiteSpace($convId)) { return $null }

    $direction    = ''
    $mediaType    = ''
    $queue        = ''
    $disconnect   = ''
    $hasMos       = $false
    $hasHold      = $false
    $segmentCount = 0
    $partCount    = 0
    $durationSec  = 0
    $ani          = ''
    $dnis         = ''
    $agentIds     = New-Object System.Collections.Generic.List[string]
    $divIdSet     = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    if ($Record.PSObject.Properties['participants']) {
        $participants = @($Record.participants)
        $partCount    = $participants.Count
        foreach ($p in $participants) {
            $purpose    = if ($p.PSObject.Properties['purpose']) { [string]$p.purpose } else { '' }
            $isCustomer = ($purpose -eq 'customer')
            $isAgent    = ($purpose -eq 'agent')
            if ($isAgent -and $p.PSObject.Properties['userId'] -and $p.userId) {
                $agentIds.Add([string]$p.userId) | Out-Null
            }
            if (-not $p.PSObject.Properties['sessions']) { continue }
            foreach ($s in @($p.sessions)) {
                if (-not $mediaType -and $s.PSObject.Properties['mediaType']) {
                    $mediaType = [string]$s.mediaType
                }
                if ($isCustomer -and -not $direction -and $s.PSObject.Properties['direction']) {
                    $direction = [string]$s.direction
                }
                if ($isCustomer) {
                    if (-not $ani  -and $s.PSObject.Properties['ani']  -and $s.ani)  { $ani  = [string]$s.ani  }
                    if (-not $dnis -and $s.PSObject.Properties['dnis'] -and $s.dnis) { $dnis = [string]$s.dnis }
                }
                if ($s.PSObject.Properties['metrics']) {
                    foreach ($m in @($s.metrics)) {
                        if ($m.PSObject.Properties['name'] -and
                            ($m.name -like '*mos*' -or $m.name -like '*Mos*')) {
                            $hasMos = $true
                        }
                    }
                }
                if (-not $s.PSObject.Properties['segments']) { continue }
                foreach ($seg in @($s.segments)) {
                    $segmentCount++
                    if ($seg.PSObject.Properties['segmentType'] -and $seg.segmentType -eq 'hold') {
                        $hasHold = $true
                    }
                    if (-not $disconnect -and $seg.PSObject.Properties['disconnectType']) {
                        $disconnect = [string]$seg.disconnectType
                    }
                    if (-not $queue -and $seg.PSObject.Properties['queueName']) {
                        $queue = [string]$seg.queueName
                    }
                }
            }
        }
    }

    # Division IDs from top-level divisionIds array
    if ($Record.PSObject.Properties['divisionIds'] -and $null -ne $Record.divisionIds) {
        foreach ($d in @($Record.divisionIds)) {
            if ($d) { $divIdSet.Add([string]$d) | Out-Null }
        }
    }

    if ($Record.PSObject.Properties['conversationStart'] -and
        $Record.PSObject.Properties['conversationEnd']) {
        try {
            $s = [datetime]::Parse($Record.conversationStart)
            $e = [datetime]::Parse($Record.conversationEnd)
            $durationSec = [int]($e - $s).TotalSeconds
        } catch { }
    }

    return [pscustomobject]@{
        conversation_id    = $convId
        direction          = $direction
        media_type         = $mediaType
        queue_name         = $queue
        disconnect_type    = $disconnect
        duration_sec       = $durationSec
        has_hold           = $hasHold
        has_mos            = $hasMos
        segment_count      = $segmentCount
        participant_count  = $partCount
        conversation_start = [string](_ObjVal $Record @('conversationStart') '')
        conversation_end   = [string](_ObjVal $Record @('conversationEnd') '')
        participants_json  = if ($Record.PSObject.Properties['participants']) { _ToJsonOrNull -Value $Record.participants } else { $null }
        attributes_json    = if ($Record.PSObject.Properties['attributes'])   { _ToJsonOrNull -Value $Record.attributes   } else { $null }
        source_file        = $RelativePath
        source_offset      = $ByteOffset
        agent_names        = ($agentIds | Select-Object -Unique) -join '|'
        division_ids       = ($divIdSet.GetEnumerator() | ForEach-Object { $_ }) -join '|'
        ani                = $ani
        dnis               = $dnis
    }
}

function _WriteConversationRows {
    param(
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteConnection]$Conn,
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$ImportId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][string]$ImportedUtc
    )

    $inserted = 0
    $skipped  = 0
    $failed   = 0

    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = @'
INSERT OR REPLACE INTO conversations
    (conversation_id, case_id, import_id, run_id,
     direction, media_type, queue_name, disconnect_type,
     duration_sec, has_hold, has_mos, segment_count, participant_count,
     conversation_start, conversation_end,
     participants_json, attributes_json,
     source_file, source_offset, imported_utc,
     agent_names, division_ids, ani, dnis)
VALUES
    (@cvid, @cid, @iid, @rid,
     @dir, @media, @queue, @disc,
     @dur, @hold, @mos, @segs, @ptcnt,
     @start, @end,
     @ptjson, @atjson,
     @srcf, @srco, @now,
     @anames, @divids, @ani, @dnis)
'@

    $pNames = '@cvid','@cid','@iid','@rid',
              '@dir','@media','@queue','@disc',
              '@dur','@hold','@mos','@segs','@ptcnt',
              '@start','@end',
              '@ptjson','@atjson',
              '@srcf','@srco','@now',
              '@anames','@divids','@ani','@dnis'
    $pMap = @{}
    foreach ($n in $pNames) {
        $p = $cmd.CreateParameter()
        $p.ParameterName = $n
        $p.Value         = [System.DBNull]::Value
        $cmd.Parameters.Add($p) | Out-Null
        $pMap[$n] = $p
    }

    try {
        foreach ($row in $Rows) {
            if ($null -eq $row) { $skipped++; continue }
            $cvid = [string](_RowVal $row 'conversation_id' '')
            if ([string]::IsNullOrWhiteSpace($cvid)) { $skipped++; continue }

            try {
                $holdRaw = _RowVal $row 'has_hold' $false
                $mosRaw  = _RowVal $row 'has_mos'  $false

                $pMap['@cvid' ].Value = $cvid
                $pMap['@cid'  ].Value = $CaseId
                $pMap['@iid'  ].Value = $ImportId
                $pMap['@rid'  ].Value = $RunId
                $pMap['@dir'  ].Value = [string](_RowVal $row 'direction'         '')
                $pMap['@media'].Value = [string](_RowVal $row 'media_type'        '')
                $pMap['@queue'].Value = [string](_RowVal $row 'queue_name'        '')
                $pMap['@disc' ].Value = [string](_RowVal $row 'disconnect_type'   '')
                $pMap['@dur'  ].Value = [int]   (_RowVal $row 'duration_sec'       0)
                $pMap['@hold' ].Value = [int]   (if ([bool]$holdRaw) { 1 } else { 0 })
                $pMap['@mos'  ].Value = [int]   (if ([bool]$mosRaw)  { 1 } else { 0 })
                $pMap['@segs' ].Value = [int]   (_RowVal $row 'segment_count'      0)
                $pMap['@ptcnt'].Value = [int]   (_RowVal $row 'participant_count'  0)
                $pMap['@start'].Value = [string](_RowVal $row 'conversation_start' '')
                $pMap['@end'  ].Value = [string](_RowVal $row 'conversation_end'   '')

                $ptj = _RowVal $row 'participants_json' $null
                $atj = _RowVal $row 'attributes_json'   $null
                $pMap['@ptjson'].Value = if ($null -ne $ptj) { [object]$ptj } else { [System.DBNull]::Value }
                $pMap['@atjson'].Value = if ($null -ne $atj) { [object]$atj } else { [System.DBNull]::Value }

                $pMap['@srcf'  ].Value = [string](_RowVal $row 'source_file'   '')
                $pMap['@srco'  ].Value = [long]  (_RowVal $row 'source_offset'  0)
                $pMap['@now'   ].Value = $ImportedUtc
                $pMap['@anames'].Value = [string](_RowVal $row 'agent_names'   '')
                $pMap['@divids'].Value = [string](_RowVal $row 'division_ids'  '')
                $pMap['@ani'   ].Value = [string](_RowVal $row 'ani'           '')
                $pMap['@dnis'  ].Value = [string](_RowVal $row 'dnis'          '')

                $cmd.ExecuteNonQuery() | Out-Null
                $inserted++
            } catch {
                $failed++
            }
        }
    } finally {
        $cmd.Dispose()
    }

    return [pscustomobject]@{
        RecordCount  = $inserted
        SkippedCount = $skipped
        FailedCount  = $failed
    }
}

function _ImportJsonlFileToConnection {
    param(
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteConnection]$Conn,
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$ImportId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Batch,
        [Parameter(Mandatory)][int]$BatchSize,
        [Parameter(Mandatory)][hashtable]$Stats,
        [Parameter(Mandatory)][string]$ImportedUtc
    )

    $relPath    = _GetRelativePath -BasePath $RunFolder -FullPath $FilePath
    $fs         = [System.IO.FileStream]::new(
        $FilePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    $bufSize    = 65536
    $buf        = New-Object byte[] $bufSize
    $lineBuffer = New-Object System.Collections.Generic.List[byte]
    $chunkStart = 0L
    $lineStart  = 0L
    $firstChunk = $true

    try {
        while (($bytesRead = $fs.Read($buf, 0, $bufSize)) -gt 0) {
            $startIdx = 0
            if ($firstChunk -and $bytesRead -ge 3 `
                    -and $buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF) {
                $startIdx   = 3
                $lineStart   = 3
            }
            $firstChunk = $false

            for ($i = $startIdx; $i -lt $bytesRead; $i++) {
                $b = $buf[$i]
                if ($b -eq 10) {
                    if ($lineBuffer.Count -gt 0 -and $lineBuffer[$lineBuffer.Count - 1] -eq 13) {
                        $lineBuffer.RemoveAt($lineBuffer.Count - 1)
                    }
                    if ($lineBuffer.Count -gt 0) {
                        $line = [System.Text.Encoding]::UTF8.GetString($lineBuffer.ToArray())
                        try {
                            $record = $line | ConvertFrom-Json
                            $row = _ConvertConversationRecordToStoreRow -Record $record -RelativePath $relPath -ByteOffset $lineStart
                            if ($null -eq $row) {
                                $Stats.SkippedCount++
                            } else {
                                $Batch.Add($row)
                                if ($Batch.Count -ge $BatchSize) {
                                    $result = _WriteConversationRows -Conn $Conn -CaseId $CaseId -ImportId $ImportId -RunId $RunId -Rows $Batch.ToArray() -ImportedUtc $ImportedUtc
                                    $Stats.RecordCount  += $result.RecordCount
                                    $Stats.SkippedCount += $result.SkippedCount
                                    $Stats.FailedCount  += $result.FailedCount
                                    $Batch.Clear()
                                }
                            }
                        } catch {
                            $Stats.FailedCount++
                        }
                    }
                    $lineBuffer.Clear()
                    $lineStart = $chunkStart + $i + 1
                } else {
                    $lineBuffer.Add($b)
                }
            }
            $chunkStart += $bytesRead
        }

        if ($lineBuffer.Count -gt 0) {
            if ($lineBuffer[$lineBuffer.Count - 1] -eq 13) {
                $lineBuffer.RemoveAt($lineBuffer.Count - 1)
            }
            if ($lineBuffer.Count -gt 0) {
                $line = [System.Text.Encoding]::UTF8.GetString($lineBuffer.ToArray())
                try {
                    $record = $line | ConvertFrom-Json
                    $row = _ConvertConversationRecordToStoreRow -Record $record -RelativePath $relPath -ByteOffset $lineStart
                    if ($null -eq $row) {
                        $Stats.SkippedCount++
                    } else {
                        $Batch.Add($row)
                    }
                } catch {
                    $Stats.FailedCount++
                }
            }
        }
    } finally {
        $fs.Dispose()
    }
}

# ── Private: Schema DDL ───────────────────────────────────────────────────────

function _ApplySchema {
    param([System.Data.SQLite.SQLiteConnection]$Conn)

    # PRAGMAs
    _Scalar   -Conn $Conn -Sql 'PRAGMA journal_mode = WAL'  | Out-Null
    _NonQuery -Conn $Conn -Sql 'PRAGMA foreign_keys = ON'   | Out-Null

    # schema_version ─────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS schema_version (
    version     INTEGER NOT NULL,
    applied_utc TEXT    NOT NULL
)
'@ | Out-Null

    # cases ──────────────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS cases (
    case_id     TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    state       TEXT NOT NULL DEFAULT 'active',
    created_utc TEXT NOT NULL,
    updated_utc TEXT NOT NULL,
    closed_utc  TEXT,
    expires_utc TEXT,
    notes       TEXT NOT NULL DEFAULT ''
)
'@ | Out-Null

    # core_runs ──────────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS core_runs (
    run_id           TEXT PRIMARY KEY,
    case_id          TEXT NOT NULL REFERENCES cases(case_id),
    dataset_key      TEXT NOT NULL DEFAULT '',
    run_folder       TEXT NOT NULL DEFAULT '',
    status           TEXT NOT NULL DEFAULT 'unknown',
    extraction_start TEXT,
    extraction_end   TEXT,
    registered_utc   TEXT NOT NULL,
    manifest_json    TEXT,
    summary_json     TEXT
)
'@ | Out-Null

    # imports ────────────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS imports (
    import_id      TEXT    PRIMARY KEY,
    case_id        TEXT    NOT NULL REFERENCES cases(case_id),
    run_id         TEXT    NOT NULL REFERENCES core_runs(run_id),
    imported_utc   TEXT    NOT NULL,
    record_count   INTEGER NOT NULL DEFAULT 0,
    skipped_count  INTEGER NOT NULL DEFAULT 0,
    failed_count   INTEGER NOT NULL DEFAULT 0,
    status         TEXT    NOT NULL DEFAULT 'pending',
    error_text     TEXT    NOT NULL DEFAULT '',
    schema_version INTEGER NOT NULL DEFAULT 1
)
'@ | Out-Null

    # conversations ──────────────────────────────────────────────────────────
    # Flat shape matching the existing index entry contract.
    # participants_json / attributes_json are side-car columns for nested detail.
    # Normalized participants / segments tables are reserved for a future schema
    # migration once operator workflows prove the need for SQL pivots by agent,
    # purpose, or segment type.
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS conversations (
    conversation_id   TEXT    NOT NULL,
    case_id           TEXT    NOT NULL REFERENCES cases(case_id),
    import_id         TEXT    NOT NULL REFERENCES imports(import_id),
    run_id            TEXT    NOT NULL REFERENCES core_runs(run_id),
    direction         TEXT    NOT NULL DEFAULT '',
    media_type        TEXT    NOT NULL DEFAULT '',
    queue_name        TEXT    NOT NULL DEFAULT '',
    disconnect_type   TEXT    NOT NULL DEFAULT '',
    duration_sec      INTEGER NOT NULL DEFAULT 0,
    has_hold          INTEGER NOT NULL DEFAULT 0,
    has_mos           INTEGER NOT NULL DEFAULT 0,
    segment_count     INTEGER NOT NULL DEFAULT 0,
    participant_count INTEGER NOT NULL DEFAULT 0,
    conversation_start TEXT   NOT NULL DEFAULT '',
    conversation_end   TEXT   NOT NULL DEFAULT '',
    participants_json  TEXT,
    attributes_json    TEXT,
    source_file        TEXT   NOT NULL DEFAULT '',
    source_offset      INTEGER NOT NULL DEFAULT 0,
    imported_utc       TEXT   NOT NULL,
    PRIMARY KEY (conversation_id, case_id)
)
'@ | Out-Null

    # case_tags ──────────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS case_tags (
    case_id     TEXT NOT NULL REFERENCES cases(case_id),
    tag         TEXT NOT NULL,
    created_utc TEXT NOT NULL,
    PRIMARY KEY (case_id, tag)
)
'@ | Out-Null

    # bookmarks ──────────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS bookmarks (
    bookmark_id      TEXT PRIMARY KEY,
    case_id          TEXT NOT NULL REFERENCES cases(case_id),
    conversation_id  TEXT NOT NULL DEFAULT '',
    title            TEXT NOT NULL DEFAULT '',
    notes            TEXT NOT NULL DEFAULT '',
    created_utc      TEXT NOT NULL,
    updated_utc      TEXT NOT NULL
)
'@ | Out-Null

    # findings ───────────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS findings (
    finding_id     TEXT PRIMARY KEY,
    case_id        TEXT NOT NULL REFERENCES cases(case_id),
    title          TEXT NOT NULL,
    summary        TEXT NOT NULL DEFAULT '',
    severity       TEXT NOT NULL DEFAULT 'info',
    status         TEXT NOT NULL DEFAULT 'open',
    evidence_json  TEXT,
    created_utc    TEXT NOT NULL,
    updated_utc    TEXT NOT NULL
)
'@ | Out-Null

    # saved_views ────────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS saved_views (
    view_id       TEXT PRIMARY KEY,
    case_id       TEXT NOT NULL REFERENCES cases(case_id),
    name          TEXT NOT NULL,
    filters_json  TEXT NOT NULL,
    created_utc   TEXT NOT NULL,
    updated_utc   TEXT NOT NULL
)
'@ | Out-Null

    # report_snapshots ───────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_snapshots (
    snapshot_id   TEXT PRIMARY KEY,
    case_id       TEXT NOT NULL REFERENCES cases(case_id),
    name          TEXT NOT NULL,
    format        TEXT NOT NULL DEFAULT 'json',
    content_json  TEXT NOT NULL,
    created_utc   TEXT NOT NULL
)
'@ | Out-Null

    # case_audit ─────────────────────────────────────────────────────────────
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS case_audit (
    audit_id      TEXT PRIMARY KEY,
    case_id       TEXT NOT NULL REFERENCES cases(case_id),
    event_type    TEXT NOT NULL,
    detail_text   TEXT NOT NULL DEFAULT '',
    payload_json  TEXT,
    created_utc   TEXT NOT NULL
)
'@ | Out-Null

    # Indexes ────────────────────────────────────────────────────────────────
    $indexes = @(
        'CREATE INDEX IF NOT EXISTS idx_conv_case_id     ON conversations(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_conv_import_id   ON conversations(import_id)',
        'CREATE INDEX IF NOT EXISTS idx_conv_run_id      ON conversations(run_id)',
        'CREATE INDEX IF NOT EXISTS idx_conv_direction   ON conversations(direction)',
        'CREATE INDEX IF NOT EXISTS idx_conv_media_type  ON conversations(media_type)',
        'CREATE INDEX IF NOT EXISTS idx_conv_queue_name  ON conversations(queue_name)',
        'CREATE INDEX IF NOT EXISTS idx_conv_start       ON conversations(conversation_start)',
        'CREATE INDEX IF NOT EXISTS idx_runs_case_id     ON core_runs(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_imports_case_id  ON imports(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_imports_run_id   ON imports(run_id)',
        'CREATE INDEX IF NOT EXISTS idx_tags_case_id     ON case_tags(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_bookmarks_case   ON bookmarks(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_bookmarks_conv   ON bookmarks(conversation_id)',
        'CREATE INDEX IF NOT EXISTS idx_findings_case    ON findings(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_views_case       ON saved_views(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_snapshots_case   ON report_snapshots(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_audit_case       ON case_audit(case_id)',
        'CREATE INDEX IF NOT EXISTS idx_audit_created    ON case_audit(created_utc)'
    )
    foreach ($idx in $indexes) {
        _NonQuery -Conn $Conn -Sql $idx | Out-Null
    }

    # Schema v3 — pivot dimension columns added to conversations
    # _AddColumnIfMissing is idempotent (ignores "duplicate column name")
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "agent_names   TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "division_ids  TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "ani           TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "dnis          TEXT NOT NULL DEFAULT ''"

    # v3 indexes
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_agent_names ON conversations(agent_names)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_ani         ON conversations(ani)'         | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_disc_type   ON conversations(disconnect_type)' | Out-Null

    # Schema v4 — reference data tables (Session 13)
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS ref_queues (
    ref_id        TEXT    PRIMARY KEY,
    case_id       TEXT    NOT NULL REFERENCES cases(case_id),
    queue_id      TEXT    NOT NULL,
    name          TEXT    NOT NULL DEFAULT '',
    description   TEXT    NOT NULL DEFAULT '',
    division_id   TEXT    NOT NULL DEFAULT '',
    media_type    TEXT    NOT NULL DEFAULT '',
    refreshed_at  TEXT    NOT NULL
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS ref_users (
    ref_id        TEXT    PRIMARY KEY,
    case_id       TEXT    NOT NULL REFERENCES cases(case_id),
    user_id       TEXT    NOT NULL,
    name          TEXT    NOT NULL DEFAULT '',
    email         TEXT    NOT NULL DEFAULT '',
    department    TEXT    NOT NULL DEFAULT '',
    division_id   TEXT    NOT NULL DEFAULT '',
    state         TEXT    NOT NULL DEFAULT '',
    refreshed_at  TEXT    NOT NULL
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS ref_divisions (
    ref_id        TEXT    PRIMARY KEY,
    case_id       TEXT    NOT NULL REFERENCES cases(case_id),
    division_id   TEXT    NOT NULL,
    name          TEXT    NOT NULL DEFAULT '',
    description   TEXT    NOT NULL DEFAULT '',
    refreshed_at  TEXT    NOT NULL
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS ref_wrapup_codes (
    ref_id        TEXT    PRIMARY KEY,
    case_id       TEXT    NOT NULL REFERENCES cases(case_id),
    code_id       TEXT    NOT NULL,
    name          TEXT    NOT NULL DEFAULT '',
    refreshed_at  TEXT    NOT NULL
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS ref_skills (
    ref_id        TEXT    PRIMARY KEY,
    case_id       TEXT    NOT NULL REFERENCES cases(case_id),
    skill_id      TEXT    NOT NULL,
    name          TEXT    NOT NULL DEFAULT '',
    refreshed_at  TEXT    NOT NULL
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS ref_flows (
    ref_id        TEXT    PRIMARY KEY,
    case_id       TEXT    NOT NULL REFERENCES cases(case_id),
    flow_id       TEXT    NOT NULL,
    name          TEXT    NOT NULL DEFAULT '',
    flow_type     TEXT    NOT NULL DEFAULT '',
    description   TEXT    NOT NULL DEFAULT '',
    refreshed_at  TEXT    NOT NULL
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS ref_flow_outcomes (
    ref_id        TEXT    PRIMARY KEY,
    case_id       TEXT    NOT NULL REFERENCES cases(case_id),
    outcome_id    TEXT    NOT NULL,
    name          TEXT    NOT NULL DEFAULT '',
    description   TEXT    NOT NULL DEFAULT '',
    refreshed_at  TEXT    NOT NULL
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS ref_flow_milestones (
    ref_id        TEXT    PRIMARY KEY,
    case_id       TEXT    NOT NULL REFERENCES cases(case_id),
    milestone_id  TEXT    NOT NULL,
    name          TEXT    NOT NULL DEFAULT '',
    description   TEXT    NOT NULL DEFAULT '',
    refreshed_at  TEXT    NOT NULL
)
'@ | Out-Null

    # v4 indexes
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_queues_case    ON ref_queues(case_id)'          | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_queues_id      ON ref_queues(queue_id)'         | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_users_case     ON ref_users(case_id)'           | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_users_id       ON ref_users(user_id)'           | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_divs_case      ON ref_divisions(case_id)'       | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_divs_id        ON ref_divisions(division_id)'   | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_wrapups_case   ON ref_wrapup_codes(case_id)'    | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_wrapups_id     ON ref_wrapup_codes(code_id)'    | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_skills_case    ON ref_skills(case_id)'          | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_flows_case     ON ref_flows(case_id)'           | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_flows_id       ON ref_flows(flow_id)'           | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_outcomes_case  ON ref_flow_outcomes(case_id)'   | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_ref_milestones_case ON ref_flow_milestones(case_id)'| Out-Null

    # Stamp schema version on first creation and after migrations
    $count = [int](_Scalar -Conn $Conn -Sql 'SELECT COUNT(*) FROM schema_version')
    if ($count -eq 0) {
        _NonQuery -Conn $Conn -Sql `
            'INSERT INTO schema_version(version, applied_utc) VALUES(@v, @t)' `
            -P @{ '@v' = $script:SchemaVersion; '@t' = [datetime]::UtcNow.ToString('o') } | Out-Null
    } else {
        $current = [int](_Scalar -Conn $Conn -Sql 'SELECT MAX(version) FROM schema_version')
        if ($current -lt $script:SchemaVersion) {
            _NonQuery -Conn $Conn -Sql `
                'INSERT INTO schema_version(version, applied_utc) VALUES(@v, @t)' `
                -P @{ '@v' = $script:SchemaVersion; '@t' = [datetime]::UtcNow.ToString('o') } | Out-Null
        }
    }
}

# ── Public: Initialization ────────────────────────────────────────────────────

function Initialize-Database {
    <#
    .SYNOPSIS
        Gate F – loads System.Data.SQLite, opens/creates the local case store,
        and ensures the current schema is applied.
        Must be called once at startup (App.ps1, after Gate A).
    .PARAMETER DatabasePath
        Full path to the .sqlite file.  Created if absent.
    .PARAMETER SqliteDllPath
        Optional explicit DLL path.  Falls back to env:SQLITE_DLL then .\lib\*.
    .PARAMETER AppDir
        Application root dir used for relative DLL path resolution.
    #>
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [string]$SqliteDllPath = '',
        [string]$AppDir        = ''
    )

    $dll = _ResolveSqliteDll -ConfigPath $SqliteDllPath -AppDir $AppDir
    _EnsureAssemblyLoaded -DllPath $dll

    $dbDir = [System.IO.Path]::GetDirectoryName($DatabasePath)
    if (-not [System.IO.Directory]::Exists($dbDir)) {
        [System.IO.Directory]::CreateDirectory($dbDir) | Out-Null
    }

    $script:ConnStr = "Data Source=$DatabasePath;Version=3;"

    $conn = _Open
    try {
        _ApplySchema -Conn $conn
    } finally {
        $conn.Close()
        $conn.Dispose()
    }

    $script:DbInitialized = $true
}

function Test-DatabaseInitialized {
    <#
    .SYNOPSIS
        Returns $true if Initialize-Database has completed successfully.
    #>
    return $script:DbInitialized
}

function _RequireDb {
    if (-not $script:DbInitialized) {
        throw 'Database is not initialized. Call Initialize-Database before using case store functions.'
    }
}

function _AuditCaseEvent {
    param(
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteConnection]$Conn,
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$EventType,
        [string]$DetailText = '',
        [string]$PayloadJson = ''
    )
    _NonQuery -Conn $Conn -Sql @'
INSERT INTO case_audit(audit_id, case_id, event_type, detail_text, payload_json, created_utc)
VALUES(@id, @cid, @evt, @detail, @payload, @now)
'@ -P @{
        '@id'      = [System.Guid]::NewGuid().ToString()
        '@cid'     = $CaseId
        '@evt'     = $EventType
        '@detail'  = $DetailText
        '@payload' = if ($PayloadJson) { [object]$PayloadJson } else { $null }
        '@now'     = [datetime]::UtcNow.ToString('o')
    } | Out-Null
}

function _GetRetentionStatusForCaseRow {
    param(
        [Parameter(Mandatory)][object]$Case,
        [datetime]$NowUtc = ([datetime]::UtcNow)
    )

    $state = [string](_RowVal $Case 'state' 'active')
    if ($state -eq 'archived')   { return 'archived' }
    if ($state -eq 'purge_ready'){ return 'purge_ready' }
    if ($state -eq 'purged')     { return 'purged' }

    $exp = [string](_RowVal $Case 'expires_utc' '')
    if ($exp) {
        try {
            $expUtc = [datetime]::Parse($exp).ToUniversalTime()
            if ($expUtc -le $NowUtc) { return 'expiring' }
        } catch { }
    }

    return $state
}

# ── Public: Case management ───────────────────────────────────────────────────

function New-Case {
    <#
    .SYNOPSIS
        Creates a new case in state 'active'.  Returns the new case_id (GUID string).
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description = '',
        [string]$ExpiresUtc  = ''
    )
    _RequireDb
    $id  = [System.Guid]::NewGuid().ToString()
    $now = [datetime]::UtcNow.ToString('o')
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
INSERT INTO cases(case_id, name, description, state, created_utc, updated_utc, expires_utc)
VALUES(@id, @name, @desc, 'active', @now, @now, @exp)
'@ -P @{
            '@id'   = $id
            '@name' = $Name
            '@desc' = $Description
            '@now'  = $now
            '@exp'  = if ($ExpiresUtc) { [object]$ExpiresUtc } else { $null }
        } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $id -EventType 'case.created' `
            -DetailText "Case created: $Name" `
            -PayloadJson (_ToJsonOrNull @{
                case_id     = $id
                name        = $Name
                description = $Description
                expires_utc = $ExpiresUtc
            })
    } finally { $conn.Close(); $conn.Dispose() }
    return $id
}

function Get-Case {
    <#
    .SYNOPSIS
        Returns a single case as pscustomobject, or $null if not found.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb
    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql 'SELECT * FROM cases WHERE case_id = @id' -P @{ '@id' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }
    if ($rows.Count -eq 0) { return $null }
    $case = [pscustomobject]$rows[0]
    $case | Add-Member -NotePropertyName 'retention_status' -NotePropertyValue (_GetRetentionStatusForCaseRow -Case $case) -Force
    return $case
}

function Get-Cases {
    <#
    .SYNOPSIS
        Returns all cases newest-first, optionally filtered by state.
        Valid states: active, closed, archived, purge_ready, purged.
    #>
    param([string]$State = '')
    _RequireDb
    $conn = _Open
    try {
        if ($State) {
            $rows = _Query -Conn $conn `
                -Sql 'SELECT * FROM cases WHERE state = @s ORDER BY created_utc DESC' `
                -P @{ '@s' = $State }
        } else {
            $rows = _Query -Conn $conn -Sql 'SELECT * FROM cases ORDER BY created_utc DESC'
        }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object {
        $case = [pscustomobject]$_
        $case | Add-Member -NotePropertyName 'retention_status' -NotePropertyValue (_GetRetentionStatusForCaseRow -Case $case) -Force
        $case
    })
}

function Update-CaseState {
    <#
    .SYNOPSIS
        Transitions a case to a new lifecycle state.
        Moving to closed / archived / purge_ready / purged stamps closed_utc if not already set.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)]
        [ValidateSet('active', 'closed', 'archived', 'purge_ready', 'purged')]
        [string]$State
    )
    _RequireDb
    $now      = [datetime]::UtcNow.ToString('o')
    $closedAt = if ($State -in @('closed', 'archived', 'purge_ready', 'purged')) { [object]$now } else { $null }
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
UPDATE cases
SET state = @state, updated_utc = @now,
    closed_utc = COALESCE(@closed, closed_utc)
WHERE case_id = @id
'@ -P @{ '@state' = $State; '@now' = $now; '@closed' = $closedAt; '@id' = $CaseId } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'case.state_changed' -DetailText "Case state changed to $State"
    } finally { $conn.Close(); $conn.Dispose() }
}

function Update-CaseNotes {
    <#
    .SYNOPSIS
        Replaces the free-text notes field on a case.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$Notes
    )
    _RequireDb
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql `
            'UPDATE cases SET notes = @notes, updated_utc = @now WHERE case_id = @id' `
            -P @{ '@notes' = $Notes; '@now' = [datetime]::UtcNow.ToString('o'); '@id' = $CaseId } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'case.notes_updated' -DetailText 'Case notes updated'
    } finally { $conn.Close(); $conn.Dispose() }
}

function Remove-CaseData {
    <#
    .SYNOPSIS
        Purges all conversations, imports, and core_runs rows for a case within a single
        transaction.  Does NOT delete the case row itself; call Update-CaseState first.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb
    $conn = _Open
    try {
        $tx = $conn.BeginTransaction()
        try {
            _NonQuery -Conn $conn -Sql 'DELETE FROM conversations WHERE case_id = @id' -P @{ '@id' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM imports      WHERE case_id = @id' -P @{ '@id' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM core_runs    WHERE case_id = @id' -P @{ '@id' = $CaseId } | Out-Null
            $tx.Commit()
        } catch {
            $tx.Rollback()
            throw
        } finally {
            $tx.Dispose()
        }
    } finally { $conn.Close(); $conn.Dispose() }
}

function Set-CaseExpiry {
    <#
    .SYNOPSIS
        Sets or clears the expiry timestamp for a case.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [string]$ExpiresUtc = ''
    )
    _RequireDb
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql `
            'UPDATE cases SET expires_utc = @exp, updated_utc = @now WHERE case_id = @id' `
            -P @{
                '@exp' = if ($ExpiresUtc) { [object]$ExpiresUtc } else { $null }
                '@now' = [datetime]::UtcNow.ToString('o')
                '@id'  = $CaseId
            } | Out-Null
        $detail = if ($ExpiresUtc) { "Case expiry set to $ExpiresUtc" } else { 'Case expiry cleared' }
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'case.expiry_updated' -DetailText $detail
    } finally { $conn.Close(); $conn.Dispose() }
}

function Get-CaseRetentionStatus {
    <#
    .SYNOPSIS
        Returns the derived retention status for a case.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb
    $case = Get-Case -CaseId $CaseId
    if ($null -eq $case) { return $null }
    return (_GetRetentionStatusForCaseRow -Case $case)
}

function Get-CaseAudit {
    <#
    .SYNOPSIS
        Returns case audit rows newest first.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [int]$LastN = 100
    )
    _RequireDb
    if ($LastN -lt 1) { $LastN = 100 }
    $conn = _Open
    try {
        $rows = _Query -Conn $conn `
            -Sql 'SELECT * FROM case_audit WHERE case_id = @cid ORDER BY created_utc DESC LIMIT @limit' `
            -P @{ '@cid' = $CaseId; '@limit' = $LastN }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Get-CaseTags {
    <#
    .SYNOPSIS
        Returns tags for a case, alphabetically.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb
    $conn = _Open
    try {
        $rows = _Query -Conn $conn `
            -Sql 'SELECT tag FROM case_tags WHERE case_id = @cid ORDER BY tag ASC' `
            -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [string]$_.tag })
}

function Set-CaseTags {
    <#
    .SYNOPSIS
        Replaces all case tags with the provided set.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [string[]]$Tags = @()
    )
    _RequireDb
    $normalized = @($Tags | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique)

    $conn = _Open
    try {
        $tx = $conn.BeginTransaction()
        try {
            _NonQuery -Conn $conn -Sql 'DELETE FROM case_tags WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            foreach ($tag in $normalized) {
                _NonQuery -Conn $conn -Sql @'
INSERT INTO case_tags(case_id, tag, created_utc)
VALUES(@cid, @tag, @now)
'@ -P @{ '@cid' = $CaseId; '@tag' = $tag; '@now' = [datetime]::UtcNow.ToString('o') } | Out-Null
            }
            _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'case.tags_updated' `
                -DetailText "Case tags updated ($($normalized.Count))" `
                -PayloadJson (_ToJsonOrNull @{ tags = $normalized })
            $tx.Commit()
        } catch {
            $tx.Rollback()
            throw
        } finally {
            $tx.Dispose()
        }
    } finally { $conn.Close(); $conn.Dispose() }
}

function New-ConversationBookmark {
    <#
    .SYNOPSIS
        Adds a case bookmark tied to a conversation id.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$ConversationId,
        [string]$Title = '',
        [string]$Notes = ''
    )
    _RequireDb
    $id  = [System.Guid]::NewGuid().ToString()
    $now = [datetime]::UtcNow.ToString('o')
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
INSERT INTO bookmarks(bookmark_id, case_id, conversation_id, title, notes, created_utc, updated_utc)
VALUES(@id, @cid, @conv, @title, @notes, @now, @now)
'@ -P @{
            '@id'    = $id
            '@cid'   = $CaseId
            '@conv'  = $ConversationId
            '@title' = $Title
            '@notes' = $Notes
            '@now'   = $now
        } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'bookmark.created' `
            -DetailText "Bookmark added for conversation $ConversationId"
    } finally { $conn.Close(); $conn.Dispose() }
    return $id
}

function Get-ConversationBookmarks {
    <#
    .SYNOPSIS
        Returns bookmarks for a case, newest first.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [string]$ConversationId = ''
    )
    _RequireDb
    $conn = _Open
    try {
        if ($ConversationId) {
            $rows = _Query -Conn $conn `
                -Sql 'SELECT * FROM bookmarks WHERE case_id = @cid AND conversation_id = @conv ORDER BY created_utc DESC' `
                -P @{ '@cid' = $CaseId; '@conv' = $ConversationId }
        } else {
            $rows = _Query -Conn $conn `
                -Sql 'SELECT * FROM bookmarks WHERE case_id = @cid ORDER BY created_utc DESC' `
                -P @{ '@cid' = $CaseId }
        }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Remove-ConversationBookmark {
    <#
    .SYNOPSIS
        Deletes a bookmark by id.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$BookmarkId
    )
    _RequireDb
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql 'DELETE FROM bookmarks WHERE case_id = @cid AND bookmark_id = @id' `
            -P @{ '@cid' = $CaseId; '@id' = $BookmarkId } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'bookmark.deleted' -DetailText 'Bookmark deleted'
    } finally { $conn.Close(); $conn.Dispose() }
}

function New-Finding {
    <#
    .SYNOPSIS
        Creates an investigation finding.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$Title,
        [string]$Summary = '',
        [ValidateSet('info', 'low', 'medium', 'high', 'critical')][string]$Severity = 'info',
        [ValidateSet('open', 'closed')][string]$Status = 'open',
        [object]$Evidence = $null
    )
    _RequireDb
    $id  = [System.Guid]::NewGuid().ToString()
    $now = [datetime]::UtcNow.ToString('o')
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
INSERT INTO findings(finding_id, case_id, title, summary, severity, status, evidence_json, created_utc, updated_utc)
VALUES(@id, @cid, @title, @summary, @sev, @status, @evidence, @now, @now)
'@ -P @{
            '@id'       = $id
            '@cid'      = $CaseId
            '@title'    = $Title
            '@summary'  = $Summary
            '@sev'      = $Severity
            '@status'   = $Status
            '@evidence' = if ($null -ne $Evidence) { [object](_ToJsonOrNull $Evidence) } else { $null }
            '@now'      = $now
        } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'finding.created' -DetailText "Finding created: $Title"
    } finally { $conn.Close(); $conn.Dispose() }
    return $id
}

function Update-Finding {
    <#
    .SYNOPSIS
        Updates a finding row.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$FindingId,
        [string]$Title = '',
        [string]$Summary = '',
        [ValidateSet('', 'info', 'low', 'medium', 'high', 'critical')][string]$Severity = '',
        [ValidateSet('', 'open', 'closed')][string]$Status = '',
        [object]$Evidence = $null
    )
    _RequireDb

    $existing = (Get-Findings -CaseId $CaseId | Where-Object { $_.finding_id -eq $FindingId } | Select-Object -First 1)
    if ($null -eq $existing) { throw "Finding not found: $FindingId" }

    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
UPDATE findings
SET title = @title, summary = @summary, severity = @sev, status = @status,
    evidence_json = @evidence, updated_utc = @now
WHERE case_id = @cid AND finding_id = @id
'@ -P @{
            '@title'    = if ($PSBoundParameters.ContainsKey('Title'))    { $Title }    else { $existing.title }
            '@summary'  = if ($PSBoundParameters.ContainsKey('Summary'))  { $Summary }  else { $existing.summary }
            '@sev'      = if ($PSBoundParameters.ContainsKey('Severity')) { $Severity } else { $existing.severity }
            '@status'   = if ($PSBoundParameters.ContainsKey('Status'))   { $Status }   else { $existing.status }
            '@evidence' = if ($PSBoundParameters.ContainsKey('Evidence')) {
                if ($null -ne $Evidence) { [object](_ToJsonOrNull $Evidence) } else { $null }
            } else {
                if ($existing.evidence_json) { [object]$existing.evidence_json } else { $null }
            }
            '@now'      = [datetime]::UtcNow.ToString('o')
            '@cid'      = $CaseId
            '@id'       = $FindingId
        } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'finding.updated' -DetailText "Finding updated: $FindingId"
    } finally { $conn.Close(); $conn.Dispose() }
}

function Get-Findings {
    <#
    .SYNOPSIS
        Returns findings for a case, newest first.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb
    $conn = _Open
    try {
        $rows = _Query -Conn $conn `
            -Sql 'SELECT * FROM findings WHERE case_id = @cid ORDER BY created_utc DESC' `
            -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function New-SavedView {
    <#
    .SYNOPSIS
        Persists a named saved view definition for a case.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$ViewDefinition
    )
    _RequireDb
    $id  = [System.Guid]::NewGuid().ToString()
    $now = [datetime]::UtcNow.ToString('o')
    $json = _ToJsonOrNull -Value $ViewDefinition
    if (-not $json) { throw 'ViewDefinition could not be serialized to JSON.' }

    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
INSERT INTO saved_views(view_id, case_id, name, filters_json, created_utc, updated_utc)
VALUES(@id, @cid, @name, @json, @now, @now)
'@ -P @{
            '@id'   = $id
            '@cid'  = $CaseId
            '@name' = $Name
            '@json' = $json
            '@now'  = $now
        } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'saved_view.created' -DetailText "Saved view created: $Name"
    } finally { $conn.Close(); $conn.Dispose() }
    return $id
}

function Get-SavedViews {
    <#
    .SYNOPSIS
        Returns saved views for a case, newest first.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb
    $conn = _Open
    try {
        $rows = _Query -Conn $conn `
            -Sql 'SELECT * FROM saved_views WHERE case_id = @cid ORDER BY created_utc DESC' `
            -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Remove-SavedView {
    <#
    .SYNOPSIS
        Deletes a saved view row.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$ViewId
    )
    _RequireDb
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql 'DELETE FROM saved_views WHERE case_id = @cid AND view_id = @id' `
            -P @{ '@cid' = $CaseId; '@id' = $ViewId } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'saved_view.deleted' -DetailText 'Saved view deleted'
    } finally { $conn.Close(); $conn.Dispose() }
}

function New-ReportSnapshot {
    <#
    .SYNOPSIS
        Stores a case-level report snapshot.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('json', 'html', 'csv', 'text')][string]$Format = 'json',
        [Parameter(Mandatory)][object]$Content
    )
    _RequireDb
    $id   = [System.Guid]::NewGuid().ToString()
    $now  = [datetime]::UtcNow.ToString('o')
    $json = if ($Content -is [string]) { [string]$Content } else { _ToJsonOrNull -Value $Content }
    if (-not $json) { throw 'Content could not be serialized for report snapshot.' }

    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
INSERT INTO report_snapshots(snapshot_id, case_id, name, format, content_json, created_utc)
VALUES(@id, @cid, @name, @fmt, @content, @now)
'@ -P @{
            '@id'      = $id
            '@cid'     = $CaseId
            '@name'    = $Name
            '@fmt'     = $Format
            '@content' = $json
            '@now'     = $now
        } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'report_snapshot.created' -DetailText "Report snapshot created: $Name"
    } finally { $conn.Close(); $conn.Dispose() }
    return $id
}

function Get-ReportSnapshots {
    <#
    .SYNOPSIS
        Returns report snapshots for a case, newest first.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb
    $conn = _Open
    try {
        $rows = _Query -Conn $conn `
            -Sql 'SELECT * FROM report_snapshots WHERE case_id = @cid ORDER BY created_utc DESC' `
            -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Remove-ReportSnapshot {
    <#
    .SYNOPSIS
        Deletes a report snapshot by id.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$SnapshotId
    )
    _RequireDb
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql 'DELETE FROM report_snapshots WHERE case_id = @cid AND snapshot_id = @id' `
            -P @{ '@cid' = $CaseId; '@id' = $SnapshotId } | Out-Null
        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'report_snapshot.deleted' -DetailText 'Report snapshot deleted'
    } finally { $conn.Close(); $conn.Dispose() }
}

function Close-Case {
    <#
    .SYNOPSIS
        Marks a case closed.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    Update-CaseState -CaseId $CaseId -State 'closed'
}

function Mark-CasePurgeReady {
    <#
    .SYNOPSIS
        Marks a case as purge-ready.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    Update-CaseState -CaseId $CaseId -State 'purge_ready'
}

function Archive-Case {
    <#
    .SYNOPSIS
        Clears imported run data for a case while preserving case workflow state.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb

    $conn = _Open
    try {
        $convCount = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM conversations WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
        $importCount = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM imports WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
        $runCount = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM core_runs WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
    } finally { $conn.Close(); $conn.Dispose() }

    Remove-CaseData -CaseId $CaseId
    Update-CaseState -CaseId $CaseId -State 'archived'

    $conn2 = _Open
    try {
        _AuditCaseEvent -Conn $conn2 -CaseId $CaseId -EventType 'case.archived' `
            -DetailText 'Case archived and imported data cleared' `
            -PayloadJson (_ToJsonOrNull @{
                conversations_removed = $convCount
                imports_removed       = $importCount
                runs_removed          = $runCount
            })
    } finally { $conn2.Close(); $conn2.Dispose() }
}

function Purge-Case {
    <#
    .SYNOPSIS
        Clears imported data and analyst-created case workflow state while keeping the case shell and audit trail.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb

    $conn = _Open
    try {
        $counts = @{
            conversations    = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM conversations WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
            imports          = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM imports WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
            runs             = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM core_runs WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
            tags             = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM case_tags WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
            bookmarks        = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM bookmarks WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
            findings         = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM findings WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
            saved_views      = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM saved_views WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
            report_snapshots = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM report_snapshots WHERE case_id = @cid' -P @{ '@cid' = $CaseId })
        }

        $tx = $conn.BeginTransaction()
        try {
            _NonQuery -Conn $conn -Sql 'DELETE FROM bookmarks WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM findings WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM saved_views WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM report_snapshots WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM case_tags WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM conversations WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM imports WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql 'DELETE FROM core_runs WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
            _NonQuery -Conn $conn -Sql `
                "UPDATE cases SET state = 'purged', notes = '', description = '', updated_utc = @now WHERE case_id = @cid" `
                -P @{ '@now' = [datetime]::UtcNow.ToString('o'); '@cid' = $CaseId } | Out-Null
            _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'case.purged' `
                -DetailText 'Case purged' `
                -PayloadJson (_ToJsonOrNull $counts)
            $tx.Commit()
        } catch {
            $tx.Rollback()
            throw
        } finally {
            $tx.Dispose()
        }
    } finally { $conn.Close(); $conn.Dispose() }
}

# ── Public: Core run registration ─────────────────────────────────────────────

function Register-CoreRun {
    <#
    .SYNOPSIS
        Records a Genesys.Core run folder in core_runs.
        If RunId is empty a new GUID is generated.  Returns the run_id used.
        Uses INSERT OR REPLACE so re-registering an existing run_id updates the row.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$RunFolder,
        [string]$RunId           = '',
        [string]$DatasetKey      = '',
        [string]$Status          = 'unknown',
        [string]$ExtractionStart = '',
        [string]$ExtractionEnd   = '',
        [string]$ManifestJson    = '',
        [string]$SummaryJson     = ''
    )
    _RequireDb
    if (-not $RunId) { $RunId = [System.Guid]::NewGuid().ToString() }
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
INSERT OR REPLACE INTO core_runs
    (run_id, case_id, dataset_key, run_folder, status,
     extraction_start, extraction_end, registered_utc, manifest_json, summary_json)
VALUES
    (@rid, @cid, @dk, @folder, @status,
     @start, @end, @now, @manifest, @summary)
'@ -P @{
            '@rid'      = $RunId
            '@cid'      = $CaseId
            '@dk'       = $DatasetKey
            '@folder'   = $RunFolder
            '@status'   = $Status
            '@start'    = if ($ExtractionStart) { [object]$ExtractionStart } else { $null }
            '@end'      = if ($ExtractionEnd)   { [object]$ExtractionEnd   } else { $null }
            '@now'      = [datetime]::UtcNow.ToString('o')
            '@manifest' = if ($ManifestJson) { [object]$ManifestJson } else { $null }
            '@summary'  = if ($SummaryJson)  { [object]$SummaryJson  } else { $null }
        } | Out-Null
    } finally { $conn.Close(); $conn.Dispose() }
    return $RunId
}

function Get-CoreRuns {
    <#
    .SYNOPSIS
        Returns all core_run rows for a case, newest first.
    #>
    param([Parameter(Mandatory)][string]$CaseId)
    _RequireDb
    $conn = _Open
    try {
        $rows = _Query -Conn $conn `
            -Sql 'SELECT * FROM core_runs WHERE case_id = @id ORDER BY registered_utc DESC' `
            -P @{ '@id' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

# ── Public: Import tracking ───────────────────────────────────────────────────

function New-Import {
    <#
    .SYNOPSIS
        Opens an import record in state 'pending'.  Returns the import_id.
        The caller must call Complete-Import or Fail-Import when done.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$RunId
    )
    _RequireDb
    $id = [System.Guid]::NewGuid().ToString()
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
INSERT INTO imports(import_id, case_id, run_id, imported_utc, status, schema_version)
VALUES(@id, @cid, @rid, @now, 'pending', @sv)
'@ -P @{
            '@id'  = $id
            '@cid' = $CaseId
            '@rid' = $RunId
            '@now' = [datetime]::UtcNow.ToString('o')
            '@sv'  = $script:SchemaVersion
        } | Out-Null
    } finally { $conn.Close(); $conn.Dispose() }
    return $id
}

function Complete-Import {
    <#
    .SYNOPSIS
        Marks an import as complete and records final counts.
    #>
    param(
        [Parameter(Mandatory)][string]$ImportId,
        [int]$RecordCount  = 0,
        [int]$SkippedCount = 0,
        [int]$FailedCount  = 0
    )
    _RequireDb
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql @'
UPDATE imports
SET status = 'complete', record_count = @rc, skipped_count = @sc, failed_count = @fc
WHERE import_id = @id
'@ -P @{ '@rc' = $RecordCount; '@sc' = $SkippedCount; '@fc' = $FailedCount; '@id' = $ImportId } | Out-Null
    } finally { $conn.Close(); $conn.Dispose() }
}

function Fail-Import {
    <#
    .SYNOPSIS
        Marks an import as failed and stores the error text.
    #>
    param(
        [Parameter(Mandatory)][string]$ImportId,
        [Parameter(Mandatory)][string]$ErrorText
    )
    _RequireDb
    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql `
            "UPDATE imports SET status = 'failed', error_text = @err WHERE import_id = @id" `
            -P @{ '@err' = $ErrorText; '@id' = $ImportId } | Out-Null
    } finally { $conn.Close(); $conn.Dispose() }
}

function Get-Imports {
    <#
    .SYNOPSIS
        Returns imports for a case (and optionally a specific run), newest first.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [string]$RunId = ''
    )
    _RequireDb
    $conn = _Open
    try {
        if ($RunId) {
            $rows = _Query -Conn $conn `
                -Sql 'SELECT * FROM imports WHERE case_id = @cid AND run_id = @rid ORDER BY imported_utc DESC' `
                -P @{ '@cid' = $CaseId; '@rid' = $RunId }
        } else {
            $rows = _Query -Conn $conn `
                -Sql 'SELECT * FROM imports WHERE case_id = @cid ORDER BY imported_utc DESC' `
                -P @{ '@cid' = $CaseId }
        }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Import-RunFolderToCase {
    <#
    .SYNOPSIS
        Imports a Core-produced run folder into the SQLite case store.

        Validation rules:
          - manifest.json, summary.json, and data\*.jsonl must exist
          - dataset key must be analytics-conversation-details-query or analytics-conversation-details
          - explicit schema / normalization major versions other than 1 are rejected

        Import semantics:
          - core_runs row is registered or refreshed from manifest/summary
          - prior complete imports for the same case_id + run_id are marked superseded
          - prior conversation rows for the same case_id + run_id are deleted
          - current rows are inserted in batches inside a single transaction
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$RunFolder,
        [int]$BatchSize = 500
    )
    _RequireDb

    if ($BatchSize -lt 1) { $BatchSize = 500 }
    $case = Get-Case -CaseId $CaseId
    if ($null -eq $case) {
        throw "Case not found: $CaseId"
    }

    $meta  = _ResolveRunImportMetadata -RunFolder $RunFolder
    $runId = Register-CoreRun `
        -CaseId          $CaseId `
        -RunFolder       $meta.RunFolder `
        -RunId           $meta.RunId `
        -DatasetKey      $meta.DatasetKey `
        -Status          $meta.Status `
        -ExtractionStart $meta.ExtractionStart `
        -ExtractionEnd   $meta.ExtractionEnd `
        -ManifestJson    $meta.ManifestJson `
        -SummaryJson     $meta.SummaryJson

    $importId = New-Import -CaseId $CaseId -RunId $runId
    $now      = [datetime]::UtcNow.ToString('o')
    $stats    = @{
        RecordCount  = 0
        SkippedCount = 0
        FailedCount  = 0
    }

    $conn = _Open
    try {
        $tx = $conn.BeginTransaction()
        try {
            _NonQuery -Conn $conn `
                -Sql "UPDATE imports SET status = 'superseded' WHERE case_id = @cid AND run_id = @rid AND status = 'complete'" `
                -P @{ '@cid' = $CaseId; '@rid' = $runId } | Out-Null

            _NonQuery -Conn $conn `
                -Sql 'DELETE FROM conversations WHERE case_id = @cid AND run_id = @rid' `
                -P @{ '@cid' = $CaseId; '@rid' = $runId } | Out-Null

            $batch = New-Object System.Collections.Generic.List[object]
            foreach ($dataFile in $meta.DataFiles) {
                _ImportJsonlFileToConnection `
                    -Conn        $conn `
                    -CaseId      $CaseId `
                    -ImportId    $importId `
                    -RunId       $runId `
                    -RunFolder   $RunFolder `
                    -FilePath    $dataFile `
                    -Batch       $batch `
                    -BatchSize   $BatchSize `
                    -Stats       $stats `
                    -ImportedUtc $now
            }

            if ($batch.Count -gt 0) {
                $result = _WriteConversationRows -Conn $conn -CaseId $CaseId -ImportId $importId -RunId $runId -Rows $batch.ToArray() -ImportedUtc $now
                $stats.RecordCount  += $result.RecordCount
                $stats.SkippedCount += $result.SkippedCount
                $stats.FailedCount  += $result.FailedCount
                $batch.Clear()
            }

            $tx.Commit()
        } catch {
            $tx.Rollback()
            throw
        } finally {
            $tx.Dispose()
        }
    } catch {
        Fail-Import -ImportId $importId -ErrorText $_.Exception.Message
        $connFail = _Open
        try {
            _AuditCaseEvent -Conn $connFail -CaseId $CaseId -EventType 'import.failed' `
                -DetailText "Import failed for run ${runId}: $($_.Exception.Message)"
        } finally { $connFail.Close(); $connFail.Dispose() }
        throw
    } finally {
        $conn.Close()
        $conn.Dispose()
    }

    Complete-Import -ImportId $importId `
        -RecordCount  $stats.RecordCount `
        -SkippedCount $stats.SkippedCount `
        -FailedCount  $stats.FailedCount

    $connComplete = _Open
    try {
        _AuditCaseEvent -Conn $connComplete -CaseId $CaseId -EventType 'import.completed' `
            -DetailText "Imported run $runId into case" `
            -PayloadJson (_ToJsonOrNull @{
                run_id        = $runId
                run_folder    = $RunFolder
                dataset_key   = $meta.DatasetKey
                record_count  = $stats.RecordCount
                skipped_count = $stats.SkippedCount
                failed_count  = $stats.FailedCount
            })
    } finally { $connComplete.Close(); $connComplete.Dispose() }

    return [pscustomobject]@{
        CaseId               = $CaseId
        CaseName             = $case.name
        RunId                = $runId
        RunFolder            = $RunFolder
        DatasetKey           = $meta.DatasetKey
        ImportId             = $importId
        RecordCount          = $stats.RecordCount
        SkippedCount         = $stats.SkippedCount
        FailedCount          = $stats.FailedCount
        ExtractionStart      = $meta.ExtractionStart
        ExtractionEnd        = $meta.ExtractionEnd
        SchemaVersion        = $meta.SchemaVersion
        NormalizationVersion = $meta.NormalizationVersion
    }
}

# ── Public: Conversation storage ──────────────────────────────────────────────

function Import-Conversations {
    <#
    .SYNOPSIS
        Batch-inserts (or replaces) conversation records in a single transaction.

        Each element of Rows must expose these keys/properties (hashtable or pscustomobject):
            conversation_id     – required; rows with empty id are skipped
            direction           – optional string
            media_type          – optional string
            queue_name          – optional string
            disconnect_type     – optional string
            duration_sec        – optional int
            has_hold            – optional bool/int
            has_mos             – optional bool/int
            segment_count       – optional int
            participant_count   – optional int
            conversation_start  – optional ISO-8601 string
            conversation_end    – optional ISO-8601 string
            participants_json   – optional JSON string (side-car)
            attributes_json     – optional JSON string (side-car)
            source_file         – optional relative path
            source_offset       – optional long byte offset

        Uses INSERT OR REPLACE: duplicate conversation_id + case_id overwrites the prior row.
        The rollback on transaction failure propagates the exception to the caller.

    .OUTPUTS
        pscustomobject  RecordCount / SkippedCount / FailedCount
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$ImportId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][object[]]$Rows
    )
    _RequireDb

    $now = [datetime]::UtcNow.ToString('o')

    $conn = _Open
    try {
        $tx = $conn.BeginTransaction()
        try {
            $result = _WriteConversationRows -Conn $conn -CaseId $CaseId -ImportId $ImportId -RunId $RunId -Rows $Rows -ImportedUtc $now
            $tx.Commit()
        } catch {
            $tx.Rollback()
            throw
        } finally {
            $tx.Dispose()
        }
    } finally {
        $conn.Close()
        $conn.Dispose()
    }
    return $result
}

function Get-ConversationCount {
    <#
    .SYNOPSIS
        Returns the total filtered conversation count for a case.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [string]$Direction      = '',
        [string]$MediaType      = '',
        [string]$Queue          = '',
        [string]$SearchText     = '',
        [string]$DisconnectType = '',
        [string]$AgentName      = '',
        [string]$Ani            = '',
        [string]$DivisionId     = '',
        [string]$StartDateTime  = '',
        [string]$EndDateTime    = ''
    )
    _RequireDb
    $where = 'case_id = @cid'
    $p     = @{ '@cid' = $CaseId }
    if ($Direction)      { $where += ' AND direction       = @dir';                                       $p['@dir']    = $Direction      }
    if ($MediaType)      { $where += ' AND media_type      = @media';                                     $p['@media']  = $MediaType      }
    if ($Queue)          { $where += ' AND queue_name      LIKE @queue';                                  $p['@queue']  = "%$Queue%"      }
    if ($SearchText)     { $where += ' AND (conversation_id LIKE @srch OR queue_name LIKE @srch OR agent_names LIKE @srch)'; $p['@srch'] = "%$SearchText%" }
    if ($DisconnectType) { $where += ' AND disconnect_type = @disc';                                      $p['@disc']   = $DisconnectType }
    if ($AgentName)      { $where += ' AND agent_names     LIKE @agent';                                  $p['@agent']  = "%$AgentName%"  }
    if ($Ani)            { $where += ' AND ani             LIKE @ani';                                    $p['@ani']    = "%$Ani%"        }
    if ($DivisionId)     { $where += ' AND division_ids    LIKE @divid';                                  $p['@divid']  = "%$DivisionId%" }
    if ($StartDateTime)  { $where += ' AND conversation_start >= @startDt';                               $p['@startDt'] = $StartDateTime }
    if ($EndDateTime)    { $where += ' AND conversation_start <= @endDt';                                 $p['@endDt']   = $EndDateTime   }

    $conn = _Open
    try {
        return [int](_Scalar -Conn $conn -Sql "SELECT COUNT(*) FROM conversations WHERE $where" -P $p)
    } finally { $conn.Close(); $conn.Dispose() }
}

function Get-ConversationsPage {
    <#
    .SYNOPSIS
        Returns a filtered, paginated page of conversation rows.
        Column names match the existing index entry / display-row shape for UI compatibility.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [int]$PageNumber        = 1,
        [int]$PageSize          = 50,
        [string]$Direction      = '',
        [string]$MediaType      = '',
        [string]$Queue          = '',
        [string]$SearchText     = '',
        [string]$DisconnectType = '',
        [string]$AgentName      = '',
        [string]$Ani            = '',
        [string]$DivisionId     = '',
        [string]$StartDateTime  = '',
        [string]$EndDateTime    = '',
        [string]$SortBy         = 'conversation_start',
        [string]$SortDir        = 'DESC'
    )
    _RequireDb

    # Whitelist sort column to prevent injection.
    $allowedCols = @('conversation_id','direction','media_type','queue_name','disconnect_type',
                     'duration_sec','has_hold','has_mos','segment_count','participant_count',
                     'conversation_start','agent_names','ani')
    if ($SortBy  -notin $allowedCols)    { $SortBy  = 'conversation_start' }
    if ($SortDir -notin @('ASC','DESC')) { $SortDir = 'DESC' }

    $where = 'case_id = @cid'
    $p     = @{ '@cid' = $CaseId }
    if ($Direction)      { $where += ' AND direction       = @dir';                                       $p['@dir']    = $Direction      }
    if ($MediaType)      { $where += ' AND media_type      = @media';                                     $p['@media']  = $MediaType      }
    if ($Queue)          { $where += ' AND queue_name      LIKE @queue';                                  $p['@queue']  = "%$Queue%"      }
    if ($SearchText)     { $where += ' AND (conversation_id LIKE @srch OR queue_name LIKE @srch OR agent_names LIKE @srch)'; $p['@srch'] = "%$SearchText%" }
    if ($DisconnectType) { $where += ' AND disconnect_type = @disc';                                      $p['@disc']   = $DisconnectType }
    if ($AgentName)      { $where += ' AND agent_names     LIKE @agent';                                  $p['@agent']  = "%$AgentName%"  }
    if ($Ani)            { $where += ' AND ani             LIKE @ani';                                    $p['@ani']    = "%$Ani%"        }
    if ($DivisionId)     { $where += ' AND division_ids    LIKE @divid';                                  $p['@divid']  = "%$DivisionId%" }
    if ($StartDateTime)  { $where += ' AND conversation_start >= @startDt';                               $p['@startDt'] = $StartDateTime }
    if ($EndDateTime)    { $where += ' AND conversation_start <= @endDt';                                 $p['@endDt']   = $EndDateTime   }

    $p['@limit']  = $PageSize
    $p['@offset'] = ($PageNumber - 1) * $PageSize

    $sql  = "SELECT * FROM conversations WHERE $where ORDER BY $SortBy $SortDir LIMIT @limit OFFSET @offset"
    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Get-ConversationById {
    <#
    .SYNOPSIS
        Returns a single conversation row by case_id + conversation_id, or $null.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$ConversationId
    )
    _RequireDb
    $conn = _Open
    try {
        $rows = _Query -Conn $conn `
            -Sql 'SELECT * FROM conversations WHERE case_id = @cid AND conversation_id = @cvid' `
            -P @{ '@cid' = $CaseId; '@cvid' = $ConversationId }
    } finally { $conn.Close(); $conn.Dispose() }
    if ($rows.Count -eq 0) { return $null }
    return [pscustomobject]$rows[0]
}

# ── Public: Reference Data (Session 13) ──────────────────────────────────────

function Import-ReferenceDataToCase {
    <#
    .SYNOPSIS
        Imports reference data from a Refresh-ReferenceData folder map into the case store.
    .DESCRIPTION
        Reads the JSONL outputs from each reference dataset run folder and upserts
        rows into the corresponding ref_* tables scoped to the specified case.

        Accepts the hashtable returned by Refresh-ReferenceData (from App.CoreAdapter.psm1).
        Each key is a dataset key; each value is the run folder path (or $null if the
        dataset failed to collect).

        Returns a hashtable of record counts per reference type.
    .PARAMETER CaseId
        Target case identifier.
    .PARAMETER FolderMap
        Hashtable returned by Refresh-ReferenceData.  Keys are dataset keys;
        values are run folder paths (may be $null for datasets that failed).
    #>
    param(
        [Parameter(Mandatory)][string]    $CaseId,
        [Parameter(Mandatory)][hashtable] $FolderMap
    )
    _RequireDb

    $now    = [datetime]::UtcNow.ToString('o')
    $counts = @{
        queues          = 0
        users           = 0
        divisions       = 0
        wrapupCodes     = 0
        skills          = 0
        flows           = 0
        flowOutcomes    = 0
        flowMilestones  = 0
    }

    function _ReadJsonlFromRunFolder ([string]$RunFolder) {
        if ([string]::IsNullOrWhiteSpace($RunFolder) -or -not [System.IO.Directory]::Exists($RunFolder)) {
            return @()
        }
        $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
        if (-not [System.IO.Directory]::Exists($dataDir)) { return @() }
        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($f in [System.IO.Directory]::GetFiles($dataDir, '*.jsonl')) {
            foreach ($line in [System.IO.File]::ReadAllLines($f)) {
                $trimmed = $line.Trim()
                if ($trimmed) {
                    try { $records.Add(($trimmed | ConvertFrom-Json)) } catch {}
                }
            }
        }
        return $records.ToArray()
    }

    $conn = _Open
    try {
        # ref_queues
        $folder = if ($FolderMap.ContainsKey('routing-queues')) { $FolderMap['routing-queues'] } else { $null }
        foreach ($r in (_ReadJsonlFromRunFolder $folder)) {
            $id = [string]$r.id
            if (-not $id) { continue }
            $refId = "$CaseId|queue|$id"
            _NonQuery -Conn $conn -Sql @'
INSERT INTO ref_queues(ref_id, case_id, queue_id, name, description, division_id, media_type, refreshed_at)
VALUES(@rid, @cid, @qid, @name, @desc, @divid, @media, @ts)
ON CONFLICT(ref_id) DO UPDATE SET
    name=excluded.name, description=excluded.description,
    division_id=excluded.division_id, media_type=excluded.media_type, refreshed_at=excluded.refreshed_at
'@ -P @{
                '@rid'   = $refId
                '@cid'   = $CaseId
                '@qid'   = $id
                '@name'  = [string]($r.name)
                '@desc'  = [string]($r.description)
                '@divid' = [string]($r.division.id)
                '@media' = [string]($r.mediaType)
                '@ts'    = $now
            } | Out-Null
            $counts['queues']++
        }

        # ref_users
        $folder = if ($FolderMap.ContainsKey('users')) { $FolderMap['users'] } else { $null }
        foreach ($r in (_ReadJsonlFromRunFolder $folder)) {
            $id = [string]$r.id
            if (-not $id) { continue }
            $refId = "$CaseId|user|$id"
            _NonQuery -Conn $conn -Sql @'
INSERT INTO ref_users(ref_id, case_id, user_id, name, email, department, division_id, state, refreshed_at)
VALUES(@rid, @cid, @uid, @name, @email, @dept, @divid, @state, @ts)
ON CONFLICT(ref_id) DO UPDATE SET
    name=excluded.name, email=excluded.email, department=excluded.department,
    division_id=excluded.division_id, state=excluded.state, refreshed_at=excluded.refreshed_at
'@ -P @{
                '@rid'   = $refId
                '@cid'   = $CaseId
                '@uid'   = $id
                '@name'  = [string]($r.name)
                '@email' = [string]($r.email)
                '@dept'  = [string]($r.department)
                '@divid' = [string]($r.division.id)
                '@state' = [string]($r.state)
                '@ts'    = $now
            } | Out-Null
            $counts['users']++
        }

        # ref_divisions
        $folder = if ($FolderMap.ContainsKey('authorization.get.all.divisions')) { $FolderMap['authorization.get.all.divisions'] } else { $null }
        foreach ($r in (_ReadJsonlFromRunFolder $folder)) {
            $id = [string]$r.id
            if (-not $id) { continue }
            $refId = "$CaseId|division|$id"
            _NonQuery -Conn $conn -Sql @'
INSERT INTO ref_divisions(ref_id, case_id, division_id, name, description, refreshed_at)
VALUES(@rid, @cid, @did, @name, @desc, @ts)
ON CONFLICT(ref_id) DO UPDATE SET name=excluded.name, description=excluded.description, refreshed_at=excluded.refreshed_at
'@ -P @{
                '@rid'  = $refId
                '@cid'  = $CaseId
                '@did'  = $id
                '@name' = [string]($r.name)
                '@desc' = [string]($r.description)
                '@ts'   = $now
            } | Out-Null
            $counts['divisions']++
        }

        # ref_wrapup_codes
        $folder = if ($FolderMap.ContainsKey('routing.get.all.wrapup.codes')) { $FolderMap['routing.get.all.wrapup.codes'] } else { $null }
        foreach ($r in (_ReadJsonlFromRunFolder $folder)) {
            $id = [string]$r.id
            if (-not $id) { continue }
            $refId = "$CaseId|wrapup|$id"
            _NonQuery -Conn $conn -Sql @'
INSERT INTO ref_wrapup_codes(ref_id, case_id, code_id, name, refreshed_at)
VALUES(@rid, @cid, @coid, @name, @ts)
ON CONFLICT(ref_id) DO UPDATE SET name=excluded.name, refreshed_at=excluded.refreshed_at
'@ -P @{
                '@rid'  = $refId
                '@cid'  = $CaseId
                '@coid' = $id
                '@name' = [string]($r.name)
                '@ts'   = $now
            } | Out-Null
            $counts['wrapupCodes']++
        }

        # ref_skills
        $folder = if ($FolderMap.ContainsKey('routing.get.all.routing.skills')) { $FolderMap['routing.get.all.routing.skills'] } else { $null }
        foreach ($r in (_ReadJsonlFromRunFolder $folder)) {
            $id = [string]$r.id
            if (-not $id) { continue }
            $refId = "$CaseId|skill|$id"
            _NonQuery -Conn $conn -Sql @'
INSERT INTO ref_skills(ref_id, case_id, skill_id, name, refreshed_at)
VALUES(@rid, @cid, @sid, @name, @ts)
ON CONFLICT(ref_id) DO UPDATE SET name=excluded.name, refreshed_at=excluded.refreshed_at
'@ -P @{
                '@rid'  = $refId
                '@cid'  = $CaseId
                '@sid'  = $id
                '@name' = [string]($r.name)
                '@ts'   = $now
            } | Out-Null
            $counts['skills']++
        }

        # ref_flows
        $folder = if ($FolderMap.ContainsKey('flows.get.all.flows')) { $FolderMap['flows.get.all.flows'] } else { $null }
        foreach ($r in (_ReadJsonlFromRunFolder $folder)) {
            $id = [string]$r.id
            if (-not $id) { continue }
            $refId = "$CaseId|flow|$id"
            _NonQuery -Conn $conn -Sql @'
INSERT INTO ref_flows(ref_id, case_id, flow_id, name, flow_type, description, refreshed_at)
VALUES(@rid, @cid, @fid, @name, @ftype, @desc, @ts)
ON CONFLICT(ref_id) DO UPDATE SET
    name=excluded.name, flow_type=excluded.flow_type, description=excluded.description, refreshed_at=excluded.refreshed_at
'@ -P @{
                '@rid'   = $refId
                '@cid'   = $CaseId
                '@fid'   = $id
                '@name'  = [string]($r.name)
                '@ftype' = [string]($r.type)
                '@desc'  = [string]($r.description)
                '@ts'    = $now
            } | Out-Null
            $counts['flows']++
        }

        # ref_flow_outcomes
        $folder = if ($FolderMap.ContainsKey('flows.get.flow.outcomes')) { $FolderMap['flows.get.flow.outcomes'] } else { $null }
        foreach ($r in (_ReadJsonlFromRunFolder $folder)) {
            $id = [string]$r.id
            if (-not $id) { continue }
            $refId = "$CaseId|outcome|$id"
            _NonQuery -Conn $conn -Sql @'
INSERT INTO ref_flow_outcomes(ref_id, case_id, outcome_id, name, description, refreshed_at)
VALUES(@rid, @cid, @oid, @name, @desc, @ts)
ON CONFLICT(ref_id) DO UPDATE SET name=excluded.name, description=excluded.description, refreshed_at=excluded.refreshed_at
'@ -P @{
                '@rid'  = $refId
                '@cid'  = $CaseId
                '@oid'  = $id
                '@name' = [string]($r.name)
                '@desc' = [string]($r.description)
                '@ts'   = $now
            } | Out-Null
            $counts['flowOutcomes']++
        }

        # ref_flow_milestones
        $folder = if ($FolderMap.ContainsKey('flows.get.flow.milestones')) { $FolderMap['flows.get.flow.milestones'] } else { $null }
        foreach ($r in (_ReadJsonlFromRunFolder $folder)) {
            $id = [string]$r.id
            if (-not $id) { continue }
            $refId = "$CaseId|milestone|$id"
            _NonQuery -Conn $conn -Sql @'
INSERT INTO ref_flow_milestones(ref_id, case_id, milestone_id, name, description, refreshed_at)
VALUES(@rid, @cid, @mid, @name, @desc, @ts)
ON CONFLICT(ref_id) DO UPDATE SET name=excluded.name, description=excluded.description, refreshed_at=excluded.refreshed_at
'@ -P @{
                '@rid'  = $refId
                '@cid'  = $CaseId
                '@mid'  = $id
                '@name' = [string]($r.name)
                '@desc' = [string]($r.description)
                '@ts'   = $now
            } | Out-Null
            $counts['flowMilestones']++
        }

        _AuditCaseEvent -Conn $conn -CaseId $CaseId -EventType 'reference_data.refreshed' `
            -DetailText "Reference data loaded: queues=$($counts.queues) users=$($counts.users) divisions=$($counts.divisions) wrapupCodes=$($counts.wrapupCodes) skills=$($counts.skills) flows=$($counts.flows)" `
            -PayloadJson (_ToJsonOrNull $counts)

    } finally { $conn.Close(); $conn.Dispose() }

    return $counts
}

function Get-ResolvedName {
    <#
    .SYNOPSIS
        Resolves a Genesys entity ID to a human-readable name from the reference tables.
    .DESCRIPTION
        Pure SQLite helper — looks up the name for a given ID in the reference
        tables for the specified entity type.  Returns $null if no match is found.
        All downstream report queries should use this instead of embedding table JOINs.
    .PARAMETER CaseId
        The case whose reference snapshot to query.
    .PARAMETER Type
        Entity type: queue, user, division, wrapupCode, skill, flow, flowOutcome, flowMilestone.
    .PARAMETER Id
        The GUID to resolve.
    .EXAMPLE
        $queueName = Get-ResolvedName -CaseId $case.case_id -Type queue -Id $row.queue_id
    .EXAMPLE
        $agentName = Get-ResolvedName -CaseId $case.case_id -Type user  -Id $userId
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [Parameter(Mandatory)]
        [ValidateSet('queue','user','division','wrapupCode','skill','flow','flowOutcome','flowMilestone')]
        [string] $Type,
        [Parameter(Mandatory)][string] $Id
    )
    _RequireDb

    $tableMap = @{
        queue          = @{ table = 'ref_queues';          idCol = 'queue_id' }
        user           = @{ table = 'ref_users';           idCol = 'user_id'  }
        division       = @{ table = 'ref_divisions';       idCol = 'division_id' }
        wrapupCode     = @{ table = 'ref_wrapup_codes';    idCol = 'code_id'  }
        skill          = @{ table = 'ref_skills';          idCol = 'skill_id' }
        flow           = @{ table = 'ref_flows';           idCol = 'flow_id'  }
        flowOutcome    = @{ table = 'ref_flow_outcomes';   idCol = 'outcome_id' }
        flowMilestone  = @{ table = 'ref_flow_milestones'; idCol = 'milestone_id' }
    }

    $meta = $tableMap[$Type]
    $sql  = "SELECT name FROM $($meta.table) WHERE case_id = @cid AND $($meta.idCol) = @id LIMIT 1"

    $conn = _Open
    try {
        $val = _Scalar -Conn $conn -Sql $sql -P @{ '@cid' = $CaseId; '@id' = $Id }
    } finally { $conn.Close(); $conn.Dispose() }

    return if ($null -ne $val -and $val -ne [System.DBNull]::Value) { [string]$val } else { $null }
}

Export-ModuleMember -Function `
    Initialize-Database, Test-DatabaseInitialized, `
    New-Case, Get-Case, Get-Cases, Update-CaseState, Update-CaseNotes, Remove-CaseData, `
    Set-CaseExpiry, Get-CaseRetentionStatus, Get-CaseAudit, `
    Set-CaseTags, Get-CaseTags, `
    New-ConversationBookmark, Get-ConversationBookmarks, Remove-ConversationBookmark, `
    New-Finding, Update-Finding, Get-Findings, `
    New-SavedView, Get-SavedViews, Remove-SavedView, `
    New-ReportSnapshot, Get-ReportSnapshots, Remove-ReportSnapshot, `
    Close-Case, Mark-CasePurgeReady, Archive-Case, Purge-Case, `
    Register-CoreRun, Get-CoreRuns, `
    New-Import, Complete-Import, Fail-Import, Get-Imports, Import-RunFolderToCase, `
    Import-Conversations, Get-ConversationCount, Get-ConversationsPage, Get-ConversationById, `
    Import-ReferenceDataToCase, Get-ResolvedName
