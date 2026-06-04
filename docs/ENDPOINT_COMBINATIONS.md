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
10. [Long Handle Time Investigation](#10-long-handle-time-investigation)
11. [Repeat Caller / FCR Proxy Investigation](#11-repeat-caller--fcr-proxy-investigation)
12. [Skill Group Routing Investigation](#12-skill-group-routing-investigation)
13. [BYOI External Conversation Investigation](#13-byoi-external-conversation-investigation)
14. [Agent Occupancy and Idle Analysis](#14-agent-occupancy-and-idle-analysis-executive)
15. [First-Call Resolution Proxy Report](#15-first-call-resolution-proxy-report-executive)
16. [Voice Infrastructure Executive Health](#16-voice-infrastructure-executive-health-executive)
17. [Bot and Self-Service Containment Report](#17-bot-and-self-service-containment-report-executive)
18. [WebRTC / Softphone Registration Audit](#18-webrtc--softphone-registration-audit-voice-engineer)
19. [DNIS Routing Path Verification](#19-dnis-routing-path-verification-voice-engineer)
20. [Hold, Escalation, and Transfer Pattern Investigation](#20-hold-escalation-and-transfer-pattern-investigation-voice-engineer)
21. [Dataset Combination Reference Matrix](#21-dataset-combination-reference-matrix)

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

## 10. Long Handle Time Investigation

**Subject:** `queueId` or `userId` + time window  
**Use case:** A supervisor or operations analyst sees an AHT spike in an executive dashboard and needs to find the root cause — is it a specific call type, a specific agent, excessive hold, or ACW bloat?

**Core question:** *Which conversations drove the AHT spike, and what specifically caused each one?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics-conversation-details-query` (sorted by tHandle desc) | seed → `conversationId` | Top-N longest conversations: `tHandle`, `tTalk`, `tHeld`, `tAcw`, `agentId`, `wrapUpCode` |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment-level breakdown: hold count, conference events, transfer segments, per-phase timing |
| 3 | `conversations.get.specific.conversation.details` | `conversationId` | Wrapup code per participant, transfer chain, BYOI indicator, full participant roster |
| 4 | `users.get.user.details.with.full.expansion` | `userId` (agent participants) | Agent identity: name, division, manager — enables attribution to team |
| 5 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | Agent-level baseline AHT in the window — compare outlier vs. own average |
| 6 | `quality.get.evaluations.query` | `conversationId` | Evaluation score, critical item failure — confirms process violation for outlier conversations |
| 7 | `routing.get.queue.wrapup.codes.by.queue` | `wrapUpCode` | Human-readable wrapup labels for the outlier set |

### Key Derived Metrics

```
holdRatio%         = tHeld / tHandle  (> 40% → excessive hold)
acwRatio%          = tAcw / tHandle   (> 30% → ACW discipline issue)
ahtDelta           = conversation tHandle - agent's avg tHandle
transferCount      = count of transfer segments in conversation-timeline
```

### Diagnostic Decision Tree

```
ahtDelta high for ALL agents on outliers → call-type/content driver (complex inquiry, billing)
ahtDelta high for ONE agent only         → agent skill or knowledge gap; target for coaching
holdRatio% > 40%                         → agent process: excessive hold usage
acwRatio% > 30%                          → ACW discipline or complex post-call work
transferCount > 1                        → routing problem; caller bouncing between queues
criticalItemFailed = true in evaluations → procedure violation contributing to AHT
```

---

## 11. Repeat Caller / FCR Proxy Investigation

**Subject:** `queueId` or `divisionId` + time window  
**Use case:** An operations director or CX analyst wants to measure first-call resolution without a formal IVR-based FCR system. ANI recurrence within a configurable window (default: 7 days) serves as the FCR proxy.

**Core question:** *Which customers are calling back, why, and which queues and agents are associated with the repeat calls?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics-conversation-details-query` | seed → `conversationId` | All connected conversations; group by ANI client-side for repeat detection |
| 2 | `(derived — client-side ANI grouping)` | `ANI` | Repeat caller list: ANI, repeat count, days between calls, first/last conversationId |
| 3 | `analytics.get.single.conversation.analytics` | `conversationId` (repeat only) | Segment detail for each repeat conversation: routing path, wrapup, agent |
| 4 | `routing.get.queue.wrapup.codes.by.queue` | `wrapUpCode` | Decode wrapup codes — repeated codes reveal the unresolved issue category |
| 5 | `quality.get.surveys` | `conversationId` | CSAT/NPS from repeat caller conversations — CX impact confirmation |
| 6 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | Agent concentration: are repeat callers concentrated on specific agents? |

### Exclusions (apply before ANI grouping)

- `tAbandon < 10s` — short abandons (caller hung up immediately)
- Conversations with no agent segment (IVR-only, no ACD routing)
- Outbound campaign-initiated conversations

### Executive Metrics

```
repeatCallerRate%      = uniqueRepeatANIs / totalUniqueANIs
fcrProxy%              = 1 − repeatCallerRate%
avgDaysBetweenCalls    (for repeat callers only)
repeatCallerCsatAvg    (from survey results where present)
topRepeatWrapupCodes   (top-3 wrapup codes in repeat chains)
```

**Executive presentation:** FCR Proxy% KPI card (target > 85%); queue-level repeat rate table sorted worst-to-best; highlight queues with repeatCallerRate% > 15% in red.

---

## 12. Skill Group Routing Investigation

**Subject:** `queueId` or `skillGroupId` + time window  
**Use case:** A contact centre architect or WFM planner investigates why a skill-based routing queue is missing SLA — is the eligible agent pool too small, too low-proficiency, or consistently off-queue?

**Core question:** *Are the right agents with the right skills on-queue when the calls arrive?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `routing.get.skill.groups` | seed → `id` | All configured skill groups, member counts, division assignments |
| 2 | `routing.get.skill.group.members` | `skillGroupId` | Eligible agent pool per skill group with proficiency ratings |
| 3 | `users.get.user.routing.skills` | `userId` | Individual skill proficiency per agent — tier distribution analysis |
| 4 | `routing.get.single.queue.config` | `queueId` | Routing method: BEST_AVAILABLE / TIMESTAMP / SKILL_BASED; skill evaluation mode |
| 5 | `routing-queue-members` | `queueId` | Live membership with routing status and presence — actual vs. eligible staffing |
| 6 | `analytics.query.queue.aggregates.service.level` | `queueId` | SLA achievement — correlate skill coverage to service level |
| 7 | `analytics.query.conversation.aggregates.agent.performance` | `userId` | AHT by agent in queue — confirms if low-proficiency agents have higher AHT |

### Division Note

Skill groups span queues within a division. An agent's primary `divisionId` does not restrict which queues they appear in. Use `authorization.list.division.queues` to enumerate all queues served by a skill group's eligible agents within a division.

### Diagnostic Signals

| Signal | Diagnosis |
|--------|-----------|
| `eligibleAgentCount` adequate, `onQueueEligibleCount` low | Agents have the skill but are off-queue — presence audit |
| SLA miss + `eligibleAgentCount` low | Coverage gap is the SLA cause, not overall headcount |
| Queue `memberCount` >> `skillGroupMemberCount` | Queue allows more members than are skill-eligible — overflow to unqualified agents |
| `avgHandleTime[tier-1]` >> `avgHandleTime[tier-4]` | Skill-based routing is correct; training to raise proficiency tiers will reduce AHT |

---

## 13. BYOI External Conversation Investigation

**Subject:** One `conversationId` where `externalTag != null`  
**Use case:** A conversation injected via the BYOI provider API (`POST /api/v2/conversations/providers/{providerId}/calls`) has a quality complaint, missing recording, or routing anomaly. The external provider needs a cross-reference using `externalConversationId`.

**BYOI Identification Check (prerequisite):**
- `conversations.get.specific.conversation.details` → `externalTag` is non-null
- `participants[].purpose = "external"` confirms provider participant
- If `externalTag` is null → use standard Single Conversation Deep Dive instead

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.specific.conversation.details` | seed → `conversationId` | `externalTag`, `externalConversationId`, participant roster |
| 2 | `conversations.get.conversation.customattributes` | `conversationId` | Provider-set attributes: CRM case ID, external call ID, intent label |
| 3 | `conversations.search.participant.attributes` | `conversationId` | Architect flow variables: intent capture, data action results |
| 4 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing — BYOI flows through identical analytics pipeline |
| 5 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace of the provider SIP-to-SIP handoff (not a PSTN leg) |
| 6 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording metadata — BYOI recordings follow queue policy |
| 7 | `quality.get.evaluations.query` | `conversationId` | Quality evaluation — identical to native calls |
| 8 | `quality.get.conversation.surveys` | `conversationId` | Post-interaction survey result |

### Voice Engineer Notes (BYOI-Specific)

- SIP trace shows **provider IP in SDP Contact/Via** — not a carrier leg. Compare to expected provider CIDR.
- SIP `4xx` on provider INVITE → provider-side rejection. Use `externalConversationId` as the provider's reference for their own logs.
- Recording absent + policy active → check if BYOI provider set a consent-blocked flag in `custom-attributes`.
- `analytics IVR duration > 0` → call transited an Architect flow. Check `participant-attributes` to confirm intent capture worked.

---

## 14. Agent Occupancy and Idle Analysis (Executive)

**Subject:** Division or management unit + time window  
**Use case:** A VP of Operations or workforce manager identifies agents who are technically on-queue but contributing low interaction volume — a hidden staffing efficiency problem.

**Core question:** *Which agents are on-queue but idle, and by how much?*

### Dataset Steps (ordered)

| Layer | Dataset Key | Metric |
|-------|-------------|--------|
| Identity | `users.division.analysis.get.users.with.division.info` | Agent list with division |
| On-queue time | `analytics.query.user.aggregates.login.activity` | `tAgentRoutingStatus[ON_QUEUE]` |
| Interacting time | `analytics.query.user.aggregates.performance.metrics` | `nConnected × avgTHandle` ≈ `tInteracting` |
| Live status | `routing-queue-members` | Current presence + routing status |
| Adherence | `workforce.get.management.unit.adherence` | Scheduled vs. actual (WFM licensed) |

### Computed Metrics

```
tIdleTime      = tOnQueueTime − tInteractingTime
occupancyPct%  = tInteractingTime / tOnQueueTime
```

**Executive presentation:** Agent occupancy heat map sorted by `occupancyPct%`; flag agents below 50% occupancy while on-queue; group by division and management unit for peer comparison.

---

## 15. First-Call Resolution Proxy Report (Executive)

**Subject:** Organisation or queue group + monthly window  
**Use case:** Monthly CX strategy review when a formal IVR-based FCR system is not deployed. Uses ANI recurrence as the FCR proxy.

### Dataset Steps

| Dataset Key | Purpose |
|-------------|---------|
| `analytics-conversation-details-query` | All connected conversations — group by normalised ANI |
| `routing-queues` | Queue names for the output table |
| `routing.get.all.wrapup.codes` | Wrapup label resolution |
| `quality.get.surveys` | CSAT from repeat-caller conversations |

### Computation Notes

- **Exclude:** `tAbandon < 10s`, IVR-only sessions, outbound campaign calls
- **Repeat window:** Default 7 days; configurable per business context
- **ANI normalisation:** Strip country code, format to E.164 before grouping

### Executive Output

```
FCR Proxy%             = 1 − repeatCallerRate%       (target: > 85%)
Repeat Caller CSAT     = avgCsatScore for repeat ANIs
Top Repeat Wrapup      = most frequent wrapup in repeat chains
Worst Queue            = queue with highest repeatCallerRate%
```

**Trend view:** week-over-week FCR Proxy% by queue; highlight regression queues in red (> 15% repeat rate).

---

## 16. Voice Infrastructure Executive Health (Executive)

**Subject:** Organisation-wide (no subject ID required)  
**Use case:** Executive operational review, major-incident bridge, or monthly infrastructure health board report.

**Core question:** *Is the voice infrastructure operating within safe parameters right now?*

### Dataset Steps

| Dataset Key | Metric |
|-------------|--------|
| `telephony.get.edges` | Edge availability: `statusCode = ACTIVE` count vs. total |
| `telephony.get.trunks` | Trunk in-service count: `inService = true` |
| `telephony.get.trunk.metrics.summary` | `currentCalls / maxConcurrentCalls` → utilisation% |
| `alerting.get.alerts` | Firing alert count by severity |
| `alerting.get.rules` | Confirm alerting thresholds are configured |
| `conversations.get.active.calls` | Current call volume against capacity headroom |

### Stoplight Thresholds

| Layer | Green | Amber | Red |
|-------|-------|-------|-----|
| Edge availability | 100% | 90-99% | < 90% |
| Trunk utilisation | < 70% | 70-85% | > 85% |
| Active CRITICAL alerts | 0 | 1-2 | > 2 |

---

## 17. Bot and Self-Service Containment Report (Executive)

**Subject:** Organisation-wide or specific bot flows + time window  
**Use case:** Bot investment justification, NLU model retraining decisions, and automation roadmap prioritisation.

**Core question:** *How many customers did bots and IVR resolve without agent escalation, and is that rate trending in the right direction?*

### Dataset Steps

| Dataset Key | Metric |
|-------------|--------|
| `analytics.query.bot.aggregates` | `nBotSessions`, `nBotTransferredToAgent`, `avgConversationTurns` |
| `analytics.query.flow.aggregates.execution.metrics` | `nFlow`, `nFlowOutcome`, `nFlowOutcomeFailed` |
| `flows.get.all.flows` | Flow names and types for labelling |
| `flows.get.flow.outcomes` | Outcome definitions for classification |
| `analytics-conversation-details-query` | Bot-originated conversations that reached queue (escaped containment) |

### Computed Metrics

```
containmentRate%  = 1 − (nBotTransferredToAgent / nBotSessions)
ivrContainment%   = 1 − (nFlowOutcomeFailed / nFlow)
deflectedVolume   = nBotSessions − nBotTransferredToAgent
nlConfidence%     = nIntentConfident / nBotSessions
```

**Executive presentation:** Containment rate KPI card (target > 40% for bots, > 60% for IVR); deflection volume as cost-avoidance estimate; week-over-week NLU confidence trend.

---

## 18. WebRTC / Softphone Registration Audit (Voice Engineer)

**Subject:** Organisation-wide (no subject ID required)  
**Use case:** Proactive shift-start audit of station registration health, or reactive investigation when agents report calls not ringing despite being "on queue."

**Core question:** *Which stations are unregistered, and which on-queue agents cannot receive calls as a result?*

### Dataset Steps

| Dataset Key | Join Key | What It Adds |
|-------------|----------|--------------|
| `stations.get.stations` | seed → `id` | All stations: `registered`, `type`, `associatedUser`, `webRtcUserId`, `status` |
| `users` | `userId` | Presence and routing status for associated users |
| `analytics.query.user.observations.real.time.status` | `userId` | Real-time `oUserPresence`, `oUserRoutingStatus` |
| `analytics.query.queue.observations.real.time.stats` | `queueId` | `oOnQueueUsers` vs. `oInteracting` ratio — detects ghost-agent queues |

### Derived Metric

```
ghostAgentCount = users where routingStatus=ON_QUEUE AND station.registered=false
```

### Diagnostic Signals

| Signal | Root Cause |
|--------|-----------|
| `station.registered=false` + `routingStatus=ON_QUEUE` | Ghost agent — ACD will offer, auto-answer will NOT_RESPOND |
| `station.webRtcUserId != user.id` | Station assigned to wrong user — reassign in admin portal |
| `oOnQueueUsers >> count(registered stations)` | Registration epidemic — check DNS, STUN/TURN (UDP 3478), firewall |
| `station.status=ASSOCIATED` + `registered=false` | ICE negotiation failure — WebRTC media port blocked |

**Enrich with:** `audit-logs` (EntityType=Station), `telephony.get.edge.performance.metrics` (if site-wide).

---

## 19. DNIS Routing Path Verification (Voice Engineer)

**Subject:** DNIS value or `queueId`  
**Use case:** Calls are reaching the wrong queue, playing the wrong IVR greeting, or being answered by incorrectly-skilled agents. A DNIS routing problem is suspected.

**Core question:** *Is the DNIS landing in the expected queue, and is the routing path correct at every hop?*

### Dataset Steps

| Dataset Key | Join Key | What It Adds |
|-------------|----------|--------------|
| `analytics-conversation-details-query` (DNIS filter) | seed → `conversationId` | Conversations matching the DNIS: actual `queueId`, `agentId`, routing path |
| `conversations.get.specific.conversation.details` | `conversationId` | `participants[].calls[].dnis` — actual DNIS received by the platform |
| `routing.get.single.queue.config` | `queueId` | Queue name, routing method — confirms expected queue is correctly configured |
| `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Wrapup codes — 'wrong-team' codes confirm agent-side awareness of mis-routing |
| `telephony.get.sip.message.for.conversation` | `conversationId` | SIP `INVITE To:` header DNIS — confirms carrier-delivered DNIS |
| `routing.get.all.routing.skills` | `skillId` | Skill labels — verify conversation segments have the expected skill tag |

### Diagnostic Decision Tree

```
analytics queueId != expected queue    → Architect flow routing to wrong queue
SIP INVITE To: DNIS != expected DNIS  → carrier-side mismatch; raise with carrier
SIP 404 Not Found on INVITE            → DNIS not configured; check DID table and inbound flow
No skill tag in segments               → Architect flow not requesting required skill
IVR segment with no queueId            → Call terminated in IVR; check for missing Transfer action
```

**Enrich with:** `flows.get.all.flows` (match by DNIS entries), `analytics.query.flow.aggregates.execution.metrics` (confirm flow is executing), `audit-logs` (EntityType=Architect, recent deployments).

---

## 20. Hold, Escalation, and Transfer Pattern Investigation (Voice Engineer)

**Subject:** `queueId` + time window  
**Use case:** CSAT surveys cite hold time, or supervisors observe agents making frequent consult calls. The investigation determines whether hold and transfer behaviour is systemic across a queue or concentrated in a specific agent cohort.

**Core question:** *Are agents using hold and transfer appropriately, and where is the behaviour costing the most in AHT and CSAT?*

### Dataset Steps

| Dataset Key | Join Key | What It Adds |
|-------------|----------|--------------|
| `analytics.query.conversation.aggregates.queue.performance` | `queueId` | `tHeld`, `tHandle`, `nConnected` — hold ratio at queue level |
| `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | `nTransferred`, `nBlindTransferred`, `nConsultTransferred` |
| `analytics-conversation-details-query` | `queueId` | Conversation list filtered by `tHeld > threshold` |
| `analytics.get.single.conversation.analytics` | `conversationId` | Segment-level hold → resume → transfer event chains |
| `quality.get.evaluations.query` | `conversationId` | Evaluation scores for high-hold/high-transfer conversations |
| `quality.get.surveys` | `conversationId` | CSAT correlation: low scores on high-hold conversations |

### Key Thresholds

| Metric | Threshold | Interpretation |
|--------|-----------|----------------|
| `tHeld / tHandle` | > 25% | Systemic hold overuse at queue level |
| `nConsultTransferred / nConnected` | > 15% | Agents escalating before attempting resolution |
| `nBlindTransferred / nTransferred` | > 50% | Blind transfer dominant — no handoff briefing for customers |
| `tHeld` on individual conversation | > 120s | Customer patience threshold; correlate to CSAT |

### Diagnostic Pattern: Hold-Seek-Transfer

A conversation with the segment sequence `hold → resume → hold → consult-transfer` is an agent who does not know the answer, puts the customer on hold while seeking help, then transfers rather than resolving. This pattern indicates an empowerment or knowledge-base gap, not a system issue.

**Enrich with:** `coaching.get.appointments` (cross-reference high-hold agents with recent coaching), `routing.get.queue.wrapup.codes.by.queue` (decode wrapup codes from transferred conversations — the resolution type the agent could not provide).

---

## 21. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

**Investigation patterns:** Conv = Single Conversation Deep Dive · Queue = Queue Investigation · Div = Division Investigation · Agent = Agent Investigation · LHT = Long Handle Time · Repeat = Repeat Caller / FCR Proxy · Skill = Skill Group Routing · BYOI = BYOI External Conversation

**Reporting patterns:** Exec = Executive Rollup · RT = Real-Time Monitoring · Occ = Occupancy/Idle · FCR = FCR Proxy Report · VoiceInfra = Voice Infrastructure Health · Bot = Bot Containment

**Voice Engineer patterns:** VE-Conv = Single Call Forensics · VE-Trunk = Trunk/Edge Health · VE-Reg = WebRTC Registration Audit · VE-DNIS = DNIS Routing Verification · VE-Hold = Hold/Transfer Investigation

| Dataset Key | Conv | Queue | Div | Agent | LHT | Repeat | Skill | BYOI | Exec | RT | Occ | FCR | VoiceInfra | Bot | VE-Conv | VE-Trunk | VE-Reg | VE-DNIS | VE-Hold |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.specific.conversation.details` | ● | | | | ○ | | | ● | | | | | | | ● | | | ● | |
| `analytics.get.single.conversation.analytics` | ● | | | | ● | ● | | ● | | | | | | | ● | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | | ● | | | | | | | ● | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | | ● | | | | | | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | | ● | | | | | | | | | | | |
| `conversations.get.conversation.participant.wrapup` | ● | | | | | | | | | | | | | | | | | | |
| `conversations.get.conversation.summaries` | ○ | | | | | | | | | | | | | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | ● | ○ | ● | | | ● | | | | | | | ● | | | | ○ |
| `quality.get.surveys` | ● | | | | | ● | | ● | ● | | | ● | | | | | | | ○ |
| `quality.get.conversation.surveys` | ● | | | | | | | ● | | | | | | | | | | | |
| `quality.get.agents.activity` | | | ● | ○ | | | | | ● | | | | | | | | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | | ● | | | | | | | ● | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | | | | | | | | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | | | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.categories` | ○ | | | | | | | | | | | | | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | | | | | | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | ● | | | | | | | | | | | ● | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | ● | ● | | | | | | | | | | | | ● | ● |
| `routing.get.skill.groups` | | | | | | | ● | | | | | | | | | | | | |
| `routing.get.skill.group.members` | | | | | | | ● | | | | | | | | | | | | |
| `routing.get.user.utilization` | | | | ○ | | | | | | | | | | | | | | | |
| `routing.get.queue.estimated.wait.time` | | ● | | | | | | | | ● | | | | | | | | | |
| `routing-queue-members` | | ● | | | | | ● | | | | ● | | | | | | ● | ● | |
| `analytics-conversation-details-query` | | ● | | ○ | ● | ● | | | | | | ● | | ○ | | | | ● | ● |
| `analytics.get.multiple.conversations.by.ids` | | | | | | | | | | | | | | | | | | | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | ● | | | | ● | | ● | | | | | | | | | | ● |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | | | | | | ● | | | | | | | | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | | | | ● | | ● | | | | | | | | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | | | | | | ● | | | | | | | | | | ● |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | | | | | | ● | | | | | | | | | | ● |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | ● | ● | ● | | ● | | ● | | | | | | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | | | | | | ● | | | | | | | | | | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | | | | ● | | ● | | | | | | | | |
| `analytics.query.user.aggregates.performance.metrics` | | | | ● | | | | | | | ● | | | | | | | | |
| `analytics.query.user.details.activity.report` | | | ● | ● | | | | | | | | | | | | | | | |
| `analytics.query.queue.observations.real.time.stats` | | ● | | | | | | | | ● | | | | | | | ● | | |
| `analytics.query.conversation.activity.real.time` | | | | | | | | | | ● | | | | | | | | | |
| `analytics.query.user.observations.real.time.status` | | ● | | | | | | | | ● | | | | | | | ● | | |
| `analytics.get.agent.active.status` | | | | ○ | | | | | | ○ | | | | | | | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | | | | | | | | ● | | | | | |
| `analytics.query.flow.observations` | | | | | | | | | | ● | | | | | | | | | |
| `analytics.post.transcripts.aggregates.query` | | | | | | | | | ● | | | | | | | | | | |
| `analytics.query.bot.aggregates` | | | | | | | | | | | | | | ● | | | | | |
| `authorization.get.single.division` | | | ● | | | | | | | | | | | | | | | | |
| `authorization.list.division.queues` | | | ● | | | | ● | | | | | | | | | | | | |
| `authorization.get.division.grants` | | | ● | | | | | | | | | | | | | | | | |
| `users.get.user.details.with.full.expansion` | | | | ● | ● | | | | | | | | | | | | | | |
| `users.get.user.routing.skills` | | | | ● | | | ● | | | | | | | | | | | | |
| `users.get.user.queue.memberships` | | | | ● | | | | | | | | | | | | | | | |
| `users.get.bulk.user.presences` | | | | ● | | | | | | | | | | | | | | | |
| `users.get.agent.active.conversations` | | | | ○ | | | | | | ○ | | | | | | | | | |
| `users.get.agent.current.routing.status` | | | | ○ | | | | | | ○ | | | | | | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | | | | | | ● | | | | | | | | |
| `audit-logs` | | | | ● | | | | | | | | | | | | | ○ | ○ | |
| `stations.get.stations` | | | | | | | | | | | | | | | | ● | ● | | |
| `users` | | | | | | | | | | | | | | | ● | | ● | | |
| `telephony.get.edges` | | | | | | | | | | | | | ● | | | ● | | | |
| `telephony.get.trunks` | | | | | | | | | | | | | ● | | | ● | | | |
| `telephony.get.trunk.metrics.summary` | | | | | | | | | ○ | | | | ● | | | ● | | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | | | | | | | | | | | | ● | ○ | | |
| `telephony.get.sip.message.for.conversation` | | | | | | | | | | | | | | | ● | | | ● | |
| `alerting.get.alerts` | | | | | | | | | ○ | | | | ● | | | ● | | | |
| `alerting.get.rules` | | | | | | | | | | | | | ● | | | ● | | | |
| `coaching.get.appointments` | | | ● | ○ | | | | | | | | | | | | | | | ○ |
| `flows.get.all.flows` | | | | | | | | | | | | | | ● | | | | ○ | |
| `flows.get.flow.outcomes` | | | | | | | | | | | | | | ● | | | | | |
| `flows.get.flow.milestones` | | | | | | | | | | | | | | ● | | | | | |
| `workforce.get.management.units` | | | | | | | | | ● | | | | | | | | | | |
| `workforce.get.business.units` | | | | | | | | | ● | | | | | | | | | | |
| `workforce.get.management.unit.users` | | | | | | | | | ● | | | | | | | | | | |
| `workforce.get.management.unit.adherence` | | | | | | | | | ● | | ● | | | | | | | | |
| `workforce.get.agent.management.unit` | | | | ● | | | | | | | | | | | | | | | |
| `workforce.get.adherence.bulk` | | | | ● | | | | | | | | | | | | | | | |
| `routing.get.all.wrapup.codes` | | | | | | ● | | | ● | | | ● | | | | | | | |
| `outbound.get.campaigns` | | | | | | | | | ● | | | | | | | | | | |
| `outbound.get.contact.lists` | | | | | | | | | ● | | | | | | | | | | |
| `outbound.get.events` | | | | | | | | | ● | | | | | | | | | | |
| `conversations.get.active.calls` | | | | | | | | | | | | | ● | | | ● | | | |
| `quality.get.published.evaluation.forms` | | | | | | | | | | | | | | | | | | | |

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
