# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-06-23  
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
7. [Outbound Campaign Investigation](#7-outbound-campaign-investigation)
8. [Agent Investigation Extensions](#8-agent-investigation-extensions-release-13)
9. [Conversation Investigation Extensions](#9-conversation-investigation-extensions-release-13)
10. [Queue Investigation Extensions](#10-queue-investigation-extensions-release-13)
11. [Reference & Lookup Layer (Fetch Once, Join Everywhere)](#11-reference--lookup-layer-fetch-once-join-everywhere)
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
| 12 *(STA enabled)* | `speechandtextanalytics.get.topics` | org-wide → match by `conversationId` in topic hits | Resolves the topic IDs returned in step 9 to human-readable topic names — "what was this call about," not just a sentiment number |
| 13 *(agent-assist enabled)* | `conversations.get.conversation.suggestions` | `conversationId` | Agent-assist / Copilot suggestions surfaced during the call — knowledge articles, scripted responses |
| 14 *(conditional on step 13)* | `conversations.get.conversation.suggestion.detail` | `suggestionId` | Full content/confidence of a specific suggestion — did the agent follow or ignore the recommended response? |

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

If metrics alone don't explain the defect, escalate to raw Edge logs:
`telephony.create.edge.logs.job` (`POST /api/v2/telephony/providers/edges/{edgeId}/logicalinterfaces/.../logs/jobs`)
→ `telephony.get.edge.logs.job` (poll job status) → `telephony.request.edge.logs.job.upload` (request the
signed upload of selected files). This is the same submit/poll/fetch shape as the analytics async jobs and
should only be invoked when metrics/SIP trace triage has narrowed the issue to a specific Edge.

For call-quality complaints that need packet-level proof (one-way audio, jitter, garbled speech),
`Export-GenesysConversationInvestigationPackage` pulls the actual PCAP: `GET /api/v2/telephony/siptraces`
(metadata matching the conversation window) → `POST /api/v2/telephony/siptraces/download` (request package)
→ `GET /api/v2/telephony/siptraces/download/{downloadId}` (poll for the signed S3 URL) → download. The
companion `apps/Parse-SipTrace/Parse-SipTrace.ps1` script parses the resulting trace into Call-ID, method,
response code, and SDP/media fields without requiring Wireshark. Requires `telephony:pcap:view` /
`telephony:pcap:add` permissions — broader than the read-only scopes most other steps in this investigation
need, so request it only when the SIP trace (step 8) shows a setup or media-negotiation anomaly worth
capturing at the packet level.

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
| 11 *(real-time, optional)* | `conversations.get.active.calls` / `.get.active.chats` / `.get.active.emails` / `.get.active.callbacks` | `queueId` filter | Live per-media-type breakdown of what's in the queue right now — pairs with step 1's `mediaTypes` config to explain *why* a chat-only queue shows zero active calls |
| 12 *(IVR upstream of queue)* | `analytics.query.flow.aggregates.execution.metrics` | `queueId` or flow filter | nFlowOutcomeFailed / nFlowMilestone for the Architect flow(s) that route into this queue — distinguishes "queue underperformed" from "IVR misrouted before the queue ever saw the call" |

> **mediaType nuance:** steps 4-8 always carry a `mediaType` dimension already — step 11 only earns its
> place when the question is specifically "what's sitting in this queue at this exact moment," since the
> aggregates in steps 4-8 already answer the same question historically.

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
| 10 *(WFM licensed)* | `workforce.get.business.units` | org-wide → match by name/division | Resolves which WFM business unit(s) this division's scheduling rolls up to |
| 11 *(WFM licensed)* | `workforce.get.management.units` | `businessUnitId` | Management units (scheduling teams) within the business unit — the WFM equivalent of "a group of agents," often cut differently than the division |
| 12 *(WFM licensed)* | `workforce.get.management.unit.users` | `managementUnitId` | Roster of agents in each management unit — intersect with step 3 to find agents who are *division members but scheduled under a different MU* (or vice versa) |
| 13 *(WFM licensed)* | `workforce.get.management.unit.adherence` | `managementUnitId` | Scheduled-vs-actual state per agent: adherence %, exception minutes, conformance — the workforce metric a director asks for in the same breath as AHT and QM score |

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
  → workforce.get.management.unit.adherence[].user.id (left join — WFM-scheduled agents only)
```

### Analytical Questions Answered

- How many agents are in this division and who are they?
- What queues does this division own?
- Which agents handled the most volume? Which had the highest AHT?
- Which agents spent the most time off-queue or in non-productive states?
- Which agents have been evaluated? Who has the highest/lowest scores?
- Which agents have received recent coaching? Is coaching correlated with score improvement?
- Which agents are out of schedule adherence, and does that correlate with their handle-time or QM trend?

### Divisions Are Not Management Units — Don't Assume a 1:1 Mapping

The task framing for this investigation treats a division as "a group of agents," and operationally
it is — but Genesys Cloud models division (authorization/access-control scope) and WFM management
unit (scheduling/forecasting scope) as two independent hierarchies. The same division frequently spans
multiple management units (e.g., a "Retail Support" division staffed by both a day-shift MU and a
night-shift MU), and a single management unit can contain agents from more than one division (shared
overflow staff). Steps 10-13 should be treated as an *enrichment join*, not a strict filter: resolve
the agent roster from step 3 first, then look up each agent's management unit membership rather than
assuming `divisionId` constrains `managementUnitId`. When the two rosters disagree, that mismatch is
itself often the finding (an agent scheduled under the wrong MU, or division access not yet revoked
after a team transfer).

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
| `workforce.get.management.unit.adherence` *(WFM licensed)* | `managementUnitId`, daily | Org-wide schedule adherence % — one of the few WFM metrics executives track alongside AHT/SLA |

#### Layer 4 — Quality & Voice-of-Customer
| Dataset Key | Grouping | Metrics |
|-------------|----------|---------|
| `quality.get.agents.activity` | `userId` | Evaluation coverage rate, average score, score distribution |
| `quality.get.surveys` | `conversationId` (aggregate) | CSAT/NPS: response rate, average score |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | Speech analytics coverage: nSpeechTextAnalyzedConversations, oSentimentScore |
| `speechandtextanalytics.get.topics` *(STA enabled)* | org-wide, joined onto STA-detected hits in the window | Top-N topic frequency — "what customers called about," the single most-requested executive view that pure metrics can't answer |

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
  - Schedule adherence: from workforce.get.management.unit.adherence (WFM licensed orgs only)
  - Top 5 contact reasons: from speechandtextanalytics.get.topics (STA-enabled orgs only)

Trend views (daily granularity):
  - Volume by day with channel mix
  - AHT trend by queue
  - Abandon rate trend by queue
  - SLA achievement heatmap by queue × day
```

Both new headline metrics are deliberately gated behind their respective licenses (WFM, STA) rather than
attempted unconditionally — an executive rollup that silently shows "0% adherence" for an org without WFM
licensed is worse than omitting the row, since it reads as a real number rather than "not applicable."

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
| 10 *(drilldown only)* | `conversations.get.active.calls` / `.get.active.chats` / `.get.active.emails` / `.get.active.callbacks` | All queues, filterable | The actual conversation list behind a wall-board number — supervisor clicked "47 waiting," this returns the 47 |

### Polling Note

Real-time datasets (`analytics.query.queue.observations.real.time.stats`,
`analytics.query.conversation.activity.real.time`, `analytics.query.user.observations.real.time.status`)
do not accept `interval` parameters — they reflect the current state as of the API call. These
should be polled at the rate appropriate for the display (typically 10–30 seconds for a wall board).

The `analytics.get.agent.active.status` endpoint returns a single agent's live state and is
intended for targeted drilldown (supervisor clicks on an agent in the wall board). Step 10 is the
queue-level equivalent — only fetch it when a supervisor drills into a specific queue's count, not on
every wall-board refresh tick, since it returns full conversation objects rather than aggregate counts.

### Alternative to Polling: Event Streaming

For organizations where 10-30 second polling latency is too slow (e.g., compliance escalation triggers,
real-time ML pipelines), Genesys Cloud's Notification API exposes the same Analytical Detail Events and
Conversation Events as a push subscription rather than a pull. `notifications.get.available.notification.topics`
lists the subscribable topics; `notifications.get.notification.subscriptions` shows current subscriptions.
This is a fundamentally different integration shape (WebSocket channel, not REST polling) and is not
part of the catalog's request/response dataset model — it's noted here so a real-time investigation
doesn't default to aggressive polling when push delivery is the better fit for the latency requirement.

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

BYOI is not limited to conversation injection — the same provider integration can ingest externally
managed **agent presence and routing-status events**, which Workforce Management and Analytics then
treat identically to native presence/routing data. If a division or agent investigation (sections 3
and 8) shows an agent with unusual `tAgentRoutingStatus` gaps or presence states that don't match any
native system presence definition (cross-check against `presence.get.system.presence.definitions`),
check whether that agent is provisioned through a BYOI provider before assuming a data quality issue.

### Embeddable Framework Conversations

Conversations visible to agents via the Embeddable Framework return the same object shape as
`conversations.get.conversation.object`. The condensed view used by the embedded client includes:
`participants[].purpose`, `participants[].state`, `participants[].calls[].state`,
`participants[].calls[].muted`, `participants[].calls[].held`. These fields are present in the
full object returned by the dataset and need no special handling.

---

## 7. Outbound Campaign Investigation

**Subject:** One `campaignId` + time window
**Use case:** A WFO/dialer administrator or operations analyst is troubleshooting an outbound voice
campaign — pacing complaints, abandon-rate spikes, or a sudden drop in connect rate. Outbound campaigns
share the same conversation/analytics pipeline as inbound, but the dialer adds its own configuration,
health, and disposition layer that inbound investigations never need.

**Core question:** *Is this campaign healthy, and what is the dialer actually doing?*

Implemented as `Get-GenesysCampaignInvestigation` (see [INVESTIGATIONS.md §4.4](INVESTIGATIONS.md));
documented here so it joins the same combination-pattern catalog as the other five investigations.

### Dataset Steps (ordered)

| Step | Dataset Key | JoinOn | What It Adds |
|------|-------------|--------|--------------|
| 1 | `outbound.get.campaigns` | seed → `campaignId` | Campaign status, dialing mode (preview/progressive/predictive), queue, caller ID, configured abandon threshold |
| 2 | `outbound.get.contact.lists` | `campaign.contactListId` | Contact list identity and size for reconciliation — is the campaign exhausting its list? |
| 3 | `routing.get.single.queue.config` | `campaign.queueId` | The connected queue's answer-handling config — agents answering outbound connects use the same queue contract as inbound |
| 4 | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Live pacing/health snapshot — current calls-per-agent ratio, current abandon rate, dialer error indicators |
| 5 | `outbound.get.events` | `campaignId` | Dialer events and contact dispositions — every attempt, connect, and disposition code in the window |
| 6 | `audit-logs` | `entity.id = campaignId` | Recent configuration changes to the campaign — did someone change the dial ratio or abandon threshold right before the spike? |
| 7 | `analytics-conversation-details-query` (campaignId segment filter) | `participants.campaignId` | The actual conversations the dialer produced — segment-level detail for connect/talk/wrapup analysis identical to inbound |
| 8 *(derived)* | `outbound.get.events` filtered to abandon-related dispositions | `campaignId` | Abandoned-attempt evidence isolated from step 5 — the specific events a compliance reviewer asks for after an abandon-rate complaint |

### Key Joins

```
outbound.get.campaigns.id
  → outbound.get.contact.lists.id (via campaign.contactListId)
  → routing.get.single.queue.config.id (via campaign.queueId)
  → outbound.get.campaign.diagnostics.summary.campaignId
  → outbound.get.events[].campaignId (dialer event stream)
  → audit-logs[].entity.id (left join — config-change correlation)
  → analytics-conversation-details-query[].participants[].campaignId (conversation-level detail)
```

### Analytical Questions Answered

- Is the campaign currently healthy (pacing, abandon rate, dialer errors)?
- Is the campaign running out of contacts to dial?
- What did agents do with the connects this campaign produced — talk time, wrapup codes, transfers?
- Did a configuration change (dial ratio, abandon threshold, queue reassignment) precede a metric shift?
- Which specific attempts abandoned, and do they cluster around a particular time or contact segment?

### Why Campaign Joins to Queue, Not the Other Way Around

Unlike the inbound investigations, this pattern treats the queue as a *leaf* enrichment step rather than
a top-level entry point — `routing.get.single.queue.config` is fetched because the campaign names a queue,
not because the investigation started from a queue. An operator who wants "all campaigns feeding queue X"
should start from the Queue Investigation (§2) and cross-reference `outbound.get.campaigns` filtered by
`queueId`, rather than fanning out N campaign investigations.

---

## 8. Agent Investigation Extensions (Release 1.3)

The existing Agent Investigation (`Get-GenesysAgentInvestigation`) covers 8 steps. These additional
datasets enrich the investigation without replacing any existing step.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| utilization | `routing.get.user.utilization` | `userId` | Max channel capacities — why can the agent only handle N simultaneous chats? |
| currentStatus | `users.get.agent.current.routing.status` | `userId` | Routing state at investigation time (IDLE / INTERACTING / OFF_QUEUE) |
| activeConversations | `users.get.agent.active.conversations` | `userId` | In-progress conversations if `currentStatus = INTERACTING` |
| qualityActivity | `quality.get.agents.activity` | `userId` | Evaluation count, average/highest/lowest scores for the window |
| coaching | `coaching.get.appointments` | `userId` | Coaching sessions attending/facilitating in the window |
| station *(voice complaints)* | `stations.get.stations` | `userId` (via station's assigned-user field) | The physical/softphone station the agent is registered to — correlates a call-quality complaint to a specific desk phone or WebRTC client rather than the agent in the abstract |

**Trigger conditions:** `currentStatus` and `activeConversations` steps are conditional on the
agent being in an active state at investigation time. `coaching` step is conditional on WFM being
licensed and configured. `station` is conditional on the complaint being voice/audio-quality related —
it adds nothing to a chat- or email-only investigation.

---

## 9. Conversation Investigation Extensions (Release 1.3)

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
| topicLabels | `speechandtextanalytics.get.topics` | topic ID from `conversations.get.speech.text.analytics` hits | Human-readable topic names instead of opaque topic IDs |
| agentAssist | `conversations.get.conversation.suggestions` + `.get.conversation.suggestion.detail` | `conversationId` → `suggestionId` | Agent-assist/Copilot suggestions offered and whether the agent acted on them |
| pcapPackage *(escalation only)* | `Export-GenesysConversationInvestigationPackage` (`telephony/siptraces` → `siptraces/download` → `siptraces/download/{downloadId}`) | `conversationId` + time window | Packet-level PCAP for the conversation, parsed via `Parse-SipTrace.ps1` |

**Conditional steps:** `sipTrace` runs only when `conversations.get.conversation.object.participants[].calls` is
non-empty (voice conversation). `sentimentTimeline` runs only when `conversations.get.speech.text.analytics`
returns `speechAndTextAnalyticsConversation.analysisStatus = "Success"`. `pcapPackage` is gated behind the
elevated `telephony:pcap:*` permission and should be requested deliberately, not run by default — see the
Voice Engineer Notes in §1 for when it's warranted.

---

## 10. Queue Investigation Extensions (Release 1.3)

The existing Queue Investigation (`Get-GenesysQueueInvestigation`) covers 6 steps. These additions
complete the picture.

| Extension Step | Dataset Key | JoinOn | What It Adds |
|----------------|-------------|--------|--------------|
| queueConfig | `routing.get.single.queue.config` | `queueId` | Full queue config (replaces/enriches the routing-queues list step) |
| wrapupLabels | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Human-readable labels for the wrapup distribution step |
| transfers | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer rate and type breakdown |
| wrapupDistribution | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Wrapup code frequencies (join wrapupLabels for labels) |
| conversationDetail | `analytics-conversation-details-query` (queueId filter) | `conversationId` | Individual conversations for case-level review |
| upstreamFlowHealth | `analytics.query.flow.aggregates.execution.metrics` | flow(s) configured to route into `queueId` | Distinguishes a queue performance problem from an IVR misroute upstream of the queue |

---

## 11. Reference & Lookup Layer (Fetch Once, Join Everywhere)

Every investigation above resolves IDs returned by transactional/analytics endpoints against a small
set of organisation-wide reference datasets. These datasets change rarely (configuration, not activity),
return their entire contents in one or two calls, and should be fetched **once per investigation run (or
cached across runs)** rather than re-queried inside every per-entity loop. Treating them as a join layer —
not a step that belongs in any single investigation's table — is what keeps the per-conversation,
per-queue, and per-agent investigations above from each re-fetching the same skill/division/presence
label dictionary dozens of times.

| Dataset Key | Resolves | Used By |
|-------------|----------|---------|
| `routing.get.all.wrapup.codes` | `wrapUpCode` → label, org-wide | Queue, Division, Executive Rollup wrapup tables |
| `routing.get.all.routing.skills` | skill ID → skill name | Agent Investigation skill list, Division skill-group reporting |
| `routing.get.skill.groups` | skill group ID → member count + division | Division Investigation (cross-queue skill groupings) |
| `routing.get.all.languages` | language ID → language name | Agent Investigation, queue language-skill config |
| `authorization.get.all.divisions` | division ID → name, org-wide | Any investigation needing to label a `divisionId` without a full division fetch |
| `authorization.get.roles` | role ID → role name/permissions | Agent Investigation (what can this agent actually do), audit-log review |
| `presence.get.system.presence.definitions` / `presence.get.organization.presence.definitions` | presence ID → label (Available, Busy, Meal, etc.) | Division/Agent time-in-state tables; also the cross-check for BYOI-sourced presence noted in §6 |
| `quality.get.published.evaluation.forms` | evaluation form ID → form name/structure | Conversation/Division QM score tables — explains *which* rubric produced a score |

**Design rule:** if a dataset's `paging.profile` is effectively "fetch all, rarely changes" and its only
purpose elsewhere in this document is label resolution (not its own metrics), it belongs here, not as a
numbered step in a per-entity investigation. This is the mechanism that keeps the investigations
informative without turning every run into a dump of every catalog dataset that happens to share a key.

---

## 12. Dataset Combination Reference Matrix

The matrix below shows which datasets are used across which investigations and reporting patterns.
`●` = used, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conversation Deep Dive | Queue Investigation | Division Investigation | Executive Rollup | Real-Time Monitoring | Agent Investigation | Campaign Investigation |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `conversations.get.conversation.object` | ● | | | | | | |
| `analytics.get.single.conversation.analytics` | ● | | | | | | |
| `conversations.get.conversation.recording.metadata` | ● | | | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | | | |
| `conversations.search.participant.attributes` | ● | | | | | | |
| `quality.get.evaluations.query` | ● | ○ | | | | | |
| `quality.get.surveys` | ● | | | ● | | | |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | |
| `conversations.get.speech.text.analytics` | ○ | | | | | | |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | |
| `speechandtextanalytics.get.topics` | ○ | | | ● | | | |
| `conversations.get.conversation.suggestions` | ○ | | | | | | |
| `conversations.get.conversation.suggestion.detail` | ○ | | | | | | |
| `routing.get.single.queue.config` | | ● | | | | | ○ |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | |
| `analytics-conversation-details-query` | | ● | | | | ○ | ○ |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | | ● | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | ● | | | |
| `analytics.query.queue.aggregates.service.level` | | ● | | ● | | | |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | ● | | | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | ● | | | |
| `analytics.query.flow.aggregates.execution.metrics` | | ○ | | | | | |
| `routing-queue-members` | | ● | | | | | |
| `conversations.get.active.calls` / `.get.active.chats` / `.get.active.emails` / `.get.active.callbacks` | | ○ | | | ○ | | |
| `authorization.get.single.division` | | | ● | | | | |
| `authorization.list.division.queues` | | | ● | | | | |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | ● | |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | ● | | ● | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | ● | |
| `analytics.query.user.details.activity.report` | | | ● | | | ● | |
| `quality.get.agents.activity` | | | ● | ● | | ○ | |
| `coaching.get.appointments` | | | ● | | | ○ | |
| `workforce.get.business.units` | | | ○ | | | | |
| `workforce.get.management.units` | | | ○ | | | | |
| `workforce.get.management.unit.users` | | | ○ | | | | |
| `workforce.get.management.unit.adherence` | | | ○ | ○ | | | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | ● | | | |
| `analytics.post.transcripts.aggregates.query` | | | | ● | | | |
| `analytics.query.queue.observations.real.time.stats` | | | | | ● | | |
| `analytics.query.conversation.activity.real.time` | | | | | ● | | |
| `analytics.query.user.observations.real.time.status` | | | | | ● | | |
| `analytics.get.agent.active.status` | | | | | ○ | ○ | |
| `users.get.agent.active.conversations` | | | | | ○ | ○ | |
| `users.get.agent.current.routing.status` | | | | | ○ | ○ | |
| `analytics.query.flow.observations` | | | | | ● | | |
| `telephony.get.trunk.metrics.summary` | | | | ○ | ● | | |
| `telephony.get.edge.performance.metrics` | ○ | | | | ● | | |
| `telephony.create.edge.logs.job` / `.get.edge.logs.job` / `.request.edge.logs.job.upload` | ○ | | | | | | |
| `alerting.get.alerts` | | | | ○ | ● | | |
| `users.get.user.details.with.full.expansion` | | | | | | ● | |
| `users.get.user.routing.skills` | | | | | | ● | |
| `users.get.user.queue.memberships` | | | | | | ● | |
| `users.get.bulk.user.presences` | | | | | | ● | |
| `routing.get.user.utilization` | | | | | | ○ | |
| `stations.get.stations` | | | | | | ○ | |
| `audit-logs` | | | | | | ● | ○ |
| `outbound.get.campaigns` | | | | | | | ● |
| `outbound.get.contact.lists` | | | | | | | ● |
| `outbound.get.campaign.diagnostics.summary` | | | | | | | ● |
| `outbound.get.events` | | | | | | | ● |
| `outbound.get.messaging.campaigns` | | | | | | | ○ |

### Reference & Lookup Datasets (used across all columns above — see §11)

`routing.get.all.wrapup.codes`, `routing.get.all.routing.skills`, `routing.get.skill.groups`,
`routing.get.all.languages`, `authorization.get.all.divisions`, `authorization.get.roles`,
`presence.get.system.presence.definitions`, `presence.get.organization.presence.definitions`,
`quality.get.published.evaluation.forms` — omitted from the per-investigation columns above because
they are not investigation-specific; they are a shared label-resolution layer fetched once and joined
wherever an ID needs a name.

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
| `nFlowOutcomeFailed` | Architect flow executions ending in a failed outcome | IVR/flow health, upstream-of-queue triage |
| `nFlowMilestone` | Flow milestone checkpoints reached | Flow completion/drop-off analysis |
| WFM adherence % | Scheduled vs. actual agent state, expressed as a percentage | Workforce layer of executive rollup; division/agent group conformance |
| Topic confidence | STA topic-match confidence score | Filtering low-confidence topic hits before counting them in a rollup |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
