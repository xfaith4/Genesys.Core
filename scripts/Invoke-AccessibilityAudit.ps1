<#
    .SYNOPSIS
        Audits the shipped Genesys.Core HTML surfaces against WCAG 2.1 (A/AA).

    .DESCRIPTION
        Runs the dependency-free static analyzer in tools/Genesys.Accessibility
        over every surface listed in config/accessibility-surfaces.json (or the
        explicit -Path set) and reports violations grouped by file.

        Exits non-zero when violations remain, so the script can gate CI.

    .PARAMETER Path
        Explicit HTML files to audit. Defaults to the surfaces manifest.

    .PARAMETER Level
        Conformance level to enforce. Defaults to the manifest value ('AA').

    .PARAMETER ExcludeRule
        Rule ids to skip, for example 'A11Y020'.

    .PARAMETER JsonPath
        Optional path for a machine-readable JSON report.

    .PARAMETER PassThru
        Emit the finding objects on the pipeline in addition to the summary.

    .EXAMPLE
        pwsh -NoProfile -File ./scripts/Invoke-AccessibilityAudit.ps1

    .EXAMPLE
        pwsh -NoProfile -File ./scripts/Invoke-AccessibilityAudit.ps1 -JsonPath ./out/accessibility-audit.json
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [ValidateSet('A', 'AA')]
    [string]$Level,
    [string[]]$ExcludeRule = @(),
    [string]$JsonPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'tools/Genesys.Accessibility/Genesys.Accessibility.psd1'
Import-Module $modulePath -Force

$manifestPath = Join-Path $repoRoot 'config/accessibility-surfaces.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

if (-not $PSBoundParameters.ContainsKey('Level')) { $Level = $manifest.conformanceLevel }

$targets = if ($Path) {
    # Explicit paths carry no manifest entry, so they get no per-surface exclusions.
    @($Path | ForEach-Object { [pscustomobject]@{ Name = $_; FullPath = (Resolve-Path -LiteralPath $_).ProviderPath; Exclude = @() } })
}
else {
    @($manifest.surfaces | ForEach-Object {
            [pscustomobject]@{
                Name     = $_.name
                FullPath = (Join-Path $repoRoot $_.path)
                # Rules the surface cannot satisfy by its nature, justified in the manifest's
                # $excludeReason. Merged with -ExcludeRule rather than replacing it. The key is
                # optional, so it is tested for: strict mode rejects a blind dereference, and
                # @($missingProperty) would yield @($null) - a one-element array - regardless.
                Exclude  = if ($_.PSObject.Properties.Name -contains 'excludeRules') { @($_.excludeRules) } else { @() }
            }
        })
}

$missing = @($targets | Where-Object { -not (Test-Path -LiteralPath $_.FullPath) })
if ($missing.Count -gt 0) {
    throw "Accessibility surfaces missing from disk: $(($missing.FullPath) -join ', ')"
}

$allFindings = [System.Collections.Generic.List[object]]::new()

Write-Host ''
Write-Host "WCAG 2.1 Level $Level audit - $($targets.Count) surface(s)" -ForegroundColor Cyan
Write-Host ('=' * 72)

foreach ($target in $targets) {
    $exclusions = @($ExcludeRule) + @($target.Exclude) | Where-Object { $_ } | Select-Object -Unique
    $findings = @(Test-HtmlAccessibility -Path $target.FullPath -Level $Level -ExcludeRule @($exclusions))
    $relative = $target.FullPath.Replace($repoRoot, '').TrimStart('\', '/') -replace '\\', '/'

    if ($findings.Count -eq 0) {
        Write-Host ("  PASS  {0,-62} 0 violations" -f $relative) -ForegroundColor Green
        continue
    }

    Write-Host ("  FAIL  {0,-62} {1} violation(s)" -f $relative, $findings.Count) -ForegroundColor Red
    foreach ($finding in ($findings | Sort-Object Line, RuleId)) {
        Write-Host ("        line {0,-6} {1}  [{2}] {3}" -f $finding.Line, $finding.RuleId, $finding.Criterion, $finding.Message)
        $allFindings.Add([pscustomobject]@{
                File      = $relative
                Line      = $finding.Line
                RuleId    = $finding.RuleId
                Criterion = $finding.Criterion
                Level     = $finding.Level
                Element   = $finding.Element
                Message   = $finding.Message
            })
    }
}

Write-Host ('=' * 72)
$summary = [pscustomobject]@{
    GeneratedAtUtc   = [datetime]::UtcNow.ToString('o')
    ConformanceLevel = $Level
    SurfacesAudited  = $targets.Count
    ViolationCount   = $allFindings.Count
    Findings         = $allFindings.ToArray()
}

if ($allFindings.Count -eq 0) {
    Write-Host "PASS - $($targets.Count) surface(s) conform to WCAG 2.1 Level $Level under static analysis." -ForegroundColor Green
}
else {
    Write-Host "FAIL - $($allFindings.Count) violation(s) across $(@($allFindings.File | Select-Object -Unique).Count) file(s)." -ForegroundColor Red
}
Write-Host ''

if ($JsonPath) {
    $jsonDir = Split-Path -Parent $JsonPath
    if ($jsonDir -and -not (Test-Path -LiteralPath $jsonDir)) {
        New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $JsonPath -Encoding UTF8
    Write-Host "JSON report: $JsonPath"
}

if ($PassThru) { $summary }

if ($allFindings.Count -gt 0) { exit 1 }
