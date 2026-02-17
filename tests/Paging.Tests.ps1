Describe 'Paging strategies' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingNextUri.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingPageNumber.ps1"
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
}
