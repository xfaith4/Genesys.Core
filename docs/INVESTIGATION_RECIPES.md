# Investigation Recipes

> Status: Reference document — endpoint combination patterns for contact-centre
> investigations and executive reporting.
>
> Last updated: 2026-05-06
>
> See also: [INVESTIGATIONS.md](INVESTIGATIONS.md) for the composer contract
> and dataset step tables. This document focuses on *why* endpoints are combined
> the way they are, and what each combination reveals.

---

## 1. Purpose

The Genesys Cloud API surface has over 3,100 endpoints. Used individually each
answers a narrow question. Combined purposefully they answer operational
questions that no single endpoint can: "Why did that call fail?", "Is this queue
healthy right now?", "Is this agent performing within expectations?", "What is
driving our abandon rate this week?"

This document captures high-value endpoint combinations for three audiences:

| Audience | Section |
| --- | --- |
| **Voice engineers** diagnosing individual call failures | § 2 |
| **Contact-centre supervisors** investigating queue health or agent performance | § 3 |
| **Executives / analysts** building rollup metrics and trend reports | § 4 |
| **Compliance / access reviewers** auditing divisions and roles | § 5 |

Each recipe names the datasets in join order, explains what each step adds, and
identifies the join key that stitches the result set together. All dataset keys
are registered in `catalog/genesys.catalog.json`.

---

## 2. Single Conversation Investigation (Voice Engineer)

**Trigger:** A customer complains about a dropped call, one-way audio, or failed
transfer. A supervisor escalates a specific conversation ID for root-cause.

**Subject:** `conversationId`

### 2.1 Minimal path (fast triage — 3 datasets)

| Order | Dataset | Join key | What it adds |
| --- | --- | --- | --- |
| 1 | `analytics.get.single.conversation.analytics` | seed | Segment timeline: who was on the call, when, how long. Immediately shows if call was connected, how many transfers occurred, and where time was spent. |
| 2 | `telephony.get.sip.message.for.conversation` | `conversationId` | SIP INVITE→180→200→BYE sequence with timestamps. Confirms call setup outcome, identifies carrier-side failures, and pinpoints where audio negotiation failed. |
| 3 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording inventory without downloading media. Confirms whether audio was captured before investing time in playback or transcript review. |

> **Voice engineer decision point:** If SIP trace shows a complete 200 OK and
> recording metadata shows a file, the problem is likely media/codec not SIP.
> If SIP trace shows 4xx/5xx or no 200, the failure is call setup. If recording
> metadata is empty on a connected call, check trunk and edge configuration.

### 2.2 Full investigation path (complete picture — 14 datasets)

| Order | Dataset | Join key | What it adds |
| --- | --- | --- | --- |
| 1 | `analytics-conversation-details` | seed | Full participant timeline with all segments and per-segment metrics (tTalk, tAcw, tHandle). The authoritative source for conversation structure. |
| 2 | `conversations.get.specific.conversation.details` | `conversationId` | Conversation API state: direction (inbound/outbound), media type, connected and disconnected timestamps, participant wrapup state. |
| 3 | `telephony.get.sip.message.for.conversation` | `conversationId` | SIP trace — INVITE, provisional responses, 200 OK, re-INVITEs, BYE. Essential for diagnosing setup failures, one-way audio, and early disconnects. |
| 4 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording inventory: file IDs, duration, archive status. Lightweight — no media download required. |
| 5 | `conversations.get.recordings` | `conversationId` | Full recording list with media references and annotation data. Use when transcript or playback review is needed. |
| 6 | `conversations.get.conversation.summaries` | `conversationId` | Genesys AI summary: reason for call, resolution status, follow-up actions. Provides conversation context without reading the transcript. |
| 7 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Detected topic categories (billing, complaint, cancellation, escalation). Identifies whether this conversation matches a known issue pattern. |
| 8 | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | NLP-derived resolution and sentiment from transcript. Richer than the AI summary when speech analytics is licensed. |
| 9 | `speechandtextanalytics.get.conversation.transcript.urls` | `communicationId` | Pre-signed S3 transcript URLs per communication leg. Enables transcript download without storing credentials in artifacts. |
| 10 | `quality.get.evaluations.query` | `conversationId` | Quality evaluation scores, evaluator, and calibration status. Confirms whether the conversation was reviewed and at what quality level. |
| 11 | `quality.get.conversation.surveys` | `conversationId` | Post-call CSAT/NPS survey response from the customer. Closes the loop: did the customer experience match the agent's documented resolution? |
| 12 | `users` (per participant userId) | `userId` | Identity for each agent participant: name, email, division, manager. |
| 13 | `users.division.analysis.get.users.with.division.info` | `userId` | Division and location for each agent at time of investigation. |
| 14 | `routing.get.all.routing.skills` (filtered) | `userId` | Skills held by each agent participant at time of investigation. |

