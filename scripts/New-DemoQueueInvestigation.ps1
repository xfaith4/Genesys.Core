[CmdletBinding()]
param(
    [string] $Destination = (Join-Path $PSScriptRoot '..\samples\demo-queue-investigation')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$opsManifest = Join-Path $repoRoot 'modules\Genesys.Ops\Genesys.Ops.psd1'
Import-Module -Name $opsManifest -Force

$queueId = 'queue-demo-1'
$fixture = @{
    'routing.get.single.queue.config' = @(
        [pscustomobject]@{ id = $queueId; name = 'Support'; mediaSettings = [pscustomobject]@{ call = [pscustomobject]@{ alertingTimeoutSeconds = 30 } } }
    )
    'routing-queue-members' = @(
        [pscustomobject]@{ id = 'agent-demo-001'; queueId = $queueId; name = 'Jane Doe'; joined = $true }
        [pscustomobject]@{ id = 'agent-demo-002'; queueId = $queueId; name = 'John Smith'; joined = $true }
    )
    'routing.get.queue.wrapup.codes.by.queue' = @(
        [pscustomobject]@{ id = 'wu-demo-1'; queueId = $queueId; name = 'Resolved' }
        [pscustomobject]@{ id = 'wu-demo-2'; queueId = $queueId; name = 'Escalated' }
    )
    'analytics.query.queue.observations.real.time.stats' = @(
        [pscustomobject]@{ queueId = $queueId; mediaType = 'voice'; oWaiting = 3; oInteracting = 5; oOnQueueUsers = 7 }
    )
    'analytics.query.conversation.aggregates.queue.performance' = @(
        [pscustomobject]@{ queueId = $queueId; mediaType = 'voice'; nOffered = 120; nAnswered = 110; tHandle = 4500 }
    )
    'analytics.query.conversation.aggregates.abandon.metrics' = @(
        [pscustomobject]@{ queueId = $queueId; nAbandoned = 4; tAbandoned = 32; nOffered = 120 }
    )
    'analytics.query.conversation.aggregates.transfer.metrics' = @(
        [pscustomobject]@{ queueId = $queueId; mediaType = 'voice'; nTransferred = 6; nBlindTransferred = 2; nConsultTransferred = 4; nConnected = 110 }
    )
    'analytics.query.conversation.aggregates.wrapup.distribution' = @(
        [pscustomobject]@{ queueId = $queueId; wrapUpCode = 'Resolved'; nConnected = 82; tHandle = 3100 }
        [pscustomobject]@{ queueId = $queueId; wrapUpCode = 'Escalated'; nConnected = 28; tHandle = 1400 }
    )
    'analytics.query.user.observations.real.time.status' = @(
        [pscustomobject]@{ queueId = $queueId; userId = 'agent-demo-001'; oUserPresence = 'AVAILABLE' }
        [pscustomobject]@{ queueId = $queueId; userId = 'agent-demo-002'; oUserPresence = 'BUSY' }
    )
}

$datasetInvoker = {
    param($Step, $Subject, $Window)
    $key = [string]$Step.DatasetKey
    $records = if ($fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
    @{ records = $records; runId = 'demo-' + $Step.Name; status = 'ok'; errorMessage = $null }
}.GetNewClosure()

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('queue-demo-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $result = Get-GenesysQueueInvestigation -QueueId $queueId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $tempRoot -RunId 'demo-run' -DatasetInvoker $datasetInvoker

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
