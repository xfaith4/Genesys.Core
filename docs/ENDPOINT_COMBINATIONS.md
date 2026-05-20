# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-20  
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
10. [Voice Engineer Network Topology Investigation](#10-voice-engineer-network-topology-investigation)
11. [Architect Flow Investigation](#11-architect-flow-investigation)
12. [Workforce Alignment Investigation](#12-workforce-alignment-investigation)
13. [Dataset Combination Reference Matrix](#13-dataset-combination-reference-matrix)

---

## 1. Single Conversation Deep Dive (Voice Engineer)

**Subject:** One `conversationId`  
**Use case:** A voice engineer or QM analyst receives a complaint about a specific call — wrong queue, long hold, audio quality, dropped call, incorrect routing. They need the complete picture of one conversation: where it came from, how it routed, how long each phase took, what the SIP signaling said, whether a recording exists, and what the quality score was.

**Core question:** *What actually happened in this conversation, end-to-end?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Participants, sessions, DNIS/ANI, start/end times, queue assignment, externalTag (BYOI indicator), externalContactId |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Per-segment timing: IVR duration, ACD wait, talk time, hold time, ACW, conference, recording start/stop |
| 3 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs, media type, duration, deletion schedule |
| 4 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by IVR/Architect flows (account numbers, intent, escalation flags) |
| 5 | `conversations.search.participant.attributes` | `conversationId` | Participant-level attributes (IVR variables, data action outcomes, flow-set values) |
| 6 | `quality.get.evaluations.query` | `conversationId` | QM evaluation IDs, scores, form used, evaluator, calibration status |
| 6a *(drill-down)* | `quality.get.single.conversation.evaluation` | `conversationId` + `evaluationId` | Full form answer set and per-question scores for a specific evaluation found in step 6 |
| 7 | `quality.get.single.conversation.surveys` | `conversationId` | Post-call CSAT/NPS survey result and per-question responses for this conversation |
| 8 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace: INVITE, 200 OK, BYE, re-INVITE, codec negotiation |
| 9 *(STA enabled)* | `conversations.get.speech.text.analytics` | `conversationId` | Sentiment score, detected topics, STA coverage summary |
| 10 *(STA enabled)* | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Sentiment timeline: per-utterance scores, agent vs customer breakdown |
| 11 *(STA enabled)* | `speechandtextanalytics.get.conversation.summaries` | `conversationId` | STA-generated reason-for-call, resolution summary, and topic labels |
| 12 *(AI enabled)* | `conversations.get.conversation.summaries` | `conversationId` | Genesys AI concise resolution summary (available after conversation ends) |
| 13 *(transcription enabled)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId` + `communicationId` | Transcript download URL per communication leg |
| 14 *(BYOI / externalContactId)* | `externalcontacts.get.single.contact` | `externalContactId` from step 1 | CRM profile behind the caller: name, org, linked history |
| 15 *(BYOI / externalContactId)* | `externalcontacts.get.contact.journey.sessions` | `contactId` | Web and app touchpoints before and after the voice call |
| 16 *(flow debugging)* | `flows.query.execution.history` | `conversationId` | Flow instance records — which flow version ran, what outcome was produced |
| 17 *(station audit)* | `users.get.user.station` | `userId` from participants | Agent's registered phone/softphone device at investigation time |

### Key Joins

```
conversations.get.conversation.object.conversationId
  → analytics.get.single.conversation.analytics.conversationId (segment overlay)
  → conversations.get.conversation.recording.metadata.conversationId
  → telephony.get.sip.messages.for.conversation.conversationId (voice only)
  → quality.get.evaluations.query[].conversationId (left join — evaluations may not exist)
  → quality.get.single.conversation.surveys.conversationId

quality.get.evaluations.query[].id (evaluationId)
  → quality.get.single.conversation.evaluation.evaluationId (drill-down to full form)

analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
  → speechandtextanalytics.get.conversation.communication.transcripturl.communicationId

conversations.get.conversation.object.participants[].externalContactId
  → externalcontacts.get.single.contact.contactId
  → externalcontacts.get.contact.journey.sessions.contactId

conversations.get.conversation.object.participants[].userId (agent)
  → users.get.user.station.userId (what phone was the agent on?)
```

### Analytical Questions Answered

- What was the full call flow? (IVR → ACD → agent → hold → ACW)
- How long did the customer wait before an agent answered?
- Was the call transferred? How many times? What queue received the transfer?
- Was a recording made? Does it still exist?
- Did the SIP trunk establish media correctly? (from SIP trace)
- Was the agent rated? What was the QM score? What were the per-question answers?
- Was the customer surveyed? What was the CSAT result?
- What intent/attributes did the IVR capture before routing?
- What did the AI summarise as the reason-for-call and resolution?
- Did the customer visit the website before calling? (journey sessions)
- Which flow version ran? What was the flow outcome? (flow execution history)
- Which physical phone/softphone did the agent use?

### Voice Engineer Notes

Step 8 (SIP trace) is the definitive source for:
- Call setup failures (no 200 OK, 486 Busy, 503 Service Unavailable)
- One-way audio (media IP mismatch in SDP)
- Premature disconnection (BYE before expected, no 200 OK to BYE)
- Codec negotiation failures

The `telephony.get.edge.performance.metrics` dataset (`GET /api/v2/telephony/providers/edges/{edgeId}/metrics`)
should be pulled for the Edge appliance that handled the call if CPU, memory, or error counters suggest
resource pressure during the conversation window. See [Pattern 10](#10-voice-engineer-network-topology-investigation)
for site-wide topology investigation when multiple calls are affected.

### BYOI Indicator

If `conversations.get.conversation.object` returns a non-null `externalTag` or `externalConversationId`,
the call was injected via the BYOI integration (`POST /api/v2/conversations/providers/{providerId}/calls`).
Custom attributes in step 4 will contain the provider's context (CRM case ID, external call ID).
The SIP trace (step 8) will reflect the provider's SIP-to-SIP handoff, not an inbound PSTN leg.
Steps 14–15 (external contact + journey) provide the full customer context from the originating system.

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
| 10 *(WFM licensed)* | `workforce.get.management.unit.adherence` | `managementUnitId` | Schedule adherence: scheduled vs. actual state with variance per agent |

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
  → workforce.get.management.unit.adherence[].user.id (WFM join)
```

### Analytical Questions Answered

- How many agents are in this division and who are they?
- What queues does this division own?
- Which agents handled the most volume? Which had the highest AHT?
- Which agents spent the most time off-queue or in non-productive states?
- Which agents have been evaluated? Who has the highest/lowest scores?
- Which agents have received recent coaching? Is coaching correlated with score improvement?
- Are agents adhering to their WFM schedules? Which agents have the highest variance?

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

#### Layer 5 — AI Insight Coverage (if licensed)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.post.transcripts.aggregates.query` (with STA topic grouping) | `queueId`, `topicId`, daily | Topic frequency: which issues drove volume? |
| `conversations.get.conversation.summaries` (sampled) | sampled conversationIds | AI summary quality spot-check — confirm automation is producing coherent output |

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
  - QM coverage: evaluations / nConnected × 100
  - Average QM score: from quality.get.agents.activity
  - Avg CSAT: from quality.get.surveys
  - STA coverage: nSpeechTextAnalyzedConversations / nConnected × 100
  - Avg sentiment score: oSentimentScore (voice queues with STA)

Trend views (daily granularity):
  - Volume by day with channel mix
  - AHT trend by queue
  - Abandon rate trend by queue
  - SLA achievement heatmap by queue × day
  - Sentiment trend by queue (STA enabled)
  - Top 5 topics by volume (STA enabled)
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
| 10 *(telephony NOC)* | `telephony.get.all.edges.metrics` | Multiple Edges | Bulk CPU/memory/call-count across all Edges — faster than N individual calls |

### Polling Note

Real-time datasets (`analytics.query.queue.observations.real.time.stats`,
`analytics.query.conversation.activity.real.time`, `analytics.query.user.observations.real.time.status`)
do not accept `interval` parameters — they reflect the current state as of the API call. These
should be polled at the rate appropriate for the display (typically 10–30 seconds for a wall board).

The `analytics.get.agent.active.status` endpoint returns a single agent's live state and is
intended for targeted drilldown (supervisor clicks on an agent in the wall board).

`telephony.get.all.edges.metrics` (step 10) is the preferred NOC pattern when monitoring more than
two Edges — it accepts a comma-separated `edgeIds` query parameter and returns all metrics in one
response, avoiding rate-limit pressure from N individual requests.

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

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| + | `conversations.get.conversation.customattributes` | `conversationId` | Provider-set custom attributes: CRM case ID, intent label, external call ID |
| + | `conversations.search.participant.attributes` | `conversationId` | IVR/Architect variables set during the injected conversation flow |
| + | `externalcontacts.get.single.contact` | `externalContactId` | CRM contact profile: name, org, custom fields — the caller's full external record |
| + | `externalcontacts.get.contact.journey.sessions` | `contactId` | Digital touchpoints (web/app sessions) linked to this contact before or after the call |

### Resolving External Contact from Conversation

The `externalContactId` is surfaced on participant records with `purpose = "customer"` or `purpose = "external"` inside the conversation object. That ID is the key to both `externalcontacts.get.single.contact` and `externalcontacts.get.contact.journey.sessions`, giving the full omnichannel picture of who the caller is and what they did before contacting the centre.

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
| station | `users.get.user.station` | `userId` | Registered phone/softphone — identifies audio endpoint for quality complaints |

**Trigger conditions:** `currentStatus` and `activeConversations` steps are conditional on the
agent being in an active state at investigation time. `coaching` step is conditional on WFM being
licensed and configured. `station` is always valuable for voice engineers — it confirms which
physical device is in the audio path.

---

## 8. Conversation Investigation Extensions (Release 1.3)

The existing Conversation Investigation (`Get-GenesysConversationInvestigation`) covers 8 steps.
These additional datasets complete the deep-dive picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| analyticsDetail | `analytics.get.single.conversation.analytics` | `conversationId` | Per-segment timing (IVR, ACD wait, talk, hold, ACW) — replaces the query-based analytics step |
| sipTrace | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace (voice only, conditional) |
| sentimentTimeline | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-utterance sentiment (STA enabled only, conditional) |
| staSummary | `speechandtextanalytics.get.conversation.summaries` | `conversationId` | STA-generated reason-for-call, resolution, and topic labels |
| aiSummary | `conversations.get.conversation.summaries` | `conversationId` | Genesys AI concise resolution summary |
| evaluationDetail | `quality.get.single.conversation.evaluation` | `conversationId` + `evaluationId` | Full form answer set per evaluation found in query step |
| surveysDetail | `quality.get.single.conversation.surveys` | `conversationId` | Survey responses directly scoped to this conversation |
| customAttributes | `conversations.get.conversation.customattributes` | `conversationId` | IVR/Architect custom attribute payload |
| participantAttributes | `conversations.search.participant.attributes` | `conversationId` | Participant-level flow variables |
| transcriptUrl | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcript download URL (transcription enabled only) |
| externalContact | `externalcontacts.get.single.contact` | `externalContactId` | CRM record for the caller (if externalContactId present on participant) |
| flowTrace | `flows.query.execution.history` | `conversationId` | Flow execution instances — which version ran, what outcome |
| agentStation | `users.get.user.station` | `userId` (agent participant) | Agent's registered phone device |

**Conditional steps:** `sipTrace` runs only when `conversations.get.conversation.object.participants[].calls` is
non-empty (voice conversation). `sentimentTimeline`, `staSummary` run only when STA analysis status is `"Success"`.
`aiSummary` requires Genesys AI licensing. `evaluationDetail` requires a prior `evaluationId` from the query step.
`externalContact` requires a non-null `externalContactId` on any participant record.

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

## 10. Voice Engineer Network Topology Investigation

**Subject:** One or more `siteId` / `edgeId` / `trunkId` + incident window  
**Use case:** Multiple callers on the same trunk or Edge are reporting call-quality issues — one-way audio,
dropped calls, high latency — but no single `conversationId` is the obvious entry point. The voice
engineer needs to establish the physical and logical topology first, then correlate individual
SIP traces against infrastructure state.

**Core question:** *Which part of the voice infrastructure is degraded and which conversations were affected?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `telephony.get.sites` | — | All Edge sites — names, locations, and site IDs. Identifies the blast radius. |
| 2 | `telephony.get.edges` | `siteId` | Edges registered to each site — online/offline status, software version |
| 3 | `telephony.get.all.edges.metrics` | `edgeId` list | Bulk CPU, memory, active call count, SIP error counters across all Edges in one call |
| 4 | `telephony.get.trunks` | `edgeId` | All SIP trunks, their state, and which Edge they terminate on |
| 5 | `telephony.get.trunk.metrics.summary` | — | Aggregate trunk utilisation and error rates across all trunks |
| 6 | `telephony.get.single.trunk.metrics` | `trunkId` | Drill down: per-trunk active calls, errors, and capacity |
| 7 | `telephony.get.dids` | `didPool.id` or `owner.id` | DID inventory — map from DNIS to its queue or IVR entry point |
| 8 | `telephony.get.phones` | `site.id` | Phone instances at the affected site — HW phones and softphones |
| 9 | `analytics-conversation-details-query` (trunkId/edgeId timewindow) | `conversationId` | All conversations that used this infrastructure during the incident window |
| 10 | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace per affected conversation — correlate trunk errors with specific calls |
| 11 | `telephony.get.edge.performance.metrics` | `edgeId` | Per-Edge real-time metrics for a specific appliance flagged in step 3 |
| 12 *(edge log capture)* | `telephony.create.edge.logs.job` | `edgeId` | Initiate Edge log collection for the affected appliance |
| 13 *(edge log capture)* | `telephony.get.edge.logs.job` | `jobId` | Poll log collection job status |
| 14 *(edge log capture)* | `telephony.request.edge.logs.job.upload` | `jobId` | Request upload of collected log files for offline analysis |

### Key Joins

```
telephony.get.sites[].id (siteId)
  → telephony.get.edges[].site.id (which Edges are on this site?)
  → telephony.get.phones[].site.id (which phones are at this site?)

telephony.get.edges[].id (edgeId)
  → telephony.get.all.edges.metrics (bulk metrics for all edgeIds)
  → telephony.get.edge.performance.metrics.edgeId (drill-down per Edge)
  → telephony.get.trunks[].edge.id (which trunks terminate here?)
  → telephony.create.edge.logs.job.edgeId (capture logs)

telephony.get.trunks[].id (trunkId)
  → telephony.get.single.trunk.metrics.trunkId (per-trunk call counts and errors)

telephony.get.dids[].owner.id (queueId or userId)
  → routing.get.single.queue.config.id (which queue owns this DID?)

analytics-conversation-details-query[].conversationId
  → telephony.get.sip.messages.for.conversation.conversationId (SIP trace per call)
```

### Analytical Questions Answered

- Which Edge sites are in the affected geographic area?
- Is any Edge offline or running a software version mismatch?
- Is any Edge under CPU or memory pressure during the incident window?
- Is any trunk exhausted (active calls near capacity) or reporting high error rates?
- Which DID (phone number) maps to the queue receiving the complaints?
- Which conversations used this trunk/Edge during the incident? (from conversation details)
- Do the SIP traces for affected conversations show a common failure pattern?
- Can we capture Edge logs for the specific appliance to get deeper diagnostics?

### Triage Decision Tree

```
Call quality complaints arrive
  └─ Isolated to one conversationId?
        └─ YES → Pattern 1 (Single Conversation Deep Dive)
        └─ NO → Pattern 10 (Network Topology Investigation)
              ├─ Check edges.metrics for CPU/memory spikes
              ├─ Check trunk.metrics for error rate or capacity issues
              └─ Fan out to SIP traces for affected conversationIds
```

### Voice Engineer Notes

- Step 3 (`telephony.get.all.edges.metrics`) uses the `edgeIds` query parameter as a
  comma-separated list — pull all Edge IDs from step 2 and batch them in a single request rather
  than making one request per Edge.
- Steps 12–14 (edge log capture) are destructive-adjacent operations — they initiate a job on the
  live appliance. Confirm with the network team before triggering in a production environment.
- `telephony.get.dids` is particularly valuable for voice engineers investigating DID routing
  issues where a customer reports calling the "wrong number" — look up the DNIS from the
  conversation object and resolve it to its queue or IVR owner via the DID inventory.

---

## 11. Architect Flow Investigation

**Subject:** One `flowId` (or one `conversationId` with unexpected routing behaviour)  
**Use case:** An Architect developer or contact centre admin observes unexpected flow behaviour —
wrong branch taken, outcome not matching expected logic, IVR variables not being set correctly,
or callers landing in the wrong queue. They need to see the actual execution trace, not just the
designed flow.

**Core question:** *What did the flow actually do when it executed, and does it match the design?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Identifies the flow entry point, queue assigned, and whether externalTag indicates BYOI injection |
| 2 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by the flow — intent labels, account numbers, escalation flags |
| 3 | `conversations.search.participant.attributes` | `conversationId` | Participant-level variables set in flow actions (data action outputs, Set Participant Data results) |
| 4 | `flows.query.execution.history` | `conversationId` | Flow execution record — flowId, version, start/end time, outcome, milestones hit |
| 5 | `flows.get.single.execution` | `flowExecutionId` from step 4 | Full step-level execution trace — each block executed, variable state, errors |
| 6 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing — IVR duration confirms flow runtime, ACD wait confirms queue assignment timing |
| 7 | `flows.get.all.flows` | `flowId` from step 4 | Flow definition metadata — name, type, published version, author |
| 8 | `flows.get.flow.outcomes` | `flowId` | Outcome definitions — maps outcome IDs from step 4/5 to human-readable labels |
| 9 | `flows.get.flow.milestones` | `flowId` | Milestone definitions — maps milestone IDs to checkpoint names |
| 10 | `analytics.query.flow.aggregates.execution.metrics` (flowId filter) | `flowId` | Aggregate outcome and milestone frequencies — is this a systemic issue or isolated? |

### Key Joins

```
conversations.get.conversation.object → identifies flowId (from participant routingRules or attributes)

flows.query.execution.history[].id (flowExecutionId)
  → flows.get.single.execution.flowExecutionId (step-level trace)

flows.get.single.execution → flowId, outcomeId, milestoneIds

flowId
  → flows.get.all.flows[].id (flow name and version)
  → flows.get.flow.outcomes[].flowId (outcome label lookup)
  → flows.get.flow.milestones[].flowId (milestone label lookup)
  → analytics.query.flow.aggregates.execution.metrics (frequency analysis)
```

### Analytical Questions Answered

- Which flow version executed for this conversation?
- Which outcome did the flow produce? Does it match the intended logic?
- Which flow milestones were hit? Which were missed?
- What variables were set by the flow's data actions and Set Participant Data blocks?
- Is this outcome occurring on every call, or just this one? (aggregate metrics)
- How long did the IVR phase last? Does it match expected flow execution time?
- Is the issue reproducible across multiple conversations using the same flow?

### Flow Investigation Notes

Step 4 (`flows.query.execution.history`) requires the Flow Execution History feature to be enabled
(`GET /api/v2/flows/instances/settings/executiondata` must return `enabled: true`). Without this,
execution data is not stored.

Step 5 (`flows.get.single.execution`) returns the detailed step-level trace and is the primary
debugging tool. Variable state at each step tells the developer what the flow "saw" at that moment.

Combine steps 4–5 with step 3 (`conversations.search.participant.attributes`) to cross-validate
what the flow set vs what the conversation record captured — discrepancies indicate a timing issue
or missing Set Participant Data block.

---

## 12. Workforce Alignment Investigation

**Subject:** One `managementUnitId` + schedule week  
**Use case:** A WFM analyst, operations manager, or HR team needs to understand whether agents are
following their assigned schedules — which agents are non-adherent, by how much, and whether the
variance correlates with handle time or quality outcomes.

**Core question:** *Are agents working when scheduled, and does non-adherence affect performance?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `workforce.get.management.units` | — | All WFM management units — names and IDs for scoping |
| 2 | `workforce.get.management.unit.users` | `managementUnitId` | Agent roster for the management unit with user IDs |
| 3 | `workforce.get.management.unit.adherence` | `managementUnitId` | Scheduled vs. actual routing state per agent — adherence percentage and variance |
| 4 | `analytics.query.user.aggregates.login.activity` | `userId` list | Actual on-queue vs. off-queue time per agent — confirm against scheduled on-queue hours |
| 5 | `analytics.query.user.details.activity.report` | `userId` list | State-change event timeline — granular login/logout/status change sequence |
| 6 | `analytics.query.conversation.aggregates.agent.performance` | `userId` list | Actual handle volume and AHT per agent — does adherence correlate with productivity? |
| 7 | `quality.get.agents.activity` | `userId` list | QM scores per agent — does adherence correlate with quality? |
| 8 *(coaching follow-up)* | `coaching.get.appointments` | `userId` list | Coaching sessions — are non-adherent agents receiving coaching? |

### Key Joins

```
workforce.get.management.unit.users[].user.id (userId)
  → workforce.get.management.unit.adherence[].user.id (scheduled vs actual state)
  → analytics.query.user.aggregates.login.activity[].group.userId (actual on-queue hours)
  → analytics.query.user.details.activity.report[].userId (state-change timeline)
  → analytics.query.conversation.aggregates.agent.performance[].group.userId (productivity)
  → quality.get.agents.activity[].user.id (quality scores)
  → coaching.get.appointments[].attendees[].id (coaching coverage)
```

### Analytical Questions Answered

- Which agents have the lowest adherence percentage?
- How much variance exists between scheduled and actual routing status per agent?
- Does low adherence correlate with lower handle volume or higher AHT?
- Does low adherence correlate with lower QM scores?
- Are non-adherent agents receiving coaching? Is there a corrective action record?
- What time of day or day of week does non-adherence peak?

### WFM Integration Notes

`workforce.get.management.unit.adherence` (`GET /api/v2/workforcemanagement/adherence`) accepts
a `userId` query parameter list and returns the current adherence state. For historical adherence
analysis covering a longer window, use the async historical adherence endpoints
(`POST /api/v2/workforcemanagement/adherence/historical/bulk`), which are not yet promoted to
catalog datasets but are available in the endpoints section.

WFM datasets require the Workforce Management license. The `coaching.get.appointments` step
additionally requires the Coaching add-on. Always check license availability before including
these steps in an automated investigation.

---

## 13. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | Network Topology | Flow Investigation | WFM Alignment |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | ● | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | ● | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | ● | |
| `conversations.search.participant.attributes` | ● | | | | | | | ● | |
| `conversations.get.conversation.summaries` | ○ | | | ○ | | | | | |
| `speechandtextanalytics.get.conversation.summaries` | ○ | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | |
| `quality.get.single.conversation.evaluation` | ○ | | | | | | | | |
| `quality.get.single.conversation.surveys` | ● | | | | | | | | |
| `quality.get.surveys` | | | | ● | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | ○ | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | |
| `externalcontacts.get.single.contact` | ○ | | | | | | | | |
| `externalcontacts.get.contact.journey.sessions` | ○ | | | | | | | | |
| `flows.query.execution.history` | ○ | | | | | | | ● | |
| `flows.get.single.execution` | | | | | | | | ● | |
| `users.get.user.station` | ○ | | | | | ○ | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ○ | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | |
| `routing-queue-members` | | ● | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | ● |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | ● |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | ● |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | ● |
| `coaching.get.appointments` | | | ● | | | ○ | | | ○ |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | | ● | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | ● | | |
| `telephony.get.single.trunk.metrics` | | | | | | | ● | | |
| `telephony.get.all.edges.metrics` | | | | | ● | | ● | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | ● | | |
| `telephony.get.edges` | | | | | | | ● | | |
| `telephony.get.sites` | | | | | | | ● | | |
| `telephony.get.trunks` | | | | | | | ● | | |
| `telephony.get.phones` | | | | | | | ● | | |
| `telephony.get.dids` | | | | | | | ● | | |
| `telephony.create.edge.logs.job` | | | | | | | ○ | | |
| `telephony.get.edge.logs.job` | | | | | | | ○ | | |
| `telephony.request.edge.logs.job.upload` | | | | | | | ○ | | |
| `alerting.get.alerts` | | | | ○ | ● | | | | |
| `alerting.get.rules` | | | | | ○ | | | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | |
| `users.get.user.routing.skills` | | | | | | ● | | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | |
| `audit-logs` | | | | | | ● | | | |
| `flows.get.all.flows` | | | | | | | | ● | |
| `flows.get.flow.outcomes` | | | | | | | | ● | |
| `flows.get.flow.milestones` | | | | | | | | ● | |
| `workforce.get.management.units` | | | | | | | | | ● |
| `workforce.get.management.unit.users` | | | | | | | | | ● |
| `workforce.get.management.unit.adherence` | | | ○ | | | | | | ● |

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
| `nFlow` | Flow executions | IVR/flow volume |
| `nFlowOutcome` | Flow executions that produced an outcome | Outcome coverage |
| `nFlowOutcomeFailed` | Failed flow outcomes | IVR failure rate |

---

## Appendix: New Datasets Summary (2026-05-20)

Fourteen datasets added in this release. All have `validationStatus: "unvalidated"` — validate
against a live org before using in production investigation workflows.

| New Dataset Key | API Path | Investigation Value |
|----------------|----------|---------------------|
| `conversations.get.conversation.summaries` | `GET /api/v2/conversations/{conversationId}/summaries` | AI resolution summary — conversation deep dive, executive spot-check |
| `speechandtextanalytics.get.conversation.summaries` | `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/summaries` | STA reason-for-call and topic labels — conversation deep dive |
| `telephony.get.sites` | `GET /api/v2/telephony/providers/edges/sites` | Edge site topology — network topology investigation seed |
| `telephony.get.phones` | `GET /api/v2/telephony/providers/edges/phones` | Phone inventory at site — audio endpoint identification |
| `telephony.get.dids` | `GET /api/v2/telephony/providers/edges/dids` | DID → queue/owner mapping — DNIS resolution |
| `telephony.get.all.edges.metrics` | `GET /api/v2/telephony/providers/edges/metrics` | Bulk edge metrics — NOC monitoring, site-wide health |
| `telephony.get.single.trunk.metrics` | `GET /api/v2/telephony/providers/edges/trunks/{trunkId}/metrics` | Per-trunk call count + errors — trunk drill-down |
| `quality.get.single.conversation.evaluation` | `GET /api/v2/quality/conversations/{conversationId}/evaluations/{evaluationId}` | Full form answer set — QM investigation drill-down |
| `quality.get.single.conversation.surveys` | `GET /api/v2/quality/conversations/{conversationId}/surveys` | Scoped survey fetch — conversation deep dive |
| `flows.query.execution.history` | `POST /api/v2/flows/instances/query` | Flow execution records for a conversation — flow investigation |
| `flows.get.single.execution` | `GET /api/v2/flows/executions/{flowExecutionId}` | Step-level flow trace — Architect debugging |
| `externalcontacts.get.single.contact` | `GET /api/v2/externalcontacts/contacts/{contactId}` | CRM contact record — BYOI and external contact enrichment |
| `externalcontacts.get.contact.journey.sessions` | `GET /api/v2/externalcontacts/contacts/{contactId}/journey/sessions` | Digital journey sessions — omnichannel customer view |
| `users.get.user.station` | `GET /api/v2/users/{userId}/station` | Agent's registered phone/softphone — audio endpoint audit |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
