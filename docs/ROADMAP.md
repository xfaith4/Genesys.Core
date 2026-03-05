# Genesys Core — Roadmap

## Vision

Build a catalog-driven Genesys Cloud Core that executes governed datasets via GitHub Actions and produces deterministic, auditable artifacts. UIs consume Core artifacts and must not reimplement Core pagination/retry/runtime logic.

## Status snapshot (2026-02-22)

- **Implemented now**
  - Catalog + schema validation and profile resolution.
  - Runtime dataset dispatcher (`Invoke-Dataset`) with deterministic output contract.
  - Retry engine with bounded jitter and 429 handling (`Retry-After` + message parsing).
  - Paging strategy plugins: `none`, `nextUri`, `pageNumber`, `cursor`, `bodyPaging`, `transactionResults`.
  - Generic async job engine (`Submit-AsyncJob`, `Get-AsyncJobStatus`, `Get-AsyncJobResults`, `Invoke-AsyncJob`).
  - Curated dataset handlers: `audit-logs`, `analytics-conversation-details`, `users`, `routing-queues`.
  - Generic catalog-driven dataset execution for additional dataset keys.
  - Test coverage for catalog validation, retry, paging, async flows, redaction, run contract, and standalone bootstrap.
  - CI + audit-specific scheduled/on-demand workflow scaffolding.
- **In progress**
  - Catalog mirror retirement and full cutover to `catalog/genesys.catalog.json`.
  - End-user workflow auth ergonomics for production-ready automation.
- **Recently hardened**
  - Expanded payload redaction to scrub embedded bearer/basic tokens, JWT-like values, and tokenized query fragments in string fields.

## Phase 0 — Bootstrap (Complete)

### Delivered

- Catalog placeholder at `catalog/genesys.catalog.json`
- Draft schema at `catalog/schema/genesys.catalog.schema.json`
- PowerShell module scaffold under `modules/Genesys.Core/`
- Pester scaffolding under `tests/`
- CI workflow to run Pester on pull requests
- Scheduled/on-demand audit logs workflows that write deterministic output files under `out/<datasetKey>/<runId>/...`

## Phase 1 — Core Runtime Foundations (Complete)

- Request/retry runtime with deterministic 429 behavior and bounded jitter.
- Pluggable paging strategies (`none`, `nextUri`, `pageNumber`, `cursor`, `bodyPaging`, `transactionResults`).
- Structured run events for retries, paging progress, and async state transitions.
- Request event redaction for sensitive headers and token-like query parameters.

## Phase 2 — Core Datasets (Complete)

- Implemented curated datasets:
  - `audit-logs`
  - `analytics-conversation-details`
  - `users`
  - `routing-queues`
- Generic catalog-backed execution is available for additional dataset keys defined in the catalog.

### Completed hardening

- Added runtime dataset parameter overrides (`-DatasetParameters`) for curated interval controls and generic endpoint query overrides.
- Added tests validating parameterized audit interval/action/service filters and generic query override behavior.
- Expanded redaction hardening to cover embedded token patterns in payload strings.

### Future enhancements

- Expand curated handlers where domain-specific normalization or orchestration is required.
- Continue redaction policy evolution (profile-driven controls and allow/deny field tuning).

## Phase 3 — Catalog and Delivery Hardening (Complete)

- Day-to-day runtime and tests now target canonical `catalog/genesys.catalog.json` usage.
- Improved onboarding ergonomics with script-level invocation support for `-BaseUri`, `-Headers`, and `-DatasetParameters`.
- Hardened auth/runtime usage guidance to favor deterministic, redacted outputs.

## Phase 4 — Endpoint Expansion Backlog (In Progress)

Tracked endpoint additions for roadmap delivery:

1. `GET /api/v2/authorization/roles`
2. `GET /api/v2/conversations/{conversationId}/recordings`
3. `GET /api/v2/oauth/clients`
4. `POST /api/v2/oauth/clients/{clientId}/usage/query`
5. `GET /api/v2/oauth/clients/{clientId}/usage/query/results/{executionId}`
6. `GET /api/v2/speechandtextanalytics/topics`
7. `POST /api/v2/analytics/transcripts/aggregates/query`
8. `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/communications/{communicationId}/transcripturl`

