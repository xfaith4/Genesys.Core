#Requires -Version 5.1
Set-StrictMode -Version Latest

# ── Index module ──────────────────────────────────────────────────────────────
# Builds and caches index.jsonl for each run folder.
# Byte offsets are computed robustly (UTF-8 BOM + LF/CRLF).
# Get-IndexedPage uses indexed byte offsets for O(pageSize)-like retrieval
# without rescanning whole data files.
# ─────────────────────────────────────────────────────────────────────────────

$script:IndexCache = @{}   # [string]RunFolder -> [object[]] index entries

# ── Path helpers ──────────────────────────────────────────────────────────────

function _GetRelativePath {
    <#
    .SYNOPSIS
        PS 5.1-compatible relative-path helper.
        Uses [IO.Path]::GetRelativePath when available; otherwise uses string comparison.
    #>
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

# ── Low-level buffered line reader with byte-offset tracking ──────────────────

function _ReadFileLines {
    <#
    .SYNOPSIS
        Reads all non-empty lines from $FilePath, returning objects with:
            Line   : string
            Offset : long  (byte offset of first byte of this line in the file)
        Handles UTF-8 BOM and both LF / CRLF newlines.
        Uses a 64 KB read buffer to avoid per-byte overhead on large files.
    #>
    param([Parameter(Mandatory)][string]$FilePath)

    $results    = New-Object System.Collections.Generic.List[pscustomobject]
    $fs         = [System.IO.FileStream]::new(
        $FilePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    try {
        $bufSize    = 65536
        $buf        = New-Object byte[] $bufSize
        $lineBuffer = New-Object System.Collections.Generic.List[byte]

        $chunkStart = 0L    # file offset of the first byte in the current read buffer
        $lineStart  = 0L    # file offset of the first byte of the current line
        $firstChunk = $true

        $bytesRead = 0
        while (($bytesRead = $fs.Read($buf, 0, $bufSize)) -gt 0) {
            $startIdx = 0

            # Skip UTF-8 BOM (EF BB BF) at the very beginning of the file
            if ($firstChunk -and $bytesRead -ge 3 `
                    -and $buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF) {
                $startIdx   = 3
                $lineStart   = 3
            }
            $firstChunk = $false

            for ($i = $startIdx; $i -lt $bytesRead; $i++) {
                $b = $buf[$i]
                if ($b -eq 10) {
                    # LF – end of line
                    # Strip trailing CR if CRLF
                    if ($lineBuffer.Count -gt 0 -and $lineBuffer[$lineBuffer.Count - 1] -eq 13) {
                        $lineBuffer.RemoveAt($lineBuffer.Count - 1)
                    }
                    if ($lineBuffer.Count -gt 0) {
                        $lineBytes = $lineBuffer.ToArray()
                        $results.Add([pscustomobject]@{
                            Line   = [System.Text.Encoding]::UTF8.GetString($lineBytes)
                            Offset = $lineStart
                        })
                    }
                    $lineBuffer.Clear()
                    $lineStart = $chunkStart + $i + 1
                } else {
                    $lineBuffer.Add($b)
                }
            }
            $chunkStart += $bytesRead
        }

        # Last line with no trailing newline
        if ($lineBuffer.Count -gt 0) {
            if ($lineBuffer[$lineBuffer.Count - 1] -eq 13) {
                $lineBuffer.RemoveAt($lineBuffer.Count - 1)
            }
            if ($lineBuffer.Count -gt 0) {
                $lineBytes = $lineBuffer.ToArray()
                $results.Add([pscustomobject]@{
                    Line   = [System.Text.Encoding]::UTF8.GetString($lineBytes)
                    Offset = $lineStart
                })
            }
        }
    } finally {
        $fs.Dispose()
    }
    return $results.ToArray()
}

# ── Metadata extraction from a Genesys conversation detail record ─────────────

function _ExtractIndexMetadata {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][long]$ByteOffset
    )

    $direction    = ''
    $mediaType    = ''
    $queue        = ''
    $disconnect   = ''
    $hasMos       = $false
    $hasHold      = $false
    $segmentCount = 0
    $partCount    = 0
    $durationSec  = 0
    $queueIds     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $userIds      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($Record.PSObject.Properties['participants']) {
        $partCount = @($Record.participants).Count
        foreach ($p in @($Record.participants)) {
            $isCustomer = ($p.PSObject.Properties['purpose'] -and $p.purpose -eq 'customer')
            if ($p.PSObject.Properties['userId'] -and $p.userId) {
                $userIds.Add([string]$p.userId) | Out-Null
            }
            if (-not $p.PSObject.Properties['sessions']) { continue }
            foreach ($s in @($p.sessions)) {
                if (-not $mediaType -and $s.PSObject.Properties['mediaType']) {
                    $mediaType = $s.mediaType
                }
                if ($isCustomer -and -not $direction -and $s.PSObject.Properties['direction']) {
                    $direction = $s.direction
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
                    if ($seg.PSObject.Properties['segmentType']) {
                        if ($seg.segmentType -eq 'hold') { $hasHold = $true }
                    }
                    if (-not $disconnect -and $seg.PSObject.Properties['disconnectType']) {
                        $disconnect = $seg.disconnectType
                    }
                    if (-not $queue -and $seg.PSObject.Properties['queueName']) {
                        $queue = $seg.queueName
                    }
                    if ($seg.PSObject.Properties['queueId'] -and $seg.queueId) {
                        $queueIds.Add([string]$seg.queueId) | Out-Null
                    }
                }
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

    $convId    = if ($Record.PSObject.Properties['conversationId'])    { $Record.conversationId }    else { '' }
    $convStart = if ($Record.PSObject.Properties['conversationStart']) { $Record.conversationStart } else { '' }
    $divIds    = @(if ($Record.PSObject.Properties['divisionIds'] -and $null -ne $Record.divisionIds) {
        @($Record.divisionIds) | Where-Object { $_ }
    })

    return [pscustomobject]@{
        id               = $convId
        file             = $RelativePath
        offset           = $ByteOffset
        direction        = $direction
        mediaType        = $mediaType
        queue            = $queue
        disconnect       = $disconnect
        hasMos           = $hasMos
        hasHold          = $hasHold
        segmentCount     = $segmentCount
        participantCount = $partCount
        durationSec      = $durationSec
        conversationStart = $convStart
        divisionIds      = $divIds
        queueIds         = @($queueIds)
        userIds          = @($userIds)
    }
}

# ── Public functions ──────────────────────────────────────────────────────────

function Build-RunIndex {
    <#
    .SYNOPSIS
        Scans all data\*.jsonl files in the run folder, writes index.jsonl, and caches results.
    #>
    param([Parameter(Mandatory)][string]$RunFolder)

    $dataDir   = [System.IO.Path]::Combine($RunFolder, 'data')
    $indexPath = [System.IO.Path]::Combine($RunFolder, 'index.jsonl')

    if (-not [System.IO.Directory]::Exists($dataDir)) {
        Write-Warning "Build-RunIndex: no 'data' directory found in $RunFolder"
        $script:IndexCache[$RunFolder] = @()
        return @()
    }

    $dataFiles = [System.IO.Directory]::GetFiles($dataDir, '*.jsonl') | Sort-Object
    $entries   = New-Object System.Collections.Generic.List[object]

    $indexFs = [System.IO.FileStream]::new(
        $indexPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    $indexSw = [System.IO.StreamWriter]::new(
        $indexFs,
        (New-Object System.Text.UTF8Encoding($false)))   # UTF-8 without BOM
    try {
        foreach ($dataFile in $dataFiles) {
            $relPath  = _GetRelativePath -BasePath $RunFolder -FullPath $dataFile
            $rawLines = _ReadFileLines -FilePath $dataFile

            foreach ($lv in $rawLines) {
                if ([string]::IsNullOrWhiteSpace($lv.Line)) { continue }
                try {
                    $record = $lv.Line | ConvertFrom-Json
                    $entry  = _ExtractIndexMetadata -Record $record -RelativePath $relPath -ByteOffset $lv.Offset
                    $entries.Add($entry)
                    $indexSw.WriteLine(($entry | ConvertTo-Json -Compress))
                } catch { <# skip malformed records #> }
            }
        }
    } finally {
        $indexSw.Dispose()
        $indexFs.Dispose()
    }

    $script:IndexCache[$RunFolder] = $entries.ToArray()
    return $script:IndexCache[$RunFolder]
}

function Load-RunIndex {
    <#
    .SYNOPSIS
        Loads an existing index.jsonl from a run folder into cache.
        Falls back to Build-RunIndex if the index file is absent.
    #>
    param([Parameter(Mandatory)][string]$RunFolder)

    if ($script:IndexCache.ContainsKey($RunFolder) -and
        $script:IndexCache[$RunFolder].Count -gt 0) {
        return $script:IndexCache[$RunFolder]
    }

    $indexPath = [System.IO.Path]::Combine($RunFolder, 'index.jsonl')
    if (-not [System.IO.File]::Exists($indexPath)) {
        return Build-RunIndex -RunFolder $RunFolder
    }

    $entries  = New-Object System.Collections.Generic.List[object]
    $rawLines = _ReadFileLines -FilePath $indexPath
    foreach ($lv in $rawLines) {
        if ([string]::IsNullOrWhiteSpace($lv.Line)) { continue }
        try {
            $entries.Add(($lv.Line | ConvertFrom-Json))
        } catch { }
    }

    $script:IndexCache[$RunFolder] = $entries.ToArray()
    return $script:IndexCache[$RunFolder]
}

function Clear-IndexCache {
    <#
    .SYNOPSIS
        Clears the in-memory index cache (optionally for a specific run folder only).
    #>
    param([string]$RunFolder = '')
    if ($RunFolder) {
        if ($script:IndexCache.ContainsKey($RunFolder)) {
            $script:IndexCache.Remove($RunFolder)
        }
    } else {
        $script:IndexCache = @{}
    }
}

function Get-RunTotalCount {
    <#
    .SYNOPSIS
        Returns the total number of indexed records for a run folder.
    #>
    param([Parameter(Mandatory)][string]$RunFolder)
    $idx = Load-RunIndex -RunFolder $RunFolder
    return $idx.Count
}

function Get-FilteredIndex {
    <#
    .SYNOPSIS
        Applies optional filter criteria to the in-memory index and returns matching entries.
    .PARAMETER Direction
        Filter by direction ('inbound'|'outbound'|'' for all).
    .PARAMETER MediaType
        Filter by mediaType ('voice'|'chat'|'email'|'' for all).
    .PARAMETER Queue
        Filter by queue name (substring, case-insensitive; '' for all).
    .PARAMETER SearchText
        Substring match against conversationId or queue (case-insensitive; '' for all).
    .PARAMETER ConversationId
        Exact match against conversationId ('' for all).
    .PARAMETER UserId
        Exact match against any entry in the userIds array ('' for all).
    .PARAMETER DivisionId
        Exact match against any entry in the divisionIds array ('' for all).
    #>
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [string]$Direction      = '',
        [string]$MediaType      = '',
        [string]$Queue          = '',
        [string]$SearchText     = '',
        [string]$ConversationId = '',
        [string]$UserId         = '',
        [string]$DivisionId     = ''
    )
    $idx = Load-RunIndex -RunFolder $RunFolder

    $filtered = $idx | Where-Object {
        $ok = $true
        if ($Direction      -and $_.direction -ne $Direction)                         { $ok = $false }
        if ($MediaType      -and $_.mediaType -ne $MediaType)                         { $ok = $false }
        if ($Queue          -and $_.queue -notlike "*$Queue*")                        { $ok = $false }
        if ($ConversationId -and $_.id -ne $ConversationId)                           { $ok = $false }
        if ($SearchText) {
            $lo = $SearchText.ToLowerInvariant()
            if ($_.id    -notlike "*$lo*" -and
                $_.queue -notlike "*$lo*") { $ok = $false }
        }
        if ($UserId     -and -not (@($_.userIds)     -contains $UserId))    { $ok = $false }
        if ($DivisionId -and -not (@($_.divisionIds) -contains $DivisionId)) { $ok = $false }
        $ok
    }
    return @($filtered)
}

function Get-IndexedPage {
    <#
    .SYNOPSIS
        Retrieves the full conversation records for a page of index entries using
        indexed byte offsets (O(pageSize) reads).
    #>
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][object[]]$IndexEntries
    )

    if ($IndexEntries.Count -eq 0) { return @() }

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $IndexEntries) {
        $fullPath = [System.IO.Path]::Combine($RunFolder, $entry.file)
        if (-not [System.IO.File]::Exists($fullPath)) { continue }

        $fs = [System.IO.FileStream]::new(
            $fullPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read)
        $lineBytes = New-Object System.Collections.Generic.List[byte]
        try {
            $fs.Seek([long]$entry.offset, [System.IO.SeekOrigin]::Begin) | Out-Null

            while ($true) {
                $nextByte = $fs.ReadByte()
                if ($nextByte -lt 0 -or $nextByte -eq 10) { break }
                $lineBytes.Add([byte]$nextByte)
            }

            if ($lineBytes.Count -gt 0 -and $lineBytes[$lineBytes.Count - 1] -eq 13) {
                $lineBytes.RemoveAt($lineBytes.Count - 1)
            }

            if ($lineBytes.Count -gt 0) {
                $line = [System.Text.Encoding]::UTF8.GetString($lineBytes.ToArray())
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    try { $results.Add(($line | ConvertFrom-Json)) } catch { }
                }
            }
        } finally {
            $fs.Dispose()
        }
    }
    return $results.ToArray()
}

function Get-ConversationRecord {
    <#
    .SYNOPSIS
        Retrieves a single full conversation record by conversationId from the index.
    #>
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][string]$ConversationId
    )
    $idx   = Load-RunIndex -RunFolder $RunFolder
    $entry = $idx | Where-Object { $_.id -eq $ConversationId } | Select-Object -First 1
    if ($null -eq $entry) { return $null }
    $page = Get-IndexedPage -RunFolder $RunFolder -IndexEntries @($entry)
    $records = @($page)
    if ($records.Count -eq 0) { return $null }
    return $records[0]
}

Export-ModuleMember -Function `
    Build-RunIndex, Load-RunIndex, Clear-IndexCache, `
    Get-IndexedPage, Get-ConversationRecord, Get-RunTotalCount, Get-FilteredIndex
