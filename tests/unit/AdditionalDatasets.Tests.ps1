Describe 'Additional dataset implementations' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../modules/Genesys.Core/Genesys.Core.psd1" -Force
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Datasets.ps1"
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'
    }

    It 'registers users and routing-queues datasets' {
        $registry = Get-DatasetRegistry
        $registry.ContainsKey('users') | Should -BeTrue
        $registry.ContainsKey('routing-queues') | Should -BeTrue
    }

    It 'runs users dataset with nextUri paging and normalized output' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-users'
        $script:userMaxRetries = [System.Collections.Generic.List[int]]::new()
        $requestInvoker = {
            param($request)
            $script:userMaxRetries.Add([int]$request.MaxRetries) | Out-Null
            if ($request.Uri -like 'https://api.test.local/api/v2/users*pageNumber=1*') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @(
                        [pscustomobject]@{ id='u1'; name='user-record-1'; email='redacted-user-1'; state='active'; presence=[pscustomobject]@{ presenceDefinition=[pscustomobject]@{ systemPresence='AVAILABLE' } }; routingStatus=[pscustomobject]@{ status='IDLE' } }
                    )
                    nextUri = 'https://api.test.local/api/v2/users?pageNumber=2'
                } }
            }
            if ($request.Uri -eq 'https://api.test.local/api/v2/users?pageNumber=2') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @(
                        [pscustomobject]@{ id='u2'; name='user-record-2'; email='redacted-user-2'; state='inactive'; presence=[pscustomobject]@{ presenceDefinition=[pscustomobject]@{ systemPresence='OFFLINE' } }; routingStatus=[pscustomobject]@{ status='NOT_RESPONDING' } }
                    )
                    nextUri = $null
                } }
            }
            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'users' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null
        $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'users') -Directory | Select-Object -First 1
        $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/users.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        $records.Count | Should -Be 2
        $records[0].recordType | Should -Be 'user'
        $records[0].presence | Should -Be 'AVAILABLE'

        $events = Get-Content -Path (Join-Path $runFolder.FullName 'events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        (@($events | Where-Object { $_.eventType -eq 'paging.progress' })).Count | Should -Be 2
        ($script:userMaxRetries | Select-Object -Unique).Count | Should -Be 1
        ($script:userMaxRetries | Select-Object -First 1) | Should -Be 4
    }

    It 'runs routing-queues dataset and normalizes records' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-queues'
        $script:queueMaxRetries = [System.Collections.Generic.List[int]]::new()
        $requestInvoker = {
            param($request)
            $script:queueMaxRetries.Add([int]$request.MaxRetries) | Out-Null
            if ($request.Uri -like 'https://api.test.local/api/v2/routing/queues*pageNumber=1*') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @(
                        [pscustomobject]@{ id='q1'; name='Support'; memberCount=12; joined=$true; division=[pscustomobject]@{ id='d1' } }
                    )
                    nextUri = $null
                } }
            }
            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'routing-queues' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null
        $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'routing-queues') -Directory | Select-Object -First 1
        $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/routing-queues.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        $records.Count | Should -Be 1
        $records[0].recordType | Should -Be 'routingQueue'
        $records[0].divisionId | Should -Be 'd1'
        ($script:queueMaxRetries | Select-Object -Unique).Count | Should -Be 1
        ($script:queueMaxRetries | Select-Object -First 1) | Should -Be 4
    }

    It 'runs catalog-defined dataset that is not explicitly registered' {
        $catalogPath = Join-Path -Path $TestDrive -ChildPath 'dynamic.catalog.json'
        $catalog = [ordered]@{
            version = '1.0.0'
            datasets = [ordered]@{
                'dynamic-users' = [ordered]@{
                    endpoint = 'dynamic.users'
                    itemsPath = '$.entities'
                    paging = [ordered]@{ profile = 'nextUri_default' }
                    retry = [ordered]@{ profile = 'default' }
                }
            }
            profiles = [ordered]@{
                paging = [ordered]@{
                    nextUri_default = [ordered]@{
                        type = 'nextUri'
                        nextUriPath = '$.nextUri'
                    }
                }
                retry = [ordered]@{
                    default = [ordered]@{
                        mode = 'rateLimitAware'
                        maxRetries = 1
                        baseDelaySeconds = 0
                        maxDelaySeconds = 0
                        jitterSeconds = 0
                        retryOnStatusCodes = @(429)
                        retryOnMethods = @('GET')
                    }
                }
            }
            endpoints = [ordered]@{
                'dynamic.users' = [ordered]@{
                    method = 'GET'
                    path = '/api/v2/users'
                    pagingProfile = 'nextUri_default'
                    retryProfile = 'default'
                    itemsPath = '$.entities'
                }
            }
        }
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $catalogPath

        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-dynamic'
        $requestInvoker = {
            param($request)
            if ($request.Uri -eq 'https://api.test.local/api/v2/users') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @(
                        [pscustomobject]@{ id = 'd1'; name = 'dynamic-user-record' }
                    )
                    nextUri = $null
                } }
            }

            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'dynamic-users' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null
        $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'dynamic-users') -Directory | Select-Object -First 1
        $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/dynamic-users.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        $records.Count | Should -Be 1
        $records[0].id | Should -Be 'd1'
    }

    It 'applies endpoint defaultQueryParams to route and query values for generic datasets' {
        $catalogPath = Join-Path -Path $TestDrive -ChildPath 'route.catalog.json'
        $catalog = [ordered]@{
            version = '1.0.0'
            datasets = [ordered]@{
                'dynamic-route' = [ordered]@{
                    endpoint = 'dynamic.route'
                    itemsPath = '$.entities'
                    paging = [ordered]@{ profile = 'none' }
                    retry = [ordered]@{ profile = 'default' }
                }
            }
            profiles = [ordered]@{
                paging = [ordered]@{
                    none = [ordered]@{ type = 'none' }
                }
                retry = [ordered]@{
                    default = [ordered]@{
                        mode = 'rateLimitAware'
                        maxRetries = 1
                        baseDelaySeconds = 0
                        maxDelaySeconds = 0
                        jitterSeconds = 0
                        retryOnStatusCodes = @(429)
                        retryOnMethods = @('GET')
                    }
                }
            }
            endpoints = [ordered]@{
                'dynamic.route' = [ordered]@{
                    method = 'GET'
                    path = '/api/v2/users/{userId}'
                    pagingProfile = 'none'
                    retryProfile = 'default'
                    itemsPath = '$.entities'
                    defaultQueryParams = [ordered]@{
                        userId = 'abc-123'
                        expand = 'routingStatus'
                    }
                }
            }
        }
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $catalogPath

        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-route'
        $requestInvoker = {
            param($request)
            if ($request.Uri -eq 'https://api.test.local/api/v2/users/abc-123?expand=routingStatus') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @(
                        [pscustomobject]@{ id = 'abc-123'; state = 'active' }
                    )
                } }
            }

            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'dynamic-route' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null
        $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'dynamic-route') -Directory | Select-Object -First 1
        $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/dynamic-route.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        $records.Count | Should -Be 1
        $records[0].id | Should -Be 'abc-123'
    }


    It 'applies DatasetParameters.Query overrides for generic datasets' {
        $catalogPath = Join-Path -Path $TestDrive -ChildPath 'query-override.catalog.json'
        $catalog = [ordered]@{
            version = '1.0.0'
            datasets = [ordered]@{
                'dynamic-query-override' = [ordered]@{
                    endpoint = 'dynamic.query.override'
                    itemsPath = '$.entities'
                    paging = [ordered]@{ profile = 'none' }
                    retry = [ordered]@{ profile = 'default' }
                }
            }
            profiles = [ordered]@{
                paging = [ordered]@{
                    none = [ordered]@{ type = 'none' }
                }
                retry = [ordered]@{
                    default = [ordered]@{
                        mode = 'rateLimitAware'
                        maxRetries = 1
                        baseDelaySeconds = 0
                        maxDelaySeconds = 0
                        jitterSeconds = 0
                        retryOnStatusCodes = @(429)
                        retryOnMethods = @('GET')
                    }
                }
            }
            endpoints = [ordered]@{
                'dynamic.query.override' = [ordered]@{
                    method = 'GET'
                    path = '/api/v2/users'
                    pagingProfile = 'none'
                    retryProfile = 'default'
                    itemsPath = '$.entities'
                    defaultQueryParams = [ordered]@{
                        pageSize = 25
                        state = 'active'
                    }
                }
            }
        }
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $catalogPath

        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-query-override'
        $requestInvoker = {
            param($request)
            if ($request.Uri -eq 'https://api.test.local/api/v2/users?pageSize=100&state=inactive') {
                return [pscustomobject]@{ Result = [pscustomobject]@{ entities = @([pscustomobject]@{ id = 'u-override' }) } }
            }

            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'dynamic-query-override' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -DatasetParameters @{ Query = @{ pageSize = 100; state = 'inactive' } } -RequestInvoker $requestInvoker | Out-Null
        $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'dynamic-query-override') -Directory | Select-Object -First 1
        $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/dynamic-query-override.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        $records.Count | Should -Be 1
        $records[0].id | Should -Be 'u-override'
    }
}


