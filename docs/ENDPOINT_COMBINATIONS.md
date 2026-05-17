# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-17  
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
10. [Bot & IVR Self-Service Rate Analysis](#10-bot--ivr-self-service-rate-analysis)
11. [Customer Journey Investigation (External Contact / BYOI)](#11-customer-journey-investigation-external-contact--byoi)
12. [Agent Performance Deep Dive (Quality + Gamification + Knowledge)](#12-agent-performance-deep-dive-quality--gamification--knowledge)
13. [Schedule Adherence Investigation](#13-schedule-adherence-investigation)
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

#### Layer 0 — Self-Service (new)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.flow.aggregates.inbound` | `flowId`, `flowType`, daily | nFlow, nFlowOutcome, nFlowOutcomeFailed — IVR containment vs. escalation |
| `analytics.query.bot.aggregates` | `botId`, `queueId`, daily | nSessions, nSessionsContained, nSessionsEscalated — bot self-service rate |

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
| `analytics.query.knowledge.aggregates` | `queueId`, `userId`, daily | Knowledge article utilisation: nKnowledgeSessions, article hits, feedback rate |

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
  - Self-service rate: nSessionsContained / nSessionsTotal (bot) × 100   [Layer 0]
  - IVR containment:  1 - (nOffered_queues / nFlow_inbound) × 100        [Layer 0]
  - Total handled:    SUM(nConnected) across all queues                   [Layer 1]
  - Abandon rate:     SUM(nAbandoned) / SUM(nOffered) × 100              [Layer 1]
  - Average handle time: WAVG(tHandle, nConnected)                       [Layer 1]
  - SLA achievement:  queues meeting target / total queues × 100         [Layer 2]
  - Transfer rate:    SUM(nTransferred) / SUM(nConnected) × 100          [Layer 2]
  - QM coverage:      evaluations / nConnected × 100                     [Layer 4]
  - Average QM score: from quality.get.agents.activity                   [Layer 4]
  - Avg CSAT:         from quality.get.surveys                           [Layer 4]
  - Knowledge usage:  nKnowledgeSessions / nConnected × 100             [Layer 4]

Trend views (daily granularity):
  - Self-service rate trend (bot + IVR containment by day)
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
| gamification | `gamification.get.agent.scorecard` | `userId` + workday | Points, rank, and objective scores in the active gamification profile |
| knowledgeUsage | `analytics.query.knowledge.aggregates` | `userId` | Knowledge article search activity — utilisation and feedback |

**Trigger conditions:** `currentStatus` and `activeConversations` steps are conditional on the
agent being in an active state at investigation time. `coaching` step is conditional on WFM being
licensed and configured. `gamification` requires Gamification to be licensed and active (check
`getGamificationStatus`). `knowledgeUsage` requires Agent Assist / Knowledge to be provisioned.

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
| externalContact | `external.contacts.get.contact` | `externalContactId` (from participants) | CRM identity of the customer (name, phone, email, org) when conversation has an external contact |
| customerJourney | `external.contacts.get.journey.sessions` | `externalContactId` | Prior channel interactions for the same customer (conditional on externalContactId present) |
| botSessions | `analytics.get.botflow.sessions` | `conversationId` | Bot interactions that preceded the agent leg (conditional on bot flow in the call path) |

**Conditional steps:** `sipTrace` runs only when `conversations.get.conversation.object.participants[].calls` is
non-empty (voice conversation). `sentimentTimeline` runs only when `conversations.get.speech.text.analytics`
returns `speechAndTextAnalyticsConversation.analysisStatus = "Success"`. `externalContact` and
`customerJourney` run only when a non-null `externalContactId` is present in the conversation participants.
`botSessions` runs only when the conversation's analytics segments include a `purpose = bot` participant.

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
| calibrations | `quality.get.calibrations` (queueId filter) | `conversationId` | QM calibration sessions and evaluator consistency review for this queue |

---

---

## 10. Bot & IVR Self-Service Rate Analysis

**Subject:** Organisation or specific queue set + time window  
**Use case:** A digital operations manager or contact centre director needs to understand how much
volume the IVR and bot layer handled without escalating to a live agent — the self-service rate.
High self-service means lower cost and shorter queue wait. The analysis also exposes which bot
outcomes are escalating most often, pointing to areas for automation improvement.

**Core question:** *How much of the inbound volume self-served, and where is the bot failing?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | — | All Architect flow IDs and types (inboundCall, bot) |
| 2 | `analytics.query.flow.aggregates.inbound` | `flowId` | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone per flow in window |
| 3 | `analytics.query.bot.aggregates` | `botId` / `flowId` | nSessions, nSessionsContained, nSessionsEscalated, tSession per bot |
| 4 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | nOffered, nConnected to the queues fed by these flows |
| 5 *(detail only)* | `analytics.get.botflow.sessions` | `botFlowId` | Individual bot sessions with conversationId for case-level drilldown |
| 6 *(detail only)* | `analytics.get.botflow.reporting.turns` | `sessionId` | Per-turn intent and user input for specific escalated sessions |

### Key Joins

```
flows.get.all.flows[].id (type=inboundCall or bot)
  → analytics.query.flow.aggregates.inbound[].group.flowId
  → analytics.query.bot.aggregates[].group.flowId (overlapping flows with bot steps)

analytics.query.bot.aggregates[].group.queueId
  → analytics.query.conversation.aggregates.queue.performance[].group.queueId

analytics.get.botflow.sessions[].conversationId
  → analytics-conversation-details-query.conversationId (case drilldown)
  → analytics.get.botflow.reporting.turns (sessionId filter)
```

### Computed Self-Service Rate

```
Self-service rate = nSessionsContained / (nSessionsContained + nSessionsEscalated)
IVR containment   = 1 - (nOffered_queue / nFlow_inbound)

Where nFlow_inbound = all inbound flows that exit toward a queue or bot
      nOffered_queue = conversations that actually reached a queue agent
```

### Analytical Questions Answered

- What percentage of inbound calls self-served in the IVR or bot?
- Which bot outcome categories (Error, UserExit, BotExit) are causing escalation?
- Which specific bot flows have the highest escalation rate?
- What did customers say in the turns just before escalation? (via botflow reporting turns)
- Is bot containment improving or degrading over time (weekly granularity)?

### Executive Headline Metrics

| Metric | Formula | Target |
|--------|---------|--------|
| IVR self-service rate | nSessionsContained / nSessionsTotal | > 30% (varies by industry) |
| Bot escalation rate | nSessionsEscalated / nSessionsTotal | < 40% |
| Flow failure rate | nFlowOutcomeFailed / nFlowOutcome | < 5% |
| Volume deflected | nFlow - nOffered (all queues) | Positive = deflection working |

---

## 11. Customer Journey Investigation (External Contact / BYOI)

**Subject:** One `externalContactId` or `conversationId` with BYOI indicators  
**Use case:** A customer service manager or CRM operations team needs to trace a customer's full
interaction history across all channels — website visits, prior calls, bot interactions, emails,
and the current conversation. This is essential when a customer escalates or complains about
inconsistent service across sessions, or when a BYOI-injected conversation carries CRM context
that needs to be understood alongside the Genesys analytics record.

**Core question:** *Who is this customer, where have they been, and what context do they bring?*

### How to Identify a Customer with External Contact Data

Look for `externalContactId` in participants of the conversation object, or for `externalTag` / `externalConversationId` at the conversation level. Either signals enrichable external CRM data.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Full conversation with `externalTag`, `externalConversationId`, participant `externalContactId` |
| 2 | `external.contacts.get.contact` | `externalContactId` | CRM identity: name, phone, email, external org, contact notes |
| 3 | `external.contacts.get.journey.sessions` | `externalContactId` | All prior journey sessions across channels in reverse chronological order |
| 4 | `conversations.get.conversation.customattributes` | `conversationId` | Provider-set custom attributes: CRM case ID, intent label, external call ID |
| 5 | `conversations.search.participant.attributes` | `conversationId` | IVR/Architect variables set during the injected conversation flow |
| 6 *(window)* | `analytics-conversation-details-query` | `externalContactId` | All conversations this contact has had in the reporting window |
| 7 *(voice)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace for the injected SIP-to-SIP handoff |

### Key Joins

```
conversations.get.conversation.object.participants[].externalContactId
  → external.contacts.get.contact.id (CRM identity)
  → external.contacts.get.journey.sessions (contactId parameter)

conversations.get.conversation.object.externalConversationId
  → conversations.get.conversation.customattributes (provider context)

external.contacts.get.journey.sessions[].conversationId
  → analytics-conversation-details-query.conversationId (historical conversation set)
```

### Analytical Questions Answered

- Who is this customer and what is their CRM profile?
- How many previous interactions has this customer had, across which channels?
- What context (CRM case ID, intent, external call ID) did the BYOI provider inject?
- What did the IVR or bot capture before routing to an agent?
- Is this a first contact or a repeat escalation?

### Division Note

Customers who interact across multiple queues in different divisions all appear in their
`external.contacts.get.journey.sessions` record. This makes the customer journey investigation
a cross-division view even when the investigation is scoped to one conversation.

---

## 12. Agent Performance Deep Dive (Quality + Gamification + Knowledge)

**Subject:** One `userId` + time window  
**Use case:** A quality manager, workforce analyst, or team lead needs a holistic picture of an
agent's performance — not just call volume and handle time, but QM scores, coaching history,
gamification ranking, and knowledge article usage. This investigation answers whether the agent
is getting the support they need and whether quality is tracking with volume.

**Core question:** *Is this agent performing well across all dimensions, and what does the data say about why?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | Identity, manager, division, skills, utilization settings |
| 2 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | nConnected, tHandle, tTalk, tAcw — volume and efficiency metrics in the window |
| 3 | `quality.get.agents.activity` | `userId` | Evaluation count, highest/average/lowest QM scores, evaluator breakdown |
| 4 | `quality.get.evaluations.query` *(userId filter)* | `userId` | Individual evaluation records with form, score, calibration flag |
| 5 | `coaching.get.appointments` | `userId` | Coaching sessions attended/facilitated: status, completion date, topics |
| 6 | `gamification.get.agent.scorecard` | `userId` | Points, rank, objective achievement in the active gamification profile |
| 7 | `analytics.query.knowledge.aggregates` *(userId filter)* | `userId` | Knowledge base search activity: sessions, document hits, feedback submitted |
| 8 | `analytics.query.user.aggregates.login.activity` | `userId` | On-queue time, off-queue time, idle time in the window |

### Key Joins

```
users.get.user.details.with.full.expansion.id
  → analytics.query.conversation.aggregates.agent.performance[].group.userId
  → quality.get.agents.activity[].user.id
  → quality.get.evaluations.query[].agent.id
  → coaching.get.appointments[].attendees[].id
  → gamification.get.agent.scorecard (userId path param — requires workday)
  → analytics.query.knowledge.aggregates[].group.userId
  → analytics.query.user.aggregates.login.activity[].group.userId
```

### Computed Indicators

```
Evaluation coverage    = evaluation_count / nConnected × 100
QM score trend         = quality.get.agents.activity average score vs prior window
Coaching-to-score gap  = sessions_completed vs score_delta (improving post-coaching?)
Knowledge utilisation  = nKnowledgeSessions / nConnected × 100  (are they using agent assist?)
Occupancy              = tHandle / tAgentRoutingStatus[INTERACTING] × 100
```

### Analytical Questions Answered

- What was this agent's evaluation coverage and average QM score?
- Did coaching sessions produce measurable score improvement?
- Where does the agent rank on the gamification leaderboard vs peers?
- Is the agent using knowledge articles? Are their article searches producing useful results (feedback)?
- Is the agent's handle time trending up or down relative to their QM scores?
- How much time was the agent actually on-queue vs idle vs off-queue?

### Conditional Steps

`gamification.get.agent.scorecard` requires Gamification to be licensed and active
(`getGamificationStatus` should return `enabled: true` before invoking).
`analytics.query.knowledge.aggregates` requires Knowledge / Agent Assist to be provisioned.
Both are marked `required: false` in the investigation manifest.

---

## 13. Schedule Adherence Investigation

**Subject:** One `managementUnitId` (or `divisionId` as entry point) + date range  
**Use case:** A WFM analyst or workforce manager needs to understand whether agents are following
their schedules — arriving on time, taking breaks as scheduled, going on-queue when expected.
This investigation combines the WFM layer (schedule and adherence) with the analytics layer
(actual routing status and presence) to give a dual-source view of adherence.

**Core question:** *Were agents on the right activity at the right time, and who was out of adherence?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.business.units` | — | Business unit IDs for the organisation |
| 2 | `workforce.get.management.units` | `businessUnitId` | Management unit IDs, names, and time zones |
| 3 | `workforce.get.management.unit.users` | `managementUnitId` | Agent roster: user IDs assigned to the MU |
| 4 | `workforce.get.management.unit.adherence` | `managementUnitId` | Real-time adherence state per agent: adherenceState, impact (POSITIVE/NEGATIVE), activityCode |
| 5 | `analytics.query.user.aggregates.login.activity` | `userId` | Actual on-queue/off-queue/idle time per agent in the window |
| 6 | `analytics.query.user.details.activity.report` | `userId` | Per-event presence and routing-status timeline (login/logout/state changes) |
| 7 *(agent drill-down)* | `users.get.user.details.with.full.expansion` | `userId` | Identity resolution for agents with high out-of-adherence counts |

### Key Joins

```
workforce.get.management.units[].id
  → workforce.get.management.unit.users.managementUnitId (agent roster)
  → workforce.get.management.unit.adherence.managementUnitId (real-time state)

workforce.get.management.unit.users[].user.id
  → analytics.query.user.aggregates.login.activity[].group.userId
  → analytics.query.user.details.activity.report[].userId
```

### Historical Adherence Note

Real-time adherence (`workforce.get.management.unit.adherence`) reflects only the current
state. For a historical view over a date range (e.g., what was adherence like last week?),
use the Genesys Cloud WFM API endpoint `POST /api/v2/workforcemanagement/adherence/historical/bulk`
(`postWorkforcemanagementAdherenceHistoricalBulk`) and poll the job status via
`GET /api/v2/workforcemanagement/adherence/historical/bulk/{jobId}`
(`getWorkforcemanagementAdherenceHistoricalBulkJob`). This async job pattern returns
scheduled-vs-actual adherence with per-agent percentage scores and exception details.
A catalog dataset for this pattern is planned for a future release once the transaction
profile is wired to the WFM adherence job lifecycle.

### Analytical Questions Answered

- How many agents in this management unit are currently out of adherence?
- Which agents have the most off-queue time relative to their scheduled on-queue time?
- What presence states do out-of-adherence agents show? (Away, Lunch, Break at wrong time)
- Is the adherence problem isolated to a team, a shift, or an individual?
- Does the actual login/logout pattern (from analytics) match the WFM schedule?

### Division as Entry Point

To investigate adherence across a full division:
1. Start from `authorization.get.single.division` → `authorization.list.division.queues`.
2. Use the queue membership (`routing-queue-members`) to enumerate agents across division queues.
3. Map each agent's `userId` to their management unit via `workforce.get.management.unit.users`
   (fan-out over all management units in the division).
4. Then run steps 4–6 above per management unit.

---

## 14. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | Self-Service Rate | Customer Journey | Agent Perf. Deep Dive | Adherence |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | ● | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | ● | | |
| `conversations.search.participant.attributes` | ● | | | | | | | ● | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | ● | |
| `quality.get.surveys` | ● | | | ● | | | | | | |
| `quality.get.calibrations` | | ○ | | | | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | ○ | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ○ | ● | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | ● | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | ● | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | ● | ● |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | ● |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | ● | |
| `coaching.get.appointments` | | | ● | | | ○ | | | ● | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | ● |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | ● | ○ |
| `users.get.user.routing.skills` | | | | | | ● | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | |
| `audit-logs` | | | | | | ● | | | | |
| `flows.get.all.flows` | | | | | | | ● | | | |
| `analytics.query.bot.aggregates` | | | | ○ | | | ● | | | |
| `analytics.query.flow.aggregates.inbound` | | | | ○ | | | ● | | | |
| `analytics.get.botflow.sessions` | ○ | | | | | | ○ | | | |
| `analytics.get.botflow.reporting.turns` | ○ | | | | | | ○ | | | |
| `analytics.query.knowledge.aggregates` | | | | ○ | | | | | ● | |
| `external.contacts.get.contact` | | | | | | | | ● | | |
| `external.contacts.get.journey.sessions` | | | | | | | | ● | | |
| `gamification.get.agent.scorecard` | | | | | | ○ | | | ● | |
| `workforce.get.business.units` | | | | | | | | | | ● |
| `workforce.get.management.units` | | | | | | | | | | ● |
| `workforce.get.management.unit.users` | | | | | | | | | | ● |
| `workforce.get.management.unit.adherence` | | | | | | | | | | ● |

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
| `nFlow` | Total Architect flow executions | IVR volume denominator |
| `nFlowOutcome` | Flow executions that reached a defined outcome | Outcome rate numerator |
| `nFlowOutcomeFailed` | Flow executions that reached a failed outcome | Flow error rate |
| `nFlowMilestone` | Flow executions that passed a named milestone checkpoint | Flow path tracking |
| `nSessions` | Total bot/digital agent sessions | Bot volume denominator |
| `nSessionsContained` | Bot sessions that resolved without agent escalation | Self-service success |
| `nSessionsEscalated` | Bot sessions that transferred to a live agent | Escalation count |
| `tSession` | Total bot session duration | Bot handle time |
| `nKnowledgeSessions` | Knowledge base search sessions initiated | Agent assist usage |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
