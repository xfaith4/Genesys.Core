# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-10  
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
10. [Dataset Combination Reference Matrix](#10-dataset-combination-reference-matrix)

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
| `quality.get.surveys` | `conversationId` (aggregate) | CSAT/NPS: response rate, average score |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | Speech analytics coverage: nSpeechTextAnalyzedConversations, oSentimentScore |

#### Layer 5 — Infrastructure Health (optional, voice-focused)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `telephony.get.trunk.metrics.summary` | — | SIP trunk utilisation, errors |
| `telephony.get.edges` | `edgeId` | Edge registration status |
| `alerting.get.alerts` | — | Currently firing threshold alerts |

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

### Polling Note

Real-time datasets (`analytics.query.queue.observations.real.time.stats`,
`analytics.query.conversation.activity.real.time`, `analytics.query.user.observations.real.time.status`)
do not accept `interval` parameters — they reflect the current state as of the API call. These
should be polled at the rate appropriate for the display (typically 10–30 seconds for a wall board).

The `analytics.get.agent.active.status` endpoint returns a single agent's live state and is
intended for targeted drilldown (supervisor clicks on an agent in the wall board).

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

## 10. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | |
| `quality.get.surveys` | ● | | | ● | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | |
| `routing.get.single.queue.config` | | ● | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | |
| `routing-queue-members` | | ● | | | | |
| `authorization.get.single.division` | | | ● | | | |
| `authorization.list.division.queues` | | | ● | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● |
| `analytics.query.user.details.activity.report` | | | ● | | | ● |
| `quality.get.agents.activity` | | | ● | ● | | ○ |
| `coaching.get.appointments` | | | ● | | | ○ |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ |
| `users.get.agent.active.conversations` | | | | | ○ | ○ |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ |
| `analytics.query.flow.observations` | | | | | ● | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | |
| `alerting.get.alerts` | | | | ○ | ● | |
| `users.get.user.details.with.full.expansion` | | | | | | ● |
| `users.get.user.routing.skills` | | | | | | ● |
| `users.get.user.queue.memberships` | | | | | | ● |
| `users.get.bulk.user.presences` | | | | | | ● |
| `routing.get.user.utilization` | | | | | | ○ |
| `audit-logs` | | | | | | ● |
| `conversations.get.conversation.ai.summaries` | ● | | | | | ○ |
| `conversations.get.conversation.secureattributes` | ○ | | | | | |
| `conversations.get.conversation.recording.annotations` | ○ | | | | | |
| `quality.get.calibrations` | | | | | | |
| `quality.get.evaluators.activity` | | | | ○ | | |
| `analytics.query.evaluations.aggregates` | | ● | ● | ● | | |
| `analytics.query.surveys.aggregates` | | ● | | ● | | |
| `analytics.query.bot.aggregates` | | | | ● | | |
| `analytics.query.flow.execution.aggregates` | | | | ● | | |
| `analytics.query.resolutions.aggregates` | | ● | | ● | | |
| `analytics.query.summaries.aggregates` | | | | ● | | |
| `analytics.query.agentcopilot.aggregates` | | | ● | ● | | ○ |
| `telephony.get.sip.trace.metadata` | ○ | | | | | |
| `telephony.request.sip.pcap.download` | ○ | | | | | |
| `telephony.get.sip.pcap.download.url` | ○ | | | | | |
| `telephony.get.edge.version.report` | | | | ○ | | |
| `telephony.get.expired.edges` | | | | ○ | ● | |
| `telephony.get.edge.diagnostic.nslookup` | ○ | | | | ○ | |
| `telephony.get.edge.diagnostic.tracepath` | ○ | | | | ○ | |
| `speechandtextanalytics.get.conversation.categories` | ● | | | | | |
| `speechandtextanalytics.search.transcripts` | ○ | | | | | |
| `externalcontacts.get.contact` | ○ | | | | | |
| `externalcontacts.get.contact.notes` | ○ | | | | | |
| `externalcontacts.get.contact.journey.sessions` | ○ | | | | | |
| `journey.get.session.events` | ○ | | | | | |
| `workforce.historical.adherence.query` | | | ● | | | |
| `workforce.get.agent.schedule.search` | | | ● | | | |
| `workforce.get.intraday` | | | | ○ | ○ | |
| `users.get.user.station` | | | | | | ● |
| `users.get.user.routing.languages` | | | | | | ● |
| `analytics.query.agent.status.counts` | | | | | ● | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | |

---

## 11. Voice Engineer Infrastructure Health Investigation

**Subject:** Organisation-wide or Edge-specific  
**Use case:** A voice engineer receives reports of intermittent call quality issues, failed call set-ups, or audio degradation and needs to determine whether the problem is an Edge appliance, a SIP trunk, or a specific site. This is infrastructure-first, not conversation-first.

**Core question:** *Is the problem the Edge, the trunk, the network path, or the call configuration?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `telephony.get.edges` | seed | All Edge appliances with registration status, version, site assignment |
| 2 | `telephony.get.expired.edges` | seed | Edges that are 4+ firmware versions behind — primary upgrade-risk flag |
| 3 | `telephony.get.edge.version.report` | seed | Full firmware version inventory across all edges |
| 4 | `telephony.get.edge.performance.metrics` | `edgeId` | CPU, memory, active call count on any Edge under suspicion |
| 5 | `telephony.get.trunks` | seed | All SIP trunks with connection state |
| 6 | `telephony.get.trunk.metrics.summary` | seed | Aggregate trunk utilisation, errors, and capacity |
| 7 | `telephony.get.sip.trace.metadata` | `conversationId` / time window | Available SIP traces — confirms whether a trace exists before requesting PCAP |
| 8 | `telephony.get.sip.messages.for.conversation` | `conversationId` | In-platform SIP message viewer for a specific conversation |
| 9 *(PCAP needed)* | `telephony.request.sip.pcap.download` | `conversationId` | Submit async job to generate PCAP file |
| 10 *(PCAP needed)* | `telephony.get.sip.pcap.download.url` | `downloadId` | Retrieve S3 pre-signed URL for Wireshark analysis |
| 11 *(network suspected)* | `telephony.get.edge.diagnostic.nslookup` | `edgeId` | DNS resolution from the Edge — confirms SBC/PSTN hostname resolution |
| 12 *(network suspected)* | `telephony.get.edge.diagnostic.tracepath` | `edgeId` | Hop-by-hop path from Edge to SBC/carrier — identifies network latency source |
| 13 | `alerting.get.alerts` | seed | Platform alerts currently firing — Edge offline, trunk error rate threshold |

### PCAP Retrieval Chain

```
telephony.get.sip.trace.metadata (query by conversationId or time window)
  → telephony.request.sip.pcap.download (submit job, returns downloadId)
  → poll until status = complete
  → telephony.get.sip.pcap.download.url (returns pre-signed S3 URL)
  → download and open in Wireshark
```

### Analytical Questions Answered

- Which Edges are running outdated firmware that could cause instability?
- Is the SIP trunk over-utilised or reporting errors?
- Did the Edge's CPU or memory spike during the reported call quality window?
- Can the Edge resolve the carrier SBC hostname? (nslookup)
- What is the network hop count and latency from Edge to carrier? (tracepath)
- Is there a platform alert that correlates with the customer complaint?

---

## 12. AI-Assisted Conversation Triage (QM Light)

**Subject:** One or many `conversationId` values (post-conversation)  
**Use case:** A QM team needs to prioritise which conversations to review in full (recording + evaluation form) without listening to every call. AI summaries and STA category/sentiment signals let a QM analyst triage dozens of conversations in minutes.

**Core question:** *Which conversations need full QM review, and what happened in the high-priority ones?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics-conversation-details-query` | queue/agent/window filter | Candidate conversations with handle times, transfer flags, hold events |
| 2 | `conversations.get.conversation.ai.summaries` | `conversationId` | AI-generated topic, outcome, action items — fast triage signal |
| 3 | `conversations.get.speech.text.analytics` | `conversationId` | Sentiment status, STA analysis coverage, topic categories |
| 4 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Specific STA categories matched with confidence scores |
| 5 | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-utterance sentiment timeline — agent vs customer breakdown |
| 6 *(high-priority only)* | `quality.get.evaluations.query` | `conversationId` | Existing evaluation if this conversation was already scored |
| 7 *(high-priority only)* | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording ID for full playback in QM tool |
| 8 *(high-priority only)* | `conversations.get.conversation.recording.annotations` | `conversationId` + `recordingId` | Prior analyst annotations flagging specific moments |

### Triage Scoring Pattern

Rank conversations by composite risk score:
```
risk_score = (
  sentiment_score < -0.5 ? 3 : 0          // negative customer sentiment
  + hold_count > 2 ? 2 : 0                 // repeated holds
  + was_transferred ? 2 : 0                // transfer event
  + tHandle > p90_tHandle ? 1 : 0          // long handle time
  + 'Escalation' in categories ? 3 : 0    // STA escalation category
  + 'Complaint' in categories ? 3 : 0     // STA complaint category
)
```

### Analytical Questions Answered

- What was this conversation about? (AI summary)
- Was the customer satisfied at the end? (sentiment score)
- Did the STA system flag a complaint, escalation, or compliance keyword?
- Was the conversation already evaluated? If so, what was the score?
- Which conversations have the highest composite risk and need immediate QM attention?

---

## 13. External Contact / CRM Context Enrichment

**Subject:** One `conversationId` where a participant is linked to an external contact  
**Use case:** A complaint is received about a customer experience. The investigator needs to see not just what happened in the conversation, but who the customer is, their prior interactions, notes left by other agents, and whether they had already tried self-service before calling.

**Core question:** *Who is this customer, what is their history, and what did they try before calling?*

### How to Identify External Contact Linkage

`conversations.get.conversation.object` returns `participants[].externalContactId` when a conversation participant has been matched to an External Contact record.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Participants including `externalContactId` if CRM-linked |
| 2 | `externalcontacts.get.contact` | `externalContactId` | Customer name, organisation, phone, email, custom CRM fields |
| 3 | `externalcontacts.get.contact.notes` | `externalContactId` | Agent-authored notes from prior interactions — complaint history |
| 4 | `externalcontacts.get.contact.journey.sessions` | `externalContactId` | Digital sessions linked to this contact — web, chat, self-service attempts |
| 5 *(if sessions found)* | `journey.get.session.events` | `sessionId` | Events within each digital session — pages visited, forms submitted, chatbot turns |
| 6 | `analytics-conversation-details-query` (externalContactId filter) | `externalContactId` | All prior voice/digital conversations linked to this contact |

### Key Joins

```
conversations.get.conversation.object.participants[].externalContactId
  → externalcontacts.get.contact.id (customer enrichment)
  → externalcontacts.get.contact.notes.contactId (history)
  → externalcontacts.get.contact.journey.sessions.contactId (digital pre-contact)

externalcontacts.get.contact.journey.sessions[].id
  → journey.get.session.events.sessionId (digital event detail)
```

### Analytical Questions Answered

- Who is this customer and what are their contact details?
- What notes have other agents left about this customer?
- Did the customer try the website or chatbot before calling? What did they do?
- How many prior conversations has this customer had, and what were the outcomes?
- Is there a pattern of repeat contacts that might indicate an unresolved issue?

---

## 14. WFM Adherence Gap Investigation

**Subject:** One `managementUnitId` + date range  
**Use case:** A workforce manager notices that a team is consistently understaffed during a specific interval, or an individual agent's time-in-state data shows unexplained non-adherence. They need to compare the published schedule against actual agent behaviour.

**Core question:** *Where is the schedule adherence breaking down and why?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.management.units` | seed → `managementUnitId` | Management unit identity and business unit linkage |
| 2 | `workforce.get.management.unit.users` | `managementUnitId` | All agents in the management unit |
| 3 | `workforce.get.management.unit.adherence` | `managementUnitId` | Live adherence state: scheduled activity vs actual presence per agent |
| 4 | `workforce.historical.adherence.query` | `managementUnitId` + date range | Historical adherence variance over the investigation window |
| 5 | `workforce.get.agent.schedule.search` | `businessUnitId` + agent list | Published schedule shifts for the investigation window |
| 6 | `analytics.query.user.aggregates.login.activity` | `userId` list | Actual time-in-state: tSystemPresence, tAgentRoutingStatus breakdown |
| 7 | `analytics.query.user.details.activity.report` | `userId` | Login/logout/on-queue event timeline per agent |

### Key Joins

```
workforce.get.management.unit.users[].userId
  → workforce.historical.adherence.query.userId (actual vs scheduled delta)
  → workforce.get.agent.schedule.search.agentId (what was scheduled)
  → analytics.query.user.aggregates.login.activity.userId (how they actually spent time)
```

### Analytical Questions Answered

- Which agents had the largest adherence variance in the investigation window?
- What was an agent scheduled to do vs what their routing status showed?
- Is non-adherence clustered in a specific interval (e.g. end of shift)?
- How does actual on-queue time compare to scheduled on-queue time?

---

## 15. Bot / Self-Service Containment Analysis

**Subject:** One or more `flowId` values (IVR / bot flows) + time window  
**Use case:** Operations leadership asks what percentage of contacts self-served without reaching an agent. This investigation measures bot and IVR containment, identifies the most common failure/exit points, and quantifies how much agent volume those failures created.

**Core question:** *How effective is our self-service, and where does it fail?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | seed | Flow catalog — identify the IVR/bot flows in scope |
| 2 | `flows.get.flow.outcomes` | seed | Outcome definitions: what does a "contained" vs "escalated" outcome mean? |
| 3 | `flows.get.flow.milestones` | seed | Milestone definitions — named checkpoints to measure partial completion |
| 4 | `analytics.query.flow.execution.aggregates` | `flowId` | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone per flow |
| 5 | `analytics.query.bot.aggregates` | `flowId` / `botId` | nBotSessions, nFlowOut (transfers to agent), bot session duration |
| 6 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` (receiving queue) | How many conversations arrived via flow transfer? nOffered contributed by IVR |
| 7 *(trend needed)* | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Execution metrics trend over the window — detect flow regression |

### Containment Rate Formula

```
Containment Rate = (nFlow - nFlowOut) / nFlow × 100
Bot Escalation Rate = nFlowOut / nBotSessions × 100
Flow Failure Rate = nFlowOutcomeFailed / nFlowOutcome × 100
```

### Analytical Questions Answered

- What percentage of IVR sessions completed without transferring to an agent?
- At which milestone do the most sessions exit to agent queue?
- Is the bot escalation rate increasing or decreasing week-over-week?
- How many agent-handled conversations originated from failed self-service attempts?
- Which outcomes are most common, and do they correlate with high-satisfaction vs low-satisfaction flows?

---

## 16. Quality Calibration Consistency Audit

**Subject:** Organisation-wide or one `queueId` + time window  
**Use case:** A QM manager suspects that different evaluators are scoring the same criteria inconsistently. Calibration sessions (where multiple evaluators score the same conversation) expose inter-rater variance. This investigation audits that variance.

**Core question:** *Are our evaluators scoring consistently, and which criteria have the most variance?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `quality.get.published.evaluation.forms` | seed | Active evaluation forms and their scoring criteria |
| 2 | `quality.get.calibrations` | seed → time window | All calibration sessions in the window — conversation + evaluator list |
| 3 | `quality.get.evaluations.query` | `calibrationId` / `conversationId` | Individual scores from each evaluator on the calibration conversation |
| 4 | `quality.get.evaluators.activity` | seed → time window | Evaluator workload — who is scoring the most / least? |
| 5 | `analytics.query.evaluations.aggregates` | `queueId` / `userId` | Aggregate score distribution by evaluator for bias detection |

### Variance Analysis Pattern

```
For each calibration session:
  scores = [evaluator1.score, evaluator2.score, ...]
  mean = avg(scores)
  std_dev = stddev(scores)
  
  Flag session if std_dev > threshold (e.g. 10 points on 100-point scale)
  Drill into question-level scores to identify which criteria vary most
```

### Analytical Questions Answered

- Which calibration sessions showed the highest score variance across evaluators?
- Which evaluation form questions are scored most inconsistently?
- Are specific evaluators consistently higher or lower than the group mean?
- Is there a correlation between evaluator workload (evaluations/week) and calibration variance?

---

## 17. First Contact Resolution (FCR) Investigation

**Subject:** One `queueId` (or organisation-wide) + time window  
**Use case:** Leadership wants to know what percentage of customers resolved their issue in one contact. This investigation cross-references resolution signals with repeat contact patterns.

**Core question:** *What is our first contact resolution rate and which contact types drive repeat calls?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.resolutions.aggregates` | `queueId` + window | nResolved, nUnresolved — system-level FCR signals |
| 2 | `analytics-conversation-details-query` | `queueId` + window | Individual conversations with participant attributes |
| 3 | `conversations.search.participant.attributes` | `conversationId` | IVR-captured issue type, account, reason codes — repeat contact indicator fields |
| 4 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Wrapup code distribution — "Resolved", "Callback Required", "Escalated" codes |
| 5 | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Labels for the wrapup codes to classify resolution vs non-resolution outcomes |
| 6 *(contact-level only)* | `externalcontacts.get.contact` | `externalContactId` | Contact-level repeat contact history — prior conversation count |

### FCR Computation Pattern

```
Resolution wrapup codes: define via step 5 (e.g. "Resolved", "Information Provided")
Non-resolution codes: "Callback Required", "Transferred", "Escalated", "Follow-up Needed"

FCR = conversations with resolution wrapup / total connected × 100
Repeat Contact Rate = contacts with >1 conversation in 7-day window / unique contacts × 100
```

### Analytical Questions Answered

- What percentage of calls end with a resolution wrapup code?
- Which wrapup codes are most associated with repeat contacts?
- Which issue types (from IVR participant attributes) have the lowest FCR?
- Does FCR differ significantly by agent or by time of day?

---

## 18. Agent AI Assist Adoption Investigation

**Subject:** One `userId` or queue scope + time window  
**Use case:** A contact centre technology manager wants to understand whether agents are using the Agent Copilot and AI suggestions that have been deployed. Low adoption may indicate training gaps, poor suggestion quality, or workflow friction.

**Core question:** *Are agents using the AI assist tools, and is usage correlated with better outcomes?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.agentcopilot.aggregates` | `userId` / `queueId` | nCopilotInteractions, nSuggestionsPresented, nSuggestionsEngaged per agent |
| 2 | `analytics.query.summaries.aggregates` | `userId` / `queueId` | AI summary generation and engagement rates |
| 3 | `conversations.get.conversation.ai.summaries` | `conversationId` | Conversation-level summary for spot-checking quality |
| 4 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | AHT, ACW, talk time — compare adopters vs non-adopters |
| 5 | `analytics.query.evaluations.aggregates` | `userId` | QM score correlation — do AI-assist users score higher? |
| 6 *(spot check)* | `conversations.get.conversation.suggestions` | `conversationId` | Individual suggestions shown to agent in a specific conversation |

### Adoption Analysis Pattern

```
Adoption Rate = nSuggestionsEngaged / nSuggestionsPresented × 100
Correlation: group agents by adoption quartile → compare mean QM score and AHT
```

### Analytical Questions Answered

- What percentage of AI suggestions presented to agents are being engaged with?
- Which agents have the highest and lowest copilot adoption rates?
- Is higher copilot adoption correlated with lower AHT or higher QM scores?
- How many conversations have AI summaries, and are agents engaging with them?

---

## 19. Multi-Queue SLA Trend for Executive Review (Extended Rollup)

This pattern extends Section 4 (Executive Reporting Rollup) with FCR, AI assist, and self-service data layers that were not previously documented.

### Additional Layer 6 — Self-Service & Automation
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.flow.execution.aggregates` | `flowId`, daily | Flow containment: nFlow, nFlowOutcome, nFlowOutcomeFailed |
| `analytics.query.bot.aggregates` | `botId` / `flowId`, daily | Bot containment: nBotSessions, nFlowOut (escalation count) |
| `analytics.query.summaries.aggregates` | `queueId`, `userId`, daily | AI summary coverage and engagement rate |

### Additional Layer 7 — Quality Depth
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.evaluations.aggregates` | `queueId`, `userId`, daily | nEvaluations, oTotalScore (comparable to quality.get.agents.activity but aggregate) |
| `analytics.query.surveys.aggregates` | `queueId`, daily | nSurveysCompleted, oSurveyTotalScore — aggregate CSAT by queue |
| `analytics.query.resolutions.aggregates` | `queueId`, daily | nResolved / nConnected → FCR rate trend |

### Extended Executive Dashboard Metrics
```
Additional headline KPIs:
  - Self-service containment rate: (nFlow - nFlowOut) / nFlow × 100
  - AI assist adoption: nSuggestionsEngaged / nSuggestionsPresented × 100  
  - FCR rate: nResolved / nConnected × 100
  - Survey response rate: nSurveysCompleted / nConnected × 100
  - Avg survey score: oSurveyTotalScore / nSurveysCompleted
```

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
