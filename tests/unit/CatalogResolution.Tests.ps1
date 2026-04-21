Describe 'Catalog resolution (canonical-only after mirror retirement)' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Catalog.ps1"
        $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/schema/genesys.catalog.schema.json'
    }

    It 'uses canonical catalog and warning list is empty by default' {
        $resolved = Resolve-Catalog -SchemaPath $schemaPath
        (Split-Path -Path $resolved.pathUsed -Leaf) | Should -Be 'genesys.catalog.json'
        @($resolved.warnings).Count | Should -Be 0
    }

    It 'uses catalog folder file when explicit CatalogPath is not supplied' {
        Push-Location $TestDrive
        try {
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'catalog') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'catalog/schema') -Force | Out-Null
            Copy-Item -Path (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') -Destination (Join-Path $TestDrive 'catalog/genesys.catalog.json')
            Copy-Item -Path (Join-Path $PSScriptRoot '../../catalog/schema/genesys.catalog.schema.json') -Destination (Join-Path $TestDrive 'catalog/schema/genesys.catalog.schema.json')
            $resolved = Resolve-Catalog -SchemaPath (Join-Path $TestDrive 'catalog/schema/genesys.catalog.schema.json')
            $resolved.pathUsed | Should -Match 'catalog[/\\]genesys.catalog.json$'
        }
        finally {
            Pop-Location
        }
    }

    It 'throws when the canonical catalog is missing (legacy mirror is no longer auto-discovered)' {
        $missingRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $missingRoot -Force | Out-Null
        $bogus = Join-Path $missingRoot 'does-not-exist.json'
        { Resolve-Catalog -CatalogPath $bogus } | Should -Throw '*Catalog file not found*'
    }

    It 'accepts -StrictCatalog as a backward-compatible no-op' {
        $resolved = Resolve-Catalog -SchemaPath $schemaPath -StrictCatalog
        (Split-Path -Path $resolved.pathUsed -Leaf) | Should -Be 'genesys.catalog.json'
        @($resolved.warnings).Count | Should -Be 0
    }
}
