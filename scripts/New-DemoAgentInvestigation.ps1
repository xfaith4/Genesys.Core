[CmdletBinding()]
param(
    [string] $Destination = (Join-Path $PSScriptRoot '..\samples\demo-agent-investigation')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$opsManifest = Join-Path $repoRoot 'modules\Genesys.Ops\Genesys.Ops.psd1'
Import-Module -Name $opsManifest -Force

$userId = 'agent-demo-001'
$fixture = @{
    'users.get.user.details.with.full.expansion' = @(
        [pscustomobject]@{ id = $userId; name = 'Jane Doe'; email = 'jane.doe@example.invalid'; state = 'ACTIVE'; division = [pscustomobject]@{ id = 'div-demo-1'; name = 'CustomerCare' } }
    )
    'users.get.user.routing.skills' = @(
        [pscustomobject]@{ id = 'sk-demo-1'; userId = $userId; name = 'English'; state = 'active' }
        [pscustomobject]@{ id = 'sk-demo-2'; userId = $userId; name = 'Billing'; state = 'active' }
    )
    'users.get.user.queue.memberships' = @(
        [pscustomobject]@{ id = 'queue-demo-1'; userId = $userId; name = 'Support'; joined = $true }
        [pscustomobject]@{ id = 'queue-demo-2'; userId = $userId; name = 'Escalations'; joined = $true }
    )
    'users.get.bulk.user.presences' = @(
        [pscustomobject]@{ userId = $userId; presence = 'AVAILABLE' }
    )
    'users.get.agent.current.routing.status' = @(
        [pscustomobject]@{ userId = $userId; status = 'INTERACTING'; startTime = '2026-04-02T10:15:00Z' }
    )
    'routing.get.user.utilization' = @(
        [pscustomobject]@{ userId = $userId; call = [pscustomobject]@{ maximumCapacity = 1; utilizedCapacity = 1 }; callback = [pscustomobject]@{ maximumCapacity = 1; utilizedCapacity = 0 } }
    )
    'analytics.query.user.details.activity.report' = @(
        [pscustomobject]@{ userId = $userId; loginMinutes = 420; onQueueMinutes = 340; interactingMinutes = 285 }
    )
    'users.get.agent.active.conversations' = @(
        [pscustomobject]@{ id = 'active-conv-demo-1'; userId = $userId; mediaType = 'voice'; state = 'connected' }
        [pscustomobject]@{ id = 'active-conv-demo-2'; userId = $userId; mediaType = 'message'; state = 'connected' }
    )
    'analytics-conversation-details-query' = @(
        [pscustomobject]@{ conversationId = 'conv-demo-A'; participants = @([pscustomobject]@{ userId = $userId; role = 'agent' }) }
        [pscustomobject]@{ conversationId = 'conv-demo-B'; participants = @([pscustomobject]@{ userId = $userId; role = 'agent' }) }
    )
    'audit-logs' = @(
        [pscustomobject]@{ id = 'audit-demo-1'; entityId = $userId; entityType = 'User'; action = 'update'; serviceName = 'directory'; timestamp = '2026-04-02T01:00:00Z' }
    )
}

$datasetInvoker = {
    param($Step, $Subject, $Window)
    $key = [string]$Step.DatasetKey
    $records = if ($fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
    @{ records = $records; runId = 'demo-' + $Step.Name; status = 'ok'; errorMessage = $null }
}.GetNewClosure()

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-demo-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $result = Get-GenesysAgentInvestigation -UserId $userId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $tempRoot -RunId 'demo-run' -DatasetInvoker $datasetInvoker

    if (Test-Path $Destination) {
        Remove-Item -Path $Destination -Recurse -Force
    }
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $result.RunFolder '*') -Destination $Destination -Recurse -Force
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
