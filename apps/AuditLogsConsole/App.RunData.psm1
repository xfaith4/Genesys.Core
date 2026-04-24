#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:AuditIndexCache = @{}

function _GetRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$FullPath
    )

    $hasRelativePath = [System.IO.Path].GetMethods() | Where-Object { $_.Name -eq 'GetRelativePath' -and $_.IsStatic } | Select-Object -First 1
    if ($null -ne $hasRelativePath) {
        return [System.IO.Path]::GetRelativePath($BasePath, $FullPath)
    }

    $normalizedBase = $BasePath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($FullPath.StartsWith($normalizedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($normalizedBase.Length)
    }

    return $FullPath
}

function _ReadFileLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath
    )

    $results = New-Object System.Collections.Generic.List[object]
    $fs = [System.IO.FileStream]::new(
        $FilePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)

    try {
        $buffer = New-Object byte[] 65536
        $lineBytes = New-Object System.Collections.Generic.List[byte]
        $chunkStart = 0L
        $lineStart  = 0L
        $firstChunk = $true

        $bytesRead = 0
        while (($bytesRead = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $startIndex = 0
            if ($firstChunk -and $bytesRead -ge 3 -and $buffer[0] -eq 0xEF -and $buffer[1] -eq 0xBB -and $buffer[2] -eq 0xBF) {
                $startIndex = 3
                $chunkStart += 3
                $lineStart = 3
            }

            $firstChunk = $false
            for ($i = $startIndex; $i -lt $bytesRead; $i++) {
                $byte = $buffer[$i]
                if ($byte -eq 10) {
                    if ($lineBytes.Count -gt 0 -and $lineBytes[$lineBytes.Count - 1] -eq 13) {
                        $lineBytes.RemoveAt($lineBytes.Count - 1)
                    }

                    if ($lineBytes.Count -gt 0) {
                        $results.Add([pscustomobject]@{
                            Line   = [System.Text.Encoding]::UTF8.GetString($lineBytes.ToArray())
                            Offset = $lineStart
                        })
                    }

                    $lineBytes.Clear()
                    $lineStart = $chunkStart + $i + 1
                }
                else {
                    $lineBytes.Add($byte)
                }
            }

            $chunkStart += $bytesRead
        }

        if ($lineBytes.Count -gt 0) {
            if ($lineBytes[$lineBytes.Count - 1] -eq 13) {
                $lineBytes.RemoveAt($lineBytes.Count - 1)
            }

            if ($lineBytes.Count -gt 0) {
                $results.Add([pscustomobject]@{
                    Line   = [System.Text.Encoding]::UTF8.GetString($lineBytes.ToArray())
                    Offset = $lineStart
                })
            }
        }
    }
    finally {
        $fs.Dispose()
    }

    return $results.ToArray()
}

function _Get-AuditDataFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
    if (-not [System.IO.Directory]::Exists($dataDir)) {
        return @()
    }

    return [System.IO.Directory]::GetFiles($dataDir, '*.jsonl') | Sort-Object
}

function _Get-NestedValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string[]]$Paths
    )

    foreach ($path in $Paths) {
        $current = $Object
        $resolved = $true
        foreach ($segment in ($path -split '\.')) {
            if ($null -eq $current -or -not $current.PSObject.Properties[$segment]) {
                $resolved = $false
                break
            }

            $current = $current.$segment
        }

        if ($resolved -and $null -ne $current -and -not [string]::IsNullOrWhiteSpace([string]$current)) {
            return $current
        }
    }

    return $null
}

function _Join-SearchParts {
    [CmdletBinding()]
    param(
        [object[]]$Values
    )

    return (($Values | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').ToLowerInvariant()
}

function ConvertTo-AuditDisplayRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$IndexEntry
    )

    return [pscustomobject]@{
        RecordId       = [string]$IndexEntry.id
        TimestampUtc   = [string]$IndexEntry.timestampUtc
        Service        = [string]$IndexEntry.service
        Action         = [string]$IndexEntry.action
        Actor          = [string]$IndexEntry.actor
        EntityType     = [string]$IndexEntry.entityType
        EntityName     = [string]$IndexEntry.entityName
        Status         = [string]$IndexEntry.status
        CorrelationId  = [string]$IndexEntry.correlationId
        Summary        = [string]$IndexEntry.summary
    }
}

