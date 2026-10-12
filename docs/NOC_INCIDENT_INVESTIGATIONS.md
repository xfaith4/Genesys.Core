# Operations investigations: product and next implementation contract

The Data Client is the common operations frontend for Genesys.Core and Genesys.Ops,
bringing together the investigation purpose of OpsConsole, GenesysInterrogator and
ConversationAnalyzer. Its primary unit of value is an answered operational question
with linked evidence. Endpoint execution is supporting diagnostics.

## First priority: mass disconnects

The next composer is `Get-GenesysDisconnectInvestigation` in Ops, with a Data Client
incident workspace over its artifacts. This is a contract, not an implemented composer.

1. Collect the complete conversation population for an explicit UTC incident interval
   and queue/user/Division scope through Core. Select a cohort using supplied error codes
   or an explicit matching rule. Preserve every matching segment and conversation ID;
   do not hardcode a guessed universal WebRTC error list. Show cohort versus full-window
   denominators and occurrence versus distinct-conversation counts.
2. Join all related users (including alert-only agents), engaged agents, queues, flow IDs
   and conversation Divisions. Resolve names in bulk through Core. Keep current user
   directory Division membership separate from conversation Division IDs. Historical
   membership requires evidence valid at the incident time; unavailable evidence stays unknown.
3. Present time buckets, affected-entity breakdowns, representative timelines and quality
   evidence. Preserve endpoint observations and their event times. Explicitly define
   discarded/received packets, sample ownership and valid sample counts. Avoid adding
   overrun/underrun to discarded again. Discarded packets are not a measured network-loss rate.
4. Collect queue performance for the affected queues during incident and comparable
   baseline windows. Calculate hold/wait/answer/abandon differences using each metric's
   valid denominator. Distinguish queue wait from agent-held time. A change needs baseline
   coverage; incident-only averages do not prove an increase.
5. Collect historical user activity for affected users, extracting NOT_RESPONDING
   segments and aligning them to conversation alert/interact segments. Present overlap,
   timing and missing coverage. A current routing-state endpoint cannot prove historical
   state; conversation tNotResponding alone cannot replace routing-status history.
6. Query audit changes for affected users, queues and flow/configuration entities over a
   stated investigation window. Complete transaction submission, status polling and
   results paging. Show candidate changes alongside incident time; label correlation as
   hypothesis until supported by additional evidence.
7. Produce one evidence packet: manifest, scope, per-source status and permissions,
   events, normalized data, findings, all denominators, baseline definitions, collection
   time and drilldown links. Partial sources remain visible. Export the whole incident,
   not just the current table page.

Existing reusable sources include analytics-conversation-details, users, routing-queues,
authorization.get.all.divisions, analytics.query.conversation.aggregates.queue.performance,
analytics.query.user.details.activity.report and the audit transaction datasets. The
composer must use the catalog and existing Ops domain functions rather than introduce
browser-owned polling, retries, pagination or a second calculation implementation.

## Job and transaction completeness

Every supported asynchronous collection is one governed dataset capability:
submit -> bounded status polling -> terminal-state validation -> all result pages.
Status/result endpoints are implementation steps, not separate user tasks. A failed or
cancelled job cannot produce a successful empty dataset. Safety caps, repeated cursors,
permission failures and missing sources must remain explicit.

Inventory every catalog job/transaction family, including currently unbound submit
endpoints. Record its dataset, submit/status/results references, polling profile, paging
strategy and coverage tests. Mark an unmatched family unsupported; a raw endpoint runner
is not evidence that the complete family is supported. Current conversation details,
monthly aggregates and audit transaction implementations are foundations, not proof
that every catalog job family is already composed.

## Acceptance gates

- Synthetic WebRTC/error cohort with multiple agents/queues/flows, repeated errors,
  duplicate entity names and missing optional observations.
- Current and historical Division evidence explicitly distinguished.
- Incident/baseline queue metrics and user-state timelines with valid denominators;
  unrelated changes excluded or labeled weak association.
- Multi-page jobs and audit transactions, failed jobs, safety termination, partial
  permissions and unavailable sources retain correct status and provenance.
- Browser flow starts with incident scope, then impact and findings, with linked details
  and whole-packet export; large-population controls preserve full denominators.
- Real tenant execution and an operations-team pilot close platform and usability gates.

The existing population workbench now supplies cohorts, names, flow IDs, packet
observations, timelines and population statistics. Automated cross-source correlation,
baseline collection, job-family coverage inventory and live NOC monitoring remain open.

Packet field meanings were verified against the
[Genesys SDK AnalyticsMediaEndpointStat model](https://github.com/MyPureCloud/platform-client-sdk-dotnet/blob/master/build/docs/AnalyticsMediaEndpointStat.md).
