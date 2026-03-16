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

        [System.Collections.Generic.List[object]]$RunEvents
    )

    if ($null -eq $RunEvents) {
        $RunEvents = [System.Collections.Generic.List[object]]::new()
    }

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

    $RunEvents.Add([pscustomobject]@{
        eventType = 'request.invoked'
        method = $Method.ToUpperInvariant()
        uri = (Protect-GcUri -Uri $Uri)
        headers = $sanitizedHeaders
        timestampUtc = [DateTime]::UtcNow.ToString('o')
    })

    $hasBody = $PSBoundParameters.ContainsKey('Body')

    $operation = {
        $invokeParams = @{
            Uri = $Uri
            Method = $Method
            TimeoutSec = $TimeoutSec
            ErrorAction = 'Stop'
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

        Invoke-RestMethod @invokeParams
    }.GetNewClosure()

    Invoke-WithRetry -Operation $operation -Method $Method -MaxRetries $MaxRetries -BaseDelaySeconds $BaseDelaySeconds -MaxDelaySeconds $MaxDelaySeconds -JitterSeconds $JitterSeconds -AllowRetryOnPost:$AllowRetryOnPost -RetryOnStatusCodes $RetryOnStatusCodes -RetryOnMethods $RetryOnMethods -RandomSeed $RandomSeed -RunEvents $RunEvents
}
### END: InvokeGcRequest
