# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-28  
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
11. [Campaign Investigation (Deep Dive)](#11-campaign-investigation-deep-dive)
12. [Agent Assist & Copilot Conversation Enrichment](#12-agent-assist--copilot-conversation-enrichment)
13. [Edge Log Collection Workflow (Voice Engineer)](#13-edge-log-collection-workflow-voice-engineer)
14. [Alerting Configuration & Active Alert Review](#14-alerting-configuration--active-alert-review)
15. [API Health & Governance Rollup](#15-api-health--governance-rollup)
16. [Routing Skill Coverage Analysis](#16-routing-skill-coverage-analysis)

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
| 3 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by IVR/Architect flows (account numbers, intent labels, escalation flags, external CRM IDs) |
| 4 | `conversations.search.participant.attributes` | `conversationId` | Participant-level flow variables: DTMF input, data action results, bot intent scores |
| 5 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs, media type, duration, deletion schedule |
| 6 | `quality.get.evaluations.query` | `conversationId` | QM evaluation scores, form used, evaluator, calibration status |
| 7 | `quality.get.surveys` | `conversationId` | Post-call CSAT/NPS survey result if survey was triggered |
| 8 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace: INVITE, 200 OK, BYE, re-INVITE, codec negotiation |
| 9 *(STA enabled)* | `conversations.get.speech.text.analytics` | `conversationId` | Sentiment score, detected topics, STA coverage summary |
| 10 *(STA enabled)* | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Sentiment timeline: per-utterance scores, agent vs customer breakdown |
| 11 *(transcription enabled)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId` + `communicationId` | Transcript download URL per communication leg |
| 12 *(Agent Assist enabled)* | `conversations.get.conversation.suggestions` | `conversationId` | Agent Assist suggestion list: type, confidence, timestamp per suggestion |
| 13 *(Agent Assist enabled)* | `conversations.get.conversation.suggestion.detail` | `suggestionId` (from step 12) | Full suggestion content: article title, source KB, confidence score |

### Key Joins

```
conversations.get.conversation.object.conversationId
  → analytics.get.single.conversation.analytics.conversationId (segment overlay)
  → conversations.get.conversation.customattributes.conversationId (IVR context)
  → conversations.search.participant.attributes.conversationId (participant flow vars)
  → conversations.get.conversation.recording.metadata.conversationId
  → telephony.get.sip.messages.for.conversation.conversationId (voice only)
  → quality.get.evaluations.query[].conversationId (left join — evaluations may not exist)
  → conversations.get.conversation.suggestions[].conversationId (Agent Assist only)

analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
  → speechandtextanalytics.get.conversation.communication.transcripturl.communicationId

conversations.get.conversation.suggestions[].id
  → conversations.get.conversation.suggestion.detail.suggestionId (one call per suggestion)
```

### Analytical Questions Answered

- What was the full call flow? (IVR → ACD → agent → hold → ACW)
- How long did the customer wait before an agent answered?
- Was the call transferred? How many times? What queue received the transfer?
- What data did the IVR capture? (custom attributes: account number, intent, DTMF selections)
- What flow variables did data actions set during the interaction?
- Was a recording made? Does it still exist?
- Did the SIP trunk establish media correctly? (from SIP trace)
- Was the agent rated? What was the QM score?
- Was the customer surveyed? What was the CSAT result?
- Did Agent Assist surface suggestions? What articles were recommended?

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

| Dataset Key | Conv Deep Dive | Queue Inv. | Division Inv. | Exec Rollup | Real-Time | Agent Inv. | Campaign Inv. | Agent Assist | Edge Logs | Alerting | API Gov. | Skill Analysis |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | ● | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | ● | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | ○ | | | | |
| `quality.get.surveys` | ● | | | ● | | | | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | | |
| `conversations.get.conversation.suggestions` | ○ | | | | | | | ● | | | | |
| `conversations.get.conversation.suggestion.detail` | ○ | | | | | | | ● | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | | | ● | | | | |
| `routing.get.single.queue.config` | | ● | | | | | ● | | | | | ● |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ● | | | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | | | | ● |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | | | ● |
| `authorization.get.single.division` | | | ● | | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | | | |
| `coaching.get.appointments` | | | ● | | | ○ | | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | ● | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | ● | | | |
| `telephony.get.edges` | | | | | | | | | ● | | | |
| `telephony.create.edge.logs.job` | | | | | | | | | ● | | | |
| `telephony.get.edge.logs.job` | | | | | | | | | ● | | | |
| `telephony.request.edge.logs.job.upload` | | | | | | | | | ● | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | ● | | |
| `alerting.get.rules` | | | | | | | | | | ● | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | | ● |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | | ● |
| `routing.get.all.routing.skills` | | | | | | | | | | | | ● |
| `routing.get.skill.groups` | | | | | | | | | | | | ● |
| `audit-logs` | | | | | | ● | ● | | | | ● | |
| `outbound.get.campaigns` | | | | ● | | | ● | | | | | |
| `outbound.get.contact.lists` | | | | ● | | | ● | | | | | |
| `outbound.get.events` | | | | ● | | | ● | | | | | |
| `outbound.get.messaging.campaigns` | | | | ● | | | ○ | | | | | |
| `outbound.get.campaign.diagnostics.summary` | | | | | | | ● | | | | | |
| `oauth.get.clients` | | | | | | | | | | | ● | |
| `oauth.get.authorizations` | | | | | | | | | | | ● | |
| `oauth.post.client.usage.query` | | | | | | | | | | | ● | |
| `usage.get.api.usage.by.client` | | | | | | | | | | | ● | |
| `usage.get.api.usage.by.user` | | | | | | | | | | | ● | |
| `usage.get.api.usage.organization.summary` | | | | | | | | | | | ● | |
| `analytics.query.rate.limit.aggregates` | | | | | | | | | | | ● | |
| `organization.get.organization.limits` | | | | | | | | | | | ● | |
| `conversations.get.active.calls` | | | | | ● | | | | | | | |
| `conversations.get.active.chats` | | | | | ● | | | | | | | |
| `conversations.get.active.callbacks` | | | | | ● | | | | | | | |
| `conversations.get.active.emails` | | | | | ● | | | | | | | |

---

## 11. Campaign Investigation (Deep Dive)

**Subject:** One `campaignId` + time window  
**Use case:** An outbound operations manager or compliance officer needs to understand a specific dialing campaign — its configuration, contact list scope, real-time diagnostics, per-contact dispositions, the conversations it connected, and who changed the campaign settings.

**Core question:** *How did this outbound campaign perform, and is it within compliance thresholds?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Campaign name, status, dialingMode, queueId, callerIdName, configuredAbandonRate, contactListId |
| 2 | `outbound.get.contact.lists` | `contactListId` (from step 1) | Contact list name, size, columnNames, attemptLimit |
| 3 | `routing.get.single.queue.config` | `queueId` (from step 1) | Answer-handling queue: ACW settings, scoring method, DNIS |
| 4 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Live pacing health, dialerErrors, callsInProgress, outstanding interactions |
| 5 | `outbound.get.events` | `campaignId` | Per-contact disposition events: callResult, attemptNumber, timestamp |
| 6 | `analytics-conversation-details-query` (outboundCampaignId filter) | `conversationId` | Analytics for every connected conversation: tTalk, tHandle, tAcw, wrapUpCode, agentId |
| 7 | `audit-logs` (EntityType=Campaign, EntityId=campaignId) | `campaignId` | Who started, paused, or modified the campaign in the window |
| 8 *(digital campaigns)* | `outbound.get.messaging.campaigns` | `campaignId` | SMS/digital campaign config: messagingCampaignStatus, smsConfig, callableTimes |

### Key Joins

```
outbound.get.campaigns.id
  → outbound.get.contact.lists.id (contactListId)
  → routing.get.single.queue.config.id (queueId)
  → outbound.get.campaign.diagnostics.summary.campaignId
  → outbound.get.events.campaignId

outbound.get.events[].contactId
  → analytics-conversation-details-query (cross-reference by outboundCampaignId filter)
```

### Analytical Questions Answered

- What is the campaign's current dial mode and configured abandon rate? Does it comply with FTC ≤3% threshold?
- How many contacts were attempted? What was the right-party contact rate?
- What disposition outcomes dominated (no answer, busy, machine, RPC, voicemail)?
- For connected conversations: what was the AHT? What wrapup codes were used?
- Who changed campaign settings during the window? Did a configuration change correlate with a performance drop?

### Compliance Note (FTC Abandon Rate)

Step 5 (`outbound.get.events`) provides raw dispositions. Derive the FTC abandon rate as:
```
abandonRate% = (dispositions where callResult = ABANDONED) / (total connected attempts) × 100
```
If `abandonRate% > 3`, cross-reference step 7 (audit) to determine whether the pacing algorithm was modified recently. The configured `abandonRate` in step 1 is the threshold Genesys enforces — verify it matches your compliance policy.

---

## 12. Agent Assist & Copilot Conversation Enrichment

**Subject:** One `conversationId` where Agent Assist or Copilot is configured  
**Use case:** A CX designer or QM analyst wants to understand whether Agent Assist surfaced relevant knowledge during a conversation — what was suggested, at what confidence, whether the agent used the suggestion, and how the Copilot summary compared to the actual wrapup.

**Core question:** *Did Agent Assist provide useful suggestions, and is the Copilot summary accurate?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.get.single.conversation.analytics` | seed → `conversationId` | Timing baseline: tTalk, mediaType, participant list, session IDs |
| 2 | `conversations.get.conversation.object` | `conversationId` | Confirms queue, direction, participants — validates Agent Assist was in scope |
| 3 | `conversations.get.conversation.suggestions` | `conversationId` | All suggestions surfaced: type, confidence, trigger event, timestamp |
| 4 | `conversations.get.conversation.suggestion.detail` | `suggestionId` (per row from step 3) | Full content per suggestion: article title, source KB, confidence score, article ID |
| 5 | `conversations.get.conversation.summaries` | `conversationId` | Copilot AI summary: reason for contact, resolution, follow-up actions |
| 6 | `quality.get.evaluations.query` (filter by conversationId) | `conversationId` | QM score — correlate suggestion quality with evaluation outcome |

### Key Joins

```
conversations.get.conversation.object.conversationId
  → conversations.get.conversation.suggestions[].conversationId

conversations.get.conversation.suggestions[].id (suggestionId)
  → conversations.get.conversation.suggestion.detail.suggestionId  ← one call per suggestion

conversations.get.conversation.summaries.summary.resolution
  → analytics.get.single.conversation.analytics.participants[].wrapupCode  ← correlation check
```

### Analytical Questions Answered

- How many suggestions were surfaced? What types (knowledge article, FAQ, script prompt)?
- What was the confidence score distribution? Were low-confidence suggestions surfacing too often?
- Which knowledge-base articles were suggested most frequently across conversations?
- Does the Copilot summary reason-for-contact field match the wrapup code selected?
- Is there a correlation between conversations with Agent Assist suggestions and higher QM scores?

### CX Designer Notes

`conversations.get.conversation.suggestions` step is conditional — if Agent Assist is not configured on the queue that handled the conversation, the response will be empty. Confirm Agent Assist is active by checking `routing.get.single.queue.config` for `agentAssist` configuration.

For volume analysis across many conversations, use `analytics-conversation-details-query` filtered by `queueId` to identify the full conversation set, then fan out step 3 per conversationId. This is a high-API-call pattern — batch and rate-limit accordingly.

---

## 13. Edge Log Collection Workflow (Voice Engineer)

**Subject:** One `edgeId` (specific Edge appliance)  
**Use case:** A voice engineer has exhausted the SIP trace (`telephony.get.sip.messages.for.conversation`) and needs raw Edge-level packet capture or syslog output — for media path failures, one-way audio, or intermittent disconnects that don't appear in SIP messages alone.

**Core question:** *What do the Edge appliance's raw logs reveal that the SIP trace didn't?*

### Workflow Steps (ordered, async)

| Step | Dataset Key | API Path | What It Does |
|------|-------------|----------|--------------|
| 1 | `telephony.get.edges` | `GET /api/v2/telephony/providers/edges` | Enumerate Edges; confirm target Edge is `ACTIVE` |
| 2 | `telephony.get.edge.performance.metrics` | `GET /api/v2/telephony/providers/edges/{edgeId}/metrics` | CPU/memory headroom check — defer if CPU > 80% to avoid impacting live calls |
| 3 | `telephony.create.edge.logs.job` | `POST /api/v2/telephony/providers/edges/{edgeId}/logs/jobs` | Submit log collection job for the time window (SIP, Media, System log types) |
| 4 | `telephony.get.edge.logs.job` | `GET /api/v2/telephony/providers/edges/{edgeId}/logs/jobs/{jobId}` | Poll until `status = COMPLETED` (typically 2–5 minutes) |
| 5 | `telephony.request.edge.logs.job.upload` | `POST /api/v2/telephony/providers/edges/{edgeId}/logs/jobs/{jobId}/upload` | Request file upload to configured SFTP/S3 destination |

### Diagnostic Signals

- **Edge `statusCode != ACTIVE`** → do not initiate a log job; Edge is offline or in failover
- **Edge CPU > 80%** (step 2) → defer log collection to avoid call processing impact
- **Log job `status = FAILED`** → Edge may be isolated from management network; check connectivity
- **Log job returns zero files** → time window predates log retention (default 7 days on-appliance)
- **SIP pcap shows one-way audio** → correlate with media IP in SDP (`c=` line) against Edge WAN IP to confirm NAT translation issue

### Voice Engineer Notes

Log files are binary (`.pcap` for media, syslog for system events). After upload, retrieve from the configured storage destination and analyse in Wireshark or a SIP analyser (e.g. SIPp, Homer).

If the problem conversation traversed a redundant Edge pair, run one log job per Edge. The SIP trace (`telephony.get.sip.messages.for.conversation`) identifies which Edge handled a conversation via the `edgeId` field in the SIP message headers — use that as the seed for step 1.

### Enrichment Chain

```
telephony.get.sip.messages.for.conversation
  → edgeId in SIP headers → seed for telephony.get.edges lookup
  → telephony.get.edge.performance.metrics (load context during the call window)
  → telephony.create.edge.logs.job (targeted log collection)
```

---

## 14. Alerting Configuration & Active Alert Review

**Subject:** Organisation-wide (point-in-time)  
**Use case:** A voice engineer or NOC analyst reviews the alerting rule inventory to verify that key infrastructure and queue thresholds are covered, then checks currently firing alerts for active incidents before starting any investigation.

**Core question:** *Are the right alert rules configured, and what is currently firing?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `alerting.get.rules` | — | All configured alert rules: threshold, condition, notification targets |
| 2 | `alerting.get.alerts` | — | Currently firing alerts: severity, startDate, acknowledgement status, alertType |

### Key Joins

```
alerting.get.rules[].id
  → alerting.get.alerts[].ruleId (match firing alert to its rule definition)
```

### Alert Coverage Gap Checklist

This pair is most valuable as a pre-investigation health check. Before investigating a queue incident, run both datasets and verify:

| Signal | What to check |
|--------|--------------|
| Trunk utilisation | Rule exists for `nInboundCurrent / nMaxConnected > 0.85`? |
| Edge CPU | Rule exists for Edge CPU > 80%? |
| Queue SLA breach | Rule exists for `oServiceLevel` below target per queue? |
| Abandon rate spike | Rule exists for `nAbandoned` above threshold? |
| Edge offline | Rule exists for `statusCode != ACTIVE`? |
| Recording gap | Rule exists for recording policy failure? |

### Analytical Questions Answered

- Which alerts are currently CRITICAL and unacknowledged? (immediate escalation required)
- Are there alert rules for every key voice-infrastructure signal?
- Are SLA alert thresholds set correctly relative to queue SLA targets?
- Which alerts have been firing for > 30 minutes? (prolonged incident — page on-call)
- Are there alerting gaps that could leave an incident undetected overnight?

### Enrichment Chain

```
alerting.get.alerts[].alertType = 'telephony'
  → telephony.get.trunk.metrics.summary (confirm trunk state against trunk alerts)
  → telephony.get.edge.performance.metrics (confirm edge load against edge alerts)
  → analytics.query.queue.observations.real.time.stats (confirm queue state against SLA alerts)
```

---

## 15. API Health & Governance Rollup

**Subject:** Organisation-wide + reporting window (weekly/monthly)  
**Use case:** An IT operations or security team needs to audit which OAuth integrations are active, how much API quota each is consuming, whether any are hitting rate limits, and whether org-level API limits are approaching their ceiling.

**Core question:** *Which integrations are consuming API quota, and are any at risk of throttling or requiring governance review?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `oauth.get.clients` | — | All OAuth client applications: name, grantType, description, createdBy |
| 2 | `oauth.get.authorizations` | `clientId` | Active authorisation grants: who authorised each client, grant scope |
| 3 | `oauth.post.client.usage.query` | `clientId` | Submit async usage query job; results via `oauth.get.client.usage.query.results` |
| 4 | `usage.get.api.usage.by.client` | `clientId` | API call volume per OAuth client per day |
| 5 | `usage.get.api.usage.by.user` | `userId` | API call volume per user per day (for user-based integrations) |
| 6 | `usage.get.api.usage.organization.summary` | — | Org-wide API call totals and quota consumption |
| 7 | `analytics.query.rate.limit.aggregates` | `clientId` | Rate-limit hit events: `nError`, `nOverLimit` per client |
| 8 | `organization.get.organization.limits` | — | Platform-enforced org limits per namespace and current utilisation |
| 9 | `audit-logs` (EntityType=OAuthClient) | `clientId` | OAuth client creation, modification, and revocation events |

### Key Joins

```
oauth.get.clients[].id (clientId)
  → oauth.get.authorizations[].client.id
  → usage.get.api.usage.by.client[].clientId
  → analytics.query.rate.limit.aggregates[].group.clientId

usage.get.api.usage.organization.summary.total
  → organization.get.organization.limits[].value (headroom = limit - total)
```

### Executive Metrics (computed)

| Metric | Formula |
|--------|---------|
| Active client count | Clients with at least one API call in window |
| Top consumers (Top 5) | `usage.get.api.usage.by.client` sorted by callCount descending |
| Rate-limit hit rate | `nOverLimit / nTotal × 100` per client |
| Org limit headroom | `(limit.value - current) / limit.value × 100` per namespace |
| Unused client count | Clients with zero usage in last 30 days |

### Security Signals

- **Client with `grantType = client_credentials` and zero usage** → candidate for revocation review
- **Spike in API calls from an unrecognised `clientId`** → potential rogue integration; check `audit-logs`
- **`nOverLimit > 0` for a production integration** → needs backoff implementation or quota increase request
- **`oauth.get.authorizations` grant older than 1 year** → review whether still required

---

## 16. Routing Skill Coverage Analysis

**Subject:** Organisation-wide or specific queue  
**Use case:** A routing engineer or workforce planner needs to understand which skills are available, how agents are distributed across skill groups, whether any skills are under-staffed, and whether queue skill-evaluation settings are creating bottlenecks.

**Core question:** *Is skill-based routing correctly configured and adequately staffed?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.all.routing.skills` | — | Complete skill catalog: skillId, name, type |
| 2 | `routing.get.skill.groups` | `skillGroupId` | Skill groups: memberCount, divisionId, assigned skills |
| 3 | `routing.get.single.queue.config` | `queueId` | Queue skill evaluation mode: `Best`, `All`, `Minimal`, `Category` |
| 4 | `routing-queue-members` | `queueId` | Current queue membership with per-agent routing status |
| 5 | `users.get.user.routing.skills` | `userId` (per agent from step 4) | Skills and proficiency ratings per agent |
| 6 | `routing.get.user.utilization` | `userId` (per agent from step 4) | Max concurrent interactions per channel per agent |
| 7 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Historical AHT and volume — validates whether routing configuration is producing the right outcomes |

### Key Joins

```
routing.get.all.routing.skills[].id (skillId)
  → routing.get.skill.groups[].skills[].skillId
  → users.get.user.routing.skills[].id (agent → skill mapping)

routing-queue-members[].id (userId)
  → users.get.user.routing.skills (fan-out per agent)
  → routing.get.user.utilization (concurrency limits)

routing.get.single.queue.config.scoringMethod
  → routing-queue-members[].count (staffing pool size)
  → analytics.query.conversation.aggregates.queue.performance.tHandle (outcome validation)
```

### Analytical Questions Answered

- How many agents hold each skill? Which skills have fewer than three agents (single-point-of-failure risk)?
- What skill groups exist, and which queues do they serve?
- Is the queue's skill evaluation mode appropriate for current staffing levels?
- Which agents are over-constrained by concurrency limits relative to queue volume?
- Does the queue's AHT suggest the routing pool is correctly sized for traffic?

### Routing Engineer Signals

| Signal | Implication |
|--------|------------|
| Skill with 1 agent | Single point of failure — expand skill assignment before that agent is absent |
| Queue `scoringMethod = SKILLS` + `All` evaluation + high AHT | Over-constrained routing pool — switch to `Best` or `Minimal` to increase eligible agents |
| Agent `maxCapacity = 1` (voice) + member of many queues | Concurrency limit is a bottleneck — agent can only handle one conversation at a time |
| Skill group `divisionId` ≠ queue `divisionId` | Cross-division skill grant may be needed for agents to receive work |
| Skills present in catalog but no agents assigned | Dead skills — remove from queues or assign agents to prevent routing gaps |

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
| `nFlowOutcome` | Flow executions with a successful exit outcome | Self-service containment |
| `nFlowOutcomeFailed` | Flow executions that exited via a failure path | IVR error rate |
| `nFlowMilestone` | Flow executions that reached a named milestone | IVR funnel analysis |
| `abandonRate%` | `nAbandoned / nOffered × 100` | FTC compliance (outbound ≤ 3%), queue health |
| `rightPartyContactRate%` | Connected calls / attempted dials | Outbound campaign effectiveness |
| `containmentRate%` | `nFlowOutcome / nFlow × 100` | Self-service ROI |
| `nOverLimit` | API calls that exceeded the rate limit | Integration throttling |
| `nError` | API calls that returned an error (rate-limit context) | Integration health |
| `adherencePct%` | Scheduled vs. actual on-queue time | WFM compliance |
| `scheduleVarianceMinutes` | Difference between scheduled and actual on-queue time | WFM drill-down |
| `suggestionCount` | Agent Assist suggestions surfaced per conversation | Copilot engagement |
| `avgConfidenceScore` | Mean confidence score of Agent Assist suggestions | Suggestion relevance |
| `skillCoverageCount` | Number of agents holding a given skill | Routing coverage |
| `orgLimitUtilisation%` | `current / limit × 100` per namespace | Platform capacity |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
