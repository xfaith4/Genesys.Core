# Genesys.Core / Genesys.Ops Corrective Refactor Prompt

## Role

You are the next AI coding agent working on the `xfaith4/Genesys.Core` repository.

This repository is PowerShell-based and contains both:

- `Genesys.Core`: the core dataset invocation, catalog, paging, and run-artifact layer.
- `Genesys.Ops`: operational cmdlets that should consume `Genesys.Core` through dataset abstractions only.

Your task is to correct a prior diagnosis, complete the runtime body-override wiring in `Genesys.Ops`, close two release-gate items in `Genesys.Core`, update tests, and revise the coverage/readiness documentation.

---

## Critical Context

A previous session hardened `Genesys.Ops` and produced this report:

```text
docs/Genesys.Ops.DatasetCoverage.md
```

That report documented 11 functions as **blocked by Genesys.Core** because it assumed `Invoke-Dataset` needed a new `-BodyOverride` parameter.

That diagnosis was wrong.

`Genesys.Core` already supports the needed mechanism through:

```powershell
DatasetParameters = @{
    Body = <hashtable-or-json-body>
}
```

The correct implementation is to pass a `Body` key inside `DatasetParameters`, not to modify `Invoke-Dataset` with a new `-BodyOverride` parameter.

---

## Repository Areas to Read Before Editing

| Path | Purpose |
|---|---|
| `modules/Genesys.Core/Public/Invoke-Dataset.ps1` | Public dataset entrypoint. Accepts `-DatasetParameters [hashtable]`. |
| `modules/Genesys.Core/Private/Datasets.ps1` | Curated dataset handlers and `Invoke-SimpleCollectionDataset`. |
| `modules/Genesys.Core/Private/Paging.ps1` | Paging strategies: `Invoke-PagingNextUri`, `Invoke-PagingPageNumber`, `Invoke-PagingBodyPaging`, `Invoke-PagingCursor`. |
| `modules/Genesys.Ops/Genesys.Ops.psm1` | All Ops cmdlets and private helpers such as `Invoke-GenesysOpsDataset`, `Invoke-GenesysDataset`, and safe property helpers. |
| `catalog/genesys.catalog.json` | Single canonical catalog. `genesys-core.catalog.json` is retired. |
| `docs/Genesys.Ops.DatasetCoverage.md` | Coverage report produced by the previous session. |
| `docs/READINESS_REVIEW.md` | Release 1.0 gate document. Read the full file before changing it. |
| `tests/unit/` | Unit test suite. Run through `pwsh -File ./scripts/Invoke-Tests.ps1`. |

---

# Objectives

Complete the work in three phases.

| Phase | Goal |
|---|---|
| Phase A | Wire runtime body overrides into the 11 medium-risk `Genesys.Ops` functions. |
| Phase B | Fix two open `Genesys.Core` release-gate items from `docs/READINESS_REVIEW.md`. |
| Phase C | Update coverage and readiness documentation to reflect the corrected implementation. |

---

# Phase A — Wire Body Overrides in Genesys.Ops

## A.1 Why the Prior Diagnosis Was Wrong

`Invoke-SimpleCollectionDataset` already supports body override through `DatasetParameters['Body']`.

In `modules/Genesys.Core/Private/Datasets.ps1`, confirm logic equivalent to:

```powershell
if ($null -ne $DatasetParameters -and $DatasetParameters.ContainsKey('Body')) {
    $bodyValue = $DatasetParameters['Body']
    $initialBody = if ($bodyValue -is [string]) {
        $bodyValue
    }
    else {
        $bodyValue | ConvertTo-Json -Depth 100
    }
}
```

The 11 blocked analytics functions all route through `Invoke-SimpleCollectionDataset`. They are not curated registry handlers in `Get-DatasetRegistry`.

Therefore, this should already work end-to-end:

```powershell
Invoke-Dataset -DatasetKey <key> -DatasetParameters @{
    Body = $body
}
```

Do **not** add a new `-BodyOverride` parameter to `Invoke-Dataset`.

---

## A.2 Analytics Query Body Shapes

### Aggregates Query Endpoints

For endpoints like:

```text
/api/v2/analytics/*/aggregates/query
```

Build bodies in this shape:

