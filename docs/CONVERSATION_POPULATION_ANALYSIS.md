# Conversation incident workbench

The workbench turns an interval-scoped population into interactive investigation evidence.
Core retrieves the records, Ops profiles them, and the frontend filters and summarizes
those profiles. It has no direct HTTP client, credentials, or browser-side API pagination.

## Run a scoped investigation

In a connected Ops session:

```powershell
Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1
# Connect-GenesysCloud using your existing authentication workflow.
Get-GenesysConversationAnalysis `
    -Since '2026-09-01T00:00:00-04:00' `
    -Until '2026-10-01T00:00:00-04:00' `
    -QueueId 'queue-guid' -UserId 'user-guid' -DivisionId 'division-guid' `
    -OutputRoot ./out -OpenReport
```

Each named filter is optional; values within a dimension are alternatives. Supplied
queue/user/media predicates are segment filters, and Division predicates are conversation
filters. Since and Until are offset-aware and converted to UTC; Until is exclusive.
Always supply explicit offsets to avoid relying on the shell's local timezone.

The thin app launcher exposes the same workflow:

```powershell
./apps/ConversationAnalysis/Start-Investigation.ps1 `
    -Since '2026-09-01T00:00:00Z' -Until '2026-10-01T00:00:00Z' `
    -UserId 'user-guid' -OpenReport
```

For an advanced analytics details query, pass `-QueryBody <hashtable>` to Ops, or
`-QueryFile ./query.json` to the launcher. The body must omit interval, which is always
set by Since/Until. Custom bodies cannot be combined with named filters; this prevents
silently dropped criteria. The browser's collection panel generates a command for
interval/queue/user/Division collection; it does not execute PowerShell or API requests.

Existing Core conversation JSONL can be imported without authentication:

```powershell
./apps/ConversationAnalysis/Start-Investigation.ps1 `
    -Since '2026-09-01T00:00:00Z' -Until '2026-10-01T00:00:00Z' `
    -InputJsonl './saved-run/data/analytics-conversation-details.jsonl' -OpenReport
```

Imported data is explicitly unverified for interval membership and collection completeness.

## Interactive workflow

1. Open the generated `report.html`, or load `analysis.json` in
   `apps/ConversationAnalysis/Investigation.html`.
2. Search profiles or add field conditions. Conditions combine with AND. Equals on an
   array tests exact membership; contains tests text. Numeric comparisons reject missing
   values. False and zero remain valid values.
3. Choose any numeric statistic field. Count, average, minimum, maximum, valid sample count
   and missing count recalculate over **all filtered conversations**, not the visible page.
4. Group by Division, queue, engaged agent, any user (including alert-only), error code,
   direction, media, flow, disconnect, or wrap-up. Select a group or error code to filter.
5. Select a conversation ID to inspect the segment timeline, error events and session facts.
6. Export all filtered profiles to JSON, or all filtered rows in the selected columns to CSV.

JSON preserves original collection coverage, scope, definitions, current filters, grouping,
selected metric, derived statistics and population size. Reopening a filtered export labels
it as a saved selection; the file does not contain excluded conversations. CSV is a flat
selected-column extract; use its companion JSON for provenance. Spreadsheet formula-like
strings are escaped. Customer names/phone numbers and wrap-up notes are omitted from public profiles;
Core's source artifacts retain their own configured redaction contract.

## Field families and definitions

The Ops implementation adapts the supplied `Get-ConversationProfile` from
`F:/Development/20_Staging/GenesysCloud/ConversationAnalyser/src/analysis/ConversationAnalysis.ps1`
(inspected 2026-10-11). That checkout is a reference, not a runtime dependency.

