# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-24  
> Companion to: [INVESTIGATIONS.md](INVESTIGATIONS.md), [ROADMAP.md](ROADMAP.md)

This document describes how catalog datasets combine into coherent investigations and executive
reporting rollups. Each combination is documented with its subject, the ordered dataset steps,
the join keys that connect them, and the analytical questions it answers.

The goal of Genesys.Core is to be **informative without being a data dump**. Every combination
here answers a specific operational question and terminates when that question is answered — not
when the API is exhausted.

All five investigation recipes (`single-conversation-investigation`, `agent-investigation`,
`queue-investigation`, `division-investigation`, `campaign-investigation`) are now codified in
`catalog/genesys.catalog.json` under `combinations.investigationRecipes`. The executive and
voice-engineer playbooks live under `combinations.executiveReportingPlaybooks` and
`combinations.voiceEngineerPlaybooks` respectively.

---

## Contents

1. [Single Conversation Deep Dive (Voice Engineer)](#1-single-conversation-deep-dive-voice-engineer)
2. [All Conversations in a Queue](#2-all-conversations-in-a-queue)
3. [Division / Agent Group Investigation](#3-division--agent-group-investigation)
4. [Campaign Investigation](#4-campaign-investigation)
5. [Executive Reporting Rollup](#5-executive-reporting-rollup)
6. [Real-Time Operations Monitoring](#6-real-time-operations-monitoring)
7. [BYOI External Conversation Enrichment](#7-byoi-external-conversation-enrichment)
8. [Agent Investigation Extensions](#8-agent-investigation-extensions)
9. [Conversation Investigation Extensions](#9-conversation-investigation-extensions)
10. [Queue Investigation Extensions](#10-queue-investigation-extensions)
11. [Dataset Combination Reference Matrix](#11-dataset-combination-reference-matrix)

---

## 1. Single Conversation Deep Dive (Voice Engineer)

**Subject:** One `conversationId`  
**Catalog recipe key:** `single-conversation-investigation`  
**Use case:** A voice engineer or QM analyst receives a complaint about a specific call — wrong queue,
long hold, audio quality, dropped call, incorrect routing. They need the complete picture: where it
came from, how it routed, how long each phase took, what the SIP signaling said, whether a recording
exists, what the quality score was, and what the customer and agent said.

**Core question:** *What actually happened in this conversation, end-to-end?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.get.single.conversation.analytics` | seed → `conversationId` | Per-segment timing: IVR duration, ACD wait, talk time, hold time, ACW, conference, recording start/stop |
| 2 | `conversations.get.specific.conversation.details` | `conversationId` | Media type, state, participants, ANI/DNIS, originating direction, externalTag (BYOI indicator) |
| 3 | `conversations.get.conversation.participant.wrapup` | `conversationId` + `participantId` | Wrapup code per agent participant — iterated over agent participants from step 2 |
| 4 | `conversations.get.call.detail` | `conversationId` | Voice-specific call legs, hold/mute events, ANI/DNIS routing path (voice only) |
| 5 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs, media type, duration, archival policy |
| 6 | `conversations.get.recordings` | `conversationId` | Signed recording download URLs |
| 7 | `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | `conversationId` | Top-level S&TA: overall sentiment, silence %, overtalk count, analysis status |
| 8 *(STA enabled)* | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic and category classifications from the S&TA engine |
| 9 *(STA enabled)* | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | AI-generated per-leg S&TA summaries |
| 10 *(transcription enabled)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId` + `communicationId` | Transcript download URL per communication leg |
| 11 | `conversations.get.conversation.summaries` | `conversationId` | Copilot AI summary — reason-for-contact, resolution notes, next-step suggestions |
| 12 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by IVR/Architect flows (account numbers, intent, escalation flags) |
| 13 | `conversations.search.participant.attributes` | `conversationId` | Participant-level IVR/Architect flow variables and data action outcomes |
| 14 | `quality.get.evaluations.query` | `conversationId` | QM evaluation scores, form used, evaluator, calibration status |
| 15 | `quality.get.conversation.surveys` | `conversationId` | Post-call CSAT/NPS survey result and completion status |
| 16 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling: INVITE, 200 OK, BYE, re-INVITE, codec negotiation |

### Key Joins

```
analytics.get.single.conversation.analytics.conversationId
  → conversations.get.specific.conversation.details.id (overlay)
  → conversations.get.conversation.recording.metadata.conversationId
  → telephony.get.sip.messages.for.conversation.conversationId (voice only)
  → quality.get.evaluations.query[].conversationId (left join)
  → quality.get.conversation.surveys[].conversationId (left join)

analytics.get.single.conversation.analytics.participants[].sessions[].communicationId
  → speechandtextanalytics.get.conversation.communication.transcripturl.communicationId

conversations.get.specific.conversation.details.participants[].id (purpose=agent)
  → conversations.get.conversation.participant.wrapup.participantId (iterated)
```

### Analytical Questions Answered

- What was the full call flow? (IVR → ACD → agent → hold → ACW)
- How long did the customer wait before an agent answered?
- Was the call transferred? How many times? What queue received the transfer?
- Was a recording made? Does it still exist?
- Did the SIP trunk establish media correctly? (from SIP trace)
- Was the agent evaluated? What was the QM score?
- Was the customer surveyed? What was the CSAT result?
- What intent/attributes did the IVR capture before routing?
- What was the overall sentiment? Were any compliance topics detected?
- What did Copilot summarise as the reason for contact and resolution?

### Voice Engineer Notes

Step 16 (SIP trace) is the definitive source for:
- Call setup failures (no 200 OK, 486 Busy, 503 Service Unavailable)
- One-way audio (media IP mismatch in SDP)
- Premature disconnection (BYE before expected, no 200 OK to BYE)
- Codec negotiation failures

The `telephony.get.edge.performance.metrics` dataset (`GET /api/v2/telephony/providers/edges/{edgeId}/metrics`)
should be pulled for the Edge appliance that handled the call if CPU, memory, or error counters suggest
resource pressure during the conversation window.

### BYOI Indicator

If `conversations.get.specific.conversation.details` returns a non-null `externalTag` or
`externalConversationId`, the call was injected via the BYOI integration
(`POST /api/v2/conversations/providers/{providerId}/calls`). Custom attributes in step 12 will
contain the provider's context (CRM case ID, external call ID). The SIP trace (step 16) will
reflect the provider's SIP-to-SIP handoff, not an inbound PSTN leg.

---

## 2. All Conversations in a Queue

**Subject:** One `queueId` + time window  
**Catalog recipe key:** `queue-investigation`  
**Use case:** A contact centre supervisor or operations analyst needs to understand the health and
behaviour of a specific queue over a period — volume patterns, handle times, abandons, transfer
rates, and wrapup outcomes.

**Core question:** *How did this queue perform, and what were the conversations like?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing-queues` | seed → `queueId` | Queue name, routing method, SLA targets, media types, scoring method |
| 2 | `routing.get.queue.wrapup.codes` | `queueId` | Human-readable wrapup code labels for the queue |
| 3 | `routing.get.queue.members.with.status` | `queueId` | Current membership roster with routing status, presence, and conversation summary |
| 4 | `analytics.query.queue.observations.real.time.stats` | `queueId` | Live queue counters: oInteracting, oWaiting, oOnQueueUsers, oOffQueueUsers |
| 5 | `routing.get.queue.estimated.wait.time` | `queueId` | Real-time EWT in seconds — compare to SLA target for immediate action |
| 6 | `analytics.query.user.observations.real.time.status` | `queueId` (member-scoped) | Per-agent presence and routing status snapshot |
| 7 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | nConnected, tHandle, tTalk, tAcw, tAnswered, nOffered |
| 8 | `analytics.query.queue.aggregates.service.level` | `queueId` | SLA achievement: nAnsweredIn20/30/60, oServiceLevel, nOverSla |
| 9 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon count: nAbandoned, tAbandon, tShortAbandon |
| 10 | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer analysis: nTransferred, nBlindTransferred, nConsultTransferred |
| 11 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` + wrapUpCode | Wrapup code frequencies (join step 2 for labels) |
| 12 | `analytics.query.conversation.details.by.queue` | `queueId` | Every conversation that touched this queue in the window — seed for per-conversation drilldown |
| 13 | `quality.get.evaluations.query` (queueId filter) | `conversationId` | QM evaluation coverage and scores for conversations in this queue |

### Key Joins

```
routing-queues.id
  → analytics.query.conversation.aggregates.*.results[].group.queueId (aggregate overlay)
  → routing.get.queue.members.with.status.queueId (who was staffed)

analytics.query.conversation.aggregates.wrapup.distribution[].group.wrapUpCode
  → routing.get.queue.wrapup.codes[].id (label resolution)

analytics.query.conversation.details.by.queue[].conversationId
  → quality.get.evaluations.query[].conversationId (left join)
```

### Analytical Questions Answered

- What was the offered/connected/abandoned volume for this queue?
- Did the queue meet its SLA target? In which hourly intervals did it miss?
- What is the estimated wait time right now?
- What percentage of conversations were transferred? Where did they go?
- What wrapup codes dominated, and what do they mean?
- Who were the active agents? What was their routing status?
- How many conversations were quality-reviewed? What was the average score?

### Divisions as Queue Groups

Queues within a division represent a natural management boundary. To investigate an entire division:
1. Use `authorization.search.division.objects` (objectType=QUEUE) to get all queue IDs in the division.
2. Fan out the steps above once per queue, or use `authorization.get.single.division` as the seed and
   filter analytics queries with `divisionId` predicates.

---

## 3. Division / Agent Group Investigation

**Subject:** One `divisionId` + time window  
**Catalog recipe key:** `division-investigation`  
**Use case:** A contact centre director or workforce analyst needs to understand how a specific
business unit (division) performed — which agents are in it, what volume each handled, time-in-state,
quality scores, and coaching coverage.

**Core question:** *How did this division's agents perform as a group?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `authorization.get.all.divisions` (filter by divisionId) | seed → `divisionId` | Division name, description, home-division flag |
| 2 | `authorization.search.division.objects` (objectType=QUEUE) | `divisionId` | All queue IDs assigned to this division |
| 3 | `users.division.analysis.get.users.with.division.info` | `divisionId` | All agents assigned to the division with user IDs, email, state |
| 4 | `authorization.get.division.grants` | `divisionId` | Access control grants — subjects and roles with division-scoped permissions |
| 5 | `analytics.query.user.aggregates.performance.metrics` (userId list) | `userId` | Per-agent: nConnected, tHandle, tTalk, tAcw |
| 6 | `analytics.query.conversation.aggregates.by.division` | `divisionId` | Division-level KPI rollup: nConnected, nOffered, tHandle, tTalk by day |
| 7 | `analytics.query.conversation.aggregates.queue.performance` (queueId list) | `queueId` | Per-queue SLA, abandon, handle metrics for all queues in the division |
| 8 | `quality.get.evaluations.query` (userId list) | `userId` | QM evaluation counts and scores per agent |

### Key Joins

```
authorization.get.all.divisions[filtered].id
  → authorization.search.division.objects[].divisionId (queue enumeration)
  → users.division.analysis.get.users.with.division.info[].divisionId (agent enumeration)

users.division.analysis.get.users.with.division.info[].id
  → analytics.query.user.aggregates.performance.metrics[].userId
  → quality.get.evaluations.query[].agent.id

authorization.search.division.objects[].id (objectType=QUEUE)
  → analytics.query.conversation.aggregates.queue.performance[].group.queueId
```

### Analytical Questions Answered

- How many agents are in this division and who are they?
- What queues does this division own?
- What was the division's total handled volume and AHT for the period?
- Which agents handled the most volume? Which had the highest AHT?
- Which agents have been evaluated? Who has the highest/lowest scores?
- Who has admin-level or elevated permissions in this division?

### Division vs Queue as Investigation Entry Point

| Start with | When you know | You get |
|------------|---------------|---------|
| `queueId` | Specific queue complaints | All conversations + SLA + wrapup + member roster |
| `divisionId` | Business unit or team scope | All queues + all agents + group performance |
| `userId` (Agent Investigation) | Specific agent complaint | That agent's conversations + skills + presence |

---

## 4. Campaign Investigation

**Subject:** One `campaignId` + time window  
**Catalog recipe key:** `campaign-investigation`  
**Use case:** An outbound operations manager needs to understand how a specific dialing campaign
performed — contact rates, dialer dispositions, compliance abandon thresholds, and the individual
conversations it generated.

**Core question:** *Is this campaign reaching the right contacts, staying within compliance, and producing quality conversations?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Campaign status, dialing mode, configured abandon threshold, connected queueId |
| 2 | `outbound.get.contact.lists` | `contactListId` (from campaign) | Contact list size and import status — baseline for list penetration |
| 3 | `routing.get.single.queue.config` | `queueId` (from campaign) | Connected queue metadata — routing mode and ACW settings for answered calls |
| 4 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Live diagnostics: lines in use, contacts dialed, abandon tally |
| 5 | `outbound.get.events` | `campaignId` | All dialer events and dispositions — right-party connects, machine detections, abandon events |
| 6 | `outbound.get.messaging.campaigns` | `campaignId` | SMS/digital messaging metrics if the campaign has a messaging leg |
| 7 | `audit-logs` (EntityType=Campaign) | `campaignId` | Configuration change history — start/stop, abandon threshold edits |
| 8 | `analytics-conversation-details-query` (campaignId filter) | `campaignId` | All connected conversations — agent performance, wrapup, AHT per call |

### Key Joins

```
outbound.get.campaigns.id
  → outbound.get.contact.lists.id (contactListId)
  → routing.get.single.queue.config.id (queueId)
  → outbound.get.campaign.diagnostics.summary.campaignId
  → outbound.get.events[].campaignId

analytics-conversation-details-query[].conversationId
  → analytics.get.single.conversation.analytics (drilldown per call)
```

### Analytical Questions Answered

- What percentage of the contact list has been dialed? (list penetration)
- Is the campaign's abandon rate below the configured compliance threshold?
- What dispositions (right-party connect, answering machine, busy, abandon) is the dialer producing?
- For connected calls, what was the average handle time and wrapup distribution?
- Were any campaign configuration changes made during the run? (compliance audit trail)
- Is the messaging leg (SMS) achieving expected delivery rates?

### Derived Metrics

```
listPenetrationPct    = diagnostics.numberOfContactsDialed / contactList.size × 100
currentAbandonRate    = diagnostics.progressAbandoned / diagnostics.numberOfContactsDialed × 100
rightPartyContactRate = count(events where eventType=RightPartyContact) / numberOfContactsDialed × 100
```

---

## 5. Executive Reporting Rollup

**Subject:** Organisation-wide (or multi-queue) + reporting window (weekly/monthly)  
**Catalog playbook keys:** `service-level-and-abandon-kpis`, `agent-performance-scorecard`,
`wrapup-and-transfer-analysis`, `quality-and-csat-summary`, `speech-text-analytics-sentiment-trends`,
`digital-channel-volume-and-sla`, `wfm-adherence-and-occupancy`, `outbound-campaign-performance`,
`flow-and-ivr-performance`  
**Use case:** A VP or Director of Operations needs a concise performance summary — not a data dump,
but the headline KPIs grouped logically.

**Core question:** *How did the contact centre perform this period, by which dimensions?*

### Dataset Steps (ordered by reporting layer)

#### Layer 1 — Volume & Efficiency
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `routing-queues` | `queueId` | Queue roster and metadata |
| `analytics.query.conversation.aggregates.queue.performance` | `queueId`, `mediaType`, daily | nOffered, nConnected, tHandle (avg), tTalk (avg), tAcw (avg) |
| `analytics.query.conversation.aggregates.abandon.metrics` | `queueId`, `mediaType`, daily | nAbandoned, tAbandon, nOffered (abandon rate = nAbandoned/nOffered) |
| `analytics.query.conversation.aggregates.digital.channels` | `mediaType`, `queueId`, daily | Channel mix: nOffered, nConnected by voice/chat/email/message |

#### Layer 2 — Service Quality
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.queue.aggregates.service.level` | `queueId`, daily | oServiceLevel, nOverSla, nAnsweredIn20/30/60 |
| `analytics.query.conversation.aggregates.transfer.metrics` | `queueId`, daily | Transfer rate: nTransferred / nConnected |
| `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId`, `wrapUpCode`, daily | Wrapup mix — outcome analysis |
| `routing.get.all.wrapup.codes` | — | Global wrapup code label resolution |

#### Layer 3 — Workforce
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.query.user.aggregates.login.activity` | `userId`, daily | tAgentRoutingStatus: available, busy, on-queue time per agent |
| `analytics.query.user.aggregates.performance.metrics` | `userId`, daily | nConnected, tHandle (avg) per agent |
| `workforce.get.management.unit.adherence` | `userId` | Scheduled vs. actual adherence % per agent |

#### Layer 4 — Quality & Voice-of-Customer
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `quality.get.agents.activity` | `userId` | Evaluation coverage rate, average score, score distribution |
| `quality.get.surveys` | aggregate | CSAT/NPS: response rate, average score |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | STA coverage: nAnalyzedConversations, oSentimentScore |
| `speechandtextanalytics.get.topics` | — | Topic definitions for frequency analysis |

#### Layer 5 — Infrastructure Health (voice-focused)
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `telephony.get.trunk.metrics.summary` | — | SIP trunk utilisation and errors |
| `telephony.get.edges` | `edgeId` | Edge registration status |
| `alerting.get.alerts` | — | Currently firing threshold alerts |

### Executive Dashboard Composition Pattern

```
Period: Last 28 days, daily granularity
Queues: All production queues (routing-queues filtered by active=true)

Headline metrics (computed):
  Total handled:     SUM(nConnected) across all queues
  Abandon rate:      SUM(nAbandoned) / SUM(nOffered) × 100
  Avg handle time:   WAVG(tHandle, nConnected)
  SLA achievement:   queues meeting target / total queues × 100
  Transfer rate:     SUM(nTransferred) / SUM(nConnected) × 100
  QM coverage:       evaluations / nConnected × 100
  Avg QM score:      from quality.get.agents.activity
  Avg CSAT:          from quality.get.surveys
  STA coverage:      nAnalyzedConversations / nConnected × 100
  Avg sentiment:     from analytics.post.transcripts.aggregates.query
```

---

## 6. Real-Time Operations Monitoring

**Subject:** Organisation or specific queues (no fixed window — point-in-time)  
**Catalog playbook keys:** `queue-saturation-and-staffing-analysis`, `trunk-and-edge-health-check`  
**Use case:** A real-time analyst, supervisor, or NOC team needs a live view of queue health and
agent availability right now.

**Core question:** *What is happening in the contact centre this moment?*

### Dataset Steps (real-time, polling pattern)

| Step | Dataset Key | Scope | What It Shows |
|------|-------------|-------|---------------|
| 1 | `analytics.query.queue.observations.real.time.stats` | All queues | oInteracting, oWaiting, oOnQueueUsers, oOffQueueUsers per queue |
| 2 | `routing.get.queue.estimated.wait.time` | One queue | Real-time EWT in seconds — immediate staffing signal |
| 3 | `analytics.query.conversation.activity.real.time` | All queues | oInteracting, oWaiting, oAlerting, oLongestWaiting per queue × mediaType |
| 4 | `analytics.query.user.observations.real.time.status` | All agents | oUserPresence, oUserRoutingStatus per agent |
| 5 | `analytics.get.agent.active.status` | One agent | Full real-time channel assignment and active conversation IDs |
| 6 | `users.get.agent.active.conversations` | One agent | All in-progress conversations for a specific agent |
| 7 | `users.get.agent.current.routing.status` | One agent | Current routing state (IDLE / INTERACTING / NOT_RESPONDING / OFF_QUEUE) |
| 8 | `analytics.query.flow.observations` | All flows | Active Architect flows currently executing |
| 9 *(telephony NOC)* | `telephony.get.trunk.metrics.summary` | — | Trunk utilisation and error counters |
| 10 *(telephony NOC)* | `telephony.get.edge.performance.metrics` | One Edge | CPU, memory, active call count on specific Edge |

### Queue Saturation Diagnostic Signals

| Signal | Meaning | Action |
|--------|---------|--------|
| oWaiting > 0 + oOnQueueUsers = 0 | No agents staffed | Escalate immediately |
| EWT > SLA target | Callers will exceed target | Supervisor intervention |
| oOffQueueUsers high vs oOnQueueUsers | Agents logged in but not ready | Presence audit |
| oInteracting / oOnQueueUsers > 0.90 | Agents fully occupied | Queue will build |
| Presence = 'On Queue' + routingStatus = 'NOT_RESPONDING' | Ghost agents | Check station registration |

### Polling Note

Real-time datasets do not accept `interval` parameters — they reflect the current state as of the
API call. Poll at 10–30 seconds for wallboards. The single-agent drilldown datasets (`analytics.get.agent.active.status`,
`users.get.agent.active.conversations`) are intended for targeted supervisor drilldown when a specific
agent is clicked.

---

## 7. BYOI External Conversation Enrichment

**Subject:** One `conversationId` that was injected via BYOI  
**Use case:** A conversation originated in an external system and was injected into Genesys Cloud
via the BYOI provider API (`POST /api/v2/conversations/providers/{providerId}/calls`).

**Core question:** *Where did this conversation come from, and what external context does it carry?*

### How to Identify a BYOI Conversation

In step 2 of the Conversation Investigation, `conversations.get.specific.conversation.details` returns:

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
`conversations.get.specific.conversation.details`. The condensed view used by the embedded client
includes: `participants[].purpose`, `participants[].state`, `participants[].calls[].state`,
`participants[].calls[].muted`, `participants[].calls[].held`. These fields are present in the
full object returned by the dataset and need no special handling.

---

## 8. Agent Investigation Extensions

The Agent Investigation (`Get-GenesysAgentInvestigation`) covers 16 steps in the catalog recipe.
These are the key extensions for enriched investigations.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| utilization | `routing.get.user.utilization` | `userId` | Max channel capacities — why can the agent only handle N simultaneous chats? |
| currentStatus | `users.get.agent.current.routing.status` | `userId` | Routing state at investigation time (IDLE / INTERACTING / OFF_QUEUE) |
| activeConversations | `users.get.agent.active.conversations` | `userId` | In-progress conversations if `currentStatus = INTERACTING` |
| qualityActivity | `quality.get.agents.activity` | `userId` | Evaluation count, average/highest/lowest scores for the window |
| coaching | `coaching.get.appointments` | `userId` | Coaching sessions attending/facilitating in the window |
| wfmUnit | `workforce.get.agent.management.unit` | `userId` | WFM management unit — entry point for schedule and adherence |
| adherence | `workforce.get.adherence.bulk` | `userId` | Scheduled vs. actual state with adherence % and impact |

**Trigger conditions:** `currentStatus` and `activeConversations` are conditional on the agent
being in an active state at investigation time. `coaching` and adherence steps are conditional on
WFM being licensed.

---

## 9. Conversation Investigation Extensions

The Conversation Investigation (`Get-GenesysConversationInvestigation`) includes these per-conversation
datasets. Use the full recipe key `single-conversation-investigation` for the complete ordered sequence.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| analyticsDetail | `analytics.get.single.conversation.analytics` | `conversationId` | Per-segment timing (IVR, ACD wait, talk, hold, ACW) |
| callDetail | `conversations.get.call.detail` | `conversationId` | Voice call legs, hold events, DNIS routing path (voice only) |
| participantWrapup | `conversations.get.conversation.participant.wrapup` | `participantId` | Per-agent wrapup selection (iterated) |
| aiSummaries | `conversations.get.conversation.summaries` | `conversationId` | Copilot reason-for-contact and resolution notes |
| staOverview | `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | `conversationId` | Overall sentiment, silence %, overtalk |
| staCategories | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Topic and category classifications |
| staSummaries | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | AI-generated per-leg S&TA summaries |
| sipTrace | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling (voice only, conditional) |
| surveyResult | `quality.get.conversation.surveys` | `conversationId` | Per-conversation CSAT/NPS result |
| customAttributes | `conversations.get.conversation.customattributes` | `conversationId` | IVR/Architect custom attribute payload |
| participantAttributes | `conversations.search.participant.attributes` | `conversationId` | Participant-level flow variables |
| transcriptUrl | `speechandtextanalytics.get.conversation.communication.transcripturl` | `communicationId` | Transcript download URL |

**Conditional steps:** `callDetail` and `sipTrace` run only for voice conversations. `staCategories`,
`staSummaries`, and `transcriptUrl` run only when the S&TA overview returns `analysisStatus = "Success"`.

---

## 10. Queue Investigation Extensions

The Queue Investigation (`Get-GenesysQueueInvestigation`) includes the following enrichment steps.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| queueConfig | `routing-queues` | `queueId` | Full queue config (routing method, ACW, SLA targets) |
| wrapupLabels | `routing.get.queue.wrapup.codes` | `queueId` | Human-readable labels for the wrapup distribution |
| currentEWT | `routing.get.queue.estimated.wait.time` | `queueId` | Real-time estimated wait time in seconds |
| transfers | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer rate and type breakdown |
| wrapupDistribution | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Wrapup code frequencies |
| conversationDetail | `analytics.query.conversation.details.by.queue` | `queueId` | Individual conversations for case-level review |
| evaluations | `quality.get.evaluations.query` | `conversationId` | QM evaluations for conversations in this queue |

---

## 11. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conv. Deep Dive | Queue Inv. | Division Inv. | Campaign Inv. | Exec Rollup | Real-Time | Agent Inv. |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `analytics.get.single.conversation.analytics` | ● | | | | | | |
| `conversations.get.specific.conversation.details` | ● | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ● | | | | | | |
| `conversations.get.call.detail` | ○ | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | |
| `conversations.get.recordings` | ● | | | | | | |
| `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | ● | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | |
| `conversations.get.conversation.summaries` | ● | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | ○ | | | | ● |
| `quality.get.conversation.surveys` | ● | | | | ○ | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | |
| `routing-queues` | | ● | | | ● | | |
| `routing.get.queue.wrapup.codes` | | ● | | | | | |
| `routing.get.queue.members.with.status` | | ● | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | | ● | |
| `routing.get.queue.estimated.wait.time.by.media` | | ○ | | | | ○ | |
| `analytics.query.queue.observations.real.time.stats` | | ● | | | | ● | |
| `analytics.query.conversation.activity.real.time` | | | | | | ● | |
| `analytics.query.user.observations.real.time.status` | | ● | | | | ● | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | ○ | | ● | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | | ● | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | | ● | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | | ● | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | | | ● | | |
| `analytics.query.conversation.details.by.queue` | | ● | | | | | |
| `analytics.query.conversation.aggregates.by.division` | | | ● | | | | |
| `authorization.get.all.divisions` | | | ● | | | | |
| `authorization.search.division.objects` | | | ● | | | | |
| `authorization.get.division.grants` | | | ● | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | | ● |
| `analytics.query.user.aggregates.performance.metrics` | | | ● | | ● | | ● |
| `analytics.query.user.aggregates.login.activity` | | | | | ● | | ● |
| `analytics.query.user.details.activity.report` | | | | | | | ● |
| `quality.get.agents.activity` | | | ○ | | ● | | ● |
| `coaching.get.appointments` | | | | | | | ○ |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | ● | | |
| `analytics.query.flow.observations` | | | | | | ● | |
| `outbound.get.campaigns` | | | | ● | | | |
| `outbound.get.contact.lists` | | | | ● | | | |
| `outbound.get.campaign.diagnostics.summary` | | | | ● | | | |
| `outbound.get.events` | | | | ● | | | |
| `outbound.get.messaging.campaigns` | | | | ○ | ○ | | |
| `analytics-conversation-details-query` | | | | ● | | | ○ |
| `routing.get.single.queue.config` | | ○ | | ● | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | | ● | | |
| `analytics.post.transcripts.aggregates.query` | | | | | ● | | |
| `speechandtextanalytics.get.topics` | | | | | ● | | |
| `workforce.get.management.unit.adherence` | | | | | ● | | |
| `workforce.get.management.units` | | | | | ● | | |
| `workforce.get.management.unit.users` | | | | | ● | | |
| `workforce.get.agent.management.unit` | | | | | | | ○ |
| `workforce.get.adherence.bulk` | | | | | | | ○ |
| `analytics.get.agent.active.status` | | | | | | ○ | ○ |
| `users.get.agent.active.conversations` | | | | | | ○ | ○ |
| `users.get.agent.current.routing.status` | | | | | | ○ | ○ |
| `telephony.get.trunk.metrics.summary` | | | | | ○ | ● | |
| `telephony.get.edge.performance.metrics` | ○ | | | | | ● | |
| `alerting.get.alerts` | | | | | ○ | ● | |
| `users.get.user.details.with.full.expansion` | | | | | | | ● |
| `users.get.user.routing.skills` | | | | | | | ● |
| `users.get.user.queue.memberships` | | | | | | | ● |
| `users.get.bulk.user.presences` | | | | | | | ● |
| `routing.get.user.utilization` | | | | | | | ○ |
| `audit-logs` | | | | ● | | | ● |

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
| `nAnalyzedConversations` | Conversations with S&TA analysis | STA coverage |
| `adherencePct` | Scheduled vs. actual on-queue % | WFM compliance |
| `listPenetrationPct` | Contacts dialed / contact list size | Campaign reach |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*  
*Refer to `catalog/genesys.catalog.json` under `combinations` for the machine-readable recipe definitions.*
