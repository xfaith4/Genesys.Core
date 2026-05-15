#Requires -Version 5.1
<#
.SYNOPSIS
    Fixture-driven integration tests for the Campaign Investigation flagship.
.DESCRIPTION
    Drives Get-GenesysCampaignInvestigation through its -DatasetInvoker test seam,
    so no live API calls are required.
#>

Describe 'Campaign Investigation flagship — fixture-driven contract' {
    BeforeAll {
        $repoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $opsManifest = Join-Path $repoRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
        $script:OpsModule = Import-Module -Name $opsManifest -Force -PassThru

        $script:KnownCampaignId = 'campaign-fixture-001'

        $script:Fixture = @{
            'outbound.get.campaigns' = @(
                [pscustomobject]@{ id = 'campaign-fixture-001'; name = 'Renewals'; campaignStatus = 'on'; dialingMode = 'power'; contactListId = 'contact-list-1'; queueId = 'queue-1'; abandonRate = 3 }
                [pscustomobject]@{ id = 'campaign-fixture-999'; name = 'Other Campaign'; campaignStatus = 'off'; dialingMode = 'preview'; contactListId = 'contact-list-9'; queueId = 'queue-9'; abandonRate = 5 }
            )
            'outbound.get.contact.lists' = @(
                [pscustomobject]@{ id = 'contact-list-1'; name = 'Renewals Contacts'; size = 2000 }
                [pscustomobject]@{ id = 'contact-list-9'; name = 'Other Contacts'; size = 900 }
            )
            'routing.get.single.queue.config' = @(
                [pscustomobject]@{ id = 'queue-1'; name = 'Outbound Sales' }
                [pscustomobject]@{ id = 'queue-9'; name = 'Other Queue' }
            )
            'outbound.get.campaign.diagnostics.summary' = @(
                [pscustomobject]@{ campaignId = 'campaign-fixture-001'; health = 'healthy'; errorCount = 0 }
            )
            'outbound.get.events' = @(
                [pscustomobject]@{ id = 'event-1'; campaignId = 'campaign-fixture-001'; timestamp = '2026-05-10T12:00:00Z'; type = 'campaignStart'; callResult = $null }
                [pscustomobject]@{ id = 'event-2'; campaignId = 'campaign-fixture-001'; timestamp = '2026-05-10T12:01:00Z'; type = 'contactCallCompleted'; callResult = 'Connected' }
                [pscustomobject]@{ id = 'event-3'; campaignId = 'campaign-fixture-001'; timestamp = '2026-05-10T12:02:00Z'; type = 'contactCallAbandon'; callResult = 'OutboundAbandon' }
                [pscustomobject]@{ id = 'event-9'; campaignId = 'campaign-fixture-999'; timestamp = '2026-05-10T12:03:00Z'; type = 'contactCallCompleted'; callResult = 'Busy' }
            )
            'audit-logs' = @(
                [pscustomobject]@{ id = 'audit-1'; entityId = 'campaign-fixture-001'; entityType = 'Campaign'; action = 'UPDATE_OUTBOUND_CAMPAIGN'; timestamp = '2026-05-10T11:30:00Z' }
                [pscustomobject]@{ id = 'audit-9'; entityId = 'campaign-fixture-999'; entityType = 'Campaign'; action = 'UPDATE_OUTBOUND_CAMPAIGN'; timestamp = '2026-05-10T10:30:00Z' }
            )
            'analytics-conversation-details-query' = @(
                [pscustomobject]@{
                    conversationId = 'conv-1'
                    participants = @(
                        [pscustomobject]@{
                            purpose = 'agent'
                            userId = 'agent-1'
                            campaignId = 'campaign-fixture-001'
                            sessions = @([pscustomobject]@{ mediaType = 'voice'; segments = @([pscustomobject]@{ campaignId = 'campaign-fixture-001'; segmentType = 'interact' }) })
                        }
                    )
                }
                [pscustomobject]@{
                    conversationId = 'conv-9'
                    participants = @(
                        [pscustomobject]@{
                            purpose = 'agent'
                            userId = 'agent-9'
                            campaignId = 'campaign-fixture-999'
                        }
                    )
                }
            )
        }

        $script:MakeInvoker = {
            param($overrides = @{})
            $fixture = $script:Fixture
            return {
                param($Step, $Subject, $Window)
                $key = [string]$Step.DatasetKey
                if ($overrides.ContainsKey($key)) {
                    $entry = $overrides[$key]
                    if ($entry -is [hashtable] -and $entry.ContainsKey('Throw')) {
                        return @{ records = @(); runId = 'run-fixture-' + $Step.Name; status = 'failed'; errorMessage = [string]$entry['Throw'] }
                    }
                    return @{ records = @($entry); runId = 'run-fixture-' + $Step.Name; status = 'ok'; errorMessage = $null }
                }
                $records = if ($fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
                return @{ records = $records; runId = 'run-fixture-' + $Step.Name; status = 'ok'; errorMessage = $null }
            }.GetNewClosure()
        }

        $script:OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("campaign-inv-tests-" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:OutputRoot -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:OutputRoot) {
            Remove-Item -Path $script:OutputRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($script:OpsModule) {
            Remove-Module -Name $script:OpsModule.Name -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'happy path' {
        BeforeAll {
            $invoker = & $script:MakeInvoker @{}
            $script:HappyResult = Get-GenesysCampaignInvestigation `
                -CampaignId $script:KnownCampaignId `
                -Since ([datetime]'2026-05-01T00:00:00Z') `
                -Until ([datetime]'2026-05-12T00:00:00Z') `
                -OutputRoot $script:OutputRoot `
                -RunId 'happy-run' `
                -DatasetInvoker $invoker
        }

        It 'creates the standard run-artifact set' {
            Test-Path $script:HappyResult.ManifestPath | Should -BeTrue
            Test-Path $script:HappyResult.EventsPath | Should -BeTrue
            Test-Path $script:HappyResult.SummaryPath | Should -BeTrue
        }

        It 'manifest identifies the campaign investigation subject' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            $m.subjectType | Should -Be 'campaign'
            $m.subjectId | Should -Be $script:KnownCampaignId
            $m.investigationKey | Should -Be 'campaign-investigation'
            @($m.datasetsInvoked).Count | Should -Be 8
        }

        It 'summary contains the expected sections' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            foreach ($section in @('campaign','contactList','queue','diagnostics','outboundEvents','auditChanges','conversationAnalytics','outboundAbandons')) {
                $s.PSObject.Properties.Name | Should -Contain $section
            }
        }

        It 'filters events, audit rows, conversations, and derived abandons to the subject campaign' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.outboundEvents).Count | Should -Be 3
            @($s.outboundEvents).campaignId | Select-Object -Unique | Should -Be @($script:KnownCampaignId)
            @($s.auditChanges).Count | Should -Be 1
            $s.auditChanges[0].entityId | Should -Be $script:KnownCampaignId
            @($s.conversationAnalytics).Count | Should -Be 1
            $s.conversationAnalytics[0].conversationId | Should -Be 'conv-1'
            @($s.outboundAbandons).Count | Should -Be 1
            $s.outboundAbandons[0].campaignId | Should -Be $script:KnownCampaignId
        }
    }
}
