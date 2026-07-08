#Requires -Version 5.1
<#
.SYNOPSIS
    Fixture-driven integration tests for the Division Investigation flagship.
.DESCRIPTION
    Drives Get-GenesysDivisionInvestigation through its -DatasetInvoker test seam,
    so no live API calls are required. Mirrors the acceptance pattern used by
    tests/integration/QueueInvestigation.Tests.ps1.
#>

Describe 'Division Investigation flagship — fixture-driven contract' {
    BeforeAll {
        $repoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $opsManifest = Join-Path $repoRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
        $script:OpsModule = Import-Module -Name $opsManifest -Force -PassThru

        $script:KnownDivisionId = 'division-fixture-001'

        # Fixture data. Records intentionally include rows for OTHER divisions/agents
        # so SubjectFilter logic is exercised.
        $script:Fixture = @{
            'authorization.get.all.divisions' = @(
                [pscustomobject]@{ id = 'division-fixture-001'; name = 'EMEA Retail'; description = 'EMEA retail queues'; homeDivision = $false }
                [pscustomobject]@{ id = 'division-fixture-999'; name = 'APAC Wholesale'; description = 'APAC wholesale queues'; homeDivision = $false }
            )
            'authorization.search.division.objects' = @(
                [pscustomobject]@{ id = 'queue-fixture-001'; name = 'Support' }
                [pscustomobject]@{ id = 'queue-fixture-002'; name = 'Billing' }
            )
            'users.division.analysis.get.users.with.division.info' = @(
                [pscustomobject]@{ id = 'agent-1'; name = 'Jane Doe';   email = 'jane@example.com';   division = [pscustomobject]@{ id = 'division-fixture-001'; name = 'EMEA Retail' } }
                [pscustomobject]@{ id = 'agent-2'; name = 'John Smith'; email = 'john@example.com';   division = [pscustomobject]@{ id = 'division-fixture-001'; name = 'EMEA Retail' } }
                [pscustomobject]@{ id = 'agent-9'; name = 'Other Div';  email = 'other@example.com';  division = [pscustomobject]@{ id = 'division-fixture-999'; name = 'APAC Wholesale' } }
            )
            'authorization.get.division.grants' = @(
                [pscustomobject]@{ subjectId = 'agent-1'; subjectType = 'PC_USER'; roleId = 'role-supervisor'; divisionId = 'division-fixture-001' }
            )
            'analytics.query.user.aggregates.performance.metrics' = @(
                [pscustomobject]@{ userId = 'agent-1'; nConnected = 40; tHandle = 9000; tTalk = 6000; tAcw = 1200; nOffered = 42; tAnswered = 300 }
                [pscustomobject]@{ userId = 'agent-2'; nConnected = 35; tHandle = 7500; tTalk = 5200; tAcw = 900;  nOffered = 37; tAnswered = 280 }
            )
            'analytics.division.analysis.conversation.aggregates.by.division.oct.15.dec.8' = @(
                [pscustomobject]@{ divisionId = 'division-fixture-001'; nConnected = 75; tHandle = 16500; tTalk = 11200; tHeld = 900; tAcw = 2100; tAnswered = 580; nOffered = 79; nOutbound = 2; nError = 1 }
            )
            'analytics.query.conversation.aggregates.queue.performance' = @(
                [pscustomobject]@{ queueId = 'queue-fixture-001'; mediaType = 'voice'; nConnected = 50; tHandle = 11000; tTalk = 7500; tAcw = 1400; tAnswered = 380; tHeld = 600; nOffered = 53; nOutbound = 1 }
                [pscustomobject]@{ queueId = 'queue-fixture-002'; mediaType = 'voice'; nConnected = 25; tHandle = 5500;  tTalk = 3700; tAcw = 700;  tAnswered = 200; tHeld = 300; nOffered = 26; nOutbound = 1 }
            )
            'quality.get.evaluations.query' = @(
                [pscustomobject]@{ id = 'eval-1'; agent = [pscustomobject]@{ id = 'agent-1'; name = 'Jane Doe' }; totalScore = 92; totalCriticalScore = 100 }
                [pscustomobject]@{ id = 'eval-2'; agent = [pscustomobject]@{ id = 'agent-9'; name = 'Other Div' }; totalScore = 88; totalCriticalScore = 100 }
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

        $script:OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("division-inv-tests-" + [guid]::NewGuid().ToString('N'))
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
            $script:HappyResult = Get-GenesysDivisionInvestigation `
                -DivisionId $script:KnownDivisionId `
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

        It 'manifest records exactly eight datasetsInvoked entries' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            @($m.datasetsInvoked).Count | Should -Be 8
        }

        It 'manifest contains every required field' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            foreach ($f in @('investigationKey','runId','subjectType','subjectId','window','datasetsInvoked','joinPlan','redactionProfile','outputArtifacts','startedAt','finishedAt','composerVersion')) {
                $m.PSObject.Properties.Name | Should -Contain $f
            }
            $m.subjectType      | Should -Be 'division'
            $m.subjectId        | Should -Be $script:KnownDivisionId
            $m.investigationKey | Should -Be 'division-investigation'
            $m.window.since     | Should -Not -BeNullOrEmpty
            $m.window.until     | Should -Not -BeNullOrEmpty
        }

        It 'summary contains the expected sections' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            foreach ($section in @('division','queues','agents','grants','agentPerformance','conversationAggregates','queuePerformance','quality')) {
                $s.PSObject.Properties.Name | Should -Contain $section
            }
        }

        It 'seed division row is filtered to the subject' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.division).Count | Should -Be 1
            $s.division[0].id    | Should -Be $script:KnownDivisionId
        }

        It 'agents section only includes agents whose primary division matches' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.agents).Count | Should -Be 2
            @($s.agents).id | Should -Contain 'agent-1'
            @($s.agents).id | Should -Contain 'agent-2'
            @($s.agents).id | Should -Not -Contain 'agent-9'
        }

        It 'quality section only includes evaluations for in-division agents' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.quality).Count | Should -Be 1
            $s.quality[0].id    | Should -Be 'eval-1'
        }

        It 'queues section reflects the division object search results' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.queues).Count | Should -Be 2
            @($s.queues).id | Should -Contain 'queue-fixture-001'
            @($s.queues).id | Should -Contain 'queue-fixture-002'
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

            $a = Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'det-A' -DatasetInvoker $invokerA
            $b = Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'det-B' -DatasetInvoker $invokerB

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

    Context '3. Missing optional step — no agents in division' {
        It 'still exits 0; agents/quality/agentPerformance sections are empty; manifest records recordCount=0' {
            $invoker = & $script:MakeInvoker @{ 'users.division.analysis.get.users.with.division.info' = @() }
            $r = Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'missing-agents' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.agents).Count | Should -Be 0
            @($s.quality).Count | Should -Be 0

            $m = Get-Content $r.ManifestPath -Raw | ConvertFrom-Json
            $entry = $m.datasetsInvoked | Where-Object { $_.stepName -eq 'agents' }
            $entry.recordCount | Should -Be 0
            $entry.status      | Should -Be 'ok'
        }
    }

    Context '4. Required step failure aborts' {
        It 'throws, writes failure event, and does not write summary.json' {
            $invoker = & $script:MakeInvoker @{ 'authorization.get.all.divisions' = @{ Throw = 'fixture: 403 forbidden' } }
            { Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'fail-required' -DatasetInvoker $invoker } | Should -Throw

            $runFolder   = Join-Path (Join-Path $script:OutputRoot 'division-investigation') 'fail-required'
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
            $r = Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'redact-1' -DatasetInvoker $invoker
            $eventsRaw = Get-Content $r.EventsPath -Raw
            $eventsRaw | Should -Not -Match 'Authorization'
            $eventsRaw | Should -Not -Match 'Bearer\s+[A-Za-z0-9._-]+'
        }
    }

    Context '6. Manifest validity' {
        It 'manifest.json validates against catalog/schema/investigation.manifest.schema.json' {
            $invoker = & $script:MakeInvoker @{}
            $r = Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'schema-1' -DatasetInvoker $invoker

            $schemaPath  = Join-Path $repoRoot 'catalog/schema/investigation.manifest.schema.json'
            $schemaRaw   = Get-Content $schemaPath -Raw
            $manifestRaw = Get-Content $r.ManifestPath -Raw

            { $manifestRaw | Test-Json -Schema $schemaRaw -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context '7. Empty aggregates — run still succeeds' {
        It 'optional steps with zero records produce empty sections and the run exits 0' {
            $invoker = & $script:MakeInvoker @{
                'authorization.search.division.objects' = @()
                'authorization.get.division.grants' = @()
                'analytics.query.user.aggregates.performance.metrics' = @()
                'analytics.division.analysis.conversation.aggregates.by.division.oct.15.dec.8' = @()
                'analytics.query.conversation.aggregates.queue.performance' = @()
            }
            $r = Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'empty-aggs' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.queues).Count                 | Should -Be 0
            @($s.grants).Count                 | Should -Be 0
            @($s.agentPerformance).Count        | Should -Be 0
            @($s.conversationAggregates).Count | Should -Be 0
            @($s.queuePerformance).Count       | Should -Be 0

            # Seed (division) and agents are independent — division must still be present.
            @($s.division).Count | Should -Be 1
        }
    }
}
