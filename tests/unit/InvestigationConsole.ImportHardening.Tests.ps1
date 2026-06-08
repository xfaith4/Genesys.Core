Describe 'Investigation Console dropped-file import hardening' {
    BeforeAll {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/InvestigationConsole/index.html'
        $content = Get-Content -Path $path -Raw -ErrorAction Stop
    }

    It 'avoids placeholder manifest identities for summary-only imports' {
        $content | Should -Not -Match 'placeholder manifest'
        $content | Should -Not -Match "investigationKey:\s*'unknown-investigation'"
        $content | Should -Match 'function synthesizeManifestFromSummary'
        $content | Should -Match 'const investigationKey = inferInvestigationKind\(summary\)'
    }

    It 'parses dropped manifest and summary files with guarded JSON handling' {
        $content | Should -Match 'async function readJsonFileSafe'
        $content | Should -Match 'warnings\.push'
        $content | Should -Match 'parseWarnings'
        $content | Should -Match 'No usable runs were imported'
    }

    It 'infers investigation kind from known summary sections' {
        $content | Should -Match "return 'agent-investigation'"
        $content | Should -Match "return 'queue-investigation'"
        $content | Should -Match "return 'conversation-investigation'"
        $content | Should -Match "return 'campaign-investigation'"
        $content | Should -Match "return 'imported-investigation'"
    }
}
