# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-29  
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
10. [Campaign Investigation](#10-campaign-investigation)
11. [External Contact (CRM) Enrichment](#11-external-contact-crm-enrichment)
12. [Edge Log Extraction (Voice Engineer)](#12-edge-log-extraction-voice-engineer)
13. [Executive CSAT & Sentiment Rollup](#13-executive-csat--sentiment-rollup)
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

## 10. Campaign Investigation

**Subject:** One `campaignId` + time window  
**Use case:** An outbound operations manager needs to diagnose a running or recently-completed
campaign — low right-party contact rate, abandon rate exceeding the FCC/Ofcom threshold,
or contact list exhaustion ahead of schedule.

**Core question:** *Why is this campaign underperforming, and what can be fixed right now?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Dialing mode, queue, caller ID, abandon threshold, campaign status |
| 2 | `outbound.get.contact.lists` | `contactListId` | Contact list size — used to compute list-penetration rate |
| 3 | `routing.get.single.queue.config` | `queueId` | Answer-handling queue config (ACW, media settings) |
| 4 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Live pacing health, real-time abandon rate, current call count |
| 5 | `outbound.get.events` | `campaignId` | Dialer event stream: dispositions, call attempts, system events |
| 6 | `audit-logs` | `campaignId` | Who started/stopped the campaign and what config was changed |
| 7 | `analytics-conversation-details-query` | `campaignId` | All conversation rows tied to the campaign in the window |

### Key Joins

```
outbound.get.campaigns.contactListId
  → outbound.get.contact.lists.id (list penetration = events / list size)

outbound.get.campaigns.queueId
  → routing.get.single.queue.config.id (answer queue context)

analytics-conversation-details-query[].conversationId
  → quality.get.evaluations.query[].conversationId (opt-in: QM coverage)
```

### Analytical Questions Answered

- Is the current abandon rate within the regulatory threshold?
- What percentage of the contact list has been dialed (penetration rate)?
- What is the distribution of call dispositions (connected, busy, no-answer, DNC)?
- Was the campaign configuration changed recently before the issue began?
- How does average handle time on this campaign compare to the queue baseline?

### Diagnostic Signals

| Signal | Likely Cause |
|--------|-------------|
| `abandonRate% > 3%` | Pacing set too aggressive; reduce lines-per-agent ratio |
| `diagnostics.numberOfCalls = 0` but campaign `status = ON` | No eligible contacts remain; list exhausted |
| `listPenetration% > 95%` | List nearly exhausted; refresh or segment required |
| Audit shows `status` toggled repeatedly | Operator manually cycling campaign; investigate pacing rules |
| `tTalk = 0` on most conversations | Calls connecting but agents not answering (staffing gap) |

---

## 11. External Contact (CRM) Enrichment

**Subject:** One `conversationId` (or batch) where an external contact is present  
**Use case:** A contact centre analyst needs to correlate Genesys conversation data with
CRM records — identifying repeat contacts, tracking customer journey across channels,
or building a 360-degree view of a specific customer's interaction history.

**Core question:** *Who was this customer, what is their CRM profile, and have they contacted us before?*

### How to Identify External Contact Presence

`conversations.get.conversation.object` returns `participants[].externalContactId` when the
conversation is linked to an external contact. A non-null `externalContactId` triggers this enrichment.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | `externalContactId` from external participant |
| 2 | `externalcontacts.get.contact.details` | `externalContactId` | Name, company, primary phone, email, custom schema fields |
| 3 | `externalcontacts.get.contact.journey.sessions` | `contactId` | Digital journey sessions — web pages visited, app events before the call |
| 4 | `analytics-conversation-details-query` | `externalContactId` | All conversations this contact has had across the date window |
| 5 | `conversations.get.conversation.customattributes` | `conversationId` | IVR-captured account numbers, intent labels, escalation flags |

### Key Joins

```
conversations.get.conversation.object.participants[externalContactId]
  → externalcontacts.get.contact.details.id
  → externalcontacts.get.contact.journey.sessions.contactId

analytics-conversation-details-query[].conversationId (filter by externalContactId)
  → quality.get.evaluations.query (QM scores for this contact's history)
  → quality.get.surveys (CSAT responses from this contact)
```

### Analytical Questions Answered

- Who is the customer (name, company, account relationship)?
- How many times has this customer contacted us? What was each outcome?
- Did the customer visit the self-service web portal before calling? What pages?
- What custom attributes (CRM case ID, account tier) did the IVR capture?
- What quality scores have conversations with this customer received?
- Is this a first-contact resolution or a repeat contact situation?

### Divisions and External Contacts

External contacts are organisation-wide; they are not scoped to a division. If an investigation
covers multiple divisions, the same external contact record may surface across queues in different
divisions. Deduplicate on `externalContactId` before computing repeat-contact rates.

---

## 12. Edge Log Extraction (Voice Engineer)

**Subject:** One `edgeId` + incident time window  
**Use case:** A voice engineer has exhausted the SIP trace (`telephony.get.sip.messages.for.conversation`)
and needs raw Edge diagnostic logs — pcap captures, system logs, and RTP statistics — to diagnose
one-way audio, codec negotiation failures, or TLS handshake problems on the PSTN trunk.

**Core question:** *What does the Edge appliance log tell us that the SIP trace cannot?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `telephony.get.edges` | seed → `edgeId` | Edge status, site, firmware version, online status |
| 2 | `telephony.get.edge.performance.metrics` | `edgeId` | CPU, memory, active call count at time of extraction |
| 3 | `telephony.create.edge.logs.job` | `edgeId` | Create a log job specifying log level and incident time window |
| 4 | `telephony.get.edge.logs.job` | `jobId` | Poll until `jobStatus = COMPLETE` — logs are packaged |
| 5 | `telephony.request.edge.logs.job.upload` | `jobId` | Trigger S3 upload of selected log files for download |

### Key Joins

```
telephony.get.edges.id (edgeId)
  → telephony.create.edge.logs.job.edgeId
  → telephony.get.edge.logs.job.jobId (polling)
  → telephony.request.edge.logs.job.upload.jobId

telephony.get.sip.messages.for.conversation.timestamp
  → Edge log file timestamps (correlate SIP events to Edge log entries)
```

### Diagnostic Signals

| Signal | Interpretation |
|--------|---------------|
| `statusCode != 'ACTIVE'` before creating job | Edge in failover — confirm peer Edge state first |
| Log job stays `PENDING > 5 min` | Management-plane connectivity issue to Edge |
| `CPU > 80%` in performance metrics during incident | Edge under load — may have caused call quality degradation |
| Pcap shows RTP stream gaps | One-way audio or media negotiation failure |
| Sys-log shows `TLS handshake failed` | Certificate or cipher mismatch on PSTN trunk |
| `onlineStatus = DISCONNECTED` | Edge lost connection — check management network path |

### Voice Engineer Notes

Edge log extraction requires the `telephony:plugin:all` permission and is rate-limited. Create
one log job per incident window rather than one per conversation. Correlate log file timestamps
against `telephony.get.sip.messages.for.conversation` timestamps to identify the exact packet
sequence that preceded the call failure.

`telephony.get.edge.performance.metrics` should always be pulled alongside the log job to provide
resource-pressure context — a CPU spike explains RTP jitter even when the SIP trace looks clean.

---

## 13. Executive CSAT & Sentiment Rollup

**Subject:** Organisation-wide (or division-scoped) + reporting window (weekly/monthly)  
**Use case:** A VP of Customer Experience needs a single-page rollup that answers: are customers
satisfied, is satisfaction trending up or down, and which topics are driving dissatisfaction?

**Core question:** *What does the voice of the customer tell us this period, and where is action needed?*

### Dataset Steps (ordered by reporting layer)

#### Layer 1 — Survey Outcomes
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.surveys.aggregates` | `queueId`, `userId`, `surveyFormId`, daily | nSurveys, avgCsatScore (1–5), avgNpsScore (0–10), promoterCount, detractorCount |
| `quality.get.surveys` | `conversationId` | Individual survey responses for drilldown on low-score cases |

#### Layer 2 — Sentiment Trends
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | nAnalyzedConversations, avgAgentSentimentScore, avgCustomerSentimentScore, oSentimentScore |
| `speechandtextanalytics.get.topics` | — | Topic catalog — resolve topicId to topic name and description |

#### Layer 3 — Quality Correlation
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.evaluations.aggregates` | `userId`, `queueId`, daily | evalCount, avgEvaluationScore, criticalItemFailCount |
| `quality.get.agents.activity` | `userId` | Agent-level eval summary — fastest path to QM outliers |

### Key Joins

```
routing-queues[].id
  → analytics.query.surveys.aggregates[].group.queueId
  → analytics.post.transcripts.aggregates.query[].group.queueId
  → analytics.query.evaluations.aggregates[].group.queueId

analytics.query.surveys.aggregates[].group.userId
  → quality.get.agents.activity[].user.id (QM / CSAT correlation per agent)

speechandtextanalytics.get.topics[].id
  → analytics.post.transcripts.aggregates.query[].group.topicId (topic label resolution)
```

### Analytical Questions Answered

- What is the overall CSAT score and NPS for the period? Is it improving?
- Which queues have the lowest CSAT? Which agents correlate with low scores?
- Which S&TA topics are most associated with negative customer sentiment?
- Is there a correlation between low QM evaluation scores and low CSAT?
- What percentage of conversations were S&TA-analyzed (coverage gap)?

### Executive Dashboard Composition

```
Period: Last 28 days, daily granularity
Headline metrics (computed):
  - CSAT: AVG(avgCsatScore) weighted by nSurveys
  - NPS: (promoterCount - detractorCount) / nSurveys × 100
  - Survey response rate: nSurveys / nConnected × 100
  - Sentiment trend: week-over-week delta of avgCustomerSentimentScore
  - STA coverage: nAnalyzedConversations / nConnected × 100
  - Critical item fail rate: criticalItemFailCount / evalCount × 100

Supporting views:
  - CSAT trend line by queue (daily)
  - Top 10 topics by conversation volume with average sentiment overlay
  - Agent CSAT vs QM score scatter plot (outlier identification)
```

---

## 14. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conv Deep Dive | Queue Invest. | Division Invest. | Executive Rollup | Real-Time Monitor | Agent Invest. | Campaign Invest. | CSAT Rollup | Ext. Contact |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | | ● |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | ● |
| `conversations.search.participant.attributes` | ● | | | | | | | | |
| `conversations.get.call.detail` | ○ | | | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ○ | | | | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | | | | |
| `conversations.get.recordings` | ● | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | ● | | | ○ |
| `quality.get.surveys` | ● | | | ● | | | | ● | ○ |
| `analytics.query.evaluations.aggregates` | | | | ● | | ○ | | ● | |
| `analytics.query.surveys.aggregates` | | | | ● | | | | ● | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | |
| `telephony.create.edge.logs.job` | | | | | | | | | |
| `telephony.get.edge.logs.job` | | | | | | | | | |
| `telephony.request.edge.logs.job.upload` | | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | ○ | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | | | |
| `speechandtextanalytics.get.conversation.sentiments` | ○ | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | |
| `speechandtextanalytics.get.topics` | | | | | | | | ● | |
| `routing.get.single.queue.config` | | ● | | | | | ● | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ● | | ● |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | ● | ● | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | |
| `routing-queue-members` | | ● | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | |
| `authorization.search.division.objects` | | | ● | | | | | | |
| `authorization.get.division.grants` | | | ○ | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | | | | ● |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | ● | |
| `coaching.get.appointments` | | | ● | | | ○ | | | |
| `workforce.get.agent.management.unit` | | | | | | ● | | | |
| `workforce.get.adherence.bulk` | | | | | | ● | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | ● | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | ● | | | | | |
| `flows.get.all.flows` | | | | ● | ○ | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | |
| `telephony.get.edges` | | | | | ● | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | |
| `alerting.get.rules` | | | | ○ | ○ | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | |
| `audit-logs` | | | | | | ● | ● | | |
| `outbound.get.campaigns` | | | | | | | ● | | |
| `outbound.get.contact.lists` | | | | | | | ● | | |
| `outbound.get.campaign.diagnostics.summary` | | | | | | | ● | | |
| `outbound.get.events` | | | | | | | ● | | |
| `externalcontacts.get.contact.details` | | | | | | | | | ● |
| `externalcontacts.get.contact.journey.sessions` | | | | | | | | | ● |
| `workforce.get.business.units` | | | | ○ | | | | | |
| `workforce.get.management.units` | | | | ○ | | | | | |
| `workforce.get.management.unit.adherence` | | | | ● | | | | | |
| `workforce.get.management.unit.users` | | | | ● | | | | | |
| `stations.get.stations` | | | | | ● | | | | |

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
| `avgCsatScore` | Average CSAT score (1–5) | Customer satisfaction |
| `avgNpsScore` | Average NPS score (0–10) | Loyalty indicator |
| `promoterRate%` | Promoters / nSurveys × 100 | Net promoter health |
| `adherencePct` | Scheduled vs actual on-queue % | WFM compliance |
| `listPenetration%` | Contacts dialed / total contacts × 100 | Outbound campaign reach |
| `rightPartyContactRate%` | Connected to decision-maker / dialed × 100 | Outbound campaign quality |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
