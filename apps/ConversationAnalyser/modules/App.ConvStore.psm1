#Requires -Version 5.1
Set-StrictMode -Version Latest

# ── Gate G ────────────────────────────────────────────────────────────────────
# App.ConvStore.psm1 owns ALL PostgreSQL interaction for the application.
# Only this module may:
#   - Load Npgsql.dll
#   - Open NpgsqlConnection objects
#   - Read or write convo.conversation_grid, convo.cases, convo.ingest_runs
#
# DLL resolution order:
#   1. NpgsqlDllPath parameter (from config)
#   2. NPGSQL_DLL environment variable
#   3. .\lib\Npgsql.dll  (repo-relative default)
#
# Requires Npgsql 4.1.x (last release targeting .NET Framework 4.5.2+,
# compatible with Windows PowerShell 5.1).
# ─────────────────────────────────────────────────────────────────────────────

$script:CsInitialized = $false
$script:CsConnStr     = $null

# ── Private: DLL resolution ───────────────────────────────────────────────────

function _CsResolveDll {
    param(
        [string]$ConfigPath = '',
        [string]$AppDir     = ''
    )
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($ConfigPath)       { $candidates.Add($ConfigPath) }
    if ($env:NPGSQL_DLL)   { $candidates.Add($env:NPGSQL_DLL) }
    if ($AppDir) {
        $candidates.Add([System.IO.Path]::Combine($AppDir, 'lib', 'Npgsql.dll'))
    }

    foreach ($c in $candidates) {
        if ([System.IO.File]::Exists($c)) { return $c }
    }

    $tried = ($candidates.ToArray() | ForEach-Object { "  - $_" }) -join "`n"
    throw (
        "Npgsql.dll not found. Paths attempted:`n$tried`n`n" +
        "Resolution: drop Npgsql.dll (4.1.x) into .\lib\  OR  " +
        "set env:NPGSQL_DLL  OR  set ConvStoreNpgsqlDllPath in Settings."
    )
}

function _CsEnsureAssembly {
    param([string]$DllPath)
    $already = [System.AppDomain]::CurrentDomain.GetAssemblies() |
               Where-Object { $_.GetName().Name -eq 'Npgsql' }
    if (-not $already) {
        Add-Type -Path $DllPath -ErrorAction Stop
    }
}

# ── Private: ADO.NET helpers ──────────────────────────────────────────────────

function _CsOpen {
    $c = New-Object Npgsql.NpgsqlConnection($script:CsConnStr)
    $c.Open()
    return $c
}

function _CsCmd {
    param(
        [Npgsql.NpgsqlConnection]$Conn,
        [string]$Sql,
        [hashtable]$P = @{}
    )
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Sql
    foreach ($kv in $P.GetEnumerator()) {
        $param              = New-Object Npgsql.NpgsqlParameter($kv.Key, [System.DBNull]::Value)
        $param.Value        = if ($null -eq $kv.Value) { [System.DBNull]::Value } else { $kv.Value }
        $cmd.Parameters.Add($param) | Out-Null
    }
    return $cmd
}

function _CsNonQuery {
    param(
        [Npgsql.NpgsqlConnection]$Conn,
        [string]$Sql,
        [hashtable]$P = @{}
    )
    $cmd = _CsCmd -Conn $Conn -Sql $Sql -P $P
    try   { return $cmd.ExecuteNonQuery() }
    finally { $cmd.Dispose() }
}

function _CsScalar {
    param(
        [Npgsql.NpgsqlConnection]$Conn,
        [string]$Sql,
        [hashtable]$P = @{}
    )
    $cmd = _CsCmd -Conn $Conn -Sql $Sql -P $P
    try   { return $cmd.ExecuteScalar() }
    finally { $cmd.Dispose() }
}

function _CsQuery {
    param(
        [Npgsql.NpgsqlConnection]$Conn,
        [string]$Sql,
        [hashtable]$P = @{}
    )
    $cmd  = _CsCmd -Conn $Conn -Sql $Sql -P $P
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

# ── Private: guard ────────────────────────────────────────────────────────────

function _RequireCs {
    if (-not $script:CsInitialized) {
        throw 'ConvStore is not initialized. Call Initialize-ConvStore first.'
    }
}

# ── Private: utilities ────────────────────────────────────────────────────────

function _CsObjVal {
    param(
        [object]$Obj,
        [string[]]$Names,
        $Default = $null
    )
    if ($null -eq $Obj) { return $Default }
    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($Obj -is [hashtable]) {
            if ($Obj.ContainsKey($name)) {
                $v = $Obj[$name]
                if ($null -ne $v -and "$v" -ne '') { return $v }
            }
            continue
        }
        $prop = $Obj.PSObject.Properties[$name]
        if ($null -ne $prop) {
            $v = $prop.Value
            if ($null -ne $v -and "$v" -ne '') { return $v }
        }
    }
    return $Default
}

