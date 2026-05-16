# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-16  
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
10. [AI Summary and Copilot Enrichment](#10-ai-summary-and-copilot-enrichment)
11. [Bot / IVR Flow Investigation](#11-bot--ivr-flow-investigation)
12. [External Contact CRM Enrichment](#12-external-contact-crm-enrichment)
13. [Quality Calibration Investigation](#13-quality-calibration-investigation)
14. [Agent Gamification and WFM Overlay](#14-agent-gamification-and-wfm-overlay)
15. [Voice Engineer Infrastructure Health Playbook](#15-voice-engineer-infrastructure-health-playbook)
16. [Workforce Adherence and Scheduling Playbook](#16-workforce-adherence-and-scheduling-playbook)
17. [Dataset Combination Reference Matrix](#17-dataset-combination-reference-matrix)

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

## 10. AI Summary and Copilot Enrichment

**Subject:** One `conversationId`  
**Use case:** Rapidly understand what happened in a conversation without listening to the recording — using AI-generated summaries from two distinct pipelines: Genesys Copilot/Agent Assist and the Speech & Text Analytics engine. Each pipeline produces different output from the same interaction.

**Core question:** *What did the AI understand about this conversation, and does it align with the analytics?*

### Dataset Steps (add to Conversation Deep Dive)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| + | `conversations.get.conversation.summaries` | `conversationId` | Copilot/Agent Assist AI-generated summary — reason for contact, resolution narrative, and next steps (requires Copilot licence) |
| + | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | STA-pipeline AI summary per communication leg — topic coverage and condensed narrative (requires STA licence) |
| + | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic and category classifications — category name, confidence score, and matched phrases |

### What Each Summary Tells You

| Source | Endpoint | Data Model | When Present |
|--------|----------|------------|--------------|
| Copilot / Agent Assist | `GET /api/v2/conversations/{conversationId}/summaries` | `summary.text`, `reasonForContact`, `resolution` per leg | Agent Assist or Copilot licence |
| STA Pipeline | `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/summaries` | `summary` per `communicationId` with topic list | STA licence + voice/digital |
| STA Categories | `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/categories` | `categoryName`, `score`, `phrases[]` | STA + topic taxonomy configured |

### Key Joins

```
conversations.get.specific.conversation.details.participants[].calls[].communicationId
  → speechandtextanalytics.get.conversation.summaries.detail.communicationId
  → speechandtextanalytics.get.conversation.communication.transcripturl.communicationId

conversations.get.conversation.summaries.entities[].communication.id
  → analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
```

### Analytical Questions Answered

- What did the AI understand the customer called about? (Copilot: `reasonForContact`)
- Was the issue resolved on the call? (Copilot: `resolution`)
- What topics did the STA engine classify the call under?
- Are AI category classifications consistent with the wrapup code the agent selected?
- Which calls in a queue had the highest category confidence scores?

---

## 11. Bot / IVR Flow Investigation

**Subject:** One `botFlowId` + time window  
**Use case:** An IVR engineer or CX designer needs to understand how a specific Architect bot flow is performing — containment rate, intent recognition accuracy, turn counts, and where customers are dropping off or transferring to agents. This is the self-service layer that precedes most voice queue interactions.

**Core question:** *Is the IVR/bot containing customers effectively, and where is it failing?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | seed → `botFlowId` | Flow name, type, division, published version, and description |
| 2 | `flows.get.flow.outcomes` | `flowId` | Configured exit outcome labels — self-served, transferred, abandoned, error |
| 3 | `flows.get.flow.milestones` | `flowId` | Named milestone checkpoints for funnel analysis |
| 4 | `analytics.get.botflow.sessions` | `botFlowId` | Each customer session — start time, outcome, exit reason, turn count, and duration |
| 5 | `analytics.get.botflow.reporting.turns` | `botFlowId` | Turn-by-turn NLU log — user input text, matched intent, confidence score, bot response |
| 6 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Aggregate: nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone per interval |
| 7 *(conditional)* | `analytics-conversation-details-query` | `conversationId` | For sessions with outcome=TRANSFERRED — full analytics detail for the handoff conversation |

### Key Joins

```
flows.get.all.flows.id (= botFlowId)
  → analytics.get.botflow.sessions.botFlowId
  → analytics.get.botflow.reporting.turns.botFlowId
  → analytics.query.flow.aggregates.execution.metrics.dimension.flowId

analytics.get.botflow.sessions[].conversationId
  → analytics-conversation-details-query[].conversationId   (transfer handoffs only)
  → analytics.get.single.conversation.analytics.conversationId (single-call drill)

flows.get.flow.outcomes[].id
  → analytics.get.botflow.sessions[].flowOutcomeId (label resolution)
```

### Analytical Questions Answered

- What percentage of sessions were fully self-served (containment rate)?
- Where in the flow do customers most often transfer to an agent or abandon?
- Which intents have low NLU confidence — indicating training data gaps?
- What is the average turn count per session? (High = confused customer or poor intent design)
- Are milestone checkpoints being reached as expected?
- For sessions that transferred: what queue received them and what was the post-transfer AHT?

### Computed Metrics

```
containmentRate = sessions[outcome='SELF_SERVED'] / totalSessions × 100
handoffRate     = sessions[outcome='TRANSFERRED'] / totalSessions × 100
avgTurns        = mean(sessions[].turnCount)
intentHitRate   = turns[confidence >= 0.8] / totalTurns × 100
milestoneRate   = sessions[milestoneReached=true] / totalSessions × 100
```

### IVR Engineering Notes

- `analytics.get.botflow.reporting.turns` is the primary NLU diagnostics dataset. Low confidence scores on common inputs indicate the NLU model needs retraining on those utterance patterns.
- `flows.get.flow.milestones` + aggregate data answer funnel questions: how many sessions reached authentication milestone vs. information-delivery milestone vs. resolution milestone.
- Use `getAnalyticsBotflowDivisionsReportingturns` (the division-scoped API) rather than the deprecated `getAnalyticsBotflowReportingturns` — the catalog dataset `analytics.get.botflow.reporting.turns` maps to the current endpoint.

---

## 12. External Contact CRM Enrichment

**Subject:** One `externalContactId` (present in `conversations.get.conversation.object.participants[].externalContactId`)  
**Use case:** A contact has been identified in the conversation object as an external CRM contact. The operator or investigation pipeline needs the CRM profile, interaction history, and digital journey context to understand who this customer is — not just what happened in the current call.

**Core question:** *Who is this customer, what is their CRM history, and what brought them to call today?*

### How to Identify an External Contact

In `conversations.get.specific.conversation.details`, the `participants` array carries:

```json
{
  "purpose": "customer",
  "externalContactId": "<uuid>",
  "externalOrganizationId": "<uuid>"
}
```

A non-null `externalContactId` signals a CRM-linked contact. BYOI conversations (identified by `externalTag`) also carry this field when the provider sets it.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `externalcontacts.get.contact` | seed → `externalContactId` | CRM contact record — name, organisation, email, phone numbers, and custom data fields |
| 2 | `externalcontacts.get.contact.notes` | `externalContactId` | Agent-authored CRM notes with timestamps — historical narrative about the contact |
| 3 | `externalcontacts.get.contact.journey.sessions` | `externalContactId` | Web and digital journey sessions — channels visited, engagement events, and trigger outcomes before the call |
| 4 | `analytics-conversation-details-query` | `externalContactId` | All Genesys conversations historically linked to this contact across channels and queues |
| 5 | `conversations.search.participant.attributes` | `conversationId` | IVR/Architect variables set in any conversation with this contact |
| 6 | `quality.get.surveys` | `conversationId` | Post-call survey outcomes across all contact conversations — CSAT and NPS history |

### Key Joins

```
externalcontacts.get.contact.id (= externalContactId)
  → analytics-conversation-details-query[].participants[].externalContactId
  → externalcontacts.get.contact.notes[].externalContactId
  → externalcontacts.get.contact.journey.sessions[].contact.id

analytics-conversation-details-query[].conversationId
  → conversations.search.participant.attributes[].conversationId (IVR variables per call)
  → quality.get.surveys[].conversationId (survey outcomes per call)
```

### Analytical Questions Answered

- How many times has this customer contacted us, and through which channels?
- What was the customer's digital journey before they called — what pages did they visit?
- Were there previous CRM notes indicating known issues or escalation history?
- What is this customer's CSAT trend over their call history?
- Did the IVR capture any consistent attributes across multiple contacts (same account number, same issue intent)?

### BYOI Alignment

For BYOI conversations, the `externalTag` and `externalContactId` together identify both the external provider's call ID and the CRM contact. Use `conversations.get.conversation.customattributes` in addition to the external contact datasets to retrieve the provider-set context variables alongside the CRM profile.

---

## 13. Quality Calibration Investigation

**Subject:** One `calibrationId`  
**Use case:** A QA manager needs to assess inter-rater reliability for a specific calibration session — comparing each evaluator's scores against the calibrator's authoritative score, identifying outliers, and determining whether evaluators need additional training.

**Core question:** *Are evaluators scoring consistently with the calibrator, and which criteria show the most variance?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `quality.get.calibration.detail` | seed → `calibrationId` | Calibration record — calibrator identity, conversation ID, evaluator list, per-evaluator scores, calibration status |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Analytics detail for the calibration conversation — queue, agent, timing, media type |
| 3 | `conversations.get.specific.conversation.details` | `conversationId` | Conversation object — participant roster, DNIS, and media type for call context |
| 4 | `conversations.get.recordings` | `conversationId` | Signed recording download URLs — so evaluators can replay the calibration call |
| 5 | `quality.get.published.evaluation.forms` | `formId` | Evaluation form definition — criteria names, weights, and critical item flags |
| 6 *(conditional)* | `quality.get.calibrations` | `calibratorId` | Other calibrations by the same calibrator — context for programme breadth and cadence |

### Key Joins

```
quality.get.calibration.detail.id (= calibrationId)
  → quality.get.calibration.detail.conversation.id → conversationId
  → quality.get.calibration.detail.evaluations[].evaluator.id → evaluatorId

quality.get.calibration.detail.calibrationForm.id
  → quality.get.published.evaluation.forms[].id (criteria and weights)

quality.get.calibration.detail.evaluations[].answers
  → computed: scoreVariance, calibratorDelta per criterion
```

### Analytical Questions Answered

- What was each evaluator's total score vs. the calibrator's score?
- Which evaluation criteria show the highest variance across evaluators?
- Which evaluators are consistently scoring above or below the calibrator?
- Did any evaluator flag a critical item differently from the calibrator?
- How frequently is this calibrator running sessions? (from conditional step 6)

### Computed Metrics

```
scoreVariance    = std_dev(evaluations[].totalScore)
calibratorDelta  = mean(evaluations[].totalScore) - calibrator.totalScore
alignmentRate    = evaluators[|score - calibratorScore| <= 5] / total × 100
critItemAgreement = evaluators[criticalItemMatch = calibrator] / total × 100
```

---

## 14. Agent Gamification and WFM Overlay

**Subject:** One `userId` + time window  
**Use case:** A supervisor or workforce planner needs to understand an agent's performance across three dimensions simultaneously: operational metrics (AHT, nConnected), quality (QM score), and engagement (gamification scorecard, peer rank). The goal is to identify coaching opportunities, recognize high performers, and correlate engagement with performance outcomes.

**Core question:** *How is this agent performing relative to their peers, and is their engagement and adherence aligned with their operational results?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | Agent identity, division, manager, routing status |
| 2 | `analytics.query.user.aggregates.performance.metrics` | `userId` | nConnected, tHandle, tTalk, tAcw for the window — core productivity |
| 3 | `analytics.query.user.aggregates.login.activity` | `userId` | Time in routing status — on-queue, idle, off-queue breakdown |
| 4 | `quality.get.agents.activity` | `userId` | Evaluation count, average/highest/lowest QM scores |
| 5 | `gamification.get.agent.scorecard` | `userId` | Workday gamification scorecard — KPI metric values and points per workday |
| 6 | `gamification.get.agent.insights` | `userId` | Peer comparison — percentile rank within division, trend direction, top/bottom KPIs |
| 7 *(WFM)* | `workforce.get.agent.management.unit` | `userId` | WFM management unit assignment — required to scope adherence queries |
| 8 *(WFM)* | `workforce.get.adherence.bulk` | `userId` | Real-time WFM schedule adherence — scheduled vs. actual state with variance |
| 9 *(conditional)* | `coaching.get.appointments` | `userId` | Coaching sessions in the window — correlate coaching with score/performance trends |

### Key Joins

```
users.get.user.details.with.full.expansion.id (= userId)
  → analytics.query.user.aggregates.performance.metrics.group.userId
  → quality.get.agents.activity.user.id
  → gamification.get.agent.scorecard.userId
  → gamification.get.agent.insights.userId

workforce.get.agent.management.unit.managementUnit.id
  → workforce.get.management.unit.adherence.user.id (join to confirm management unit)
```

### Analytical Questions Answered

- Where does this agent rank among their peers in the division? (percentile from insights step)
- Is their gamification KPI performance improving, stable, or declining?
- Does the agent's QM score correlate with their operational productivity (AHT, nConnected)?
- How much of their scheduled time was spent on-queue vs. off-queue?
- Were coaching appointments associated with subsequent score improvements?
- Are agents with high gamification scores also the top performers on operational metrics?

### Executive View (Division Roll-Up)

Fan out steps 5–6 across `users.division.analysis.get.users.with.division.info` to build a division-level gamification leaderboard. Join with `quality.get.agents.activity` to create a quality vs. engagement quadrant:

```
Q1 (High Gamification, High QM) → Top performers — recognize and retain
Q2 (High Gamification, Low QM)  → Engaged but skill gaps — coaching target
Q3 (Low Gamification, High QM)  → Quality-focused but disengaged — risk of attrition
Q4 (Low Gamification, Low QM)   → Priority intervention — performance management
```

---

## 15. Voice Engineer Infrastructure Health Playbook

**Subject:** Organisation-wide (no fixed subject)  
**Use case:** A NOC team member or voice engineer starting a shift, or triaging a reported audio quality or call failure incident, needs a structured view of platform infrastructure health — trunk capacity, Edge appliance status, active alerts, and current queue depth — before drilling into individual conversation SIP traces.

**Core question:** *Is the voice infrastructure healthy, and are there systemic issues that explain reported call quality problems?*

### Playbook Layers (ordered by triage priority)

#### Layer 1 — Trunk Health
| Dataset Key | Metrics | Role |
|-------------|---------|------|
| `telephony.get.trunks` | `trunkType`, `state`, `name`, `managedStatus` | Full trunk inventory with state — identify trunks in error or maintenance |
| `telephony.get.trunk.metrics.summary` | `inServiceCount`, `outOfServiceCount`, `activeCalls`, `callsIn`, `callsOut`, `errorCount` | Capacity utilisation and error counters — flag saturation or failure |

#### Layer 2 — Edge Appliance Status
| Dataset Key | Metrics | Role |
|-------------|---------|------|
| `telephony.get.edges` | `name`, `onlineStatus`, `softwareStatus`, `callCount`, `edgeGroup` | Edge registration and call-carrying status — confirm all Edges are online |
| `telephony.get.edge.performance.metrics` *(conditional)* | `cpuCapacity`, `memoryCapacity`, `diskCapacity`, `activeCalls` | Resource pressure on specific Edges — root cause of audio quality issues |

#### Layer 3 — Active Alerts
| Dataset Key | Metrics | Role |
|-------------|---------|------|
| `alerting.get.alerts` | `alertType`, `severity`, `ruleId`, `startDate` | Currently firing platform threshold alerts |
| `alerting.get.rules` | `name`, `conditions`, `notificationUsers` | Alert rule definitions — understand what each alert means |

#### Layer 4 — Real-Time Queue Depth (leading indicator)
| Dataset Key | Metrics | Role |
|-------------|---------|------|
| `analytics.query.queue.observations.real.time.stats` | `oInteracting`, `oWaiting`, `oOnQueueUsers`, `oLongestWaiting` | Live queue depth — high `oWaiting` during a trunk issue confirms causality |
| `analytics.query.conversation.activity.real.time` | `oInteracting`, `oWaiting`, `oAlerting`, `oLongestWaiting` | In-flight conversations by queue and mediaType |

### Incident Triage Decision Tree

```
Reported symptom: call setup failures
  → telephony.get.sip.message.for.conversation
  → Look for: no 200 OK, 486 Busy, 503 Service Unavailable, 5xx responses
  → If 503: check telephony.get.trunk.metrics.summary for outOfServiceCount
  → If 486: check routing.get.single.queue.config for overflowAction

Reported symptom: one-way audio
  → telephony.get.sip.message.for.conversation
  → Look for: SDP media IP mismatch in re-INVITE, asymmetric codec in 200 OK
  → Cross-check: telephony.get.edge.performance.metrics for CPU pressure

Reported symptom: widespread call drops / increased abandons
  → telephony.get.trunk.metrics.summary → trunkSaturation = activeCalls / inServiceCount
  → If > 0.9: trunk at capacity — check provisioned channels vs peak demand
  → telephony.get.edges → confirm all Edges are ONLINE
  → analytics.query.queue.observations.real.time.stats → oWaiting surge confirms traffic

Reported symptom: edge performance degradation
  → telephony.get.edge.performance.metrics → CPU/memory > 80%
  → telephony.create.edge.logs.job → collect diagnostic logs
  → telephony.request.edge.logs.job.upload → upload for Genesys support
```

---

## 16. Workforce Adherence and Scheduling Playbook

**Subject:** One or more `managementUnitId` values (no fixed time window — point-in-time)  
**Use case:** A WFM analyst or real-time supervisor needs to monitor live schedule adherence across a management unit, identify agents who are off-schedule, correlate adherence gaps with queue depth, and estimate the impact on wait times. This playbook is designed for intraday management — typically polled at 60–120 second intervals.

**Core question:** *Which agents are off-schedule right now, and how is this affecting queue service levels?*

### Playbook Layers

#### Layer 1 — Management Unit Roster
| Dataset Key | Join Key | Metrics | Role |
|-------------|----------|---------|------|
| `workforce.get.management.units` | seed | `name`, `timezone`, `agentCount` | Management unit inventory |
| `workforce.get.management.unit.users` | `managementUnitId` | `userId`, `name`, `division` | Agent roster per management unit — all agents to track |

#### Layer 2 — Real-Time Adherence
| Dataset Key | Join Key | Metrics | Role |
|-------------|----------|---------|------|
| `workforce.get.management.unit.adherence` | `managementUnitId` | `adherencePercentage`, `systemPresence`, `scheduledActivityCategory`, `actualActivityCategory`, `impact` | Scheduled vs. actual state per agent — adherence score and variance |
| `workforce.get.adherence.bulk` | `userId` list | `adherenceState`, `routingStatus`, `presence`, `timeOfAdherenceChange` | Bulk real-time adherence state — faster lookup for targeted user lists |

#### Layer 3 — Management Unit Routing
| Dataset Key | Join Key | Metrics | Role |
|-------------|----------|---------|------|
| `workforce.get.agent.management.unit` | `userId` | `managementUnitId`, `managementUnitName` | Resolve an individual agent to their management unit — entry point when starting from an agent, not a unit |

#### Layer 4 — Queue Staffing Alignment
| Dataset Key | Join Key | Metrics | Role |
|-------------|----------|---------|------|
| `analytics.query.queue.observations.real.time.stats` | `queueId` | `oOnQueueUsers`, `oInteracting`, `oWaiting` | Live staffing level vs. queue demand |
| `routing.get.queue.estimated.wait.time` | `queueId` | `estimatedWaitTime` | Projected customer wait given current staffing — impact model |

### Key Joins

```
workforce.get.management.unit.users[].id (= userId)
  → workforce.get.management.unit.adherence[].user.id
  → workforce.get.adherence.bulk (request body: userId list)
  → analytics.query.user.observations.real.time.status[].group.userId

workforce.get.management.units[].id (= managementUnitId)
  → workforce.get.management.unit.adherence.managementUnit.id
  → workforce.get.management.unit.users.managementUnit.id
```

### Intraday Intervention Decision

```
Agents with adherenceState != 'InAdherence'
  AND scheduledActivityCategory == 'OnQueue'
  AND actualActivityCategory    != 'OnQueue'
  → Off-queue agents who should be available — direct supervisor intervention

Cross-join with analytics.query.queue.observations.real.time.stats:
  If oWaiting > threshold AND adherenceGap > N agents → escalate to WFM reforecast

routing.get.queue.estimated.wait.time → quantify customer impact of adherence gap
```

---

## 17. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | Bot/IVR Investigation | External Contact | Calibration | Gamification / WFM | Infra Health | Adherence |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.specific.conversation.details` | ● | | | | | | | ○ | ● | | | |
| `conversations.get.conversation.object` | ● | | | | | | | ○ | | | | |
| `conversations.get.call.detail` | ○ | | | | | | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ● | | | | | | | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | ○ | | ● | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | | | |
| `conversations.get.recordings` | ● | | | | | | | | ● | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | ○ | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | ● | | | | |
| `quality.get.evaluations.query` | ● | ○ | ○ | | | ○ | | | | | | |
| `quality.get.surveys` | ● | | | ● | | | | ● | | | | |
| `quality.get.conversation.surveys` | ○ | | | | | | | | | | | |
| `telephony.get.sip.message.for.conversation` | ○ | | | | | | | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | | | |
| `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | ○ | | | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | | | |
| `routing.get.queue.wrapup.codes` | | ● | | | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | | | |
| `routing.get.queue.members.with.status` | | ● | | | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ○ | | | ○ | | | | | | | ● |
| `analytics-conversation-details-query` | | ● | | | | ○ | ○ | ● | | | | |
| `analytics.query.conversation.details.by.queue` | | ● | | | | | | | | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | ○ | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | | |
| `authorization.search.division.objects` | | | ● | | | | | | | | | |
| `authorization.get.division.grants` | | | ○ | | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | ● | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | ● | | |
| `analytics.query.user.aggregates.performance.metrics` | | | ● | ● | | ● | | | | ● | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | | |
| `analytics.division.analysis.conversation.aggregates.by.division` | | | ● | | | | | | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | ● | | |
| `quality.get.calibrations` | | | | | | | | | ○ | | | |
| `quality.get.calibration.detail` | | | | | | | | | ● | | | |
| `quality.get.published.evaluation.forms` | | | | | | | | | ● | | | |
| `coaching.get.appointments` | | | ● | | | ○ | | | | ○ | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | ● | ● |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | ● | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | ● | | | | | |
| `analytics.get.botflow.sessions` | | | | | | | ● | | | | | |
| `analytics.get.botflow.reporting.turns` | | | | | | | ● | | | | | |
| `flows.get.all.flows` | | | | | | | ● | | | | | |
| `flows.get.flow.outcomes` | | | | | | | ● | | | | | |
| `flows.get.flow.milestones` | | | | | | | ● | | | | | |
| `externalcontacts.get.contact` | | | | | | | | ● | | | | |
| `externalcontacts.get.contact.notes` | | | | | | | | ● | | | | |
| `externalcontacts.get.contact.journey.sessions` | | | | | | | | ● | | | | |
| `gamification.get.agent.scorecard` | | | | | | | | | | ● | | |
| `gamification.get.agent.insights` | | | | | | | | | | ● | | |
| `telephony.get.trunks` | | | | | | | | | | | ● | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | | | | | | | ● | |
| `telephony.get.edges` | | | | ○ | | | | | | | ● | |
| `telephony.get.edge.performance.metrics` | ○ | | | | | | | | | | ● | |
| `telephony.create.edge.logs.job` | ○ | | | | | | | | | | ○ | |
| `alerting.get.alerts` | | | | ○ | | | | | | | ● | |
| `alerting.get.rules` | | | | ○ | | | | | | | ● | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | ● | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | | |
| `workforce.get.management.units` | | | | | | | | | | | | ● |
| `workforce.get.management.unit.users` | | | | | | | | | | | | ● |
| `workforce.get.management.unit.adherence` | | | | ○ | | | | | | | | ● |
| `workforce.get.adherence.bulk` | | | | | | ● | | | | ○ | | ● |
| `workforce.get.agent.management.unit` | | | | | | ● | | | | ● | | ● |
| `audit-logs` | | | | | | ● | | | | | | |

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
| `containmentRate` | Bot sessions self-served / total sessions × 100 | IVR effectiveness |
| `handoffRate` | Bot sessions transferred to agent / total sessions × 100 | Bot-to-human transfer rate |
| `avgTurns` | Mean turn count per bot session | IVR complexity / confusion indicator |
| `intentMatchRate` | Turns with NLU confidence ≥ threshold / total turns × 100 | NLU model quality |
| `scoreVariance` | Std dev of evaluator scores in a calibration | Evaluator consistency |
| `calibratorDelta` | Mean evaluator score − calibrator score | Calibration bias |
| `alignmentRate` | Evaluators within ±5 pts of calibrator / total × 100 | Inter-rater reliability |
| `adherencePercentage` | Time in scheduled state / total scheduled time × 100 | WFM compliance |
| `estimatedWaitTime` | Seconds until next interaction is expected to be answered | Real-time EWT |
| `peerPercentileRank` | Agent's performance rank within division peer group | Gamification tier |
| `trendDirection` | Improving / Stable / Declining (from gamification insights) | Engagement trajectory |
| `trunkSaturation` | activeCalls / inServiceCount | Trunk capacity utilisation |
| `cpuCapacity` | Edge CPU utilisation percentage | Edge resource pressure |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
