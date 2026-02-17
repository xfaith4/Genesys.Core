function Assert-Catalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CatalogPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SchemaPath
    )

    if (-not (Test-Path -Path $CatalogPath)) {
        throw "Catalog file not found: $($CatalogPath)"
    }

    if (-not (Test-Path -Path $SchemaPath)) {
        throw "Schema file not found: $($SchemaPath)"
    }

    $catalogRaw = Get-Content -Path $CatalogPath -Raw
    $catalog = $catalogRaw | ConvertFrom-Json -Depth 100

    $testJsonCommand = Get-Command -Name Test-Json -ErrorAction SilentlyContinue
    if ($null -ne $testJsonCommand) {
        $schemaRaw = Get-Content -Path $SchemaPath -Raw
        $isValid = $catalogRaw | Test-Json -Schema $schemaRaw
        if (-not $isValid) {
            throw "Catalog schema validation failed for '$($CatalogPath)'."
        }
    }

    foreach ($endpoint in $catalog.endpoints) {
        if ([string]::IsNullOrWhiteSpace($endpoint.itemsPath)) {
            throw "Endpoint '$($endpoint.key)' is missing required 'itemsPath'."
        }

        if ($null -eq $endpoint.paging -or [string]::IsNullOrWhiteSpace($endpoint.paging.profile)) {
            throw "Endpoint '$($endpoint.key)' is missing required 'paging.profile'."
        }
    }

    return $catalog
}