function _ConvertTo-AuditIndexEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][long]$ByteOffset
    )

    $id = _Get-NestedValue -Object $Record -Paths @('id', 'recordId', 'transactionId')
    if ([string]::IsNullOrWhiteSpace([string]$id)) {
        $id = [guid]::NewGuid().ToString('N')
    }

    $timestamp = _Get-NestedValue -Object $Record -Paths @('timestamp', 'timestampUtc', 'eventTime', 'eventDate')
    $service = _Get-NestedValue -Object $Record -Paths @('serviceName', 'service', 'category')
    $action = _Get-NestedValue -Object $Record -Paths @('action', 'operation', 'eventType')
    $actor = _Get-NestedValue -Object $Record -Paths @('userName', 'userEmail', 'userId', 'actor.name', 'actor.email', 'actor.id')
    $entityType = _Get-NestedValue -Object $Record -Paths @('context.type', 'entity.type', 'entityType')
    $entityId = _Get-NestedValue -Object $Record -Paths @('context.entityId', 'entity.id', 'entityId')
    $entityName = _Get-NestedValue -Object $Record -Paths @('context.entityName', 'entity.name', 'entityName')
    $status = _Get-NestedValue -Object $Record -Paths @('status', 'result', 'outcome')
    $correlation = _Get-NestedValue -Object $Record -Paths @('correlationId', 'traceId', 'correlationContext.correlationId')
    $summary = _Get-NestedValue -Object $Record -Paths @('message', 'summary', 'description')
    $actorEmail = _Get-NestedValue -Object $Record -Paths @('userEmail', 'actor.email')
    $actorId = _Get-NestedValue -Object $Record -Paths @('userId', 'actor.id')

    $sortTicks = 0L
    if (-not [string]::IsNullOrWhiteSpace([string]$timestamp)) {
        try {
            $sortTicks = ([datetime]$timestamp).ToUniversalTime().Ticks
        }
        catch {
            $sortTicks = 0L
        }
    }

    return [pscustomobject]@{
        id            = [string]$id
        file          = $RelativePath
        offset        = $ByteOffset
        timestampUtc  = [string]$timestamp
        service       = [string]$service
        action        = [string]$action
        actor         = [string]$actor
        actorEmail    = [string]$actorEmail
        actorId       = [string]$actorId
        entityType    = [string]$entityType
        entityId      = [string]$entityId
        entityName    = [string]$entityName
        status        = [string]$status
        correlationId = [string]$correlation
        summary       = [string]$summary
        searchText    = _Join-SearchParts -Values @($id, $timestamp, $service, $action, $actor, $actorEmail, $actorId, $entityType, $entityId, $entityName, $status, $correlation, $summary)
        sortTicks     = $sortTicks
    }
}

function Build-AuditIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    $indexPath = [System.IO.Path]::Combine($RunFolder, 'audit.index.jsonl')
    $entries = New-Object System.Collections.Generic.List[object]

    $indexFs = [System.IO.FileStream]::new(
        $indexPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    $indexSw = [System.IO.StreamWriter]::new($indexFs, (New-Object System.Text.UTF8Encoding($false)))

    try {
        foreach ($dataFile in @(_Get-AuditDataFiles -RunFolder $RunFolder)) {
            $relativePath = _GetRelativePath -BasePath $RunFolder -FullPath $dataFile
            foreach ($lineInfo in @(_ReadFileLines -FilePath $dataFile)) {
                if ([string]::IsNullOrWhiteSpace($lineInfo.Line)) {
                    continue
                }

                try {
                    $record = $lineInfo.Line | ConvertFrom-Json -Depth 100
                    $entry = _ConvertTo-AuditIndexEntry -Record $record -RelativePath $relativePath -ByteOffset $lineInfo.Offset
                    $entries.Add($entry)
                    $indexSw.WriteLine(($entry | ConvertTo-Json -Compress))
                }
                catch {
                }
            }
        }
    }
    finally {
        $indexSw.Dispose()
        $indexFs.Dispose()
    }

    $sorted = @($entries.ToArray() | Sort-Object -Property @{ Expression = { $_.sortTicks }; Descending = $true }, @{ Expression = { $_.id }; Descending = $false })
    $script:AuditIndexCache[$RunFolder] = $sorted
    return $sorted
}

