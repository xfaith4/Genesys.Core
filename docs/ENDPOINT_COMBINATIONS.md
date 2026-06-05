# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-05  
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
11. [Digital Conversation Investigation (Chat / Email / Messaging)](#11-digital-conversation-investigation-chat--email--messaging)
12. [AI Copilot & Agent Assist Enrichment](#12-ai-copilot--agent-assist-enrichment)
13. [External Contact & Repeat Caller Investigation](#13-external-contact--repeat-caller-investigation)
14. [Bot-Assisted & Self-Service Investigation](#14-bot-assisted--self-service-investigation)
15. [Recording & Compliance Coverage](#15-recording--compliance-coverage)

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
| `conversations.get.email.messages` | ○ | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | ○ |
| `conversations.get.call.detail` | ○ | | | | | |
| `conversations.get.conversation.participant.wrapup` | ○ | | | | | |
| `quality.get.conversation.surveys` | ○ | | | ● | | |
| `routing.get.queue.estimated.wait.time` | | | | | ○ | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | |
| `authorization.get.division.grants` | | | ○ | | | |
| `workforce.get.adherence.bulk` | | | | ● | ○ | |
| `workforce.get.agent.management.unit` | | | | | | ○ |
| `externalcontacts.get.contact.details` | ○ | | | | | |
| `analytics.query.bot.aggregates` | | | | ● | ○ | |
| `recording.get.media.retention.policies` | | | | ● | | |
| `analytics.query.knowledge.aggregates` | | | | ● | | ○ |

---

## 11. Digital Conversation Investigation (Chat / Email / Messaging)

**Subject:** One `conversationId` where `mediaType` is `chat`, `email`, `message`, or `webmessaging`  
**Use case:** An operator or QM analyst investigates a digital interaction — a chat abandoned mid-session, an email thread with no reply, a messaging conversation that escalated to a supervisor. Digital interactions lack SIP traces but have message threads, bot handoffs, and asynchronous session windows.

**Core question:** *What was the full digital interaction lifecycle — content, routing, AI enrichment, and customer outcome?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.specific.conversation.details` | seed → `conversationId` | Confirms `mediaType`, participant roster, `externalContactId`, originating direction, queue assignment |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment-level timing: ACD wait, agent response time, ACW — identical structure to voice |
| 3 *(email only)* | `conversations.get.email.messages` | `conversationId` | Full message thread: subject, body, from/to addresses, attachment metadata, timestamps |
| 4 | `conversations.get.conversation.summaries` | `conversationId` | Copilot/Agent Assist AI summary — reason for contact, resolution notes, wrap-up prediction |
| 5 *(chat/messaging, STA licensed)* | `conversations.get.speech.text.analytics` | `conversationId` | Sentiment score, detected topics, STA coverage summary for the digital session |
| 6 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Interaction categories (e.g., "Billing Dispute", "Technical Issue") applied by the S&TA engine |
| 7 | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | AI-generated per-leg summaries and detected key phrases from the S&TA transcription pipeline |
| 8 *(externalContactId non-null)* | `externalcontacts.get.contact.details` | `participants[].externalContactId` | Full CRM contact record — name, organisation, all phone/email identifiers, notes |
| 9 | `quality.get.evaluations.query` | `conversationId` (filter) | QM evaluation score, critical items, evaluator — digital interactions are fully evaluatable |
| 10 | `quality.get.conversation.surveys` | `conversationId` | Post-interaction CSAT/NPS survey outcome if triggered |

### Key Joins

```
conversations.get.specific.conversation.details.conversationId
  → analytics.get.single.conversation.analytics.conversationId
  → conversations.get.email.messages.conversationId         [email only]
  → conversations.get.conversation.summaries.conversationId
  → speechandtextanalytics.get.conversation.categories.conversationId
  → quality.get.evaluations.query[].conversationId          [left join]
  → quality.get.conversation.surveys[].conversationId       [left join]

conversations.get.specific.conversation.details.participants[].externalContactId
  → externalcontacts.get.contact.details.contactId          [left join, when non-null]
```

### Conditional Execution

| Step | Run When |
|------|----------|
| `conversations.get.email.messages` | `mediaType = 'email'` |
| `conversations.get.speech.text.analytics` | `mediaType in {chat, message, webmessaging}` and S&TA licensed |
| `speechandtextanalytics.get.conversation.categories` | S&TA licensed |
| `speechandtextanalytics.get.conversation.summaries.detail` | S&TA transcription pipeline active |
| `externalcontacts.get.contact.details` | `participants[].externalContactId` is non-null |

### Analytical Questions Answered

- What was the full message exchange? (email thread or chat session content)
- How long did the customer wait before an agent joined?
- What topic did the S&TA engine classify this interaction under?
- What was the Copilot summary — reason for contact, resolution?
- Who was the customer? Do they have a CRM record?
- Was the digital interaction scored by QM? What was the result?
- Did the customer complete a post-interaction survey?

### Digital-Specific Notes

- **Email threading:** `conversations.get.email.messages` returns all messages in the ACD email conversation, including reply chains. The `messageSubject` and `messageBody` fields are PII-rich — apply the `conversation-investigation-recordings` redaction profile.
- **Bot handoffs:** If the digital conversation was preceded by a bot session, the bot conversationId is linked via `participants[].purpose = 'acd'` segment transitions. Cross-reference with `analytics.query.bot.aggregates` to see if the bot resolved intent before escalating.
- **No SIP trace:** Digital conversations have no telephony signalling. The analytics detail record is the primary timing source.

---

## 12. AI Copilot & Agent Assist Enrichment

**Subject:** One `conversationId` or a set of conversations per agent/queue over a window  
**Use case:** An ops lead wants to confirm Agent Copilot is being used and adding value — are agents searching the knowledge base, are summaries being generated, does higher knowledge use correlate with better QM scores? A training team wants to identify agents who are not adopting AI tooling.

**Core question:** *Is Agent Copilot being used, and is it improving agent outcomes?*

### Dataset Steps — Per-Conversation Enrichment

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.summaries` | `conversationId` | Copilot AI summary: reason for contact, resolution notes, wrap-up code prediction |
| 2 | `analytics.query.knowledge.aggregates` | `conversationId`, `userId` | Knowledge searches, articles surfaced, document views, positive/negative feedback signals |
| 3 | `quality.get.evaluations.query` | `conversationId` | QM score alongside Copilot usage — correlation bridge |

### Dataset Steps — Per-Agent/Queue Adoption Rollup

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.knowledge.aggregates` | `userId`, `queueId` | Aggregate knowledge search counts, surfacing rate, document view rate per agent/queue |
| 2 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | AHT, nConnected — handle time baseline for adoption correlation |
| 3 | `quality.get.agents.activity` | `userId` | QM scores — correlation: does high knowledge use predict higher eval scores? |
| 4 *(low adopters)* | `coaching.get.appointments` | `userId` | Coaching schedule — confirm whether low-adoption agents have active coaching interventions |

### Key Joins

```
analytics.query.knowledge.aggregates.userId
  → analytics.query.conversation.aggregates.agent.performance.userId (AHT correlation)
  → quality.get.agents.activity.userId                                 (QM correlation)
  → coaching.get.appointments.userId                                   [left join]

conversations.get.conversation.summaries.conversationId
  → quality.get.evaluations.query[].conversationId                    [left join]
```

### Derived Metrics

| Metric | Formula |
|--------|---------|
| `knowledgeSurfacingRate%` | `nKnowledgeSurfaced / nConnected` |
| `knowledgeAdoptionRate%` | `nKnowledgeDocumentView / nKnowledgeSurfaced` |
| `knowledgeFeedbackScore%` | `nKnowledgeFeedbackPositive / (nKnowledgeFeedbackPositive + nKnowledgeFeedbackNegative)` |
| `copilotSummaryRate%` | conversations with non-empty summary / nConnected |

### Diagnostic Signals

- `nKnowledgeSearch = 0` for agent across window → agent not using knowledge search; coaching candidate
- `nKnowledgeFeedbackNegative / nKnowledgeSurfaced > 0.3` → articles surfaced are not relevant; review knowledge base content
- High AHT + low `nKnowledgeDocumentView` → agent searching manually rather than using Copilot
- `nKnowledgeSurfaced / nConnected` well below org average → queue may not have Agent Copilot configured
- Low knowledge use + low QM score + no `coaching.get.appointments` entry → immediate coaching intervention needed

---

## 13. External Contact & Repeat Caller Investigation

**Subject:** One `externalContactId` (CRM contact record) over a time window  
**Use case:** A supervisor or QM analyst suspects a customer has contacted the centre multiple times without resolution — the repeat-contact pattern. Investigation spans all conversations linked to that customer identity across any queue or channel, surfacing unresolved issues, CSAT trends, and escalation history.

**Core question:** *Why does this customer keep calling back, and is the issue getting resolved?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `externalcontacts.get.contact.details` | seed → `externalContactId` | Customer identity anchor: name, org, all phone numbers, email, CRM notes |
| 2 | `analytics-conversation-details-query` | `externalContactId` (filter via `participantAttributes` or ANI match) | All conversationIds for the customer in the window, queue routing, handle times, wrap-up codes |
| 3 *(fan-out)* | `conversations.get.specific.conversation.details` | `conversationId` per row | Full participant roster, state, queue assignment, originating direction per conversation |
| 4 *(fan-out)* | `conversations.get.conversation.summaries` | `conversationId` per row | Copilot reason-for-contact and resolution per conversation — rapid cross-conversation topic mapping |
| 5 *(fan-out)* | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` per row | Sentiment timeline per conversation — declining score across repeat contacts confirms systemic issue |
| 6 *(fan-out, optional)* | `quality.get.evaluations.query` | `conversationId` per row | QM scores — reveals whether QM caught repeated issues |
| 7 *(fan-out, optional)* | `quality.get.conversation.surveys` | `conversationId` per row | CSAT per conversation — tracks whether satisfaction improved or degraded across repeat contacts |

### Key Joins

```
externalcontacts.get.contact.details.id (= externalContactId)
  → analytics-conversation-details-query[].participants[].externalContactId
      → conversations.get.specific.conversation.details.conversationId  [fan-out]
      → conversations.get.conversation.summaries.conversationId         [fan-out]
      → speech.and.text.analytics.get.sentiment.for.conversation.id     [fan-out]
      → quality.get.evaluations.query[].conversationId                  [fan-out, left join]
      → quality.get.conversation.surveys[].conversationId               [fan-out, left join]
```

### Derived Metrics

| Metric | Formula |
|--------|---------|
| `repeatContactCount` | `COUNT(conversationIds)` in window |
| `firstContactResolutionRate%` | Conversations with `wrapUpCode != 'Unresolved'` / total |
| `avgCSATTrend` | CSAT scores ordered by `conversationStart` — slope indicates resolution trajectory |
| `escalationRate%` | Conversations with supervisor join or transfer / total |
| `channelSwitchCount` | Unique `mediaTypes` across the conversation set |

### Investigation Notes

- **Identity resolution:** `externalContactId` is not always populated. For voice, ANI matching against `externalcontacts.get.contact.details.phoneNumbers` may be needed to link conversations. This is a known gap — document in the run manifest.
- **Fan-out volume:** Limit the analytics query window to prevent excessive fan-out. A 90-day window on an active customer can return dozens of conversations.
- **Copilot summaries as rapid triage:** Running `conversations.get.conversation.summaries` in the fan-out before pulling full recordings allows the analyst to map all reasons for contact in seconds without listening to audio.

---

## 14. Bot-Assisted & Self-Service Investigation

**Subject:** One or more `botId` / `flowId` values over a time window, optionally scoped to a queue  
**Use case:** An IVR/bot engineer or operations lead investigates why self-service containment has dropped, why escalation rates are rising, or whether a recent bot training update improved intent matching. Combines bot aggregate metrics with flow execution data and the queue performance at the escalation destination.

**Core question:** *How effectively are bots and IVR flows resolving customer intent before reaching a live agent?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | seed | Flow inventory: name, type (bot/inbound/outbound), active version |
| 2 | `flows.get.flow.outcomes` | `flowId` | Configured outcome types for each flow — which outcomes indicate resolution vs. escalation |
| 3 | `analytics.query.bot.aggregates` | `botId`, `flowId` | Bot session counts, average turns per session, intent match rate, response time |
| 4 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Total executions, outcome distribution, exit reasons |
| 5 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` (escalation destination) | Post-escalation AHT and volume — the cost of bot failure |
| 6 *(real-time)* | `analytics.query.flow.observations` | `flowId` | Currently active flow sessions — use during a live degradation incident |

### Key Joins

```
flows.get.all.flows.id (= flowId)
  → flows.get.flow.outcomes.flowId
  → analytics.query.flow.aggregates.execution.metrics.groupByValue[flowId]
  → analytics.query.bot.aggregates.groupByValue[flowId]

analytics.query.bot.aggregates.groupByValue[botId]
  → flows.get.all.flows (botId is a flowId for bot flows in Genesys)

escalation destination queue from flow outcome
  → analytics.query.conversation.aggregates.queue.performance.groupByValue[queueId]
```

### Derived Metrics

| Metric | Formula |
|--------|---------|
| `containmentRate%` | Bot/flow sessions resolved without agent / total `nBotInteractions` |
| `intentMatchRate%` | `nBotIntentMatched / (nBotIntentMatched + nBotIntentNotMatched)` |
| `avgBotTurns` | `nBotSessionTurnAvgCount` |
| `escalationToAgentRate%` | `nFlowOutcomeFailed / nFlow` |
| `postEscalationAHT` | `tHandle` on conversations in the escalation queue |
| `botResponseTimeP95` | `tBotResponseTime` at P95 — latency indicator |

### Diagnostic Signals

- `intentMatchRate%` drop after a bot update → training regression; review added/modified intents
- `avgBotTurns` spike → bot asking more clarifying questions; simplify utterance model
- `containmentRate%` down + `escalation queue nOffered` up → bot failing to resolve; check flow outcome configuration
- `tBotResponseTime` P95 above 2s → NLU or fulfillment latency issue; check bot integration health
- `nBotInteractions` up + queue `oWaiting` unchanged → bot deflecting successfully at increased volume

### Voice Engineer Notes

- Run step 6 (`analytics.query.flow.observations`) first when triaging a live bot degradation — active session count confirms the scope before pulling historical aggregates.
- Compare `flows.get.flow.outcomes` against `analytics.query.flow.aggregates.execution.metrics` outcome distribution to confirm that all expected outcome types are firing.

---

## 15. Recording & Compliance Coverage

**Subject:** One queue, one agent, or the entire org over an audit window  
**Use case:** A compliance officer or QM manager needs to confirm that every interaction subject to recording policy was actually recorded and archived. Critical for GDPR/HIPAA audit periods, legal hold reviews, or after a recording system outage.

**Core question:** *Was every conversation that should have been recorded actually recorded, and is the recording safely retained?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `recording.get.media.retention.policies` | seed | Policy inventory: conditions (queue, agent, mediaType), retention duration, archival destination, deletion schedule |
| 2 | `routing-queues` | `queueId` | Queue metadata — confirm which queues are covered by which policies |
| 3 | `analytics-conversation-details-query` | `queueId` / window | All conversations in scope — the denominator for coverage calculation |
| 4 | `conversations.get.conversation.recording.metadata` | `conversationId` (fan-out) | Recording metadata per conversation: recording IDs, media type, duration, `archiveDate`, deletion status |
| 5 *(optional)* | `quality.get.evaluations.query` | `conversationId` (fan-out filter) | Evaluation coverage — confirms QM sampling rate against connected volume |

### Key Joins

```
recording.get.media.retention.policies[].conditions.queueIds[]
  → routing-queues.id (= queueId)
  → analytics-conversation-details-query[].queueId
      → conversations.get.conversation.recording.metadata.conversationId  [fan-out]
      → quality.get.evaluations.query[].conversationId                     [fan-out, left join]
```

### Derived Metrics

| Metric | Formula |
|--------|---------|
| `recordingCoverageRate%` | Conversations with ≥1 recording / `nConnected` |
| `evaluationCoverageRate%` | Conversations with ≥1 evaluation / `nConnected` |
| `recordingsAtRisk` | Recordings where `archiveDate < today` and `archiveDestination` is null |
| `policyMismatches` | Conversations where `recording.mediaType` ≠ `conversation.mediaType` |

### Diagnostic Signals

- `recordingCoverageRate% < 100%` on a policy-required queue → edge recording policy misconfigured or media capture service interrupted
- `archiveDate` past with no `archiveDestination` → archival export job not running; records at deletion risk
- `evaluationCoverageRate%` below target → QM staffing gap or form-filter misconfiguration
- `policyMismatches` > 0 → a recording exists but was captured under the wrong media classification; affects retention rule application
- Queue has conversations but no matching policy entry → coverage gap; queue was added after the policy was last reviewed

### Compliance Notes

- **Legal hold:** Conversations under an active legal hold should be excluded from `recordingsAtRisk` — check `recording.get.conversation.recording.metadata` for `restoreExpirationTime` before flagging for deletion risk.
- **Fan-out volume:** Limit the analytics query to the audit period only. Do not pull conversation-level recording metadata for the full retention window in one run.
- **Policy condition precedence:** Genesys applies the most specific matching policy. Confirm that the policy order in `recording.get.media.retention.policies` matches the expected precedence for the queues under audit.

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
