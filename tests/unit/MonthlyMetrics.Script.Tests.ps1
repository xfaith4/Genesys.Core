Describe 'MonthlyMetrics reporting contract' {
    BeforeAll {
        $script:MonthlyMetricsPath = Join-Path $PSScriptRoot '../../apps/MonthlyMetrics/Get-GenesysMonthlyMetrics.ps1'
        $script:MonthlyMetricsSource = Get-Content -Path $script:MonthlyMetricsPath -Raw
    }

    It 'parses cleanly' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $script:MonthlyMetricsPath),
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null

        $errors.Count | Should -Be 0
    }

    It 'defaults both Year and Month to the previous calendar month' {
        $script:MonthlyMetricsSource | Should -Match '\$Year\s+=\s+\(Get-Date\)\.AddMonths\(-1\)\.Year'
        $script:MonthlyMetricsSource | Should -Match '\$Month\s+=\s+\(Get-Date\)\.AddMonths\(-1\)\.Month'
    }

    It 'queries monthly totals by originating direction, media type, and message type' {
        $script:MonthlyMetricsSource | Should -Match "groupBy\s+=\s+@\('originatingDirection','mediaType','messageType'\)"
        $script:MonthlyMetricsSource | Should -Match "'nOffered','nAnswered','nConnected','nOutbound','nAbandoned','nAbandonedPhase'"
        $script:MonthlyMetricsSource | Should -Match "Monthly_Totals"
        $script:MonthlyMetricsSource | Should -Match "tbl_MonthlyTotals"
    }

    It 'uses originatingDirection rather than direction for conversation volume detail' {
        $script:MonthlyMetricsSource | Should -Match "groupBy\s+=\s+@\('queueId','mediaType','originatingDirection'\)"
        $script:MonthlyMetricsSource | Should -Not -Match "groupBy\s+=\s+@\('queueId','mediaType','direction'\)"
    }

    It 'queries peak concurrent voice by inbound and outbound originating direction' {
        $script:MonthlyMetricsSource | Should -Match '\[string\]\s+\$ConcurrencyGranularity\s+=\s+''PT15M'''
        $script:MonthlyMetricsSource | Should -Match "metrics\s+=\s+@\('oConcurrent'\)"
        $script:MonthlyMetricsSource | Should -Match "groupBy\s+=\s+@\('originatingDirection','mediaType'\)"
        $script:MonthlyMetricsSource | Should -Match "Peak Concurrent Voice Inbound"
        $script:MonthlyMetricsSource | Should -Match "Peak Concurrent Voice Outbound"
        $script:MonthlyMetricsSource | Should -Match "Voice_PeakConcurrent"
    }
}
