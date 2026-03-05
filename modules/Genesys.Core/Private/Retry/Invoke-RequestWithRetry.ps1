function Invoke-RequestWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Request,

        [psobject]$RetrySettings,

        [scriptblock]$RequestInvoker,

        [System.Collections.Generic.List[object]]$RunEvents,

        [scriptblock]$SleepAction
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    if ($null -eq $RetrySettings) {
        $RetrySettings = Resolve-RetryRuntimeSettings
    }

    $effectiveMethod = 'GET'
    if ($Request.PSObject.Properties.Name -contains 'Method' -and [string]::IsNullOrWhiteSpace([string]$Request.Method) -eq $false) {
        $effectiveMethod = [string]$Request.Method
    }

    if ($null -eq $RequestInvoker) {
        return Invoke-GcRequest -Uri $Request.Uri -Method $effectiveMethod -Headers $Request.Headers -Body $Request.Body -MaxRetries $RetrySettings.maxRetries -BaseDelaySeconds $RetrySettings.baseDelaySeconds -MaxDelaySeconds $RetrySettings.maxDelaySeconds -JitterSeconds $RetrySettings.jitterSeconds -AllowRetryOnPost:$RetrySettings.allowRetryOnPost -RetryOnStatusCodes $RetrySettings.retryOnStatusCodes -RetryOnMethods $RetrySettings.retryOnMethods -RandomSeed $RetrySettings.randomSeed -RunEvents $RunEvents
    }

    $requestData = [ordered]@{}
    foreach ($property in $Request.PSObject.Properties) {
        $requestData[$property.Name] = $property.Value
    }

    $requestData['MaxRetries'] = $RetrySettings.maxRetries
    $requestData['BaseDelaySeconds'] = $RetrySettings.baseDelaySeconds
    $requestData['MaxDelaySeconds'] = $RetrySettings.maxDelaySeconds
    $requestData['JitterSeconds'] = $RetrySettings.jitterSeconds
    $requestData['AllowRetryOnPost'] = $RetrySettings.allowRetryOnPost
    $requestData['RetryOnStatusCodes'] = $RetrySettings.retryOnStatusCodes
    $requestData['RetryOnMethods'] = $RetrySettings.retryOnMethods
    $requestData['RandomSeed'] = $RetrySettings.randomSeed
    $requestData['RunEvents'] = $RunEvents
    $requestForInvoker = [pscustomobject]$requestData

    $operation = {
        $result = & $RequestInvoker $requestForInvoker
        if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Result') {
            return $result.Result
        }

        return $result
    }.GetNewClosure()

    $retryParams = @{
        Operation = $operation
        Method = $effectiveMethod
        MaxRetries = $RetrySettings.maxRetries
        BaseDelaySeconds = $RetrySettings.baseDelaySeconds
        MaxDelaySeconds = $RetrySettings.maxDelaySeconds
        JitterSeconds = $RetrySettings.jitterSeconds
        AllowRetryOnPost = $RetrySettings.allowRetryOnPost
        RetryOnStatusCodes = $RetrySettings.retryOnStatusCodes
        RetryOnMethods = $RetrySettings.retryOnMethods
        RunEvents = $RunEvents
        RandomSeed = $RetrySettings.randomSeed
    }

    if ($null -ne $SleepAction) {
        $retryParams['SleepAction'] = $SleepAction
    }

    return Invoke-WithRetry @retryParams
}
