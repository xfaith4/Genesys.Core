# Conversation population performance: local evidence

These are single-run synthetic measurements on the local development machine, not tenant
or production capacity guarantees. The app checks used native Windows Node 24; the
standalone engine benchmark used v20.20.2. Browser checks used Chromium under WSL.

## Engine measurements

The 50k/100k fixtures have 15 top-level profile fields, four timeline segments per
conversation, one session, 10k distinct agents and multi-queue membership.

| Operation | 50k before | 50k after | 100k after |
| --- | ---: | ---: | ---: |
| First text search | 398.88 ms | 446.23 ms | 946.16 ms |
| Repeat text search | 282.04 ms | 17.05 ms | 35.56 ms |
| Numeric filter | 77.46 ms | 77.06 ms | 142.47 ms |
| Full grouped statistics | 164.61 ms | 170.16 ms | 303.58 ms |
| Error distribution | 37.17 ms | 36.7 ms | 57.95 ms |

Heap used after the 50k run: 99 MiB before, 108 MiB after; 100k: 193 MiB.
The search index trades memory for repeated-query speed. First search still builds it.
Streaming group accumulators remove member arrays; timings do not establish a significant
grouping speed improvement.

## Browser measurements

A 41 MiB, 50k-conversation analysis imported into the Data Client, with 10k agent groups:

| Interaction | Observed |
| --- | ---: |
| Import to visible population | 1101 ms |
| Group change | 123 ms |
| First search | 353 ms |
| Repeat search | 247 ms |
| Numeric filter | 131 ms |
| Skin restore | 4611 ms |
| Warm render inside frame | 61 ms |

Interaction wall times include Playwright and the 160 ms search debounce.
The table rendered 50 rows; groups initially rendered 100 of 10k, then 200 after show-more.
Filtering handle >100 retained 7,904 conversations, average 110 seconds, maximum 119.
Downloaded JSON independently contained all 7,904 records and 4,750 complete group results.
Initial skin restore was 6,421 ms; avoiding a duplicate population transfer/default-view
render reduced the measured run to 4,611 ms. Restore still needs improvement for large bundles.

A separate standalone browser check loaded 20k fully normalized, 99-field Ops profiles
(59.8 MiB, repeated from 1,000 synthetic conversations with unique IDs) in 831 ms.
It preserved average handle 500.5/max 1,000, both Division groups and 4,000 matching users.
This fixture predates the added optional packet/current-membership fields; missing optional
fields are supported. It is richer than the 15-field scale fixture, but remains synthetic.

## Ops profiling and export

A 1,000-conversation synthetic collection, profiling, labels and artifact export completed
in 14,029 ms after serialization reuse (earlier observed run 24,453 ms).
No network was involved. This is not a forecast for tenant extraction throughput.

| Phase | Observed |
| --- | ---: |
| collectionMs | 492 ms |
| profilingMs | 7,408 ms |
| entityResolutionMs | 1,956 ms |
| statisticsMs | 337 ms |

Wall time also includes module startup, JSON serialization and disk writes. The report
stores phase timings separately; it does not mislabel their sum as full elapsed time.

## Remaining limits

- Files are still parsed in memory. Large imports and initial search can block the UI.
- Skin changes recreate the sandbox and clone its population; no indexed disk store or
  background worker has been delivered. Export serialization is also synchronous.
- Browser checks cover 50k compact profiles and 20k richer profiles, not 100k full Ops
  profiles. The 100k result is engine-only.
- Paging/job completeness, tenant permissions, directory size, API throttling and network
  collection time require separate live validation.
- Next scale gate: background indexing or indexed storage, repeated percentile measurements
  and realistic tenant artifacts before claiming a larger operating envelope.

Reproduce engine benchmarks with `scripts/Measure-ConversationPopulation.mjs`; generate
fully normalized fixtures with `scripts/New-DemoConversationAnalysis.ps1 -ConversationCount 1000`.