### 2.3 Key joins in this investigation

```
analytics-conversation-details
  └── participantData[].userId
        ├── users                                      (identity)
        ├── users.division.analysis.*                  (division)
        └── routing.get.all.routing.skills             (skills)
  └── conversationId
        ├── conversations.get.specific.conversation.details
        ├── telephony.get.sip.message.for.conversation
        ├── conversations.get.conversation.recording.metadata
        ├── conversations.get.recordings
        ├── conversations.get.conversation.summaries
        ├── speechandtextanalytics.get.conversation.categories
        ├── speechandtextanalytics.get.conversation.summaries.detail
        ├── quality.get.evaluations.query
        └── quality.get.conversation.surveys
  └── communicationId (per leg)
        └── speechandtextanalytics.get.conversation.transcript.urls
```

### 2.4 What each combination reveals

| Question | Datasets to combine |
| --- | --- |
| Did the call connect at all? | SIP trace + analytics segment timeline |
| Was audio captured? | Recording metadata |
| What was the call about? | AI summary + speech categories |
| Was the resolution correct? | NLP summary + evaluation scores + survey |
| Which agent handled it and are they skilled for it? | Users + skills |
| Was it a one-way audio issue? | SIP trace (look for re-INVITEs) + recording file size |
| Was there a transfer problem? | Analytics segments (nTransferred > 1) + SIP trace |
| Did the customer provide feedback? | Survey response |

---

## 3. Supervisor Investigations

### 3.1 Agent performance investigation

**Trigger:** A supervisor is reviewing an agent's performance for a coaching
session, a formal review, or an escalation investigation.

**Subject:** `userId` (resolved from agent name by the Ops cmdlet wrapper)

#### Phase 1 — Identity and configuration

| Dataset | What it adds |
| --- | --- |
| `users.get.user.details.with.full.expansion` | Full profile: department, manager chain, primary station, authorization groups |
| `users.division.analysis.get.users.with.division.info` | Division assignment — the authorization boundary this agent operates within |
| `users.get.user.s.queue.memberships` | Every queue the agent is currently joined to, with join state |
| `routing.get.all.routing.skills` (filtered) | Skills and proficiency levels — what the agent is certified to handle |
| `routing.get.user.utilization` | Max concurrent channel capacity — how many simultaneous interactions the agent can handle per channel |

#### Phase 2 — Availability and productivity

| Dataset | Join key | What it adds |
| --- | --- | --- |
| `users.get.user.routing.status` | `userId` | Current routing status at investigation time (Idle, Interacting, Off Queue) |
| `users.get.bulk.user.presences` | `userId` | Presence timeline in the review window |
| `analytics.query.user.details.activity.report` | `userId` | Login/logout events, on-queue time, and routing state transitions |
| `analytics.query.user.aggregates.login.activity` | `userId` | tOnQueueTime, tOffQueueTime, tIdleTime — total time in each state |
| `analytics.query.user.aggregates.performance.metrics` | `userId` | nConnected, tHandle, tTalk, tAcw — production volume and efficiency |

#### Phase 3 — Conversation and quality review

| Dataset | Join key | What it adds |
| --- | --- | --- |
| `analytics-conversation-details-query` (filtered by participant) | `userId` | Every conversation the agent participated in during the window |
| `quality.get.agents.activity` | `userId` | Evaluation scores: highest, average, lowest, and per-evaluator breakdown |
| `quality.get.published.evaluation.forms` | `formId` | Form definitions to interpret evaluation scores in context |
| `coaching.get.appointments` (filtered) | `userId` | Coaching sessions scheduled and completed for this agent |

#### Phase 4 — WFM and adherence

