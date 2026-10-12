#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputRoot = './output/conversation-analysis-demo', [ValidateRange(1,100000)][int]$ConversationCount = 120)
Import-Module (Join-Path $PSScriptRoot '../modules/Genesys.Ops/Genesys.Ops.psd1') -Force
Get-GenesysConversationAnalysis -Since '2026-09-01T00:00:00Z' -Until '2026-10-01T00:00:00Z' -OutputRoot $OutputRoot -ResolveEntityNames -EntityLookupInvoker {
    param($Kind,$Dataset,$Ids,$OutputRoot)
    $records=@(foreach($id in $Ids){
        $record=@{id=$id;name="Demo $Kind $id"}
        if($Kind -eq 'users'){$record.division=@{id="division-$([int]($id.Split('-')[-1]) % 2)"}}
        $record
    })
    return @{Records=$records;Status='complete'}
} -DatasetInvoker ({
    param($Dataset, $Body, $OutputRoot)
    $records = @(foreach ($i in 1..$ConversationCount) {
        $errors = @()
        if ($i % 4 -eq 0) { $errors = @(
            @{ segmentStart = '2026-09-15T12:00:05Z'; segmentEnd = '2026-09-15T12:00:06Z'; segmentType = 'interact'; errorCode = 'error.demo.ice'; disconnectType = 'error' },
            @{ segmentStart = '2026-09-15T12:00:07Z'; segmentEnd = '2026-09-15T12:00:08Z'; segmentType = 'interact'; errorCode = 'error.demo.ice'; disconnectType = 'peer' }
        ) }
        @{
            conversationId = 'demo-conversation-{0:000}' -f $i; conversationStart = '2026-09-15T12:00:00Z'; conversationEnd = '2026-09-15T12:03:00Z'
            originatingDirection = if ($i % 3) { 'inbound' } else { 'outbound' }; divisionIds = @("division-$($i % 2)")
            participants = @(
                @{ purpose = 'customer'; sessions = @(@{ mediaType = 'voice'; segments = @() }) },
                @{ purpose = 'acd'; sessions = @(@{ mediaType = 'voice'; flow = @{flowId="flow-$($i % 4)";flowName="Demo IVR $($i % 4)"}; metrics = @(@{name='nOffered';value=1},@{name='tAnswered';value=10000}); segments = @(@{queueId="queue-$($i % 3)";segmentType='interact';segmentStart='2026-09-15T12:00:00Z';segmentEnd='2026-09-15T12:00:10Z'}) }) },
                @{ purpose = 'agent'; userId = "agent-$($i % 5)"; sessions = @(@{ mediaType = 'voice'; mediaEndpointStats = @(@{ minMos = 1 + ($i % 4); discardedPackets=$i % 10; receivedPackets=1000; overrunPackets=0; underrunPackets=0; eventTime='2026-09-15T12:02:00Z'; maxLatencyMs = 20 + $i; codecs = @('opus') }); metrics = @(@{name='tHandle';value=$i*1000},@{name='tTalk';value=$i*800},@{name='nConnected';value=1}); segments = @(@{queueId="queue-$($i % 3)";segmentType='interact';segmentStart='2026-09-15T12:00:10Z';segmentEnd='2026-09-15T12:02:00Z';disconnectType='client'}) + $errors }) }
            )
        }
    })
    return @{ Records = @($records | ConvertTo-Json -Depth 30 | ConvertFrom-Json); Status = 'complete'; Events = @() }
}.GetNewClosure())
