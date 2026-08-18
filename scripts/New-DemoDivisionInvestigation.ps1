[CmdletBinding()]
param(
    [string] $Destination = (Join-Path $PSScriptRoot '..\samples\demo-division-investigation')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$opsManifest = Join-Path $repoRoot 'modules\Genesys.Ops\Genesys.Ops.psd1'
Import-Module -Name $opsManifest -Force

$divisionId = 'division-demo-1'
$fixture = @{
    'authorization.get.all.divisions' = @(
        [pscustomobject]@{ id = $divisionId; name = 'North America'; description = 'NA contact centre operations'; homeDivision = $false }
    )
    'authorization.list.division.queues' = @(
        [pscustomobject]@{ id = 'queue-demo-001'; name = 'Support' }
        [pscustomobject]@{ id = 'queue-demo-002'; name = 'Sales' }
    )
    'users.division.analysis.get.users.with.division.info' = @(
        [pscustomobject]@{ id = 'agent-demo-001'; name = 'Jane Doe';   email = 'jane@x.com';  state = 'ACTIVE'; division = [pscustomobject]@{ id = $divisionId; name = 'North America' } }
        [pscustomobject]@{ id = 'agent-demo-002'; name = 'John Smith'; email = 'john@x.com';  state = 'ACTIVE'; division = [pscustomobject]@{ id = $divisionId; name = 'North America' } }
    )
    'authorization.get.division.grants' = @(
        [pscustomobject]@{ subjectId = 'agent-demo-001'; subjectType = 'PC_USER'; roleId = 'role-supervisor'; roleName = 'Supervisor'; grantMadeAt = '2026-01-15T00:00:00Z' }
    )
    'analytics.query.user.aggregates.performance.metrics' = @(
        [pscustomobject]@{ userId = 'agent-demo-001'; nConnected = 42; tHandle = 15600; tTalk = 12100; tAcw = 3500; nOffered = 45; tAnswered = 40 }
        [pscustomobject]@{ userId = 'agent-demo-002'; nConnected = 38; tHandle = 13900; tTalk = 10800; tAcw = 3100; nOffered = 40; tAnswered = 37 }
    )
    'analytics.query.conversation.aggregates.division.performance' = @(
        [pscustomobject]@{ divisionId = $divisionId; nConnected = 180; tHandle = 64800; tTalk = 50200; tHeld = 4100; tAcw = 14600; tAnswered = 168; nOffered = 190; nOutbound = 12; nError = 2 }
    )
    'analytics.query.conversation.aggregates.queue.performance' = @(
        [pscustomobject]@{ queueId = 'queue-demo-001'; mediaType = 'voice'; nConnected = 120; tHandle = 43200; tTalk = 33500; tAcw = 9800; tAnswered = 112; tHeld = 2600; nOffered = 125; nOutbound = 0 }
        [pscustomobject]@{ queueId = 'queue-demo-002'; mediaType = 'voice'; nConnected = 60;  tHandle = 21600; tTalk = 16700; tAcw = 4800;  tAnswered = 56;  tHeld = 1500; nOffered = 65;  nOutbound = 12 }
    )
    'quality.get.evaluations.query' = @(
        [pscustomobject]@{ id = 'eval-demo-1'; agent = [pscustomobject]@{ id = 'agent-demo-001'; name = 'Jane Doe' }; totalScore = 92 }
        [pscustomobject]@{ id = 'eval-demo-2'; agent = [pscustomobject]@{ id = 'agent-demo-002'; name = 'John Smith' }; totalScore = 87 }
    )
}

$datasetInvoker = {
    param($Step, $Subject, $Window)
    $key = [string]$Step.DatasetKey
    $records = if ($fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
    @{ records = $records; runId = 'demo-' + $Step.Name; status = 'ok'; errorMessage = $null }
}.GetNewClosure()

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('division-demo-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $result = Get-GenesysDivisionInvestigation -DivisionId $divisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $tempRoot -RunId 'demo-run' -DatasetInvoker $datasetInvoker

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