| Dataset | Join key | What it adds |
| --- | --- | --- |
| `workforce.get.agent.management.unit` | `userId` | WFM management unit — resolves the scheduling team |
| `workforce.get.adherence.bulk` (filtered) | `userId` | Schedule adherence: was the agent on-queue when scheduled? |

#### Key insight: divisions as cross-queue groups

Division membership is a more stable grouping than queue membership. An agent
can be temporarily un-joined from a queue (leave of absence, project rotation)
while remaining in the same division. Reporting on division rather than queue
captures the agent's organizational context even when queue state changes. The
`users.division.analysis.get.users.with.division.info` dataset is the canonical
way to group agents by division across all investigations.

---

### 3.2 Queue health investigation

**Trigger:** A supervisor sees elevated abandon rates or SLA breach alerts and
needs to understand what is happening in a specific queue right now and over
the past shift.

**Subject:** `queueId`

#### Real-time layer (current state)

| Dataset | What it adds |
| --- | --- |
| `routing.get.queue.details` | Queue config: name, division, ACW settings, default flow |
| `routing.get.queue.estimated.wait.time` | Current EWT in seconds — the leading indicator before abandons materialize |
| `analytics.query.queue.observations.real.time.stats` | Live counts: oWaiting, oInteracting, oOnQueueUsers, oOffQueueUsers |
| `analytics.query.user.observations.real.time.status` | Agents currently on-queue with their routing state |

#### Historical layer (shift/day window)

| Dataset | Join key | What it adds |
| --- | --- | --- |
| `analytics.query.queue.aggregates.service.level` | `queueId` | SLA compliance: nAnsweredIn20/30/60, percentage |
| `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | nAbandoned, tAbandoned, abandon rate trend |
| `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | nTransferred, nBlindTransferred, nConsultTransferred — overflow and escalation volume |
| `analytics.query.conversation.aggregates.agent.performance` | `queueId` | Per-agent AHT, ACW, and connected count — identifies outliers on the queue |

#### Configuration and disposition layer

| Dataset | Join key | What it adds |
| --- | --- | --- |
| `routing.get.queue.members` | `queueId` | Full member roster with join state — who should be answering |
| `routing.get.queue.wrapup.codes` | `queueId` | Valid dispositions for this queue — expected wrapup behaviour |
| `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Actual disposition distribution — do agents use expected codes? |

#### Combine for: abandonment root-cause

```
EWT > threshold → check oWaiting (real-time) → check member roster (joined agents)
  → if agents short: check adherence via workforce.get.adherence.bulk
  → if agents present but slow: check per-agent AHT from conversation aggregates
  → if volume spike: check abandon trend vs. historical SLA