Delivered in this phase increment:

- Added catalog endpoint and dataset definitions for all tracked Phase 4 endpoints.
- Added Phase 4 Pester coverage to assert dataset/endpoint wiring and profile resolution.

Remaining implementation tasks:

- Validate each Phase 4 endpoint against live API behavior to confirm `itemsPath` and paging strategy choices.
- Add curated handler(s) for OAuth usage submit/results orchestration if async transaction chaining is required in production.
- Add mock-based paging termination tests for newly introduced `pageNumber_default` and `nextUri_default` endpoint selections.

## External client readiness

The repository is ready for controlled external invocation of module command `Invoke-Dataset` when callers provide valid auth headers and consume output artifacts from `out/<datasetKey>/<runId>/`.

Before broad production automation, complete:

- workflow auth wiring and examples
- mirror-catalog consolidation
- redaction/profile hardening


## Phase 5 — Visibility Dashboard Core  (In Progress)

### Vision

Expand Genesys.Core into a fine-tuned set of targeted API endpoints and Ops-layer
functions that allow wrapper UI applications to build monitoring and analytics
dashboards **without** having to worry about which APIs tie to which services,
pagination, timeouts, or retry logic.

### 30 New Dashboard Ideas

The following 30 ideas map directly to new catalog endpoints, datasets, and
`Genesys.Ops` functions.  Each idea has a one-line summary, the Ops cmdlet(s)
that implement it, and the backing catalog key(s).

---

#### Idea 1 — Edge Health Monitor
**Goal:** Real-time visibility into Edge appliance registration and online status across all sites.
**Cmdlet:** `Get-GenesysEdge`
**Catalog endpoint:** `telephony.get.edges`
**Status:** ✅ Delivered

---

#### Idea 2 — Trunk Capacity Dashboard
**Goal:** Monitor SIP trunk utilisation and headroom to prevent capacity-related call failures.
**Cmdlets:** `Get-GenesysTrunk`, `Get-GenesysTrunkMetrics`
**Catalog endpoints:** `telephony.get.trunks`, `telephony.get.trunk.metrics.summary`
**Status:** ✅ Delivered

---

#### Idea 3 — Edge + Trunk Infrastructure Snapshot
**Goal:** Single at-a-glance widget combining edge online state and trunk health — feeds alerting pipelines.
**Cmdlet:** `Get-GenesysEdgeHealthSnapshot`
**Backing cmdlets:** `Get-GenesysEdge`, `Get-GenesysTrunk`
**Status:** ✅ Delivered

---

#### Idea 4 — Station Status Inventory
**Goal:** Understand how many softphones/hardphones are active, ringing, or idle at any moment.
**Cmdlet:** `Get-GenesysStation`
**Catalog endpoint:** `stations.get.stations`
**Status:** ✅ Delivered

---

#### Idea 5 — Edge Alarms & Event Feed *(Future)*
**Goal:** Surface Edge system events and error logs in real-time for NOC dashboards.
**Catalog endpoint:** `GET /api/v2/telephony/providers/edges/{edgeId}/logs` *(to be added)*
**Status:** 🔲 Planned

---

#### Idea 6 — Queue Abandon Rate Dashboard
**Goal:** Per-queue abandon rate (%) with real-time waiting counts — the #1 contact centre KPI.
**Cmdlets:** `Get-GenesysQueueAbandonRate`, `Get-GenesysAbandonRateDashboard`
**Catalog endpoint:** `analytics.query.conversation.aggregates.abandon.metrics`
**Status:** ✅ Delivered

---

#### Idea 7 — Queue Service Level (SLA) Compliance
**Goal:** Track % of contacts answered within 20/30/60 seconds per queue — compare against SLA targets.
**Cmdlet:** `Get-GenesysQueueServiceLevel`
**Catalog endpoint:** `analytics.query.queue.aggregates.service.level`
**Status:** ✅ Delivered

---

#### Idea 8 — Multi-Queue Health Snapshot
**Goal:** Colour-coded (GREEN/AMBER/RED) queue health combining real-time observations + SLA data.
**Cmdlet:** `Get-GenesysQueueHealthSnapshot`
**Backing cmdlets:** `Get-GenesysQueueObservation`, `Get-GenesysQueueServiceLevel`
**Status:** ✅ Delivered

