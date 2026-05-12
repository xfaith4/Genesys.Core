Describe 'Genesys.Ops investigation packaging export surface' {
    BeforeAll {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../../modules/Genesys.Ops/Genesys.Ops.psd1'
        $manifest = Import-PowerShellDataFile -Path $moduleManifestPath
        $exports = @($manifest.FunctionsToExport)
        $module = Import-Module -Name $moduleManifestPath -Force -PassThru
        $expected = @(
            'Export-GenesysInvestigationPackage',
            'Export-GenesysInvestigationDiagnosticsBundle'
        )
    }

    AfterAll {
        if ($null -ne $module) {
            Remove-Module -Name $module.Name -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exports the expected packaging commands' {
        foreach ($fn in $expected) {
            $exports | Should -Contain $fn
        }
    }

    It 'imports the expected packaging commands' {
        foreach ($fn in $expected) {
            $cmd = Get-Command -Name $fn -Module $module.Name -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }
    }
}
