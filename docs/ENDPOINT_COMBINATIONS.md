# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-12  
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
11. [Outbound Campaign Investigation](#11-outbound-campaign-investigation)
12. [IVR / Bot Self-Service Containment Investigation](#12-ivr--bot-self-service-containment-investigation)
13. [Customer Journey Investigation (External Contact)](#13-customer-journey-investigation-external-contact)
14. [Recording Compliance Investigation](#14-recording-compliance-investigation)
15. [Sentiment-Driven Quality Investigation](#15-sentiment-driven-quality-investigation)
16. [AI Conversation Summary Layer](#16-ai-conversation-summary-layer)
17. [Telephony Infrastructure Investigation](#17-telephony-infrastructure-investigation)

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

---

## 11. Outbound Campaign Investigation

**Subject:** One `campaignId` + time window  
**Use case:** A dialer administrator or outbound supervisor receives a report that a campaign is
underperforming — low connect rate, high abandons, contacts not being reached, or wrapup codes
suggesting wrong-numbers/disconnected. They need to see campaign health, conversation outcomes,
and agent performance on this specific campaign.

**Core question:** *Why is this outbound campaign performing the way it is?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Campaign config: contact list, dialing mode (preview/predictive/power), caller ID, abandon rate threshold, skill routing |
| 2 | `outbound.get.campaign.progress` | `campaignId` | Real-time: % complete, contacted count, remaining contacts, current status (running/stopped/complete) |
| 3 | `analytics-conversation-details-query` (campaign filter via `outboundCampaignId`) | `campaignId` | All conversations that originated from this campaign, with segment timing and wrapup codes |
| 4 | `analytics.query.conversation.aggregates.queue.performance` (campaign queue filter) | `queueId` | AHT, talk time, ACW for agent-handled legs of campaign conversations |
| 5 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon count on the campaign queue — differentiate campaign drop vs. customer hang-up |
| 6 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` + wrapUpCode | Wrapup code frequencies — right-party contact, no-answer, voicemail, DNC, callback |
| 7 | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Labels for the wrapup codes in step 6 |
| 8 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | Per-agent metrics on campaign: who handled the most, who had highest ACW |
| 9 *(voice campaign)* | `telephony.get.trunk.metrics.summary` | — | Trunk utilisation during campaign window — confirm sufficient capacity for outbound traffic |

### Key Joins

```
outbound.get.campaigns.id
  → outbound.get.campaign.progress.campaignId
  → analytics-conversation-details-query[].outboundCampaignId (conversation enumeration)

analytics-conversation-details-query[].participants[].sessions[].wrapUpCode
  → routing.get.queue.wrapup.codes.by.queue[].id (label resolution)

analytics-conversation-details-query[].participants[].userId
  → analytics.query.conversation.aggregates.agent.performance[].userId
```

### Analytical Questions Answered

- How many contacts have been reached? What percentage of the list remains?
- What is the right-party contact (RPC) rate? What fraction ended in voicemail or no-answer?
- Which agents are handling the most campaign volume? Are any outliers in AHT?
- Is the campaign pacing correctly, or is the abandon rate exceeding the configured threshold?
- Were there trunk capacity constraints during the campaign run?

### Wrapup Code Interpretation for Outbound

Outbound wrapup codes reveal outcomes that aggregate metrics cannot. Map these codes in step 6:
- High voicemail/no-answer → list penetration problem, not an agent problem
- High DNC → list hygiene required
- High wrong-number → contact data quality
- High callback-scheduled → high intent, positive indicator

---

## 12. IVR / Bot Self-Service Containment Investigation

**Subject:** One `flowId` (or set of flows) + time window  
**Use case:** An IVR designer or operations manager suspects that customers are falling out of
self-service faster than expected — too many escalate to a queue that should not be reached, or
flow outcomes indicate failures at specific milestones. Containment rate directly drives cost-per-contact.

**Core question:** *Where in the IVR/bot flow are customers abandoning self-service, and what drives escalation?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | seed → `flowId` | Flow name, type (inbound-call, in-queue, bot), published version |
| 2 | `flows.get.flow.outcomes` | — | Named outcome definitions: Self-Service, Escalated, Abandoned, Error — the vocabulary for step 3 |
| 3 | `flows.get.flow.milestones` | — | Named milestone definitions: authenticated, intent-captured, routed — checkpoints within the flow |
| 4 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | nFlow, nFlowOutcome by outcome type, nFlowMilestone by milestone — containment vs. escalation counts |
| 5 | `analytics.query.conversation.aggregates.queue.performance` (escalation queue filter) | `queueId` | Volume landing in the escalation queue — the leak |
| 6 | `analytics-conversation-details-query` (flowId in sessions, nFlowOutcome = Escalated) | `conversationId` | Individual escalated conversations for case review |
| 7 *(STA enabled)* | `conversations.get.speech.text.analytics` (fan-out on escalated conversations) | `conversationId` | Topics and sentiment of escalated conversations — why are they escaping? |
| 8 *(STA enabled)* | `speechandtextanalytics.get.conversation.categories` | `conversationId` | STA category matches (billing, cancellation, complaints) — segment escalation by intent |

### Key Joins

```
flows.get.flow.outcomes[].id
  → analytics.query.flow.aggregates.execution.metrics.results[].group.flowOutcomeId

flows.get.flow.milestones[].id
  → analytics.query.flow.aggregates.execution.metrics.results[].group.flowMilestoneId

analytics-conversation-details-query[].conversationId
  → conversations.get.speech.text.analytics[].speechAndTextAnalyticsConversation.conversationId
  → speechandtextanalytics.get.conversation.categories[].conversationId
```

### Analytical Questions Answered

- What percentage of conversations are contained in self-service vs. transferred to a queue?
- At which milestone does the highest drop-off occur?
- Which flow outcome dominates — self-served, escalated, abandoned, or error?
- What topics appear most in escalated conversations? (billing? complaints? authentication failure?)
- Is there a specific hour or day-of-week pattern to the escalation rate?

### Containment Rate Formula

```
Self-Service Containment Rate = nFlowOutcome[Self-Service] / nFlow × 100

Escalation Rate = nFlowOutcome[Escalated] / nFlow × 100

Milestone Drop-Off at Step N = (nFlowMilestone[N-1] - nFlowMilestone[N]) / nFlowMilestone[N-1] × 100
```

---

## 13. Customer Journey Investigation (External Contact)

**Subject:** One `contactId` (external contact) + optional time window  
**Use case:** A customer service manager or compliance investigator needs to understand a
customer's full history across all channels — every conversation they had, what topics
were discussed, how each was resolved, and what the sentiment trend was over time.
This is distinct from a single-conversation investigation: it spans the contact's lifetime.

**Core question:** *What is this customer's complete interaction history, and is it consistent with their current complaint?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `externalcontacts.get.contact` | seed → `contactId` | Customer name, phone, email, account, organisation, and custom attributes |
| 2 | `analytics-conversation-details-query` (externalContactId filter) | `contactId` | All conversations linked to this external contact in the window — voice, chat, email, messaging |
| 3 | `conversations.get.conversation.object` (fan-out per conversationId) | `conversationId` | Per-conversation: queue, DNIS/ANI, participants, hold/transfer events |
| 4 | `conversations.get.speech.text.analytics` (STA-enabled conversations) | `conversationId` | Topics and sentiment per conversation |
| 5 | `speechandtextanalytics.get.conversation.summaries` (STA-enabled conversations) | `conversationId` | AI-generated summary, resolution status, and follow-up actions per conversation |
| 6 | `quality.get.evaluations.query` (conversationId filter, left join) | `conversationId` | QM scores across the customer's history — were the conversations handled well? |
| 7 | `quality.get.surveys` (conversationId filter, left join) | `conversationId` | CSAT/NPS survey responses per conversation — voice of the customer over time |

### Key Joins

```
externalcontacts.get.contact.id
  → analytics-conversation-details-query[].participants[].externalContactId

analytics-conversation-details-query[].conversationId
  → conversations.get.conversation.object[].id
  → conversations.get.speech.text.analytics[].speechAndTextAnalyticsConversation.conversationId
  → speechandtextanalytics.get.conversation.summaries[].conversationId
  → quality.get.evaluations.query[].conversationId (left join)
  → quality.get.surveys[].conversationId (left join)
```

### Analytical Questions Answered

- How many times has this customer contacted us in the window? Across which channels?
- What topics did they discuss? Were the topics consistent (e.g., an ongoing billing dispute)?
- What was the sentiment trajectory — improving, stable, or deteriorating?
- Were the customer's conversations evaluated? Did they score well?
- Has the customer completed a CSAT survey? What was the score?
- Are there unresolved conversations — summaries with follow-up actions that were never closed?

### Privacy Note

This investigation retrieves conversation-level analytics filtered by external contact ID.
No personal identifiable information beyond the contact object's own fields is fetched.
Apply `agent-investigation-users` redaction to step 1 outputs and
`conversation-sentiment` redaction to STA outputs.

---

## 14. Recording Compliance Investigation

**Subject:** A set of `conversationId`s (typically from an analytics query) + compliance window  
**Use case:** A compliance officer, legal hold manager, or QM team lead needs to verify that
conversations that should have been recorded were recorded, download a batch of recordings for
legal review, and confirm deletion schedules are consistent with retention policy.

**Core question:** *Are recordings present, intact, and compliant with retention obligations?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics-conversation-details-query` (date range + queue/agent filter) | — | Conversation IDs in scope — the population to audit |
| 2 | `conversations.get.conversation.recording.metadata` (fan-out per conversationId) | `conversationId` | Recording IDs, media type, duration, deletion schedule, `fileState` |
| 3 *(gap analysis)* | Compare conversations from step 1 against recordings from step 2 | `conversationId` | Conversations with no recording — potential compliance gap |
| 4 | `recording.post.batch.requests` (list of recording IDs from step 2) | `recordingId` | Submit bulk download job; returns `jobId` |
| 5 | `recording.get.batch.request.status` | `jobId` | Signed download URLs per recording — poll until complete |
| 6 *(optional)* | `quality.get.evaluations.query` (conversationId filter) | `conversationId` | Evaluations against recordings in scope — confirm QM sampling coverage |

### Key Joins

```
analytics-conversation-details-query[].conversationId
  → conversations.get.conversation.recording.metadata[].conversationId
    (left join — no recording row means no recording was made)

conversations.get.conversation.recording.metadata[].recordings[].id
  → recording.post.batch.requests.batchRequest.recordingIds[]
  → recording.get.batch.request.status.results[].recordingId
```

### Compliance Gap Detection

```
Conversations without recordings = 
  SET(analytics-conversation-details-query[].conversationId)
  MINUS
  SET(conversations.get.conversation.recording.metadata[].conversationId)

Recordings at risk of deletion = 
  conversations.get.conversation.recording.metadata[].recordings[?(@.deleteDate <= complianceHorizon)]
```

### Analytical Questions Answered

- Which conversations in scope have no recording? Is the gap explainable (e.g., agent initiated, IVR-only leg)?
- Are any recordings scheduled for deletion before the compliance retention period expires?
- For a legal hold request, which recording IDs need to be downloaded and preserved?
- What is the QM sampling rate over the batch — were evaluated conversations also recorded?

### Permissions Required

- `recording:recording:view` — required for recording metadata and batch download
- `recording:recording:viewSensitiveData` — required if org has sensitive data redaction enabled
  (absent this permission, redacted recordings are excluded from batch download results)

---

## 15. Sentiment-Driven Quality Investigation

**Subject:** A queue or division + time window, surfacing the worst-sentiment conversations  
**Use case:** A Quality Manager wants to proactively find conversations that need evaluation
attention — not just a random sample, but the conversations where customers expressed the most
distress. This surfaces coaching opportunities that random sampling misses.

**Core question:** *Which conversations had the most negative customer sentiment, and do they reveal agent behaviour or process gaps?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | oSentimentScore aggregates by queue and agent — identify low-scoring queues and agents |
| 2 | `analytics-conversation-details-query` (queueId filter, ordered by sentiment asc) | `queueId` | Individual conversations sorted by worst sentiment in the window |
| 3 | `conversations.get.speech.text.analytics` (fan-out on bottom-N conversations) | `conversationId` | Full STA: overall score, agent score, customer score, detected topics |
| 4 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic categories matched — distinguish complaint patterns from isolated incidents |
| 5 | `speechandtextanalytics.get.conversation.summaries` | `conversationId` | AI summary — rapid triage without listening to every recording |
| 6 | `quality.get.evaluations.query` (left join) | `conversationId` | Were the worst-sentiment conversations already evaluated? Coverage check |
| 7 *(voice)* | `conversations.get.conversation.recording.metadata` | `conversationId` | Confirm recording exists before assigning for evaluation |
| 8 | `quality.get.published.evaluation.forms` | — | Available evaluation forms — select appropriate form for the queue |

### Key Joins

```
analytics.post.transcripts.aggregates.query.results[].group.queueId
  → analytics-conversation-details-query.filter.queueId (scoped pull)

analytics-conversation-details-query[].conversationId
  → conversations.get.speech.text.analytics[].speechAndTextAnalyticsConversation.conversationId
  → speechandtextanalytics.get.conversation.categories[].conversationId
  → speechandtextanalytics.get.conversation.summaries[].conversationId
  → quality.get.evaluations.query[].conversationId (left join — unassigned = opportunity)
```

### Analytical Questions Answered

- Which queues have the lowest average sentiment score this period?
- Which agents are consistently appearing in the bottom-sentiment conversations?
- What topics appear disproportionately in negative-sentiment conversations?
- Are the worst conversations already being evaluated, or are they slipping through random sampling?
- What does the AI summary say happened? (Fast triage before assigning for full evaluation)

### Sentiment Score Reference

| Score Range | Label | Typical Driver |
|------------|-------|---------------|
| +40 to +100 | Positive | Resolution achieved, agent empathy high |
| 0 to +39 | Neutral | Transactional, low emotion |
| -39 to -1 | Slightly Negative | Friction, hold, transfer |
| -100 to -40 | Strongly Negative | Complaint, escalation, repeated contacts |

---

## 16. AI Conversation Summary Layer

**Subject:** Any conversation (single or batch) with Speech and Text Analytics enabled  
**Use case:** A supervisor or QM analyst needs to triage a large volume of conversations quickly —
reading summaries instead of reviewing full recordings. Summaries also surface follow-up actions
that may have been committed but not delivered, which is a compliance and CSAT risk.

**Core question:** *What happened in this conversation in plain language, and was it resolved?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.speech.text.analytics` | seed → `conversationId` | Analysis status — confirms STA ran successfully before fetching sub-resources |
| 2 | `speechandtextanalytics.get.conversation.summaries` | `conversationId` | AI-generated abstractive summary, reason for contact, resolution flag, follow-up actions, agent coaching notes |
| 3 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic categories from STA program — business-level intent labels |
| 4 | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Sentiment timeline — combined with summary for complete picture |
| 5 *(optional)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcript download URL if verbatim is needed after summary review |

### Prerequisite Check

Step 2 and beyond are only meaningful when step 1 returns:
```json
{ "speechAndTextAnalyticsConversation": { "analysisStatus": "Success" } }
```
If `analysisStatus` is `NotAnalyzed` or `Cancelled`, skip steps 2–5.

### Summary Fields of Particular Value

| Field | Investigation Use |
|-------|------------------|
| `summaryText` | Triage — what happened in plain language |
| `reasonText` | Why the customer called — intent classification |
| `resolutionText` | Was the issue resolved? |
| `followUpText` | Were any follow-up commitments made by the agent? |
| `reminderText` | Coaching notes for the agent's supervisor |

### Executive Use

At scale, the `summaries` layer answers the question an executive dashboard cannot:
*what kinds of problems are customers bringing us?*
Aggregating `reasonText` values across conversations reveals demand patterns without
requiring topic configuration or phrase modelling.

---

## 17. Telephony Infrastructure Investigation

**Subject:** Organisation-wide (or specific region/site) + time window  
**Use case:** A voice engineer or network operations centre (NOC) team is investigating systemic
call quality degradation — not limited to one call, but a pattern affecting multiple calls on
specific Edge appliances, trunk groups, or during a specific time window.

**Core question:** *Which part of the telephony infrastructure is causing call quality issues, and what is the blast radius?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `telephony.get.edge.groups` | — | Named Edge groups — logical groupings of Edges sharing trunks; seed for site-level investigation |
| 2 | `telephony.get.edges` | `edgeGroupId` | All Edge appliances with registration status, software version, site assignment, and online/offline state |
| 3 | `telephony.get.trunks` | `edgeId` | SIP trunks per Edge — carrier, type (external/phone), registration state |
| 4 | `telephony.get.trunk.metrics.summary` | — | Organisation-wide trunk utilisation and error counters |
| 5 | `telephony.get.edge.performance.metrics` (fan-out on impacted Edges) | `edgeId` | CPU, memory, active call count, QoS mismatch count — resource pressure indicators |
| 6 | `alerting.get.alerts` | — | Currently firing platform alerts — may already document the incident |
| 7 | `alerting.get.rules` | — | Configured alert thresholds — confirms whether monitoring covers the affected metric |
| 8 *(targeted conversation)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace for a specific call suspected to be on the impacted Edge |
| 9 *(Edge log collection)* | `telephony.create.edge.logs.job` → `telephony.get.edge.logs.job` → `telephony.request.edge.logs.job.upload` | `edgeId` | Edge appliance log files for the time window — 3-step async log collection job |

### Key Joins

```
telephony.get.edge.groups[].id
  → telephony.get.edges[].edgeGroup.id (group → Edge mapping)

telephony.get.edges[].id
  → telephony.get.trunks[].edgeGroup (Edge → trunk mapping)
  → telephony.get.edge.performance.metrics (targeted pull for suspect Edges)
  → telephony.create.edge.logs.job.edgeId

telephony.get.trunks[].id
  → telephony.get.trunk.metrics.summary (trunk-level error correlation)

alerting.get.alerts[].rule.id
  → alerting.get.rules[].id (alert → rule → threshold)
```

### Analytical Questions Answered

- Are there Edges currently in an offline or degraded state?
- Which Edge groups and trunks show the highest error counts or QoS mismatches?
- Are any Edges running at CPU/memory thresholds that would explain audio degradation?
- Is an alert already firing for the incident, or is it below current alert thresholds?
- What does the SIP trace reveal for a specific call on the suspected Edge (codec, media IP, re-INVITE)?
- Where are the Edge log files needed for TAC case submission?

### Edge Log Collection Pattern

The Edge log collection is a 3-step async job:
```
Step 1: POST /api/v2/telephony/providers/edges/{edgeId}/logs/jobs
        → returns { jobId, state: "CREATED" }
Step 2: GET  /api/v2/telephony/providers/edges/{edgeId}/logs/jobs/{jobId}
        → poll until state = "COMPLETE"
Step 3: POST /api/v2/telephony/providers/edges/{edgeId}/logs/jobs/{jobId}/upload
        → triggers upload to a signed URL; returns download link
```

Datasets: `telephony.create.edge.logs.job` → `telephony.get.edge.logs.job` →
`telephony.request.edge.logs.job.upload`

---

## Updated Dataset Combination Reference Matrix

The matrix below extends the original to include datasets added in the June 2026 enrichment pass.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conv Deep Dive | Queue Inv | Division Inv | Exec Rollup | Real-Time | Agent Inv | Outbound Campaign | IVR Containment | Customer Journey | Recording Compliance | Sentiment QM | AI Summary | Telephony Infra |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | | ● | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | ● | ● | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | ○ | ○ | ● | | |
| `quality.get.surveys` | ● | | | ● | | | | | ● | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | | | | ● |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | ○ | ● | | ● | ● | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | | ● | ● | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | | ○ | |
| `speechandtextanalytics.get.conversation.summaries` | ○ | | | | | | | | ● | | ● | ● | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | ● | | | ● | ● | |
| `routing.get.single.queue.config` | | ● | | | | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | ● | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ● | ● | ● | ● | ● | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | ● | ● | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | ● | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | ● | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | ● | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | | ● | | |
| `quality.get.calibrations` | | | | | | | | | | | ○ | | |
| `quality.get.evaluation.form.detail` | | | | | | | | | | | ○ | | |
| `quality.get.published.evaluation.forms` | | | | | | | | | | | ● | | |
| `coaching.get.appointments` | | | ● | | | ○ | | | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | | ● | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | | ● | | | | | |
| `flows.get.all.flows` | | | | | | | | ● | | | | | |
| `flows.get.flow.outcomes` | | | | | | | | ● | | | | | |
| `flows.get.flow.milestones` | | | | | | | | ● | | | | | |
| `telephony.get.edge.groups` | | | | | | | | | | | | | ● |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | ○ | | | | | | ● |
| `telephony.get.edges` | | | | | ● | | | | | | | | ● |
| `telephony.get.trunks` | | | | | | | | | | | | | ● |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | | | | ● |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | | | | ● |
| `telephony.create.edge.logs.job` | | | | | | | | | | | | | ● |
| `telephony.get.edge.logs.job` | | | | | | | | | | | | | ● |
| `telephony.request.edge.logs.job.upload` | | | | | | | | | | | | | ● |
| `alerting.get.alerts` | | | | ○ | ● | | | | | | | | ● |
| `alerting.get.rules` | | | | | | | | | | | | | ● |
| `outbound.get.campaigns` | | | | | | | ● | | | | | | |
| `outbound.get.campaign.progress` | | | | | | | ● | | | | | | |
| `externalcontacts.get.contact` | | | | | | | | | ● | | | | |
| `recording.post.batch.requests` | | | | | | | | | | ● | | | |
| `recording.get.batch.request.status` | | | | | | | | | | ● | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | | | |
| `audit-logs` | | | | | | ● | | | | ○ | | | |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
