Set-StrictMode -Version Latest

<#
    Genesys.Accessibility
    ---------------------
    Static WCAG 2.1 (Level A / AA) conformance analyzer for the single-file HTML
    surfaces shipped by Genesys.Core (operator consoles, catalog browser, docs).

    The analyzer is deliberately dependency-free: it parses markup and CSS with
    regular expressions so it runs on Windows PowerShell 5.1 and PowerShell 7+
    with no npm/Node toolchain, in CI or offline.

    Scope note: static analysis cannot evaluate rendered layout, computed styles,
    or runtime DOM. Success criteria that require a rendered page (1.4.10 Reflow,
    1.4.11 Non-text Contrast on canvas output, 2.4.3 Focus Order in practice) are
    covered by the manual checklist in docs/ACCESSIBILITY.md, not by this module.
#>

$script:VoidElements = @(
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
    'param', 'source', 'track', 'wbr'
)

$script:InteractiveElements = @('a', 'button', 'input', 'select', 'textarea', 'summary', 'details', 'label', 'option')

$script:ValidAriaRoles = @(
    'alert', 'alertdialog', 'application', 'article', 'banner', 'button', 'cell', 'checkbox',
    'columnheader', 'combobox', 'complementary', 'contentinfo', 'definition', 'dialog',
    'directory', 'document', 'feed', 'figure', 'form', 'grid', 'gridcell', 'group', 'heading',
    'img', 'link', 'list', 'listbox', 'listitem', 'log', 'main', 'marquee', 'math', 'menu',
    'menubar', 'menuitem', 'menuitemcheckbox', 'menuitemradio', 'navigation', 'none', 'note',
    'option', 'presentation', 'progressbar', 'radio', 'radiogroup', 'region', 'row', 'rowgroup',
    'rowheader', 'scrollbar', 'search', 'searchbox', 'separator', 'slider', 'spinbutton',
    'status', 'switch', 'tab', 'table', 'tablist', 'tabpanel', 'term', 'textbox', 'timer',
    'toolbar', 'tooltip', 'tree', 'treegrid', 'treeitem'
)

# Rule catalogue. Level filters execution when -Level A is requested.
$script:RuleCatalog = @(
    [pscustomobject]@{ RuleId = 'A11Y001'; Criterion = '3.1.1 Language of Page'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y002'; Criterion = '2.4.2 Page Titled'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y003'; Criterion = '1.4.4 Resize Text'; Level = 'AA' }
    [pscustomobject]@{ RuleId = 'A11Y004'; Criterion = '1.3.1 Info and Relationships'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y005'; Criterion = '2.4.1 Bypass Blocks'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y006'; Criterion = '2.4.6 Headings and Labels'; Level = 'AA' }
    [pscustomobject]@{ RuleId = 'A11Y007'; Criterion = '1.3.1 Info and Relationships'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y008'; Criterion = '4.1.1 Parsing'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y009'; Criterion = '2.4.3 Focus Order'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y010'; Criterion = '3.3.2 Labels or Instructions'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y011'; Criterion = '4.1.2 Name, Role, Value'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y012'; Criterion = '1.1.1 Non-text Content'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y013'; Criterion = '1.1.1 Non-text Content'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y014'; Criterion = '1.1.1 Non-text Content'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y015'; Criterion = '2.1.1 Keyboard'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y016'; Criterion = '4.1.2 Name, Role, Value'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y017'; Criterion = '4.1.2 Name, Role, Value'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y018'; Criterion = '1.1.1 Non-text Content'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y019'; Criterion = '2.4.7 Focus Visible'; Level = 'AA' }
    [pscustomobject]@{ RuleId = 'A11Y020'; Criterion = '1.4.3 Contrast (Minimum)'; Level = 'AA' }
    [pscustomobject]@{ RuleId = 'A11Y021'; Criterion = '1.3.1 Info and Relationships'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y022'; Criterion = '4.1.3 Status Messages'; Level = 'AA' }
    [pscustomobject]@{ RuleId = 'A11Y023'; Criterion = '4.1.2 Name, Role, Value'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y024'; Criterion = '2.4.1 Bypass Blocks'; Level = 'A' }
    [pscustomobject]@{ RuleId = 'A11Y025'; Criterion = '1.4.3 Contrast (Minimum)'; Level = 'AA' }
)

function Get-GenesysAccessibilityRule {
    <#
        .SYNOPSIS
            Returns the rule catalogue enforced by Test-HtmlAccessibility.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $script:RuleCatalog | ForEach-Object { $_.PSObject.Copy() }
}

# ─────────────────────────── Colour helpers ────────────────────────────

function ConvertFrom-CssColor {
    <#
        .SYNOPSIS
            Parses a CSS colour literal into an RGB triple.
        .OUTPUTS
            [pscustomobject] with R, G, B (0-255) and A (0.0-1.0), or $null when
            unparseable (gradients, currentColor, named colours outside the map).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Color
    )

    $value = $Color.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }

    $named = @{
        'white' = '#ffffff'; 'black' = '#000000'; 'red' = '#ff0000'; 'green' = '#008000'
        'blue' = '#0000ff'; 'gray' = '#808080'; 'grey' = '#808080'; 'silver' = '#c0c0c0'
        'navy' = '#000080'; 'teal' = '#008080'; 'olive' = '#808000'; 'purple' = '#800080'
        'maroon' = '#800000'; 'lime' = '#00ff00'; 'aqua' = '#00ffff'; 'fuchsia' = '#ff00ff'
        'yellow' = '#ffff00'; 'orange' = '#ffa500'
    }
    if ($named.ContainsKey($value.ToLowerInvariant())) { $value = $named[$value.ToLowerInvariant()] }

    if ($value -match '^#([0-9a-fA-F]{3})$') {
        $h = $Matches[1]
        return [pscustomobject]@{
            R = [Convert]::ToInt32("$($h[0])$($h[0])", 16)
            G = [Convert]::ToInt32("$($h[1])$($h[1])", 16)
            B = [Convert]::ToInt32("$($h[2])$($h[2])", 16)
            A = 1.0
        }
    }
    if ($value -match '^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$') {
        $h = $Matches[1]
        $alpha = 1.0
        if ($Matches[2]) { $alpha = [Convert]::ToInt32($Matches[2], 16) / 255.0 }
        return [pscustomobject]@{
            R = [Convert]::ToInt32($h.Substring(0, 2), 16)
            G = [Convert]::ToInt32($h.Substring(2, 2), 16)
            B = [Convert]::ToInt32($h.Substring(4, 2), 16)
            A = $alpha
        }
    }
    if ($value -match '^rgba?\(\s*([0-9.]+)[\s,]+([0-9.]+)[\s,]+([0-9.]+)(?:[\s,/]+([0-9.]+%?))?') {
        $alpha = 1.0
        if ($Matches[4]) {
            $alpha = if ($Matches[4].EndsWith('%')) { [double]$Matches[4].TrimEnd('%') / 100.0 } else { [double]$Matches[4] }
        }
        return [pscustomobject]@{
            R = [int][double]$Matches[1]
            G = [int][double]$Matches[2]
            B = [int][double]$Matches[3]
            A = $alpha
        }
    }

    return $null
}

