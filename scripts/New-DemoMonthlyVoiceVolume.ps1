#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputRoot = './output/monthly-volume-demo')
Import-Module (Join-Path $PSScriptRoot '../modules/Genesys.Ops/Genesys.Ops.psd1') -Force
Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $OutputRoot -DatasetInvoker {
    param($Dataset, $Body, $OutputRoot)
    $records = @()
    if ($Dataset -like '*aggregates*') {
        $offered = if ($Dataset -eq 'analytics-conversation-aggregates-jobs') { 4 } else { 3 }
        $records = @(@{ group = @{ mediaType = 'voice' }; data = @(@{ interval = $Body.interval; metrics = @(
            @{ metric = 'nOffered'; stats = @{ count = $offered } },
            @{ metric = 'nConnected'; stats = @{ count = 2 } },
            @{ metric = 'nOutbound'; stats = @{ count = 1 } }
        ) }) })
    }
    else {
        $ids = if ($Dataset -eq 'analytics-conversation-details-query') { @('demo-a', 'demo-b') } else { @('demo-b', 'demo-c', 'demo-d') }
        $records = @($ids | ForEach-Object { @{ conversationId = $_; participants = @(@{ sessions = @(@{ mediaType = 'voice' }) }) } })
    }
    return @{ Records = $records; Status = 'complete'; Events = @() }
}
