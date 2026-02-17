function Test-IsSensitiveFieldName {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return $Name -match '(?i)(^|_|-)(token|secret|password|authorization|apikey|clientsecret|client_secret|email|phone|ssn|userid|employeeid)(_|-|$)' -or $Name -match '(?i)^(token|secret|password|authorization|apikey|clientsecret|email|phone|ssn)$'
}

function Protect-RecordData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [string]$CurrentFieldName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if (Test-IsSensitiveFieldName -Name $CurrentFieldName) {
        return '[REDACTED]'
    }

    if ($InputObject -is [string]) {
        if ($InputObject -match '(?i)^Bearer\s+[A-Za-z0-9\-\._~\+\/=]+$') {
            return '[REDACTED]'
        }

        if ($InputObject -match '(?i)^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$') {
            return '[REDACTED]'
        }

        return $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $sanitizedMap = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $fieldName = [string]$key
            $sanitizedMap[$fieldName] = Protect-RecordData -InputObject $InputObject[$key] -CurrentFieldName $fieldName
        }

        return [pscustomobject]$sanitizedMap
    }

    if ($InputObject -is [pscustomobject]) {
        $sanitizedObject = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $fieldName = [string]$property.Name
            $sanitizedObject[$fieldName] = Protect-RecordData -InputObject $property.Value -CurrentFieldName $fieldName
        }

        return [pscustomobject]$sanitizedObject
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $sanitizedItems = @()
        foreach ($item in $InputObject) {
            $sanitizedItems += ,(Protect-RecordData -InputObject $item)
        }

        return $sanitizedItems
    }

    return $InputObject
}
