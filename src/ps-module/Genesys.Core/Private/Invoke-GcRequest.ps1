### BEGIN: InvokeGcRequest
function Protect-GcUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri
    )

    $builder = [System.UriBuilder]::new($Uri)
    if ([string]::IsNullOrWhiteSpace($builder.Query)) {
        return $builder.Uri.AbsoluteUri
    }

    $safePairs = New-Object System.Collections.Generic.List[string]
    foreach ($pair in ($builder.Query.TrimStart('?') -split '&')) {
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

    $builder.Query = [string]::Join('&', $safePairs.ToArray())
    return $builder.Uri.AbsoluteUri
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

        [switch]$AllowRetryOnPost,

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

        if ($PSBoundParameters.ContainsKey('Body')) {
            $invokeParams.Body = $Body
        }

        Invoke-RestMethod @invokeParams
    }.GetNewClosure()

    Invoke-WithRetry -Operation $operation -Method $Method -MaxRetries $MaxRetries -AllowRetryOnPost:$AllowRetryOnPost -RunEvents $RunEvents
}
### END: InvokeGcRequest
