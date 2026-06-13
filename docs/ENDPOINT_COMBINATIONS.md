# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-13  
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
10. [Bot & IVR Pre-Queue Analysis](#10-bot--ivr-pre-queue-analysis)
11. [Recording Compliance & Calibration Audit](#11-recording-compliance--calibration-audit)
12. [Knowledge Base & AI Effectiveness](#12-knowledge-base--ai-effectiveness)
13. [WFM Adherence Investigation](#13-wfm-adherence-investigation)
14. [Trunk & Edge Infrastructure Health](#14-trunk--edge-infrastructure-health)
15. [Dataset Combination Reference Matrix](#15-dataset-combination-reference-matrix)

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

## 10. Bot & IVR Pre-Queue Analysis

**Subject:** One `conversationId` or `flowId` + time window  
**Use case:** A voice engineer or CX architect needs to understand what happened to a caller *before* they reached an agent — the IVR menu traversal, bot interaction, data actions, and the trigger that caused an agent handoff. Also used for self-service deflection rate reporting.

**Core question:** *What did the IVR/bot collect and do before the call hit the queue?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.specific.conversation.details` | seed → `conversationId` | Identifies IVR/bot participants by `purpose=acd/ivr` before the agent participant appears |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timeline: `tFlow` (IVR time), `tAcd` (queue wait), `tTalk` — the pre-queue duration |
| 3 | `conversations.get.conversation.customattributes` | `conversationId` | IVR-captured data: intent, account number, authentication result, escalation trigger |
| 4 | `conversations.search.participant.attributes` | `conversationId` | Per-participant flow variables: DTMF selections, data action results, retry counts |
| 5 | `analytics.post.bots.aggregates.query` | `flowId` | Bot session aggregates: `nBotSessions`, `nBotTurns`, `nBotIntentConfirmed`, `nBotIntentNotHandled` |
| 6 | `analytics.get.botflow.sessions` | `flowId` | Individual bot sessions with intent, outcome (`Escalated/Handled/Abandoned`), turn count |
| 7 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Architect flow execution: `nFlow`, `nFlowOutcome`, `nFlowOutcomeFailed`, `nFlowMilestone` |
| 8 | `flows.get.all.flows` | `flowId` | Flow metadata: name, type (`INBOUNDCALL/BOT/INQUEUECALL`), published version |
| 9 | `flows.get.flow.outcomes` | `outcomeId` | Outcome label definitions — decode `nFlowOutcome` values |
| 10 | `flows.get.flow.milestones` | `milestoneId` | Milestone labels — identify where callers drop off in the flow |

### Key Joins

```
conversations.get.specific.conversation.details.participants[purpose=ivr/acd].calls[].flowId
  → analytics.query.flow.aggregates.execution.metrics.flowId
  → analytics.get.botflow.sessions.flowId
  → flows.get.all.flows.id (name resolution)
  → flows.get.flow.outcomes.id (outcome label resolution)
  → flows.get.flow.milestones.id (milestone label resolution)

analytics.get.single.conversation.analytics.participants[purpose=ivr].sessions[].segments[segmentType=IVR]
  → tFlow (IVR duration per session)
```

### Analytical Questions Answered

- How long did the caller spend in IVR/bot before reaching a queue?
- What intent did the bot capture? Was the intent successfully handled or escalated?
- What data did the IVR collect (account number, authentication) before the agent received the call?
- Which flow outcome was reached? Were there flow failures?
- What is the self-service containment rate across all bot sessions in the period?
- Which milestone in the flow do callers most often abandon?

### Diagnostic Signals

| Signal | Likely Root Cause |
|--------|-------------------|
| `nBotIntentNotHandled` high | Missing intent training data — NLU coverage gap |
| `outcome=Escalated` + `turnCount > 5` | Bot retry threshold too low; caller frustration |
| `nFlowOutcomeFailed` spike | External data action (CRM/DB API) returning errors |
| `tFlow > 120s` for simple queries | IVR menu too deep or data action latency |
| `customattributes` missing expected fields | Data action failure or flow variable not set before transfer |
| `bot-sessions.outcome = Abandoned` + `tFlow < 10s` | Caller dropped in IVR immediately — check DTMF routing or greeting audio |

### Executive Metrics (Self-Service Reporting)

```
selfServiceRate%       = nBotSessions(outcome=Handled) / total nBotSessions
escalationRate%        = nBotSessions(outcome=Escalated) / total nBotSessions
avgBotDuration         = tBotConversationDuration / nBotSessions
intentSuccessRate%     = nBotIntentConfirmed / nBotTurns
ivrPreQueueTime (avg)  = average tFlow per conversation
```

---

## 11. Recording Compliance & Calibration Audit

**Subject:** One `queueId` or `agentUserId` (or organisation-wide) + time window  
**Use case:** A QM manager or compliance officer needs to verify that all required conversations were recorded, that evaluations are being made at the required rate, and that calibration sessions are ensuring evaluator consistency. This is the periodic audit of the QM programme itself.

**Core question:** *Are recordings being captured and evaluations being made consistently and objectively?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.conversation.details.by.queue` | seed → `queueId` | Full conversation list for the scope — the denominator for coverage calculations |
| 2 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording existence, `fileState`, `deleteDate`, policy name — confirms recording was captured |
| 3 | `quality.get.evaluations.query` | `conversationId` | All evaluations in scope — evaluation coverage numerator; `calibrated=true` flags calibration sessions |
| 4 | `quality.get.published.evaluation.forms` | `formId` | Form definitions — decode form names, identify critical questions |
| 5 | `quality.get.calibrations` | `calibrationId` | Calibration sessions: participating evaluators, form, conversation — inter-rater consistency data |
| 6 | `conversations.get.recording.annotations` | `conversationId` + `recordingId` | QM annotations: `PAUSE/RESUME` events indicate redaction; bookmarks indicate reviewed moments |
| 7 | `quality.get.agents.activity` | `userId` | Aggregate QA summary per agent — evaluation count, average score, critical fail count |

### Key Joins

```
analytics.query.conversation.details.by.queue[].conversationId
  → conversations.get.conversation.recording.metadata.conversationId (left join — recording may be absent)
  → quality.get.evaluations.query[].conversationId (left join — not all conversations are evaluated)
  → conversations.get.recording.annotations.conversationId + recordingId (requires recordingId from step 2)

quality.get.evaluations.query[].evaluationForm.id
  → quality.get.published.evaluation.forms.id (form label resolution)

quality.get.calibrations[].conversationId
  → quality.get.evaluations.query[].conversationId (maps calibrations to their associated evaluations)
```

### Derived Metrics

| Metric | Formula |
|--------|---------|
| `recordingCoverage%` | `conversationsWithRecording / totalConversations` |
| `evaluationCoverage%` | `conversationsWithEvaluation / totalConversations` |
| `criticalItemFailRate%` | `evaluationsWithCriticalFail / totalEvaluations` |
| `calibrationFrequency` | `calibrationCount / evaluatorCount / weeks` |
| `evaluatorVariance` | `stddev(score)` across evaluators on same calibration conversation |

### Diagnostic Signals

| Signal | Action |
|--------|--------|
| `recordingCoverage% < 95%` | Recording policy not applied; check edge recording or consent rules |
| `evaluationCoverage% < target` | QM team understaffed or queue filter misconfigured |
| Calibrations absent in window | Evaluators not being calibrated — objectivity risk |
| `criticalItemFailRate% > 5%` | Systemic compliance/CX issue; requires coaching escalation |
| Large score variance in calibration | Evaluator training required |
| `fileState=DELETED` before retention date | Premature deletion — compliance audit required |

---

## 12. Knowledge Base & AI Effectiveness

**Subject:** One `queueId` or `userId` (or organisation-wide) + time window  
**Use case:** A CX technology leader or QM director needs to quantify the impact of AI-assisted tools — knowledge base article suggestions, Copilot AI summaries, and Agent Assist features. Used to justify AI investments, identify adoption gaps, and measure AHT reduction.

**Core question:** *Are agents engaging with AI suggestions, and does that engagement reduce handle time?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.conversation.aggregates.queue.performance` | seed → `queueId` | Baseline AHT (`tHandle/nConnected`) for comparison — before-AI reference point |
| 2 | `analytics.post.knowledge.aggregates.query` | `queueId` | `nKnowledgeSessionSuggested`, `nKnowledgeSessionPresented`, `nKnowledgeSessionEngaged` |
| 3 | `analytics.post.summaries.aggregates.query` | `queueId` | `nSummaryGenerated`, `nSummaryEngaged` — Copilot AI summary adoption |
| 4 | `conversations.get.conversation.suggestions` | `conversationId` | Per-conversation Agent Assist suggestions offered (type: FAQ/Article/Script) |
| 5 | `conversations.get.conversation.suggestion.detail` | `conversationId` + `suggestionId` | Whether each suggestion was engaged — direct agent utilisation measure |
| 6 | `analytics.query.conversation.transcripts` | `queueId` | S&TA coverage and `oSentimentScore` — emotional context of AI-assisted vs. unassisted calls |
| 7 | `speechandtextanalytics.get.topics` | `topicId` | Topic library — decode topic IDs to business labels for sentiment correlation |
| 8 | `analytics.query.user.aggregates.performance.metrics` | `userId` | Per-agent performance — segment AI-enabled vs. non-enabled cohorts to measure AHT delta |

### Key Joins

```
analytics.query.conversation.aggregates.queue.performance[].group.queueId
  → analytics.post.knowledge.aggregates.query[].group.queueId
  → analytics.post.summaries.aggregates.query[].group.queueId
  → analytics.query.user.aggregates.performance.metrics[].group.userId (segment by AI-enabled cohort)

conversations.get.conversation.suggestions[].suggestions[].id
  → conversations.get.conversation.suggestion.detail[].suggestionId
```

### Derived Metrics

| Metric | Formula |
|--------|---------|
| `knowledgeEngagementRate%` | `nKnowledgeSessionEngaged / nKnowledgeSessionPresented` |
| `knowledgePresentRate%` | `nKnowledgeSessionPresented / nKnowledgeSessionSuggested` |
| `aiSummaryAdoptionRate%` | `nSummaryEngaged / nSummaryGenerated` |
| `aiEnabledAhtDelta` | `avgHandleTime(AI-enabled) - avgHandleTime(baseline)` |
| `suggestionUtilisationRate%` | `engagedSuggestions / totalSuggestionsOffered` |

### Analytical Questions Answered

- What percentage of suggested knowledge articles are agents actually reading?
- Are agents engaging with Copilot AI summaries? Which queues have the lowest adoption?
- Does knowledge engagement correlate with lower AHT or ACW?
- Which topic categories most often trigger AI suggestions?
- Is there a sentiment difference between AI-assisted and non-assisted calls?

---

## 13. WFM Adherence Investigation

**Subject:** One `managementUnitId` or set of `userId`s + time window  
**Use case:** A workforce manager or operations director needs to understand schedule adherence patterns — which agents are consistently off-schedule, whether adherence impacts queue performance, and whether coaching is being targeted at the right agents.

**Core question:** *Which agents are not adhering to their schedules, and what is the operational impact?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.management.units` | seed | All WFM management units with agent counts |
| 2 | `workforce.get.management.unit.users` | `managementUnitId` | Agents assigned to each WFM team with work plan IDs |
| 3 | `workforce.get.management.unit.adherence` | `managementUnitId` | Real-time adherence: scheduled vs. actual state, variance minutes, impact |
| 4 | `workforce.get.adherence.bulk` | `userId` list | Bulk adherence for a specific agent cohort — `adherenceState`, `adherencePct`, `impactSeconds` |
| 5 | `workforce.get.agent.management.unit` | `userId` | An individual agent's WFM unit — gateway to their schedule and adherence data |
| 6 | `analytics.query.user.aggregates.login.activity` | `userId` | Actual presence/routing-status segments: `tAgentRoutingStatus`, `tSystemPresence` — actual vs. scheduled |
| 7 | `analytics.query.user.aggregates.performance.metrics` | `userId` | `nConnected`, `tHandle` — compute occupancy from actual productive time |
| 8 | `coaching.get.appointments` | `userId` | Coaching sessions — correlate low adherence with coaching activity |

### Key Joins

```
workforce.get.management.units[].id
  → workforce.get.management.unit.users.managementUnitId (agent roster per unit)
  → workforce.get.management.unit.adherence.managementUnitId (real-time adherence state)

workforce.get.management.unit.users[].user.id
  → workforce.get.adherence.bulk.userId (bulk adherence data)
  → analytics.query.user.aggregates.login.activity[].group.userId (actual time-in-state)
  → analytics.query.user.aggregates.performance.metrics[].group.userId (productivity)
  → coaching.get.appointments[].attendees[].id (coaching overlay)
```

### Derived Metrics

| Metric | Formula |
|--------|---------|
| `adherencePct%` | From `workforce.get.adherence.bulk.adherencePct` |
| `onQueueTime%` | `tAgentRoutingStatus(INTERACTING+IDLE) / totalLoggedInTime` |
| `occupancy%` | `tHandle / tOnQueue` |
| `avgIdleTime` | `tAgentRoutingStatus(IDLE) / nConnected` |
| `notRespondingEpisodes` | Count of `NOT_RESPONDING` segments in window |

### Divisions as the WFM Group Lens

WFM management units and divisions can span the same agent population from different angles:
- **Division** → organisational/reporting structure (who the agent reports to)
- **Management Unit** → WFM scheduling structure (what schedule they follow)
- An agent may belong to one division but a different management unit. Use `workforce.get.agent.management.unit` to resolve the WFM unit for agents found via division queries.

---

## 14. Trunk & Edge Infrastructure Health

**Subject:** Organisation-wide (or specific trunk/edge) — point-in-time or over a window  
**Use case:** A voice engineer or NOC team needs a complete picture of the SIP infrastructure — edge appliance status, trunk utilisation, active call load, and station registrations. Used for proactive monitoring and incident response when call quality or connectivity issues are reported.

**Core question:** *Is the SIP infrastructure healthy, and where is the capacity or registration problem?*

### Dataset Steps (ordered)

| Step | Dataset Key | What It Shows |
|------|-------------|---------------|
| 1 | `telephony.get.edges` | Edge appliance status: `statusCode`, `onlineStatus`, software version, assigned trunks |
| 2 | `telephony.get.trunks` | SIP trunk inventory: `inService`, `edgeId`, `maxConcurrentCalls`, trunk type |
| 3 | `telephony.get.trunk.metrics.summary` | Live trunk counters: `currentCalls`, `totalErrorCount`, `callsWithError` |
| 4 | `telephony.get.edge.performance.metrics` | Edge CPU/memory/active call count — spot resource pressure during incidents |
| 5 | `stations.get.stations` | Softphone/desk phone registrations: `registered`, `userId`, `status` |
| 6 | `conversations.get.active.calls` | Live voice conversations — cross-reference against trunk utilisation |
| 7 | `alerting.get.alerts` | Active telephony alerts: threshold breaches on trunk capacity or error rates |
| 8 | `alerting.get.rules` | Alert rule configurations — confirm thresholds are set appropriately |

### Diagnostic Decision Tree

```
Edge statusCode != ACTIVE
  → Failover condition; check edge firmware version and management network path

Trunk inService=false
  → Provider circuit down or PSTN gateway misconfiguration; check carrier status

trunk.currentCalls / trunk.maxConcurrentCalls > 0.85
  → Capacity saturation; add trunk channels or reroute overflow to alternate trunk

stations.registered=false spike (multiple agents)
  → Network/DNS issue affecting WebRTC registration; check STUN/TURN configuration

Edge cpuUsage > 80%
  → Media processing overload; consider call load redistribution across edges

SIP trace (telephony.get.sip.message.for.conversation)
  → Pull for any specific failing conversationId to correlate trunk errors with exact calls
```

### Joins to Conversation Forensics

```
telephony.get.edges[].id
  → telephony.get.trunks[].edge.id (trunks on each edge)
  → telephony.get.trunk.metrics.summary[].trunkId

stations.get.stations[].associatedUser.id
  → analytics.query.user.observations.real.time.status (agent routing status at station)

telephony.get.sip.message.for.conversation.conversationId
  → analytics.get.single.conversation.analytics.conversationId (correlate SIP errors to timing)
```

---

## 15. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

**Column abbreviations:** Conv=Conversation Deep Dive, Queue=Queue Investigation, Div=Division Investigation, Exec=Executive Rollup, RT=Real-Time Monitoring, Agent=Agent Investigation, Bot=Bot/IVR Pre-Queue, Rec=Recording Compliance, AI=Knowledge/AI Effectiveness, WFM=WFM Adherence, Infra=Trunk/Edge Health

| Dataset Key | Conv | Queue | Div | Exec | RT | Agent | Bot | Rec | AI | WFM | Infra |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Conversation Core** | | | | | | | | | | | |
| `conversations.get.specific.conversation.details` | ● | | | | | | ● | | | | |
| `conversations.get.call.detail` | ● | | | | | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ● | | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | ● | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | ● | | | | |
| `conversations.get.conversation.summaries` | ● | | | | | | | | | | |
| `conversations.get.active.calls` | | | | | ● | | | | | | ● |
| `conversations.get.recording.annotations` | | | | | | | | ● | | | |
| **Analytics — Conversation** | | | | | | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | ● | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | | | | | |
| `analytics.query.conversation.details.by.queue` | | ● | | | | | | ● | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | ● | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | |
| `analytics.query.conversation.transcripts` | | | | ● | | | | | ● | | |
| **Analytics — Queue/Service Level** | | | | | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | |
| **Analytics — User/Agent** | | | | | | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | ● | |
| `analytics.query.user.aggregates.performance.metrics` | | | | ● | | ● | | | ● | ● | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | |
| `analytics.post.users.details.jobs` | | | ● | | | ○ | | | | | |
| **Analytics — Flow & Bot** | | | | | | | | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | ● | | | ● | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | |
| `analytics.post.bots.aggregates.query` | | | | ● | | | ● | | | | |
| `analytics.get.botflow.sessions` | | | | | | | ● | | | | |
| **Analytics — AI & Knowledge** | | | | | | | | | | | |
| `analytics.post.knowledge.aggregates.query` | | | | | | | | | ● | | |
| `analytics.post.summaries.aggregates.query` | | | | | | | | | ● | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | ● | | |
| **Recording & Quality** | | | | | | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | ● | | | |
| `conversations.get.recordings` | ● | | | | | | | ● | | | |
| `quality.get.evaluations.query` | ● | ○ | | ● | | ○ | | ● | | | |
| `quality.get.surveys` | ● | | | ● | | | | | | | |
| `quality.get.conversation.surveys` | ● | | | | | | | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | ● | | | |
| `quality.get.published.evaluation.forms` | | | | | | | | ● | | | |
| `quality.get.calibrations` | | | | | | | | ● | | | |
| **Speech & Text Analytics** | | | | | | | | | | | |
| `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | ● | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ● | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ● | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | |
| `speechandtextanalytics.get.topics` | | | | ● | | | | | ● | | |
| **Routing** | | | | | | | | | | | |
| `routing-queues` | | ● | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | | |
| `routing.get.queue.members.with.status` | | ● | | | | | | | | | ● |
| `routing.get.queue.wrapup.codes` | | ● | | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | | | | | | |
| `routing.get.all.wrapup.codes` | | | | ● | | | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | |
| `routing.get.skill.groups` | | | | | | | | | | | |
| **Users & Presence** | | | | | | | | | | | |
| `users` | | | | | | | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | ● | | | | | | | |
| **Coaching** | | | | | | | | | | | |
| `coaching.get.appointments` | | | ● | ● | | ○ | | | | ● | |
| **Authorization & Divisions** | | | | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | |
| `authorization.get.all.divisions` | | | | | | | | | | | |
| `authorization.search.division.objects` | | | ● | | | | | | | | |
| `authorization.get.division.grants` | | | ● | | | | | | | | |
| **Flows & IVR** | | | | | | | | | | | |
| `flows.get.all.flows` | | | | | | | ● | | | | |
| `flows.get.flow.outcomes` | | | | ● | | | ● | | | | |
| `flows.get.flow.milestones` | | | | ● | | | ● | | | | |
| **Telephony** | | | | | | | | | | | |
| `telephony.get.sip.message.for.conversation` | ● | | | | | | | | | | |
| `telephony.get.edges` | | | | | | | | | | | ● |
| `telephony.get.trunks` | | | | | | | | | | | ● |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | | ● |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | | ● |
| **Stations** | | | | | | | | | | | |
| `stations.get.stations` | | | | | | | | | | | ● |
| **Alerting** | | | | | | | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | | ● |
| `alerting.get.rules` | | | | | | | | | | | ● |
| **Workforce Management** | | | | | | | | | | | |
| `workforce.get.management.units` | | | | | | | | | | ● | |
| `workforce.get.management.units` | | | | | | | | | | ● | |
| `workforce.get.management.unit.users` | | | | | | | | | | ● | |
| `workforce.get.management.unit.adherence` | | | | | | | | | | ● | |
| `workforce.get.adherence.bulk` | | | ● | ● | | ● | | | | ● | |
| `workforce.get.agent.management.unit` | | | | | | ● | | | | ● | |
| **Audit** | | | | | | | | | | | |
| `audit-logs` | | | | | | ● | | | | | |

---

## Appendix: Metric Glossary

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| **Volume** | | |
| `nOffered` | Conversations offered to the queue | Volume denominator |
| `nConnected` | Conversations connected to an agent | Handled volume |
| `nAbandoned` | Conversations abandoned before connection | Abandon count |
| `nTransferred` | Conversations transferred | Transfer volume |
| `nBlindTransferred` | Blind transfers (no consult) | Routing compliance indicator |
| `nConsultTransferred` | Consult transfers (warm handoff) | Quality routing measure |
| **Timing** | | |
| `tHandle` | Total handle time (talk + hold + ACW) | AHT numerator |
| `tTalk` | Total talk time | Talk-time component |
| `tAcw` | After-call work time | ACW component |
| `tAnswered` | Time from offered to answered | Speed of answer |
| `tAbandon` | Time in queue before abandonment | Abandon patience measure |
| `tFlow` | Time spent in IVR/Architect flow | Pre-queue IVR duration |
| `tAcd` | Time waiting in ACD queue after IVR | Pure queue wait time |
| `tHeld` | Total time on hold during interaction | Hold experience measure |
| **Service Level** | | |
| `oServiceLevel` | Current SLA percentage | Real-time SLA |
| `nOverSla` | Conversations that exceeded SLA threshold | SLA misses |
| `oServiceTarget` | Configured SLA target % | SLA comparison reference |
| **Real-Time Observations** | | |
| `oInteracting` | Agents currently on interactions | Active agents |
| `oWaiting` | Interactions waiting in queue | Queue depth |
| `oAlerting` | Interactions currently alerting agents | Ringing/auto-answer state |
| `oLongestWaiting` | Seconds the longest-waiting customer has been waiting | Worst-case wait |
| `oOnQueueUsers` | Agents currently on queue | Staffed capacity |
| `oOffQueueUsers` | Agents logged in but off queue | Available-but-idle population |
| **Agent State** | | |
| `tAgentRoutingStatus` | Time in each routing status | On-queue vs off-queue time |
| `tSystemPresence` | Time in each system presence | Available, Busy, Away, Offline |
| `adherencePct` | Schedule adherence percentage | WFM compliance |
| `impactSeconds` | Variance seconds between scheduled and actual state | WFM impact quantification |
| **Speech & Text Analytics** | | |
| `oSentimentScore` | Aggregate sentiment score (−100 to +100) | Voice-of-customer indicator |
| `nSpeechTextAnalyzedConversations` | Conversations with STA analysis | STA coverage |
| `nCustomerSentimentPositive` | Conversations with positive customer sentiment | CX health |
| `nCustomerSentimentNegative` | Conversations with negative customer sentiment | CX risk signal |
| `silencePercent` | Percentage of call in silence | Hold/dead-air detection |
| `overtalkCount` | Agent/customer simultaneous speech events | Agent listening quality |
| **Bot & IVR** | | |
| `nBotSessions` | Total bot interaction sessions | Bot volume |
| `nBotTurns` | Total conversational turns in bot sessions | Bot engagement depth |
| `nBotIntentConfirmed` | Intents successfully identified | NLU accuracy |
| `nBotIntentNotHandled` | Intents the bot could not handle | NLU coverage gap |
| `tBotConversationDuration` | Total bot session duration | Bot efficiency |
| `nFlowOutcome` | Architect flow outcomes reached | Self-service vs. escalation |
| `nFlowOutcomeFailed` | Flow outcomes classified as failed | IVR health indicator |
| `nFlowMilestone` | Flow milestone events triggered | Caller journey progress |
| **Knowledge & AI** | | |
| `nKnowledgeSessionSuggested` | Knowledge articles suggested to agents | AI suggestion volume |
| `nKnowledgeSessionPresented` | Articles surfaced in the agent UI | Agent visibility |
| `nKnowledgeSessionEngaged` | Articles actually opened by agents | Agent adoption |
| `nSummaryGenerated` | Copilot AI summaries generated | AI summary availability |
| `nSummaryEngaged` | AI summaries opened/used by agents | Summary adoption |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*  
*Structured investigation recipes (with step definitions and join sequences) are in `catalog/genesys.catalog.json` under `combinations.investigationRecipes`, `combinations.executiveReportingPlaybooks`, and `combinations.voiceEngineerPlaybooks`.*
