# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-02  
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
11. [Teams Investigation](#11-teams-investigation)
12. [External Contact / CRM Context Enrichment](#12-external-contact--crm-context-enrichment)
13. [Voice Engineer SIP + Edge Triage](#13-voice-engineer-sip--edge-triage)
14. [IVR / Bot Flow Performance Investigation](#14-ivr--bot-flow-performance-investigation)
15. [Quality Management Deep Dive](#15-quality-management-deep-dive)
16. [Agent Development & Schedule Adherence](#16-agent-development--schedule-adherence)
17. [AI-Assisted Conversation Review (Copilot + STA)](#17-ai-assisted-conversation-review-copilot--sta)
18. [Journey-Linked Conversation Context](#18-journey-linked-conversation-context)
19. [Recording Governance Audit](#19-recording-governance-audit)
20. [Extended Reference Matrix](#20-extended-dataset-combination-reference-matrix)

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

---

## 11. Teams Investigation

**Subject:** One `teamId` + time window  
**Use case:** A supervisor team in Genesys Cloud is a grouping that cuts across queues and can span
division boundaries — a team lead might own agents across multiple queues within or outside one
division. When an incident involves a specific supervisor's team, the investigation scope is the
team roster rather than a division or queue.

**Core question:** *How did this team's agents perform, and what is their current state?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `teams.get.all.teams` | seed → name lookup → `teamId` | Team name, description, member count |
| 2 | `teams.get.team.members` | `teamId` | Agent userId list with current routing status and presence |
| 3 | `analytics.query.conversation.aggregates.agent.performance` (userId list) | `userId` | Per-agent: nConnected, tHandle, tTalk, tAcw in the window |
| 4 | `analytics.query.user.aggregates.login.activity` (userId list) | `userId` | Time in each routing status and system presence per agent |
| 5 | `quality.get.agents.activity` (userId list) | `userId` | Evaluation count, average/highest/lowest scores |
| 6 | `gamification.get.scorecard.by.user` (per userId) | `userId` | Gamification scorecard: KPI values and points vs. targets |
| 7 | `coaching.get.appointments` (userId list) | `userId` | Coaching sessions scheduled or completed in the window |
| 8 | `learning.get.assignments` (userId filter) | `userId` | Training assignments: completion status, overdue flag |

### Key Joins

```
teams.get.team.members[].id
  → analytics.query.conversation.aggregates.agent.performance[].group.userId
  → analytics.query.user.aggregates.login.activity[].group.userId
  → quality.get.agents.activity[].user.id
  → gamification.get.scorecard.by.user (fan-out per userId)
  → coaching.get.appointments[].attendees[].id
  → learning.get.assignments[].user.id
```

### Analytical Questions Answered

- Which agents on this team handled the most volume? The least?
- Which agents have the highest AHT compared to team average?
- Who has been off-queue disproportionately?
- Which agents haven't been evaluated recently?
- Are gamification scores aligned with quality scores?
- Which agents have overdue training assignments?
- Is coaching correlated with score improvement for this team?

### Teams vs. Divisions as Investigation Entry Point

| Start with | When you know | You get |
|------------|---------------|---------|
| `divisionId` | Business unit scope (all queues + all agents in a division) | Division-wide group performance with queue breakdown |
| `teamId` | Supervisor-owned team (may span divisions/queues) | Tightly scoped agent roster performance and development |
| `queueId` | Specific queue health concern | Queue-level SLA + conversation details + member roster |

---

## 12. External Contact / CRM Context Enrichment

**Subject:** One `conversationId` where a participant has an `externalContactId` or `externalOrganizationId`  
**Use case:** Many contact centre conversations are linked to a CRM contact record — either because
the customer was identified by the IVR, a data action matched their phone number, or an agent
manually associated them. The external contact object carries the full customer profile: name,
company, prior interaction notes, and the customer's full Journey history.

**Core question:** *Who was this customer, and what was their prior digital history before calling?*

### How to Identify a Linked External Contact

In `conversations.get.conversation.object`:

```json
{
  "participants": [
    {
      "purpose": "customer",
      "externalContactId": "abc-123-contact-id",
      "externalOrganizationId": "xyz-456-org-id"
    }
  ]
}
```

Either field being non-null means the conversation has a CRM link.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Conversation baseline; extracts `externalContactId` and `externalOrganizationId` |
| 2 | `external.contacts.get.contact` | `externalContactId` | Full contact profile: name, phone, email, company, opt-out flags, custom fields |
| 3 | `external.contacts.get.organization` | `externalOrganizationId` | Linked company record: name, address, tier, custom fields |
| 4 | `external.contacts.get.contact.journey.sessions` | `externalContactId` | Historical Journey sessions: prior web visits, digital interactions, previous contact centre sessions |
| 5 | `journey.get.session` | `sessionId` from step 4 | Full session detail for the most recent Journey session |
| 6 | `journey.get.session.events` | `sessionId` | Events within the session: page views, form submissions, product views that preceded the call |

### Key Joins

```
conversations.get.conversation.object.participants[purpose=customer].externalContactId
  → external.contacts.get.contact.id
  → external.contacts.get.contact.journey.sessions[].id (session list)
    → journey.get.session.sessionId
    → journey.get.session.events[].sessionId

conversations.get.conversation.object.participants[purpose=customer].externalOrganizationId
  → external.contacts.get.organization.id
```

### Analytical Questions Answered

- Who was the customer? What is their company?
- Did the customer opt out of surveys? (surveyOptOut field)
- What was the customer doing online before they called? (Journey events)
- Have they called before? How many prior sessions exist?
- Did a specific web action (e.g. pricing page visit, checkout abandonment) trigger the call?
- Is the customer associated with a high-value organisation?

### BYOI + External Contact Overlap

BYOI conversations (`externalTag` non-null) frequently also have `externalContactId` set when the
external provider links the injected call to a CRM record. In those cases, run both the BYOI
enrichment steps (Section 6) and the External Contact steps above in parallel.

---

## 13. Voice Engineer SIP + Edge Triage

**Subject:** One `conversationId` with reported call quality or connectivity issues  
**Use case:** A voice engineer receives a report of one-way audio, a dropped call, a call that
never connected, or poor audio quality on a specific conversation. The SIP trace combined with
per-edge and per-trunk metrics gives the complete signaling and infrastructure picture needed
to root-cause the problem without opening a Genesys support ticket.

**Core question:** *What did the SIP signaling show, and was the Edge or trunk under stress?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Participants, sessions, `provider` field (identifies Edge), `edgeId` from sessions |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing: IVR, ACD, talk, hold — establishes timeline |
| 3 | `telephony.get.sip.messages.for.conversation` | `conversationId` | Full SIP trace: INVITE, 18x, 200 OK, BYE, re-INVITE, codec SDP |
| 4 | `telephony.get.edge.performance.metrics` | `edgeId` from step 1 | CPU, memory, active call count, SIP errors on the Edge at time of call |
| 5 *(if trunk suspected)* | `telephony.get.trunk.metrics.by.trunk` | `trunkId` from step 1 | Per-trunk: active sessions, call capacity, error counters |
| 6 *(if Edge logs needed)* | `telephony.create.edge.logs.job` → `telephony.get.edge.logs.job` | `edgeId` | Edge log capture job: triggers log upload for deeper media plane analysis |
| 7 | `telephony.get.trunks` | org scope | SIP trunk inventory: confirms trunk registration and base configuration |
| 8 | `architect.get.ivrs` | `dnis` from step 1 | IVR configuration: which IVR entry matched the DNIS, which flow was invoked |
| 9 | `architect.get.schedules` | `scheduleGroup` from step 8 | Confirms schedule rules were active (open/closed state at time of call) |

### Key Joins

```
conversations.get.conversation.object.participants[purpose=system].calls[].provider
  → telephony.get.edges[].id (Edge lookup by provider string)

telephony.get.sip.messages.for.conversation[].callId
  → cross-reference with Edge SIP logs (step 6 output)

conversations.get.conversation.object.participants[purpose=external].calls[].self.addressUri
  → architect.get.ivrs[].dnis[] (DNIS match → IVR entry)
```

### SIP Diagnostic Decision Tree

```
INVITE received?
  No → Trunk or network issue (step 5, step 6)
  Yes → 200 OK returned?
    No → 4xx/5xx → call rejected at far end (step 3 status code)
       → 503 Service Unavailable → Edge overload (step 4 CPU/memory)
    Yes → Media established?
      One-way audio → SDP IP mismatch in step 3 (check a= line, c= line)
      No audio → NAT or firewall blocking RTP (step 3 media port analysis)
      Audio then drops → re-INVITE failure or network interruption (step 3 BYE analysis)
```

### Voice Engineer Notes

The `edgeId` is not always directly exposed in the conversation object. It can be derived from:
1. `participants[].calls[].provider` — the provider string contains the Edge identifier
2. SIP Call-ID in step 3 — the Genesys Edge includes its ID in the Call-ID header

`telephony.get.edge.performance.metrics` returns a snapshot of **current** Edge state. For historical
comparison, cross-reference with `alerting.get.alerts` (any Edge alerts firing during the conversation
window) and the Edge log files retrieved in step 6.

---

## 14. IVR / Bot Flow Performance Investigation

**Subject:** One `flowId` (or bot `flowId`) + time window  
**Use case:** Self-service rates are dropping, customers are escalating from the bot more than
expected, or a specific IVR flow has high abandonment. A voice engineer or operations analyst needs
to understand whether the flow is executing correctly, what outcomes are being triggered, and
whether specific intents or milestones are failing.

**Core question:** *Is this flow performing as designed, and where are customers dropping off or escalating?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` | seed → name lookup → `flowId` | Flow name, type (inboundCall, bot, inQueue), published version |
| 2 | `flows.get.flow.outcomes` | `flowId` | Outcome label definitions: Self-Contained, Escalated, Abandoned, etc. |
| 3 | `flows.get.flow.milestones` | `flowId` | Named milestone definitions for tracking progress through the flow |
| 4 | `analytics.query.flow.aggregates.execution.metrics` | `flowId` | Aggregate counts: nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone per hour |
| 5 *(bot flows only)* | `analytics.query.bot.aggregates` | `botId` | Bot-level: nBotSessions, nBotIntents, nBotSuccesses, nBotFailures, tBotSession |
| 6 *(bot flows only)* | `analytics.get.botflow.sessions` | `botFlowId` | Individual bot session records: intent sequence, escalation reason, session duration |
| 7 | `analytics-conversation-details-query` (flowId filter) | `conversationId` | Conversations that passed through this flow — for case-level drill-down |
| 8 | `architect.get.ivrs` | `flowId` from step 1 | IVR entries pointing to this flow: DNIS and schedule context |

### Key Joins

```
flows.get.all.flows[].id
  → analytics.query.flow.aggregates.execution.metrics[].group.flowId
  → analytics.query.bot.aggregates[].group.botId (if bot flow)
  → analytics.get.botflow.sessions[].flowId

analytics.query.flow.aggregates.execution.metrics[].group.flowOutcome
  → flows.get.flow.outcomes[].id (label resolution)

analytics.query.flow.aggregates.execution.metrics[].group.flowMilestone
  → flows.get.flow.milestones[].id (label resolution)
```

### Analytical Questions Answered

- What percentage of callers completed the flow self-service vs. escalated to an agent?
- Which outcomes are most frequent? Is the escalation rate increasing?
- Are specific milestones seeing high failure rates (data action timeouts, invalid input loops)?
- For bot flows: which intents have the highest failure rate? What does a failing session look like?
- What is the average bot session duration? Are sessions timing out?
- Which DNIS numbers route to this flow? Is DNIS coverage correct?

### Self-Service Rate Formula

```
Self-Service Rate = nFlowOutcome[outcome=Self-Contained] / nFlow × 100
Escalation Rate   = nFlowOutcome[outcome=Escalated] / nFlow × 100
Containment Rate  = 1 - Escalation Rate
Bot Success Rate  = nBotSuccesses / nBotSessions × 100
```

---

## 15. Quality Management Deep Dive

**Subject:** Queue, agent, or conversation scoped + time window  
**Use case:** A QM manager or compliance officer needs to understand evaluation coverage, evaluator
calibration alignment, score trends, and customer survey outcomes across a specific queue or for
a specific agent. This combination gives the full QM picture from form definition through to
calibration verification.

**Core question:** *Are we evaluating consistently, and what do the scores and surveys tell us?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `quality.get.published.evaluation.forms` | — | Active form definitions: question categories, weights, critical questions |
| 2 | `quality.get.evaluations.query` (queueId or userId filter) | `conversationId` + `userId` | Evaluation records: score, form used, evaluator, calibration flag, release status |
| 3 | `quality.get.calibrations` (conversationId or calibratorId filter) | `conversationId` | Calibration sessions: calibrated score vs. original, evaluator alignment |
| 4 | `quality.get.agents.activity` (userId list) | `userId` | Per-agent summary: evaluation count, average/highest/lowest scores, evaluator breakdown |
| 5 | `quality.get.surveys` (queueId or conversationId filter) | `conversationId` | Customer CSAT/NPS survey results matched to evaluated conversations |
| 6 *(for sampled conversations)* | `conversations.get.speech.text.analytics` | `conversationId` | STA overall sentiment — compare to QM score (do they correlate?) |
| 7 *(for sampled conversations)* | `speechandtextanalytics.get.conversation.summaries` | `conversationId` | AI-generated summary: resolution status and follow-up intent |

### Key Joins

```
quality.get.evaluations.query[].conversationId
  → quality.get.surveys[].conversationId (CSAT match)
  → quality.get.calibrations[].conversationId (calibration match)
  → conversations.get.speech.text.analytics.conversationId (sentiment match)

quality.get.evaluations.query[].evaluationForm.id
  → quality.get.published.evaluation.forms[].id (form definition)

quality.get.evaluations.query[].agent.id
  → quality.get.agents.activity[].user.id
```

### Analytical Questions Answered

- What is the evaluation coverage rate (evaluations / nConnected)?
- Are evaluator scores consistent across calibration sessions?
- Which agents have the widest gap between QM score and customer CSAT?
- Are low-scoring agents improving over time?
- Do conversations with negative STA sentiment also have low QM scores?
- Which evaluation forms are most commonly used? Are critical questions failing frequently?

### QM Coverage Formula

```
Coverage Rate     = COUNT(evaluations) / nConnected × 100
Calibration Delta = AVG(|calibratedScore - originalScore|)  [lower = better alignment]
Score / CSAT Gap  = AVG(QM score) vs AVG(CSAT score)  [large gap = scoring calibration issue]
```

---

## 16. Agent Development & Schedule Adherence

**Subject:** One `userId` + time window  
**Use case:** An operations manager or WFM analyst needs to understand whether a specific agent
is meeting their schedule, progressing through training, responding to coaching, and improving
their gamification metrics over time. This is the development-focused counterpart to the
performance-focused Agent Investigation.

**Core question:** *Is this agent developing as expected — adherent, trained, coached, and improving?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | Identity, manager, current routing status, current presence |
| 2 | `analytics.query.user.details.activity.report` | `userId` | Presence and routing status event timeline: login/logout, on-queue/off-queue transitions |
| 3 | `workforce.get.management.unit.adherence` | `managementUnitId` (from user WFM record) | WFM adherence record: scheduled state vs. actual state with variance minutes |
| 4 | `coaching.get.appointments` | `userId` | Coaching sessions: status (Scheduled/InProgress/Completed), facilitator, topics |
| 5 | `learning.get.assignments` | `userId` | Training assignments: module name, completion status, score, overdue flag |
| 6 | `quality.get.agents.activity` | `userId` | QM summary: evaluation count, average score, trend direction |
| 7 | `gamification.get.scorecard.by.user` | `userId` | Gamification scorecard: KPI values, points earned, vs. profile targets |

### Key Joins

```
users.get.user.details.with.full.expansion.id
  → analytics.query.user.details.activity.report.userDetails[].userId
  → coaching.get.appointments[].attendees[].id
  → learning.get.assignments[].user.id
  → quality.get.agents.activity[].user.id
  → gamification.get.scorecard.by.user (single-call fan-out)

workforce.get.management.unit.adherence
  (filter by userId after fetching management unit)
```

### Analytical Questions Answered

- How many minutes of schedule variance did this agent have this week?
- What percentage of shifts was the agent on-queue vs. scheduled to be on-queue?
- Has the agent completed all assigned training modules?
- Has the agent been coached recently? What was discussed?
- Is the agent's QM score improving, stable, or declining?
- How does the agent's gamification score compare to team average?
- Is there a pattern between coaching sessions and subsequent score improvement?

### WFM Adherence Notes

`workforce.get.management.unit.adherence` returns all agents in the management unit. After fetching,
filter to the target `userId`. The `adhere` and `actualActivityCategory` fields give the most
operationally relevant signal. For teams in multiple management units, fan out per
`managementUnitId` found via `workforce.get.management.units` filtered to the user's assigned unit.

---

## 17. AI-Assisted Conversation Review (Copilot + STA)

**Subject:** One `conversationId` with STA enabled and Agent Copilot configured  
**Use case:** A QM analyst or supervisor wants to review a conversation using all AI-generated
signals — the Agent Copilot summary, detected sentiment timeline, identified topics, and transcript
— without having to listen to the entire recording. This is the fastest path to a complete
AI-enriched picture of a single conversation.

**Core question:** *What did AI observe about this conversation — intent, sentiment, resolution, topics?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | Conditional? | What It Adds |
|------|-------------|----------|--------------|--------------|
| 1 | `conversations.get.conversation.object` | seed | Always | Participants, start/end, media type, externalTag indicator |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Always | Segment timing: IVR, ACD wait, talk, hold, ACW |
| 3 | `conversations.get.speech.text.analytics` | `conversationId` | STA enabled | STA summary: analysisStatus, overall sentiment category, topics detected |
| 4 | `speechandtextanalytics.get.conversation.summaries` | `conversationId` | Copilot enabled | AI summary: resolution type, reason for contact, follow-up required, wrap-up suggestion |
| 5 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | STA enabled | Detected topic categories with confidence scores |
| 6 | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | STA enabled | Per-utterance sentiment: agent vs. customer breakdown, phrase-level sentiment |
| 7 | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcription enabled | Pre-signed transcript URL per communication leg |
| 8 | `quality.get.evaluations.query` | `conversationId` | Optional | QM score — compare to AI sentiment for correlation |

### Conditional Step Logic

```
Step 3 runs when: mediaType = 'voice' AND speechAndTextAnalytics licence active
Step 4 runs when: step 3 returns analysisStatus = 'Success' AND Copilot configured
Step 5 runs when: step 3 returns analysisStatus = 'Success'
Step 6 runs when: step 3 returns analysisStatus = 'Success'
Step 7 runs when: step 3 returns transcriptStatus = 'Transcribed'
  → communicationId sourced from analytics.get.single.conversation.analytics
    participants[].sessions[].communicationId
```

### Analytical Questions Answered

- What did Agent Copilot summarise as the reason for contact and resolution type?
- Did the customer's sentiment improve or worsen over the course of the conversation?
- What topics were detected? Do they match the wrapup code selected by the agent?
- Is the Copilot-suggested wrapup code aligned with what the agent actually chose?
- Were there emotional escalation points? At what timestamp?
- Is the QM score consistent with the AI sentiment assessment?

---

## 18. Journey-Linked Conversation Context

**Subject:** One `conversationId` where a Journey session exists for the customer  
**Use case:** Predictive engagement or a web-to-voice handoff caused the customer interaction.
The Journey session object carries the customer's full digital footprint before contact — what
pages they visited, what actions they triggered, and what segment they belong to. This context
explains *why* the customer called when the IVR attributes don't tell the complete story.

**Core question:** *What digital journey preceded this conversation?*

### How Journey Sessions Link to Conversations

Genesys Cloud's Journey platform writes a `sessionId` into the conversation's custom attributes
or participant attributes when a web interaction transitions to a voice or messaging conversation.
Look for it in:

1. `conversations.get.conversation.customattributes` → `journey.sessionId`
2. `conversations.search.participant.attributes` → `journey.sessionId` or `predictor.sessionId`
3. `conversations.get.conversation.object` → `participants[].calls[].journeyContext.journeySession.id`

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Conversation baseline; look for `journeyContext.journeySession.id` in participants |
| 2 | `conversations.get.conversation.customattributes` | `conversationId` | Journey session ID in custom attributes if set by flow or data action |
| 3 | `conversations.search.participant.attributes` | `conversationId` | Participant-level flow variables including journey session reference |
| 4 | `journey.get.session` | `sessionId` from steps 1–3 | Full journey session: customer ID, device, segment list, referrer, duration |
| 5 | `journey.get.session.events` | `sessionId` | Event stream: page views, product views, form interactions, search terms |
| 6 *(if externalContactId set)* | `external.contacts.get.contact` | `externalContactId` | CRM contact profile matched to the journey customer |
| 7 *(if externalContactId set)* | `external.contacts.get.contact.journey.sessions` | `externalContactId` | All prior journey sessions for this customer — multi-visit history |

### Key Joins

```
conversations.get.conversation.object.participants[].calls[].journeyContext.journeySession.id
  → journey.get.session.id
  → journey.get.session.events[].session.id

external.contacts.get.contact.journey.sessions[].id
  → journey.get.session.id (for each prior session)
```

### Analytical Questions Answered

- What page was the customer on when they initiated the contact?
- Did the customer visit the pricing, checkout, or account page before calling?
- How long had the customer been on the website before calling?
- Had the customer searched for a specific product or knowledge article?
- Does the customer have a prior session history that indicates repeat escalation?
- Was a predictive engagement action map triggered for this customer?

---

## 19. Recording Governance Audit

**Subject:** Organisation-wide + reporting window  
**Use case:** A compliance officer or QM manager needs to verify that recording policies are
correctly configured, that recordings exist for conversations that should have them, and that
no unexpected retention gaps exist. This combination covers policy definition, conversation-level
recording verification, and settings confirmation.

**Core question:** *Are we recording everything we should, and are retention policies correct?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `recording.get.settings` | — | Org-wide recording settings: screen recording, consent mode, pause/resume rules |
| 2 | `recording.get.media.retention.policies` | — | Active retention policies: deletion schedules, enabled state, media type coverage |
| 3 | `routing-queues` | — | All queues — cross-reference to identify queues with retention policies applied |
| 4 | `analytics-conversation-details-query` (queueId filter, media=voice) | `queueId` | All conversations in scope — provides conversationId list for recording check |
| 5 | `conversations.get.conversation.recording.metadata` (per conversationId) | `conversationId` | Recording metadata: whether a recording was captured, duration, deletion schedule |
| 6 | `quality.get.evaluations.query` (conversationId list) | `conversationId` | Which conversations were evaluated — confirm recording existed at evaluation time |
| 7 | `audit-logs` (EntityType=Recording) | — | Audit trail: recording deletions, policy changes, access events |

### Key Joins

```
recording.get.media.retention.policies[].conditions[].queueIds[]
  → routing-queues[].id (which queues have retention policies)

analytics-conversation-details-query[].conversationId
  → conversations.get.conversation.recording.metadata[].conversationId
    (left join — missing metadata = no recording captured)

quality.get.evaluations.query[].conversationId
  → conversations.get.conversation.recording.metadata[].conversationId
    (verify recording existed when evaluation was conducted)
```

### Analytical Questions Answered

- Do all voice queues have an active retention policy?
- What percentage of handled conversations have recording metadata?
- Are any evaluated conversations missing recordings?
- When was the most recent retention policy change, and who made it?
- Are recordings being deleted earlier than policy requires?
- Are screen recordings enabled for queues that require compliance recording?

---

## 20. Extended Dataset Combination Reference Matrix

The matrix below extends the original matrix (Section 10) to include all new datasets added in
the 2026-06-02 enrichment pass. `●` = primary use, `○` = conditional/optional, blank = not used.

| Dataset Key | Conv Deep Dive | Queue Inv | Division Inv | Exec Rollup | Real-Time | Agent Inv | Teams Inv | Ext Contact | SIP Triage | Bot/IVR | QM Deep Dive | Dev & Adherence | AI Review | Journey | Rec Governance |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | ● | ● | | | | ● | ● | ● |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | ● | | | | ● | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | | | | | | ● |
| `conversations.get.conversation.customattributes` | ● | | | | | | | ● | | | | | | ● | |
| `conversations.search.participant.attributes` | ● | | | | | | | ● | | | | | | ● | |
| `quality.get.evaluations.query` | ● | ○ | | | | | ○ | | | | ● | | ○ | | ● |
| `quality.get.surveys` | ● | | | ● | | | | | | | ● | | | | |
| `quality.get.published.evaluation.forms` | | | | | | | | | | | ● | | | | |
| `quality.get.calibrations` | | | | | | | | | | | ● | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | ● | | | | ● | ● | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | ● | | | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | ● | | | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | ● | | | | | | |
| `telephony.get.trunk.metrics.by.trunk` | | | | | | | | | ● | | | | | | |
| `telephony.get.trunks` | | | | | | | | | ● | | | | | | |
| `telephony.create.edge.logs.job` | | | | | | | | | ● | | | | | | |
| `telephony.get.edges` | | | | | ● | | | | ● | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | | ● | | ● | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | | | | ● | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | | | ● | | |
| `speechandtextanalytics.get.conversation.summaries` | | | | | | | | | | | ○ | | ● | | |
| `speechandtextanalytics.get.conversation.categories` | | | | | | | | | | | ○ | | ● | | |
| `speechandtextanalytics.get.topics` | | | | ● | | | | | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | | | | | | ● |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | | | | ● | | | | | ● |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | | | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | | | | | | |
| `routing.get.all.wrapup.codes` | | | | ● | | | | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | ● | | | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | ● | | | | | ● | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | | ● | | | |
| `coaching.get.appointments` | | | ● | | | ○ | ● | | | | | ● | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | | | | | |
| `analytics.query.user.observations.real.time.status` | | ○ | | | ● | | | | | | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | ● | | | | | | ● | | | | | |
| `analytics.query.bot.aggregates` | | | | ○ | | | | | | ● | | | | | |
| `analytics.get.botflow.sessions` | | | | | | | | | | ● | | | | | |
| `flows.get.all.flows` | | | | | | | | | | ● | | | | | |
| `flows.get.flow.outcomes` | | | | | | | | | | ● | | | | | |
| `flows.get.flow.milestones` | | | | | | | | | | ● | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | ● | | | | | | |
| `architect.get.ivrs` | | | | | | | | | ● | ● | | | | | |
| `architect.get.schedules` | | | | | | | | | ● | ● | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | | ● | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | | | | | |
| `audit-logs` | | | | | | ● | | | | | | | | | ● |
| `teams.get.all.teams` | | | | | | | ● | | | | | | | | |
| `teams.get.team.members` | | | | | | | ● | | | | | | | | |
| `gamification.get.status` | | | | ○ | | | ○ | | | | | | | | |
| `gamification.get.profiles` | | | | ○ | | | ○ | | | | | | | | |
| `gamification.get.scorecard.by.user` | | | ○ | | | ○ | ● | | | | | ● | | | |
| `external.contacts.get.contact` | | | | | | | | ● | | | | | | ● | |
| `external.contacts.get.organization` | | | | | | | | ● | | | | | | | |
| `external.contacts.get.contact.journey.sessions` | | | | | | | | ● | | | | | | ● | |
| `journey.get.session` | | | | | | | | ● | | | | | | ● | |
| `journey.get.session.events` | | | | | | | | | | | | | | ● | |
| `journey.get.action.maps` | | | | ○ | | | | | | | | | | ● | |
| `learning.get.modules` | | | | | | | ○ | | | | | ○ | | | |
| `learning.get.assignments` | | | | | | | ● | | | | | ● | | | |
| `groups.get.all.groups` | | | ○ | | | | | | | | | | | | |
| `groups.get.group.members` | | | ○ | | | | | | | | | | | | |
| `quality.get.calibrations` | | | | | | | | | | | ● | | | | |
| `recording.get.media.retention.policies` | | | | | | | | | | | | | | | ● |
| `recording.get.settings` | | | | | | | | | | | | | | | ● |
| `workforce.get.management.units` | | | | | | | | | | | | ● | | | |
| `workforce.get.management.unit.users` | | | | | | | | | | | | ● | | | |
| `workforce.get.management.unit.adherence` | | | | | | | | | | | | ● | | | |
| `routing.get.skill.groups` | | | | | | ○ | | | | | | | | | |

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
| `nBotSessions` | Bot flow sessions initiated | Bot volume |
| `nBotIntents` | Bot intents matched | Bot interaction depth |
| `nBotSuccesses` | Bot sessions with successful outcome | Self-service success |
| `nBotFailures` | Bot sessions that failed or errored | Bot fault rate |
| `tBotSession` | Total bot session duration | Bot AHT equivalent |
| `nFlow` | Flow executions (Architect flows) | IVR/flow volume |
| `nFlowOutcome` | Flow executions with a recorded outcome | Outcome coverage |
| `nFlowOutcomeFailed` | Flow executions with a failed outcome | IVR failure rate |
| `nFlowMilestone` | Flow milestone events recorded | Progress tracking |

---

## Appendix: Investigation Entry-Point Quick Reference

Use this table to choose the right starting point when beginning an investigation.

| You know… | Start with | Then fan out to |
|---|---|---|
| A specific `conversationId` | `conversations.get.conversation.object` | Analytics, recordings, SIP trace, STA, evaluations |
| A queue name/ID | `routing.get.single.queue.config` | Queue members, SLA aggregates, abandons, wrapup |
| An agent name/email | `users.search.users.by.name.or.email` → `userId` | Agent investigation steps, skills, presences |
| A division name | `authorization.get.all.divisions` → `divisionId` | Division investigation: queues, agents, performance |
| A team name | `teams.get.all.teams` → `teamId` | Teams investigation: members, performance, development |
| A bot/IVR problem | `flows.get.all.flows` → `flowId` | Flow aggregates, bot sessions, IVR config |
| A SIP/audio problem | `conversations.get.conversation.object` → `edgeId` | SIP trace, edge metrics, trunk metrics |
| A customer complaint | `conversations.get.conversation.object` → `externalContactId` | External contact profile, journey sessions |
| A recording gap | `recording.get.settings` + `recording.get.media.retention.policies` | Queue list, conversation recording metadata |
| An agent performance concern | `users.get.user.details.with.full.expansion` | Agent investigation + development & adherence |
| Executive period report | `routing-queues` (all active) | All aggregate steps (SLA, volume, AHT, abandon, QM) |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
