#Requires -Version 5.1
<#
.SYNOPSIS
    Generates a demo conversation investigation package without Genesys credentials.
.DESCRIPTION
    Uses the Get-GenesysConversationInvestigation -DatasetInvoker seam to produce
    a sample run folder, then packages it with Export-GenesysConversationInvestigationPackage.
#>

[CmdletBinding()]
param(
    [string] $OutputDirectory,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'samples/demo-conversation-investigation'
}

$opsManifest = Join-Path $repoRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
Import-Module -Name $opsManifest -Force

$conversationId = 'demo-conversation-001'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("genesys-core-demo-package-" + [guid]::NewGuid().ToString('N'))
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $fixture = @{
        'analytics-conversation-details-query' = @(
            [pscustomobject]@{
                conversationId    = $conversationId
                conversationStart = '2026-05-01T14:00:00.000Z'
                conversationEnd   = '2026-05-01T14:12:45.000Z'
                mediaType         = 'voice'
                participants      = @(
                    [pscustomobject]@{
                        userId   = 'demo-agent-001'
                        purpose  = 'agent'
                        sessions = @(
                            [pscustomobject]@{
                                mediaType = 'voice'
                                direction = 'inbound'
                                ani       = '+15551230000'
                                dnis      = '+15559870000'
                                segments  = @(
                                    [pscustomobject]@{
                                        segmentStart   = '2026-05-01T14:00:35.000Z'
                                        segmentEnd     = '2026-05-01T14:01:15.000Z'
                                        segmentType    = 'alert'
                                        queueName      = 'CustomerCare'
                                        disconnectType = ''
                                    }
                                    [pscustomobject]@{
                                        segmentStart   = '2026-05-01T14:01:15.000Z'
                                        segmentEnd     = '2026-05-01T14:09:40.000Z'
                                        segmentType    = 'interact'
                                        queueName      = 'CustomerCare'
                                        disconnectType = ''
                                    }
                                    [pscustomobject]@{
                                        segmentStart   = '2026-05-01T14:09:40.000Z'
                                        segmentEnd     = '2026-05-01T14:12:45.000Z'
                                        segmentType    = 'wrapup'
                                        queueName      = 'CustomerCare'
                                        disconnectType = 'client'
                                        wrapUpCodeName = 'Billing question resolved'
                                    }
                                )
                            }
                        )
                    }
                    [pscustomobject]@{
                        userId   = 'demo-customer-001'
                        purpose  = 'customer'
                        sessions = @(
                            [pscustomobject]@{
                                mediaType = 'voice'
                                direction = 'inbound'
                                segments  = @(
                                    [pscustomobject]@{
                                        segmentStart   = '2026-05-01T14:00:00.000Z'
                                        segmentEnd     = '2026-05-01T14:12:45.000Z'
                                        segmentType    = 'interact'
                                        queueName      = 'CustomerCare'
                                        disconnectType = 'client'
                                    }
                                )
                            }
                        )
                    }
                )
            }
        )
        'users' = @(
            [pscustomobject]@{ id = 'demo-agent-001'; name = 'Demo Agent'; email = 'demo.agent@example.invalid'; state = 'ACTIVE' }
        )
        'users.division.analysis.get.users.with.division.info' = @(
            [pscustomobject]@{ id = 'demo-agent-001'; division = [pscustomobject]@{ id = 'demo-division'; name = 'CustomerCare' } }
        )
        'routing.get.all.routing.skills' = @(
            [pscustomobject]@{ id = 'demo-skill-voice'; name = 'Voice Support'; state = 'active' }
        )
        'conversations.get.recordings' = @(
            [pscustomobject]@{ id = 'demo-recording-001'; conversationId = $conversationId; mediaType = 'audio' }
        )
        'quality.get.evaluations.query' = @(
            [pscustomobject]@{
                id           = 'demo-evaluation-001'
                conversation = [pscustomobject]@{ id = $conversationId }
                totalScore   = 91
            }
        )
    }

    $datasetInvoker = {
        param($Step, $Subject, $Window)
        $key = [string]$Step.DatasetKey
        $records = if ($fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
        return @{ records = $records; runId = 'demo-' + $Step.Name; status = 'ok'; errorMessage = $null }
    }.GetNewClosure()

    $sipTracePath = Join-Path $tempRoot 'demo-sip-trace.log'
    Set-Content -Path $sipTracePath -Encoding utf8 -Value @'
2026-05-01T14:00:20.000Z INVITE sip:+15559870000@example.invalid SIP/2.0
Call-ID: demo-call-001
From: <sip:+15551230000@example.invalid>
To: <sip:+15559870000@example.invalid>
Contact: <sip:demo.agent@example.invalid>
User-Agent: Demo WebRTC Client
CSeq: 1 INVITE
Via: SIP/2.0/TLS edge.example.invalid
c=IN IP4 203.0.113.10
m=audio 19000 RTP/AVP 0 8 101
a=sendrecv

2026-05-01T14:00:25.000Z SIP/2.0 180 Ringing
Call-ID: demo-call-001
From: <sip:+15551230000@example.invalid>
To: <sip:+15559870000@example.invalid>
Server: Demo Edge
CSeq: 1 INVITE
Via: SIP/2.0/TLS edge.example.invalid

2026-05-01T14:00:30.000Z SIP/2.0 486 Busy Here
Call-ID: demo-call-001
From: <sip:+15551230000@example.invalid>
To: <sip:+15559870000@example.invalid>
Server: Demo SBC
CSeq: 1 INVITE
Via: SIP/2.0/TLS edge.example.invalid
'@

    $run = Get-GenesysConversationInvestigation `
        -ConversationId $conversationId `
        -OutputRoot $tempRoot `
        -RunId 'demo-run' `
        -DatasetInvoker $datasetInvoker

    Export-GenesysConversationInvestigationPackage `
        -RunFolder $run.RunFolder `
        -SipTracePath $sipTracePath `
        -OutputDirectory $OutputDirectory `
        -PackageName 'demo-conversation-investigation' `
        -Force:$Force
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
