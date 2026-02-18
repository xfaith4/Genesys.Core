Describe 'Catalog resolution precedence and strict mode' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Catalog/Resolve-Catalog.ps1"
        $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../catalog/schema/genesys-core.catalog.schema.json'
    }

    It 'uses root catalog when both files exist and warning is empty when identical' {
        $resolved = Resolve-Catalog -SchemaPath $schemaPath
        (Split-Path -Path $resolved.pathUsed -Leaf) | Should -Be 'genesys-core.catalog.json'
        @($resolved.warnings).Count | Should -Be 0
    }

    It 'uses catalog folder file when root is missing' {
        Push-Location $TestDrive
        try {
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'catalog') | Out-Null
            Copy-Item -Path (Join-Path $PSScriptRoot '../catalog/genesys-core.catalog.json') -Destination (Join-Path $TestDrive 'catalog/genesys-core.catalog.json')
            Copy-Item -Path (Join-Path $PSScriptRoot '../catalog/schema/genesys-core.catalog.schema.json') -Destination (Join-Path $TestDrive 'catalog/genesys-core.catalog.schema.json')
            $resolved = Resolve-Catalog -SchemaPath (Join-Path $TestDrive 'catalog/schema/genesys-core.catalog.schema.json')
            $resolved.pathUsed | Should -Match 'catalog[/\\]genesys-core.catalog.json$'
        }
        finally {
            Pop-Location
        }
    }

    It 'warns when root and catalog files differ' {
        Push-Location $TestDrive
        try {
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'catalog') | Out-Null
            Set-Content -Path (Join-Path $TestDrive 'genesys-core.catalog.json') -Value '{"version":"1.0","datasets":{"audit-logs":{"endpoint":"audits.query.submit","itemsPath":"$.results","paging":{"profile":"transactionResults"},"retry":{"profile":"rateLimitAware"}}},"endpoints":[{"key":"audits.query.submit","method":"POST","path":"/a","itemsPath":"$","paging":{"profile":"none"},"retry":{"profile":"rateLimitAware"}}]}'
            Set-Content -Path (Join-Path $TestDrive 'catalog/genesys-core.catalog.json') -Value '{"version":"1.1","datasets":{"audit-logs":{"endpoint":"audits.query.submit","itemsPath":"$.results","paging":{"profile":"transactionResults"},"retry":{"profile":"rateLimitAware"}}},"endpoints":[{"key":"audits.query.submit","method":"POST","path":"/b","itemsPath":"$","paging":{"profile":"none"},"retry":{"profile":"rateLimitAware"}}]}'
            $resolved = Resolve-Catalog
            @($resolved.warnings).Count | Should -Be 1
        }
        finally {
            Pop-Location
        }
    }

    It 'fails strict mode when root and catalog files differ' {
        Push-Location $TestDrive
        try {
            New-Item -ItemType Directory -Path (Join-Path $TestDrive 'catalog') | Out-Null
            Set-Content -Path (Join-Path $TestDrive 'genesys-core.catalog.json') -Value '{"version":"1.0","datasets":{"audit-logs":{"endpoint":"audits.query.submit","itemsPath":"$.results","paging":{"profile":"transactionResults"},"retry":{"profile":"rateLimitAware"}}},"endpoints":[{"key":"audits.query.submit","method":"POST","path":"/a","itemsPath":"$","paging":{"profile":"none"},"retry":{"profile":"rateLimitAware"}}]}'
            Set-Content -Path (Join-Path $TestDrive 'catalog/genesys-core.catalog.json') -Value '{"version":"1.1","datasets":{"audit-logs":{"endpoint":"audits.query.submit","itemsPath":"$.results","paging":{"profile":"transactionResults"},"retry":{"profile":"rateLimitAware"}}},"endpoints":[{"key":"audits.query.submit","method":"POST","path":"/b","itemsPath":"$","paging":{"profile":"none"},"retry":{"profile":"rateLimitAware"}}]}'
            { Resolve-Catalog -StrictCatalog } | Should -Throw '*Catalog mismatch detected*'
        }
        finally {
            Pop-Location
        }
    }
}
