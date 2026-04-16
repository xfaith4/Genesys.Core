Describe 'Genesys.Ops Phase 5 export surface' {
    BeforeAll {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../../modules/Genesys.Ops/Genesys.Ops.psd1'
        $manifest = Import-PowerShellDataFile -Path $moduleManifestPath
        $exports = @($manifest.FunctionsToExport)
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru
        $moduleSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '../../modules/Genesys.Ops/Genesys.Ops.psm1'
        $moduleSource = Get-Content -Path $moduleSourcePath -Raw
        # Roadmap ideas 24–30 are implemented by 10 exported commands
        # (idea 26 contributes multiple composite commands).
        $phase5Cmdlets = @(
            'Get-GenesysWorkforceManagementUnit',
            'Get-GenesysJourneyActionMap',
            'Get-GenesysAbandonRateDashboard',
            'Get-GenesysQueueHealthSnapshot',
            'Get-GenesysAgentQualitySnapshot',
            'Invoke-GenesysOperationsReport',
            'Get-GenesysPeakHourLoad',
            'Get-GenesysChangeAuditFeed',
            'Get-GenesysOutboundCampaignPerformance',
            'Get-GenesysFlowOutcomeKpiCorrelation'
        )
    }

    AfterAll {
        if ($null -ne $module) {
            Remove-Module -Name $module.Name -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exports the expected Phase 5 command surface' {
        foreach ($fn in $phase5Cmdlets) {
            $exports | Should -Contain $fn
        }
    }

    It 'exposes all Phase 5 idea cmdlets as importable module commands' {
        foreach ($fn in $phase5Cmdlets) {
            $cmd = Get-Command -Name $fn -Module $module.Name -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }
    }

    It 'does not duplicate exported function names' {
        ($exports | Select-Object -Unique).Count | Should -Be $exports.Count
    }

    It 'defines each expected Phase 5 command in module source' {
        foreach ($fn in $phase5Cmdlets) {
            [regex]::IsMatch($moduleSource, "(?m)^function\s+$([regex]::Escape($fn))\s*\{") | Should -BeTrue
        }
    }
}
