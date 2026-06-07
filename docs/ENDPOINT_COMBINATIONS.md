# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-07  
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
10. [Outbound Campaign Investigation](#10-outbound-campaign-investigation)
11. [Customer 360 Investigation (External Contact)](#11-customer-360-investigation-external-contact)
12. [WFM Schedule Adherence Investigation](#12-wfm-schedule-adherence-investigation)
13. [Flow / IVR Performance Investigation](#13-flow--ivr-performance-investigation)
14. [AI Copilot & Knowledge Effectiveness Investigation](#14-ai-copilot--knowledge-effectiveness-investigation)
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

## 10. Outbound Campaign Investigation

**Subject:** One `campaignId` + optional `contactListId`  
**Use case:** An outbound operations manager or voice engineer needs to understand why a campaign is
underperforming — low contact rate, pacing issues, disposition failures, or poor call quality on
connected records. This is the ROADMAP 1.3 candidate flagship investigation.

**Core question:** *Is this campaign contacting customers effectively, and what does call quality look like on connected records?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` (single record) | seed → `campaignId` | Campaign config: dialing mode, pacing, queue assignment, DNC lists, recency filters |
| 2 | `outbound.get.campaign.progress` | `campaignId` | Live progress: nContacted, nCompleted, nSkipped, nOutstandingContacts, currentPacingRate |
| 3 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Health indicators: pacing issues, current error flags, DNC hit rate |
| 4 | `outbound.get.contact.lists` (single record) | `contactListId` | Contact list metadata: total records, column definitions, import date |
| 5 | `outbound.get.events` | `campaignId` | Dialer disposition events: CONNECTED, BUSY, NO_ANSWER, ANSWERING_MACHINE, FAILED |
| 6 | `analytics-conversation-details-query` (campaignId filter) | `conversationId` | Conversations generated by this campaign — segment timing, agent, queue, duration |
| 7 | `analytics.query.conversation.aggregates.queue.performance` (queueId filter) | `queueId` | Aggregate outbound queue performance for the campaign's queue |
| 8 *(voice)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace on a sample connected record — diagnose audio/setup failures on outbound legs |
| 9 *(QM licensed)* | `quality.get.evaluations.query` (campaignId or conversationId filter) | `conversationId` | QM scores on connected outbound calls |

### Key Joins

```
outbound.get.campaigns.id
  → outbound.get.campaign.progress.campaignId
  → outbound.get.campaign.diagnostics.summary.campaignId
  → outbound.get.events[].campaign.id
  → analytics-conversation-details-query.filter(campaignId)

outbound.get.events[].conversationId
  → analytics-conversation-details-query[].conversationId (connected records only)
  → telephony.get.sip.messages.for.conversation.conversationId (voice only)
```

### Analytical Questions Answered

- What percentage of the contact list has been worked? What remains?
- What is the current pacing rate and is it constrained by DNC, skill, or capacity?
- How are dispositions breaking down? Is BUSY/NO_ANSWER disproportionate?
- For connected records: what was average handle time and ACW?
- Are there SIP call-setup failures on outbound legs (busy, rejected, no answer on trunk)?
- Are connected outbound calls being evaluated? What is the average QM score?

### Outbound vs Inbound Queue Comparison

A campaign that appears to have low contact rates may actually be pacing-limited by the inbound
queue sharing the same agents. Pull `analytics.query.queue.observations.real.time.stats` for the
campaign's queue at the same time as `outbound.get.campaign.progress` to see if agent scarcity
is the constraint.

---

## 11. Customer 360 Investigation (External Contact)

**Subject:** One `externalContactId` or ANI/email identifier  
**Use case:** A supervisor or compliance analyst needs the complete history of a specific customer
across all conversations — voice, chat, email — including their digital journey before contacting the
centre. This is the primary cross-channel, cross-conversation investigation type.

**Core question:** *Who is this customer, and what has their complete experience with us been?*

### How to Find an External Contact ID

In `conversations.get.conversation.object`, check `participants[].externalContactId`. If the
customer was identified by the IVR or previous interaction, this field is populated. Alternatively,
use the identifier lookup endpoint to resolve a phone number or email to a contact.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `externalcontacts.get.contact` | seed → `externalContactId` | Customer profile: name, phone, email, external-org linkage, CRM reference |
| 2 | `externalcontacts.get.contact.identifiers` | `externalContactId` | All identity attributes: every phone, email, and external-source ID on record |
| 3 | `externalcontacts.get.contact.journey.sessions` | `externalContactId` | Journey sessions: web visits and digital events before each conversation (≤60 days) |
| 4 | `journey.get.session.events` (per sessionId) | `sessionId` | Events within a journey session — page views, form submits, intent signals |
| 5 | `analytics-conversation-details-query` (externalContactId filter) | `conversationId` | All conversations this customer had across all channels in the window |
| 6 | `analytics.get.single.conversation.analytics` (per conversationId) | `conversationId` | Per-conversation segment timing for each historical interaction |
| 7 | `quality.get.surveys` (conversationId list) | `conversationId` | CSAT/NPS results — customer sentiment across interactions |
| 8 *(optional)* | `quality.get.evaluations.query` (conversationId list) | `conversationId` | QM scores for conversations where this customer was evaluated |

### Key Joins

```
externalcontacts.get.contact.id
  → externalcontacts.get.contact.identifiers.externalContactId
  → externalcontacts.get.contact.journey.sessions[].externalContact.id

externalcontacts.get.contact.journey.sessions[].id
  → journey.get.session.events[].session.id

analytics-conversation-details-query[].participants[].externalContactId
  → externalcontacts.get.contact.id (reverse join — confirm contact match)

analytics-conversation-details-query[].conversationId
  → quality.get.surveys[].conversationId
  → quality.get.evaluations.query[].conversationId
```

### Analytical Questions Answered

- How many times has this customer contacted us, and on which channels?
- What was the customer doing on our website or digital channels before calling?
- Did the customer's CSAT improve or decline across interactions?
- Has the customer ever been on hold for extended periods or experienced abandoned calls?
- What external CRM records are linked to this customer?
- Are there repeat contacts on the same topic (suggesting unresolved issues)?

### Division Context

If a customer contacts multiple divisions (e.g., sales and support), their `externalContactId`
is shared across all conversations. The `analytics-conversation-details-query` results will span
all divisions; filter by `divisionId` to scope to a single division's view of the customer.

---

## 12. WFM Schedule Adherence Investigation

**Subject:** One `managementUnitId` + date range  
**Use case:** A workforce manager or operations director needs to understand whether agents are
adhering to their schedules — are they on queue when planned, taking breaks at the right times,
and logging out on time?

**Core question:** *Are agents following their schedules, and where are the largest variance gaps?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.management.units` | seed → `managementUnitId` | Management unit name, timezone, and scheduling configuration |
| 2 | `workforce.get.management.unit.users` | `managementUnitId` | Agent roster for this WFM unit with user IDs |
| 3 | `workforce.get.agent.schedules.search` | `managementUnitId` + date range | Planned activities: on-queue blocks, breaks, meetings, training — scheduled start/end times |
| 4 | `workforce.get.management.unit.adherence` | `managementUnitId` | Current adherence state: adherence status, scheduled activity, actual activity, impact minutes |
| 5 | `analytics.query.user.details.activity.report` | `userId` | Actual agent presence and routing status timeline for the same date range |
| 6 | `analytics.query.user.aggregates.login.activity` | `userId`, daily | Aggregate time-in-state: on-queue vs off-queue vs idle, per agent per day |

### Key Joins

```
workforce.get.management.unit.users[].user.id
  → workforce.get.agent.schedules.search[].userId
  → workforce.get.management.unit.adherence[].user.id
  → analytics.query.user.details.activity.report[].userId
  → analytics.query.user.aggregates.login.activity[].group.userId

workforce.get.agent.schedules.search[].shifts[].activities[].startTime
  ↔  analytics.query.user.details.activity.report[].primaryPresenceDivision (time overlap join)
```

### Analytical Questions Answered

- Which agents had the most adherence exceptions this week?
- Which activity type (on-queue, break, training) generated the most variance?
- Is off-queue time correlated with low handle volume in certain intervals?
- Are late logins or early logouts concentrated in a particular shift or team group?
- How does adherence variance correlate with queue SLA misses?

### Adherence Calculation Pattern

```
Planned on-queue minutes  = SUM(activity.lengthMinutes WHERE activity.type = "OnQueueWork")
Actual on-queue minutes   = SUM(tAgentRoutingStatus.available + tAgentRoutingStatus.interacting)
Adherence variance        = Actual – Planned
Adherence %               = MIN(Actual, Planned) / Planned × 100
```

This calculation requires a time-interval join between the planned activities in
`workforce.get.agent.schedules.search` and the state-change events in
`analytics.query.user.details.activity.report`. The join key is `userId` + overlapping
`[startTime, endTime]` windows.

---

## 13. Flow / IVR Performance Investigation

**Subject:** One `flowId` + time window  
**Use case:** An Architect developer or IVR analyst receives complaints that calls are being
misrouted, dropped in the IVR, or reaching incorrect queues. They need to understand which flow
paths are executing, what outcomes are being recorded, and which conversations entered the flow
but never reached an agent.

**Core question:** *Is this Architect flow executing as designed, and where are callers dropping out?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `flows.get.all.flows` (single record) | seed → `flowId` | Flow name, type (inboundCall, inQueue, bot), published version, division |
| 2 | `flows.get.flow.outcomes` | `flowId` | Outcome label definitions — the named results this flow can produce |
| 3 | `flows.get.flow.milestones` | `flowId` | Milestone definitions — named checkpoints within the flow for analytics tracking |
| 4 | `analytics.query.flow.aggregates.execution.metrics` (flowId filter) | `flowId` | Aggregate: nFlow, nFlowOutcome (by outcomeId), nFlowOutcomeFailed, nFlowMilestone, tFlowDisconnect |
| 5 | `analytics-conversation-details-query` (flowId filter) | `conversationId` | Every conversation that executed this flow — segment timing, queue reached, outcome |
| 6 | `analytics.query.flow.observations` | `flowId` | Real-time: how many callers are currently inside this flow |
| 7 *(bot flows)* | `analytics.get.botflow.sessions` | `botFlowId` | Bot session records: duration, exit reason, agent escalation rate |

### Key Joins

```
flows.get.all.flows[].id
  → analytics.query.flow.aggregates.execution.metrics[].group.flowId
  → analytics-conversation-details-query[].participants[].sessions[].flowId

flows.get.flow.outcomes[].id
  → analytics.query.flow.aggregates.execution.metrics[].group.flowOutcomeId

analytics-conversation-details-query[].conversationId
  → conversations.get.conversation.object.id (detailed participant/segment view)
  → telephony.get.sip.messages.for.conversation.conversationId (SIP check on drop calls)
```

### Analytical Questions Answered

- What percentage of calls reach each defined flow outcome?
- Which outcomes indicate failures (FAILED, TIMEOUT, SYSTEM_ERROR)?
- What is the flow disconnect rate (callers abandoning inside the IVR)?
- Are any milestones never reached — indicating dead branches?
- For bot flows: what is the human escalation rate? What triggers escalation?
- Do conversations that exit via a specific outcome correlate with downstream transfers or escalations?

### IVR Abandonment Pattern

Conversations that enter the flow but have no `participants[].purpose = "agent"` segment were
handled entirely by the IVR (self-service) or abandoned inside it. Filter
`analytics-conversation-details-query` for the `flowId` and count records with no agent segment
vs records that transferred to a queue. This ratio is the **IVR containment rate** — a key
executive metric for self-service investment.

```
IVR containment rate = conversations with no agent segment / total conversations in flow × 100
```

---

## 14. AI Copilot & Knowledge Effectiveness Investigation

**Subject:** One or more `assistantId` / `knowledgeBaseId` + time window  
**Use case:** A CX technology leader or quality director needs to understand whether Genesys AI
Agent Assist (copilot) is reducing handle time, improving first-call resolution, and surfacing
accurate knowledge. This investigation answers whether the AI investment is delivering measurable
outcomes.

**Core question:** *Is Agent Assist reducing AHT and improving outcomes on AI-assisted queues?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `copilot.get.assistants` | seed → `assistantId` | Copilot configuration: name, knowledge-base IDs, NLU model, queue assignments |
| 2 | `copilot.get.assistant.queue.assignments` | `assistantId` | Which queues have copilot enabled — defines the AI-assisted population |
| 3 | `analytics.query.knowledge.aggregates` (knowledgeBaseId filter) | `knowledgeBaseId`, `queueId` | Article usage: nKnowledgeDocumentsAnswered, nKnowledgeDocumentsFailed, tKnowledgeSearch |
| 4 | `analytics.query.conversation.aggregates.queue.performance` (AI-assisted queueIds) | `queueId` | AHT, ACW, handle volume for AI-assisted queues — baseline comparison |
| 5 | `analytics.query.conversation.aggregates.queue.performance` (non-assisted queueIds) | `queueId` | Same metrics for non-assisted control queues — AHT delta computation |
| 6 | `quality.get.agents.activity` (AI-assisted queueIds) | `userId` | QM scores on AI-assisted agents — quality delta vs non-assisted agents |
| 7 *(conversation detail)* | `conversations.get.conversation.ai.summary` | `conversationId` | AI-generated post-call summaries — outcome classification, next-step labels |
| 8 *(STA enabled)* | `conversations.get.conversation.sta.summaries` | `conversationId` | STA conversation summaries — topic labels, resolution status, key phrases |

### Key Joins

```
copilot.get.assistant.queue.assignments[].queue.id
  → analytics.query.knowledge.aggregates[].group.queueId
  → analytics.query.conversation.aggregates.queue.performance[].group.queueId

analytics-conversation-details-query[].conversationId (AI-assisted queue, sampled)
  → conversations.get.conversation.ai.summary.conversationId
  → conversations.get.conversation.sta.summaries.conversationId
```

### Analytical Questions Answered

- What is the knowledge article answer rate vs failure rate per queue?
- Are AI-assisted queues showing lower AHT than comparable non-assisted queues?
- What topics are most frequently triggering knowledge lookups?
- Are agent QM scores higher on AI-assisted queues?
- What outcome categories does the AI summarizer most frequently assign (resolved, escalated, callback)?
- Is there a correlation between knowledge article usage and first-call resolution (no repeat contact)?

### AHT Delta Pattern

```
AHT (AI-assisted queues)     = WAVG(tHandle, nConnected) over copilot.get.assistant.queue.assignments[].queue.id
AHT (non-assisted queues)    = WAVG(tHandle, nConnected) over remaining production queues (same media type)
AHT delta                    = AHT (non-assisted) − AHT (AI-assisted)
Copilot contribution estimate = AHT delta / AHT (non-assisted) × 100
```

Note: This delta is indicative, not causal. Queue composition (volume, skill level, topic mix) must
be controlled before attributing AHT improvement to the copilot.

---

## 15. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

Columns 1–6 are the original patterns; columns 7–11 are the patterns added in this release.

| Dataset Key | Conv Deep Dive | Queue Inv | Division Inv | Exec Rollup | Real-Time | Agent Inv | Outbound Campaign | Customer 360 | WFM Adherence | Flow/IVR | AI Copilot |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | ○ | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | ○ | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | | | |
| `conversations.get.conversation.ai.summary` | ○ | | | | | | | | | | ○ |
| `conversations.get.conversation.sta.summaries` | ○ | | | | | | | | | | ○ |
| `quality.get.evaluations.query` | ● | ○ | | | | | ○ | ○ | | | |
| `quality.get.surveys` | ● | | | ● | | | | ● | | | |
| `quality.get.calibrations` | | | | ○ | | | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | ○ | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | | | |
| `routing.get.skill.group.members` | | | ○ | | | ○ | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ● | ● | | ● | ○ |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | ● | | | | ● |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | | | |
| `routing-queue-members` | | ● | | | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | ● | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | ● | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | | | ● |
| `coaching.get.appointments` | | | ● | | | ○ | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | | ● | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | | | | ● | |
| `analytics.get.botflow.sessions` | | | | | | | | | | ○ | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | | | |
| `audit-logs` | | | | | | ● | | | | | |
| `outbound.get.campaigns` | | | | | | | ● | | | | |
| `outbound.get.campaign.progress` | | | | | | | ● | | | | |
| `outbound.get.campaigns.progress.bulk` | | | | ○ | | | ● | | | | |
| `outbound.get.campaign.diagnostics.summary` | | | | | | | ● | | | | |
| `outbound.get.contact.lists` | | | | | | | ● | | | | |
| `outbound.get.events` | | | | | | | ● | | | | |
| `externalcontacts.get.contact` | | | | | | | | ● | | | |
| `externalcontacts.get.contact.identifiers` | | | | | | | | ● | | | |
| `externalcontacts.get.contact.journey.sessions` | | | | | | | | ● | | | |
| `journey.get.session.events` | | | | | | | | ○ | | | |
| `workforce.get.management.units` | | | | | | | | | ● | | |
| `workforce.get.management.unit.users` | | | | | | | | | ● | | |
| `workforce.get.agent.schedules.search` | | | | | | | | | ● | | |
| `workforce.get.management.unit.adherence` | | | | | | | | | ● | | |
| `flows.get.all.flows` | | | | | | | | | | ● | |
| `flows.get.flow.outcomes` | | | | | | | | | | ● | |
| `flows.get.flow.milestones` | | | | | | | | | | ● | |
| `copilot.get.assistants` | | | | | | | | | | | ● |
| `copilot.get.assistant.queue.assignments` | | | | | | | | | | | ● |
| `analytics.query.knowledge.aggregates` | | | | ○ | | | | | | | ● |
| `journey.get.action.maps` | | | | | | | | ○ | | | |

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
| `nFlow` | Number of times a flow executed | IVR volume |
| `nFlowOutcome` | Flow exits with a specific named outcome | Flow outcome distribution |
| `nFlowOutcomeFailed` | Flow exits classified as failure outcomes | IVR failure rate |
| `nFlowMilestone` | Times a named milestone was reached in the flow | IVR path analysis |
| `tFlowDisconnect` | Time callers spent in the flow before disconnecting | IVR abandonment duration |
| `nContacted` | Outbound campaign records where a live person was reached | Campaign contact rate numerator |
| `nOutstandingContacts` | Outbound records not yet dialed in the campaign | Campaign completion forecast |
| `currentPacingRate` | Current lines-per-agent ratio the dialer is using | Campaign pacing health |
| `nKnowledgeDocumentsAnswered` | Times a knowledge article was presented to an agent | Copilot coverage |
| `nKnowledgeDocumentsFailed` | Knowledge lookup failures (no article match) | Copilot gap analysis |
| `tKnowledgeSearch` | Time agents spent on knowledge searches | Copilot efficiency |
| `adherenceStatus` | Whether the agent is adherent to their scheduled activity | WFM adherence flag |
| `impactMinutes` | Accumulated out-of-adherence minutes for the agent | WFM variance magnitude |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*  
*Patterns 10–14 (Outbound Campaign, Customer 360, WFM Adherence, Flow/IVR, AI Copilot) were added 2026-06-07 and use new catalog datasets introduced in the same update.*
