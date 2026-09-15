Describe 'Release 1.3 trend checkpoint evidence' {
    BeforeAll {
        $coreAdapterPath = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalyzer/modules/App.CoreAdapter.psm1'
        $databasePath = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalyzer/modules/App.Database.psm1'
        $readmePath = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalyzer/README.md'
        $readinessPath = Join-Path -Path $PSScriptRoot -ChildPath '../../docs/READINESS_REVIEW.md'
        $releaseEvidencePath = Join-Path -Path $PSScriptRoot -ChildPath '../../docs/RELEASE_1_3_TREND_EVIDENCE.md'

        $coreAdapter = Get-Content -Path $coreAdapterPath -Raw -ErrorAction Stop
        $database = Get-Content -Path $databasePath -Raw -ErrorAction Stop
        $readme = Get-Content -Path $readmePath -Raw -ErrorAction Stop
        $readiness = Get-Content -Path $readinessPath -Raw -ErrorAction Stop
        $releaseEvidence = Get-Content -Path $releaseEvidencePath -Raw -ErrorAction Stop
    }

    It 'keeps trend pulls routed through the Core adapter dataset contract' {
        $coreAdapter | Should -Match 'function Get-TrendReport'
        $coreAdapter | Should -Match 'analytics\.query\.conversation\.aggregates\.queue\.performance'
        $coreAdapter | Should -Match 'analytics\.query\.conversation\.aggregates\.abandon\.metrics'
        $coreAdapter | Should -Match 'analytics\.query\.queue\.aggregates\.service\.level'
        $coreAdapter | Should -Match 'must provide non-empty Start and End values'
    }

    It 'retains trend import and comparison functions with persisted trend schema artifacts' {
        $database | Should -Match 'function Import-TrendReport'
        $database | Should -Match 'function Get-TrendComparisonRows'
        $database | Should -Match 'function Get-TrendChangeLeaders'
        $database | Should -Match 'function Get-IncidentImpactSummary'
        $database | Should -Match 'function Export-IncidentImpactSummary'
        $database | Should -Match 'CREATE TABLE IF NOT EXISTS report_trend_windows'
        $database | Should -Match 'CREATE TABLE IF NOT EXISTS report_trend_comparison'
        $database | Should -Match 'CREATE VIEW report_trend_delta'
    }

    It 'documents the Trend workflow and readiness checkpoint cross-reference' {
        $readme | Should -Match '### Trend Comparison'
        $readme | Should -Match 'Export Summary'
        $readiness | Should -Match '## 10\. Release 1\.3 checkpoint — Session 20 temporal trends'
        $readiness | Should -Match 'J-01'
        $readiness | Should -Match 'J-02'
        $readiness | Should -Match 'J-03'
    }

    It 'captures fixture execution evidence and release sign-off references' {
        $readiness | Should -Match 'RELEASE_1_3_TREND_EVIDENCE\.md'
        $releaseEvidence | Should -Match 'scripts/Invoke-Tests\.ps1 -Path tests/unit'
        $releaseEvidence | Should -Match 'Invoke-Pester -Path \./tests/unit/ConversationAnalyzer\.TrendCheckpoint\.Tests\.ps1'
        $releaseEvidence | Should -Match '## Sign-off'
    }
}
