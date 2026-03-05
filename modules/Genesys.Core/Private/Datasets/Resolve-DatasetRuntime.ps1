function ConvertTo-PlainOrderedMap {
    [CmdletBinding()]
    param(
        [object]$InputObject
    )

    $result = [ordered]@{}
    if ($null -eq $InputObject) {
        return $result
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = $InputObject[$key]
        }

        return $result
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $result[[string]$property.Name] = $property.Value
    }

    return $result
}

function Resolve-DatasetInterval {
    [CmdletBinding()]
    param(
        [hashtable]$DatasetParameters,
        [ValidateRange(1, 720)]
        [int]$DefaultLookbackHours
    )

    $utcNow = [DateTime]::UtcNow

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('Interval')) {
        $interval = [string]$DatasetParameters['Interval']
        if (-not [string]::IsNullOrWhiteSpace($interval)) {
            return $interval
        }
    }

    $startUtc = $null
    $endUtc = $null

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('StartUtc')) {
        $startUtc = [DateTime]::Parse([string]$DatasetParameters['StartUtc']).ToUniversalTime()
    }

    if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('EndUtc')) {
        $endUtc = [DateTime]::Parse([string]$DatasetParameters['EndUtc']).ToUniversalTime()
    }

    if ($null -eq $startUtc -and $null -eq $endUtc) {
        $lookbackHours = $DefaultLookbackHours
        if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('LookbackHours')) {
            $lookbackHours = [int]$DatasetParameters['LookbackHours']
        }

        if ($lookbackHours -lt 1 -or $lookbackHours -gt 720) {
            throw "LookbackHours must be between 1 and 720. Received '$($lookbackHours)'."
        }

        $startUtc = $utcNow.AddHours(-1 * $lookbackHours)
        $endUtc = $utcNow
    }
    else {
        if ($null -eq $startUtc) {
            throw 'StartUtc is required when EndUtc is provided.'
        }

        if ($null -eq $endUtc) {
            throw 'EndUtc is required when StartUtc is provided.'
        }

        if ($startUtc -ge $endUtc) {
            throw "StartUtc must be earlier than EndUtc. Received StartUtc '$($startUtc.ToString('o'))' and EndUtc '$($endUtc.ToString('o'))'."
        }
    }

    return "$($startUtc.ToString('o'))/$($endUtc.ToString('o'))"
}