function _CsToJsonOrNull {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    try { return ($Value | ConvertTo-Json -Compress -Depth 20) }
    catch { return $null }
}

# ── Private: extract grid row from raw JSON record ────────────────────────────

function _CsExtractGridRow {
    param(
        [Parameter(Mandatory)][object]$Record,
        [string]$CaseKey      = '',
        [string]$IncidentKey  = '',
        [string]$IngestRunId  = '',
        [datetime]$RetentionExpires = [datetime]::MinValue
    )

    $convId = [string](_CsObjVal $Record @('conversationId') '')
    if ([string]::IsNullOrWhiteSpace($convId)) { return $null }

    $direction     = ''
    $mediaSet      = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $queueSet      = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $agentIdSet    = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $divIdSet      = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $discSet       = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $hasMos        = $false
    $hasHold       = $false
    $segmentCount  = 0
    $partCount     = 0
    $durationMs    = 0L
    $ani           = ''
    $dnis          = ''

    if ($Record.PSObject.Properties['participants']) {
        $participants = @($Record.participants)
        $partCount    = $participants.Count
        foreach ($p in $participants) {
            $purpose    = if ($p.PSObject.Properties['purpose']) { [string]$p.purpose } else { '' }
            $isCustomer = ($purpose -eq 'customer')
            $isAgent    = ($purpose -eq 'agent')
            if ($isAgent -and $p.PSObject.Properties['userId'] -and $p.userId) {
                $agentIdSet.Add([string]$p.userId) | Out-Null
            }
            if (-not $p.PSObject.Properties['sessions']) { continue }
            foreach ($s in @($p.sessions)) {
                if ($s.PSObject.Properties['mediaType'] -and $s.mediaType) {
                    $mediaSet.Add([string]$s.mediaType) | Out-Null
                }
                if ($isCustomer -and -not $direction -and $s.PSObject.Properties['direction'] -and $s.direction) {
                    $direction = [string]$s.direction
                }
                if ($isCustomer) {
                    if (-not $ani  -and $s.PSObject.Properties['ani']  -and $s.ani)  { $ani  = [string]$s.ani  }
                    if (-not $dnis -and $s.PSObject.Properties['dnis'] -and $s.dnis) { $dnis = [string]$s.dnis }
                }
                if ($s.PSObject.Properties['metrics']) {
                    foreach ($m in @($s.metrics)) {
                        if ($m.PSObject.Properties['name'] -and ($m.name -like '*mos*' -or $m.name -like '*Mos*')) {
                            $hasMos = $true
                        }
                    }
                }
                if (-not $s.PSObject.Properties['segments']) { continue }
                foreach ($seg in @($s.segments)) {
                    $segmentCount++
                    if ($seg.PSObject.Properties['segmentType'] -and $seg.segmentType -eq 'hold') { $hasHold = $true }
                    if ($seg.PSObject.Properties['disconnectType'] -and $seg.disconnectType) {
                        $discSet.Add([string]$seg.disconnectType) | Out-Null
                    }
                    if ($seg.PSObject.Properties['queueName'] -and $seg.queueName) {
                        $queueSet.Add([string]$seg.queueName) | Out-Null
                    }
                }
            }
        }
    }

    if ($Record.PSObject.Properties['divisionIds'] -and $null -ne $Record.divisionIds) {
        foreach ($d in @($Record.divisionIds)) {
            if ($d) { $divIdSet.Add([string]$d) | Out-Null }
        }
    }

    $startUtc = $null
    $endUtc   = $null
    try {
        $startStr = [string](_CsObjVal $Record @('conversationStart') '')
        $endStr   = [string](_CsObjVal $Record @('conversationEnd')   '')
        if ($startStr) { $startUtc = [datetime]::Parse($startStr, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) }
        if ($endStr)   { $endUtc   = [datetime]::Parse($endStr,   $null, [System.Globalization.DateTimeStyles]::RoundtripKind) }
        if ($null -ne $startUtc -and $null -ne $endUtc) {
            $durationMs = [long]($endUtc - $startUtc).TotalMilliseconds
        }
    } catch { }

    $payloadJson = _CsToJsonOrNull -Value $Record

    return @{
        conversation_id         = $convId
        ingest_run_id           = if ($IngestRunId) { $IngestRunId } else { $null }
        case_key                = $CaseKey
        incident_key            = $IncidentKey
        originating_direction   = $direction
        media_types             = ($mediaSet.GetEnumerator() | Sort-Object) -join '|'
        queue_names             = ($queueSet.GetEnumerator() | Sort-Object) -join '|'
        agent_ids               = ($agentIdSet.GetEnumerator() | Sort-Object) -join '|'
        division_ids            = ($divIdSet.GetEnumerator() | Sort-Object) -join '|'
        ani                     = $ani
        dnis                    = $dnis
        disconnect_types        = ($discSet.GetEnumerator() | Sort-Object) -join '|'
        duration_ms             = $durationMs
        has_hold                = $hasHold
        has_mos                 = $hasMos
        segment_count           = $segmentCount
        participant_count       = $partCount
        conversation_start_utc  = $startUtc
        conversation_end_utc    = $endUtc
        retention_expires_utc   = if ($RetentionExpires -ne [datetime]::MinValue) { $RetentionExpires } else { $null }
        payload_json            = $payloadJson
    }
}

