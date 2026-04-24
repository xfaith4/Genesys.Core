Describe 'Audit logs dataset' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../modules/Genesys.Core/Genesys.Core.psd1" -Force
    }

    It 'runs submit->poll->results flow and writes audit outputs' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'

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
                        [pscustomobject]@{ id = '1'; action = 'create'; serviceName = 'routing'; userEmail = 'redacted-user-1'; authorization = 'Bearer synthetic-token-1' },
                        [pscustomobject]@{ id = '2'; action = 'update'; serviceName = 'platform'; context = [pscustomobject]@{ apiKey = 'abc123'; nestedToken = 'value' } }
                    )
                    nextUri = 'https://api.test.local/api/v2/audits/query/tx-123/results?pageNumber=2'
                    totalHits = 3
                } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-123/results?pageNumber=2') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    results = @(
                        [pscustomobject]@{ id = '3'; action = 'create'; serviceName = 'routing'; jwt = 'aaa.bbb.ccc' }
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

        $auditRecords = @($auditLines | ForEach-Object { $_ | ConvertFrom-Json })
        $auditRecords[0].userEmail | Should -Be '[REDACTED]'
        $auditRecords[0].authorization | Should -Be '[REDACTED]'
        $auditRecords[1].context.apiKey | Should -Be '[REDACTED]'
        $auditRecords[1].context.nestedToken | Should -Be '[REDACTED]'
        $auditRecords[2].jwt | Should -Be '[REDACTED]'

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



    It 'submits a valid unfiltered audit query body' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-unfiltered'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'

        $script:capturedSubmitBody = $null
        $requestInvoker = {
            param($request)

            $uri = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/servicemapping') {
                return [pscustomobject]@{ Result = @('routing', 'platform') }
            }

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/audits/query') {
                $script:capturedSubmitBody = $request.Body | ConvertFrom-Json -Depth 20
                return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'tx-unfiltered' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-unfiltered') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-unfiltered/results') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ results = @(); nextUri = $null } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        $parameters = @{
            StartUtc = '2026-02-20T00:00:00Z'
            EndUtc = '2026-02-20T01:00:00Z'
        }

        Invoke-Dataset -Dataset 'audit-logs' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -DatasetParameters $parameters -RequestInvoker $requestInvoker | Out-Null

        $script:capturedSubmitBody.interval | Should -Be '2026-02-20T00:00:00.0000000Z/2026-02-20T01:00:00.0000000Z'
        @($script:capturedSubmitBody.filters).Count | Should -Be 0
        @($script:capturedSubmitBody.sort).Count | Should -Be 1
        $script:capturedSubmitBody.PSObject.Properties.Name | Should -Not -Contain 'serviceName'
        $script:capturedSubmitBody.PSObject.Properties.Name | Should -Not -Contain 'action'
    }

    It 'supports dataset parameter overrides for interval, service name, entity type, and action' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-parameterized'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'

        $script:capturedSubmitBody = $null
        $requestInvoker = {
            param($request)

            $uri = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/servicemapping') {
                return [pscustomobject]@{ Result = @('routing', 'platform') }
            }

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/audits/query') {
                $script:capturedSubmitBody = $request.Body | ConvertFrom-Json -Depth 20
                return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'tx-params' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-params') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-params/results') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    results = @([pscustomobject]@{ id = '1'; action = 'delete'; serviceName = 'routing' })
                    nextUri = $null
                } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        $parameters = @{
            StartUtc = '2026-02-20T00:00:00Z'
            EndUtc = '2026-02-20T01:00:00Z'
            ServiceNames = @('routing')
            EntityTypes = @('Queue')
            Actions = @('delete')
        }

        Invoke-Dataset -Dataset 'audit-logs' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -DatasetParameters $parameters -RequestInvoker $requestInvoker | Out-Null

        $script:capturedSubmitBody.interval | Should -Be '2026-02-20T00:00:00.0000000Z/2026-02-20T01:00:00.0000000Z'
        $script:capturedSubmitBody.serviceName | Should -Be 'routing'
        @($script:capturedSubmitBody.filters).Count | Should -Be 2
        ($script:capturedSubmitBody.filters | Where-Object { $_.property -eq 'EntityType' }).value | Should -Be 'Queue'
        ($script:capturedSubmitBody.filters | Where-Object { $_.property -eq 'Action' }).value | Should -Be 'delete'
        $script:capturedSubmitBody.PSObject.Properties.Name | Should -Not -Contain 'action'
    }

    It 'fails before submit when action is supplied without entity type' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-action-without-entity'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'

        $script:submitAttempted = $false
        $requestInvoker = {
            param($request)

            $uri = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/servicemapping') {
                return [pscustomobject]@{ Result = @('routing') }
            }

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/audits/query') {
                $script:submitAttempted = $true
                return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'tx-invalid' } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        {
            Invoke-Dataset -Dataset 'audit-logs' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -DatasetParameters @{
                StartUtc = '2026-02-20T00:00:00Z'
                EndUtc = '2026-02-20T01:00:00Z'
                Actions = @('delete')
            } -RequestInvoker $requestInvoker
        } | Should -Throw '*requires an EntityType filter*'

        $script:submitAttempted | Should -BeFalse
    }
    It 'fails when transaction reaches FAILED terminal state' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'

        $requestInvoker = {
            param($request)

            $uri = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/servicemapping') {
                return [pscustomobject]@{ Result = @('routing') }
            }

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/audits/query') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'tx-failed' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-failed') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FAILED' } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        {
            Invoke-Dataset -Dataset 'audit-logs' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker
        } | Should -Throw "*Audit transaction ended in state 'FAILED'.*"
    }

    It 'fails when transaction reaches CANCELLED terminal state' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'

        $requestInvoker = {
            param($request)

            $uri = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/servicemapping') {
                return [pscustomobject]@{ Result = @('routing') }
            }

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/audits/query') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'tx-cancelled' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/audits/query/tx-cancelled') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'CANCELLED' } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        {
            Invoke-Dataset -Dataset 'audit-logs' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker
        } | Should -Throw "*Audit transaction ended in state 'CANCELLED'.*"
    }
}


