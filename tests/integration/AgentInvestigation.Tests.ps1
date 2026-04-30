#Requires -Version 5.1
<#
.SYNOPSIS
    Fixture-driven integration tests for the Agent Investigation flagship.
.DESCRIPTION
    Drives Get-GenesysAgentInvestigation through its -DatasetInvoker test seam,
    so no live API calls are required. Asserts the seven acceptance criteria
    in docs/ROADMAP.md § "Acceptance tests for Agent Investigation".
#>

Describe 'Agent Investigation flagship — fixture-driven contract' {
    BeforeAll {
        $repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $opsManifest = Join-Path $repoRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
        $script:OpsModule = Import-Module -Name $opsManifest -Force -PassThru

        # Seed agent for the fixture.
        $script:KnownUserId = 'agent-fixture-001'

        # Build a fixture invoker keyed on dataset key. Records intentionally
        # contain rows for OTHER users so we exercise SubjectFilter logic.
        $script:Fixture = @{
            'users' = @(
                [pscustomobject]@{ id = 'agent-fixture-001'; name = 'Jane Doe';  email = 'jane@x.com';  state = 'ACTIVE' }
                [pscustomobject]@{ id = 'agent-fixture-999'; name = 'Other Agt'; email = 'other@x.com'; state = 'ACTIVE' }
            )
            'users.division.analysis.get.users.with.division.info' = @(
                [pscustomobject]@{ id = 'agent-fixture-001'; division = [pscustomobject]@{ id = 'div-1'; name = 'CustomerCare' } }
                [pscustomobject]@{ id = 'agent-fixture-999'; division = [pscustomobject]@{ id = 'div-2'; name = 'Sales' } }
            )
            'routing.get.all.routing.skills' = @(
                [pscustomobject]@{ id = 'sk-1'; name = 'English'; state = 'active' }
                [pscustomobject]@{ id = 'sk-2'; name = 'French';  state = 'active' }
            )
            'routing-queues' = @(
                [pscustomobject]@{
                    id = 'q-1'; name = 'Support'; memberCount = 1
                    members = @([pscustomobject]@{ id = 'agent-fixture-001' })
                }
                [pscustomobject]@{
                    id = 'q-2'; name = 'Billing'; memberCount = 1
                    members = @([pscustomobject]@{ id = 'agent-fixture-999' })
                }
            )
            'users.get.bulk.user.presences' = @(
                [pscustomobject]@{ userId = 'agent-fixture-001'; presence = 'AVAILABLE' }
                [pscustomobject]@{ userId = 'agent-fixture-999'; presence = 'OFFLINE' }
            )
            'analytics.query.user.details.activity.report' = @(
                [pscustomobject]@{ userId = 'agent-fixture-001'; loginMinutes = 420; onQueueMinutes = 340 }
            )
            'analytics-conversation-details-query' = @(
                [pscustomobject]@{
                    conversationId = 'conv-A'
                    participants = @([pscustomobject]@{ userId = 'agent-fixture-001'; role = 'agent' })
                }
                [pscustomobject]@{
                    conversationId = 'conv-B'
                    participants = @([pscustomobject]@{ userId = 'agent-fixture-001'; role = 'agent' })
                }
                [pscustomobject]@{
                    conversationId = 'conv-C'
                    participants = @([pscustomobject]@{ userId = 'agent-fixture-999'; role = 'agent' })
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

        $script:OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-inv-tests-" + [guid]::NewGuid().ToString('N'))
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

    Context '1. Happy path, full window' {
        BeforeAll {
            $invoker = & $script:MakeInvoker @{}
            $script:HappyResult = Get-GenesysAgentInvestigation `
                -UserId $script:KnownUserId `
                -Since ([datetime]'2026-04-01T00:00:00Z') `
                -Until ([datetime]'2026-04-08T00:00:00Z') `
                -OutputRoot $script:OutputRoot `
                -RunId 'happy-run' `
                -DatasetInvoker $invoker
        }

        It 'creates the standard run-artifact set' {
            Test-Path $script:HappyResult.ManifestPath | Should -BeTrue
            Test-Path $script:HappyResult.EventsPath  | Should -BeTrue
            Test-Path $script:HappyResult.SummaryPath | Should -BeTrue
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
            $m.subjectType      | Should -Be 'agent'
            $m.subjectId        | Should -Be $script:KnownUserId
            $m.investigationKey | Should -Be 'agent-investigation'
        }

        It 'summary contains the seven expected sections' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            foreach ($section in @('agent','division','skills','queues','presence','activity','conversations')) {
                $s.PSObject.Properties.Name | Should -Contain $section
            }
        }

        It 'seed identity row is filtered to the subject' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.agent).Count    | Should -Be 1
            $s.agent[0].id       | Should -Be $script:KnownUserId
            @($s.division).Count | Should -Be 1
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

            $a = Get-GenesysAgentInvestigation -UserId $script:KnownUserId -OutputRoot $script:OutputRoot -RunId 'det-A' -DatasetInvoker $invokerA
            $b = Get-GenesysAgentInvestigation -UserId $script:KnownUserId -OutputRoot $script:OutputRoot -RunId 'det-B' -DatasetInvoker $invokerB

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

    Context '3. Missing optional step' {
        It 'still exits 0; conversations section is empty; manifest records recordCount=0' {
            $invoker = & $script:MakeInvoker @{ 'analytics-conversation-details-query' = @() }
            $r = Get-GenesysAgentInvestigation -UserId $script:KnownUserId -OutputRoot $script:OutputRoot -RunId 'missing-conv' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.conversations).Count | Should -Be 0

            $m = Get-Content $r.ManifestPath -Raw | ConvertFrom-Json
            $convEntry = $m.datasetsInvoked | Where-Object { $_.stepName -eq 'conversations' }
            $convEntry.recordCount | Should -Be 0
            $convEntry.status      | Should -Be 'ok'
        }
    }

    Context '4. Required step failure aborts' {
        It 'throws, writes failure event, and does not write summary.json' {
            $invoker = & $script:MakeInvoker @{ 'users' = @{ Throw = 'fixture: 401 unauthorized' } }
            { Get-GenesysAgentInvestigation -UserId $script:KnownUserId -OutputRoot $script:OutputRoot -RunId 'fail-required' -DatasetInvoker $invoker } | Should -Throw

            $runFolder  = Join-Path (Join-Path $script:OutputRoot 'agent-investigation') 'fail-required'
            $eventsPath = Join-Path $runFolder 'events.jsonl'
            $summaryPath= Join-Path $runFolder 'summary.json'

            Test-Path $eventsPath  | Should -BeTrue
            Test-Path $summaryPath | Should -BeFalse

            $events = Get-Content $eventsPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
            ($events | Where-Object { $_.eventType -eq 'step.failed' }).Count            | Should -BeGreaterThan 0
            ($events | Where-Object { $_.eventType -eq 'investigation.failed' }).Count   | Should -BeGreaterThan 0
        }
    }

    Context '5. Redaction (no auth headers / token-shaped strings leaked)' {
        It 'events.jsonl contains no Authorization header text' {
            $invoker = & $script:MakeInvoker @{}
            $r = Get-GenesysAgentInvestigation -UserId $script:KnownUserId -OutputRoot $script:OutputRoot -RunId 'redact-1' -DatasetInvoker $invoker
            $eventsRaw = Get-Content $r.EventsPath -Raw
            $eventsRaw | Should -Not -Match 'Authorization'
            $eventsRaw | Should -Not -Match 'Bearer\s+[A-Za-z0-9._-]+'
        }
    }

    Context '6. Manifest validity' {
        It 'manifest.json validates against catalog/schema/investigation.manifest.schema.json' {
            $invoker = & $script:MakeInvoker @{}
            $r = Get-GenesysAgentInvestigation -UserId $script:KnownUserId -OutputRoot $script:OutputRoot -RunId 'schema-1' -DatasetInvoker $invoker

            $repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
            $schemaPath = Join-Path $repoRoot 'catalog/schema/investigation.manifest.schema.json'
            $schemaRaw   = Get-Content $schemaPath -Raw
            $manifestRaw = Get-Content $r.ManifestPath -Raw

            { $manifestRaw | Test-Json -Schema $schemaRaw -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context '7. Subject-by-name resolution boundary' {
        It 'manifest subjectId is the resolved GUID, never the supplied name' {
            # Stub Find-GenesysUser inside the module scope so resolution succeeds without auth.
            $resolved = [pscustomobject]@{ id = $script:KnownUserId; name = 'Jane Doe'; email = 'jane@x.com' }
            InModuleScope -ModuleName $script:OpsModule.Name -Parameters @{ resolved = $resolved } -ScriptBlock {
                param($resolved)
                Mock -CommandName 'Find-GenesysUser' -MockWith { $resolved }
                Mock -CommandName 'Assert-GenesysConnected' -MockWith { }
            }

            try {
                $invoker = & $script:MakeInvoker @{}
                $r = Get-GenesysAgentInvestigation -UserName 'Jane Doe' -OutputRoot $script:OutputRoot -RunId 'byname-1' -DatasetInvoker $invoker
                $m = Get-Content $r.ManifestPath -Raw | ConvertFrom-Json
                $m.subjectId | Should -Be $script:KnownUserId
                $m.subjectId | Should -Not -Be 'Jane Doe'
            } finally {
                # Mocks scope to the It block in Pester 5; nothing to undo.
            }
        }
    }
}
