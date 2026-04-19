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
# Schema version: 10
# Conversation detail is stored as canonical raw JSON plus flattened and
# normalized analytical dimensions. App.Database.psm1 owns all SQLite access.
# ─────────────────────────────────────────────────────────────────────────────

$script:DbInitialized = $false
$script:ConnStr       = $null
$script:SchemaVersion = 10

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

function _GetSha256Hex {
    param([string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash  = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function _TryParseDateUtc {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try { return ([datetime]::Parse([string]$Value)).ToUniversalTime() } catch { return $null }
}

function _GetDurationSeconds {
    param([object]$Start, [object]$End)
    $s = _TryParseDateUtc $Start
    $e = _TryParseDateUtc $End
    if ($null -eq $s -or $null -eq $e -or $e -lt $s) { return 0 }
    return [int][Math]::Round(($e - $s).TotalSeconds)
}

function _AddDistinctString {
    param(
        [System.Collections.Generic.List[string]]$List,
        [object]$Value
    )
    if ($null -eq $Value) { return }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    if (-not ($List -contains $text)) { $List.Add($text) | Out-Null }
}

function _NewBridgeList {
    return (New-Object System.Collections.Generic.List[object])
}

function _NormalizeFilterState {
    <#
    .SYNOPSIS
        Returns the canonical conversation filter object used by SQL counts,
        pages, population reports, saved views, and exports.
    #>
    param(
        [object]$FilterState = $null,
        [string]$StartDateTimeUtc = '',
        [string]$EndDateTimeUtc = '',
        [string]$Direction = '',
        [string]$MediaType = '',
        [string]$QueueText = '',
        [string]$ConversationId = '',
        [string]$SearchText = '',
        [string]$DisconnectType = '',
        [string]$AgentName = '',
        [string]$Ani = '',
        [string]$DivisionId = '',
        [hashtable]$ColumnFilters = @{},
        [string]$SortBy = 'conversation_start',
        [string]$SortDirection = 'DESC'
    )

    $read = {
        param([string]$Name, $Default = '')
        if ($null -eq $FilterState) { return $Default }
        if ($FilterState -is [hashtable] -and $FilterState.ContainsKey($Name)) {
            $v = $FilterState[$Name]
        } else {
            $prop = $FilterState.PSObject.Properties[$Name]
            $v = if ($null -ne $prop) { $prop.Value } else { $null }
        }
        if ($null -eq $v) { return $Default }
        return $v
    }

    $cols = (& $read 'ColumnFilters' $ColumnFilters)
    if ($null -eq $cols) { $cols = @{} }
    if (-not ($cols -is [hashtable])) {
        $ht = @{}
        foreach ($p in $cols.PSObject.Properties) { $ht[$p.Name] = [string]$p.Value }
        $cols = $ht
    }

    $sortDir = [string](& $read 'SortDirection' $SortDirection)
    if ([string]::IsNullOrWhiteSpace($sortDir)) { $sortDir = $SortDirection }
    $sortDir = $sortDir.ToUpperInvariant()
    if ($sortDir -notin @('ASC','DESC')) { $sortDir = 'DESC' }

    return [pscustomobject][ordered]@{
        StartDateTimeUtc = [string](& $read 'StartDateTimeUtc' $StartDateTimeUtc)
        EndDateTimeUtc   = [string](& $read 'EndDateTimeUtc'   $EndDateTimeUtc)
        Direction        = [string](& $read 'Direction'        $Direction)
        MediaType        = [string](& $read 'MediaType'        $MediaType)
        QueueText        = [string](& $read 'QueueText'        $QueueText)
        ConversationId   = [string](& $read 'ConversationId'   $ConversationId)
        SearchText       = [string](& $read 'SearchText'       $SearchText)
        DisconnectType   = [string](& $read 'DisconnectType'   $DisconnectType)
        AgentName        = [string](& $read 'AgentName'        $AgentName)
        Ani              = [string](& $read 'Ani'              $Ani)
        DivisionId       = [string](& $read 'DivisionId'       $DivisionId)
        ColumnFilters    = $cols
        SortBy           = [string](& $read 'SortBy'           $SortBy)
        SortDirection    = $sortDir
    }
}

function _GetConversationSortClause {
    param(
        [string]$SortBy = 'conversation_start',
        [string]$SortDirection = 'DESC'
    )

    $allowedCols = @{
        conversation_id = 'conversation_id'
        direction = 'direction'
        media_type = 'media_type'
        queue_name = 'queue_name'
        disconnect_type = 'disconnect_type'
        duration_sec = 'duration_sec'
        has_hold = 'has_hold'
        has_mos = 'has_mos'
        segment_count = 'segment_count'
        participant_count = 'participant_count'
        conversation_start = 'conversation_start'
        agent_names = 'agent_names'
        ani = 'ani'
        imported_utc = 'imported_utc'
        newest = 'conversation_start'
        oldest = 'conversation_start'
        longest_duration = 'duration_sec'
        highest_transfer_count = 'transfer_count'
        longest_hold = 'hold_duration_sec'
        lowest_mos = 'mos_min'
        highest_risk_score = 'risk_score'
        conversation_signature_frequency = 'signature_frequency'
        repeated_ani_frequency = 'ani_frequency'
        risk_score = 'risk_score'
        transfer_count = 'transfer_count'
        hold_duration_sec = 'hold_duration_sec'
        mos_min = 'mos_min'
        conversation_signature = 'conversation_signature'
    }
    $displayMap = @{
        ConversationId = 'conversation_id'
        Direction = 'direction'
        MediaType = 'media_type'
        Queue = 'queue_name'
        AgentNames = 'agent_names'
        DurationSec = 'duration_sec'
        Disconnect = 'disconnect_type'
        HasHold = 'has_hold'
        HasMos = 'has_mos'
        SegmentCount = 'segment_count'
        ParticipantCount = 'participant_count'
        ConversationStart = 'conversation_start'
        RiskScore = 'risk_score'
        TransferCount = 'transfer_count'
        HoldDurationSec = 'hold_duration_sec'
        MosMin = 'mos_min'
    }

    if ($displayMap.ContainsKey($SortBy)) { $SortBy = $displayMap[$SortBy] }
    if (-not $allowedCols.ContainsKey($SortBy)) { $SortBy = 'conversation_start' }

    $col = $allowedCols[$SortBy]
    $dir = if ([string]$SortDirection -and ([string]$SortDirection).ToUpperInvariant() -eq 'ASC') { 'ASC' } else { 'DESC' }
    if ($SortBy -eq 'oldest') { $dir = 'ASC' }
    if ($SortBy -eq 'newest') { $dir = 'DESC' }
    if ($SortBy -eq 'lowest_mos') { $dir = 'ASC' }

    if ($col -eq 'signature_frequency') {
        return "(SELECT COUNT(*) FROM conversations c2 WHERE c2.case_id = conversations.case_id AND c2.conversation_signature = conversations.conversation_signature) $dir, conversation_start DESC"
    }
    if ($col -eq 'ani_frequency') {
        return "(SELECT COUNT(*) FROM conversations c2 WHERE c2.case_id = conversations.case_id AND c2.ani = conversations.ani AND c2.ani <> '') $dir, conversation_start DESC"
    }
    return "$col $dir, conversation_id ASC"
}

function _GetConversationWhereClause {
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [object]$FilterState = $null,
        [string]$Direction = '',
        [string]$MediaType = '',
        [string]$Queue = '',
        [string]$SearchText = '',
        [string]$DisconnectType = '',
        [string]$AgentName = '',
        [string]$Ani = '',
        [string]$DivisionId = '',
        [string]$ConversationId = '',
        [string]$StartDateTime = '',
        [string]$EndDateTime = '',
        [hashtable]$ColumnFilters = @{}
    )

    $f = _NormalizeFilterState `
        -FilterState $FilterState `
        -StartDateTimeUtc $StartDateTime `
        -EndDateTimeUtc $EndDateTime `
        -Direction $Direction `
        -MediaType $MediaType `
        -QueueText $Queue `
        -ConversationId $ConversationId `
        -SearchText $SearchText `
        -DisconnectType $DisconnectType `
        -AgentName $AgentName `
        -Ani $Ani `
        -DivisionId $DivisionId `
        -ColumnFilters $ColumnFilters

    $where = 'case_id = @cid'
    $p = @{ '@cid' = $CaseId }

    if ($f.Direction)      { $where += ' AND direction = @dir'; $p['@dir'] = $f.Direction }
    if ($f.MediaType)      { $where += ' AND media_type = @media'; $p['@media'] = $f.MediaType }
    if ($f.QueueText)      { $where += ' AND (queue_name LIKE @queue OR primary_queue LIKE @queue OR final_queue LIKE @queue)'; $p['@queue'] = "%$($f.QueueText)%" }
    if ($f.ConversationId) { $where += ' AND conversation_id = @convId'; $p['@convId'] = $f.ConversationId }
    if ($f.SearchText)     { $where += ' AND (conversation_id LIKE @srch OR queue_name LIKE @srch OR agent_names LIKE @srch OR ani LIKE @srch OR dnis LIKE @srch OR conversation_signature LIKE @srch)'; $p['@srch'] = "%$($f.SearchText)%" }
    if ($f.DisconnectType) { $where += ' AND disconnect_type = @disc'; $p['@disc'] = $f.DisconnectType }
    if ($f.AgentName)      { $where += ' AND agent_names LIKE @agent'; $p['@agent'] = "%$($f.AgentName)%" }
    if ($f.Ani)            { $where += ' AND ani LIKE @ani'; $p['@ani'] = "%$($f.Ani)%" }
    if ($f.DivisionId)     { $where += ' AND division_ids LIKE @divid'; $p['@divid'] = "%$($f.DivisionId)%" }
    if ($f.StartDateTimeUtc) { $where += ' AND conversation_start >= @startDt'; $p['@startDt'] = $f.StartDateTimeUtc }
    if ($f.EndDateTimeUtc)   { $where += ' AND conversation_start <= @endDt'; $p['@endDt'] = $f.EndDateTimeUtc }

    $colMap = @{
        ConversationId = 'conversation_id'
        Direction = 'direction'
        MediaType = 'media_type'
        Queue = 'queue_name'
        AgentNames = 'agent_names'
        DurationSec = 'duration_sec'
        Disconnect = 'disconnect_type'
        HasHold = 'has_hold'
        HasMos = 'has_mos'
        SegmentCount = 'segment_count'
        ParticipantCount = 'participant_count'
        Ani = 'ani'
        Dnis = 'dnis'
        ConversationStart = 'conversation_start'
        PrimaryQueue = 'primary_queue'
        FinalQueue = 'final_queue'
        TransferCount = 'transfer_count'
        HoldDurationSec = 'hold_duration_sec'
        MosMin = 'mos_min'
        RiskScore = 'risk_score'
        ConversationSignature = 'conversation_signature'
        WrapupCode = 'wrapup_code'
        WrapupName = 'wrapup_name'
    }
    $i = 0
    foreach ($key in @($f.ColumnFilters.Keys)) {
        $val = [string]$f.ColumnFilters[$key]
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        if (-not $colMap.ContainsKey($key)) { continue }
        $paramName = "@cf$i"
        $where += " AND CAST($($colMap[$key]) AS TEXT) LIKE $paramName"
        $p[$paramName] = "%$val%"
        $i++
    }

    return [pscustomobject]@{
        Where = $where
        Parameters = $p
        FilterState = $f
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

    $rawJson      = _ToJsonOrNull -Value $Record
    $payloadHash  = _GetSha256Hex -Text $rawJson
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
    $agentNames   = New-Object System.Collections.Generic.List[string]
    $queueNames   = New-Object System.Collections.Generic.List[string]
    $flowIds      = New-Object System.Collections.Generic.List[string]
    $flowNames    = New-Object System.Collections.Generic.List[string]
    $wrapupCodes  = New-Object System.Collections.Generic.List[string]
    $wrapupNames  = New-Object System.Collections.Generic.List[string]
    $mosValues    = New-Object System.Collections.Generic.List[double]
    $divIdSet     = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $agentBridge  = _NewBridgeList
    $queueBridge  = _NewBridgeList
    $divBridge    = _NewBridgeList
    $flowBridge   = _NewBridgeList
    $wrapBridge   = _NewBridgeList

    $transferCount = 0
    $blindTransferCount = 0
    $consultTransferCount = 0
    $holdCount = 0
    $holdDurationSec = 0
    $externalContactPresent = $false
    $customerDisconnect = $false
    $agentDisconnect = $false
    $acdDisconnect = $false
    $containsCallback = $false
    $containsVoicemail = $false

    if ($Record.PSObject.Properties['participants']) {
        $participants = @($Record.participants)
        $partCount    = $participants.Count
        foreach ($p in $participants) {
            $purpose    = if ($p.PSObject.Properties['purpose']) { [string]$p.purpose } else { '' }
            $isCustomer = ($purpose -eq 'customer')
            $isAgent    = ($purpose -eq 'agent')
            if ($isAgent -and $p.PSObject.Properties['userId'] -and $p.userId) {
                _AddDistinctString -List $agentIds -Value $p.userId
                $agentName = [string](_ObjVal $p @('name','userName') '')
                _AddDistinctString -List $agentNames -Value $(if ($agentName) { $agentName } else { $p.userId })
                $agentBridge.Add([pscustomobject]@{
                    user_id = [string]$p.userId
                    user_name = $agentName
                    purpose = $purpose
                }) | Out-Null
            }
            if ($p.PSObject.Properties['divisionId'] -and $p.divisionId) {
                $divIdSet.Add([string]$p.divisionId) | Out-Null
                $divBridge.Add([pscustomobject]@{ division_id = [string]$p.divisionId; source = 'participant' }) | Out-Null
            }
            if ($p.PSObject.Properties['externalContactId'] -and $p.externalContactId) {
                $externalContactPresent = $true
            }
            if (-not $p.PSObject.Properties['sessions']) { continue }
            foreach ($s in @($p.sessions)) {
                if (-not $mediaType -and $s.PSObject.Properties['mediaType']) {
                    $mediaType = [string]$s.mediaType
                }
                if ($s.PSObject.Properties['mediaType'] -and [string]$s.mediaType -match 'callback') { $containsCallback = $true }
                if ($s.PSObject.Properties['mediaType'] -and [string]$s.mediaType -match 'voicemail') { $containsVoicemail = $true }
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
                            foreach ($prop in $m.PSObject.Properties) {
                                if ($prop.Value -is [double] -or $prop.Value -is [int] -or $prop.Value -is [long] -or $prop.Value -is [decimal]) {
                                    $mosValues.Add([double]$prop.Value) | Out-Null
                                }
                            }
                            if ($m.PSObject.Properties['stats'] -and $null -ne $m.stats) {
                                foreach ($sp in $m.stats.PSObject.Properties) {
                                    if ($sp.Value -is [double] -or $sp.Value -is [int] -or $sp.Value -is [long] -or $sp.Value -is [decimal]) {
                                        $mosValues.Add([double]$sp.Value) | Out-Null
                                    }
                                }
                            }
                        }
                    }
                }
                if ($s.PSObject.Properties['flow'] -and $null -ne $s.flow) {
                    $fid = [string](_ObjVal $s.flow @('id','flowId') '')
                    $fname = [string](_ObjVal $s.flow @('name','flowName') '')
                    _AddDistinctString -List $flowIds -Value $fid
                    _AddDistinctString -List $flowNames -Value $fname
                    if ($fid -or $fname) { $flowBridge.Add([pscustomobject]@{ flow_id = $fid; flow_name = $fname }) | Out-Null }
                }
                if (-not $s.PSObject.Properties['segments']) { continue }
                foreach ($seg in @($s.segments)) {
                    $segmentCount++
                    $segType = if ($seg.PSObject.Properties['segmentType']) { [string]$seg.segmentType } else { '' }
                    if ($segType -eq 'hold') {
                        $hasHold = $true
                        $holdCount++
                        $holdDurationSec += _GetDurationSeconds -Start (_ObjVal $seg @('segmentStart') $null) -End (_ObjVal $seg @('segmentEnd') $null)
                    }
                    if ($segType -match 'transfer') {
                        $transferCount++
                        if ($segType -match 'blind') { $blindTransferCount++ }
                        if ($segType -match 'consult') { $consultTransferCount++ }
                    }
                    if (-not $disconnect -and $seg.PSObject.Properties['disconnectType']) {
                        $disconnect = [string]$seg.disconnectType
                    }
                    if ($seg.PSObject.Properties['disconnectType'] -and $seg.disconnectType) {
                        $disc = [string]$seg.disconnectType
                        if ($isCustomer -or $disc -match 'client|customer|peer') { $customerDisconnect = $true }
                        if ($isAgent -or $disc -match 'agent|endpoint') { $agentDisconnect = $true }
                        if ($disc -match 'acd|system|transfer') { $acdDisconnect = $true }
                    }
                    if (-not $queue -and $seg.PSObject.Properties['queueName']) {
                        $queue = [string]$seg.queueName
                    }
                    $qid = [string](_ObjVal $seg @('queueId') '')
                    $qname = [string](_ObjVal $seg @('queueName') '')
                    _AddDistinctString -List $queueNames -Value $qname
                    if ($qid -or $qname) {
                        $queueBridge.Add([pscustomobject]@{ queue_id = $qid; queue_name = $qname; purpose = $purpose }) | Out-Null
                    }
                    $fid = [string](_ObjVal $seg @('flowId') '')
                    $fname = [string](_ObjVal $seg @('flowName') '')
                    _AddDistinctString -List $flowIds -Value $fid
                    _AddDistinctString -List $flowNames -Value $fname
                    if ($fid -or $fname) { $flowBridge.Add([pscustomobject]@{ flow_id = $fid; flow_name = $fname }) | Out-Null }

                    $wcode = [string](_ObjVal $seg @('wrapUpCode','wrapupCode','wrapupCodeId') '')
                    $wname = [string](_ObjVal $seg @('wrapUpCodeName','wrapupCodeName','wrapupName') '')
                    _AddDistinctString -List $wrapupCodes -Value $wcode
                    _AddDistinctString -List $wrapupNames -Value $wname
                    if ($wcode -or $wname) {
                        $wrapBridge.Add([pscustomobject]@{ wrapup_code = $wcode; wrapup_name = $wname }) | Out-Null
                    }
                    if (($seg | ConvertTo-Json -Compress -Depth 8) -match 'callback') { $containsCallback = $true }
                    if (($seg | ConvertTo-Json -Compress -Depth 8) -match 'voicemail') { $containsVoicemail = $true }
                }
            }
        }
    }

    # Division IDs from top-level divisionIds array
    if ($Record.PSObject.Properties['divisionIds'] -and $null -ne $Record.divisionIds) {
        foreach ($d in @($Record.divisionIds)) {
            if ($d) {
                $divIdSet.Add([string]$d) | Out-Null
                $divBridge.Add([pscustomobject]@{ division_id = [string]$d; source = 'top_level' }) | Out-Null
            }
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

    $primaryQueue = if ($queueNames.Count -gt 0) { $queueNames[0] } else { $queue }
    $finalQueue   = if ($queueNames.Count -gt 0) { $queueNames[$queueNames.Count - 1] } else { $queue }
    $mosMin = $null
    $mosMax = $null
    $mosAvg = $null
    if ($mosValues.Count -gt 0) {
        $mosMin = [double]($mosValues | Measure-Object -Minimum).Minimum
        $mosMax = [double]($mosValues | Measure-Object -Maximum).Maximum
        $mosAvg = [double]($mosValues | Measure-Object -Average).Average
    }
    $wrapupCode = if ($wrapupCodes.Count -gt 0) { $wrapupCodes[0] } else { '' }
    $wrapupName = if ($wrapupNames.Count -gt 0) { $wrapupNames[0] } else { '' }
    $flowId = if ($flowIds.Count -gt 0) { $flowIds[0] } else { '' }
    $flowName = if ($flowNames.Count -gt 0) { $flowNames[0] } else { '' }
    $signature = (@($direction, $mediaType, $primaryQueue, $finalQueue, $transferCount, $disconnect, $wrapupCode) | ForEach-Object { [string]$_ }) -join '|'
    $flags = New-Object System.Collections.Generic.List[string]
    if ($transferCount -ge 2) { $flags.Add('multi_transfer') | Out-Null }
    if ($holdDurationSec -ge 300) { $flags.Add('long_hold') | Out-Null }
    if ($hasMos -and $null -ne $mosMin -and $mosMin -lt 3.5) { $flags.Add('low_mos') | Out-Null }
    if (-not $primaryQueue) { $flags.Add('missing_queue') | Out-Null }
    if ($agentIds.Count -eq 0) { $flags.Add('missing_agent') | Out-Null }
    if ($customerDisconnect) { $flags.Add('customer_disconnect') | Out-Null }
    if ($acdDisconnect) { $flags.Add('acd_disconnect') | Out-Null }
    $riskScore = 0
    $riskScore += [Math]::Min(30, $transferCount * 10)
    if ($holdDurationSec -gt 0) { $riskScore += [Math]::Min(25, [int]($holdDurationSec / 60)) }
    if ($hasMos -and $null -ne $mosMin -and $mosMin -lt 3.5) { $riskScore += 25 }
    if ($customerDisconnect) { $riskScore += 10 }
    if ($acdDisconnect) { $riskScore += 10 }
    if ($riskScore -gt 100) { $riskScore = 100 }

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
        raw_json           = $rawJson
        payload_hash       = $payloadHash
        source_file        = $RelativePath
        source_offset      = $ByteOffset
        agent_names        = if ($agentNames.Count -gt 0) { ($agentNames | Select-Object -Unique) -join '|' } else { ($agentIds | Select-Object -Unique) -join '|' }
        division_ids       = ($divIdSet.GetEnumerator() | ForEach-Object { $_ }) -join '|'
        ani                = $ani
        dnis               = $dnis
        primary_queue      = $primaryQueue
        final_queue        = $finalQueue
        queue_count        = @($queueNames | Select-Object -Unique).Count
        agent_count        = @($agentIds | Select-Object -Unique).Count
        transfer_count     = $transferCount
        blind_transfer_count = $blindTransferCount
        consult_transfer_count = $consultTransferCount
        hold_count         = $holdCount
        hold_duration_sec  = $holdDurationSec
        mos_min            = $mosMin
        mos_max            = $mosMax
        mos_avg            = $mosAvg
        wrapup_code        = $wrapupCode
        wrapup_name        = $wrapupName
        flow_id            = $flowId
        flow_name          = $flowName
        external_contact_present = $externalContactPresent
        customer_disconnect = $customerDisconnect
        agent_disconnect   = $agentDisconnect
        acd_disconnect     = $acdDisconnect
        contains_callback  = $containsCallback
        contains_voicemail = $containsVoicemail
        conversation_signature = $signature
        anomaly_flags      = ($flags.ToArray() -join '|')
        risk_score         = $riskScore
        _bridge_agents     = $agentBridge.ToArray()
        _bridge_queues     = $queueBridge.ToArray()
        _bridge_divisions  = $divBridge.ToArray()
        _bridge_flows      = $flowBridge.ToArray()
        _bridge_wrapups    = $wrapBridge.ToArray()
    }
}

function _WriteConversationLineageAndBridges {
    param(
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteConnection]$Conn,
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$ImportId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][object]$Row,
        [Parameter(Mandatory)][string]$ImportedUtc
    )

    $cvid = [string](_RowVal $Row 'conversation_id' '')
    if ([string]::IsNullOrWhiteSpace($cvid)) { return }

    _NonQuery -Conn $Conn -Sql @'
INSERT INTO conversation_versions(
    version_id, case_id, conversation_id, import_id, run_id,
    source_file, source_offset, imported_utc, payload_hash, raw_json)
VALUES(@vid, @cid, @cvid, @iid, @rid, @srcf, @srco, @now, @hash, @raw)
'@ -P @{
        '@vid'  = [System.Guid]::NewGuid().ToString()
        '@cid'  = $CaseId
        '@cvid' = $cvid
        '@iid'  = $ImportId
        '@rid'  = $RunId
        '@srcf' = [string](_RowVal $Row 'source_file' '')
        '@srco' = [long](_RowVal $Row 'source_offset' 0)
        '@now'  = $ImportedUtc
        '@hash' = [string](_RowVal $Row 'payload_hash' '')
        '@raw'  = if (_RowVal $Row 'raw_json' $null) { [object](_RowVal $Row 'raw_json' '') } else { $null }
    } | Out-Null

    foreach ($tbl in @('conversation_agents','conversation_queues','conversation_divisions','conversation_flows','conversation_wrapups')) {
        _NonQuery -Conn $Conn -Sql "DELETE FROM $tbl WHERE case_id = @cid AND conversation_id = @cvid" -P @{ '@cid' = $CaseId; '@cvid' = $cvid } | Out-Null
    }

    foreach ($a in @(_RowVal $Row '_bridge_agents' @())) {
        _NonQuery -Conn $Conn -Sql @'
INSERT OR IGNORE INTO conversation_agents(case_id, conversation_id, import_id, run_id, user_id, user_name, purpose, imported_utc)
VALUES(@cid, @cvid, @iid, @rid, @uid, @uname, @purpose, @now)
'@ -P @{
            '@cid' = $CaseId; '@cvid' = $cvid; '@iid' = $ImportId; '@rid' = $RunId
            '@uid' = [string](_RowVal $a 'user_id' ''); '@uname' = [string](_RowVal $a 'user_name' '')
            '@purpose' = [string](_RowVal $a 'purpose' ''); '@now' = $ImportedUtc
        } | Out-Null
    }
    foreach ($q in @(_RowVal $Row '_bridge_queues' @())) {
        _NonQuery -Conn $Conn -Sql @'
INSERT OR IGNORE INTO conversation_queues(case_id, conversation_id, import_id, run_id, queue_id, queue_name, purpose, imported_utc)
VALUES(@cid, @cvid, @iid, @rid, @qid, @qname, @purpose, @now)
'@ -P @{
            '@cid' = $CaseId; '@cvid' = $cvid; '@iid' = $ImportId; '@rid' = $RunId
            '@qid' = [string](_RowVal $q 'queue_id' ''); '@qname' = [string](_RowVal $q 'queue_name' '')
            '@purpose' = [string](_RowVal $q 'purpose' ''); '@now' = $ImportedUtc
        } | Out-Null
    }
    foreach ($d in @(_RowVal $Row '_bridge_divisions' @())) {
        _NonQuery -Conn $Conn -Sql @'
INSERT OR IGNORE INTO conversation_divisions(case_id, conversation_id, import_id, run_id, division_id, source, imported_utc)
VALUES(@cid, @cvid, @iid, @rid, @did, @source, @now)
'@ -P @{
            '@cid' = $CaseId; '@cvid' = $cvid; '@iid' = $ImportId; '@rid' = $RunId
            '@did' = [string](_RowVal $d 'division_id' ''); '@source' = [string](_RowVal $d 'source' '')
            '@now' = $ImportedUtc
        } | Out-Null
    }
    foreach ($f in @(_RowVal $Row '_bridge_flows' @())) {
        _NonQuery -Conn $Conn -Sql @'
INSERT OR IGNORE INTO conversation_flows(case_id, conversation_id, import_id, run_id, flow_id, flow_name, imported_utc)
VALUES(@cid, @cvid, @iid, @rid, @fid, @fname, @now)
'@ -P @{
            '@cid' = $CaseId; '@cvid' = $cvid; '@iid' = $ImportId; '@rid' = $RunId
            '@fid' = [string](_RowVal $f 'flow_id' ''); '@fname' = [string](_RowVal $f 'flow_name' '')
            '@now' = $ImportedUtc
        } | Out-Null
    }
    foreach ($w in @(_RowVal $Row '_bridge_wrapups' @())) {
        _NonQuery -Conn $Conn -Sql @'
INSERT OR IGNORE INTO conversation_wrapups(case_id, conversation_id, import_id, run_id, wrapup_code, wrapup_name, imported_utc)
VALUES(@cid, @cvid, @iid, @rid, @wcode, @wname, @now)
'@ -P @{
            '@cid' = $CaseId; '@cvid' = $cvid; '@iid' = $ImportId; '@rid' = $RunId
            '@wcode' = [string](_RowVal $w 'wrapup_code' ''); '@wname' = [string](_RowVal $w 'wrapup_name' '')
            '@now' = $ImportedUtc
        } | Out-Null
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
     participants_json, attributes_json, raw_json, payload_hash,
     source_file, source_offset, imported_utc,
     agent_names, division_ids, ani, dnis,
     primary_queue, final_queue, queue_count, agent_count,
     transfer_count, blind_transfer_count, consult_transfer_count,
     hold_count, hold_duration_sec, mos_min, mos_max, mos_avg,
     wrapup_code, wrapup_name, flow_id, flow_name,
     external_contact_present, customer_disconnect, agent_disconnect, acd_disconnect,
     contains_callback, contains_voicemail, conversation_signature, anomaly_flags, risk_score)
VALUES
    (@cvid, @cid, @iid, @rid,
     @dir, @media, @queue, @disc,
     @dur, @hold, @mos, @segs, @ptcnt,
     @start, @end,
     @ptjson, @atjson, @rawjson, @hash,
     @srcf, @srco, @now,
     @anames, @divids, @ani, @dnis,
     @pqueue, @fqueue, @qcnt, @acnt,
     @xcnt, @bxcnt, @cxcnt,
     @hcnt, @hdur, @mosmin, @mosmax, @mosavg,
     @wcode, @wname, @flowid, @flowname,
     @extcontact, @custdisc, @agentdisc, @acddisc,
     @callback, @voicemail, @signature, @flags, @risk)
'@

    $pNames = '@cvid','@cid','@iid','@rid',
              '@dir','@media','@queue','@disc',
              '@dur','@hold','@mos','@segs','@ptcnt',
              '@start','@end',
              '@ptjson','@atjson','@rawjson','@hash',
              '@srcf','@srco','@now',
              '@anames','@divids','@ani','@dnis',
              '@pqueue','@fqueue','@qcnt','@acnt',
              '@xcnt','@bxcnt','@cxcnt',
              '@hcnt','@hdur','@mosmin','@mosmax','@mosavg',
              '@wcode','@wname','@flowid','@flowname',
              '@extcontact','@custdisc','@agentdisc','@acddisc',
              '@callback','@voicemail','@signature','@flags','@risk'
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
                $raw = _RowVal $row 'raw_json'           $null
                $pMap['@ptjson'].Value = if ($null -ne $ptj) { [object]$ptj } else { [System.DBNull]::Value }
                $pMap['@atjson'].Value = if ($null -ne $atj) { [object]$atj } else { [System.DBNull]::Value }
                $pMap['@rawjson'].Value = if ($null -ne $raw) { [object]$raw } else { [System.DBNull]::Value }
                $pMap['@hash'  ].Value = [string](_RowVal $row 'payload_hash' '')

                $pMap['@srcf'  ].Value = [string](_RowVal $row 'source_file'   '')
                $pMap['@srco'  ].Value = [long]  (_RowVal $row 'source_offset'  0)
                $pMap['@now'   ].Value = $ImportedUtc
                $pMap['@anames'].Value = [string](_RowVal $row 'agent_names'   '')
                $pMap['@divids'].Value = [string](_RowVal $row 'division_ids'  '')
                $pMap['@ani'   ].Value = [string](_RowVal $row 'ani'           '')
                $pMap['@dnis'  ].Value = [string](_RowVal $row 'dnis'          '')
                $pMap['@pqueue'].Value = [string](_RowVal $row 'primary_queue' '')
                $pMap['@fqueue'].Value = [string](_RowVal $row 'final_queue' '')
                $pMap['@qcnt'  ].Value = [int](_RowVal $row 'queue_count' 0)
                $pMap['@acnt'  ].Value = [int](_RowVal $row 'agent_count' 0)
                $pMap['@xcnt'  ].Value = [int](_RowVal $row 'transfer_count' 0)
                $pMap['@bxcnt' ].Value = [int](_RowVal $row 'blind_transfer_count' 0)
                $pMap['@cxcnt' ].Value = [int](_RowVal $row 'consult_transfer_count' 0)
                $pMap['@hcnt'  ].Value = [int](_RowVal $row 'hold_count' 0)
                $pMap['@hdur'  ].Value = [int](_RowVal $row 'hold_duration_sec' 0)
                foreach ($pair in @(
                    @{ Name='@mosmin'; Key='mos_min' },
                    @{ Name='@mosmax'; Key='mos_max' },
                    @{ Name='@mosavg'; Key='mos_avg' }
                )) {
                    $mv = _RowVal $row $pair['Key'] $null
                    $pMap[$pair['Name']].Value = if ($null -ne $mv) { [double]$mv } else { [System.DBNull]::Value }
                }
                $pMap['@wcode' ].Value = [string](_RowVal $row 'wrapup_code' '')
                $pMap['@wname' ].Value = [string](_RowVal $row 'wrapup_name' '')
                $pMap['@flowid'].Value = [string](_RowVal $row 'flow_id' '')
                $pMap['@flowname'].Value = [string](_RowVal $row 'flow_name' '')
                $pMap['@extcontact'].Value = [int](if ([bool](_RowVal $row 'external_contact_present' $false)) { 1 } else { 0 })
                $pMap['@custdisc'  ].Value = [int](if ([bool](_RowVal $row 'customer_disconnect' $false)) { 1 } else { 0 })
                $pMap['@agentdisc' ].Value = [int](if ([bool](_RowVal $row 'agent_disconnect' $false)) { 1 } else { 0 })
                $pMap['@acddisc'   ].Value = [int](if ([bool](_RowVal $row 'acd_disconnect' $false)) { 1 } else { 0 })
                $pMap['@callback'  ].Value = [int](if ([bool](_RowVal $row 'contains_callback' $false)) { 1 } else { 0 })
                $pMap['@voicemail' ].Value = [int](if ([bool](_RowVal $row 'contains_voicemail' $false)) { 1 } else { 0 })
                $pMap['@signature' ].Value = [string](_RowVal $row 'conversation_signature' '')
                $pMap['@flags'     ].Value = [string](_RowVal $row 'anomaly_flags' '')
                $pMap['@risk'      ].Value = [int](_RowVal $row 'risk_score' 0)

                $cmd.ExecuteNonQuery() | Out-Null
                _WriteConversationLineageAndBridges -Conn $Conn -CaseId $CaseId -ImportId $ImportId -RunId $RunId -Row $row -ImportedUtc $ImportedUtc
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

    # Schema v5 — Queue Performance aggregate report table (Session 14)
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_queue_perf (
    row_id              TEXT    PRIMARY KEY,
    case_id             TEXT    NOT NULL REFERENCES cases(case_id),
    queue_id            TEXT    NOT NULL DEFAULT '',
    queue_name          TEXT    NOT NULL DEFAULT '',
    division_id         TEXT    NOT NULL DEFAULT '',
    division_name       TEXT    NOT NULL DEFAULT '',
    interval_start      TEXT    NOT NULL DEFAULT '',
    n_offered           INTEGER NOT NULL DEFAULT 0,
    n_connected         INTEGER NOT NULL DEFAULT 0,
    n_abandoned         INTEGER NOT NULL DEFAULT 0,
    abandon_rate_pct    REAL    NOT NULL DEFAULT 0,
    t_handle_avg_sec    REAL    NOT NULL DEFAULT 0,
    t_talk_avg_sec      REAL    NOT NULL DEFAULT 0,
    t_acw_avg_sec       REAL    NOT NULL DEFAULT 0,
    n_answered_in_20    INTEGER NOT NULL DEFAULT 0,
    n_answered_in_30    INTEGER NOT NULL DEFAULT 0,
    n_answered_in_60    INTEGER NOT NULL DEFAULT 0,
    service_level_pct   REAL    NOT NULL DEFAULT 0,
    imported_utc        TEXT    NOT NULL DEFAULT ''
)
'@ | Out-Null

    # v5 indexes
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_qperf_case_id       ON report_queue_perf(case_id)'      | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_qperf_queue_id      ON report_queue_perf(queue_id)'     | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_qperf_division_id   ON report_queue_perf(division_id)'  | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_qperf_interval      ON report_queue_perf(interval_start)'| Out-Null

    # Schema v6 — Agent Performance aggregate report table (Session 15)
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_agent_perf (
    row_id              TEXT    PRIMARY KEY,
    case_id             TEXT    NOT NULL REFERENCES cases(case_id),
    user_id             TEXT    NOT NULL DEFAULT '',
    user_name           TEXT    NOT NULL DEFAULT '',
    user_email          TEXT    NOT NULL DEFAULT '',
    department          TEXT    NOT NULL DEFAULT '',
    division_id         TEXT    NOT NULL DEFAULT '',
    division_name       TEXT    NOT NULL DEFAULT '',
    queue_ids           TEXT    NOT NULL DEFAULT '',
    n_connected         INTEGER NOT NULL DEFAULT 0,
    n_offered           INTEGER NOT NULL DEFAULT 0,
    t_handle_avg_sec    REAL    NOT NULL DEFAULT 0,
    t_talk_avg_sec      REAL    NOT NULL DEFAULT 0,
    t_acw_avg_sec       REAL    NOT NULL DEFAULT 0,
    t_on_queue_sec      REAL    NOT NULL DEFAULT 0,
    t_off_queue_sec     REAL    NOT NULL DEFAULT 0,
    t_idle_sec          REAL    NOT NULL DEFAULT 0,
    talk_ratio_pct      REAL    NOT NULL DEFAULT 0,
    acw_ratio_pct       REAL    NOT NULL DEFAULT 0,
    idle_ratio_pct      REAL    NOT NULL DEFAULT 0,
    imported_utc        TEXT    NOT NULL DEFAULT ''
)
'@ | Out-Null

    # v6 indexes
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_aperf_case_id       ON report_agent_perf(case_id)'      | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_aperf_user_id       ON report_agent_perf(user_id)'      | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_aperf_division_id   ON report_agent_perf(division_id)'  | Out-Null

    # Schema v7 — Transfer & Escalation Chain report tables (Session 16)
    # report_transfer_flows : per queue-to-queue pair, transfer count by type
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_transfer_flows (
    row_id               TEXT    PRIMARY KEY,
    case_id              TEXT    NOT NULL REFERENCES cases(case_id),
    queue_id_from        TEXT    NOT NULL DEFAULT '',
    queue_name_from      TEXT    NOT NULL DEFAULT '',
    queue_id_to          TEXT    NOT NULL DEFAULT '',
    queue_name_to        TEXT    NOT NULL DEFAULT '',
    transfer_type        TEXT    NOT NULL DEFAULT '',
    n_transfers          INTEGER NOT NULL DEFAULT 0,
    pct_of_total_offered REAL    NOT NULL DEFAULT 0,
    imported_utc         TEXT    NOT NULL DEFAULT ''
)
'@ | Out-Null

    # report_transfer_chains : per conversation, the ordered queue-hop sequence
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_transfer_chains (
    row_id                  TEXT    PRIMARY KEY,
    case_id                 TEXT    NOT NULL REFERENCES cases(case_id),
    conversation_id         TEXT    NOT NULL DEFAULT '',
    transfer_sequence       TEXT    NOT NULL DEFAULT '',
    hop_count               INTEGER NOT NULL DEFAULT 0,
    final_queue_name        TEXT    NOT NULL DEFAULT '',
    final_disconnect_type   TEXT    NOT NULL DEFAULT '',
    has_blind_transfer      INTEGER NOT NULL DEFAULT 0,
    has_consult_transfer    INTEGER NOT NULL DEFAULT 0,
    imported_utc            TEXT    NOT NULL DEFAULT ''
)
'@ | Out-Null

    # v7 indexes
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_xfer_flows_case      ON report_transfer_flows(case_id)'            | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_xfer_flows_from      ON report_transfer_flows(queue_id_from)'      | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_xfer_flows_to        ON report_transfer_flows(queue_id_to)'        | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_xfer_chains_case     ON report_transfer_chains(case_id)'           | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_xfer_chains_conv     ON report_transfer_chains(conversation_id)'   | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_xfer_chains_hop      ON report_transfer_chains(hop_count)'         | Out-Null

    # Schema v8 — Flow & IVR containment report tables (Session 17)
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_flow_perf (
    row_id                  TEXT    PRIMARY KEY,
    case_id                 TEXT    NOT NULL REFERENCES cases(case_id),
    flow_id                 TEXT    NOT NULL DEFAULT '',
    flow_name               TEXT    NOT NULL DEFAULT '',
    flow_type               TEXT    NOT NULL DEFAULT '',
    division_id             TEXT    NOT NULL DEFAULT '',
    division_name           TEXT    NOT NULL DEFAULT '',
    n_flow                  INTEGER NOT NULL DEFAULT 0,
    n_flow_outcome_success  INTEGER NOT NULL DEFAULT 0,
    n_flow_outcome_failed   INTEGER NOT NULL DEFAULT 0,
    n_flow_milestone_hit    INTEGER NOT NULL DEFAULT 0,
    containment_rate_pct    REAL    NOT NULL DEFAULT 0,
    failure_rate_pct        REAL    NOT NULL DEFAULT 0,
    imported_utc            TEXT    NOT NULL DEFAULT ''
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_flow_milestone_distribution (
    row_id           TEXT    PRIMARY KEY,
    case_id          TEXT    NOT NULL REFERENCES cases(case_id),
    flow_id          TEXT    NOT NULL DEFAULT '',
    flow_name        TEXT    NOT NULL DEFAULT '',
    milestone_id     TEXT    NOT NULL DEFAULT '',
    milestone_name   TEXT    NOT NULL DEFAULT '',
    n_hit            INTEGER NOT NULL DEFAULT 0,
    pct_of_entries   REAL    NOT NULL DEFAULT 0,
    imported_utc     TEXT    NOT NULL DEFAULT ''
)
'@ | Out-Null

    # v8 indexes
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_flow_perf_case       ON report_flow_perf(case_id)'                       | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_flow_perf_flow       ON report_flow_perf(flow_id)'                       | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_flow_perf_contain    ON report_flow_perf(containment_rate_pct)'          | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_flow_milestone_case  ON report_flow_milestone_distribution(case_id)'     | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_flow_milestone_flow  ON report_flow_milestone_distribution(flow_id)'     | Out-Null

    # Schema v9 — Wrapup Code Distribution report tables (Session 18)
    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_wrapup_distribution (
    row_id                  TEXT    PRIMARY KEY,
    case_id                 TEXT    NOT NULL REFERENCES cases(case_id),
    queue_id                TEXT    NOT NULL DEFAULT '',
    queue_name              TEXT    NOT NULL DEFAULT '',
    wrapup_code_id          TEXT    NOT NULL DEFAULT '',
    wrapup_code_name        TEXT    NOT NULL DEFAULT '',
    n_connected             INTEGER NOT NULL DEFAULT 0,
    pct_of_queue_total      REAL    NOT NULL DEFAULT 0,
    pct_of_org_total        REAL    NOT NULL DEFAULT 0,
    imported_utc            TEXT    NOT NULL DEFAULT ''
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS report_wrapup_by_hour (
    row_id                  TEXT    PRIMARY KEY,
    case_id                 TEXT    NOT NULL REFERENCES cases(case_id),
    hour_of_day             INTEGER NOT NULL DEFAULT 0,
    wrapup_code_id          TEXT    NOT NULL DEFAULT '',
    wrapup_code_name        TEXT    NOT NULL DEFAULT '',
    n_connected             INTEGER NOT NULL DEFAULT 0,
    imported_utc            TEXT    NOT NULL DEFAULT ''
)
'@ | Out-Null

    # v9 indexes
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_wrapup_dist_case     ON report_wrapup_distribution(case_id)'       | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_wrapup_dist_code     ON report_wrapup_distribution(wrapup_code_id)'| Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_wrapup_dist_queue    ON report_wrapup_distribution(queue_id)'      | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_wrapup_dist_nconn    ON report_wrapup_distribution(n_connected)'   | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_wrapup_hour_case     ON report_wrapup_by_hour(case_id)'             | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_wrapup_hour_code     ON report_wrapup_by_hour(wrapup_code_id)'      | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_wrapup_hour_h        ON report_wrapup_by_hour(hour_of_day)'         | Out-Null

    # Schema v10 — investigation workbench foundation
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "raw_json TEXT"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "payload_hash TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "primary_queue TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "final_queue TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "queue_count INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "agent_count INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "transfer_count INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "blind_transfer_count INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "consult_transfer_count INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "hold_count INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "hold_duration_sec INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "mos_min REAL"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "mos_max REAL"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "mos_avg REAL"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "wrapup_code TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "wrapup_name TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "flow_id TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "flow_name TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "external_contact_present INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "customer_disconnect INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "agent_disconnect INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "acd_disconnect INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "contains_callback INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "contains_voicemail INTEGER NOT NULL DEFAULT 0"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "conversation_signature TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "anomaly_flags TEXT NOT NULL DEFAULT ''"
    _AddColumnIfMissing -Conn $Conn -Table 'conversations' -ColDef "risk_score INTEGER NOT NULL DEFAULT 0"

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS conversation_versions (
    version_id      TEXT PRIMARY KEY,
    case_id         TEXT NOT NULL REFERENCES cases(case_id),
    conversation_id TEXT NOT NULL DEFAULT '',
    import_id       TEXT NOT NULL REFERENCES imports(import_id),
    run_id          TEXT NOT NULL REFERENCES core_runs(run_id),
    source_file     TEXT NOT NULL DEFAULT '',
    source_offset   INTEGER NOT NULL DEFAULT 0,
    imported_utc    TEXT NOT NULL,
    payload_hash    TEXT NOT NULL DEFAULT '',
    raw_json        TEXT
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS conversation_agents (
    case_id         TEXT NOT NULL REFERENCES cases(case_id),
    conversation_id TEXT NOT NULL DEFAULT '',
    import_id       TEXT NOT NULL REFERENCES imports(import_id),
    run_id          TEXT NOT NULL REFERENCES core_runs(run_id),
    user_id         TEXT NOT NULL DEFAULT '',
    user_name       TEXT NOT NULL DEFAULT '',
    purpose         TEXT NOT NULL DEFAULT '',
    imported_utc    TEXT NOT NULL,
    PRIMARY KEY(case_id, conversation_id, user_id, purpose)
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS conversation_queues (
    case_id         TEXT NOT NULL REFERENCES cases(case_id),
    conversation_id TEXT NOT NULL DEFAULT '',
    import_id       TEXT NOT NULL REFERENCES imports(import_id),
    run_id          TEXT NOT NULL REFERENCES core_runs(run_id),
    queue_id        TEXT NOT NULL DEFAULT '',
    queue_name      TEXT NOT NULL DEFAULT '',
    purpose         TEXT NOT NULL DEFAULT '',
    imported_utc    TEXT NOT NULL,
    PRIMARY KEY(case_id, conversation_id, queue_id, queue_name, purpose)
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS conversation_divisions (
    case_id         TEXT NOT NULL REFERENCES cases(case_id),
    conversation_id TEXT NOT NULL DEFAULT '',
    import_id       TEXT NOT NULL REFERENCES imports(import_id),
    run_id          TEXT NOT NULL REFERENCES core_runs(run_id),
    division_id     TEXT NOT NULL DEFAULT '',
    source          TEXT NOT NULL DEFAULT '',
    imported_utc    TEXT NOT NULL,
    PRIMARY KEY(case_id, conversation_id, division_id, source)
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS conversation_flows (
    case_id         TEXT NOT NULL REFERENCES cases(case_id),
    conversation_id TEXT NOT NULL DEFAULT '',
    import_id       TEXT NOT NULL REFERENCES imports(import_id),
    run_id          TEXT NOT NULL REFERENCES core_runs(run_id),
    flow_id         TEXT NOT NULL DEFAULT '',
    flow_name       TEXT NOT NULL DEFAULT '',
    imported_utc    TEXT NOT NULL,
    PRIMARY KEY(case_id, conversation_id, flow_id, flow_name)
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql @'
CREATE TABLE IF NOT EXISTS conversation_wrapups (
    case_id         TEXT NOT NULL REFERENCES cases(case_id),
    conversation_id TEXT NOT NULL DEFAULT '',
    import_id       TEXT NOT NULL REFERENCES imports(import_id),
    run_id          TEXT NOT NULL REFERENCES core_runs(run_id),
    wrapup_code     TEXT NOT NULL DEFAULT '',
    wrapup_name     TEXT NOT NULL DEFAULT '',
    imported_utc    TEXT NOT NULL,
    PRIMARY KEY(case_id, conversation_id, wrapup_code, wrapup_name)
)
'@ | Out-Null

    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_payload_hash ON conversations(payload_hash)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_primary_queue ON conversations(primary_queue)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_final_queue ON conversations(final_queue)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_transfer_count ON conversations(transfer_count)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_hold_duration ON conversations(hold_duration_sec)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_risk_score ON conversations(risk_score)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_signature ON conversations(conversation_signature)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_versions_case_conv ON conversation_versions(case_id, conversation_id)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_versions_import ON conversation_versions(import_id)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_agents_case_user ON conversation_agents(case_id, user_id)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_queues_case_queue ON conversation_queues(case_id, queue_name)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_divs_case_div ON conversation_divisions(case_id, division_id)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_flows_case_flow ON conversation_flows(case_id, flow_id)' | Out-Null
    _NonQuery -Conn $Conn -Sql 'CREATE INDEX IF NOT EXISTS idx_conv_wrapups_case_code ON conversation_wrapups(case_id, wrapup_code)' | Out-Null

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

    # First-run fast path: seed from the shipped pre-built DB if the target is
    # missing. _ApplySchema still runs below (idempotent) so any migrations
    # beyond the seed's schema version are applied to the copied file.
    if (-not [System.IO.File]::Exists($DatabasePath) -and $AppDir) {
        $seed = [System.IO.Path]::Combine($AppDir, 'lib', 'cases.seed.sqlite')
        if ([System.IO.File]::Exists($seed)) {
            [System.IO.File]::Copy($seed, $DatabasePath, $false)
        }
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

function New-DefaultCaseIfEmpty {
    <#
    .SYNOPSIS
        Creates a default "Research" case when the store contains no cases yet.
        Lets engineers run conversation-detail jobs and accumulate results
        without first ceremony (open Case Manager → New Case → pick name).

        Returns the new case_id on creation, or $null if cases already exist
        or the store is not initialized.
    #>
    param(
        [string]$Name        = 'Research',
        [string]$Description = 'Default case. Conversation-detail runs accumulate here unless you create and activate another case.'
    )
    if (-not $script:DbInitialized) { return $null }

    $conn = _Open
    try {
        $count = [int](_Scalar -Conn $conn -Sql 'SELECT COUNT(*) FROM cases')
    } finally {
        $conn.Close(); $conn.Dispose()
    }
    if ($count -gt 0) { return $null }

    return (New-Case -Name $Name -Description $Description)
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
            foreach ($tbl in @('conversation_agents','conversation_queues','conversation_divisions','conversation_flows','conversation_wrapups','conversation_versions')) {
                _NonQuery -Conn $conn -Sql "DELETE FROM $tbl WHERE case_id = @id" -P @{ '@id' = $CaseId } | Out-Null
            }
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
            foreach ($tbl in @('conversation_agents','conversation_queues','conversation_divisions','conversation_flows','conversation_wrapups','conversation_versions')) {
                _NonQuery -Conn $conn -Sql "DELETE FROM $tbl WHERE case_id = @cid" -P @{ '@cid' = $CaseId } | Out-Null
            }
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

            foreach ($tbl in @('conversation_agents','conversation_queues','conversation_divisions','conversation_flows','conversation_wrapups')) {
                _NonQuery -Conn $conn `
                    -Sql "DELETE FROM $tbl WHERE case_id = @cid AND run_id = @rid" `
                    -P @{ '@cid' = $CaseId; '@rid' = $runId } | Out-Null
            }

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
        [object]$FilterState = $null,
        [string]$Direction      = '',
        [string]$MediaType      = '',
        [string]$Queue          = '',
        [string]$ConversationId = '',
        [string]$SearchText     = '',
        [string]$DisconnectType = '',
        [string]$AgentName      = '',
        [string]$Ani            = '',
        [string]$DivisionId     = '',
        [string]$StartDateTime  = '',
        [string]$EndDateTime    = '',
        [hashtable]$ColumnFilters = @{}
    )
    _RequireDb
    $filter = _GetConversationWhereClause `
        -CaseId $CaseId -FilterState $FilterState -Direction $Direction -MediaType $MediaType `
        -Queue $Queue -ConversationId $ConversationId -SearchText $SearchText `
        -DisconnectType $DisconnectType -AgentName $AgentName -Ani $Ani -DivisionId $DivisionId `
        -StartDateTime $StartDateTime -EndDateTime $EndDateTime -ColumnFilters $ColumnFilters

    $conn = _Open
    try {
        return [int](_Scalar -Conn $conn -Sql "SELECT COUNT(*) FROM conversations WHERE $($filter.Where)" -P $filter.Parameters)
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
        [object]$FilterState = $null,
        [string]$Direction      = '',
        [string]$MediaType      = '',
        [string]$Queue          = '',
        [string]$ConversationId = '',
        [string]$SearchText     = '',
        [string]$DisconnectType = '',
        [string]$AgentName      = '',
        [string]$Ani            = '',
        [string]$DivisionId     = '',
        [string]$StartDateTime  = '',
        [string]$EndDateTime    = '',
        [string]$SortBy         = 'conversation_start',
        [string]$SortDir        = 'DESC',
        [hashtable]$ColumnFilters = @{}
    )
    _RequireDb

    $normalized = _NormalizeFilterState -FilterState $FilterState -SortBy $SortBy -SortDirection $SortDir
    $filter = _GetConversationWhereClause `
        -CaseId $CaseId -FilterState $FilterState -Direction $Direction -MediaType $MediaType `
        -Queue $Queue -ConversationId $ConversationId -SearchText $SearchText `
        -DisconnectType $DisconnectType -AgentName $AgentName -Ani $Ani -DivisionId $DivisionId `
        -StartDateTime $StartDateTime -EndDateTime $EndDateTime -ColumnFilters $ColumnFilters
    $orderBy = _GetConversationSortClause -SortBy $(if ($SortBy) { $SortBy } else { $normalized.SortBy }) -SortDirection $(if ($SortDir) { $SortDir } else { $normalized.SortDirection })

    $p = $filter.Parameters
    $p['@limit']  = $PageSize
    $p['@offset'] = ($PageNumber - 1) * $PageSize

    $sql  = "SELECT * FROM conversations WHERE $($filter.Where) ORDER BY $orderBy LIMIT @limit OFFSET @offset"
    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Get-ConversationPopulationRows {
    <#
    .SYNOPSIS
        Returns the full filtered SQL-backed population for reports/exports.
        This intentionally ignores UI page number so report totals are page-independent.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [object]$FilterState = $null,
        [int]$Limit = 0
    )
    _RequireDb
    $f = _NormalizeFilterState -FilterState $FilterState
    $filter = _GetConversationWhereClause -CaseId $CaseId -FilterState $f
    $orderBy = _GetConversationSortClause -SortBy $f.SortBy -SortDirection $f.SortDirection
    $sql = "SELECT * FROM conversations WHERE $($filter.Where) ORDER BY $orderBy"
    $p = $filter.Parameters
    if ($Limit -gt 0) {
        $sql += ' LIMIT @limit'
        $p['@limit'] = $Limit
    }
    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Get-ConversationPopulationSummary {
    <#
    .SYNOPSIS
        Returns aggregate summary metrics for the full filtered population.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [object]$FilterState = $null
    )
    _RequireDb
    $filter = _GetConversationWhereClause -CaseId $CaseId -FilterState $FilterState
    $conn = _Open
    try {
        $row = _Query -Conn $conn -Sql @"
SELECT
    COUNT(*) AS total_conversations,
    COALESCE(SUM(duration_sec), 0) AS total_duration_sec,
    COALESCE(AVG(duration_sec), 0) AS avg_duration_sec,
    COALESCE(SUM(transfer_count), 0) AS total_transfers,
    COALESCE(AVG(transfer_count), 0) AS avg_transfers,
    COALESCE(SUM(hold_count), 0) AS total_holds,
    COALESCE(SUM(hold_duration_sec), 0) AS total_hold_duration_sec,
    COALESCE(AVG(hold_duration_sec), 0) AS avg_hold_duration_sec,
    MIN(mos_min) AS mos_min,
    MAX(mos_max) AS mos_max,
    AVG(mos_avg) AS mos_avg,
    COALESCE(AVG(risk_score), 0) AS avg_risk_score,
    COALESCE(MAX(risk_score), 0) AS max_risk_score,
    COALESCE(SUM(customer_disconnect), 0) AS customer_disconnects,
    COALESCE(SUM(agent_disconnect), 0) AS agent_disconnects,
    COALESCE(SUM(acd_disconnect), 0) AS acd_disconnects,
    MIN(conversation_start) AS first_conversation_start,
    MAX(conversation_start) AS last_conversation_start
FROM conversations
WHERE $($filter.Where)
"@ -P $filter.Parameters
    } finally { $conn.Close(); $conn.Dispose() }
    if ($row.Count -eq 0) { return $null }
    $summary = [pscustomobject]$row[0]
    $summary | Add-Member -NotePropertyName 'filter_state' -NotePropertyValue $filter.FilterState -Force
    return $summary
}

function Get-ConversationFacetCounts {
    <#
    .SYNOPSIS
        Returns common facet counts for the full filtered population.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [object]$FilterState = $null,
        [int]$Top = 20
    )
    _RequireDb
    if ($Top -lt 1) { $Top = 20 }
    $filter = _GetConversationWhereClause -CaseId $CaseId -FilterState $FilterState
    $conn = _Open
    try {
        $facets = [ordered]@{}
        foreach ($facet in @(
            @{ Name = 'direction'; Column = 'direction' },
            @{ Name = 'media_type'; Column = 'media_type' },
            @{ Name = 'queue'; Column = 'queue_name' },
            @{ Name = 'disconnect_type'; Column = 'disconnect_type' },
            @{ Name = 'wrapup_code'; Column = 'wrapup_code' },
            @{ Name = 'primary_queue'; Column = 'primary_queue' },
            @{ Name = 'final_queue'; Column = 'final_queue' },
            @{ Name = 'conversation_signature'; Column = 'conversation_signature' }
        )) {
            $sql = "SELECT $($facet.Column) AS value, COUNT(*) AS count FROM conversations WHERE $($filter.Where) AND $($facet.Column) <> '' GROUP BY $($facet.Column) ORDER BY count DESC, value ASC LIMIT @top"
            $p = @{}
            foreach ($kv in $filter.Parameters.GetEnumerator()) { $p[$kv.Key] = $kv.Value }
            $p['@top'] = $Top
            $facets[$facet.Name] = @(_Query -Conn $conn -Sql $sql -P $p | ForEach-Object { [pscustomobject]$_ })
        }
    } finally { $conn.Close(); $conn.Dispose() }
    return [pscustomobject]$facets
}

function Get-RepresentativeConversations {
    <#
    .SYNOPSIS
        Returns representative/high-signal examples from the filtered population.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [object]$FilterState = $null,
        [int]$Top = 10
    )
    _RequireDb
    if ($Top -lt 1) { $Top = 10 }
    $filter = _GetConversationWhereClause -CaseId $CaseId -FilterState $FilterState
    $p = $filter.Parameters
    $p['@top'] = $Top
    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql @"
SELECT *,
       (risk_score + (transfer_count * 5) + CASE WHEN hold_duration_sec > 300 THEN 10 ELSE 0 END) AS representative_score
FROM conversations
WHERE $($filter.Where)
ORDER BY representative_score DESC, duration_sec DESC, conversation_start DESC
LIMIT @top
"@ -P $p
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
}

function Get-AnomalyRiskCohorts {
    <#
    .SYNOPSIS
        Returns cohort counts for common risk/anomaly conditions.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [object]$FilterState = $null
    )
    _RequireDb
    $filter = _GetConversationWhereClause -CaseId $CaseId -FilterState $FilterState
    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql @"
SELECT 'high_risk' AS cohort, COUNT(*) AS count FROM conversations WHERE $($filter.Where) AND risk_score >= 60
UNION ALL SELECT 'multi_transfer', COUNT(*) FROM conversations WHERE $($filter.Where) AND transfer_count >= 2
UNION ALL SELECT 'long_hold', COUNT(*) FROM conversations WHERE $($filter.Where) AND hold_duration_sec >= 300
UNION ALL SELECT 'low_mos', COUNT(*) FROM conversations WHERE $($filter.Where) AND mos_min IS NOT NULL AND mos_min < 3.5
UNION ALL SELECT 'customer_disconnect', COUNT(*) FROM conversations WHERE $($filter.Where) AND customer_disconnect = 1
UNION ALL SELECT 'acd_disconnect', COUNT(*) FROM conversations WHERE $($filter.Where) AND acd_disconnect = 1
"@ -P $filter.Parameters
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

function Get-ConversationVersions {
    <#
    .SYNOPSIS
        Returns preserved historical versions for a conversation.
    #>
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$ConversationId
    )
    _RequireDb
    $conn = _Open
    try {
        $rows = _Query -Conn $conn `
            -Sql 'SELECT * FROM conversation_versions WHERE case_id = @cid AND conversation_id = @cvid ORDER BY imported_utc DESC' `
            -P @{ '@cid' = $CaseId; '@cvid' = $ConversationId }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows | ForEach-Object { [pscustomobject]$_ })
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

    if ($null -ne $val -and $val -ne [System.DBNull]::Value) {
        return [string]$val
    }
    return $null
}

# ── Public: Queue Performance Report (Session 14) ─────────────────────────────

function Import-QueuePerformanceReport {
    <#
    .SYNOPSIS
        Imports queue performance aggregate data from three Core run folders into
        the report_queue_perf table for the active case.
    .DESCRIPTION
        Reads JSONL outputs from:
          - analytics.query.conversation.aggregates.queue.performance (nConnected, tHandle, tTalk, tAcw, nOffered)
          - analytics.query.conversation.aggregates.abandon.metrics    (nAbandoned, nOffered)
          - analytics.query.queue.aggregates.service.level             (nAnsweredIn20/30/60, nOffered)

        Each JSONL record has the shape:
            { "group": { "queueId": "...", ... }, "data": [ { "interval": "start/end", "metrics": [...] } ] }

        Rows are upserted by (case_id, queue_id, interval_start).  Queue names and
        division names are resolved from ref_queues / ref_divisions.

        Returns a hashtable with RecordCount and SkippedCount.
    .PARAMETER CaseId
        Target case identifier.
    .PARAMETER FolderMap
        Hashtable returned by Get-QueuePerformanceReport (App.CoreAdapter.psm1).
        Keys: 'QueuePerfFolder', 'AbandonFolder', 'ServiceLevelFolder'.
    #>
    param(
        [Parameter(Mandatory)][string]    $CaseId,
        [Parameter(Mandatory)][hashtable] $FolderMap
    )
    _RequireDb

    $now    = [datetime]::UtcNow.ToString('o')
    $stats  = @{ RecordCount = 0; SkippedCount = 0 }

    # ── Helper: read JSONL records from a run folder ──────────────────────────
    function _ReadAggJsonl ([string]$RunFolder) {
        if ([string]::IsNullOrWhiteSpace($RunFolder) -or
            -not [System.IO.Directory]::Exists($RunFolder)) {
            return @()
        }
        $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
        if (-not [System.IO.Directory]::Exists($dataDir)) { return @() }
        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($f in [System.IO.Directory]::GetFiles($dataDir, '*.jsonl')) {
            foreach ($line in [System.IO.File]::ReadAllLines($f)) {
                $t = $line.Trim()
                if ($t) {
                    try { $records.Add(($t | ConvertFrom-Json)) } catch {
                        Write-Warning "Import-QueuePerformanceReport: skipping malformed JSONL line in $f — $($_.Exception.Message)"
                    }
                }
            }
        }
        return $records.ToArray()
    }

    # ── Helper: flatten a single result record into per-interval metric rows ──
    # Returns List<hashtable> with keys: queueId, intervalStart, metrics{}
    function _FlattenAggResult ([object]$Result) {
        $rows = [System.Collections.Generic.List[hashtable]]::new()
        if ($null -eq $Result -or $null -eq $Result.data) { return $rows }
        $queueId = [string]($Result.group.queueId)
        if (-not $queueId) { return $rows }
        foreach ($d in @($Result.data)) {
            $istr = [string]($d.interval)
            # interval is "startISO/endISO" — take the start part
            $intervalStart = if ($istr -match '^([^/]+)/') { $Matches[1] } else { $istr }
            $mHash = @{}
            foreach ($m in @($d.metrics)) {
                $mHash[$m.metric] = $m.stats
            }
            $rows.Add(@{
                QueueId       = $queueId
                IntervalStart = $intervalStart
                Metrics       = $mHash
            })
        }
        return $rows
    }

    # ── Build merged dictionary keyed by "queueId|intervalStart" ─────────────
    $merged = @{}   # key → hashtable with queued up metric values

    function _Ensure ([string]$Key, [string]$Qid, [string]$Istart) {
        if (-not $merged.ContainsKey($Key)) {
            $merged[$Key] = @{
                QueueId         = $Qid
                IntervalStart   = $Istart
                nConnected      = 0
                tHandleSum      = 0.0
                tTalkSum        = 0.0
                tAcwSum         = 0.0
                nOfferedPerf    = 0
                nAbandoned      = 0
                nOfferedAbandon = 0
                nAnsweredIn20   = 0
                nAnsweredIn30   = 0
                nAnsweredIn60   = 0
                nOfferedSL      = 0
            }
        }
    }

    # Queue performance dataset
    $qpFolder = if ($FolderMap.ContainsKey('QueuePerfFolder'))   { $FolderMap['QueuePerfFolder']   } else { $null }
    foreach ($r in (_ReadAggJsonl $qpFolder)) {
        foreach ($row in (_FlattenAggResult $r)) {
            $key = "$($row.QueueId)|$($row.IntervalStart)"
            _Ensure $key $row.QueueId $row.IntervalStart
            $mx = $row.Metrics
            if ($mx.ContainsKey('nConnected'))  { $merged[$key].nConnected    += [int]  ($mx['nConnected'].count) }
            if ($mx.ContainsKey('tHandle'))     { $merged[$key].tHandleSum    += [double]($mx['tHandle'].sum)    }
            if ($mx.ContainsKey('tTalk'))       { $merged[$key].tTalkSum      += [double]($mx['tTalk'].sum)      }
            if ($mx.ContainsKey('tAcw'))        { $merged[$key].tAcwSum       += [double]($mx['tAcw'].sum)       }
            if ($mx.ContainsKey('nOffered'))    { $merged[$key].nOfferedPerf  += [int]  ($mx['nOffered'].count)  }
        }
    }

    # Abandon metrics dataset
    $abFolder = if ($FolderMap.ContainsKey('AbandonFolder'))    { $FolderMap['AbandonFolder']    } else { $null }
    foreach ($r in (_ReadAggJsonl $abFolder)) {
        foreach ($row in (_FlattenAggResult $r)) {
            $key = "$($row.QueueId)|$($row.IntervalStart)"
            _Ensure $key $row.QueueId $row.IntervalStart
            $mx = $row.Metrics
            if ($mx.ContainsKey('nAbandoned'))  { $merged[$key].nAbandoned      += [int]($mx['nAbandoned'].count) }
            if ($mx.ContainsKey('nOffered'))    { $merged[$key].nOfferedAbandon += [int]($mx['nOffered'].count)   }
        }
    }

    # Service level dataset
    $slFolder = if ($FolderMap.ContainsKey('ServiceLevelFolder')) { $FolderMap['ServiceLevelFolder'] } else { $null }
    foreach ($r in (_ReadAggJsonl $slFolder)) {
        foreach ($row in (_FlattenAggResult $r)) {
            $key = "$($row.QueueId)|$($row.IntervalStart)"
            _Ensure $key $row.QueueId $row.IntervalStart
            $mx = $row.Metrics
            if ($mx.ContainsKey('nAnsweredIn20')) { $merged[$key].nAnsweredIn20 += [int]($mx['nAnsweredIn20'].count) }
            if ($mx.ContainsKey('nAnsweredIn30')) { $merged[$key].nAnsweredIn30 += [int]($mx['nAnsweredIn30'].count) }
            if ($mx.ContainsKey('nAnsweredIn60')) { $merged[$key].nAnsweredIn60 += [int]($mx['nAnsweredIn60'].count) }
            if ($mx.ContainsKey('nOffered'))      { $merged[$key].nOfferedSL   += [int]($mx['nOffered'].count)      }
        }
    }

    if ($merged.Count -eq 0) {
        return $stats
    }

    # ── Resolve queue names and division names ────────────────────────────────
    $conn = _Open
    try {
        foreach ($entry in $merged.Values) {
            $qid    = $entry.QueueId
            $rowKey = "$CaseId|qperf|$qid|$($entry.IntervalStart)"

            # Resolve queue name and division id from ref_queues
            $qname  = ''
            $divId  = ''
            $qRow   = _Query -Conn $conn -Sql @'
SELECT name, division_id FROM ref_queues
WHERE case_id = @cid AND queue_id = @qid
LIMIT 1
'@ -P @{ '@cid' = $CaseId; '@qid' = $qid }
            if ($qRow.Count -gt 0) {
                $qname = [string]($qRow[0].name)
                $divId = [string]($qRow[0].division_id)
            }
            if (-not $qname) { $qname = "$qid (unresolved)" }

            # Resolve division name from ref_divisions
            $divName = ''
            if ($divId) {
                $dRow = _Query -Conn $conn -Sql @'
SELECT name FROM ref_divisions
WHERE case_id = @cid AND division_id = @did
LIMIT 1
'@ -P @{ '@cid' = $CaseId; '@did' = $divId }
                if ($dRow.Count -gt 0) { $divName = [string]($dRow[0].name) }
            }

            # Derive computed metrics
            $nConn      = $entry.nConnected
            $tHandleSec = if ($nConn -gt 0) { [Math]::Round($entry.tHandleSum / $nConn / 1000.0, 1) } else { 0.0 }
            $tTalkSec   = if ($nConn -gt 0) { [Math]::Round($entry.tTalkSum   / $nConn / 1000.0, 1) } else { 0.0 }
            $tAcwSec    = if ($nConn -gt 0) { [Math]::Round($entry.tAcwSum    / $nConn / 1000.0, 1) } else { 0.0 }

            # nOffered: prefer abandon dataset's offered (more complete), fall back to perf
            $nOffered    = if ($entry.nOfferedAbandon -gt 0) { $entry.nOfferedAbandon } else { $entry.nOfferedPerf }
            $nAbandoned  = $entry.nAbandoned
            $abanRate    = if ($nOffered -gt 0) { [Math]::Round(($nAbandoned / $nOffered) * 100.0, 1) } else { 0.0 }

            $nOfferedSL  = if ($entry.nOfferedSL -gt 0) { $entry.nOfferedSL } else { $nOffered }
            $slPct       = if ($nOfferedSL -gt 0) { [Math]::Round(($entry.nAnsweredIn30 / $nOfferedSL) * 100.0, 1) } else { 0.0 }

            try {
                _NonQuery -Conn $conn -Sql @'
INSERT INTO report_queue_perf(
    row_id, case_id, queue_id, queue_name, division_id, division_name, interval_start,
    n_offered, n_connected, n_abandoned, abandon_rate_pct,
    t_handle_avg_sec, t_talk_avg_sec, t_acw_avg_sec,
    n_answered_in_20, n_answered_in_30, n_answered_in_60, service_level_pct,
    imported_utc)
VALUES(
    @rid, @cid, @qid, @qname, @divid, @divname, @istart,
    @noff, @nconn, @naban, @abanrate,
    @thandle, @ttalk, @tacw,
    @n20, @n30, @n60, @slpct,
    @ts)
ON CONFLICT(row_id) DO UPDATE SET
    queue_name=excluded.queue_name, division_id=excluded.division_id,
    division_name=excluded.division_name,
    n_offered=excluded.n_offered, n_connected=excluded.n_connected,
    n_abandoned=excluded.n_abandoned, abandon_rate_pct=excluded.abandon_rate_pct,
    t_handle_avg_sec=excluded.t_handle_avg_sec, t_talk_avg_sec=excluded.t_talk_avg_sec,
    t_acw_avg_sec=excluded.t_acw_avg_sec,
    n_answered_in_20=excluded.n_answered_in_20, n_answered_in_30=excluded.n_answered_in_30,
    n_answered_in_60=excluded.n_answered_in_60, service_level_pct=excluded.service_level_pct,
    imported_utc=excluded.imported_utc
'@ -P @{
                    '@rid'     = $rowKey
                    '@cid'     = $CaseId
                    '@qid'     = $qid
                    '@qname'   = $qname
                    '@divid'   = $divId
                    '@divname' = $divName
                    '@istart'  = $entry.IntervalStart
                    '@noff'    = $nOffered
                    '@nconn'   = $nConn
                    '@naban'   = $nAbandoned
                    '@abanrate'= $abanRate
                    '@thandle' = $tHandleSec
                    '@ttalk'   = $tTalkSec
                    '@tacw'    = $tAcwSec
                    '@n20'     = $entry.nAnsweredIn20
                    '@n30'     = $entry.nAnsweredIn30
                    '@n60'     = $entry.nAnsweredIn60
                    '@slpct'   = $slPct
                    '@ts'      = $now
                } | Out-Null
                $stats.RecordCount++
            } catch {
                Write-Warning "Import-QueuePerformanceReport: failed to upsert row for queue '$qid' interval '$($entry.IntervalStart)' — $($_.Exception.Message)"
                $stats.SkippedCount++
            }
        }
    } finally { $conn.Close(); $conn.Dispose() }

    return $stats
}

function Get-QueuePerfRows {
    <#
    .SYNOPSIS
        Returns queue performance rows for a case, optionally filtered by division.
    .DESCRIPTION
        Returns all rows from report_queue_perf for the given case, sorted by
        interval_start ascending then queue_name ascending.  When DivisionId is
        provided, only rows for that division are returned.
    .PARAMETER CaseId
        The case to query.
    .PARAMETER DivisionId
        Optional division GUID to filter by.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [string] $DivisionId = ''
    )
    _RequireDb

    if ($DivisionId) {
        $sql = @'
SELECT queue_id, queue_name, division_id, division_name, interval_start,
       n_offered, n_connected, n_abandoned, abandon_rate_pct,
       t_handle_avg_sec, t_talk_avg_sec, t_acw_avg_sec,
       n_answered_in_20, n_answered_in_30, n_answered_in_60, service_level_pct
FROM   report_queue_perf
WHERE  case_id = @cid AND division_id = @did
ORDER  BY interval_start ASC, queue_name ASC
'@
        $p = @{ '@cid' = $CaseId; '@did' = $DivisionId }
    } else {
        $sql = @'
SELECT queue_id, queue_name, division_id, division_name, interval_start,
       n_offered, n_connected, n_abandoned, abandon_rate_pct,
       t_handle_avg_sec, t_talk_avg_sec, t_acw_avg_sec,
       n_answered_in_20, n_answered_in_30, n_answered_in_60, service_level_pct
FROM   report_queue_perf
WHERE  case_id = @cid
ORDER  BY interval_start ASC, queue_name ASC
'@
        $p = @{ '@cid' = $CaseId }
    }

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }

    return @($rows)
}

function Get-QueuePerfSummary {
    <#
    .SYNOPSIS
        Returns org-wide aggregate totals across all report_queue_perf rows for a case.
    .DESCRIPTION
        Rolls up all rows (or those matching an optional DivisionId filter) into a
        single summary object used to populate the summary bar above the DataGrid.
    .PARAMETER CaseId
        The case to query.
    .PARAMETER DivisionId
        Optional division GUID to filter by.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [string] $DivisionId = ''
    )
    _RequireDb

    if ($DivisionId) {
        $sql = @'
SELECT
    COUNT(DISTINCT queue_id)    AS total_queues,
    SUM(n_offered)              AS total_offered,
    SUM(n_abandoned)            AS total_abandoned,
    AVG(abandon_rate_pct)       AS avg_abandon_pct,
    AVG(service_level_pct)      AS avg_sl_30s_pct,
    AVG(t_handle_avg_sec)       AS avg_handle_sec
FROM report_queue_perf
WHERE case_id = @cid AND division_id = @did
'@
        $p = @{ '@cid' = $CaseId; '@did' = $DivisionId }
    } else {
        $sql = @'
SELECT
    COUNT(DISTINCT queue_id)    AS total_queues,
    SUM(n_offered)              AS total_offered,
    SUM(n_abandoned)            AS total_abandoned,
    AVG(abandon_rate_pct)       AS avg_abandon_pct,
    AVG(service_level_pct)      AS avg_sl_30s_pct,
    AVG(t_handle_avg_sec)       AS avg_handle_sec
FROM report_queue_perf
WHERE case_id = @cid
'@
        $p = @{ '@cid' = $CaseId }
    }

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }

    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            TotalQueues   = 0
            TotalOffered  = 0
            TotalAbandoned= 0
            AvgAbandonPct = 0.0
            AvgSL30sPct   = 0.0
            AvgHandleSec  = 0.0
        }
    }
    $r = $rows[0]
    return [pscustomobject]@{
        TotalQueues    = [int]   (_RowVal $r 'total_queues'   0)
        TotalOffered   = [int]   (_RowVal $r 'total_offered'  0)
        TotalAbandoned = [int]   (_RowVal $r 'total_abandoned' 0)
        AvgAbandonPct  = [double](_RowVal $r 'avg_abandon_pct' 0.0)
        AvgSL30sPct    = [double](_RowVal $r 'avg_sl_30s_pct'  0.0)
        AvgHandleSec   = [double](_RowVal $r 'avg_handle_sec'  0.0)
    }
}

function Import-AgentPerformanceReport {
    <#
    .SYNOPSIS
        Imports agent performance aggregate data from three Core run folders into
        the report_agent_perf table for the active case.
    .DESCRIPTION
        Reads JSONL outputs from:
          - analytics.query.conversation.aggregates.agent.performance (nConnected, tHandle, tTalk, tAcw)
          - analytics.query.user.aggregates.performance.metrics        (nConnected, nOffered, tHandle, tTalk, tAcw)
          - analytics.query.user.aggregates.login.activity             (tOnQueueTime, tOffQueueTime, tIdleTime)

        Each JSONL record has the shape:
            { "group": { "userId": "...", ... }, "data": [ { "interval": "start/end", "metrics": [...] } ] }

        Rows are upserted by (case_id, user_id).  User names are resolved from
        ref_users; division names from ref_divisions.

        talk_ratio_pct  = tTalk / tHandle * 100  (0 if tHandle == 0)
        acw_ratio_pct   = tAcw  / tHandle * 100  (0 if tHandle == 0)
        idle_ratio_pct  = tIdleTime / (tOnQueueTime + tOffQueueTime + tIdleTime) * 100 (0 if total == 0)

        Returns a hashtable with RecordCount and SkippedCount.
    .PARAMETER CaseId
        Target case identifier.
    .PARAMETER FolderMap
        Hashtable returned by Get-AgentPerformanceReport (App.CoreAdapter.psm1).
        Keys: 'AgentPerfFolder', 'UserPerfFolder', 'LoginActivityFolder'.
    #>
    param(
        [Parameter(Mandatory)][string]    $CaseId,
        [Parameter(Mandatory)][hashtable] $FolderMap
    )
    _RequireDb

    $now   = [datetime]::UtcNow.ToString('o')
    $stats = @{ RecordCount = 0; SkippedCount = 0 }

    # ── Helper: read JSONL records from a run folder ──────────────────────────
    function _ReadAgentJsonl ([string]$RunFolder) {
        if ([string]::IsNullOrWhiteSpace($RunFolder) -or
            -not [System.IO.Directory]::Exists($RunFolder)) {
            return @()
        }
        $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
        if (-not [System.IO.Directory]::Exists($dataDir)) { return @() }
        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($f in [System.IO.Directory]::GetFiles($dataDir, '*.jsonl')) {
            foreach ($line in [System.IO.File]::ReadAllLines($f)) {
                $t = $line.Trim()
                if ($t) {
                    try { $records.Add(($t | ConvertFrom-Json)) } catch {
                        Write-Warning "Import-AgentPerformanceReport: skipping malformed JSONL line in $f — $($_.Exception.Message)"
                    }
                }
            }
        }
        return $records.ToArray()
    }

    # ── Helper: flatten a single result record, accumulating per-userId metrics ─
    # Returns List<hashtable> with keys: UserId, metrics{}
    function _FlattenUserResult ([object]$Result) {
        $rows = [System.Collections.Generic.List[hashtable]]::new()
        if ($null -eq $Result -or $null -eq $Result.data) { return $rows }
        $userId = [string]($Result.group.userId)
        if (-not $userId) { return $rows }
        $mHash = @{}
        foreach ($d in @($Result.data)) {
            foreach ($m in @($d.metrics)) {
                $mn = $m.metric
                if (-not $mHash.ContainsKey($mn)) { $mHash[$mn] = @{ sum = 0.0; count = 0 } }
                if ($m.stats.sum)   { $mHash[$mn].sum   += [double]($m.stats.sum)   }
                if ($m.stats.count) { $mHash[$mn].count += [int]   ($m.stats.count) }
            }
        }
        $rows.Add(@{ UserId = $userId; Metrics = $mHash })
        return $rows
    }

    # ── Build merged dictionary keyed by userId ───────────────────────────────
    $merged = @{}   # userId → hashtable of accumulated metric values

    function _EnsureAgent ([string]$Uid) {
        if (-not $merged.ContainsKey($Uid)) {
            $merged[$Uid] = @{
                UserId             = $Uid
                # conversation-aggregate agent performance
                nConnectedConv     = 0
                tHandleSumConv     = 0.0
                tTalkSumConv       = 0.0
                tAcwSumConv        = 0.0
                # user-aggregate performance metrics
                nConnectedUser     = 0
                nOfferedUser       = 0
                tHandleSumUser     = 0.0
                tTalkSumUser       = 0.0
                tAcwSumUser        = 0.0
                # login activity
                tOnQueueMs         = 0.0
                tOffQueueMs        = 0.0
                tIdleMs            = 0.0
            }
        }
    }

    # Conversation-aggregate agent performance dataset
    $apFolder = if ($FolderMap.ContainsKey('AgentPerfFolder')) { $FolderMap['AgentPerfFolder'] } else { $null }
    foreach ($r in (_ReadAgentJsonl $apFolder)) {
        foreach ($row in (_FlattenUserResult $r)) {
            _EnsureAgent $row.UserId
            $mx = $row.Metrics
            if ($mx.ContainsKey('nConnected')) { $merged[$row.UserId].nConnectedConv  += $mx['nConnected'].count }
            if ($mx.ContainsKey('tHandle'))    { $merged[$row.UserId].tHandleSumConv  += $mx['tHandle'].sum      }
            if ($mx.ContainsKey('tTalk'))      { $merged[$row.UserId].tTalkSumConv    += $mx['tTalk'].sum        }
            if ($mx.ContainsKey('tAcw'))       { $merged[$row.UserId].tAcwSumConv     += $mx['tAcw'].sum         }
        }
    }

    # User-aggregate performance metrics dataset
    $upFolder = if ($FolderMap.ContainsKey('UserPerfFolder')) { $FolderMap['UserPerfFolder'] } else { $null }
    foreach ($r in (_ReadAgentJsonl $upFolder)) {
        foreach ($row in (_FlattenUserResult $r)) {
            _EnsureAgent $row.UserId
            $mx = $row.Metrics
            if ($mx.ContainsKey('nConnected')) { $merged[$row.UserId].nConnectedUser  += $mx['nConnected'].count }
            if ($mx.ContainsKey('nOffered'))   { $merged[$row.UserId].nOfferedUser    += $mx['nOffered'].count   }
            if ($mx.ContainsKey('tHandle'))    { $merged[$row.UserId].tHandleSumUser  += $mx['tHandle'].sum      }
            if ($mx.ContainsKey('tTalk'))      { $merged[$row.UserId].tTalkSumUser    += $mx['tTalk'].sum        }
            if ($mx.ContainsKey('tAcw'))       { $merged[$row.UserId].tAcwSumUser     += $mx['tAcw'].sum         }
        }
    }

    # Login activity dataset
    $laFolder = if ($FolderMap.ContainsKey('LoginActivityFolder')) { $FolderMap['LoginActivityFolder'] } else { $null }
    foreach ($r in (_ReadAgentJsonl $laFolder)) {
        foreach ($row in (_FlattenUserResult $r)) {
            _EnsureAgent $row.UserId
            $mx = $row.Metrics
            if ($mx.ContainsKey('tOnQueueTime'))  { $merged[$row.UserId].tOnQueueMs  += $mx['tOnQueueTime'].sum  }
            if ($mx.ContainsKey('tOffQueueTime')) { $merged[$row.UserId].tOffQueueMs += $mx['tOffQueueTime'].sum }
            if ($mx.ContainsKey('tIdleTime'))     { $merged[$row.UserId].tIdleMs     += $mx['tIdleTime'].sum     }
        }
    }

    if ($merged.Count -eq 0) {
        return $stats
    }

    # ── Resolve names and upsert ──────────────────────────────────────────────
    $conn = _Open
    try {
        foreach ($entry in $merged.Values) {
            $uid    = $entry.UserId
            $rowKey = "$CaseId|aperf|$uid"

            # Resolve user name, email, department, division_id from ref_users
            $uname   = ''
            $uemail  = ''
            $udept   = ''
            $divId   = ''
            $uRow    = _Query -Conn $conn -Sql @'
SELECT name, email, department, division_id FROM ref_users
WHERE case_id = @cid AND user_id = @uid
LIMIT 1
'@ -P @{ '@cid' = $CaseId; '@uid' = $uid }
            if ($uRow.Count -gt 0) {
                $uname  = [string]($uRow[0].name)
                $uemail = [string]($uRow[0].email)
                $udept  = [string]($uRow[0].department)
                $divId  = [string]($uRow[0].division_id)
            }
            if (-not $uname) { $uname = "$uid (unresolved)" }

            # Resolve division name from ref_divisions
            $divName = ''
            if ($divId) {
                $dRow = _Query -Conn $conn -Sql @'
SELECT name FROM ref_divisions
WHERE case_id = @cid AND division_id = @did
LIMIT 1
'@ -P @{ '@cid' = $CaseId; '@did' = $divId }
                if ($dRow.Count -gt 0) { $divName = [string]($dRow[0].name) }
            }

            # Resolve queue names that this agent handled in the case conversations.
            # Use delimiter-aware matching to avoid partial name matches: the
            # agent_names column stores pipe-delimited display names.
            $queueIds = ''
            if ($uname -and -not $uname.EndsWith('(unresolved)')) {
                # Match exact name: alone, at start, in middle, or at end of the pipe-delimited list
                $pExact  = $uname
                $pStart  = "$uname|%"
                $pMid    = "%|$uname|%"
                $pEnd    = "%|$uname"
                $qRows = _Query -Conn $conn -Sql @'
SELECT DISTINCT queue_name
FROM conversations
WHERE case_id = @cid AND queue_name <> ''
  AND (   agent_names = @exact
       OR agent_names LIKE @pstart
       OR agent_names LIKE @pmid
       OR agent_names LIKE @pend)
ORDER BY queue_name
'@ -P @{ '@cid' = $CaseId; '@exact' = $pExact; '@pstart' = $pStart; '@pmid' = $pMid; '@pend' = $pEnd }
                $queueIds = ($qRows | ForEach-Object { [string]($_.queue_name) } | Where-Object { $_ }) -join '|'
            }

            # Choose the best-available handle count and sums
            # Prefer user-aggregate metrics when available (more complete); fall back to conv-aggregate
            $nConn     = if ($entry.nConnectedUser -gt 0) { $entry.nConnectedUser } else { $entry.nConnectedConv }
            $nOffered  = $entry.nOfferedUser
            $tHandleMs = if ($entry.tHandleSumUser -gt 0) { $entry.tHandleSumUser } else { $entry.tHandleSumConv }
            $tTalkMs   = if ($entry.tTalkSumUser   -gt 0) { $entry.tTalkSumUser   } else { $entry.tTalkSumConv   }
            $tAcwMs    = if ($entry.tAcwSumUser    -gt 0) { $entry.tAcwSumUser    } else { $entry.tAcwSumConv    }

            $tHandleAvg = if ($nConn -gt 0) { [Math]::Round($tHandleMs / $nConn / 1000.0, 1) } else { 0.0 }
            $tTalkAvg   = if ($nConn -gt 0) { [Math]::Round($tTalkMs   / $nConn / 1000.0, 1) } else { 0.0 }
            $tAcwAvg    = if ($nConn -gt 0) { [Math]::Round($tAcwMs    / $nConn / 1000.0, 1) } else { 0.0 }

            $tOnQueueSec  = [Math]::Round($entry.tOnQueueMs  / 1000.0, 1)
            $tOffQueueSec = [Math]::Round($entry.tOffQueueMs / 1000.0, 1)
            $tIdleSec     = [Math]::Round($entry.tIdleMs     / 1000.0, 1)

            # talk_ratio_pct = tTalk / tHandle * 100
            $talkRatio = if ($tHandleMs -gt 0) { [Math]::Round(($tTalkMs / $tHandleMs) * 100.0, 1) } else { 0.0 }
            # acw_ratio_pct  = tAcw / tHandle * 100
            $acwRatio  = if ($tHandleMs -gt 0) { [Math]::Round(($tAcwMs  / $tHandleMs) * 100.0, 1) } else { 0.0 }
            # idle_ratio_pct = tIdle / (tOnQueue + tOffQueue + tIdle) * 100
            $totalTime = $entry.tOnQueueMs + $entry.tOffQueueMs + $entry.tIdleMs
            $idleRatio = if ($totalTime -gt 0) { [Math]::Round(($entry.tIdleMs / $totalTime) * 100.0, 1) } else { 0.0 }

            try {
                _NonQuery -Conn $conn -Sql @'
INSERT INTO report_agent_perf(
    row_id, case_id, user_id, user_name, user_email, department,
    division_id, division_name, queue_ids,
    n_connected, n_offered,
    t_handle_avg_sec, t_talk_avg_sec, t_acw_avg_sec,
    t_on_queue_sec, t_off_queue_sec, t_idle_sec,
    talk_ratio_pct, acw_ratio_pct, idle_ratio_pct,
    imported_utc)
VALUES(
    @rid, @cid, @uid, @uname, @uemail, @udept,
    @divid, @divname, @qids,
    @nconn, @noff,
    @thandle, @ttalk, @tacw,
    @tonq, @toffq, @tidle,
    @talkr, @acwr, @idler,
    @ts)
ON CONFLICT(row_id) DO UPDATE SET
    user_name=excluded.user_name, user_email=excluded.user_email,
    department=excluded.department,
    division_id=excluded.division_id, division_name=excluded.division_name,
    queue_ids=excluded.queue_ids,
    n_connected=excluded.n_connected, n_offered=excluded.n_offered,
    t_handle_avg_sec=excluded.t_handle_avg_sec,
    t_talk_avg_sec=excluded.t_talk_avg_sec,
    t_acw_avg_sec=excluded.t_acw_avg_sec,
    t_on_queue_sec=excluded.t_on_queue_sec,
    t_off_queue_sec=excluded.t_off_queue_sec,
    t_idle_sec=excluded.t_idle_sec,
    talk_ratio_pct=excluded.talk_ratio_pct,
    acw_ratio_pct=excluded.acw_ratio_pct,
    idle_ratio_pct=excluded.idle_ratio_pct,
    imported_utc=excluded.imported_utc
'@ -P @{
                    '@rid'     = $rowKey
                    '@cid'     = $CaseId
                    '@uid'     = $uid
                    '@uname'   = $uname
                    '@uemail'  = $uemail
                    '@udept'   = $udept
                    '@divid'   = $divId
                    '@divname' = $divName
                    '@qids'    = $queueIds
                    '@nconn'   = $nConn
                    '@noff'    = $nOffered
                    '@thandle' = $tHandleAvg
                    '@ttalk'   = $tTalkAvg
                    '@tacw'    = $tAcwAvg
                    '@tonq'    = $tOnQueueSec
                    '@toffq'   = $tOffQueueSec
                    '@tidle'   = $tIdleSec
                    '@talkr'   = $talkRatio
                    '@acwr'    = $acwRatio
                    '@idler'   = $idleRatio
                    '@ts'      = $now
                } | Out-Null
                $stats.RecordCount++
            } catch {
                Write-Warning "Import-AgentPerformanceReport: failed to upsert row for user '$uid' — $($_.Exception.Message)"
                $stats.SkippedCount++
            }
        }
    } finally { $conn.Close(); $conn.Dispose() }

    return $stats
}

function Get-AgentPerfRows {
    <#
    .SYNOPSIS
        Returns agent performance rows for a case, optionally filtered by division.
    .DESCRIPTION
        Returns all rows from report_agent_perf for the given case, sorted by
        user_name ascending.  When DivisionId is provided, only rows for that
        division are returned.
    .PARAMETER CaseId
        The case to query.
    .PARAMETER DivisionId
        Optional division GUID to filter by.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [string] $DivisionId = ''
    )
    _RequireDb

    if ($DivisionId) {
        $sql = @'
SELECT user_id, user_name, user_email, department,
       division_id, division_name, queue_ids,
       n_connected, n_offered,
       t_handle_avg_sec, t_talk_avg_sec, t_acw_avg_sec,
       t_on_queue_sec, t_off_queue_sec, t_idle_sec,
       talk_ratio_pct, acw_ratio_pct, idle_ratio_pct
FROM   report_agent_perf
WHERE  case_id = @cid AND division_id = @did
ORDER  BY user_name ASC
'@
        $p = @{ '@cid' = $CaseId; '@did' = $DivisionId }
    } else {
        $sql = @'
SELECT user_id, user_name, user_email, department,
       division_id, division_name, queue_ids,
       n_connected, n_offered,
       t_handle_avg_sec, t_talk_avg_sec, t_acw_avg_sec,
       t_on_queue_sec, t_off_queue_sec, t_idle_sec,
       talk_ratio_pct, acw_ratio_pct, idle_ratio_pct
FROM   report_agent_perf
WHERE  case_id = @cid
ORDER  BY user_name ASC
'@
        $p = @{ '@cid' = $CaseId }
    }

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }

    return @($rows)
}

function Get-AgentPerfSummary {
    <#
    .SYNOPSIS
        Returns org-wide aggregate totals across all report_agent_perf rows for a case.
    .DESCRIPTION
        Rolls up all rows (or those matching an optional DivisionId filter) into a
        single summary object used to populate the summary bar above the DataGrid.
    .PARAMETER CaseId
        The case to query.
    .PARAMETER DivisionId
        Optional division GUID to filter by.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [string] $DivisionId = ''
    )
    _RequireDb

    if ($DivisionId) {
        $sql = @'
SELECT
    COUNT(DISTINCT user_id)     AS total_agents,
    SUM(n_connected)            AS total_connected,
    AVG(t_handle_avg_sec)       AS avg_handle_sec,
    AVG(talk_ratio_pct)         AS avg_talk_pct,
    AVG(acw_ratio_pct)          AS avg_acw_pct,
    AVG(idle_ratio_pct)         AS avg_idle_pct
FROM report_agent_perf
WHERE case_id = @cid AND division_id = @did
'@
        $p = @{ '@cid' = $CaseId; '@did' = $DivisionId }
    } else {
        $sql = @'
SELECT
    COUNT(DISTINCT user_id)     AS total_agents,
    SUM(n_connected)            AS total_connected,
    AVG(t_handle_avg_sec)       AS avg_handle_sec,
    AVG(talk_ratio_pct)         AS avg_talk_pct,
    AVG(acw_ratio_pct)          AS avg_acw_pct,
    AVG(idle_ratio_pct)         AS avg_idle_pct
FROM report_agent_perf
WHERE case_id = @cid
'@
        $p = @{ '@cid' = $CaseId }
    }

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }

    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            TotalAgents    = 0
            TotalConnected = 0
            AvgHandleSec   = 0.0
            AvgTalkPct     = 0.0
            AvgAcwPct      = 0.0
            AvgIdlePct     = 0.0
        }
    }
    $r = $rows[0]
    return [pscustomobject]@{
        TotalAgents    = [int]   (_RowVal $r 'total_agents'    0)
        TotalConnected = [int]   (_RowVal $r 'total_connected' 0)
        AvgHandleSec   = [double](_RowVal $r 'avg_handle_sec'  0.0)
        AvgTalkPct     = [double](_RowVal $r 'avg_talk_pct'    0.0)
        AvgAcwPct      = [double](_RowVal $r 'avg_acw_pct'     0.0)
        AvgIdlePct     = [double](_RowVal $r 'avg_idle_pct'    0.0)
    }
}

function Import-TransferReport {
    <#
    .SYNOPSIS
        Session 16 — imports transfer aggregate data and derives per-conversation
        escalation chains from the already-imported participants_json payloads.
    .DESCRIPTION
        Two-phase import:

        Phase 1 — read the aggregate dataset run folder for
        analytics.query.conversation.aggregates.transfer.metrics to derive the
        denominator for pct_of_total_offered.  The catalog emits nConnected and
        nTransferred for this dataset; nOffered is supported when present.

        Phase 2 — walk every conversation row for the case, parse
        participants_json, collect segments that carry a queueId (any segment
        type), sort them chronologically, and build a distinct-queue sequence.
        From that sequence we derive:
          - per-conversation transfer chain  → report_transfer_chains
          - per (from, to, type) aggregate   → report_transfer_flows

        Transfer-type classification is per-conversation:
          - consult : the conversation contains any segment whose segmentType
                      matches 'consult' OR a participant whose purpose is
                      'internal' or 'peer' (consult call peer).
          - blind   : default when no consult indicator is present.

        The whole conversation's hops inherit that label.  This is a
        pragmatic inference — the Genesys segment model does not emit a
        per-hop transfer-type flag — and is documented in code so readers
        understand the limitation.

        Rows in report_transfer_flows are upserted by
        (case_id, queue_id_from, queue_id_to, transfer_type).
        Rows in report_transfer_chains are upserted by
        (case_id, conversation_id).

        Returns a hashtable with RecordCount (flow rows written),
        ChainCount (chain rows written), TotalOffered (denominator),
        and SkippedCount.
    .PARAMETER CaseId
        Target case identifier.
    .PARAMETER FolderMap
        Hashtable returned by Get-TransferReport (App.CoreAdapter.psm1).
        Keys: 'TransferMetricsFolder'.  When null/missing, phase 1 is skipped
        and pct_of_total_offered is computed against the sum of n_transfers.
    #>
    param(
        [Parameter(Mandatory)][string]    $CaseId,
        [Parameter(Mandatory)][hashtable] $FolderMap
    )
    _RequireDb

    $now   = [datetime]::UtcNow.ToString('o')
    $stats = @{ RecordCount = 0; ChainCount = 0; TotalOffered = 0; SkippedCount = 0 }

    # ── Phase 1 : read aggregate dataset for the denominator ──────────────────
    $metricTotals = @{
        nOffered     = 0
        nConnected   = 0
        nTransferred = 0
    }
    $xferFolder = if ($FolderMap.ContainsKey('TransferMetricsFolder')) { $FolderMap['TransferMetricsFolder'] } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($xferFolder) -and
        [System.IO.Directory]::Exists($xferFolder)) {

        $dataDir = [System.IO.Path]::Combine($xferFolder, 'data')
        if ([System.IO.Directory]::Exists($dataDir)) {
            foreach ($f in [System.IO.Directory]::GetFiles($dataDir, '*.jsonl')) {
                foreach ($line in [System.IO.File]::ReadAllLines($f)) {
                    $t = $line.Trim()
                    if (-not $t) { continue }
                    try {
                        $result = $t | ConvertFrom-Json
                        if ($null -eq $result -or $null -eq $result.data) { continue }
                        foreach ($d in @($result.data)) {
                            foreach ($m in @($d.metrics)) {
                                $metricName = [string]$m.metric
                                if ($metricTotals.ContainsKey($metricName) -and $m.stats -and $m.stats.count) {
                                    $metricTotals[$metricName] += [int]$m.stats.count
                                }
                            }
                        }
                    } catch {
                        Write-Warning "Import-TransferReport: skipping malformed JSONL line in $f — $($_.Exception.Message)"
                    }
                }
            }
        }
    }
    $totalOffered = if ($metricTotals.nOffered -gt 0) {
        $metricTotals.nOffered
    } elseif ($metricTotals.nConnected -gt 0) {
        $metricTotals.nConnected
    } else {
        $metricTotals.nTransferred
    }
    $stats.TotalOffered = $totalOffered

    # ── Phase 2 : walk conversations, build chains ────────────────────────────
    $conn = _Open
    try {
        # Purge any existing flow+chain rows for this case so the import is
        # authoritative and repeat pulls don't accumulate stale pairs.
        _NonQuery -Conn $conn -Sql 'DELETE FROM report_transfer_flows  WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
        _NonQuery -Conn $conn -Sql 'DELETE FROM report_transfer_chains WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null

        # Read all conversations for this case.  We only need the side-car
        # participants JSON + disconnect_type to build chains.
        $convRows = _Query -Conn $conn -Sql @'
SELECT conversation_id, disconnect_type, participants_json
FROM   conversations
WHERE  case_id = @cid
'@ -P @{ '@cid' = $CaseId }

        # Resolve queue-id → queue-name map for this case from ref_queues.
        $queueNameMap = @{}
        $qRefRows = _Query -Conn $conn -Sql 'SELECT queue_id, name FROM ref_queues WHERE case_id = @cid' -P @{ '@cid' = $CaseId }
        foreach ($qr in $qRefRows) {
            $qid = [string]$qr.queue_id
            if ($qid) { $queueNameMap[$qid] = [string]$qr.name }
        }

        # Accumulator:  "from|to|type"  →  @{ From; To; FromName; ToName; Type; Count }
        $flowAgg = @{}
        # List<chainRow>
        $chainRows = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($cr in $convRows) {
            $convId        = [string]$cr.conversation_id
            $convDisconn   = [string]$cr.disconnect_type
            $partJson      = _RowVal $cr 'participants_json' $null
            if ($null -eq $partJson -or [string]::IsNullOrWhiteSpace([string]$partJson)) { continue }

            try {
                $participants = @($partJson | ConvertFrom-Json)
            } catch {
                $stats.SkippedCount++
                continue
            }
            if ($participants.Count -eq 0) { continue }

            # Collect queue touches from every segment that carries a queueId.
            # Also track consult-indicator presence anywhere in the conversation.
            $touches       = [System.Collections.Generic.List[pscustomobject]]::new()
            $hasConsult    = $false
            $lastDisconn   = $convDisconn
            $lastQueueName = ''

            foreach ($p in $participants) {
                $purpose = if ($p.PSObject.Properties['purpose']) { [string]$p.purpose } else { '' }
                # 'internal' or 'peer' participant purpose is a consult-call signal
                if ($purpose -eq 'internal' -or $purpose -eq 'peer') { $hasConsult = $true }

                if (-not $p.PSObject.Properties['sessions']) { continue }
                foreach ($s in @($p.sessions)) {
                    if (-not $s.PSObject.Properties['segments']) { continue }
                    foreach ($seg in @($s.segments)) {
                        $segType = if ($seg.PSObject.Properties['segmentType']) { [string]$seg.segmentType } else { '' }
                        if ($segType -match '(?i)consult') { $hasConsult = $true }

                        $qId   = if ($seg.PSObject.Properties['queueId'])   { [string]$seg.queueId   } else { '' }
                        $qName = if ($seg.PSObject.Properties['queueName']) { [string]$seg.queueName } else { '' }
                        if (-not $qId -and -not $qName) { continue }

                        $startStr = if ($seg.PSObject.Properties['segmentStart']) { [string]$seg.segmentStart } else { '' }
                        $startDt  = [datetime]::MinValue
                        if ($startStr) {
                            try { $startDt = [datetime]::Parse($startStr).ToUniversalTime() } catch { }
                        }
                        $segDisconn = if ($seg.PSObject.Properties['disconnectType']) { [string]$seg.disconnectType } else { '' }

                        $touches.Add([pscustomobject]@{
                            Start       = $startDt
                            QueueId     = $qId
                            QueueName   = $qName
                            DisconnType = $segDisconn
                        })
                    }
                }
            }

            if ($touches.Count -eq 0) { continue }

            # Sort chronologically and build a distinct-queue sequence.
            $ordered = @($touches | Sort-Object Start)
            $sequence = [System.Collections.Generic.List[pscustomobject]]::new()
            foreach ($tch in $ordered) {
                $qKey = if ($tch.QueueId) { $tch.QueueId } else { "name:$($tch.QueueName)" }
                if ($sequence.Count -eq 0 -or $sequence[$sequence.Count - 1].Key -ne $qKey) {
                    $sequence.Add([pscustomobject]@{
                        Key         = $qKey
                        QueueId     = $tch.QueueId
                        QueueName   = $tch.QueueName
                        DisconnType = $tch.DisconnType
                    })
                }
                if ($tch.DisconnType) { $lastDisconn = $tch.DisconnType }
                if ($tch.QueueName)   { $lastQueueName = $tch.QueueName }
            }

            $hopCount = [Math]::Max(0, $sequence.Count - 1)
            if ($hopCount -eq 0) { continue }   # queue-touched but never transferred

            # Classify conversation type (applied to every hop in the chain).
            $convType = if ($hasConsult) { 'consult' } else { 'blind' }

            # Build pipe-delimited sequence of queue display names.
            $seqNames = [System.Collections.Generic.List[string]]::new()
            foreach ($n in $sequence) {
                $disp = if ($n.QueueName) { $n.QueueName }
                        elseif ($n.QueueId -and $queueNameMap.ContainsKey($n.QueueId)) { $queueNameMap[$n.QueueId] }
                        elseif ($n.QueueId) { "$($n.QueueId) (unresolved)" }
                        else { '(unknown)' }
                $seqNames.Add($disp) | Out-Null
            }
            $transferSeq   = ($seqNames -join '|')
            $finalQueueNm  = if ($seqNames.Count -gt 0) { $seqNames[$seqNames.Count - 1] } else { $lastQueueName }

            $chainRows.Add(@{
                ConversationId      = $convId
                TransferSequence    = $transferSeq
                HopCount            = $hopCount
                FinalQueueName      = $finalQueueNm
                FinalDisconnectType = $lastDisconn
                HasBlind            = if ($convType -eq 'blind')   { 1 } else { 0 }
                HasConsult          = if ($convType -eq 'consult') { 1 } else { 0 }
            })

            # Aggregate hops into flow buckets.
            for ($i = 0; $i -lt $sequence.Count - 1; $i++) {
                $from = $sequence[$i]
                $to   = $sequence[$i + 1]
                $fromName = if ($from.QueueName) { $from.QueueName }
                            elseif ($from.QueueId -and $queueNameMap.ContainsKey($from.QueueId)) { $queueNameMap[$from.QueueId] }
                            elseif ($from.QueueId) { "$($from.QueueId) (unresolved)" }
                            else { '(unknown)' }
                $toName   = if ($to.QueueName) { $to.QueueName }
                            elseif ($to.QueueId -and $queueNameMap.ContainsKey($to.QueueId)) { $queueNameMap[$to.QueueId] }
                            elseif ($to.QueueId) { "$($to.QueueId) (unresolved)" }
                            else { '(unknown)' }
                $fromKey  = if ($from.QueueId) { [string]$from.QueueId } else { [string]$from.Key }
                $toKey    = if ($to.QueueId)   { [string]$to.QueueId   } else { [string]$to.Key }
                $flowKey  = "$fromKey|$toKey|$convType"
                if (-not $flowAgg.ContainsKey($flowKey)) {
                    $flowAgg[$flowKey] = @{
                        FromKey      = $fromKey
                        From         = $from.QueueId
                        FromName     = $fromName
                        ToKey        = $toKey
                        To           = $to.QueueId
                        ToName       = $toName
                        Type         = $convType
                        Count        = 0
                    }
                }
                $flowAgg[$flowKey].Count++
            }
        }

        # ── Write report_transfer_flows ───────────────────────────────────────
        $denominator = if ($totalOffered -gt 0) {
            $totalOffered
        } else {
            # Fallback: use the sum of all hop counts if the aggregate dataset
            # returned no data. Percentages then reflect share of total hops.
            $sum = 0
            foreach ($v in $flowAgg.Values) { $sum += $v.Count }
            if ($sum -eq 0) { 1 } else { $sum }
        }

        foreach ($f in $flowAgg.Values) {
            $rowKey = "$CaseId|xfer|$($f.FromKey)|$($f.ToKey)|$($f.Type)"
            $pct    = [Math]::Round(($f.Count / $denominator) * 100.0, 1)
            try {
                _NonQuery -Conn $conn -Sql @'
INSERT INTO report_transfer_flows(
    row_id, case_id,
    queue_id_from, queue_name_from, queue_id_to, queue_name_to,
    transfer_type, n_transfers, pct_of_total_offered, imported_utc)
VALUES(
    @rid, @cid,
    @qfid, @qfname, @qtid, @qtname,
    @type, @n, @pct, @ts)
ON CONFLICT(row_id) DO UPDATE SET
    queue_name_from=excluded.queue_name_from,
    queue_name_to=excluded.queue_name_to,
    n_transfers=excluded.n_transfers,
    pct_of_total_offered=excluded.pct_of_total_offered,
    imported_utc=excluded.imported_utc
'@ -P @{
                    '@rid'    = $rowKey
                    '@cid'    = $CaseId
                    '@qfid'   = [string]$f.From
                    '@qfname' = [string]$f.FromName
                    '@qtid'   = [string]$f.To
                    '@qtname' = [string]$f.ToName
                    '@type'   = [string]$f.Type
                    '@n'      = [int]$f.Count
                    '@pct'    = [double]$pct
                    '@ts'     = $now
                } | Out-Null
                $stats.RecordCount++
            } catch {
                Write-Warning "Import-TransferReport: failed to upsert flow row '$rowKey' — $($_.Exception.Message)"
                $stats.SkippedCount++
            }
        }

        # ── Write report_transfer_chains ──────────────────────────────────────
        foreach ($c in $chainRows) {
            $rowKey = "$CaseId|chain|$($c.ConversationId)"
            try {
                _NonQuery -Conn $conn -Sql @'
INSERT INTO report_transfer_chains(
    row_id, case_id, conversation_id, transfer_sequence, hop_count,
    final_queue_name, final_disconnect_type,
    has_blind_transfer, has_consult_transfer, imported_utc)
VALUES(
    @rid, @cid, @cvid, @seq, @hops,
    @finalq, @finald,
    @blind, @consult, @ts)
ON CONFLICT(row_id) DO UPDATE SET
    transfer_sequence=excluded.transfer_sequence,
    hop_count=excluded.hop_count,
    final_queue_name=excluded.final_queue_name,
    final_disconnect_type=excluded.final_disconnect_type,
    has_blind_transfer=excluded.has_blind_transfer,
    has_consult_transfer=excluded.has_consult_transfer,
    imported_utc=excluded.imported_utc
'@ -P @{
                    '@rid'     = $rowKey
                    '@cid'     = $CaseId
                    '@cvid'    = [string]$c.ConversationId
                    '@seq'     = [string]$c.TransferSequence
                    '@hops'    = [int]   $c.HopCount
                    '@finalq'  = [string]$c.FinalQueueName
                    '@finald'  = [string]$c.FinalDisconnectType
                    '@blind'   = [int]   $c.HasBlind
                    '@consult' = [int]   $c.HasConsult
                    '@ts'      = $now
                } | Out-Null
                $stats.ChainCount++
            } catch {
                Write-Warning "Import-TransferReport: failed to upsert chain row '$rowKey' — $($_.Exception.Message)"
                $stats.SkippedCount++
            }
        }
    } finally { $conn.Close(); $conn.Dispose() }

    return $stats
}

function Get-TransferFlowRows {
    <#
    .SYNOPSIS
        Returns report_transfer_flows rows for a case, sorted by n_transfers
        descending then queue_name_from ascending.
    .PARAMETER CaseId
        The case to query.
    .PARAMETER TransferType
        Optional 'blind' or 'consult' filter. Empty returns both.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [string] $TransferType = ''
    )
    _RequireDb

    if ($TransferType) {
        $sql = @'
SELECT queue_id_from, queue_name_from, queue_id_to, queue_name_to,
       transfer_type, n_transfers, pct_of_total_offered
FROM   report_transfer_flows
WHERE  case_id = @cid AND transfer_type = @type
ORDER  BY n_transfers DESC, queue_name_from ASC
'@
        $p = @{ '@cid' = $CaseId; '@type' = $TransferType }
    } else {
        $sql = @'
SELECT queue_id_from, queue_name_from, queue_id_to, queue_name_to,
       transfer_type, n_transfers, pct_of_total_offered
FROM   report_transfer_flows
WHERE  case_id = @cid
ORDER  BY n_transfers DESC, queue_name_from ASC
'@
        $p = @{ '@cid' = $CaseId }
    }

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P $p
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows)
}

function Get-TransferChainRows {
    <#
    .SYNOPSIS
        Returns report_transfer_chains rows for a case, sorted by hop_count
        descending then conversation_id ascending.
    .PARAMETER CaseId
        The case to query.
    .PARAMETER MinHops
        Minimum hop_count to include (default 1). Use 2 for the multi-hop view.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [int] $MinHops = 1
    )
    _RequireDb

    $sql = @'
SELECT conversation_id, transfer_sequence, hop_count,
       final_queue_name, final_disconnect_type,
       has_blind_transfer, has_consult_transfer
FROM   report_transfer_chains
WHERE  case_id = @cid AND hop_count >= @min
ORDER  BY hop_count DESC, conversation_id ASC
'@
    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql $sql -P @{ '@cid' = $CaseId; '@min' = $MinHops }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows)
}

function Get-TransferSummary {
    <#
    .SYNOPSIS
        Returns aggregate Blind vs Consult counts and totals for the summary tiles.
    .DESCRIPTION
        Produces a single PSCustomObject with:
          TotalFlows, TotalTransfers, BlindTransfers, ConsultTransfers,
          BlindPct, ConsultPct, TotalChains, MultiHopChains.
    .PARAMETER CaseId
        The case to query.
    #>
    param([Parameter(Mandatory)][string] $CaseId)
    _RequireDb

    $conn = _Open
    try {
        $fRow = _Query -Conn $conn -Sql @'
SELECT
    COUNT(*)                                                      AS total_flows,
    COALESCE(SUM(n_transfers), 0)                                 AS total_transfers,
    COALESCE(SUM(CASE WHEN transfer_type='blind'   THEN n_transfers ELSE 0 END), 0) AS blind_count,
    COALESCE(SUM(CASE WHEN transfer_type='consult' THEN n_transfers ELSE 0 END), 0) AS consult_count
FROM report_transfer_flows
WHERE case_id = @cid
'@ -P @{ '@cid' = $CaseId }
        $cRow = _Query -Conn $conn -Sql @'
SELECT
    COUNT(*)                              AS total_chains,
    SUM(CASE WHEN hop_count >= 2 THEN 1 ELSE 0 END) AS multi_hop_chains
FROM report_transfer_chains
WHERE case_id = @cid
'@ -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }

    $total  = if ($fRow.Count -gt 0) { [int](_RowVal $fRow[0] 'total_transfers' 0) } else { 0 }
    $blind  = if ($fRow.Count -gt 0) { [int](_RowVal $fRow[0] 'blind_count'     0) } else { 0 }
    $cons   = if ($fRow.Count -gt 0) { [int](_RowVal $fRow[0] 'consult_count'   0) } else { 0 }
    $flows  = if ($fRow.Count -gt 0) { [int](_RowVal $fRow[0] 'total_flows'     0) } else { 0 }
    $chains = if ($cRow.Count -gt 0) { [int](_RowVal $cRow[0] 'total_chains'    0) } else { 0 }
    $multi  = if ($cRow.Count -gt 0) { [int](_RowVal $cRow[0] 'multi_hop_chains' 0) } else { 0 }
    $blindPct   = if ($total -gt 0) { [Math]::Round(($blind / $total) * 100.0, 1) } else { 0.0 }
    $consultPct = if ($total -gt 0) { [Math]::Round(($cons  / $total) * 100.0, 1) } else { 0.0 }

    return [pscustomobject]@{
        TotalFlows       = $flows
        TotalTransfers   = $total
        BlindTransfers   = $blind
        ConsultTransfers = $cons
        BlindPct         = $blindPct
        ConsultPct       = $consultPct
        TotalChains      = $chains
        MultiHopChains   = $multi
    }
}

# ── Public: Flow & IVR Containment Report (Session 17) ───────────────────────

function Import-FlowContainmentReport {
    <#
    .SYNOPSIS
        Session 17 — imports flow execution aggregate data into the local case
        store and computes IVR containment/failure metrics.
    .DESCRIPTION
        Reads JSONL outputs from:
          - analytics.query.flow.aggregates.execution.metrics
          - flows.get.all.flows
          - flows.get.flow.outcomes
          - flows.get.flow.milestones

        Rows are upserted into report_flow_perf by (case_id, flow_id, flow_type)
        and report_flow_milestone_distribution by
        (case_id, flow_id, milestone_id).  When the aggregate payload does not
        include a milestone dimension, the milestone table stores an aggregate
        "(all milestones)" row for the flow.

        Containment is a conservative aggregate proxy:
          (nFlowOutcome - nFlowOutcomeFailed) / nFlow * 100

        This treats successful defined outcomes as self-service completions.
        Queue overflow correlation is computed separately from local
        conversation detail rows by Get-FlowQueueRouteRows.
    #>
    param(
        [Parameter(Mandatory)][string]    $CaseId,
        [Parameter(Mandatory)][hashtable] $FolderMap
    )
    _RequireDb

    $now   = [datetime]::UtcNow.ToString('o')
    $stats = @{ RecordCount = 0; MilestoneCount = 0; SkippedCount = 0 }

    function _ReadFlowJsonl ([string]$RunFolder) {
        if ([string]::IsNullOrWhiteSpace($RunFolder) -or
            -not [System.IO.Directory]::Exists($RunFolder)) {
            return @()
        }
        $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
        if (-not [System.IO.Directory]::Exists($dataDir)) { return @() }
        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($f in [System.IO.Directory]::GetFiles($dataDir, '*.jsonl')) {
            foreach ($line in [System.IO.File]::ReadAllLines($f)) {
                $t = $line.Trim()
                if ($t) {
                    try { $records.Add(($t | ConvertFrom-Json)) } catch {
                        Write-Warning "Import-FlowContainmentReport: skipping malformed JSONL line in $f — $($_.Exception.Message)"
                    }
                }
            }
        }
        return $records.ToArray()
    }

    $flowDefsFolder = if ($FolderMap.ContainsKey('FlowDefsFolder')) { $FolderMap['FlowDefsFolder'] } else { $null }
    $milestoneFolder = if ($FolderMap.ContainsKey('FlowMilestonesFolder')) { $FolderMap['FlowMilestonesFolder'] } else { $null }
    $aggFolder = if ($FolderMap.ContainsKey('FlowAggFolder')) { $FolderMap['FlowAggFolder'] } else { $null }

    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql 'DELETE FROM report_flow_perf WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
        _NonQuery -Conn $conn -Sql 'DELETE FROM report_flow_milestone_distribution WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null

        $divisionMap = @{}
        foreach ($d in (_Query -Conn $conn -Sql 'SELECT division_id, name FROM ref_divisions WHERE case_id = @cid' -P @{ '@cid' = $CaseId })) {
            $did = [string]$d.division_id
            if ($did) { $divisionMap[$did] = [string]$d.name }
        }

        $flowMap = @{}
        foreach ($f in (_Query -Conn $conn -Sql 'SELECT flow_id, name, flow_type FROM ref_flows WHERE case_id = @cid' -P @{ '@cid' = $CaseId })) {
            $fid = [string]$f.flow_id
            if ($fid) {
                $flowMap[$fid] = @{
                    Name         = [string]$f.name
                    FlowType     = [string]$f.flow_type
                    DivisionId   = ''
                    DivisionName = ''
                }
            }
        }

        foreach ($f in (_ReadFlowJsonl $flowDefsFolder)) {
            $fid = [string](_ObjVal $f @('id','flowId') '')
            if (-not $fid) { continue }
            $divId = [string](_ObjVal (_ObjVal $f @('division') $null) @('id') '')
            $divName = [string](_ObjVal (_ObjVal $f @('division') $null) @('name') '')
            if (-not $divName -and $divId -and $divisionMap.ContainsKey($divId)) { $divName = $divisionMap[$divId] }
            $flowMap[$fid] = @{
                Name         = [string](_ObjVal $f @('name') '')
                FlowType     = [string](_ObjVal $f @('type','flowType') '')
                DivisionId   = $divId
                DivisionName = $divName
            }
        }

        $milestoneMap = @{}
        foreach ($m in (_Query -Conn $conn -Sql 'SELECT milestone_id, name FROM ref_flow_milestones WHERE case_id = @cid' -P @{ '@cid' = $CaseId })) {
            $mid = [string]$m.milestone_id
            if ($mid) { $milestoneMap[$mid] = [string]$m.name }
        }
        foreach ($m in (_ReadFlowJsonl $milestoneFolder)) {
            $mid = [string](_ObjVal $m @('id','milestoneId','flowMilestoneId') '')
            if ($mid) { $milestoneMap[$mid] = [string](_ObjVal $m @('name') '') }
        }

        $merged = @{}
        $milestones = @{}

        foreach ($r in (_ReadFlowJsonl $aggFolder)) {
            if ($null -eq $r -or $null -eq $r.data) { continue }
            $group = $r.group
            $flowId = [string](_ObjVal $group @('flowId') '')
            if (-not $flowId) { $stats.SkippedCount++; continue }
            $flowType = [string](_ObjVal $group @('flowType') '')
            $key = "$flowId|$flowType"
            if (-not $merged.ContainsKey($key)) {
                $merged[$key] = @{
                    FlowId = $flowId; FlowType = $flowType
                    nFlow = 0; nOutcome = 0; nFailed = 0; nMilestone = 0
                }
            }

            $milestoneId = [string](_ObjVal $group @('flowMilestoneId','milestoneId') '')
            foreach ($d in @($r.data)) {
                foreach ($m in @($d.metrics)) {
                    $metric = [string]$m.metric
                    $count = if ($m.stats -and $m.stats.count) { [int]$m.stats.count } else { 0 }
                    if ($count -eq 0) { continue }
                    switch ($metric) {
                        'nFlow' { $merged[$key].nFlow += $count }
                        'nFlowOutcome' { $merged[$key].nOutcome += $count }
                        'nFlowOutcomeFailed' { $merged[$key].nFailed += $count }
                        'nFlowMilestone' {
                            $merged[$key].nMilestone += $count
                            $mKey = if ($milestoneId) { "$flowId|$milestoneId" } else { "$flowId|__all__" }
                            if (-not $milestones.ContainsKey($mKey)) {
                                $milestones[$mKey] = @{ FlowId = $flowId; MilestoneId = $milestoneId; Count = 0 }
                            }
                            $milestones[$mKey].Count += $count
                        }
                    }
                }
            }
        }

        foreach ($entry in $merged.Values) {
            $fid = [string]$entry.FlowId
            $meta = if ($flowMap.ContainsKey($fid)) { $flowMap[$fid] } else { $null }
            $flowName = if ($null -ne $meta -and $meta.Name) { [string]$meta.Name } else { "$fid (unresolved)" }
            $flowType = if ($entry.FlowType) { [string]$entry.FlowType } elseif ($null -ne $meta) { [string]$meta.FlowType } else { '' }
            $divId = if ($null -ne $meta) { [string]$meta.DivisionId } else { '' }
            $divName = if ($null -ne $meta) { [string]$meta.DivisionName } else { '' }
            $success = [Math]::Max(0, [int]$entry.nOutcome - [int]$entry.nFailed)
            $contain = if ($entry.nFlow -gt 0) { [Math]::Round(($success / $entry.nFlow) * 100.0, 1) } else { 0.0 }
            $failure = if ($entry.nFlow -gt 0) { [Math]::Round(($entry.nFailed / $entry.nFlow) * 100.0, 1) } else { 0.0 }
            $rowKey = "$CaseId|flow|$fid|$flowType"

            _NonQuery -Conn $conn -Sql @'
INSERT INTO report_flow_perf(
    row_id, case_id, flow_id, flow_name, flow_type, division_id, division_name,
    n_flow, n_flow_outcome_success, n_flow_outcome_failed, n_flow_milestone_hit,
    containment_rate_pct, failure_rate_pct, imported_utc)
VALUES(
    @rid, @cid, @fid, @fname, @ftype, @divid, @divname,
    @nflow, @nsuccess, @nfailed, @nms,
    @contain, @fail, @ts)
ON CONFLICT(row_id) DO UPDATE SET
    flow_name=excluded.flow_name, flow_type=excluded.flow_type,
    division_id=excluded.division_id, division_name=excluded.division_name,
    n_flow=excluded.n_flow,
    n_flow_outcome_success=excluded.n_flow_outcome_success,
    n_flow_outcome_failed=excluded.n_flow_outcome_failed,
    n_flow_milestone_hit=excluded.n_flow_milestone_hit,
    containment_rate_pct=excluded.containment_rate_pct,
    failure_rate_pct=excluded.failure_rate_pct,
    imported_utc=excluded.imported_utc
'@ -P @{
                '@rid' = $rowKey; '@cid' = $CaseId; '@fid' = $fid; '@fname' = $flowName
                '@ftype' = $flowType; '@divid' = $divId; '@divname' = $divName
                '@nflow' = [int]$entry.nFlow; '@nsuccess' = [int]$success
                '@nfailed' = [int]$entry.nFailed; '@nms' = [int]$entry.nMilestone
                '@contain' = [double]$contain; '@fail' = [double]$failure; '@ts' = $now
            } | Out-Null
            $stats.RecordCount++
        }

        foreach ($m in $milestones.Values) {
            $fid = [string]$m.FlowId
            $meta = if ($flowMap.ContainsKey($fid)) { $flowMap[$fid] } else { $null }
            $flowName = if ($null -ne $meta -and $meta.Name) { [string]$meta.Name } else { "$fid (unresolved)" }
            $mid = [string]$m.MilestoneId
            $mName = if ($mid -and $milestoneMap.ContainsKey($mid)) { $milestoneMap[$mid] } elseif ($mid) { "$mid (unresolved)" } else { '(all milestones)' }
            $flowTotal = 0
            foreach ($entry in $merged.Values) { if ($entry.FlowId -eq $fid) { $flowTotal += [int]$entry.nFlow } }
            $pct = if ($flowTotal -gt 0) { [Math]::Round(($m.Count / $flowTotal) * 100.0, 1) } else { 0.0 }
            $rowKey = "$CaseId|flowms|$fid|$(if ($mid) { $mid } else { '__all__' })"

            _NonQuery -Conn $conn -Sql @'
INSERT INTO report_flow_milestone_distribution(
    row_id, case_id, flow_id, flow_name, milestone_id, milestone_name,
    n_hit, pct_of_entries, imported_utc)
VALUES(
    @rid, @cid, @fid, @fname, @mid, @mname,
    @n, @pct, @ts)
ON CONFLICT(row_id) DO UPDATE SET
    flow_name=excluded.flow_name,
    milestone_name=excluded.milestone_name,
    n_hit=excluded.n_hit,
    pct_of_entries=excluded.pct_of_entries,
    imported_utc=excluded.imported_utc
'@ -P @{
                '@rid' = $rowKey; '@cid' = $CaseId; '@fid' = $fid; '@fname' = $flowName
                '@mid' = $mid; '@mname' = $mName; '@n' = [int]$m.Count; '@pct' = [double]$pct; '@ts' = $now
            } | Out-Null
            $stats.MilestoneCount++
        }
    } finally { $conn.Close(); $conn.Dispose() }

    return $stats
}

function Get-FlowPerfRows {
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [string] $FlowType = ''
    )
    _RequireDb

    if ($FlowType) {
        $sql = @'
SELECT flow_id, flow_name, flow_type, division_id, division_name,
       n_flow, n_flow_outcome_success, n_flow_outcome_failed, n_flow_milestone_hit,
       containment_rate_pct, failure_rate_pct
FROM report_flow_perf
WHERE case_id = @cid AND LOWER(flow_type) = LOWER(@type)
ORDER BY containment_rate_pct ASC, n_flow DESC, flow_name ASC
'@
        $p = @{ '@cid' = $CaseId; '@type' = $FlowType }
    } else {
        $sql = @'
SELECT flow_id, flow_name, flow_type, division_id, division_name,
       n_flow, n_flow_outcome_success, n_flow_outcome_failed, n_flow_milestone_hit,
       containment_rate_pct, failure_rate_pct
FROM report_flow_perf
WHERE case_id = @cid
ORDER BY containment_rate_pct ASC, n_flow DESC, flow_name ASC
'@
        $p = @{ '@cid' = $CaseId }
    }

    $conn = _Open
    try { $rows = _Query -Conn $conn -Sql $sql -P $p }
    finally { $conn.Close(); $conn.Dispose() }
    return @($rows)
}

function Get-FlowMilestoneRows {
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [string] $FlowId = ''
    )
    _RequireDb

    if ($FlowId) {
        $sql = @'
SELECT flow_id, flow_name, milestone_id, milestone_name, n_hit, pct_of_entries
FROM report_flow_milestone_distribution
WHERE case_id = @cid AND flow_id = @fid
ORDER BY n_hit DESC, milestone_name ASC
'@
        $p = @{ '@cid' = $CaseId; '@fid' = $FlowId }
    } else {
        $sql = @'
SELECT flow_id, flow_name, milestone_id, milestone_name, n_hit, pct_of_entries
FROM report_flow_milestone_distribution
WHERE case_id = @cid
ORDER BY n_hit DESC, flow_name ASC
'@
        $p = @{ '@cid' = $CaseId }
    }

    $conn = _Open
    try { $rows = _Query -Conn $conn -Sql $sql -P $p }
    finally { $conn.Close(); $conn.Dispose() }
    return @($rows)
}

function Get-FlowContainmentSummary {
    param([Parameter(Mandatory)][string] $CaseId)
    _RequireDb

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql @'
SELECT
    COUNT(*) AS total_flows,
    COALESCE(SUM(n_flow), 0) AS total_entries,
    CASE WHEN COALESCE(SUM(n_flow), 0) > 0
         THEN ROUND((COALESCE(SUM(n_flow_outcome_success), 0) * 100.0) / SUM(n_flow), 1)
         ELSE 0 END AS avg_containment_pct,
    CASE WHEN COALESCE(SUM(n_flow), 0) > 0
         THEN ROUND((COALESCE(SUM(n_flow_outcome_failed), 0) * 100.0) / SUM(n_flow), 1)
         ELSE 0 END AS avg_failure_pct,
    SUM(CASE WHEN containment_rate_pct < 50 THEN 1 ELSE 0 END) AS low_containment_flows
FROM report_flow_perf
WHERE case_id = @cid
'@ -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }

    if ($rows.Count -eq 0) {
        return [pscustomobject]@{ TotalFlows = 0; TotalEntries = 0; AvgContainmentPct = 0.0; AvgFailurePct = 0.0; LowContainmentFlows = 0 }
    }
    $r = $rows[0]
    return [pscustomobject]@{
        TotalFlows          = [int]   (_RowVal $r 'total_flows' 0)
        TotalEntries        = [int]   (_RowVal $r 'total_entries' 0)
        AvgContainmentPct   = [double](_RowVal $r 'avg_containment_pct' 0.0)
        AvgFailurePct       = [double](_RowVal $r 'avg_failure_pct' 0.0)
        LowContainmentFlows = [int]   (_RowVal $r 'low_containment_flows' 0)
    }
}

function Get-FlowQueueRouteRows {
    <#
    .SYNOPSIS
        Derives queues reached by conversations that touched a selected flow,
        using local participants_json stored in the case.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [string] $FlowId = '',
        [string] $FlowName = ''
    )
    _RequireDb

    $conn = _Open
    try {
        $convRows = _Query -Conn $conn -Sql @'
SELECT conversation_id, participants_json
FROM conversations
WHERE case_id = @cid
'@ -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }

    $queueCounts = @{}
    foreach ($cr in $convRows) {
        $partJson = _RowVal $cr 'participants_json' $null
        if ($null -eq $partJson -or [string]::IsNullOrWhiteSpace([string]$partJson)) { continue }
        try { $participants = @($partJson | ConvertFrom-Json) } catch { continue }

        $flowTouched = $false
        $queues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($p in $participants) {
            $partFlowId = [string](_ObjVal $p @('flowId') '')
            $partFlowName = [string](_ObjVal $p @('flowName','participantName') '')
            if (($FlowId -and $partFlowId -eq $FlowId) -or
                ($FlowName -and $partFlowName -eq $FlowName)) {
                $flowTouched = $true
            }
            if (-not $p.PSObject.Properties['sessions']) { continue }
            foreach ($s in @($p.sessions)) {
                $sessFlowId = [string](_ObjVal $s @('flowId') '')
                $sessFlowName = [string](_ObjVal $s @('flowName') '')
                if (($FlowId -and $sessFlowId -eq $FlowId) -or
                    ($FlowName -and $sessFlowName -eq $FlowName)) {
                    $flowTouched = $true
                }
                $sessQueueName = [string](_ObjVal $s @('queueName') '')
                if ($sessQueueName) { $queues.Add($sessQueueName) | Out-Null }
                if (-not $s.PSObject.Properties['segments']) { continue }
                foreach ($seg in @($s.segments)) {
                    $segFlowId = [string](_ObjVal $seg @('flowId') '')
                    $segFlowName = [string](_ObjVal $seg @('flowName') '')
                    if (($FlowId -and $segFlowId -eq $FlowId) -or
                        ($FlowName -and $segFlowName -eq $FlowName)) {
                        $flowTouched = $true
                    }
                    $qName = [string](_ObjVal $seg @('queueName') '')
                    if ($qName) { $queues.Add($qName) | Out-Null }
                }
            }
        }

        if (-not $flowTouched) { continue }
        foreach ($q in $queues) {
            if (-not $queueCounts.ContainsKey($q)) { $queueCounts[$q] = 0 }
            $queueCounts[$q]++
        }
    }

    $rows = @($queueCounts.GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, Name | ForEach-Object {
        [pscustomobject]@{ QueueName = [string]$_.Key; ConversationCount = [int]$_.Value }
    })
    return $rows
}

function Import-WrapupDistributionReport {
    <#
    .SYNOPSIS
        Session 18 — imports wrapup distribution aggregate data into the local
        case store. Writes per-queue-per-code distribution and a per-hour
        rollup for contact reason heat-maps.
    .DESCRIPTION
        Reads JSONL outputs from:
          - analytics.query.conversation.aggregates.wrapup.distribution
          - routing.get.all.wrapup.codes

        Aggregate rows are grouped by (queueId, wrapUpCode) with `nConnected`.
        Hourly rollups are derived from each result's per-interval `data[]`
        buckets (aggregate `granularity` of PT1H or PT1D — if buckets are
        day-sized the hour is 0 for every row and the heat-map degenerates to
        a single column, which is still meaningful).

        pct_of_queue_total and pct_of_org_total are computed locally from the
        aggregated counts. Wrapup code names are resolved from the routing
        wrapup code reference dataset (and the per-case ref_wrapup_codes
        snapshot as a fallback).
    #>
    param(
        [Parameter(Mandatory)][string]    $CaseId,
        [Parameter(Mandatory)][hashtable] $FolderMap
    )
    _RequireDb

    $now   = [datetime]::UtcNow.ToString('o')
    $stats = @{ RecordCount = 0; HourRecordCount = 0; SkippedCount = 0 }

    function _ReadWrapupJsonl ([string]$RunFolder) {
        if ([string]::IsNullOrWhiteSpace($RunFolder) -or
            -not [System.IO.Directory]::Exists($RunFolder)) {
            return @()
        }
        $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
        if (-not [System.IO.Directory]::Exists($dataDir)) { return @() }
        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($f in [System.IO.Directory]::GetFiles($dataDir, '*.jsonl')) {
            foreach ($line in [System.IO.File]::ReadAllLines($f)) {
                $t = $line.Trim()
                if ($t) {
                    try { $records.Add(($t | ConvertFrom-Json)) } catch {
                        Write-Warning "Import-WrapupDistributionReport: skipping malformed JSONL line in $f — $($_.Exception.Message)"
                    }
                }
            }
        }
        return $records.ToArray()
    }

    $aggFolder   = if ($FolderMap.ContainsKey('WrapupAggFolder'))   { $FolderMap['WrapupAggFolder']   } else { $null }
    $codesFolder = if ($FolderMap.ContainsKey('WrapupCodesFolder')) { $FolderMap['WrapupCodesFolder'] } else { $null }

    $conn = _Open
    try {
        _NonQuery -Conn $conn -Sql 'DELETE FROM report_wrapup_distribution WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null
        _NonQuery -Conn $conn -Sql 'DELETE FROM report_wrapup_by_hour     WHERE case_id = @cid' -P @{ '@cid' = $CaseId } | Out-Null

        $queueMap = @{}
        foreach ($q in (_Query -Conn $conn -Sql 'SELECT queue_id, name FROM ref_queues WHERE case_id = @cid' -P @{ '@cid' = $CaseId })) {
            $qid = [string]$q.queue_id
            if ($qid) { $queueMap[$qid] = [string]$q.name }
        }

        $codeMap = @{}
        foreach ($c in (_Query -Conn $conn -Sql 'SELECT code_id, name FROM ref_wrapup_codes WHERE case_id = @cid' -P @{ '@cid' = $CaseId })) {
            $cid = [string]$c.code_id
            if ($cid) { $codeMap[$cid] = [string]$c.name }
        }
        foreach ($c in (_ReadWrapupJsonl $codesFolder)) {
            $cid = [string](_ObjVal $c @('id','codeId') '')
            if ($cid) { $codeMap[$cid] = [string](_ObjVal $c @('name') '') }
        }

        # Aggregations:
        #   byPair[queueId|codeId] → @{ QueueId; CodeId; N }
        #   byQueue[queueId]       → total n for the queue
        #   byCode[codeId]         → total n for the code across queues
        #   byHour[hour|codeId]    → @{ Hour; CodeId; N }
        $byPair  = @{}
        $byQueue = @{}
        $byCode  = @{}
        $byHour  = @{}
        $orgTotal = 0

        foreach ($r in (_ReadWrapupJsonl $aggFolder)) {
            if ($null -eq $r) { $stats.SkippedCount++; continue }
            $group = if ($r.PSObject.Properties['group']) { $r.group } else { $null }
            $queueId = [string](_ObjVal $group @('queueId') '')
            $codeId  = [string](_ObjVal $group @('wrapUpCode','wrapupCode') '')
            if (-not $codeId) { $stats.SkippedCount++; continue }

            $pairKey = "$queueId|$codeId"
            if (-not $byPair.ContainsKey($pairKey)) {
                $byPair[$pairKey] = @{ QueueId = $queueId; CodeId = $codeId; N = 0 }
            }
            if (-not $byQueue.ContainsKey($queueId)) { $byQueue[$queueId] = 0 }
            if (-not $byCode.ContainsKey($codeId))   { $byCode[$codeId]   = 0 }

            if (-not $r.PSObject.Properties['data']) { continue }
            foreach ($d in @($r.data)) {
                $intervalStr = [string](_ObjVal $d @('interval') '')
                $hour = 0
                if ($intervalStr) {
                    $slash = $intervalStr.IndexOf('/')
                    $startPart = if ($slash -gt 0) { $intervalStr.Substring(0, $slash) } else { $intervalStr }
                    try {
                        $dt = [datetime]::Parse($startPart, [System.Globalization.CultureInfo]::InvariantCulture,
                                                [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                        $hour = $dt.Hour
                    } catch { $hour = 0 }
                }

                if (-not $d.PSObject.Properties['metrics']) { continue }
                foreach ($m in @($d.metrics)) {
                    $metric = [string](_ObjVal $m @('metric') '')
                    if ($metric -ne 'nConnected') { continue }
                    $count = 0
                    if ($m.PSObject.Properties['stats'] -and $null -ne $m.stats -and
                        $m.stats.PSObject.Properties['count']) {
                        $count = [int]$m.stats.count
                    }
                    if ($count -le 0) { continue }

                    $byPair[$pairKey].N += $count
                    $byQueue[$queueId]  += $count
                    $byCode[$codeId]    += $count
                    $orgTotal           += $count

                    $hourKey = "$hour|$codeId"
                    if (-not $byHour.ContainsKey($hourKey)) {
                        $byHour[$hourKey] = @{ Hour = $hour; CodeId = $codeId; N = 0 }
                    }
                    $byHour[$hourKey].N += $count
                }
            }
        }

        foreach ($pair in $byPair.Values) {
            $qid   = [string]$pair.QueueId
            $cid   = [string]$pair.CodeId
            $n     = [int]$pair.N
            if ($n -le 0) { continue }

            $qName = if ($qid -and $queueMap.ContainsKey($qid)) { $queueMap[$qid] }
                     elseif ($qid) { "$qid (unresolved)" }
                     else { '(no queue)' }
            $cName = if ($cid -and $codeMap.ContainsKey($cid)) { $codeMap[$cid] }
                     elseif ($cid) { "$cid (unresolved)" }
                     else { '(no code)' }

            $queueTotal = if ($qid -and $byQueue.ContainsKey($qid)) { [int]$byQueue[$qid] } else { 0 }
            $pctQueue   = if ($queueTotal -gt 0) { [Math]::Round(($n / [double]$queueTotal) * 100.0, 1) } else { 0.0 }
            $pctOrg     = if ($orgTotal   -gt 0) { [Math]::Round(($n / [double]$orgTotal)   * 100.0, 1) } else { 0.0 }

            $rowKey = "$CaseId|wrapup|$qid|$cid"

            _NonQuery -Conn $conn -Sql @'
INSERT INTO report_wrapup_distribution(
    row_id, case_id, queue_id, queue_name, wrapup_code_id, wrapup_code_name,
    n_connected, pct_of_queue_total, pct_of_org_total, imported_utc)
VALUES(
    @rid, @cid, @qid, @qname, @wid, @wname,
    @n, @pq, @po, @ts)
ON CONFLICT(row_id) DO UPDATE SET
    queue_name=excluded.queue_name,
    wrapup_code_name=excluded.wrapup_code_name,
    n_connected=excluded.n_connected,
    pct_of_queue_total=excluded.pct_of_queue_total,
    pct_of_org_total=excluded.pct_of_org_total,
    imported_utc=excluded.imported_utc
'@ -P @{
                '@rid' = $rowKey; '@cid' = $CaseId
                '@qid' = $qid; '@qname' = $qName
                '@wid' = $cid; '@wname' = $cName
                '@n'   = $n; '@pq' = [double]$pctQueue; '@po' = [double]$pctOrg
                '@ts'  = $now
            } | Out-Null
            $stats.RecordCount++
        }

        foreach ($hr in $byHour.Values) {
            $hour = [int]$hr.Hour
            $cid  = [string]$hr.CodeId
            $n    = [int]$hr.N
            if ($n -le 0) { continue }

            $cName = if ($cid -and $codeMap.ContainsKey($cid)) { $codeMap[$cid] }
                     elseif ($cid) { "$cid (unresolved)" }
                     else { '(no code)' }
            $rowKey = "$CaseId|wrapuph|$hour|$cid"

            _NonQuery -Conn $conn -Sql @'
INSERT INTO report_wrapup_by_hour(
    row_id, case_id, hour_of_day, wrapup_code_id, wrapup_code_name,
    n_connected, imported_utc)
VALUES(
    @rid, @cid, @h, @wid, @wname, @n, @ts)
ON CONFLICT(row_id) DO UPDATE SET
    wrapup_code_name=excluded.wrapup_code_name,
    n_connected=excluded.n_connected,
    imported_utc=excluded.imported_utc
'@ -P @{
                '@rid' = $rowKey; '@cid' = $CaseId; '@h' = $hour
                '@wid' = $cid;    '@wname' = $cName
                '@n'   = $n;      '@ts' = $now
            } | Out-Null
            $stats.HourRecordCount++
        }
    } finally { $conn.Close(); $conn.Dispose() }

    return $stats
}

function Get-WrapupCodeRows {
    <#
    .SYNOPSIS
        Org-wide ranked list of wrapup codes (aggregated across queues).
    #>
    param([Parameter(Mandatory)][string] $CaseId)
    _RequireDb

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql @'
SELECT wrapup_code_id,
       MAX(wrapup_code_name) AS wrapup_code_name,
       SUM(n_connected)      AS n_connected,
       ROUND(SUM(pct_of_org_total), 1) AS pct_of_org_total,
       COUNT(DISTINCT queue_id) AS queue_count
FROM report_wrapup_distribution
WHERE case_id = @cid
GROUP BY wrapup_code_id
ORDER BY SUM(n_connected) DESC, MAX(wrapup_code_name) ASC
'@ -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows)
}

function Get-WrapupByQueueRows {
    <#
    .SYNOPSIS
        Per-queue breakdown for a single wrapup code (ordered by n_connected).
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [Parameter(Mandatory)][string] $WrapupCodeId
    )
    _RequireDb

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql @'
SELECT queue_id, queue_name, n_connected, pct_of_queue_total, pct_of_org_total
FROM report_wrapup_distribution
WHERE case_id = @cid AND wrapup_code_id = @wid
ORDER BY n_connected DESC, queue_name ASC
'@ -P @{ '@cid' = $CaseId; '@wid' = $WrapupCodeId }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows)
}

function Get-WrapupByHourRows {
    <#
    .SYNOPSIS
        Heat-map rows for the top-N wrapup codes × hours 0..23.
        Returns one row per (wrapup_code_id, hour_of_day) with n_connected.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [int] $TopCodes = 10
    )
    _RequireDb

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql @"
SELECT h.wrapup_code_id, h.wrapup_code_name, h.hour_of_day, h.n_connected
FROM report_wrapup_by_hour h
WHERE h.case_id = @cid
  AND h.wrapup_code_id IN (
        SELECT wrapup_code_id
        FROM report_wrapup_distribution
        WHERE case_id = @cid
        GROUP BY wrapup_code_id
        ORDER BY SUM(n_connected) DESC
        LIMIT @top
  )
ORDER BY h.wrapup_code_name ASC, h.hour_of_day ASC
"@ -P @{ '@cid' = $CaseId; '@top' = $TopCodes }
    } finally { $conn.Close(); $conn.Dispose() }
    return @($rows)
}

function Get-WrapupSummary {
    <#
    .SYNOPSIS
        Header KPIs for the Contact Reasons tab.
    #>
    param([Parameter(Mandatory)][string] $CaseId)
    _RequireDb

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql @'
SELECT
    COUNT(DISTINCT wrapup_code_id) AS total_codes,
    COUNT(DISTINCT queue_id)       AS total_queues,
    COALESCE(SUM(n_connected), 0)  AS total_connected
FROM report_wrapup_distribution
WHERE case_id = @cid
'@ -P @{ '@cid' = $CaseId }

        $topRows = _Query -Conn $conn -Sql @'
SELECT wrapup_code_id, MAX(wrapup_code_name) AS wrapup_code_name,
       SUM(n_connected) AS n_connected
FROM report_wrapup_distribution
WHERE case_id = @cid
GROUP BY wrapup_code_id
ORDER BY SUM(n_connected) DESC
LIMIT 1
'@ -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }

    $r = if ($rows.Count -gt 0) { $rows[0] } else { $null }
    $top = if ($topRows.Count -gt 0) { $topRows[0] } else { $null }
    return [pscustomobject]@{
        TotalCodes     = if ($null -ne $r)   { [int](_RowVal $r   'total_codes'     0) } else { 0 }
        TotalQueues    = if ($null -ne $r)   { [int](_RowVal $r   'total_queues'    0) } else { 0 }
        TotalConnected = if ($null -ne $r)   { [int](_RowVal $r   'total_connected' 0) } else { 0 }
        TopReasonName  = if ($null -ne $top) { [string](_RowVal $top 'wrapup_code_name' '') } else { '' }
        TopReasonCount = if ($null -ne $top) { [int]   (_RowVal $top 'n_connected'      0) } else { 0 }
    }
}

function Get-WrapupConcentrationInsights {
    <#
    .SYNOPSIS
        Top N wrapup codes by concentration index. Index is the ratio of the
        top queue's share of the code to the average queue's share (1 / queueCount).
        High ratio = code is heavily concentrated in one queue.
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [int] $Top = 5
    )
    _RequireDb

    $conn = _Open
    try {
        $rows = _Query -Conn $conn -Sql @'
SELECT wrapup_code_id, wrapup_code_name, queue_id, queue_name, n_connected
FROM report_wrapup_distribution
WHERE case_id = @cid
ORDER BY wrapup_code_id ASC, n_connected DESC
'@ -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }

    $byCode = @{}
    foreach ($r in $rows) {
        $cid = [string]$r.wrapup_code_id
        if (-not $byCode.ContainsKey($cid)) {
            $byCode[$cid] = [System.Collections.Generic.List[object]]::new()
        }
        $byCode[$cid].Add($r)
    }

    $out = New-Object System.Collections.Generic.List[object]
    foreach ($cid in $byCode.Keys) {
        $list = $byCode[$cid]
        if ($list.Count -eq 0) { continue }
        $total = 0
        foreach ($r in $list) { $total += [int]$r.n_connected }
        if ($total -le 0) { continue }
        $top = $list[0]
        $topN = [int]$top.n_connected
        $topShare = $topN / [double]$total
        $avgShare = 1.0 / [double]$list.Count
        $index = if ($avgShare -gt 0) { $topShare / $avgShare } else { 0.0 }
        $out.Add([pscustomobject]@{
            WrapupCodeId       = $cid
            WrapupCodeName     = [string]$top.wrapup_code_name
            NConnectedTotal    = $total
            TopQueueName       = [string]$top.queue_name
            TopQueueN          = $topN
            QueueCount         = $list.Count
            ConcentrationIndex = [Math]::Round($index, 2)
        })
    }

    $sorted = @($out | Where-Object { $_.QueueCount -gt 1 -and $_.NConnectedTotal -ge 5 } | Sort-Object -Property ConcentrationIndex, NConnectedTotal -Descending)
    if ($sorted.Count -gt $Top) {
        return @($sorted[0..($Top - 1)])
    }
    return $sorted
}

function Get-WrapupHandleTimeCrossRef {
    <#
    .SYNOPSIS
        For the top-N wrapup codes, compute the median handle time and median
        segment count of conversations in the case store that carry that code.
        Reads wrapup code ids from participants_json (participant.wrapup.code).
    .OUTPUTS
        WrapupCodeId, WrapupCodeName, ConversationCount, MedianHandleSec, MedianSegmentCount
    #>
    param(
        [Parameter(Mandatory)][string] $CaseId,
        [int] $TopCodes = 10
    )
    _RequireDb

    $conn = _Open
    try {
        $topRows = _Query -Conn $conn -Sql @'
SELECT wrapup_code_id, MAX(wrapup_code_name) AS wrapup_code_name
FROM report_wrapup_distribution
WHERE case_id = @cid
GROUP BY wrapup_code_id
ORDER BY SUM(n_connected) DESC
LIMIT @top
'@ -P @{ '@cid' = $CaseId; '@top' = $TopCodes }

        $topIds    = @{}
        $nameByCid = @{}
        foreach ($r in $topRows) {
            $cid = [string]$r.wrapup_code_id
            if (-not $cid) { continue }
            $topIds[$cid] = $true
            $nameByCid[$cid] = [string]$r.wrapup_code_name
        }
        if ($topIds.Count -eq 0) { return @() }

        $codeMap = @{}
        foreach ($c in (_Query -Conn $conn -Sql 'SELECT code_id, name FROM ref_wrapup_codes WHERE case_id = @cid' -P @{ '@cid' = $CaseId })) {
            $cid = [string]$c.code_id
            if ($cid) { $codeMap[$cid] = [string]$c.name }
        }

        $convRows = _Query -Conn $conn -Sql @'
SELECT duration_sec, segment_count, participants_json
FROM conversations
WHERE case_id = @cid
'@ -P @{ '@cid' = $CaseId }
    } finally { $conn.Close(); $conn.Dispose() }

    $buckets = @{}
    foreach ($cid in $topIds.Keys) {
        $buckets[$cid] = @{ Durations = [System.Collections.Generic.List[double]]::new(); Segments = [System.Collections.Generic.List[int]]::new() }
    }

    foreach ($cr in $convRows) {
        $partJson = _RowVal $cr 'participants_json' $null
        if ($null -eq $partJson -or [string]::IsNullOrWhiteSpace([string]$partJson)) { continue }
        try { $participants = @($partJson | ConvertFrom-Json) } catch { continue }

        $codesThisConv = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($p in $participants) {
            $cid = ''
            if ($p.PSObject.Properties['wrapup'] -and $null -ne $p.wrapup) {
                $cid = [string](_ObjVal $p.wrapup @('code','codeId') '')
                if (-not $cid) { $cid = [string](_ObjVal $p.wrapup @('name') '') }
            }
            if (-not $cid -and $p.PSObject.Properties['sessions']) {
                foreach ($s in @($p.sessions)) {
                    if (-not $s.PSObject.Properties['segments']) { continue }
                    foreach ($seg in @($s.segments)) {
                        if ($seg.PSObject.Properties['wrapUpCode']) {
                            $cid = [string]$seg.wrapUpCode
                            if ($cid) { break }
                        }
                    }
                    if ($cid) { break }
                }
            }
            if ($cid -and $topIds.ContainsKey($cid)) {
                $codesThisConv.Add($cid) | Out-Null
            }
        }

        if ($codesThisConv.Count -eq 0) { continue }
        $dur  = [double](_RowVal $cr 'duration_sec'  0)
        $segs = [int]   (_RowVal $cr 'segment_count' 0)
        foreach ($cid in $codesThisConv) {
            $buckets[$cid].Durations.Add($dur)  | Out-Null
            $buckets[$cid].Segments.Add($segs)  | Out-Null
        }
    }

    $out = New-Object System.Collections.Generic.List[object]
    foreach ($cid in $topIds.Keys) {
        $b = $buckets[$cid]
        $count = $b.Durations.Count
        $medDur = 0.0
        $medSeg = 0.0
        if ($count -gt 0) {
            $sortedDur = @($b.Durations | Sort-Object)
            $sortedSeg = @($b.Segments  | Sort-Object)
            $mid = [int]([Math]::Floor($count / 2))
            if ($count % 2 -eq 1) {
                $medDur = [double]$sortedDur[$mid]
                $medSeg = [double]$sortedSeg[$mid]
            } else {
                $medDur = ([double]$sortedDur[$mid - 1] + [double]$sortedDur[$mid]) / 2.0
                $medSeg = ([double]$sortedSeg[$mid - 1] + [double]$sortedSeg[$mid]) / 2.0
            }
        }

        $codeName = if ($nameByCid.ContainsKey($cid)) { $nameByCid[$cid] }
                    elseif ($codeMap.ContainsKey($cid)) { $codeMap[$cid] }
                    else { "$cid (unresolved)" }

        $out.Add([pscustomobject]@{
            WrapupCodeId       = $cid
            WrapupCodeName     = $codeName
            ConversationCount  = $count
            MedianHandleSec    = [Math]::Round($medDur, 1)
            MedianSegmentCount = [Math]::Round($medSeg, 1)
        })
    }

    return @($out | Sort-Object -Property ConversationCount -Descending)
}

Export-ModuleMember -Function `
    Initialize-Database, Test-DatabaseInitialized, New-DefaultCaseIfEmpty, `
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
    Import-Conversations, Get-ConversationCount, Get-ConversationsPage, Get-ConversationPopulationRows, `
    Get-ConversationPopulationSummary, Get-ConversationFacetCounts, Get-RepresentativeConversations, `
    Get-AnomalyRiskCohorts, Get-ConversationById, Get-ConversationVersions, `
    Import-ReferenceDataToCase, Get-ResolvedName, `
    Import-QueuePerformanceReport, Get-QueuePerfRows, Get-QueuePerfSummary, `
    Import-AgentPerformanceReport, Get-AgentPerfRows, Get-AgentPerfSummary, `
    Import-TransferReport, Get-TransferFlowRows, Get-TransferChainRows, Get-TransferSummary, `
    Import-FlowContainmentReport, Get-FlowPerfRows, Get-FlowMilestoneRows, `
    Get-FlowContainmentSummary, Get-FlowQueueRouteRows, `
    Import-WrapupDistributionReport, Get-WrapupCodeRows, Get-WrapupByQueueRows, `
    Get-WrapupByHourRows, Get-WrapupSummary, Get-WrapupConcentrationInsights, `
    Get-WrapupHandleTimeCrossRef
