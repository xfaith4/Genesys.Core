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
        # contain rows for OTHER users where the live API can still return them,
        # so we exercise SubjectFilter logic without masking scoped parameters.
        $script:Fixture = @{
            'users.get.user.details.with.full.expansion' = @(
                [pscustomobject]@{ id = 'agent-fixture-001'; name = 'Jane Doe';  email = 'jane@x.com';  state = 'ACTIVE'; division = [pscustomobject]@{ id = 'div-1'; name = 'CustomerCare' } }
                [pscustomobject]@{ id = 'agent-fixture-999'; name = 'Other Agt'; email = 'other@x.com'; state = 'ACTIVE' }
            )
            'users.get.user.routing.skills' = @(
                [pscustomobject]@{ id = 'sk-1'; userId = 'agent-fixture-001'; name = 'English'; state = 'active' }
                [pscustomobject]@{ id = 'sk-2'; userId = 'agent-fixture-001'; name = 'French';  state = 'active' }
            )
            'users.get.user.queue.memberships' = @(
                [pscustomobject]@{ id = 'q-1'; userId = 'agent-fixture-001'; name = 'Support'; joined = $true }
                [pscustomobject]@{ id = 'q-2'; userId = 'agent-fixture-001'; name = 'Billing'; joined = $true }
            )
            'users.get.bulk.user.presences' = @(
                [pscustomobject]@{ userId = 'agent-fixture-001'; presence = 'AVAILABLE' }
                [pscustomobject]@{ userId = 'agent-fixture-999'; presence = 'OFFLINE' }
            )
            'users.get.agent.current.routing.status' = @(
                [pscustomobject]@{ userId = 'agent-fixture-001'; status = 'INTERACTING'; startTime = '2026-04-02T10:15:00Z' }
                [pscustomobject]@{ userId = 'agent-fixture-999'; status = 'OFF_QUEUE'; startTime = '2026-04-02T09:00:00Z' }
            )
            'routing.get.user.utilization' = @(
                [pscustomobject]@{ userId = 'agent-fixture-001'; call = [pscustomobject]@{ maximumCapacity = 1; utilizedCapacity = 1 } }
                [pscustomobject]@{ userId = 'agent-fixture-999'; call = [pscustomobject]@{ maximumCapacity = 1; utilizedCapacity = 0 } }
            )
            'analytics.query.user.details.activity.report' = @(
                [pscustomobject]@{ userId = 'agent-fixture-001'; loginMinutes = 420; onQueueMinutes = 340 }
            )
            'users.get.agent.active.conversations' = @(
                [pscustomobject]@{ id = 'active-conv-1'; userId = 'agent-fixture-001'; mediaType = 'voice'; state = 'connected' }
                [pscustomobject]@{ id = 'active-conv-2'; userId = 'agent-fixture-001'; mediaType = 'message'; state = 'connected' }
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
            'audit-logs' = @(
                [pscustomobject]@{ id = 'audit-1'; entityId = 'agent-fixture-001'; entityType = 'User'; action = 'update'; serviceName = 'directory'; timestamp = '2026-04-02T01:00:00Z' }
            )
        }

        $script:MakeInvoker = {
            param($overrides = @{})
            if ($null -eq $overrides) { $overrides = @{} }
            $fixture = $script:Fixture
            $script:CapturedInvocations = [System.Collections.Generic.List[object]]::new()
            return {
                param($Step, $Subject, $Window)
                if ($null -eq $script:CapturedInvocations) {
                    $script:CapturedInvocations = [System.Collections.Generic.List[object]]::new()
                }
                $capturedDatasetParameters = if ($Step.ContainsKey('DatasetParameters')) { $Step['DatasetParameters'] } else { $null }
                $script:CapturedInvocations.Add([pscustomobject]@{
                    Name              = [string]$Step['Name']
                    DatasetKey        = [string]$Step['DatasetKey']
                    DatasetParameters = $capturedDatasetParameters
                    Window            = $Window
                }) | Out-Null
                $key = [string]$Step['DatasetKey']
                if ($null -ne $overrides -and $overrides.ContainsKey($key)) {
                    $entry = $overrides[$key]
                    if ($entry -is [hashtable] -and $entry.ContainsKey('Throw')) {
                        return @{ records = @(); runId = 'run-fixture-' + $Step['Name']; status = 'failed'; errorMessage = [string]$entry['Throw'] }
                    }
                    return @{ records = @($entry); runId = 'run-fixture-' + $Step['Name']; status = 'ok'; errorMessage = $null }
                }
                $records = if ($null -ne $fixture -and $fixture.ContainsKey($key)) { @($fixture[$key]) } else { @() }
                return @{ records = $records; runId = 'run-fixture-' + $Step['Name']; status = 'ok'; errorMessage = $null }
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

        It 'manifest records the scoped dataset and derived-section entries' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            @($m.datasetsInvoked).Count | Should -Be 11
        }

        It 'manifest contains every required field' {
            $m = Get-Content $script:HappyResult.ManifestPath -Raw | ConvertFrom-Json
            foreach ($f in @('investigationKey','runId','subjectType','subjectId','window','datasetsInvoked','joinPlan','redactionProfile','outputArtifacts','startedAt','finishedAt','composerVersion')) {
                $m.PSObject.Properties.Name | Should -Contain $f
            }
            $m.subjectType      | Should -Be 'agent'
            $m.subjectId        | Should -Be $script:KnownUserId
            $m.investigationKey | Should -Be 'agent-investigation'
            $divisionJoin = $m.joinPlan | Where-Object { $_.stepName -eq 'division' }
            $divisionJoin.leftSource | Should -Be 'identity'
            $divisionJoin.leftKey    | Should -Be 'agent.id'
            $divisionJoin.rightKey   | Should -Be 'userId'
        }

        It 'summary contains the expected scoped sections' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            foreach ($section in @('agent','division','skills','queues','presence','routingStatus','utilization','activity','activeConversations','conversations','auditAccountChanges')) {
                $s.PSObject.Properties.Name | Should -Contain $section
            }
        }

        It 'seed identity row is filtered to the subject' {
            $s = Get-Content $script:HappyResult.SummaryPath -Raw | ConvertFrom-Json
            @($s.agent).Count    | Should -Be 1
            $s.agent[0].id       | Should -Be $script:KnownUserId
            @($s.division).Count | Should -Be 1
        }

        It 'builds user and window scoped DatasetParameters for live dataset invocations' {
            $getMapValue = {
                param($InputObject, [string]$Name)
                if ($null -eq $InputObject) { return $null }
                if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject[$Name] }
                $prop = $InputObject.PSObject.Properties[$Name]
                if ($prop) { return $prop.Value }
                return $null
            }

            $parametersByStep = InModuleScope -ModuleName $script:OpsModule.Name -Parameters @{ KnownUserId = $script:KnownUserId } -ScriptBlock {
                param($KnownUserId)
                $subject = @{ SubjectId = $KnownUserId; UserId = $KnownUserId }
                $window = @{
                    Since = [datetime]'2026-04-01T00:00:00Z'
                    Until = [datetime]'2026-04-08T00:00:00Z'
                }
                $steps = Get-GenesysAgentInvestigationStepDefinition -UserId $KnownUserId -Since $window.Since -Until $window.Until
                $result = [ordered]@{}
                foreach ($stepName in @('identity','skills','queues','presence','routingStatus','utilization','activity','activeConversations','conversations','auditAccountChanges')) {
                    $step = $steps | Where-Object { $_['Name'] -eq $stepName } | Select-Object -First 1
                    $result[$stepName] = & $step['Parameters'] $subject @{} $window
                }
                [pscustomobject]$result
            }

            $identityQuery = & $getMapValue $parametersByStep.identity 'Query'
            $skillsQuery = & $getMapValue $parametersByStep.skills 'Query'
            $queuesQuery = & $getMapValue $parametersByStep.queues 'Query'
            $presenceQuery = & $getMapValue $parametersByStep.presence 'Query'
            $routingStatusQuery = & $getMapValue $parametersByStep.routingStatus 'Query'
            $utilizationQuery = & $getMapValue $parametersByStep.utilization 'Query'
            $activeConversationsQuery = & $getMapValue $parametersByStep.activeConversations 'Query'

            (& $getMapValue $identityQuery 'userId') | Should -Be $script:KnownUserId
            (& $getMapValue $skillsQuery 'userId') | Should -Be $script:KnownUserId
            (& $getMapValue $queuesQuery 'userId') | Should -Be $script:KnownUserId
            (& $getMapValue $presenceQuery 'id') | Should -Be $script:KnownUserId
            (& $getMapValue $routingStatusQuery 'userId') | Should -Be $script:KnownUserId
            (& $getMapValue $utilizationQuery 'userId') | Should -Be $script:KnownUserId
            (& $getMapValue $activeConversationsQuery 'userId') | Should -Be $script:KnownUserId

            $activityBody = & $getMapValue $parametersByStep.activity 'Body'
            (& $getMapValue $activityBody 'interval') | Should -Be '2026-04-01T00:00:00.0000000Z/2026-04-08T00:00:00.0000000Z'
            $activityPredicate = @((& $getMapValue (@((& $getMapValue $activityBody 'userFilters'))[0]) 'predicates'))[0]
            (& $getMapValue $activityPredicate 'dimension') | Should -Be 'userId'
            (& $getMapValue $activityPredicate 'value') | Should -Be $script:KnownUserId

            $conversationBody = & $getMapValue $parametersByStep.conversations 'Body'
            (& $getMapValue $conversationBody 'interval') | Should -Be '2026-04-01T00:00:00.0000000Z/2026-04-08T00:00:00.0000000Z'
            $conversationPredicate = @((& $getMapValue (@((& $getMapValue $conversationBody 'segmentFilters'))[0]) 'predicates'))[0]
            (& $getMapValue $conversationPredicate 'dimension') | Should -Be 'userId'
            (& $getMapValue $conversationPredicate 'value') | Should -Be $script:KnownUserId

            @((& $getMapValue $parametersByStep.auditAccountChanges 'EntityTypes'))[0] | Should -Be 'User'
            @((& $getMapValue $parametersByStep.auditAccountChanges 'EntityIds'))[0] | Should -Be $script:KnownUserId
            (& $getMapValue $parametersByStep.auditAccountChanges 'StartUtc') | Should -Be '2026-04-01T00:00:00.0000000Z'
            (& $getMapValue $parametersByStep.auditAccountChanges 'EndUtc') | Should -Be '2026-04-08T00:00:00.0000000Z'
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
            $invoker = & $script:MakeInvoker @{ 'users.get.user.details.with.full.expansion' = @{ Throw = 'fixture: 401 unauthorized' } }
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
                Mock -CommandName 'Find-GenesysUser' -MockWith {
                    [pscustomobject]@{ id = 'agent-fixture-001'; name = 'Jane Doe'; email = 'jane@x.com' }
                }
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
