Describe 'Invoke-WithRetry' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Retry/Resolve-RetryRuntimeSettings.ps1"
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
        $script:attempt = 0
        $runEvents = [System.Collections.Generic.List[object]]::new()
        $sleepDelays = [System.Collections.Generic.List[double]]::new()

        $operation = {
            $script:attempt++
            if ($script:attempt -lt 3) {
                $error = [System.Exception]::new('Retry the request in [1] seconds')
                $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                    StatusCode = 429
                    Headers = @{}
                })
                throw $error
            }

            return @{ ok = $true }
        }

        $result = Invoke-WithRetry -Operation $operation -Method GET -MaxRetries 2 -JitterSeconds 0 -RetryOnStatusCodes @(429, 503) -RunEvents $runEvents -SleepAction {
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
        $script:attempt = 0
        $runEvents = [System.Collections.Generic.List[object]]::new()

        {
            Invoke-WithRetry -Operation {
                $script:attempt++
                $error = [System.Exception]::new('Retry the request in [5] seconds')
                $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                    StatusCode = 429
                    Headers = @{}
                })
                throw $error
            } -Method POST -MaxRetries 4 -JitterSeconds 0 -RunEvents $runEvents -SleepAction { }
        } | Should -Throw

        $script:attempt | Should -Be 1
        ($runEvents | Where-Object { $_.eventType -eq 'request.retry.scheduled' }).Count | Should -Be 0
    }

    It 'retries 503 when status code is in retry allowlist' {
        $script:attempt = 0
        $runEvents = [System.Collections.Generic.List[object]]::new()
        $sleepDelays = [System.Collections.Generic.List[double]]::new()

        $result = Invoke-WithRetry -Operation {
            $script:attempt++
            if ($script:attempt -eq 1) {
                $error = [System.Exception]::new('Service unavailable')
                $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                    StatusCode = 503
                    Headers = @{}
                })
                throw $error
            }

            return @{ ok = $true }
        } -Method GET -MaxRetries 2 -JitterSeconds 0 -RetryOnStatusCodes @(429, 503) -RunEvents $runEvents -SleepAction {
            param([double]$Seconds)
            $sleepDelays.Add($Seconds) | Out-Null
        }

        $result.Attempts | Should -Be 2
        $sleepDelays.Count | Should -Be 1
    }

    It 'retries POST only when allowlist explicitly enables it' {
        $script:attempt = 0
        $runEvents = [System.Collections.Generic.List[object]]::new()

        $result = Invoke-WithRetry -Operation {
            $script:attempt++
            if ($script:attempt -eq 1) {
                $error = [System.Exception]::new('Retry the request in [0] seconds')
                $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                    StatusCode = 429
                    Headers = @{}
                })
                throw $error
            }

            return @{ ok = $true }
        } -Method POST -AllowRetryOnPost -RetryOnMethods @('GET', 'POST') -RetryOnStatusCodes @(429) -MaxRetries 1 -JitterSeconds 0 -RunEvents $runEvents -SleepAction { }

        $result.Attempts | Should -Be 2
        ($runEvents | Where-Object { $_.eventType -eq 'request.retry.scheduled' }).Count | Should -Be 1
    }

    It 'produces deterministic jitter delays for a fixed seed' {
        $runA = [System.Collections.Generic.List[double]]::new()
        $runB = [System.Collections.Generic.List[double]]::new()

        $script:attemptA = 0
        Invoke-WithRetry -Operation {
            $script:attemptA++
            if ($script:attemptA -le 2) {
                $error = [System.Exception]::new('Retry the request in [0] seconds')
                $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                    StatusCode = 429
                    Headers = @{}
                })
                throw $error
            }

            return @{ ok = $true }
        } -Method GET -MaxRetries 2 -BaseDelaySeconds 1 -MaxDelaySeconds 10 -JitterSeconds 0.5 -RandomSeed 99 -RunEvents ([System.Collections.Generic.List[object]]::new()) -SleepAction {
            param([double]$Seconds)
            $runA.Add($Seconds) | Out-Null
        } | Out-Null

        $script:attemptB = 0
        Invoke-WithRetry -Operation {
            $script:attemptB++
            if ($script:attemptB -le 2) {
                $error = [System.Exception]::new('Retry the request in [0] seconds')
                $error | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{
                    StatusCode = 429
                    Headers = @{}
                })
                throw $error
            }

            return @{ ok = $true }
        } -Method GET -MaxRetries 2 -BaseDelaySeconds 1 -MaxDelaySeconds 10 -JitterSeconds 0.5 -RandomSeed 99 -RunEvents ([System.Collections.Generic.List[object]]::new()) -SleepAction {
            param([double]$Seconds)
            $runB.Add($Seconds) | Out-Null
        } | Out-Null

        $runA.Count | Should -Be 2
        $runB.Count | Should -Be 2
        $runA[0] | Should -Be $runB[0]
        $runA[1] | Should -Be $runB[1]
    }

    It 'keeps POST retry disabled unless explicitly allowed in profile' {
        $settings = Resolve-RetryRuntimeSettings -RetryProfile ([pscustomobject]@{
            retryOnMethods = @('GET', 'POST')
            retryOnStatusCodes = @(429, 503)
        })

        $settings.allowRetryOnPost | Should -BeFalse
        @($settings.retryOnMethods) | Should -Not -Contain 'POST'
    }

    It 'returns full retry settings shape' {
        $settings = Resolve-RetryRuntimeSettings

        $settings.PSObject.Properties.Name | Should -Contain 'maxRetries'
        $settings.PSObject.Properties.Name | Should -Contain 'baseDelaySeconds'
        $settings.PSObject.Properties.Name | Should -Contain 'maxDelaySeconds'
        $settings.PSObject.Properties.Name | Should -Contain 'jitterSeconds'
        $settings.PSObject.Properties.Name | Should -Contain 'allowRetryOnPost'
        $settings.PSObject.Properties.Name | Should -Contain 'retryOnStatusCodes'
        $settings.PSObject.Properties.Name | Should -Contain 'retryOnMethods'
        $settings.PSObject.Properties.Name | Should -Contain 'randomSeed'
    }
}
