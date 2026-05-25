# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-25  
> Companion to: [INVESTIGATIONS.md](INVESTIGATIONS.md), [ROADMAP.md](ROADMAP.md)

This document describes how catalog datasets combine into coherent investigations and executive
reporting rollups. Each combination is documented with its subject, the ordered dataset steps,
the join keys that connect them, and the analytical questions it answers.

The goal of Genesys.Core is to be **informative without being a data dump**. Every combination
here answers a specific operational question and terminates when that question is answered — not
when the API is exhausted.

Each catalog dataset now carries an `investigations` array in `catalog/genesys.catalog.json`
identifying which patterns it participates in. The catalog browser (`catalog/catalog-browser.html`)
can filter by investigation pattern using the **Investigation** chip row.

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
10. [Outbound Campaign Investigation](#10-outbound-campaign-investigation)
11. [Architect Flow / IVR Investigation](#11-architect-flow--ivr-investigation)
12. [WFM Schedule Adherence Investigation](#12-wfm-schedule-adherence-investigation)
13. [API Governance & Security Audit](#13-api-governance--security-audit)
14. [Dataset Combination Reference Matrix](#14-dataset-combination-reference-matrix)

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
| 4 | `conversations.get.recordings` | `conversationId` | Recording download URLs and annotation metadata |
| 5 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by IVR/Architect flows (account numbers, intent, escalation flags) |
| 6 | `conversations.search.participant.attributes` | `conversationId` | Participant-level attributes (IVR variables, data action outcomes, flow-set values) |
| 7 | `quality.get.evaluations.query` | `conversationId` | QM evaluation scores, form used, evaluator, calibration status |
| 8 | `quality.get.published.evaluation.forms` | `formId` from step 7 | Evaluation form definition — question text, category weights (join to interpret scores) |
| 9 | `quality.get.surveys` | `conversationId` | Post-call CSAT/NPS survey result if survey was triggered |
| 10 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace: INVITE, 200 OK, BYE, re-INVITE, codec negotiation |
| 11 *(voice only)* | `stations.get.stations` | `stationId` from step 1 | Station registration info for the agent's device — hardware model, IP, registration status |
| 12 *(voice only — edge logs)* | `telephony.create.edge.logs.job` | `edgeId` from step 10 | Initiate Edge log collection for the conversation window |
| 13 *(voice only — edge logs)* | `telephony.get.edge.logs.job` | `jobId` from step 12 | Poll log job status until FULFILLED |
| 14 *(voice only — edge logs)* | `telephony.request.edge.logs.job.upload` | `jobId` from step 12 | Request upload of selected log files for download |
| 15 *(STA enabled)* | `conversations.get.speech.text.analytics` | `conversationId` | Sentiment score, detected topics, STA coverage summary |
| 16 *(STA enabled)* | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Sentiment timeline: per-utterance scores, agent vs customer breakdown |
| 17 *(STA enabled)* | `speechandtextanalytics.get.topics` | `topicId` from step 15 | Topic definitions — label, category, and associated phrases for IDs returned in step 15 |
| 18 *(transcription enabled)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId` + `communicationId` | Transcript download URL per communication leg |
| 19 *(agent assist enabled)* | `conversations.get.conversation.suggestions` | `conversationId` | Agent assist suggestions surfaced during the call |
| 20 *(agent assist enabled)* | `conversations.get.conversation.suggestion.detail` | `suggestionId` from step 19 | Full suggestion content, confidence score, article source |

### Key Joins

```
conversations.get.conversation.object.conversationId
  → analytics.get.single.conversation.analytics.conversationId (segment overlay)
  → conversations.get.conversation.recording.metadata.conversationId
  → telephony.get.sip.messages.for.conversation.conversationId (voice only)
  → quality.get.evaluations.query[].conversationId (left join — evaluations may not exist)

analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
  → speechandtextanalytics.get.conversation.communication.transcripturl.communicationId

quality.get.evaluations.query[].evaluationForm.id
  → quality.get.published.evaluation.forms[].id (form definition for score context)

conversations.get.conversation.object.participants[].stationId
  → stations.get.stations[].id (station registration detail)

conversations.get.speech.text.analytics.topics[].id
  → speechandtextanalytics.get.topics[].id (topic label resolution)
```

### Analytical Questions Answered

- What was the full call flow? (IVR → ACD → agent → hold → ACW)
- How long did the customer wait before an agent answered?
- Was the call transferred? How many times? What queue received the transfer?
- Was a recording made? Does it still exist? What is the download URL?
- Did the SIP trunk establish media correctly? (from SIP trace)
- What station/device was the agent on? Is it registered correctly?
- Was the agent rated? What was the QM score? Which form was used?
- Was the customer surveyed? What was the CSAT result?
- What intent/attributes did the IVR capture before routing?
- What sentiment trajectory did the conversation follow? (STA)
- Did agent assist surface relevant suggestions? Were they accurate?

### Voice Engineer Notes

Step 10 (SIP trace) is the definitive source for:
- Call setup failures (no 200 OK, 486 Busy, 503 Service Unavailable)
- One-way audio (media IP mismatch in SDP)
- Premature disconnection (BYE before expected, no 200 OK to BYE)
- Codec negotiation failures

Steps 12–14 (Edge log job) should be run when the SIP trace alone is insufficient:
specifically when the call shows SIP 4xx/5xx without clear cause, or when there is
audio corruption not explained by codec negotiation. The Edge log contains raw
SIP state machine events and media-plane diagnostics not present in the SIP trace.

Step 11 (station lookup) resolves the agent's device for any station-reported errors
in the SIP trace — if the remote SDP IP is unexpected, the station record will show
whether the device is behind NAT or registered to the wrong region.

The `telephony.get.edge.performance.metrics` dataset (`GET /api/v2/telephony/providers/edges/{edgeId}/metrics`)
should be pulled for the Edge appliance that handled the call if CPU, memory, or error counters suggest
resource pressure during the conversation window.

### BYOI Indicator

If `conversations.get.conversation.object` returns a non-null `externalTag` or `externalConversationId`,
the call was injected via the BYOI integration (`POST /api/v2/conversations/providers/{providerId}/calls`).
Custom attributes in step 5 will contain the provider's context (CRM case ID, external call ID).
The SIP trace (step 10) will reflect the provider's SIP-to-SIP handoff, not an inbound PSTN leg.

### Agent Assist Assessment (Steps 19–20)

When evaluating AI-augmented calls, compare `quality.get.evaluations.query` scores against
`conversations.get.conversation.suggestions` coverage. Calls where suggestions were surfaced
can be correlated with QM score outcomes to assess AI-assist effectiveness over time.

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
| 3 | `routing.get.all.wrapup.codes` | — | Global wrapup label fallback for codes not returned in step 2 |
| 4 | `analytics-conversation-details-query` (queueId filter) | `queueId` | Every conversation that touched this queue in the window, with participant/segment detail |
| 5 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Aggregate: nConnected, tHandle, tTalk, tAcw, tAnswered, tHeld, nOffered, nOutbound |
| 6 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon count: nAbandoned, tAbandon, tShortAbandon |
| 7 | `analytics.query.queue.aggregates.service.level` | `queueId` | SLA achievement: nAnsweredIn20/30/60, oServiceLevel, oServiceTarget, nOverSla |
| 8 | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer analysis: nTransferred, nBlindTransferred, nConsultTransferred |
| 9 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` + wrapUpCode | Wrapup code frequencies (join step 2/3 for labels) |
| 10 | `routing-queue-members` | `queueId` | Current membership roster with routing status and presence |
| 11 | `analytics.query.user.observations.real.time.status` | `userId` from step 10 | Real-time routing status for each member — IDLE, INTERACTING, OFF_QUEUE |
| 12 | `quality.get.evaluations.query` (queueId filter) | `conversationId` | QM evaluation coverage and scores for conversations in this queue |
| 13 | `speechandtextanalytics.get.topics` | `topicId` from step 4 | Topic definition labels for any STA topic IDs appearing in conversation details |
| 14 | `conversations.search.customattributes` (conversationId list) | `conversationId` | Bulk custom attribute enrichment for conversations in the queue window |

### Key Joins

```
routing.get.single.queue.config.id
  → analytics.query.conversation.aggregates.*.queueId (aggregate overlay)
  → routing-queue-members.queueId (who was staffed)

analytics.query.conversation.aggregates.wrapup.distribution.wrapUpCode
  → routing.get.queue.wrapup.codes.by.queue.id (label resolution)
  → routing.get.all.wrapup.codes.id (fallback label)

analytics-conversation-details-query[].conversationId
  → quality.get.evaluations.query[].conversationId (left join — not all conversations are evaluated)

routing-queue-members[].id
  → analytics.query.user.observations.real.time.status[].userId
```

### Analytical Questions Answered

- What was the offered/connected/abandoned volume for this queue?
- Did the queue meet its SLA target? In which hourly intervals did it miss?
- What percentage of conversations were transferred? Where did they go?
- What wrapup codes dominated, and what do they mean?
- Who were the active agents? What was their routing status during the window?
- How many conversations were quality-reviewed? What was the average score?
- What topics did STA detect across conversations in this queue?
- What custom attributes did IVR/Architect set for conversations entering this queue?

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
| 4 | `routing.get.skill.groups` | — | Skill group definitions — cross-queue agent capability groupings; join on `userId` membership to understand which skill groups this division's agents belong to |
| 5 | `analytics.query.conversation.aggregates.agent.performance` (divisionId filter) | `userId` | Per-agent: nConnected, tHandle, tTalk, tAcw, tAnswered |
| 6 | `analytics.query.user.aggregates.login.activity` (divisionId filter) | `userId` | Per-agent time-in-state: tAgentRoutingStatus, tSystemPresence, tOrganizationPresence |
| 7 | `analytics.query.user.details.activity.report` (userId list) | `userId` | Login/logout/on-queue presence event timeline per agent |
| 8 | `quality.get.agents.activity` | `userId` | QM evaluation counts, highest/average/lowest scores per agent |
| 9 | `coaching.get.appointments` | `userId` | Coaching sessions scheduled/completed for agents in the window |
| 10 | `analytics.query.conversation.aggregates.wrapup.distribution` (divisionId filter) | `queueId` | Wrapup code distribution across all queues in the division |
| 11 *(WFM licensed)* | `workforce.get.management.units` | — | Management unit(s) covering this division's agents — required seed for adherence |
| 12 *(WFM licensed)* | `workforce.get.management.unit.users` | `managementUnitId` from step 11 | Agent roster cross-reference to confirm WFM ↔ division alignment |
| 13 *(WFM licensed)* | `workforce.get.management.unit.adherence` | `managementUnitId` from step 11 | Scheduled vs. actual state per agent — adherence score and variance |

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
  → workforce.get.management.unit.users[].user.id (WFM cross-reference)

workforce.get.management.unit.users[].user.id
  → workforce.get.management.unit.adherence[].user.id

routing.get.skill.groups[].members[].userId
  → users.division.analysis.get.users.with.division.info[].id (skill group coverage per division agent)
```

### Analytical Questions Answered

- How many agents are in this division and who are they?
- What queues does this division own?
- Which agents belong to which skill groups — and do skill groups span queue boundaries?
- Which agents handled the most volume? Which had the highest AHT?
- Which agents spent the most time off-queue or in non-productive states?
- Which agents have been evaluated? Who has the highest/lowest scores?
- Which agents have received recent coaching? Is coaching correlated with score improvement?
- *(WFM)* Which agents had the best/worst schedule adherence this period?

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
| `routing.get.all.wrapup.codes` | — | Global wrapup label resolution |

#### Layer 3 — Workforce
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.user.aggregates.login.activity` | `userId`, daily | tAgentRoutingStatus: available, busy, on-queue time per agent |
| `analytics.query.user.aggregates.performance.metrics` | `userId`, daily | nConnected, tHandle (avg) per agent — productivity comparison |
| `workforce.get.business.units` | — | WFM business unit hierarchy (seed for adherence rollup) |
| `workforce.get.management.units` | `businessUnitId` | Management units — scheduling team groupings |
| `workforce.get.management.unit.adherence` | `managementUnitId`, daily | Schedule adherence rates: scheduled vs. actual state, variance per agent |

#### Layer 4 — Quality & Voice-of-Customer
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `quality.get.agents.activity` | `userId` | Evaluation coverage rate, average score, score distribution |
| `quality.get.published.evaluation.forms` | `formId` | Form definitions — maps form IDs in evaluation results to readable names and category weights |
| `quality.get.surveys` | `conversationId` (aggregate) | CSAT/NPS: response rate, average score |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | Speech analytics coverage: nSpeechTextAnalyzedConversations, oSentimentScore |
| `speechandtextanalytics.get.topics` | — | Topic definitions — label reference for topic frequency analytics |
| `analytics.query.flow.aggregates.execution.metrics` | `flowId`, daily | IVR containment: nFlow, nFlowOutcome, nFlowOutcomeFailed — % of calls resolved in IVR vs. escalated |

#### Layer 5 — Infrastructure Health (optional, voice-focused)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `telephony.get.trunk.metrics.summary` | — | SIP trunk utilisation, errors |
| `telephony.get.edges` | `edgeId` | Edge registration status |
| `alerting.get.alerts` | — | Currently firing threshold alerts |
| `alerting.get.rules` | — | Configured alert thresholds — context for interpreting active alerts |
| `analytics.get.reporting.exports` | — | Scheduled export jobs — avoid duplicating reports already being auto-delivered |

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
  - IVR containment: nFlowOutcome / nFlow × 100 (where outcome ≠ failed/escalated)
  - Schedule adherence: from workforce.get.management.unit.adherence

Trend views (daily granularity):
  - Volume by day with channel mix
  - AHT trend by queue
  - Abandon rate trend by queue
  - SLA achievement heatmap by queue × day
  - IVR containment trend by flow
  - Adherence rate trend by management unit
```

### Key Joins for Executive Reporting

```
routing-queues[].id
  → analytics.query.conversation.aggregates.*.results[].group.queueId
  → routing.get.all.wrapup.codes[].id (wrapup label resolution)
  → quality.get.agents.activity (left join via queue membership)

analytics.query.conversation.aggregates.wrapup.distribution[].group.wrapUpCode
  → routing.get.all.wrapup.codes[].id (global wrapup code labels)

quality.get.evaluations.query[].evaluationForm.id
  → quality.get.published.evaluation.forms[].id (form name for score grouping)

workforce.get.business.units[].id
  → workforce.get.management.units[].businessUnit.id
  → workforce.get.management.unit.adherence[].managementUnit.id
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
| 8 | `conversations.get.active.calls` | — | Active voice calls across the organisation — live inbound/outbound voice snapshot |
| 9 | `conversations.get.active.conversations` | — | All active conversations (all media types) — overall live interaction count |
| 10 | `conversations.get.active.chats` | — | Active chat conversations |
| 11 | `conversations.get.active.emails` | — | Active email conversations |
| 12 | `conversations.get.active.callbacks` | — | Active callback conversations awaiting agent connection |
| 13 | `stations.get.stations` | — | Station registration health — unregistered or error-state phones visible in real-time |
| 14 *(telephony NOC)* | `telephony.get.trunks` | — | SIP trunk inventory with registration status |
| 15 *(telephony NOC)* | `telephony.get.trunk.metrics.summary` | — | Trunk utilisation and error counters |
| 16 *(telephony NOC)* | `telephony.get.edges` | — | Edge registration list — any Edge offline is a service-impacting event |
| 17 *(telephony NOC)* | `telephony.get.edge.performance.metrics` | One Edge | CPU, memory, active call count on specific Edge |
| 18 | `alerting.get.alerts` | — | Currently firing threshold alerts — active alarm list |
| 19 | `alerting.get.rules` | — | Alert rule definitions — threshold context for interpreting active alerts |

### Polling Note

Real-time datasets (`analytics.query.queue.observations.real.time.stats`,
`analytics.query.conversation.activity.real.time`, `analytics.query.user.observations.real.time.status`)
do not accept `interval` parameters — they reflect the current state as of the API call. These
should be polled at the rate appropriate for the display (typically 10–30 seconds for a wall board).

The `analytics.get.agent.active.status` endpoint returns a single agent's live state and is
intended for targeted drilldown (supervisor clicks on an agent in the wall board).

The `conversations.get.active.*` endpoints (steps 8–12) return a live snapshot of in-flight
interactions and are suitable for an operations overview tile showing current load by media type.
They differ from the analytics observation endpoints in that they return conversation objects
(with participant detail) rather than metric aggregates.

The station health snapshot (step 13) is most useful during an incident — unregistered stations
produce no calls, and a pattern of station failures often precedes trunk or Edge degradation.

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
- `conversations.get.recordings` — recording download URLs
- `quality.get.evaluations.query` — evaluations proceed normally
- `telephony.get.sip.messages.for.conversation` — reflects the BYOI SIP-to-SIP handoff, not a PSTN leg

### Embeddable Framework Conversations

Conversations visible to agents via the Embeddable Framework return the same object shape as
`conversations.get.conversation.object`. The condensed view used by the embedded client includes:
`participants[].purpose`, `participants[].state`, `participants[].calls[].state`,
`participants[].calls[].muted`, `participants[].calls[].held`. These fields are present in the
full object returned by the dataset and need no special handling.

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
| staTopics | `speechandtextanalytics.get.topics` | `topicId` | Topic label resolution for STA topic IDs (STA enabled only) |
| customAttributes | `conversations.get.conversation.customattributes` | `conversationId` | IVR/Architect custom attribute payload |
| participantAttributes | `conversations.search.participant.attributes` | `conversationId` | Participant-level flow variables |
| transcriptUrl | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcript download URL (transcription enabled only) |
| recordings | `conversations.get.recordings` | `conversationId` | Recording download URLs and annotations |
| evaluationForm | `quality.get.published.evaluation.forms` | `formId` | Evaluation form definition (join to quality.get.evaluations.query[].evaluationForm.id) |
| agentAssist | `conversations.get.conversation.suggestions` | `conversationId` | Agent assist suggestions (agent assist enabled only) |

**Conditional steps:** `sipTrace` runs only when `conversations.get.conversation.object.participants[].calls` is
non-empty (voice conversation). `sentimentTimeline` and `staTopics` run only when `conversations.get.speech.text.analytics`
returns `speechAndTextAnalyticsConversation.analysisStatus = "Success"`.

---

## 9. Queue Investigation Extensions (Release 1.3)

The existing Queue Investigation (`Get-GenesysQueueInvestigation`) covers 6 steps. These additions
complete the picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| queueConfig | `routing.get.single.queue.config` | `queueId` | Full queue config (replaces/enriches the routing-queues list step) |
| wrapupLabels | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Human-readable labels for the wrapup distribution step |
| wrapupFallback | `routing.get.all.wrapup.codes` | — | Global wrapup code labels for any codes not in queue-specific list |
| transfers | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer rate and type breakdown |
| wrapupDistribution | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Wrapup code frequencies (join wrapupLabels for labels) |
| conversationDetail | `analytics-conversation-details-query` (queueId filter) | `conversationId` | Individual conversations for case-level review |
| topicLabels | `speechandtextanalytics.get.topics` | `topicId` | Topic label resolution for STA topic IDs in conversation detail |
| memberStatus | `analytics.query.user.observations.real.time.status` | `userId` | Real-time status of each queue member |

---

## 10. Outbound Campaign Investigation

**Subject:** One `campaignId` + time window  
**Use case:** An outbound operations manager needs to diagnose a dialing campaign — is it pacing
correctly, what is the answer rate, where did contacts go, what dispositions dominate, and
have recent configuration changes affected performance?

**Core question:** *Is this campaign running correctly and what did it produce?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Campaign config: dialing mode, queue, caller ID, abandon threshold, status |
| 2 | `outbound.get.contact.lists` | `contactListId` from step 1 | Contact list size and column definitions |
| 3 | `routing.get.single.queue.config` | `queueId` from step 1 | Answer-handling queue configuration |
| 4 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Live pacing health: dial rate, utilisation, abandon indicators |
| 5 | `outbound.get.events` | `campaignId` | Dialer events: call dispositions, contact attempts, abandon events |
| 6 | `analytics-conversation-details-query` (campaignId filter) | `campaignId` | All conversations generated by this campaign — connected, abandoned, voicemail |
| 7 | `audit-logs` (EntityType=campaign, EntityId=`campaignId`) | `campaignId` | Recent configuration changes affecting the campaign |
| 8 *(outbound messaging)* | `outbound.get.messaging.campaigns` | `campaignId` | Digital outbound campaign config (SMS/email) if a messaging campaign |

### Key Joins

```
outbound.get.campaigns[].id
  → outbound.get.contact.lists[].id (contact list cross-reference)
  → routing.get.single.queue.config[].id (answer queue)
  → outbound.get.campaign.diagnostics.summary.campaignId
  → outbound.get.events[].campaign.id

analytics-conversation-details-query[].conversationId
  → outbound.get.events[].conversationId (disposition per conversation)
```

### Analytical Questions Answered

- Is the campaign currently running and at what pacing level?
- What is the answer rate vs. abandoned/voicemail rate?
- How does the current abandon rate compare to the configured TCPA threshold?
- What dispositions dominated — answered, no-answer, answering machine, busy?
- What configuration changes were made recently that might explain a performance shift?
- Are connected calls routing correctly to the configured queue?

### Abandon Rate Note (Regulatory)

Outbound abandon rate is a regulated KPI in many jurisdictions (TCPA: ≤3%, Ofcom: ≤3%).
Compare `outbound.get.campaign.diagnostics.summary` live abandon rate against the
`outbound.get.campaigns[].abandonRate` configured threshold. If the live rate is approaching
the threshold, pacing or list quality investigation is required before continuing the campaign.

---

## 11. Architect Flow / IVR Investigation

**Subject:** One `flowId` (or all flows) + time window  
**Use case:** A voice engineer or IVR designer needs to understand how an Architect flow is
performing — how many calls entered, how many were self-served (contained), where they exited
(milestone hits), and which conversations experienced flow failures. This investigation links
IVR performance to contact centre load: failed containment directly increases queue volume.

**Core question:** *How is this Architect flow performing, and what is its containment rate?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | — | Flow catalog: all IVR, inbound-call, in-queue, bot, and outbound flows with IDs and current publish status |
| 2 | `flows.get.flow.milestones` | — | Milestone definitions — named checkpoints within flows used for analytics tracking |
| 3 | `flows.get.flow.outcomes` | — | Outcome definitions — configurable labels classifying flow exits (Self-Service, Transfer, Abandon, Failure) |
| 4 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Flow execution aggregate: nFlow (entered), nFlowOutcome (exited with outcome), nFlowOutcomeFailed, nFlowMilestone by flowId |
| 5 | `analytics.query.flow.observations` | — | Live flows currently executing — how many calls are in this flow right now |
| 6 | `analytics-conversation-details-query` (flowId filter) | `conversationId` | Individual conversations that traversed this flow — enables case-by-case outcome review |
| 7 | `analytics.get.single.conversation.analytics` | `conversationId` from step 6 | Per-segment timing — IVR dwell time, when flow exited to queue |

### Key Joins

```
flows.get.all.flows[].id
  → analytics.query.flow.aggregates.execution.metrics[].group.flowId

flows.get.flow.milestones[].id
  → analytics.query.flow.aggregates.execution.metrics[].group.flowMilestoneId

flows.get.flow.outcomes[].id
  → analytics.query.flow.aggregates.execution.metrics[].group.flowOutcomeId

analytics-conversation-details-query[].conversationId
  → analytics.get.single.conversation.analytics.conversationId (segment timing overlay)
```

### Analytical Questions Answered

- How many calls entered this flow and what fraction were self-served?
- Which milestones are being hit — and which are never reached (broken menu options)?
- What flow outcome is dominant — transfer, self-service, or failure?
- Which conversations failed the flow? Are they concentrated in a time window (incident)?
- How long do callers spend in the IVR before reaching an agent? (IVR dwell from segment timing)
- Is there a live incident? How many calls are currently in this flow?

### Containment Rate Formula

```
Containment rate = nFlowOutcome (non-transfer, non-failure) / nFlow × 100

Escalation rate  = nFlowOutcome (transfer to queue) / nFlow × 100

Failure rate     = nFlowOutcomeFailed / nFlow × 100
```

`flows.get.flow.outcomes` provides the outcome definitions — map `flowOutcomeId` to
outcome category (success/transfer/failure) before computing these ratios.

### Executive Value

IVR containment is an executive-level KPI: higher containment lowers per-call cost. The
`analytics.query.flow.aggregates.execution.metrics` dataset, grouped by `flowId` with daily
granularity, provides the trend data for executive dashboards (see Layer 4 in
[Section 4 — Executive Reporting Rollup](#4-executive-reporting-rollup)).

---

## 12. WFM Schedule Adherence Investigation

**Subject:** One WFM business unit or management unit + reporting window  
**Use case:** A workforce management analyst or operations director needs to understand whether
agents are following their scheduled times — on-queue when scheduled, off-queue when not. Poor
adherence erodes service level and inflates staffing costs. This investigation bridges the gap
between WFM scheduling data and ACD activity data.

**Core question:** *Are agents adhering to their schedules, and where are the gaps?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.business.units` | — | WFM business unit list — top-level scheduling container |
| 2 | `workforce.get.management.units` | `businessUnitId` from step 1 | Management units (team groupings) within the business unit |
| 3 | `workforce.get.management.unit.users` | `managementUnitId` from step 2 | Agent roster for each management unit with user IDs |
| 4 | `workforce.get.management.unit.adherence` | `managementUnitId` from step 2 | Scheduled vs. actual state per agent — adherence score and variance per interval |
| 5 | `users.division.analysis.get.users.with.division.info` | `userId` from step 3 | Division assignment for each agent — links WFM teams to Genesys divisions |
| 6 | `analytics.query.user.aggregates.login.activity` (userId list) | `userId` | ACD actual time-in-state: on-queue, off-queue, busy, available — corroborates adherence data |
| 7 | `analytics.query.conversation.aggregates.agent.performance` (userId list) | `userId` | Actual productivity: conversations handled, AHT — what agents produced during scheduled time |

### Key Joins

```
workforce.get.business.units[].id
  → workforce.get.management.units[].businessUnit.id

workforce.get.management.units[].id
  → workforce.get.management.unit.users[].managementUnit.id
  → workforce.get.management.unit.adherence[].managementUnit.id

workforce.get.management.unit.users[].user.id
  → workforce.get.management.unit.adherence[].user.id (adherence per agent)
  → analytics.query.user.aggregates.login.activity[].userId (ACD corroboration)
  → analytics.query.conversation.aggregates.agent.performance[].userId
  → users.division.analysis.get.users.with.division.info[].id (division cross-reference)
```

### Analytical Questions Answered

- What is the overall adherence rate for each management unit this period?
- Which agents had the lowest adherence scores?
- Is poor adherence correlated with lower productivity (fewer conversations handled)?
- Do adherence patterns vary by day of week, shift type, or queue assignment?
- Which management units are most affected — by division, by supervisor group?

### Adherence as Division Investigation Extension

When running a Division Investigation (Section 3), steps 11–13 connect WFM adherence data
to the division's agent roster via the join:

```
users.division.analysis.get.users.with.division.info[].id
  ↔ workforce.get.management.unit.users[].user.id
```

If agents in a division span multiple management units, fan out step 4 once per management unit.

---

## 13. API Governance & Security Audit

**Subject:** Organisation or specific OAuth client  
**Use case:** A platform administrator or security team needs to audit API usage — which OAuth
clients are making the most calls, whether rate limits are being hit, which users have granted
authorisations, and whether there are anomalous usage patterns. This investigation is not
contact-centre operational but is critical for platform health and compliance.

**Core question:** *Who is calling the API, how often, and is anything misbehaving?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `oauth.get.clients` | — | All configured OAuth client applications: name, grant type, scope, created date |
| 2 | `oauth.post.client.usage.query` | — | Submit usage analytics job for a specified client and window |
| 3 | `oauth.get.client.usage.query.results` | `jobId` from step 2 | Usage result: call count, latency, error rate by endpoint per client |
| 4 | `usage.get.api.usage.by.client` | `clientId` | API call volume by OAuth client — top callers |
| 5 | `usage.get.api.usage.by.user` | `userId` | API call volume attributed to specific users |
| 6 | `usage.get.api.usage.organization.summary` | — | Organisation-wide API usage summary: total calls, error rate |
| 7 | `analytics.query.rate.limit.aggregates` | — | Rate limit events: nError, nOverLimit by time window — identifies abusive or misconfigured clients |
| 8 | `audit-logs` (EntityType=OAuthClient) | `clientId` | Recent changes to OAuth client configuration (scope changes, secret rotation) |
| 9 | `oauth.get.authorizations` | — | Active authorization grants: which users have authorised which clients |
| 10 | `authorization.get.roles` | — | Role definitions — context for evaluating whether client scopes are appropriately restricted |
| 11 | `organization.get.organization.limits` | — | Platform limits: max API calls/min, max concurrent sessions |

### Key Joins

```
oauth.get.clients[].id
  → oauth.post.client.usage.query + oauth.get.client.usage.query.results (two-step: submit then poll)
  → usage.get.api.usage.by.client[].client.id
  → audit-logs[].entity.id (where entityType = OAuthClient)
  → oauth.get.authorizations[].client.id

analytics.query.rate.limit.aggregates[].group.clientId
  → oauth.get.clients[].id (client name resolution)
```

### Analytical Questions Answered

- Which OAuth clients are calling the most endpoints and at what volume?
- Is any client hitting rate limits repeatedly? Which endpoints are affected?
- Have any client configurations changed recently (scope expansion, new secrets)?
- Which users have granted third-party authorisations? Are any grants unexpected?
- Are organisation-wide API limits being approached?

### Trigger Conditions

This investigation should be run when:
- A service degradation coincides with rate-limit alert events
- A new integration is deployed and API baseline needs to be established
- Quarterly access review requires OAuth client audit
- `alerting.get.alerts` returns an active rate-limit threshold alert

---

## 14. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = primary/always used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation | Queue | Division | Executive | Real-Time | Agent | Campaign | Flow/IVR | WFM | API Gov |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | ○ | | |
| `analytics-conversation-details-query` | ● | ● | | | | ● | ● | ● | | |
| `analytics-conversation-details` | ○ | ● | | | | ● | | | | |
| `analytics-conversation-timeline-analysis` | ○ | | | | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | |
| `conversations.get.recordings` | ● | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | | |
| `conversations.search.customattributes` | ● | ○ | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | | |
| `quality.get.published.evaluation.forms` | ● | | | ● | | | | | | |
| `quality.get.surveys` | ● | | | ● | | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | |
| `speechandtextanalytics.get.topics` | ○ | ○ | | ● | | | | | | |
| `conversations.get.conversation.suggestions` | ○ | | | | | | | | | |
| `conversations.get.conversation.suggestion.detail` | ○ | | | | | | | | | |
| `stations.get.stations` | ○ | | | | ● | | | | | |
| `telephony.create.edge.logs.job` | ○ | | | | | | | | | |
| `telephony.get.edge.logs.job` | ○ | | | | | | | | | |
| `telephony.request.edge.logs.job.upload` | ○ | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | ● | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | |
| `routing.get.all.wrapup.codes` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | |
| `analytics.query.user.observations.real.time.status` | | ● | | | ● | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | |
| `authorization.get.all.divisions` | | | | | | | | | ● | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | ● | |
| `routing.get.skill.groups` | | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | ● | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | ● | |
| `analytics.query.user.aggregates.performance.metrics` | | | | ● | | ● | | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | |
| `coaching.get.appointments` | | | ● | | | ○ | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | ● | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | ● | | | | ● | | |
| `flows.get.all.flows` | | | | | | | | ● | | |
| `flows.get.flow.milestones` | | | | | | | | ● | | |
| `flows.get.flow.outcomes` | | | | | | | | ● | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | |
| `conversations.get.active.calls` | | | | | ● | | | | | |
| `conversations.get.active.conversations` | | | | | ● | | | | | |
| `conversations.get.active.chats` | | | | | ● | | | | | |
| `conversations.get.active.emails` | | | | | ● | | | | | |
| `conversations.get.active.callbacks` | | | | | ● | | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | |
| `telephony.get.trunks` | | | | | ● | | | | | |
| `telephony.get.edges` | | | | ○ | ● | | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | |
| `alerting.get.rules` | | | | ○ | ● | | | | | |
| `analytics.get.reporting.exports` | | | | ● | | | | | | |
| `outbound.get.campaigns` | | | | | | | ● | | | |
| `outbound.get.contact.lists` | | | | | | | ● | | | |
| `outbound.get.events` | | | | | | | ● | | | |
| `outbound.get.campaign.diagnostics.summary` | | | | | | | ● | | | |
| `outbound.get.messaging.campaigns` | | | | | | | ○ | | | |
| `workforce.get.business.units` | | | | ● | | | | | ● | |
| `workforce.get.management.units` | | | ○ | | | | | | ● | |
| `workforce.get.management.unit.users` | | | ○ | | | | | | ● | |
| `workforce.get.management.unit.adherence` | | | ○ | ● | | | | | ● | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | |
| `routing.get.all.routing.skills` | | | | | | ● | | | | |
| `routing-queues` | | | | ● | | ● | | | | |
| `users` | | | | ● | | ● | | | | |
| `audit-logs` | | | | | | ● | ● | | | ● |
| `oauth.get.clients` | | | | | | | | | | ● |
| `oauth.post.client.usage.query` | | | | | | | | | | ● |
| `oauth.get.client.usage.query.results` | | | | | | | | | | ● |
| `oauth.get.authorizations` | | | | | | | | | | ● |
| `usage.get.api.usage.by.client` | | | | | | | | | | ● |
| `usage.get.api.usage.by.user` | | | | | | | | | | ● |
| `usage.get.api.usage.organization.summary` | | | | | | | | | | ● |
| `analytics.query.rate.limit.aggregates` | | | | | | | | | | ● |
| `authorization.get.roles` | | | | | | | | | | ● |
| `organization.get.organization.limits` | | | | | | | | | | ● |

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
| `nBlindTransferred` | Blind (no-consult) transfers | Transfer type breakdown |
| `nConsultTransferred` | Consult transfers | Transfer type breakdown |
| `oServiceLevel` | Current SLA percentage | Real-time SLA |
| `nOverSla` | Conversations that exceeded SLA threshold | SLA misses |
| `oInteracting` | Agents currently on interactions | Active agents |
| `oWaiting` | Interactions waiting in queue | Queue depth |
| `oLongestWaiting` | Seconds the longest-waiting customer has been waiting | Worst-case wait |
| `tAgentRoutingStatus` | Time in each routing status | On-queue vs off-queue time |
| `tSystemPresence` | Time in each system presence | Available, Busy, Away, Offline |
| `oSentimentScore` | Aggregate sentiment score (STA) | Voice-of-customer indicator |
| `nSpeechTextAnalyzedConversations` | Conversations with STA analysis | STA coverage |
| `nFlow` | Conversations that entered an Architect flow | IVR volume denominator |
| `nFlowOutcome` | Conversations that exited a flow with a defined outcome | Containment/escalation count |
| `nFlowOutcomeFailed` | Conversations that exited a flow with a failure outcome | IVR failure rate |
| `nFlowMilestone` | Flow milestone events hit | Milestone reach rate |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All dataset entries carry an `investigations` array identifying which patterns they participate in.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
