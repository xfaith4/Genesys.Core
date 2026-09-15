function Join-EndpointUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUri,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [hashtable]$RouteValues
    )

    $normalizedBase = $BaseUri.Trim()
    if ($normalizedBase -notmatch '^https?://') {
        throw "BaseUri '$normalizedBase' is not a valid absolute URI. It must begin with 'https://' or 'http://'."
    }

    $resolvedPath = $Path
    if ($null -ne $RouteValues) {
        foreach ($key in $RouteValues.Keys) {
            $resolvedPath = $resolvedPath.Replace("{$($key)}", [string]$RouteValues[$key])
        }
    }

    if ($resolvedPath.StartsWith('http://') -or $resolvedPath.StartsWith('https://')) {
        return $resolvedPath
    }

    $trimmedBase = $normalizedBase.TrimEnd('/')
    if ($resolvedPath.StartsWith('/')) {
        return "$($trimmedBase)$($resolvedPath)"
    }

    return "$($trimmedBase)/$($resolvedPath)"
}

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

function Write-GcProgressMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Host "[Genesys.Core] $Message"
}

function Get-GcHeaderValue {
    [CmdletBinding()]
    param(
        [object]$Headers,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $Headers) {
        return $null
    }

    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if ([string]$key -eq $Name) {
                return $Headers[$key]
            }
        }
    }

    foreach ($property in $Headers.PSObject.Properties) {
        if ($property.Name -eq $Name) {
            return $property.Value
        }
    }

    return $null
}

function Get-GcResponseMetrics {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Response,

        [object]$ResponseHeaders
    )

    $responseItemCount = $null
    if ($null -eq $Response) {
        $responseItemCount = 0
    }
    elseif ($Response -is [string]) {
        $responseItemCount = $null
    }
    elseif ($Response -is [System.Collections.IEnumerable] -and $Response -isnot [System.Collections.IDictionary]) {
        $responseItemCount = @($Response).Count
    }
    else {
        foreach ($propertyName in @('results', 'conversations', 'entities', 'items')) {
            if ($Response.PSObject.Properties.Name -contains $propertyName -and $null -ne $Response.$propertyName) {
                $responseItemCount = @($Response.$propertyName).Count
                break
            }
        }
    }

    $responseBytes = $null
    $contentLength = Get-GcHeaderValue -Headers $ResponseHeaders -Name 'Content-Length'
    if ($null -ne $contentLength -and [string]::IsNullOrWhiteSpace([string]$contentLength) -eq $false) {
        $parsedLength = 0L
        if ([long]::TryParse([string]$contentLength, [ref]$parsedLength)) {
            $responseBytes = $parsedLength
        }
    }

    if ($null -eq $responseBytes -and $null -ne $Response) {
        try {
            $responseJson = $Response | ConvertTo-Json -Depth 50 -Compress
            $responseBytes = [System.Text.Encoding]::UTF8.GetByteCount([string]$responseJson)
        }
        catch {
            $responseBytes = $null
        }
    }

    return [pscustomobject]@{
        responseBytes = $responseBytes
        responseItemCount = $responseItemCount
    }
}

function Add-GcRequestInvokedEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [string]$EndpointKey,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [hashtable]$Headers
    )

    $sanitizedHeaders = @{}
    if ($null -ne $Headers) {
        foreach ($headerKey in $Headers.Keys) {
            if ($headerKey -match 'Authorization|Token|Secret') {
                $sanitizedHeaders[$headerKey] = '[REDACTED]'
            }
            else {
                $sanitizedHeaders[$headerKey] = $Headers[$headerKey]
            }
        }
    }

    $safeUri = Protect-GcUri -Uri $Uri
    $RunEvents.Add([pscustomobject]@{
        eventType = 'request.invoked'
        endpointKey = $EndpointKey
        method = $Method.ToUpperInvariant()
        uri = $safeUri
        headers = $sanitizedHeaders
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    })

    Write-GcProgressMessage -Message "Calling $($Method.ToUpperInvariant()) $($safeUri)"
}

