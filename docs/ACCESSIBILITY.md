# Accessibility — WCAG 2.1 Level AA

Genesys.Core ships seven HTML surfaces: three operator consoles, a dataset
browser, two documentation pages, and the HTML report emitted by the
investigation packaging cmdlets. All seven are held to **WCAG 2.1 Level AA**,
enforced automatically on every pull request.

## Conformance claim

| Item | Value |
| --- | --- |
| Standard | WCAG 2.1 |
| Conformance level | AA |
| Scope | The seven surfaces listed in `config/accessibility-surfaces.json` |
| Enforcement | `scripts/Invoke-AccessibilityAudit.ps1` + `tests/unit/Accessibility.Wcag21.Tests.ps1`, run by the `accessibility` and `pester` CI jobs |
| Last full audit | 2026-09-02 — 0 violations across 7 surfaces |
| Known limitations | See [Manual verification](#manual-verification) below |

This is a *supported* claim, not a certified one: the automated gate covers the
statically decidable criteria, and the manual checklist covers the rest.

## Running the audit

```powershell
# Audit every declared surface (exit code 1 when violations remain)
pwsh -NoProfile -File ./scripts/Invoke-AccessibilityAudit.ps1

# Machine-readable report
pwsh -NoProfile -File ./scripts/Invoke-AccessibilityAudit.ps1 -JsonPath ./out/accessibility-audit.json

# One file, or a stricter/looser level
pwsh -NoProfile -File ./scripts/Invoke-AccessibilityAudit.ps1 -Path ./apps/OpsConsole/index.html -Level A
```

The analyzer is a dependency-free PowerShell module (`tools/Genesys.Accessibility`)
that runs on Windows PowerShell 5.1 and PowerShell 7+ with no Node/npm toolchain,
so it works offline and inside CI without extra provisioning.

```powershell
Import-Module ./tools/Genesys.Accessibility/Genesys.Accessibility.psd1
Test-HtmlAccessibility -Path ./catalog/catalog-browser.html | Format-Table Line, RuleId, Message
Get-GenesysAccessibilityRule | Format-Table RuleId, Level, Criterion
Get-ContrastRatio -Foreground '#5b6b62' -Background '#ffffff'   # 5.64
```

## Adding a surface

New HTML pages must be added to `config/accessibility-surfaces.json`. A test in
`tests/unit/Accessibility.Wcag21.Tests.ps1` walks `apps/`, `catalog/`, `docs/`,
and `samples/` and fails when a shipped `.html` file is not declared, so a new
page cannot silently skip the gate.

## Enforced rules

| Rule | Success criterion | Level | What it checks |
| --- | --- | --- | --- |
| A11Y001 | 3.1.1 Language of Page | A | `<html lang>` is present and non-empty |
| A11Y002 | 2.4.2 Page Titled | A | A descriptive `<title>` exists |
| A11Y003 | 1.4.4 Resize Text | AA | A viewport meta exists and does not block zoom to 200% |
| A11Y004 | 1.3.1 Info and Relationships | A | Exactly one `main` landmark |
| A11Y005 | 2.4.1 Bypass Blocks | A | A skip link targets the main landmark |
| A11Y006 | 2.4.6 Headings and Labels | AA | Exactly one `<h1>` |
| A11Y007 | 1.3.1 Info and Relationships | A | Heading levels do not skip |
| A11Y008 | 4.1.1 Parsing | A | `id` values are unique |
| A11Y009 | 2.4.3 Focus Order | A | No positive `tabindex` |
| A11Y010 | 3.3.2 Labels or Instructions | A | Form controls have a programmatic label (a placeholder is not one) |
| A11Y011 | 4.1.2 Name, Role, Value | A | Buttons and links have an accessible name |
| A11Y012 | 1.1.1 Non-text Content | A | `<img>` carries `alt` |
| A11Y013 | 1.1.1 Non-text Content | A | `<canvas>` charts carry `role="img"` plus a name |
| A11Y014 | 1.1.1 Non-text Content | A | Inline `<svg>` is named or `aria-hidden` |
| A11Y015 | 2.1.1 Keyboard | A | Click handlers sit on real controls, not bare `div`/`span` |
| A11Y016 | 4.1.2 Name, Role, Value | A | `aria-labelledby` / `aria-controls` / `for` resolve to real ids |
| A11Y017 | 4.1.2 Name, Role, Value | A | Tab widgets wire `tablist` / `tab` / `tabpanel` correctly |
| A11Y018 | 1.1.1 Non-text Content | A | Glyph-only content is hidden or named |
| A11Y019 | 2.4.7 Focus Visible | AA | A visible focus indicator exists and is never suppressed without replacement |
| A11Y020 | 1.4.3 Contrast (Minimum) | AA | Colour/background pairs declared in the same CSS rule |
| A11Y021 | 1.3.1 Info and Relationships | A | Tables have a name and scoped `<th>` headers |
| A11Y022 | 4.1.3 Status Messages | AA | Transient-message containers are live regions |
| A11Y023 | 4.1.2 Name, Role, Value | A | `role` values are valid ARIA roles |
| A11Y024 | 2.4.1 Bypass Blocks | A | The main landmark has an id to skip to |
| A11Y025 | 1.4.3 Contrast (Minimum) | AA | Contrast resolved through the DOM using a simplified CSS cascade |

## Design tokens

Each console defines two colour families, because WCAG applies different minima
to text and to graphics:

- **Graphical tokens** — `--accent`, `--ok`, `--warn`, `--danger`. Used for
  borders, status dots, chart fills, and focus rings. Held to **3:1** by
  SC 1.4.11 (Non-text Contrast).
- **Text tokens** — `--accent-text`, `--ok-text`, `--warn-text`,
  `--danger-text`, plus `--muted`, `--ink`, `--ink2`. Held to **4.5:1** by
  SC 1.4.3, verified against all three light surfaces (`#ffffff`, `#f8faf9`,
  `#f0f4f1`).

White label text never sits on `--accent` (3.39:1); button and active-chip fills
use `--accent-dk` (5.35:1). The Pester suite asserts both families directly, so
a token change that breaks contrast fails the build.

## Patterns used

- **Bypass block** — every page opens with a `.skip-link` that targets the
  `main` landmark and becomes visible on focus.
- **Tabs** — the Ops and Investigation consoles implement the WAI-ARIA tabs
  pattern: `role="tablist"`, `aria-selected`, `aria-controls`, a roving
  `tabindex`, and Arrow/Home/End keyboard navigation.
- **Toggle filters** — every filter chip is a `<button>` with `aria-pressed`,
  including the ones generated at runtime.
- **Sortable tables** — column headers are `<th scope="col">` wrapping a
  `<button>`, with `aria-sort` reflecting the current order.
- **Charts** — every `<canvas>` declares `role="img"` and an `aria-label` that
  names the chart and points at the equivalent data table where one exists.
  Mermaid diagrams are labelled from their card titles after rendering.
- **Status messages** — toasts, run counts, and load status use `role="status"`
  so updates are announced without moving focus.
- **Decorative glyphs** — emoji and arrow characters are wrapped in
  `aria-hidden="true"` spans so they are not read as words.

## Generated HTML

Three code paths emit HTML and are covered by source-level tests, because
static analysis cannot see markup that does not exist yet:

| Generator | Location |
| --- | --- |
| `ConvertTo-GenesysHtmlTable` | `modules/Genesys.Ops/Genesys.Ops.psm1` |
| `New-GenesysConversationPackageHtml`, `New-GenesysInvestigationPackageHtml` | `modules/Genesys.Ops/Genesys.Ops.psm1` |
| `Export-AuditHtml` | `apps/AuditLogsConsole/App.Export.psm1` |

Each emits a viewport meta, a skip link, a named `main` landmark, a
`:focus-visible` indicator, and tables with `<caption>` and `scope="col"`.

The conversation grid in `apps/ConversationAnalysis/index.html` builds its header
row at runtime; the table declares `data-dynamic-headers="true"` so the static
rule defers to a source-level assertion on the generator instead.

## Manual verification

Static analysis cannot evaluate rendered layout or runtime state. The following
criteria are verified by hand before a release and are **not** covered by the
automated gate:

- **1.4.10 Reflow** — no horizontal scrolling at 320 CSS pixels wide.
- **1.4.11 Non-text Contrast** — rendered chart series against their plot
  background (Chart.js palettes are chosen at runtime).
- **1.4.12 Text Spacing** — no clipping when user stylesheets increase line
  height and letter spacing.
- **1.4.13 Content on Hover or Focus** — tooltips are dismissible and hoverable.
- **2.4.3 Focus Order** — tab order matches the visual order end to end.
- **Translucent backgrounds** — the analyzer skips `rgba()` backgrounds whose
  alpha is below 1, because the composited colour depends on an ancestor it
  cannot resolve. The affected rules are the nav hover/active states in the
  consoles and the copy button in the onboarding page; all were checked by hand
  against their rendered backgrounds.
- **Screen-reader pass** — one full pass per console with NVDA or Narrator.

## History

- **2026-09-02** — Initial WCAG 2.1 AA conformance across all seven surfaces.
  175 violations remediated; static analyzer, CI gate, and Pester suite added.
  Also fixed a pre-existing mermaid parse failure in `docs/architecture.html`
  (`classDef call` — `call` is a reserved keyword) that left one architecture
  diagram rendering as an error box.
