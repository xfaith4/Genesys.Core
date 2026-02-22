$analyticsPath = 'G:\Development\20_Staging\Genesys.Core\out-mock\analytics-conversation-details\20260221T002216Z\data\analytics-conversation-details.jsonl'
$rawLines = Get-Content $analyticsPath

Write-Host "`n=== Grep for sessions/segments patterns in raw JSONL ===`n"
foreach ($line in $rawLines) {
    $r = $line | ConvertFrom-Json
    Write-Host "  $($r.conversationId):"
    # Check raw JSON contains array brackets for sessions
    $jsonSnip = $line | Select-String -Pattern '"sessions"\s*:\s*\[' -AllMatches
    Write-Host "    sessions is JSON array: $($jsonSnip.Matches.Count -gt 0)"
    $jsonSnip2 = $line | Select-String -Pattern '"segments"\s*:\s*\[' -AllMatches
    Write-Host "    segments is JSON array: $($jsonSnip2.Matches.Count -gt 0)"
}

Write-Host "`n=== Full JSON first participant (conv-v001) ===`n"
$first = ($rawLines[0] | ConvertFrom-Json).participants[0]
$first | ConvertTo-Json -Depth 8