function Add-GcRequestCompletedEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [string]$EndpointKey,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [AllowNull()]
        [object]$Response,

        [object]$ResponseHeaders,

        [Nullable[int]]$StatusCode,

        [Nullable[int]]$Attempts,

        [Parameter(Mandatory = $true)]
        [long]$DurationMs
    )

    $metrics = Get-GcResponseMetrics -Response $Response -ResponseHeaders $ResponseHeaders
    $safeUri = Protect-GcUri -Uri $Uri

    $requestEvent = [pscustomobject]@{
        eventType = 'request.completed'
        endpointKey = $EndpointKey
        method = $Method.ToUpperInvariant()
        uri = $safeUri
        success = $true
        statusCode = $StatusCode
        durationMs = $DurationMs
        attempts = $Attempts
        responseBytes = $metrics.responseBytes
        responseItemCount = $metrics.responseItemCount
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    }

    $RunEvents.Add($requestEvent)
    Write-GcApiLogEvent -RequestEvent $requestEvent

    $itemText = if ($null -ne $metrics.responseItemCount) { ", items: $($metrics.responseItemCount)" } else { '' }
    $attemptText = if ($null -ne $Attempts) { ", attempts: $($Attempts)" } else { '' }
    Write-GcProgressMessage -Message "$($Method.ToUpperInvariant()) $($safeUri) completed in $($DurationMs) ms$($attemptText)$($itemText)."
}

function Add-GcRequestFailedEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [string]$EndpointKey,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Nullable[int]]$StatusCode,

        [Parameter(Mandatory = $true)]
        [long]$DurationMs,

        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    $safeUri = Protect-GcUri -Uri $Uri
    $requestEvent = [pscustomobject]@{
        eventType = 'request.failed'
        endpointKey = $EndpointKey
        method = $Method.ToUpperInvariant()
        uri = $safeUri
        success = $false
        statusCode = $StatusCode
        durationMs = $DurationMs
        attempts = $null
        responseBytes = $null
        responseItemCount = $null
        errorMessage = $ErrorMessage
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    }

    $RunEvents.Add($requestEvent)
    Write-GcApiLogEvent -RequestEvent $requestEvent

    Write-GcProgressMessage -Message "$($Method.ToUpperInvariant()) $($safeUri) failed after $($DurationMs) ms: $($ErrorMessage)"
}

function Write-GcApiLogEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RequestEvent
    )

    $activeRunContextVariable = Get-Variable -Name 'GcActiveRunContext' -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $activeRunContextVariable -or $null -eq $activeRunContextVariable.Value) {
        return
    }

    if (-not (Get-Command -Name 'Write-ApiCallLogEntry' -ErrorAction SilentlyContinue)) {
        return
    }

    $event = [pscustomobject]@{
        timestampUtc = $RequestEvent.timestampUtc
        datasetKey = $activeRunContextVariable.Value.datasetKey
        runId = $activeRunContextVariable.Value.runId
        eventType = $RequestEvent.eventType
        payload = $RequestEvent
    }

    Write-ApiCallLogEntry -RunContext $activeRunContextVariable.Value -Event $event | Out-Null
}

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

    $endpointKey = $null
    if ($Request.PSObject.Properties.Name -contains 'EndpointKey' -and [string]::IsNullOrWhiteSpace([string]$Request.EndpointKey) -eq $false) {
        $endpointKey = [string]$Request.EndpointKey
    }

    if ($null -eq $RequestInvoker) {
        return Invoke-GcRequest -Uri $Request.Uri -Method $effectiveMethod -Headers $Request.Headers -Body $Request.Body -EndpointKey $endpointKey -MaxRetries $RetrySettings.maxRetries -BaseDelaySeconds $RetrySettings.baseDelaySeconds -MaxDelaySeconds $RetrySettings.maxDelaySeconds -JitterSeconds $RetrySettings.jitterSeconds -AllowRetryOnPost:$RetrySettings.allowRetryOnPost -RetryOnStatusCodes $RetrySettings.retryOnStatusCodes -RetryOnMethods $RetrySettings.retryOnMethods -RandomSeed $RetrySettings.randomSeed -RunEvents $RunEvents
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

    Add-GcRequestInvokedEvent -RunEvents $RunEvents -EndpointKey $endpointKey -Method $effectiveMethod -Uri $Request.Uri -Headers $Request.Headers
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $retryResult = Invoke-WithRetry @retryParams
        $stopwatch.Stop()

        $response = $retryResult
        $attempts = $null
        if ($null -ne $retryResult -and $retryResult.PSObject.Properties.Name -contains 'Result') {
            $response = $retryResult.Result
        }
        if ($null -ne $retryResult -and $retryResult.PSObject.Properties.Name -contains 'Attempts') {
            $attempts = [int]$retryResult.Attempts
        }

        Add-GcRequestCompletedEvent -RunEvents $RunEvents -EndpointKey $endpointKey -Method $effectiveMethod -Uri $Request.Uri -Response $response -ResponseHeaders $null -StatusCode $null -Attempts $attempts -DurationMs $stopwatch.ElapsedMilliseconds
        return $retryResult
    }
    catch {
        $stopwatch.Stop()
        $errMsg = $_.Exception.Message
        if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            $errMsg = "$errMsg | body: $($_.ErrorDetails.Message)"
        }
        Add-GcRequestFailedEvent -RunEvents $RunEvents -EndpointKey $endpointKey -Method $effectiveMethod -Uri $Request.Uri -StatusCode (Get-GcHttpStatusCode -Exception $_.Exception) -DurationMs $stopwatch.ElapsedMilliseconds -ErrorMessage $errMsg
        throw
    }
}

