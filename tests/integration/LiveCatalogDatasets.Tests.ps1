Describe 'Live catalog dataset validation pass' -Tag 'Integration', 'Live' {
    BeforeAll {
        $script:livePassEnabled = $env:GENESYS_LIVE_CATALOG_PASS -eq '1'
        $script:livePassScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-LiveCatalogDatasetPass.ps1'
        $script:allowedStatuses = @('Working', 'Empty', 'Unsupported', 'Needs Parameters', 'Shape Mismatch')
    }

    It 'probes every catalog dataset and emits checklist statuses when explicitly enabled' -Skip:(-not $script:livePassEnabled) {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'live-catalog-pass'
        $results = & $script:livePassScript -Region 'usw2.pure.cloud' -OutputRoot $outputRoot -PassThru

        @($results).Count | Should -BeGreaterThan 0
        foreach ($result in @($results)) {
            $script:allowedStatuses | Should -Contain $result.Status
            [string]::IsNullOrWhiteSpace([string]$result.Dataset) | Should -BeFalse
            [string]::IsNullOrWhiteSpace([string]$result.Reason) | Should -BeFalse
        }

        Test-Path (Join-Path -Path $outputRoot -ChildPath 'live-catalog-shareable-report.md') | Should -BeTrue
        Test-Path (Join-Path -Path $outputRoot -ChildPath 'live-catalog-shareable-report.json') | Should -BeTrue
        Test-Path (Join-Path -Path $outputRoot -ChildPath 'live-catalog-shareable-report.csv') | Should -BeTrue
    }
}
