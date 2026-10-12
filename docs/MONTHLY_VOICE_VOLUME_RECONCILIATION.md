# Monthly voice volume reconciliation

Status: acceptance contract recorded; implementation and live validation pending.

## Purpose

Answer monthly voice-volume questions by cross-referencing four Genesys analytics
collection paths. Preserve differing results rather than choosing a winning endpoint
or treating disagreement as an application failure. Endpoint nuances must be observed
on a real platform; explanations remain hypotheses until supported by evidence.

## Sources

All paths below are prefixed with `/api/v2/`.

| Source | Collection | Result to retain |
| --- | --- | --- |
| Details query | `analytics/conversations/details/query` | Returned rows and distinct voice conversation IDs |
| Details jobs | `analytics/conversations/details/jobs`, status, and results | Returned rows and distinct voice conversation IDs |
| Aggregates query | `analytics/conversations/aggregates/query` | Each requested metric, statistic, group, and interval |
| Aggregates jobs | `analytics/conversations/aggregates/jobs`, status, and results | Each requested metric, statistic, group, and interval |

An aggregate metric is not implicitly a distinct-conversation count. Retain original
metric names and units; any derived volume needs an explicit, versioned definition.
Do not silently substitute offered, connected, or outbound counts for one another.

## Collection contract

- Record organization, region, reporting timezone, local month, UTC boundaries,
  effective filters, permissions failures, and collection timestamps for every source.
- Use the same intended scope across sources. Preserve each actual request body and
  disclose filters or time semantics that cannot be represented equivalently.
- Execute through Core and catalog profiles. Verify paging, async polling, and result
  paging against endpoint contracts before relying on existing profile declarations.
- If an interval requires splitting, record every partition and its status. Deduplicate
  detail conversation IDs across partitions; do not assume aggregate counts can be
  summed across partitions without verifying their attribution semantics.
- Keep source results independent. Do not populate a failed source from another source.
- Record completion, page counts, raw row counts, distinct counts where applicable,
  warnings, job IDs, and evidence references. Missing or partial results are not zero.

## Comparison output

Show all four sources side by side with their definitions and coverage. Display signed
absolute differences and percentage differences for explicitly selected comparisons.
Name the percentage baseline; if it is zero, percentage difference is unavailable.
Comparisons of unlike definitions remain visible but are labelled non-equivalent.

For the two detail sources, export IDs present only in each source, duplicate counts,
and links to conversation investigation. Aggregate-only results cannot establish which
specific conversations account for a difference.

Separate observed differences from possible explanations. Investigate request scope,
time attribution, data availability, permissions, retrieval completeness, and metric
grain without asserting any of them caused the difference without supporting evidence.
Retain collection time so later reruns can reveal changing results.

## Acceptance

- Synthetic equal-source scenario verifies presentation and calculation only.
- Synthetic divergent-source scenario verifies differences are retained and highlighted.
- Fixtures cover repeated IDs, partial paging, failed jobs, denied sources, absent metrics,
  zero baselines, non-equivalent definitions, and timezone/month boundaries.
- Real-tenant acceptance runs all four sources for the same reporting month, preserves
  requests and evidence, and records observed agreement or disagreement without forcing
  equality. Recollection is recorded as a separate run.
- Mock validation and live-platform validation are reported separately. Whether the
  existing mock produces equal totals must be measured, not assumed.

## Implemented command and report

`Compare-GenesysMonthlyVoiceVolume` is exported by `Genesys.Ops`. Core owns all HTTP
collection; Ops owns definitions, reconciliation, evidence assembly, and report output.
The app launcher delegates to Ops and can open its HTML report in a browser.

In an already authenticated session:

```powershell
Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1
# Connect-GenesysCloud using your existing authentication workflow first.
./apps/MonthlyMetrics/Compare-MonthlyVoiceVolume.ps1 `
    -Year 2026 -Month 9 -TimeZoneId 'America/New_York' `
    -OutputRoot ./out -OpenReport
```

Optional `-DivisionId`, `-QueueId`, and `-OrganizationId` record investigation scope.
OrganizationId is investigator-supplied context, not a verified identity check. Timezone
IDs depend on the host; Windows PowerShell 5.1 may require `Eastern Standard Time`.
Ambiguous or invalid month boundaries are rejected rather than guessed.

Each run creates a unique `monthly-voice-volume/<runId>` folder with `report.html`,
`summary.json`, `comparison.csv`, `manifest.json`, `events.jsonl`, request JSON, source
Core artifacts, and detail conversation-ID lists. The HTML highlights differing or
partial comparisons and lists observed ID set differences for further investigation
with `Get-GenesysConversationInvestigation`.

Aggregate totals currently expose `nOffered.count`, `nConnected.count`, and
`nOutbound.count` independently. Original metric statistics and returned groups and
intervals remain in JSON. Multiple returned series for a metric are retained but not
silently summed into a total. Missing metrics remain null. There is no automatic
partitioning/retry with narrower time windows: source limits or failures remain visible
as unavailable, and paging safety termination marks coverage partial. Monthly high-volume
limits and scope equivalence still require live acceptance.

Generate an offline demonstration, including intentionally different source totals:

```powershell
./scripts/New-DemoMonthlyVoiceVolume.ps1
# Open report.html under the returned runFolder.
```

The mock server now has synchronous and cursor-paged asynchronous aggregate fixtures.
Its existing detail fixtures return different populations (2 synchronous records and 5
async records), and the aggregate fixtures intentionally return different offered counts
(3 synchronous and 4 async). Fixtures are static: they do not implement tenant permissions,
real month filtering, or actual metric attribution. Their timestamps and totals cannot
be used as evidence for the requested month on a real platform.

The aggregate cursor contract was checked against the official Genesys SDK:
[Analytics API](https://github.com/MyPureCloud/platform-client-sdk-python/blob/master/build/PureCloudPlatformClientV2/apis/analytics_api.py)
and [aggregate response model](https://github.com/MyPureCloud/platform-client-sdk-python/blob/master/build/PureCloudPlatformClientV2/models/conversation_async_aggregate_query_response.py).

Data Client route integration, automatic interval partitioning, and live tenant
acceptance remain open. The standalone browser report is the first frontend for the
shared Ops function.
