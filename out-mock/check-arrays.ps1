$analyticsPath = 'G:\Development\20_Staging\Genesys.Core\out-mock\analytics-conversation-details\20260221T002216Z\data\analytics-conversation-details.jsonl'
$auditPath     = 'G:\Development\20_Staging\Genesys.Core\out-mock\audit-logs\20260221T002213Z\data\audit.jsonl'

Write-Host "`n=== Analytics: sessions/segments array check ===`n"
$lines = Get-Content $analyticsPath
foreach ($line in $lines) {
    $r = $line | ConvertFrom-Json
    $p0 = $r.participants[0]
    $sessionIsArray  = $p0.sessions -is [array]
    $sessionCount    = if ($sessionIsArray) { $p0.sessions.Count } else { '(object)' }
    $seg0 = if ($sessionIsArray) { $p0.sessions[0].segments } else { $p0.sessions.segments }
    $segIsArray = $seg0 -is [array]
    $segCount   = if ($segIsArray) { $seg0.Count } else { '(object)' }
    $userId = $r.participants[0].userId
    Write-Host "  conv=$($r.conversationId)  participants=$($r.participants.Count)  sessions[$($sessionCount)]=$(if($sessionIsArray){'OK'}else{'FAIL'})  segments[$($segCount)]=$(if($segIsArray){'OK'}else{'FAIL'})  userId=$userId"
}

Write-Host "`n=== Audit: context.changes array check ===`n"
$auditLines = Get-Content $auditPath
foreach ($al in $auditLines) {
    $a = $al | ConvertFrom-Json
    $changes = $a.context.changes
    if ($null -ne $changes) {
        $isArray = $changes -is [array]
        Write-Host "  id=$($a.id)  changes count=$($changes.Count)  isArray=$(if($isArray){'OK'}else{'FAIL'})"
    }
}

Write-Host "`n=== Raw JSON spot-check (conv-1 first participant) ===`n"
($lines[0] | ConvertFrom-Json).participants[0] | ConvertTo-Json -Depth 6