```

---

### 3.3 Skill group investigation

**Trigger:** A routing architect wants to understand whether a skill group is
correctly staffed and whether agents in the group are handling their assigned
interactions.

**Subject:** `skillGroupId` (from `routing.get.skill.groups`)

| Order | Dataset | Join key | What it adds |
| --- | --- | --- | --- |
| 1 | `routing.get.skill.groups` | seed | Skill group name, division, member count |
| 2 | `routing.get.skill.group.members` | `skillGroupId` | Agent IDs in the skill group |
| 3 | `users` (per member) | `userId` | Identity for each member |
| 4 | `routing.get.all.routing.skills` (filtered) | `userId` | Proficiency levels for the skill that defines the group |
| 5 | `analytics.query.user.aggregates.performance.metrics` | `userId` | Handle metrics per agent in the group |
| 6 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | Queue-level performance for agents in the group |

---

## 4. Executive Reporting Combinations

Executive reports require **rollup metrics** — aggregates across many queues,
agents, or time windows — rather than per-record detail. The following patterns
are designed to populate dashboards and period-over-period comparisons with the
minimum number of API calls.

### 4.1 Daily operations scorecard

One report cycle, all queues, current day or prior day.

| Dataset | Granularity | Metric group |
| --- | --- | --- |
| `analytics.query.conversation.aggregates.queue.performance` | Per queue, hourly intervals | Volume (nOffered, nConnected), efficiency (tHandle), service (tAnswered) |
| `analytics.query.queue.aggregates.service.level` | Per queue, day interval | SLA compliance: nAnsweredIn20/30/60 |
| `analytics.query.conversation.aggregates.abandon.metrics` | Per queue, day interval | Abandon rate and abandon handle time |
| `analytics.query.conversation.aggregates.transfer.metrics` | Per queue, day interval | Transfer rate — proxy for first-contact resolution |
| `analytics.query.user.aggregates.performance.metrics` | Per agent, day interval | Agent productivity: nConnected, tHandle, tTalk, tAcw |
| `analytics.query.user.aggregates.login.activity` | Per agent, day interval | Staffing adherence: tOnQueueTime vs. scheduled |
| `analytics.post.agents.status.counts` | Point-in-time | Current headcount by routing state |

> **Rollup recipe:** POST all aggregate queries with a 24-hour interval and
> `groupBy: queueId`. Sum nOffered across queues for total volume. Ratio
> nAnsweredIn20 / nOffered for overall SLA. Ratio nAbandoned / nOffered for
> abandon rate. Average tHandle for AHT.

### 4.2 Weekly quality and CSAT report

| Dataset | Granularity | Metric group |
| --- | --- | --- |
| `quality.get.evaluations.query` | Per agent, week | QA scores: average, highest, lowest |
| `quality.get.agents.activity` | Per agent, week | Evaluation activity counts and score distribution |
| `quality.get.surveys` | Per queue, week | CSAT / NPS scores with verbatim |
| `quality.get.published.evaluation.forms` | Catalog | Form definitions for score interpretation |
| `analytics.query.conversation.aggregates.wrapup.distribution` | Per queue, week | Disposition mix — proxy for FCR |

### 4.3 Channel mix and digital volume report

| Dataset | Granularity | Metric group |
| --- | --- | --- |
| `analytics.query.conversation.aggregates.digital.channels` | Per media type, day | nOffered, nConnected, nAbandoned by channel (voice, chat, email, message) |
| `analytics.query.conversation.aggregates.queue.performance` | Per queue, day | Channel-specific SLA and AHT |
| `analytics.query.flow.aggregates.execution.metrics` | Per flow, day | IVR containment: nFlow, nFlowOutcome, nFlowOutcomeFailed |
| `flows.get.flow.outcomes` | Catalog | Flow outcome definitions for labelling |

### 4.4 Outbound campaign performance

| Dataset | What it adds |
| --- | --- |
| `outbound.get.campaigns` | Campaign status, mode, progress |
| `analytics.query.conversation.aggregates.queue.performance` | Outbound queue AHT and connection rate |
| `analytics.query.user.aggregates.performance.metrics` | Agent-level production on outbound queues |
| `outbound.get.events` | Contact disposition events from the dialer |

### 4.5 IVR and flow effectiveness

| Dataset | Join key | What it adds |
| --- | --- | --- |
| `flows.get.all.flows` | seed | All Architect flows with type (inbound, in-queue, bot) |
| `analytics.query.flow.aggregates.execution.metrics` | `flowId` | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone |
| `analytics.query.flow.observations` | `flowId` | Real-time flows in progress |
| `flows.get.flow.milestones` | `milestoneId` | Milestone definitions to interpret analytics |
| `flows.get.flow.outcomes` | `outcomeId` | Outcome definitions to label flow exits |
| `analytics-conversation-details-query` (with flow segment filter) | `flowId` | Conversations that entered a specific flow |

> **IVR containment rate:** nFlowOutcome (self-served) / nFlow (total entered).
> For calls that exit to a queue, join to `analytics.query.conversation.aggregates.queue.performance`
> on the queue the flow routes to.

### 4.6 Real-time executive snapshot (sub-minute)

For live wallboards and NOC displays. Uses observation endpoints only — no async
jobs, no heavy queries.

| Dataset | What it shows |
| --- | --- |
| `analytics.query.queue.observations.real.time.stats` | Per-queue: oWaiting, oInteracting, oOnQueueUsers |
| `analytics.post.agents.status.counts` | Org-wide headcount by routing state |
| `analytics.post.agents.status.query` | Top-50 agents with active sessions |
| `analytics.query.conversation.activity` | In-progress conversations by queue and media type |
| `routing.get.queue.estimated.wait.time` | Real-time EWT per queue |

---

## 5. Division and Compliance Investigation

### 5.1 Division health investigation

**Trigger:** A contact-centre manager owns a division (e.g., "West Region" or
"Tier-2 Support") and wants a consolidated view of performance, staffing, and
access.

A division is an authorization boundary — it groups queues, flows, users, and
other objects under shared access control. Unlike a queue (which receives
interactions), a division is a *governance container*. Multiple queues can share
a division; an agent's division determines which objects they can see and modify.

| Order | Dataset | Join key | What it adds |
| --- | --- | --- | --- |
| 1 | `authorization.get.division.details` | seed | Division name, description, home-org flag, object counts |
| 2 | `authorization.search.division.objects` | `divisionId` | All resources in the division: queues, flows, trunks, routing |
| 3 | `authorization.get.division.grants` | `divisionId` | Role grants: who has what permission within this division |
| 4 | `routing-queues` (filtered by division) | `divisionId` | Queues owned by this division with config details |
| 5 | `users` (filtered by division) | `divisionId` | Agents whose primary division is this one |
| 6 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` (per queue in step 4) | Aggregated performance for all queues in division |
| 7 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon metrics rolled up to division level |
| 8 | `analytics.query.user.aggregates.performance.metrics` | `userId` (per agent in step 5) | Per-agent production in window |
| 9 | `quality.get.evaluations.query` | `userId` | Quality scores for agents in division |
| 10 | `workforce.get.management.units` | `divisionId` | WFM management units in this division |

