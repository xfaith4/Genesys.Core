#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for Invoke-GenesysNotRespondingReport auto-answer scoping and the
    daily-recurrence pattern flag (no live API required).
.DESCRIPTION
    Mocks the connection assertion, the agent roster, and the user-details dataset so
    the report aggregation can be exercised deterministically. Fixture:
      User A — NOT_RESPONDING on all 7 window days, acdAutoAnswer = true
      User B — NOT_RESPONDING on 2 days,          acdAutoAnswer = true
      User C — NOT_RESPONDING on all 7 days,       acdAutoAnswer = false
#>

BeforeAll {
    $script:ModuleManifestPath = Join-Path $PSScriptRoot '../../modules/Genesys.Ops/Genesys.Ops.psd1'
    $script:OpsModule = Import-Module -Name $script:ModuleManifestPath -Force -PassThru

    # Fixed window so day buckets are deterministic.
    $script:Until = [datetime]::SpecifyKind([datetime]'2026-06-04T12:00:00', [System.DateTimeKind]::Utc)
    $script:Since = $script:Until.AddDays(-7)
    # Seven distinct UTC days inside the window (since+1h .. since+6d+1h).
    $script:NrDays = 0..6 | ForEach-Object { $script:Since.AddDays($_).AddHours(1) }
}

AfterAll {
    if ($script:OpsModule) {
        Remove-Module -Name $script:OpsModule.Name -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-GenesysNotRespondingReport — auto-answer scoping and daily pattern' {

    BeforeEach {
        InModuleScope 'Genesys.Ops' -Parameters @{ NrDays = $script:NrDays } {
            param($NrDays)

            function script:New-NrUserRecord {
                param([string]$Id, [datetime[]]$Days)
                $segs = foreach ($d in $Days) {
                    [pscustomobject]@{
                        routingStatus = 'NOT_RESPONDING'
                        startTime     = $d.ToString('o')
                        endTime       = $d.AddMinutes(2).ToString('o')
                    }
                }
                [pscustomobject]@{ userId = $Id; routingStatusDetail = @($segs) }
            }

            $script:UserDetailsFixture = @(
                New-NrUserRecord -Id 'A' -Days $NrDays
                New-NrUserRecord -Id 'B' -Days $NrDays[0..1]
                New-NrUserRecord -Id 'C' -Days $NrDays
            )

            $script:RosterFixture = @(
                [pscustomobject]@{ id = 'A'; name = 'Agent A'; state = 'ACTIVE'; acdAutoAnswer = $true;  division = [pscustomobject]@{ name = 'Div1' } }
                [pscustomobject]@{ id = 'B'; name = 'Agent B'; state = 'ACTIVE'; acdAutoAnswer = $true;  division = [pscustomobject]@{ name = 'Div1' } }
                [pscustomobject]@{ id = 'C'; name = 'Agent C'; state = 'ACTIVE'; acdAutoAnswer = $false; division = [pscustomobject]@{ name = 'Div2' } }
            )

            Mock Assert-GenesysConnected { }
            Mock Get-GenesysAgent { $script:RosterFixture }
            Mock Invoke-GenesysDataset { $script:UserDetailsFixture } -ParameterFilter { $Dataset -eq 'analytics.post.users.details.jobs' }
        }
    }

    It 'computes DaysWithNotResponding per user (distinct NR days)' {
        InModuleScope 'Genesys.Ops' -Parameters @{ Since = $script:Since; Until = $script:Until } {
            param($Since, $Until)
            $report = Invoke-GenesysNotRespondingReport -Since $Since -Until $Until
            ($report.AllUsers | Where-Object UserId -eq 'A').DaysWithNotResponding | Should -Be 7
            ($report.AllUsers | Where-Object UserId -eq 'B').DaysWithNotResponding | Should -Be 2
        }
    }

    It 'excludes non auto-answer agents when -AutoAnswerEnabledOnly is set' {
        InModuleScope 'Genesys.Ops' -Parameters @{ Since = $script:Since; Until = $script:Until } {
            param($Since, $Until)
            $report = Invoke-GenesysNotRespondingReport -Since $Since -Until $Until -AutoAnswerEnabledOnly
            @($report.AllUsers).UserId | Should -Not -Contain 'C'
            @($report.AllUsers).UserId | Should -Contain 'A'
            @($report.AllUsers).UserId | Should -Contain 'B'
            ($report.AllUsers | Where-Object UserId -eq 'A').AcdAutoAnswer | Should -BeTrue
        }
    }

    It 'flags only every-day agents with DailyPattern = Daily at the window threshold' {
        InModuleScope 'Genesys.Ops' -Parameters @{ Since = $script:Since; Until = $script:Until } {
            param($Since, $Until)
            $report = Invoke-GenesysNotRespondingReport -Since $Since -Until $Until -AutoAnswerEnabledOnly -MinDaysWithNotResponding 7
            ($report.AllUsers | Where-Object UserId -eq 'A').DailyPattern | Should -Be 'Daily'
            ($report.AllUsers | Where-Object UserId -eq 'B').DailyPattern | Should -Be ''
            $report.UsersFlaggedDailyPattern | Should -Be 1
            $report.Threshold.AutoAnswerEnabledOnly | Should -BeTrue
            $report.Threshold.MinDaysWithNotResponding | Should -Be 7
        }
    }

    It 'is backward compatible: no new params keeps all users and sets no daily flag' {
        InModuleScope 'Genesys.Ops' -Parameters @{ Since = $script:Since; Until = $script:Until } {
            param($Since, $Until)
            $report = Invoke-GenesysNotRespondingReport -Since $Since -Until $Until
            @($report.AllUsers).UserId | Should -Contain 'C'
            $report.UsersFlaggedDailyPattern | Should -Be 0
            @($report.AllUsers | Where-Object { $_.DailyPattern -eq 'Daily' }).Count | Should -Be 0
            # Additive fields are present even when the features are off.
            ($report.AllUsers | Where-Object UserId -eq 'A').PSObject.Properties.Name | Should -Contain 'AcdAutoAnswer'
            ($report.AllUsers | Where-Object UserId -eq 'A').PSObject.Properties.Name | Should -Contain 'DaysWithNotResponding'
        }
    }
}
