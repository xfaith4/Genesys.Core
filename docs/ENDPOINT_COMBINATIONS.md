# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-07-31  
> Companion to: [INVESTIGATIONS.md](INVESTIGATIONS.md), [ROADMAP.md](ROADMAP.md)

This document describes how catalog datasets combine into coherent investigations and executive
reporting rollups. Each combination is documented with its subject, the ordered dataset steps,
the join keys that connect them, and the analytical questions it answers.

The goal of Genesys.Core is to be **informative without being a data dump**. Every combination
here answers a specific operational question and terminates when that question is answered — not
when the API is exhausted.

---

## Contents

1. [Single Conversation Deep Dive (Voice Engineer)](#1-single-conversation-deep-dive-voice-engineer)
2. [All Conversations in a Queue](#2-all-conversations-in-a-queue)
3. [Division / Agent Group Investigation](#3-division--agent-group-investigation)
4. [Executive Reporting Rollup](#4-executive-reporting-rollup)
5. [Real-Time Operations Monitoring](#5-real-time-operations-monitoring)
6. [BYOI External Conversation Enrichment](#6-byoi-external-conversation-enrichment)
7. [Agent Investigation Extensions](#7-agent-investigation-extensions-release-13)
8. [Conversation Investigation Extensions](#8-conversation-investigation-extensions-release-13)
9. [Queue Investigation Extensions](#9-queue-investigation-extensions-release-13)
10. [Groups — Cross-Queue Agent Cohorts (New)](#10-groups--cross-queue-agent-cohorts-new)
11. [Flow / IVR Investigation (New Combination Pattern)](#11-flow--ivr-investigation-new-combination-pattern)
12. [Platform & Integration Health Rollup (New)](#12-platform--integration-health-rollup-new)
13. [Dataset Combination Reference Matrix](#13-dataset-combination-reference-matrix)

---

## 1. Single Conversation Deep Dive (Voice Engineer)

**Subject:** One `conversationId`  
**Use case:** A voice engineer or QM analyst receives a complaint about a specific call — wrong queue, long hold, audio quality, dropped call, incorrect routing. They need the complete picture of one conversation: where it came from, how it routed, how long each phase took, what the SIP signaling said, whether a recording exists, and what the quality score was.

**Core question:** *What actually happened in this conversation, end-to-end?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Participants, sessions, DNIS/ANI, start/end times, queue assignment, externalTag (BYOI indicator) |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Per-segment timing: IVR duration, ACD wait, talk time, hold time, ACW, conference, recording start/stop |
| 3 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs, media type, duration, deletion schedule |
| 4 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by IVR/Architect flows (account numbers, intent, escalation flags) |
| 5 | `conversations.search.participant.attributes` | `conversationId` | Participant-level attributes (IVR variables, data action outcomes, flow-set values) |
| 6 | `quality.get.evaluations.query` | `conversationId` | QM evaluation scores, form used, evaluator, calibration status |
| 7 | `quality.get.surveys` | `conversationId` | Post-call CSAT/NPS survey result if survey was triggered |
| 8 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace: INVITE, 200 OK, BYE, re-INVITE, codec negotiation |
| 9 *(STA enabled)* | `conversations.get.speech.text.analytics` | `conversationId` | Sentiment score, detected topics, STA coverage summary |
| 10 *(STA enabled)* | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Sentiment timeline: per-utterance scores, agent vs customer breakdown |
| 11 *(transcription enabled)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId` + `communicationId` | Transcript download URL per communication leg |
| 12 *(evaluated)* | `quality.get.published.evaluation.forms` | `formId` (from step 6) | Resolves the evaluation form's question text and scoring weights so a raw QM score can be read in context — label resolution, not a new fact |
| 13 *(Agent Assist/Predictive Engagement enabled)* | `conversations.get.conversation.suggestions` | `conversationId` | Knowledge/response suggestions surfaced to the agent during the call |
| 14 *(step 13 non-empty)* | `conversations.get.conversation.suggestion.detail` | `conversationId` + `suggestionId` | Whether a specific suggestion was shown, accepted, or dismissed — ties AI assistance to outcome |
| 15 *(voice only, optional)* | `stations.get.stations` | `station.id` (from the participant record in step 1) | Which physical/software station handled the call — narrows audio-quality triage to a device or WebRTC client instead of the whole Edge |

### Key Joins

```
conversations.get.conversation.object.conversationId
  → analytics.get.single.conversation.analytics.conversationId (segment overlay)
  → conversations.get.conversation.recording.metadata.conversationId
  → telephony.get.sip.messages.for.conversation.conversationId (voice only)
  → quality.get.evaluations.query[].conversationId (left join — evaluations may not exist)

analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
  → speechandtextanalytics.get.conversation.communication.transcripturl.communicationId
```

### Analytical Questions Answered

- What was the full call flow? (IVR → ACD → agent → hold → ACW)
- How long did the customer wait before an agent answered?
- Was the call transferred? How many times? What queue received the transfer?
- Was a recording made? Does it still exist?
- Did the SIP trunk establish media correctly? (from SIP trace)
- Was the agent rated? What was the QM score?
- Was the customer surveyed? What was the CSAT result?
- What intent/attributes did the IVR capture before routing?

### Voice Engineer Notes

Step 8 (SIP trace) is the definitive source for:
- Call setup failures (no 200 OK, 486 Busy, 503 Service Unavailable)
- One-way audio (media IP mismatch in SDP)
- Premature disconnection (BYE before expected, no 200 OK to BYE)
- Codec negotiation failures

The `telephony.get.edge.performance.metrics` dataset (`GET /api/v2/telephony/providers/edges/{edgeId}/metrics`)
should be pulled for the Edge appliance that handled the call if CPU, memory, or error counters suggest
resource pressure during the conversation window.

For a suspected single-agent audio problem (as opposed to trunk-wide degradation), pull the agent's
`stations.get.stations` record (step 15) before escalating to the Edge. A station-level issue (WebRTC
client, headset, local network) and an Edge-level issue produce similar customer complaints but require
different remediation — station scope narrows the investigation before involving network engineering.

### BYOI Indicator

If `conversations.get.conversation.object` returns a non-null `externalTag` or `externalConversationId`,
the call was injected via the BYOI integration (`POST /api/v2/conversations/providers/{providerId}/calls`).
Custom attributes in step 4 will contain the provider's context (CRM case ID, external call ID).
The SIP trace (step 8) will reflect the provider's SIP-to-SIP handoff, not an inbound PSTN leg.

---

## 2. All Conversations in a Queue

**Subject:** One `queueId` + time window  
**Use case:** A contact centre supervisor or operations analyst needs to understand the health and
behaviour of a specific queue over a period — volume patterns, handle times, abandons, transfer
rates, and wrapup outcomes.

**Core question:** *How did this queue perform, and what were the conversations like?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.single.queue.config` | seed → `queueId` | Queue name, routing method, SLA targets, media types, skill evaluation mode |
| 2 | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Human-readable wrapup code labels for the queue |
| 3 | `analytics-conversation-details-query` (queueId filter) | `queueId` | Every conversation that touched this queue in the window, with participant/segment detail |
| 4 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Aggregate: nConnected, tHandle, tTalk, tAcw, tAnswered, tHeld, nOffered, nOutbound |
| 5 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon count: nAbandoned, tAbandon, tShortAbandon |
| 6 | `analytics.query.queue.aggregates.service.level` | `queueId` | SLA achievement: nAnsweredIn20/30/60, oServiceLevel, oServiceTarget, nOverSla |
| 7 | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer analysis: nTransferred, nBlindTransferred, nConsultTransferred |
| 8 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` + wrapUpCode | Wrapup code frequencies (join step 2 for labels) |
| 9 | `routing-queue-members` | `queueId` | Current membership roster with routing status and presence |
| 10 | `quality.get.evaluations.query` (queueId filter) | `conversationId` | QM evaluation coverage and scores for conversations in this queue |

### Key Joins

```
routing.get.single.queue.config.id
  → analytics.query.conversation.aggregates.*.queueId (aggregate overlay)
  → routing-queue-members.queueId (who was staffed)

analytics.query.conversation.aggregates.wrapup.distribution.wrapUpCode
  → routing.get.queue.wrapup.codes.by.queue.id (label resolution)

analytics-conversation-details-query[].conversationId
  → quality.get.evaluations.query[].conversationId (left join — not all conversations are evaluated)
```

### Analytical Questions Answered

- What was the offered/connected/abandoned volume for this queue?
- Did the queue meet its SLA target? In which hourly intervals did it miss?
- What percentage of conversations were transferred? Where did they go?
- What wrapup codes dominated, and what do they mean?
- Who were the active agents? What was their routing status during the window?
- How many conversations were quality-reviewed? What was the average score?

### Divisions as Queue Groups

Queues within a division represent a natural management boundary — a division is effectively
a group of queues and agents. To investigate an entire division:
1. Use `authorization.list.division.queues` to get all queue IDs in the division.
2. Fan out the steps above once per queue, or use `authorization.get.single.division` as the
   seed and filter analytics queries with `divisionId` predicates.

---

## 3. Division / Agent Group Investigation

**Subject:** One `divisionId` + time window  
**Use case:** A contact centre director or workforce analyst needs to understand how a specific
business unit (division) performed — which agents are in it, what volume each handled, time-in-state,
quality scores, and coaching coverage.

**Core question:** *How did this division's agents perform as a group?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `authorization.get.single.division` | seed → `divisionId` | Division name, description, home-division flag |
| 2 | `authorization.list.division.queues` | `divisionId` | All queue IDs assigned to this division |
| 3 | `users.division.analysis.get.users.with.division.info` | `divisionId` | All agents assigned to the division with user IDs |
| 4 | `analytics.query.conversation.aggregates.agent.performance` (divisionId filter) | `userId` | Per-agent: nConnected, tHandle, tTalk, tAcw, tAnswered |
| 5 | `analytics.query.user.aggregates.login.activity` (divisionId filter) | `userId` | Per-agent time-in-state: tAgentRoutingStatus, tSystemPresence, tOrganizationPresence |
| 6 | `analytics.query.user.details.activity.report` (userId list) | `userId` | Login/logout/on-queue presence event timeline per agent |
| 7 | `quality.get.agents.activity` | `userId` | QM evaluation counts, highest/average/lowest scores per agent |
| 8 | `coaching.get.appointments` | `userId` | Coaching sessions scheduled/completed for agents in the window |
| 9 | `analytics.query.conversation.aggregates.wrapup.distribution` (divisionId filter) | `queueId` | Wrapup code distribution across all queues in the division |
| 10 *(WFM licensed)* | `workforce.get.business.units` + `workforce.get.management.units` | `divisionId` (filter) | Resolves which WFM management unit(s) schedule agents in this division — required before pulling adherence |
| 11 *(WFM licensed)* | `workforce.get.management.unit.users` | `managementUnitId` (from step 10) | Confirms which agents in the division are on a published WFM schedule |
| 12 *(WFM licensed)* | `workforce.get.management.unit.adherence` | `managementUnitId` | Real-time schedule adherence state per agent — the workforce counterpart to step 5's routing-status time-in-state |
| 13 | `routing.get.skill.groups` | `divisionId` (filter, if supported) or post-hoc filter on step 3's userIds | Skill-group membership — a coarser, admin-managed grouping of routing skills distinct from both Divisions and ad hoc Groups (see [§10](#10-groups--cross-queue-agent-cohorts-new)) |

### Key Joins

```
authorization.get.single.division.id
  → authorization.list.division.queues.divisionId (queue enumeration)
  → users.division.analysis.get.users.with.division.info.divisionId (agent enumeration)

users.division.analysis.get.users.with.division.info[].id
  → analytics.query.conversation.aggregates.agent.performance[].userId
  → analytics.query.user.aggregates.login.activity[].userId
  → quality.get.agents.activity[].user.id
  → coaching.get.appointments[].attendees[].id
```

### Analytical Questions Answered

- How many agents are in this division and who are they?
- What queues does this division own?
- Which agents handled the most volume? Which had the highest AHT?
- Which agents spent the most time off-queue or in non-productive states?
- Which agents have been evaluated? Who has the highest/lowest scores?
- Which agents have received recent coaching? Is coaching correlated with score improvement?
- Which agents are out of schedule adherence right now, and by how much? (step 12; requires WFM)
- Is an agent's low `nConnected` explained by an unstaffed schedule, or by being staffed but off-queue?
  (join step 12's adherence state against step 5's `tAgentRoutingStatus` — a real-time-status agent
  with poor adherence is a coaching case; a schedule agent with a legitimate exception is not)

### Adherence vs. Routing Status — Which to Use

Both `analytics.query.user.aggregates.login.activity` (step 5) and `workforce.get.management.unit.adherence`
(step 12) describe an agent's time, but they answer different questions:

- **Routing status time-in-state** (step 5) is the ACD's view: how long the agent spent
  `Available`/`Busy`/`Off Queue` regardless of whether a shift was scheduled.
- **WFM adherence** (step 12) is the *scheduling* view: how the agent's actual activity compares to
  what their published WFM schedule says they should be doing right now. It requires WFM licensing
  and a management unit with a published schedule; skip steps 10–12 entirely if the org does not use
  Genesys WFM scheduling.

### Division vs Queue as Investigation Entry Point

| Start with | When you know | You get |
|------------|---------------|---------|
| `queueId` | Specific queue complaints | All conversations + SLA + wrapup + member roster |
| `divisionId` | Business unit or team scope | All queues + all agents + group performance |
| `userId` (Agent Investigation) | Specific agent complaint | That agent's conversations + skills + presence |

---

## 4. Executive Reporting Rollup

**Subject:** Organisation-wide (or multi-queue) + reporting window (weekly/monthly)  
**Use case:** A VP or Director of Operations needs a concise performance summary suitable for
executive review — not a data dump, but the headline KPIs grouped logically.

**Core question:** *How did the contact centre perform this period, by which dimensions?*

### Dataset Steps (ordered by reporting layer)

#### Layer 1 — Volume & Efficiency
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.conversation.aggregates.queue.performance` | `queueId`, `mediaType`, daily granularity | nOffered, nConnected, tHandle (avg), tTalk (avg), tAcw (avg) |
| `analytics.query.conversation.aggregates.abandon.metrics` | `queueId`, `mediaType`, daily | nAbandoned, tAbandon, nOffered (abandon rate = nAbandoned/nOffered) |
| `analytics.query.conversation.aggregates.digital.channels` | `mediaType`, `queueId`, daily | Channel mix: nOffered, nConnected by voice/chat/email/message |

#### Layer 2 — Service Quality
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.queue.aggregates.service.level` | `queueId`, daily | oServiceLevel, nOverSla, nAnsweredIn20 (configurable speed-of-answer) |
| `analytics.query.conversation.aggregates.transfer.metrics` | `queueId`, daily | Transfer rate: nTransferred / nConnected |
| `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId`, `wrapUpCode`, daily | Wrapup mix — outcome analysis |

#### Layer 3 — Workforce
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.user.aggregates.login.activity` | `userId`, daily | tAgentRoutingStatus: available, busy, on-queue time per agent |
| `analytics.query.user.aggregates.performance.metrics` | `userId`, daily | nConnected, tHandle (avg) per agent — productivity comparison |

#### Layer 4 — Quality & Voice-of-Customer
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `quality.get.agents.activity` | `userId` | Evaluation coverage rate, average score, score distribution |
| `quality.get.published.evaluation.forms` | `formId` | Question-level labels — needed if the exec view drills from an overall score into which questions dragged it down |
| `quality.get.surveys` | `conversationId` (aggregate) | CSAT/NPS: response rate, average score |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | Speech analytics coverage: nSpeechTextAnalyzedConversations, oSentimentScore |

#### Layer 5 — Infrastructure Health (optional, voice-focused)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `telephony.get.trunk.metrics.summary` | — | SIP trunk utilisation, errors |
| `telephony.get.edges` | `edgeId` | Edge registration status |
| `alerting.get.alerts` | — | Currently firing threshold alerts |

#### Layer 6 — Platform & Integration Health (optional, admin-focused)

See [§12](#12-platform--integration-health-rollup-new) for the full combination. Included at the
executive layer only as a one-line capacity signal — this is a platform-team concern, not a
day-to-day operational metric, so keep it to a single row on the exec dashboard rather than
expanding it inline here:

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `usage.get.api.usage.organization.summary` | daily | API call volume against the org's rate-limit ceiling — an early warning that integration growth is approaching a platform limit |

### Executive Dashboard Composition Pattern

```
Period: Last 28 days, daily granularity
Queues: All production queues (from routing-queues, filtered by active=true)

Headline metrics (computed, not raw):
  - Total handled: SUM(nConnected) across all queues
  - Abandon rate: SUM(nAbandoned) / SUM(nOffered) × 100
  - Average handle time: WAVG(tHandle, nConnected)
  - SLA achievement: queues meeting target / total queues × 100
  - Transfer rate: SUM(nTransferred) / SUM(nConnected) × 100
  - QM coverage: evaluations / nConnected × 100
  - Average QM score: from quality.get.agents.activity
  - Avg CSAT: from quality.get.surveys

Trend views (daily granularity):
  - Volume by day with channel mix
  - AHT trend by queue
  - Abandon rate trend by queue
  - SLA achievement heatmap by queue × day
```

### Key Joins for Executive Reporting

```
routing-queues[].id
  → analytics.query.conversation.aggregates.*.results[].group.queueId
  → routing.get.queue.wrapup.codes.by.queue.queueId (label resolution)
  → quality.get.agents.activity (left join via queue membership)

analytics.query.conversation.aggregates.wrapup.distribution[].group.wrapUpCode
  → routing.get.all.wrapup.codes[].id (global wrapup code labels)
```

---

## 5. Real-Time Operations Monitoring

**Subject:** Organisation or specific queues (no fixed window — point-in-time)  
**Use case:** A real-time analyst, supervisor, or NOC team needs a live view of queue health and
agent availability right now, without waiting for a historical analytics job.

**Core question:** *What is happening in the contact centre this moment?*

### Dataset Steps (real-time, polling pattern)

| Step | Dataset Key | Scope | What It Shows |
|------|-------------|-------|---------------|
| 1 | `analytics.query.queue.observations.real.time.stats` | All queues | oInteracting, oWaiting, oOnQueueUsers, oOffQueueUsers, oActiveUsers per queue |
| 2 | `analytics.query.conversation.activity.real.time` | All queues | oInteracting, oWaiting, oAlerting, oLongestWaiting per queue × mediaType |
| 3 | `analytics.query.user.observations.real.time.status` | All agents | oUserPresence (system presence), oUserRoutingStatus per agent |
| 4 | `analytics.get.agent.active.status` | One agent | Full real-time channel assignment for a specific agent — active conversation IDs |
| 5 | `users.get.agent.active.conversations` | One agent | All in-progress conversations for a specific agent |
| 6 | `users.get.agent.current.routing.status` | One agent | Current routing state (IDLE / INTERACTING / NOT_RESPONDING / OFF_QUEUE) |
| 7 | `analytics.query.flow.observations` | All flows | oFlow: active Architect flows currently executing |
| 8 *(telephony NOC)* | `telephony.get.trunk.metrics.summary` | — | Trunk utilisation and error counters |
| 9 *(telephony NOC)* | `telephony.get.edge.performance.metrics` | One Edge | CPU, memory, active call count on specific Edge |
| 10 *(drilldown)* | `conversations.get.active.calls` / `.active.chats` / `.active.emails` / `.active.callbacks` / `.active.conversations` | All queues, per mediaType | The actual conversation IDs behind step 1/2's aggregate counts — step 1 says "12 waiting," step 10 says which 12 |
| 11 *(label resolution)* | `presence.get.organization.presence.definitions` + `presence.get.system.presence.definitions` | `presenceId` | Human-readable labels for the raw presence IDs in step 3 — a wall board showing GUIDs instead of "Available"/"Meeting"/"Break" is a data dump, not a display |

### Polling Note

Real-time datasets (`analytics.query.queue.observations.real.time.stats`,
`analytics.query.conversation.activity.real.time`, `analytics.query.user.observations.real.time.status`)
do not accept `interval` parameters — they reflect the current state as of the API call. These
should be polled at the rate appropriate for the display (typically 10–30 seconds for a wall board).

The `analytics.get.agent.active.status` endpoint returns a single agent's live state and is
intended for targeted drilldown (supervisor clicks on an agent in the wall board).

### Push Alternative to Polling

`notifications.get.available.notification.topics` and `notifications.get.notification.subscriptions`
enumerate the WebSocket notification topics available to the org (e.g. `v2.routing.queues.{id}.observations`,
`v2.users.{id}.routingStatus`). A wall board that needs sub-10-second latency at scale should subscribe
to these topics instead of polling steps 1–3 on a timer — the datasets above remain the correct choice
for a one-time snapshot, a scheduled report, or an environment where standing up a WebSocket client is
not worth the operational cost. This is a design choice, not an API gap: both paths return the same
underlying state.

---

## 6. BYOI External Conversation Enrichment

**Subject:** One `conversationId` that was injected via BYOI  
**Use case:** A conversation originated in an external system (CRM telephony, third-party contact
centre, a custom SIP provider) and was injected into Genesys Cloud via the BYOI provider API
(`POST /api/v2/conversations/providers/{providerId}/calls`). The conversation appears in Genesys
analytics and recordings, but context lives in the external system.

**Core question:** *Where did this conversation come from, and what external context does it carry?*

### How to Identify a BYOI Conversation

In step 1 of the Conversation Investigation, `conversations.get.conversation.object` returns:

```json
{
  "externalTag": "<your-provider-set-tag>",
  "externalConversationId": "<provider-conversation-id>",
  "participants": [
    { "purpose": "external", "externalContactId": "..." }
  ]
}
```

A non-null `externalTag` is the definitive BYOI indicator.

### Additional Steps for BYOI Conversations

| Step | Dataset Key | What It Adds |
|------|-------------|--------------|
| + | `conversations.get.conversation.customattributes` | Provider-set custom attributes: CRM case ID, intent label, external call ID |
| + | `conversations.search.participant.attributes` | IVR/Architect variables set during the injected conversation flow |

### BYOI Conversation in Analytics

BYOI conversations flow through the same Architect flows, queue routing, and analytics pipeline
as native Genesys conversations. The following datasets apply identically:
- `analytics.get.single.conversation.analytics` — segment timing is accurate
- `conversations.get.conversation.recording.metadata` — recordings exist if enabled
- `quality.get.evaluations.query` — evaluations proceed normally
- `telephony.get.sip.messages.for.conversation` — reflects the BYOI SIP-to-SIP handoff, not a PSTN leg

### Embeddable Framework Conversations

Conversations visible to agents via the Embeddable Framework return the same object shape as
`conversations.get.conversation.object`. The condensed view used by the embedded client includes:
`participants[].purpose`, `participants[].state`, `participants[].calls[].state`,
`participants[].calls[].muted`, `participants[].calls[].held`. These fields are present in the
full object returned by the dataset and need no special handling.

### Finding BYOI Conversations by External Context, Not Just by ID

Everything above assumes the investigation already has a `conversationId`. When the starting point
is instead an external identifier — a CRM case number, a provider's own call ID — use
`conversations.search.customattributes` to search across conversations by the custom-attribute
values a BYOI provider set at injection time, rather than enumerating conversations and checking
each one's `externalTag`. This is the correct entry point for "find the Genesys side of CRM case
#12345" style requests, which come up often enough in BYOI support handoffs to warrant a dedicated
step rather than a queue- or division-scoped fishing expedition.

---

## 7. Agent Investigation Extensions (Release 1.3)

The existing Agent Investigation (`Get-GenesysAgentInvestigation`) covers 8 steps. These additional
datasets enrich the investigation without replacing any existing step.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| utilization | `routing.get.user.utilization` | `userId` | Max channel capacities — why can the agent only handle N simultaneous chats? |
| currentStatus | `users.get.agent.current.routing.status` | `userId` | Routing state at investigation time (IDLE / INTERACTING / OFF_QUEUE) |
| activeConversations | `users.get.agent.active.conversations` | `userId` | In-progress conversations if `currentStatus = INTERACTING` |
| qualityActivity | `quality.get.agents.activity` | `userId` | Evaluation count, average/highest/lowest scores for the window |
| coaching | `coaching.get.appointments` | `userId` | Coaching sessions attending/facilitating in the window |

**Trigger conditions:** `currentStatus` and `activeConversations` steps are conditional on the
agent being in an active state at investigation time. `coaching` step is conditional on WFM being
licensed and configured.

---

## 8. Conversation Investigation Extensions (Release 1.3)

The existing Conversation Investigation (`Get-GenesysConversationInvestigation`) covers 8 steps.
These additional datasets complete the deep-dive picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| analyticsDetail | `analytics.get.single.conversation.analytics` | `conversationId` | Per-segment timing (IVR, ACD wait, talk, hold, ACW) — replaces the query-based analytics step |
| sipTrace | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace (voice only, conditional) |
| sentimentTimeline | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-utterance sentiment (STA enabled only, conditional) |
| customAttributes | `conversations.get.conversation.customattributes` | `conversationId` | IVR/Architect custom attribute payload |
| participantAttributes | `conversations.search.participant.attributes` | `conversationId` | Participant-level flow variables |
| transcriptUrl | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcript download URL (transcription enabled only) |

**Conditional steps:** `sipTrace` runs only when `conversations.get.conversation.object.participants[].calls` is
non-empty (voice conversation). `sentimentTimeline` runs only when `conversations.get.speech.text.analytics`
returns `speechAndTextAnalyticsConversation.analysisStatus = "Success"`.

---

## 9. Queue Investigation Extensions (Release 1.3)

The existing Queue Investigation (`Get-GenesysQueueInvestigation`) covers 6 steps. These additions
complete the picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| queueConfig | `routing.get.single.queue.config` | `queueId` | Full queue config (replaces/enriches the routing-queues list step) |
| wrapupLabels | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Human-readable labels for the wrapup distribution step |
| transfers | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer rate and type breakdown |
| wrapupDistribution | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Wrapup code frequencies (join wrapupLabels for labels) |
| conversationDetail | `analytics-conversation-details-query` (queueId filter) | `conversationId` | Individual conversations for case-level review |

---

## 10. Groups — Cross-Queue Agent Cohorts (New)

**Subject:** One `groupId` (ad hoc Genesys Cloud Group)
**Use case:** A division is an administrative/reporting boundary — one agent belongs to exactly one
division, and a division owns a fixed set of queues. A **Group** is a different, complementary
construct: an ad hoc, admin-managed cohort of users that can cross division and queue boundaries
entirely — "Spanish Speakers," "Certified Closers," "Team Leads," a project taskforce. The user's
framing that "divisions assigned to agents are groups in themselves, even across queues" is exactly
right for Divisions (§3); Groups are the *other* cross-cutting cohort worth investigating the same
way, because they answer questions Divisions structurally cannot (an agent can be in one division but
five groups).

**Core question:** *Which agents belong to this cohort, and how did they perform as a set — regardless
of which division or queue each one sits in?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `groups.get.single.group` | seed → `groupId` | Group name, description, type, visibility |
| 2 | `groups.get.group.members` | `groupId` | Every `userId` in the group — individuals, owners, and dynamically-included members |
| 3 | `analytics.query.conversation.aggregates.agent.performance` (userId list from step 2) | `userId` | Per-member volume/AHT, same as the Division investigation's step 4 |
| 4 | `analytics.query.user.aggregates.login.activity` (userId list) | `userId` | Per-member time-in-state |
| 5 | `quality.get.agents.activity` (userId list) | `userId` | Per-member evaluation coverage and scores |
| 6 | `users.division.analysis.get.users.with.division.info` (userId list) | `userId` | Which division(s) group members actually belong to — the cross-tab that makes this investigation useful |

### Key Joins

```
groups.get.single.group.id
  → groups.get.group.members.groupId (membership enumeration)

groups.get.group.members[].id
  → analytics.query.conversation.aggregates.agent.performance[].userId
  → analytics.query.user.aggregates.login.activity[].userId
  → quality.get.agents.activity[].user.id
  → users.division.analysis.get.users.with.division.info[].id (division cross-tab)
```

### Analytical Questions Answered

- Who is actually in this group right now, and does membership match the roster someone remembers?
- How did this cross-cutting cohort perform as a unit — e.g. did the "Spanish Speakers" group meet
  its handle-time target regardless of which queue or division each member sits in?
- Does group membership correlate with division or queue assignment, or is it genuinely cross-cutting?
  (Answered by joining step 6 back against step 2 — if every member is in the same division, a Group
  investigation was unnecessary and the Division investigation in §3 would have sufficed.)

### When to Use Groups vs. Divisions vs. Queues as the Entry Point

| Start with | When you know | You get |
|------------|---------------|---------|
| `queueId` (§2) | Specific queue complaints | All conversations in that queue |
| `divisionId` (§3) | Business unit / reporting boundary | All queues + all agents *administratively* assigned to that boundary |
| `groupId` (§10) | A named cohort that does not map to one division or queue | All members of that cohort, wherever they sit |

**Note on catalog status:** `groups.get.groups`, `groups.get.single.group`, and `groups.get.group.members`
were added to `catalog/genesys.catalog.json` as part of this evaluation pass and carry
`validationStatus: unvalidated` — they follow the same paging/retry contract as the rest of the
catalog but have not yet been exercised against a live org. Treat this section as a scoped combination
pattern, not a shipped investigation; see [INVESTIGATIONS.md §4.6](INVESTIGATIONS.md) for the composer
scope.

---

## 11. Flow / IVR Investigation (New Combination Pattern)

**Subject:** One `flowId` (Architect flow) + time window
**Use case:** The Conversation Deep Dive (§1) and Queue Investigation (§2) both surface IVR duration
and routing outcome at the *conversation* level, but neither answers a flow-designer's question: is
this specific Architect flow itself healthy across all the conversations that ran through it? This
combination is the flow-centric counterpart to the queue-centric and conversation-centric
investigations already in this document, and directly answers `docs/ROADMAP.md`'s open "Next" item
of scoping a Flow flagship investigation.

**Core question:** *Is this IVR/bot flow behaving correctly across the conversations that ran it, and
where in the flow do calls get stuck, error out, or exit early?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` (filtered to one flow) | seed → `flowId` | Flow name, type (inbound call / bot / in-queue), division, published version |
| 2 | `flows.get.flow.outcomes` | `flowId` (filter) | Configured outcome labels this flow can exit with (e.g. "Resolved in IVR," "Transferred to Agent," "Abandoned in Flow") |
| 3 | `flows.get.flow.milestones` | `flowId` (filter) | Named checkpoints inside the flow used for stage-by-stage timing |
| 4 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` + window | Aggregate execution counts, average duration, and outcome distribution across all runs in the window |
| 5 | `analytics.query.flow.observations` | `flowId` | Real-time count of conversations currently executing this flow — useful when the investigation starts from "the IVR seems stuck right now" |
| 6 | `analytics-conversation-details-query` (flow-touched filter) | `conversationId` | Individual conversations that touched this flow, for case-level drilldown into a specific bad outcome |

### Key Joins

```
flows.get.all.flows.id
  → flows.get.flow.outcomes.flowId (label resolution for step 4's outcome distribution)
  → flows.get.flow.milestones.flowId (label resolution for stage timings)
  → analytics.query.flow.aggregates.execution.metrics.flowId (aggregate overlay)
  → analytics.query.flow.observations.flowId (real-time overlay)

analytics-conversation-details-query[].conversationId
  → conversations.get.conversation.object.conversationId (drill into §1 for one bad-outcome call)
```

### Analytical Questions Answered

- Which outcome does this flow produce most often, and has that mix shifted after a recent
  publish? (compare step 4 across two windows bracketing a flow-version change)
- Where in the flow — which milestone — do calls spend the most time, or fail to reach?
- Is a live-reported "IVR is stuck" complaint reflected in step 5's real-time execution count?
- For a specific bad outcome (e.g. unexpected "Abandoned in Flow"), which conversations produced it,
  and what do they have in common when drilled into via §1?

### Relationship to the Conversation Deep Dive

This pattern does not replace §1's per-conversation IVR-duration step — it answers the "is the flow
itself healthy across many calls" question that a single conversation's timing cannot. Use §1 to
diagnose one call; use this pattern to decide whether the flow needs a design change.

**Note on catalog status:** every dataset in this pattern already exists in `catalog/genesys.catalog.json`;
this section documents a previously undocumented combination, it does not add new endpoints. See
[INVESTIGATIONS.md §4.7](INVESTIGATIONS.md) for composer scoping notes.

---

## 12. Platform & Integration Health Rollup (New)

**Subject:** Organisation-wide, no fixed subject — a platform/admin concern, not an operational one
**Use case:** Contact-centre reporting (§4) tracks customer-facing KPIs. A separate, smaller audience —
the platform admin or integration owner — needs a periodic check that the org is not approaching a
Genesys Cloud rate limit or accumulating stale/unused OAuth clients, either of which causes outages
that look like unrelated application bugs when they hit.

**Core question:** *Is our API/integration footprint healthy, or are we approaching a platform ceiling?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `usage.get.api.usage.organization.summary` | — | Org-wide API call volume against the rate-limit ceiling, by time bucket |
| 2 | `usage.get.api.usage.by.client` | `clientId` | Per-OAuth-client call volume — identifies which integration is driving usage |
| 3 | `usage.get.api.usage.by.user` | `userId` | Per-user call volume — identifies a runaway script or misbehaving personal-access-token usage |
| 4 | `oauth.get.clients` | `clientId` | Client name, grant type, and roles — resolves step 2's `clientId` to a readable integration name |
| 5 | `oauth.get.authorizations` | `clientId` | Which OAuth clients are currently authorized and with what scope — flags clients that should have been revoked |
| 6 | `oauth.post.client.usage.query` → `oauth.get.client.usage.query.results` | `clientId` | Historical usage trend for one client, once step 2/3 identifies a candidate worth trending |
| 7 | `analytics.query.rate.limit.aggregates` | — | Rate-limit-specific view (429 counts, throttled calls) as a direct corroborating signal for step 1's ceiling proximity |

### Key Joins

```
usage.get.api.usage.by.client[].clientId
  → oauth.get.clients[].id (name resolution)
  → oauth.get.authorizations[].client.id (authorization/scope context)
  → oauth.post.client.usage.query + oauth.get.client.usage.query.results (trend drilldown)
```

### Analytical Questions Answered

- Are we within our organisation's API rate-limit ceiling, and how much headroom is left this period?
- Which integration or client is responsible for the largest share of API volume?
- Are 429s (step 7) showing up, and do they correlate with a specific client's usage spike (step 2)?
- Are there authorized OAuth clients (step 5) with no corresponding usage (step 2/3) — dead
  integrations still holding a valid grant that should be revoked as a security cleanup item?

### Reporting Cadence

Unlike §4's daily/weekly contact-centre KPIs, this rollup is a **monthly or on-threshold-alert**
concern — pull it on a schedule far coarser than operational reporting, or trigger it from an
`alerting.get.alerts` rule if the org has a rate-limit-proximity alert configured. Running it daily
produces noise without a corresponding daily action.

---

## 13. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable. The Platform & Integration Health
Rollup (§12) is org-wide rather than subject-centred and is intentionally not a column here — see
§12 directly for its dataset list.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | Groups Investigation | Flow Investigation |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | |
| `conversations.search.customattributes` | ○ | | | | | | | |
| `conversations.get.conversation.suggestions` | ○ | | | | | | | |
| `conversations.get.conversation.suggestion.detail` | ○ | | | | | | | |
| `stations.get.stations` | ○ | | | | | ○ | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | |
| `quality.get.published.evaluation.forms` | ○ | | | ○ | | | | |
| `quality.get.surveys` | ● | | | ● | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | | ○ |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | |
| `routing-queue-members` | | ● | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | ● | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | ● | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | ● | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | ● | |
| `coaching.get.appointments` | | | ● | | | ○ | | |
| `workforce.get.business.units` | | | ○ | | | | | |
| `workforce.get.management.units` | | | ○ | | | | | |
| `workforce.get.management.unit.users` | | | ○ | | | | | |
| `workforce.get.management.unit.adherence` | | | ○ | | | | | |
| `routing.get.skill.groups` | | | ● | | | | ○ | |
| `groups.get.groups` | | | | | | | ○ | |
| `groups.get.single.group` | | | | | | | ● | |
| `groups.get.group.members` | | | | | | | ● | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | |
| `conversations.get.active.calls` | | | | | ○ | | | |
| `conversations.get.active.chats` | | | | | ○ | | | |
| `conversations.get.active.emails` | | | | | ○ | | | |
| `conversations.get.active.callbacks` | | | | | ○ | | | |
| `conversations.get.active.conversations` | | | | | ○ | | | |
| `presence.get.organization.presence.definitions` | | | ○ | | ○ | | | |
| `presence.get.system.presence.definitions` | | | ○ | | ○ | | | |
| `notifications.get.available.notification.topics` | | | | | ○ | | | |
| `notifications.get.notification.subscriptions` | | | | | ○ | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | |
| `flows.get.all.flows` | | | | | | | | ● |
| `flows.get.flow.outcomes` | | | | | | | | ● |
| `flows.get.flow.milestones` | | | | | | | | ● |
| `analytics.query.flow.observations` | | | | | ● | | | ● |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | | ● |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | |
| `users.get.user.routing.skills` | | | | | | ● | | |
| `users.get.user.queue.memberships` | | | | | | ● | | |
| `users.get.bulk.user.presences` | | | | | | ● | | |
| `routing.get.user.utilization` | | | | | | ○ | | |
| `audit-logs` | | | | | | ● | | |

---

## Appendix: Metric Glossary

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `nOffered` | Conversations offered to the queue | Volume denominator |
| `nConnected` | Conversations connected to an agent | Handled volume |
| `nAbandoned` | Conversations abandoned before connection | Abandon count |
| `tHandle` | Total handle time (talk + hold + ACW) | AHT numerator |
| `tTalk` | Total talk time | Talk-time component |
| `tAcw` | After-call work time | ACW component |
| `tAnswered` | Time from offered to answered | Speed of answer |
| `nTransferred` | Conversations transferred | Transfer volume |
| `oServiceLevel` | Current SLA percentage | Real-time SLA |
| `nOverSla` | Conversations that exceeded SLA threshold | SLA misses |
| `oInteracting` | Agents currently on interactions | Active agents |
| `oWaiting` | Interactions waiting in queue | Queue depth |
| `oLongestWaiting` | Seconds the longest-waiting customer has been waiting | Worst-case wait |
| `tAgentRoutingStatus` | Time in each routing status | On-queue vs off-queue time |
| `tSystemPresence` | Time in each system presence | Available, Busy, Away, Offline |
| `oSentimentScore` | Aggregate sentiment score (STA) | Voice-of-customer indicator |
| `nSpeechTextAnalyzedConversations` | Conversations with STA analysis | STA coverage |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
