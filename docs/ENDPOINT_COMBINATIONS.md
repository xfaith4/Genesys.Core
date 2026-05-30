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
11. [AI Summary and Copilot Enrichment](#11-ai-summary-and-copilot-enrichment)
12. [Bot Containment and Data Action Diagnostics](#12-bot-containment-and-data-action-diagnostics)
13. [WFM Adherence and Performance Correlation](#13-wfm-adherence-and-performance-correlation)
14. [Queue Voicemail Overflow Analysis](#14-queue-voicemail-overflow-analysis)
15. [Extended Executive Rollup — AI, Bots, Surveys, Journey](#15-extended-executive-rollup--ai-bots-surveys-journey)
16. [Agent Station and Call Path Investigation](#16-agent-station-and-call-path-investigation)

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

## 11. AI Summary and Copilot Enrichment

**Subject:** One `conversationId` (or queue/agent rollup)  
**Use case:** A QM analyst or supervisor wants to review call content without listening to recordings. An executive wants to know what percentage of conversations have AI summaries and whether agents are engaging with Copilot suggestions. Two distinct endpoints serve this: the Genesys Copilot/Agent Assist summary (`conversations.get.conversation.summaries`) and the S&TA engine summary (`speechandtextanalytics.get.conversation.summaries.detail`).

**Core question:** *What did this conversation cover, what was resolved, and is the AI assistant being used?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Base conversation with participants, state, ANI/DNIS |
| 2 | `conversations.get.conversation.summaries` | `conversationId` | Copilot/Agent Assist AI summary: reason for contact, resolution outcome, follow-up actions |
| 3 | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | S&TA engine summary per communication leg with confidence score and coverage status |
| 4 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Category and topic classifications with phrase evidence (compliance, intent labelling) |
| 5 | `conversations.get.conversation.suggestions` | `conversationId` | All Copilot article/knowledge suggestions presented to the agent during the call |
| 6 *(exec rollup)* | `analytics.post.summaries.aggregates.query` | `queueId` / `userId` | nSummaries, oSummaryEngagement — Copilot adoption rate across queue or team |

### Key Joins

```
conversations.get.conversation.object.conversationId
  → conversations.get.conversation.summaries.conversationId (Copilot summary)
  → speechandtextanalytics.get.conversation.summaries.detail.conversationId (S&TA summary)
  → speechandtextanalytics.get.conversation.categories[].conversationId (topic labels)
  → conversations.get.conversation.suggestions[].conversationId (suggestion engagement)

analytics.post.summaries.aggregates.query.results[].group.queueId
  → routing-queues[].id (queue name label resolution)
```

### Analytical Questions Answered

- What was the reason for the customer's contact (AI-extracted)?
- Was the issue resolved in this interaction?
- What follow-up actions were recommended by Copilot?
- What topics and categories did the S&TA engine detect?
- Which knowledge articles did the agent receive as suggestions?
- Across the queue, what percentage of conversations received a Copilot summary? (adoption metric)

### Executive Reporting Use

`analytics.post.summaries.aggregates.query` with `groupBy: ["queueId"]` and `granularity: "P1D"` produces a daily trend of Copilot adoption. Divide `nSummaries` by `nConnected` (from queue performance aggregates) to produce the **Summary Coverage Rate** — the share of handled conversations where the AI summary fired. A summary coverage rate below 80% typically indicates agents are leaving conversations before the summary triggers or the S&TA pipeline is not fully configured.

---

## 12. Bot Containment and Data Action Diagnostics

**Subject:** Bot flows + IVR data actions (org-wide or filtered by flow/queue)  
**Use case:** A voice engineer or IVR developer investigates why customers are being handed off from the bot to an agent at a high rate, or why data lookups in the Architect flow are failing. Two analytics namespaces serve this: bot aggregates and actions aggregates.

**Core question:** *Are bots containing calls as expected, and are the data lookups in the IVR working correctly?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.post.bots.aggregates.query` | `botId` | nBotInteractions, nBotHandoffs, nBotSessions — containment rate and handoff frequency |
| 2 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone — Architect flow execution counters |
| 3 | `analytics.post.actions.aggregates.query` | `actionId` | nExecutions, nErrors, tExecution — data action error rate and latency per action |
| 4 | `flows.get.all.flows` | `flowId` | Flow name, type, and description to label analytics results |
| 5 *(drilldown)* | `analytics-conversation-details-query` (bot handoff filter) | `conversationId` | Individual conversations where bot handed off to agent — root cause evidence |
| 6 *(drilldown)* | `conversations.get.conversation.customattributes` | `conversationId` | IVR attributes set before handoff: intent, confidence score, data action result code |

### Bot Containment Rate Formula

```
containmentRate% = (nBotSessions - nBotHandoffs) / nBotSessions × 100
```

A healthy bot containment rate is typically 60–85% depending on channel and bot capability.
A sudden drop in containment rate combined with `nErrors > 0` in `analytics.post.actions.aggregates.query` almost always indicates a failing data action (CRM lookup, account auth, database call).

### Voice Engineer Notes

When `analytics.post.actions.aggregates.query` shows elevated `nErrors`:
1. Note the `actionId` and map it to the action name via the Integrations API
2. Cross-reference with `conversations.get.conversation.customattributes` — a `dataActionResult` of `FAILED` or `TIMEOUT` in the conversation attributes confirms the action failure was on the path of the affected conversation
3. Escalate to the integration owner with the `actionId`, error count, and a sample `conversationId`

### Analytical Questions Answered

- What is the bot containment rate per bot/flow?
- Which data actions have the highest error rate?
- How long do data actions take on average? Is latency degrading the caller experience?
- Which conversations were handed off from the bot, and what was in the IVR attributes at handoff?
- Which Architect flow milestone was last reached before the handoff?

---

## 13. WFM Adherence and Performance Correlation

**Subject:** One `managementUnitId` + time window  
**Use case:** A WFM manager or operations analyst investigates whether poor adherence is correlated with degraded queue performance — the classic "where are my agents?" question during a service-level miss.

**Core question:** *Which agents were out of adherence during the SLA miss, and is there a causal pattern?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.management.units` | seed → `managementUnitId` | Management unit name and business unit linkage |
| 2 | `workforce.get.management.unit.users` | `managementUnitId` | All agents in the WFM team — the population |
| 3 | `workforce.get.agent.management.unit` | `userId` | Confirm management unit assignment for individual agents |
| 4 | `workforce.get.adherence.bulk` | `userId` list | Current adherence state per agent: scheduled activity, actual presence, deviation seconds |
| 5 | `workforce.get.management.unit.adherence` | `managementUnitId` | Adherence snapshot for all agents in the unit simultaneously |
| 6 | `analytics.query.user.aggregates.login.activity` | `userId` | Time in each routing status: on-queue, off-queue, idle — joins to adherence state |
| 7 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | SLA and volume for queues served by this management unit during the window |
| 8 | `analytics.query.queue.aggregates.service.level` | `queueId` | SLA achievement per queue — the outcome being correlated |

### Key Joins

```
workforce.get.management.unit.users[].id
  → workforce.get.adherence.bulk[].user.id
  → analytics.query.user.aggregates.login.activity[].userId
  → analytics.query.user.aggregates.performance.metrics[].userId

workforce.get.management.unit.users[].queues[].id (if available)
  → analytics.query.conversation.aggregates.queue.performance[].group.queueId
  → analytics.query.queue.aggregates.service.level[].group.queueId
```

### Correlation Pattern

```
For each 15-minute interval in the window:
  oOutOfAdherence agents = count(adherence.state = 'OUT_OF_ADHERENCE')
  oWaiting callers = sum(queue.oWaiting) across managed queues
  SLA achievement = sum(nAnsweredInThreshold) / sum(nOffered)

High oOutOfAdherence + high oWaiting + low SLA = staffing gap driven by adherence
High oOutOfAdherence + low oWaiting + low SLA = routing or skill mismatch, not staffing
Low oOutOfAdherence + high oWaiting + low SLA = understaffed or unexpected volume spike
```

### Analytical Questions Answered

- Which agents were out of adherence when the SLA missed?
- What was the scheduled activity vs. actual presence for the team?
- Is the adherence deviation random (breaks/bathroom) or systematic (early logout, long ACW)?
- Did the SLA miss track with the number of out-of-adherence agents?
- Which queues were impacted, and which had members in the management unit?

---

## 14. Queue Voicemail Overflow Analysis

**Subject:** One `queueId` + time window  
**Use case:** A contact centre manager suspects that callers who abandon the queue are leaving voicemails instead of callbacks or re-calling. The ACD abandons metric does not capture voicemail volume — this combination closes that gap.

**Core question:** *How much call volume escapes the queue to voicemail, and when does it peak?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.single.queue.config` | seed → `queueId` | Queue config — voicemail enabled flag, after-hours config |
| 2 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | ACD abandons: nAbandoned, tAbandon — the ACD-visible abandons |
| 3 | `voicemail.get.queue.messages` | `queueId` | Voicemail messages left in the queue's shared mailbox — overflow count, timestamps, durations |
| 4 *(optional)* | `routing.get.queue.estimated.wait.time` | `queueId` | Real-time EWT — if high, expect voicemail intake to rise in the next interval |
| 5 *(enrichment)* | `analytics.query.queue.observations.real.time.stats` | `queueId` | Current oWaiting — validates whether queue pressure is active now |

### Analytical Questions Answered

- How many voicemails did the queue receive vs. how many callers abandoned the ACD queue?
- What is the average voicemail duration? (proxy for message complexity)
- At what time of day does voicemail volume peak?
- Are voicemails being assigned/returned, or are they sitting unread?
- Is voicemail volume correlated with EWT spikes?

### Voice Engineer Note

If the queue's `voicemailEnabled` flag is `false` in the queue config but voicemails are arriving, the voicemail overflow may be configured at the Architect flow level (via a menu action that routes to voicemail on no-answer), not at the queue level. In this case, check the flow's voicemail node configuration and the participant attributes from `conversations.get.conversation.customattributes` for a `vmRouted` attribute.

---

## 15. Extended Executive Rollup — AI, Bots, Surveys, Journey

**Subject:** Organisation-wide + reporting window (weekly/monthly)  
**Use case:** An extended version of the Executive Reporting Rollup (Section 4) that adds AI adoption, bot performance, CSAT aggregates, and journey analytics to the headline metrics.

**Core question:** *How are automation, AI, and customer experience trending alongside traditional volume and quality metrics?*

### Additional Layers (extend Section 4)

#### Layer 6 — AI and Automation
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.post.summaries.aggregates.query` | `queueId`, `userId`, daily | nSummaries, oSummaryEngagement (Copilot adoption) |
| `analytics.post.bots.aggregates.query` | `botId`, daily | nBotInteractions, nBotHandoffs (containment rate = 1 − handoffs/interactions) |
| `analytics.post.actions.aggregates.query` | `actionId`, daily | nExecutions, nErrors, tExecution (data action health) |

#### Layer 7 — Voice of Customer (Survey Aggregates)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.post.surveys.aggregates.query` | `queueId`, `userId`, daily | nSurveysSent, nSurveysCompleted, oSurveyTotalScore |

Survey response rate = `nSurveysCompleted / nSurveysSent × 100`.  
Note: `quality.get.surveys` returns individual survey records; `analytics.post.surveys.aggregates.query` returns pre-aggregated counts and scores — use the aggregate for rollup, the individual records for drilldown.

#### Layer 8 — Journey and Predictive Engagement
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.post.journeys.aggregates.query` | `journeyActionId`, daily | nJourneys — volume of predictive engagement triggers fired |
| `journey.get.action.maps` | — | Action map names for label resolution |

### Extended Executive Dashboard Metrics

```
AI Automation Layer:
  - Copilot Summary Coverage Rate: nSummaries / nConnected × 100
  - Bot Containment Rate: (nBotSessions - nBotHandoffs) / nBotSessions × 100
  - Data Action Error Rate: nErrors / nExecutions × 100 (health indicator)

Voice of Customer Layer:
  - Survey Response Rate: nSurveysCompleted / nSurveysSent × 100
  - Average CSAT Score: oSurveyTotalScore / nSurveysCompleted (normalise to 0–10 or 0–5)
  - Agent CSAT Ranking: from quality.get.agents.activity (if survey-linked evaluations)

Journey Layer:
  - Predictive Engagement Fire Rate: nJourneys / total web sessions (if web sessions tracked)
  - Journey-to-Contact Conversion: nJourneys where outcome = CONTACT / total nJourneys
```

### Key Joins for Extended Rollup

```
analytics.post.bots.aggregates.query[].group.botId
  → flows.get.all.flows (flow name for bot flows)
  → analytics-conversation-details-query (conversations with bot segments, for sample drilldown)

analytics.post.surveys.aggregates.query[].group.queueId
  → routing-queues[].id (queue name label resolution)
  → quality.get.agents.activity[].user.id (agent-level CSAT join)

journey.get.action.maps[].id
  → analytics.post.journeys.aggregates.query[].group.journeyActionId
```

---

## 16. Agent Station and Call Path Investigation

**Subject:** One `userId` at a specific point in time  
**Use case:** A voice engineer is troubleshooting an audio quality complaint, one-way audio, or missed calls for a specific agent. The physical station (phone or softphone), its Edge assignment, and call forwarding configuration collectively explain the inbound call path — and where audio problems originate.

**Core question:** *What hardware or softphone is this agent using, and does the call path explain the reported issue?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | Agent identity, current presence, routing status, and station field |
| 2 | `users.get.user.station` | `userId` | Station ID, type (ININ\_REMOTE\_STATION, ININ\_WEBRTC\_SOFTPHONE, etc.), Edge site |
| 3 | `users.get.user.callforwarding` | `userId` | Call forwarding enabled state, destination number, and caller ID overrides |
| 4 | `telephony.get.edges` | Edge site from step 2 | Edge registration status and software version |
| 5 | `telephony.get.edge.performance.metrics` | `edgeId` | Real-time CPU, memory, active call count, SIP error counters on the agent's Edge |
| 6 *(voice complaint)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace from the complaint conversation — codec negotiation, SDP IPs, error codes |
| 7 *(voicemail)* | `voicemail.get.user.messages` | `userId` | Voicemail messages — confirms agent received calls that were not answered |

### Key Joins

```
users.get.user.details.with.full.expansion.station.id
  → users.get.user.station.associatedStation.id (confirm active station)

users.get.user.station.associatedStation.edgeGroup.edges[].id
  → telephony.get.edges[].id (Edge registration status)
  → telephony.get.edge.performance.metrics.edgeId (live metrics)

telephony.get.sip.messages.for.conversation.sipMessages[].localSdp
  → users.get.user.station (verify SDP IP matches station IP — one-way audio diagnosis)
```

### Voice Engineer Diagnostic Patterns

| Symptom | Datasets to Pull | What to Look For |
|---------|-----------------|-----------------|
| One-way audio | SIP trace + station | SDP IP mismatch: local media IP in SIP does not match the station's registered IP |
| Calls not alerting | station + call forwarding | `callForwarding.enabled = true` rerouting before alert; or station not registered (STATION\_UNREGISTERED) |
| Missed calls going to voicemail | voicemail messages + routing status | `voicemail.count > 0` during periods agent was supposedly on-queue; check if agent was actually INTERACTING |
| Audio quality degradation | Edge metrics + SIP trace | Edge CPU > 85% correlates with jitter and packet loss in recorded calls |
| WebRTC softphone issues | station type + SIP trace | `ININ_WEBRTC_SOFTPHONE` station type: SIP trace will show DTLS/SRTP negotiation — check for ICE failures |

### Analytical Questions Answered

- What station type is the agent using right now?
- Is the agent's Edge healthy (CPU, memory, call count)?
- Does the agent have call forwarding enabled that might be intercepting calls?
- Do the SIP SDPs in the complaint call show the expected media IP for this station?
- Are voicemails building up, indicating missed calls the ACD is not capturing?

---

## Updated Dataset Combination Reference Matrix

The matrix below extends Section 10 with new datasets added in this revision.
`●` = used, `○` = optional/conditional.

| Dataset Key | Conv Deep Dive | Queue Inv | Division Inv | Exec Rollup | Real-Time | Agent Inv | AI/Bot | WFM Adherence | Call Path |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.summaries` | ○ | | | | | | ● | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | ● | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | ● | | |
| `conversations.get.conversation.participant.wrapup` | ● | | | | | | | | |
| `conversations.get.call.detail` | ● | | | | | | | | |
| `quality.get.conversation.surveys` | ● | | | | | | | | |
| `conversations.get.specific.conversation.details` | ● | | | | | | | | |
| `analytics.query.conversation.details.by.queue` | | ● | | | | ○ | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | | | | |
| `routing.get.queue.members.with.status` | | ● | | | | | | | |
| `routing.get.queue.wrapup.codes` | | ● | | | | | | | |
| `voicemail.get.queue.messages` | | ● | | ○ | | | | | |
| `authorization.get.division.grants` | | | ● | | | | | | |
| `authorization.search.division.objects` | | | ● | | | | | | |
| `analytics.post.summaries.aggregates.query` | | | | ● | | | ● | | |
| `analytics.post.bots.aggregates.query` | | | | ● | | | ● | | |
| `analytics.post.actions.aggregates.query` | | | | ○ | | | ● | | |
| `analytics.post.journeys.aggregates.query` | | | | ● | | | | | |
| `analytics.post.surveys.aggregates.query` | | | | ● | | | | | |
| `gamification.get.insights.user.details` | | | | | | ○ | | | |
| `gamification.get.leaderboard` | | | | ● | | | | | |
| `workforce.get.agent.management.unit` | | | | | | ● | | ● | |
| `workforce.get.adherence.bulk` | | | | | | ● | | ● | |
| `workforce.get.management.unit.adherence` | | | | | | | | ● | |
| `analytics.query.conversation.transcripts` | | | | ● | | | ● | | |
| `users.get.user.station` | | | | | | ○ | | | ● |
| `users.get.user.callforwarding` | | | | | | ○ | | | ● |
| `voicemail.get.user.messages` | | | | | | ○ | | | ● |
| `routing.get.contact.center.settings` | | | | | | | | | ○ |
| `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | ● | | | | | | ● | | |

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
| `nSummaries` | AI summaries generated (Copilot/Agent Assist) | Copilot adoption numerator |
| `oSummaryEngagement` | Agents who viewed or used a summary | Copilot engagement rate |
| `nBotInteractions` | Bot interactions started | Total bot traffic |
| `nBotHandoffs` | Bot sessions transferred to an agent | Bot escalation volume |
| `nBotSessions` | Distinct bot sessions | Bot containment denominator |
| `nExecutions` | Data action executions | IVR data lookup volume |
| `nErrors` | Data action execution errors | IVR data lookup failure count |
| `tExecution` | Data action execution duration | IVR data lookup latency |
| `nSurveysSent` | Post-call surveys delivered to customers | Survey deployment volume |
| `nSurveysCompleted` | Surveys completed by customers | Survey response count |
| `oSurveyTotalScore` | Aggregate CSAT/NPS survey score | Customer satisfaction aggregate |
| `nJourneys` | Predictive engagement journeys fired | Journey action trigger count |
| `adherenceState` | Current WFM adherence state (IN/OUT) | Per-agent compliance flag |
| `adherencePct` | Schedule adherence percentage for the window | Team compliance score |
| `estimatedWaitTimeSeconds` | Predicted wait time per media type | Real-time queue health |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
