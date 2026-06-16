# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-16  
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
11. [Campaign Investigation](#11-campaign-investigation)
12. [Bot / IVR Self-Service Investigation](#12-bot--ivr-self-service-investigation)
13. [WFM Adherence Correlation](#13-wfm-adherence-correlation)
14. [External Contact Journey Enrichment (BYOI)](#14-external-contact-journey-enrichment-byoi)

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
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | |
| `conversations.get.call.detail` | ○ | | | | | |
| `quality.get.conversation.surveys` | ● | | | | | |
| `quality.get.calibration.sessions` | | | | ○ | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | |
| `routing.get.queue.operating.hours` | | ○ | | | | |
| `routing.get.predictors` | | ○ | | ○ | | |
| `authorization.get.division.grants` | | | ● | | | |
| `workforce.get.agent.management.unit` | | | | | | ● |
| `workforce.get.adherence.bulk` | | | | ● | | ● |
| `analytics.query.bot.aggregates` | | | | ● | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | ● | ● | |
| `outbound.get.campaign.progress` | | | | | | |
| `externalcontacts.get.single.contact` | ○ | | | | | |

---

## 11. Campaign Investigation

**Subject:** One `campaignId` + time window
**Use case:** An outbound operations manager or dialer administrator needs to understand why a campaign is underperforming — low right-party contact rates, pacing issues, compliance-sensitive dispositions, or unexpected agent impact on queue SLA.

**Core question:** *Why is this campaign not performing to target, and what conversations did it produce?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Campaign config: dialing mode, queue assignment, caller ID, abandon rate threshold |
| 2 | `outbound.get.campaign.progress` | `campaignId` | Real-time list penetration: contacts dialled, remaining, completion % |
| 3 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Live pacing diagnostics: health indicators, error counters, pacing compliance status |
| 4 | `outbound.get.contact.lists` | `contactListId` (from step 1) | Contact list identity and size — validates list assignment |
| 5 | `outbound.get.events` | `campaignId` | Dialer event stream: contact attempt outcomes, dispositions, timestamps |
| 6 | `analytics-conversation-details-query` (campaignId filter) | `campaignId` | Conversation analytics for connected calls: tTalk, tHandle, wrapUpCode per agent conversation |
| 7 | `routing.get.single.queue.config` | `queueId` (from step 1) | Queue receiving answered calls — validates queue assignment and ACW config |
| 8 | `audit-logs` (EntityType=Campaign, EntityId=campaignId) | `campaignId` | Config changes, start/stop events, and actor audit trail |

### Key Joins

```
outbound.get.campaigns.id
  → outbound.get.campaign.progress.campaignId
  → outbound.get.campaign.diagnostics.summary.campaignId
  → outbound.get.events.campaignId
  → analytics-conversation-details-query[].conversationFilters.campaignId
  → routing.get.single.queue.config.id (via campaign.queueId)
  → outbound.get.contact.lists.id (via campaign.contactListId)
```

### Analytical Questions Answered

- What percentage of the contact list has been dialled? What remains?
- What is the right-party contact rate and answer rate?
- Is the campaign pacing within configured abandon rate limits?
- How long are agents spending on connected calls vs. ACW?
- What wrapup codes are agents using? Are dispositions correct?
- Were there any configuration changes that could explain performance shifts?

### Executive Metrics

| Metric | Formula |
|--------|---------|
| Completion rate | `completionPct` from campaign progress |
| Right-party contact rate | `nConnected / contactsDialed` |
| Abandon rate | from campaign diagnostics |
| AHT for answered calls | `tHandle / nConnected` from analytics |
| Wrapup distribution | from `analytics-conversation-details-query` |

---

## 12. Bot / IVR Self-Service Investigation

**Subject:** One `flowId` + time window
**Use case:** A digital or voice operations analyst needs to understand why a bot or IVR flow is not containing callers — what percentage are self-serving versus escalating to agents, where in the flow drop-off occurs, and what those escalated callers are calling about.

**Core question:** *Is this flow containing callers? Where are they abandoning, and why are they escalating?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | seed → `flowId` | Flow definition: type (inboundcall, bot, inqueue), division, active version |
| 2 | `flows.get.flow.outcomes` | `flowId` | Outcome definitions: what constitutes self-service success vs. failure |
| 3 | `flows.get.flow.milestones` | `flowId` | Named checkpoints — used to identify where callers drop off mid-flow |
| 4 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Aggregate execution: nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone |
| 5 *(bot flows)* | `analytics.query.bot.aggregates` | `flowId` | Bot-specific: nBotSessions, nBotHandledSessions, nBotEscalatedSessions, tBotSession |
| 6 | `analytics.query.flow.observations` | `flowId` | Real-time: active executions in progress right now |
| 7 | `analytics-conversation-details-query` (flowId + segmentType=SYSTEM) | `flowId` | Escalated conversations: which queue they went to, tFlow, wrapUpCode |
| 8 *(STA enabled)* | `analytics.post.transcripts.aggregates.query` | `queueId` (escalation queue) | STA topic frequency: what escalated callers were calling about and their sentiment on arrival |

### Key Joins

```
flows.get.all.flows.id
  → analytics.query.flow.aggregates.execution.metrics.flowId (aggregate overlay)
  → analytics.query.bot.aggregates.flowId (bot-specific overlay)
  → analytics-conversation-details-query[].conversationId (escalation cases)

analytics-conversation-details-query[escalated].queueId
  → analytics.post.transcripts.aggregates.query.queueId (topic distribution on arrival)
```

### Derived Metrics

| Metric | Formula |
|--------|---------|
| Containment rate | `nBotHandledSessions / nBotSessions` |
| Escalation rate | `nBotEscalatedSessions / nBotSessions` |
| IVR failure rate | `nFlowOutcomeFailed / nFlow` |
| Milestone drop-off | `(nFlow − nFlowMilestone[step]) / nFlow` per checkpoint |
| Avg session duration | `tBotSession / nBotSessions` |

### Executive Presentation

- **Containment funnel**: total sessions → self-served → escalated → failed
- **Milestone heatmap**: where in the flow callers are abandoning (ordered by milestone sequence)
- **Escalation destinations**: which queues receive bot hand-offs and in what volume
- **Topic clouds**: top STA topics for escalated calls (what the bot couldn't handle)

### Voice Engineer Notes

Step 6 (`analytics.query.flow.observations`) shows live stuck executions — a non-zero `oFlow` count combined with zero new completions for several minutes indicates a flow deadlock (usually a timed-out data action or a broken REST call within the Architect flow).

---

## 13. WFM Adherence Correlation

**Subject:** One or more `userId` values (or `managementUnitId`) + time window
**Use case:** A workforce management analyst or contact centre director needs to understand whether agents are adhering to their schedules and whether off-schedule behaviour correlates with service level misses. Divisions group WFM management units, so a division-level adherence report spans all management units in that division's queues.

**Core question:** *Are agents on schedule, and does non-adherence correlate with queue degradation?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.business.units` | seed | Business unit list — top-level WFM container |
| 2 | `workforce.get.management.units` | `businessUnitId` | Management units within the business unit |
| 3 | `workforce.get.management.unit.users` | `managementUnitId` | Agents in the management unit — userId roster |
| 4 | `workforce.get.agent.management.unit` | `userId` (per agent) | Agent's management unit assignment — required before adherence lookup |
| 5 | `workforce.get.adherence.bulk` | `userId` list | Bulk adherence: IN_ADHERENCE / OUT_OF_ADHERENCE, scheduled category, actual routing status, variance |
| 6 | `workforce.get.management.unit.adherence` | `managementUnitId` | Full management-unit adherence snapshot (alternative to bulk when all agents needed) |
| 7 | `analytics.query.user.aggregates.login.activity` | `userId` | Actual on-queue time vs. scheduled on-queue time for delta calculation |
| 8 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Queue SLA and volume during periods of high non-adherence — the impact side |
| 9 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon rate during non-adherence windows — confirms caller impact |

### Key Joins

```
workforce.get.management.unit.users[].id
  → workforce.get.adherence.bulk.userId (adherence state per agent)
  → analytics.query.user.aggregates.login.activity.userId (actual vs. scheduled time)

non-adherence windows (derived from adherence.outOfAdherenceSeconds + timestamp)
  → analytics.query.conversation.aggregates.queue.performance[hourly] (SLA during those windows)
  → analytics.query.conversation.aggregates.abandon.metrics[hourly] (abandon rate during those windows)
```

### Analytical Questions Answered

- Which agents are OUT_OF_ADHERENCE and by how many minutes?
- Is non-adherence clustered in specific time windows (lunch, shift start, break periods)?
- Do queue SLA misses or abandon rate spikes coincide with high non-adherence periods?
- Which management units have the worst adherence scores?

### Executive Metrics

| Metric | Formula |
|--------|---------|
| Adherence rate | `timeInAdherence / scheduledTime × 100` |
| Schedule variance | `actualOnQueueTime − scheduledOnQueueTime` (minutes) |
| Non-adherence impact | Overlap of non-adherence windows with SLA miss intervals |
| Coverage gap | `oOnQueueUsers` during non-adherence periods vs. demand |

---

## 14. External Contact Journey Enrichment (BYOI)

**Subject:** One `conversationId` where `externalContactId` is non-null
**Use case:** A contact centre analyst or CRM team member needs to enrich a conversation investigation with the customer's identity and history from the external contact store — typically after a BYOI-injected call or when the IVR/Architect flow used a data action to look up and tag the caller.

**Core question:** *Who is this customer, and what does Genesys know about them outside this conversation?*

### How to Identify a Candidate

In `conversations.get.conversation.object` (or `conversations.get.specific.conversation.details`):

```json
{
  "participants": [
    {
      "purpose": "customer",
      "externalContactId": "<contact-guid>",
      "externalOrganizationId": "<org-guid>"
    }
  ]
}
```

A non-null `externalContactId` on a customer participant means the caller was matched to an external contact record. This is set by:
- IVR data actions that look up the caller by ANI
- BYOI provider tagging the call with a CRM contact ID at injection
- Architect flows that set `externalContactId` explicitly

### Dataset Steps (ordered, after identifying externalContactId)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Full conversation with externalContactId on the customer participant |
| 2 | `externalcontacts.get.single.contact` | `externalContactId` | Customer identity: name, phone numbers, email, CRM identifiers, external org |
| 3 | `conversations.get.conversation.customattributes` | `conversationId` | IVR/Architect attributes set during the call: account number, intent, CRM case ID |
| 4 | `conversations.search.participant.attributes` | `conversationId` | Participant-level flow variables capturing lookup results and data action outputs |
| 5 | `analytics.get.single.conversation.analytics` | `conversationId` | Full segment timing with participant detail |
| 6 | `quality.get.conversation.surveys` | `conversationId` | CSAT/NPS result if the survey was triggered for this customer |

### Key Joins

```
conversations.get.conversation.object.participants[purpose=customer].externalContactId
  → externalcontacts.get.single.contact.id (customer identity enrichment)

externalcontacts.get.single.contact.externalOrganizationId
  → (optional: external organization record for B2B enrichment)

conversations.get.conversation.customattributes.results[].name
  → (match against known attribute keys set by IVR: accountId, intentLabel, crmCaseId)
```

### Analytical Questions Answered

- Who is the customer? (name, known phone numbers, email addresses)
- What CRM identifiers did Genesys capture? (account number, case ID, contact ID)
- What was the customer's intent as captured by the IVR or bot?
- What data action results were set during the call?
- Was the customer surveyed after this interaction? What was their CSAT score?

### BYOI Context

For conversations injected via `POST /api/v2/conversations/providers/{providerId}/calls`, the provider sets `externalTag` and `externalConversationId` at injection time. These appear in the conversation object alongside any `externalContactId` the provider or Architect flow sets. The `conversations.get.conversation.customattributes` dataset is the authoritative source for provider-injected context beyond the base conversation fields.

---

## Expanded Reference Matrix (All Combinations)

The complete matrix below extends section 10 with the new combination patterns added in this update.
`●` = primary, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation | Queue | Division | Agent | Executive | Real-Time | Campaign | Bot/IVR | WFM Adherence | External Contact |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | | | ● |
| `conversations.get.specific.conversation.details` | ● | | | | | | | | | ● |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | | ● |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | |
| `conversations.get.call.detail` | ○ | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | ● |
| `conversations.search.participant.attributes` | ● | | | | | | | | | ● |
| `conversations.get.conversation.summaries` | ○ | | | | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ○ | | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | | |
| `quality.get.surveys` | ● | | | | ● | | | | | |
| `quality.get.conversation.surveys` | ● | | | | | | | | | ● |
| `quality.get.calibration.sessions` | | | | | ○ | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | |
| `telephony.get.sip.message.for.conversation` | ○ | | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | |
| `analytics.query.conversation.transcripts` | | | | | ● | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | | ● | | | ○ | | |
| `routing.get.single.queue.config` | | ● | | | | | ● | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | |
| `routing.get.queue.wrapup.codes` | | ● | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | | ● | | | | |
| `routing.get.queue.operating.hours` | | ○ | | | | | | | | |
| `routing.get.predictors` | | ○ | | | ○ | | | | | |
| `analytics-conversation-details-query` | | ● | | ○ | | | ● | ● | | |
| `analytics.query.conversation.details.by.queue` | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | | ● | | | | ● | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | | ● | | | | ● | |
| `analytics.query.queue.aggregates.service.level` | | ● | | | ● | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | | ● | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | | ● | | | | | |
| `routing-queue-members` | | ● | | | | | | | | |
| `routing.get.queue.members.with.status` | | ● | | | | ● | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | |
| `authorization.search.division.objects` | | | ● | | | | | | | |
| `authorization.get.division.grants` | | | ● | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | | | ● | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | ● | | | | ● | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | |
| `analytics.query.user.aggregates.performance.metrics` | | | | ● | | | | | | |
| `quality.get.agents.activity` | | | ● | ○ | ● | | | | | |
| `coaching.get.appointments` | | | ● | | | | ○ | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | | ● | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | | ● | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | | ● | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | | ● | | | | |
| `analytics.get.agent.active.status` | | | | | | ○ | | | | |
| `users.get.agent.active.conversations` | | | | | | ○ | | | | |
| `users.get.agent.current.routing.status` | | | | | | ○ | | | | |
| `analytics.query.flow.observations` | | | | | | ● | | ● | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | ● | | | ● | | |
| `analytics.query.bot.aggregates` | | | | | ● | | | ● | | |
| `telephony.get.trunk.metrics.summary` | | | | | ○ | ● | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | | ● | | | | |
| `alerting.get.alerts` | | | | | ○ | ● | | | | |
| `users.get.user.details.with.full.expansion` | | | | ● | | | | | | |
| `users.get.user.routing.skills` | | | | ● | | | | | | |
| `users.get.user.queue.memberships` | | | | ● | | | | | | |
| `users.get.bulk.user.presences` | | | | ● | | | | | | |
| `routing.get.user.utilization` | | | | ○ | | | | | | |
| `audit-logs` | | | | ● | | | ● | | | |
| `flows.get.all.flows` | | | | | ● | | | ● | | |
| `flows.get.flow.outcomes` | | | | | ● | | | ● | | |
| `flows.get.flow.milestones` | | | | | ● | | | ● | | |
| `outbound.get.campaigns` | | | | | | | ● | | | |
| `outbound.get.campaign.progress` | | | | | | | ● | | | |
| `outbound.get.campaign.diagnostics.summary` | | | | | | | ● | | | |
| `outbound.get.contact.lists` | | | | | | | ● | | | |
| `outbound.get.events` | | | | | | | ● | | | |
| `workforce.get.business.units` | | | | | ● | | | | ● | |
| `workforce.get.management.units` | | | | | ● | | | | ● | |
| `workforce.get.management.unit.users` | | | | | ● | | | | ● | |
| `workforce.get.management.unit.adherence` | | | | | ● | | | | ● | |
| `workforce.get.agent.management.unit` | | | | ● | | | | | ● | |
| `workforce.get.adherence.bulk` | | | | | ● | | | | ● | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | ● | | | | ● | |
| `routing.get.queue.operating.hours` | | ○ | | | | | | | ● | |
| `externalcontacts.get.single.contact` | | | | | | | | | | ● |
| `speechandtextanalytics.get.topics` | | | | | ● | | | ○ | | |

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
| `nBotSessions` | Bot/virtual-agent sessions entered | Self-service entry volume |
| `nBotHandledSessions` | Sessions resolved by bot (no agent) | Self-service containment count |
| `nBotEscalatedSessions` | Sessions escalated to an agent | Escalation count |
| `tBotSession` | Total bot session duration | Self-service handle time |
| `containmentRate%` | `nBotHandledSessions / nBotSessions × 100` | Bot ROI headline metric |
| `adherencePct` | Time in scheduled activity / scheduled time | WFM schedule compliance |
| `scheduleVarianceMinutes` | Actual on-queue − scheduled on-queue time | WFM impact analysis |
| `nFlowOutcome` | Flow executions reaching a defined outcome | Self-service completion count |
| `nFlowOutcomeFailed` | Flow executions exiting via failure path | IVR failure count |
| `completionPct` | Campaign contacts dialled / list size × 100 | Outbound campaign progress |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