---

#### Idea 9 — Transfer Analysis (Blind vs Consult)
**Goal:** Identify queues with high blind transfer rates — signals training gaps or routing issues.
**Cmdlet:** `Get-GenesysTransferAnalysis`
**Catalog endpoint:** `analytics.query.conversation.aggregates.transfer.metrics`
**Status:** ✅ Delivered

---

#### Idea 10 — Wrapup Code Distribution
**Goal:** Understand outcome/disposition patterns per queue — drives process and compliance review.
**Cmdlet:** `Get-GenesysWrapupDistribution`
**Catalog endpoint:** `analytics.query.conversation.aggregates.wrapup.distribution`
**Status:** ✅ Delivered

---

#### Idea 11 — Digital Channel Volume Trending
**Goal:** Compare voice vs chat vs email vs messaging volumes over time — informs channel strategy.
**Cmdlet:** `Get-GenesysDigitalChannelVolume`
**Catalog endpoint:** `analytics.query.conversation.aggregates.digital.channels`
**Status:** ✅ Delivered

---

#### Idea 12 — CSAT / NPS Survey Trending
**Goal:** Track post-call survey scores (NPS, CSAT) by queue and agent over time.
**Cmdlet:** `Get-GenesysSurvey`
**Catalog endpoint:** `quality.get.surveys`
**Status:** ✅ Delivered

---

#### Idea 13 — Quality Evaluation Scores
**Goal:** Supervisor-scored evaluation trends per agent — coaching priority identification.
**Cmdlet:** `Get-GenesysEvaluation`
**Catalog endpoint:** `quality.get.evaluations.query`
**Status:** ✅ Delivered

---

#### Idea 14 — Sentiment Trending
**Goal:** Speech analytics sentiment scores trending by queue/agent — early warning for customer frustration.
**Cmdlet:** `Get-GenesysSentimentTrend`
**Backing dataset:** `analytics-conversation-details` (sentimentScore field)
**Status:** ✅ Delivered

---

#### Idea 15 — Agent Quality Snapshot
**Goal:** Per-agent KPI leaderboard: handle time, ACW, talk time — ready for coaching or reporting.
**Cmdlet:** `Get-GenesysAgentQualitySnapshot`
**Backing cmdlet:** `Get-GenesysAgentPerformance`
**Status:** ✅ Delivered

---

#### Idea 16 — Alerting Rules Inventory
**Goal:** Audit which KPI thresholds are monitored, which rules are disabled, and which are in alarm.
**Cmdlet:** `Get-GenesysAlertingRule`
**Catalog endpoint:** `alerting.get.rules`
**Status:** ✅ Delivered

---

#### Idea 17 — Active Platform Alerts Feed
**Goal:** Real-time feed of active threshold breaches — feeds NOC/ops ChatOps bots.
**Cmdlet:** `Get-GenesysAlert`
**Catalog endpoint:** `alerting.get.alerts`
**Status:** ✅ Delivered

---

#### Idea 18 — Agent Login & Occupancy Analysis
**Goal:** Track on-queue vs off-queue vs idle time per agent — staffing adherence proxy.
**Cmdlet:** `Get-GenesysAgentLoginActivity`
**Catalog endpoint:** `analytics.query.user.aggregates.login.activity`
**Status:** ✅ Delivered

---

#### Idea 19 — ACW Anomaly Detection
**Goal:** Flag agents whose after-call work time is statistically far above the organisation average.
**Cmdlet:** `Get-GenesysAgentAcwAnomaly`
**Backing cmdlet:** `Get-GenesysAgentPerformance`
**Status:** ✅ Delivered

---

#### Idea 20 — Long Handle Time Investigation
**Goal:** Identify conversations exceeding a handle-time threshold — supervisor escalation queue.
**Cmdlet:** `Get-GenesysLongHandleConversation`
**Backing dataset:** `analytics-conversation-details`
**Status:** ✅ Delivered

---

#### Idea 21 — Repeat Caller / FCR Proxy
**Goal:** Detect customers contacting more than once in a window — proxy for First Contact Resolution failure.
**Cmdlet:** `Get-GenesysRepeatCaller`
**Backing dataset:** `analytics-conversation-details`
**Status:** ✅ Delivered

