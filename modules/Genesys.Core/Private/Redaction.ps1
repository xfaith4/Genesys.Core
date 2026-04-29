function Test-IsSensitiveFieldName {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    # Match fields containing sensitive terms (case-insensitive)
    # Covers patterns like: email, userEmail, user_email, authorization, apiKey, etc.
    return $Name -match '(?i)(token|secret|password|authorization|apikey|api_key|clientsecret|client_secret|access_token|refresh_token|id_token|email|phone|ssn|userid|employeeid|jwt)'
}

function Resolve-DatasetRedactionProfile {
    <#
    .SYNOPSIS
        Resolves a dataset's named redaction profile from the catalog.
    .DESCRIPTION
        Looks up the dataset entry's redactionProfile field and returns the
        corresponding profile hashtable from catalog.profiles.redaction.
        Returns $null when no profile is declared or the named profile does not exist.
    #>
    [CmdletBinding()]
    param(
        [psobject]$Catalog,
        [string]$DatasetKey
    )

    if ($null -eq $Catalog -or [string]::IsNullOrWhiteSpace($DatasetKey)) {
        return $null
    }

    $dataset = $Catalog.datasets[$DatasetKey]
    if ($null -eq $dataset) { return $null }

    $profileProp = $dataset.PSObject.Properties | Where-Object { $_.Name -eq 'redactionProfile' }
    if ($null -eq $profileProp) { return $null }
    $profileName = [string]$profileProp.Value
    if ([string]::IsNullOrWhiteSpace($profileName)) { return $null }

    $redactionProfiles = $null
    $profilesProp = $Catalog.PSObject.Properties | Where-Object { $_.Name -eq 'profiles' }
    if ($null -ne $profilesProp) {
        $redProp = $profilesProp.Value.PSObject.Properties | Where-Object { $_.Name -eq 'redaction' }
        if ($null -ne $redProp) {
            $redactionProfiles = $redProp.Value
        }
    }
    if ($null -eq $redactionProfiles) { return $null }

    $namedProp = $redactionProfiles.PSObject.Properties | Where-Object { $_.Name -eq $profileName }
    if ($null -eq $namedProp) { return $null }

    $profileObj = $namedProp.Value
    $result = @{}
    foreach ($prop in $profileObj.PSObject.Properties) {
        $result[$prop.Name] = @($prop.Value)
    }
    return $result
}

function Protect-SensitiveString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    $sanitized = $Value

    # Replace full bearer/basic header values.
    $sanitized = [System.Text.RegularExpressions.Regex]::Replace(
        $sanitized,
        '(?i)\b(Bearer|Basic)\s+[A-Za-z0-9\-\._~\+/=]+',
        '$1 [REDACTED]'
    )

    # Replace JWT-like tokens appearing as standalone values.
    $sanitized = [System.Text.RegularExpressions.Regex]::Replace(
        $sanitized,
        '(?i)\b[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
        '[REDACTED]'
    )

    # Replace query-style token fields even when embedded in longer strings.
    $sanitized = [System.Text.RegularExpressions.Regex]::Replace(
        $sanitized,
        '(?i)([?&]|^)(access_token|refresh_token|id_token|token|apikey|api_key|secret|password)=([^&\s]+)',
        '$1$2=[REDACTED]'
    )

    return $sanitized
}

function Protect-RecordData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $InputObject,

        [string]$CurrentFieldName,

        [hashtable]$Profile = $null
    )

    if ($null -eq $InputObject) {
        return $null
    }

    # Profile-driven explicit removeFields check (takes precedence over the heuristic).
    if ($null -ne $Profile -and
        -not [string]::IsNullOrWhiteSpace($CurrentFieldName) -and
        $null -ne $Profile['removeFields'] -and
        $Profile['removeFields'] -contains $CurrentFieldName) {
        return '[REDACTED]'
    }

    if (Test-IsSensitiveFieldName -Name $CurrentFieldName) {
        return '[REDACTED]'
    }

    if ($InputObject -is [string]) {
        return (Protect-SensitiveString -Value $InputObject)
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $sanitizedMap = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $fieldName = [string]$key
            $sanitizedMap[$fieldName] = Protect-RecordData -InputObject $InputObject[$key] -CurrentFieldName $fieldName -Profile $Profile
        }

        return [pscustomobject]$sanitizedMap
    }

    if ($InputObject -is [pscustomobject]) {
        $sanitizedObject = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $fieldName = [string]$property.Name
            $sanitizedObject[$fieldName] = Protect-RecordData -InputObject $property.Value -CurrentFieldName $fieldName -Profile $Profile
        }

        return [pscustomobject]$sanitizedObject
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $sanitizedItems = @()
        foreach ($item in $InputObject) {
            $sanitizedItems += ,(Protect-RecordData -InputObject $item -Profile $Profile)
        }

        return ,$sanitizedItems
    }

    return $InputObject
}
