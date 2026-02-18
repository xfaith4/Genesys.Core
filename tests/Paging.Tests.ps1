Describe 'Paging strategies' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingNextUri.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingPageNumber.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingCursor.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingBodyPaging.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Async/Invoke-AuditTransaction.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Invoke-CoreEndpoint.ps1"
    }

    It 'enumerates nextUri pages and terminates when nextUri is empty' {
        $responses = @{
            'https://example.test/api/v2/audits?page=1' = [pscustomobject]@{
                results = @('a', 'b')
                nextUri = 'https://example.test/api/v2/audits?page=2'
                totalHits = 3
            }
            'https://example.test/api/v2/audits?page=2' = [pscustomobject]@{
                results = @('c')
                nextUri = $null
                totalHits = 3
            }
        }

        $calls = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = 'audits.query'
            method = 'GET'
            itemsPath = '$.results'
            paging = [pscustomobject]@{ profile = 'nextUri' }
        }) -InitialUri 'https://example.test/api/v2/audits?page=1' -RetryProfile ([pscustomobject]@{ maxRetries = 1 }) -RequestInvoker {
            param($request)
            $calls.Add($request.Uri) | Out-Null
            return [pscustomobject]@{ Result = $responses[$request.Uri] }
        }

        @($result.Items).Count | Should -Be 3
        @($result.Items) | Should -Be @('a', 'b', 'c')
        $calls.Count | Should -Be 2
        @($result.PagingTelemetry).Count | Should -Be 2
        $result.PagingTelemetry[0].page | Should -Be 1
        $result.PagingTelemetry[0].nextUri | Should -Match 'page=2'
        $result.PagingTelemetry[0].totalHits | Should -Be 3
        $result.PagingTelemetry[1].nextUri | Should -BeNullOrEmpty
    }

    It 'enumerates pageNumber pages and stops when totalHits reached' {
        $responses = @{
            'https://example.test/api/v2/users?pageNumber=1' = [pscustomobject]@{
                results = @('u1', 'u2')
                totalHits = 3
            }
            'https://example.test/api/v2/users?pageNumber=2' = [pscustomobject]@{
                results = @('u3')
                totalHits = 3
            }
        }

        $calls = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = 'users.list'
            method = 'GET'
            itemsPath = '$.results'
            paging = [pscustomobject]@{
                profile = 'pageNumber'
                pageParam = 'pageNumber'
            }
        }) -InitialUri 'https://example.test/api/v2/users' -RequestInvoker {
            param($request)
            $calls.Add($request.Uri) | Out-Null
            return [pscustomobject]@{ Result = $responses[$request.Uri] }
        }

        @($result.Items) | Should -Be @('u1', 'u2', 'u3')
        $calls.Count | Should -Be 2
        @($result.PagingTelemetry).Count | Should -Be 2
        $result.PagingTelemetry[0].nextUri | Should -Match 'pageNumber=2'
        $result.PagingTelemetry[1].nextUri | Should -BeNullOrEmpty
    }

    It 'terminates pageNumber when empty page is returned' {
        $responses = @{
            'https://example.test/api/v2/groups?pageNumber=1' = [pscustomobject]@{
                results = @('g1')
            }
            'https://example.test/api/v2/groups?pageNumber=2' = [pscustomobject]@{
                results = @()
            }
        }

        $calls = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = 'groups.list'
            method = 'GET'
            itemsPath = '$.results'
            paging = [pscustomobject]@{ profile = 'pageNumber' }
        }) -InitialUri 'https://example.test/api/v2/groups' -RequestInvoker {
            param($request)
            $calls.Add($request.Uri) | Out-Null
            return [pscustomobject]@{ Result = $responses[$request.Uri] }
        }

        @($result.Items) | Should -Be @('g1')
        $calls.Count | Should -Be 2
        $result.PagingTelemetry[1].itemCount | Should -Be 0
        $result.PagingTelemetry[1].nextUri | Should -BeNullOrEmpty
    }

    It 'enumerates cursor pages and terminates when cursor is missing' {
        $responses = @{
            'https://example.test/api/v2/cursor-items' = [pscustomobject]@{
                results = @('c1', 'c2')
                cursor = 'abc'
            }
            'https://example.test/api/v2/cursor-items?cursor=abc' = [pscustomobject]@{
                results = @('c3')
                cursor = $null
            }
        }

        $calls = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = 'cursor.items'
            method = 'GET'
            itemsPath = '$.results'
            paging = [pscustomobject]@{
                profile = 'cursor'
                cursorParam = 'cursor'
                cursorPath = '$.cursor'
            }
        }) -InitialUri 'https://example.test/api/v2/cursor-items' -RequestInvoker {
            param($request)
            $calls.Add($request.Uri) | Out-Null
            return [pscustomobject]@{ Result = $responses[$request.Uri] }
        }

        @($result.Items) | Should -Be @('c1', 'c2', 'c3')
        $calls.Count | Should -Be 2
        @($result.PagingTelemetry).Count | Should -Be 2
        $result.PagingTelemetry[0].nextUri | Should -Match 'cursor=abc'
        $result.PagingTelemetry[1].nextUri | Should -BeNullOrEmpty
    }

    It 'enumerates bodyPaging pages and stops when totalHits reached' {
        $requestBodies = [System.Collections.Generic.List[object]]::new()
        $result = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = 'analytics.query'
            method = 'POST'
            itemsPath = '$.conversations'
            paging = [pscustomobject]@{
                profile = 'bodyPaging'
                pageParam = 'pageNumber'
                totalHitsPath = '$.totalHits'
            }
        }) -InitialUri 'https://example.test/api/v2/analytics/conversations/details/query' -InitialBody '{"interval":"now","pageSize":2}' -RequestInvoker {
            param($request)
            $body = ConvertFrom-Json -InputObject $request.Body
            $requestBodies.Add($body) | Out-Null

            if ($body.pageNumber -eq 1) {
                return [pscustomobject]@{ Result = [pscustomobject]@{ conversations = @('a1', 'a2'); totalHits = 3 } }
            }

            if ($body.pageNumber -eq 2) {
                return [pscustomobject]@{ Result = [pscustomobject]@{ conversations = @('a3'); totalHits = 3 } }
            }

            throw "Unexpected pageNumber: $($body.pageNumber)"
        }

        @($result.Items) | Should -Be @('a1', 'a2', 'a3')
        $requestBodies.Count | Should -Be 2
        $requestBodies[0].pageNumber | Should -Be 1
        $requestBodies[1].pageNumber | Should -Be 2
        @($result.PagingTelemetry).Count | Should -Be 2
        $result.PagingTelemetry[1].nextUri | Should -BeNullOrEmpty
    }

    It 'writes bodyPaging page number to nested request path when configured' {
        $requestBodies = [System.Collections.Generic.List[object]]::new()
        $result = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = 'analytics.query.nested'
            method = 'POST'
            itemsPath = '$.conversations'
            paging = [pscustomobject]@{
                profile = 'bodyPaging'
                pagePath = 'paging.pageNumber'
                totalHitsPath = '$.totalHits'
            }
        }) -InitialUri 'https://example.test/api/v2/analytics/conversations/details/query' -InitialBody '{"interval":"now","paging":{"pageSize":2}}' -RequestInvoker {
            param($request)
            $body = ConvertFrom-Json -InputObject $request.Body
            $requestBodies.Add($body) | Out-Null

            if ($body.paging.pageNumber -eq 1) {
                return [pscustomobject]@{ Result = [pscustomobject]@{ conversations = @('a1', 'a2'); totalHits = 3 } }
            }

            if ($body.paging.pageNumber -eq 2) {
                return [pscustomobject]@{ Result = [pscustomobject]@{ conversations = @('a3'); totalHits = 3 } }
            }

            throw "Unexpected nested pageNumber: $($body.paging.pageNumber)"
        }

        @($result.Items) | Should -Be @('a1', 'a2', 'a3')
        $requestBodies.Count | Should -Be 2
        $requestBodies[0].paging.pageNumber | Should -Be 1
        $requestBodies[1].paging.pageNumber | Should -Be 2
    }

    It 'executes transactionResults with custom route and pageNumber results paging' {
        $script:jobPollCount = 0
        $calls = [System.Collections.Generic.List[string]]::new()

        $result = Invoke-CoreEndpoint -EndpointSpec ([pscustomobject]@{
            key = 'jobs.submit'
            method = 'POST'
            path = '/api/v2/jobs'
            itemsPath = '$'
            paging = [pscustomobject]@{
                profile = 'transactionResults'
                transactionIdPath = '$.job.id'
            }
            retry = [pscustomobject]@{
                profile = 'rateLimitAware'
                maxRetries = 4
            }
            transaction = [pscustomobject]@{
                profile = 'transactionResults'
                statePath = '$.status.state'
                terminalStates = @('DONE', 'FAILED')
                fulfilledState = 'DONE'
                pollIntervalSeconds = 0
                maxPolls = 5
                eventPrefix = 'job.transaction'
                routeParamName = 'jobId'
                baseUri = 'https://example.test'
                submit = [pscustomobject]@{
                    key = 'jobs.submit'
                    method = 'POST'
                    path = '/api/v2/jobs'
                    retry = [pscustomobject]@{ profile = 'rateLimitAware'; maxRetries = 4 }
                }
                status = [pscustomobject]@{
                    key = 'jobs.status'
                    method = 'GET'
                    path = '/api/v2/jobs/{jobId}'
                    itemsPath = '$'
                    paging = [pscustomobject]@{ profile = 'none' }
                    retry = [pscustomobject]@{ profile = 'rateLimitAware'; maxRetries = 4 }
                }
                results = [pscustomobject]@{
                    key = 'jobs.results'
                    method = 'GET'
                    path = '/api/v2/jobs/{jobId}/results'
                    itemsPath = '$.entities'
                    paging = [pscustomobject]@{
                        profile = 'pageNumber'
                        pageParam = 'pageNumber'
                        totalHitsPath = '$.totalHits'
                    }
                    retry = [pscustomobject]@{ profile = 'rateLimitAware'; maxRetries = 4 }
                }
            }
        }) -InitialUri 'https://example.test/api/v2/jobs' -InitialBody '{"interval":"now"}' -RetryProfile ([pscustomobject]@{ profile = 'rateLimitAware'; maxRetries = 4 }) -RequestInvoker {
            param($request)
            $calls.Add("$($request.Method) $($request.Uri)") | Out-Null

            if ($request.Method -eq 'POST' -and $request.Uri -eq 'https://example.test/api/v2/jobs') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ job = [pscustomobject]@{ id = 'job-7' } } }
            }

            if ($request.Method -eq 'GET' -and $request.Uri -eq 'https://example.test/api/v2/jobs/job-7') {
                $script:jobPollCount++
                if ($script:jobPollCount -eq 1) {
                    return [pscustomobject]@{ Result = [pscustomobject]@{ status = [pscustomobject]@{ state = 'RUNNING' } } }
                }

                return [pscustomobject]@{ Result = [pscustomobject]@{ status = [pscustomobject]@{ state = 'DONE' } } }
            }

            if ($request.Method -eq 'GET' -and $request.Uri -eq 'https://example.test/api/v2/jobs/job-7/results?pageNumber=1') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ entities = @('r1', 'r2'); totalHits = 3 } }
            }

            if ($request.Method -eq 'GET' -and $request.Uri -eq 'https://example.test/api/v2/jobs/job-7/results?pageNumber=2') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ entities = @('r3'); totalHits = 3 } }
            }

            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        @($result.Items) | Should -Be @('r1', 'r2', 'r3')
        (@($result.RunEvents | Where-Object { $_.eventType -eq 'job.transaction.poll' })).Count | Should -Be 2
        (@($calls | Where-Object { $_ -eq 'GET https://example.test/api/v2/jobs/job-7' })).Count | Should -Be 2
        (@($calls | Where-Object { $_ -eq 'GET https://example.test/api/v2/jobs/job-7/results?pageNumber=1' })).Count | Should -Be 1
    }
}