### BEGIN: InvokeGcRequest
function Protect-GcUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri
    )

    $builder = $null
    $queryText = $null
    $pathPrefix = $null
    $isAbsolute = $true

    try {
        $builder = [System.UriBuilder]::new($Uri)
        $queryText = $builder.Query
        $pathPrefix = $builder.Uri.GetLeftPart([System.UriPartial]::Path)
    }
    catch {
        $isAbsolute = $false
        $rawUri = [string]$Uri
        $questionIndex = $rawUri.IndexOf('?')
        if ($questionIndex -lt 0) {
            return $rawUri
        }

        $pathPrefix = $rawUri.Substring(0, $questionIndex)
        if ($questionIndex -lt ($rawUri.Length - 1)) {
            $queryText = $rawUri.Substring($questionIndex + 1)
        }
        else {
            $queryText = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$queryText)) {
        if ($isAbsolute) {
            return $builder.Uri.AbsoluteUri
        }

        return $pathPrefix
    }

    $safePairs = New-Object System.Collections.Generic.List[string]
    foreach ($pair in ($queryText.TrimStart('?') -split '&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) {
            continue
        }

        $nameValue = $pair -split '=', 2
        $name = [System.Uri]::UnescapeDataString($nameValue[0])
        $value = ''
        if ($nameValue.Count -gt 1) {
            $value = [System.Uri]::UnescapeDataString($nameValue[1])
        }

        $isSensitiveName = $name -match '(?i)token|secret|authorization|password|apikey'
        $isSensitiveValue = $value -match '(?i)^Bearer\s+[A-Za-z0-9\-\._~\+\/=]+'

        $safeValue = $value
        if ($isSensitiveName -or $isSensitiveValue) {
            $safeValue = '[REDACTED]'
        }

        $safePairs.Add("$([System.Uri]::EscapeDataString($name))=$([System.Uri]::EscapeDataString($safeValue))") | Out-Null
    }

    $safeQuery = [string]::Join('&', $safePairs.ToArray())

    if ($isAbsolute) {
        $builder.Query = $safeQuery
        return $builder.Uri.AbsoluteUri
    }

    if ([string]::IsNullOrWhiteSpace($safeQuery)) {
        return $pathPrefix
    }

    return "$($pathPrefix)?$($safeQuery)"
}