| Family | Examples |
| --- | --- |
| Identity and scope | ConversationId, StartUtc, EndUtc, DurationSec, Direction, MediaTypes, DivisionIds |
| Routing and ownership | chronological QueueIds, engaged AgentKeys, all UserIds, skills, languages, requested/used routing |
| Outcome and timing | offered/answered/abandoned observations, holds, transfers, talk, handle, ACW, queue/IVR/flow times |
| Voice quality | MinMos, ConversationMinMos, EndpointMinMos, MinRFactor, MaxLatencyMs, Codecs |
| Failure evidence | every ErrorEvent, ErrorCodes, HasErrorCodeProperty, ErrorSegmentCount, SIP and Q850 codes |
| Flow and wrap-up | FlowNames/type/entry/exit, outcomes/failures, final wrap-up and terminal disconnect |
| Quality links | evaluation/survey/resolution counts and available scores |
| Detail | normalized chronological Timeline and per-agent/ACD session metric facts |

Statistics use one non-null value per distinct conversation. A missing numeric metric is
null, not zero. Seconds columns convert milliseconds; MaxLatencyMs and raw session Metrics
retain milliseconds. Outcome flags describe observed emissions/segments; absence of a flag's
supporting evidence is not independent proof of the business outcome. SelfServedSource labels
platform flags versus the reference's flow-only heuristic.

`MinMos` prefers the conversation summary and falls back to endpoint minimum.
`EndpointMinMos` specifically finds the lowest `mediaEndpointStats[].minMos` across sessions;
select it for average literal endpoint-minimum MOS by Division. Numeric precision is retained
until formatting. Engaged-agent paths exclude alert-only agents; UserIds includes them.
Unknown segment times sort after known timeline times and cannot outrank a known terminal
disconnect. TransferCount follows the reference's maximum of transfer-family sums, with
individual components exposed; it is not the sum of all transfer-related metrics.

Group membership is many-to-many: a conversation can enter multiple queues or Divisions,
so group counts are not additive. Error distribution counts both distinct affected
conversations per code and all segment occurrences, across all participants and media.
Empty errorCode properties are discoverable with HasErrorCodeProperty, but do not create
non-empty error occurrences.

## Evidence and validation boundaries

Each unique run includes analysis.json, report.html, summary.json, manifest.json, events.jsonl,
normalized data/profiles.jsonl and retained Core artifacts for online collection. Duplicate IDs
retain the first returned record and are disclosed; missing IDs are excluded with partial
coverage. Paging safety termination is partial. Failed jobs do not generate a successful
analysis report. Successful retrieval means the requested extraction completed, not that
permissions, indexing availability or real-tenant filter semantics are independently proven.

The demo is deliberately synthetic:

```powershell
./scripts/New-DemoConversationAnalysis.ps1
```

It contains 120 conversations: average handle time 60.5 seconds, maximum 120; filtering
handle >100 seconds leaves 20 conversations averaging 110.5. Thirty conversations carry
60 occurrences of one error code. This exercises full-population statistics and paging;
it is not tenant evidence or a performance certification for very large datasets.

This slice does not replace the Windows case store or the existing raw-JSONL viewer.
Entity-name lookup and measured population optimizations are implemented below.
Background indexing, automated cross-source incident correlation and live acceptance remain open.

## Open in the Data Client

Select **Conversation investigation** in either skin, or open `#/investigation` after
signing in. Use **Open Ops analysis JSON** to load the generated `analysis.json`.
The embedded workbench uses the same frontend as the standalone report; it does not
recompute profiles or retrieve conversations directly from Genesys.

The loaded population, filters, search, metric, grouping, sort, page and selected columns
remain in memory while navigating between pages or switching skins. Reloading or closing
the tab clears that state; export JSON before leaving to retain the investigation.
The collection panel generates a PowerShell command to run in your connected Ops session.
There is no browser-to-PowerShell service in this slice. Enable `-ResolveEntityNames` to collect directory labels through Core/Ops.



Local validation recorded on 2026-10-12: 52 focused Ops/Core tests and eight engine
tests passed. The full Core unit run had 233 passes, one skip and one existing failure
because five shipped golden-path HTML pages are absent from the accessibility surface
manifest (the HTML files themselves exist). These are local results, not a full green gate.

