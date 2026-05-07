#Requires -Version 5.1
<#
.SYNOPSIS
    Fixture-driven package tests for conversation investigations.
.DESCRIPTION
    Exercises Export-GenesysConversationInvestigationPackage without live Genesys
    credentials by reusing the conversation investigation -DatasetInvoker seam.
#>

Describe 'Conversation Investigation package export' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $opsManifest = Join-Path $repoRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
        $script:OpsModule = Import-Module -Name $opsManifest -Force -PassThru

        $script:ConversationId = 'conv-package-001'
        $script:OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("conv-package-tests-" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:OutputRoot -ItemType Directory -Force | Out-Null

        $script:Fixture = @{
            'analytics-conversation-details-query' = @(
                [pscustomobject]@{
                    conversationId    = $script:ConversationId
                    conversationStart = '2026-05-01T14:00:00.000Z'
                    conversationEnd   = '2026-05-01T14:08:30.000Z'
                    mediaType         = 'voice'
                    participants      = @(
                        [pscustomobject]@{
                            userId   = 'agent-package-001'
                            purpose  = 'agent'
                            sessions = @(
                                [pscustomobject]@{
                                    mediaType = 'voice'
                                    direction = 'inbound'
                                    ani       = '+15551230000'
                                    dnis      = '+15559870000'
                                    segments  = @(
                                        [pscustomobject]@{
                                            segmentStart   = '2026-05-01T14:01:00.000Z'
                                            segmentEnd     = '2026-05-01T14:05:00.000Z'
                                            segmentType    = 'interact'
                                            queueName      = 'CustomerCare'
                                            disconnectType = ''
                                        }
                                        [pscustomobject]@{
                                            segmentStart   = '2026-05-01T14:05:00.000Z'
                                            segmentEnd     = '2026-05-01T14:08:30.000Z'
                                            segmentType    = 'wrapup'
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
                [pscustomobject]@{ id = 'agent-package-001'; name = 'Package Agent'; email = 'agent@example.invalid'; state = 'ACTIVE' }
            )
            'users.division.analysis.get.users.with.division.info' = @(
                [pscustomobject]@{ id = 'agent-package-001'; division = [pscustomobject]@{ id = 'div-package'; name = 'CustomerCare' } }
            )
            'routing.get.all.routing.skills' = @(
                [pscustomobject]@{ id = 'skill-package'; name = 'Voice Support'; state = 'active' }
            )
            'conversations.get.recordings' = @(
                [pscustomobject]@{ id = 'rec-package-001'; conversationId = $script:ConversationId; mediaType = 'audio' }
            )
            'quality.get.evaluations.query' = @(
                [pscustomobject]@{
                    id           = 'eval-package-001'
                    conversation = [pscustomobject]@{ id = $script:ConversationId }
                    totalScore   = 91
                }
            )
        }

        $script:DatasetInvoker = {
            param($Step, $Subject, $Window)
            $key = [string]$Step.DatasetKey
            $records = if ($script:Fixture.ContainsKey($key)) { @($script:Fixture[$key]) } else { @() }
            return @{ records = $records; runId = 'run-fixture-' + $Step.Name; status = 'ok'; errorMessage = $null }
        }

        $script:SipTracePath = Join-Path $script:OutputRoot 'sip-trace.log'
        Set-Content -Path $script:SipTracePath -Encoding utf8 -Value @'
2026-05-01T14:00:20.000Z INVITE sip:+15559870000@example.invalid SIP/2.0
Call-ID: package-call-001
From: <sip:+15551230000@example.invalid>
To: <sip:+15559870000@example.invalid>
Contact: <sip:agent@example.invalid>
User-Agent: Fixture UA
CSeq: 1 INVITE
Via: SIP/2.0/TLS edge.example.invalid
c=IN IP4 203.0.113.10
m=audio 19000 RTP/AVP 0 8 101
a=sendrecv

2026-05-01T14:00:25.000Z SIP/2.0 486 Busy Here
Call-ID: package-call-001
From: <sip:+15551230000@example.invalid>
To: <sip:+15559870000@example.invalid>
Server: Fixture SBC
CSeq: 1 INVITE
Via: SIP/2.0/TLS edge.example.invalid
'@

        $script:Run = Get-GenesysConversationInvestigation `
            -ConversationId $script:ConversationId `
            -OutputRoot $script:OutputRoot `
            -RunId 'package-run' `
            -DatasetInvoker $script:DatasetInvoker

        $script:Package = Export-GenesysConversationInvestigationPackage `
            -RunFolder $script:Run.RunFolder `
            -SipTracePath $script:SipTracePath `
            -OutputDirectory (Join-Path $script:OutputRoot 'package') `
            -PackageName 'conversation-investigation' `
            -Force
    }

    AfterAll {
        if ($script:OpsModule) {
            Remove-Module -Name $script:OpsModule.Name -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:OutputRoot) {
            Remove-Item -Path $script:OutputRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes the expected package artifact set' {
        Test-Path $script:Package.HtmlPath        | Should -BeTrue
        Test-Path $script:Package.TimelineCsvPath | Should -BeTrue
        Test-Path $script:Package.SipTraceCsvPath | Should -BeTrue
        Test-Path $script:Package.FindingsCsvPath | Should -BeTrue
        Test-Path $script:Package.WorkbookPath    | Should -BeTrue
        Test-Path $script:Package.PackageJsonPath | Should -BeTrue
    }

    It 'produces an HTML investigation report with conversation and SIP sections' {
        $html = Get-Content -Path $script:Package.HtmlPath -Raw
        $html | Should -Match 'Conversation Investigation Package'
        $html | Should -Match ([regex]::Escape($script:ConversationId))
        $html | Should -Match 'SIP Trace Breakdown'
    }

    It 'combines conversation detail and SIP trace rows into the timeline CSV' {
        $timeline = Get-Content -Path $script:Package.TimelineCsvPath -Raw
        $timeline | Should -Match 'Conversation Detail'
        $timeline | Should -Match 'SIP Trace'
        $timeline | Should -Match 'wrapup'
    }

    It 'orders the combined timeline chronologically when SIP timestamps are available' {
        $timeline = @(Import-Csv -Path $script:Package.TimelineCsvPath)
        @($timeline | Where-Object { $_.Source -eq 'SIP Trace' -and $_.TimeUtc -eq '2026-05-01T14:00:20.0000000Z' }).Count | Should -Be 1

        $datedRows = @($timeline | Where-Object { -not [string]::IsNullOrWhiteSpace($_.TimeUtc) })
        for ($i = 1; $i -lt $datedRows.Count; $i++) {
            ([datetime]$datedRows[$i].TimeUtc) | Should -BeGreaterOrEqual ([datetime]$datedRows[$i - 1].TimeUtc)
        }
    }

    It 'captures SIP errors as findings' {
        $packageJson = Get-Content -Path $script:Package.PackageJsonPath -Raw | ConvertFrom-Json
        $packageJson.counts.sipMessages | Should -Be 2
        @($packageJson.findings | Where-Object { $_.Finding -match '486' }).Count | Should -Be 1
    }

    It 'creates a real XLSX zip container' {
        $bytes = [System.IO.File]::ReadAllBytes($script:Package.WorkbookPath)
        ([char]$bytes[0] + [char]$bytes[1]) | Should -Be 'PK'
        $bytes.Length | Should -BeGreaterThan 200
    }
}
