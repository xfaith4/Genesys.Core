Describe 'New-DemoRequestInvoker' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../modules/Genesys.Core/Genesys.Core.psd1" -Force
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'
        $fixturesPath = Join-Path -Path $PSScriptRoot -ChildPath '../fixtures/demo'
    }

    It 'is exported by the module' {
        Get-Command -Name 'New-DemoRequestInvoker' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'returns a scriptblock' {
        $invoker = New-DemoRequestInvoker -FixturesPath $fixturesPath
        $invoker | Should -BeOfType [scriptblock]
    }

    It 'throws if fixtures path does not exist' {
        { New-DemoRequestInvoker -FixturesPath 'C:\nonexistent\path\does\not\exist' } | Should -Throw
    }

    # -------------------------------------------------------------------------
    # Users dataset — nextUri paging
    # -------------------------------------------------------------------------
    Context 'users dataset' {
        It 'runs users dataset with demo invoker and produces normalized output' {
            $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-users'
            $invoker = New-DemoRequestInvoker -FixturesPath $fixturesPath

            Invoke-Dataset -Dataset 'users' -CatalogPath $catalogPath -OutputRoot $outputRoot `
                -BaseUri 'https://api.demo.local' -RequestInvoker $invoker | Out-Null

            $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'users') -Directory | Select-Object -First 1
            $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/users.jsonl') |
                ForEach-Object { $_ | ConvertFrom-Json }

            $records.Count | Should -BeGreaterThan 1
            $records[0].recordType | Should -Be 'user'
            ($records | Where-Object { $_.id -eq 'user-agent-0001-alice' }).Count | Should -Be 1
        }
    }

    # -------------------------------------------------------------------------
    # Routing queues dataset — nextUri paging
    # -------------------------------------------------------------------------
    Context 'routing-queues dataset' {
        It 'runs routing-queues dataset with demo invoker' {
            $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-queues'
            $invoker = New-DemoRequestInvoker -FixturesPath $fixturesPath

            Invoke-Dataset -Dataset 'routing-queues' -CatalogPath $catalogPath -OutputRoot $outputRoot `
                -BaseUri 'https://api.demo.local' -RequestInvoker $invoker | Out-Null

            $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'routing-queues') -Directory | Select-Object -First 1
            $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/routing-queues.jsonl') |
                ForEach-Object { $_ | ConvertFrom-Json }

            $records.Count | Should -BeGreaterThan 1
            $records[0].recordType | Should -Be 'routingQueue'
            ($records | Where-Object { $_.id -eq 'queueid-0001-0001-0001-aabbccddeeff' }).Count | Should -Be 1
        }
    }

    # -------------------------------------------------------------------------
    # Audit logs dataset — async transaction + nextUri result paging
    # -------------------------------------------------------------------------
    Context 'audit-logs dataset' {
        It 'runs audit-logs dataset with demo invoker through full async flow' {
            $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-audits'
            $invoker = New-DemoRequestInvoker -FixturesPath $fixturesPath -PollingRoundsBeforeFulfilled 1

            Invoke-Dataset -Dataset 'audit-logs' -CatalogPath $catalogPath -OutputRoot $outputRoot `
                -BaseUri 'https://api.demo.local' -RequestInvoker $invoker | Out-Null

            $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'audit-logs') -Directory | Select-Object -First 1

            $auditPath = Join-Path -Path $runFolder.FullName -ChildPath 'data/audit.jsonl'
            Test-Path -Path $auditPath | Should -BeTrue

            $auditLines = @(Get-Content -Path $auditPath)
            $auditLines.Count | Should -Be 20

            $events = @(Get-Content -Path (Join-Path $runFolder.FullName 'events.jsonl') |
                ForEach-Object { $_ | ConvertFrom-Json })
            (@($events | Where-Object { $_.eventType -eq 'paging.progress' })).Count | Should -BeGreaterThan 1
        }
    }

    # -------------------------------------------------------------------------
    # Analytics conversation details — async job + cursor paging
    # -------------------------------------------------------------------------
    Context 'analytics-conversation-details dataset' {
        It 'runs analytics-conversation-details with demo invoker through full async flow' {
            $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-analytics'
            $invoker = New-DemoRequestInvoker -FixturesPath $fixturesPath -PollingRoundsBeforeFulfilled 1

            Invoke-Dataset -Dataset 'analytics-conversation-details' -CatalogPath $catalogPath `
                -OutputRoot $outputRoot -BaseUri 'https://api.demo.local' -RequestInvoker $invoker | Out-Null

            $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'analytics-conversation-details') `
                -Directory | Select-Object -First 1

            $dataPath = Join-Path -Path $runFolder.FullName -ChildPath 'data/analytics-conversation-details.jsonl'
            Test-Path -Path $dataPath | Should -BeTrue

            $lines = @(Get-Content -Path $dataPath)
            $lines.Count | Should -Be 5

            $summary = Get-Content -Path (Join-Path $runFolder.FullName 'summary.json') -Raw | ConvertFrom-Json
            $summary.totals.totalConversations | Should -Be 5
        }
    }

    # -------------------------------------------------------------------------
    # Analytics conversation details query — direct POST, body paging
    # -------------------------------------------------------------------------
    Context 'analytics-conversation-details-query dataset' {
        It 'runs analytics-conversation-details-query with demo invoker' {
            $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-analytics-query'
            $invoker = New-DemoRequestInvoker -FixturesPath $fixturesPath

            Invoke-Dataset -Dataset 'analytics-conversation-details-query' -CatalogPath $catalogPath `
                -OutputRoot $outputRoot -BaseUri 'https://api.demo.local' -RequestInvoker $invoker | Out-Null

            $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'analytics-conversation-details-query') `
                -Directory | Select-Object -First 1

            $dataPath = Join-Path $runFolder.FullName 'data/analytics-conversation-details-query.jsonl'
            Test-Path -Path $dataPath | Should -BeTrue
            $lines = @(Get-Content -Path $dataPath)
            $lines.Count | Should -BeGreaterThan 0
        }
    }

    # -------------------------------------------------------------------------
    # Fallback — unregistered endpoint throws clearly
    # -------------------------------------------------------------------------
    Context 'fallback behavior' {
        It 'throws a descriptive error for unregistered endpoints' {
            $invoker = New-DemoRequestInvoker -FixturesPath $fixturesPath
            $request = [pscustomobject]@{
                Uri    = 'https://api.demo.local/api/v2/unrecognized/endpoint'
                Method = 'GET'
                Body   = $null
            }
            { & $invoker $request } | Should -Throw '*New-DemoRequestInvoker*'
        }
    }

    # -------------------------------------------------------------------------
    # PollingRoundsBeforeFulfilled parameter
    # -------------------------------------------------------------------------
    Context 'PollingRoundsBeforeFulfilled parameter' {
        It 'respects custom polling rounds value' {
            $script:pollCount = 0
            $innerInvoker = New-DemoRequestInvoker -FixturesPath $fixturesPath -PollingRoundsBeforeFulfilled 3

            # Simulate polling the analytics job status directly
            $submitRequest = [pscustomobject]@{
                Uri    = 'https://api.demo.local/api/v2/analytics/conversations/details/jobs'
                Method = 'POST'
                Body   = '{}'
            }
            $submitResult = & $innerInvoker $submitRequest
            $jobId = $submitResult.Result.jobId

            $statusRequest = [pscustomobject]@{
                Uri    = "https://api.demo.local/api/v2/analytics/conversations/details/jobs/$jobId"
                Method = 'GET'
                Body   = $null
            }

            # Polls 1 and 2 should not be FULFILLED (threshold = 3)
            $poll1 = & $innerInvoker $statusRequest
            $poll1.Result.state | Should -Not -Be 'FULFILLED'

            $poll2 = & $innerInvoker $statusRequest
            $poll2.Result.state | Should -Not -Be 'FULFILLED'

            # Poll 3 reaches threshold → FULFILLED
            $poll3 = & $innerInvoker $statusRequest
            $poll3.Result.state | Should -Be 'FULFILLED'
        }
    }
}
