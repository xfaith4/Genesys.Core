[CmdletBinding()]
param(
    [string] $Destination = (Join-Path $PSScriptRoot '..\samples\demo-conversation-investigation-run')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$opsManifest = Join-Path $repoRoot 'modules\Genesys.Ops\Genesys.Ops.psd1'
Import-Module -Name $opsManifest -Force

$conversationId = 'conv-demo-001'
$fixture = @{
    'conversations.get.specific.conversation.details' = @(
        [pscustomobject]@{
            conversationId = $conversationId
            conversationStart = '2026-04-05T13:10:00Z'
            conversationEnd = '2026-04-05T13:27:00Z'
            participants = @(
                [pscustomobject]@{ userId = 'agent-demo-001'; purpose = 'agent'; queueId = 'queue-demo-1'; divisionId = 'div-demo-1' },
                [pscustomobject]@{ purpose = 'customer' }
            )
        }
    )
    'analytics-conversation-details-query' = @(
        [pscustomobject]@{
            conversationId = $conversationId
            participants = @([pscustomobject]@{ userId = 'agent-demo-001'; role = 'agent' })
        }
    )
    'users' = @(
        [pscustomobject]@{ id = 'agent-demo-001'; name = 'Jane Doe'; division = [pscustomobject]@{ id = 'div-demo-1'; name = 'CustomerCare' } }
    )
    'users.division.analysis.get.users.with.division.info' = @(
        [pscustomobject]@{ userId = 'agent-demo-001'; division = [pscustomobject]@{ id = 'div-demo-1'; name = 'CustomerCare' } }
    )
    'routing.get.all.routing.skills' = @(
        [pscustomobject]@{ id = 'skill-demo-1'; userId = 'agent-demo-001'; name = 'Billing' }
        [pscustomobject]@{ id = 'skill-demo-2'; userId = 'agent-demo-001'; name = 'Retention' }
    )
    'conversations.get.recordings' = @(
        [pscustomobject]@{ id = 'rec-demo-1'; conversationId = $conversationId; mediaType = 'voice'; status = 'available' }
    )
    'quality.get.evaluations.query' = @(
        [pscustomobject]@{ id = 'eval-demo-1'; conversation = [pscustomobject]@{ id = $conversationId }; totalScore = 91 }
    )
    'quality.get.surveys' = @(
        [pscustomobject]@{ id = 'survey-demo-1'; conversationId = $conversationId; npsScore = 10; csatScore = 4.9; comment = 'Agent resolved the issue quickly.' }
    )
}

$datasetInvoker = {
    param($Step, $Subject, $Window)
    $key = [string]$Step.DatasetKey
    $records = if ($fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
    @{ records = $records; runId = 'demo-' + $Step.Name; status = 'ok'; errorMessage = $null }
}.GetNewClosure()

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('conversation-demo-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $result = Get-GenesysConversationInvestigation -ConversationId $conversationId -OutputRoot $tempRoot -RunId 'demo-run' -DatasetInvoker $datasetInvoker

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
