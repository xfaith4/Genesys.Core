# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-03  
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
10. [WFM Schedule Adherence Integration](#10-wfm-schedule-adherence-integration)
11. [Campaign Investigation](#11-campaign-investigation)
12. [Bot & Self-Service Containment](#12-bot--self-service-containment)
13. [Quality Program Health Audit](#13-quality-program-health-audit)
14. [Agent Development & Learning](#14-agent-development--learning)
15. [Skill-Based Routing Efficiency](#15-skill-based-routing-efficiency)
16. [Voice Engineer — Edge Log Collection](#16-voice-engineer--edge-log-collection)
17. [Voice Engineer — Multi-Trunk Comparison](#17-voice-engineer--multi-trunk-comparison)
18. [Voice Engineer — WebRTC & Softphone Audit](#18-voice-engineer--webrtc--softphone-audit)
19. [Dataset Combination Reference Matrix](#19-dataset-combination-reference-matrix)

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

## 10. WFM Schedule Adherence Integration

**Subject:** Agent (`userId`) or Management Unit (`managementUnitId`) + point-in-time  
**Use case:** A WFM analyst or supervisor needs to correlate an agent's actual behaviour (presence, routing status, conversation volume) against their scheduled activity to compute adherence and flag out-of-adherence events. Divisions serve as grouping boundaries that can span multiple management units.

**Core question:** *Is this agent working according to their schedule, and how does out-of-adherence time correlate with performance gaps?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | Identity, email, state, manager |
| 2 | `workforce.get.agent.management.unit` | `userId` | `managementUnitId` and `businessUnitId` — required to pull schedule and adherence |
| 3 | `workforce.get.management.unit.adherence` | `managementUnitId` | All agents' adherence state, scheduled activity category, impact, out-of-adherence duration |
| 4 | `analytics.query.user.details.activity.report` | `userId` | Login/logout/presence event timeline for the window |
| 5 | `analytics.query.user.aggregates.login.activity` | `userId` | Time-in-state aggregates: tOnQueueTime, tOffQueueTime, tIdleTime |
| 6 | `analytics.query.user.aggregates.performance.metrics` | `userId` | nConnected, tHandle during the window — production output correlator |

### Key Joins

```
users.get.user.details.with.full.expansion.id
  → workforce.get.agent.management.unit.agentId (resolve managementUnitId)
  → workforce.get.management.unit.adherence[].userId (filter by userId)

workforce.get.management.unit.adherence[].userId
  → analytics.query.user.aggregates.login.activity[].group.userId
  → analytics.query.user.aggregates.performance.metrics[].group.userId
```

### Analytical Questions Answered

- Was the agent in their scheduled activity at the time of a reported incident?
- How much of their shift was spent out of adherence (off-queue when scheduled on-queue)?
- Does out-of-adherence time correlate with elevated abandon rates in the queues they serve?
- Which agents in a management unit have the highest out-of-adherence duration this week?

### Division Note

Divisions span queues. To investigate an entire division's adherence:
1. Use `authorization.list.division.queues` to enumerate queue IDs.
2. Pull `routing-queue-members` for each queue to get userId lists.
3. Look up each user's management unit via `workforce.get.agent.management.unit`.
4. Fan out `workforce.get.management.unit.adherence` per management unit.

---

## 11. Campaign Investigation

**Subject:** One `campaignId` + time window  
**Use case:** An outbound operations manager needs to diagnose why a campaign is performing below target — too few connects, high abandons due to pacing, unexpected wrapup distributions, or agents receiving too many unanswered dials.

**Core question:** *Why is this campaign underperforming, and what changed?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Name, status, dialingMode, queueId, contactListId, abandonRate threshold, callerIdNumber |
| 2 | `outbound.get.contact.lists` | `contactListId` | Contact list name, column schema, and total size for coverage reconciliation |
| 3 | `routing.get.single.queue.config` | `queueId` | Queue receiving answered calls — confirms routing target is correct |
| 4 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Live pacing diagnostics — linesPerAgent, health indicators, current error state |
| 5 | `outbound.get.events` | `campaignId` | Dialer event log — call dispositions, contact attempts, agent assignments |
| 6 | `audit-logs` (EntityType=Campaign) | `campaignId` | Configuration changes made to the campaign during the window |
| 7 | `analytics-conversation-details-query` | `campaignId` | Analytics rows for conversations this campaign generated — talk time, wrapup, answer state |

### Key Joins

```
outbound.get.campaigns.id (campaignId)
  → outbound.get.campaign.diagnostics.summary.campaignId
  → outbound.get.events[].campaignId
  → analytics-conversation-details-query[].conversationId (left join — answered calls only)

outbound.get.campaigns.queueId
  → routing.get.single.queue.config.id

outbound.get.campaigns.contactListId
  → outbound.get.contact.lists.id
```

### Analytical Questions Answered

- Is the pacing rate appropriate for current agent staffing (linesPerAgent diagnostic)?
- What percentage of dial attempts resulted in a connect vs. answer machine / busy / no answer?
- Did anyone change campaign settings (abandon threshold, caller ID, dial rate) during the window?
- What is the wrapup code distribution for connected calls — is right-party contact rate acceptable?

---

## 12. Bot & Self-Service Containment

**Subject:** Organisation or specific flows + time window  
**Use case:** A digital transformation leader or VP of Operations needs to measure how effectively bot and IVR flows are handling contacts without escalating to live agents. This is the ROI metric for AI investment.

**Core question:** *What percentage of contacts is the bot resolving, and which flows have the highest escalation rates?*

### Dataset Steps (ordered by reporting layer)

#### Layer 1 — Bot Volume
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.bot.aggregates` | `flowId`, `queueId`, daily | nBotSessions, nBotHandled, nBotEscalated, tBotSession |

#### Layer 2 — Flow Reference
| Dataset Key | Role | What It Adds |
|-------------|------|--------------|
| `flows.get.all.flows` | reference | Flow names for label resolution |
| `flows.get.flow.outcomes` | reference | Outcome labels — decode self-service vs. escalation exit paths |

#### Layer 3 — IVR/Flow Execution
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.flow.aggregates.execution.metrics` | `flowId`, daily | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone |

#### Layer 4 — Queue Impact Correlation
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.conversation.aggregates.queue.performance` | `queueId`, daily | nOffered, nConnected — compare escalation volume to queue volume |

### Derived Metrics

```
containmentRate%    = 1 − (nBotEscalated / nBotSessions) × 100
escalationRate%     = nBotEscalated / nBotSessions × 100
avgBotSessionMins   = tBotSession / nBotSessions / 60
flowSuccessRate%    = nFlowOutcome / nFlow × 100
```

### Analytical Questions Answered

- What is the overall bot containment rate across all flows this period?
- Which specific flows have escalation rates above the target threshold?
- Is the self-service containment rate improving or declining over time?
- For flows that fail (`nFlowOutcomeFailed`), which milestone does execution reach before failure?

### Executive Presentation

Containment funnel: total bot sessions → self-served → escalated. Daily trend line with target containment rate reference. Per-flow escalation heat map.

---

## 13. Quality Program Health Audit

**Subject:** Organisation-wide or queue-scoped + reporting window  
**Use case:** A Quality Manager or Contact Centre Director needs to understand how well the QM program is running — evaluation coverage rate, score trends, evaluator consistency, and whether form scoring aligns with business intent.

**Core question:** *Is the QM program evaluating the right calls, at the right frequency, with fair and consistent scoring?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `quality.get.published.evaluation.forms` | seed | All active evaluation forms — names, question counts, critical items |
| 2 | `quality.get.evaluation.form.detail` | `formId` | Full form definition: question weights, answer categories, critical-item flags |
| 3 | `quality.get.evaluations.query` | `conversationId` | All evaluations in window — score, evaluator, form used, calibration status, agent |
| 4 | `quality.get.agents.activity` | `userId` | Per-agent summary: evalCount, avgScore, highScore, lowScore, evaluator breakdown |
| 5 | `analytics-conversation-details-query` | `conversationId` | Total connected conversations — denominator for coverage rate |
| 6 | `quality.get.surveys` | `conversationId` | Customer survey results — correlate CSAT with evaluation score |

### Key Joins

```
quality.get.published.evaluation.forms[].id
  → quality.get.evaluation.form.detail.id (full question detail)
  → quality.get.evaluations.query[].evaluationForm.id (which form was used per evaluation)

quality.get.evaluations.query[].agent.id
  → quality.get.agents.activity[].user.id

quality.get.evaluations.query[].conversationId
  → analytics-conversation-details-query[].conversationId (left join — not all conversations are evaluated)
  → quality.get.surveys[].conversationId (left join — not all have surveys)
```

### Derived Metrics

```
evaluationCoverageRate%  = evalCount / nConnected × 100
calibrationComplianceRate% = calibratedEvals / totalEvals × 100
criticalItemFailRate%    = criticalItemFailed / totalEvals × 100
evaluatorVariance        = STDEV(scoreByEvaluator) for same agent/form combination
csatVsQmCorrelation      = CORR(evaluationScore, surveyScore) per conversationId join
```

### Analytical Questions Answered

- Are evaluations distributed fairly across agents, or are the same agents evaluated repeatedly?
- Which evaluation form questions have the highest failure rates (systemic training gap)?
- Is there evaluator score variance for the same form — calibration issue?
- Do high QM scores correlate with high CSAT scores? If not, the form may not measure what customers care about.

---

## 14. Agent Development & Learning

**Subject:** Agent (`userId`) or cohort (division/management unit) + time window  
**Use case:** A Learning & Development manager, QM lead, or operations director needs to measure whether coaching and training investments are translating into agent performance improvements.

**Core question:** *Are evaluated, coached, and trained agents improving, and who needs intervention?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `quality.get.agents.activity` | seed → `userId` | evalCount, avgScore, criticalItemFailCount per agent — quality baseline |
| 2 | `coaching.get.appointments` | `userId` | Coaching sessions: dates, status, facilitator, topic |
| 3 | `learning.get.modules` | `moduleId` (reference) | Module catalog — names for label resolution |
| 4 | `learning.get.user.assignments` | `userId` | Per-agent module assignments: completion status, score, due date |
| 5 | `analytics.query.user.aggregates.performance.metrics` | `userId` | nConnected, tHandle, tTalk, tAcw — handle time trend pre/post development |
| 6 | `analytics.query.user.aggregates.login.activity` | `userId` | tOnQueueTime — confirms agents are available to be coached |

### Key Joins

```
quality.get.agents.activity[].user.id
  → coaching.get.appointments[].attendees[].id
  → learning.get.user.assignments[].user.id
  → analytics.query.user.aggregates.performance.metrics[].group.userId

learning.get.user.assignments[].module.id
  → learning.get.modules[].id (label resolution)
```

### Analytical Questions Answered

- Which agents have been evaluated but not coached this period?
- Is there a measurable handle time improvement after coaching or learning completion?
- Which learning modules have the lowest completion rates — priority for manager follow-up?
- For agents with critical item failures, has a coaching session been scheduled?

### Executive Presentation

Agent development funnel: evaluated → coached → trained → improved. Score trajectory chart for coached vs. uncoached cohorts over the reporting period.

---

## 15. Skill-Based Routing Efficiency

**Subject:** Organisation or division + time window  
**Use case:** A routing architect or WFM analyst suspects that skill-based routing is causing extended wait times or SLA misses due to insufficient agent coverage for specific skill combinations.

**Core question:** *Are the right skills staffed in sufficient depth for the volume demanding them?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.all.routing.skills` | reference | Org-wide skill catalog — skill IDs and names |
| 2 | `routing.get.skill.groups` | reference | Skill group definitions with member counts and division assignments |
| 3 | `routing-queues` | `queueId` | Queue skill evaluation mode (`BestAvailableSkill` vs `Standard`) |
| 4 | `users` (expand=routingSkills) | `userId` | Agent skill assignments and proficiency levels |
| 5 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | nOffered, nConnected, tAnswered — volume and speed of answer per queue |
| 6 | `analytics.query.queue.aggregates.service.level` | `queueId` | oServiceLevel, nOverSla — SLA miss pattern by queue |

### Key Joins

```
routing.get.skill.groups[].id
  → users[].routingSkills[].skill.id (coverage count per skill group)

routing-queues[].id
  → analytics.query.conversation.aggregates.queue.performance[].group.queueId
  → analytics.query.queue.aggregates.service.level[].group.queueId

SLA miss (nOverSla > 0) on a BestAvailableSkill queue
  → cross-reference agent skill coverage for that queue's required skills
```

### Analytical Questions Answered

- Which queues using skill-based routing are missing SLA targets?
- For those queues, how many agents have the required skills at sufficient proficiency?
- Which skills have fewer than N qualified agents — single-point-of-failure risk?
- Are skill groups sized appropriately for current contact volume?

### Executive Presentation

Skill coverage heat map: skill rows × queue columns, coloured by SLA achievement rate. Red = coverage gap, Green = adequate coverage. Sort skills by SLA impact descending.

---

## 16. Voice Engineer — Edge Log Collection

**Subject:** One `edgeId` + time window covering the affected calls  
**Use case:** A voice engineer has identified that call quality issues (audio degradation, one-way audio, unexpected disconnects) are concentrated on a specific Edge appliance and needs the raw SIP and media logs for carrier escalation or deep packet analysis.

**Core question:** *What do the Edge logs reveal about call setup, media path, and teardown during the affected window?*

### Dataset Steps (async job sequence)

| Step | Dataset Key | Action |
|------|-------------|--------|
| 1 | `telephony.get.edges` | List all Edges; identify the `edgeId` handling affected calls |
| 2 | `telephony.get.edge.performance.metrics` | Capture CPU%, memory%, activeCalls baseline before triggering collection |
| 3 | `telephony.create.edge.logs.job` | Submit log collection job — returns `jobId` |
| 4 | `telephony.get.edge.logs.job` | Poll until `state = FULFILLED` (typically 60–300 s) |
| 5 | `telephony.request.edge.logs.job.upload` | Request upload of selected files — returns signed download URL |

### Diagnostic Signals from Edge Logs

| Signal | Interpretation |
|--------|---------------|
| TCP connection timeout in SIP log | Network path issue between Edge and PSTN gateway |
| RTCP packet loss > 5% in media log | Network quality degradation on media path |
| Repeated 401 Unauthorized in auth log | Edge certificate or SIP credentials need renewal |
| Job state `FAILED` | Edge offline or log service degraded — verify Edge connectivity first |
| Log file size 0 bytes | No calls in the specified window or log retention cleared |

### When to Use vs. SIP Trace

`telephony.get.sip.messages.for.conversation` (catalog step 8 in Conversation Deep Dive) returns the signaling for a single call from the Genesys platform perspective. Edge logs provide the raw SIP and media data from the Edge appliance itself — use Edge logs when:
- SIP trace shows unexpected media outcomes and you need to verify the Edge-side view
- Multiple calls share the same fault pattern and a carrier escalation ticket is needed
- Audio degradation is intermittent and not captured in analytics metrics

---

## 17. Voice Engineer — Multi-Trunk Comparison

**Subject:** All SIP trunks in the organisation (no subject parameter — full inventory)  
**Use case:** A voice engineer or NOC analyst has received reports of call quality issues affecting only certain inbound numbers (DIDs). Suspicion is that one trunk or carrier circuit is degraded while others are healthy.

**Core question:** *Which trunk is causing problems, and is it degraded or at capacity?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `telephony.get.trunks` | seed | All trunk definitions — name, state, inServiceState, maxConcurrentCalls, assignedEdge |
| 2 | `telephony.get.trunk.metrics.summary` | `trunkId` | currentCalls, maxConcurrentCalls, errorCount, utilisation% |
| 3 | `telephony.get.edges` | `edgeId` | Edge registration status — confirm Edge handling the trunk is healthy |
| 4 | `conversations.get.active.calls` | — | Active call count for cross-referencing trunk utilisation |
| 5 | `alerting.get.alerts` | — | Currently firing alerts — check for active trunk threshold breaches |

### Key Joins

```
telephony.get.trunks[].id
  → telephony.get.trunk.metrics.summary[].trunkId (utilisation overlay)

telephony.get.trunks[].edge.id
  → telephony.get.edges[].id (Edge health for that trunk)
```

### Diagnostic Signals

| Signal | Interpretation |
|--------|---------------|
| Trunk A `errorCount` >> Trunk B | Provider circuit fault on Trunk A — escalate to carrier |
| All trunks `currentCalls / maxConcurrentCalls > 0.80` simultaneously | Org-level capacity event |
| Trunk `inServiceState = INACTIVE` | Circuit not provisioned or provider-side deactivation |
| Active calls disproportionately on one trunk | Load balancing misconfiguration |
| Edge with zero active trunks but non-zero active calls | Media bypass or IP routing anomaly |

---

## 18. Voice Engineer — WebRTC & Softphone Audit

**Subject:** Organisation-wide or specific queue (no fixed subject — full inventory)  
**Use case:** A voice engineer has received reports of agents experiencing audio issues, calls not ringing on softphones, or intermittent disconnections that are correlated with WebRTC softphone usage rather than a carrier issue.

**Core question:** *Which stations are failing to register, and is there a pattern pointing to network, policy, or configuration issues?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `stations.get.stations` | seed | All station registrations — type, registered flag, line appearances, associated user |
| 2 | `users` | `userId` | Agent identity — name, email, station assignment, webRtcRequireManagedBrowser flag |
| 3 | `analytics.query.user.observations.real.time.status` | `userId` | Live routing status — cross-reference `registered=false` stations against agent routing status |
| 4 | `telephony.get.edges` | `edgeId` | Edge health — CPU/memory on the Edge nearest the affected agents |

### Diagnostic Signals

| Signal | Interpretation |
|--------|---------------|
| `station.registered = false` for an active-shift agent | Softphone not connected — check SIP ALG or firewall blocking WebRTC |
| Multiple stations registered for one `userId` | Duplicate session — stale registration not released on prior logout |
| `station.type = WEBRTC` but `user.station.webRtcRequireManagedBrowser = false` | Unmanaged browser WebRTC may be blocked by org policy |
| `station.lineAppearances.registered = false` but agent `routingStatus = IDLE` | Ghost agent — calls will fail to alert the agent's device |
| Edge nearest affected stations has CPU > 80% | Media processing bottleneck causing audio degradation |

### Follow-Up Datasets

- `audit-logs` (filter `service=Station`) — find recent station assignment or policy changes
- `alerting.get.alerts` — check for active station or WebRTC alerts
- `telephony.get.edge.performance.metrics` — detailed Edge metrics if elevated CPU is suspected

---

## 19. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conv. Deep Dive | Queue Invest. | Division Invest. | Exec. Rollup | Real-Time | Agent Invest. | Campaign | BYOI Conv. | Bot/Self-Svc | Quality Audit | Dev & Learning | WFM Adherence |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | ● | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | ● | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | ● | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | ● | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | | | ○ | | | | |
| `conversations.get.conversation.participant.wrapup` | ○ | | | | | | | | | | | |
| `conversations.get.call.detail` | ○ | | | | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | ○ | | ● | | |
| `quality.get.surveys` | ● | | | ● | | | | | | ● | | |
| `quality.get.conversation.surveys` | ○ | | | | | | | | | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | ● | ● | |
| `quality.get.published.evaluation.forms` | | | | | | | | | | ● | | |
| `quality.get.evaluation.form.detail` | | | | | | | | | | ● | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | ○ | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | ○ | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | | | | | | | |
| `routing.get.all.routing.skills` | | | | | | ● | | | | | | |
| `routing.get.skill.groups` | | | | | | | | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | | | |
| `routing-queues` | | | | | | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ● | | | ● | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | ● | | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | ● | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | ● | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.by.division` | | | ● | | | | | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | | | |
| `analytics.query.bot.aggregates` | | | | ● | | | | | ● | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | | | ○ | ● |
| `analytics.query.user.aggregates.performance.metrics` | | | | | | ● | | | | | ● | ● |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | | | | ● |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | | | ● | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | | | ○ |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | | | |
| `flows.get.all.flows` | | | | | | | | | ● | | | |
| `flows.get.flow.outcomes` | | | | | | | | | ● | | | |
| `flows.get.flow.milestones` | | | | | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | | |
| `authorization.get.division.grants` | | | ○ | | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | | ● |
| `users.get.user.routing.skills` | | | | | | ● | | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | | |
| `users` | | | | | | | | | | | | ○ |
| `stations.get.stations` | | | | | | | | | | | | |
| `externalcontacts.get.contact` | | | | | | | | ● | | | | |
| `externalcontacts.search.contacts` | | | | | | | | ○ | | | | |
| `outbound.get.campaigns` | | | | | | | ● | | | | | |
| `outbound.get.contact.lists` | | | | | | | ● | | | | | |
| `outbound.get.campaign.diagnostics.summary` | | | | | | | ● | | | | | |
| `outbound.get.events` | | | | | | | ● | | | | | |
| `coaching.get.appointments` | | | ● | | | ○ | | | | | ● | |
| `learning.get.modules` | | | | | | | | | | | ● | |
| `learning.get.user.assignments` | | | | | | | | | | | ● | |
| `workforce.get.management.units` | | | | | | | | | | | | ● |
| `workforce.get.management.unit.users` | | | | | | | | | | | | ● |
| `workforce.get.management.unit.adherence` | | | | | | | | | | | | ● |
| `workforce.get.agent.management.unit` | | | | | | ○ | | | | | | ● |
| `workforce.get.adherence.bulk` | | | | | | ○ | | | | | | ● |
| `audit-logs` | | | | | | ● | ● | | | | | |
| `telephony.get.edges` | | | | | ● | | | | | | | |
| `telephony.get.trunks` | | | | | ● | | | | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | | | |
| `telephony.create.edge.logs.job` | | | | | | | | | | | | |
| `telephony.get.edge.logs.job` | | | | | | | | | | | | |
| `telephony.request.edge.logs.job.upload` | | | | | | | | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | | | |
| `alerting.get.rules` | | | | | ○ | | | | | | | |

> Edge log collection datasets (`telephony.create.edge.logs.job`, `telephony.get.edge.logs.job`, `telephony.request.edge.logs.job.upload`) and WebRTC audit datasets (`stations.get.stations`) are used exclusively in the Voice Engineer playbooks documented in sections 16–18.
>
> Skill-Based Routing Efficiency datasets (`routing.get.skill.groups`, `routing-queues`) are used in the skill investigation pattern (section 15) and are omitted from the matrix columns above for space; see section 15 for their full join plan.

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
| `nBotSessions` | Bot or virtual agent sessions initiated | Self-service volume |
| `nBotHandled` | Bot sessions resolved without escalation | Containment count |
| `nBotEscalated` | Bot sessions that escalated to a live agent | Escalation count |
| `tBotSession` | Total bot session duration | Avg bot handle time |
| `nFlowOutcomeFailed` | Architect flows that exited via a failure outcome | IVR error rate |
| `nFlowMilestone` | Flow milestone events reached | Self-service completion depth |
| `adherencePct` | Agent schedule adherence percentage | WFM compliance |
| `estimatedWaitTimeSecs` | Forecasted caller wait in seconds | Real-time EWT |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
