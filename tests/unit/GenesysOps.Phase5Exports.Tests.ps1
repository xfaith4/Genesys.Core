Describe 'Genesys.Ops Phase 5 export surface' {
    BeforeAll {
        $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../../modules/Genesys.Ops/Genesys.Ops.psd1'
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $exports = @($manifest.FunctionsToExport)
    }

    It 'exports all Phase 5 idea cmdlets (24-30)' {
        $expected = @(
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

        foreach ($fn in $expected) {
            $exports | Should -Contain $fn
        }
    }

    It 'does not duplicate exported function names' {
        ($exports | Select-Object -Unique).Count | Should -Be $exports.Count
    }
}
