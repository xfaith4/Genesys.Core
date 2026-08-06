# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-08-06  
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
10. [Workforce Management Group Investigation (Management Units)](#10-workforce-management-group-investigation-management-units)
11. [Cross-Cutting Reference & Diagnostics Datasets](#11-cross-cutting-reference--diagnostics-datasets)
12. [Dataset Combination Reference Matrix](#12-dataset-combination-reference-matrix)

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

When the complaint implicates a specific handset or softphone rather than the trunk or Edge (one-sided
audio only on one agent's calls, an agent whose calls consistently drop), cross-reference
`stations.get.stations` for the agent's assigned station — registration status and station type help
rule the physical/soft endpoint in or out before escalating to a trunk- or Edge-level explanation.

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

### Division Is Not the Only Cross-Queue Agent Grouping

An **authorization division** groups queues and agents for permission scoping — it answers *who is
allowed to see/manage what*. It is not the only axis on which agents are grouped independently of
the queues they staff. A **WFM management unit** (`workforce.get.management.units`) groups the same
agents for scheduling and adherence purposes, and its membership frequently does **not** line up
1:1 with division membership — an agent can be scheduled by one management unit while working
queues that span several divisions, or a management unit can pull members from queues in more than
one division. Treat division and management unit as two independent grouping axes over the same
agent population and cross-reference both before concluding "this team" means one thing. See
[Section 10](#10-workforce-management-group-investigation-management-units) for the management-unit
investigation pattern, including the join that surfaces division/management-unit mismatches.

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
| `quality.get.published.evaluation.forms` | `evaluationForm.id` (label join) | Resolves scores in `quality.get.agents.activity` / `quality.get.evaluations.query` to form/question names instead of raw form GUIDs |
| `quality.get.surveys` | `conversationId` (aggregate) | CSAT/NPS: response rate, average score |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | Speech analytics coverage: nSpeechTextAnalyzedConversations, oSentimentScore |
| `speechandtextanalytics.get.topics` | `topicId` (label join) | Resolves topic IDs surfaced by STA aggregates to human-readable topic names for a "top customer topics" rollup panel |

#### Layer 5 — Infrastructure Health (optional, voice-focused)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `telephony.get.trunk.metrics.summary` | — | SIP trunk utilisation, errors |
| `telephony.get.edges` | `edgeId` | Edge registration status |
| `alerting.get.alerts` | — | Currently firing threshold alerts |

#### Layer 6 — Workforce Adherence (optional, WFM-licensed orgs)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `workforce.get.business.units` | — | Enumerates BUs to fan the rollup out per business unit |
| `workforce.get.management.unit.adherence` | `managementUnitId`, daily | Org-wide adherence %: scheduled-vs-actual variance, exception minutes |

### Automating Delivery

`analytics.get.reporting.exports` lists the org's configured scheduled export jobs (format,
recipients, cadence). Cross-reference it before building a bespoke delivery mechanism for this
rollup — the export may already exist, or the rollup can be registered as a new export using the
same schedule/recipient pattern rather than inventing a parallel distribution path.

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
| 10 *(channel drilldown)* | `conversations.get.active.calls` / `.get.active.chats` / `.get.active.emails` / `.get.active.callbacks` | Org or queue | Per-media-type live conversation lists — the individual conversation IDs behind the aggregate counts in steps 1–2 |

### Media-Type Drilldown

Steps 1–2 give aggregate counts (`oInteracting`, `oWaiting`) but not *which* conversations they
are. When a wall board shows an unusual `oWaiting` spike for a queue, step 10's per-media-type
active lists (`conversations.get.active.calls`, `.get.active.chats`, `.get.active.emails`,
`.get.active.callbacks`) give the actual conversation IDs and durations so a supervisor can jump
straight to the [Single Conversation Deep Dive](#1-single-conversation-deep-dive-voice-engineer)
for the longest-waiting item instead of waiting for an analytics job to populate.

For **after-the-fact** reconciliation (a call that has already ended and needs to be found without
a known `conversationId`), `conversations.get.call.history` provides a lighter-weight,
non-analytics-job lookup path scoped to voice — useful when a voice engineer only has a phone
number and an approximate time and needs to locate the conversation before starting a deep dive.

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
| agentAssist | `conversations.get.conversation.suggestions` | `conversationId` | Agent Assist / Predictive Engagement suggestions offered during the conversation (knowledge articles, response suggestions) |
| agentAssistDetail | `conversations.get.conversation.suggestion.detail` | `suggestionId` (from `agentAssist`) | Full content, confidence score, and source of a specific suggestion — was it shown, and was it used? |
| flowDiagnostics | `analytics.query.flow.aggregates.execution.metrics` | `flowId` (from participant/session flow field) + window | Aggregate outcome/failure/milestone counts for the Architect flow the conversation traversed — is this conversation's slow IVR/misroute part of a wider flow problem? |

**Conditional steps:** `sipTrace` runs only when `conversations.get.conversation.object.participants[].calls` is
non-empty (voice conversation). `sentimentTimeline` runs only when `conversations.get.speech.text.analytics`
returns `speechAndTextAnalyticsConversation.analysisStatus = "Success"`. `agentAssist`/`agentAssistDetail`
run only when the org has Agent Assist / Predictive Engagement licensed and the conversation carries a
`participants[].attributes` entry referencing a suggestion. `flowDiagnostics` is a queue-of-work style
aggregate (not conversation-scoped) — it complements a single conversation's flow experience with "is this
typical for this flow" context rather than replacing per-conversation attribute data.

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

## 10. Workforce Management Group Investigation (Management Units)

**Subject:** One `managementUnitId` (optionally scoped by `businessUnitId`) + time window
**Use case:** A WFM analyst or operations director needs to know whether a scheduling team is
adhering to its plan, and whether that team's membership actually lines up with the division/queue
boundaries used everywhere else in reporting. Management units are WFM's grouping construct — a
management unit is *also* a group of agents that can span multiple queues, exactly like a division,
but on an independent axis (scheduling, not permissions).

**Core question:** *Is this scheduling team adhering to plan, and who is actually in it?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.business.units` | seed | Enumerate business units (top-level WFM container) |
| 2 | `workforce.get.management.units` | `businessUnitId` | Management units within the business unit |
| 3 | `workforce.get.management.unit.users` | `managementUnitId` | Agent roster (`userId`) scheduled under this management unit |
| 4 | `workforce.get.management.unit.adherence` | `managementUnitId` | Per-agent scheduled-vs-actual state and variance for the window |
| 5 | `users.division.analysis.get.users.with.division.info` | `userId` (from step 3) | Division assignment for the same roster — surfaces division/management-unit mismatches |
| 6 | `analytics.query.conversation.aggregates.agent.performance` | `userId` (from step 3) | Ties adherence variance to actual handle volume/AHT for the same agents |

### Key Joins

```
workforce.get.business.units.id
  → workforce.get.management.units.businessUnitId

workforce.get.management.units.id
  → workforce.get.management.unit.users.managementUnitId
  → workforce.get.management.unit.adherence.managementUnitId

workforce.get.management.unit.users[].id
  → users.division.analysis.get.users.with.division.info[].id (left join — surfaces mismatches, not just matches)
  → analytics.query.conversation.aggregates.agent.performance[].userId
```

### Analytical Questions Answered

- Which agents are out of adherence right now, and by how much?
- Does the management-unit roster match the division roster reported elsewhere, or does this team
  pull members from more than one division/queue?
- Is a queue's real-time understaffing (Section 5) explained by scheduled agents currently
  out-of-adherence in their management unit?
- Did adherence variance correlate with a drop in handled volume or a rise in AHT for the same
  agents (step 6)?

### Note on Scope

This is a distinct investigation entry point from Section 3 (Authorization Division), not a
replacement for it. Run both when a "team" needs to be fully characterized — division answers *who
can see/manage what*, management unit answers *who is scheduled together*. See
[the cross-referencing note in Section 3](#division-is-not-the-only-cross-queue-agent-grouping)
for why the two rosters can legitimately disagree.

---

## 11. Cross-Cutting Reference & Diagnostics Datasets

The datasets below are not investigation entry points on their own — they are **label-resolution
and drilldown joins** that turn raw IDs already returned by the investigations above into
operator-readable context. Each is a small, single-purpose lookup; combine it with the investigation
it enriches rather than pulling it standalone.

| Dataset Key | Resolves / Enriches | Join Key | Used By |
|-------------|---------------------|----------|---------|
| `quality.get.published.evaluation.forms` | Evaluation form/question names for raw `evaluationForm.id` values | `evaluationForm.id` | Conversation Deep Dive (step 6), Division Investigation (step 7), Executive Rollup Layer 4 |
| `speechandtextanalytics.get.topics` | Topic names for raw topic IDs surfaced by STA sentiment/aggregate results | `topicId` | Conversation Deep Dive (steps 9–10), Executive Rollup Layer 4 |
| `routing.get.skill.groups` | Skill-based agent groupings (an alternate cut to division/management-unit — capability rather than schedule or permission) | `skillGroupId` | Division Investigation, Real-Time Operations Monitoring |
| `stations.get.stations` | Physical/soft-phone device assigned to an agent, registration status | `userId` → assigned station | Conversation Deep Dive Voice Engineer Notes |
| `users.search.users.by.name.or.email` | Resolves an agent's name or email to `userId` | free-text → `userId` | Entry point resolution for Agent Investigation and any investigation seeded by name rather than GUID (see [`INVESTIGATIONS.md` §10](INVESTIGATIONS.md#10-open-questions) — this dataset is the resolution mechanism the "subject-by-name lookups" open question calls for) |
| `analytics.get.reporting.exports` | Existing scheduled export jobs — avoid building a parallel delivery mechanism for a new rollup | — | Executive Reporting Rollup |
| `journey.get.action.maps` | Predictive Engagement trigger/condition definitions referenced by a conversation's originating action map | `actionMapId` | Conversation Deep Dive (BYOI/digital origin context) |

---

## 12. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | WFM Group Investigation |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | |
| `quality.get.published.evaluation.forms` | ○ | | ○ | ○ | | | |
| `quality.get.surveys` | ● | | | ● | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | |
| `speechandtextanalytics.get.topics` | ○ | | | ○ | | | |
| `conversations.get.conversation.suggestions` | ○ | | | | | | |
| `conversations.get.conversation.suggestion.detail` | ○ | | | | | | |
| `journey.get.action.maps` | ○ | | | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | ○ | | | | | | |
| `stations.get.stations` | ○ | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | |
| `routing-queue-members` | | ● | | | | | |
| `routing.get.skill.groups` | | ○ | ○ | | ○ | | |
| `authorization.get.single.division` | | | ● | | | | |
| `authorization.list.division.queues` | | | ● | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | ● |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | ● |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | |
| `coaching.get.appointments` | | | ● | | | ○ | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | |
| `analytics.get.reporting.exports` | | | | ● | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | |
| `conversations.get.active.calls` / `.get.active.chats` / `.get.active.emails` / `.get.active.callbacks` | | ○ | | | ● | | |
| `conversations.get.call.history` | ○ | | | | ○ | | |
| `analytics.query.flow.observations` | | | | | ● | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | |
| `alerting.get.alerts` | | | | ○ | ● | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | |
| `users.get.user.routing.skills` | | | | | | ● | |
| `users.get.user.queue.memberships` | | | | | | ● | |
| `users.get.bulk.user.presences` | | | | | | ● | |
| `users.search.users.by.name.or.email` | | | | | | ○ | ○ |
| `routing.get.user.utilization` | | | | | | ○ | |
| `audit-logs` | | | | | | ● | |
| `workforce.get.business.units` | | | | ○ | | | ● |
| `workforce.get.management.units` | | | | | | | ● |
| `workforce.get.management.unit.users` | | | | | | | ● |
| `workforce.get.management.unit.adherence` | | | | ○ | | | ● |

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
