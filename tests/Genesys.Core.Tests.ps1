Describe 'Genesys Core bootstrap' {
    It 'has canonical root catalog and schema' {
        Test-Path -Path './genesys-core.catalog.json' | Should -BeTrue
        Test-Path -Path './catalog/genesys-core.catalog.json' | Should -BeTrue
        Test-Path -Path './catalog/schema/genesys-core.catalog.schema.json' | Should -BeTrue
    }

    It 'catalog includes required top-level nodes and datasets' {
        $catalog = Get-Content -Path './genesys-core.catalog.json' -Raw | ConvertFrom-Json -Depth 100

        $catalog.version | Should -Not -BeNullOrEmpty
        $catalog.datasets.PSObject.Properties.Name.Count | Should -BeGreaterThan 0
        $catalog.datasets.PSObject.Properties.Name | Should -Contain 'audit-logs'
        $catalog.datasets.PSObject.Properties.Name | Should -Contain 'users'
        $catalog.datasets.PSObject.Properties.Name | Should -Contain 'routing-queues'
    }

    It 'Invoke-Dataset WhatIf returns successfully' {
        $output = & pwsh -NoProfile -File ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 -Dataset audit-logs -WhatIf 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'WhatIf'
    }
}
