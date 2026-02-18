Describe 'Long-form catalog profile mapping' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Catalog/Resolve-Catalog.ps1"
    }

    It 'maps cursor, bodyPaging, and transactionResults profiles into executable endpoint specs' {
        $longCatalog = [pscustomobject]@{
            version = '1.0.0'
            datasets = [pscustomobject]@{
                jobs = [pscustomobject]@{
                    endpoint = 'jobs.submit'
                    itemsPath = '$.entities'
                    paging = [pscustomobject]@{ profile = 'transactionResults' }
                    retry = [pscustomobject]@{ profile = 'rateLimitAware' }
                }
            }
            profiles = [pscustomobject]@{
                paging = [pscustomobject]@{
                    jobs_tx = [pscustomobject]@{
                        type = 'transactionResults'
                        transactionIdPath = '$.job.id'
                    }
                    jobs_results = [pscustomobject]@{
                        type = 'pageNumber'
                        pageNumberParam = 'pageNumber'
                        totalHitsPath = '$.totalHits'
                    }
                    analytics_body = [pscustomobject]@{
                        type = 'bodyPaging'
                        pageNumberParam = 'pageNumber'
                        totalHitsPath = '$.totalHits'
                    }
                    cursor_default = [pscustomobject]@{
                        type = 'cursor'
                        cursorParam = 'cursor'
                        cursorPath = '$.cursor'
                    }
                }
                retry = [pscustomobject]@{
                    default = [pscustomobject]@{
                        mode = 'rateLimitAware'
                        maxRetries = 4
                    }
                }
                transaction = [pscustomobject]@{
                    jobs_tx = [pscustomobject]@{
                        statusEndpointRef = 'jobs.status'
                        resultsEndpointRef = 'jobs.results'
                        pollIntervalSeconds = 1
                        maxPolls = 10
                        statePath = '$.state'
                        terminalStates = @('DONE', 'FAILED')
                    }
                }
            }
            endpoints = [pscustomobject]@{
                'jobs.submit' = [pscustomobject]@{
                    method = 'POST'
                    path = '/api/v2/jobs'
                    itemsPath = '$'
                    pagingProfile = 'jobs_tx'
                    retryProfile = 'default'
                    transactionProfile = 'jobs_tx'
                }
                'jobs.status' = [pscustomobject]@{
                    method = 'GET'
                    path = '/api/v2/jobs/{jobId}'
                    itemsPath = '$'
                    pagingProfile = 'none'
                    retryProfile = 'default'
                }
                'jobs.results' = [pscustomobject]@{
                    method = 'GET'
                    path = '/api/v2/jobs/{jobId}/results'
                    itemsPath = '$.entities'
                    pagingProfile = 'jobs_results'
                    retryProfile = 'default'
                }
                'analytics.query' = [pscustomobject]@{
                    method = 'POST'
                    path = '/api/v2/analytics/conversations/details/query'
                    itemsPath = '$.conversations'
                    pagingProfile = 'analytics_body'
                    retryProfile = 'default'
                }
                'cursor.query' = [pscustomobject]@{
                    method = 'GET'
                    path = '/api/v2/cursor'
                    itemsPath = '$.entities'
                    pagingProfile = 'cursor_default'
                    retryProfile = 'default'
                }
            }
        }

        $resolvedCatalog = Resolve-CoreCatalog -Catalog $longCatalog
        $jobsEndpoint = Resolve-EndpointSpecForExecution -Catalog $resolvedCatalog -EndpointKey 'jobs.submit'
        $analyticsEndpoint = Resolve-EndpointSpecForExecution -Catalog $resolvedCatalog -EndpointKey 'analytics.query'
        $cursorEndpoint = Resolve-EndpointSpecForExecution -Catalog $resolvedCatalog -EndpointKey 'cursor.query'

        $jobsEndpoint.paging.profile | Should -Be 'transactionResults'
        $jobsEndpoint.transaction.transactionIdPath | Should -Be '$.job.id'
        $jobsEndpoint.transaction.status.key | Should -Be 'jobs.status'
        $jobsEndpoint.transaction.results.key | Should -Be 'jobs.results'
        $jobsEndpoint.transaction.results.paging.profile | Should -Be 'pageNumber'
        $jobsEndpoint.transaction.results.paging.pageParam | Should -Be 'pageNumber'
        $jobsEndpoint.retry.maxRetries | Should -Be 4

        $analyticsEndpoint.paging.profile | Should -Be 'bodyPaging'
        $analyticsEndpoint.paging.pageParam | Should -Be 'pageNumber'
        $analyticsEndpoint.paging.totalHitsPath | Should -Be '$.totalHits'

        $cursorEndpoint.paging.profile | Should -Be 'cursor'
        $cursorEndpoint.paging.cursorParam | Should -Be 'cursor'
        $cursorEndpoint.paging.cursorPath | Should -Be '$.cursor'
    }
}
