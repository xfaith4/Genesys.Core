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
10. [Digital Channel Conversation Investigation](#10-digital-channel-conversation-investigation)
11. [Quality Deep Dive with Calibration](#11-quality-deep-dive-with-calibration)
12. [BYOI External Contact Resolution](#12-byoi-external-contact-resolution)
13. [Predictive Routing Effectiveness Analysis](#13-predictive-routing-effectiveness-analysis)
14. [Knowledge and Agent Assist Analytics](#14-knowledge-and-agent-assist-analytics)
15. [WFM Adherence Spot Check](#15-wfm-adherence-spot-check)
16. [Dataset Combination Reference Matrix](#16-dataset-combination-reference-matrix)

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

---

## 10. Digital Channel Conversation Investigation

**Subject:** One `conversationId` (mediaType: chat, email, or message)
**Use case:** An analyst or QA manager needs the complete picture of a chat, email, or web-messaging interaction — how it routed, what the bot captured, what the agent said, whether sentiment was negative, whether the customer was surveyed. Voice-specific steps (SIP trace, call detail) are absent; digital-specific steps (AI summaries, topic categories, external contact) replace them.

**Core question:** *What happened in this digital interaction, and why did the customer contact us?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.get.single.conversation.analytics` | seed → `conversationId` | Segment timing: queue wait, connect, ACW, handle time |
| 2 | `conversations.get.conversation.object` | `conversationId` | mediaType confirm, participants, externalTag, externalContactId |
| 3 | `conversations.get.conversation.customattributes` | `conversationId` | Bot/IVR custom attributes: intent, routing flags, CRM case ID |
| 4 | `conversations.search.participant.attributes` | `conversationId` | Architect/bot flow variables captured during the interaction |
| 5 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording metadata — screen/co-browse recording if present |
| 6 | `conversations.get.speech.text.analytics` | `conversationId` | S&TA summary: sentiment on text, analysisStatus (no audio metrics) |
| 7 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic/category classifications from S&TA engine |
| 8 | `conversations.get.conversation.summaries` | `conversationId` | Copilot/Agent Assist AI summary: reason for contact, resolution |
| 9 | `quality.get.evaluations.query` | `conversationId` | QM evaluation score and criticalItemFailed flag |
| 10 | `quality.get.conversation.surveys` | `conversationId` | Post-interaction CSAT/NPS survey result |
| 11 *(conditional)* | `externalcontacts.get.contact` | `externalContactId` | CRM contact record if conversation has external contact linkage |

### Key Joins

```
conversations.get.conversation.object.participants[].externalContactId
  → externalcontacts.get.contact (conditional — only if externalContactId is non-null)

analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
  → speechandtextanalytics.get.conversation.categories.conversationId
  → conversations.get.conversation.summaries.conversationId
```

### What Changes vs. Voice Deep Dive

| Voice Step | Digital Replacement | Reason |
|------------|---------------------|--------|
| `telephony.get.sip.messages.for.conversation` | *(omitted)* | No SIP signalling on digital channels |
| `conversations.get.call.detail` | `conversations.get.conversation.customattributes` | Bot/flow attributes replace call-leg detail |
| `speech.and.text.analytics.get.sentiment.for.conversation` | `speechandtextanalytics.get.conversation.categories` | Text-based categories more relevant than audio timeline |
| *(absent in voice)* | `conversations.get.conversation.summaries` | AI summary is highest-ROI step for digital |

### Analytical Questions Answered

- Was this a bot-handled or agent-handled interaction? (from `custom-attributes`: routing path)
- What was the customer's intent before the agent took over? (from `participant-attributes`)
- What topic/category did S&TA classify this interaction as? Escalation? Complaint?
- Was there an AI summary? What was the reason for contact and was it resolved?
- Was the interaction evaluated? Did the agent fail any critical QM item?
- Was the customer surveyed on a digital channel? What was the score?

---

## 11. Quality Deep Dive with Calibration

**Subject:** One `queueId` or `divisionId` + time window (optionally scoped to one `userId`)
**Use case:** A QM manager needs to assess the health of the evaluation programme — not just scores, but scoring consistency (calibration), CSAT correlation, and whether coaching is reaching agents who need it. This combination answers whether the QM programme itself is working, not just whether agents are.

**Core question:** *Is the QM programme producing consistent, actionable results?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `quality.get.evaluations.query` | seed → `conversationId` / `agentUserId` | All evaluation records: scores, forms, calibration flag, evaluator |
| 2 | `quality.get.calibrations` | `calibrationId` (from evaluation) | Calibration session detail — target score, participating evaluators |
| 3 | `quality.get.published.evaluation.forms` | `formId` (from evaluation) | Form definition — question weights, critical items |
| 4 | `quality.get.agents.activity` | `agentUserId` | Aggregated scores per agent: count, avg, highest, lowest |
| 5 | `quality.get.conversation.surveys` | `conversationId` | CSAT/NPS for evaluated conversations (left join for correlation) |
| 6 | `coaching.get.appointments` | `agentUserId` | Coaching sessions attending/facilitating in the window |

### Key Joins

```
quality.get.evaluations.query[].conversation.id
  → quality.get.conversation.surveys[].conversationId (left join — CSAT correlation)

quality.get.evaluations.query[].evaluationForm.id
  → quality.get.published.evaluation.forms[].id (form definition)

quality.get.evaluations.query[].calibration.id
  → quality.get.calibrations[].id (calibration session detail)

quality.get.agents.activity[].user.id
  → coaching.get.appointments[].attendees[].id (left join — coaching pipeline)
```

### Derived Metrics

| Metric | Computation |
|--------|-------------|
| `evaluationCoverageRate%` | `evaluations` / `nConnected` from `analytics.query.conversation.aggregates.queue.performance` |
| `calibrationAgreementRate%` | calibrated evaluations scoring within tolerance / total calibrated |
| `criticalItemFailRate%` | evaluations with `criticalItemFailed=true` / total evaluations |
| `csatCorrelation` | `evalScore` vs. `csatScore` joined on `conversationId` |
| `coachingCoverage%` | agents with coaching appointment / agents in bottom score quartile |

### Analytical Questions Answered

- Are evaluators scoring consistently? (calibration agreement rate)
- Which evaluation form questions have the highest fail rate? (systemic training gaps)
- Do high QM scores correlate with high CSAT? If not, what needs to change in the form?
- Are agents who score lowest in QM receiving coaching?
- Which evaluator-agent pairs have the largest score variance? (evaluator bias detection)

---

## 12. BYOI External Contact Resolution

**Subject:** One `conversationId` with a non-null `externalContactId` or `externalTag`
**Use case:** A conversation was injected via the BYOI integration and the customer's full CRM profile and digital journey need to be resolved. This goes beyond Section 6 (BYOI indicator) by actively fetching the external contact record and their journey sessions from the Genesys platform.

**Core question:** *Who is this customer, what did they do before calling, and what context does the CRM carry?*

### BYOI Identification

In `conversations.get.conversation.object`, look for:
```json
{
  "externalTag": "<provider-tag>",
  "participants": [
    { "purpose": "customer", "externalContactId": "<contact-id>" }
  ]
}
```

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | `externalContactId`, `externalTag`, participant purposes |
| 2 | `conversations.get.conversation.customattributes` | `conversationId` | Provider-injected attributes: CRM case ID, external call ID, intent |
| 3 | `externalcontacts.get.contact` | `externalContactId` | Full CRM contact: name, org, phones, emails, external system URL |
| 4 | `externalcontacts.get.contact.journey.sessions` | `contactId` | All digital journey sessions linked to this contact |
| 5 | `journey.get.session` | `sessionId` (most recent) | Session detail: channel, device, referrer, outcome scores |
| 6 | `journey.get.session.events` | `sessionId` | Event timeline: pages viewed, forms submitted, self-service attempts |
| 7 | `conversations.search.participant.attributes` | `conversationId` | Architect flow variables from the BYOI injection flow |

### Key Joins

```
conversations.get.conversation.object.participants[].externalContactId
  → externalcontacts.get.contact.id
  → externalcontacts.get.contact.journey.sessions.contactId
  → journey.get.session.id (most recent session, or session closest to conversation start)
  → journey.get.session.events.sessionId
```

### Analytical Questions Answered

- Who is the customer in the CRM? What organisation do they belong to?
- What was the customer doing on our website/app before they called?
- Did the customer try to use self-service (chat, web form) before calling?
- What CRM case/context did the BYOI provider inject with this call?
- What routing intent did Architect capture from the BYOI call flow?

### Diagnostic Signals

- `externalContactId` present but `getExternalcontactsContact` returns 404 → CRM sync gap
- Journey events contain `formSubmit` events → customer tried self-service and failed
- Journey session `awayCount > 2` → customer frustrated before calling; flag for sentiment correlation
- `externalTag` contains CRM case ID → link conversation to the open case for agent coaching

---

## 13. Predictive Routing Effectiveness Analysis

**Subject:** One or more `queueId` values with predictive routing enabled + time window
**Use case:** A contact centre director or routing architect needs to quantify whether predictive routing is improving outcomes versus the baseline routing method. Run monthly after enabling predictive routing, or after updating predictor models.

**Core question:** *Is predictive routing improving handle time, CSAT, and first-contact resolution versus the baseline?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.predictors` | seed | Predictor IDs, KPI targets, queue assignments, model status |
| 2 | `analytics-conversation-details-query` (queueId filter) | `queueId` | All conversations — segment attributes identify predictor-routed ones |
| 3 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | tHandle, nConnected — baseline AHT for comparison |
| 4 | `quality.get.surveys` | `conversationId` | CSAT for conversations in the comparison window |
| 5 | `quality.get.agents.activity` | `userId` | Per-agent eval scores — confirm predictor is routing to better-performing agents |

### Key Joins

```
routing.get.predictors[].queue.id
  → analytics-conversation-details-query filter: queueId + window
  → conversations[].participants[].sessions[].metrics.oPredictor (segment attribute, if present)

analytics-conversation-details-query[].conversationId
  → quality.get.surveys[].conversationId (left join — CSAT overlay)
```

### Derived Metrics

| Metric | Computation |
|--------|-------------|
| `predictiveRoutedPct%` | Conversations with predictor segment attribute / total conversations |
| `ahtDelta` | `avgHandleTime(predictive)` − `avgHandleTime(baseline)` |
| `csatDelta` | `avgCSAT(predictive)` − `avgCSAT(baseline)` |
| `transferRateDelta` | `nTransferred(predictive)/nConnected` − baseline transfer rate |

### Analytical Questions Answered

- What percentage of conversations are being routed by the predictor?
- Is AHT lower for predictor-routed conversations vs. baseline?
- Is CSAT higher for predictor-routed conversations?
- Are transfers lower (fewer wrong-agent routings) for predictor-routed conversations?
- Are higher-performing agents (by QM score) being selected more often by the predictor?

---

## 14. Knowledge and Agent Assist Analytics

**Subject:** Organisation-wide or per `queueId`/`knowledgeBaseId` + time window
**Use case:** A knowledge management team or operations analyst needs to measure whether agents are using the knowledge base, whether articles are relevant, and whether knowledge use correlates with lower handle times or higher CSAT.

**Core question:** *Is the knowledge base adding value, and where are the content gaps?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.post.knowledge.aggregates.query` | seed → `knowledgeBaseId` / `userId` / `queueId` | Article search counts, presentation rates, positive/negative feedback |
| 2 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | AHT baseline — compare with and without knowledge use |
| 3 | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer rate — knowledge use should reduce transfers |
| 4 *(per-conversation)* | `conversations.get.conversation.suggestions` | `conversationId` | Individual suggestion events for specific conversation investigation |

### Aggregate Query Body (Step 1)

```json
{
  "interval": "2026-06-01T00:00:00.000Z/2026-06-07T23:59:59.999Z",
  "groupBy": ["knowledgeBaseId", "userId", "queueId"],
  "metrics": [
    "nKnowledgeDocumentsSearched",
    "nKnowledgeDocumentsPresented",
    "nKnowledgeDocumentsFeedbackPositive",
    "nKnowledgeDocumentsFeedbackNegative"
  ]
}
```

### Key Derived Metrics

| Metric | Computation |
|--------|-------------|
| `searchRate%` | `nKnowledgeDocumentsSearched` / `nConnected` |
| `presentationRate%` | `nKnowledgeDocumentsPresented` / `nKnowledgeDocumentsSearched` |
| `positiveFeedbackRate%` | `nFeedbackPositive` / `nPresented` |
| `deflectionProxy%` | `conversations with knowledge use AND no transfer` / `conversations with knowledge use` |

### Analytical Questions Answered

- Are agents using the knowledge base at all? (search rate)
- Are search results returning relevant articles? (presentation rate)
- Are agents rating articles positively? (feedback rate)
- Does knowledge use correlate with lower AHT and fewer transfers?
- Which agents have low search rates — training gap or UX issue?

---

## 15. WFM Adherence Spot Check

**Subject:** One or more `userId` values in a WFM management unit + current state
**Use case:** A real-time WFM analyst or supervisor sees off-queue agents during a busy period and needs to determine whether they are on a scheduled break (adherent) or genuinely unavailable (non-adherent). This is a point-in-time check, not a historical report.

**Core question:** *Are off-queue agents on scheduled breaks, or are they a staffing problem right now?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.queue.observations.real.time.stats` | seed → `queueId` | `oOffQueueUsers`, `oOnQueueUsers`, `oWaiting` — identifies the staffing gap |
| 2 | `routing-queue-members` | `queueId` | Member roster with current `routingStatus` and `systemPresence` |
| 3 | `workforce.get.agent.management.unit` | `userId` | Maps each off-queue agent to their WFM management unit |
| 4 | `workforce.get.adherence.bulk` | `userId` | Scheduled vs. actual state — adherencePct and scheduledActivityCategory |
| 5 | `workforce.get.realtime.adherence` | `userId` | Real-time adherence snapshot for targeted agent list |
| 6 | `analytics.query.user.observations.real.time.status` | `userId` | Confirms current oUserPresence and oUserRoutingStatus |

### Key Joins

```
analytics.query.queue.observations.real.time.stats.group.queueId
  → routing-queue-members.queueId (member roster)

routing-queue-members[].id (userId)
  → workforce.get.agent.management.unit.userId (management unit lookup)
  → workforce.get.adherence.bulk (userId list)
  → workforce.get.realtime.adherence (userId list)
  → analytics.query.user.observations.real.time.status.userId
```

### Analytical Questions Answered

- How many agents are off-queue vs. scheduled to be off-queue right now?
- Which specific agents are off-queue and what is their WFM scheduled state?
- Are the off-queue agents in adherence (on a scheduled break or lunch)?
- Which agents are non-adherent (off-queue without a scheduled break)?
- Is current oWaiting > 0 while oOffQueueUsers is high — staffing intervention needed?

### Diagnostic Signals

- `oWaiting > 0` + `oOffQueueUsers > 2` → investigate adherence immediately
- `adherenceState = ADHERENT` + `scheduledActivityCategory = Break` → expected off-queue; no action
- `adherenceState = OUT_OF_ADHERENCE` + `oUserPresence ≠ 'On Queue'` → non-adherent agent; escalate to supervisor
- `oUserPresence = 'On Queue'` but `oUserRoutingStatus = NOT_RESPONDING` → ghost agent; check station registration

---

## 16. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

**Column key:** Conv = Voice Conversation Deep Dive, Queue = Queue Investigation, Div = Division Investigation, Exec = Executive Rollup, RT = Real-Time Monitoring, Agent = Agent Investigation, Digital = Digital Channel Investigation, QM = Quality Deep Dive, BYOI = BYOI External Contact, PredR = Predictive Routing, Know = Knowledge Analytics, WFM = WFM Adherence Spot Check

| Dataset Key | Conv | Queue | Div | Exec | RT | Agent | Digital | QM | BYOI | PredR | Know | WFM |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | ● | | ● | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | ● | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | ● | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | ● | | ● | | | |
| `conversations.search.participant.attributes` | ● | | | | | | ● | | ● | | | |
| `conversations.get.call.detail` | ○ | | | | | | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ○ | | | | | | | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | | ● | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | ● | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | ○ | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | ● | ● | | | | |
| `quality.get.surveys` | ● | | | ● | | | | ● | | | | |
| `quality.get.conversation.surveys` | ○ | | | | | | ● | ● | | | | |
| `quality.get.conversation.evaluation` | ○ | | | | | | | ● | | | | |
| `quality.get.calibrations` | | | | | | | | ● | | | | |
| `quality.get.published.evaluation.forms` | | | | | | | | ● | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | ● | | ● | | |
| `coaching.get.appointments` | | | ● | | | ○ | | ● | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | ● | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ○ | | | ○ | | | | | | | ● |
| `routing.get.predictors` | | | | | | | | | | ● | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | | | ● |
| `analytics-conversation-details-query` | | ● | | | | ○ | | | | ● | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | | ● | ● | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | ● | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | | | |
| `analytics.post.knowledge.aggregates.query` | | | | ● | | | | | | | ● | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | | ● |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | | | ● |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | | |
| `audit-logs` | | | | | | ● | | | | | | |
| `externalcontacts.get.contact` | | | | | | | ○ | | ● | | | |
| `externalcontacts.search.contacts` | | | | | | | | | ○ | | | |
| `externalcontacts.get.contact.journey.sessions` | | | | | | | | | ● | | | |
| `journey.get.session` | | | | | | | | | ● | | | |
| `journey.get.session.events` | | | | | | | | | ● | | | |
| `journey.get.outcome.predictors` | | | | | | | | | | ● | | |
| `conversations.get.conversation.suggestions` | ○ | | | | | | | | | | ● | |
| `workforce.get.agent.management.unit` | | | | | | | | | | | | ● |
| `workforce.get.adherence.bulk` | | | | | | | | | | | | ● |
| `workforce.get.realtime.adherence` | | | | | | | | | | | | ● |
| `workforce.get.management.unit.adherence` | | | | | | | | | | | | ○ |

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
| `nKnowledgeDocumentsSearched` | Knowledge articles searched by agents | Agent Assist usage |
| `nKnowledgeDocumentsPresented` | Knowledge articles surfaced to agents | Relevance proxy |
| `nKnowledgeDocumentsFeedbackPositive` | Positive thumbs-up on surfaced articles | Content quality |
| `calibrationAgreementRate%` | % of calibrated evaluations within scoring tolerance | Evaluator consistency |
| `criticalItemFailRate%` | % of evaluations with a critical item marked failed | Systemic training gap indicator |
| `adherencePct` | Scheduled vs. actual on-queue time | WFM compliance |
| `predictiveRoutedPct%` | % of conversations routed by ML predictor | Predictor activation rate |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
