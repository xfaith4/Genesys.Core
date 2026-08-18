#Requires -Version 5.1
<#
.SYNOPSIS
    Fixture-driven integration tests for the Division Investigation flagship.
.DESCRIPTION
    Drives Get-GenesysDivisionInvestigation through its -DatasetInvoker test
    seam, so no live API calls are required. Asserts the same seven acceptance
    criteria used by the Agent, Conversation, and Queue Investigation suites,
    against combinations.investigationRecipes.division-investigation in
    catalog/genesys.catalog.json.
#>

Describe 'Division Investigation flagship — fixture-driven contract' {
    BeforeAll {
        $repoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $opsManifest = Join-Path $repoRoot 'modules/Genesys.Ops/Genesys.Ops.psd1'
        $script:OpsModule = Import-Module -Name $opsManifest -Force -PassThru

        $script:KnownDivisionId = 'division-fixture-001'

        # Fixture data. Records intentionally include rows for OTHER
        # divisions/queues/agents so SubjectFilter logic is exercised. The
        # queues and grants datasets are path-scoped by divisionId in the
        # live API (authorization/divisions/{divisionId}/objects|grants), so
        # — mirroring Queue Investigation's 'members' step — their fixtures
        # contain only rows for the subject division.
        $script:Fixture = @{
            'authorization.get.all.divisions' = @(
                [pscustomobject]@{ id = 'division-fixture-001'; name = 'North America'; description = 'NA operations'; homeDivision = $false }
                [pscustomobject]@{ id = 'division-fixture-999'; name = 'EMEA';          description = 'EMEA operations'; homeDivision = $false }
            )
            'authorization.list.division.queues' = @(
                [pscustomobject]@{ id = 'queue-fixture-001'; name = 'Support' }
                [pscustomobject]@{ id = 'queue-fixture-002'; name = 'Sales' }
            )
            'users.division.analysis.get.users.with.division.info' = @(
                [pscustomobject]@{ id = 'agent-fixture-001'; name = 'Jane Doe';   email = 'jane@x.com'; state = 'ACTIVE'; division = [pscustomobject]@{ id = 'division-fixture-001'; name = 'North America' } }
                [pscustomobject]@{ id = 'agent-fixture-002'; name = 'John Smith'; email = 'john@x.com'; state = 'ACTIVE'; division = [pscustomobject]@{ id = 'division-fixture-001'; name = 'North America' } }
                [pscustomobject]@{ id = 'agent-fixture-999'; name = 'Other Agt';  email = 'other@x.com'; state = 'ACTIVE'; division = [pscustomobject]@{ id = 'division-fixture-999'; name = 'EMEA' } }
            )
            'authorization.get.division.grants' = @(
                [pscustomobject]@{ subjectId = 'agent-fixture-001'; subjectType = 'PC_USER'; roleId = 'role-supervisor'; roleName = 'Supervisor'; grantMadeAt = '2026-01-15T00:00:00Z' }
            )
            'analytics.query.user.aggregates.performance.metrics' = @(
                [pscustomobject]@{ userId = 'agent-fixture-001'; nConnected = 42; tHandle = 15600; tTalk = 12100; tAcw = 3500; nOffered = 45; tAnswered = 40 }
                [pscustomobject]@{ userId = 'agent-fixture-002'; nConnected = 38; tHandle = 13900; tTalk = 10800; tAcw = 3100; nOffered = 40; tAnswered = 37 }
                [pscustomobject]@{ userId = 'agent-fixture-999'; nConnected = 12; tHandle = 4200;  tTalk = 3100;  tAcw = 900;  nOffered = 13; tAnswered = 12 }
            )
            'analytics.query.conversation.aggregates.division.performance' = @(
                [pscustomobject]@{ divisionId = 'division-fixture-001'; nConnected = 180; tHandle = 64800; tTalk = 50200; tHeld = 4100; tAcw = 14600; tAnswered = 168; nOffered = 190; nOutbound = 12; nError = 2 }
                [pscustomobject]@{ divisionId = 'division-fixture-999'; nConnected = 90;  tHandle = 32000; tTalk = 25000; tHeld = 2000; tAcw = 7000;  tAnswered = 85;  nOffered = 95;  nOutbound = 4;  nError = 1 }
            )
            'analytics.query.conversation.aggregates.queue.performance' = @(
                [pscustomobject]@{ queueId = 'queue-fixture-001'; mediaType = 'voice'; nConnected = 120; tHandle = 43200; tTalk = 33500; tAcw = 9800; tAnswered = 112; tHeld = 2600; nOffered = 125; nOutbound = 0 }
                [pscustomobject]@{ queueId = 'queue-fixture-002'; mediaType = 'voice'; nConnected = 60;  tHandle = 21600; tTalk = 16700; tAcw = 4800; tAnswered = 56;  tHeld = 1500; nOffered = 65;  nOutbound = 12 }
                [pscustomobject]@{ queueId = 'queue-fixture-999'; mediaType = 'voice'; nConnected = 30;  tHandle = 10800; tTalk = 8300;  tAcw = 2400; tAnswered = 28;  tHeld = 700;  nOffered = 32;  nOutbound = 1 }
            )
            'quality.get.evaluations.query' = @(
                [pscustomobject]@{ id = 'eval-fixture-1'; agent = [pscustomobject]@{ id = 'agent-fixture-001'; name = 'Jane Doe' };   totalScore = 92 }
                [pscustomobject]@{ id = 'eval-fixture-2'; agent = [pscustomobject]@{ id = 'agent-fixture-002'; name = 'John Smith' }; totalScore = 87 }
                [pscustomobject]@{ id = 'eval-fixture-9'; agent = [pscustomobject]@{ id = 'agent-fixture-999'; name = 'Other Agt' };  totalScore = 65 }
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
            foreach ($section in @('division','queues','agents','grants','agentPerformance','divisionPerformance','queuePerformance','qualityScores')) {
                $s.PSObject.Properties.Name | Should -Contain $section
            }
        }

        It 'seed division row is filtered to the subject' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.division).Count | Should -Be 1
            $s.division[0].id    | Should -Be $script:KnownDivisionId
        }

        It 'queues section contains the definitive division-scoped queue list' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.queues).Count | Should -Be 2
            @($s.queues).id    | Should -Contain 'queue-fixture-001'
            @($s.queues).id    | Should -Contain 'queue-fixture-002'
        }

        It 'agents section excludes agents from other divisions' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.agents).Count | Should -Be 2
            @($s.agents).id    | Should -Contain 'agent-fixture-001'
            @($s.agents).id    | Should -Contain 'agent-fixture-002'
            @($s.agents).id    | Should -Not -Contain 'agent-fixture-999'
        }

        It 'grants section contains the division-scoped grant list' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.grants).Count       | Should -Be 1
            $s.grants[0].subjectId   | Should -Be 'agent-fixture-001'
        }

        It 'agentPerformance excludes agents from other divisions' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.agentPerformance).Count  | Should -Be 2
            @($s.agentPerformance).userId | Should -Contain 'agent-fixture-001'
            @($s.agentPerformance).userId | Should -Contain 'agent-fixture-002'
            @($s.agentPerformance).userId | Should -Not -Contain 'agent-fixture-999'
        }

        It 'divisionPerformance is filtered to the subject division' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.divisionPerformance).Count      | Should -Be 1
            $s.divisionPerformance[0].divisionId | Should -Be $script:KnownDivisionId
        }

        It 'queuePerformance excludes queues from other divisions' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.queuePerformance).Count   | Should -Be 2
            @($s.queuePerformance).queueId | Should -Contain 'queue-fixture-001'
            @($s.queuePerformance).queueId | Should -Contain 'queue-fixture-002'
            @($s.queuePerformance).queueId | Should -Not -Contain 'queue-fixture-999'
        }

        It 'qualityScores excludes evaluations for agents in other divisions' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.qualityScores).Count      | Should -Be 2
            @($s.qualityScores).agent.id   | Should -Contain 'agent-fixture-001'
            @($s.qualityScores).agent.id   | Should -Contain 'agent-fixture-002'
            @($s.qualityScores).agent.id   | Should -Not -Contain 'agent-fixture-999'
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
        It 'produces byte-equivalent summary.json and data/*.jsonl across two runs' {
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

    Context '3. Missing optional step — no grants' {
        It 'still exits 0; grants section is empty; manifest records recordCount=0' {
            $invoker = & $script:MakeInvoker @{ 'authorization.get.division.grants' = @() }
            $r = Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'missing-grants' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.grants).Count | Should -Be 0

            $m = Get-Content $r.ManifestPath -Raw | ConvertFrom-Json
            $entry = $m.datasetsInvoked | Where-Object { $_.stepName -eq 'grants' }
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
            # Note: unlike the other flagships, several Division Investigation
            # dataset keys legitimately start with the catalog namespace
            # "authorization." (e.g. authorization.get.all.divisions), so a
            # bare substring match on 'Authorization' would false-positive on
            # those dataset keys. Assert against the HTTP-header/bearer-token
            # *shape* instead of the bare word.
            $eventsRaw | Should -Not -Match '(?i)Authorization\s*[:=]'
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
                'authorization.list.division.queues'                             = @()
                'users.division.analysis.get.users.with.division.info'           = @()
                'authorization.get.division.grants'                              = @()
                'analytics.query.user.aggregates.performance.metrics'            = @()
                'analytics.query.conversation.aggregates.division.performance'   = @()
                'analytics.query.conversation.aggregates.queue.performance'      = @()
                'quality.get.evaluations.query'                                  = @()
            }
            $r = Get-GenesysDivisionInvestigation -DivisionId $script:KnownDivisionId -Since ([datetime]'2026-04-01T00:00:00Z') -Until ([datetime]'2026-04-08T00:00:00Z') -OutputRoot $script:OutputRoot -RunId 'empty-aggs' -DatasetInvoker $invoker

            $s = Get-Content $r.SummaryPath -Raw | ConvertFrom-Json
            @($s.queues).Count              | Should -Be 0
            @($s.agents).Count              | Should -Be 0
            @($s.grants).Count              | Should -Be 0
            @($s.agentPerformance).Count    | Should -Be 0
            @($s.divisionPerformance).Count | Should -Be 0
            @($s.queuePerformance).Count    | Should -Be 0
            @($s.qualityScores).Count       | Should -Be 0

            # Seed (division) is independent — it must still be present.
            @($s.division).Count | Should -Be 1
        }
    }
}
