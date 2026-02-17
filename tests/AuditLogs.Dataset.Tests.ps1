Describe 'Audit logs dataset' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../src/ps-module/Genesys.Core/Genesys.Core.psd1" -Force
    }

    It 'runs submit->poll->results flow and writes audit outputs' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../catalog/genesys-core.catalog.json'

        $script:pollCount = 0
        $requestInvoker = {
            param($request)

            $uri = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/servicemapping') {
                return [pscustomobject]@{ Result = @('routing', 'platform') }
            }

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/audits/query') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'tx-123' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-123') {
                $script:pollCount++
                if ($script:pollCount -lt 2) {
                    return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'RUNNING' } }
                }

                return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-123/results') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    results = @(
                        [pscustomobject]@{ id = '1'; action = 'create'; serviceName = 'routing' },
                        [pscustomobject]@{ id = '2'; action = 'update'; serviceName = 'platform' }
                    )
                    nextUri = 'https://api.test.local/api/v2/audits/query/tx-123/results?pageNumber=2'
                    totalHits = 3
                } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-123/results?pageNumber=2') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    results = @(
                        [pscustomobject]@{ id = '3'; action = 'create'; serviceName = 'routing' }
                    )
                    nextUri = $null
                    totalHits = 3
                } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        Invoke-Dataset -Dataset 'audit-logs' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null

        $datasetFolder = Join-Path -Path $outputRoot -ChildPath 'audit-logs'
        $runFolder = Get-ChildItem -Path $datasetFolder -Directory | Select-Object -First 1

        $auditPath = Join-Path -Path $runFolder.FullName -ChildPath 'data/audit.jsonl'
        Test-Path -Path $auditPath | Should -BeTrue

        $auditLines = @(Get-Content -Path $auditPath)
        $auditLines.Count | Should -Be 3

        $summaryPath = Join-Path -Path $runFolder.FullName -ChildPath 'summary.json'
        $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json

        $summary.totals.totalRecords | Should -Be 3
        $summary.countsByAction.create | Should -Be 2
        $summary.countsByServiceName.routing | Should -Be 2

        $eventsPath = Join-Path -Path $runFolder.FullName -ChildPath 'events.jsonl'
        $events = @(Get-Content -Path $eventsPath | ForEach-Object { $_ | ConvertFrom-Json })
        (@($events | Where-Object { $_.eventType -eq 'audit.transaction.poll' })).Count | Should -Be 2
        (@($events | Where-Object { $_.eventType -eq 'paging.progress' })).Count | Should -BeGreaterThan 0
    }
}
