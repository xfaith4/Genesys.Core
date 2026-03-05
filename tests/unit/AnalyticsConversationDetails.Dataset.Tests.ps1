Describe 'Analytics conversation details dataset' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../modules/Genesys.Core/Genesys.Core.psd1" -Force
    }

    It 'runs submit->poll->results flow with cursor paging and writes outputs' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'

        $script:pollCount = 0
        $requestInvoker = {
            param($request)

            $uri    = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ jobId = 'job-abc' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs/job-abc') {
                $script:pollCount++
                if ($script:pollCount -lt 2) {
                    return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'RUNNING' } }
                }

                return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs/job-abc/results') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    conversations = @(
                        [pscustomobject]@{ conversationId = 'conv-1'; mediaType = 'voice'; userId = 'user-secret-1' },
                        [pscustomobject]@{ conversationId = 'conv-2'; mediaType = 'chat' }
                    )
                    cursor = 'cursor-page-2'
                } }
            }

            if ($method -eq 'GET' -and $uri -like '*cursor=cursor-page-2*') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    conversations = @(
                        [pscustomobject]@{ conversationId = 'conv-3'; mediaType = 'email' }
                    )
                    cursor = $null
                } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        Invoke-Dataset -Dataset 'analytics-conversation-details' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null

        $datasetFolder = Join-Path -Path $outputRoot -ChildPath 'analytics-conversation-details'
        $runFolder = Get-ChildItem -Path $datasetFolder -Directory | Select-Object -First 1

        $dataPath = Join-Path -Path $runFolder.FullName -ChildPath 'data/analytics-conversation-details.jsonl'
        Test-Path -Path $dataPath | Should -BeTrue

        $lines   = @(Get-Content -Path $dataPath)
        $records = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
        $records.Count | Should -Be 3
        $records[0].conversationId | Should -Be 'conv-1'
        $records[2].conversationId | Should -Be 'conv-3'

        $summaryPath = Join-Path -Path $runFolder.FullName -ChildPath 'summary.json'
        $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json
        $summary.totals.totalConversations | Should -Be 3

        $eventsPath = Join-Path -Path $runFolder.FullName -ChildPath 'events.jsonl'
        $events = @(Get-Content -Path $eventsPath | ForEach-Object { $_ | ConvertFrom-Json })
        (@($events | Where-Object { $_.eventType -eq 'analytics.job.submitted' })).Count | Should -Be 1
        (@($events | Where-Object { $_.eventType -eq 'analytics.job.poll' })).Count | Should -Be 2
        (@($events | Where-Object { $_.eventType -eq 'paging.progress' })).Count | Should -BeGreaterThan 1

        $manifestPath = Join-Path -Path $runFolder.FullName -ChildPath 'manifest.json'
        $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
        $manifest.counts.itemCount | Should -Be 3
    }

    It 'fails when analytics job reaches FAILED terminal state' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-failed'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'

        $requestInvoker = {
            param($request)
            $uri    = [string]$request.Uri
            $method = [string]$request.Method

            if ($method -eq 'POST' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ jobId = 'job-fail' } }
            }

            if ($method -eq 'GET' -and $uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/jobs/job-fail') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FAILED' } }
            }

            throw "Unexpected request: $($method) $($uri)"
        }

        {
            Invoke-Dataset -Dataset 'analytics-conversation-details' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker
        } | Should -Throw "*Analytics conversation details job ended in state 'FAILED'.*"
    }

    It 'runs analytics-conversation-details-query with body paging via generic dispatch' {
        $catalogPath = Join-Path -Path $TestDrive -ChildPath 'query.catalog.json'
        $catalog = [ordered]@{
            version  = '1.0.0'
            datasets = [ordered]@{
                'analytics-conversation-details-query' = [ordered]@{
                    endpoint  = 'analytics.conversation.details.query'
                    itemsPath = '$.conversations'
                    paging    = [ordered]@{ profile = 'analytics_details_query' }
                    retry     = [ordered]@{ profile = 'default' }
                }
            }
            profiles = [ordered]@{
                paging = [ordered]@{
                    analytics_details_query = [ordered]@{
                        type          = 'bodyPaging'
                        totalHitsPath = '$.totalHits'
                    }
                }
                retry  = [ordered]@{
                    default = [ordered]@{
                        mode              = 'rateLimitAware'
                        maxRetries        = 1
                        baseDelaySeconds  = 0
                        maxDelaySeconds   = 0
                        jitterSeconds     = 0
                        retryOnStatusCodes = @(429)
                        retryOnMethods    = @('GET', 'POST')
                    }
                }
            }
            endpoints = [ordered]@{
                'analytics.conversation.details.query' = [ordered]@{
                    method       = 'POST'
                    path         = '/api/v2/analytics/conversations/details/query'
                    pagingProfile = 'analytics_details_query'
                    retryProfile  = 'default'
                    itemsPath    = '$.conversations'
                }
            }
        }
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $catalogPath

        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-query'
        $script:queryPageCount = 0
        $requestInvoker = {
            param($request)
            $script:queryPageCount++
            if ($request.Method -eq 'POST' -and $request.Uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/query') {
                $body = $request.Body | ConvertFrom-Json
                if ($body.pageNumber -eq 1) {
                    return [pscustomobject]@{ Result = [pscustomobject]@{
                        conversations = @(
                            [pscustomobject]@{ conversationId = 'qconv-1'; mediaType = 'voice' }
                        )
                        totalHits = 2
                    } }
                }
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    conversations = @(
                        [pscustomobject]@{ conversationId = 'qconv-2'; mediaType = 'chat' }
                    )
                    totalHits = 2
                } }
            }

            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'analytics-conversation-details-query' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null
        $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'analytics-conversation-details-query') -Directory | Select-Object -First 1
        $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/analytics-conversation-details-query.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        $records.Count | Should -Be 2
        $records[0].conversationId | Should -Be 'qconv-1'
        $records[1].conversationId | Should -Be 'qconv-2'
        $script:queryPageCount | Should -Be 2
    }
}


