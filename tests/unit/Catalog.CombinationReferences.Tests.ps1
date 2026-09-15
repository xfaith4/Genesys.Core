Describe 'Catalog combination reference integrity' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $catalog = Get-Content (Join-Path $repoRoot 'catalog/genesys.catalog.json') -Raw | ConvertFrom-Json
        $known = @($catalog.datasets.PSObject.Properties.Name) + @($catalog.endpoints.PSObject.Properties.Name)
        function Get-CombinationReference {
            param($Value)
            if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return }
            if ($Value -is [System.Collections.IEnumerable]) {
                foreach ($item in $Value) { Get-CombinationReference $item }
                return
            }
            foreach ($property in $Value.PSObject.Properties) {
                if ($property.Name -in @('dataset', 'endpoint') -and $property.Value -is [string]) {
                    $property.Value
                }
                elseif ($property.Name -in @('datasets', 'datasetsInOrder', 'endpoints')) {
                    foreach ($item in $property.Value) {
                        if ($item -is [string]) { $item } else { Get-CombinationReference $item }
                    }
                }
                else { Get-CombinationReference $property.Value }
            }
        }
    }

    It 'resolves every structured recipe reference to a dataset or endpoint' {
        $missing = @(Get-CombinationReference $catalog.combinations | Where-Object { $_ -ne '(derived)' -and $_ -notin $known } | Sort-Object -Unique)
        $missing | Should -BeNullOrEmpty
    }

    It 'does not recommend the fabricated generic provider call injection route' {
        ($catalog.combinations | ConvertTo-Json -Depth 100) | Should -Not -Match '/conversations/providers/\{providerId\}/calls'
    }
}
