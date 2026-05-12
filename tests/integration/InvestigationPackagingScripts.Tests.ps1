Describe 'Release 1.4 packaging and diagnostics scripts' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ExportScript = Join-Path $script:RepoRoot 'scripts/Export-InvestigationPackage.ps1'
        $script:DiagnosticsScript = Join-Path $script:RepoRoot 'scripts/Copy-InvestigationDiagnosticsBundle.ps1'
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('genesys-packaging-tests-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:TempRoot -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TempRoot) {
            Remove-Item -Path $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exports markdown/xlsx packages for agent, conversation, and queue runs' {
        $destinationRoot = Join-Path $script:TempRoot 'packages'
        $result = & $script:ExportScript -RunFolder @(
            (Join-Path $script:RepoRoot 'samples/demo-agent-investigation'),
            (Join-Path $script:RepoRoot 'samples/demo-conversation-investigation-run'),
            (Join-Path $script:RepoRoot 'samples/demo-queue-investigation')
        ) -DestinationRoot $destinationRoot -Force

        @($result).Count | Should -Be 3
        foreach ($package in @($result)) {
            Test-Path $package.MarkdownPath | Should -BeTrue
            Test-Path $package.WorkbookPath | Should -BeTrue
            Test-Path $package.PackageJsonPath | Should -BeTrue
            Test-Path $package.CsvDirectory | Should -BeTrue

            $packageJson = Get-Content -Path $package.PackageJsonPath -Raw | ConvertFrom-Json
            $packageJson.packageType | Should -Be 'investigation-package'
            $packageJson.files.markdown | Should -Match '\.md$'
            $packageJson.files.workbook | Should -Match '\.xlsx$'
        }
    }

    It 'writes a redacted diagnostics bundle for support handoff' {
        $runCopy = Join-Path $script:TempRoot 'agent-run-copy'
        Copy-Item -Path (Join-Path $script:RepoRoot 'samples/demo-agent-investigation') -Destination $runCopy -Recurse -Force

        $eventsPath = Join-Path $runCopy 'events.jsonl'
        Add-Content -Path $eventsPath -Value '{"timestampUtc":"2026-05-12T11:00:00Z","investigationKey":"agent-investigation","runId":"demo-run","eventType":"step.failed","payload":{"errorMessage":"Authorization: Bearer secret-demo-token"}}'

        $outputPath = Join-Path $script:TempRoot 'support-bundle.json'
        $result = & $script:DiagnosticsScript -RunFolder @($runCopy) -OutputPath $outputPath -PassThru

        Test-Path $result.OutputPath | Should -BeTrue
        $raw = Get-Content -Path $result.OutputPath -Raw
        $raw | Should -Not -Match 'secret-demo-token'
        $raw | Should -Not -Match 'Authorization:'

        $bundle = $raw | ConvertFrom-Json
        $bundle.runCount | Should -Be 1
        @($bundle.runs[0].steps).Count | Should -BeGreaterThan 0
        @($bundle.runs[0].recentEvents).Count | Should -Be 1
    }
}
