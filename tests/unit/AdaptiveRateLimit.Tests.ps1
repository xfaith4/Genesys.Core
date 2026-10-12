Describe 'Adaptive endpoint pacing' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Transport.ps1"
        function New-RateLimitError {
            param([string]$RetryAfter = '5', [int]$Status = 429)
            $error = [Exception]::new('Throttled')
            $error | Add-Member NoteProperty Response ([pscustomobject]@{
                StatusCode = $Status; Headers = @{ 'Retry-After' = $RetryAfter }
            })
            return $error
        }
        function Invoke-PacedTest {
            param([scriptblock]$Operation = { 'ok' }, [string]$Endpoint = 'users',
                [string]$Uri = 'https://example.test/api/v2/users?pageNumber=1',
                [string]$Method = 'GET', [int]$MaxRetries = 0)
            Invoke-WithRetry -Operation $Operation -EndpointKey $Endpoint -RequestUri $Uri `
                -Method $Method -MaxRetries $MaxRetries -JitterSeconds 0 -RunEvents $script:events `
                -UtcNowAction { $script:now } -SleepAction {
                    param($seconds)
                    $script:delays.Add($seconds)
                    $script:now = $script:now.AddSeconds($seconds)
                }
        }
    }
    BeforeEach {
        $script:GcRateLimits = @{}
        $script:GcRateLimitCooldowns = @{}
        $script:now = [DateTimeOffset]'2026-10-11T12:00:00Z'
        $script:events = [System.Collections.Generic.List[object]]::new()
        $script:delays = [System.Collections.Generic.List[double]]::new()
    }
    It 'records a final 429 and paces later pages of the same endpoint' {
        { Invoke-PacedTest -Operation { throw (New-RateLimitError) } } | Should -Throw
        Invoke-PacedTest -Uri 'https://example.test/api/v2/users?pageNumber=2' | Out-Null
        Invoke-PacedTest | Out-Null
        $script:delays.Count | Should -Be 2
        $script:delays[0] | Should -Be 5
        $script:delays[1] | Should -Be 1
        $observed = @($script:events | Where-Object eventType -eq 'request.rateLimit.observed')
        $observed.Count | Should -Be 1
        $observed[0].endpointKey | Should -Be 'users'
        $observed[0].total429 | Should -Be 1
    }
    It 'doubles learned spacing after repeated 429s' {
        { Invoke-PacedTest -Operation { throw (New-RateLimitError '0') } } | Should -Throw
        { Invoke-PacedTest -Operation { throw (New-RateLimitError '0') } } | Should -Throw
        Invoke-PacedTest | Out-Null
        $script:delays[0] | Should -Be 1
        $script:delays[1] | Should -Be 2
        $state = @($script:GcRateLimits.Values)[0]
        $state.count | Should -Be 2
        $state.interval | Should -Be 2
    }
    It 'shares server cooldown but does not transfer endpoint spacing' {
        { Invoke-PacedTest -Operation { throw (New-RateLimitError) } } | Should -Throw
        Invoke-PacedTest -Endpoint 'queues' -Uri 'https://example.test/api/v2/routing/queues' | Out-Null
        Invoke-PacedTest -Endpoint 'queues' -Uri 'https://example.test/api/v2/routing/queues' | Out-Null
        $script:delays.Count | Should -Be 1
        $script:delays[0] | Should -Be 5
    }
    It 'isolates different servers' {
        { Invoke-PacedTest -Operation { throw (New-RateLimitError) } } | Should -Throw
        Invoke-PacedTest -Uri 'https://other.test/api/v2/users' | Out-Null
        $script:delays.Count | Should -Be 0
    }
    It 'records nonretryable POSTs without resubmitting them' {
        $script:attempts = 0
        { Invoke-PacedTest -Method POST -MaxRetries 3 -Operation {
            $script:attempts++; throw (New-RateLimitError)
        } } | Should -Throw
        $script:attempts | Should -Be 1
        @($script:events | Where-Object eventType -eq 'request.rateLimit.observed').Count | Should -Be 1
    }
    It 'recovers gradually after twenty successful requests' {
        { Invoke-PacedTest -Operation { throw (New-RateLimitError) } } | Should -Throw
        1..20 | ForEach-Object { Invoke-PacedTest | Out-Null }
        @($script:GcRateLimits.Values)[0].interval | Should -Be 0.9
    }
    It 'honors Retry-After beyond the retry cap and despite negative jitter' {
        $script:attempts = 0
        Invoke-WithRetry -Operation {
            $script:attempts++
            if ($script:attempts -eq 1) { throw (New-RateLimitError '120') }
            'ok'
        } -MaxRetries 1 -MaxDelaySeconds 10 -JitterSeconds 1 -JitterCalculator { -1 } `
            -SleepAction { param($seconds) $script:delays.Add($seconds) } | Out-Null
        $script:delays[0] | Should -Be 120
    }
    It 'reads PowerShell 7 HTTP response headers' {
        $response = [System.Net.Http.HttpResponseMessage]::new()
        $response.Headers.TryAddWithoutValidation('Retry-After', '75') | Out-Null
        $error = [Exception]::new('Throttled')
        $error | Add-Member NoteProperty Response $response
        Get-GcRetryAfterSeconds -Exception $error -Message 'Throttled' | Should -Be 75
        $response.Dispose()
    }
    It 'groups catalog routes across resource IDs and ignores query strings' {
        $a = Get-GcRateLimitIdentity -Uri 'https://example.test/api/v2/users/one?x=1' -Method GET -EndpointKey 'user.detail'
        $b = Get-GcRateLimitIdentity -Uri 'https://example.test/api/v2/users/two?x=2' -Method GET -EndpointKey 'user.detail'
        $a.key | Should -Be $b.key
        $c = Get-GcRateLimitIdentity -Uri 'https://example.test/api/v2/users?x=2' -Method GET
        $d = Get-GcRateLimitIdentity -Uri 'https://example.test/api/v2/users?x=3' -Method GET
        $c.key | Should -Be $d.key
    }
    It 'does not learn endpoint pacing from a 503' {
        { Invoke-PacedTest -Operation { throw (New-RateLimitError '5' 503) } } | Should -Throw
        Invoke-PacedTest | Out-Null
        $script:delays.Count | Should -Be 0
        @($script:events | Where-Object eventType -eq 'request.rateLimit.observed').Count | Should -Be 0
    }
    It 'preserves fractional waits on Windows PowerShell-compatible sleep calls' {
        Mock Start-Sleep { }
        Wait-GcRequestDelay -Seconds 0.125
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 125 }
    }
    It 'passes endpoint identity through the HTTP transport path' {
        Mock Invoke-WithRetry { [pscustomobject]@{ Result = @{ ok = $true }; Attempts = 1 } }
        Invoke-GcRequest -Uri 'https://transport.test/api/v2/users' -EndpointKey 'users' `
            -MaxRetries 0 -RunEvents $script:events | Out-Null
        Should -Invoke Invoke-WithRetry -Times 1 -Exactly -ParameterFilter {
            $EndpointKey -eq 'users' -and $RequestUri -eq 'https://transport.test/api/v2/users'
        }
    }
    It 'writes a durable journal even when the dataset fails' {
        Import-Module "$PSScriptRoot/../../modules/Genesys.Core/Genesys.Core.psd1" -Force
        Mock Wait-GcRequestDelay { } -ModuleName Genesys.Core
        $outputRoot = Join-Path $TestDrive 'failed-rate-limit'
        { Invoke-Dataset -Dataset users -OutputRoot $outputRoot -BaseUri 'https://journal.test' `
            -RequestInvoker {
                $failure = [Exception]::new('Throttled')
                $failure | Add-Member NoteProperty Response ([pscustomobject]@{
                    StatusCode = 429; Headers = @{ 'Retry-After' = '0' }
                })
                throw $failure
            } } | Should -Throw
        $journal = @(Get-ChildItem $outputRoot -Recurse -Filter 'rate-limits.jsonl')
        $journal.Count | Should -Be 1
        $entries = @(Get-Content $journal[0].FullName | ForEach-Object { $_ | ConvertFrom-Json })
        $entries.Count | Should -BeGreaterThan 0
        $entries[0].statusCode | Should -Be 429
        $entries[0].endpointKey | Should -Be 'users.get.all.users.with.presence.and.status'
        $entries[0].timestampUtc | Should -Not -BeNullOrEmpty
    }

}
