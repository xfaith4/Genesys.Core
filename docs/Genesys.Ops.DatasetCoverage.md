# Genesys.Ops Dataset Coverage Report

> Version: 2.0 — 2026-05-01
>
> Supersedes the prior coverage report. Body-override is implemented via
> `DatasetParameters['Body']` in `Invoke-SimpleCollectionDataset`. All eleven
> previously medium-risk analytics functions now accept runtime filter
> parameters and construct request bodies inline.

---

## Summary

| Metric | Count |
|---|---|
| Functions relying on default body (Medium risk) | 0 |
| Functions requiring parameter/body override work | 0 |
| Functions covered as Low risk after the 2026-05-01 refactor | 11 |

## Evidence interpretation

`Risk: Low` in this report means the wrapper implementation is low risk after
offline runtime checks. It does not mean the dataset is live-ready.

Evidence: `Dataset route construction passed`; `Dataset response processing
passed` where mocked or fixture responses cover the function path.

Live status: `unvalidated` unless separately promoted in
`docs/READINESS_REVIEW.md` with `Live Invoke-Dataset acceptance passed`.

The previous report's blocker note —
> *Until `Invoke-Dataset` accepts a `-BodyOverride` parameter, eleven analytics
> functions cannot scope their queries at runtime…*

— was based on a misdiagnosis. Body override is implemented via
`DatasetParameters['Body']` in `Invoke-SimpleCollectionDataset`. All eleven
functions now accept runtime filter parameters.

---

## How runtime body override works

`Invoke-SimpleCollectionDataset` (`modules/Genesys.Core/Private/Datasets.ps1`)
accepts a `Body` key inside `DatasetParameters`:

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

`Genesys.Ops` calls `Invoke-Dataset` through the local `Invoke-GenesysDataset`
helper, which now forwards a `[hashtable] $DatasetParameters` argument. Each
analytics cmdlet builds an ordered hashtable for `Body` and passes it through:

```powershell
Invoke-GenesysDataset -Dataset <key> -DatasetParameters @{ Body = $body }
```

No new `-BodyOverride` parameter was added to `Invoke-Dataset`. No direct REST
calls were introduced into `Genesys.Ops`.

---

## Implementation summary by function group

### Real-time observation cmdlets

POST `/api/v2/analytics/*/observations/query`. Body shape:
`{ filter?, metrics }` — no interval.

| Function | Optional parameters | Filter dimensions | Risk |
|---|---|---|---|
| `Get-GenesysQueueObservation` | `-QueueId [string[]]`, `-MediaType [string]` | `queueId`, `mediaType` | Low |
| `Get-GenesysUserObservation` | `-UserId [string[]]` | `userId` | Low |
| `Get-GenesysFlowObservation` | `-FlowType [string]`, `-FlowId [string[]]`, `-Interval [string]` | `flowType`, `flowId` | Low |

### Aggregate metric cmdlets

POST `/api/v2/analytics/*/aggregates/query`. Body shape:
`{ interval, granularity?, groupBy, filter?, metrics }`. When `-Since`/`-Until`
are not supplied, a 24-hour default lookback is computed via
`New-GenesysAnalyticsInterval`.

| Function | Optional parameters | Filter dimensions | Risk |
|---|---|---|---|
| `Get-GenesysAgentPerformance` | `-UserId`, `-MediaType`, `-Since`, `-Until`, `-Granularity` | `userId`, `mediaType` | Low |
| `Get-GenesysAgentLoginActivity` | `-UserId`, `-Since`, `-Until` | `userId` | Low |
| `Get-GenesysQueuePerformance` | `-QueueId`, `-MediaType`, `-Since`, `-Until`, `-Granularity` | `queueId`, `mediaType` | Low |
| `Get-GenesysQueueAbandonRate` | `-QueueId`, `-MediaType`, `-Since`, `-Until` | `queueId`, `mediaType` | Low |
| `Get-GenesysQueueServiceLevel` | `-QueueId`, `-MediaType`, `-Since`, `-Until` | `queueId`, `mediaType` | Low |
| `Get-GenesysTransferAnalysis` | `-QueueId`, `-Since`, `-Until` | `queueId` | Low |
| `Get-GenesysWrapupDistribution` | `-QueueId`, `-WrapupCodeId`, `-Since`, `-Until` | `queueId`, `wrapUpCode` | Low |
| `Get-GenesysDigitalChannelVolume` | `-MediaType`, `-Since`, `-Until` | `mediaType` | Low |

---

## Filter shape

`New-GenesysAnalyticsFilter` (private helper in `Genesys.Ops.psm1`) emits:

- **No filter** — when no parameters yield predicates. The `filter` key is
  omitted entirely (Genesys treats an empty filter object as an error).
- **Single dimension, single value** —
  `{ type:'and', predicates:[ { type:'dimension', dimension, operator:'matches', value } ] }`
- **Single dimension, multiple values** —
  `{ type:'or', predicates:[ … ] }`
- **Multiple dimensions** —
  `{ type:'and', clauses:[ { type:'or', predicates:[…] }, … ] }` with one
  sub-clause per dimension.

All predicates use `operator = 'matches'`.

---

## Constraints honoured

- No `Invoke-RestMethod` or `Invoke-WebRequest` was added to `Genesys.Ops`.
- `Invoke-Dataset` was **not** modified with a `-BodyOverride` parameter.
- All extraction goes through `Invoke-GenesysDataset` → `Invoke-Dataset` →
  `Invoke-SimpleCollectionDataset`.
- PowerShell 5.1 compatibility preserved: no ternary, no null-coalescing, no
  `if`-expressions inside hashtable literals; explicit `if` blocks only.
- `Set-StrictMode -Version Latest` retained at module scope.

---

## Resolved release-gate items

| Gate | Status | Resolution |
|---|---|---|
| `C-03` — Paging max-page guard | ✅ GREEN | `Invoke-PagingNextUri` now reads `paging.maxPages` (default 1000) and emits `paging.terminated.maxPages` when the ceiling is hit. Verified by `Paging.Tests.ps1`. |
| `F-03` — CI determinism assertion | ✅ GREEN | `RunContract.Tests.ps1` runs `Invoke-Dataset` twice over the same fixture invoker and asserts byte-equivalent `summary.json` (after stripping `runId` and ISO-8601 timestamps) and SHA-256-equal `data/*.jsonl`. |

---

## Out of scope

Live-validation gates `H-01` through `H-08` (live-org verification of the seven
Agent Investigation datasets) remain blocked on credentials and are not
addressed by this refactor.
