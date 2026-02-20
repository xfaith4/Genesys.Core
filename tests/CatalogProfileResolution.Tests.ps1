Describe 'Catalog profile resolution' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Catalog/Resolve-Catalog.ps1"
    }

    It 'resolves paging profile references to concrete runtime profile types' {
        $catalog = [pscustomobject]@{
            profiles = [pscustomobject]@{
                paging = [pscustomobject]@{
                    analytics_details_query = [pscustomobject]@{
                        type = 'bodyPaging'
                        totalHitsPath = '$.totalHits'
                        pageParam = 'pageNumber'
                    }
                }
                retry = [pscustomobject]@{
                    default = [pscustomobject]@{
                        mode = 'rateLimitAware'
                        maxRetries = 4
                        baseDelaySeconds = 2
                        maxDelaySeconds = 60
                        jitterSeconds = 0.5
                    }
                }
                transaction = [pscustomobject]@{}
            }
        }

        $endpoint = [pscustomobject]@{
            key = 'analytics.query'
            method = 'POST'
            path = '/api/v2/analytics/conversations/details/query'
            itemsPath = '$.entities'
            paging = [pscustomobject]@{ profile = 'analytics_details_query' }
            retry = [pscustomobject]@{ profile = 'default' }
        }

        $dataset = [pscustomobject]@{
            itemsPath = '$.conversations'
            paging = [pscustomobject]@{ profile = 'analytics_details_query' }
            retry = [pscustomobject]@{ profile = 'rateLimitAware' }
        }

        $resolved = Resolve-EndpointSpecProfiles -Catalog $catalog -EndpointSpec $endpoint -DatasetSpec $dataset

        $resolved.itemsPath | Should -Be '$.conversations'
        $resolved.paging.profile | Should -Be 'bodyPaging'
        $resolved.paging.totalHitsPath | Should -Be '$.totalHits'
        $resolved.retry.profile | Should -Be 'rateLimitAware'
        $resolved.retry.maxRetries | Should -Be 4
        $resolved.retry.baseDelaySeconds | Should -Be 2
    }

    It 'falls back to endpoint transaction profile when dataset transaction profile is unknown' {
        $catalog = [pscustomobject]@{
            profiles = [pscustomobject]@{
                paging = [pscustomobject]@{}
                retry = [pscustomobject]@{}
                transaction = [pscustomobject]@{
                    audit_query_transaction_then_results = [pscustomobject]@{
                        maxPolls = 300
                        pollIntervalSeconds = 2
                        statusEndpointRef = 'audit_query_transaction_then_results.status'
                        resultsEndpointRef = 'audit_query_transaction_then_results.results'
                    }
                }
            }
        }

        $endpoint = [pscustomobject]@{
            key = 'audits.query.submit'
            method = 'POST'
            path = '/api/v2/audits/query'
            itemsPath = '$'
            transaction = [pscustomobject]@{ profile = 'audit_query_transaction_then_results' }
        }

        $dataset = [pscustomobject]@{
            transaction = [pscustomobject]@{ profile = 'auditTransaction' }
        }

        $resolved = Resolve-EndpointSpecProfiles -Catalog $catalog -EndpointSpec $endpoint -DatasetSpec $dataset

        $resolved.transaction.profile | Should -Be 'audit_query_transaction_then_results'
        $resolved.transaction.statusEndpointRef | Should -Be 'audit_query_transaction_then_results.status'
        $resolved.transaction.resultsEndpointRef | Should -Be 'audit_query_transaction_then_results.results'
    }

    It 'applies precedence dataset inline > endpoint inline > profile defaults' {
        $catalog = [pscustomobject]@{
            profiles = [pscustomobject]@{
                paging = [pscustomobject]@{
                    p = [pscustomobject]@{
                        type = 'nextUri'
                        maxPages = 100
                    }
                }
                retry = [pscustomobject]@{
                    r = [pscustomobject]@{
                        mode = 'rateLimitAware'
                        maxRetries = 4
                        baseDelaySeconds = 2
                    }
                }
                transaction = [pscustomobject]@{}
            }
        }

        $endpoint = [pscustomobject]@{
            paging = [pscustomobject]@{
                profile = 'p'
                maxPages = 50
            }
            retry = [pscustomobject]@{
                profile = 'r'
                maxRetries = 3
            }
        }

        $dataset = [pscustomobject]@{
            paging = [pscustomobject]@{
                profile = 'p'
                maxPages = 10
            }
            retry = [pscustomobject]@{
                profile = 'r'
                maxRetries = 1
            }
        }

        $resolved = Resolve-EndpointSpecProfiles -Catalog $catalog -EndpointSpec $endpoint -DatasetSpec $dataset

        $resolved.paging.profile | Should -Be 'nextUri'
        $resolved.paging.maxPages | Should -Be 10
        $resolved.retry.profile | Should -Be 'r'
        $resolved.retry.maxRetries | Should -Be 1
        $resolved.retry.baseDelaySeconds | Should -Be 2
    }
}
