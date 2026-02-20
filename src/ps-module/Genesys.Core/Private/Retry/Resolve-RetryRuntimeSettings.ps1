function Resolve-RetryRuntimeSettings {
    [CmdletBinding()]
    param(
        [psobject]$RetryProfile
    )

    $maxRetries = 3
    $baseDelaySeconds = 1.0
    $maxDelaySeconds = 60.0
    $jitterSeconds = 0.25
    $allowRetryOnPost = $false
    $retryOnStatusCodes = @(429)
    $retryOnMethods = @('GET', 'HEAD', 'OPTIONS')
    $randomSeed = 17

    if ($null -ne $RetryProfile) {
        if ($RetryProfile.PSObject.Properties.Name -contains 'maxRetries') {
            $maxRetries = [int]$RetryProfile.maxRetries
        }

        if ($RetryProfile.PSObject.Properties.Name -contains 'baseDelaySeconds') {
            $baseDelaySeconds = [double]$RetryProfile.baseDelaySeconds
        }

        if ($RetryProfile.PSObject.Properties.Name -contains 'maxDelaySeconds') {
            $maxDelaySeconds = [double]$RetryProfile.maxDelaySeconds
        }

        if ($RetryProfile.PSObject.Properties.Name -contains 'jitterSeconds') {
            $jitterSeconds = [double]$RetryProfile.jitterSeconds
        }

        if ($RetryProfile.PSObject.Properties.Name -contains 'retryOnStatusCodes' -and $null -ne $RetryProfile.retryOnStatusCodes) {
            $statusCodeList = [System.Collections.Generic.List[int]]::new()
            foreach ($statusCode in @($RetryProfile.retryOnStatusCodes)) {
                if ($null -eq $statusCode) {
                    continue
                }

                $statusCodeList.Add([int]$statusCode) | Out-Null
            }

            if ($statusCodeList.Count -gt 0) {
                $retryOnStatusCodes = @($statusCodeList)
            }
        }

        if ($RetryProfile.PSObject.Properties.Name -contains 'retryOnMethods' -and $null -ne $RetryProfile.retryOnMethods) {
            $methodSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($method in @($RetryProfile.retryOnMethods)) {
                if ([string]::IsNullOrWhiteSpace([string]$method)) {
                    continue
                }

                $methodSet.Add(([string]$method).ToUpperInvariant()) | Out-Null
            }

            if ($methodSet.Count -gt 0) {
                $retryOnMethods = @($methodSet)
            }
        }

        if ($RetryProfile.PSObject.Properties.Name -contains 'allowRetryOnPost' -and $null -ne $RetryProfile.allowRetryOnPost) {
            $allowRetryOnPost = [bool]$RetryProfile.allowRetryOnPost
        }

        if ($RetryProfile.PSObject.Properties.Name -contains 'randomSeed' -and $null -ne $RetryProfile.randomSeed) {
            $randomSeed = [int]$RetryProfile.randomSeed
        }
    }

    if ($allowRetryOnPost) {
        if (@($retryOnMethods | Where-Object { $_ -eq 'POST' }).Count -eq 0) {
            $retryOnMethods = @($retryOnMethods + @('POST'))
        }
    }
    else {
        $retryOnMethods = @($retryOnMethods | Where-Object { $_ -ne 'POST' })
    }

    return [pscustomobject]@{
        maxRetries = $maxRetries
        baseDelaySeconds = $baseDelaySeconds
        maxDelaySeconds = $maxDelaySeconds
        jitterSeconds = $jitterSeconds
        allowRetryOnPost = $allowRetryOnPost
        retryOnStatusCodes = @($retryOnStatusCodes)
        retryOnMethods = @($retryOnMethods)
        randomSeed = $randomSeed
    }
}
