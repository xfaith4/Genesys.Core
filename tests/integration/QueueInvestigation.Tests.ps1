#Requires -Version 5.1
<#
.SYNOPSIS
    Fixture-driven integration tests for the Queue Investigation flagship.
.DESCRIPTION
    Drives Get-GenesysQueueInvestigation through its -DatasetInvoker test seam,
    so no live API calls are required. Asserts the seven acceptance criteria
    mirroring docs/ROADMAP.md § Release 1.2 — Queue Investigation.
#>

Describe 'Queue Investigation flagship — fixture-driven contract' {
    BeforeAll {
        $repoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $opsManifest = Join-Path $repoRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
        $script:OpsModule = Import-Module -Name $opsManifest -Force -PassThru

        $script:KnownQueueId = 'queue-fixture-001'

        # Fixture data. Records intentionally include rows for OTHER queues so
        # SubjectFilter logic is exercised.
        $script:Fixture = @{
            'routing-queues' = @(
                [pscustomobject]@{
                    id = 'queue-fixture-001'; name = 'Support'; mediaSettings = [pscustomobject]@{ call = [pscustomobject]@{ alertingTimeoutSeconds = 30 } }
                }
                [pscustomobject]@{
                    id = 'queue-fixture-999'; name = 'Sales'; mediaSettings = [pscustomobject]@{ call = [pscustomobject]@{ alertingTimeoutSeconds = 25 } }
                }
            )
            'routing-queue-members' = @(
                [pscustomobject]@{ id = 'agent-1'; queueId = 'queue-fixture-001'; name = 'Jane Doe';   joined = $true }
                [pscustomobject]@{ id = 'agent-2'; queueId = 'queue-fixture-001'; name = 'John Smith'; joined = $true }
            )
            'analytics.query.queue.observations.real.time.stats' = @(
                [pscustomobject]@{ queueId = 'queue-fixture-001'; mediaType = 'voice'; oWaiting = 3; oInteracting = 5; oOnQueueUsers = 7 }
                [pscustomobject]@{ queueId = 'queue-fixture-999'; mediaType = 'voice'; oWaiting = 1; oInteracting = 2; oOnQueueUsers = 3 }
            )
            'analytics.query.conversation.aggregates.queue.performance' = @(
                [pscustomobject]@{ queueId = 'queue-fixture-001'; mediaType = 'voice'; nOffered = 120; nAnswered = 110; tHandle = 4500 }
                [pscustomobject]@{ queueId = 'queue-fixture-999'; mediaType = 'voice'; nOffered = 60;  nAnswered = 55;  tHandle = 1800 }
            )
            'analytics.query.conversation.aggregates.abandon.metrics' = @(
                [pscustomobject]@{ queueId = 'queue-fixture-001'; nAbandoned = 4;  tAbandoned = 32; nOffered = 120 }
                [pscustomobject]@{ queueId = 'queue-fixture-999'; nAbandoned = 1;  tAbandoned = 9;  nOffered = 60 }
            )
            'analytics.query.user.observations.real.time.status' = @(
                [pscustomobject]@{ queueId = 'queue-fixture-001'; userId = 'agent-1'; oUserPresence = 'AVAILABLE' }
                [pscustomobject]@{ queueId = 'queue-fixture-001'; userId = 'agent-2'; oUserPresence = 'BUSY' }
                [pscustomobject]@{ queueId = 'queue-fixture-999'; userId = 'agent-9'; oUserPresence = 'AVAILABLE' }
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

        $script:OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("queue-inv-tests-" + [guid]::NewGuid().ToString('N'))
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
            $script:HappyResult = Get-GenesysQueueInvestigation `
                -QueueId    $script:KnownQueueId `
                -Since      ([datetime]'2026-04-01T00:00:00Z') `
                -Until      ([datetime]'2026-04-08T00:00:00Z') `
                -OutputRoot $script:OutputRoot `
                -RunId      'happy-run' `
                -DatasetInvoker $invoker
        }

        It 'creates the standard run-artifact set' {
            Test-Path $script:HappyResult.ManifestPath | Should -BeTrue
            Test-Path $script:HappyResult.EventsPath   | Should -BeTrue
            Test-Path $script:HappyResult.SummaryPath  | Should -BeTrue
        }

        It 'manifest records exactly six datasetsInvoked entries' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            @($m.datasetsInvoked).Count | Should -Be 6
        }

        It 'manifest contains every required field' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            foreach ($f in @('investigationKey','runId','subjectType','subjectId','window','datasetsInvoked','joinPlan','redactionProfile','outputArtifacts','startedAt','finishedAt','composerVersion')) {
                $m.PSObject.Properties.Name | Should -Contain $f
            }
            $m.subjectType      | Should -Be 'queue'
            $m.subjectId        | Should -Be $script:KnownQueueId
            $m.investigationKey | Should -Be 'queue-investigation'
            $m.window.since     | Should -Not -BeNullOrEmpty
            $m.window.until     | Should -Not -BeNullOrEmpty
        }

        It 'summary contains the six expected sections' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            foreach ($section in @('queue','members','observations','sla','abandons','activeAgents')) {
                $s.PSObject.Properties.Name | Should -Contain $section
            }
        }

        It 'seed queue row is filtered to the subject' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.queue).Count | Should -Be 1
            $s.queue[0].id    | Should -Be $script:KnownQueueId
        }

        It 'observations are filtered to the subject queue' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.observations).Count        | Should -Be 1
            $s.observations[0].queueId       | Should -Be $script:KnownQueueId
        }

        It 'sla and abandons are filtered to the subject queue' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.sla).Count          | Should -Be 1
            $s.sla[0].queueId        | Should -Be $script:KnownQueueId
            @($s.abandons).Count     | Should -Be 1
            $s.abandons[0].queueId   | Should -Be $script:KnownQueueId
        }

        It 'activeAgents only includes agents on the subject queue' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.activeAgents).Count | Should -Be 2
            @($s.activeAgents).userId | Should -Contain 'agent-1'
            @($s.activeAgents).userId | Should -Contain 'agent-2'
            @($s.activeAgents).userId | Should -Not -Contain 'agent-9'
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

            $a = Get-GenesysQueueInvestigation -QueueId $script:KnownQueueId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'det-A' -DatasetInvoker $invokerA
            $b = Get-GenesysQueueInvestigation -QueueId $script:KnownQueueId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'det-B' -DatasetInvoker $invokerB

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

    Context '3. Missing optional step — no members' {
        It 'still exits 0; members section is empty; manifest records recordCount=0' {
            $invoker = & $script:MakeInvoker @{ 'routing-queue-members' = @() }
            $r = Get-GenesysQueueInvestigation -QueueId $script:KnownQueueId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'missing-members' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.members).Count | Should -Be 0

            $m = Get-Content $r.ManifestPath -Raw | ConvertFrom-Json
            $entry = $m.datasetsInvoked | Where-Object { $_.stepName -eq 'members' }
            $entry.recordCount | Should -Be 0
            $entry.status      | Should -Be 'ok'
        }
    }

    Context '4. Required step failure aborts' {
        It 'throws, writes failure event, and does not write summary.json' {
            $invoker = & $script:MakeInvoker @{ 'routing-queues' = @{ Throw = 'fixture: 403 forbidden' } }
            { Get-GenesysQueueInvestigation -QueueId $script:KnownQueueId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'fail-required' -DatasetInvoker $invoker } | Should -Throw

            $runFolder   = Join-Path (Join-Path $script:OutputRoot 'queue-investigation') 'fail-required'
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
            $r = Get-GenesysQueueInvestigation -QueueId $script:KnownQueueId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'redact-1' -DatasetInvoker $invoker
            $eventsRaw = Get-Content $r.EventsPath -Raw
            $eventsRaw | Should -Not -Match 'Authorization'
            $eventsRaw | Should -Not -Match 'Bearer\s+[A-Za-z0-9._-]+'
        }
    }

    Context '6. Manifest validity' {
        It 'manifest.json validates against catalog/schema/investigation.manifest.schema.json' {
            $invoker = & $script:MakeInvoker @{}
            $r = Get-GenesysQueueInvestigation -QueueId $script:KnownQueueId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'schema-1' -DatasetInvoker $invoker

            $schemaPath  = Join-Path $repoRoot 'catalog/schema/investigation.manifest.schema.json'
            $schemaRaw   = Get-Content $schemaPath -Raw
            $manifestRaw = Get-Content $r.ManifestPath -Raw

            { $manifestRaw | Test-Json -Schema $schemaRaw -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context '7. Empty observations / aggregates — run still succeeds' {
        It 'optional steps with zero records produce empty sections and the run exits 0' {
            $invoker = & $script:MakeInvoker @{
                'analytics.query.queue.observations.real.time.stats'      = @()
                'analytics.query.conversation.aggregates.queue.performance' = @()
                'analytics.query.conversation.aggregates.abandon.metrics' = @()
                'analytics.query.user.observations.real.time.status'      = @()
            }
            $r = Get-GenesysQueueInvestigation -QueueId $script:KnownQueueId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'empty-aggs' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.observations).Count | Should -Be 0
            @($s.sla).Count          | Should -Be 0
            @($s.abandons).Count     | Should -Be 0
            @($s.activeAgents).Count | Should -Be 0

            # Seed (queue) and members are independent — queue must still be present.
            @($s.queue).Count | Should -Be 1
        }
    }
}