function Get-RelativeLuminance {
    <#
        .SYNOPSIS
            WCAG 2.1 relative luminance for an sRGB colour.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Rgb
    )

    $channel = {
        param([double]$Value)
        $s = $Value / 255.0
        if ($s -le 0.03928) { return $s / 12.92 }
        return [Math]::Pow((($s + 0.055) / 1.055), 2.4)
    }

    $r = & $channel $Rgb.R
    $g = & $channel $Rgb.G
    $b = & $channel $Rgb.B

    return (0.2126 * $r) + (0.7152 * $g) + (0.0722 * $b)
}

function Get-ContrastRatio {
    <#
        .SYNOPSIS
            WCAG 2.1 contrast ratio between two CSS colours (1.0 - 21.0).
        .EXAMPLE
            Get-ContrastRatio -Foreground '#5b6b62' -Background '#ffffff'
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Foreground,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Background
    )

    $fg = ConvertFrom-CssColor -Color $Foreground
    $bg = ConvertFrom-CssColor -Color $Background
    if ($null -eq $fg -or $null -eq $bg) { return [double]::NaN }

    $l1 = Get-RelativeLuminance -Rgb $fg
    $l2 = Get-RelativeLuminance -Rgb $bg
    if ($l2 -gt $l1) { $tmp = $l1; $l1 = $l2; $l2 = $tmp }

    return [Math]::Round((($l1 + 0.05) / ($l2 + 0.05)), 2)
}

# ─────────────────────────── Parsing helpers ───────────────────────────

function ConvertTo-BlankedSource {
    <#
        .SYNOPSIS
            Replaces comment / script / style bodies with spaces so markup rules
            never match inside them while byte offsets and line numbers stay valid.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Html
    )

    $builder = [System.Text.StringBuilder]::new($Html)
    $patterns = @(
        '(?s)<!--.*?-->',
        '(?s)(?<=<script\b[^>]*>).*?(?=</script>)',
        '(?s)(?<=<style\b[^>]*>).*?(?=</style>)'
    )

    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($builder.ToString(), $pattern, 'IgnoreCase')) {
            for ($i = $match.Index; $i -lt ($match.Index + $match.Length); $i++) {
                if ($builder[$i] -ne "`n" -and $builder[$i] -ne "`r") { $builder[$i] = ' ' }
            }
        }
    }

    return $builder.ToString()
}

function Get-LineOffsetTable {
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text
    )

    $offsets = [System.Collections.Generic.List[int]]::new()
    $offsets.Add(0)
    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq "`n") { $offsets.Add($i + 1) }
    }
    return $offsets.ToArray()
}

function Get-LineNumber {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [int[]]$Offsets,
        [Parameter(Mandatory)] [int]$Index
    )

    $lo = 0
    $hi = $Offsets.Length - 1
    while ($lo -lt $hi) {
        $mid = [int](($lo + $hi + 1) / 2)
        if ($Offsets[$mid] -le $Index) { $lo = $mid } else { $hi = $mid - 1 }
    }
    return $lo + 1
}

function ConvertFrom-HtmlAttribute {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$AttributeText
    )

    $attributes = @{}
    $pattern = '([a-zA-Z_:@][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|''([^'']*)''|([^\s"''=<>`]+)))?'
    foreach ($match in [regex]::Matches($AttributeText, $pattern)) {
        $name = $match.Groups[1].Value.ToLowerInvariant()
        $value = ''
        if ($match.Groups[2].Success) { $value = $match.Groups[2].Value }
        elseif ($match.Groups[3].Success) { $value = $match.Groups[3].Value }
        elseif ($match.Groups[4].Success) { $value = $match.Groups[4].Value }
        if (-not $attributes.ContainsKey($name)) { $attributes[$name] = $value }
    }
    return $attributes
}

function Get-HtmlElement {
    <#
        .SYNOPSIS
            Enumerates every tag in blanked markup as an ordered element list.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Markup,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [int[]]$Offsets
    )

    $pattern = '<(/?)([a-zA-Z][a-zA-Z0-9:-]*)((?:"[^"]*"|''[^'']*''|[^>"''])*?)(/?)>'
    $elements = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($match in [regex]::Matches($Markup, $pattern)) {
        $name = $match.Groups[2].Value.ToLowerInvariant()
        $isClosing = $match.Groups[1].Value -eq '/'
        $selfClosing = ($match.Groups[4].Value -eq '/') -or ($script:VoidElements -contains $name)

        $elements.Add([pscustomobject]@{
                Name         = $name
                IsClosing    = $isClosing
                SelfClosing  = $selfClosing
                Attributes   = if ($isClosing) { @{} } else { ConvertFrom-HtmlAttribute -AttributeText $match.Groups[3].Value }
                Index        = $match.Index
                EndIndex     = $match.Index + $match.Length
                Line         = Get-LineNumber -Offsets $Offsets -Index $match.Index
                Raw          = $match.Value
            })
    }

    return $elements.ToArray()
}

function Get-ElementInnerHtml {
    <#
        .SYNOPSIS
            Returns the raw inner markup for the opening tag at $StartOrdinal,
            or an empty string for void / self-closing elements.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Markup,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$Elements,
        [Parameter(Mandatory)] [int]$StartOrdinal
    )

    $open = $Elements[$StartOrdinal]
    if ($open.SelfClosing) { return '' }

    $depth = 1
    for ($i = $StartOrdinal + 1; $i -lt $Elements.Length; $i++) {
        $candidate = $Elements[$i]
        if ($candidate.Name -ne $open.Name) { continue }
        if ($candidate.SelfClosing) { continue }
        if ($candidate.IsClosing) {
            $depth--
            if ($depth -eq 0) { return $Markup.Substring($open.EndIndex, $candidate.Index - $open.EndIndex) }
        }
        else { $depth++ }
    }

    return ''
}

