<#
.SYNOPSIS
    Parses a SIP trace log and extracts key SIP troubleshooting information.

.DESCRIPTION
    This script scans a SIP trace log and extracts the top 10 vital SIP fields:
    Call-ID, SIP Methods, Response Codes, From, To, Contact, User-Agent,
    CSeq, Via, and SDP media details.

.EXAMPLE
    .\Parse-SipTrace.ps1 -Path "C:\Logs\siptrace.log"

.EXAMPLE
    .\Parse-SipTrace.ps1 -Path "C:\Logs\siptrace.log" -ExportCsv "C:\Logs\sip-summary.csv"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$ExportCsv
)

if (-not (Test-Path $Path)) {
    throw "Log file not found: $Path"
}

$content = Get-Content -Path $Path -Raw

# Split SIP messages.
# Most SIP traces separate messages with blank lines.
# This also works reasonably well for many packet-capture-style text exports.
$messages = $content -split "(`r?`n){2,}" | Where-Object {
    $_ -match "SIP/2.0|INVITE|ACK|BYE|CANCEL|OPTIONS|REGISTER|PRACK|UPDATE|REFER|INFO|SUBSCRIBE|NOTIFY|MESSAGE"
}

$results = foreach ($message in $messages) {

    $lines = $message -split "`r?`n"

    $startLine = ($lines | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim()

    # Determine whether this is a request or response
    $messageType = if ($startLine -match "^SIP/2.0\s+(\d{3})\s+(.*)$") {
        "Response"
    }
    elseif ($startLine -match "^(INVITE|ACK|BYE|CANCEL|OPTIONS|REGISTER|PRACK|UPDATE|REFER|INFO|SUBSCRIBE|NOTIFY|MESSAGE)\s+") {
        "Request"
    }
    else {
        "Unknown"
    }

    $sipMethod = $null
    $responseCode = $null
    $responseText = $null

    if ($startLine -match "^SIP/2.0\s+(\d{3})\s+(.*)$") {
        $responseCode = $matches[1]
        $responseText = $matches[2]
    }
    elseif ($startLine -match "^(INVITE|ACK|BYE|CANCEL|OPTIONS|REGISTER|PRACK|UPDATE|REFER|INFO|SUBSCRIBE|NOTIFY|MESSAGE)\s+") {
        $sipMethod = $matches[1]
    }

    function Get-SipHeader {
        param(
            [string[]]$Lines,
            [string[]]$Names
        )

        foreach ($name in $Names) {
            $match = $Lines | Where-Object {
                $_ -match "^\s*$([regex]::Escape($name))\s*:"
            } | Select-Object -First 1

            if ($match) {
                return ($match -replace "^\s*$([regex]::Escape($name))\s*:\s*", "").Trim()
            }
        }

        return $null
    }

    $callId    = Get-SipHeader -Lines $lines -Names @("Call-ID", "i")
    $from      = Get-SipHeader -Lines $lines -Names @("From", "f")
    $to        = Get-SipHeader -Lines $lines -Names @("To", "t")
    $contact   = Get-SipHeader -Lines $lines -Names @("Contact", "m")
    $userAgent = Get-SipHeader -Lines $lines -Names @("User-Agent", "Server")
    $cseq      = Get-SipHeader -Lines $lines -Names @("CSeq")
    $via       = Get-SipHeader -Lines $lines -Names @("Via", "v")

    # SDP extraction
    $sdpConnectionIp = $null
    $audioPort = $null
    $audioCodecs = $null
    $mediaDirection = $null

    $connectionLine = $lines | Where-Object {
        $_ -match "^c=IN\s+IP[46]\s+(.+)$"
    } | Select-Object -First 1

    if ($connectionLine -match "^c=IN\s+IP[46]\s+(.+)$") {
        $sdpConnectionIp = $matches[1].Trim()
    }

    $audioLine = $lines | Where-Object {
        $_ -match "^m=audio\s+(\d+)\s+\S+\s+(.+)$"
    } | Select-Object -First 1

    if ($audioLine -match "^m=audio\s+(\d+)\s+\S+\s+(.+)$") {
        $audioPort = $matches[1]
        $audioCodecs = $matches[2].Trim()
    }

    $directionLine = $lines | Where-Object {
        $_ -match "^a=(sendrecv|sendonly|recvonly|inactive)$"
    } | Select-Object -First 1

    if ($directionLine -match "^a=(sendrecv|sendonly|recvonly|inactive)$") {
        $mediaDirection = $matches[1]
    }

    [pscustomobject]@{
        MessageType      = $messageType
        StartLine        = $startLine
        Method           = $sipMethod
        ResponseCode     = $responseCode
        ResponseText     = $responseText
        CallID           = $callId
        From             = $from
        To               = $to
        Contact          = $contact
        UserAgent        = $userAgent
        CSeq             = $cseq
        Via              = $via
        MediaIP          = $sdpConnectionIp
        AudioPort        = $audioPort
        AudioCodecs      = $audioCodecs
        MediaDirection   = $mediaDirection
    }
}

# Display parsed SIP messages
$results | Format-Table -AutoSize

# Summary statistics
Write-Host "`n===== SIP Trace Summary =====" -ForegroundColor Cyan

Write-Host "`nTop Call-IDs:" -ForegroundColor Yellow
$results |
    Where-Object CallID |
    Group-Object CallID |
    Sort-Object Count -Descending |
    Select-Object -First 10 Count, Name |
    Format-Table -AutoSize

Write-Host "`nSIP Methods:" -ForegroundColor Yellow
$results |
    Where-Object Method |
    Group-Object Method |
    Sort-Object Count -Descending |
    Format-Table Count, Name -AutoSize

Write-Host "`nSIP Response Codes:" -ForegroundColor Yellow
$results |
    Where-Object ResponseCode |
    Group-Object ResponseCode, ResponseText |
    Sort-Object Count -Descending |
    Format-Table Count, Name -AutoSize

Write-Host "`nUser-Agents / Servers:" -ForegroundColor Yellow
$results |
    Where-Object UserAgent |
    Group-Object UserAgent |
    Sort-Object Count -Descending |
    Select-Object -First 10 Count, Name |
    Format-Table -AutoSize

Write-Host "`nMedia Endpoints:" -ForegroundColor Yellow
$results |
    Where-Object MediaIP |
    Group-Object MediaIP |
    Sort-Object Count -Descending |
    Select-Object -First 10 Count, Name |
    Format-Table -AutoSize

Write-Host "`nAudio Ports:" -ForegroundColor Yellow
$results |
    Where-Object AudioPort |
    Group-Object AudioPort |
    Sort-Object Count -Descending |
    Select-Object -First 10 Count, Name |
    Format-Table -AutoSize

Write-Host "`nMedia Directions:" -ForegroundColor Yellow
$results |
    Where-Object MediaDirection |
    Group-Object MediaDirection |
    Sort-Object Count -Descending |
    Format-Table Count, Name -AutoSize

# Optional CSV export
if ($ExportCsv) {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "`nExported parsed SIP data to: $ExportCsv" -ForegroundColor Green
}
