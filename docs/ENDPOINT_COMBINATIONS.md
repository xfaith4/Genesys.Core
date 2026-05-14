# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-14  
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
11. [External Contact / Omnichannel Customer Investigation](#11-external-contact--omnichannel-customer-investigation)
12. [Quality Management Aggregate Deep Dive](#12-quality-management-aggregate-deep-dive)
13. [Bot Containment & Digital Deflection](#13-bot-containment--digital-deflection)
14. [WFM Schedule Adherence Investigation](#14-wfm-schedule-adherence-investigation)
15. [BYOI + External Routing Forensics (Voice Engineer)](#15-byoi--external-routing-forensics-voice-engineer)
16. [New Dataset Quick Reference](#16-new-dataset-quick-reference)

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

## 11. External Contact / Omnichannel Customer Investigation

**Subject:** One `externalContactId` (or phone/email resolved via identifier lookup)  
**Use case:** A customer has called multiple times, used chat, and filled out a survey — but each appears as a separate conversation. An operations analyst or customer experience lead needs the complete lifetime picture of one customer across all channels without manually correlating conversation IDs.

**Core question:** *What is the full history of this customer's interactions with us, across every channel?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 0 *(if only phone/email known)* | `externalcontacts.identifier.lookup` | phone / email → `externalContactId` | Resolves the Genesys contact ID from a caller's phone number or email address |
| 1 | `externalcontacts.get.contact.detail` | seed → `id` | Contact name, phone, email, organization link, all known identifiers |
| 2 | `analytics-conversation-details-query` | `externalContactId` predicate | Every conversation in Genesys linked to this contact — voice, chat, email, messaging |
| 3 | `externalcontacts.get.contact.journey.sessions` | `contactId` | Digital journey sessions — web activity, page views, app events before and between contacts (60-day retention) |
| 4 | `quality.get.evaluations.query` | `conversationId` (left join) | Quality evaluations for the customer's interactions |
| 5 | `quality.get.surveys` | `conversationId` (left join) | Post-interaction surveys completed by this customer |

### Key Joins

```
externalcontacts.identifier.lookup → externalContactId (step 0 pivot)

externalcontacts.get.contact.detail.id
  → analytics-conversation-details-query (conversationFilters.externalContactId predicate)
  → externalcontacts.get.contact.journey.sessions.contactId

analytics-conversation-details-query[].conversationId
  → quality.get.evaluations.query[].conversationId (left join)
  → quality.get.surveys[].conversationId (left join)
```

### Analytical Questions Answered

- How many times has this customer contacted us, and through which channels?
- What was their last interaction about? What was the outcome?
- How many of their calls were evaluated? What was the quality score trend?
- Did they complete a survey? What was their CSAT/NPS score?
- Did they visit the website or self-service portal before calling?
- Are there repeat contacts for the same issue? (First Contact Resolution gap)
- Were they served by the same agents across contacts, or a different agent each time?

### Lookup Entry Point

When only a caller's phone number is known (common when investigating a complaint call), prepend `externalcontacts.identifier.lookup` with `{ "identifier": { "type": "phone", "value": "+15005550000" } }`. This returns the `externalContactId` to seed all downstream steps without knowing the Genesys contact ID.

### BYOI Enrichment

For BYOI-injected conversations, the `externalTag` and `externalConversationId` on each conversation object are the provider's correlation IDs. Use `conversations.get.conversation.object` on each conversation to retrieve those fields and cross-reference the provider's system.

---

## 12. Quality Management Aggregate Deep Dive

**Subject:** Organisation-wide or per-queue/agent + reporting window  
**Use case:** A QM manager or Director of Quality needs accurate QM coverage rates and score distributions for a reporting period without waiting for the individual evaluations endpoint to paginate thousands of records. The aggregate endpoint returns pre-computed counts and score totals in one call.

**Core question:** *Are we evaluating enough interactions, and are scores improving?*

### Why Aggregates vs. Individual Evaluations

| Approach | Dataset | Speed | Use Case |
|----------|---------|-------|---------|
| Aggregate rollup | `analytics.query.evaluation.aggregates` | Fast (single POST) | Executive KPI cards, trend charts, coverage rates |
| Individual records | `quality.get.evaluations.query` | Slow (pages of records) | Drill-down to specific evaluations, see comments |
| Agent summary | `quality.get.agents.activity` | Fast | Agent-level score comparison without time-series |

### Dataset Steps (Executive QM Rollup)

| Step | Dataset Key | Grouping | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing-queues` | — | Queue names for label joins |
| 2 | `analytics.query.evaluation.aggregates` | `queueId`, `userId`, `evaluatorId` | nEvaluations, tEvaluationScore, nEvaluationsWithCriticalFail, nEvaluationsInProcess |
| 3 | `analytics.query.survey.aggregates` | `queueId`, `userId`, `surveyFormId` | nSurveys, oSurveyNpsScore, oSurveyScore |
| 4 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | nConnected — denominator for coverage rate calculation |
| 5 | `quality.get.published.evaluation.forms` | — | Form names to decode evaluationFormId |

### Derived Metrics

```
evaluationCoverageRate%  = nEvaluations / nConnected × 100
avgEvaluationScore%      = tEvaluationScore / nEvaluations
criticalFailRate%        = nEvaluationsWithCriticalFail / nEvaluations × 100
surveyResponseRate%      = nSurveys / nConnected × 100
avgCsatScore             = oSurveyScore / nSurveys
avgNpsScore              = oSurveyNpsScore / nSurveys
```

### Executive Alert Thresholds

- Coverage < 5% on any queue → understaffed QM team or evaluation assignment gap
- Critical fail rate > 10% → policy compliance issue; escalate to training
- CSAT < 3.5 / 5 → CX deterioration signal; cross-reference with sentiment trends
- NPS < 30 → detractor risk; identify which queues and agents drive the score

### Key Joins

```
routing-queues[].id
  → analytics.query.evaluation.aggregates[].group.queueId (label resolution)

analytics.query.evaluation.aggregates[].group.userId
  → analytics.query.conversation.aggregates.queue.performance[].group.userId
    (coverage rate denominator: nConnected per agent)
```

---

## 13. Bot Containment & Digital Deflection

**Subject:** Organisation-wide or per-flow + reporting window  
**Use case:** A digital transformation director or operations VP needs to measure the ROI of bot and IVR self-service investments — what percentage of contacts are resolved without reaching an agent, and how does this vary by channel and flow?

**Core question:** *How much are bots and IVR deflecting from human agents, and is it improving?*

### Containment Hierarchy

```
Total inbound contacts (nOffered from digital-channels dataset)
  └─ Bot handled (nBotFinalIntents from bot.aggregates)
  └─ IVR self-served (nFlowOutcome from flow.aggregates)
  └─ Escalated to queue (nConnected from queue performance)
       └─ Completed with agent
       └─ Abandoned in queue
```

### Dataset Steps (ordered)

| Step | Dataset Key | Grouping | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | — | Flow names and types for label joins |
| 2 | `flows.get.flow.outcomes` | — | Outcome definitions (self-service, escalation, error) |
| 3 | `analytics.query.bot.aggregates` | `botFlowId`, `botFlowType` | nBotSessions, nBotIntents, nBotFinalIntents, tBotSession |
| 4 | `analytics.query.flow.aggregates.execution.metrics` | `flowId`, `flowType` | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone |
| 5 | `analytics.query.conversation.aggregates.digital.channels` | `mediaType`, `queueId` | nOffered, nConnected, nAbandoned by channel — total contact volume denominator |

### Key Metrics

```
botContainmentRate%        = nBotFinalIntents / nBotSessions × 100
ivrContainmentRate%        = nFlowOutcome / nFlow × 100
overallDeflectionRate%     = (nBotFinalIntents + nFlowOutcome) / nOffered × 100
avgBotSessionDuration      = tBotSession / nBotSessions (seconds)
botEscalationRate%         = (nBotSessions - nBotFinalIntents) / nBotSessions × 100
flowFailureRate%           = nFlowOutcomeFailed / nFlow × 100
```

### Voice Engineer Notes

A `flowFailureRate% > 10%` on any flow warrants immediate investigation using the `flow-and-ivr-diagnostics` voice engineer playbook. Combine with `analytics-conversation-details-query` filtered by `flowId` in `segmentFilters` to identify which specific conversations experienced the failures.

### Key Joins

```
flows.get.all.flows[].id
  → analytics.query.bot.aggregates[].group.botFlowId (bot flow name resolution)
  → analytics.query.flow.aggregates.execution.metrics[].group.flowId (IVR flow name)

flows.get.flow.outcomes[].id
  → analytics.query.flow.aggregates.execution.metrics[].group.flowOutcomeId (outcome label)
```

---

## 14. WFM Schedule Adherence Investigation

**Subject:** One `managementUnitId` + schedule date range  
**Use case:** A WFM analyst or operations manager investigating why a queue had a service level miss during a specific shift — did agents show up as scheduled, were they on the right activity, and does scheduled staffing match historical volume?

**Core question:** *Were agents working their scheduled hours, and did staffing match demand?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.business.units` | — | Business unit names for context |
| 2 | `workforce.get.management.units` | `businessUnitId` | Management unit details (team name, timezone) |
| 3 | `workforce.get.management.unit.users` | `managementUnitId` | Full agent roster for the team |
| 4 | `workforce.get.agent.management.unit` | `userId` | Confirms which management unit each agent belongs to (pivot for individual agent investigations) |
| 5 | `workforce.get.agent.schedule` | `managementUnitId` | Scheduled shifts — activity type, start/end, paid hours per agent |
| 6 | `workforce.get.historical.adherence` | `managementUnitId` | Actual vs. scheduled state — adherence %, variance minutes, exceptions |
| 7 | `workforce.get.adherence.bulk` | `userId` list | Real-time current adherence state (point-in-time, for live investigations) |
| 8 | `analytics.query.user.aggregates.login.activity` | `userId` | Login/logout timing and on-queue time for the window (corroboration) |

### Key Joins

```
workforce.get.management.unit.users[].id (userId)
  → workforce.get.agent.schedule.userSchedules[].userId
  → workforce.get.historical.adherence.userAdherenceRecords[].userId
  → analytics.query.user.aggregates.login.activity[].group.userId

workforce.get.historical.adherence[].scheduledActivityCategory
  → schedule activityCodes (join to interpret activity type labels)
```

### Derived Metrics

```
adherencePct%          = actualOnQueueMinutes / scheduledOnQueueMinutes × 100
scheduleVarianceMins   = scheduledMinutes − actualMinutes (signed)
exceptionRate%         = exceptionsCount / scheduledShifts × 100
occupancyPct%          = tInteracting / tOnQueue × 100 (from login activity)
```

### Analytical Questions Answered

- Which agents were non-adherent during the service level miss window?
- Were agents scheduled but not logged in? (No-show vs. late arrival)
- Were agents on a scheduled break or unplanned off-queue activity?
- Does the schedule have enough agents to meet the forecasted volume?
- Which management units consistently have the lowest adherence?
- Is there a correlation between adherence drops and service level misses?

### WFM Investigation Entry Points

| Known Information | Start With |
|-------------------|------------|
| Management unit ID | Steps 2-8 in order |
| Individual agent | `workforce.get.agent.management.unit` → then steps 5-8 |
| Queue with SLA miss | `routing.get.single.queue.config` → `divisionId` → `users.division.analysis.get.users.with.division.info` → `workforce.get.agent.management.unit` per agent |

---

## 15. BYOI + External Routing Forensics (Voice Engineer)

**Subject:** One `conversationId` that was injected via the BYOI provider API  
**Use case:** A voice engineer or integration architect is investigating a call that arrived via a third-party telephony provider integrated through the Genesys BYOI framework. The call shows anomalies — one-way audio, unexpected disconnect, wrong agent group — and both the Genesys SIP trace and the provider's logs need to be correlated.

**Core question:** *Where did this BYOI call come from, how was it handed off, and what went wrong in the provider-to-Genesys path?*

### How to Confirm a BYOI Call

`conversations.get.conversation.object` returns these BYOI indicators:

```json
{
  "externalTag": "<provider-correlation-ID>",
  "externalConversationId": "<provider-call-ID>",
  "participants": [
    { "purpose": "external", "externalContactId": "..." }
  ]
}
```

A non-null `externalTag` is the definitive BYOI indicator. Use `externalTag` to cross-reference the provider's call log.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | `externalTag`, `externalConversationId`, `participants[purpose=external].externalContactId`, ANI/DNIS |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing: IVR, ACD wait, talk, hold, ACW — confirms Genesys-side call flow |
| 3 | `conversations.get.conversation.customattributes` | `conversationId` | Provider-injected context: CRM case ID, intent label, external call ID |
| 4 | `conversations.search.participant.attributes` | `conversationId` | IVR/Architect variables set after BYOI injection |
| 5 | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace for the BYOI SIP-to-SIP handoff (not PSTN) |
| 6 | `externalcontacts.get.contact.detail` | `externalContactId` from step 1 | External contact profile — name, org, identifiers |
| 7 | `externalcontacts.get.contact.journey.sessions` | `contactId` | Customer's digital journey before the BYOI call was initiated |

### Diagnostic Signals — BYOI Specific

| Signal | Cause | Action |
|--------|-------|--------|
| `externalTag` set but `externalConversationId` is null | Provider did not send the conversation ID in the inject payload | Check provider BYOI implementation against `POST /api/v2/conversations/providers/{providerId}/calls` spec |
| SIP From-header domain is provider domain, not org domain | Expected for BYOI — provider → Edge SIP-to-SIP path | Verify From-header matches provider's registered SIP trunk identity |
| `tTalk = 0` + SIP 200 OK in trace | Media path established but audio not flowing | SDP `c=` address mismatch between provider's media server and Edge; check NAT traversal |
| No SIP INVITE in trace | Call went through WebRTC/SDK BYOI path, not SIP | Examine `conversations.get.conversation.customattributes` for `byoiTransportType` |
| `participants[purpose=external]` missing | BYOI inject did not specify externalContactId | Update provider integration to pass `externalContactId` in inject body |
| `customAttributes` empty | Provider did not pass context attributes in inject | Provider implementation gap; contact is unlinked to CRM |

### Key Joins

```
conversations.get.conversation.object.participants[purpose=external].externalContactId
  → externalcontacts.get.contact.detail.id
  → externalcontacts.get.contact.journey.sessions.contactId

conversations.get.conversation.object.externalTag
  → provider's external call log (cross-system join — manual)
```

---

## 16. New Dataset Quick Reference

This section lists all datasets added in the May 2026 catalog update, with their API paths and primary use cases.

### Analytics Aggregates (new)

| Dataset Key | API Path | Primary Use |
|-------------|----------|-------------|
| `analytics.query.evaluation.aggregates` | `POST /api/v2/analytics/evaluations/aggregates/query` | QM coverage rate, avg score, critical fail rate by queue/agent/evaluator |
| `analytics.query.survey.aggregates` | `POST /api/v2/analytics/surveys/aggregates/query` | CSAT/NPS aggregate scores by queue/agent/form |
| `analytics.query.bot.aggregates` | `POST /api/v2/analytics/bots/aggregates/query` | Bot containment rate, intent resolution, session duration |

### External Contacts (new domain)

| Dataset Key | API Path | Primary Use |
|-------------|----------|-------------|
| `externalcontacts.identifier.lookup` | `POST /api/v2/externalcontacts/identifierlookup` | Resolve contactId from phone number or email |
| `externalcontacts.get.contact.detail` | `GET /api/v2/externalcontacts/contacts/{contactId}` | Customer profile, identifiers, org link |
| `externalcontacts.get.contact.journey.sessions` | `GET /api/v2/externalcontacts/contacts/{contactId}/journey/sessions` | Digital session history (60-day retention) |

### WFM Detailed (new)

| Dataset Key | API Path | Primary Use |
|-------------|----------|-------------|
| `workforce.get.agent.schedule` | `POST /api/v2/workforcemanagement/managementunits/{id}/agentschedules/search` | Scheduled shifts — start/end, activity type, paid hours |
| `workforce.get.historical.adherence` | `POST /api/v2/workforcemanagement/managementunits/{id}/historicaladherencequery` | Historical adherence — scheduled vs. actual state with variance |
| `workforce.get.adherence.bulk` | `GET /api/v2/workforcemanagement/adherence` | Real-time adherence state for multiple agents |
| `workforce.get.agent.management.unit` | `GET /api/v2/workforcemanagement/agents/{agentId}/managementunit` | Resolve agent's management unit and business unit IDs |

### Referenced-but-Previously-Missing (now added)

| Dataset Key | API Path | Primary Use |
|-------------|----------|-------------|
| `routing.get.queue.estimated.wait.time` | `GET /api/v2/routing/queues/{queueId}/estimatedwaittime` | Predicted caller wait time in seconds, by media type |
| `speechandtextanalytics.get.conversation.categories` | `GET /api/v2/speechandtextanalytics/conversations/{id}/categories` | STA topic/category classifications for a conversation |
| `conversations.get.conversation.summaries` | `GET /api/v2/conversations/{conversationId}/summaries` | AI Copilot reason-for-contact and resolution notes |
| `authorization.get.division.grants` | `GET /api/v2/authorization/divisions/{divisionId}/grants` | Access control grants for a division |

### Updated Combination Patterns

| Pattern Key | Section | Type |
|-------------|---------|------|
| `external-contact-investigation` | §11 | Investigation recipe |
| `evaluation-aggregate-kpis` | §12 | Executive playbook |
| `bot-containment-and-digital-deflection` | §13 | Executive playbook |
| `wfm-schedule-adherence-deep-dive` | §14 | Executive playbook |
| `byoi-and-external-routing-investigation` | §15 | Voice engineer playbook |

---

## Updated Dataset Combination Reference Matrix

The additions below extend the matrix from Section 10. `●` = used, `○` = optional/conditional.

| Dataset Key | Ext. Contact Inv. | QM Aggregate Rollup | Bot Containment | WFM Adherence | BYOI Forensics |
|---|:---:|:---:|:---:|:---:|:---:|
| `externalcontacts.identifier.lookup` | ○ | | | | ○ |
| `externalcontacts.get.contact.detail` | ● | | | | ● |
| `externalcontacts.get.contact.journey.sessions` | ● | | | | ● |
| `analytics-conversation-details-query` | ● | | | | |
| `quality.get.evaluations.query` | ○ | | | | |
| `quality.get.surveys` | ○ | | | | |
| `analytics.query.evaluation.aggregates` | | ● | | | ○ |
| `analytics.query.survey.aggregates` | | ● | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | | |
| `quality.get.published.evaluation.forms` | | ● | | | |
| `analytics.query.bot.aggregates` | | | ● | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | ● | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | ● | | |
| `flows.get.all.flows` | | | ● | | |
| `flows.get.flow.outcomes` | | | ● | | |
| `workforce.get.business.units` | | | | ● | |
| `workforce.get.management.units` | | | | ● | |
| `workforce.get.management.unit.users` | | | | ● | |
| `workforce.get.agent.management.unit` | | | | ● | ○ |
| `workforce.get.agent.schedule` | | | | ● | |
| `workforce.get.historical.adherence` | | | | ● | |
| `workforce.get.adherence.bulk` | | | | ○ | |
| `analytics.query.user.aggregates.login.activity` | | | | ● | |
| `conversations.get.conversation.object` | | | | | ● |
| `analytics.get.single.conversation.analytics` | | | | | ● |
| `conversations.get.conversation.customattributes` | | | | | ● |
| `conversations.search.participant.attributes` | | | | | ● |
| `telephony.get.sip.messages.for.conversation` | | | | | ● |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
