# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-18  
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
11. [SIP Trace & PCAP Download Chain](#11-sip-trace--pcap-download-chain)
12. [IVR / Architect Flow Effectiveness](#12-ivr--architect-flow-effectiveness)
13. [Digital Channel Conversation Investigation](#13-digital-channel-conversation-investigation)
14. [External Contact / CRM Enrichment Chain](#14-external-contact--crm-enrichment-chain)
15. [WFM Adherence Investigation](#15-wfm-adherence-investigation)
16. [Transfer & Escalation Chain Analysis](#16-transfer--escalation-chain-analysis)
17. [Quality Program Health Investigation](#17-quality-program-health-investigation)
18. [Bot / Virtual Agent Performance](#18-bot--virtual-agent-performance)

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

For PCAP-level analysis (packet capture), extend this investigation with the three-step PCAP chain
documented in [Section 11](#11-sip-trace--pcap-download-chain).

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

#### Layer 6 — Self-Service & Automation (optional)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.bot.aggregates` | `flowId`, `mediaType`, daily | Bot containment rate: nBotContained / nBotSessions, avg session duration |
| `analytics.query.flow.aggregates.execution.metrics` | `flowId`, daily | IVR/flow execution: nFlow, nFlowOutcome, nFlowOutcomeFailed |

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
  - Bot containment rate: nBotContained / nBotSessions × 100 (if bots deployed)

Trend views (daily granularity):
  - Volume by day with channel mix
  - AHT trend by queue
  - Abandon rate trend by queue
  - SLA achievement heatmap by queue × day
  - Bot containment trend (if applicable)
```

### Key Joins for Executive Reporting

```
routing-queues[].id
  → analytics.query.conversation.aggregates.*.results[].group.queueId
  → routing.get.queue.wrapup.codes.by.queue.queueId (label resolution)
  → quality.get.agents.activity (left join via queue membership)

analytics.query.conversation.aggregates.wrapup.distribution[].group.wrapUpCode
  → routing.get.all.wrapup.codes[].id (global wrapup code labels)

flows.get.all.flows[].id (type=Bot filter)
  → analytics.query.bot.aggregates[].group.flowId
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
| + | `externalcontacts.get.contact` | Full CRM contact record for the participant's `externalContactId` |
| + | `externalcontacts.get.organization` | CRM company record if the contact belongs to an organisation |

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

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | PCAP Chain | Flow / IVR | Digital Channel | CRM Enrich | WFM Adherence | Transfer Chain | Quality Health | Bot Perf |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | ● | | ● | ● | | ● | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | ● | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | ● | ● | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | ● | ● | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | | | | | ● | |
| `quality.get.surveys` | ● | | | ● | | | | | | | | | ● | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | ● | | | | | | | |
| `telephony.get.sip.traces` | | | | | | | ● | | | | | | | |
| `telephony.post.sip.trace.download.request` | | | | | | | ● | | | | | | | |
| `telephony.get.sip.trace.download.status` | | | | | | | ● | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | ○ | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | ○ | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | ○ | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | | | | | | ● | | ○ |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | | ● | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | | | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | | | | ● | |
| `quality.get.calibrations` | | | | | | | | | | | | | ● | |
| `coaching.get.appointments` | | | ● | | | ○ | | | | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | ○ | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | | ● | | | | | | |
| `flows.get.all.flows` | | | | | | | | ● | | | | | | ● |
| `flows.get.flow.outcomes` | | | | | | | | ● | | | | | | |
| `flows.get.flow.milestones` | | | | | | | | ● | | | | | | |
| `flows.get.single.flow` | | | | | | | | ● | | | | | | ● |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | | | | |
| `audit-logs` | | | | | | ● | | | | | | | | |
| `externalcontacts.get.contact` | | | | | | | | | | ● | | | | |
| `externalcontacts.get.organization` | | | | | | | | | | ● | | | | |
| `externalcontacts.reverse.whitepages.lookup` | | | | | | | | | | ● | | | | |
| `workforce.get.business.units` | | | | | | | | | | | ● | | | |
| `workforce.get.management.units` | | | | | | | | | | | ● | | | |
| `workforce.get.management.unit.users` | | | | | | | | | | | ● | | | |
| `workforce.get.management.unit.adherence` | | | | | | | | | | | ● | | | |
| `analytics.query.bot.aggregates` | | | | ○ | | | | | | | | | | ● |
| `analytics.get.botflow.sessions` | | | | | | | | | | | | | | ● |
| `quality.get.published.evaluation.forms` | | | | | | | | | | | | | ● | |

---

## 11. SIP Trace & PCAP Download Chain

**Subject:** One `conversationId` (voice conversation)  
**Use case:** A voice engineer needs the actual network capture (PCAP) for a call — for Wireshark
analysis of RTP streams, codec negotiation, DTMF, or signaling anomalies that are not visible in
the SIP message text alone. This is the highest-fidelity debugging tool available for voice quality
and call-setup failures.

**Core question:** *What did the SIP signaling and media look like at the packet level?*

### Dataset Steps (ordered — sequential, not parallelisable)

| Step | Dataset Key | Input | What It Returns |
|------|-------------|-------|-----------------|
| 1 | `conversations.get.conversation.object` | `conversationId` | `startTime`, `endTime`, DNIS/ANI — time range needed for SIP trace query |
| 2 | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP message text trace — readable signaling events (INVITE, 200 OK, BYE) |
| 3 | `telephony.get.sip.traces` | `conversationId` + `dateStart` / `dateEnd` from step 1 | SIP trace record IDs and metadata — required to request the PCAP |
| 4 | `telephony.post.sip.trace.download.request` | trace IDs from step 3 | `downloadId` — async PCAP preparation job handle |
| 5 | `telephony.get.sip.trace.download.status` | `downloadId` from step 4 | Signed download URL when status = `COMPLETED` — poll until complete |

### Required Permissions

```
telephony:pcap:view     — read SIP traces and poll download status
telephony:pcap:add      — submit the PCAP download request (step 4)
```

Without `telephony:pcap:add`, steps 3–5 are unavailable. The SIP message text (step 2) remains
readable with standard telephony read permissions.

### Key Joins

```
conversations.get.conversation.object.startTime / endTime
  → telephony.get.sip.traces.dateStart / dateEnd (date range filter)
  → telephony.get.sip.traces.conversationId (conversation filter)

telephony.get.sip.traces[].id
  → telephony.post.sip.trace.download.request.body.traceIds[]

telephony.post.sip.trace.download.request.downloadId
  → telephony.get.sip.trace.download.status.downloadId
```

### Polling Pattern for Step 5

The PCAP download preparation is asynchronous. Poll step 5 until `state = "COMPLETED"`:

```
Poll interval: 5 seconds
Timeout: 120 seconds (most PCAPs complete in < 30 seconds)
Terminal states: COMPLETED (proceed to download URL), FAILED (abort)
```

### Analytical Questions Answered

- Was RTP media established? (SDP answer media IPs match between INVITE and 200 OK)
- Was DTMF transmitted correctly? (RFC 2833 events visible in RTP stream)
- Was there a one-way audio event? (one-directional RTP stream, media IP mismatch)
- Did a re-INVITE occur? (hold/resume, codec renegotiation)
- What caused the call to drop? (BYE origin, 408/503 errors, TCP RST)
- What codec was negotiated? (G.711, G.729, Opus)

### Voice Engineer Notes

- The SIP message text (step 2) is sufficient for signaling analysis. The PCAP (steps 3–5) is
  only needed when packet-level evidence is required — typically for RTP quality issues, DTMF
  failures, or carrier disputes.
- `Export-GenesysConversationInvestigationPackage` automates steps 3–5 and writes the `.pcap`
  into the package bundle. Use the cmdlet rather than calling these datasets directly when
  producing a support deliverable.
- The Edge performance metrics dataset (`telephony.get.edge.performance.metrics`) should accompany
  any PCAP investigation when the Edge appliance is suspected of resource pressure.

---

## 12. IVR / Architect Flow Effectiveness

**Subject:** One or more `flowId` values + time window  
**Use case:** An IVR designer or contact centre architect needs to understand whether Architect
flows are containing interactions, which exit outcomes dominate, which milestones are reached
and which are never reached, and whether failed flows correlate with queue spikes.

**Core question:** *Are our flows working as designed — containing, routing correctly, and not failing?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | seed | All flows: ID, name, type (InboundCall, InboundShortMessage, Bot, InQueue), publish status |
| 2 | `flows.get.single.flow` | `flowId` (from step 1, target flows) | Full flow config: current published version, division, description — resolves flowId for analytics joins |
| 3 | `flows.get.flow.outcomes` | — | All configured outcome labels — required to translate `nFlowOutcome` metrics to human-readable labels |
| 4 | `flows.get.flow.milestones` | — | All configured milestone definitions — required to label milestone analytics |
| 5 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Execution counts: nFlow (entries), nFlowOutcome (successful exits), nFlowOutcomeFailed (failures), nFlowMilestone |
| 6 | `analytics.query.flow.observations` | `flowId` | Current flows in execution (real-time view of how many conversations are live in each flow) |
| 7 | `analytics-conversation-details-query` (flowId segment filter) | `conversationId` | Individual conversations that passed through the flow — for outlier drilldown |

### Key Joins

```
flows.get.all.flows[].id
  → flows.get.single.flow.id (one-at-a-time for target flows)
  → analytics.query.flow.aggregates.execution.metrics.results[].group.flowId

flows.get.flow.outcomes[].id
  → analytics.query.flow.aggregates.execution.metrics.results[].group.flowOutcomeId (label resolution)

flows.get.flow.milestones[].id
  → analytics.query.flow.aggregates.execution.metrics.results[].group.flowMilestoneId (label resolution)

analytics.query.flow.aggregates.execution.metrics.results[].group.flowId
  → analytics-conversation-details-query[].participants[].sessions[].flowId (conversation linkage)
```

### Analytical Questions Answered

- What percentage of calls entering the IVR were contained (self-served) vs. routed to a queue?
- Which flow outcomes are most frequent? Are "failure" outcomes disproportionate?
- Which milestones are never reached — indicating dead code paths or broken options?
- Are there flows with high `nFlowOutcomeFailed` rates correlating with queue volume spikes?
- How many conversations are currently executing in each flow (real-time)?

### IVR Containment Formula

```
Containment rate = nFlowOutcome (self-service outcomes) / nFlow × 100
Escalation rate  = nFlowOutcome (agent outcomes) / nFlow × 100
Failure rate     = nFlowOutcomeFailed / nFlow × 100
```

Outcome labels are organisation-defined. Configure outcome names consistently
(`Self-Service`, `Agent`, `Failure`) to enable this calculation without hardcoding IDs.

---

## 13. Digital Channel Conversation Investigation

**Subject:** One `conversationId` (chat, email, or messaging conversation)  
**Use case:** An analyst or QM reviewer needs to investigate a digital (non-voice) conversation —
a chat interaction with long response times, an email thread that escalated, or an SMS conversation
that ended without resolution. Digital conversations have no SIP trace, but transcript and
sentiment are the equivalent.

**Core question:** *What happened in this digital conversation, and how did the customer experience it?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Participants, media type (chat/email/message), start/end times, queue assignment, channel identifiers |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Per-segment timing: routing wait, agent response time, ACW |
| 3 | `conversations.get.conversation.customattributes` | `conversationId` | Bot/flow-set attributes captured before agent delivery |
| 4 | `conversations.search.participant.attributes` | `conversationId` | Flow variables set by digital bot or routing flow |
| 5 | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcript download URL — full text of the conversation |
| 6 *(STA enabled)* | `conversations.get.speech.text.analytics` | `conversationId` | Sentiment summary, detected topics, STA coverage |
| 7 *(STA enabled)* | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-message sentiment — customer frustration indicators |
| 8 | `quality.get.evaluations.query` | `conversationId` | QM evaluation (if the interaction was reviewed) |
| 9 | `quality.get.surveys` | `conversationId` | Post-chat survey result |
| 10 | `conversations.get.conversation.suggestions` | `conversationId` | Agent assist / knowledge base articles suggested during the conversation |

### Key Joins

```
conversations.get.conversation.object.participants[].messages[].communicationId
  → speechandtextanalytics.get.conversation.communication.transcripturl.communicationId

conversations.get.conversation.object.participants[].purpose = 'customer'
  → externalcontacts.get.contact (if externalContactId is set — see Section 14)
```

### Digital vs Voice Differences

| Dimension | Voice | Digital |
|-----------|-------|---------|
| Signaling trace | SIP messages + PCAP | Not applicable |
| Content capture | Recording + transcript (STA) | Transcript (full text) |
| Timing unit | Seconds (talk time) | Seconds (response time between messages) |
| Sentiment | Speech-based acoustics + text | Text-only |
| Attachment evidence | — | File/image metadata in suggestions |

### Analytical Questions Answered

- How long did the customer wait for an agent to accept the chat?
- What was the average message response time during the interaction?
- Did the bot handle any turns before the agent took over?
- Was the transcript captured? What topics or keywords appear in it?
- What was the customer's sentiment trajectory — did it worsen during the conversation?
- Was the agent offered relevant knowledge articles? Were they used?

---

## 14. External Contact / CRM Enrichment Chain

**Subject:** One `conversationId` (any media type)  
**Use case:** A QM analyst or operations manager needs to link a Genesys conversation to the CRM
record of the customer — identifying the customer's name, company, account tier, history, and
relationship. This enrichment converts a raw conversation record into a customer-context record.

**Core question:** *Who was this customer, and what company or account do they represent?*

### How the External Contact Link Works

Genesys Cloud associates conversations to external contacts through two paths:

**Path A — Participant-level link (most common):**
`conversations.get.conversation.object.participants[].externalContactId` is populated when the
customer's ANI matched a known external contact during routing, or when an agent manually linked
the conversation to a contact.

**Path B — Reverse whitepages lookup (ANI-based):**
When no participant `externalContactId` is set, the customer's ANI (from `participants[].calls[].ani`)
can be sent to `externalcontacts.reverse.whitepages.lookup` to find a matching contact by phone number.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | ANI, DNIS, participant `externalContactId` (if linked) |
| 2a *(linked)* | `externalcontacts.get.contact` | participant `externalContactId` | Full contact: name, phone, email, title, custom fields, linked organisation |
| 2b *(unlinked)* | `externalcontacts.reverse.whitepages.lookup` | ANI from step 1 | Searches by phone number — returns matching contact(s) |
| 3 | `externalcontacts.get.organization` | contact `externalOrganizationId` from step 2 | Company record: name, address, industry, revenue tier, key contacts |
| 4 | `conversations.get.conversation.customattributes` | `conversationId` | IVR-captured intent, account number, case ID — maps to CRM fields |

### Key Joins

```
conversations.get.conversation.object.participants[{purpose=customer}].externalContactId
  → externalcontacts.get.contact.id

conversations.get.conversation.object.participants[{purpose=customer}].calls[].ani
  → externalcontacts.reverse.whitepages.lookup?lookup=<ANI>

externalcontacts.get.contact.externalOrganization.id
  → externalcontacts.get.organization.id
```

### Analytical Questions Answered

- Who was the customer? What is their contact record in CRM?
- What company or account tier do they belong to?
- Is this a known high-value or at-risk account?
- What was the customer's ANI, and does it match the contact's registered phone?
- What custom attributes (account number, case ID) did the IVR capture for this contact?

### Privacy and Redaction Note

External contact records contain PII (name, phone, email). All datasets in this chain should be
assigned a `conversation-investigation-external-contact` redaction profile in the catalog before
being used in production investigations. Field-level redaction should apply to
`phoneNumbers`, `emailAddresses`, `twitterId`, and any `customFields` configured in the org.

---

## 15. WFM Adherence Investigation

**Subject:** One `managementUnitId` (or `businessUnitId`) + time window  
**Use case:** A workforce planner or operations manager needs to understand schedule adherence
across a team — which agents are in or out of adherence, how much time was spent in non-scheduled
states, and whether adherence scores correlate with queue SLA performance.

**Core question:** *Are agents following their schedules, and where are the adherence exceptions?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.business.units` | seed (org-wide) | All WFM business units — top-level scheduling containers |
| 2 | `workforce.get.management.units` | `businessUnitId` | Management units (team groupings) within the business unit |
| 3 | `workforce.get.management.unit.users` | `managementUnitId` | Agents assigned to the management unit — roster for adherence join |
| 4 | `workforce.get.management.unit.adherence` | `managementUnitId` | Real-time adherence status: scheduled state vs. actual state, seconds in adherence/exception per agent |
| 5 | `analytics.query.user.aggregates.login.activity` | `userId` | Actual time-in-state from ACD: available, busy, ACW, idle per agent in the window |
| 6 | `analytics.query.user.details.activity.report` | `userId` | Granular presence event timeline — cross-reference with scheduled state transitions |

### Key Joins

```
workforce.get.business.units[].id
  → workforce.get.management.units[].businessUnit.id

workforce.get.management.units[].id
  → workforce.get.management.unit.users[].managementUnit.id
  → workforce.get.management.unit.adherence[].user.id

workforce.get.management.unit.users[].user.id
  → analytics.query.user.aggregates.login.activity[].group.userId
  → analytics.query.user.details.activity.report[].userId
```

### Analytical Questions Answered

- Which agents are currently out of adherence and for how long?
- What is the percentage of agents in adherence across the management unit?
- Which agents consistently appear in exception states (break overrun, logged off early)?
- Does lower adherence in a specific hour correlate with SLA misses for the associated queues?
- What is the breakdown of scheduled vs. actual time by state (available, on break, offline)?

### Adherence vs. Routing Status Cross-Reference

The `workforce.get.management.unit.adherence` dataset reflects the WFM scheduled state vs. the
actual Genesys routing status. The `analytics.query.user.aggregates.login.activity` dataset
reflects the *actual* ACD state independently of WFM scheduling. Comparing the two reveals agents
who are in ACD-available states but outside their scheduled window, or agents on schedule but
in unavailable ACD states.

---

## 16. Transfer & Escalation Chain Analysis

**Subject:** One `queueId` (or conversation set) + time window  
**Use case:** An operations analyst needs to understand where calls go after they leave a queue —
which queues receive the most transfers, whether blind or consult transfers dominate, and whether
specific conversation paths involve excessive hops before resolution.

**Core question:** *Where do calls go after they leave this queue, and is the transfer pattern healthy?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.single.queue.config` | seed → `queueId` | Queue name, routing method — anchor for transfer analysis |
| 2 | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer volume: nTransferred, nBlindTransferred, nConsultTransferred |
| 3 | `analytics-conversation-details-query` (queueId filter, `nTransferred > 0`) | `queueId` | Conversations that involved a transfer — individual records for chain analysis |
| 4 | `conversations.get.conversation.object` | `conversationId` (per transferred conversation) | Full participant sequence — reveals the queue/agent chain for each transfer hop |
| 5 | `routing.get.single.queue.config` | destination `queueId` from step 4 | Config of destination queues — identifies where the transfer landed |
| 6 | `analytics.query.conversation.aggregates.queue.performance` | destination `queueId` | Performance metrics for destination queues — do they compound the problem? |

### Key Joins

```
routing.get.single.queue.config.id (source queue)
  → analytics.query.conversation.aggregates.transfer.metrics.results[].group.queueId

analytics-conversation-details-query[].conversationId
  → conversations.get.conversation.object.conversationId (per-hop detail)

conversations.get.conversation.object.participants[].queueId
  → routing.get.single.queue.config.id (destination queue resolution)
```

### Transfer Pattern Signals

| Signal | Threshold (indicative) | Likely Cause |
|--------|------------------------|--------------|
| Blind transfer rate > 20% | `nBlindTransferred / nTransferred` | Agents routing around skills gaps |
| Average hops > 2 | participants[].queueId count | Routing logic misconfiguration |
| Transfers to a single queue > 40% | Destination frequency | Routing table misconfiguration or skill shortage in origin |
| Transfer rate spike in one hour | Hourly granularity | Skill outage or unexpected call type surge |

### Analytical Questions Answered

- What fraction of calls from this queue were transferred?
- Are transfers predominantly blind (warm handoff not happening) or consult (proper warm handoff)?
- Which queues receive the most transfers from this queue?
- Are there conversations with 3+ queue hops, indicating a routing loop or misconfiguration?
- Does the destination queue's SLA worsen when transfer volume from this queue increases?

---

## 17. Quality Program Health Investigation

**Subject:** Organisation-wide or division-scoped + time window  
**Use case:** A QM manager or quality director needs to assess the health of the quality programme
itself — not just scores, but whether coverage is adequate, whether forms are being used correctly,
whether calibration is happening, and whether survey responses are representative.

**Core question:** *Is our quality programme running as designed, and are the scores meaningful?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing-queues` | seed (org or division filter) | Queue roster — denominator for evaluation coverage calculation |
| 2 | `users` (filtered by queue membership or division) | `userId` | Agent roster — denominator for per-agent coverage |
| 3 | `quality.get.evaluations.query` | `queueId` or `userId` | All evaluations in window: scores, form used, evaluator, calibration status, completion status |
| 4 | `quality.get.published.evaluation.forms` | `formId` from step 3 | Form definitions — identifies active forms, question weights, critical questions |
| 5 | `quality.get.agents.activity` | `userId` | Per-agent evaluation summary: count, highest/average/lowest, evaluator breakdown |
| 6 | `quality.get.calibrations` | — | Calibration sessions in window: participants, conversation, scoring variance |
| 7 | `quality.get.surveys` | `conversationId` | Survey responses: NPS, CSAT, verbatim comments |
| 8 | `analytics.post.transcripts.aggregates.query` | `queueId` + `userId` | STA coverage: what fraction of conversations were analysed for sentiment/topics |

### Key Joins

```
routing-queues[].id
  → quality.get.evaluations.query[].queue.id

users[].id
  → quality.get.evaluations.query[].agent.id
  → quality.get.agents.activity[].user.id

quality.get.evaluations.query[].evaluationForm.id
  → quality.get.published.evaluation.forms[].id (form definition join)

quality.get.evaluations.query[].conversationId
  → quality.get.surveys[].conversationId (survey response overlay)
```

### Quality Programme KPIs (computed from this combination)

| KPI | Formula | Source |
|-----|---------|--------|
| Evaluation coverage | evaluations / nConnected × 100 | evaluations + queue performance |
| Average QM score | SUM(totalScore) / COUNT(evaluations) | quality.get.evaluations.query |
| Low-score rate | evaluations below threshold / total | quality.get.evaluations.query |
| Calibration frequency | calibration sessions / agents | quality.get.calibrations |
| Survey response rate | surveys completed / eligible | quality.get.surveys |
| Avg CSAT | SUM(score) / surveys responded | quality.get.surveys |
| STA coverage | nSpeechTextAnalyzedConversations / nConnected | analytics.post.transcripts.aggregates.query |

### Analytical Questions Answered

- What fraction of handled conversations received a quality evaluation?
- Which agents have not been evaluated in the window?
- Is there evaluator bias (does one evaluator consistently score lower)?
- Are calibration sessions happening? Are scores converging between evaluators?
- What is the CSAT/NPS from the survey programme? Does it correlate with QM scores?
- Which evaluation forms are in use? Are there deprecated forms being used by mistake?
- Do conversations with low QM scores also show negative sentiment in STA?

---

## 18. Bot / Virtual Agent Performance

**Subject:** One or more bot `flowId` values + time window  
**Use case:** A self-service design team or digital operations manager needs to understand how
virtual agents are performing — containment rate, escalation rate, session duration, and which
flows are failing or causing unexpected escalations to live agents.

**Core question:** *How effectively are our bots containing interactions, and where are they breaking down?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` (type=Bot filter) | seed | All bot flows: ID, name, type, publish status, division |
| 2 | `flows.get.single.flow` | `flowId` | Full bot flow config — version, configuration, integration type (Genesys Dialog Engine, Google CCAI, Amazon Lex) |
| 3 | `analytics.query.bot.aggregates` | `flowId` | Aggregate bot metrics: nBotSessions, tBotSession, nBotContained, nBotTransferred, nBotInteractions |
| 4 | `analytics.get.botflow.sessions` | `flowId` | Per-session records: turn count, outcome (contained / escalated), session duration, linked conversationId |
| 5 | `analytics-conversation-details-query` (flowId filter, escalated sessions) | `conversationId` | Full conversation analytics for escalated sessions — what happened after bot escalation |
| 6 | `analytics.query.conversation.aggregates.queue.performance` | destination `queueId` | Queue load from bot escalations — are receiving queues absorbing the overflow? |

### Key Joins

```
flows.get.all.flows[{type=Bot}].id
  → flows.get.single.flow.id (config detail)
  → analytics.query.bot.aggregates.results[].group.flowId

analytics.get.botflow.sessions[].conversationId
  → analytics-conversation-details-query[].conversationId (escalated session drilldown)

analytics.get.botflow.sessions[{outcome=Escalated}].queueId
  → analytics.query.conversation.aggregates.queue.performance.results[].group.queueId
```

### Bot Performance KPIs

| KPI | Formula | Benchmark |
|-----|---------|-----------|
| Containment rate | nBotContained / nBotSessions × 100 | Target: org-specific (typically 30–60%) |
| Escalation rate | nBotTransferred / nBotSessions × 100 | Inverse of containment |
| Avg session duration | tBotSession / nBotSessions | Shorter = more efficient self-service |
| Avg turns per session | total turns / nBotSessions | High turn count may indicate confusion |
| Failure rate | sessions with error outcome / nBotSessions | Target: < 5% |

### Bot Integration Types (flows.get.single.flow context)

| Flow Type Tag | Integration | When to Check |
|---------------|-------------|----------------|
| `DIGITALBOT` | Architect Digital Bot | Genesys-native NLU |
| `BOT` (with `botConnector`) | Bot Connector (Lex, CCAI) | External NLU integration — check integration health too |
| `INBOUNDSHORTMESSAGE` (with bot prefix) | SMS/messaging bot | Digital channel-specific |

### Analytical Questions Answered

- What is the bot containment rate overall and by individual flow?
- Which bot flows have the highest escalation rate — is it intentional design or failure?
- What is the average number of turns before containment or escalation?
- Do bot escalations correlate with queue volume spikes?
- What time-of-day patterns exist in bot sessions? (staffed hours vs. after-hours self-service)
- Are session errors (failed API calls, NLU failures) visible in botflow session outcomes?

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
| `nBlindTransferred` | Blind (cold) transfers | Transfer quality indicator |
| `nConsultTransferred` | Consult (warm) transfers | Transfer quality indicator |
| `oServiceLevel` | Current SLA percentage | Real-time SLA |
| `nOverSla` | Conversations that exceeded SLA threshold | SLA misses |
| `oInteracting` | Agents currently on interactions | Active agents |
| `oWaiting` | Interactions waiting in queue | Queue depth |
| `oLongestWaiting` | Seconds the longest-waiting customer has been waiting | Worst-case wait |
| `tAgentRoutingStatus` | Time in each routing status | On-queue vs off-queue time |
| `tSystemPresence` | Time in each system presence | Available, Busy, Away, Offline |
| `oSentimentScore` | Aggregate sentiment score (STA) | Voice-of-customer indicator |
| `nSpeechTextAnalyzedConversations` | Conversations with STA analysis | STA coverage |
| `nBotSessions` | Bot/virtual agent sessions initiated | Bot volume |
| `nBotContained` | Bot sessions resolved without live agent | Self-service success |
| `nBotTransferred` | Bot sessions escalated to a live agent | Escalation count |
| `tBotSession` | Total bot session duration | Bot efficiency |
| `nFlow` | Architect flow entries | IVR volume |
| `nFlowOutcome` | Flow exits with a configured outcome | Successful flow completion |
| `nFlowOutcomeFailed` | Flow exits with a failure outcome | IVR failure count |
| `nFlowMilestone` | Milestone checkpoints reached | IVR path tracking |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
