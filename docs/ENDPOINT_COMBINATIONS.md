# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-31  
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
7. [Agent Investigation Extensions](#7-agent-investigation-extensions)
8. [Conversation Investigation Extensions](#8-conversation-investigation-extensions)
9. [Queue Investigation Extensions](#9-queue-investigation-extensions)
10. [Bot & IVR Containment Analysis](#10-bot--ivr-containment-analysis)
11. [AI Assist & Copilot Adoption](#11-ai-assist--copilot-adoption)
12. [Quality Management Rollup](#12-quality-management-rollup)
13. [Voice Engineer Acute Triage](#13-voice-engineer-acute-triage)
14. [Team Supervisor Dashboard](#14-team-supervisor-dashboard)
15. [Comprehensive Executive KPI Rollup](#15-comprehensive-executive-kpi-rollup)
16. [Dataset Combination Reference Matrix](#16-dataset-combination-reference-matrix)

---

## 1. Single Conversation Deep Dive (Voice Engineer)

**Subject:** One `conversationId`  
**Use case:** A voice engineer or QM analyst receives a complaint about a specific call — wrong queue, long hold, audio quality, dropped call, incorrect routing. They need the complete picture of one conversation: where it came from, how it routed, how long each phase took, what the SIP signaling said, whether a recording exists, and what the quality score was.

**Core question:** *What actually happened in this conversation, end-to-end?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.get.single.conversation.analytics` | seed → `conversationId` | Per-segment timing: IVR duration, ACD wait, talk time, hold time, ACW, conference, recording start/stop |
| 2 | `conversations.get.specific.conversation.details` | `conversationId` | Media type, state, originatingDirection, full participant roster, ANI/DNIS, externalTag (BYOI indicator) |
| 3 | `conversations.get.conversation.participant.wrapup` | `conversationId` + `participantId` | Wrapup code per agent participant — iterate over agent participants from step 2 |
| 4 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs, media type, duration, deletion schedule |
| 5 | `conversations.get.recordings` | `conversationId` | Actual recording objects with signed download URLs |
| 6 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by IVR/Architect flows (account numbers, intent, escalation flags) |
| 7 | `conversations.search.participant.attributes` | `conversationId` | Participant-level attributes (IVR variables, data action outcomes, flow-set values) |
| 8 | `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | `conversationId` | Top-level S&TA: agentSentimentScore, customerSentimentScore, overtalkCount, silencePercent |
| 9 *(STA enabled)* | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic and category classifications — call reason, escalation triggers, compliance topics |
| 10 *(STA enabled)* | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | AI-generated summary per communication leg — rapid content review without listening |
| 11 | `conversations.get.conversation.summaries` | `conversationId` | Copilot/Agent Assist summaries — reasonForContact, resolution notes |
| 12 | `quality.get.evaluations.query` | `conversationId` | QM evaluation scores, form used, evaluator, calibration status |
| 13 | `quality.get.conversation.surveys` | `conversationId` | Post-call CSAT/NPS survey result |
| 14 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace: INVITE, 200 OK, BYE, re-INVITE, codec negotiation |
| 15 *(transcription)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId` + `communicationId` | Transcript download URL per communication leg |

### Key Joins

```
analytics.get.single.conversation.analytics.conversationId
  → conversations.get.specific.conversation.details.conversationId (participant overlay)
  → conversations.get.conversation.recording.metadata.conversationId
  → telephony.get.sip.messages.for.conversation.conversationId (voice only)
  → quality.get.evaluations.query[].conversationId (left join — evaluations may not exist)
  → quality.get.conversation.surveys[].conversationId (left join — surveys may not exist)

conversations.get.specific.conversation.details.participants[].id
  → conversations.get.conversation.participant.wrapup.participantId (iterate agent participants)

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
- What topics and sentiment did S&TA detect?
- What did the AI summary say was the reason for contact and was it resolved?

### Voice Engineer Notes

Step 14 (SIP trace) is the definitive source for:
- Call setup failures (no 200 OK, 486 Busy, 503 Service Unavailable)
- One-way audio (media IP mismatch in SDP)
- Premature disconnection (BYE before expected, no 200 OK to BYE)
- Codec negotiation failures
- Hold/transfer events (re-INVITE sequences)

The `telephony.get.edge.performance.metrics` dataset should be pulled for the Edge appliance
that handled the call if CPU, memory, or error counters suggest resource pressure.

### BYOI Indicator

If `conversations.get.specific.conversation.details` returns a non-null `externalTag` or
`externalConversationId`, the call was injected via the BYOI integration. Custom attributes
in step 6 will contain the provider's context (CRM case ID, external call ID). The SIP trace
(step 14) reflects the provider's SIP-to-SIP handoff, not an inbound PSTN leg.

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
| 1 | `routing-queues` | seed → `queueId` | Queue name, routing method, SLA targets, media types, skill evaluation mode |
| 2 | `routing.get.queue.wrapup.codes` | `queueId` | Human-readable wrapup code labels for the queue |
| 3 | `routing.get.queue.members.with.status` | `queueId` | Current membership roster with routing status and presence |
| 4 | `analytics.query.queue.observations.real.time.stats` | `queueId` | Live queue counters: oInteracting, oWaiting, oOnQueueUsers, oAlerting |
| 5 | `routing.get.queue.estimated.wait.time` | `queueId` | Real-time EWT by media type — compare to SLA target |
| 6 | `analytics.query.conversation.details.by.queue` | `queueId` | Every conversation that touched this queue in the window, with participant/segment detail |
| 7 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Aggregate: nConnected, tHandle, tTalk, tAcw, tAnswered, nOffered |
| 8 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon count: nAbandoned, tAbandon, tShortAbandon |
| 9 | `analytics.query.queue.aggregates.service.level` | `queueId` | SLA achievement: nAnsweredIn20/30/60, oServiceLevel, oServiceTarget, nOverSla |
| 10 | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer analysis: nTransferred, nBlindTransferred, nConsultTransferred |
| 11 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` + wrapUpCode | Wrapup code frequencies (join step 2 for labels) |
| 12 | `quality.get.evaluations.query` (queueId filter) | `conversationId` | QM evaluation coverage and scores for conversations in this queue |

### Key Joins

```
routing-queues.id
  → routing.get.queue.members.with.status.queueId (member roster)
  → analytics.query.conversation.aggregates.*.queueId (all aggregate steps)
  → routing.get.queue.estimated.wait.time.queueId (EWT)

analytics.query.conversation.details.by.queue[].conversationId
  → quality.get.evaluations.query[].conversationId (left join — not all conversations are evaluated)

analytics.query.conversation.aggregates.wrapup.distribution[].group.wrapUpCode
  → routing.get.queue.wrapup.codes[].id (label resolution)
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
1. Use `authorization.search.division.objects` (objectType=QUEUE) to get all queue IDs in the division.
2. Fan out the steps above once per queue, or filter analytics queries with `divisionId` predicates.

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
| 1 | `authorization.get.all.divisions` | seed → `divisionId` | Division name, description, home-division flag |
| 2 | `authorization.search.division.objects` (objectType=QUEUE) | `divisionId` | All queue IDs assigned to this division |
| 3 | `authorization.get.division.grants` | `divisionId` | Access control grants — who has permissions in this division |
| 4 | `users.division.analysis.get.users.with.division.info` | `divisionId` | All agents assigned to the division with user IDs |
| 5 | `analytics.query.conversation.aggregates.agent.performance` (divisionId filter) | `userId` | Per-agent: nConnected, tHandle, tTalk, tAcw, tAnswered |
| 6 | `analytics.query.user.aggregates.login.activity` (divisionId filter) | `userId` | Per-agent time-in-state: tAgentRoutingStatus, tSystemPresence, tOrganizationPresence |
| 7 | `analytics.query.user.details.activity.report` (userId list) | `userId` | Login/logout/on-queue presence event timeline per agent |
| 8 | `analytics.query.evaluation.aggregates` (userId list) | `userId` | QM evaluation counts and average score per agent — faster than iterating individual evaluations |
| 9 | `quality.get.agents.activity` | `userId` | QM evaluation counts, highest/average/lowest scores per agent |
| 10 | `coaching.get.appointments` | `userId` | Coaching sessions scheduled/completed for agents in the window |
| 11 | `analytics.query.conversation.aggregates.wrapup.distribution` (divisionId filter) | `queueId` | Wrapup code distribution across all queues in the division |

### Key Joins

```
authorization.get.all.divisions.id
  → authorization.search.division.objects.divisionId (queue enumeration)
  → authorization.get.division.grants.divisionId (access control)
  → users.division.analysis.get.users.with.division.info.divisionId (agent enumeration)

users.division.analysis.get.users.with.division.info[].id
  → analytics.query.conversation.aggregates.agent.performance[].userId
  → analytics.query.user.aggregates.login.activity[].userId
  → analytics.query.evaluation.aggregates[].userId
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
- Who has permissions in this division and at what role level?

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

#### Layer 3 — Automation & AI
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.bot.aggregates` | `botId`, daily | botContainmentRate%, nBotHandled, nBotTransferred |
| `analytics.query.agent.copilot.aggregates` | `queueId`, daily | copilotAdoptionRate%, nCopilotSuggestionsAccepted |
| `analytics.query.resolution.aggregates` | `queueId`, daily | firstContactResolutionRate%, nResolutions |

#### Layer 4 — Workforce
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.user.aggregates.login.activity` | `userId`, daily | tAgentRoutingStatus: available, busy, on-queue time per agent |
| `analytics.query.conversation.aggregates.agent.performance` | `userId`, daily | nConnected, tHandle (avg) per agent — productivity comparison |

#### Layer 5 — Quality & Voice-of-Customer
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.evaluation.aggregates` | `queueId`, monthly | avgEvaluationScore, evaluationCoverage%, nCriticalItemFailed |
| `analytics.query.survey.aggregates` | `queueId`, monthly | avgSurveyScore (CSAT/NPS), surveyResponseRate |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | Speech analytics coverage: nSpeechTextAnalyzedConversations, oSentimentScore |

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
  - Total handled:              SUM(nConnected) across all queues
  - Abandon rate:               SUM(nAbandoned) / SUM(nOffered) × 100
  - Average handle time:        WAVG(tHandle, nConnected)
  - SLA achievement:            queues meeting target / total queues × 100
  - Transfer rate:              SUM(nTransferred) / SUM(nConnected) × 100
  - Bot containment rate:       SUM(nBotHandled) / SUM(nBotInteractions) × 100
  - Copilot adoption rate:      SUM(nCopilotSuggestionsAccepted) / SUM(generated) × 100
  - FCR rate:                   SUM(nResolutions) / SUM(nConnected) × 100
  - QM coverage:                SUM(nEvaluations) / SUM(nConnected) × 100
  - Average QM score:           WAVG(avgEvaluationScore, nEvaluations)
  - Avg CSAT:                   WAVG(avgSurveyScore, nSurveysCompleted)
  - S&TA coverage:              SUM(nSpeechTextAnalyzed) / SUM(nConnected) × 100
  - Sentiment index:            AVG(oSentimentScore) across all STA-analysed conversations

Trend views (daily granularity):
  - Volume by day with channel mix
  - AHT trend by queue
  - Abandon rate trend by queue
  - SLA achievement heatmap by queue × day
  - Bot containment trend by bot flow
  - Copilot adoption by queue
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
| 3 | `analytics.query.conversations.activity` | All queues | Rich real-time view: routing context, media type, agent assignment per active conversation |
| 4 | `routing.get.queue.estimated.wait.time` | Specific queues | EWT by media type — caller wait forecast; action trigger |
| 5 | `analytics.query.agents.status.counts` | Org-wide | Fast count: how many agents in each presence/routing status right now |
| 6 | `analytics.query.user.observations.real.time.status` | All agents | oUserPresence (system presence), oUserRoutingStatus per agent |
| 7 | `analytics.query.agents.status.query` | Filtered agents | Detailed per-agent status with timestamps for supervisor's team |
| 8 | `analytics.get.agent.active.status` | One agent | Full real-time channel assignment for a specific agent — active conversation IDs |
| 9 | `users.get.agent.active.conversations` | One agent | All in-progress conversations for a specific agent |
| 10 | `users.get.agent.current.routing.status` | One agent | Current routing state (IDLE / INTERACTING / NOT_RESPONDING / OFF_QUEUE) |
| 11 | `analytics.query.flow.observations` | All flows | oFlow: active Architect flows currently executing |
| 12 *(telephony NOC)* | `telephony.get.trunk.metrics.summary` | — | Trunk utilisation and error counters |
| 13 *(telephony NOC)* | `telephony.get.edge.performance.metrics` | One Edge | CPU, memory, active call count on specific Edge |

### Polling Note

Real-time datasets do not accept `interval` parameters — they reflect current state as of the
API call. Poll at the rate appropriate for the display (typically 10–30 seconds for a wall board).

Steps 5 (`analytics.query.agents.status.counts`) is the fastest org-wide status check — a single
call returns a status-bucketed count without iterating agents. Use it for the wall board header;
use step 6 or 7 for the per-agent table below.

---

## 6. BYOI External Conversation Enrichment

**Subject:** One `conversationId` that was injected via BYOI  
**Use case:** A conversation originated in an external system (CRM telephony, third-party contact
centre, a custom SIP provider) and was injected into Genesys Cloud via the BYOI provider API
(`POST /api/v2/conversations/providers/{providerId}/calls`). The conversation appears in Genesys
analytics and recordings, but context lives in the external system.

**Core question:** *Where did this conversation come from, and what external context does it carry?*

### How to Identify a BYOI Conversation

In step 1 of the Conversation Investigation, `conversations.get.specific.conversation.details` returns:

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
| + | `conversations.get.conversation.summaries` | Copilot summary if agent used AI assist during the injected conversation |

### BYOI Conversation in Analytics

BYOI conversations flow through the same Architect flows, queue routing, and analytics pipeline
as native Genesys conversations. All standard datasets apply identically:
- `analytics.get.single.conversation.analytics` — segment timing is accurate
- `conversations.get.conversation.recording.metadata` — recordings exist if enabled
- `quality.get.conversation.surveys` — surveys proceed normally
- `telephony.get.sip.messages.for.conversation` — reflects the BYOI SIP-to-SIP handoff

### Embeddable Framework Conversations

Conversations visible to agents via the Embeddable Framework return the same object shape as
`conversations.get.specific.conversation.details`. The condensed view includes:
`participants[].purpose`, `participants[].state`, `participants[].calls[].state`,
`participants[].calls[].muted`, `participants[].calls[].held`. These fields are present in the
full object returned by the dataset and need no special handling.

---

## 7. Agent Investigation Extensions

The existing Agent Investigation (`Get-GenesysAgentInvestigation`) covers 16 steps including
identity, division, skills, queue memberships, utilization, presence activity, performance, conversations,
audit changes, real-time status, evaluations, QA summary, WFM management unit, adherence, and coaching.

These additional datasets enrich the investigation without replacing any existing step.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| evaluationAggregates | `analytics.query.evaluation.aggregates` | `userId` | QM aggregate counts and avg score — faster than iterating individual evaluations for summary line |
| copilotActivity | `analytics.query.agent.copilot.aggregates` | `userId` | Copilot suggestion acceptance rate — AI assist engagement for this agent |
| aiSummaryView | `analytics.query.ai.summary.aggregates` | `userId` | AI summary view rate — did the agent read Copilot summaries in ACW? |
| divisionGrants | `authorization.get.division.grants` | `divisionId` | Roles and grants in the agent's division — security context |

---

## 8. Conversation Investigation Extensions

The existing Conversation Investigation covers 14 steps. These additional datasets complete the picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| participantWrapup | `conversations.get.conversation.participant.wrapup` | `conversationId` + `participantId` | Per-participant wrapup code — iterate agent participants |
| staOverview | `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | `conversationId` | Top-level S&TA: sentiment, overtalk, silence — gate-check before STA detail steps |
| staCategories | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic classifications — call reason, escalation, compliance phrases |
| staSummaries | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | S&TA AI summary per communication leg |
| copilotSummary | `conversations.get.conversation.summaries` | `conversationId` | Agent Copilot reason-for-contact and resolution summary |
| specificSurvey | `quality.get.conversation.surveys` | `conversationId` | Conversation-specific survey result (more targeted than org-wide quality.get.surveys) |

**Conditional steps:** `staCategories`, `staSummaries` run only when `staOverview.analysisStatus = "Success"`.

---

## 9. Queue Investigation Extensions

The existing Queue Investigation covers 13 steps. These additions complete the picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| estimatedWaitTime | `routing.get.queue.estimated.wait.time` | `queueId` | Real-time EWT by media type — compare to SLA target for immediate action |
| evaluationAggregates | `analytics.query.evaluation.aggregates` | `queueId` | QM aggregate score and coverage% — faster than iterating evaluations for rollup |
| surveyAggregates | `analytics.query.survey.aggregates` | `queueId` | CSAT/NPS aggregate for the queue in the window |
| resolutionRate | `analytics.query.resolution.aggregates` | `queueId` | FCR alongside QM scores for quality triangle |
| divisionObjects | `authorization.search.division.objects` | `divisionId` | Verify queue's division assignment — confirms scope boundary |

---

## 10. Bot & IVR Containment Analysis

**Subject:** One `botFlowId` + time window  
**Use case:** A CX architect or digital channel manager needs to understand how much of the bot/IVR
traffic is self-served versus escalated to an agent — where in the dialogue customers fail, which
intents drive transfers, and whether IVR instability is causing incorrect escalations.

**Core question:** *Is the bot actually containing calls, and where does it break down?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.bot.aggregates` | seed → `botId` | nBotInteractions, nBotHandled (contained), nBotTransferred (escalated), tBotSessionDuration |
| 2 | `analytics.get.botflow.sessions` | `botFlowId` | Individual session outcomes: exitReason (COMPLETED/TRANSFERRED/ERROR/ABANDONED), conversationId |
| 3 | `analytics.get.botflow.reporting.turns` | `botFlowId` | Turn-by-turn: intentName, confidence, userInput, exitReason per turn |
| 4 | `analytics.query.flow.execution.aggregates` | `flowId` (inbound Architect flow) | nFlowExecutions, nFlowErrors, nFlowDisconnects — IVR instability check |
| 5 | `analytics-conversation-details-query` | `conversationId` (from TRANSFERRED sessions) | tTalk, tHandle, queueId, wrapUpCode for escalated conversations |

### Key Joins

```
analytics.query.bot.aggregates.botId
  → analytics.get.botflow.sessions.botFlowId (per-session detail)

analytics.get.botflow.sessions[exitReason=TRANSFERRED].conversationId
  → analytics-conversation-details-query.conversationId (enrichment of escalated calls)

analytics.get.botflow.reporting.turns.intentName
  → (aggregate by intent to find top failure intents)
```

### Analytical Questions Answered

- What is the containment rate? (nBotHandled / nBotInteractions)
- Which specific intents or dialogue points cause customers to transfer?
- Are there bot errors (not just transfers) — flow timeouts, data action failures?
- What happens to transferred calls — which queue absorbs them, how long do they take?
- Is the inbound Architect flow that launches the bot stable, or is it failing?

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| containmentRate < 30% | Bot not resolving most requests — review top-failing intents in bot-turns |
| nBotTransferred spikes for specific intent | Missing utterance training or broken data action |
| nFlowErrors spike | Architect flow failure — data action timeout or flow logic error |
| tBotSessionDuration increasing | Customers looping through intents — disambiguation failure |
| ABANDONED exit reason spike | IVR menu too long or customer frustration — UX redesign needed |

---

## 11. AI Assist & Copilot Adoption

**Subject:** All queues in a division + time window  
**Use case:** A CX director or technology lead needs to measure how much agents are using AI-generated
suggestions, whether high adoption correlates with better outcomes (lower AHT, higher QM scores),
and which queues or teams are lagging in adoption.

**Core question:** *Are agents using AI assist, and is it improving results?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.agent.copilot.aggregates` | seed → `queueId` | nCopilotSuggestionsGenerated, nCopilotSuggestionsAccepted, adoptionRate |
| 2 | `analytics.query.ai.summary.aggregates` | `queueId` | nSummariesGenerated, nSummariesViewed, aiSummaryCoverage% |
| 3 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | tHandle, tAcw baseline — compare high vs. low adoption queues |
| 4 | `analytics.query.evaluation.aggregates` | `queueId` | avgEvaluationScore — QM quality correlation with AI adoption |
| 5 | `analytics.query.resolution.aggregates` | `queueId` | resolutionRate — FCR correlation with AI adoption |
| 6 | `conversations.get.conversation.summaries` (sample) | `conversationId` | Qualitative sample — check summary accuracy and usefulness |

### Key Joins

```
analytics.query.agent.copilot.aggregates.queueId
  → analytics.query.ai.summary.aggregates.queueId (AI coverage overlay)
  → analytics.query.conversation.aggregates.queue.performance.queueId (AHT baseline)
  → analytics.query.evaluation.aggregates.queueId (QM correlation)
  → analytics.query.resolution.aggregates.queueId (FCR correlation)
```

### Analytical Questions Answered

- Which queues have the highest/lowest Copilot adoption rates?
- Does high adoption correlate with lower AHT or higher QM scores?
- Are agents viewing AI summaries, or ignoring them?
- Which queues have Copilot configured but zero suggestions generated? (licensing/config gap)

---

## 12. Quality Management Rollup

**Subject:** QM programme across multiple queues + reporting window  
**Use case:** A QM manager or CX director needs a monthly QM programme health report — evaluation
coverage, score distribution, critical item failures, survey response rates, and CSAT trends.

**Core question:** *Is the QM programme covering the right conversations and driving score improvement?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.query.evaluation.aggregates` | seed → `queueId` | nEvaluations, avgEvaluationScore, nCriticalItemFailed, evaluationCoverage% |
| 2 | `analytics.query.survey.aggregates` | `queueId` | nSurveysSent, nSurveysCompleted, avgSurveyScore, surveyResponseRate |
| 3 | `analytics.query.resolution.aggregates` | `queueId` | resolutionRate — triangle: QM score + CSAT + FCR should move together |
| 4 | `quality.get.agents.activity` | `userId` | Per-agent: evalCount, avgScore, highScore, lowScore — identify zero-coverage agents |
| 5 | `quality.get.published.evaluation.forms` | `formId` | Form definitions — interpret scores and critical item context |
| 6 | `quality.get.evaluations.query` (critical failures only) | `conversationId` | Drill-down sample of critical failures — feeds calibration and coaching triggers |

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| evaluationCoverage < 5% | QM under-resourced or automated evaluation not enabled |
| avgQmScore high but CSAT low | Evaluation form not reflecting real customer experience |
| nCriticalItemFailed spike | Compliance or escalation risk — immediate management review |
| surveyResponseRate < 5% | Survey delivery misconfigured or wrong channel |
| resolutionRate diverges from QM score | Agents closing interactions without resolving — coaching needed |

### Executive Metrics Surfaced

`evaluationCoverage%`, `avgEvaluationScore`, `criticalFailureRate%`, `avgCSAT`,
`surveyResponseRate%`, `resolutionRate%`, `agentsEvaluatedCount`, `agentsWithZeroEvaluations`

---

## 13. Voice Engineer Acute Triage

**Subject:** One `conversationId` (or `edgeId` for infrastructure-wide triage)  
**Use case:** A voice engineer responding to an active call quality incident — call setup failures,
one-way audio, premature disconnections, or codec negotiation errors. This combination prioritises
speed: SIP trace first, then infrastructure context, then conversation detail for validation.

**Core question:** *Why did this call fail, and is the problem isolated to this call or systemic?*

### Dataset Steps (ordered by diagnostic priority)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `telephony.get.sip.messages.for.conversation` | seed → `conversationId` | Raw SIP signalling — definitive source for failure mode identification |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing — tTalkComplete=0 + tAbandon>0 confirms pre-answer abandon |
| 3 | `conversations.get.specific.conversation.details` | `conversationId` | ANI, DNIS, originatingDirection, externalTag — confirms routing path |
| 4 | `telephony.get.trunk.metrics.summary` | trunkId (from SIP From/To headers) | Trunk health: inService, activeCalls, errorCount, utilizationPct |
| 5 | `telephony.get.edge.performance.metrics` | `edgeId` | Edge CPU/memory/active-call — resource pressure explains call quality degradation |
| 6 | `alerting.get.alerts` | `edgeId` or `trunkId` | Threshold alerts firing during the call window |
| 7 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording presence = media was established; absence = call never connected |

### SIP Trace Decision Tree

```
SIP 486 Busy Here   → Trunk capacity exhausted — check trunk-metrics.activeCalls vs. capacity
SIP 503 Unavailable → Trunk/edge offline — check alerting.get.alerts for alarms
SIP 487 Terminated  → Caller hung up during ring — confirm with tAbandon in analytics
No 200 OK after INVITE → edge CPU > 85%? Drop in registrations — check edge-metrics
re-INVITE present   → Hold or transfer event — correlate with tHeld in analytics
SDP IP mismatch     → One-way audio — NAT traversal failure; check edge STUN/TURN config
No recording        → Recording gap or edge recording service down — check recording-check
```

### Systemic vs Isolated Test

- **Isolated:** SIP 486/487 on one conversation, all other trunks healthy → far-end carrier issue
- **Systemic:** Multiple conversations fail within 5-minute window + edge CPU > 85% → Edge overload
- **Trunk-level:** All conversations on one trunk fail → trunk capacity or configuration issue
- **BYOI-path:** `externalTag` present + SIP failure → BYOI provider SIP-to-SIP handoff failing

---

## 14. Team Supervisor Dashboard

**Subject:** One `teamId` or `managementUnitId`  
**Use case:** A supervisor managing a team across one or more queues needs a unified view of their
team's live status, queue health, WFM adherence, and recent conversation performance.

**Core question:** *How is my team performing right now and today?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Shows |
|------|-------------|----------|---------------|
| 1 | `teams.get.team.members` | seed → `teamId` | userId list, name, email — scope for all subsequent queries |
| 2 | `analytics.query.agents.status.query` | `userId` (filtered) | Live presence and routing status with timestamps per agent |
| 3 | `analytics.query.queue.observations.real.time.stats` | `queueId` (from member queue memberships) | oInteracting, oWaiting, oOnQueueUsers per queue |
| 4 | `routing.get.queue.estimated.wait.time` | `queueId` | Real-time EWT — supervisor action trigger if EWT > SLA |
| 5 | `workforce.get.adherence.bulk` | `userId` | WFM adherence state per agent — IN_ADHERENCE / OUT_OF_ADHERENCE |
| 6 | `analytics.query.conversation.aggregates.agent.performance` | `userId` (today) | Today's nConnected, tHandle, tTalk per agent |
| 7 | `analytics-conversation-details-query` | `userId` (last 2 hours) | Recent conversation list — drilldown seed for flagged interactions |

### Key Joins

```
teams.get.team.members[].id
  → analytics.query.agents.status.query.userId (live status)
  → workforce.get.adherence.bulk.userId (adherence)
  → analytics.query.conversation.aggregates.agent.performance.userId (today's perf)

users.get.user.queue.memberships[].id (from team member userIds)
  → analytics.query.queue.observations.real.time.stats.queueId (queue health)
  → routing.get.queue.estimated.wait.time.queueId (EWT)
```

### Diagnostic Signals

| Signal | Action |
|--------|--------|
| oWaiting > team capacity | Approve overtime or pull agents from lower-priority queues |
| EWT > SLA target | Move available agents to undersupported queue |
| >30% of team OUT_OF_ADHERENCE | Supervisor coaching — schedule deviation pattern |
| One agent tHandle 3× team average | Skill gap or difficult call type — QM review trigger |

---

## 15. Comprehensive Executive KPI Rollup

**Subject:** Org-wide (or `divisionId` for business-unit view) + reporting window  
**Use case:** Weekly or monthly executive review requiring all 14 KPI dimensions in a single
composition. Not a data dump — each layer surfaces 2–3 headline numbers and a trend.

**Core question:** *How did the contact centre perform across volume, quality, automation, workforce, and infrastructure?*

### Composition Architecture

```
routing-queues (active=true)
  └── LAYER 1: Volume & Efficiency
      ├── analytics.query.conversation.aggregates.queue.performance    → totalHandled, AHT
      ├── analytics.query.conversation.aggregates.abandon.metrics      → abandonRate%
      └── analytics.query.conversation.aggregates.digital.channels    → channelMix

  └── LAYER 2: Service Quality
      ├── analytics.query.queue.aggregates.service.level              → slaAchievement%
      ├── analytics.query.conversation.aggregates.transfer.metrics    → transferRate%
      └── analytics.query.conversation.aggregates.wrapup.distribution → outcomeDistribution

  └── LAYER 3: Automation & AI
      ├── analytics.query.bot.aggregates                             → botContainmentRate%
      ├── analytics.query.agent.copilot.aggregates                   → copilotAdoptionRate%
      └── analytics.query.resolution.aggregates                     → fcRate%

  └── LAYER 4: Workforce
      ├── analytics.query.user.aggregates.login.activity            → onQueueUtilisation%
      └── analytics.query.conversation.aggregates.agent.performance → agentProductivity

  └── LAYER 5: Quality & VoC
      ├── analytics.query.evaluation.aggregates                     → avgQmScore, coverage%
      ├── analytics.query.survey.aggregates                         → avgCSAT, responseRate%
      └── analytics.post.transcripts.aggregates.query              → staCoverage%, sentiment

  └── LAYER 6: Infrastructure (voice-only)
      ├── telephony.get.trunk.metrics.summary                       → trunkErrors
      └── alerting.get.alerts                                       → incidentCount
```

### 14 Headline KPI Definitions

| KPI | Formula | Dataset Sources |
|-----|---------|-----------------|
| `totalHandled` | SUM(nConnected) | queue.performance |
| `abandonRate%` | SUM(nAbandoned) / SUM(nOffered) × 100 | abandon.metrics |
| `avgHandleTime` | WAVG(tHandle, nConnected) | queue.performance |
| `slaAchievement%` | queues meeting oServiceLevel / total queues × 100 | service.level |
| `transferRate%` | SUM(nTransferred) / SUM(nConnected) × 100 | transfer.metrics |
| `botContainmentRate%` | SUM(nBotHandled) / SUM(nBotInteractions) × 100 | bot.aggregates |
| `copilotAdoptionRate%` | SUM(nCopilotSuggestionsAccepted) / SUM(generated) × 100 | copilot.aggregates |
| `fcRate%` | SUM(nResolutions) / SUM(nConnected) × 100 | resolution.aggregates |
| `onQueueUtilisation%` | AVG(tInteracting / tTotal) per agent | user.aggregates.login |
| `qmCoverage%` | SUM(nEvaluations) / SUM(nConnected) × 100 | evaluation.aggregates |
| `avgQmScore` | WAVG(avgEvaluationScore, nEvaluations) | evaluation.aggregates |
| `avgCSAT` | WAVG(avgSurveyScore, nSurveysCompleted) | survey.aggregates |
| `staCoverage%` | SUM(nSpeechTextAnalyzed) / SUM(nConnected) × 100 | transcripts.aggregates |
| `sentimentIndex` | AVG(oSentimentScore) across STA-analysed conversations | transcripts.aggregates |

---

## 16. Dataset Combination Reference Matrix

`●` = used in primary path, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation | Queue | Division | Executive | Real-Time | Agent | Bot/IVR | AI Adopt | QM Rollup | VE Triage | Team Dash |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | | ● | |
| `conversations.get.specific.conversation.details` | ● | | | | | | | | | ● | |
| `conversations.get.conversation.participant.wrapup` | ● | | | | | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | ● | |
| `conversations.get.recordings` | ● | | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | | | |
| `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | ● | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | ○ | | ○ | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | ● | | | ● | | |
| `quality.get.conversation.surveys` | ● | | | | | | | | | | |
| `quality.get.published.evaluation.forms` | | | | | | | | | ● | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | ● | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | ● | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | |
| `routing-queues` | | ● | | ● | | | | | | | |
| `routing.get.queue.wrapup.codes` | | ● | | | | | | | | | |
| `routing.get.queue.members.with.status` | | ● | | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | | | | | | ● |
| `analytics.query.conversation.details.by.queue` | | ● | | | | ○ | | | | | ○ |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | ● | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | | ● |
| `analytics.query.bot.aggregates` | | | | ● | | | ● | | | | |
| `analytics.query.agent.copilot.aggregates` | | | | ● | | | | ● | | | |
| `analytics.query.evaluation.aggregates` | | ○ | ● | ● | | ○ | | ● | ● | | |
| `analytics.query.survey.aggregates` | | ○ | | ● | | | | | ● | | |
| `analytics.query.resolution.aggregates` | | ○ | | ● | | | | ● | ● | | |
| `analytics.query.ai.summary.aggregates` | | | | ● | | ○ | | ● | | | |
| `analytics.query.flow.execution.aggregates` | | | | | | | ● | | | | |
| `analytics.query.routing.activity` | | | | | ○ | | | | | ○ | |
| `analytics.query.agents.status.counts` | | | | | ● | | | | | | |
| `analytics.query.agents.status.query` | | | | | ● | | | | | | ● |
| `analytics.get.botflow.reporting.turns` | | | | | | | ● | | | | |
| `analytics.get.botflow.sessions` | | | | | | | ● | | | | |
| `analytics.query.conversations.activity` | | | | | ● | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | ● |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | |
| `authorization.get.all.divisions` | | | ● | | | | | | | | |
| `authorization.search.division.objects` | | ○ | ● | | | | | | | | |
| `authorization.get.division.grants` | | | ● | | | ○ | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | ● | | ● | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | |
| `workforce.get.management.units` | | | | | | ● | | | | | |
| `workforce.get.agent.management.unit` | | | | | | ● | | | | | ● |
| `workforce.get.adherence.bulk` | | | | | | ● | | | | | ● |
| `coaching.get.appointments` | | | ● | | | ○ | | | | | |
| `teams.get.teams` | | | | | | | | | | | ● |
| `teams.get.team.members` | | | | | | | | | | | ● |
| `analytics-conversation-details-query` | | ● | | | | ○ | ○ | | | | ○ |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | ● | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | ● | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | ● | |
| `telephony.get.edges` | | | | ○ | | | | | | ● | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | ● | |
| `audit-logs` | | | | | | ● | | | | | |

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
| `oSentimentScore` | Aggregate sentiment score (S&TA) | Voice-of-customer indicator |
| `nSpeechTextAnalyzedConversations` | Conversations with S&TA analysis | S&TA coverage |
| `nBotInteractions` | Bot/virtual-agent interactions started | Bot volume |
| `nBotHandled` | Interactions fully resolved by the bot | Self-service success |
| `nBotTransferred` | Interactions escalated from bot to agent | Escalation volume |
| `botContainmentRate%` | nBotHandled / nBotInteractions × 100 | Self-service effectiveness |
| `nCopilotSuggestionsGenerated` | AI suggestions generated by Agent Copilot | AI assist volume |
| `nCopilotSuggestionsAccepted` | AI suggestions accepted by agents | AI assist adoption |
| `copilotAdoptionRate%` | nAccepted / nGenerated × 100 | AI ROI indicator |
| `nResolutions` | Interactions resolved (AI Resolution classification) | FCR numerator |
| `fcRate%` | nResolutions / nConnected × 100 | First-contact resolution |
| `avgEvaluationScore` | Average QM evaluation score | Quality programme output |
| `evaluationCoverage%` | nEvaluations / nConnected × 100 | QM programme reach |
| `nCriticalItemFailed` | Evaluations with a critical item failure | Compliance/risk indicator |
| `avgSurveyScore` | Average CSAT or NPS survey score | Voice-of-customer |
| `surveyResponseRate%` | nSurveysCompleted / nSurveysSent × 100 | Survey data quality |
| `adherencePct` | % time agent was in scheduled state | WFM adherence |
| `estimatedWaitTimeSeconds` | Predicted wait time for next interaction in queue | Real-time staffing signal |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
