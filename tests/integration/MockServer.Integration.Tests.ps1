#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for Genesys.Core against the Genesys.MockServer HTTP demo server.

.DESCRIPTION
    These tests start Genesys.MockServer as a background process, configure Genesys.Core
    to point at http://localhost:7778 (separate from the default dev port), run Invoke-Dataset
    against the five Tier 1 datasets, and validate the output structure.

    Requirements:
      - dotnet SDK 8+ installed and on PATH
      - Genesys.Core module in modules/Genesys.Core/
      - tools/Genesys.MockServer/ built (or buildable)

    Run via:
      pwsh -NoProfile -File ./scripts/Invoke-Tests.ps1 -IncludeIntegration
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Integration test output intentionally uses Write-Host for clarity')]
param()

$ErrorActionPreference = 'Stop'

# ─── Pester suite ────────────────────────────────────────────────────────────

# Configuration and the server lifecycle helpers live inside BeforeAll deliberately. Pester v5
# evaluates a test file's body during discovery and then runs the blocks in a separate scope, so
# anything defined at script level here is gone by the time BeforeAll executes. Assigning with
# $script: inside BeforeAll puts these where the It blocks can still reach them.

Describe 'Genesys.MockServer Integration Tests' {

    BeforeAll {
        $script:MockPort      = 7778   # 7778 avoids colliding with a running dev server
        $script:DemoToken     = 'demo-bearer-token-genesys-testplatform'
        $script:BaseUri       = "http://localhost:$($script:MockPort)"
        $script:RepoRoot      = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $script:ModulePath    = Join-Path $script:RepoRoot 'modules/Genesys.Core/Genesys.Core.psd1'
        $script:ProjectPath   = Join-Path $script:RepoRoot 'tools/Genesys.MockServer/Genesys.MockServer.csproj'
        $script:OutputRoot    = Join-Path $env:TEMP "GenesysMockIntegration_$(Get-Date -Format 'yyyyMMddHHmmss')"
        $script:ServerProcess = $null

        function Start-MockServer {
            Write-Host '[Integration] Starting Genesys.MockServer ...' -ForegroundColor Cyan

            if (-not (Test-Path $script:ProjectPath)) {
                throw "MockServer project not found at: $($script:ProjectPath)"
            }

            $env:MOCK_PORT           = $script:MockPort
            $env:MOCK_POLLING_ROUNDS = '1'   # Fast: 1 poll before FULFILLED in tests

            $script:ServerProcess = Start-Process -FilePath 'dotnet' `
                -ArgumentList "run --project `"$($script:ProjectPath)`"" `
                -PassThru -WindowStyle Hidden -RedirectStandardOutput ([System.IO.Path]::GetTempFileName())

            # Wait up to 30 seconds for the server to become ready
            $ready   = $false
            $timeout = [datetime]::UtcNow.AddSeconds(30)
            while ([datetime]::UtcNow -lt $timeout) {
                Start-Sleep -Milliseconds 500
                try {
                    $probe = Invoke-RestMethod -Uri "$($script:BaseUri)/health" -TimeoutSec 2 -ErrorAction Stop
                    if ($probe.status -eq 'ok') {
                        $ready = $true
                        break
                    }
                } catch {
                    # Server not ready yet
                }
            }

            if (-not $ready) {
                Stop-MockServer
                throw "Genesys.MockServer did not become ready within 30 seconds on port $($script:MockPort)"
            }

            Write-Host "[Integration] Mock server ready on $($script:BaseUri)" -ForegroundColor Green
        }

        function Stop-MockServer {
            if ($null -ne $script:ServerProcess -and -not $script:ServerProcess.HasExited) {
                $script:ServerProcess.Kill($true)
                $script:ServerProcess.WaitForExit(5000) | Out-Null
                Write-Host '[Integration] Mock server stopped.' -ForegroundColor DarkGray
            }
            $script:ServerProcess = $null
        }

        Start-MockServer

        Import-Module $script:ModulePath -Force -ErrorAction Stop

        # The demo token is not a secret - the server prints it on startup and the README quotes
        # it. It is declared above rather than inlined so there is one place to change it.
        $script:Headers = @{ Authorization = "Bearer $($script:DemoToken)" }
        New-Item -ItemType Directory -Path $script:OutputRoot -Force | Out-Null
    }

    AfterAll {
        Stop-MockServer
        if (Test-Path $OutputRoot) {
            Remove-Item -Recurse -Force $OutputRoot -ErrorAction SilentlyContinue
        }
    }

    # ─── Connectivity ────────────────────────────────────────────────────────

    Context 'Server connectivity' {
        It 'Health endpoint returns ok' {
            $r = Invoke-RestMethod -Uri "$BaseUri/health" -ErrorAction Stop
            $r.status | Should -Be 'ok'
        }

        It 'OAuth token endpoint issues demo bearer token' {
            $body = @{ grant_type = 'client_credentials'; client_id = 'test'; client_secret = 'test' }
            $r = Invoke-RestMethod -Uri "$BaseUri/oauth/token" -Method Post -Body $body -ErrorAction Stop
            $r.access_token | Should -Be $DemoToken
            $r.token_type | Should -Be 'bearer'
        }

        It 'Unauthorized request returns 401' {
            { Invoke-RestMethod -Uri "$BaseUri/api/v2/users" -ErrorAction Stop } | Should -Throw
        }
    }

    # ─── Dataset: users ──────────────────────────────────────────────────────

    Context 'Dataset: users' {
        It 'Invoke-Dataset returns output files' {
            $out = Join-Path $OutputRoot 'users'
            { Invoke-Dataset -Dataset 'users' -BaseUri $BaseUri -Headers $script:Headers `
                  -OutputRoot $out -ErrorAction Stop } | Should -Not -Throw

            Test-Path (Join-Path $out 'users') | Should -Be $true
        }

        It 'Manifest.json exists and has correct schema' {
            $manifest = Get-ChildItem -Path (Join-Path $OutputRoot 'users') `
                -Filter 'manifest.json' -Recurse -ErrorAction Stop | Select-Object -First 1
            $manifest | Should -Not -BeNullOrEmpty
            # Matches what Invoke-Dataset actually writes: datasetKey, runId, startedAtUtc,
            # endedAtUtc, gitSha, counts, warnings. The previous assertions named 'dataset' and
            # 'totalItems', which this manifest has never carried - they went unnoticed because
            # the whole Describe failed in BeforeAll and never reached this test.
            # -LiteralPath, not a pipe: Get-Content does not take a bare string from the pipeline
            # (-Path is ValueFromPipelineByPropertyName only), so "$path | Get-Content" raises a
            # parameter-binding error. Pester does not stop on that, so $m was silently $null and
            # the failure read as a missing property rather than a failed read.
            $m = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
            $m.datasetKey | Should -Be 'users'
            $m.counts.itemCount | Should -BeGreaterThan 0
        }

        It 'Events.jsonl contains records' {
            $eventsFile = Get-ChildItem -Path (Join-Path $OutputRoot 'users') `
                -Filter 'events.jsonl' -Recurse -ErrorAction Stop | Select-Object -First 1
            $eventsFile | Should -Not -BeNullOrEmpty
            $lines = Get-Content $eventsFile.FullName
            $lines.Count | Should -BeGreaterThan 0
            # Each line must be valid JSON
            foreach ($line in $lines) {
                { $line | ConvertFrom-Json } | Should -Not -Throw
            }
        }
    }

    # ─── Dataset: routing-queues ──────────────────────────────────────────────

    Context 'Dataset: routing-queues' {
        It 'Invoke-Dataset completes without error' {
            $out = Join-Path $OutputRoot 'routing-queues'
            { Invoke-Dataset -Dataset 'routing-queues' -BaseUri $BaseUri `
                  -Headers $script:Headers -OutputRoot $out -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Produces at least one entity' {
            $eventsFile = Get-ChildItem -Path (Join-Path $OutputRoot 'routing-queues') `
                -Filter 'events.jsonl' -Recurse -ErrorAction Stop | Select-Object -First 1
            $eventsFile | Should -Not -BeNullOrEmpty
            $lines = Get-Content $eventsFile.FullName
            $lines.Count | Should -BeGreaterThan 0
        }
    }

    # ─── Dataset: audit-logs ─────────────────────────────────────────────────

    Context 'Dataset: audit-logs' {
        It 'Invoke-Dataset completes the submit→poll→results flow' {
            $out = Join-Path $OutputRoot 'audit-logs'
            { Invoke-Dataset -Dataset 'audit-logs' -BaseUri $BaseUri `
                  -Headers $script:Headers -OutputRoot $out -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Audit results contain events across pages' {
            $eventsFile = Get-ChildItem -Path (Join-Path $OutputRoot 'audit-logs') `
                -Filter 'events.jsonl' -Recurse -ErrorAction Stop | Select-Object -First 1
            $eventsFile | Should -Not -BeNullOrEmpty
            $lines = Get-Content $eventsFile.FullName
            $lines.Count | Should -BeGreaterThan 5
        }
    }

    # ─── Dataset: analytics-conversation-details ─────────────────────────────

    Context 'Dataset: analytics-conversation-details' {
        It 'Invoke-Dataset completes the async job flow' {
            $out = Join-Path $OutputRoot 'analytics-conv'
            { Invoke-Dataset -Dataset 'analytics-conversation-details' `
                  -BaseUri $BaseUri -Headers $script:Headers `
                  -OutputRoot $out -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Conversation records are present' {
            $eventsFile = Get-ChildItem -Path (Join-Path $OutputRoot 'analytics-conv') `
                -Filter 'events.jsonl' -Recurse -ErrorAction Stop | Select-Object -First 1
            $eventsFile | Should -Not -BeNullOrEmpty
            (Get-Content $eventsFile.FullName).Count | Should -BeGreaterThan 0
        }
    }

    # ─── Dataset: speechandtextanalytics-topics ───────────────────────────────

    Context 'Dataset: speechandtextanalytics-topics' {
        It 'Invoke-Dataset returns topics' {
            $out = Join-Path $OutputRoot 'sta-topics'
            { Invoke-Dataset -Dataset 'speechandtextanalytics.get.topics' `
                  -BaseUri $BaseUri -Headers $script:Headers `
                  -OutputRoot $out -ErrorAction Stop } | Should -Not -Throw
        }
    }
}