function ConvertTo-PlainText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Html
    )

    $text = [regex]::Replace($Html, '<[^>]*>', ' ')
    # Numeric entities are decoded, not dropped: a glyph written as &#9660; is
    # still a glyph, and rules that inspect text content must see it.
    $text = [regex]::Replace($text, '&#x([0-9a-fA-F]+);', {
            param($m) [char]::ConvertFromUtf32([Convert]::ToInt32($m.Groups[1].Value, 16))
        })
    $text = [regex]::Replace($text, '&#(\d+);', {
            param($m) [char]::ConvertFromUtf32([int]$m.Groups[1].Value)
        })
    $text = $text -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"'
    return ($text -replace '\s+', ' ').Trim()
}

function Test-HasReadableText {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text
    )

    return [bool]([regex]::IsMatch($Text, '[\p{L}\p{N}]'))
}

function Get-CssRuleBlock {
    <#
        .SYNOPSIS
            Extracts selector / declaration pairs from every <style> block.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Html,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [int[]]$Offsets
    )

    $blocks = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($style in [regex]::Matches($Html, '(?is)<style\b[^>]*>(.*?)</style>')) {
        $css = $style.Groups[1].Value
        $cssStart = $style.Groups[1].Index
        $stripped = [regex]::Replace($css, '(?s)/\*.*?\*/', { param($m) (' ' * $m.Value.Length) })

        foreach ($rule in [regex]::Matches($stripped, '(?s)([^{}]+)\{([^{}]*)\}')) {
            $selector = ($rule.Groups[1].Value -replace '\s+', ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($selector)) { continue }
            if ($selector.StartsWith('@')) { continue }

            $declarations = @{}
            foreach ($decl in ($rule.Groups[2].Value -split ';')) {
                if ($decl -notmatch '^\s*([-a-zA-Z]+)\s*:\s*(.+?)\s*$') { continue }
                $declarations[$Matches[1].ToLowerInvariant()] = $Matches[2].Trim()
            }

            $blocks.Add([pscustomobject]@{
                    Selector     = $selector
                    Declarations = $declarations
                    Line         = Get-LineNumber -Offsets $Offsets -Index ($cssStart + $rule.Index)
                })
        }
    }

    return $blocks.ToArray()
}

function Resolve-CssValue {
    <#
        .SYNOPSIS
            Resolves var(--token[, fallback]) references against collected
            custom-property definitions.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Value,
        [Parameter(Mandatory)] [hashtable]$Variables,
        [int]$Depth = 0
    )

    if ($Depth -gt 5) { return $Value }
    if ($Value -notmatch 'var\(') { return $Value }

    $resolved = [regex]::Replace($Value, 'var\(\s*(--[-a-zA-Z0-9_]+)\s*(?:,\s*([^()]*))?\)', {
            param($m)
            $token = $m.Groups[1].Value
            if ($Variables.ContainsKey($token)) { return $Variables[$token] }
            if ($m.Groups[2].Success) { return $m.Groups[2].Value.Trim() }
            return ''
        })

    return Resolve-CssValue -Value $resolved -Variables $Variables -Depth ($Depth + 1)
}

# ──────────────────── Simplified cascade for contrast ──────────────────

function ConvertTo-SimpleSelector {
    <#
        .SYNOPSIS
            Parses a comma-separated selector list into simple selectors the
            resolver can match. Complex selectors (descendant, pseudo-class,
            attribute) are skipped rather than approximated.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Selector
    )

    $result = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($part in ($Selector -split ',')) {
        $simple = $part.Trim()
        if ($simple -notmatch '^(?<tag>[a-zA-Z][a-zA-Z0-9]*)?(?<rest>(?:[.#][A-Za-z0-9_-]+)*)$') { continue }
        if ([string]::IsNullOrWhiteSpace($simple)) { continue }

        $tag = $Matches['tag']
        $rest = $Matches['rest']
        if ([string]::IsNullOrWhiteSpace($tag) -and [string]::IsNullOrWhiteSpace($rest)) { continue }

        $ids = @()
        $classes = @()
        foreach ($token in [regex]::Matches($rest, '([.#])([A-Za-z0-9_-]+)')) {
            if ($token.Groups[1].Value -eq '#') { $ids += $token.Groups[2].Value }
            else { $classes += $token.Groups[2].Value }
        }

        $result.Add([pscustomobject]@{
                Tag         = if ($tag) { $tag.ToLowerInvariant() } else { $null }
                Ids         = $ids
                Classes     = $classes
                Specificity = ($ids.Count * 100) + ($classes.Count * 10) + $(if ($tag) { 1 } else { 0 })
            })
    }

    return $result.ToArray()
}

function New-DomNodeTree {
    <#
        .SYNOPSIS
            Builds a parent-linked node tree with direct text for each element.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Markup,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$Elements
    )

    $nodes = [System.Collections.Generic.List[pscustomobject]]::new()
    $stack = [System.Collections.Generic.List[pscustomobject]]::new()
    $skipped = @('script', 'style', 'head', 'title', 'meta', 'link', 'br', 'template')

    for ($i = 0; $i -lt $Elements.Length; $i++) {
        $tag = $Elements[$i]
        if ($skipped -contains $tag.Name) { continue }

        if ($tag.IsClosing) {
            for ($s = $stack.Count - 1; $s -ge 0; $s--) {
                if ($stack[$s].Tag -eq $tag.Name) {
                    $stack[$s].TextEnd = $tag.Index
                    $stack.RemoveRange($s, $stack.Count - $s)
                    break
                }
            }
            continue
        }

        $attrs = $tag.Attributes
        $classes = @()
        if ($attrs.ContainsKey('class')) { $classes = @($attrs['class'] -split '\s+' | Where-Object { $_ }) }

        $node = [pscustomobject]@{
            Tag        = $tag.Name
            Id         = if ($attrs.ContainsKey('id')) { $attrs['id'] } else { $null }
            Classes    = $classes
            Style      = if ($attrs.ContainsKey('style')) { $attrs['style'] } else { '' }
            AriaHidden = $attrs.ContainsKey('aria-hidden') -and $attrs['aria-hidden'] -eq 'true'
            Parent     = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $null }
            Line       = $tag.Line
            TextStart  = $tag.EndIndex
            TextEnd    = $tag.EndIndex
            DirectText = ''
        }
        $nodes.Add($node)

        if (-not $tag.SelfClosing) { $stack.Add($node) | Out-Null }
    }

    foreach ($node in $nodes) {
        if ($node.TextEnd -le $node.TextStart) { continue }
        $inner = $Markup.Substring($node.TextStart, $node.TextEnd - $node.TextStart)
        # Direct text only: drop everything inside nested elements.
        $direct = [regex]::Replace($inner, '(?s)<[a-zA-Z][^>]*>.*?(?=<|$)', ' ')
        $direct = [regex]::Replace($direct, '<[^>]*>', ' ')
        $node.DirectText = (ConvertTo-PlainText -Html $direct)
    }

    return $nodes.ToArray()
}

