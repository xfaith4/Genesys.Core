### BEGIN: InvokeWithRetry
function Get-GcHttpStatusCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )

    if ($null -ne $Exception.Response -and $null -ne $Exception.Response.StatusCode) {
        return [int]$Exception.Response.StatusCode
    }

    return $null
}

function Get-GcRetryAfterSeconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $retryAfterSeconds = $null

    if ($null -ne $Exception.Response -and $null -ne $Exception.Response.Headers) {
        $headers = $Exception.Response.Headers
        $retryAfterHeader = $null

        if ($headers -is [System.Collections.IDictionary]) {
            $retryAfterHeader = $headers['Retry-After']
        }
        elseif ($headers.PSObject.Properties.Name -contains 'Retry-After') {
            $retryAfterHeader = $headers.'Retry-After'
        }

        if ([string]::IsNullOrWhiteSpace([string]$retryAfterHeader) -eq $false) {
            $secondsValue = 0
            if ([int]::TryParse([string]$retryAfterHeader, [ref]$secondsValue)) {
                return [Math]::Max(0, $secondsValue)
            }

            $retryAfterDate = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse([string]$retryAfterHeader, [ref]$retryAfterDate)) {
                $deltaSeconds = [Math]::Ceiling(($retryAfterDate - [DateTimeOffset]::UtcNow).TotalSeconds)
                return [Math]::Max(0, [int]$deltaSeconds)
            }
        }
    }

    $regexMatch = [regex]::Match($Message, 'Retry the request in\s*\[?(\d+)\]?\s*seconds', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($regexMatch.Success) {
        return [int]$regexMatch.Groups[1].Value
    }

    return $retryAfterSeconds
}

function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,

        [ValidateNotNullOrEmpty()]
        [string]$Method = 'GET',

        [ValidateRange(0, 100)]
        [int]$MaxRetries = 3,

        [ValidateRange(0, 600)]
        [double]$BaseDelaySeconds = 1,

        [ValidateRange(0, 3600)]
        [double]$MaxDelaySeconds = 60,

        [ValidateRange(0, 30)]
        [double]$JitterSeconds = 0.25,

        [switch]$AllowRetryOnPost,

        [int[]]$RetryOnStatusCodes = @(429),

        [string[]]$RetryOnMethods = @('GET', 'HEAD', 'OPTIONS'),

        [scriptblock]$SleepAction = { param([double]$Seconds) Start-Sleep -Seconds $Seconds },

        [System.Collections.Generic.List[object]]$RunEvents,

        [int]$RandomSeed = 17,

        [scriptblock]$JitterCalculator
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    $normalizedMethod = $Method.ToUpperInvariant()
    $allowedMethods = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($retryMethod in @($RetryOnMethods)) {
        if ([string]::IsNullOrWhiteSpace([string]$retryMethod)) {
            continue
        }

        $allowedMethods.Add(([string]$retryMethod).ToUpperInvariant()) | Out-Null
    }

    if ($allowedMethods.Count -eq 0) {
        $allowedMethods.Add('GET') | Out-Null
        $allowedMethods.Add('HEAD') | Out-Null
        $allowedMethods.Add('OPTIONS') | Out-Null
    }

    if ($AllowRetryOnPost) {
        $allowedMethods.Add('POST') | Out-Null
    }
    else {
        $allowedMethods.Remove('POST') | Out-Null
    }

    $retryableStatuses = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($status in @($RetryOnStatusCodes)) {
        if ($null -eq $status) {
            continue
        }

        $retryableStatuses.Add([int]$status) | Out-Null
    }

    if ($retryableStatuses.Count -eq 0) {
        $retryableStatuses.Add(429) | Out-Null
    }

    $retryableMethod = $allowedMethods.Contains($normalizedMethod)
    $attempt = 0
    $random = [System.Random]::new($RandomSeed)

    while ($true) {
        $attempt++
        try {
            $result = & $Operation
            $RunEvents.Add([pscustomobject]@{
                eventType = 'request.attempt.succeeded'
                attempt = $attempt
                method = $normalizedMethod
                timestampUtc = [DateTime]::UtcNow.ToString('o')
            })

            return [pscustomobject]@{
                Result = $result
                Attempts = $attempt
                Events = $RunEvents
            }
        }
        catch {
            $exception = $_.Exception
            $statusCode = Get-GcHttpStatusCode -Exception $exception
            $message = [string]$exception.Message
            $isRetryableStatus = $null -ne $statusCode -and $retryableStatuses.Contains([int]$statusCode)
            $isRetryableError = $retryableMethod -and $isRetryableStatus
            $maxAttempts = $MaxRetries + 1

            if ($isRetryableError -eq $false -or $attempt -ge $maxAttempts) {
                $RunEvents.Add([pscustomobject]@{
                    eventType = 'request.attempt.failed'
                    attempt = $attempt
                    method = $normalizedMethod
                    statusCode = $statusCode
                    retryable = $isRetryableError
                    timestampUtc = [DateTime]::UtcNow.ToString('o')
                })

                throw
            }

            $retryAfterSeconds = Get-GcRetryAfterSeconds -Exception $exception -Message $message
            $backoff = [Math]::Min($MaxDelaySeconds, $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1))
            if ($null -ne $retryAfterSeconds) {
                $backoff = [Math]::Min($MaxDelaySeconds, [double]$retryAfterSeconds)
            }

            $jitterOffset = 0
            if ($JitterSeconds -gt 0) {
                if ($null -ne $JitterCalculator) {
                    $jitterOffset = [double](& $JitterCalculator ([pscustomobject]@{
                        attempt = $attempt
                        backoff = $backoff
                        jitterSeconds = $JitterSeconds
                        random = $random
                    }))
                }
                else {
                    $jitterOffset = ($random.NextDouble() * 2 - 1) * $JitterSeconds
                }
            }

            $delaySeconds = [Math]::Max(0, [Math]::Round($backoff + $jitterOffset, 3))

            $RunEvents.Add([pscustomobject]@{
                eventType = 'request.retry.scheduled'
                attempt = $attempt
                method = $normalizedMethod
                statusCode = $statusCode
                delaySeconds = $delaySeconds
                retryAfterSeconds = $retryAfterSeconds
                timestampUtc = [DateTime]::UtcNow.ToString('o')
            })

            & $SleepAction $delaySeconds
        }
    }
}
### END: InvokeWithRetry
