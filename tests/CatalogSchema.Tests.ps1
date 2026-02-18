Describe 'Catalog schema validation' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Catalog/Resolve-Catalog.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Assert-Catalog.ps1"
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../genesys-core.catalog.json'
        $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../catalog/schema/genesys-core.catalog.schema.json'
    }

    It 'passes validation for canonical catalog' {
        { Assert-Catalog -CatalogPath $catalogPath -SchemaPath $schemaPath } | Should -Not -Throw
    }

    It 'fails when dataset is missing endpoint' {
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
        $catalog.datasets.'users'.PSObject.Properties.Remove('endpoint')
        $invalidCatalogPath = Join-Path -Path $TestDrive -ChildPath 'missing-dataset-endpoint.catalog.json'
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $invalidCatalogPath

        { Assert-Catalog -CatalogPath $invalidCatalogPath -SchemaPath $schemaPath } | Should -Throw
    }

    It 'fails when endpoint is missing paging profile' {
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
        $catalog.endpoints.'audits.query.submit'.PSObject.Properties.Remove('pagingProfile')
        $invalidCatalogPath = Join-Path -Path $TestDrive -ChildPath 'missing-endpoint-paging.catalog.json'
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $invalidCatalogPath

        { Assert-Catalog -CatalogPath $invalidCatalogPath -SchemaPath $schemaPath } | Should -Throw
    }
}
