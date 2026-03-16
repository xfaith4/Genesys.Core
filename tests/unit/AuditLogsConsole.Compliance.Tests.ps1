Describe 'AuditLogsConsole — Core-First Compliance' {
    BeforeAll {
        $appRoot = Join-Path $PSScriptRoot '../../apps/AuditLogsConsole'
        $appFiles = Get-ChildItem -Path $appRoot -Recurse -File -Include '*.ps1','*.psm1','*.xaml','*.psd1'
        $script:AppFileContents = @{}
        foreach ($file in $appFiles) {
            $script:AppFileContents[$file.FullName] = Get-Content -Path $file.FullName -Raw
        }
    }

    It 'contains no Invoke-RestMethod usage in the app' {
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object { $_.Value -match 'Invoke-RestMethod' } | Select-Object -ExpandProperty Key
        $violations | Should -BeNullOrEmpty
    }

    It 'contains no Invoke-WebRequest usage in the app' {
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object { $_.Value -match 'Invoke-WebRequest' } | Select-Object -ExpandProperty Key
        $violations | Should -BeNullOrEmpty
    }

    It 'contains no /api/v2/ literal in the app' {
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object { $_.Value -match '/api/v2/' } | Select-Object -ExpandProperty Key
        $violations | Should -BeNullOrEmpty
    }

    It 'does not copy Genesys.Core into the app folder' {
        Get-ChildItem -Path (Join-Path $PSScriptRoot '../../apps/AuditLogsConsole') -Recurse -File -Filter 'Genesys.Core.psd1' | Should -BeNullOrEmpty
        Get-ChildItem -Path (Join-Path $PSScriptRoot '../../apps/AuditLogsConsole') -Recurse -File -Filter 'Genesys.Core.psm1' | Should -BeNullOrEmpty
    }

    It 'keeps Invoke-Dataset usage inside App.CoreAdapter only' {
        $hits = $script:AppFileContents.GetEnumerator() | Where-Object { $_.Value -match 'Invoke-Dataset' } | Select-Object -ExpandProperty Key
        $hits.Count | Should -BeGreaterThan 0
        @($hits | Where-Object { $_ -notlike '*App.CoreAdapter.psm1' -and $_ -notlike '*MainWindow.xaml' }).Count | Should -Be 0
    }

    It 'keeps Assert-Catalog usage inside App.CoreAdapter or App.ps1 startup narrative only' {
        $hits = $script:AppFileContents.GetEnumerator() | Where-Object { $_.Value -match 'Assert-Catalog' } | Select-Object -ExpandProperty Key
        @($hits | Where-Object { $_ -notlike '*App.CoreAdapter.psm1' -and $_ -notlike '*Architecture.md' -and $_ -notlike '*ValidationChecklist.md' }).Count | Should -Be 0
    }
}
