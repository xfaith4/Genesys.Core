function Assert-Catalog {
    [CmdletBinding()]
    param(
        [string]$CatalogPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SchemaPath,

        [switch]$StrictCatalog
    )

    $resolved = Resolve-Catalog -CatalogPath $CatalogPath -SchemaPath $SchemaPath -StrictCatalog:$StrictCatalog
    $catalog = $resolved.catalogObject

    if ([string]::IsNullOrWhiteSpace([string]$catalog.version)) {
        throw "Catalog '$($resolved.pathUsed)' is missing required 'version'."
    }

    if ($null -eq $catalog.datasets -or $catalog.datasets.Keys.Count -eq 0) {
        throw "Catalog '$($resolved.pathUsed)' is missing required dataset entries."
    }

    foreach ($datasetKey in $catalog.datasets.Keys) {
        $dataset = $catalog.datasets[$datasetKey]
        if ([string]::IsNullOrWhiteSpace([string]$dataset.endpoint)) {
            throw "Dataset '$($datasetKey)' is missing required 'endpoint'."
        }

        if ([string]::IsNullOrWhiteSpace([string]$dataset.itemsPath)) {
            throw "Dataset '$($datasetKey)' is missing required 'itemsPath'."
        }

        if ($null -eq $dataset.paging -or [string]::IsNullOrWhiteSpace([string]$dataset.paging.profile)) {
            throw "Dataset '$($datasetKey)' is missing required 'paging.profile'."
        }

        if ($null -eq $dataset.retry -or [string]::IsNullOrWhiteSpace([string]$dataset.retry.profile)) {
            throw "Dataset '$($datasetKey)' is missing required 'retry.profile'."
        }
    }

    foreach ($endpoint in @($catalog.endpoints)) {
        if ([string]::IsNullOrWhiteSpace([string]$endpoint.key)) {
            throw "Endpoint in '$($resolved.pathUsed)' is missing required 'key'."
        }

        if ([string]::IsNullOrWhiteSpace([string]$endpoint.itemsPath)) {
            throw "Endpoint '$($endpoint.key)' is missing required 'itemsPath'."
        }

        if ($null -eq $endpoint.paging -or [string]::IsNullOrWhiteSpace([string]$endpoint.paging.profile)) {
            throw "Endpoint '$($endpoint.key)' is missing required 'paging.profile'."
        }

        if ($null -eq $endpoint.retry -or [string]::IsNullOrWhiteSpace([string]$endpoint.retry.profile)) {
            throw "Endpoint '$($endpoint.key)' is missing required 'retry.profile'."
        }
    }

    return $resolved
}
