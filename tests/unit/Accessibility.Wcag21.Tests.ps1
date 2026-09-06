Describe 'WCAG 2.1 Level AA conformance' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).ProviderPath
        Import-Module (Join-Path $script:RepoRoot 'tools/Genesys.Accessibility/Genesys.Accessibility.psd1') -Force

        $manifestPath = Join-Path $script:RepoRoot 'config/accessibility-surfaces.json'
        $script:SurfaceManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $script:Surfaces = @($script:SurfaceManifest.surfaces | ForEach-Object {
                # Both keys are optional, so test for them rather than dereferencing blindly:
                # @($missingProperty) is @($null), a one-element array whose Count is 1.
                $declared = $_.PSObject.Properties.Name

                [pscustomobject]@{
                    Name     = $_.name
                    Relative = $_.path
                    FullPath = Join-Path $script:RepoRoot $_.path
                    # Rules a surface cannot satisfy by its nature - an application shell has no
                    # rendered DOM to inspect. Every exclusion must carry a written justification;
                    # the 'Surface manifest' context below enforces that.
                    Exclude  = if ($declared -contains 'excludeRules') { @($_.excludeRules) } else { @() }
                    Reason   = if ($declared -contains '$excludeReason') { $_.'$excludeReason' } else { $null }
                }
            })

        # Cache each surface's source once; several contexts read it.
        $script:SurfaceText = @{}
        foreach ($surface in $script:Surfaces) {
            $script:SurfaceText[$surface.Relative] = Get-Content -LiteralPath $surface.FullPath -Raw
        }
    }

    Context 'Surface manifest' {
        It 'declares AA as the enforced conformance level' {
            $script:SurfaceManifest.conformanceLevel | Should -Be 'AA'
        }

        It 'lists every shipped HTML surface in the repository' {
            $searchRoots = @('apps', 'catalog', 'docs', 'samples') |
                ForEach-Object { Join-Path $script:RepoRoot $_ } |
                Where-Object { Test-Path -LiteralPath $_ }

            # Only authored, shipped source counts. Dependency trees and build output are neither
            # written here nor committed: apps/GenesysDataClient vendors node_modules and emits
            # dist/ from its own index.html, and that index.html is itself a declared surface.
            $generatedPattern = '(^|/)(node_modules|dist|build|coverage)/'

            $onDisk = @(
                Get-ChildItem -Path $searchRoots -Recurse -File -Include '*.html', '*.htm' |
                    ForEach-Object { $_.FullName.Substring($script:RepoRoot.Length + 1) -replace '\\', '/' } |
                    Where-Object { $_ -notmatch $generatedPattern }
            )

            $declared = @($script:Surfaces.Relative)
            $undeclared = @($onDisk | Where-Object { $declared -notcontains $_ })
            $undeclared | Should -BeNullOrEmpty -Because 'every shipped HTML page must be held to the same WCAG bar'
        }

        It 'justifies every rule it excludes' {
            # An exclusion is a claim that a rule cannot apply, not a way to silence a real
            # finding. Requiring a written reason keeps that claim reviewable.
            foreach ($surface in @($script:Surfaces | Where-Object { $_.Exclude.Count -gt 0 })) {
                $surface.Reason | Should -Not -BeNullOrEmpty -Because "$($surface.Relative) excludes $($surface.Exclude -join ', ') and must say why in `$excludeReason"
            }
        }

        It 'points at files that exist' {
            foreach ($surface in $script:Surfaces) {
                Test-Path -LiteralPath $surface.FullPath | Should -BeTrue -Because "$($surface.Relative) is declared in the manifest"
            }
        }
    }

    Context 'Static analyzer self-checks' {
        It 'computes WCAG relative contrast ratios correctly' {
            Get-ContrastRatio -Foreground '#000000' -Background '#ffffff' | Should -Be 21
            Get-ContrastRatio -Foreground '#ffffff' -Background '#ffffff' | Should -Be 1
            # #767676 on white is the documented 4.54:1 boundary; one step
            # lighter (#777777, 4.48:1) falls below the SC 1.4.3 minimum.
            Get-ContrastRatio -Foreground '#767676' -Background '#ffffff' | Should -BeGreaterOrEqual 4.5
            Get-ContrastRatio -Foreground '#777777' -Background '#ffffff' | Should -BeLessThan 4.5
            Get-ContrastRatio -Foreground '#0d9f6e' -Background '#ffffff' | Should -BeLessThan 4.5
        }

        It 'parses hex, shorthand hex, and rgba colours including alpha' {
            (ConvertFrom-CssColor -Color '#fff').R | Should -Be 255
            (ConvertFrom-CssColor -Color '#0d9f6e').G | Should -Be 159
            (ConvertFrom-CssColor -Color 'rgba(10, 20, 30, .5)').B | Should -Be 30
            (ConvertFrom-CssColor -Color 'rgba(10, 20, 30, .5)').A | Should -Be 0.5
            (ConvertFrom-CssColor -Color '#11223344').A | Should -BeLessThan 1
            ConvertFrom-CssColor -Color 'linear-gradient(red, blue)' | Should -BeNullOrEmpty
        }

        It 'publishes a rule catalogue covering the enforced success criteria' {
            $rules = @(Get-GenesysAccessibilityRule)
            $rules.Count | Should -BeGreaterThan 20
            ($rules | Where-Object Level -eq 'AA').Count | Should -BeGreaterThan 0
            $criteria = @($rules.Criterion | Sort-Object -Unique)
            foreach ($expected in @(
                    '1.1.1 Non-text Content',
                    '1.3.1 Info and Relationships',
                    '1.4.3 Contrast (Minimum)',
                    '2.1.1 Keyboard',
                    '2.4.1 Bypass Blocks',
                    '2.4.7 Focus Visible',
                    '4.1.2 Name, Role, Value',
                    '4.1.3 Status Messages')) {
                $criteria | Should -Contain $expected
            }
        }

        It 'detects seeded violations in a deliberately inaccessible page' {
            $bad = Join-Path ([System.IO.Path]::GetTempPath()) ("a11y-negative-{0}.html" -f ([guid]::NewGuid()))
            @'
<!DOCTYPE html>
<html>
<head><title></title></head>
<body>
<style>
  body { background: #ffffff; }
  .faint { color: #bbbbbb; background: #ffffff; }
  input { outline: none; }
</style>
<div onclick="doThing()">Clickable div</div>
<input type="text" placeholder="Unlabelled" />
<img src="x.png" />
<canvas id="c"></canvas>
<table><tr><td>no headers</td></tr></table>
<p class="faint">Low contrast text</p>
<span>&#9660;</span>
</body>
</html>
'@ | Set-Content -LiteralPath $bad -Encoding UTF8

            try {
                $findings = @(Test-HtmlAccessibility -Path $bad)
                $ruleIds = @($findings.RuleId | Sort-Object -Unique)

                $ruleIds | Should -Contain 'A11Y001'   # missing lang
                $ruleIds | Should -Contain 'A11Y002'   # empty title
                $ruleIds | Should -Contain 'A11Y003'   # missing viewport
                $ruleIds | Should -Contain 'A11Y004'   # no main landmark
                $ruleIds | Should -Contain 'A11Y006'   # no h1
                $ruleIds | Should -Contain 'A11Y010'   # unlabelled input
                $ruleIds | Should -Contain 'A11Y012'   # img without alt
                $ruleIds | Should -Contain 'A11Y013'   # unnamed canvas
                $ruleIds | Should -Contain 'A11Y015'   # click handler on a div
                $ruleIds | Should -Contain 'A11Y018'   # glyph-only span
                $ruleIds | Should -Contain 'A11Y019'   # suppressed focus outline
                $ruleIds | Should -Contain 'A11Y021'   # table without headers
                ($ruleIds -contains 'A11Y020' -or $ruleIds -contains 'A11Y025') | Should -BeTrue -Because 'the faint paragraph fails SC 1.4.3'
            }
            finally {
                Remove-Item -LiteralPath $bad -Force -ErrorAction SilentlyContinue
            }
        }

        It 'reports no violations for a conforming page' {
            $good = Join-Path ([System.IO.Path]::GetTempPath()) ("a11y-positive-{0}.html" -f ([guid]::NewGuid()))
            @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Conforming page</title>
<style>
  body { color: #111111; background: #ffffff; }
  :focus-visible { outline: 3px solid #0052cc; }
</style>
</head>
<body>
<a class="skip-link" href="#main-content">Skip to main content</a>
<main id="main-content">
  <h1>Conforming page</h1>
  <h2>Records</h2>
  <label for="q">Search</label>
  <input type="text" id="q" />
  <button type="button">Run search</button>
  <table>
    <caption>Records</caption>
    <thead><tr><th scope="col">Name</th></tr></thead>
    <tbody><tr><td>Value</td></tr></tbody>
  </table>
  <p role="status">Ready</p>
</main>
</body>
</html>
'@ | Set-Content -LiteralPath $good -Encoding UTF8

            try {
                @(Test-HtmlAccessibility -Path $good) | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $good -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Shipped surfaces' {
        It 'reports zero WCAG 2.1 Level AA violations across every surface' {
            $failures = [System.Collections.Generic.List[string]]::new()
            foreach ($surface in $script:Surfaces) {
                foreach ($finding in @(Test-HtmlAccessibility -Path $surface.FullPath -Level 'AA' -ExcludeRule $surface.Exclude)) {
                    $failures.Add(("{0}:{1} [{2}] {3}" -f $surface.Relative, $finding.Line, $finding.RuleId, $finding.Message))
                }
            }
            $failures | Should -BeNullOrEmpty
        }
    }

    Context 'Design token contrast' {
        # The utility classes below are applied to markup generated at runtime,
        # which static DOM analysis cannot reach, so the tokens are asserted
        # directly against the surfaces they render on.
        BeforeAll {
            $script:ConsoleSurfaces = @(
                'apps/OpsConsole/index.html',
                'apps/InvestigationConsole/index.html',
                'apps/ConversationAnalysis/index.html'
            )
            $script:LightSurfaces = @('#ffffff', '#f8faf9', '#f0f4f1')
        }

        It 'defines text-safe status tokens in <_>' -ForEach $script:ConsoleSurfaces {
            $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot $_) -Raw
            foreach ($token in @('--ok-text', '--warn-text', '--danger-text', '--accent-text')) {
                $text | Should -Match ([regex]::Escape($token) + '\s*:')
            }
        }

        It 'keeps every text token above 4.5:1 on each light surface in <_>' -ForEach $script:ConsoleSurfaces {
            $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot $_) -Raw
            foreach ($token in @('--ok-text', '--warn-text', '--danger-text', '--accent-text', '--muted', '--ink', '--ink2')) {
                $pattern = [regex]::Escape($token) + '\s*:\s*(#[0-9a-fA-F]{3,8})\s*;'
                $match = [regex]::Match($text, $pattern)
                $match.Success | Should -BeTrue -Because "$token must be declared in $_"

                foreach ($background in @('#ffffff', '#f8faf9', '#f0f4f1')) {
                    $ratio = Get-ContrastRatio -Foreground $match.Groups[1].Value -Background $background
                    $ratio | Should -BeGreaterOrEqual 4.5 -Because "$token ($($match.Groups[1].Value)) is body text on $background in $_"
                }
            }
        }

        It 'keeps graphical tokens above the 3:1 SC 1.4.11 minimum in <_>' -ForEach $script:ConsoleSurfaces {
            $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot $_) -Raw
            foreach ($token in @('--ok', '--warn', '--danger', '--accent')) {
                $pattern = '(?<!-)' + [regex]::Escape($token) + '\s*:\s*(#[0-9a-fA-F]{3,8})\s*;'
                $match = [regex]::Match($text, $pattern)
                $match.Success | Should -BeTrue -Because "$token must be declared in $_"
                $ratio = Get-ContrastRatio -Foreground $match.Groups[1].Value -Background '#ffffff'
                $ratio | Should -BeGreaterOrEqual 3.0 -Because "$token ($($match.Groups[1].Value)) is a UI graphic on white in $_"
            }
        }

        It 'uses the darker accent wherever white text sits on an accent fill in <_>' -ForEach $script:ConsoleSurfaces {
            $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot $_) -Raw
            $offenders = [regex]::Matches($text, '\{[^{}]*background:\s*var\(--accent\)[^{}]*color:\s*#fff[^{}]*\}')
            @($offenders) | Should -BeNullOrEmpty -Because 'white on --accent is 3.39:1; --accent-dk is required for text'
        }
    }

    Context 'Runtime-generated markup' {
        It 'emits scoped, keyboard-operable headers from the conversation grid builder' {
            $text = $script:SurfaceText['apps/ConversationAnalysis/index.html']
            $text | Should -Match '<th scope="col" \$\{sortAttr\}>'
            $text | Should -Match '<th scope="col" aria-sort="none"'
            $text | Should -Match 'class="th-sort"'
            $text | Should -Match "setAttribute\('aria-sort'"
        }

        It 'keeps ARIA tab state in step with the visual state in every tabbed console' {
            foreach ($relative in @('apps/OpsConsole/index.html', 'apps/InvestigationConsole/index.html')) {
                $text = $script:SurfaceText[$relative]
                $text | Should -Match "setAttribute\('aria-selected'" -Because "$relative must announce the selected tab"
                $text | Should -Match 'ArrowRight' -Because "$relative must support the WAI-ARIA tabs keyboard pattern"
                $text | Should -Match 'tabIndex = selected \? 0 : -1' -Because "$relative must use a roving tabindex"
            }
        }

        It 'gives every filter toggle a pressed state' {
            foreach ($relative in @('apps/OpsConsole/index.html', 'apps/ConversationAnalysis/index.html', 'catalog/catalog-browser.html')) {
                $script:SurfaceText[$relative] | Should -Match 'aria-pressed' -Because "$relative renders toggle filters"
            }
        }

        It 'names every rendered mermaid diagram from its card title' {
            $text = $script:SurfaceText['docs/architecture.html']
            $text | Should -Match 'function labelRenderedDiagrams'
            $text | Should -Match "svg\.setAttribute\('role', 'img'\)"
            $text | Should -Match "svg\.setAttribute\('aria-label', name\)"
            # The labelling pass must survive a diagram that fails to render.
            $text | Should -Match 'finally \{\s*\r?\n\s*labelRenderedDiagrams\(\);'
        }

        It 'avoids mermaid reserved keywords in classDef names' {
            $text = $script:SurfaceText['docs/architecture.html']
            foreach ($reserved in @('call', 'click', 'style', 'class', 'end', 'graph', 'subgraph')) {
                $text | Should -Not -Match ("classDef\s+$reserved\s") -Because "'$reserved' is a mermaid keyword and makes the diagram fail to parse"
            }
        }
    }

    Context 'PowerShell HTML generators' {
        It 'emits accessible tables from ConvertTo-GenesysHtmlTable' {
            $source = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'modules/Genesys.Ops/Genesys.Ops.psm1') -Raw
            $source | Should -Match "<table><caption>"
            $source | Should -Match '<th scope="col">'
            $source | Should -Not -Match "\[void\]\`$sb\.Append\('<th>'"
        }

        It 'emits a skip link, viewport, and named main landmark from every package template' {
            $source = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'modules/Genesys.Ops/Genesys.Ops.psm1') -Raw
            ([regex]::Matches($source, '<meta name="viewport"')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($source, 'class="skip-link" href="#main-content"')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($source, '<main id="main-content">')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($source, ':focus-visible')).Count | Should -BeGreaterOrEqual 2
        }

        It 'emits accessible audit-log exports' {
            $source = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'apps/AuditLogsConsole/App.Export.psm1') -Raw
            $source | Should -Match '<meta name="viewport"'
            $source | Should -Match 'class="skip-link" href="#main-content"'
            $source | Should -Match '<main id="main-content">'
            $source | Should -Match 'scope=""col""'
            $source | Should -Match '<caption>'
        }
    }
}
