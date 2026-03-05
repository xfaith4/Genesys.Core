## Critic skill: `agent-genesyscore-app-critic`

This is a **separate Claude/VSCode skill profile** whose only job is to **prove** the builder complied with the Core-first constitution. It doesn’t “suggest”; it **passes/fails** with receipts.

---

name: agent-genesyscore-app-critic
description: Reviews Genesys Core apps for strict Core-first compliance. Runs mechanical grep checks, verifies dataset key mapping, validates run-artifact consumption, indexing strategy, streaming exports, and PS gotchas. Produces pass/fail report with file+line references and required fixes.
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Genesys Core App Critic (Compliance + Quality)

## Critical Instructions

* **You are a gatekeeper.** Your output is a compliance verdict: PASS or FAIL.
* **No vibes-based approvals.** Every claim must cite a file path and matching line(s).
* **Never relax Core-first constraints.** If the app violates extraction rules, it fails.

---

## What You Must Verify (Hard Gates)

### Gate A — Core import + catalog validation

PASS only if:

* Genesys.Core is imported **only** in `App.CoreAdapter.psm1`
* `Assert-Catalog` is called at startup (CoreAdapter init)
* App fails fast with a visible UI error when catalog invalid

### Gate B — Dataset-driven extraction only

PASS only if:

* `Invoke-Dataset` is used for Preview and Full Run
* Preview dataset key = `analytics-conversation-details-query`
* Full dataset key = `analytics-conversation-details`
* No custom paging/retry/job polling exists in app code

### Gate C — UI reads run artifacts (streaming)

PASS only if:

* UI grid reads from run artifacts via streaming + index
* Drilldown loads a single record on demand
* Recent runs and open run folder exist

### Gate D — Mechanical forbidden patterns

FAIL if any appear anywhere in app code (excluding Genesys.Core path):

* `Invoke-RestMethod`
* `Invoke-WebRequest`
* `/api/v2/`
* Hardcoded Genesys Cloud API base URLs

Also FAIL if:

* Genesys.Core source exists inside the app repo (copied dependency)
* Genesys.Core is imported outside CoreAdapter

### Gate E — Authentication containment

PASS only if:

* If Core exports auth helper (Connect-*), app uses it
* Else `App.Auth.psm1` only returns headers and stores token securely
* No `/api/v2/` calls in auth module

---

## Scale & Performance Gates

### Indexing gate

PASS only if:

* Run index is created and cached: `index.jsonl` or `index.sqlite`
* Paging does not require rescanning full JSONL each page after indexing

### Streaming gate

FAIL if:

* `Get-Content` used on large `data\*.jsonl` for paging
* App keeps full dataset in memory (e.g., `$allConversations` global mega list)

### Export gate

PASS only if:

* Export of entire run is streaming (not “load all then export”)

---

## PowerShell Correctness Gates

FAIL if:

* StrictMode is missing in modules
* obvious `$var:` parser gotcha exists in strings (require `$($var):`)

---

## Required Output Format (Critic Report)

Produce:

1. `VERDICT: PASS|FAIL`
2. **Evidence table** with: Gate, Pass/Fail, File, Line, Note
3. **Fix list** (only if FAIL): exact change requests

---

## Commands you SHOULD use in review (examples)

* `Select-String -Path <appRoot>\*.ps* -Pattern 'Invoke-RestMethod|Invoke-WebRequest|/api/v2/' -AllMatches`
* `Select-String -Path <appRoot>\*.ps* -Pattern 'Import-Module\s+.*Genesys\.Core|Assert-Catalog|Invoke-Dataset' -AllMatches`
* Search for mega-list patterns: `List\[object\]::new|ObservableCollection.*AddRange|\$script:all`

---

## Test harness: reusable compliance + acceptance checks

This is a PowerShell script you can drop into every app repo under `Tests\Invoke-AppCompliance.ps1`. It’s designed to be:

* **Fast**
* **Deterministic**
* **PS 5.1 + PS 7 compatible**
* Friendly failure output (actionable)

### `Tests\Invoke-AppCompliance.ps1`

