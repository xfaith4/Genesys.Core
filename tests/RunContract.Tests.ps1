Describe 'Run output contract' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Run/New-RunContext.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Run/Write-Jsonl.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Run/Write-RunEvent.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Run/Write-Manifest.ps1"
    }

    It 'creates out/<datasetKey>/<runId>/ with manifest and events files' {
        $root = Join-Path -Path $TestDrive -ChildPath 'out'
        $runContext = New-RunContext -DatasetKey 'audit-logs' -OutputRoot $root -RunId 'run-001'

        Write-RunEvent -RunContext $runContext -EventType 'run.started' -Payload @{ ok = $true } | Out-Null
        Write-RunEvent -RunContext $runContext -EventType 'run.completed' -Payload @{ ok = $true } | Out-Null
        Write-Manifest -RunContext $runContext -Counts @{ itemCount = 2 } -Warnings @('stub-warning') | Out-Null

        Test-Path -Path $runContext.runFolder | Should -BeTrue
        Test-Path -Path $runContext.dataFolder | Should -BeTrue
        Test-Path -Path $runContext.eventsPath | Should -BeTrue
        Test-Path -Path $runContext.manifestPath | Should -BeTrue
        (Split-Path -Path $runContext.runFolder -Leaf) | Should -Be 'run-001'
        (Split-Path -Path (Split-Path -Path $runContext.runFolder -Parent) -Leaf) | Should -Be 'audit-logs'

        $eventsLines = @(Get-Content -Path $runContext.eventsPath)
        $eventsLines.Count | Should -Be 2

        $eventOne = $eventsLines[0] | ConvertFrom-Json
        $eventOne.eventType | Should -Be 'run.started'
        $eventOne.datasetKey | Should -Be 'audit-logs'

        $manifest = Get-Content -Path $runContext.manifestPath -Raw | ConvertFrom-Json
        $manifest.datasetKey | Should -Be 'audit-logs'
        $manifest.startedAtUtc | Should -Not -BeNullOrEmpty
        $manifest.endedAtUtc | Should -Not -BeNullOrEmpty
        $manifest.counts.itemCount | Should -Be 2
        @($manifest.warnings).Count | Should -Be 1
    }

    It 'writes git sha into manifest when env var exists' {
        $root = Join-Path -Path $TestDrive -ChildPath 'out'
        $runContext = New-RunContext -DatasetKey 'users' -OutputRoot $root -RunId 'run-002'

        $original = [Environment]::GetEnvironmentVariable('GITHUB_SHA')
        try {
            [Environment]::SetEnvironmentVariable('GITHUB_SHA', 'abc123')
            Write-Manifest -RunContext $runContext | Out-Null
        }
        finally {
            [Environment]::SetEnvironmentVariable('GITHUB_SHA', $original)
        }

        $manifest = Get-Content -Path $runContext.manifestPath -Raw | ConvertFrom-Json
        $manifest.gitSha | Should -Be 'abc123'
    }

    It 'local stub run writes contract files' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        Import-Module "$PSScriptRoot/../src/ps-module/Genesys.Core/Genesys.Core.psd1" -Force
        Invoke-Dataset -Dataset 'audit-logs' -OutputRoot $outputRoot | Out-Null

        $datasetFolder = Join-Path -Path $outputRoot -ChildPath 'audit-logs'
        Test-Path -Path $datasetFolder | Should -BeTrue

        $runFolder = Get-ChildItem -Path $datasetFolder -Directory | Select-Object -First 1
        $runFolder | Should -Not -BeNullOrEmpty

        Test-Path -Path (Join-Path -Path $runFolder.FullName -ChildPath 'manifest.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $runFolder.FullName -ChildPath 'events.jsonl') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $runFolder.FullName -ChildPath 'summary.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $runFolder.FullName -ChildPath 'data/records.jsonl') | Should -BeTrue

        $events = @(Get-Content -Path (Join-Path -Path $runFolder.FullName -ChildPath 'events.jsonl'))
        $events.Count | Should -BeGreaterThan 0
    }
}