Data Client integration validation: 79 client tests, typechecking and production build passed;
the extended rendered accessibility gate audited 21 surfaces with zero violations.
Browser validation also covered retained pagination/columns, invalid imports, timeline
drilldown, filtered exports and 390px layout. These use synthetic artifacts.

## Entity names

Pass `-ResolveEntityNames` to `Get-GenesysConversationAnalysis` or the thin launcher,
including when generating a command in the collection panel. The extra directory datasets
run through Core once per referenced family: queues, users, Divisions, wrap-up codes,
routing skills and languages. They page the accessible directory, then retain only
referenced ID/name pairs in the analysis lookup. Redacted Core directory artifacts are
retained as lookup evidence; they can contain other accessible directory records.

IDs remain unchanged and authoritative. The table, timeline and group labels show
`name [id]`, and profiles add QueueNames, AgentNames, UserNames, DivisionNames, SkillNames,
LanguageNames and WrapUpName. Group selection filters on the ID, so two queues with the
same name remain distinct. Name fields can be filtered directly when desired.
Missing names fall back to the ID. Conflicting names for one ID remain unresolved.

`entityResolution.coverage` records status, dataset, requested/resolved counts, unresolved
IDs and evidence path for each family. Failed, denied or partial lookups do not invalidate
successful conversation collection. Check both kinds of coverage. Names are current
at lookup time, not historical names for the conversation month. Offline and synthetic
collections require an explicit EntityLookupInvoker to supply name evidence; they never
silently contact a tenant.

For online name resolution, Ops requests Core's catalog-defined identity redaction policy
that retains userId join identifiers. Core's normal dataset redaction remains the default;
contact fields and credentials are still redacted under the investigation policy.
Customer names, phone numbers and wrap-up notes remain omitted from public profiles;
requested directory user display names are included.

## Population scale

Search uses a lazy, per-population text index and a 160 ms debounce. Export flushes pending
search first so records and query provenance agree. Initial group/error tables show up to
100 rows with explicit totals and show-more controls. Conversation pages still contain
50 rows. Statistics and JSON exports cover every filtered conversation and every group,
regardless of the number of rows displayed. Group aggregation keeps running accumulators
rather than arrays of conversation references. The search cache assumes loaded profiles
are immutable; validating a new bundle clears it.

Run the reproducible engine benchmark from the repository root:

```bash
node scripts/Measure-ConversationPopulation.mjs 50000 result.json analysis.json
node scripts/Measure-ConversationPopulation.mjs 100000 result-100k.json
```

The optional fourth argument writes a synthetic analysis for browser import. The demo
script also accepts `-ConversationCount 1000` for a full Ops profiling/export exercise.
Its default remains 120. Ops reports collectionMs, profilingMs, entityResolutionMs and
statisticsMs in `performance`; these exclude artifact serialization/write time.

See [measured scale results and boundaries](CONVERSATION_POPULATION_PERFORMANCE.md).


## Operational evidence foundations

Profiles now retain FlowIds and sanitized EndpointStats observations with session/user,
event time, discarded/received/duplicate/invalid/overrun/underrun packet fields.
AvgDiscardedPackets is the mean of valid endpoint-stat observations within a conversation;
population averages then use one such value per conversation. MaxDiscardedPackets and
DiscardedPacketSamples preserve the maximum and denominator. Observations can overlap;
these values are not network-loss percentages or unique-packet totals. Overrun/underrun
are components of discarded and must not be added again. Packet field semantics follow the
[Genesys SDK model](https://github.com/MyPureCloud/platform-client-sdk-dotnet/blob/master/build/docs/AnalyticsMediaEndpointStat.md).

Name resolution also retains current user directory Division membership as UserDivisionIds,
AgentDivisionIds and corresponding name arrays. These remain separate from DivisionIds
reported on the conversation. Missing membership has its own coverage. Directory membership
is current at lookup time; it does not prove a user's Division during a historical incident.
See the [NOC investigation contract](NOC_INCIDENT_INVESTIGATIONS.md) for composed analysis
and acceptance work still required.