# ── Private: batch upsert ─────────────────────────────────────────────────────

$script:_CsUpsertSql = @'
INSERT INTO convo.conversation_grid (
    conversation_id, ingest_run_id, case_key, incident_key,
    originating_direction, media_types, queue_names, agent_ids,
    division_ids, ani, dnis, disconnect_types, duration_ms,
    has_hold, has_mos, segment_count, participant_count,
    conversation_start_utc, conversation_end_utc,
    retention_expires_utc, payload_json,
    inserted_utc, updated_utc
) VALUES (
    @convid::uuid, @runid::uuid, @casekey, @inckey,
    @dir, @media, @queue, @agents,
    @divids, @ani, @dnis, @disc, @durms,
    @hold, @mos, @segs, @ptcnt,
    @start, @end,
    @retention, @payload::jsonb,
    NOW(), NOW()
)
ON CONFLICT (conversation_id) DO UPDATE SET
    ingest_run_id          = EXCLUDED.ingest_run_id,
    case_key               = EXCLUDED.case_key,
    incident_key           = EXCLUDED.incident_key,
    originating_direction  = EXCLUDED.originating_direction,
    media_types            = EXCLUDED.media_types,
    queue_names            = EXCLUDED.queue_names,
    agent_ids              = EXCLUDED.agent_ids,
    division_ids           = EXCLUDED.division_ids,
    ani                    = EXCLUDED.ani,
    dnis                   = EXCLUDED.dnis,
    disconnect_types       = EXCLUDED.disconnect_types,
    duration_ms            = EXCLUDED.duration_ms,
    has_hold               = EXCLUDED.has_hold,
    has_mos                = EXCLUDED.has_mos,
    segment_count          = EXCLUDED.segment_count,
    participant_count      = EXCLUDED.participant_count,
    conversation_start_utc = EXCLUDED.conversation_start_utc,
    conversation_end_utc   = EXCLUDED.conversation_end_utc,
    retention_expires_utc  = EXCLUDED.retention_expires_utc,
    payload_json           = EXCLUDED.payload_json,
    updated_utc            = NOW()
'@