function Get-CascadeStyle {
    <#
        .SYNOPSIS
            Resolves one declared CSS property for a node using simple-selector
            matching, specificity, source order, and the inline style attribute.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Node,
        [Parameter(Mandatory)] [string]$Property,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$Rules
    )

    if ($Node.Style -match "(?i)(?:^|;)\s*$([regex]::Escape($Property))\s*:\s*([^;]+)") {
        return $Matches[1].Trim()
    }

    $best = $null
    $bestScore = -1
    $order = 0
    foreach ($rule in $Rules) {
        $order++
        if (-not $rule.Declarations.ContainsKey($Property)) { continue }
        foreach ($simple in $rule.Simple) {
            if ($simple.Tag -and $simple.Tag -ne $Node.Tag) { continue }
            $matched = $true
            foreach ($id in $simple.Ids) { if ($Node.Id -ne $id) { $matched = $false; break } }
            if (-not $matched) { continue }
            foreach ($cls in $simple.Classes) { if ($Node.Classes -notcontains $cls) { $matched = $false; break } }
            if (-not $matched) { continue }

            $score = ($simple.Specificity * 100000) + $order
            if ($score -gt $bestScore) {
                $bestScore = $score
                $best = $rule.Declarations[$Property]
            }
        }
    }

    return $best
}

function Test-DomContrast {
    <#
        .SYNOPSIS
            Resolves foreground/background pairs from the parsed DOM and reports
            text that falls below the WCAG 2.1 SC 1.4.3 minimum.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$Nodes,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [pscustomobject[]]$CssBlocks,
        [Parameter(Mandatory)] [hashtable]$Variables
    )

    $rules = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($block in $CssBlocks) {
        if ($block.Selector -match ':(hover|focus|active|visited|disabled|checked)') { continue }
        $simple = @(ConvertTo-SimpleSelector -Selector $block.Selector)
        if ($simple.Count -eq 0) { continue }
        $rules.Add([pscustomobject]@{ Simple = $simple; Declarations = $block.Declarations })
    }
    $ruleArray = $rules.ToArray()

    $resolveColor = {
        param([pscustomobject]$Node, [string]$Property)
        $raw = Get-CascadeStyle -Node $Node -Property $Property -Rules $ruleArray
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $value = Resolve-CssValue -Value $raw -Variables $Variables
        if ($value -match '(?i)gradient|url\(|transparent|currentcolor|inherit') { return $null }
        if ($value -match '^\s*(\S+)') { $value = $Matches[1] }
        return ConvertFrom-CssColor -Color $value
    }

    foreach ($node in $Nodes) {
        if ($node.AriaHidden) { continue }
        if (-not (Test-HasReadableText -Text $node.DirectText)) { continue }

        # Foreground: own colour, else nearest ancestor that declares one.
        $fg = $null
        $cursor = $node
        while ($null -ne $cursor -and $null -eq $fg) {
            $fg = & $resolveColor $cursor 'color'
            $cursor = $cursor.Parent
        }
        if ($null -eq $fg -or $fg.A -lt 1.0) { continue }

        # Background: nearest opaque ancestor background; default page white.
        $bg = $null
        $cursor = $node
        $unresolved = $false
        while ($null -ne $cursor -and $null -eq $bg) {
            foreach ($prop in @('background-color', 'background')) {
                $candidate = & $resolveColor $cursor $prop
                if ($null -eq $candidate) {
                    $declared = Get-CascadeStyle -Node $cursor -Property $prop -Rules $ruleArray
                    if (-not [string]::IsNullOrWhiteSpace($declared)) { $unresolved = $true }
                    continue
                }
                if ($candidate.A -lt 1.0) { $unresolved = $true; continue }
                $bg = $candidate
                break
            }
            if ($unresolved) { break }
            $cursor = $cursor.Parent
        }
        if ($unresolved) { continue }
        if ($null -eq $bg) { $bg = [pscustomobject]@{ R = 255; G = 255; B = 255; A = 1.0 } }

        $l1 = Get-RelativeLuminance -Rgb $fg
        $l2 = Get-RelativeLuminance -Rgb $bg
        if ($l2 -gt $l1) { $tmp = $l1; $l1 = $l2; $l2 = $tmp }
        $ratio = [Math]::Round((($l1 + 0.05) / ($l2 + 0.05)), 2)

        # Large text (>=24px, or >=18.66px bold) may use the 3:1 minimum.
        $sizePx = 16.0
        $cursor = $node
        while ($null -ne $cursor) {
            $declared = Get-CascadeStyle -Node $cursor -Property 'font-size' -Rules $ruleArray
            if (-not [string]::IsNullOrWhiteSpace($declared)) {
                $declared = Resolve-CssValue -Value $declared -Variables $Variables
                if ($declared -match '^\s*([0-9.]+)px') { $sizePx = [double]$Matches[1]; break }
                if ($declared -match '^\s*([0-9.]+)(rem|em)') { $sizePx = [double]$Matches[1] * 16; break }
            }
            $cursor = $cursor.Parent
        }
        $weight = Get-CascadeStyle -Node $node -Property 'font-weight' -Rules $ruleArray
        $bold = $weight -match '^\s*(bold|[6-9]00)'
        $threshold = if ($sizePx -ge 24 -or ($bold -and $sizePx -ge 18.66)) { 3.0 } else { 4.5 }

        if ($ratio -lt $threshold) {
            $hexFg = '#{0:x2}{1:x2}{2:x2}' -f $fg.R, $fg.G, $fg.B
            $hexBg = '#{0:x2}{1:x2}{2:x2}' -f $bg.R, $bg.G, $bg.B
            $sample = $node.DirectText
            if ($sample.Length -gt 40) { $sample = $sample.Substring(0, 40) + '...' }
            [pscustomobject]@{
                Line    = $node.Line
                Element = $node.Tag
                Message = "Text '$sample' renders $hexFg on $hexBg at $ratio`:1, below the required $threshold`:1."
            }
        }
    }
}

# ───────────────────────────── Main analyzer ───────────────────────────