```powershell
### BEGIN FILE: Tests\Invoke-AppCompliance.ps1
[CmdletBinding()]
param(
  [Parameter()]
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,

  # Path to the Core module (used only to EXCLUDE it from forbidden scans if present on disk elsewhere)
  [Parameter()]
  [string]$CoreModulePath = $env:GENESYS_CORE_MODULE_PATH
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Fail {
  param([string]$Message, [object]$Details = $null)
  Write-Error $Message
  if ($null -ne $Details) {
    $Details | Format-List * | Out-String | Write-Host
  }
  throw $Message
}

function Get-AppFiles {
  param([string]$Root)
  # Scan PowerShell + XAML; exclude typical build folders
  $exclude = @("\bin\", "\obj\", "\.git\", "\.venv\", "\node_modules\")
  Get-ChildItem -Path $Root -Recurse -File |
    Where-Object {
      ($_.Extension -in @(".ps1",".psm1",".psd1",".xaml",".json",".md")) -and
      ($exclude | ForEach-Object { $_ } | Where-Object { $_ -and $_ -in $_.FullName }) -eq $null
    }
}

function Select-StringSafe {
  param(
    [string[]]$Paths,
    [string]$Pattern
  )
  $hits = @()
  foreach ($p in $Paths) {
    try {
      $m = Select-String -LiteralPath $p -Pattern $Pattern -AllMatches -ErrorAction SilentlyContinue
      if ($m) { $hits += $m }
    } catch { }
  }
  return $hits
}

# -----------------------------
# Identify app source files
# -----------------------------
$appFiles = Get-AppFiles -Root $RepoRoot
$psFiles  = $appFiles | Where-Object { $_.Extension -in @(".ps1",".psm1",".psd1") } | Select-Object -ExpandProperty FullName
$xamlFiles= $appFiles | Where-Object { $_.Extension -eq ".xaml" } | Select-Object -ExpandProperty FullName

if (-not $psFiles) { New-Fail "No PowerShell files found under RepoRoot: $RepoRoot" }

# -----------------------------
# Gate D: Forbidden patterns
# -----------------------------
$forbiddenPattern = "(Invoke-RestMethod|Invoke-WebRequest|/api/v2/)"
$forbiddenHits = Select-StringSafe -Paths $psFiles -Pattern $forbiddenPattern

# Exclude hits if they are inside Genesys.Core module folder (ONLY if the app repo accidentally contains it)
# But we ALSO separately fail if Genesys.Core is copied into the repo (see below).
if ($forbiddenHits.Count -gt 0) {
  New-Fail "Forbidden API patterns found in app source. The app must not call Genesys endpoints directly." ($forbiddenHits | Select-Object Path,LineNumber,Line)
}

# -----------------------------
# Gate: Genesys.Core must NOT be copied into repo
# -----------------------------
$coreCopied = Get-ChildItem -Path $RepoRoot -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -eq "Genesys.Core" -or $_.FullName -match "Genesys\.Core\\src\\ps-module" } |
  Select-Object -First 1

if ($coreCopied) {
  New-Fail "Genesys.Core appears to be copied into this repo ($($coreCopied.FullName)). Core must be a referenced dependency, not vendored into the app."
}

# -----------------------------
# Gate: Genesys.Core import must ONLY occur in App.CoreAdapter.psm1
# -----------------------------
$importPattern = "(Import-Module\s+.*Genesys\.Core|Import-Module\s+.*Genesys\.Core\.psd1|Assert-Catalog|Invoke-Dataset)"
$importHits = Select-StringSafe -Paths $psFiles -Pattern $importPattern

if (-not $importHits) {
  New-Fail "No evidence of Genesys.Core usage (Import-Module/Assert-Catalog/Invoke-Dataset) found. App must use Genesys.Core via Invoke-Dataset."
}

$coreAdapter = Join-Path $RepoRoot "App.CoreAdapter.psm1"
if (-not (Test-Path -LiteralPath $coreAdapter)) {
  New-Fail "Missing required module: App.CoreAdapter.psm1 (the only allowed Core integration seam)."
}

# Ensure Invoke-Dataset & Assert-Catalog appear in CoreAdapter
$coreAdapterHits = Select-String -LiteralPath $coreAdapter -Pattern "(Assert-Catalog|Invoke-Dataset)" -AllMatches -ErrorAction SilentlyContinue
if (-not $coreAdapterHits) {
  New-Fail "App.CoreAdapter.psm1 does not contain Assert-Catalog and/or Invoke-Dataset usage."
}

# Ensure Import-Module Genesys.Core appears only in CoreAdapter
$importCoreHits = Select-StringSafe -Paths $psFiles -Pattern "Import-Module\s+.*Genesys\.Core"
$importOutside = $importCoreHits | Where-Object { $_.Path -ne $coreAdapter }
if ($importOutside) {
  New-Fail "Genesys.Core is imported outside App.CoreAdapter.psm1. Only CoreAdapter may import Genesys.Core." ($importOutside | Select-Object Path,LineNumber,Line)
}

# -----------------------------
# Gate: StrictMode
# -----------------------------
$strictHits = Select-StringSafe -Paths $psFiles -Pattern "Set-StrictMode\s+-Version\s+Latest"
if (-not $strictHits) {
  New-Fail "Set-StrictMode -Version Latest not found. Require strict mode for reliability."
}

# -----------------------------
# Gate: Parser gotcha ($var:)
# - heuristic check: finds "$name:" style occurrences in double-quoted strings
#   and recommends $($name): instead. Not perfect, but catches common mistakes.
# -----------------------------
$colonVarHits = Select-StringSafe -Paths $psFiles -Pattern '"[^"]*\$[A-Za-z_][A-Za-z0-9_]*:'
if ($colonVarHits) {
  New-Fail "Potential PowerShell parser issue: variable followed by ':' inside double quotes. Use `$($var):` form." ($colonVarHits | Select-Object Path,LineNumber,Line)
}

Write-Host "✅ Compliance checks passed." -ForegroundColor Green
### END FILE: Tests\Invoke-AppCompliance.ps1
```

### Optional: `Tests\Invoke-AppSmoke.ps1` (fast “run-fix loop” equivalent)

This can be a minimal smoke test that:

* imports CoreAdapter
* runs catalog validation
* confirms preview run function exists
* (optionally) runs a preview with mocked parameters **only if** Core supports dry-run; otherwise skip

If you want, I’ll generate a smoke test tailored to your actual `Invoke-Dataset` signature (so it won’t guess wrong).

---

## How to use this harness (CLI + CI)

### Local

```powershell
pwsh -NoLogo -File .\Tests\Invoke-AppCompliance.ps1 -RepoRoot .
```

### GitHub Actions snippet

```yaml
- name: Compliance checks
  shell: pwsh
  run: |
    pwsh -NoLogo -File .\Tests\Invoke-AppCompliance.ps1 -RepoRoot .
```

---

## One improvement you’ll probably want immediately

The “Core copied into repo” detection is intentionally strict. If you prefer allowing a **git submodule** at `modules/Genesys.Core`, we can tweak the harness to allow that path *only if* it’s a submodule and never imported by relative path outside CoreAdapter.

---

If you drop these two pieces into your workflow—**Builder skill + Critic skill + harness**—you’ll get a self-healing loop:

1. Builder produces app
2. Critic runs harness → fails fast with line-level receipts
3. Builder fixes exactly what the harness flags
4. Repeat until PASS
