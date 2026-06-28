# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-28  
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
10. [Agent-in-Queue Cross Section](#10-agent-in-queue-cross-section)
11. [Cross-Division Executive Comparison](#11-cross-division-executive-comparison)
12. [Dataset Combination Reference Matrix](#12-dataset-combination-reference-matrix)

---

## 1. Single Conversation Deep Dive (Voice Engineer)

**Subject:** One `conversationId`  
**Use case:** A voice engineer or QM analyst receives a complaint about a specific call — wrong queue, long hold, audio quality, dropped call, incorrect routing. They need the complete picture of one conversation: where it came from, how it routed, how long each phase took, what the SIP signaling said, whether a recording exists, and what the quality score was.

**Core question:** *What actually happened in this conversation, end-to-end?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Participants, sessions, DNIS/ANI, start/end times, queue assignment, external-origin indicators (see [§6](#6-byoi-external-conversation-enrichment)) |
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

A conversation injected through Bring Your Own Interactions (BYOI) is still created through the
standard conversation-creation surface (`postConversationsCalls`, `postConversationsMessagesAgentless`,
`postConversationsEmailsAgentless`, or the Open Messaging family — see [§6](#6-byoi-external-conversation-enrichment)
for the full mapping); there is no separate `/conversations/providers/{providerId}/calls` endpoint in
this catalog. Custom attributes in step 4 will typically contain the provider's context (CRM case ID,
external call ID) if the injecting integration set them. The SIP trace (step 8) will reflect the
provider's SIP-to-SIP handoff, not an inbound PSTN leg, for voice BYOI conversations.

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

**Subject:** One `conversationId` that was injected via Bring Your Own Interactions (BYOI)  
**Use case:** A conversation originated in an external system (CRM telephony, third-party contact
centre, a custom SIP provider) and was injected into Genesys Cloud so Analytics, WFM, and Quality
treat it like a native conversation. The conversation appears in Genesys analytics and recordings,
but context lives in the external system.

**Core question:** *Where did this conversation come from, and what external context does it carry?*

> **Correction (2026-06-28):** an earlier version of this section cited a specific injection
> endpoint, `POST /api/v2/conversations/providers/{providerId}/calls`, that does not exist anywhere
> in this repo's swagger-derived catalog of 3,100+ endpoints (`catalog/genesys.catalog.json`), and no
> endpoint in the catalog is tagged or described as BYOI-related. The corrected mapping below uses
> only endpoints that are actually present in the catalog. The official BYOI integration guide
> (`developer.genesys.cloud/platform/integrations/byoi-integration-guide/`) and its conversation
> injection page were not reachable from this environment at the time of writing (HTTP 403, site-side
> bot protection) — treat the endpoint names below as the best catalog-grounded mapping, not a
> byte-for-byte transcription of the BYOI guide, and re-verify against that guide directly when it is
> reachable.

### How BYOI Conversations Are Actually Created

There is no dedicated `/conversations/providers/{providerId}/calls` resource in the catalog.
Externally-originated interactions are injected through the same conversation-creation family every
other agentless/external integration uses:

| Injection Channel | Dataset / Endpoint Key | Path |
|---|---|---|
| Voice (BYOI call leg) | `postConversationsCalls` | `POST /api/v2/conversations/calls` |
| Agentless outbound message | `postConversationsMessagesAgentless` | `POST /api/v2/conversations/messages/agentless` |
| Agentless outbound email | `postConversationsEmailsAgentless` | `POST /api/v2/conversations/emails/agentless` |
| Open Messaging inbound (legacy) | `postConversationsMessagesInboundOpen` | `POST /api/v2/conversations/messages/inbound/open` |
| Open Messaging integration setup | `postConversationsMessagingIntegrationsOpen` | `POST /api/v2/conversations/messaging/integrations/open` |

BYOI also ingests **agent-state events** (not just conversations) for the externally-handled
interaction, so WFM adherence and presence reporting line up. This repo's catalog does not currently
carry a dedicated agent-state-ingestion dataset — that is a documentation/catalog gap, not a claim
that no such API exists. Flagging it here rather than inventing a path.

### How to Identify a BYOI Conversation

Genesys's documented convention for externally-sourced objects is a tag/external-ID field (commonly
named `externalTag` / `externalConversationId` in other Genesys APIs), but **this catalog's endpoint
metadata does not capture response schemas**, so the presence and exact naming of those fields on
`conversations.get.conversation.object` is not independently verified from this repo alone. Treat a
non-null external-tag-style field as a strong signal, confirm the exact field name against the live
BYOI integration guide or a sample payload before building automation on it, and fall back to
`participants[].purpose == "external"` (which the conversation object schema does support) as a
secondary signal.

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
`conversations.get.conversation.object`. The condensed view used by the embedded client
(`developer.genesys.cloud/platform/embeddable-framework/condensed-conversation-info`) includes:
`participants[].purpose`, `participants[].state`, `participants[].calls[].state`,
`participants[].calls[].muted`, `participants[].calls[].held`, and `queueId`. These fields are
present in the full object returned by the dataset and need no special handling. The condensed
`queueId` attribute is the same value the Queue Investigation (§2) groups by, so a supervisor working
from the embedded client can jump directly from "what queue is this agent's call in right now" to a
full Queue Investigation for that `queueId` without re-deriving it from a different dataset. The
framework also exposes an `Interaction.addCustomAttributes` action for client-side code to set
custom attributes on a live conversation — those attributes surface later through
`conversations.get.conversation.customattributes` in step 4 above.

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

## 10. Agent-in-Queue Cross Section

**Subject:** One `userId` + one `queueId` + time window  
**Use case:** A supervisor gets a complaint or a coaching signal about one agent in one specific
queue — "how is this agent doing in *this* queue" — without wanting the agent's entire cross-queue
history (Agent Investigation, §7) or the queue's entire roster (Queue Investigation, §2/§9). This is
the lean intersection of the two, scoped to stay informative without dumping either full investigation.

**Core question:** *How is this specific agent performing in this specific queue, and is that
performance distinguishable from their overall average or from the queue's overall average?*

This recipe is grounded in a real catalog capability: the conversation aggregates query
(`POST /api/v2/analytics/conversations/aggregates/query`, dataset
`analytics.query.conversation.aggregates.agent.performance`) already documents a `filter.predicates`
array that combines a `queueId` predicate with a `userId`-scoped result via `groupBy: ["userId"]` in
the same request — the catalog's own `defaultBody` example for this dataset filters by `queueId` and
groups by `userId`. Adding a second `userId` predicate to the same `filter.predicates` array (both
dimensions are supported together) scopes the aggregate to one agent in one queue, rather than every
agent in the queue or every queue the agent touches.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | Agent identity — name, email, state, department |
| 2 | `routing-queues` | seed → `queueId` | Queue identity — name, divisionId, media settings |
| 3 | `users.get.user.queue.memberships` | `userId` → filter for `queueId` | Confirms the agent is actually a member of this queue before drawing conclusions from a zero-volume result |
| 4 | `analytics.query.conversation.aggregates.agent.performance` | `queueId` + `userId` (combined predicate) | nConnected, tHandle, tTalk, tAcw, tAnswered — scoped to this agent in this queue only |
| 5 | `analytics.query.conversation.details.by.queue` | `queueId` (conversationFilters) + `userId` (segmentFilters) | The actual conversations this agent handled in this queue — seed list for per-conversation drilldown via §1 |
| 6 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` + `userId` | This agent's wrapup-code mix in this queue, comparable against the queue-wide mix from §2/§9 |
| 7 | `quality.get.evaluations.query` | `agentUserId` + `queueId` | Evaluation scores scoped to this queue, comparable against the agent's overall average from Agent Investigation |
| 8 | `workforce.get.adherence.bulk` | `userId` | Schedule adherence — not queue-scoped in Genesys WFM, included as context for low volume in any one queue |

### Key Joins

```
users.get.user.details.with.full.expansion.id (userId)
  → analytics.query.conversation.aggregates.agent.performance (filter.predicates: queueId AND userId)
  → analytics.query.conversation.details.by.queue (conversationFilters: queueId; segmentFilters: userId)
  → analytics.query.conversation.aggregates.wrapup.distribution (filter.predicates: queueId AND userId)
  → quality.get.evaluations.query (agentUserId + queueId)
```

### Analytical Questions Answered

- Is this agent actually a member of this queue, or is the complaint based on a stale assumption?
- What is this agent's handle/talk/ACW time *in this queue specifically*, vs. their cross-queue average?
- Which conversations did this agent personally handle in this queue, for spot-check drilldown?
- Does this agent's wrapup-code mix in this queue differ from the queue's overall mix — are they
  resolving differently, or seeing a different mix of contact reasons?
- Are this agent's evaluation scores in this queue consistent with their overall average?
- Is schedule adherence a contributing factor to low volume in this queue?

### Why Not Just Run the Full Agent or Queue Investigation?

The full Agent Investigation (16 steps) and Queue Investigation (13 steps) both answer broader
questions than "this agent in this queue." Running either in full and manually filtering the output
re-introduces the "overwhelming data dump" the catalog explicitly tries to avoid. This cross-section
exists as its own recipe so the combined `queueId`+`userId` predicate is used at the API level —
the filtering happens server-side, not by discarding rows after the fact.

---

## 11. Cross-Division Executive Comparison

**Subject:** Organisation-wide — every division, no single-division filter — + reporting window  
**Use case:** A VP or Director of Operations needs to compare business units or regions (divisions)
against each other — "which division is over capacity, understaffed, or underperforming relative to
its peers" — before deciding which one warrants a deeper Division Investigation (§3). Divisions are
the cross-queue grouping unit in Genesys Cloud: an agent's division does not restrict which queues
(potentially in other divisions) they serve, so a division-level rollup is the right level above an
individual queue or agent that still spans the whole org regardless of how queues happen to be split.

**Core question:** *How do divisions compare to each other this period, and which one needs a closer
look?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `authorization.get.all.divisions` | seed (no filter — all divisions) | divisionId, name, description for every division in the org |
| 2 | `users.division.analysis.get.users.with.division.info` | `divisionId` | Headcount — agent count per division |
| 3 | `analytics.division.analysis.conversation.aggregates.by.division.oct.15.dec.8` | `divisionId` | nConnected, tHandle, tTalk, tHeld, tAcw, tAnswered, nOffered, nOutbound, nError — grouped by `divisionId` |

### Key Joins

```
authorization.get.all.divisions[].id
  → users.division.analysis.get.users.with.division.info.divisionId (headcount)
  → analytics.division.analysis.conversation.aggregates.by.division.oct.15.dec.8 (group.divisionId)
```

### Output Metrics

- `divisionName`
- `headcount` (agent count per division)
- `nOffered`, `nConnected`, `nError`
- `tHandle` (avg), `tTalk` (avg), `tAcw` (avg)
- `conversationsPerAgent = nConnected / headcount` — the cross-division capacity signal

### Executive Presentation

A division comparison table ranked by `conversationsPerAgent` and average handle time, plus a
volume-share chart across divisions. This is intentionally the *only* rollup level above a single
queue or agent — once a division is flagged here, pivot directly into the Division Investigation
(§3) for that `divisionId` rather than adding more breadth to this comparison.

### Relationship to the Division Investigation (§3)

This is not a replacement for §3 — it is the wide-but-shallow comparison that decides *which*
division gets the deep-but-narrow treatment in §3. Note that the Division Investigation's seed step
uses `authorization.get.single.division` (by-ID lookup) because it is scoped to one division, while
this comparison deliberately uses the unfiltered `authorization.get.all.divisions` because it needs
every division at once.

---

## 12. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | Agent-in-Queue Cross Section | Cross-Division Comparison |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | ● | |
| `quality.get.surveys` | ● | | | ● | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | ● | |
| `routing-queues` | | | | | | | ● | ● |
| `routing-queue-members` | | ● | | | | | | |
| `authorization.get.all.divisions` | | | | | | | | ● |
| `authorization.get.single.division` | | | ● | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | ● |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | ● | |
| `analytics.query.conversation.details.by.queue` | | | | | | | ● | |
| `analytics.division.analysis.conversation.aggregates.by.division.oct.15.dec.8` | | | | | | | | ● |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | |
| `coaching.get.appointments` | | | ● | | | ○ | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | |
| `analytics.query.flow.observations` | | | | | ● | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | ● | |
| `users.get.user.routing.skills` | | | | | | ● | | |
| `users.get.user.queue.memberships` | | | | | | ● | ● | |
| `users.get.bulk.user.presences` | | | | | | ● | | |
| `routing.get.user.utilization` | | | | | | ○ | | |
| `audit-logs` | | | | | | ● | | |
| `workforce.get.adherence.bulk` | | | | | | | ● | |

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
