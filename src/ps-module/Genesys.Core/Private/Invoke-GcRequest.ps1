### BEGIN: InvokeGcRequest
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
        uri = $Uri
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
