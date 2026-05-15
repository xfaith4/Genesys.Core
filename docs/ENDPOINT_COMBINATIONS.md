# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-15  
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
10. [Agent Adherence + Performance Correlation](#10-agent-adherence--performance-correlation)
11. [Multi-Channel Customer Journey Investigation](#11-multi-channel-customer-journey-investigation)
12. [Copilot & AI Assist Effectiveness](#12-copilot--ai-assist-effectiveness-executive)
13. [Knowledge Base Utilisation](#13-knowledge-base-utilisation-executive)
14. [Bot & IVR Deflection ROI](#14-bot--ivr-deflection-roi-executive)
15. [BYOI Integration Health Check](#15-byoi-integration-health-check-voice-engineer)
16. [SIP PCAP Trace Download Workflow](#16-sip-pcap-trace-download-workflow-voice-engineer)
17. [Queue Routing Validation](#17-queue-routing-validation-voice-engineer)
18. [Dataset Combination Reference Matrix](#18-dataset-combination-reference-matrix)

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

## 10. Agent Adherence + Performance Correlation

**Subject:** One `userId` + time window  
**Use case:** A WFM analyst or supervisor needs to determine whether an agent's schedule adherence gaps correlate with performance issues — were handle time spikes or quality dips linked to periods when the agent was off-schedule?

**Core question:** *Did this agent's off-schedule time cause or correlate with degraded performance?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | Agent identity, division, manager |
| 2 | `workforce.get.agent.management.unit` | `userId` | Management unit ID — scopes adherence records |
| 3 | `workforce.get.adherence.bulk` | `userId` + window | Scheduled vs. actual routing status per 15-min interval; adherencePct, deviationSeconds |
| 4 | `analytics.query.user.details.activity.report` | `userId` + window | Actual presence/routing-status segments — raw input for adherence computation |
| 5 | `analytics.query.user.aggregates.performance.metrics` | `userId` | nConnected, tHandle, tTalk, tAcw aggregates |
| 6 | `analytics-conversation-details-query` | `userId` + window | Conversation records with timestamps — overlay on adherence timeline |
| 7 | `quality.get.agents.activity` | `userId` | QM scores for the window — correlate quality with adherence |

### Analytical Questions Answered

- What % of scheduled time was the agent actually on-queue?
- Do AHT spikes occur during or immediately after adherence violations?
- Are quality scores lower on high-deviation days?
- Which scheduled states does the agent most frequently deviate from?

---

## 11. Multi-Channel Customer Journey Investigation

**Subject:** One `externalContactId` + time window  
**Use case:** A CX analyst investigates a customer who contacted the centre multiple times across channels — linking digital web activity, bot sessions, and voice/chat conversations to understand the complete experience.

**Core question:** *What was this customer's complete cross-channel journey, and at which touchpoint did the experience break down?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `externalcontacts.get.contact.journey.sessions` | seed → `externalContactId` | All journey sessions — web/app activity clusters |
| 2 | `journey.get.session` | `sessionId` (fan-out) | Session detail — channel, first/last event time, originating trigger |
| 3 | `journey.get.session.events` | `sessionId` (fan-out) | Full event timeline per session — pages, forms, custom events |
| 4 | `analytics-conversation-details-query` | `externalContactId` / ANI | All conversations in the window across all media types |
| 5 | `conversations.get.specific.conversation.details` | `conversationId` (fan-out) | Full participant roster, externalTag, state, originatingDirection |
| 6 | `conversations.get.speech.text.analytics` | `conversationId` (voice only) | Top-level sentiment — identifies which touchpoint degraded CX |
| 7 | `quality.get.conversation.surveys` | `conversationId` | Post-interaction CSAT/NPS per conversation |

### Channel Join Strategy

Link journey session to conversation via:
1. `externalTag` on the conversation carrying a `sessionId` set by a journey action trigger
2. ANI match between `participants[purpose=customer].calls[].ani` and the journey session phone
3. External contact ID present on both records when CRM integration is active

---

## 12. Copilot & AI Assist Effectiveness (Executive)

**Subject:** Organisation-wide or per-division + reporting window  
**Core question:** *Is Agent Copilot reducing handle time and improving quality? Where is it not being used?*

### Dataset Steps (ordered)

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.get.agent.copilot.aggregates` | `userId`, `queueId`, daily | Suggestion acceptances, article clicks, script adherence |
| `analytics.query.user.aggregates.performance.metrics` | `userId`, daily | tHandle per agent — split copilot-assisted vs. unassisted |
| `analytics.query.knowledge.aggregates` | `articleId`, `queueId`, daily | Knowledge article views, search queries, deflection |
| `quality.get.agents.activity` | `userId` | QM score correlation with copilot usage tier |

### Executive Dashboard Composition

```
Headline:
  Copilot acceptance rate% = acceptedSuggestions / totalSuggestions
  Assisted AHT vs. unassisted AHT (delta in seconds)
  Knowledge article click rate% = articleClicks / nConnected
  QM score (copilot-high vs. copilot-low agents)

Decision signals:
  acceptance rate < 30% → agents not engaging; review relevance + training
  assistedAHT > unassistedAHT → copilot friction; review placement and timing
  zero-result article searches rising → knowledge gap; commission content
```

---

## 13. Knowledge Base Utilisation (Executive)

**Subject:** Organisation-wide or per-queue + reporting window  
**Core question:** *Which knowledge articles are driving self-service and agent efficiency? Where are content gaps?*

### Dataset Steps

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.knowledge.aggregates` | `articleId`, `queueId`, daily | Views, searches, self-service deflections |
| `analytics.get.agent.copilot.aggregates` | `userId`, daily | Agent-initiated knowledge lookups |
| `analytics.query.user.aggregates.performance.metrics` | `userId`, daily | AHT for agents with high vs. low knowledge usage |

### Executive Outputs

- Top-10 articles by view count per queue
- Zero-result search queries list (content gap indicator)
- Self-service deflection count and trend
- AHT delta between high-knowledge-usage and low-usage agents

---

## 14. Bot & IVR Deflection ROI (Executive)

**Subject:** All flows + reporting window  
**Core question:** *What percentage of contacts are self-served by bot or IVR, and what is the cost avoidance?*

### Dataset Steps

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `flows.get.all.flows` + `flows.get.flow.outcomes` | `flowId` | Flow catalog with outcome definitions |
| `analytics.query.flow.aggregates.execution.metrics` | `flowId`, `flowType`, daily | nFlow, nFlowOutcome, nFlowOutcomeFailed |
| `analytics.get.botflow.sessions` | `botFlowId`, daily | Bot session outcomes, handoff-to-agent count |
| `analytics.query.flow.execution.aggregates` | `flowId`, daily | Execution-level aggregates with milestone completion |
| `analytics.query.conversation.aggregates.queue.performance` | `queueId`, daily | Agent-handled volume (denominator for deflection rate) |

### Executive Outputs

```
containmentRate% = nFlowOutcomeSuccess / (nFlowOutcomeSuccess + agentConnected)
deflectedContacts = nFlowOutcomeSuccess with no queue transfer
deflectionValue = deflectedContacts × avgAgentHandleTimeCost (configurable)
botHandoffRate% = botSessionsTransferred / totalBotSessions
```

---

## 15. BYOI Integration Health Check (Voice Engineer)

**Subject:** One `conversationId` from a BYOI-injected call, or a time window on a BYOI provider  
**Use case:** A BYOI-integrated third-party telephony platform is reporting delivery failures, misrouted calls, or missing metadata. The engineer needs to confirm the injection pattern is working end-to-end.

**Core question:** *Is the BYOI provider injecting conversations correctly, and are they routing and recording as expected?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | `externalTag`, `externalConversationId`, participants[purpose=external] |
| 2 | `conversations.get.conversation.customattributes` | `conversationId` | Provider-set context: CRM caseId, external callId, intent label |
| 3 | `conversations.search.participant.attributes` | `conversationId` | Architect flow variables set during injected conversation |
| 4 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing — confirms ACD routing and IVR handling |
| 5 | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP INVITE from provider SBC — confirms trunk and credential path |
| 6 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording presence — BYOI recordings behave identically to native |

### Diagnostic Signals

| Observation | Diagnosis |
|-------------|-----------|
| `externalTag` null | Provider not setting tag at injection; check POST body |
| `externalConversationId` present, `customattributes` empty | Provider injected without context; CRM integration gap |
| SIP INVITE From-header mismatches provider config | Wrong SIP trunk routing BYOI to PSTN path |
| IVR segment > 0 when bypass expected | Architect flow not recognising BYOI path; check externalTag condition |
| Recording absent | BYOI queue not inheriting recording policy; check queue recording settings |

---

## 16. SIP PCAP Trace Download Workflow (Voice Engineer)

**Subject:** One `conversationId` + `edgeId`  
**Use case:** SIP header analysis is inconclusive for an audio quality or codec issue. A packet capture is needed to inspect the RTP media path.

**Core question:** *What does the media-layer packet capture reveal about audio quality?*

### Workflow Steps (sequential — each depends on the prior)

```
1. GET telephony.get.sip.messages.for.conversation
   → Retrieve SIP headers; extract edgeId and Call-ID

2. GET telephony.get.sip.messages.for.conversation (headers variant)
   → Keys: Via, Contact, From, To, Call-ID — identify trunk and NAT path

3. GET telephony.get.edges
   → Confirm Edge is ACTIVE before requesting capture

4. POST telephony.create.edge.logs.job (edgeId + time window)
   → Create Edge log capture job

5. GET telephony.get.edge.logs.job (poll)
   → Wait until status = READY

6. PUT telephony.request.edge.logs.job.upload
   → Trigger PCAP upload to S3

7. GET signed download URL
   → Retrieve PCAP for Wireshark analysis
```

### Diagnostic Signals from PCAP

| Signal | Diagnosis |
|--------|-----------|
| RTP to wrong IP | NAT traversal failure — STUN/TURN misconfiguration |
| 200 OK but no RTP | Media plane blocked — firewall or SBC media-pinhole issue |
| Codec in SDP offer rejected | Fallback codec negotiation explaining audio quality drop |
| BYE before expected | Premature disconnect — correlate with `tTalk` in analytics |

---

## 17. Queue Routing Validation (Voice Engineer)

**Subject:** One `queueId` (expected destination) + time window  
**Use case:** After a routing change or IVR deployment, calls are arriving in the wrong queue, or a DNIS is not routing correctly. The engineer validates the full routing path.

**Core question:** *Are inbound calls routing to this queue as configured?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.single.queue.config` | seed → `queueId` | Queue name, DNIS, routing method, ACW settings |
| 2 | `analytics.query.conversation.details.by.queue` | `queueId` + window | All conversations routed to this queue — volume and pattern |
| 3 | `conversations.get.specific.conversation.details` | `conversationId` (sample) | ANI, DNIS, participant chain — confirm expected routing path |
| 4 | `conversations.get.conversation.customattributes` | `conversationId` | IVR-set routing flags — confirm Architect data action outcome |
| 5 | `telephony.get.sip.messages.for.conversation` | `conversationId` (voice) | DNIS in SIP INVITE headers — confirms DID table lookup |
| 6 | `flows.get.all.flows` | `flowId` | IVR flow version active at routing time |

### Diagnostic Signals

| Observation | Diagnosis |
|-------------|-----------|
| DNIS mismatch in SIP INVITE | DID assignment misconfigured; check trunk DNIS routing table |
| Conversations arriving with no IVR segment | Callers routing direct to queue, bypassing IVR; confirm DID points to flow |
| High `transferCount` on majority of conversations | Routing loop or under-staffed primary queue causing cascading transfers |
| ANI = Anonymous on misrouted calls | CLI blocking affecting ANI-dependent routing logic |
| `customattributes` routing flag = unexpected value | Architect data action returned wrong intent; check data action response mapping |

---

## 18. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conv Deep Dive | Queue Inv | Division Inv | Exec Rollup | Real-Time | Agent Inv | Adherence | Journey | Copilot/KB | BYOI/Voice Eng |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | | | ● |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | | ● |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | ● |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | ● |
| `conversations.search.participant.attributes` | ● | | | | | | | | | ● |
| `conversations.get.call.detail` | ● | | | | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ● | | | | | | | | | |
| `conversations.get.conversation.summaries` | ● | | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | | |
| `quality.get.conversation.surveys` | ● | | | | | | | ● | | |
| `quality.get.surveys` | | | | ● | | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | ● |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | ○ | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | ● |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ● | ● | | |
| `analytics.query.conversation.details.by.queue` | | ● | | | | | | | | ● |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | ● | ● | | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | |
| `authorization.get.division.grants` | | | ● | | | ● | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | ● | | | |
| `analytics.query.user.aggregates.performance.metrics` | | | | ● | | ● | ● | | ● | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | ● | | ● | |
| `coaching.get.appointments` | | | ● | | | ○ | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | |
| `analytics.query.conversation.transcripts` | | | | ● | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | ● |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | ● |
| `alerting.get.alerts` | | | | ○ | ● | | | | | ○ |
| `users.get.user.details.with.full.expansion` | | | | | | ● | ● | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | |
| `audit-logs` | | | | | | ● | | | | |
| `workforce.get.agent.management.unit` | | | | | | | ● | | | |
| `workforce.get.adherence.bulk` | | | | | | | ● | | | |
| `workforce.get.management.units` | | | | ● | | | | | | |
| `workforce.get.management.unit.adherence` | | | | ● | | | | | | |
| `journey.get.session` | | | | | | | | ● | | ● |
| `journey.get.session.events` | | | | | | | | ● | | ● |
| `externalcontacts.get.contact.journey.sessions` | | | | | | | | ● | | |
| `analytics.get.agent.copilot.aggregates` | | | | | | | | | ● | |
| `analytics.query.knowledge.aggregates` | | | | | | | | | ● | |
| `analytics.get.botflow.sessions` | | | | ● | | | | | ● | |
| `analytics.query.flow.execution.aggregates` | | | | ● | | | | | ● | |
| `flows.get.all.flows` | | | | ● | ○ | | | | ● | ● |
| `flows.get.flow.outcomes` | | | | ● | | | | | ● | |
| `flows.get.flow.milestones` | | | | ● | | | | | | |

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
| `adherencePct` | Scheduled vs. actual on-queue time % | WFM performance |
| `deviationSeconds` | Seconds deviated from scheduled state | Adherence gap magnitude |
| `estimatedWaitTimeSeconds` | Forecast wait time for next caller | Real-time staffing trigger |
| `nFlowExecutions` | Total flow executions | Self-service volume |
| `nFlowOutcomeSuccess` | Successful self-service exits | Containment numerator |
| `containmentRate` | Self-served / total flow executions % | Bot/IVR ROI |
| `copilotAcceptanceRate` | Accepted copilot suggestions / total % | AI assist engagement |
| `nArticleViews` | Knowledge article views by agents | KB utilisation |
| `searchQueriesWithNoResult` | Searches returning no article | Content gap indicator |
| `externalTag` | BYOI provider-set conversation tag | BYOI identification |
| `externalConversationId` | Provider's own conversation identifier | BYOI cross-reference |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
