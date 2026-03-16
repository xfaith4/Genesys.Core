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
