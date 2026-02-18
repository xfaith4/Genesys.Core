Describe 'Catalog schema validation' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Catalog/Resolve-Catalog.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Assert-Catalog.ps1"

        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../catalog/genesys-core.catalog.json'
        $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../catalog/schema/genesys-core.catalog.schema.json'
    }

    It 'passes validation for the sample catalog entry' {
        { Assert-Catalog -CatalogPath $catalogPath -SchemaPath $schemaPath } | Should -Not -Throw
    }

    It 'fails when an endpoint is missing itemsPath' {
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
        $catalog.endpoints[0].PSObject.Properties.Remove('itemsPath')
        $invalidCatalogPath = Join-Path -Path $TestDrive -ChildPath 'missing-itemsPath.catalog.json'
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $invalidCatalogPath

        { Assert-Catalog -CatalogPath $invalidCatalogPath -SchemaPath $schemaPath } | Should -Throw
    }

    It 'fails when an endpoint is missing paging.profile' {
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
        $catalog.endpoints[0].paging.PSObject.Properties.Remove('profile')
        $invalidCatalogPath = Join-Path -Path $TestDrive -ChildPath 'missing-paging-profile.catalog.json'
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $invalidCatalogPath

        { Assert-Catalog -CatalogPath $invalidCatalogPath -SchemaPath $schemaPath } | Should -Throw
    }

    It 'fails when an endpoint is missing retry.profile' {
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
        $catalog.endpoints[0].retry.PSObject.Properties.Remove('profile')
        $invalidCatalogPath = Join-Path -Path $TestDrive -ChildPath 'missing-retry-profile.catalog.json'
        $catalog | ConvertTo-Json -Depth 100 | Set-Content -Path $invalidCatalogPath

        { Assert-Catalog -CatalogPath $invalidCatalogPath -SchemaPath $schemaPath } | Should -Throw
    }
}
