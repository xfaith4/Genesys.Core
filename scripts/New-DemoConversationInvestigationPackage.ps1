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
        'conversations.get.specific.conversation.details' = @(
            [pscustomobject]@{
                id        = $conversationId
                startTime = '2026-05-01T14:00:00.000Z'
                endTime   = '2026-05-01T14:12:45.000Z'
            }
        )
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
        'quality.get.surveys' = @(
            [pscustomobject]@{
                id             = 'demo-survey-001'
                conversationId = $conversationId
                npsScore       = 10
                csatScore      = 4.9
                comment        = 'Agent resolved the billing question quickly.'
            }
        )
    }

    $datasetInvoker = {
        param($Step, $Subject, $Window)
        $key = [string]$Step.DatasetKey
        $records = if ($fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
        return @{ records = $records; runId = 'demo-' + $Step.Name; status = 'ok'; errorMessage = $null }
    }.GetNewClosure()

    $apiInvoker = {
        param($Request)
        if ($Request.Method -eq 'GET' -and $Request.Path -eq '/api/v2/telephony/siptraces') {
            return [pscustomobject]@{
                data = @(
                    [pscustomobject]@{
                        date           = '2026-05-01T14:00:20.000Z'
                        method         = 'INVITE'
                        callid         = 'demo-call-001'
                        fromUser       = '+15551230000'
                        toUser         = '+15559870000'
                        contactUser    = 'demo.agent@example.invalid'
                        userAgent      = 'Demo WebRTC Client'
                        cseq           = '1 INVITE'
                        via1           = 'SIP/2.0/TLS edge.example.invalid'
                        sourceIp       = '203.0.113.10'
                        sourcePort     = '19000'
                        conversationId = $conversationId
                    }
                    [pscustomobject]@{
                        date           = '2026-05-01T14:00:25.000Z'
                        replyReason    = '180 Ringing'
                        callid         = 'demo-call-001'
                        fromUser       = '+15551230000'
                        toUser         = '+15559870000'
                        userAgent      = 'Demo Edge'
                        cseq           = '1 INVITE'
                        via1           = 'SIP/2.0/TLS edge.example.invalid'
                        conversationId = $conversationId
                    }
                    [pscustomobject]@{
                        date           = '2026-05-01T14:00:30.000Z'
                        replyReason    = '486 Busy Here'
                        callid         = 'demo-call-001'
                        fromUser       = '+15551230000'
                        toUser         = '+15559870000'
                        userAgent      = 'Demo SBC'
                        cseq           = '1 INVITE'
                        via1           = 'SIP/2.0/TLS edge.example.invalid'
                        conversationId = $conversationId
                    }
                )
            }
        }
        if ($Request.Method -eq 'POST' -and $Request.Path -eq '/api/v2/telephony/siptraces/download') {
            return [pscustomobject]@{ downloadId = 'demo-pcap-download'; documentId = 'demo-pcap-document' }
        }
        if ($Request.Method -eq 'GET' -and $Request.Path -eq '/api/v2/telephony/siptraces/download/{downloadId}') {
            return [pscustomobject]@{ url = 'https://signed.example.invalid/demo-conversation-investigation.pcap' }
        }
        throw "Unexpected demo API request: $($Request.Method) $($Request.Path)"
    }.GetNewClosure()

    $downloadInvoker = {
        param($Request)
        [byte[]](0x50, 0x43, 0x41, 0x50, 0x2d, 0x44, 0x45, 0x4d, 0x4f)
    }

    $run = Get-GenesysConversationInvestigation `
        -ConversationId $conversationId `
        -OutputRoot $tempRoot `
        -RunId 'demo-run' `
        -DatasetInvoker $datasetInvoker

    Export-GenesysConversationInvestigationPackage `
        -RunFolder $run.RunFolder `
        -OutputDirectory $OutputDirectory `
        -PackageName 'demo-conversation-investigation' `
        -ApiInvoker $apiInvoker `
        -DownloadInvoker $downloadInvoker `
        -Force:$Force
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