function Load-AuditIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    if ($script:AuditIndexCache.ContainsKey($RunFolder)) {
        return $script:AuditIndexCache[$RunFolder]
    }

    $indexPath = [System.IO.Path]::Combine($RunFolder, 'audit.index.jsonl')
    if (-not [System.IO.File]::Exists($indexPath)) {
        return Build-AuditIndex -RunFolder $RunFolder
    }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($lineInfo in @(_ReadFileLines -FilePath $indexPath)) {
        if ([string]::IsNullOrWhiteSpace($lineInfo.Line)) {
            continue
        }

        try {
            $entries.Add(($lineInfo.Line | ConvertFrom-Json))
        }
        catch {
        }
    }

    if ($entries.Count -eq 0 -and @(_Get-AuditDataFiles -RunFolder $RunFolder).Count -gt 0) {
        return Build-AuditIndex -RunFolder $RunFolder
    }

    $script:AuditIndexCache[$RunFolder] = @($entries.ToArray() | Sort-Object -Property @{ Expression = { $_.sortTicks }; Descending = $true }, @{ Expression = { $_.id }; Descending = $false })
    return $script:AuditIndexCache[$RunFolder]
}

function Clear-AuditIndexCache {
    [CmdletBinding()]
    param(
        [string]$RunFolder = ''
    )

    if ([string]::IsNullOrWhiteSpace($RunFolder)) {
        $script:AuditIndexCache = @{}
        return
    }

    if ($script:AuditIndexCache.ContainsKey($RunFolder)) {
        $script:AuditIndexCache.Remove($RunFolder)
    }
}

function _Matches-Filter {
    [CmdletBinding()]
    param(
        [string]$Needle,
        [string]$Haystack,
        [switch]$Exact
    )

    if ([string]::IsNullOrWhiteSpace($Needle)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($Haystack)) {
        return $false
    }

    if ($Exact) {
        return $Haystack.Equals($Needle, [System.StringComparison]::OrdinalIgnoreCase)
    }

    return ($Haystack.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Search-AuditRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [string]$Service = '',
        [string]$Action = '',
        [string]$Actor = '',
        [string]$Entity = '',
        [string]$Keyword = '',
        [int]$Limit = 0
    )

    $index = Load-AuditIndex -RunFolder $RunFolder
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $index) {
        if (-not (_Matches-Filter -Needle $Service -Haystack $entry.service)) {
            continue
        }

        if (-not (_Matches-Filter -Needle $Action -Haystack $entry.action)) {
            continue
        }

        $actorText = "$($entry.actor) $($entry.actorEmail) $($entry.actorId)"
        if (-not (_Matches-Filter -Needle $Actor -Haystack $actorText)) {
            continue
        }

        $entityText = "$($entry.entityType) $($entry.entityId) $($entry.entityName)"
        if (-not (_Matches-Filter -Needle $Entity -Haystack $entityText)) {
            continue
        }

        if (-not (_Matches-Filter -Needle $Keyword -Haystack $entry.searchText)) {
            continue
        }

        $results.Add($entry)
        if ($Limit -gt 0 -and $results.Count -ge $Limit) {
            break
        }
    }

    return $results.ToArray()
}

