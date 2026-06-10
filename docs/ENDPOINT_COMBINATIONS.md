# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-10  
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
10. [Skill Group Investigation](#10-skill-group-investigation)
11. [Outbound Campaign Investigation](#11-outbound-campaign-investigation)
12. [MOS / Voice Quality Investigation](#12-mos--voice-quality-investigation)
13. [Executive Playbook Extensions](#13-executive-playbook-extensions)
14. [Dataset Combination Reference Matrix](#14-dataset-combination-reference-matrix)
15. [Appendix: Metric Glossary](#appendix-metric-glossary)

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

## 10. Skill Group Investigation

**Subject:** One `skillGroupId` + time window  
**Use case:** A routing administrator or workforce analyst needs to understand how a skill-based
routing group is performing — which agents belong to it, how their proficiency is distributed,
what queues they cover, and whether skill routing is yielding measurable performance differences.

Skill groups cut across queues and divisions, making them the right lens when agents serve
multiple queues under a single skill umbrella.

**Core question:** *Is this skill group properly staffed, and is higher proficiency actually
producing better outcomes?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.skill.groups` | seed → `skillGroupId` | Group name, member count, owning division |
| 2 | `routing.get.skill.group.members` | `skillGroupId` | All agent userIds in the group |
| 3 | `users.get.user.routing.skills` | `userId` (each member) | Individual skill proficiency ratings per agent |
| 4 | `users.get.user.queue.memberships` | `userId` (each member) | Queues each agent serves — maps group to queue coverage |
| 5 | `analytics.query.user.aggregates.performance.metrics` | `userId` list | nConnected, tHandle, tTalk, tAcw per agent |
| 6 | `analytics-conversation-details-query` | `userId` list | All conversations by skill-group members in the window |
| 7 | `quality.get.agents.activity` | `userId` list | Evaluation counts and scores per member |

### Key Joins

```
routing.get.skill.groups.id
  → routing.get.skill.group.members.skillGroupId (member enumeration)

routing.get.skill.group.members[].id
  → users.get.user.routing.skills[].userId (proficiency overlay)
  → analytics.query.user.aggregates.performance.metrics[].group.userId
  → quality.get.agents.activity[].user.id

analytics.query.user.aggregates.performance.metrics[].group.userId
  (group by proficiencyRating band for skill-performance correlation)
```

### Analytical Questions Answered

- Are high-proficiency agents handling calls faster (lower AHT)?
- Does the skill group have sufficient coverage across the queues it supports?
- Which agents have proficiency ratings that don't match their actual handle time?
- Are any skill-group members missing evaluations for the window?
- Is proficiency distribution heavily bottom-weighted (many P1 agents, few P5)?

---

## 11. Outbound Campaign Investigation

**Subject:** One `campaignId` + time window  
**Use case:** A dialer administrator or outbound operations manager needs to understand campaign
reach rates, contact dispositions, agent efficiency, and pacing health for a single outbound
campaign.

**Core question:** *Is this campaign reaching contacts effectively, and what are the outcomes?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Mode, status, queueId, contactListId, callerName |
| 2 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Real-time health: outstanding contacts, contacts/hour, error count |
| 3 | `outbound.get.contact.lists` | `contactListId` from step 1 | Contact list size and import health |
| 4 | `outbound.get.events` | `campaignId` | Per-contact dialer events: CONNECTED, NO_ANSWER, BUSY, MACHINE |
| 5 | `analytics-conversation-details-query` | `queueId` from step 1 | Conversations that connected — tTalk, tHandle, wrapUpCode |
| 6 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Queue-level handle metrics for the outbound queue |
| 7 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Wrapup outcome distribution (sales, callbacks, refusals) |

### Key Joins

```
outbound.get.campaigns.id
  → outbound.get.campaign.diagnostics.summary.campaignId
  → outbound.get.contact.lists[].id (via contactListId)
  → outbound.get.events[].campaignId

outbound.get.events[].conversationId (where present)
  → analytics-conversation-details-query[].conversationId (outcome overlay)

outbound.get.campaigns.queueId
  → analytics.query.conversation.aggregates.queue.performance[].group.queueId
  → analytics.query.conversation.aggregates.wrapup.distribution[].group.queueId
```

### Computed Campaign KPIs

```
connectRate%        = nConnected / totalDialed × 100
machineRate%        = MACHINE_DETECT events / totalDialed × 100
noAnswerRate%       = NO_ANSWER events / totalDialed × 100
penetrationRate%    = contactsDialed / contactListSize × 100
avgHandleTime       = tHandle / nConnected (for connected calls only)
rightPartyContact%  = SALE/COMMITTED wrapUps / nConnected × 100
```

### Diagnostic Signals

- `contactsPerHour` well below target pacing → check `dialingMode`; progressive/power campaigns
  throttle based on agent availability
- High `MACHINE_DETECT` rate → AMD (Answering Machine Detection) sensitivity; tune sensitivity
  level in campaign config
- High `errorCount` in diagnostics → check campaign's phone column mapping and contact timezone
  settings
- `campaignStatus = STOPPING` but not complete → campaign may be hitting DNC list matches or
  contact attempt limits

---

## 12. MOS / Voice Quality Investigation

**Subject:** Queue, edge, or organisation-wide + time window  
**Use case:** A voice engineer receives complaints about call audio quality — choppy audio,
echo, or one-way audio. They need to identify which conversations had degraded MOS scores,
which infrastructure handled them, and whether the degradation is systemic (edge/trunk) or
episodic (single call).

**Core question:** *Which calls had degraded audio quality, and is there a common infrastructure
cause?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics-conversation-details-query` | `queueId` or all queues | `mediaStatsMinConversationMos`, `mediaStatsMinConversationRFactor` per conversation |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` (for each low-MOS call) | Segment timing, edgeId from participant sessions |
| 3 | `telephony.get.edges` | `edgeId` from step 2 | Edge name, site, status, softwareVersion |
| 4 | `telephony.get.trunk.metrics.summary` | trunks used in window | SIP trunk utilisation, packet loss, error counters |
| 5 | `telephony.get.edge.performance.metrics` | `edgeId` from step 2 | CPU, memory, active call count during degraded window |

### MOS Threshold Reference

| MOS Range | Quality | Action |
|-----------|---------|--------|
| 4.3–5.0 | Excellent | No action |
| 4.0–4.3 | Good | Monitor |
| 3.6–4.0 | Fair | Investigate if trending |
| 3.1–3.6 | Poor | Active investigation |
| < 3.1 | Bad | Escalate immediately |

### Diagnostic Signals

- Multiple low-MOS calls on same `edgeId` → edge resource pressure or codec misconfiguration
- Low MOS + trunk error spikes at same timestamps → carrier issue on specific trunk
- CPU > 80% on `telephony.get.edge.performance.metrics` during the window → edge overload,
  consider call load rebalancing
- Low MOS isolated to WebRTC sessions (`participantType = WebRTC`) → client-side network or
  browser issue, not edge
- Low `mediaStatsMinConversationRFactor` (< 70) without matching MOS degradation → jitter/
  packet-loss profile, possibly transient

### Voice Engineer Notes

`mediaStatsMinConversationMos` is populated only when the Genesys Edge has media statistics
collection enabled. If the field is absent, verify Edge analytics settings. Use
`telephony.get.sip.message.for.conversation` on specific low-MOS calls for codec SDP validation —
a G.711 call forced to a low-bandwidth codec produces predictable MOS degradation.

---

## 13. Executive Playbook Extensions

Three new executive playbooks added to the catalog, covering gaps in quality correlation,
AI feature adoption, and skill-routing ROI.

### 13a. CSAT and Survey Quality Rollup

**Use case:** Monthly quality board reporting — link survey completion rates to evaluation
coverage so leadership can see whether QM investment aligns with customer satisfaction.

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.surveys.aggregates.query` | `queueId`, `userId` | nSurveysSent, nSurveysCompleted, oSurveyScore |
| `quality.get.agents.activity` | `userId` | evalCount, avgScore, criticalItemFailCount |
| `quality.get.surveys` | `conversationId` | Individual survey responses for case-level drill |
| `analytics.query.conversation.aggregates.queue.performance` | `queueId` | nConnected (denominator for coverage %) |

**Computed KPIs:**
```
surveyCompletionRate%  = nSurveysCompleted / nSurveysSent × 100
avgCsatScore           = oSurveyScore aggregate (0–10 scale)
qmCoverage%            = evalCount / nConnected × 100
avgEvalScore           = from quality.get.agents.activity
```

**Executive presentation:** 2×2 scatter plot (CSAT vs QM score by queue) — highlight the
low-CSAT, low-QM-coverage quadrant as the highest-risk area.

---

### 13b. AI Summary Coverage Report

**Use case:** Measure Copilot/Agent Assist AI summary adoption after rollout — track which
queues and agents are generating summaries and whether failure rates are elevated.

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `analytics.summaries.aggregates.query` | `queueId`, `userId` | nSummariesGenerated, nSummariesFailed |
| `analytics.query.conversation.aggregates.queue.performance` | `queueId` | nConnected (denominator) |
| `routing-queues` | — | Queue names for label resolution |

**Computed KPIs:**
```
aiSummaryCoverage%  = nSummariesGenerated / nConnected × 100
aiSummaryFailRate%  = nSummariesFailed / (nSummariesGenerated + nSummariesFailed) × 100
```

**Note:** A summary failure rate > 10% on a queue indicates a transcription or AI configuration
issue for that queue. Check the queue's transcription settings and language model configuration.

---

### 13c. Skills Routing Effectiveness

**Use case:** Validate that skill-based routing investments are yielding measurable performance
differences — lower AHT, fewer transfers, better quality on skill-matched interactions.

| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `routing.get.all.routing.skills` | — | Skill catalog (name/id lookup) |
| `routing.get.skill.groups` | — | Skill group definitions |
| `analytics.query.user.aggregates.performance.metrics` | `userId` | tHandle per agent (compare across proficiency bands) |
| `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Queue baseline AHT |
| `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer rate per queue |

**Join:** Enrich agent performance with skill proficiency from `users.get.user.routing.skills`
→ group agents into proficiency tiers (P1–P5) → compare average tHandle per tier.

**Expected pattern:** P4/P5 agents should show 10–20% lower AHT than P1/P2 on the same queue.
If no difference is observed, skill assignments may be nominal rather than reflective of actual
competency.

---

## 14. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

Columns: **Conv** = Conversation Deep Dive · **Queue** = Queue Investigation · **Div** = Division Investigation · **Exec** = Executive Rollup · **RT** = Real-Time Monitoring · **Agent** = Agent Investigation · **Skill** = Skill Group Investigation · **OB** = Outbound Campaign · **MOS** = Voice Quality/MOS

| Dataset Key | Conv | Queue | Div | Exec | RT | Agent | Skill | OB | MOS |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.specific.conversation.details` | ● | | | | | | | | |
| `conversations.get.call.detail` | ● | | | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ● | | | | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | ● |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | |
| `conversations.get.recordings` | ● | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | ○ | | | ● | ○ | | |
| `quality.get.surveys` | ● | | | ● | | | | | |
| `quality.get.conversation.surveys` | ● | | | | | | | | |
| `telephony.get.sip.message.for.conversation` | ○ | | | | | | | | ○ |
| `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` | ○ | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.data.for.conversation` | ○ | | | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | | |
| `speechandtextanalytics.get.conversation.summaries.detail` | ○ | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | ○ | |
| `routing.get.queue.wrapup.codes` | | ● | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | |
| `routing.get.queue.members.with.status` | | ● | | | ● | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | ● | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ● | ● | ● |
| `analytics.query.conversation.details.by.queue` | | ● | | | | | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | ● | ● | | | | ● | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | ● | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | ● | |
| `routing-queue-members` | | ● | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | |
| `authorization.search.division.objects` | | | ● | | | | | | |
| `authorization.get.division.grants` | | | ● | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | |
| `analytics.division.conversation.aggregates` | | | ● | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | ● | | |
| `coaching.get.appointments` | | | ● | | | ○ | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | |
| `analytics.query.conversation.aggregates.by.media.type` | | | | ● | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | |
| `analytics.surveys.aggregates.query` | | | | ● | | | | | |
| `analytics.summaries.aggregates.query` | | | | ● | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | |
| `analytics.query.user.observations.real.time.status` | | ● | | | ● | ● | | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | ● |
| `telephony.get.edges` | | | | | ● | | | | ● |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | | ● |
| `telephony.create.edge.logs.job` | | | | | | | | | ○ |
| `telephony.get.edge.logs.job` | | | | | | | | | ○ |
| `alerting.get.alerts` | | | | ○ | ● | | | | |
| `alerting.get.rules` | | | | | | | | | ○ |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | |
| `users.get.user.routing.skills` | | | | | | ● | ● | | |
| `users.get.user.queue.memberships` | | | | | | ● | ● | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | |
| `routing.get.skill.groups` | | | | ● | | | ● | | |
| `routing.get.skill.group.members` | | | | | | | ● | | |
| `routing.get.all.routing.skills` | | | | ● | | | ○ | | |
| `outbound.get.campaigns` | | | | | | | | ● | |
| `outbound.get.campaign.diagnostics.summary` | | | | | | | | ● | |
| `outbound.get.contact.lists` | | | | | | | | ● | |
| `outbound.get.events` | | | | | | | | ● | |
| `outbound.get.messaging.campaigns` | | | | | | | | ● | |
| `workforce.get.adherence.bulk` | | | | | | ● | | | |
| `workforce.get.agent.management.unit` | | | | | | ● | | | |
| `workforce.get.management.units` | | | | ● | | | | | |
| `workforce.get.management.unit.users` | | | | ● | | | | | |
| `workforce.get.management.unit.adherence` | | | | ● | | | | | |
| `audit-logs` | | | ○ | | | ● | | | |
| `stations.get.stations` | | | | | | ○ | | | ○ |

---

## Appendix: Metric Glossary

### Analytics Metrics (Conversation & Queue)

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `nOffered` | Conversations offered to the queue | Volume denominator |
| `nConnected` | Conversations connected to an agent | Handled volume |
| `nAbandoned` | Conversations abandoned before connection | Abandon count |
| `tHandle` | Total handle time (talk + hold + ACW) | AHT numerator |
| `tTalk` | Total talk time | Talk-time component |
| `tAcw` | After-call work time | ACW component |
| `tHeld` | Total hold time | Hold-time component |
| `tAnswered` | Time from offered to answered | Speed of answer |
| `tAbandon` | Time before abandonment | Abandon patience |
| `tShortAbandon` | Abandon time below short-abandon threshold | IVR-triggered or accidental hang-ups |
| `nTransferred` | Conversations transferred | Transfer volume |
| `nBlindTransferred` | Blind (cold) transfers | Transfer quality indicator |
| `nConsultTransferred` | Consult transfers | Warm transfer volume |
| `oServiceLevel` | Current SLA percentage | Real-time SLA |
| `nOverSla` | Conversations that exceeded SLA threshold | SLA misses |
| `nAnsweredIn20` | Calls answered within 20 seconds | Speed-of-answer sub-metric |

### Analytics Metrics (Real-Time Observations)

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `oInteracting` | Agents currently on interactions | Active agents |
| `oWaiting` | Interactions waiting in queue | Queue depth |
| `oAlerting` | Interactions alerting an agent | In-progress answer |
| `oOnQueueUsers` | Agents on-queue and available | Staffed capacity |
| `oOffQueueUsers` | Agents off-queue | Absent capacity |
| `oLongestWaiting` | Seconds the longest-waiting customer has waited | Worst-case wait |

### Agent Analytics Metrics

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `tAgentRoutingStatus` | Time in each routing status | On-queue vs off-queue time |
| `tSystemPresence` | Time in each system presence | Available, Busy, Away, Offline |
| `nNotResponding` | Times agent entered NOT_RESPONDING | Auto-answer failure count |

### Speech & Text Analytics

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `oSentimentScore` | Aggregate sentiment score (STA) | Voice-of-customer indicator |
| `nSpeechTextAnalyzedConversations` | Conversations with STA analysis | STA coverage |
| `agentSentimentScore` | Agent-side sentiment average | Agent tone monitoring |
| `customerSentimentScore` | Customer-side sentiment average | CX quality indicator |
| `overtalkPercent` | % of conversation with overlapping speech | Conversation dynamic |
| `silencePercent` | % of conversation in silence | Dead air / hold indicator |

### Voice Quality

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `mediaStatsMinConversationMos` | Minimum MOS score observed in conversation | Audio quality floor |
| `mediaStatsMinConversationRFactor` | Minimum R-Factor (0–100) | Jitter/packet-loss indicator |

### Survey & Quality

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `nSurveysSent` | Surveys triggered after conversations | Survey outreach volume |
| `nSurveysCompleted` | Surveys completed by customers | Response volume |
| `oSurveyScore` | Aggregate CSAT/NPS survey score | Voice-of-customer KPI |
| `evalCount` | Evaluations completed for an agent | QM coverage |
| `evalAvgScore` | Average evaluation score | QM performance |
| `criticalItemFailCount` | Critical item failures in evaluations | Compliance risk indicator |

### AI / Copilot

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `nSummariesGenerated` | AI summaries successfully created | Copilot adoption |
| `nSummariesFailed` | AI summary generation failures | Feature reliability |

### Outbound / Dialer

| Metric | Meaning | Typical Use |
|--------|---------|-------------|
| `connectRate%` | nConnected / totalDialed | Campaign reach |
| `machineRate%` | MACHINE_DETECT / totalDialed | AMD accuracy |
| `penetrationRate%` | contactsDialed / contactListSize | List progress |
| `rightPartyContact%` | Successful outcome wrapups / nConnected | Campaign quality |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*  

---

## Appendix: Endpoint → Dataset Quick Reference

Key Genesys Cloud API paths and their catalog dataset keys for rapid lookup.

| API Path | Method | Dataset Key |
|----------|--------|-------------|
| `/api/v2/conversations/{conversationId}` | GET | `conversations.get.specific.conversation.details` |
| `/api/v2/conversations/calls/{conversationId}` | GET | `conversations.get.call.detail` |
| `/api/v2/conversations/{conversationId}/participants/{participantId}/wrapup` | GET | `conversations.get.conversation.participant.wrapup` |
| `/api/v2/conversations/{conversationId}/summaries` | GET | `conversations.get.conversation.summaries` |
| `/api/v2/conversations/{conversationId}/recordingmetadata` | GET | `conversations.get.conversation.recording.metadata` |
| `/api/v2/conversations/{conversationId}/recordings` | GET | `conversations.get.recordings` |
| `/api/v2/analytics/conversations/{conversationId}/details` | GET | `analytics.get.single.conversation.analytics` |
| `/api/v2/analytics/conversations/details/query` | POST | `analytics-conversation-details-query`, `analytics.query.conversation.details.by.queue` |
| `/api/v2/analytics/conversations/details/jobs` | POST | `analytics-conversation-details` (async) |
| `/api/v2/analytics/conversations/aggregates/query` | POST | `analytics.query.conversation.aggregates.*` |
| `/api/v2/analytics/queues/observations/query` | POST | `analytics.query.queue.observations.real.time.stats` |
| `/api/v2/analytics/users/observations/query` | POST | `analytics.query.user.observations.real.time.status` |
| `/api/v2/analytics/users/aggregates/query` | POST | `analytics.query.user.aggregates.*` |
| `/api/v2/analytics/users/details/query` | POST | `analytics.query.user.details.activity.report` |
| `/api/v2/analytics/flows/aggregates/query` | POST | `analytics.query.flow.aggregates.execution.metrics` |
| `/api/v2/analytics/transcripts/aggregates/query` | POST | `analytics.post.transcripts.aggregates.query` |
| `/api/v2/analytics/surveys/aggregates/query` | POST | `analytics.surveys.aggregates.query` |
| `/api/v2/analytics/summaries/aggregates/query` | POST | `analytics.summaries.aggregates.query` |
| `/api/v2/routing/queues` | GET | `routing-queues` |
| `/api/v2/routing/queues/{queueId}` | GET | `routing.get.single.queue.config` |
| `/api/v2/routing/queues/{queueId}/members` | GET | `routing.get.queue.members.with.status` |
| `/api/v2/routing/queues/{queueId}/wrapupcodes` | GET | `routing.get.queue.wrapup.codes` |
| `/api/v2/routing/queues/{queueId}/estimatedwaittime` | GET | `routing.get.queue.estimated.wait.time` |
| `/api/v2/routing/skillgroups` | GET | `routing.get.skill.groups` |
| `/api/v2/routing/skillgroups/{skillGroupId}/members` | GET | `routing.get.skill.group.members` |
| `/api/v2/speechandtextanalytics/conversations/{conversationId}` | GET | `speech.and.text.analytics.get.speech.and.text.analytics.for.conversation` |
| `/api/v2/speechandtextanalytics/conversations/{conversationId}/sentiments` | GET | `speech.and.text.analytics.get.sentiment.data.for.conversation` |
| `/api/v2/speechandtextanalytics/conversations/{conversationId}/categories` | GET | `speechandtextanalytics.get.conversation.categories` |
| `/api/v2/speechandtextanalytics/conversations/{conversationId}/summaries` | GET | `speechandtextanalytics.get.conversation.summaries.detail` |
| `/api/v2/quality/evaluations/query` | GET | `quality.get.evaluations.query` |
| `/api/v2/quality/conversations/{conversationId}/surveys` | GET | `quality.get.conversation.surveys` |
| `/api/v2/authorization/divisions/{divisionId}/objects` | GET | `authorization.search.division.objects` |
| `/api/v2/authorization/divisions/{divisionId}/grants` | GET | `authorization.get.division.grants` |
| `/api/v2/telephony/sipmessages/conversations/{conversationId}` | GET | `telephony.get.sip.message.for.conversation` |
| `/api/v2/workforcemanagement/adherence` | GET | `workforce.get.adherence.bulk` |
| `/api/v2/workforcemanagement/agents/{agentId}/managementunit` | GET | `workforce.get.agent.management.unit` |
