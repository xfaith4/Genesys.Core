# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-11  
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
11. [Digital Channel Investigation (Chat / Email / Messaging)](#11-digital-channel-investigation-chat--email--messaging)
12. [BYOI Full Provenance Chain](#12-byoi-full-provenance-chain)
13. [Executive QM & VoC Combined Rollup](#13-executive-qm--voc-combined-rollup)
14. [Bot Containment & Self-Service Analysis](#14-bot-containment--self-service-analysis)
15. [Knowledge Base & Agent-Assist Effectiveness](#15-knowledge-base--agent-assist-effectiveness)
16. [Agent Station & Audio Quality Investigation](#16-agent-station--audio-quality-investigation)
17. [New Dataset Quick Reference](#17-new-dataset-quick-reference)

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
| `nEvaluations` | Evaluations completed in the window | QM coverage numerator |
| `oEvaluationScore` | Average evaluation score | QM quality indicator |
| `nEvaluationsCriticalItem` | Evaluations with a critical item failure | Compliance risk signal |
| `nSurveySent` | Post-call surveys triggered | VoC outreach volume |
| `nSurveyResponses` | Surveys with a customer response | VoC response rate denominator |
| `oSurveyScore` | Average CSAT score from survey responses | Customer satisfaction |
| `nSurveyPromoter` | Survey responses scoring 9–10 (NPS) | Promoter count |
| `nSurveyDetractor` | Survey responses scoring 0–6 (NPS) | Detractor count |
| `nBotSessions` | Total bot/virtual-agent sessions initiated | Self-service attempt volume |
| `nBotSessionsContained` | Bot sessions resolved without live agent | Containment count |
| `nBotTransfers` | Bot sessions escalated to a live agent | Escalation count |
| `tSessionMinutes` | Total bot session duration | Self-service engagement time |
| `nKnowledgeSessionSuggestions` | Agent-assist suggestions surfaced to agents | Suggestion delivery |
| `nKnowledgeConfirmedAnswers` | Suggestions accepted/confirmed by agents | Suggestion acceptance |
| `nKnowledgeSelfServiceArticles` | Self-service article views (non-agent) | Self-service deflection |

---

## 11. Digital Channel Investigation (Chat / Email / Messaging)

**Subject:** One `conversationId` where `mediaType ∈ {chat, email, message, callback}`  
**Use case:** A supervisor or QM analyst is reviewing a digital interaction — a chat that went poorly, an email that took too long, or a WhatsApp message thread with a complaint. They need the same structured investigation as a voice call, adapted to the digital context.

**Core question:** *What happened in this digital interaction and why did the customer or agent experience it that way?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.specific.conversation.details` | seed → `conversationId` | Media type, state, participants, originatingDirection, email subject/from/to, chat queue |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timeline: routing wait, chat active time, ACW, hold (if callback) |
| 3 | `conversations.get.conversation.participant.wrapup` | `conversationId` + `participantId` | Wrapup code per agent participant — iterate over agent participants from step 1 |
| 4 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs — for digital, may include chat transcript or email body recording |
| 5 | `conversations.get.conversation.summaries` | `conversationId` | AI Copilot summaries: reason for contact, resolution, action items |
| 6 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | S&TA topic/category classifications via text analytics (chat and messaging) |
| 7 | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | S&TA-generated per-leg summaries (distinct from Copilot summaries) |
| 8 | `quality.get.evaluations.query` | `conversationId` (filter) | QM evaluation scores, form used, evaluator |
| 9 | `quality.get.conversation.evaluation.detail` | `conversationId` + `evaluationId` | Per-question scores and critical answers — drill-in from step 8 evaluation IDs |
| 10 | `quality.get.conversation.surveys` | `conversationId` | CSAT/NPS survey result scoped to this conversation |

### Key Joins

```
conversations.get.specific.conversation.details.participants[{purpose=agent}].id
  → conversations.get.conversation.participant.wrapup.participantId  (per agent)

analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
  → speechandtextanalytics.get.conversation.summaries.detail (per-leg)

quality.get.evaluations.query[].evaluationId
  → quality.get.conversation.evaluation.detail.evaluationId  (drill-in)
```

### Channel Variations

| Channel | tTalk Meaning | AI Summary | STA |
|---------|---------------|------------|-----|
| Chat | Active chat engagement time (exclude idle periods) | High value — saves reading the transcript | Text analytics applies |
| Email | Time to read + compose the response | Highest value — email threads are long | Text analytics applies |
| Messaging (SMS/WhatsApp) | Async thread span hours to days | Critical — conversation may span multiple shifts | Text analytics applies |
| Callback | Agent-initiated outbound leg; voice after connect | Lower value — treat as voice post-connection | Voice STA applies |

### Analytical Questions Answered

- How long did the customer wait before an agent accepted the digital interaction?
- What wrapup code was applied and by which agent?
- What did Copilot summarise as the reason for contact and resolution?
- Were any compliance or topic categories detected in the transcript?
- Was the agent evaluated? What were the per-question scores?
- Did the customer respond to the CSAT survey?

---

## 12. BYOI Full Provenance Chain

**Subject:** One `conversationId` with `externalTag ≠ null`  
**Use case:** A conversation was injected via the BYOI provider API (`POST /api/v2/conversations/providers/{providerId}/calls`). Platform engineers and integrations teams need to correlate the Genesys conversation record back to the originating external system (CRM case, third-party call ID, external SBC).

**BYOI Detection:** `GET /api/v2/conversations/{conversationId}` returning a non-null `externalTag` or `externalConversationId` confirms BYOI injection. Any participant with `purpose = external` further confirms.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | `externalTag`, `externalConversationId`, external participant purpose, originatingDirection |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing — applies identically for BYOI conversations |
| 3 | `conversations.get.conversation.customattributes` | `conversationId` | **Primary cross-system linkage** — provider-set fields: CRM case ID, external call ID, correlation token |
| 4 | `conversations.search.participant.attributes` | `conversationId` | IVR/Architect flow variables set during the injected conversation |
| 5 | `conversations.get.conversation.summaries` | `conversationId` | Copilot AI summaries (if licensed) |
| 6 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording metadata — proceeds identically for BYOI |
| 7 | `quality.get.evaluations.query` | `conversationId` (filter) | QM evaluation if assigned |
| 8 | `quality.get.conversation.surveys` | `conversationId` | CSAT survey result |
| 9 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace showing provider SIP-to-SIP handoff — From/To headers carry provider SIP identity |

### Key Joins

```
conversations.get.conversation.object.externalTag
  → external CRM / ticketing system (out-of-band lookup using the tag value)

conversations.get.conversation.customattributes.results[]
  → provider-specific fields, e.g. "crmCaseId", "externalCallId", "correlationToken"

telephony.get.sip.messages.for.conversation[{method=INVITE}].headers.From
  → provider's SIP identity / originating SBC address
```

### Analytical Questions Answered

- Was this conversation BYOI-injected? (externalTag check)
- What external system originated this call? (custom attributes + SIP From header)
- What IVR context did the provider supply? (participant attributes)
- Did Genesys apply its full quality process (recording, evaluation, CSAT)?
- Where in the SIP signalling did the provider hand off to Genesys? (SIP trace)

---

## 13. Executive QM & VoC Combined Rollup

**Subject:** Organisation-wide or multi-queue + reporting window (weekly/monthly)  
**Use case:** A QM Manager or VP of Operations needs a single view of quality and customer satisfaction — QM scores, evaluation coverage, CSAT, and NPS — aggregated at queue and division level, suitable for the monthly executive review deck.

**Core question:** *How are we performing on quality and customer experience, and where are the gaps?*

### Dataset Steps by Layer

#### Layer 1 — QM Coverage & Score

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.evaluations.aggregates.by.queue` | `queueId`, `userId`, daily granularity | nEvaluations, oEvaluationScore, nEvaluationsCriticalItem |
| `quality.get.published.evaluation.forms` | — | Form definitions for label resolution (formId → form name) |
| `quality.get.agents.activity` | `userId` | Per-agent eval count, avg/high/low scores — for agent-level QM comparison |

#### Layer 2 — Voice of Customer

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.surveys.aggregates.by.queue` | `queueId`, daily granularity | nSurveySent, nSurveyResponses, oSurveyScore, nSurveyPromoter, nSurveyDetractor |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | oSentimentScore, nSpeechTextAnalyzedConversations — STA sentiment trend |

#### Layer 3 — QM + Volume Context (join with Layer 1)

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.conversation.aggregates.queue.performance` | `queueId`, daily | nConnected — denominator for qmCoverageRate |

### Computed Executive Metrics

```
QM Coverage Rate      = SUM(nEvaluations) / SUM(nConnected) × 100   (per queue, per month)
Avg QM Score          = AVG(oEvaluationScore)                        (weighted by nEvaluations)
Critical Fail Rate    = SUM(nEvaluationsCriticalItem) / SUM(nEvaluations) × 100
Survey Response Rate  = SUM(nSurveyResponses) / SUM(nSurveySent) × 100
NPS Score             = (nSurveyPromoter - nSurveyDetractor) / nSurveyResponses × 100
Avg CSAT              = AVG(oSurveyScore)
STA Sentiment Trend   = daily AVG(oSentimentScore) — negative trend flags CX degradation
```

### Key Joins

```
routing-queues[].id
  → analytics.query.evaluations.aggregates.by.queue[].group.queueId
  → analytics.query.surveys.aggregates.by.queue[].group.queueId
  → analytics.query.conversation.aggregates.queue.performance[].group.queueId

analytics.query.evaluations.aggregates.by.queue[].group.userId
  → quality.get.agents.activity[].user.id  (agent-level detail)

analytics.query.evaluations.aggregates.by.queue[].group.formId
  → quality.get.published.evaluation.forms[].id  (form name resolution)
```

---

## 14. Bot Containment & Self-Service Analysis

**Subject:** Organisation-wide or specific bot/flow + reporting window  
**Use case:** A VP of Digital or Head of Operations needs to know what percentage of interactions are being handled without a live agent. Used for capacity planning, bot investment justification, and IVR performance reviews.

**Core question:** *How effectively is automation containing interactions, and where are callers escalating to live agents?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.bot.aggregates` | `botId` / `flowId` / `queueId` | nBotSessions, nBotSessionsContained, nBotTransfers, nBotSessionsAbandoned, tSessionMinutes |
| 2 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | nFlow, nFlowOutcome, nFlowOutcomeFailed — flow execution health |
| 3 | `flows.get.all.flows` | `flowId` | Flow name resolution — join friendly name onto bot/flow IDs |
| 4 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | nConnected — live agent volume for containment rate denominator |
| 5 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | nAbandoned — post-bot abandon rate (callers leaving after escalation) |

### Computed Executive Metrics

```
Containment Rate    = nBotSessionsContained / nBotSessions × 100
Escalation Rate     = nBotTransfers / nBotSessions × 100
Self-Service Defl.  = nBotSessionsContained / (nBotSessionsContained + nConnected) × 100
Bot Abandon Rate    = nBotSessionsAbandoned / nBotSessions × 100
Flow Failure Rate   = nFlowOutcomeFailed / nFlow × 100
```

### Diagnostic Signals

- Containment Rate sudden drop → bot config change or NLU degradation; check `flows.get.all.flows` for recent publishes
- nBotTransfers spike without nBotSessions change → new intent falling through to escalation path
- nFlowOutcomeFailed / nBotSessions > 0.05 → backend data action timeouts inside the bot flow
- nBotSessionsAbandoned / nBotSessions > 0.15 → excessive bot menu depth or poor prompt UX

---

## 15. Knowledge Base & Agent-Assist Effectiveness

**Subject:** Organisation-wide or per-queue + reporting window  
**Use case:** A Contact Centre Director or Knowledge Manager wants to understand whether Agent Assist is helping agents handle interactions faster and with higher quality — and whether the knowledge base is surfacing the right articles.

**Core question:** *Is Agent Assist making agents more effective, and is the knowledge base content relevant?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.knowledge.aggregates` | `queueId` / `userId` / `knowledgeBaseId` | nKnowledgeSessionSuggestions, nKnowledgeConfirmedAnswers, nKnowledgeSelfServiceArticles |
| 2 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | tHandle (avg) per agent — AHT comparison for agents using vs. not using assist |
| 3 | `quality.get.agents.activity` | `userId` | avgQMScore — quality comparison for agents with high vs. low suggestion acceptance |
| 4 | `analytics.post.transcripts.aggregates.query` | `queueId` | oSentimentScore — sentiment context alongside suggestion data |

### Computed Metrics

```
Suggestion Accept Rate   = nKnowledgeConfirmedAnswers / nKnowledgeSessionSuggestions × 100
Agent Assist Coverage    = nKnowledgeSessionSuggestions / nConnected × 100   (requires step 2 join)
Self-Service Rate        = nKnowledgeSelfServiceArticles / nKnowledgeSessionSuggestions × 100
```

### Diagnostic Signals

- Suggestion Accept Rate < 10% → agents not engaging; check UI placement or suggestion latency
- Agent Assist Coverage < 50% → knowledge base topic gaps for this queue's common intents
- High suggestionAcceptRate but no QM score improvement → suggestions accurate but insufficient to influence evaluation criteria
- Zero nKnowledgeSessionSuggestions for a queue → knowledge base not configured for that queue's Architect flow

---

## 16. Agent Station & Audio Quality Investigation

**Subject:** One `userId` + optional `conversationId`  
**Use case:** An agent reports one-way audio, echo, clipping, or dropped calls. A voice engineer needs to trace the complaint from the agent's phone/softphone through the Edge appliance to the SIP trunk, using the specific call's signalling and media endpoint statistics as evidence.

**Core question:** *Is this a phone problem, a network problem, or a trunk/Edge problem — and what does the SIP trace say?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | `station.id`, `station.type` (WebRTC/desk-phone), current presence and routing status |
| 2 | `stations.get.stations` | `stationId` from step 1 | Station type (WebRTC/managed/BYOC), line appearances, registered WebRTC endpoint |
| 3 | `telephony.get.edges` | `edgeId` from station (BYOC/managed only) | Edge `statusCode`, `onlineStatus`, `softwareVersion`, peer connections |
| 4 | `telephony.get.edge.performance.metrics` | `edgeId` from step 3 | Real-time CPU, memory, `activeCallCount`, SIP error counters |
| 5 *(specific call)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SDP offer/answer (codec, IP, port), re-INVITE events, BYE cause |
| 6 *(specific call)* | `analytics.get.single.conversation.analytics` | `conversationId` | `mediaEndpointStats`: MOS score, jitter, packet loss, round-trip time |

### Key Joins

```
users.get.user.details.with.full.expansion.station.id
  → stations.get.stations[].id (station detail)
  → telephony.get.edges[].stationIds[] (edge ↔ station mapping, if managed)

telephony.get.sip.messages.for.conversation[{method=INVITE}].headers.Contact
  → Edge IP address (confirms which edge handled the call)

analytics.get.single.conversation.analytics.participants[].sessions[].mediaEndpointStats
  → MOS score < 3.5 confirms audible quality degradation
```

### Diagnostic Decision Tree

| Symptom | Check | Signal |
|---------|-------|--------|
| One-way audio | SIP SDP offer/answer IP | RFC1918 NAT IP in SDP → ICE failure; check STUN/TURN config |
| Echo | Station type | WebRTC softphone → acoustic echo; Managed phone → tail cancellation issue |
| Clipping / choppy | Edge CPU or mediaEndpointStats.jitter | CPU > 80% → resource-induced loss; jitter > 40ms → QoS issue |
| Call drops | SIP BYE cause + edge online status | `DISCONNECTED` edge during window → edge failover mid-call |
| No SIP trace returned | Edge type | BYOC Cloud trunk → carrier-side SIP; engage Genesys Cloud Support |

### Enrichment

```
telephony.get.trunk.metrics.summary → confirm trunk error rates were normal during the window
alerting.get.alerts               → check for active edge/trunk alerts during the window
audit-logs (service=Telephony)    → recent Edge config changes that could affect routing
```

---

## 17. New Dataset Quick Reference

The following datasets were added in the 2026-06-11 catalog update. Each resolves gaps identified from the `combinations` section and from the Genesys API evaluation.

| Dataset Key | API Path | Primary Use Case |
|-------------|----------|-----------------|
| `conversations.get.call.detail` | `GET /api/v2/conversations/calls/{conversationId}` | Voice-specific call legs, hold events, ANI/DNIS routing path |
| `conversations.get.conversation.participant.wrapup` | `GET /api/v2/conversations/{conversationId}/participants/{participantId}/wrapup` | Wrapup code per agent participant in multi-participant conversations |
| `conversations.get.conversation.summaries` | `GET /api/v2/conversations/{conversationId}/summaries` | Copilot AI-generated reason for contact, resolution, action items |
| `speechandtextanalytics.get.conversation.categories` | `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/categories` | S&TA topic/category classifications with confidence scores |
| `speechandtextanalytics.get.conversation.summaries.detail` | `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/summaries` | S&TA per-leg AI summaries |
| `quality.get.conversation.evaluation.detail` | `GET /api/v2/quality/conversations/{conversationId}/evaluations/{evaluationId}` | Per-question evaluation scores and critical item answers |
| `quality.get.conversation.surveys` | `GET /api/v2/quality/conversations/{conversationId}/surveys` | CSAT/NPS survey result scoped to a single conversation |
| `routing.get.queue.estimated.wait.time` | `GET /api/v2/routing/queues/{queueId}/estimatedwaittime` | Real-time EWT for a queue — used in live supervisor views |
| `authorization.get.division.grants` | `GET /api/v2/authorization/divisions/{divisionId}/grants` | RBAC grants within a division for access audit |
| `workforce.get.agent.management.unit` | `GET /api/v2/workforcemanagement/agents/{agentId}/managementunit` | Agent WFM management unit — bridge to schedule/adherence |
| `workforce.get.adherence.bulk` | `GET /api/v2/workforcemanagement/adherence` | Bulk schedule adherence for a list of agents |
| `analytics.query.conversation.details.by.queue` | `POST /api/v2/analytics/conversations/details/query` | Conversation-level analytics detail filtered to one queue |
| `analytics.query.evaluations.aggregates.by.queue` | `POST /api/v2/analytics/evaluations/aggregates/query` | QM score aggregates by queue and agent — executive QM reporting |
| `analytics.query.surveys.aggregates.by.queue` | `POST /api/v2/analytics/surveys/aggregates/query` | CSAT/NPS aggregates by queue — executive VoC reporting |
| `analytics.query.bot.aggregates` | `POST /api/v2/analytics/bots/aggregates/query` | Bot/virtual-agent containment, transfer, and session metrics |
| `analytics.query.knowledge.aggregates` | `POST /api/v2/analytics/knowledge/aggregates/query` | Knowledge base suggestion, acceptance, and self-service metrics |
| `routing.get.skill.group.members` | `GET /api/v2/routing/skillgroups/{skillGroupId}/members` | Agents in a routing skill group — preferred-agent routing investigation |

### Key Analytics Metrics Added

| Metric | Source Dataset | Meaning |
|--------|----------------|---------|
| `nEvaluations` | `analytics.query.evaluations.aggregates.by.queue` | Evaluation volume — QM coverage numerator |
| `oEvaluationScore` | `analytics.query.evaluations.aggregates.by.queue` | Average evaluation score — QM quality indicator |
| `nEvaluationsCriticalItem` | `analytics.query.evaluations.aggregates.by.queue` | Critical failure count — compliance risk signal |
| `nSurveySent` / `nSurveyResponses` | `analytics.query.surveys.aggregates.by.queue` | VoC outreach and response volumes |
| `oSurveyScore` | `analytics.query.surveys.aggregates.by.queue` | Average CSAT score |
| `nSurveyPromoter` / `nSurveyDetractor` | `analytics.query.surveys.aggregates.by.queue` | NPS promoter/detractor counts for NPS calculation |
| `nBotSessions` | `analytics.query.bot.aggregates` | Total bot sessions — self-service attempt volume |
| `nBotSessionsContained` | `analytics.query.bot.aggregates` | Sessions resolved without live agent — containment count |
| `nBotTransfers` | `analytics.query.bot.aggregates` | Escalations from bot to live agent |
| `nKnowledgeSessionSuggestions` | `analytics.query.knowledge.aggregates` | Agent-assist suggestions surfaced |
| `nKnowledgeConfirmedAnswers` | `analytics.query.knowledge.aggregates` | Suggestions accepted by agents |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
