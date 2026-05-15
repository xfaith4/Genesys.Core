#Requires -Version 5.1
[CmdletBinding()]
param(
    [string] $Destination = (Join-Path $PSScriptRoot '..\samples\demo-campaign-investigation')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$opsManifest = Join-Path $repoRoot 'modules\Genesys.Ops\Genesys.Ops.psd1'
Import-Module -Name $opsManifest -Force

$campaignId = 'campaign-demo-1'
$fixture = @{
    'outbound.get.campaigns' = @(
        [pscustomobject]@{
            id = $campaignId
            name = 'Spring Renewal'
            campaignStatus = 'on'
            dialingMode = 'power'
            contactListId = 'contact-list-demo-1'
            queueId = 'queue-demo-1'
            callerName = 'Genesys Cloud'
            callerAddress = '+15551234567'
            abandonRate = 3
        }
    )
    'outbound.get.contact.lists' = @(
        [pscustomobject]@{ id = 'contact-list-demo-1'; name = 'Renewals Q2'; size = 2400; columnNames = @('phone','firstName') }
    )
    'routing.get.single.queue.config' = @(
        [pscustomobject]@{ id = 'queue-demo-1'; name = 'Outbound Sales'; mediaSettings = [pscustomobject]@{ call = [pscustomobject]@{ alertingTimeoutSeconds = 25 } } }
    )
    'outbound.get.campaign.diagnostics.summary' = @(
        [pscustomobject]@{ campaignId = $campaignId; health = 'healthy'; pacingMode = 'power'; errorCount = 0; contactableRate = 78.1 }
    )
    'outbound.get.events' = @(
        [pscustomobject]@{ id = 'evt-1'; campaignId = $campaignId; timestamp = '2026-05-10T14:00:00Z'; type = 'campaignStart'; callResult = $null }
        [pscustomobject]@{ id = 'evt-2'; campaignId = $campaignId; timestamp = '2026-05-10T14:01:00Z'; type = 'contactCallCompleted'; callResult = 'Connected' }
        [pscustomobject]@{ id = 'evt-3'; campaignId = $campaignId; timestamp = '2026-05-10T14:02:00Z'; type = 'contactCallCompleted'; callResult = 'NoAnswer' }
        [pscustomobject]@{ id = 'evt-4'; campaignId = $campaignId; timestamp = '2026-05-10T14:03:00Z'; type = 'contactCallAbandon'; callResult = 'OutboundAbandon' }
    )
    'audit-logs' = @(
        [pscustomobject]@{ id = 'audit-1'; entityId = $campaignId; entityType = 'Campaign'; action = 'UPDATE_OUTBOUND_CAMPAIGN'; serviceName = 'outbound'; timestamp = '2026-05-10T13:45:00Z' }
    )
    'analytics-conversation-details-query' = @(
        [pscustomobject]@{
            conversationId = 'conv-campaign-1'
            originatingDirection = 'outbound'
            participants = @(
                [pscustomobject]@{
                    purpose = 'agent'
                    userId = 'agent-demo-001'
                    campaignId = $campaignId
                    sessions = @(
                        [pscustomobject]@{
                            mediaType = 'voice'
                            segments = @(
                                [pscustomobject]@{ segmentType = 'interact'; campaignId = $campaignId; queueId = 'queue-demo-1'; disconnectType = 'client' }
                            )
                        }
                    )
                }
            )
        }
    )
}

$datasetInvoker = {
    param($Step, $Subject, $Window)
    $key = [string]$Step.DatasetKey
    $records = if ($fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
    @{ records = $records; runId = 'demo-' + $Step.Name; status = 'ok'; errorMessage = $null }
}.GetNewClosure()

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('campaign-demo-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $result = Get-GenesysCampaignInvestigation -CampaignId $campaignId -Since ([datetime]'2026-05-01T00:00:00Z') -Until ([datetime]'2026-05-12T00:00:00Z') -OutputRoot $tempRoot -RunId 'demo-run' -DatasetInvoker $datasetInvoker

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
