##
## ConversationAnalysis.Compliance.Tests.ps1
##
## Gate D compliance tests for the Conversation Analysis web tool.
## Ensures the app code never makes direct Genesys REST calls and never
## imports Genesys.Core outside the designated CoreAdapter boundary.
##
## These tests MUST stay green. If any gate fails, the build is rejected.
##

Describe 'ConversationAnalysis — Gate D Compliance' {

    BeforeAll {
        $appRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis'
        $appFiles = Get-ChildItem -Path $appRoot -Recurse -File `
            -Include '*.html','*.js','*.ts','*.psm1','*.ps1' `
            -ErrorAction SilentlyContinue

        # Cache file content for repeated checks
        $script:AppFileContents = @{}
        foreach ($f in $appFiles) {
            $script:AppFileContents[$f.FullName] = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate B.1 — No Invoke-RestMethod in app code
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE B.1: app code must not call Invoke-RestMethod' {
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object {
            $_.Value -match 'Invoke-RestMethod'
        } | Select-Object -ExpandProperty Key

        $violations | Should -BeNullOrEmpty -Because (
            "App code must delegate all HTTP calls to Genesys.Core via Invoke-Dataset. " +
            "Found Invoke-RestMethod in: $($violations -join ', ')"
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate B.2 — No Invoke-WebRequest in app code
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE B.2: app code must not call Invoke-WebRequest' {
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object {
            $_.Value -match 'Invoke-WebRequest'
        } | Select-Object -ExpandProperty Key

        $violations | Should -BeNullOrEmpty -Because (
            "App code must delegate all HTTP calls to Genesys.Core via Invoke-Dataset. " +
            "Found Invoke-WebRequest in: $($violations -join ', ')"
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate B.3 — No /api/v2/ URL literals in app code
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE B.3: app code must not contain literal /api/v2/ paths' {
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object {
            $_.Value -match '/api/v2/'
        } | Select-Object -ExpandProperty Key

        $violations | Should -BeNullOrEmpty -Because (
            "All Genesys REST endpoint paths are owned by Genesys.Core via the catalog. " +
            "Found /api/v2/ literal in: $($violations -join ', ')"
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate B.4 — No fetch() calls to Genesys API hostnames
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE B.4: app code must not call fetch() against Genesys API hosts' {
        $genesysHostPattern = 'fetch\s*\(\s*[''"]https://api\.(mypurecloud|pure\.cloud|usw2|cac1|euw2|aps1|apne2)\.'
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object {
            $_.Value -match $genesysHostPattern
        } | Select-Object -ExpandProperty Key

        $violations | Should -BeNullOrEmpty -Because (
            "Browser fetch() to Genesys API hosts is not allowed in app code. " +
            "Use Genesys.Core Invoke-Dataset instead. Found in: $($violations -join ', ')"
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate C.1 — Genesys.Core module is not copied into the app folder
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE C.1: Genesys.Core module must not be copied into the app folder' {
        $appRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis'
        $coreFiles = Get-ChildItem -Path $appRoot -Recurse -File `
            -Filter 'Genesys.Core.psd1' -ErrorAction SilentlyContinue

        $coreFiles | Should -BeNullOrEmpty -Because (
            "Genesys.Core must be imported by reference, not copied into the app directory."
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate C.2 — Genesys.Core psm1 not in app folder
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE C.2: Genesys.Core.psm1 must not be present in the app folder' {
        $appRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis'
        $coreFiles = Get-ChildItem -Path $appRoot -Recurse -File `
            -Filter 'Genesys.Core.psm1' -ErrorAction SilentlyContinue

        $coreFiles | Should -BeNullOrEmpty -Because (
            "Genesys.Core must not be bundled into the app folder."
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate D.1 — App HTML file exists
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE D.1: apps/ConversationAnalysis/index.html must exist' {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis/index.html'
        Test-Path -Path $path | Should -BeTrue -Because 'The main app SPA must be present.'
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate D.2 — index.html references Chart.js only via CDN (no bundled charts library)
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE D.2: index.html must not bundle chart libraries locally' {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis/index.html'
        $content = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue

        # Must not have a local chart.js file reference
        $localChartRef = $content -match 'src=[''"](?!https?://).*chart.*\.js'
        $localChartRef | Should -BeFalse -Because (
            "Chart.js must be loaded from CDN, not bundled locally. Use a CDN src attribute."
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate D.3 — index.html uses FileReader/File API, not fetch to load data
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE D.3: index.html must use FileReader API for data loading' {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis/index.html'
        $content = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue

        $content | Should -Match 'FileReader' -Because (
            "Data must be loaded via FileReader (local files), not via HTTP fetch to Genesys APIs."
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate D.4 — App folder does not contain node_modules or build artifacts
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE D.4: app folder must not contain node_modules' {
        $appRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis'
        $nodeModules = Join-Path -Path $appRoot -ChildPath 'node_modules'
        Test-Path -Path $nodeModules | Should -BeFalse -Because (
            "The web tool must be dependency-free (no npm build artifacts)."
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate D.5 — No hardcoded bearer tokens or credentials in app files
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE D.5: app code must not contain hardcoded bearer tokens' {
        $tokenPattern = 'Bearer\s+[A-Za-z0-9\-_\.]{20,}'
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object {
            $_.Value -match $tokenPattern
        } | Select-Object -ExpandProperty Key

        $violations | Should -BeNullOrEmpty -Because (
            "Hardcoded bearer tokens are a security violation. Found in: $($violations -join ', ')"
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate D.6 — No hardcoded client secrets
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE D.6: app code must not contain hardcoded client_secret values' {
        $secretPattern = 'client_secret\s*[:=]\s*[''"][^''"]{10,}[''"]'
        $violations = $script:AppFileContents.GetEnumerator() | Where-Object {
            $_.Value -match $secretPattern
        } | Select-Object -ExpandProperty Key

        $violations | Should -BeNullOrEmpty -Because (
            "Hardcoded client secrets are a security violation. Found in: $($violations -join ', ')"
        )
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate D.7 — README exists
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE D.7: apps/ConversationAnalysis/README.md must exist' {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis/README.md'
        Test-Path -Path $path | Should -BeTrue -Because 'The app must have usage documentation.'
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Gate D.8 — index.html must reference Invoke-Dataset concept (docblock)
    # ─────────────────────────────────────────────────────────────────────────
    It 'GATE D.8: index.html must reference Invoke-Dataset in its content (Core-first traceability)' {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '../../apps/ConversationAnalysis/index.html'
        $content = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue

        $content | Should -Match 'Invoke-Dataset' -Because (
            "The app must visibly declare its Core-first architecture by referencing Invoke-Dataset."
        )
    }
}
