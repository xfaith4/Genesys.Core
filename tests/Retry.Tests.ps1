Describe 'Invoke-WithRetry' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1"
    }

    It 'parses Retry-After header seconds for 429 responses' {
        $exception = [System.Exception]::new('Too many requests')
        $exception | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
            StatusCode = 429
            Headers = @{ 'Retry-After' = '7' }
        })

        $retryAfter = Get-GcRetryAfterSeconds -Exception $exception -Message $exception.Message

        $retryAfter | Should -Be 7
    }

    It 'parses retry seconds from service message when header is absent' {
        $exception = [System.Exception]::new('Rate limit exceeded. Retry the request in [11] seconds')
        $exception | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
            StatusCode = 429
            Headers = @{}
        })

        $retryAfter = Get-GcRetryAfterSeconds -Exception $exception -Message $exception.Message

        $retryAfter | Should -Be 11
    }

    It 'bounds retries and emits retry events for GET' {
        $attempt = 0
        $runEvents = [System.Collections.Generic.List[object]]::new()
        $sleepDelays = [System.Collections.Generic.List[double]]::new()

        $operation = {
            $attempt++
            if ($attempt -lt 3) {
                $error = [System.Exception]::new('Retry the request in [1] seconds')
                $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                    StatusCode = 429
                    Headers = @{}
                })
                throw $error
            }

            return @{ ok = $true }
        }

        $result = Invoke-WithRetry -Operation $operation -Method GET -MaxRetries 2 -JitterSeconds 0 -RunEvents $runEvents -SleepAction {
            param([double]$Seconds)
            $sleepDelays.Add($Seconds) | Out-Null
        }

        $result.Attempts | Should -Be 3
        $sleepDelays.Count | Should -Be 2
        $sleepDelays[0] | Should -Be 1
        $sleepDelays[1] | Should -Be 1
        ($runEvents | Where-Object { $_.eventType -eq 'request.retry.scheduled' }).Count | Should -Be 2
    }

    It 'does not retry POST by default' {
        $attempt = 0
        $runEvents = [System.Collections.Generic.List[object]]::new()

        {
            Invoke-WithRetry -Operation {
                $attempt++
                $error = [System.Exception]::new('Retry the request in [5] seconds')
                $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                    StatusCode = 429
                    Headers = @{}
                })
                throw $error
            } -Method POST -MaxRetries 4 -JitterSeconds 0 -RunEvents $runEvents -SleepAction { }
        } | Should -Throw

        $attempt | Should -Be 1
        ($runEvents | Where-Object { $_.eventType -eq 'request.retry.scheduled' }).Count | Should -Be 0
    }
}
