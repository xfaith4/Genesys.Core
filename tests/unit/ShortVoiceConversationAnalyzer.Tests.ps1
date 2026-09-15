Describe 'Short Voice Conversation Analyzer' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $modulePath = Join-Path $repoRoot 'apps/ConversationAnalyzer/modules/App.ShortVoice.psm1'
        Import-Module $modulePath -Force
        $script:FixturePath = Join-Path $repoRoot 'tests/fixtures/short-voice/conversations.jsonl'
    }

    It 'calculates duration from conversation start/end deterministically' {
        $record = [pscustomobject]@{
            conversationStart = '2026-05-10T10:00:00.000Z'
            conversationEnd = '2026-05-10T10:00:03.000Z'
        }
        $duration = Get-ShortVoiceDuration -Conversation $record
        $duration.IsValid | Should -BeTrue
        $duration.DurationSeconds | Should -Be 3
        $duration.Method | Should -Be 'conversationStart-conversationEnd'
    }

    It 'builds summary, threshold filtering, and direction rollups correctly' {
        $runFolder = Join-Path $TestDrive 'run-a'
        $dataDir = Join-Path $runFolder 'data'
        New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
        Copy-Item -Path $script:FixturePath -Destination (Join-Path $dataDir 'analytics-conversation-details.jsonl')

        $result = Invoke-ShortVoiceConversationPostProcess -RunFolder $runFolder -ThresholdSeconds 5 -Directions @('inbound','outbound') -ExportJson -ExportMarkdown -ExportCsv

        $result.Summary.TotalVoiceConversationsScanned | Should -Be 6
        $result.Summary.TotalShortVoiceConversations | Should -Be 3
        $result.Summary.InboundShortCount | Should -Be 2
        $result.Summary.OutboundShortCount | Should -Be 1

        # exactly 5 seconds must be excluded for '< threshold' logic
        (@($result.PreviewDetails | Where-Object { $_.ConversationId -eq 'conv-inbound-5s' })).Count | Should -Be 0

        # missing end conversation is excluded by default
        $result.Summary.MissingEndTimeCount | Should -Be 1
        $result.Summary.ExcludedIncompleteConversationCount | Should -Be 1

        $queueRollup = @($result.Rollup.ByQueue | Where-Object { $_.Key -eq 'Support A' })
        $queueRollup.Count | Should -BeGreaterThan 0
        $queueRollup[0].Count | Should -Be 1

        Test-Path $result.SummaryPath | Should -BeTrue
        Test-Path $result.RollupPath | Should -BeTrue
        Test-Path $result.DetailPath | Should -BeTrue
        Test-Path $result.MarkdownPath | Should -BeTrue
    }

    It 'supports include incomplete mode without counting incomplete as short' {
        $runFolder = Join-Path $TestDrive 'run-b'
        $dataDir = Join-Path $runFolder 'data'
        New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
        Copy-Item -Path $script:FixturePath -Destination (Join-Path $dataDir 'analytics-conversation-details.jsonl')

        $result = Invoke-ShortVoiceConversationPostProcess -RunFolder $runFolder -ThresholdSeconds 5 -Directions @('inbound','outbound') -IncludeIncompleteConversations -ExportJson

        $result.Summary.TotalVoiceConversationsScanned | Should -Be 7
        $result.Summary.TotalShortVoiceConversations | Should -Be 3
    }

    It 'creates deterministic elastic document ids and dry-run payload output' {
        $runFolder = Join-Path $TestDrive 'run-c'
        $dataDir = Join-Path $runFolder 'data'
        New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
        Copy-Item -Path $script:FixturePath -Destination (Join-Path $dataDir 'analytics-conversation-details.jsonl')

        $analysis = Invoke-ShortVoiceConversationPostProcess -RunFolder $runFolder -ThresholdSeconds 5 -Directions @('inbound','outbound') -ExportJson

        $context = [ordered]@{
            Timestamp = [DateTime]::UtcNow.ToString('o')
            OrgName = 'TestOrg'
            OrgId = 'org-1'
            Region = 'usw2.pure.cloud'
            RunId = 'run-c'
            IntervalStart = '2026-05-10T10:00:00.000Z'
            IntervalEnd = '2026-05-10T11:00:00.000Z'
            SourceArtifactPath = $runFolder
            AppVersion = 'test'
            ModuleVersion = 'test'
        }

        $docs = New-ShortVoiceElasticDocuments -Summary $analysis.Summary -Rollup $analysis.Rollup -Context $context
        @($docs).Count | Should -BeGreaterThan 5

        $id1 = Get-ShortVoiceDeterministicId -RunId 'run-c' -DocumentType 'queue_rollup' -DimensionKey 'Support A'
        $id2 = Get-ShortVoiceDeterministicId -RunId 'run-c' -DocumentType 'queue_rollup' -DimensionKey 'Support A'
        $id1 | Should -Be $id2

        $publish = Publish-ShortVoiceElasticRollups -RunFolder $runFolder -ElasticConfig @{ IndexName = 'genesys-short-voice-conversations-rollup'; UseDailyIndexSuffix = $true; DryRun = $true } -Documents $docs -DryRun
        $publish.DryRun | Should -BeTrue
        Test-Path $publish.BulkPayloadPath | Should -BeTrue
    }
}