function Invoke-GcRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [ValidateNotNullOrEmpty()]
        [string]$Method = 'GET',

        [hashtable]$Headers,

        [object]$Body,

        [ValidateRange(1, 600)]
        [int]$TimeoutSec = 120,

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

        [int]$RandomSeed = 17,

        [string]$EndpointKey,

        [System.Collections.Generic.List[object]]$RunEvents
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

    Add-GcRequestInvokedEvent -RunEvents $RunEvents -EndpointKey $EndpointKey -Method $Method -Uri $Uri -Headers $Headers

    $hasBody = $PSBoundParameters.ContainsKey('Body')

    $operation = {
        $gcResponseStatusCode = $null
        $gcResponseHeaders = $null
        $invokeParams = @{
            Uri = $Uri
            Method = $Method
            TimeoutSec = $TimeoutSec
            ErrorAction = 'Stop'
            StatusCodeVariable = 'gcResponseStatusCode'
            ResponseHeadersVariable = 'gcResponseHeaders'
        }

        if ($null -ne $Headers) {
            $invokeParams.Headers = $Headers
        }

        if ($hasBody) {
            $invokeParams.Body = $Body

            $hasContentTypeHeader = $false
            if ($null -ne $Headers) {
                foreach ($headerKey in $Headers.Keys) {
                    if ([string]$headerKey -match '^(?i)content-type$') {
                        $hasContentTypeHeader = $true
                        break
                    }
                }
            }

            if (-not $hasContentTypeHeader) {
                $methodName = ([string]$Method).ToUpperInvariant()
                if ($methodName -in @('POST', 'PUT', 'PATCH')) {
                    $bodyString = [string]$Body
                    $trimmedBody = $bodyString.TrimStart()
                    if ($trimmedBody.StartsWith('{') -or $trimmedBody.StartsWith('[')) {
                        $invokeParams.ContentType = 'application/json'
                    }
                }
            }
        }

        $result = Invoke-RestMethod @invokeParams
        return [pscustomobject]@{
            __gcTransportResponse = $true
            Result = $result
            StatusCode = $gcResponseStatusCode
            ResponseHeaders = $gcResponseHeaders
        }
    }.GetNewClosure()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $retryResult = Invoke-WithRetry -Operation $operation -Method $Method -MaxRetries $MaxRetries -BaseDelaySeconds $BaseDelaySeconds -MaxDelaySeconds $MaxDelaySeconds -JitterSeconds $JitterSeconds -AllowRetryOnPost:$AllowRetryOnPost -RetryOnStatusCodes $RetryOnStatusCodes -RetryOnMethods $RetryOnMethods -RandomSeed $RandomSeed -RunEvents $RunEvents
        $stopwatch.Stop()

        $response = $retryResult
        $statusCode = $null
        $responseHeaders = $null
        $attempts = $null

        if ($null -ne $retryResult -and $retryResult.PSObject.Properties.Name -contains 'Attempts') {
            $attempts = [int]$retryResult.Attempts
        }

        if ($null -ne $retryResult -and $retryResult.PSObject.Properties.Name -contains 'Result') {
            $response = $retryResult.Result
        }

        if ($null -ne $response -and $response.PSObject.Properties.Name -contains '__gcTransportResponse') {
            $statusCode = $response.StatusCode
            $responseHeaders = $response.ResponseHeaders
            $response = $response.Result

            if ($retryResult.PSObject.Properties.Name -contains 'Result') {
                $retryResult.Result = $response
            }

            if ($retryResult.PSObject.Properties.Name -notcontains 'StatusCode') {
                $retryResult | Add-Member -MemberType NoteProperty -Name StatusCode -Value $statusCode
            }
        }

        Add-GcRequestCompletedEvent -RunEvents $RunEvents -EndpointKey $EndpointKey -Method $Method -Uri $Uri -Response $response -ResponseHeaders $responseHeaders -StatusCode $statusCode -Attempts $attempts -DurationMs $stopwatch.ElapsedMilliseconds
        return $retryResult
    }
    catch {
        $stopwatch.Stop()
        $errMsg = $_.Exception.Message
        if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            $errMsg = "$errMsg | body: $($_.ErrorDetails.Message)"
        }
        Add-GcRequestFailedEvent -RunEvents $RunEvents -EndpointKey $EndpointKey -Method $Method -Uri $Uri -StatusCode (Get-GcHttpStatusCode -Exception $_.Exception) -DurationMs $stopwatch.ElapsedMilliseconds -ErrorMessage $errMsg
        throw
    }
}
### END: InvokeGcRequest
