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
10. [AI Copilot and S&TA Deep Enrichment](#10-ai-copilot-and-sta-deep-enrichment)
11. [External Contact History (BYOI Extended)](#11-external-contact-history-byoi-extended)
12. [WFM Adherence Cross-Reference](#12-wfm-adherence-cross-reference)
13. [Division Grants and Access Audit](#13-division-grants-and-access-audit)
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
| wfmUnit | `workforce.get.agent.management.unit` | `userId` | WFM management unit membership — enables adherence lookup |
| adherence | `workforce.get.adherence.bulk` | `managementUnitId` | Live schedule adherence: scheduled vs. actual state, impact score |

**Trigger conditions:** `currentStatus` and `activeConversations` steps are conditional on the
agent being in an active state at investigation time. `coaching`, `wfmUnit`, and `adherence` steps
are conditional on WFM being licensed and the agent being scheduled in a management unit.

---

## 8. Conversation Investigation Extensions (Release 1.3)

The existing Conversation Investigation (`Get-GenesysConversationInvestigation`) covers 8 steps.
These additional datasets complete the deep-dive picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| analyticsDetail | `analytics.get.single.conversation.analytics` | `conversationId` | Per-segment timing (IVR, ACD wait, talk, hold, ACW) — replaces the query-based analytics step |
| callDetail | `conversations.get.call.detail` | `conversationId` | Voice-specific call object: codec, muted/held state, DNIS routing path (voice only) |
| sipTrace | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace (voice only, conditional) |
| sentimentTimeline | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-utterance sentiment (STA enabled only, conditional) |
| staCategories | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic/category classifications with compliance flags (STA enabled only) |
| staSummaries | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | AI S&TA summaries per communication leg (STA enabled only) |
| copilotSummaries | `conversations.get.conversation.summaries` | `conversationId` | Agent Assist Copilot summaries — reason for contact, resolution, follow-up (Copilot licence) |
| customAttributes | `conversations.get.conversation.customattributes` | `conversationId` | IVR/Architect custom attribute payload |
| participantAttributes | `conversations.search.participant.attributes` | `conversationId` | Participant-level flow variables |
| transcriptUrl | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcript download URL (transcription enabled only) |
| conversationSurvey | `quality.get.conversation.surveys` | `conversationId` | Single-conversation CSAT/NPS — direct pivot, no filter needed |

**Conditional steps:** `callDetail` and `sipTrace` run only when `conversations.get.conversation.object.participants[].calls` is
non-empty (voice conversation). `staCategories`, `staSummaries`, and `sentimentTimeline` run only when `conversations.get.speech.text.analytics`
returns `speechAndTextAnalyticsConversation.analysisStatus = "Success"`. `copilotSummaries` runs only when the Agent Assist Copilot product is licensed.

---

## 9. Queue Investigation Extensions (Release 1.3)

The existing Queue Investigation (`Get-GenesysQueueInvestigation`) covers 6 steps. These additions
complete the picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| queueConfig | `routing.get.single.queue.config` | `queueId` | Full queue config (replaces/enriches the routing-queues list step) |
| estimatedWaitTime | `routing.get.queue.estimated.wait.time` | `queueId` | Real-time EWT across all media types — immediate intervention trigger |
| wrapupLabels | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Human-readable labels for the wrapup distribution step |
| transfers | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer rate and type breakdown |
| wrapupDistribution | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Wrapup code frequencies (join wrapupLabels for labels) |
| conversationDetail | `analytics-conversation-details-query` (queueId filter) | `conversationId` | Individual conversations for case-level review |

**EWT note:** `routing.get.queue.estimated.wait.time` is a point-in-time endpoint — it returns current
EWT and should be polled alongside `analytics.query.queue.observations.real.time.stats` for a complete
real-time queue health view. When EWT exceeds the queue's SLA target, it is the primary trigger for
supervisor intervention (pulling agents from training, offline activity, or lower-priority queues).

---

---

## 10. AI Copilot and S&TA Deep Enrichment

**Subject:** One `conversationId`  
**Use case:** A QM analyst or supervisor needs to assess conversation quality without listening to the full recording — using AI-generated summaries, topic categories, and sentiment scores to triage which calls need evaluation attention. Also used in post-call coaching preparation.

**Core question:** *What did the AI understand about this conversation, and does it flag a quality or compliance risk?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.speech.text.analytics` | seed → `conversationId` | Top-level S&TA scores: agent/customer sentiment, overtalk %, silence % |
| 2 | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Compliance and topic categories with confidence scores — compliance risk flag, escalation topic, dead-air |
| 3 | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-utterance sentiment timeline — pinpoints the moment CX degraded |
| 4 | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | AI-generated summary per communication leg — reason for contact, resolution, follow-up action |
| 5 | `conversations.get.conversation.summaries` | `conversationId` | Agent Assist Copilot summary — the AI-composed post-call wrap that the agent saw (Copilot licence required) |
| 6 *(conditional)* | `quality.get.evaluations.query` | `conversationId` | If a QM evaluation exists, compare AI scores to human evaluator scores for calibration |

### Key Joins

```
conversations.get.speech.text.analytics.conversationId
  → speechandtextanalytics.get.conversation.categories.conversationId
  → speech.and.text.analytics.get.sentiment.for.conversation.conversationId
  → speechandtextanalytics.get.conversation.summaries.detail.conversationId

conversations.get.speech.text.analytics.analysisStatus
  → guard condition: skip steps 2–4 if analysisStatus != "Success"

conversations.get.conversation.summaries.summaryId
  → (optional) compare Copilot vs. S&TA narrative for consistency
```

### Analytical Questions Answered

- Was this conversation flagged with a compliance risk category (e.g. regulatory language, hostile language)?
- What was the customer sentiment at the point of transfer or escalation?
- What did the AI summarise as the reason for contact and resolution? Does it match the wrapup code?
- Did the agent and customer sentiment diverge? (Agent calm, customer escalating = coaching opportunity)
- Did the Copilot suggest a follow-up action? Was a task created?

### Executive Metric Contribution

| Metric | Source Dataset |
|--------|---------------|
| `avgCustomerSentimentScore` | `conversations.get.speech.text.analytics` |
| `complianceCategoryFlagRate%` | `speechandtextanalytics.get.conversation.categories` |
| `aiSummaryCoverageRate%` | `speechandtextanalytics.get.conversation.summaries.detail` |
| `copilotAdoptionRate%` | `conversations.get.conversation.summaries` |

---

## 11. External Contact History (BYOI Extended)

**Subject:** One `externalContactId` (derived from a BYOI conversation)  
**Use case:** A complaint handler or CRM administrator needs to view all interactions Genesys has handled for a specific external contact — understanding the full service history before escalating or resolving the case. This is the cross-conversation view for BYOI environments.

**Core question:** *What is the service history for the customer behind this external contact ID?*

### How to Arrive at This Investigation

From the standard Conversation Investigation, `conversations.get.conversation.object` returns:

```json
{
  "participants": [
    {
      "purpose": "customer",
      "externalContactId": "<id>",
      "externalOrganizationId": "<org-id>"
    }
  ]
}
```

A non-null `externalContactId` is the trigger for this investigation.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `externalcontacts.get.contact` | seed → `externalContactId` | Contact name, organisation, phone, email, and CRM custom fields |
| 2 | `analytics-conversation-details-query` (filter by `externalContactId`) | `externalContactId` | All conversations linked to this external contact in the window |
| 3 | `quality.get.evaluations.query` (filter by `conversationId` list from step 2) | `conversationId` | Evaluation scores across the contact's conversation history |
| 4 | `quality.get.surveys` (filter by `conversationId` list) | `conversationId` | CSAT/NPS across the contact history — trend toward satisfaction or escalation? |
| 5 *(voice only)* | `analytics.get.single.conversation.analytics` | `conversationId` (per conversation) | Per-conversation timing breakdown for each voice interaction |

### Key Joins

```
externalcontacts.get.contact.id
  → analytics-conversation-details-query[].participants[].externalContactId

analytics-conversation-details-query[].conversationId
  → quality.get.evaluations.query[].conversationId (left join)
  → quality.get.surveys[].conversationId (left join)
```

### Analytical Questions Answered

- How many times has this customer contacted us? Over what span of time?
- Has the customer escalated before? Which queues did they reach?
- Is the CSAT trend improving or declining for this contact?
- What wrapup codes appear in this contact's history? (Patterns indicate unresolved issues)
- Was this customer ever evaluated? What was their evaluator's verdict on the agent who handled them?

### Notes

- `externalcontacts.get.contact` returns current CRM state, not historical. For BYOI environments where contact records can be updated, run this step first and store the snapshot.
- The `externalcontacts-contact-enrichment` redaction profile strips personal address and social fields not required for investigation.
- If `externalOrganizationId` is non-null, follow up with the external organisation record to understand business-account context.

---

## 12. WFM Adherence Cross-Reference

**Subject:** One `userId` (agent) or one `managementUnitId`  
**Use case:** A workforce analyst or operations manager needs to understand whether an off-queue pattern in the analytics data is explained by scheduled activity — was the agent genuinely on a planned break or training session, or were they non-adherent?

**Core question:** *Is the agent's off-queue time explained by their WFM schedule, or is it unplanned?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.agent.management.unit` | seed → `userId` | The agent's WFM management unit ID — required before adherence lookup |
| 2 | `workforce.get.management.unit.users` | `managementUnitId` | All agents in the unit — confirm this agent is scheduled in this MU |
| 3 | `workforce.get.adherence.bulk` | `managementUnitId` | Live adherence state for all agents in the unit — scheduled activity vs. actual state |
| 4 | `analytics.query.user.aggregates.login.activity` | `userId` | Historical on/off-queue time — correlate with adherence snapshot |
| 5 | `analytics.query.user.details.activity.report` | `userId` | Full presence event timeline — exact timestamps for each state change |

### Key Joins

```
workforce.get.agent.management.unit.managementUnit.id
  → workforce.get.adherence.bulk (filter by managementUnitId)
  → workforce.get.management.unit.users (confirm agent roster)

workforce.get.adherence.bulk[].userId
  → analytics.query.user.aggregates.login.activity[].userId

analytics.query.user.details.activity.report[].userId
  → (overlay presence events with scheduled activity windows for variance calculation)
```

### Analytical Questions Answered

- Was the agent's off-queue time on a scheduled break, training, or meeting? (adherence state = In Adherence)
- Was the off-queue time unplanned? (adherence state = Out Of Adherence + no schedule activity)
- What is the agent's adherence percentage for the investigation window?
- Is this agent consistently non-adherent during a particular time of day or day of week?
- Compared to the management unit average, is this agent an outlier in on-queue time?

### Division-Level Adherence Rollup

To roll adherence up to division level:
1. Use `authorization.list.division.queues` to enumerate queues.
2. Use `routing-queue-members` to get agent IDs per queue.
3. Fan out `workforce.get.agent.management.unit` per agent.
4. Aggregate `workforce.get.adherence.bulk` results across management units in the division.

### Executive Metric Contribution

| Metric | Computed From |
|--------|--------------|
| `adherencePct%` | `workforce.get.adherence.bulk[].adherencePct` |
| `scheduleVarianceMinutes` | adherence impact + login activity overlay |
| `occupancyPct = tInteracting / tOnQueue` | `analytics.query.user.aggregates.login.activity` |

---

## 13. Division Grants and Access Audit

**Subject:** One `divisionId`  
**Use case:** A security administrator or compliance officer needs to audit who has access to a business unit's resources — queues, recordings, evaluations. This is often required after a data access incident or as part of periodic access reviews.

**Core question:** *Who has what permissions in this division, and is the access appropriate?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `authorization.get.single.division` | seed → `divisionId` | Division name and home-division flag |
| 2 | `authorization.get.division.grants` | `divisionId` | All subjects (users/roles/groups) with permissions in this division and grant timestamps |
| 3 | `authorization.get.roles` | `roleId` (from grants) | Role definitions — what permissions each role carries |
| 4 | `users.division.analysis.get.users.with.division.info` | `divisionId` | Agents whose home division this is — operational personnel baseline |
| 5 | `audit-logs` (EntityType=`AuthorizationGrant`, EntityId=`divisionId`) | `divisionId` | Recent grant/revoke audit events — who changed access and when |

### Key Joins

```
authorization.get.division.grants[].subject.id
  → users.get.user.details.with.full.expansion (for each user subject — name, title, department)

authorization.get.division.grants[].role.id
  → authorization.get.roles[].id (role name and permission list)

audit-logs[].entityId == divisionId
  → authorization.get.division.grants (compare current grants to audit history for orphaned access)
```

### Analytical Questions Answered

- Who has admin or supervisor rights in this division that aren't operational agents?
- Are there grants with roles that include recording access or evaluation access beyond their job function?
- When was each grant made? Were any grants created outside a normal change-management window?
- Are there users with grants to this division who are no longer active (locked/disabled users)?
- What permissions changed in the last 30 days and who authorised them?

### Cross-Reference with Agent Investigation

Use this pattern as a step 0 before an agent investigation when the agent has reported permissions issues or when an access-control incident is being investigated. The grants audit confirms whether the agent's access profile is correct before analysing their operational performance.

---

## 14. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conv. Deep Dive | Queue Inv. | Division Inv. | Exec. Rollup | Real-Time | Agent Inv. | AI/S&TA | Ext. Contact | WFM Adherence | Div. Access |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | ● | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | ○ | ○ | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | | |
| `conversations.get.call.detail` | ○ | | | | | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | | ● | | | |
| `quality.get.evaluations.query` | ● | ○ | ○ | | | ○ | ○ | ○ | | |
| `quality.get.surveys` | ● | | | ● | | | | ○ | | |
| `quality.get.conversation.surveys` | ○ | | | | | | | ● | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | ● | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | ● | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | ○ | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | ● | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | ● | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ○ | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | | ● | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | ○ | ● | | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | |
| `routing-queue-members` | | ● | | | | | | | ○ | |
| `authorization.get.single.division` | | | ● | | | | | | | ● |
| `authorization.list.division.queues` | | | ● | | | | | | ○ | |
| `authorization.get.division.grants` | | | ○ | | | | | | | ● |
| `authorization.get.roles` | | | | | | | | | | ● |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | ● |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | ● | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | ● | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | |
| `coaching.get.appointments` | | | ● | | | ○ | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | ○ | | | |
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
| `audit-logs` | | | ○ | | | ● | | | | ● |
| `externalcontacts.get.contact` | | | | | | | | ● | | |
| `workforce.get.agent.management.unit` | | | | | | ○ | | | ● | |
| `workforce.get.adherence.bulk` | | | | ○ | | ○ | | | ● | |
| `workforce.get.management.unit.users` | | | | ○ | | | | | ● | |
| `workforce.get.management.units` | | | | ○ | | | | | ● | |
| `workforce.get.business.units` | | | | ○ | | | | | ● | |

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

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
