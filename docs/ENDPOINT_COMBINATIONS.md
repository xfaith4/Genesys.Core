# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-09-13  
> Companion to: [INVESTIGATIONS.md](INVESTIGATIONS.md), [ROADMAP.md](ROADMAP.md)

This document describes how catalog datasets combine into coherent investigations and executive
reporting rollups. Each combination is documented with its subject, the ordered dataset steps,
the join keys that connect them, and the analytical questions it answers.

The goal of Genesys.Core is to be **informative without being a data dump**. Every combination
here answers a specific operational question and terminates when that question is answered — not
when the API is exhausted.

**Machine-readable counterpart:** every pattern below (except the metric glossary) is also encoded
as a structured recipe in `catalog/genesys.catalog.json` under `combinations.investigationRecipes`,
`combinations.executiveReportingPlaybooks`, and `combinations.voiceEngineerPlaybooks`. The JSON
recipes carry the same step/joinKey/dataset shape as this document plus `executiveMetrics` and
`voiceEngineerHighlights` arrays intended for direct consumption by reporting/investigation
tooling. Pattern 5 (Real-Time Operations Monitoring) maps to the
`real-time-operations-monitoring` recipe key; Pattern 6 (BYOI Enrichment) maps to the
`byoi-conversation-enrichment` recipe key; Pattern 10 maps to `skill-coverage-gap-analysis`;
Pattern 11 maps to `alert-root-cause-drilldown`; Pattern 12 maps to
`digital-engagement-journey-correlation`; Pattern 13 maps to the executive playbook
`coaching-effectiveness-and-score-trend`; Pattern 14 maps to the voice-engineer playbook
`integration-and-api-throttling-diagnostics`. Every `dataset` value in a JSON recipe resolves to
either a curated `datasets` entry or a raw `endpoints` operationId in the same catalog file —
there is no third namespace.

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
10. [Skill Coverage Gap Analysis](#10-skill-coverage-gap-analysis)
11. [Alert Root-Cause Drilldown](#11-alert-root-cause-drilldown)
12. [Digital Engagement / Journey Correlation](#12-digital-engagement--journey-correlation)
13. [Coaching Effectiveness Rollup (Executive)](#13-coaching-effectiveness-rollup-executive)
14. [Integration & API Throttling Diagnostics (BYOI)](#14-integration--api-throttling-diagnostics-byoi)
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

## 10. Skill Coverage Gap Analysis

**Subject:** One `skillId` (or an org-wide sweep with no filter) + time window
**Use case:** A staffing analyst suspects a skill-based routing queue is understaffed for a
particular skill, but skills are assigned to agents independently of queue or division — an
agent's skill set follows them everywhere they're eligible to route. A single-queue or
single-division view cannot see the whole picture; this pattern can.

**Core question:** *Do we have enough qualified agents for this skill, relative to how often it's requested — and is that true in every division, or just on average?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.all.routing.skills` | seed → `skillId` | Skill catalog — id/name, org-wide or scoped to one skill |
| 2 | `routing.get.skill.groups` | `skillIds[]` contains `skillId` | Skill group membership and `memberDivisionIds` — the first division-level signal |
| 3 | `users` | fan-out source | Active agent roster to check for skill assignment |
| 4 | `users.get.user.routing.skills` | `userId` (fan-out) | Per-agent skill id, proficiency, `state` (active/inactive) |
| 5 | `analytics-conversation-details-query` | window + `requestedRoutingSkillIds` contains `skillId` | Demand-side volume — conversations that actually requested this skill, with outcome |
| 6 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` (from step 5) | Confirms whether the gap is producing real pain (abandons, long waits) on the affected queues |
| 7 | `users.division.analysis.get.users.with.division.info` | `userId` (from step 4) | Breaks the qualified-agent count out by division |

### Key Joins

```
routing.get.all.routing.skills.id
  → routing.get.skill.groups[].skillIds[] (group-level rollup)
  → users.get.user.routing.skills[].id (per-agent qualification, fan-out over all users)

analytics-conversation-details-query[].requestedRoutingSkillIds[]
  → routing.get.all.routing.skills.id (demand-side volume for the coverage ratio denominator)

users.get.user.routing.skills[].userId
  → users.division.analysis.get.users.with.division.info[].id (division breakout)
```

### Analytical Questions Answered

- How many active, qualified agents exist for this skill, org-wide and per division?
- How much conversation volume actually requests this skill in the window?
- Is the coverage ratio (qualified agents ÷ skill-request volume) declining over successive windows?
- Are the queues that route on this skill showing rising abandons or wait times — i.e. is the gap material, not just theoretical?
- Is a skill adequately staffed org-wide but critically short in one specific division's agent pool?

### Why This Isn't Just Queue Investigation

Genesys Cloud does not attach a fixed skill requirement to a queue's configuration — skills are
requested per-conversation (via Architect flow or routing rule) and matched against whichever
agents currently hold that skill, regardless of queue or division membership. `queue-investigation`
answers "how did this queue perform"; this pattern answers "do we have the people," which is a
staffing question that can only be answered by looking at the skill and its agent population
directly, then cross-referencing the queues and divisions that happen to depend on it.

---

## 11. Alert Root-Cause Drilldown

**Subject:** One `alertId` (a currently firing platform alert)
**Use case:** Real-Time Operations Monitoring (Pattern 5) surfaces that an alert is firing, but an
alert list alone just says *something* crossed a line. A NOC analyst or supervisor needs to know
which line, on which resource, and whether it's a spike or a sustained condition before deciding
whether to act.

**Core question:** *This alert fired — what actually breached, on what, and is it still happening?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `alerting.get.alerts` | seed → `alertId` | `ruleId`, `resourceId`, `resourceType`, `triggeredTime`, current value |
| 2 | `alerting.get.rules` | `ruleId` | The metric name, comparison operator, and threshold that was actually breached |
| 3a *(resourceType=queue)* | `analytics.query.queue.observations.real.time.stats` | `queueId` | Live `oWaiting`/`oInteracting`/`oOnQueueUsers` for the alerting queue |
| 3b *(resourceType=edge/trunk)* | `telephony.get.edge.performance.metrics` | `edgeId` | CPU, memory, active call count on the alerting Edge |
| 3c *(resourceType=user)* | `analytics.query.user.observations.real.time.status` | `userId` | Current presence/routing status for the alerting agent |
| 4 | `analytics.query.conversation.aggregates.queue.performance` | `queueId`, short trailing window | Distinguishes a transient spike from a sustained trend |

### Branch Rule

`resourceType` on the alert instance selects **exactly one** of steps 3a/3b/3c — never fan out to
all three. This is the pattern that keeps an alert drilldown from turning into a full data dump:
resolve the resource type first, then pull only the metrics relevant to that resource class.

### Analytical Questions Answered

- Which metric and threshold actually fired — not just "an alert is active"?
- Is the breach still current, or has the underlying condition already cleared?
- Is this a momentary spike (self-resolving) or a sustained condition needing a staffing/config change?
- What follow-up investigation applies? (Route to `queue-investigation`, `trunk-and-edge-health-check`, or `agent-investigation` once the resource is identified.)

### Composition Note

This pattern is deliberately a *bridge*, not a terminus — it exists to hand off to the right deep
dive (Patterns 2, 5, 7, or the voice-engineer trunk/edge playbook) once the alerting resource and
metric are known, rather than duplicating those investigations' own steps.

---

## 12. Digital Engagement / Journey Correlation

**Subject:** One `conversationId` (a digital — chat/message — conversation)
**Use case:** A digital channel analyst wants to know whether a web messaging conversation came
from a customer-initiated chat or from a Predictive Engagement action map (a proactive offer
triggered by journey behaviour), and whether that offer actually led to a good outcome. This is the
Embeddable Framework / journey counterpart to BYOI enrichment (Pattern 6): BYOI explains
conversations injected from an *external* system, this explains digital conversations originated by
an *on-site* journey trigger rather than the customer opening chat unprompted.

**Core question:** *Did this digital conversation come from a proactive engagement, which campaign, and did it work?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | `mediaType`, `participants[].purpose`, `originatingDirection` — confirms this is a digital conversation |
| 2 | `conversations.get.conversation.customattributes` | `conversationId` | Action-map/campaign attributes set at engagement time (e.g. originating action map id, trigger page) |
| 3 | `journey.get.action.maps` | action-map id from step 2 | Action map name, trigger condition, target segment, offered action — the human-readable campaign definition |
| 4 | `conversations.search.participant.attributes` | `conversationId` | Architect flow variables captured during the digital session (bot handoff, intent capture) |
| 5 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing — wait, handle, disconnect type |
| 6 | `quality.get.surveys` | `conversationId` | Post-chat CSAT/NPS if triggered |

### Identifying an Action-Map-Originated Conversation

A conversation is action-map-originated when `conversations.get.conversation.customattributes`
carries an action-map/journey attribute key; its absence means the conversation was customer-
initiated (organic). **Always compare the two populations** — reporting only on triggered
conversations overstates the program's apparent volume and hides its true conversion rate.

### Analytical Questions Answered

- Was this digital conversation customer-initiated or proactively triggered by a journey action map?
- Which action map, and what trigger condition produced it?
- Do action-map-originated conversations have better or worse CSAT and handle time than organic ones?
- What's the actual conversion rate (offers extended vs. conversations that resulted from step 3's target segment)?

### Embeddable Framework Note

The Embeddable Framework's condensed conversation view (used by the web widget) is the same object
shape returned by `conversations.get.conversation.object` — `participants[].purpose`,
`participants[].state`, `participants[].calls[].state/muted/held` — so no separate dataset or
transformation is needed to reconcile widget-side state with the server-side conversation record.

---

## 13. Coaching Effectiveness Rollup (Executive)

**Subject:** Organisation or division, reporting window (monthly/quarterly)
**Use case:** A QM/WFM director needs to justify (or cut) a coaching program budget. Reporting that
"N coaching sessions happened" answers nothing an executive cares about; this playbook answers
whether coaching measurably moved quality scores.

**Core question:** *Did coaching actually improve scores, and by how much compared to agents who weren't coached?*

### Dataset Steps (ordered)

| Dataset Key | Role |
|-------------|------|
| `coaching.get.appointments` | Completed coaching sessions per agent, with date |
| `quality.get.evaluations.query` | Individual evaluation scores, dated — split into a pre-coaching and post-coaching trailing window per agent |
| `quality.get.agents.activity` | Per-agent evaluation count/average/high/low for the reporting window |
| `analytics.query.conversation.aggregates.agent.performance` | `tHandle` per agent, for the same before/after comparison |

### Output Metrics

- `coachingSessionCount` (completed, in window)
- `evalAvgScore` — 30-day trailing average **before** an agent's first completed coaching session
- `evalAvgScore` — 30-day trailing average **after** an agent's last completed coaching session
- `scoreDelta` (after − before) and `tHandle` delta, per coached agent
- **Coached cohort** score delta vs. **uncoached cohort** score delta over the same period — the actual causal comparison

### Executive Presentation

A two-cohort comparison (coached vs. not-coached this period) with score-delta bars, plus a
per-agent before/after sparkline *for the coached cohort only*. Deliberately excludes a full
per-agent history table for every agent in the org — that would be the data dump this catalog is
designed to avoid; the coached-cohort delta is the number that answers the executive's question.

---

## 14. Integration & API Throttling Diagnostics (BYOI)

**Subject:** One OAuth client (a BYOI provider integration or other custom integration)
**Use case:** A BYOI provider integration starts failing to inject conversations, or conversations
appear to drop silently. The instinctive first check is the SIP/media path, but a `429` on
`POST /api/v2/conversations/providers/{providerId}/calls` looks identical to a dropped call from
the provider's point of view. This playbook checks the API control plane before the media plane.

**Core question:** *Is the integration actually broken, or is it being rate-limited (or mis-scoped) at the API layer?*

### Dataset Steps (ordered)

| Dataset Key | Role |
|-------------|------|
| `oauth.get.clients` | Confirms the integration's OAuth client exists and has the expected scopes (missing scope → `403`, not throttling) |
| `usage.get.api.usage.by.client` | Per-client call volume — sustained near the rate ceiling in the incident window is the throttling signal |
| `usage.get.api.usage.organization.summary` | Org-wide usage — rules out a noisy-neighbor client saturating the shared limit |
| `analytics.query.rate.limit.aggregates` | `nOverLimit` — confirms actual `429`s occurred in the incident window, not just proximity to the ceiling |
| `oauth.get.client.usage.query.results` | Confirms the integration is still calling the API at all (empty results → the problem is upstream of Genesys Cloud) |

### Diagnostic Signals

- Sustained near-ceiling usage on the integration's client, correlated in time with reported missing/delayed conversations → throttling is the root cause.
- Org-wide usage near cap while the integration's own client is well under its limit → a different client is the actual cause; look elsewhere before touching the integration.
- Client missing the conversations/BYOI scope → misconfigured authorization, not a capacity problem.
- No usage recorded for the client at all → the integration has stopped calling out; the fault is on the provider's side of the handoff, not in Genesys Cloud.

### Enrich With

- `alerting.get.alerts` — an organization API-limit alert firing in the same window corroborates the diagnosis.
- `conversations.get.active.conversations` — confirms whether injected conversations are actually landing during the suspected throttling window.

---

## 15. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | Skill Coverage | Alert Drilldown | Digital Engagement |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | | | ● |
| `analytics.get.single.conversation.analytics` | ● | | | | | | | | ● |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | | ● |
| `conversations.search.participant.attributes` | ● | | | | | | | | ● |
| `quality.get.evaluations.query` | ● | ○ | | | | | | | |
| `quality.get.surveys` | ● | | | ● | | | | | ● |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | | | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ● | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | ● | ● | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | | | |
| `routing-queue-members` | | ● | | | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | ● | | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | | | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | | | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | | | |
| `coaching.get.appointments` | | | ● | | | ○ | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | | ● | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | | ● | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | | | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | | | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | | | |
| `analytics.query.flow.observations` | | | | | ● | | | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | | ● | |
| `alerting.get.alerts` | | | | ○ | ● | | | ● | |
| `alerting.get.rules` | | | | | | | | ● | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | | | |
| `users.get.user.routing.skills` | | | | | | ● | ● | | |
| `users.get.user.queue.memberships` | | | | | | ● | | | |
| `users.get.bulk.user.presences` | | | | | | ● | | | |
| `routing.get.user.utilization` | | | | | | ○ | | | |
| `audit-logs` | | | | | | ● | | | |
| `routing.get.all.routing.skills` | | | | | | | ● | | |
| `routing.get.skill.groups` | | | | | | | ● | | |
| `users` | | | | | | | ● | | |
| `journey.get.action.maps` | | | | | | | | | ● |

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
| `coverageRatio` | Qualified agents ÷ skill-request volume, for one routing skill | Skill staffing gap indicator |
| `scoreDelta` | Post-coaching avg eval score − pre-coaching avg eval score, per agent | Coaching program ROI |
| `nOverLimit` | Count of API calls that exceeded the org/client rate limit in a window | Integration throttling root cause |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