---

#### Idea 22 — WebRTC Disconnect Heatmap
**Goal:** Hourly trend of WebRTC error codes (ICE, STUN, TURN, RTP) — isolates network/firewall issues.
**Cmdlet:** `Get-GenesysWebRtcDisconnectSummary`
**Backing cmdlet:** `Get-GenesysAgentVoiceQuality`
**Status:** ✅ Delivered

---

#### Idea 23 — Conversation Latency Trending
**Goal:** Track hourly avg handle, talk, ACW, and speed-of-answer per queue — detect latency spikes.
**Cmdlet:** `Get-GenesysConversationLatencyTrend`
**Backing cmdlet:** `Get-GenesysQueuePerformance`
**Status:** ✅ Delivered

---

#### Idea 24 — WFM Management Unit Visibility
**Goal:** Understand workforce management unit structure — supports scheduling and adherence dashboards.
**Cmdlet:** `Get-GenesysWorkforceManagementUnit`
**Catalog endpoint:** `workforce.get.management.units`
**Status:** ✅ Delivered

---

#### Idea 25 — Journey Action Map Inventory
**Goal:** Track active predictive engagement triggers (web chat offers, callbacks) — digital CX visibility.
**Cmdlet:** `Get-GenesysJourneyActionMap`
**Catalog endpoint:** `journey.get.action.maps`
**Status:** ✅ Delivered

---

#### Idea 26 — Enhanced Operations Report
**Goal:** Single composite report covering abandon rates, SLA, edge health, alerts, and WebRTC issues.
**Cmdlet:** `Invoke-GenesysOperationsReport`
**Backing cmdlets:** All new KPI cmdlets above
**Status:** ✅ Delivered

---

#### Idea 27 — Peak Hour Load Analysis *(Future)*
**Goal:** Identify staffing gaps vs offered volume by 15-minute interval — feeds WFM scheduling.
**Planned extension:** `analytics.query.conversation.aggregates.queue.performance` with PT15M granularity
**Status:** 🔲 Planned — use `Get-GenesysConversationLatencyTrend` with custom catalog body override

---

#### Idea 28 — Configuration Change Audit Feed *(Future)*
**Goal:** Near-real-time feed of admin changes (queue, flow, user) via audit logs — change governance.
**Planned extension:** Combine `Get-GenesysAuditEvent` with webhook/notification push
**Status:** 🔲 Planned — `Get-GenesysAuditEvent` already available; notification push layer to come

---

#### Idea 29 — Outbound Campaign Performance Dashboard *(Future)*
**Goal:** Dial rate, contact rate, abandon rate, pacing mode for outbound campaigns.
**Existing cmdlets:** `Get-GenesysOutboundCampaign`, `Get-GenesysOutboundEvent`
**Status:** 🔲 Planned — requires analytics aggregates for outbound-specific metrics

---

#### Idea 30 — Flow Outcome KPI Correlation *(Future)*
**Goal:** Correlate IVR flow outcomes with CSAT scores and handle time — identify self-service drop-off.
**Existing cmdlets:** `Get-GenesysFlowAggregate`, `Get-GenesysFlowObservation`, `Get-GenesysSurvey`
**Status:** 🔲 Planned — correlation layer requires join logic across flow and conversation datasets

---

### Phase 5 Summary

| Category                        | Ideas | New Catalog Endpoints | New Ops Cmdlets |
|---------------------------------|-------|-----------------------|-----------------|
| Edge / Telephony Telemetry      | 1–5   | 4                     | 5               |
| Queue KPIs                      | 6–11  | 5                     | 5               |
| Quality & CSAT                  | 12–15 | 2                     | 3               |
| Alerting                        | 16–17 | 2                     | 2               |
| Agent Insights                  | 18–21 | 1                     | 4               |
| WebRTC & Latency                | 22–23 | —                     | 2               |
| WFM & Journey                   | 24–25 | 2                     | 2               |
| Composite Snapshots             | 26    | —                     | 4               |
| Planned (future phases)         | 27–30 | —                     | —               |
| **Total**                       | **30**| **16**                | **27**          |

