Describe 'Catalog resolution precedence and strict mode' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Catalog/Resolve-Catalog.ps1"
        $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/schema/genesys.catalog.schema.json'
    }

    It 'uses canonical catalog and warning is empty by default' {
        $resolved = Resolve-Catalog -SchemaPath $schemaPath
        (Split-Path -Path $resolved.pathUsed -Leaf) | Should -Be 'genesys.catalog.json'
        @($resolved.warnings).Count | Should -Be 0
    }

    It 'uses catalog folder file when root is missing' {
        Push-Location $TestDrive
        try {
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'catalog') | Out-Null
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

    It 'warns when canonical catalog is missing and legacy fallback is used' {
        Push-Location $TestDrive
        try {
            if (Test-Path (Join-Path $TestDrive 'catalog/genesys.catalog.json')) {
                Remove-Item (Join-Path $TestDrive 'catalog/genesys.catalog.json') -Force
            }
            Set-Content -Path (Join-Path $TestDrive 'genesys-core.catalog.json') -Value '{"version":"1.0","datasets":{"audit-logs":{"endpoint":"audits.query.submit","itemsPath":"$.results","paging":{"profile":"transactionResults"},"retry":{"profile":"rateLimitAware"}}},"endpoints":[{"key":"audits.query.submit","method":"POST","path":"/a","itemsPath":"$","paging":{"profile":"none"},"retry":{"profile":"rateLimitAware"}}]}'
            $resolved = Resolve-Catalog
            @($resolved.warnings).Count | Should -Be 1
            $resolved.pathUsed | Should -Match 'genesys-core.catalog.json$'
        }
        finally {
            Pop-Location
        }
    }

    It 'fails strict mode when canonical catalog is missing and fallback would be used' {
        Push-Location $TestDrive
        try {
            if (Test-Path (Join-Path $TestDrive 'catalog/genesys.catalog.json')) {
                Remove-Item (Join-Path $TestDrive 'catalog/genesys.catalog.json') -Force
            }
            Set-Content -Path (Join-Path $TestDrive 'genesys-core.catalog.json') -Value '{"version":"1.0","datasets":{"audit-logs":{"endpoint":"audits.query.submit","itemsPath":"$.results","paging":{"profile":"transactionResults"},"retry":{"profile":"rateLimitAware"}}},"endpoints":[{"key":"audits.query.submit","method":"POST","path":"/a","itemsPath":"$","paging":{"profile":"none"},"retry":{"profile":"rateLimitAware"}}]}'
            { Resolve-Catalog -StrictCatalog } | Should -Throw '*Canonical catalog*'
        }
        finally {
            Pop-Location
        }
    }
}

