#Requires -Version 5.1
<#
.SYNOPSIS
    Fixture-driven integration tests for the Conversation Investigation flagship.
.DESCRIPTION
    Drives Get-GenesysConversationInvestigation through its -DatasetInvoker test seam,
    so no live API calls are required. Asserts the seven acceptance criteria
    mirroring docs/ROADMAP.md § "Acceptance tests for Agent Investigation".
#>

Describe 'Conversation Investigation flagship — fixture-driven contract' {
    BeforeAll {
        $repoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $opsManifest = Join-Path $repoRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
        $script:OpsModule = Import-Module -Name $opsManifest -Force -PassThru

        $script:KnownConversationId = 'conv-fixture-001'
        $script:ParticipantUserId1  = 'agent-fixture-001'
        $script:ParticipantUserId2  = 'agent-fixture-002'

        # Fixture data. Records intentionally include rows for OTHER conversations/agents
        # so SubjectFilter and participant-derived filtering logic is exercised.
        $script:Fixture = @{
            'analytics-conversation-details-query' = @(
                [pscustomobject]@{
                    conversationId = 'conv-fixture-001'
                    mediaType      = 'voice'
                    participants   = @(
                        [pscustomobject]@{ userId = 'agent-fixture-001'; purpose = 'agent' }
                        [pscustomobject]@{ userId = 'agent-fixture-002'; purpose = 'agent' }
                    )
                }
                [pscustomobject]@{
                    conversationId = 'conv-fixture-999'
                    mediaType      = 'chat'
                    participants   = @(
                        [pscustomobject]@{ userId = 'agent-fixture-999'; purpose = 'agent' }
                    )
                }
            )
            'users' = @(
                [pscustomobject]@{ id = 'agent-fixture-001'; name = 'Jane Doe';   email = 'jane@x.com'; state = 'ACTIVE' }
                [pscustomobject]@{ id = 'agent-fixture-002'; name = 'John Smith'; email = 'john@x.com'; state = 'ACTIVE' }
                [pscustomobject]@{ id = 'agent-fixture-999'; name = 'Other Agt';  email = 'other@x.com'; state = 'ACTIVE' }
            )
            'users.division.analysis.get.users.with.division.info' = @(
                [pscustomobject]@{ id = 'agent-fixture-001'; division = [pscustomobject]@{ id = 'div-1'; name = 'CustomerCare' } }
                [pscustomobject]@{ id = 'agent-fixture-002'; division = [pscustomobject]@{ id = 'div-1'; name = 'CustomerCare' } }
                [pscustomobject]@{ id = 'agent-fixture-999'; division = [pscustomobject]@{ id = 'div-2'; name = 'Sales' } }
            )
            'routing.get.all.routing.skills' = @(
                [pscustomobject]@{ id = 'sk-1'; name = 'English'; state = 'active' }
                [pscustomobject]@{ id = 'sk-2'; name = 'French';  state = 'active' }
            )
            'conversations.get.recordings' = @(
                [pscustomobject]@{ id = 'rec-1'; conversationId = 'conv-fixture-001'; mediaType = 'audio' }
                [pscustomobject]@{ id = 'rec-2'; conversationId = 'conv-fixture-999'; mediaType = 'audio' }
            )
            'quality.get.evaluations.query' = @(
                [pscustomobject]@{
                    id           = 'eval-1'
                    conversation = [pscustomobject]@{ id = 'conv-fixture-001' }
                    totalScore   = 92
                }
                [pscustomobject]@{
                    id           = 'eval-2'
                    conversation = [pscustomobject]@{ id = 'conv-fixture-999' }
                    totalScore   = 75
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

        $script:OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("conv-inv-tests-" + [guid]::NewGuid().ToString('N'))
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

    Context '1. Happy path' {
        BeforeAll {
            $invoker = & $script:MakeInvoker @{}
            $script:HappyResult = Get-GenesysConversationInvestigation `
                -ConversationId $script:KnownConversationId `
                -OutputRoot     $script:OutputRoot `
                -RunId          'happy-run' `
                -DatasetInvoker $invoker
        }

        It 'creates the standard run-artifact set' {
            Test-Path $script:HappyResult.ManifestPath | Should -BeTrue
            Test-Path $script:HappyResult.EventsPath   | Should -BeTrue
            Test-Path $script:HappyResult.SummaryPath  | Should -BeTrue
        }

        It 'manifest records exactly seven datasetsInvoked entries' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            @($m.datasetsInvoked).Count | Should -Be 7
        }

        It 'manifest contains every required field' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            foreach ($f in @('investigationKey','runId','subjectType','subjectId','window','datasetsInvoked','joinPlan','redactionProfile','outputArtifacts','startedAt','finishedAt','composerVersion')) {
                $m.PSObject.Properties.Name | Should -Contain $f
            }
            $m.subjectType      | Should -Be 'conversation'
            $m.subjectId        | Should -Be $script:KnownConversationId
            $m.investigationKey | Should -Be 'conversation-investigation'
            $m.window.since     | Should -BeNullOrEmpty
            $m.window.until     | Should -BeNullOrEmpty
        }

        It 'summary contains the seven expected sections' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            foreach ($section in @('conversation','participants','agents','divisions','skills','recordings','evaluations')) {
                $s.PSObject.Properties.Name | Should -Contain $section
            }
        }

        It 'seed conversation row is filtered to the subject' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.conversation).Count              | Should -Be 1
            $s.conversation[0].conversationId     | Should -Be $script:KnownConversationId
        }

        It 'participants section contains only the agents on this conversation' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.participants).Count | Should -Be 2
            @($s.participants).userId | Should -Contain $script:ParticipantUserId1
            @($s.participants).userId | Should -Contain $script:ParticipantUserId2
        }

        It 'agents section contains only agents who were participants' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.agents).Count | Should -Be 2
            @($s.agents).id    | Should -Contain $script:ParticipantUserId1
            @($s.agents).id    | Should -Contain $script:ParticipantUserId2
            @($s.agents).id    | Should -Not -Contain 'agent-fixture-999'
        }

        It 'recordings section contains only recordings for this conversation' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.recordings).Count                    | Should -Be 1
            $s.recordings[0].conversationId           | Should -Be $script:KnownConversationId
        }

        It 'evaluations section contains only evaluations for this conversation' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.evaluations).Count                   | Should -Be 1
            $s.evaluations[0].conversation.id         | Should -Be $script:KnownConversationId
        }

        It 'data/*.jsonl line counts match manifest recordCount per step' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            foreach ($entry in $m.datasetsInvoked) {
                $path = (Join-Path $script:HappyResult.DataFolder ("$($entry.stepName).jsonl"))
                $lines = if (Test-Path $path) { @(Get-Content $path | Where-Object { $_.Trim() }) } else { @() }
                $lines.Count | Should -Be $entry.recordCount
            }
        }
    }

    Context '2. Determinism' {
        It 'produces byte-equivalent summary.json and data/*.jsonl across two runs (after stripping runId & timestamps)' {
            $invokerA = & $script:MakeInvoker @{}
            $invokerB = & $script:MakeInvoker @{}

            $a = Get-GenesysConversationInvestigation -ConversationId $script:KnownConversationId -OutputRoot $script:OutputRoot -RunId 'det-A' -DatasetInvoker $invokerA
            $b = Get-GenesysConversationInvestigation -ConversationId $script:KnownConversationId -OutputRoot $script:OutputRoot -RunId 'det-B' -DatasetInvoker $invokerB

            (Get-Content $a.SummaryPath -Raw) | Should -Be (Get-Content $b.SummaryPath -Raw)

            $aFiles = Get-ChildItem $a.DataFolder -Filter '*.jsonl' | Sort-Object Name
            $bFiles = Get-ChildItem $b.DataFolder -Filter '*.jsonl' | Sort-Object Name
            $aFiles.Count | Should -Be $bFiles.Count
            for ($i = 0; $i -lt $aFiles.Count; $i++) {
                $aFiles[$i].Name | Should -Be $bFiles[$i].Name
                (Get-Content $aFiles[$i].FullName -Raw) | Should -Be (Get-Content $bFiles[$i].FullName -Raw)
            }
        }
    }

    Context '3. Missing optional step — no recordings' {
        It 'still exits 0; recordings section is empty; manifest records recordCount=0' {
            $invoker = & $script:MakeInvoker @{ 'conversations.get.recordings' = @() }
            $r = Get-GenesysConversationInvestigation -ConversationId $script:KnownConversationId -OutputRoot $script:OutputRoot -RunId 'missing-rec' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.recordings).Count | Should -Be 0

            $m = Get-Content $r.ManifestPath -Raw | ConvertFrom-Json
            $recEntry = $m.datasetsInvoked | Where-Object { $_.stepName -eq 'recordings' }
            $recEntry.recordCount | Should -Be 0
            $recEntry.status      | Should -Be 'ok'
        }
    }

    Context '4. Required step failure aborts' {
        It 'throws, writes failure event, and does not write summary.json' {
            $invoker = & $script:MakeInvoker @{ 'analytics-conversation-details-query' = @{ Throw = 'fixture: 403 forbidden' } }
            { Get-GenesysConversationInvestigation -ConversationId $script:KnownConversationId -OutputRoot $script:OutputRoot -RunId 'fail-required' -DatasetInvoker $invoker } | Should -Throw

            $runFolder   = Join-Path (Join-Path $script:OutputRoot 'conversation-investigation') 'fail-required'
            $eventsPath  = Join-Path $runFolder 'events.jsonl'
            $summaryPath = Join-Path $runFolder 'summary.json'

            Test-Path $eventsPath  | Should -BeTrue
            Test-Path $summaryPath | Should -BeFalse

            $events = Get-Content $eventsPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
            ($events | Where-Object { $_.eventType -eq 'step.failed' }).Count          | Should -BeGreaterThan 0
            ($events | Where-Object { $_.eventType -eq 'investigation.failed' }).Count | Should -BeGreaterThan 0
        }
    }

    Context '5. Redaction (no auth headers / token-shaped strings leaked)' {
        It 'events.jsonl contains no Authorization header text' {
            $invoker = & $script:MakeInvoker @{}
            $r = Get-GenesysConversationInvestigation -ConversationId $script:KnownConversationId -OutputRoot $script:OutputRoot -RunId 'redact-1' -DatasetInvoker $invoker
            $eventsRaw = Get-Content $r.EventsPath -Raw
            $eventsRaw | Should -Not -Match 'Authorization'
            $eventsRaw | Should -Not -Match 'Bearer\s+[A-Za-z0-9._-]+'
        }
    }

    Context '6. Manifest validity' {
        It 'manifest.json validates against catalog/schema/investigation.manifest.schema.json' {
            $invoker = & $script:MakeInvoker @{}
            $r = Get-GenesysConversationInvestigation -ConversationId $script:KnownConversationId -OutputRoot $script:OutputRoot -RunId 'schema-1' -DatasetInvoker $invoker

            $schemaPath  = Join-Path $repoRoot 'catalog/schema/investigation.manifest.schema.json'
            $schemaRaw   = Get-Content $schemaPath -Raw
            $manifestRaw = Get-Content $r.ManifestPath -Raw

            { $manifestRaw | Test-Json -Schema $schemaRaw -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context '7. No participants — derived step returns empty array; run exits 0' {
        It 'participants section is empty and dependent steps are empty when conversation has no participant userIds' {
            # Return a conversation record that has participants with no userId fields.
            $noUserConv = [pscustomobject]@{
                conversationId = 'conv-fixture-001'
                mediaType      = 'voice'
                participants   = @([pscustomobject]@{ purpose = 'customer' })  # no userId
            }
            $invoker = & $script:MakeInvoker @{ 'analytics-conversation-details-query' = $noUserConv }
            $r = Get-GenesysConversationInvestigation -ConversationId $script:KnownConversationId -OutputRoot $script:OutputRoot -RunId 'no-participants' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.participants).Count | Should -Be 0
            @($s.agents).Count       | Should -Be 0
            @($s.divisions).Count    | Should -Be 0
        }
    }
}