function _CsFlushBatch {
    param(
        [Parameter(Mandatory)][Npgsql.NpgsqlConnection]$Conn,
        [Parameter(Mandatory)][System.Collections.Generic.List[hashtable]]$Batch,
        [Parameter(Mandatory)][ref]$Inserted,
        [Parameter(Mandatory)][ref]$Failed
    )

    if ($Batch.Count -eq 0) { return }

    $tx  = $Conn.BeginTransaction()
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $script:_CsUpsertSql
    $cmd.Transaction = $tx

    # Pre-create parameters
    $pNames = '@convid','@runid','@casekey','@inckey',
              '@dir','@media','@queue','@agents',
              '@divids','@ani','@dnis','@disc','@durms',
              '@hold','@mos','@segs','@ptcnt',
              '@start','@end',
              '@retention','@payload'

    $pMap = @{}
    foreach ($n in $pNames) {
        $p = New-Object Npgsql.NpgsqlParameter($n, [System.DBNull]::Value)
        $cmd.Parameters.Add($p) | Out-Null
        $pMap[$n] = $p
    }

    try {
        foreach ($row in $Batch) {
            try {
                $pMap['@convid'   ].Value = [string]$row.conversation_id
                $pMap['@runid'    ].Value = if ($row.ingest_run_id) { [string]$row.ingest_run_id } else { [System.DBNull]::Value }
                $pMap['@casekey'  ].Value = [string]$row.case_key
                $pMap['@inckey'   ].Value = [string]$row.incident_key
                $pMap['@dir'      ].Value = [string]$row.originating_direction
                $pMap['@media'    ].Value = [string]$row.media_types
                $pMap['@queue'    ].Value = [string]$row.queue_names
                $pMap['@agents'   ].Value = [string]$row.agent_ids
                $pMap['@divids'   ].Value = [string]$row.division_ids
                $pMap['@ani'      ].Value = [string]$row.ani
                $pMap['@dnis'     ].Value = [string]$row.dnis
                $pMap['@disc'     ].Value = [string]$row.disconnect_types
                $pMap['@durms'    ].Value = [long]$row.duration_ms
                $pMap['@hold'     ].Value = [bool]$row.has_hold
                $pMap['@mos'      ].Value = [bool]$row.has_mos
                $pMap['@segs'     ].Value = [int]$row.segment_count
                $pMap['@ptcnt'    ].Value = [int]$row.participant_count
                $pMap['@start'    ].Value = if ($null -ne $row.conversation_start_utc) { [datetime]$row.conversation_start_utc } else { [System.DBNull]::Value }
                $pMap['@end'      ].Value = if ($null -ne $row.conversation_end_utc)   { [datetime]$row.conversation_end_utc   } else { [System.DBNull]::Value }
                $pMap['@retention'].Value = if ($null -ne $row.retention_expires_utc)  { [datetime]$row.retention_expires_utc  } else { [System.DBNull]::Value }
                $pMap['@payload'  ].Value = if ($row.payload_json) { [string]$row.payload_json } else { [System.DBNull]::Value }

                $cmd.ExecuteNonQuery() | Out-Null
                $Inserted.Value++
            } catch {
                $Failed.Value++
            }
        }
        $tx.Commit()
    } catch {
        try { $tx.Rollback() } catch { }
        throw
    } finally {
        $cmd.Dispose()
        $tx.Dispose()
    }

    $Batch.Clear()
}

# ── Public: initialization ────────────────────────────────────────────────────

function Initialize-ConvStore {
    <#
    .SYNOPSIS
        Loads Npgsql, validates the connection string, and marks the store ready.
        Non-fatal: callers should catch and store the error in a warning variable.
    #>
    param(
        [string]$ConnStr       = '',
        [string]$NpgsqlDllPath = '',
        [string]$AppDir        = ''
    )

    $script:CsInitialized = $false
    $script:CsConnStr     = $null

    if ([string]::IsNullOrWhiteSpace($ConnStr)) {
        throw 'ConvStoreConnStr is empty. Configure a PostgreSQL connection string in Settings.'
    }

    $dll = _CsResolveDll -ConfigPath $NpgsqlDllPath -AppDir $AppDir
    _CsEnsureAssembly -DllPath $dll

    # Test connectivity
    $conn = New-Object Npgsql.NpgsqlConnection($ConnStr)
    try {
        $conn.Open()
        $conn.Close()
    } finally {
        $conn.Dispose()
    }

    $script:CsConnStr     = $ConnStr
    $script:CsInitialized = $true
}

function Test-ConvStoreReady {
    <#
    .SYNOPSIS
        Returns $true if the ConvStore has been successfully initialized.
    #>
    return $script:CsInitialized
}