function Get-AuditRecordsByIndexEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][object[]]$IndexEntries
    )

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($fileGroup in ($IndexEntries | Group-Object -Property file)) {
        $fullPath = [System.IO.Path]::Combine($RunFolder, $fileGroup.Name)
        if (-not [System.IO.File]::Exists($fullPath)) {
            continue
        }

        $fs = [System.IO.FileStream]::new(
            $fullPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite)
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        try {
            foreach ($entry in $fileGroup.Group) {
                $fs.Seek([long]$entry.offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                $sr.DiscardBufferedData()
                $line = $sr.ReadLine()
                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }

                try {
                    $records.Add(($line | ConvertFrom-Json -Depth 100))
                }
                catch {
                }
            }
        }
        finally {
            $sr.Dispose()
            $fs.Dispose()
        }
    }

    return $records.ToArray()
}

function Get-AuditResultPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][object[]]$IndexEntries,
        [int]$PageNumber = 1,
        [int]$PageSize = 100
    )

    $totalCount = @($IndexEntries).Count
    if ($totalCount -eq 0) {
        return [pscustomobject]@{
            TotalCount  = 0
            TotalPages  = 0
            PageNumber  = 0
            PageSize    = $PageSize
            IndexEntries = @()
            Records     = @()
            Rows        = @()
        }
    }

    $totalPages = [int][math]::Ceiling($totalCount / $PageSize)
    if ($PageNumber -lt 1) {
        $PageNumber = 1
    }
    if ($PageNumber -gt $totalPages) {
        $PageNumber = $totalPages
    }

    $startIndex = ($PageNumber - 1) * $PageSize
    $endIndex = [math]::Min($startIndex + $PageSize - 1, $totalCount - 1)
    $pageEntries = @($IndexEntries[$startIndex..$endIndex])
    $records = Get-AuditRecordsByIndexEntries -RunFolder $RunFolder -IndexEntries $pageEntries
    $rows = @($pageEntries | ForEach-Object { ConvertTo-AuditDisplayRow -IndexEntry $_ })

    return [pscustomobject]@{
        TotalCount   = $totalCount
        TotalPages   = $totalPages
        PageNumber   = $PageNumber
        PageSize     = $PageSize
        IndexEntries = $pageEntries
        Records      = $records
        Rows         = $rows
    }
}

function Get-AuditRecordById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][string]$RecordId
    )

    $entry = Load-AuditIndex -RunFolder $RunFolder | Where-Object { $_.id -eq $RecordId } | Select-Object -First 1
    if ($null -eq $entry) {
        return $null
    }

    $records = Get-AuditRecordsByIndexEntries -RunFolder $RunFolder -IndexEntries @($entry)
    if (@($records).Count -eq 0) {
        return $null
    }

    return $records[0]
}

function Get-AuditRunSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )

    $summaryPath = [System.IO.Path]::Combine($RunFolder, 'summary.json')
    $manifestPath = [System.IO.Path]::Combine($RunFolder, 'manifest.json')
    $requestPath = [System.IO.Path]::Combine($RunFolder, 'app.request.json')

    return [pscustomobject]@{
        Summary = if ([System.IO.File]::Exists($summaryPath)) { (Get-Content -Path $summaryPath -Raw | ConvertFrom-Json) } else { $null }
        Manifest = if ([System.IO.File]::Exists($manifestPath)) { (Get-Content -Path $manifestPath -Raw | ConvertFrom-Json) } else { $null }
        Request = if ([System.IO.File]::Exists($requestPath)) { (Get-Content -Path $requestPath -Raw | ConvertFrom-Json) } else { $null }
        TotalCount = @(Load-AuditIndex -RunFolder $RunFolder).Count
    }
}

function Get-AuditDistinctValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][ValidateSet('service', 'action')] [string]$Field
    )

    return @(Load-AuditIndex -RunFolder $RunFolder | ForEach-Object { [string]$_.$Field } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

Export-ModuleMember -Function `
    Build-AuditIndex, Load-AuditIndex, Clear-AuditIndexCache, `
    Search-AuditRun, Get-AuditResultPage, Get-AuditRecordsByIndexEntries, `
    Get-AuditRecordById, Get-AuditRunSummary, Get-AuditDistinctValues, `
    ConvertTo-AuditDisplayRow
