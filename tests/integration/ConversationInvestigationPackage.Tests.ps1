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
            'conversations.get.specific.conversation.details' = @(
                [pscustomobject]@{
                    id        = $script:ConversationId
                    startTime = '2026-05-01T14:00:00.000Z'
                    endTime   = '2026-05-01T14:08:30.000Z'
                }
            )
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

        $script:ApiRequests = [System.Collections.Generic.List[object]]::new()
        $script:ApiInvoker = {
            param($Request)
            $script:ApiRequests.Add($Request) | Out-Null
            if ($Request.Method -eq 'GET' -and $Request.Path -eq '/api/v2/telephony/siptraces') {
                return [pscustomobject]@{
                    data = @(
                        [pscustomobject]@{
                            date           = '2026-05-01T14:00:20.000Z'
                            method         = 'INVITE'
                            callid         = 'package-call-001'
                            fromUser       = '+15551230000'
                            toUser         = '+15559870000'
                            userAgent      = 'Fixture UA'
                            cseq           = '1 INVITE'
                            via1           = 'SIP/2.0/TLS edge.example.invalid'
                            conversationId = $script:ConversationId
                        }
                        [pscustomobject]@{
                            date           = '2026-05-01T14:00:25.000Z'
                            replyReason    = '486 Busy Here'
                            callid         = 'package-call-001'
                            fromUser       = '+15551230000'
                            toUser         = '+15559870000'
                            userAgent      = 'Fixture SBC'
                            cseq           = '1 INVITE'
                            via1           = 'SIP/2.0/TLS edge.example.invalid'
                            conversationId = $script:ConversationId
                        }
                    )
                }
            }
            if ($Request.Method -eq 'POST' -and $Request.Path -eq '/api/v2/telephony/siptraces/download') {
                return [pscustomobject]@{ downloadId = 'pcap-download-001'; documentId = 'pcap-doc-001' }
            }
            if ($Request.Method -eq 'GET' -and $Request.Path -eq '/api/v2/telephony/siptraces/download/{downloadId}') {
                return [pscustomobject]@{ url = 'https://signed.example.invalid/package.pcap' }
            }
            throw "Unexpected API request: $($Request.Method) $($Request.Path)"
        }
        $script:DownloadInvoker = {
            param($Request)
            [byte[]](0x50, 0x43, 0x41, 0x50)
        }

        $script:Run = Get-GenesysConversationInvestigation `
            -ConversationId $script:ConversationId `
            -OutputRoot $script:OutputRoot `
            -RunId 'package-run' `
            -DatasetInvoker $script:DatasetInvoker

        $script:Package = Export-GenesysConversationInvestigationPackage `
            -RunFolder $script:Run.RunFolder `
            -OutputDirectory (Join-Path $script:OutputRoot 'package') `
            -PackageName 'conversation-investigation' `
            -ApiInvoker $script:ApiInvoker `
            -DownloadInvoker $script:DownloadInvoker `
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
        Test-Path $script:Package.PcapMetadataCsvPath | Should -BeTrue
        Test-Path $script:Package.PcapPath        | Should -BeTrue
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
        $packageJson.files.pcap | Should -Be 'conversation-investigation.pcap'
        $packageJson.files.pcapMetadataCsv | Should -Be 'conversation-investigation.pcap-metadata.csv'
        @($packageJson.findings | Where-Object { $_.Finding -match '486' }).Count | Should -Be 1
    }

    It 'requests SIP metadata and PCAP using the conversation start/end window' {
        $metadataRequest = $script:ApiRequests | Where-Object { $_.Method -eq 'GET' -and $_.Path -eq '/api/v2/telephony/siptraces' } | Select-Object -First 1
        $metadataRequest.Query.conversationId | Should -Be $script:ConversationId
        $metadataRequest.Query.dateStart | Should -Be '2026-05-01T14:00:00.0000000Z'
        $metadataRequest.Query.dateEnd | Should -Be '2026-05-01T14:08:30.0000000Z'

        $downloadRequest = $script:ApiRequests | Where-Object { $_.Method -eq 'POST' -and $_.Path -eq '/api/v2/telephony/siptraces/download' } | Select-Object -First 1
        ($downloadRequest.Body | ConvertFrom-Json).conversationId | Should -Be $script:ConversationId
    }

    It 'creates a real XLSX zip container' {
        $bytes = [System.IO.File]::ReadAllBytes($script:Package.WorkbookPath)
        ([char]$bytes[0] + [char]$bytes[1]) | Should -Be 'PK'
        $bytes.Length | Should -BeGreaterThan 200
    }
}
