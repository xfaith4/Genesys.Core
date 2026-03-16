#Requires -Version 5.1
Set-StrictMode -Version Latest

function ConvertTo-AuditFlatRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Record
    )

    $changeSummary = ''
    $changes = @()
    foreach ($path in @('changes', 'context.changes', 'changedProperties')) {
        $current = $Record
        $resolved = $true
        foreach ($segment in ($path -split '\.')) {
            if ($null -eq $current -or -not $current.PSObject.Properties[$segment]) {
                $resolved = $false
                break
            }
            $current = $current.$segment
        }
        if ($resolved -and $null -ne $current) {
            $changes = @($current)
            break
        }
    }

    if ($changes.Count -gt 0) {
        $changeSummary = ($changes | ForEach-Object {
            $field = if ($_.PSObject.Properties['field']) { $_.field } elseif ($_.PSObject.Properties['name']) { $_.name } else { '' }
            $before = if ($_.PSObject.Properties['before']) { $_.before } else { '' }
            $after = if ($_.PSObject.Properties['after']) { $_.after } else { '' }
            "${field}: $before -> $after"
        }) -join '; '
    }

    $actor = if ($Record.PSObject.Properties['userName']) {
        $Record.userName
    }
    elseif ($Record.PSObject.Properties['userEmail']) {
        $Record.userEmail
    }
    elseif ($Record.PSObject.Properties['userId']) {
        $Record.userId
    }
    else {
        ''
    }

    $entityType = ''
    $entityId = ''
    $entityName = ''
    if ($Record.PSObject.Properties['context']) {
        if ($Record.context.PSObject.Properties['type']) { $entityType = $Record.context.type }
        if ($Record.context.PSObject.Properties['entityId']) { $entityId = $Record.context.entityId }
        if ($Record.context.PSObject.Properties['entityName']) { $entityName = $Record.context.entityName }
    }

    return [ordered]@{
        recordId       = if ($Record.PSObject.Properties['id']) { [string]$Record.id } else { '' }
        timestampUtc   = if ($Record.PSObject.Properties['timestamp']) { [string]$Record.timestamp } elseif ($Record.PSObject.Properties['timestampUtc']) { [string]$Record.timestampUtc } else { '' }
        serviceName    = if ($Record.PSObject.Properties['serviceName']) { [string]$Record.serviceName } else { '' }
        action         = if ($Record.PSObject.Properties['action']) { [string]$Record.action } else { '' }
        actor          = [string]$actor
        actorEmail     = if ($Record.PSObject.Properties['userEmail']) { [string]$Record.userEmail } else { '' }
        actorId        = if ($Record.PSObject.Properties['userId']) { [string]$Record.userId } else { '' }
        entityType     = [string]$entityType
        entityId       = [string]$entityId
        entityName     = [string]$entityName
        status         = if ($Record.PSObject.Properties['status']) { [string]$Record.status } else { '' }
        correlationId  = if ($Record.PSObject.Properties['correlationId']) { [string]$Record.correlationId } elseif ($Record.PSObject.Properties['traceId']) { [string]$Record.traceId } else { '' }
        message        = if ($Record.PSObject.Properties['message']) { [string]$Record.message } elseif ($Record.PSObject.Properties['summary']) { [string]$Record.summary } else { '' }
        changedFields  = [string]$changeSummary
    }
}

function _Quote-Csv {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Value
    )

    if ($Value -match '[,"\r\n]') {
        return '"' + $Value.Replace('"', '""') + '"'
    }

    return $Value
}

function _Write-FlatRowsToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.StreamWriter]$Writer,
        [Parameter(Mandatory)][object[]]$Records,
        [Parameter(Mandatory)][ref]$HeaderWritten
    )

    foreach ($record in $Records) {
        $row = ConvertTo-AuditFlatRow -Record $record
        if (-not $HeaderWritten.Value) {
            $Writer.WriteLine((@($row.Keys | ForEach-Object { _Quote-Csv -Value ([string]$_) }) -join ','))
            $HeaderWritten.Value = $true
        }

        $Writer.WriteLine((@($row.Values | ForEach-Object { _Quote-Csv -Value ([string]$_) }) -join ','))
    }
}

