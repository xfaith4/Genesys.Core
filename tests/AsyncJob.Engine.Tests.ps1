Describe 'Async job engine' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Http/Join-EndpointUri.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Retry/Resolve-RetryRuntimeSettings.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Retry/Invoke-RequestWithRetry.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingNextUri.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingPageNumber.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingCursor.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingBodyPaging.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Invoke-CoreEndpoint.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Async/Invoke-AsyncJob.ps1"
    }

    It 'runs analytics-style async profile with custom id/state paths' {
        $script:statusPolls = 0
        $runEvents = [System.Collections.Generic.List[object]]::new()

        $submitEndpoint = [pscustomobject]@{
            key = 'analytics.jobs.submit'
            method = 'POST'
            path = '/api/v2/analytics/conversations/details/jobs'
            retry = [pscustomobject]@{ maxRetries = 1; baseDelaySeconds = 0; maxDelaySeconds = 0; jitterSeconds = 0; allowRetryOnPost = $true; retryOnStatusCodes = @(429, 503); retryOnMethods = @('GET', 'POST') }
        }

        $statusEndpoint = [pscustomobject]@{
            key = 'analytics.jobs.status'
            method = 'GET'
            path = '/api/v2/analytics/conversations/details/jobs/{jobId}'
            retry = [pscustomobject]@{ maxRetries = 1; baseDelaySeconds = 0; maxDelaySeconds = 0; jitterSeconds = 0; retryOnStatusCodes = @(429, 503); retryOnMethods = @('GET') }
        }

        $resultsEndpoint = [pscustomobject]@{
            key = 'analytics.jobs.results'
            method = 'GET'
            path = '/api/v2/analytics/conversations/details/jobs/{jobId}/results'
            itemsPath = '$.entities'
            paging = [pscustomobject]@{ profile = 'nextUri' }
            retry = [pscustomobject]@{ maxRetries = 1; baseDelaySeconds = 0; maxDelaySeconds = 0; jitterSeconds = 0; retryOnStatusCodes = @(429, 503); retryOnMethods = @('GET') }
        }

        $asyncProfile = [pscustomobject]@{
            transactionIdPath = '$.jobId'
            statePath = '$.job.state'
            terminalStates = @('COMPLETED', 'FAILED')
            successStates = @('COMPLETED')
            pollIntervalSeconds = 0
            maxPolls = 5
        }

        $requestInvoker = {
            param($request)

            $uri = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ jobId = 'job-123' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs/job-123') {
                $script:statusPolls++
                if ($script:statusPolls -eq 1) {
                    return [pscustomobject]@{ Result = [pscustomobject]@{ job = [pscustomobject]@{ state = 'RUNNING' } } }
                }

                return [pscustomobject]@{ Result = [pscustomobject]@{ job = [pscustomobject]@{ state = 'COMPLETED' } } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs/job-123/results') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @('a', 'b')
                    nextUri = 'https://api.test.local/api/v2/analytics/conversations/details/jobs/job-123/results?pageNumber=2'
                } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs/job-123/results?pageNumber=2') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @('c')
                    nextUri = $null
                } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        $result = Invoke-AsyncJob -SubmitEndpointSpec $submitEndpoint -StatusEndpointSpec $statusEndpoint -ResultsEndpointSpec $resultsEndpoint -AsyncProfile $asyncProfile -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker -SubmitBody @{ interval = 'x/y' } -RunEvents $runEvents -SleepAction { }

        @($result.Items).Count | Should -Be 3
        (@($runEvents | Where-Object { $_.eventType -eq 'async.job.submitted' })).Count | Should -Be 1
        (@($runEvents | Where-Object { $_.eventType -eq 'async.job.poll' })).Count | Should -Be 2
        (@($runEvents | Where-Object { $_.eventType -eq 'paging.progress' })).Count | Should -Be 2
    }

    It 'handles transient retries + paging + async polling in one flow' {
        $script:submitAttempts = 0
        $script:statusAttempts = 0
        $script:resultsAttempts = 0
        $runEvents = [System.Collections.Generic.List[object]]::new()

        $retryProfile = [pscustomobject]@{
            maxRetries = 2
            baseDelaySeconds = 0
            maxDelaySeconds = 0
            jitterSeconds = 0
            allowRetryOnPost = $true
            retryOnStatusCodes = @(429, 503)
            retryOnMethods = @('GET', 'POST')
        }

        $submitEndpoint = [pscustomobject]@{
            key = 'jobs.submit'
            method = 'POST'
            path = '/api/v2/jobs'
            retry = $retryProfile
        }

        $statusEndpoint = [pscustomobject]@{
            key = 'jobs.status'
            method = 'GET'
            path = '/api/v2/jobs/{jobId}'
            retry = $retryProfile
        }

        $resultsEndpoint = [pscustomobject]@{
            key = 'jobs.results'
            method = 'GET'
            path = '/api/v2/jobs/{jobId}/results'
            itemsPath = '$.items'
            paging = [pscustomobject]@{ profile = 'nextUri' }
            retry = $retryProfile
        }

        $asyncProfile = [pscustomobject]@{
            transactionIdPath = '$.jobId'
            statePath = '$.state'
            terminalStates = @('FULFILLED', 'FAILED')
            successStates = @('FULFILLED')
            pollIntervalSeconds = 0
            maxPolls = 5
        }

        $requestInvoker = {
            param($request)

            $uri = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/jobs') {
                $script:submitAttempts++
                if ($script:submitAttempts -eq 1) {
                    $error = [System.Exception]::new('Temporary submit failure')
                    $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                        StatusCode = 503
                        Headers = @{}
                    })
                    throw $error
                }

                return [pscustomobject]@{ Result = [pscustomobject]@{ jobId = 'job-golden' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/jobs/job-golden') {
                $script:statusAttempts++
                if ($script:statusAttempts -eq 1) {
                    $error = [System.Exception]::new('Retry the request in [0] seconds')
                    $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                        StatusCode = 429
                        Headers = @{ 'Retry-After' = '0' }
                    })
                    throw $error
                }

                if ($script:statusAttempts -eq 2) {
                    return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'RUNNING' } }
                }

                return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/jobs/job-golden/results') {
                $script:resultsAttempts++
                if ($script:resultsAttempts -eq 1) {
                    $error = [System.Exception]::new('Temporary results failure')
                    $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                        StatusCode = 503
                        Headers = @{}
                    })
                    throw $error
                }

                return [pscustomobject]@{ Result = [pscustomobject]@{
                    items = @('r1', 'r2')
                    nextUri = 'https://api.test.local/api/v2/jobs/job-golden/results?pageNumber=2'
                } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/jobs/job-golden/results?pageNumber=2') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    items = @('r3')
                    nextUri = $null
                } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        $result = Invoke-AsyncJob -SubmitEndpointSpec $submitEndpoint -StatusEndpointSpec $statusEndpoint -ResultsEndpointSpec $resultsEndpoint -AsyncProfile $asyncProfile -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker -SubmitBody @{ interval = 'x/y' } -RunEvents $runEvents -SleepAction { }

        @($result.Items) | Should -Be @('r1', 'r2', 'r3')
        (@($runEvents | Where-Object { $_.eventType -eq 'request.retry.scheduled' })).Count | Should -BeGreaterThan 2
        (@($runEvents | Where-Object { $_.eventType -eq 'paging.progress' })).Count | Should -Be 2
        (@($runEvents | Where-Object { $_.eventType -eq 'async.job.poll' })).Count | Should -Be 2
    }
}