function Deploy-ConvStoreSchema {
    <#
    .SYNOPSIS
        Executes conversations_schema_v2.sql against the configured PostgreSQL database.
        Safe to run multiple times (all DDL uses IF NOT EXISTS / CREATE OR REPLACE).
    #>
    param(
        [Parameter(Mandatory)][string]$SchemaFilePath
    )
    _RequireCs
    if (-not [System.IO.File]::Exists($SchemaFilePath)) {
        throw "Schema file not found: $SchemaFilePath"
    }
    $sql  = [System.IO.File]::ReadAllText($SchemaFilePath, [System.Text.Encoding]::UTF8)
    $conn = _CsOpen
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        try   { $cmd.ExecuteNonQuery() | Out-Null }
        finally { $cmd.Dispose() }
    } finally {
        $conn.Close()
        $conn.Dispose()
    }
}

# ── Public: case management ───────────────────────────────────────────────────

function New-ConvStoreCase {
    <#
    .SYNOPSIS
        Creates a new case row in convo.cases. Returns the new case_key.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$CaseKey      = '',
        [string]$IncidentKey  = '',
        [string]$Description  = '',
        [int]$RetentionDays   = 90
    )
    _RequireCs
    if ([string]::IsNullOrWhiteSpace($CaseKey)) {
        $CaseKey = 'case-' + [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N')[0..7] -join '')
    }
    $conn = _CsOpen
    try {
        _CsNonQuery -Conn $conn -Sql @'
INSERT INTO convo.cases (case_key, incident_key, name, description, retention_days)
VALUES (@ckey, @ikey, @name, @desc, @ret)
ON CONFLICT (case_key) DO NOTHING
'@ -P @{
            '@ckey' = $CaseKey
            '@ikey' = $IncidentKey
            '@name' = $Name
            '@desc' = $Description
            '@ret'  = $RetentionDays
        } | Out-Null
    } finally { $conn.Close(); $conn.Dispose() }
    return $CaseKey
}