function Test-HtmlAccessibility {
    <#
        .SYNOPSIS
            Runs the static WCAG 2.1 rule set over one or more HTML files.

        .DESCRIPTION
            Emits one object per violation. An empty result means the file passed
            every statically decidable rule at the requested conformance level.

        .PARAMETER Path
            One or more HTML files to analyze.

        .PARAMETER Level
            'A' runs only Level A rules; 'AA' (default) runs Level A and AA rules.

        .PARAMETER ExcludeRule
            Rule ids to skip, for example 'A11Y020'.

        .EXAMPLE
            Test-HtmlAccessibility -Path ./apps/OpsConsole/index.html

        .OUTPUTS
            [pscustomobject] RuleId, Criterion, Level, File, Line, Element, Message
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,

        [ValidateSet('A', 'AA')]
        [string]$Level = 'AA',

        [string[]]$ExcludeRule = @()
    )

    begin {
        $activeRules = @{}
        foreach ($rule in $script:RuleCatalog) {
            if ($ExcludeRule -contains $rule.RuleId) { continue }
            if ($Level -eq 'A' -and $rule.Level -eq 'AA') { continue }
            $activeRules[$rule.RuleId] = $rule
        }
    }

    process {
        foreach ($item in $Path) {
            $resolved = @(Resolve-Path -LiteralPath $item -ErrorAction Stop)
            foreach ($file in $resolved) {
                $filePath = $file.ProviderPath
                $raw = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
                if ($null -eq $raw) { $raw = '' }

                foreach ($finding in (Invoke-AccessibilityRule -Html $raw -FilePath $filePath -ActiveRules $activeRules)) {
                    $finding
                }
            }
        }
    }
}

