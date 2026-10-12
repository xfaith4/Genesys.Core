BeforeAll {
    Import-Module "$PSScriptRoot/../../modules/Genesys.Ops/Genesys.Ops.psd1" -Force
    function New-VoiceRecord($Id, $Media = 'voice') {
        return @{ conversationId = $Id; participants = @(@{ sessions = @(@{ mediaType = $Media }) }) }
    }
    function New-AggregateRecord($Count) {
        return @{ group = @{ mediaType = 'voice' }; data = @(@{ interval = '2026-09-01T00:00:00Z/2026-10-01T00:00:00Z'; metrics = @(@{ metric = 'nOffered'; stats = @{ count = $Count } }) }) }
    }
    $script:EqualInvoker = {
        param($Dataset, $Body, $OutputRoot)
        $records = if ($Dataset -like '*aggregates*') { @(New-AggregateRecord 2) } else { @(New-VoiceRecord 'a'; New-VoiceRecord 'b') }
        return @{ Records = $records; Status = 'complete'; Events = @() }
    }
}
Describe 'Monthly voice volume reconciliation' {
    It 'exports the shared Ops command' {
        Get-Command Compare-GenesysMonthlyVoiceVolume | Should -Not -BeNullOrEmpty
    }
    It 'retains four sources and labels matching unlike measures as non-equivalent' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -DatasetInvoker $script:EqualInvoker
        $report.sources.Count | Should -Be 4
        @($report.sources | Where-Object status -ne complete).Count | Should -Be 0
        $report.evidenceMode | Should -Be 'synthetic'
        $comparison = $report.comparisons | Where-Object { $_.baselineSource -eq 'details-query' -and $_.comparedSource -eq 'aggregates-query' -and $_.comparedDefinition -eq 'nOffered.count' }
        $comparison.status | Should -Be 'equal'
        $comparison.equivalentDefinition | Should -BeFalse
        Test-Path (Join-Path $report.runFolder 'report.html') | Should -BeTrue
        Test-Path (Join-Path $report.runFolder 'manifest.json') | Should -BeTrue
        Test-Path (Join-Path $report.runFolder 'events.jsonl') | Should -BeTrue
        $saved = Get-Content (Join-Path $report.runFolder 'summary.json') -Raw | ConvertFrom-Json
        $saved.sources.Count | Should -Be 4
        @($saved.measures | Where-Object { $_.definition -eq 'nConnected.count' -and $null -eq $_.value }).Count | Should -Be 2
    }
    It 'highlights differences, deduplicates voice IDs and ignores digital-only conversations' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset, $Body, $OutputRoot)
            $records = if ($Dataset -like '*aggregates*') { @(New-AggregateRecord 5) }
            elseif ($Dataset -eq 'analytics-conversation-details-query') { @(New-VoiceRecord 'a'; New-VoiceRecord 'a'; New-VoiceRecord 'b'; New-VoiceRecord 'digital' 'message') }
            else { @(New-VoiceRecord 'b'; New-VoiceRecord 'c') }
            return @{ Records = $records; Status = 'complete'; Events = @() }
        }
        $report.sources[0].distinctConversations | Should -Be 2
        $report.sources[0].duplicateVoiceRows | Should -Be 1
        $report.detailIdComparison.onlyDetailsQuery | Should -Be @('a')
        $report.detailIdComparison.onlyDetailsJobs | Should -Be @('c')
        $comparison = $report.comparisons | Where-Object { $_.baselineSource -eq 'details-query' -and $_.comparedSource -eq 'aggregates-query' -and $_.comparedDefinition -eq 'nOffered.count' }
        $comparison.difference | Should -Be 3
        $comparison.percentOfBaseline | Should -Be 150
        $comparison.status | Should -Be 'different'
    }
    It 'preserves a failed source as unavailable rather than zero' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset, $Body, $OutputRoot)
            if ($Dataset -eq 'analytics-conversation-details') { throw '403 forbidden secret-value' }
            return @{ Records = @(); Status = 'complete'; Events = @() }
        }
        $report.sources[1].status | Should -Be 'unavailable'
        $report.measures[1].value | Should -BeNullOrEmpty
        $report.detailIdComparison.coverage | Should -Be 'partial'
        (Get-Content (Join-Path $report.runFolder 'summary.json') -Raw) | Should -Not -Match 'secret-value'
    }
    It 'marks safety termination and missing IDs as partial' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset, $Body, $OutputRoot)
            return @{ Records = @(New-VoiceRecord ''); Status = 'complete'; Events = @(@{ eventType = 'paging.terminated.maxPages' }) }
        }
        $report.sources[0].status | Should -Be 'partial'
        $report.sources[0].missingConversationIds | Should -Be 1
        $report.comparisons[0].status | Should -Be 'partial'
    }
    It 'does not divide by zero or coerce missing aggregate metrics to zero' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset, $Body, $OutputRoot)
            return @{ Records = @(); Status = 'complete'; Events = @() }
        }
        $report.comparisons[0].difference | Should -Be 0
        $report.comparisons[0].percentOfBaseline | Should -BeNullOrEmpty
        $report.measures[2].value | Should -BeNullOrEmpty
    }
    It 'converts a DST month with different start and end offsets' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 3 -TimeZoneId 'America/New_York' -OutputRoot $TestDrive -DatasetInvoker $script:EqualInvoker
        $report.scope.interval | Should -Be '2026-03-01T05:00:00.0000000Z/2026-04-01T04:00:00.0000000Z'
    }
    It 'retains ambiguous aggregate series without summing their counts' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset, $Body, $OutputRoot)
            return @{ Records = @(New-AggregateRecord 2; New-AggregateRecord 3); Status = 'complete'; Events = @() }
        }
        $report.sources[2].metricStatistics.Count | Should -Be 2
        $report.measures[2].value | Should -BeNullOrEmpty
    }
}
Describe 'Four sources through actual Core execution' {
    It 'pages nested detail requests and cursor-pages both async sources' {
        $requests = [System.Collections.Generic.List[object]]::new()
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -RequestInvoker {
            param($request)
            $requests.Add($request)
            $uri = [string]$request.Uri
            $payload = $null
            if ($uri -match '/details/query$') {
                $body = $request.Body | ConvertFrom-Json
                $id = if ($body.paging.pageNumber -eq 1) { 'a' } else { 'b' }
                $payload = @{ conversations = @(New-VoiceRecord $id); totalHits = 2 }
            }
            elseif ($uri -match '/(details|aggregates)/jobs$') { $payload = @{ jobId = 'job-1' } }
            elseif ($uri -match '/jobs/job-1$') { $payload = @{ state = 'FULFILLED' } }
            elseif ($uri -match '/details/jobs/job-1/results') {
                $payload = if ($uri -match 'cursor=') { @{ conversations = @(New-VoiceRecord 'c') } } else { @{ conversations = @(New-VoiceRecord 'b'); cursor = 'next' } }
            }
            elseif ($uri -match '/aggregates/jobs/job-1/results') {
                if ($uri -match 'cursor=') {
                    $payload = @{ results = @(@{ group = @{ mediaType = 'voice' }; data = @(@{ interval = 'month'; metrics = @(@{ metric = 'nConnected'; stats = @{ count = 3 } }) }) }) }
                }
                else { $payload = @{ results = @(New-AggregateRecord 4); cursor = 'aggregate-next' } }
            }
            elseif ($uri -match '/aggregates/query$') { $payload = @{ results = @(New-AggregateRecord 3) } }
            else { throw "Unexpected request: $uri" }
            # Match deserialized HTTP response objects, not in-memory hashtable records.
            return [pscustomobject]@{ Result = ($payload | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }
        }
        @($report.sources | Where-Object status -ne complete).Count | Should -Be 0
        $report.sources[0].pageCount | Should -Be 2
        $report.sources[1].pageCount | Should -Be 2
        $report.sources[3].pageCount | Should -Be 2
        $report.sources[0].distinctConversations | Should -Be 2
        $report.sources[3].metricStatistics.Count | Should -Be 2
        $report.detailIdComparison.onlyDetailsQuery | Should -Be @('a')
        $report.detailIdComparison.onlyDetailsJobs | Should -Be @('c')
        $bodies = @($requests | Where-Object { $_.Uri -match '/details/query$' } | ForEach-Object { $_.Body | ConvertFrom-Json })
        $bodies[0].paging.pageNumber | Should -Be 1
        $bodies[1].paging.pageNumber | Should -Be 2
        $bodies[0].PSObject.Properties.Name | Should -Not -Contain 'pageNumber'
        $aggregateCalls = @($requests | Where-Object { $_.Uri -match '/aggregates/(jobs|query)$' } | ForEach-Object { $_.Body | ConvertFrom-Json })
        $aggregateCalls[0].interval | Should -Be $aggregateCalls[1].interval
    }
}
Describe 'Source scope and incomplete population evidence' {
    It 'records queue and Division predicates in each source-specific request' {
        $bodies = [System.Collections.Generic.List[object]]::new()
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -DivisionId 'division-a' -QueueId 'queue-a' -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset, $Body, $OutputRoot)
            $bodies.Add($Body)
            return @{ Records = @(); Events = @(); Status = 'complete' }
        }
        $bodies[0].conversationFilters[0].predicates[0].value | Should -Be 'division-a'
        $bodies[0].segmentFilters[1].predicates[0].value | Should -Be 'queue-a'
        $bodies[2].filter.clauses[2].predicates[0].value | Should -Be 'division-a'
        $bodies[2].interval | Should -Be $bodies[0].interval
        $report.scope.organizationVerified | Should -BeFalse
    }
    It 'does not call premature empty-page retrieval complete' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset, $Body, $OutputRoot)
            return @{ Records = @(New-VoiceRecord 'a'); Status = 'complete'; Events = @(@{ eventType = 'paging.progress'; itemCount = 0; totalHits = 2; profile = 'bodyPaging' }) }
        }
        $report.sources[0].status | Should -Be 'partial'
    }
    It 'marks repeated cursor evidence partial' {
        $report = Compare-GenesysMonthlyVoiceVolume -Year 2026 -Month 9 -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset, $Body, $OutputRoot)
            return @{ Records = @(); Status = 'complete'; Events = @(@{ eventType = 'paging.terminated.duplicateCursor' }) }
        }
        $report.sources[3].status | Should -Be 'partial'
    }
}