```json
{
  "interval": "<ISO8601-start>/<ISO8601-end>",
  "granularity": "PT30M",
  "groupBy": ["queueId"],
  "filter": {
    "type": "and",
    "predicates": [
      {
        "type": "dimension",
        "dimension": "queueId",
        "operator": "matches",
        "value": "<id>"
      }
    ]
  },
  "metrics": ["nOffered", "nConnected", "tHandle"]
}
```

### Observations Query Endpoints

For endpoints like:

```text
/api/v2/analytics/*/observations/query
```

Build bodies in this shape:

```json
{
  "filter": {
    "type": "or",
    "predicates": [
      {
        "type": "dimension",
        "dimension": "queueId",
        "operator": "matches",
        "value": "<id>"
      }
    ]
  },
  "metrics": ["oInteracting", "oWaiting"]
}
```

---

## A.3 Implementation Requirements

For each of the 11 functions below:

1. Add the listed optional parameters.
2. Build a request body hashtable from those parameters.
3. Pass the body through:

```powershell
DatasetParameters = @{
    Body = $body
}
```

4. Invoke the dataset through the existing `Genesys.Ops` helper path:
   - Prefer `Invoke-GenesysOpsDataset` where that is the local convention.
   - Use `Invoke-GenesysDataset` only where the existing module pattern already does so.
5. Do not bypass the dataset abstraction.

---

## A.4 Functions to Update

| Function | New Optional Parameters | Filter Dimensions |
|---|---|---|
| `Get-GenesysQueueObservation` | `-QueueId [string[]]`, `-MediaType [string]` | `queueId`, `mediaType` |
| `Get-GenesysUserObservation` | `-UserId [string[]]` | `userId` |
| `Get-GenesysFlowObservation` | `-FlowType [string]`, `-FlowId [string[]]`, `-Interval [string]` | `flowType`, `flowId` |
| `Get-GenesysAgentPerformance` | `-UserId [string[]]`, `-MediaType [string]`, `-Since [datetime]`, `-Until [datetime]`, `-Granularity [string]` | `userId`, `mediaType` |
| `Get-GenesysAgentLoginActivity` | `-UserId [string[]]`, `-Since [datetime]`, `-Until [datetime]` | `userId` |
| `Get-GenesysQueuePerformance` | `-QueueId [string[]]`, `-MediaType [string]`, `-Since [datetime]`, `-Until [datetime]`, `-Granularity [string]` | `queueId`, `mediaType` |
| `Get-GenesysQueueAbandonRate` | `-QueueId [string[]]`, `-MediaType [string]`, `-Since [datetime]`, `-Until [datetime]` | `queueId`, `mediaType` |
| `Get-GenesysQueueServiceLevel` | `-QueueId [string[]]`, `-MediaType [string]`, `-Since [datetime]`, `-Until [datetime]` | `queueId`, `mediaType` |
| `Get-GenesysTransferAnalysis` | `-QueueId [string[]]`, `-Since [datetime]`, `-Until [datetime]` | `queueId` |
| `Get-GenesysWrapupDistribution` | `-QueueId [string[]]`, `-WrapupCodeId [string[]]`, `-Since [datetime]`, `-Until [datetime]` | `queueId`, `wrapUpCode` |
| `Get-GenesysDigitalChannelVolume` | `-MediaType [string]`, `-Since [datetime]`, `-Until [datetime]` | `mediaType` |

---

## A.5 Body-Building Rules

### Parameters

- All new parameters are optional.
- Observation endpoints do not require an interval.
- Time-windowed aggregate endpoints should use a sensible default when no time window is passed.
  - Recommended default: last 24 hours.
- If callers provide `-Since` and/or `-Until`, build a valid ISO-8601 interval string.
- `Get-GenesysFlowObservation` may accept a prebuilt `-Interval [string]`.

### Filters

- Build a `filter` block only when there is at least one predicate.
- Do not emit an empty filter object.
- Empty filter objects can cause API errors.
- For ID arrays, use `[string[]]`.
- For arrays with more than one value, create one predicate per value.
- Use `operator = "matches"` for dimension predicates.

### Predicate Shape

Use this shape:

```powershell
@{
    type      = 'dimension'
    dimension = '<dimensionName>'
    operator  = 'matches'
    value     = '<value>'
}
```

### Filter Type

For multiple predicates, prefer a clear helper that can create:

```powershell
@{
    type       = 'or'
    predicates = @($predicates)
}
```

For mixed dimensions, either:

- Use an `and` filter containing per-dimension `or` subfilters, if the API endpoint expects compound filters; or
- Follow the existing repository’s established analytics filter shape if one already exists.

Prefer the existing repository convention over inventing a new filter model.

---

## A.6 PowerShell Compatibility Rules

Preserve PowerShell 5.1 compatibility.

Do not use:

- Ternary operator: `?:`
- Null-coalescing operators
- `if` expressions inside hashtable literals
- PowerShell 7-only syntax

Use:

- Explicit `if` blocks
- Precomputed variables
- Plain arrays and hashtables
- Existing safe property helpers:
  - `Get-PropertyValue`
  - `Get-NestedPropertyValue`

Preserve:

```powershell
Set-StrictMode -Version Latest
```

---

## A.7 Non-Negotiable Genesys.Ops Constraint

Do **not** add either of these to `Genesys.Ops`:

```powershell
Invoke-RestMethod
Invoke-WebRequest
```

All extraction must go through:

```powershell
Invoke-GenesysOpsDataset
Invoke-GenesysDataset
Invoke-Dataset
```

---

# Phase B — Fix Two Open Genesys.Core Release-Gate Items

Both items are documented in:

```text
docs/READINESS_REVIEW.md
```

Read the full file before editing.

---

## B.1 Fix C-03 — Add Explicit Page-Count Ceiling to Invoke-PagingNextUri

### Target File

```text
modules/Genesys.Core/Private/Paging.ps1
```

### Target Function

```powershell
Invoke-PagingNextUri
```

### Current Problem

`Invoke-PagingNextUri` currently terminates only when:

- `nextUri` is absent; or
- a duplicate URI is detected.

`Invoke-PagingPageNumber` already has a `$maxPages = 1000` ceiling guard.

`Invoke-PagingNextUri` needs the same kind of ceiling.

### Required Changes

Add page-count ceiling logic:

1. Add or reuse a `$pageNumber` counter.
2. Read `$maxPages` from:

```powershell
$EndpointSpec.paging.maxPages
```

3. Default to `1000` when no value is configured.
4. Add a guard equivalent to:

```powershell
if ($pageNumber -gt $maxPages) {
    # log paging.terminated.maxPages run event
    break
}
```

5. Emit a run event named:

```text
paging.terminated.maxPages
```

6. Preserve existing duplicate-URI detection.
7. Preserve current paging behavior unless the ceiling is exceeded.

### Required Test

Add a Pester test in `tests/unit/` that:

- Uses a mock invoker that always returns a `nextUri`.
- Configures a low max-page ceiling.
- Confirms the guard fires at the configured ceiling.
- Confirms the function terminates instead of looping indefinitely.
- Confirms a `paging.terminated.maxPages` run event is emitted or captured according to existing test conventions.

### Documentation Update

After the test passes, update criterion `C-03` in:

```text
docs/READINESS_REVIEW.md
```

from:

```text
⚠️ PARTIAL
```

to:

```text
✅ GREEN
```

---

## B.2 Fix F-03 — Add CI Determinism Assertion for Run Artifacts

### Target Documentation

```text
docs/READINESS_REVIEW.md
```

Criterion `F-03` is currently `⚠️ PARTIAL`.

The gap: determinism is asserted only for fixtures, not in CI.

### Required Test

Add a Pester test in `tests/unit/`, near the existing run-contract tests, that:

1. Runs `Invoke-Dataset` twice using the same mock or fixture invoker.
2. Locates the generated run artifacts for both runs.
3. Compares both `summary.json` files byte-for-byte after stripping volatile fields:
   - `runId`
   - ISO-8601 timestamp fields
4. Compares all files under:

```text
data/*.jsonl
```

byte-for-byte.
5. Asserts the normalized outputs are identical.

### Documentation Update

After the test passes, update criterion `F-03` in:

```text
docs/READINESS_REVIEW.md
```

from:

```text
⚠️ PARTIAL
```

to:

```text
✅ GREEN
```

---

# Phase C — Update the Coverage Report

Update:

```text
docs/Genesys.Ops.DatasetCoverage.md
```

## Required Report Changes

1. Change all 11 previously medium-risk functions to **Low risk**.
2. Update this summary count:

```text
Functions relying on default body (Medium risk): 11
```

to:

```text
Functions relying on default body (Medium risk): 0
```

3. Update this summary count:

```text
Functions requiring parameter/body override work: 11
```

to:

```text
Functions requiring parameter/body override work: 0
```

4. Remove the blocker note equivalent to:

```text
Until Invoke-Dataset accepts a -BodyOverride parameter...
```

5. Replace it with:

```text
Body override is implemented via DatasetParameters['Body'] in Invoke-SimpleCollectionDataset. All 11 functions now accept runtime filter parameters.
```

6. Add an Implementation Summary row for each updated function group.
7. Mark `C-03` and `F-03` as resolved.

---

# Validation Requirements

Run the test suite before and after changes:

```powershell
pwsh -File ./scripts/Invoke-Tests.ps1
```

Expected result:

- All existing tests continue to pass.
- The new paging ceiling test passes.
- The new run-artifact determinism test passes.
- The prior baseline of 139 tests should not regress.
- The final test count should increase by the number of new tests added.

---

# Commit / Progress Requirements

Use `report_progress` after completing each phase:

1. After Phase A is complete.
2. After Phase B is complete.
3. After Phase C and final validation are complete.

Each progress report should include:

- Files changed.
- Tests added.
- Test status.
- Any unresolved risk or intentionally deferred item.

---

# Out-of-Scope Items

Do not touch live validation items:

```text
H-01 through H-08
```

Those require live Genesys Cloud credentials and are out of scope for this coding-agent task.

---

# Non-Negotiable Constraints

## Architecture

- Do not bypass `Genesys.Core`.
- Do not add direct REST calls in `Genesys.Ops`.
- Do not add `Invoke-RestMethod` or `Invoke-WebRequest` to `Genesys.Ops`.
- Do not add `-BodyOverride` to `Invoke-Dataset`.
- Use `DatasetParameters['Body']` as the body override mechanism.

## Compatibility

- Preserve PowerShell 5.1 compatibility.
- Preserve `Set-StrictMode -Version Latest`.
- Avoid PowerShell 7-only syntax.

## Scope Control

- Do not modify live-validation gate items `H-01` through `H-08`.
- Do not replace the catalog model.
- Do not revive `genesys-core.catalog.json`.
- Do not rewrite the module architecture.

---

# Key Facts to Verify Before Coding

Before editing files, confirm:

1. `DatasetParameters['Body']` wiring exists in `Invoke-SimpleCollectionDataset`.
2. `Invoke-GenesysOpsDataset` accepts a `$DatasetParameters` hashtable and forwards it to `Invoke-GenesysDataset`.
3. All 11 analytics dataset keys exist in:

```text
catalog/genesys.catalog.json
```

4. The relevant analytics endpoints are `method: POST`.
5. The relevant endpoints either have no `defaultBody` or require runtime body generation.
6. The 11 functions route through simple collection dataset handling.
7. `Invoke-PagingNextUri` loop structure is understood before adding a guard.
8. Existing tests in these files are reviewed before adding new tests:

```text
tests/unit/Paging.Tests.ps1
tests/unit/RunContract.Tests.ps1
```

---

# Acceptance Criteria

The task is complete only when all of the following are true:

- The 11 `Genesys.Ops` functions accept the required optional parameters.
- Those functions construct valid analytics query bodies.
- Runtime bodies are passed through `DatasetParameters['Body']`.
- No direct REST calls are added to `Genesys.Ops`.
- `Invoke-Dataset` is not modified with a `-BodyOverride` parameter.
- `Invoke-PagingNextUri` has a configurable max-page ceiling.
- The paging ceiling behavior has a Pester test.
- Run-artifact determinism is asserted by a CI-suitable Pester test.
- `docs/READINESS_REVIEW.md` marks `C-03` and `F-03` as `✅ GREEN`.
- `docs/Genesys.Ops.DatasetCoverage.md` reflects the corrected low-risk status of the 11 functions.
- `pwsh -File ./scripts/Invoke-Tests.ps1` passes.
- Any remaining risks are explicitly documented and are not hidden.

---

# Final Response Expected From Coding Agent

When finished, report:

1. Summary of implementation.
2. Files changed.
3. Tests added.
4. Test command run and result.
5. Confirmation that no direct REST calls were introduced.
6. Confirmation that `DatasetParameters['Body']` was used instead of `-BodyOverride`.
7. Any deferred live-validation items, specifically noting that `H-01` through `H-08` remain out of scope.