function Invoke-AccessibilityRule {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Html,
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [hashtable]$ActiveRules
    )

    $findings = [System.Collections.Generic.List[pscustomobject]]::new()
    $offsets = Get-LineOffsetTable -Text $Html
    $markup = ConvertTo-BlankedSource -Html $Html
    $elements = Get-HtmlElement -Markup $markup -Offsets $offsets
    $openTags = @($elements | Where-Object { -not $_.IsClosing })

    $add = {
        param([string]$RuleId, [int]$Line, [string]$Element, [string]$Message)
        if (-not $ActiveRules.ContainsKey($RuleId)) { return }
        $rule = $ActiveRules[$RuleId]
        $findings.Add([pscustomobject]@{
                RuleId    = $RuleId
                Criterion = $rule.Criterion
                Level     = $rule.Level
                File      = $FilePath
                Line      = $Line
                Element   = $Element
                Message   = $Message
            })
    }

    # Index of ids declared anywhere in the document.
    $declaredIds = @{}
    foreach ($tag in $openTags) {
        if (-not $tag.Attributes.ContainsKey('id')) { continue }
        $id = $tag.Attributes['id']
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($declaredIds.ContainsKey($id)) { $declaredIds[$id] = $declaredIds[$id] + 1 }
        else { $declaredIds[$id] = 1 }
    }

    # ── A11Y001 / A11Y002 / A11Y003 — document-level requirements ──
    $htmlTag = $openTags | Where-Object { $_.Name -eq 'html' } | Select-Object -First 1
    if ($null -eq $htmlTag -or -not $htmlTag.Attributes.ContainsKey('lang') -or [string]::IsNullOrWhiteSpace($htmlTag.Attributes['lang'])) {
        & $add 'A11Y001' 1 'html' 'The <html> element must declare a non-empty lang attribute.'
    }

    $titleTag = $openTags | Where-Object { $_.Name -eq 'title' } | Select-Object -First 1
    if ($null -eq $titleTag) {
        & $add 'A11Y002' 1 'title' 'The document must have a <title> element.'
    }
    else {
        $titleOrdinal = [Array]::IndexOf($elements, $titleTag)
        $titleText = ConvertTo-PlainText -Html (Get-ElementInnerHtml -Markup $markup -Elements $elements -StartOrdinal $titleOrdinal)
        if (-not (Test-HasReadableText -Text $titleText)) {
            & $add 'A11Y002' $titleTag.Line 'title' 'The <title> element must contain descriptive text.'
        }
    }

    $viewport = $openTags |
        Where-Object { $_.Name -eq 'meta' -and $_.Attributes.ContainsKey('name') -and $_.Attributes['name'].ToLowerInvariant() -eq 'viewport' } |
        Select-Object -First 1
    if ($null -eq $viewport) {
        & $add 'A11Y003' 1 'meta[name=viewport]' 'A responsive viewport meta tag is required so content can be resized and reflowed.'
    }
    else {
        $content = if ($viewport.Attributes.ContainsKey('content')) { $viewport.Attributes['content'] } else { '' }
        if ($content -match 'user-scalable\s*=\s*(no|0)') {
            & $add 'A11Y003' $viewport.Line 'meta[name=viewport]' 'The viewport must not set user-scalable=no; zoom to 200% must remain available.'
        }
        if ($content -match 'maximum-scale\s*=\s*([0-9.]+)' -and [double]$Matches[1] -lt 2) {
            & $add 'A11Y003' $viewport.Line 'meta[name=viewport]' "The viewport must not cap maximum-scale below 2 (found $($Matches[1]))."
        }
    }

    # ── A11Y004 — exactly one main landmark ──
    $mainLandmarks = @($openTags | Where-Object {
            $_.Name -eq 'main' -or ($_.Attributes.ContainsKey('role') -and $_.Attributes['role'] -eq 'main')
        })
    if ($mainLandmarks.Count -eq 0) {
        & $add 'A11Y004' 1 'main' 'The document must expose a single <main> landmark wrapping its primary content.'
    }
    elseif ($mainLandmarks.Count -gt 1) {
        & $add 'A11Y004' $mainLandmarks[1].Line 'main' "The document must expose exactly one main landmark (found $($mainLandmarks.Count))."
    }

    # ── A11Y024 / A11Y005 — bypass block ──
    $mainId = $null
    if ($mainLandmarks.Count -ge 1 -and $mainLandmarks[0].Attributes.ContainsKey('id')) { $mainId = $mainLandmarks[0].Attributes['id'] }

    $skipLinks = @($openTags | Where-Object {
            $_.Name -eq 'a' -and $_.Attributes.ContainsKey('href') -and $_.Attributes['href'].StartsWith('#') -and $_.Attributes['href'].Length -gt 1
        })
    $skipToMain = $false
    foreach ($link in $skipLinks) {
        $target = $link.Attributes['href'].Substring(1)
        if ($null -ne $mainId -and $target -eq $mainId) { $skipToMain = $true; break }
    }
    if (-not $skipToMain) {
        if ($null -eq $mainId) {
            & $add 'A11Y024' 1 'a.skip-link' 'The main landmark needs an id so a skip link can target it.'
        }
        else {
            & $add 'A11Y005' 1 'a.skip-link' "The document must provide a keyboard skip link whose href is '#$mainId'."
        }
    }

    # ── A11Y006 / A11Y007 — heading structure ──
    $headings = @($openTags | Where-Object { $_.Name -match '^h[1-6]$' })
    $h1s = @($headings | Where-Object { $_.Name -eq 'h1' })
    if ($h1s.Count -eq 0) {
        & $add 'A11Y006' 1 'h1' 'The document must contain exactly one <h1> naming the page.'
    }
    elseif ($h1s.Count -gt 1) {
        & $add 'A11Y006' $h1s[1].Line 'h1' "The document must contain exactly one <h1> (found $($h1s.Count))."
    }

    $previousLevel = 0
    foreach ($heading in $headings) {
        $current = [int]$heading.Name.Substring(1)
        if ($previousLevel -gt 0 -and $current -gt ($previousLevel + 1)) {
            & $add 'A11Y007' $heading.Line $heading.Name "Heading level jumps from h$previousLevel to h$current; heading levels must not skip."
        }
        $previousLevel = $current
    }

    # ── A11Y008 — duplicate ids ──
    foreach ($entry in $declaredIds.GetEnumerator()) {
        if ($entry.Value -le 1) { continue }
        $dup = $openTags | Where-Object { $_.Attributes.ContainsKey('id') -and $_.Attributes['id'] -eq $entry.Key } | Select-Object -Skip 1 -First 1
        & $add 'A11Y008' $dup.Line $dup.Name "Duplicate id '$($entry.Key)' appears $($entry.Value) times; ids must be unique."
    }

    # ── Per-element rules ──
    for ($ordinal = 0; $ordinal -lt $elements.Length; $ordinal++) {
        $tag = $elements[$ordinal]
        if ($tag.IsClosing) { continue }
        $attrs = $tag.Attributes
        $line = $tag.Line

        $ariaHidden = $attrs.ContainsKey('aria-hidden') -and $attrs['aria-hidden'] -eq 'true'
        $role = if ($attrs.ContainsKey('role')) { $attrs['role'].Trim().ToLowerInvariant() } else { '' }

        # A11Y009 — positive tabindex
        if ($attrs.ContainsKey('tabindex')) {
            $tabIndexValue = 0
            if ([int]::TryParse($attrs['tabindex'], [ref]$tabIndexValue) -and $tabIndexValue -gt 0) {
                & $add 'A11Y009' $line $tag.Name "tabindex=$tabIndexValue overrides natural focus order; use 0 or -1."
            }
        }

        # A11Y023 — role must be a valid ARIA role
        if (-not [string]::IsNullOrWhiteSpace($role)) {
            foreach ($token in ($role -split '\s+')) {
                if ($script:ValidAriaRoles -notcontains $token) {
                    & $add 'A11Y023' $line $tag.Name "'$token' is not a valid ARIA role."
                }
            }
        }

        # A11Y016 — IDREF attributes must resolve
        foreach ($idrefAttr in @('aria-labelledby', 'aria-describedby', 'aria-controls', 'aria-owns', 'for')) {
            if (-not $attrs.ContainsKey($idrefAttr)) { continue }
            if ($idrefAttr -eq 'for' -and $tag.Name -ne 'label') { continue }
            foreach ($ref in ($attrs[$idrefAttr] -split '\s+')) {
                if ([string]::IsNullOrWhiteSpace($ref)) { continue }
                if (-not $declaredIds.ContainsKey($ref)) {
                    & $add 'A11Y016' $line $tag.Name "$idrefAttr references '$ref', which is not declared anywhere in the document."
                }
            }
        }

        # A11Y012 — images need alt text
        if ($tag.Name -eq 'img' -and -not $attrs.ContainsKey('alt')) {
            & $add 'A11Y012' $line 'img' 'Every <img> needs an alt attribute (alt="" when decorative).'
        }

        # A11Y014 — inline SVG must be labelled or hidden
        if ($tag.Name -eq 'svg' -and -not $ariaHidden) {
            $svgInner = Get-ElementInnerHtml -Markup $markup -Elements $elements -StartOrdinal $ordinal
            $hasTitle = $svgInner -match '(?i)<title\b'
            $hasLabel = ($attrs.ContainsKey('aria-label') -and -not [string]::IsNullOrWhiteSpace($attrs['aria-label'])) -or $attrs.ContainsKey('aria-labelledby')
            if (-not $hasTitle -and -not $hasLabel) {
                & $add 'A11Y014' $line 'svg' 'Inline <svg> must carry role="img" with an accessible name, or aria-hidden="true" when decorative.'
            }
            elseif ($role -ne 'img') {
                & $add 'A11Y014' $line 'svg' 'A labelled inline <svg> must also declare role="img" so its name is exposed.'
            }
        }

        # A11Y013 — canvas needs a text alternative
        if ($tag.Name -eq 'canvas') {
            $hasName = ($attrs.ContainsKey('aria-label') -and -not [string]::IsNullOrWhiteSpace($attrs['aria-label'])) -or $attrs.ContainsKey('aria-labelledby')
            $fallback = ConvertTo-PlainText -Html (Get-ElementInnerHtml -Markup $markup -Elements $elements -StartOrdinal $ordinal)
            if (-not $hasName -and -not (Test-HasReadableText -Text $fallback)) {
                & $add 'A11Y013' $line 'canvas' 'Every <canvas> chart needs role="img" plus an accessible name, or readable fallback content.'
            }
            elseif ($role -ne 'img' -and -not $ariaHidden) {
                & $add 'A11Y013' $line 'canvas' 'A named <canvas> must declare role="img" so assistive technology exposes the name.'
            }
        }

        # A11Y015 — click handlers on non-interactive elements
        $hasClickHandler = $attrs.ContainsKey('onclick')
        if ($hasClickHandler -and $script:InteractiveElements -notcontains $tag.Name) {
            $interactiveRole = @('button', 'link', 'tab', 'menuitem', 'checkbox', 'radio', 'switch', 'option') -contains $role
            $focusable = $attrs.ContainsKey('tabindex')
            $keyboard = $attrs.ContainsKey('onkeydown') -or $attrs.ContainsKey('onkeyup') -or $attrs.ContainsKey('onkeypress')
            if (-not ($interactiveRole -and $focusable -and $keyboard)) {
                & $add 'A11Y015' $line $tag.Name 'A click handler on a non-interactive element must be a <button>, or carry an interactive role, tabindex, and a keyboard handler.'
            }
        }

        # A11Y010 — form controls need an accessible name
        if (@('input', 'select', 'textarea') -contains $tag.Name) {
            $type = if ($attrs.ContainsKey('type')) { $attrs['type'].ToLowerInvariant() } else { 'text' }
            if ($type -notin @('hidden', 'submit', 'reset', 'button', 'image')) {
                $named = ($attrs.ContainsKey('aria-label') -and -not [string]::IsNullOrWhiteSpace($attrs['aria-label'])) -or
                         $attrs.ContainsKey('aria-labelledby') -or
                        ($attrs.ContainsKey('title') -and -not [string]::IsNullOrWhiteSpace($attrs['title']))
                if (-not $named -and $attrs.ContainsKey('id')) {
                    $controlId = $attrs['id']
                    $named = [bool](@($openTags | Where-Object {
                                $_.Name -eq 'label' -and $_.Attributes.ContainsKey('for') -and $_.Attributes['for'] -eq $controlId
                            }).Count)
                }
                if (-not $named) {
                    & $add 'A11Y010' $line $tag.Name 'Form controls need a programmatic label: <label for>, aria-label, or aria-labelledby. A placeholder is not a label.'
                }
            }
        }

        # A11Y011 — interactive controls need an accessible name
        if (@('button', 'a', 'summary') -contains $tag.Name -and -not $ariaHidden) {
            if ($tag.Name -eq 'a' -and -not $attrs.ContainsKey('href')) { continue }
            $named = ($attrs.ContainsKey('aria-label') -and -not [string]::IsNullOrWhiteSpace($attrs['aria-label'])) -or
                     $attrs.ContainsKey('aria-labelledby') -or
                    ($attrs.ContainsKey('title') -and -not [string]::IsNullOrWhiteSpace($attrs['title']))
            if (-not $named) {
                $inner = Get-ElementInnerHtml -Markup $markup -Elements $elements -StartOrdinal $ordinal
                # An aria-hidden decorative child contributes nothing to the name.
                $visible = [regex]::Replace($inner, '(?is)<([a-z][a-z0-9]*)\b[^>]*aria-hidden\s*=\s*("true"|''true'')[^>]*>.*?</\1>', ' ')
                $named = Test-HasReadableText -Text (ConvertTo-PlainText -Html $visible)
                if (-not $named) { $named = $inner -match '(?i)<img\b[^>]*\salt\s*=\s*"[^"]+"' }
            }
            if (-not $named) {
                & $add 'A11Y011' $line $tag.Name "<$($tag.Name)> has no accessible name; add text content or aria-label."
            }
        }

        # A11Y018 — glyph-only leaf content must be hidden or named
        if (-not $ariaHidden -and -not $tag.SelfClosing -and @('span', 'div', 'i', 'em', 'strong', 'b', 'td', 'th', 'p', 'li') -contains $tag.Name) {
            $inner = Get-ElementInnerHtml -Markup $markup -Elements $elements -StartOrdinal $ordinal
            if ($inner -notmatch '<') {
                $text = ConvertTo-PlainText -Html $inner
                $hasName = ($attrs.ContainsKey('aria-label') -and -not [string]::IsNullOrWhiteSpace($attrs['aria-label'])) -or $attrs.ContainsKey('aria-labelledby')
                if (-not $hasName -and $text.Length -gt 0 -and -not (Test-HasReadableText -Text $text)) {
                    & $add 'A11Y018' $line $tag.Name "Decorative glyph content '$text' must be marked aria-hidden=`"true`" or given an accessible name."
                }
            }
        }

        # A11Y021 — data tables need headers and an accessible name
        if ($tag.Name -eq 'table') {
            $tableInner = Get-ElementInnerHtml -Markup $markup -Elements $elements -StartOrdinal $ordinal
            $named = ($attrs.ContainsKey('aria-label') -and -not [string]::IsNullOrWhiteSpace($attrs['aria-label'])) -or
                     $attrs.ContainsKey('aria-labelledby') -or
                     ($tableInner -match '(?i)<caption\b')
            if (-not $named) {
                & $add 'A11Y021' $line 'table' 'Data tables need an accessible name via <caption>, aria-label, or aria-labelledby.'
            }
            $headerCells = [regex]::Matches($tableInner, '(?i)<th\b([^>]*)>')
            # A table whose header row is built at runtime declares that
            # explicitly; the generator is covered by a source-level test
            # instead, because static analysis cannot see emitted markup.
            $dynamicHeaders = $attrs.ContainsKey('data-dynamic-headers') -and $attrs['data-dynamic-headers'] -eq 'true'
            if ($headerCells.Count -eq 0 -and -not $dynamicHeaders) {
                & $add 'A11Y021' $line 'table' 'Data tables must mark header cells with <th>, or declare data-dynamic-headers="true" when the header row is generated at runtime.'
            }
            else {
                foreach ($cell in $headerCells) {
                    if ($cell.Groups[1].Value -notmatch '(?i)\bscope\s*=') {
                        & $add 'A11Y021' $line 'th' 'Every <th> must declare scope="col" or scope="row".'
                        break
                    }
                }
            }
        }

        # A11Y022 — transient status containers must be live regions
        $identity = ''
        if ($attrs.ContainsKey('id')) { $identity += ' ' + $attrs['id'] }
        if ($attrs.ContainsKey('class')) { $identity += ' ' + $attrs['class'] }
        if ($identity -match '(?i)(^|[\s_-])(toast|snackbar|notification|banner)([\s_-]|$)') {
            $isLive = $attrs.ContainsKey('aria-live') -or @('status', 'alert', 'log') -contains $role
            if (-not $isLive) {
                & $add 'A11Y022' $line $tag.Name 'Containers that surface transient messages must be live regions (role="status" or aria-live).'
            }
        }
    }

    # ── A11Y017 — tab widget wiring ──
    $tabs = @($openTags | Where-Object { $_.Attributes.ContainsKey('role') -and $_.Attributes['role'] -eq 'tab' })
    $tabLists = @($openTags | Where-Object { $_.Attributes.ContainsKey('role') -and $_.Attributes['role'] -eq 'tablist' })
    $tabPanels = @($openTags | Where-Object { $_.Attributes.ContainsKey('role') -and $_.Attributes['role'] -eq 'tabpanel' })

    if ($tabs.Count -gt 0 -and $tabLists.Count -eq 0) {
        & $add 'A11Y017' $tabs[0].Line 'role=tab' 'Elements with role="tab" must be contained by an element with role="tablist".'
    }
    foreach ($tab in $tabs) {
        if (-not $tab.Attributes.ContainsKey('aria-selected')) {
            & $add 'A11Y017' $tab.Line 'role=tab' 'Each role="tab" must declare aria-selected.'
        }
        if (-not $tab.Attributes.ContainsKey('aria-controls')) {
            & $add 'A11Y017' $tab.Line 'role=tab' 'Each role="tab" must declare aria-controls pointing at its panel.'
            continue
        }
        $panelId = $tab.Attributes['aria-controls']
        $panel = $tabPanels | Where-Object { $_.Attributes.ContainsKey('id') -and $_.Attributes['id'] -eq $panelId } | Select-Object -First 1
        if ($null -eq $panel) {
            & $add 'A11Y017' $tab.Line 'role=tab' "aria-controls='$panelId' does not resolve to an element with role=`"tabpanel`"."
        }
    }
    foreach ($panel in $tabPanels) {
        if (-not $panel.Attributes.ContainsKey('aria-labelledby')) {
            & $add 'A11Y017' $panel.Line 'role=tabpanel' 'Each role="tabpanel" must declare aria-labelledby referencing its tab.'
        }
    }

    # ── CSS rules: A11Y019 focus visibility, A11Y020 contrast ──
    $cssBlocks = Get-CssRuleBlock -Html $Html -Offsets $offsets

    $variables = @{}
    foreach ($block in $cssBlocks) {
        foreach ($decl in $block.Declarations.GetEnumerator()) {
            if ($decl.Key.StartsWith('--')) { $variables[$decl.Key] = $decl.Value }
        }
    }
    foreach ($key in @($variables.Keys)) {
        $variables[$key] = Resolve-CssValue -Value $variables[$key] -Variables $variables
    }

    if ($ActiveRules.ContainsKey('A11Y019')) {
        $focusBlocks = @($cssBlocks | Where-Object { $_.Selector -match ':focus' })
        $visibleFocus = @($focusBlocks | Where-Object {
                $d = $_.Declarations
                ($d.ContainsKey('outline') -and $d['outline'] -notmatch '^\s*(none|0)\s*$') -or
                ($d.ContainsKey('outline-width') -and $d['outline-width'] -notmatch '^\s*0') -or
                $d.ContainsKey('box-shadow')
            })
        if ($visibleFocus.Count -eq 0) {
            & $add 'A11Y019' 1 ':focus-visible' 'The stylesheet must define a visible keyboard focus indicator (:focus-visible with an outline or box-shadow).'
        }
        # Any rule that zeroes the outline suppresses the focus ring, whether or
        # not the selector mentions :focus. It is acceptable only when a
        # :focus rule for the same base selector restores an indicator.
        $focusSelectors = @($focusBlocks | ForEach-Object { $_.Selector })
        foreach ($block in $cssBlocks) {
            $d = $block.Declarations
            if (-not $d.ContainsKey('outline')) { continue }
            if ($d['outline'] -notmatch '^\s*(none|0)\s*$') { continue }
            if ($d.ContainsKey('box-shadow') -or $d.ContainsKey('border') -or $d.ContainsKey('background') -or $d.ContainsKey('background-color')) { continue }

            $covered = $false
            if ($block.Selector -notmatch ':focus') {
                foreach ($focusSelector in $focusSelectors) {
                    if ($focusSelector -like "$($block.Selector):focus*") { $covered = $true; break }
                }
            }
            if ($covered) { continue }

            & $add 'A11Y019' $block.Line $block.Selector "Selector '$($block.Selector)' removes the focus outline without providing a replacement indicator."
        }
    }

    if ($ActiveRules.ContainsKey('A11Y020')) {
        foreach ($block in $cssBlocks) {
            $d = $block.Declarations
            if (-not $d.ContainsKey('color')) { continue }

            $bgRaw = $null
            if ($d.ContainsKey('background-color')) { $bgRaw = $d['background-color'] }
            elseif ($d.ContainsKey('background')) { $bgRaw = $d['background'] }
            if ($null -eq $bgRaw) { continue }
            # Gradients and layered backgrounds cannot be reduced to one colour.
            if ($bgRaw -match '(?i)gradient|url\(') { continue }

            $fg = Resolve-CssValue -Value $d['color'] -Variables $variables
            $bg = Resolve-CssValue -Value $bgRaw -Variables $variables
            if ($bg -match '^\s*(\S+)') { $bg = $Matches[1] }
            if ([string]::IsNullOrWhiteSpace($fg) -or [string]::IsNullOrWhiteSpace($bg)) { continue }

            # A translucent background composites against an ancestor this
            # analyzer cannot resolve; those pairs are on the manual checklist.
            $bgColor = ConvertFrom-CssColor -Color $bg
            if ($null -ne $bgColor -and $bgColor.A -lt 1.0) { continue }

            $ratio = Get-ContrastRatio -Foreground $fg -Background $bg
            if ([double]::IsNaN($ratio)) { continue }

            $threshold = 4.5
            $sizePx = 0.0
            if ($d.ContainsKey('font-size')) {
                if ($d['font-size'] -match '^\s*([0-9.]+)px') { $sizePx = [double]$Matches[1] }
                elseif ($d['font-size'] -match '^\s*([0-9.]+)(rem|em)') { $sizePx = [double]$Matches[1] * 16 }
            }
            $bold = $d.ContainsKey('font-weight') -and $d['font-weight'] -match '^\s*(bold|[6-9]00)'
            if ($sizePx -ge 24 -or ($bold -and $sizePx -ge 18.66)) { $threshold = 3.0 }

            if ($ratio -lt $threshold) {
                & $add 'A11Y020' $block.Line $block.Selector "Contrast $ratio`:1 for $fg on $bg is below the required $threshold`:1."
            }
        }
    }

    if ($ActiveRules.ContainsKey('A11Y025')) {
        $nodes = New-DomNodeTree -Markup $markup -Elements $elements
        foreach ($hit in (Test-DomContrast -Nodes $nodes -CssBlocks $cssBlocks -Variables $variables)) {
            & $add 'A11Y025' $hit.Line $hit.Element $hit.Message
        }
    }

    return $findings.ToArray()
}

Export-ModuleMember -Function @(
    'Test-HtmlAccessibility',
    'Get-GenesysAccessibilityRule',
    'Get-ContrastRatio',
    'Get-RelativeLuminance',
    'ConvertFrom-CssColor'
)