**Division-spanning skill group cohort:** Agents in the same division who share
a skill group represent a cross-queue capability cohort. Combine `authorization.get.division.details`
+ `routing.get.skill.groups` (filtered by division) + `routing.get.skill.group.members`
to identify this cohort without iterating individual agent records.

### 5.2 Access review (role and grant audit)

| Dataset | What it adds |
| --- | --- |
| `authorization.get.all.divisions` | All divisions — enumerate for org-wide review |
| `authorization.get.division.grants` (per division) | Role-to-subject grants within each division |
| `authorization.get.roles` | Role catalog with permissions — interpret what each grant means |
| `users` | Resolve subject IDs to human-readable identities |
| `oauth.get.clients` | OAuth client applications and their grant types |
| `oauth.get.authorizations` | Active authorization grants issued to users |
| `audit-logs` | Configuration change events for division and role modifications |

**Combination for segregation of duties check:**
1. Pull `authorization.get.division.grants` for all divisions
2. Join to `users` on subject ID
3. Cross-reference: agents who appear as both a grantee and a supervisor in the
   same division — potential segregation concern
4. Validate against `audit-logs` for recent permission changes

---

## 6. Voice Engineer Toolbox Summary

This table is the quick reference for voice engineers. Each symptom maps to the
smallest set of datasets that diagnoses it.

| Symptom | Primary dataset | Secondary dataset | What to look for |
| --- | --- | --- | --- |
| Call never connected | `telephony.get.sip.message.for.conversation` | `analytics.get.single.conversation.analytics` | 4xx/5xx in SIP trace; zero-duration segment in analytics |
| Call connected but no audio | `telephony.get.sip.message.for.conversation` | `conversations.get.conversation.recording.metadata` | re-INVITE in SIP; missing or zero-byte recording |
| Call dropped unexpectedly | `telephony.get.sip.message.for.conversation` | `analytics.get.single.conversation.analytics` | BYE sent before expected; short tTalk in segment |
| Transfer failed | `analytics.get.single.conversation.analytics` | `telephony.get.sip.message.for.conversation` | nTransferred in analytics; REFER/4xx in SIP trace |
| Agent could not hear customer | `telephony.get.sip.message.for.conversation` | `stations.get.stations` | SDP negotiation in SIP; station codec config |
| Recording missing | `conversations.get.conversation.recording.metadata` | `telephony.get.edges` | Empty recording list; edge recording policy |
| High AHT / long call | `analytics.get.single.conversation.analytics` | `conversations.get.conversation.summaries` | Segment breakdown; AI summary for hold/transfer reason |
| Customer survey mismatch | `quality.get.conversation.surveys` | `analytics.get.single.conversation.analytics` | CSAT vs. agent-documented resolution vs. actual timeline |
| SIP trunk capacity issue | `telephony.get.trunk.metrics.summary` | `alerting.get.alerts` | Trunk utilisation metrics; active alerts on trunk |
| Edge connectivity alarm | `telephony.get.edges` | `telephony.get.edge.metrics` | Edge status; per-edge metric anomalies |