function Export-AuditCsv {
    [CmdletBinding(DefaultParameterSetName = 'FullRun')]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(ParameterSetName = 'Filtered')][object[]]$IndexEntries
    )

    $writer = [System.IO.StreamWriter]::new($OutputPath, $false, (New-Object System.Text.UTF8Encoding($true)))
    try {
        $headerWritten = $false
        if ($PSCmdlet.ParameterSetName -eq 'Filtered') {
            $records = Get-AuditRecordsByIndexEntries -RunFolder $RunFolder -IndexEntries $IndexEntries
            _Write-FlatRowsToCsv -Writer $writer -Records $records -HeaderWritten ([ref]$headerWritten)
            return
        }

        foreach ($dataFile in @([System.IO.Directory]::GetFiles((Join-Path $RunFolder 'data'), '*.jsonl') | Sort-Object)) {
            $records = New-Object System.Collections.Generic.List[object]
            $fs = [System.IO.FileStream]::new(
                $dataFile,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite)
            $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
            try {
                while (-not $sr.EndOfStream) {
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

            _Write-FlatRowsToCsv -Writer $writer -Records $records.ToArray() -HeaderWritten ([ref]$headerWritten)
        }
    }
    finally {
        $writer.Dispose()
    }
}

function _HtmlEncode {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Value
    )

    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function _Write-HtmlRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.StreamWriter]$Writer,
        [Parameter(Mandatory)][object[]]$Records
    )

    foreach ($record in $Records) {
        $row = ConvertTo-AuditFlatRow -Record $record
        $cells = @()
        foreach ($value in $row.Values) {
            $cells += "<td>$(_HtmlEncode -Value ([string]$value))</td>"
        }
        $Writer.WriteLine("<tr>$($cells -join '')</tr>")
    }
}

function Export-AuditHtml {
    [CmdletBinding(DefaultParameterSetName = 'FullRun')]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$ReportTitle = 'Genesys Cloud Audit Logs Report',
        [AllowNull()][object]$Summary,
        [hashtable]$Filters = @{},
        [string]$ViewMode = 'Full Run',
        [Parameter(ParameterSetName = 'Filtered')][object[]]$IndexEntries
    )

    $writer = [System.IO.StreamWriter]::new($OutputPath, $false, (New-Object System.Text.UTF8Encoding($true)))
    try {
        $writer.WriteLine('<!DOCTYPE html>')
        $writer.WriteLine('<html lang="en"><head><meta charset="utf-8" />')
        $writer.WriteLine("<title>$(_HtmlEncode -Value $ReportTitle)</title>")
        $writer.WriteLine('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1a1a1a}h1,h2{margin:0 0 12px}table{border-collapse:collapse;width:100%;font-size:12px}th,td{border:1px solid #d0d7de;padding:6px 8px;vertical-align:top}th{background:#f3f6f9;text-align:left}.meta{margin:12px 0 24px;display:grid;grid-template-columns:220px 1fr;gap:6px 14px}.muted{color:#5f6b7a}.pill{display:inline-block;padding:3px 8px;background:#e8eef5;border-radius:999px;margin-right:6px}</style>')
        $writer.WriteLine('</head><body>')
        $writer.WriteLine("<h1>$(_HtmlEncode -Value $ReportTitle)</h1>")
        $writer.WriteLine("<p class=""muted"">Generated $(_HtmlEncode -Value ([datetime]::UtcNow.ToString('u'))) UTC</p>")
        $writer.WriteLine('<div class="meta">')
        $writer.WriteLine("<div>Run folder</div><div>$(_HtmlEncode -Value $RunFolder)</div>")
        $writer.WriteLine("<div>Export scope</div><div>$(_HtmlEncode -Value $ViewMode)</div>")
        if ($null -ne $Summary -and $Summary.totals) {
            $writer.WriteLine("<div>Total records</div><div>$(_HtmlEncode -Value ([string]$Summary.totals.totalRecords))</div>")
            $writer.WriteLine("<div>Total services</div><div>$(_HtmlEncode -Value ([string]$Summary.totals.totalServices))</div>")
            $writer.WriteLine("<div>Total actions</div><div>$(_HtmlEncode -Value ([string]$Summary.totals.totalActions))</div>")
        }
        $writer.WriteLine("<div>Selected filters</div><div>$(_HtmlEncode -Value (($Filters.GetEnumerator() | ForEach-Object { ""$($_.Key)=$($_.Value)"" }) -join '; '))</div>")
        $writer.WriteLine('</div>')
        $writer.WriteLine('<h2>Results</h2>')

        $headerKeys = @((ConvertTo-AuditFlatRow -Record ([pscustomobject]@{})).Keys)
        $writer.WriteLine('<table><thead><tr>')
        foreach ($key in $headerKeys) {
            $writer.WriteLine("<th>$(_HtmlEncode -Value ([string]$key))</th>")
        }
        $writer.WriteLine('</tr></thead><tbody>')

        if ($PSCmdlet.ParameterSetName -eq 'Filtered') {
            _Write-HtmlRows -Writer $writer -Records (Get-AuditRecordsByIndexEntries -RunFolder $RunFolder -IndexEntries $IndexEntries)
        }
        else {
            foreach ($dataFile in @([System.IO.Directory]::GetFiles((Join-Path $RunFolder 'data'), '*.jsonl') | Sort-Object)) {
                $records = New-Object System.Collections.Generic.List[object]
                $fs = [System.IO.FileStream]::new(
                    $dataFile,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite)
                $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
                try {
                    while (-not $sr.EndOfStream) {
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

                _Write-HtmlRows -Writer $writer -Records $records.ToArray()
            }
        }

        $writer.WriteLine('</tbody></table></body></html>')
    }
    finally {
        $writer.Dispose()
    }
}

Export-ModuleMember -Function ConvertTo-AuditFlatRow, Export-AuditCsv, Export-AuditHtml