function Get-ConvStoreCases {
    <#
    .SYNOPSIS
        Returns all cases from convo.cases, newest first.
    #>
    _RequireCs
    $conn = _CsOpen
    try {
        $rows = _CsQuery -Conn $conn -Sql 'SELECT * FROM convo.cases ORDER BY created_utc DESC'
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Get-ConvStoreCase {
    <#
    .SYNOPSIS
        Returns a single case by case_key, or $null.
    #>
    param([Parameter(Mandatory)][string]$CaseKey)
    _RequireCs
    $conn = _CsOpen
    try {
        $rows = _CsQuery -Conn $conn -Sql 'SELECT * FROM convo.cases WHERE case_key = @k' -P @{ '@k' = $CaseKey }
    } finally { $conn.Close(); $conn.Dispose() }
    if ($rows.Count -eq 0) { return $null }
    return [pscustomobject]$rows[0]
}

# ── Public: import ────────────────────────────────────────────────────────────

function Import-RunFolderToConvStore {
    <#
    .SYNOPSIS
        Streams a Core-produced run folder into convo.conversation_grid.
        Reads data\*.jsonl line-by-line in batches of 500 rows per transaction.
        Returns a stats object: InsertedCount, SkippedCount, FailedCount.
    #>
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [string]$CaseKey        = '',
        [string]$IncidentKey    = '',
        [int]$RetentionDays     = 90,
        [int]$BatchSize         = 500
    )
    _RequireCs

    if (-not [System.IO.Directory]::Exists($RunFolder)) {
        throw "Run folder not found: $RunFolder"
    }

    $dataDir   = [System.IO.Path]::Combine($RunFolder, 'data')
    if (-not [System.IO.Directory]::Exists($dataDir)) {
        throw "Run folder is missing data directory: $RunFolder"
    }

    $dataFiles = @([System.IO.Directory]::GetFiles($dataDir, '*.jsonl') | Sort-Object)
    if ($dataFiles.Count -eq 0) {
        throw "Run folder contains no data\*.jsonl files: $RunFolder"
    }

    # Compute retention expiry
    $retentionExpires = if ($RetentionDays -gt 0) {
        [datetime]::UtcNow.AddDays($RetentionDays)
    } else { [datetime]::MinValue }

    # Create an ingest_run record
    $ingestRunId = $null
    $conn = _CsOpen
    try {
        $manifestPath = [System.IO.Path]::Combine($RunFolder, 'manifest.json')
        $runIdVal     = [System.IO.Path]::GetFileName($RunFolder)
        if ([System.IO.File]::Exists($manifestPath)) {
            try {
                $mf = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                $ri = [string](_CsObjVal $mf @('run_id','runId','id') '')
                if ($ri) { $runIdVal = $ri }
            } catch { }
        }

        $row = _CsQuery -Conn $conn -Sql @'
INSERT INTO convo.ingest_runs (request_id, incident_key, case_key, status)
VALUES (@rid, @ikey, @ckey, 'running')
RETURNING ingest_run_id
'@ -P @{ '@rid' = $runIdVal; '@ikey' = $IncidentKey; '@ckey' = $CaseKey }
        if ($row.Count -gt 0) {
            $ingestRunId = [string]$row[0]['ingest_run_id']
        }
    } catch {
        # ingest_run creation is non-fatal
    } finally { $conn.Close(); $conn.Dispose() }

    $inserted = 0
    $skipped  = 0
    $failed   = 0

    $batch = New-Object System.Collections.Generic.List[hashtable]

    $conn = _CsOpen
    try {
        foreach ($filePath in $dataFiles) {
            $sr = New-Object System.IO.StreamReader($filePath, [System.Text.Encoding]::UTF8)
            try {
                while ($null -ne ($line = $sr.ReadLine())) {
                    $line = $line.Trim()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    try {
                        $record = $line | ConvertFrom-Json
                        $row = _CsExtractGridRow `
                            -Record           $record `
                            -CaseKey          $CaseKey `
                            -IncidentKey      $IncidentKey `
                            -IngestRunId      $ingestRunId `
                            -RetentionExpires $retentionExpires
                        if ($null -eq $row) {
                            $skipped++
                        } else {
                            $batch.Add($row)
                            if ($batch.Count -ge $BatchSize) {
                                _CsFlushBatch -Conn $conn -Batch $batch -Inserted ([ref]$inserted) -Failed ([ref]$failed)
                            }
                        }
                    } catch {
                        $skipped++
                    }
                }
            } finally { $sr.Dispose() }
        }

        # Flush remaining rows
        if ($batch.Count -gt 0) {
            _CsFlushBatch -Conn $conn -Batch $batch -Inserted ([ref]$inserted) -Failed ([ref]$failed)
        }
    } finally { $conn.Close(); $conn.Dispose() }

    # Update ingest_run status
    if ($ingestRunId) {
        $conn = _CsOpen
        try {
            _CsNonQuery -Conn $conn -Sql @'
UPDATE convo.ingest_runs
SET status = 'completed', run_completed_utc = NOW(),
    conversation_count = @total, inserted_count = @ins, skipped_count = @skip, error_count = @fail
WHERE ingest_run_id = @rid::uuid
'@ -P @{
                '@total' = $inserted + $skipped + $failed
                '@ins'   = $inserted
                '@skip'  = $skipped
                '@fail'  = $failed
                '@rid'   = $ingestRunId
            } | Out-Null
        } catch { }
        finally { $conn.Close(); $conn.Dispose() }
    }

    return [pscustomobject]@{
        InsertedCount = $inserted
        SkippedCount  = $skipped
        FailedCount   = $failed
    }
}

# ── Public: query ─────────────────────────────────────────────────────────────

function Get-ConvStoreConversationCount {
    <#
    .SYNOPSIS
        Returns the count of rows in conversation_grid matching the given filters.
    #>
    param(
        [string]$CaseKey        = '',
        [string]$Direction      = '',
        [string]$MediaType      = '',
        [string]$Queue          = '',
        [string]$SearchText     = '',
        [string]$DisconnectType = '',
        [string]$AgentId        = '',
        [string]$DivisionId     = '',
        [string]$StartDateTime  = '',
        [string]$EndDateTime    = ''
    )
    _RequireCs

    $where = '1=1'
    $p     = @{}
    if ($CaseKey)        { $where += ' AND case_key               = @ckey';                                              $p['@ckey']    = $CaseKey        }
    if ($Direction)      { $where += ' AND originating_direction   = @dir';                                              $p['@dir']     = $Direction      }
    if ($MediaType)      { $where += ' AND media_types             LIKE @media';                                         $p['@media']   = "%$MediaType%"  }
    if ($Queue)          { $where += ' AND queue_names             ILIKE @queue';                                        $p['@queue']   = "%$Queue%"      }
    if ($SearchText)     { $where += ' AND (conversation_id::text ILIKE @srch OR queue_names ILIKE @srch OR agent_ids ILIKE @srch)'; $p['@srch'] = "%$SearchText%" }
    if ($DisconnectType) { $where += ' AND disconnect_types        ILIKE @disc';                                         $p['@disc']    = "%$DisconnectType%" }
    if ($AgentId)        { $where += ' AND agent_ids               ILIKE @agent';                                        $p['@agent']   = "%$AgentId%"    }
    if ($DivisionId)     { $where += ' AND division_ids            ILIKE @divid';                                        $p['@divid']   = "%$DivisionId%" }
    if ($StartDateTime)  { $where += ' AND conversation_start_utc >= @startDt';                                          $p['@startDt'] = $StartDateTime  }
    if ($EndDateTime)    { $where += ' AND conversation_start_utc <= @endDt';                                            $p['@endDt']   = $EndDateTime    }

    $conn = _CsOpen
    try {
        $v = _CsScalar -Conn $conn -Sql "SELECT COUNT(*) FROM convo.conversation_grid WHERE $where" -P $p
    } finally { $conn.Close(); $conn.Dispose() }
    return [long]$v
}

function Get-ConvStoreConversationsPage {
    <#
    .SYNOPSIS
        Returns a paginated, filtered, sorted page of conversation_grid rows.
        Column names match the conversation_grid table for UI compatibility.
    #>
    param(
        [string]$CaseKey        = '',
        [int]$PageNumber        = 1,
        [int]$PageSize          = 50,
        [string]$Direction      = '',
        [string]$MediaType      = '',
        [string]$Queue          = '',
        [string]$SearchText     = '',
        [string]$DisconnectType = '',
        [string]$AgentId        = '',
        [string]$DivisionId     = '',
        [string]$StartDateTime  = '',
        [string]$EndDateTime    = '',
        [string]$SortBy         = 'conversation_start_utc',
        [string]$SortDir        = 'DESC'
    )
    _RequireCs

    # Whitelist sort column to prevent injection
    $allowedCols = @('conversation_id','originating_direction','media_types','queue_names',
                     'disconnect_types','duration_ms','has_hold','has_mos','segment_count',
                     'participant_count','conversation_start_utc','agent_ids','ani')
    if ($SortBy  -notin $allowedCols)    { $SortBy  = 'conversation_start_utc' }
    if ($SortDir -notin @('ASC','DESC')) { $SortDir = 'DESC' }

    $where = '1=1'
    $p     = @{}
    if ($CaseKey)        { $where += ' AND case_key               = @ckey';                                              $p['@ckey']    = $CaseKey        }
    if ($Direction)      { $where += ' AND originating_direction   = @dir';                                              $p['@dir']     = $Direction      }
    if ($MediaType)      { $where += ' AND media_types             LIKE @media';                                         $p['@media']   = "%$MediaType%"  }
    if ($Queue)          { $where += ' AND queue_names             ILIKE @queue';                                        $p['@queue']   = "%$Queue%"      }
    if ($SearchText)     { $where += ' AND (conversation_id::text ILIKE @srch OR queue_names ILIKE @srch OR agent_ids ILIKE @srch)'; $p['@srch'] = "%$SearchText%" }
    if ($DisconnectType) { $where += ' AND disconnect_types        ILIKE @disc';                                         $p['@disc']    = "%$DisconnectType%" }
    if ($AgentId)        { $where += ' AND agent_ids               ILIKE @agent';                                        $p['@agent']   = "%$AgentId%"    }
    if ($DivisionId)     { $where += ' AND division_ids            ILIKE @divid';                                        $p['@divid']   = "%$DivisionId%" }
    if ($StartDateTime)  { $where += ' AND conversation_start_utc >= @startDt';                                          $p['@startDt'] = $StartDateTime  }
    if ($EndDateTime)    { $where += ' AND conversation_start_utc <= @endDt';                                            $p['@endDt']   = $EndDateTime    }

    $p['@limit']  = $PageSize
    $p['@offset'] = ($PageNumber - 1) * $PageSize

    $sql  = "SELECT * FROM convo.conversation_grid WHERE $where ORDER BY $SortBy $SortDir LIMIT @limit OFFSET @offset"
    $conn = _CsOpen
    try {
        $rows = _CsQuery -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Get-ConvStoreConversationById {
    <#
    .SYNOPSIS
        Returns a single conversation_grid row by conversation_id, or $null.
    #>
    param([Parameter(Mandatory)][string]$ConversationId)
    _RequireCs
    $conn = _CsOpen
    try {
        $rows = _CsQuery -Conn $conn `
            -Sql 'SELECT * FROM convo.conversation_grid WHERE conversation_id = @cvid::uuid' `
            -P @{ '@cvid' = $ConversationId }
    } finally { $conn.Close(); $conn.Dispose() }
    if ($rows.Count -eq 0) { return $null }
    return [pscustomobject]$rows[0]
}

function Get-ConvStoreDisplayRow {
    <#
    .SYNOPSIS
        Returns a lightweight display object from a conversation_grid row.
        Maps PostgreSQL column names to the same PascalCase shape as
        Get-ConversationDisplayRow / Get-DbConversationDisplayRow.
    #>
    param([Parameter(Mandatory)][object]$GridRow)

    $get = {
        param([string]$k, $d = '')
        if ($GridRow -is [hashtable]) {
            $v = $GridRow[$k]
        } else {
            $prop = $GridRow.PSObject.Properties[$k]
            $v    = if ($null -ne $prop) { $prop.Value } else { $null }
        }
        if ($null -eq $v) { return $d } else { return $v }
    }

    $durMs  = [long](& $get 'duration_ms' 0)
    $durSec = [int][math]::Round($durMs / 1000.0)

    $startVal = (& $get 'conversation_start_utc' '')
    $startStr = if ($startVal -is [datetime]) { $startVal.ToString('o') } else { [string]$startVal }

    return [pscustomobject]@{
        ConversationId    = [string](& $get 'conversation_id'       '')
        Direction         = [string](& $get 'originating_direction' '')
        MediaType         = [string](& $get 'media_types'           '')
        Queue             = [string](& $get 'queue_names'           '')
        Disconnect        = [string](& $get 'disconnect_types'      '')
        DurationSec       = $durSec
        HasHold           = [bool]  (& $get 'has_hold'              $false)
        HasMos            = [bool]  (& $get 'has_mos'               $false)
        SegmentCount      = [int]   (& $get 'segment_count'         0)
        ParticipantCount  = [int]   (& $get 'participant_count'     0)
        AgentNames        = [string](& $get 'agent_ids'             '')
        ConversationStart = $startStr
    }
}

function Get-ConvStoreIngestRuns {
    <#
    .SYNOPSIS
        Returns recent ingest_run records, newest first.
    #>
    param([int]$Limit = 50)
    _RequireCs
    $conn = _CsOpen
    try {
        $rows = _CsQuery -Conn $conn `
            -Sql 'SELECT * FROM convo.ingest_runs ORDER BY run_started_utc DESC LIMIT @lim' `
            -P @{ '@lim' = $Limit }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Invoke-ConvStoreRetentionPurge {
    <#
    .SYNOPSIS
        Calls convo.purge_expired() to delete rows past their retention date.
        Returns the number of rows deleted.
    #>
    param([int]$RetentionDays = 0)
    _RequireCs

    # If RetentionDays provided, first backfill any rows missing retention_expires_utc
    if ($RetentionDays -gt 0) {
        $conn = _CsOpen
        try {
            _CsNonQuery -Conn $conn -Sql @'
UPDATE convo.conversation_grid
SET retention_expires_utc = inserted_utc + (@days || ' days')::interval
WHERE retention_expires_utc IS NULL
'@ -P @{ '@days' = [string]$RetentionDays } | Out-Null
        } finally { $conn.Close(); $conn.Dispose() }
    }

    $conn = _CsOpen
    try {
        $deleted = _CsScalar -Conn $conn -Sql 'SELECT convo.purge_expired()'
    } finally { $conn.Close(); $conn.Dispose() }

    return [int]$deleted
}

Export-ModuleMember -Function `
    Initialize-ConvStore, Test-ConvStoreReady, Deploy-ConvStoreSchema, `
    New-ConvStoreCase, Get-ConvStoreCases, Get-ConvStoreCase, `
    Import-RunFolderToConvStore, `
    Get-ConvStoreConversationCount, Get-ConvStoreConversationsPage, `
    Get-ConvStoreConversationById, Get-ConvStoreDisplayRow, `
    Get-ConvStoreIngestRuns, Invoke-ConvStoreRetentionPurge