---

## 7. Dataset Dependency Map

The following shows which datasets can be joined on common keys. This is the
reference for building new investigation steps or extending existing ones.

### By `conversationId`

```
analytics-conversation-details          (primary analytics record)
analytics.get.single.conversation.analytics
conversations.get.specific.conversation.details
conversations.get.conversation.recording.metadata
conversations.get.recordings
conversations.get.conversation.summaries
speechandtextanalytics.get.conversation.categories
speechandtextanalytics.get.conversation.summaries.detail
telephony.get.sip.message.for.conversation
quality.get.evaluations.query
quality.get.conversation.surveys
```

### By `communicationId` (derived from conversation)

```
speechandtextanalytics.get.conversation.transcript.urls
speechandtextanalytics.get.conversation.communication.transcripturl
```

### By `userId`

```
users                                   (primary identity)
users.get.user.details.with.full.expansion
users.division.analysis.get.users.with.division.info
users.get.user.s.queue.memberships
users.get.user.routing.status
users.get.bulk.user.presences
routing.get.all.routing.skills          (filtered)
routing.get.user.utilization
analytics.query.user.details.activity.report
analytics.query.user.aggregates.performance.metrics
analytics.query.user.aggregates.login.activity
analytics.get.agent.active.status
quality.get.agents.activity
coaching.get.appointments               (filtered)
workforce.get.agent.management.unit
workforce.get.adherence.bulk            (filtered)
```

### By `queueId`

```
routing-queues                          (primary config)
routing.get.queue.details
routing.get.queue.members
routing.get.queue.wrapup.codes
routing.get.queue.estimated.wait.time
analytics.query.queue.observations.real.time.stats
analytics.query.queue.aggregates.service.level
analytics.query.conversation.aggregates.queue.performance
analytics.query.conversation.aggregates.abandon.metrics
analytics.query.conversation.aggregates.transfer.metrics
analytics.query.conversation.aggregates.wrapup.distribution
analytics.query.conversation.aggregates.agent.performance
analytics.query.user.observations.real.time.status
```

### By `divisionId`

```
authorization.get.division.details      (primary config)
authorization.search.division.objects
authorization.get.division.grants
users                                   (filtered)
routing-queues                          (filtered)
routing.get.skill.groups                (filtered)
workforce.get.management.units          (filtered)
```

### By `managementUnitId`

```
workforce.get.management.unit.users
workforce.get.management.unit.adherence
```

### By `skillGroupId`

```
routing.get.skill.groups                (primary)
routing.get.skill.group.members
analytics.query.user.aggregates.performance.metrics  (per member)
```

### By `flowId`

```
flows.get.all.flows                     (primary)
analytics.query.flow.aggregates.execution.metrics
analytics.query.flow.observations
```

---

## 8. Performance and Rate-Limit Guidance

When combining many datasets in a single investigation session:

| Dataset type | Rate-limit profile | Guidance |
| --- | --- | --- |
| Real-time observation queries | Low — sub-second | Burst-safe; safe to call on each poll cycle |
| Aggregate queries (POST) | Medium — 100-300 RPM | Group queues/users into single body rather than one call per entity |
| Async detail jobs (conversation, user) | Low RPM, long-lived | Submit once; poll status; results persist for 24h |
| Single-resource GET | Medium | Batch-safe for small sets; use bulk endpoints for >10 entities |
| Speech analytics transcript fetch | Low | Pre-signed URLs expire; fetch transcript close to investigation time |
| Audit log queries | Async transaction | One submit per investigation; fetch results after polling |

**Key guidance for executive reporting:** Use aggregate endpoints (POST body
queries with `groupBy`) rather than iterating per-queue or per-agent GET
requests. A single aggregate query can cover all queues in a division in one
call; iterating 50 queues individually consumes 50x the rate-limit budget.

**Key guidance for voice engineers:** The SIP trace endpoint is not rate-limited
as aggressively as analytics endpoints. Fetch it first — it is the fastest path
to triage a call failure. If it shows a complete 200 OK and final BYE, the call
setup was clean and the problem is elsewhere (media, recording, routing logic).
