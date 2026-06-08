# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-08  
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
7. [Bot / Virtual Agent Investigation](#7-bot--virtual-agent-investigation)
8. [Agent Investigation Extensions](#8-agent-investigation-extensions-release-13)
9. [Conversation Investigation Extensions](#9-conversation-investigation-extensions-release-13)
10. [Queue Investigation Extensions](#10-queue-investigation-extensions-release-13)
11. [Dataset Combination Reference Matrix](#11-dataset-combination-reference-matrix)

---

## 1. Single Conversation Deep Dive (Voice Engineer)

**Subject:** One `conversationId`  
**Use case:** A voice engineer or QM analyst receives a complaint about a specific call — wrong queue,
long hold, audio quality, dropped call, incorrect routing. They need the complete picture of one
conversation: where it came from, how it routed, how long each phase took, what the SIP signaling said,
whether a recording exists, and what the quality score was.

**Core question:** *What actually happened in this conversation, end-to-end?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Participants, sessions, DNIS/ANI, start/end times, queue assignment, externalTag (BYOI indicator), externalContactId |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Per-segment timing: IVR duration, ACD wait, talk time, hold time, ACW, conference, recording start/stop |
| 3 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs, media type, duration, deletion schedule |
| 4 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by IVR/Architect flows (account numbers, intent, escalation flags) |
| 5 | `conversations.search.participant.attributes` | `conversationId` | Participant-level attributes (IVR variables, data action outcomes, flow-set values) |
| 6 | `quality.get.evaluations.query` | `conversationId` | QM evaluation scores, form used, evaluator, calibration status |
| 7 *(if evaluated)* | `quality.get.calibrations` | `conversationId` | Whether the evaluation was part of a calibration session and inter-rater agreement |
| 8 | `quality.get.surveys` | `conversationId` | Post-call CSAT/NPS survey result if survey was triggered |
| 9 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace: INVITE, 200 OK, BYE, re-INVITE, codec negotiation |
| 10 *(STA enabled)* | `conversations.get.speech.text.analytics` | `conversationId` | Sentiment score, detected topics, STA coverage summary |
| 11 *(STA enabled)* | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Sentiment timeline: per-utterance scores, agent vs customer breakdown |
| 12 *(transcription enabled)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId` + `communicationId` | Transcript download URL per communication leg |
| 13 *(external contact present)* | `externalcontacts.get.contact` | `participants[].externalContactId` | CRM contact record: name, org, phone, email, custom schema fields |
| 14 *(external contact present)* | `externalcontacts.get.contact.journey.sessions` | `externalContactId` | Customer's prior journey sessions — repeat contact history, previous channels used |

### Key Joins

```
conversations.get.conversation.object.conversationId
  → analytics.get.single.conversation.analytics.conversationId (segment overlay)
  → conversations.get.conversation.recording.metadata.conversationId
  → telephony.get.sip.messages.for.conversation.conversationId (voice only)
  → quality.get.evaluations.query[].conversationId (left join — evaluations may not exist)
  → quality.get.calibrations[].conversationId (left join — conditional on evaluation)

conversations.get.conversation.object.participants[].externalContactId
  → externalcontacts.get.contact.id (left join — present only if CRM linked)
  → externalcontacts.get.contact.journey.sessions[].externalContactId

analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
  → speechandtextanalytics.get.conversation.communication.transcripturl.communicationId
```

### Analytical Questions Answered

- What was the full call flow? (IVR → ACD → agent → hold → ACW)
- How long did the customer wait before an agent answered?
- Was the call transferred? How many times? What queue received the transfer?
- Was a recording made? Does it still exist?
- Did the SIP trunk establish media correctly? (from SIP trace)
- Was the agent rated? What was the QM score? Was it a calibration call?
- Was the customer surveyed? What was the CSAT result?
- What intent/attributes did the IVR capture before routing?
- Is this a known customer? What is their repeat-contact history? (via external contact + journey)

### Voice Engineer Notes

Step 9 (SIP trace) is the definitive source for:
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
The SIP trace (step 9) will reflect the provider's SIP-to-SIP handoff, not an inbound PSTN leg.

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
| 10 | `routing.get.queue.estimated.wait.time` | `queueId` | Current real-time estimated wait time at investigation moment |
| 11 | `quality.get.evaluations.query` (queueId filter) | `conversationId` | QM evaluation coverage and scores for conversations in this queue |
| 12 *(bot-enabled queue)* | `analytics.query.bot.aggregates` | `queueId` | Self-service containment rate: nBotSessions handled vs escalated to queue |

### Key Joins

```
routing.get.single.queue.config.id
  → analytics.query.conversation.aggregates.*.queueId (aggregate overlay)
  → routing-queue-members.queueId (who was staffed)
  → routing.get.queue.estimated.wait.time.queueId (real-time EWT snapshot)

analytics.query.conversation.aggregates.wrapup.distribution.wrapUpCode
  → routing.get.queue.wrapup.codes.by.queue.id (label resolution)

analytics-conversation-details-query[].conversationId
  → quality.get.evaluations.query[].conversationId (left join — not all conversations are evaluated)

analytics.query.bot.aggregates[].group.queueId
  → routing.get.single.queue.config.id (containment rate = nBotSessions not escalated / total)
```

### Analytical Questions Answered

- What was the offered/connected/abandoned volume for this queue?
- Did the queue meet its SLA target? In which hourly intervals did it miss?
- What percentage of conversations were transferred? Where did they go?
- What wrapup codes dominated, and what do they mean?
- Who were the active agents? What was their routing status during the window?
- How many conversations were quality-reviewed? What was the average score?
- What is the current estimated wait time? (real-time EWT)
- What share of contacts was handled by the bot before reaching this queue? (containment rate)

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
quality scores, coaching coverage, and gamification standing.

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
| 10 *(WFM licensed)* | `workforce.get.user.schedule.adherence` | `userId` | Schedule adherence: actual vs scheduled presence, adherence % per agent |
| 11 *(gamification enabled)* | `gamification.get.agent.insights` | `userId` | Per-agent gamification ranking, metric scores, period-over-period trend |

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
  → workforce.get.user.schedule.adherence[].userId
  → gamification.get.agent.insights.userId
```

### Analytical Questions Answered

- How many agents are in this division and who are they?
- What queues does this division own?
- Which agents handled the most volume? Which had the highest AHT?
- Which agents spent the most time off-queue or in non-productive states?
- Which agents have been evaluated? Who has the highest/lowest scores?
- Which agents have received recent coaching? Is coaching correlated with score improvement?
- Which agents are off-schedule today? By how much? (schedule adherence)
- How do agents rank in the gamification program? Who is in the top/bottom quartile?

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
| `workforce.get.user.schedule.adherence` | `userId`, point-in-time | Adherence % snapshot — flag agents significantly off-schedule |

#### Layer 4 — Quality & Voice-of-Customer
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `quality.get.agents.activity` | `userId` | Evaluation coverage rate, average score, score distribution |
| `quality.get.surveys` | `conversationId` (aggregate) | CSAT/NPS: response rate, average score |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | Speech analytics coverage: nSpeechTextAnalyzedConversations, oSentimentScore |

#### Layer 5 — Self-Service & Automation
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.bot.aggregates` | `queueId`, `botId`, daily | Bot containment rate: nBotSessions not escalated / total offered to bot |
| `analytics.query.flow.aggregates.execution.metrics` | `flowId`, daily | IVR flow completion: nFlow, nFlowOutcome, nFlowOutcomeSuccess |

#### Layer 6 — Infrastructure Health (optional, voice-focused)
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
  - Bot containment rate: nBotSessions contained / total bot sessions × 100
  - Self-service rate: bot contained / (bot contained + nConnected) × 100
  - QM coverage: evaluations / nConnected × 100
  - Average QM score: from quality.get.agents.activity
  - Avg CSAT: from quality.get.surveys
  - IVR completion rate: nFlowOutcomeSuccess / nFlow × 100

Trend views (daily granularity):
  - Volume by day with channel mix
  - AHT trend by queue
  - Abandon rate trend by queue
  - SLA achievement heatmap by queue × day
  - Bot containment trend by queue (if bot-enabled)
```

### Key Joins for Executive Reporting

```
routing-queues[].id
  → analytics.query.conversation.aggregates.*.results[].group.queueId
  → routing.get.queue.wrapup.codes.by.queue.queueId (label resolution)
  → quality.get.agents.activity (left join via queue membership)
  → analytics.query.bot.aggregates[].group.queueId (left join — bot-enabled queues only)

analytics.query.conversation.aggregates.wrapup.distribution[].group.wrapUpCode
  → routing.get.all.wrapup.codes[].id (global wrapup code labels)

flows.get.all.flows[].id
  → analytics.query.flow.aggregates.execution.metrics[].group.flowId (IVR completion by flow)
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
| 3 | `routing.get.queue.estimated.wait.time` | Target queue | Current EWT in seconds — lagging indicator to validate observations data |
| 4 | `analytics.query.user.observations.real.time.status` | All agents | oUserPresence (system presence), oUserRoutingStatus per agent |
| 5 | `analytics.get.agent.active.status` | One agent | Full real-time channel assignment for a specific agent — active conversation IDs |
| 6 | `users.get.agent.active.conversations` | One agent | All in-progress conversations for a specific agent |
| 7 | `users.get.agent.current.routing.status` | One agent | Current routing state (IDLE / INTERACTING / NOT_RESPONDING / OFF_QUEUE) |
| 8 | `analytics.query.flow.observations` | All flows | oFlow: active Architect flows currently executing |
| 9 | `analytics.query.flow.activity` | All flows | oFlowMilestone, oFlowOutcome: IVR milestone and outcome state per flow |
| 10 *(telephony NOC)* | `telephony.get.trunk.metrics.summary` | — | Trunk utilisation and error counters |
| 11 *(telephony NOC)* | `telephony.get.edge.performance.metrics` | One Edge | CPU, memory, active call count on specific Edge |

### Polling Note

Real-time datasets (`analytics.query.queue.observations.real.time.stats`,
`analytics.query.conversation.activity.real.time`, `analytics.query.user.observations.real.time.status`)
do not accept `interval` parameters — they reflect the current state as of the API call. These
should be polled at the rate appropriate for the display (typically 10–30 seconds for a wall board).

`routing.get.queue.estimated.wait.time` provides a second perspective on wait — the algorithmic EWT
forecast — that may diverge from `oWaiting` when volume is spiking faster than the observations update.

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
| + | `externalcontacts.get.contact` | Full CRM contact record for the participant (name, org, history fields) |
| + | `externalcontacts.get.contact.journey.sessions` | Customer's full journey: prior web sessions, previous contacts, channel history |

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

## 7. Bot / Virtual Agent Investigation

**Subject:** One `botFlowId` + time window  
**Use case:** A bot developer, conversation designer, or operations analyst needs to understand
how a bot flow is performing — session volumes, containment rates, escalation patterns, and which
turn sequences most often lead to escalation. This investigation identifies self-service
improvements and diagrams the boundary between bot and human-handled contacts.

**Core question:** *How well is this bot containing contacts, and where is it failing?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` (filtered by type=bot) | seed → `flowId` / `botFlowId` | Bot flow metadata: name, version, published state, inbound entry points |
| 2 | `analytics.get.botflow.sessions` | `botFlowId` | All sessions: start/end times, containment outcome (CONTAINED / ESCALATED / ABANDONED), linked conversationId |
| 3 | `analytics.query.bot.aggregates` | `botFlowId` / `queueId` | Aggregate roll-up: nBotSessions, tBotSessionDuration (avg), nBotSessionTurns (avg), containment rate |
| 4 | `analytics.get.botflow.reporting.turns` | `botFlowId` | Turn-by-turn detail: intents recognised, NLU confidence, slot values, turn outcome — identify which turns precede escalation |
| 5 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Flow-level: nFlow, nFlowOutcome, nFlowOutcomeSuccess, nFlowOutcomeFail — milestone and outcome funnel |
| 6 *(escalated sessions)* | `analytics-conversation-details-query` (conversationId list from step 2) | `conversationId` | Full conversation analytics for escalated sessions — queue routed to, agent AHT, wrapup |
| 7 *(escalated sessions)* | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Aggregate performance for the queues receiving bot escalations — validates escalation routing |

### Containment Rate Formula

```
Containment rate = (nBotSessions where outcome = CONTAINED) / total nBotSessions × 100

From analytics.query.bot.aggregates, group by botId:
  nBotSessions (total)
  nFlowOutcomeSuccess (contained)
  nFlowOutcomeFail (unresolved / abandoned)
  escalated = nBotSessions - nFlowOutcomeSuccess

Escalation rate = escalated / nBotSessions × 100
```

### Key Joins

```
flows.get.all.flows[].id (botFlowId)
  → analytics.get.botflow.sessions[].botFlowId
  → analytics.query.bot.aggregates[].group.flowId
  → analytics.get.botflow.reporting.turns[].botFlowId

analytics.get.botflow.sessions[].conversationId (escalated sessions only)
  → analytics-conversation-details-query[].conversationId
  → analytics.query.conversation.aggregates.queue.performance[].group.queueId
```

### Analytical Questions Answered

- How many contacts entered the bot? What percentage were fully contained?
- Which sessions escalated? To which queues? What wrapup codes resulted?
- At which turn in the conversation does escalation most often occur?
- What intents have low NLU confidence (contributing to fallback escalations)?
- How does average bot session duration compare to human handle time for the same intent?
- What is the per-queue escalation volume? Are certain queues overloaded by bot handoffs?

---

## 8. Agent Investigation Extensions (Release 1.3)

The existing Agent Investigation (`Get-GenesysAgentInvestigation`) covers 8 steps. These additional
datasets enrich the investigation without replacing any existing step.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| station | `users.get.user.station` | `userId` | Default station (desk phone / softphone), associated station, registration status |
| utilization | `routing.get.user.utilization` | `userId` | Max channel capacities — why can the agent only handle N simultaneous chats? |
| currentStatus | `users.get.agent.current.routing.status` | `userId` | Routing state at investigation time (IDLE / INTERACTING / OFF_QUEUE) |
| activeConversations | `users.get.agent.active.conversations` | `userId` | In-progress conversations if `currentStatus = INTERACTING` |
| qualityActivity | `quality.get.agents.activity` | `userId` | Evaluation count, average/highest/lowest scores for the window |
| coaching | `coaching.get.appointments` | `userId` | Coaching sessions attending/facilitating in the window |
| scheduleAdherence | `workforce.get.user.schedule.adherence` | `userId` | Current adherence state and adherence % — is the agent on schedule? |
| gamificationInsights | `gamification.get.agent.insights` | `userId` | Performance program ranking, metric scores, period trend (gamification licensed only) |
| gamificationProfile | `gamification.get.agent.profile` | `userId` | Which performance profile governs this agent's scorecard |

**Trigger conditions:**
- `currentStatus` and `activeConversations` — conditional on agent being in an active state at investigation time.
- `coaching` — conditional on WFM being licensed and configured.
- `scheduleAdherence` — conditional on WFM schedule being published for the agent's management unit.
- `gamificationInsights` / `gamificationProfile` — conditional on Gamification module being licensed.

**Station enrichment note:** `users.get.user.station` returns three station slots: `defaultStation`,
`associatedStation`, and `effectiveStation`. For voice quality investigations, the `effectiveStation`
at call time determines which Edge the agent's SIP traffic traversed — cross-reference with the SIP
trace's `Contact` header.

---

## 9. Conversation Investigation Extensions (Release 1.3)

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
| calibration | `quality.get.calibrations` | `conversationId` | Whether the QM evaluation was part of a calibration session |
| externalContact | `externalcontacts.get.contact` | `participants[].externalContactId` | CRM contact record (conditional on externalContactId being present) |
| customerJourney | `externalcontacts.get.contact.journey.sessions` | `externalContactId` | Customer's prior sessions — repeat contact history (conditional on external contact) |

**Conditional steps:**
- `sipTrace` — runs only when `conversations.get.conversation.object.participants[].calls` is non-empty (voice conversation).
- `sentimentTimeline` — runs only when `conversations.get.speech.text.analytics` returns `analysisStatus = "Success"`.
- `calibration` — runs only when `quality.get.evaluations.query` returns at least one evaluation.
- `externalContact` / `customerJourney` — run only when any participant has a non-null `externalContactId`.

---

## 10. Queue Investigation Extensions (Release 1.3)

The existing Queue Investigation (`Get-GenesysQueueInvestigation`) covers 6 steps. These additions
complete the picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| queueConfig | `routing.get.single.queue.config` | `queueId` | Full queue config (replaces/enriches the routing-queues list step) |
| wrapupLabels | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Human-readable labels for the wrapup distribution step |
| transfers | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer rate and type breakdown |
| wrapupDistribution | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Wrapup code frequencies (join wrapupLabels for labels) |
| conversationDetail | `analytics-conversation-details-query` (queueId filter) | `conversationId` | Individual conversations for case-level review |
| estimatedWaitTime | `routing.get.queue.estimated.wait.time` | `queueId` | Current real-time EWT at investigation moment |
| estimatedWaitTimeByMedia | `routing.get.queue.estimated.wait.time.by.media` | `queueId` + `mediaType` | Per-channel EWT (voice, chat, email, callback) |
| botContainment | `analytics.query.bot.aggregates` | `queueId` | Bot containment feeding this queue: escalation volume and rate |

---

## 11. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | Bot Investigation |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | |
| `quality.get.calibrations` | ○ | | | | | | |
| `quality.get.surveys` | ● | | | ● | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | |
| `externalcontacts.get.contact` | ○ | | | | | | ○ |
| `externalcontacts.get.contact.journey.sessions` | ○ | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | | |
| `routing.get.queue.estimated.wait.time.by.media` | | ○ | | | ○ | | |
| `routing.get.skill.group.members` | | | ○ | | | ○ | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ○ |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | ○ |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | |
| `routing-queue-members` | | ● | | | | | |
| `analytics.query.bot.aggregates` | | ○ | | ● | | | ● |
| `analytics.get.botflow.sessions` | | | | | | | ● |
| `analytics.get.botflow.reporting.turns` | | | | | | | ● |
| `analytics.query.flow.activity` | | | | | ● | | |
| `authorization.get.single.division` | | | ● | | | | |
| `authorization.list.division.queues` | | | ● | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | |
| `coaching.get.appointments` | | | ● | | | ○ | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | ● | | | ● |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | |
| `analytics.query.flow.observations` | | | | | ● | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | |
| `alerting.get.alerts` | | | | ○ | ● | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | |
| `users.get.user.routing.skills` | | | | | | ● | |
| `users.get.user.queue.memberships` | | | | | | ● | |
| `users.get.bulk.user.presences` | | | | | | ● | |
| `users.get.user.station` | | | | | | ○ | |
| `routing.get.user.utilization` | | | | | | ○ | |
| `workforce.get.user.schedule.adherence` | | | ○ | ● | | ○ | |
| `gamification.get.agent.insights` | | | ○ | | | ○ | |
| `gamification.get.agent.profile` | | | | | | ○ | |
| `flows.get.all.flows` | | | | | | | ● |
| `audit-logs` | | | | | | ● | |

---

## Appendix A: Metric Glossary

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
| `nBotSessions` | Total bot flow sessions | Self-service volume |
| `tBotSessionDuration` | Total bot session duration | Bot handling time |
| `nBotSessionTurns` | Turns (exchanges) per bot session | Conversation depth |
| `nFlowOutcome` | Times a flow outcome was reached | Completion tracking |
| `nFlowOutcomeSuccess` | Times a success outcome was reached | Containment / resolution |

---

## Appendix B: New Datasets Added (June 2026)

The following 14 datasets were added to the catalog in this review cycle to support richer
investigations and the combinations documented above:

| Dataset Key | Endpoint | Investigation Use |
|-------------|----------|-------------------|
| `routing.get.skill.group.members` | `GET /api/v2/routing/skillgroups/{skillGroupId}/members` | Agent investigation — skill group membership |
| `routing.get.queue.estimated.wait.time` | `GET /api/v2/routing/queues/{queueId}/estimatedwaittime` | Queue investigation + real-time monitoring |
| `routing.get.queue.estimated.wait.time.by.media` | `GET /api/v2/routing/queues/{queueId}/mediatypes/{mediaType}/estimatedwaittime` | Queue investigation per channel |
| `analytics.query.bot.aggregates` | `POST /api/v2/analytics/bots/aggregates/query` | Bot investigation + executive rollup (Layer 5) |
| `analytics.get.botflow.sessions` | `GET /api/v2/analytics/botflows/{botFlowId}/sessions` | Bot investigation — session list |
| `analytics.get.botflow.reporting.turns` | `GET /api/v2/analytics/botflows/{botFlowId}/reportingturns` | Bot investigation — turn-level NLU detail |
| `analytics.query.flow.activity` | `POST /api/v2/analytics/flows/activity/query` | Real-time monitoring — active flow executions |
| `gamification.get.agent.insights` | `GET /api/v2/gamification/insights/users/{userId}/details` | Agent investigation + division investigation |
| `gamification.get.agent.profile` | `GET /api/v2/gamification/profiles/users/{userId}` | Agent investigation — scorecard context |
| `quality.get.calibrations` | `GET /api/v2/quality/calibrations` | Conversation investigation — calibration coverage |
| `externalcontacts.get.contact` | `GET /api/v2/externalcontacts/contacts/{contactId}` | Conversation investigation — CRM record |
| `externalcontacts.get.contact.journey.sessions` | `GET /api/v2/externalcontacts/contacts/{contactId}/journey/sessions` | Conversation investigation — repeat contact |
| `users.get.user.station` | `GET /api/v2/users/{userId}/station` | Agent investigation — station assignment |
| `workforce.get.user.schedule.adherence` | `GET /api/v2/workforcemanagement/adherence` | Agent + division investigation — adherence |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
