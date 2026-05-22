# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-22  
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
10. [Customer Context Investigation](#10-customer-context-investigation)
11. [IVR / Bot Containment Analysis](#11-ivr--bot-containment-analysis)
12. [AI-Assisted Rapid Triage](#12-ai-assisted-rapid-triage)
13. [Quality Management Cohort Analysis](#13-quality-management-cohort-analysis)
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

---

## 10. Customer Context Investigation

**Subject:** One `conversationId` where the caller is a known external contact  
**Use case:** A CRM-integrated contact centre needs to understand not just what happened in the
Genesys conversation, but who the customer is, what they've done across digital channels before
calling, and what prior interaction history exists. Divisions group agents who serve specific
customer segments — this pattern crosses the segment boundary to add customer-side context.

**Core question:** *Who was this customer, what did they do before calling, and what happened in
their conversation?*

### How to Identify an External Contact

`conversations.get.conversation.object` returns `participants[].externalContactId` when the
conversation was associated with a known CRM contact. A non-null value is the entry point.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | `externalContactId` from participants, queue, start/end, DNIS/ANI |
| 2 | `externalcontacts.get.contact.details` | `externalContactId` | Name, phone, email, title, org link, custom CRM fields |
| 3 | `externalcontacts.get.contact.notes` | `externalContactId` | Prior interaction notes, follow-up actions, agent-authored history |
| 4 | `externalcontacts.get.contact.journey.sessions` | `externalContactId` | Journey session list linked to this contact |
| 5 | `journey.get.session.details` | `sessionId` (from step 4) | Channel, device, start time for the session closest to call time |
| 6 | `journey.get.session.events` | `sessionId` | Page views, form fills, engagement triggers before the call |
| 7 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing: IVR duration, ACD wait, talk, hold, ACW |
| 8 *(STA enabled)* | `speechandtextanalytics.get.conversation.summaries` | `conversationId` | AI summary: reason for call, resolution, action items |

### Key Joins

```
conversations.get.conversation.object.participants[].externalContactId
  → externalcontacts.get.contact.details.id
  → externalcontacts.get.contact.notes[].contact.id
  → externalcontacts.get.contact.journey.sessions[].contact.id

externalcontacts.get.contact.journey.sessions[].sessionId
  → journey.get.session.details.id
  → journey.get.session.events[].session.id

[time filter: select session with startTime closest to conversation.startTime]
```

### Analytical Questions Answered

- Is this customer a repeat caller? How many prior notes exist?
- What pages did the customer visit before calling? Did they try self-service first?
- Did predictive engagement trigger a proactive offer before the call?
- What was the call reason and resolution (from AI summary)?
- Was the customer able to resolve their issue, or is this a repeat contact?

### Division Note

Divisions define which agents serve which customer segments. When an external contact is linked
to a division-scoped queue, the `externalContactId` bridge connects the external CRM identity
to internal routing and agent performance data without blurring division boundaries.

---

## 11. IVR / Bot Containment Analysis

**Subject:** One `botFlowId` + time window  
**Use case:** A voice engineer or IVR developer needs to understand how effectively the bot/IVR
is containing calls without agent escalation. High escalation rates signal intent recognition
failures, missing self-service paths, or customers actively bypassing automation.

**Core question:** *Is the bot/IVR containing calls effectively, and where does it fail?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | seed → `botFlowId` | Flow name, flow type, published version |
| 2 | `analytics.botflow.get.sessions` | `botFlowId` | All sessions in the window: containment outcome, escalation reason, conversation IDs |
| 3 | `analytics.botflow.get.reporting.turns` | `botFlowId` + `sessionId` | Per-turn NLU results: intent detected, confidence, entity extraction, misfire |
| 4 | `analytics.query.bot.aggregates` | `botFlowId` | Aggregate: nBotTurns, nBotContainedCompletions, nBotEscalations, nBotDisconnectCompletions |
| 5 | `analytics.query.flowexecution.aggregates` | `flowId` | nFlowEntries, nFlowExits, nFlowMilestones, nFlowOutcomes (IVR path coverage) |
| 6 *(escalated only)* | `analytics-conversation-details-query` (sessionIds filter) | `conversationId` | Full conversation analytics for escalated sessions — where the call went after escalation |
| 7 *(STA enabled)* | `speechandtextanalytics.get.conversation.categories` | `conversationId` (escalated) | What topics/categories appeared in escalated conversations |

### Key Joins

```
analytics.botflow.get.sessions[].id (sessionId)
  → analytics.botflow.get.reporting.turns.sessionId
  → analytics.botflow.get.sessions[].conversationId (escalated only)
    → analytics-conversation-details-query[].conversationId
    → speechandtextanalytics.get.conversation.categories[].conversationId

analytics.query.bot.aggregates[].group.botFlowId
  → flows.get.all.flows[].id (name resolution)
```

### Analytical Questions Answered

- What percentage of sessions were contained vs. escalated? (containment rate)
- What intents had the highest miss/fallback rate?
- Which turns in the flow most often lead to "I don't understand" escalations?
- What topics are customers escalating about that the bot cannot handle?
- After escalation, which queues and agents receive bot-deflected calls?

### Aggregate KPI Composition

```
Containment rate: nBotContainedCompletions / (nBotContainedCompletions + nBotEscalations) × 100
Escalation rate: nBotEscalations / total sessions × 100
Avg turns per session: nBotTurns / total sessions
Intent hit rate: turns with recognised intent / total turns × 100
```

---

## 12. AI-Assisted Rapid Triage

**Subject:** One `conversationId` (or a batch from a queue/agent investigation)  
**Use case:** A QM analyst or supervisor needs to triage a large number of conversations quickly —
flagged by a rule, a customer complaint, or a scheduled review batch — without listening to every
recording. The AI-derived layers (summaries, sentiment, categories, transcripts) reduce the
time-to-insight from minutes to seconds per conversation.

**Core question:** *What happened in this conversation, and does it warrant deeper review?*

### Dataset Steps (ordered, all conditional on STA/AI licence)

| Step | Dataset Key | Join Key | What It Adds | Licence |
|------|-------------|----------|--------------|---------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Participants, queue, DNIS/ANI, start/end, externalTag |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing: IVR, wait, talk, hold, ACW — flags unusually long or short segments | Any |
| 3 | `speechandtextanalytics.get.conversation.summaries` | `conversationId` | AI summary: reason, resolution, action items — **read this first** | STA + Summarisation |
| 4 | `conversations.get.speech.text.analytics` | `conversationId` | Overall sentiment, topics, STA analysis status — confirms STA ran | STA |
| 5 | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-utterance sentiment timeline — which moments were most negative? | STA |
| 6 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Interaction categories fired — compliance, complaint, escalation signals | STA |
| 7 *(targeted)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcript download URL — read specific utterances identified in steps 5–6 | STA |
| 8 *(targeted)* | `speechandtextanalytics.get.transcript.urls.all.segments` | `communicationId` | All segment transcript URLs for multi-segment calls | STA |
| 9 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs — escalate to full recording review only if steps 3–6 flag the call | Any |
| 10 | `quality.get.evaluations.query` | `conversationId` | Was this conversation already evaluated? What score? | QM |

### Triage Decision Tree

```
Step 3 summary: call reason resolved? → No → flag for evaluation
Step 4 status: STA analysisStatus = "Success"? → No → escalate to manual review
Step 5 sentiment: customer sentiment trend negative throughout? → Yes → flag
Step 6 categories: "complaint", "escalation", "legal", "churn" detected? → Yes → priority flag
Any flag → read step 7 transcript snippet for specific utterances
Multiple flags → schedule evaluation (step 10 confirms if one already exists)
No flags + steps 3/4/5 all clear → mark as triaged, no further action
```

### Executive Value

This pattern scales across a population: run steps 1–6 for every conversation in a queue in a
week, aggregate the category detections, and you have a call-reason taxonomy and complaint-rate
dashboard without manually reviewing a single call.

---

## 13. Quality Management Cohort Analysis

**Subject:** A set of agents (by `userId` list), queues (`queueId` list), or a division (`divisionId`) + time window  
**Use case:** A QM manager or contact centre director needs to understand evaluation coverage,
score trends, and coaching effectiveness across a group. Divisions are the natural cohort boundary —
a division is a group of agents, and QM targets are often set at the division level.

**Core question:** *How well is this group being evaluated, what are the score trends, and is coaching driving improvement?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.division.analysis.get.users.with.division.info` | seed → `divisionId` | All agents in the division |
| 2 | `analytics.query.evaluation.aggregates` | `userId` list | nEvaluations, oEvaluationScore, nEvaluationsWithScores per agent — coverage and average score |
| 3 | `quality.get.agents.activity` | `userId` | Evaluation counts, highest/average/lowest scores, evaluator IDs |
| 4 | `analytics.query.evaluation.aggregates` (by `evaluatorUserId`) | `evaluatorUserId` | Evaluator workload distribution — who is evaluating whom? |
| 5 | `quality.get.evaluations.query` | `userId` + window | Individual evaluations with form IDs — which forms are being used? |
| 6 | `quality.get.conversation.evaluation.detail` | `evaluationId` (from step 5) | Full section scores and evaluator comments for targeted drilldown |
| 7 | `quality.get.surveys` | `conversationId` (from step 5) | Post-call CSAT/NPS for evaluated conversations — does score correlate with satisfaction? |
| 8 | `coaching.get.appointments` | `userId` | Coaching sessions scheduled/completed — is coaching correlated with score improvement? |

### Key Joins

```
users.division.analysis.get.users.with.division.info[].id
  → analytics.query.evaluation.aggregates[].group.userId
  → quality.get.agents.activity[].user.id
  → coaching.get.appointments[].attendees[].id

quality.get.evaluations.query[].id (evaluationId)
  → quality.get.conversation.evaluation.detail.id

quality.get.evaluations.query[].conversation.id
  → quality.get.surveys[].conversation.id (left join — survey may not exist)
```

### Analytical Questions Answered

- What percentage of agents in this division have been evaluated in the window? (coverage rate)
- Which agents have the highest/lowest average scores?
- Is there a correlation between low scores and subsequent coaching sessions?
- Did scores improve after coaching appointments?
- Which evaluators are scoring most harshly or most leniently? (inter-rater reliability signal)
- For agents with the lowest scores, which evaluation form sections are dragging them down?
- Is post-call CSAT correlated with evaluation score? (validates QM form design)

### Executive Metric Composition

```
QM coverage rate: agents_evaluated / total_agents × 100
Average QM score: oEvaluationScore weighted average across cohort
Score distribution: histogram of oEvaluationScore values
Coaching impact: ΔAVG(score) for coached vs. non-coached agents in the period
CSAT correlation: Pearson(oEvaluationScore, survey.totalScore) per queue
```

---

## 14. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conv Deep Dive | Queue Inv | Division Inv | Exec Rollup | Real-Time | Agent Inv | Customer Context | Bot/IVR | AI Triage | QM Cohort |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | ● | | ● | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | ● | | ● | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | ● | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | ● | ● |
| `quality.get.surveys` | ● | | | ● | | | | | | ● |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | ● | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | ● | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | ● | |
| `routing.get.single.queue.config` | | ● | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | | ○ | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | ● |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | ● |
| `coaching.get.appointments` | | | ● | | | ○ | | | | ● |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | |
| `audit-logs` | | | | | | ● | | | | |
| `externalcontacts.get.contact.details` | | | | | | | ● | | | |
| `externalcontacts.get.contact.notes` | | | | | | | ● | | | |
| `externalcontacts.get.contact.journey.sessions` | | | | | | | ● | | | |
| `journey.get.session.details` | | | | | | | ● | | | |
| `journey.get.session.events` | | | | | | | ● | | | |
| `analytics.botflow.get.sessions` | | | | | | | | ● | | |
| `analytics.botflow.get.reporting.turns` | | | | | | | | ● | | |
| `analytics.query.bot.aggregates` | | | | ○ | | | | ● | | |
| `analytics.query.flowexecution.aggregates` | | | | ○ | | | | ● | | |
| `flows.get.all.flows` | | | | | | | | ● | | |
| `speechandtextanalytics.get.conversation.summaries` | | | | | | | ○ | | ● | |
| `speechandtextanalytics.get.conversation.categories` | | | | | | | | ○ | ● | |
| `speechandtextanalytics.get.transcript.urls.all.segments` | ○ | | | | | | | | ● | |
| `quality.get.conversation.evaluation.detail` | | | | | | | | | | ● |
| `analytics.query.evaluation.aggregates` | | | | ● | | | | | | ● |
| `analytics.query.agentcopilot.aggregates` | | | | ○ | | | | | | |

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
| `nBotTurns` | Total turns processed by a bot flow session | Bot engagement depth |
| `nBotContainedCompletions` | Sessions fully resolved without agent escalation | Self-service containment |
| `nBotEscalations` | Sessions escalated to an agent | Escalation rate numerator |
| `nBotDisconnectCompletions` | Sessions ended by customer without resolution | Abandonment in bot |
| `nFlowEntries` | Times a flow was entered | IVR invocation volume |
| `nFlowExits` | Times a flow exited normally | Flow completion count |
| `nFlowMilestones` | Milestone actions reached in a flow | Path coverage indicator |
| `nFlowOutcomes` | Distinct outcomes fired in a flow | IVR outcome distribution |
| `nEvaluations` | Total QM evaluations scored | Evaluation coverage count |
| `oEvaluationScore` | Average quality evaluation score (0–100) | QM quality KPI |
| `nEvaluationsWithScores` | Evaluations that have a numeric score (excludes in-progress) | Coverage denominator |
| `nCopilotSuggestionsAccepted` | Agent Copilot suggestions the agent accepted | AI adoption rate |
| `nCopilotSuggestionsDeclined` | Agent Copilot suggestions the agent dismissed | AI adoption rate complement |
| `nCopilotKnowledgeArticleViews` | Knowledge articles viewed via Agent Copilot | Knowledge utilisation |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*  
*New datasets added 2026-05-22: externalcontacts, journey, bot/flow analytics, STA summaries/categories, QM evaluation detail, evaluation aggregates, Agent Copilot aggregates.*
