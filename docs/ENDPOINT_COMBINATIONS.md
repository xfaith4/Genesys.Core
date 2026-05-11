# Endpoint Combinations — Investigation Patterns & Executive Rollups

> Status: Active  
> Last updated: 2026-05-11  
> Companion to: [INVESTIGATIONS.md](INVESTIGATIONS.md), [ROADMAP.md](ROADMAP.md)

This document describes how catalog datasets combine into coherent investigations and executive
reporting rollups. Each combination is documented with its subject, the ordered dataset steps,
the join keys that connect them, and the analytical questions it answers.

The goal of Genesys.Core is to be **informative without being a data dump**. Every combination
here answers a specific operational question and terminates when that question is answered — not
when the API is exhausted.

---

## Contents

**Investigation Recipes**

1. [Single Conversation Deep Dive (Voice Engineer)](#1-single-conversation-deep-dive-voice-engineer)
2. [All Conversations in a Queue](#2-all-conversations-in-a-queue)
3. [Division / Agent Group Investigation](#3-division--agent-group-investigation)
4. [Agent Investigation](#4-agent-investigation)
5. [Call History & Customer Journey](#5-call-history--customer-journey)
6. [Agent Assist & Copilot Effectiveness](#6-agent-assist--copilot-effectiveness)
7. [BYOI External Conversation Investigation](#7-byoi-external-conversation-investigation)

**Executive Reporting Playbooks**

8. [Service Level & Abandon KPIs](#8-service-level--abandon-kpis)
9. [Agent Performance Scorecard](#9-agent-performance-scorecard)
10. [Wrapup & Transfer Analysis](#10-wrapup--transfer-analysis)
11. [Quality & CSAT Summary](#11-quality--csat-summary)
12. [Speech & Text Analytics Sentiment Trends](#12-speech--text-analytics-sentiment-trends)
13. [Digital Channel Volume & SLA](#13-digital-channel-volume--sla)
14. [WFM Adherence & Occupancy](#14-wfm-adherence--occupancy)
15. [Outbound Campaign Performance](#15-outbound-campaign-performance)
16. [Flow & IVR Performance](#16-flow--ivr-performance)
17. [Platform Security & API Governance](#17-platform-security--api-governance)
18. [Organisation Health & Limits](#18-organisation-health--limits)
19. [Skills & Routing Workforce Readiness](#19-skills--routing-workforce-readiness)

**Voice Engineer Playbooks**

20. [Single Call Forensics](#20-single-call-forensics)
21. [Trunk & Edge Health Check](#21-trunk--edge-health-check)
22. [Queue Saturation & Staffing Analysis](#22-queue-saturation--staffing-analysis)
23. [Flow & IVR Diagnostics](#23-flow--ivr-diagnostics)
24. [Recording Compliance Audit](#24-recording-compliance-audit-by-queue)
25. [Routing Architecture Audit](#25-routing-architecture-audit)
26. [Presence & Routing Status Audit](#26-presence--routing-status-audit)
27. [Multi-Channel Active Contact Centre Snapshot](#27-multi-channel-active-contact-centre-snapshot)

**Reference**

28. [Dataset Combination Reference Matrix](#28-dataset-combination-reference-matrix)
29. [Metric Glossary](#appendix-metric-glossary)

---

## 1. Single Conversation Deep Dive (Voice Engineer)

**Subject:** One `conversationId`  
**Use case:** A voice engineer or QM analyst receives a complaint about a specific call — wrong queue,
long hold, audio quality, dropped call, incorrect routing. They need the complete picture of one
conversation: where it came from, how it routed, how long each phase took, what the SIP signaling said,
whether a recording exists, and what the quality score was.

**Core question:** *What actually happened in this conversation, end-to-end?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics.get.single.conversation.analytics` | seed → `conversationId` | Per-segment timing: IVR duration, ACD wait, talk time, hold time, ACW, conference |
| 2 | `conversations.get.conversation.object` | `conversationId` | Participants, sessions, DNIS/ANI, state, originatingDirection, `externalTag` (BYOI indicator) |
| 3 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording IDs, media type, duration, archival status |
| 4 | `conversations.get.recordings` | `conversationId` | Recording download URLs and media type |
| 5 | `conversations.get.conversation.customattributes` | `conversationId` | Custom attributes set by IVR/Architect flows (account numbers, intent, escalation flags) |
| 6 | `conversations.search.participant.attributes` | `conversationId` | Participant-level attributes (IVR variables, data action outcomes, flow-set values) |
| 7 | `conversations.get.speech.text.analytics` | `conversationId` | Top-level S&TA: sentiment scores, silence%, overtalk count, analysis status |
| 8 *(STA enabled)* | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-utterance sentiment timeline, agent vs. customer breakdown |
| 9 *(STA enabled)* | `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId+communicationId` | Transcript download URL per communication leg |
| 10 | `conversations.get.conversation.suggestions` | `conversationId` | Agent Assist suggestions offered during the conversation |
| 11 | `quality.get.evaluations.query` | `conversationId` | QM evaluation scores, form used, evaluator, calibration status |
| 12 | `quality.get.surveys` | `conversationId` | Post-call CSAT/NPS survey result if survey was triggered |
| 13 *(voice only)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP signaling trace: INVITE, 200 OK, BYE, re-INVITE, codec negotiation |

### Key Joins

```
analytics.get.single.conversation.analytics.conversationId
  → conversations.get.conversation.object.conversationId (participant overlay)
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
- Were Agent Assist suggestions offered? Were they relevant?
- Was this a BYOI injected call? (check `externalTag` from step 2)

### Voice Engineer Notes

Step 13 (SIP trace) is the definitive source for:
- Call setup failures (no 200 OK, 486 Busy, 503 Service Unavailable)
- One-way audio (media IP mismatch in SDP)
- Premature disconnection (BYE before expected, no 200 OK to BYE)
- Codec negotiation failures

The `telephony.get.edge.performance.metrics` dataset should be pulled for the Edge appliance
that handled the call if CPU, memory, or error counters suggest resource pressure during the
conversation window.

### BYOI Indicator

If `conversations.get.conversation.object` returns a non-null `externalTag` or
`externalConversationId`, the call was injected via the BYOI integration. See
[section 7](#7-byoi-external-conversation-investigation) for the specialised BYOI investigation.

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
| 1 | `routing.get.single.queue.config` | seed → `queueId` | Full queue config: routing method, SLA targets, DNIS, skill evaluation mode, ACW settings |
| 2 | `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Human-readable wrapup code labels for the queue |
| 3 | `routing-queue-members` | `queueId` | Current member roster with routing status, presence, and conversation summary |
| 4 | `analytics-conversation-details-query` (queueId filter) | `queueId` | Every conversation in the window with participant/segment detail |
| 5 | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Aggregate: nConnected, tHandle, tTalk, tAcw, tAnswered, nOffered |
| 6 | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon count: nAbandoned, tAbandon, tShortAbandon |
| 7 | `analytics.query.queue.aggregates.service.level` | `queueId` | SLA achievement: nAnsweredIn20/30/60, oServiceLevel, nOverSla |
| 8 | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Transfer analysis: nTransferred, nBlindTransferred, nConsultTransferred |
| 9 | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` + wrapUpCode | Wrapup code frequencies (join step 2 for labels) |
| 10 | `quality.get.evaluations.query` (queueId filter) | `conversationId` | QM evaluation coverage and scores for conversations in this queue |

### Key Joins

```
routing.get.single.queue.config.id
  → analytics.query.conversation.aggregates.*.queueId (aggregate overlay)
  → routing-queue-members.queueId (who was staffed)

analytics.query.conversation.aggregates.wrapup.distribution.wrapUpCode
  → routing.get.queue.wrapup.codes.by.queue.id (label resolution)

analytics-conversation-details-query[].conversationId
  → quality.get.evaluations.query[].conversationId (left join)
```

### Analytical Questions Answered

- What was the offered/connected/abandoned volume for this queue?
- Did the queue meet its SLA target? In which hourly intervals did it miss?
- What percentage of conversations were transferred? Where did they go?
- What wrapup codes dominated, and what do they mean?
- Who were the active agents? What was their routing status during the window?
- How many conversations were quality-reviewed? What was the average score?

### Divisions as Queue Groups

Queues within a division represent a natural management boundary. To investigate an entire division:
1. Use `authorization.list.division.queues` to get all queue IDs in the division.
2. Fan out the steps above once per queue, or use `authorization.get.single.division` as the
   seed and filter analytics queries with `divisionId` predicates.

---

## 3. Division / Agent Group Investigation

**Subject:** One `divisionId` + time window  
**Use case:** A contact centre director or workforce analyst needs to understand how a specific
business unit (division) performed — which agents are in it, what volume each handled, time-in-state,
quality scores, and coaching coverage. Divisions are the primary cross-queue grouping unit in Genesys
Cloud; an agent's `divisionId` ties them to queues across the organisation regardless of queue
configuration.

**Core question:** *How did this division's agents perform as a group?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `authorization.get.all.divisions` | seed → `divisionId` filter | Division name, description, home-division flag |
| 2 | `authorization.list.division.queues` | `divisionId` | All queue IDs assigned to this division |
| 3 | `users.division.analysis.get.users.with.division.info` | `divisionId` | All agents in the division with user IDs, name, email |
| 4 | `analytics.query.user.aggregates.performance.metrics` (divisionId via userId list) | `userId` | Per-agent: nConnected, tHandle, tTalk, tAcw |
| 5 | `analytics.query.user.details.activity.report` (userId list) | `userId` | Login/logout/on-queue presence event timeline per agent |
| 6 | `analytics.query.conversation.aggregates.queue.performance` (queueId list from step 2) | `queueId` | Queue-level SLA, volume, and handle metrics for all division queues |
| 7 | `quality.get.evaluations.query` (agentUserId filter) | `userId` | Quality evaluations for agents in the division |
| 8 | `quality.get.agents.activity` | `userId` | Evaluation counts, average/highest/lowest scores per agent |
| 9 | `coaching.get.appointments` | `userId` | Coaching sessions for agents in the window |
| 10 | `analytics.query.conversation.aggregates.wrapup.distribution` (queueId list) | `queueId` | Wrapup code distribution across all division queues |

### Key Joins

```
authorization.get.all.divisions[divisionId].id
  → authorization.list.division.queues.divisionId (queue enumeration)
  → users.division.analysis.get.users.with.division.info.divisionId (agent enumeration)

users.division.analysis.get.users.with.division.info[].id
  → analytics.query.user.aggregates.performance.metrics[].userId
  → quality.get.agents.activity[].user.id
  → coaching.get.appointments[].attendees[].id
```

### Analytical Questions Answered

- How many agents are in this division and who are they?
- What queues does this division own?
- Which agents handled the most volume? Which had the highest AHT?
- Which agents spent the most time off-queue or in non-productive states?
- Which agents have been evaluated? Who has the highest/lowest scores?
- Which agents have received recent coaching?

---

## 4. Agent Investigation

**Subject:** One `userId` + time window  
**Use case:** A supervisor, HR manager, or QM analyst needs a complete picture of a single agent —
their identity, division, skills, queue memberships, conversation history, performance aggregates,
quality scores, schedule adherence, and coaching record. Used for performance reviews, PIPs, and
escalation root-cause.

**Core question:** *What did this agent do, how well, and why?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `users.get.user.details.with.full.expansion` | seed → `userId` | Name, email, state, department, manager, station, division |
| 2 | `users.get.user.routing.skills` | `userId` | All skills with proficiency ratings |
| 3 | `users.get.user.queue.memberships` | `userId` | Queues the agent belongs to, across all divisions |
| 4 | `routing.get.user.utilization` | `userId` | Max channel capacities (simultaneous calls/chats/emails) |
| 5 | `analytics.query.user.details.activity.report` | `userId` + window | Presence segments, routing-status events, login/logout events |
| 6 | `analytics.query.user.aggregates.performance.metrics` | `userId` + window | Aggregated nConnected, tHandle, tTalk, tAcw |
| 7 | `analytics-conversation-details-query` (participantUserId filter) | `userId` | All conversations the agent handled in the window |
| 8 | `quality.get.agents.activity` | `userId` | Evaluation count, average/highest/lowest scores |
| 9 | `quality.get.evaluations.query` (agentUserId filter) | `userId` | Individual evaluation records |
| 10 | `coaching.get.appointments` | `userId` | Coaching sessions |
| 11 | `workforce.get.management.unit.users` | `userId` | WFM management unit membership |
| 12 | `workforce.get.management.unit.adherence` | `userId` | Schedule adherence — scheduled vs. actual state |
| 13 *(real-time)* | `analytics.get.agent.active.status` | `userId` | Live active channels and current conversation IDs |
| 14 *(real-time)* | `users.get.agent.current.routing.status` | `userId` | Current routing state (IDLE / INTERACTING / NOT_RESPONDING) |
| 15 | `audit-logs` (EntityType=User, EntityId=userId) | `userId` | Account change events (skill add/remove, role change) |

### Key Joins

```
users.get.user.details.with.full.expansion.id → (all subsequent steps via userId)
users.get.user.queue.memberships[].id → routing-queues (queue names)
analytics-conversation-details-query[].conversationId → quality.get.evaluations.query[].conversationId
workforce.get.management.unit.users[].managementUnitId → workforce.get.management.unit.adherence
```

### Divisions as Cross-Queue Agent Groups

An agent's `divisionId` (from step 1) is the key for grouping agents regardless of queue membership.
Use it to pull comparison peers: `users.division.analysis.get.users.with.division.info` with the same
`divisionId` returns all agents in the same business unit for benchmarking.

---

## 5. Call History & Customer Journey

**Subject:** Customer ANI or externalContactId + time window  
**Use case:** A supervisor or CX analyst needs to understand a repeat caller's history — how many times
they contacted the centre, whether their issues were resolved, which queues they traversed, and whether
they switched channels. Used for complaint resolution, NPS detractor analysis, and first-contact
resolution measurement.

**Core question:** *What has this customer experienced across all their interactions, and are we resolving their issue?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.call.history` | seed → ANI/customer | List of conversation IDs across the window, ordered by startTime |
| 2 | `analytics.get.multiple.conversations.by.ids` | `conversationId` list | Batch analytics: tTalk, tAcw, tHandle, queueId, wrapUpCode, agentId per conversation |
| 3 | `analytics-conversation-timeline-analysis` | `conversationId` | Normalised timeline events per conversation: IVR/ACD/agent segments |
| 4 | `conversations.search.participant.attributes` | `conversationId` | IVR intent variables, data action outcomes across all conversations |
| 5 | `conversations.search.customattributes` | `conversationId` | Custom attributes set by flows: CRM case IDs, escalation flags, automation outcomes |
| 6 | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording metadata for each historical conversation |
| 7 | `journey.get.action.maps` | *(reference catalogue)* | Predictive engagement action map definitions — cross-reference to web session data |

### Key Joins

```
conversations.get.call.history[].conversationId
  → analytics.get.multiple.conversations.by.ids (batch lookup)
  → analytics-conversation-timeline-analysis (per-conversation segment enrichment)
  → conversations.search.participant.attributes (per-conversation IVR variables)
  → conversations.search.customattributes (per-conversation flow attributes)
  → conversations.get.conversation.recording.metadata (recording confirmation)
```

### Analytical Questions Answered

- How many times did this customer call in the window?
- Were their issues resolved? (wrapup codes across conversations)
- Did they transfer repeatedly — evidence of poor first-time routing?
- Did they switch channels (voice → callback → chat)?
- What IVR intent was captured — did it change across calls, suggesting unclear self-service?
- Are recordings available for all prior calls for complaint evidence?
- Were any predictive engagement offers made during web sessions?

### Derived Metrics

| Metric | Calculation |
|--------|-------------|
| `repeatContactCount` | COUNT(conversationIds) in window |
| `totalHandleTime` | SUM(tHandle) across conversations |
| `queueTraversalCount` | COUNT DISTINCT(queueId) across all conversations |
| `firstCallResolution estimate` | conversationCount=1 AND wrapUpCode indicates resolved |

---

## 6. Agent Assist & Copilot Effectiveness

**Subject:** `queueId` or `agentUserId` + time window  
**Use case:** A CX technology team or QM manager needs to measure whether Copilot and Agent Assist
suggestions are improving agent performance — specifically handle time reduction, quality score uplift,
and sentiment improvement. Used for Copilot programme ROI validation and confidence-threshold tuning.

**Core question:** *Are AI suggestions improving agent performance and customer experience?*

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `analytics-conversation-details-query` | seed → `queueId`/`userId` | Conversation list with tHandle, tTalk, tAcw, agentId, wrapUpCode |
| 2 | `conversations.get.conversation.suggestions` | `conversationId` | Suggestions offered: type (Knowledge/FAQ/Script), timestamp |
| 3 | `conversations.get.conversation.suggestion.detail` | `conversationId+suggestionId` | Content, confidence score, source (article/script), accepted flag |
| 4 | `conversations.get.speech.text.analytics` | `conversationId` | S&TA: agentSentimentScore, customerSentimentScore, silencePct, overtalkPct |
| 5 | `speech.and.text.analytics.get.sentiment.for.conversation` | `conversationId` | Per-utterance sentiment timeline — compare trajectory with/without accepted suggestions |
| 6 | `quality.get.evaluations.query` | `conversationId` | QM scores — primary correlation target for suggestion acceptance |
| 7 | `quality.get.published.evaluation.forms` | *(form catalogue reference)* | Form definitions — understand which scoring dimensions suggestions address |

### Key Joins

```
analytics-conversation-details-query[].conversationId
  → conversations.get.conversation.suggestions[].conversationId
  → conversations.get.conversation.suggestion.detail (conversationId + suggestionId)
  → quality.get.evaluations.query[].conversationId (left join — not all conversations evaluated)
  → conversations.get.speech.text.analytics[].conversationId
```

### Derived Metrics

| Metric | Calculation |
|--------|-------------|
| `suggestionCoverageRate%` | conversationsWithSuggestions / totalConversations |
| `suggestionAcceptanceRate%` | acceptedSuggestions / offeredSuggestions |
| `ahtDelta` | avgTHandle(accepted) − avgTHandle(declined) |
| `evalScoreDelta` | avgEvalScore(accepted) − avgEvalScore(declined) |

### Analytical Questions Answered

- What percentage of conversations had at least one suggestion offered?
- What is the acceptance rate by suggestion type (Knowledge, FAQ, Script)?
- Do accepted suggestions correlate with lower AHT?
- Do accepted suggestions correlate with higher evaluation scores?
- Are certain agents consistently declining suggestions — a coaching opportunity?
- Which knowledge articles are most frequently surfaced and accepted?

---

## 7. BYOI External Conversation Investigation

**Subject:** One `conversationId` with a non-null `externalTag`  
**Use case:** A conversation originated in an external telephony system and was injected into Genesys
Cloud via the BYOI provider API (`POST /api/v2/conversations/providers/{providerId}/calls`). The
conversation appears in Genesys analytics and recordings, but context lives in the external system.

**Core question:** *Where did this conversation come from, and is Genesys fully processing the injected call?*

### How to Identify a BYOI Conversation

In step 2 of the Single Conversation Deep Dive, `conversations.get.conversation.object` returns:

```json
{
  "externalTag": "<provider-set-tag>",
  "externalConversationId": "<provider-conversation-id>",
  "participants": [{ "purpose": "external", "externalContactId": "..." }]
}
```

A non-null `externalTag` is the definitive BYOI indicator.

### Dataset Steps (ordered)

| Step | Dataset Key | Join Key | What It Adds |
|------|-------------|----------|--------------|
| 1 | `conversations.get.conversation.object` | seed → `conversationId` | Confirms `externalTag`; extracts `externalConversationId` for provider-side lookup |
| 2 | `analytics.get.single.conversation.analytics` | `conversationId` | Segment timing — confirms IVR/ACD/agent timing captured post-injection |
| 3 | `conversations.get.conversation.customattributes` | `conversationId` | Provider-set context: CRM case ID, external call ID, intent label, escalation flags |
| 4 | `conversations.search.participant.attributes` | `conversationId` | Architect-side enrichment that occurred after the BYOI handoff |
| 5 | `conversations.get.conversation.recording.metadata` | `conversationId` | Confirms recording policy triggered for the injected conversation |
| 6 | `conversations.get.recordings` | `conversationId` | Recording download URLs — confirm audio captured from the BYOI SIP handoff |
| 7 *(voice)* | `telephony.get.sip.messages.for.conversation` | `conversationId` | SIP trace of the BYOI SIP-to-SIP handoff (not a PSTN leg) |
| 8 *(STA enabled)* | `conversations.get.speech.text.analytics` | `conversationId` | Confirms S&TA running on injected calls; `analysisStatus` should be 'Success' |
| 9 | `quality.get.evaluations.query` | `conversationId` | Confirms injected conversations flow through QM pipeline identically |

### BYOI Diagnostic Signals

| Signal | Likely Cause |
|--------|-------------|
| `analytics-detail tTalk=0` | Injection succeeded but media never connected; check SIP SDP in trace |
| Recording absent | BYOI SIP handoff audio not captured; check edge recording policy on provider trunk |
| `sta-overview analysisStatus='Failed'` | Audio codec incompatible with S&TA; check SDP offer for codec list |
| `custom-attributes empty` | Provider did not set context at injection; integration bug in provider's POST body |
| `externalTag null` | Conversation is native, not BYOI; use standard Single Conversation Deep Dive instead |

### Embeddable Framework Conversations

Conversations visible to agents via the Embeddable Framework return the same object shape as
`conversations.get.conversation.object`. The condensed view used by the embedded client includes:
`participants[].purpose`, `participants[].state`, `participants[].calls[].state`,
`participants[].calls[].muted`, `participants[].calls[].held`.

---

## 8. Service Level & Abandon KPIs

**Subject:** All queues (or selected subset) + reporting window  
**Purpose:** Weekly/monthly SLA health — service level %, abandon rate, and volume trends grouped by
queue. The primary input for executive contact-centre dashboards.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `routing-queues` | — | Queue name and divisionId lookup |
| `analytics.query.queue.aggregates.service.level` | `queueId`, `mediaType`, daily | nAnsweredIn20/30/60, oServiceLevel, nOverSla |
| `analytics.query.conversation.aggregates.abandon.metrics` | `queueId`, `mediaType`, daily | nAbandoned, tAbandon, nOffered |
| `analytics.query.conversation.aggregates.queue.performance` | `queueId`, `mediaType`, daily | nConnected, tHandle, tTalk, tAcw, nOffered |

**Join key:** `queueId`  
**Computed metrics:** `abandonRate% = nAbandoned/nOffered`, `serviceLevelPct = 1-(nOverSla/nOffered)`, `avgHandleTime = tHandle/nConnected`  
**Executive view:** KPI cards — Service Level %, Abandon Rate %, Total Volume, AHT trend by queue

---

## 9. Agent Performance Scorecard

**Subject:** All agents in a division + reporting window  
**Purpose:** Per-agent handle time, volume, and quality scores across all queues. Used for monthly
scorecards, performance reviews, and PIP tracking.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `users.division.analysis.get.users.with.division.info` | `divisionId` | Agent roster with userId |
| `analytics.query.user.aggregates.performance.metrics` | `userId`, daily | nConnected, tHandle, tTalk, tAcw |
| `analytics.query.conversation.aggregates.agent.performance` | `userId`, daily | Per-agent conversation volume |
| `quality.get.agents.activity` | `userId` | evalCount, avgScore, criticalItemFailCount |
| `coaching.get.appointments` | `userId` | coachingSessionCount in window |

**Join key:** `userId`  
**Executive view:** Sortable agent scorecard table; highlight outliers on AHT and eval score

---

## 10. Wrapup & Transfer Analysis

**Subject:** All queues + reporting window  
**Purpose:** Wrapup code distribution and transfer rates — reveals mis-classification, escalation
patterns, and call routing gaps.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `routing.get.all.wrapup.codes` | — | Global wrapup code label catalogue |
| `routing.get.queue.wrapup.codes.by.queue` | `queueId` | Per-queue valid wrapup codes |
| `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId`, `wrapUpCode` | nConnected by wrapUpCode |
| `analytics.query.conversation.aggregates.transfer.metrics` | `queueId`, daily | nTransferred, nBlindTransferred, nConsultTransferred |

**Join key:** `queueId`, `wrapUpCode`  
**Computed metrics:** `transferRate% = nTransferred/nConnected`, `blindTransferRate% = nBlindTransferred/nTransferred`  
**Executive view:** Wrapup distribution pie + transfer type bar chart; flag queues with blind transfer > 20%

---

## 11. Quality & CSAT Summary

**Subject:** All agents and queues + reporting window  
**Purpose:** QM evaluation coverage, scores, and CSAT/NPS completion rates. Feeds calibration sessions
and quality management dashboards.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `quality.get.published.evaluation.forms` | — | Form definitions — critical items, weight distribution |
| `quality.get.evaluations.query` | `agentUserId`, `queueId` | Individual evaluation records with scores |
| `quality.get.agents.activity` | `userId` | evalCount, avgEvaluationScore, criticalItemFailRate |
| `quality.get.surveys` | `conversationId` | CSAT/NPS survey results |

**Join key:** `agentUserId` or `conversationId`  
**Computed metrics:** `evalCoverageRate% = evaluations/nConnected`, `criticalItemFailRate%`, `avgCsatScore`  
**Executive view:** QM trend line + agent ranking table; highlight critical-item failures

---

## 12. Speech & Text Analytics Sentiment Trends

**Subject:** All queues or selected division + reporting window  
**Purpose:** Org-wide sentiment and topic trends for voice channels. Identifies rising negativity,
compliance-risk conversations, and topic spikes.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `speechandtextanalytics.get.topics` | — | Topic catalogue with definitions |
| `analytics.post.transcripts.aggregates.query` | `queueId`, `userId`, daily | nAnalyzedConversations, avgSentimentScore, silencePct, overtalkPct |

**Join key:** `queueId` or `userId`  
**Executive view:** Sentiment trend chart + topic frequency heat map; flag topics with negative sentiment correlation

---

## 13. Digital Channel Volume & SLA

**Subject:** All queues + reporting window  
**Purpose:** Omni-channel volume breakdown — compare voice, chat, email, and messaging workloads for
capacity planning and SLA compliance across all media types.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `analytics.query.conversation.aggregates.digital.channels` | `mediaType`, `queueId`, daily | nOffered, nConnected, nAbandoned, tHandle by mediaType |
| `analytics.query.conversation.aggregates.queue.performance` | `queueId`, `mediaType`, daily | Queue-level volume and handle time |

**Join key:** `queueId`, `mediaType`  
**Computed metrics:** `mediaTypeMix% = channelVolume/totalVolume`  
**Executive view:** Channel mix stacked bar; SLA comparison table by mediaType

---

## 14. WFM Adherence & Occupancy

**Subject:** WFM management units + reporting window  
**Purpose:** Scheduled vs. actual on-queue time for workforce management reporting, staffing adjustment,
and payroll validation.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `workforce.get.business.units` | — | Business unit names and IDs |
| `workforce.get.management.units` | `businessUnitId` | Management unit roster |
| `workforce.get.management.unit.users` | `managementUnitId` | Agent-to-unit mapping |
| `workforce.get.management.unit.adherence` | `userId` | adherencePct, scheduledActivityCategory, variance |
| `analytics.query.user.aggregates.login.activity` | `userId`, daily | tOnQueueTime, tOffQueueTime, tIdleTime |

**Join key:** `managementUnitId → userId`  
**Computed metrics:** `occupancyPct = tInteracting/tOnQueue`, `scheduleVarianceMinutes`  
**Executive view:** Adherence heat map by management unit + agent variance table

---

## 15. Outbound Campaign Performance

**Subject:** All outbound campaigns + reporting window  
**Purpose:** Campaign reach rates, contact dispositions, and messaging engagement for ROI reporting.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `outbound.get.campaigns` | `campaignId` | Campaign name, status, mode (preview/progressive/predictive) |
| `outbound.get.contact.lists` | `contactListId` | Contact list size and penetration |
| `outbound.get.events` | `campaignId` | Disposition events per contact |
| `outbound.get.messaging.campaigns` | `campaignId` | SMS/digital campaign stats |

**Join key:** `campaignId`  
**Executive view:** Campaign funnel + disposition breakdown pie

---

## 16. Flow & IVR Performance

**Subject:** All Architect flows + reporting window  
**Purpose:** IVR and bot flow execution metrics — outcome success rates, milestone completion,
self-service containment. Informs IVR design and bot deflection ROI.

### Datasets (ordered)

| Dataset | Grouping | Metrics |
|---------|----------|---------|
| `flows.get.all.flows` | — | Flow definitions: name, type (inbound/bot/outbound), published version |
| `flows.get.flow.outcomes` | `flowId` | Outcome label definitions |
| `flows.get.flow.milestones` | `flowId` | Milestone (checkpoint) definitions |
| `analytics.query.flow.aggregates.execution.metrics` | `flowId`, daily | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone |

**Join key:** `flowId`  
**Computed metrics:** `containmentRate% = nFlowOutcome/nFlow`  
**Executive view:** Containment funnel + flow outcome breakdown; compare bot vs. IVR containment rates

---

## 17. Platform Security & API Governance

**Subject:** Organisation-wide  
**Purpose:** OAuth client inventory, active authorisation grants, role assignments, API consumption
metrics, and rate-limit events. Used by IT security teams and compliance officers for access reviews,
integration audits, and over-privileged client identification.

### Datasets (ordered)

| Dataset | Join Key | What It Reveals |
|---------|----------|-----------------|
| `oauth.get.clients` | `clientId` | All OAuth apps: grant type, created date, scope |
| `oauth.get.authorizations` | `userId` | Active auth grants per user — identify unused or stale grants |
| `authorization.get.roles` | `roleId` | Role catalogue — identifies privileged roles |
| `oauth.post.client.usage.query` + `oauth.get.client.usage.query.results` | `clientId` | Per-client API call volumes (async job) |
| `usage.get.api.usage.organization.summary` | — | Org-level API usage totals |
| `usage.get.api.usage.by.client` | `clientId` | Per-client call counts and error rates |
| `usage.get.api.usage.by.user` | `userId` | Per-user API call volumes |
| `analytics.query.rate.limit.aggregates` | `clientId` | Rate-limit hits: nError, nOverLimit |
| `audit-logs` | `entityId` | Auth change events: CREATE/UPDATE/DELETE on roles, divisions, grants |

**Audit log filter:** `service=Authorization`, action in `[CREATE, UPDATE, DELETE]`  
**Computed metrics:** `activeGrantCount`, `apiCallsPerClient`, `rateLimitHitRate% = nOverLimit/nTotal`, `authChangeEventCount`  
**Executive view:** OAuth client table with call volume and active grants; flag clients with rate-limit hits or grants older than 90 days

---

## 18. Organisation Health & Limits

**Subject:** Organisation singleton + last 24 hours  
**Purpose:** Platform health snapshot — organisation configuration, resource limits, firing alerts,
and rate-limit pressure. Key pre-deployment and post-migration validation checklist.

### Datasets (ordered)

| Dataset | What It Reveals |
|---------|-----------------|
| `organization.get.organization.details` | Org name, ID, default language, enabled features |
| `organization.get.organization.limits` | Per-feature resource limits (max queues, users, etc.) |
| `alerting.get.alerts` | Currently firing alerts by severity |
| `alerting.get.rules` | Configured alert thresholds and notification targets |
| `analytics.query.rate.limit.aggregates` | Rate-limit events in the last 24 hours |
| `usage.get.api.usage.organization.summary` | Org-level API call totals vs. typical |

**Diagnostic signals:**
- `alerting.get.alerts` CRITICAL with no acknowledgement → immediate escalation required
- `analytics.query.rate.limit.aggregates nOverLimit > 0` → identify offending client via `oauth.get.clients`
- `organization.get.organization.limits` remaining capacity < 20% → capacity planning action needed

---

## 19. Skills & Routing Workforce Readiness

**Subject:** Organisation or division + routing window  
**Purpose:** Cross-queue skill coverage analysis. Identifies under-skilled queues, skill gaps ahead
of volume peaks, and mismatches between queue skill requirements and available agent proficiency.

### Datasets (ordered)

| Dataset | Join Key | What It Reveals |
|---------|----------|-----------------|
| `routing.get.all.routing.skills` | `skillId` | Complete skill catalogue |
| `routing.get.skill.groups` | `skillGroupId` | Skill group membership counts and division assignments |
| `routing.get.all.languages` | `languageId` | Language routing options |
| `routing-queues` | `queueId` | Queues with skill requirements and scoring method |
| `routing.get.single.queue.config` | `queueId` | Full queue config: skill evaluation mode, required skills |
| `routing-queue-members` | `queueId` | Queue member roster with routing status |
| `routing.get.user.utilization` | `userId` | Per-agent channel capacity limits |
| `workforce.get.management.unit.users` | `managementUnitId` | WFM roster |
| `users.get.user.routing.skills` | `userId` | Per-agent skill proficiency ratings |

**Computed metrics:** `skillCoverageRate% = agentsWithRequiredSkill/totalQueueAgents`, `multilingualCoverage%`, `omniChannelCapacity`  
**Executive view:** Skill coverage heat map (skill × queue) + language routing table + channel capacity chart; flag queues with < 3 qualified agents per required skill

---

## 20. Single Call Forensics

**Voice engineer playbook | Subject:** One `conversationId`  
**Use case:** Deep-dive diagnosis of one call — quality issues, misrouting, recording gaps, unexpected
disconnects. The go-to playbook for a customer escalation or complaint.

### Datasets (ordered)

| Dataset | Diagnostic Value |
|---------|-----------------|
| `analytics.get.single.conversation.analytics` | Segment timing — confirms call flow phases |
| `conversations.get.conversation.object` | DNIS/ANI, participants, `externalTag` (BYOI check) |
| `telephony.get.sip.messages.for.conversation` | SIP signaling trace — call setup, teardown, codec |
| `conversations.get.recordings` | Recording objects with signed download URLs |
| `conversations.get.conversation.recording.metadata` | Recording archival status |
| `conversations.get.speech.text.analytics` | Sentiment overview and analysis status |

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| SIP 486 Busy Here | Trunk at capacity → check `telephony.get.trunk.metrics.summary` |
| SIP 503 Service Unavailable | Edge or trunk provider outage |
| SIP 487 Request Terminated | Caller hung up before answer (confirmed abandon) |
| SIP 4xx on INVITE with wrong DNIS | Routing table misconfiguration |
| `tTalkComplete=0` + `tAbandon>0` | Caller abandoned in queue before agent |
| Recording absent | Edge recording policy or consent flag missing |
| `agentSentimentScore < -0.5` | Severe CX impact; escalate to QM |
| ANI displayed as 'Anonymous' | CLI blocking active on inbound DID |

**Enrich with:** `users` (agent identity from userId in analytics participants), `quality.get.evaluations.query` (evaluation if one exists)

---

## 21. Trunk & Edge Health Check

**Voice engineer playbook | Subject:** Organisation-wide (no fixed window — point-in-time)**Use case:** SIP infrastructure health snapshot — edge appliance status, trunk utilisation, active
call load, station registration. Used for proactive monitoring and incident response.

### Datasets (ordered)

| Dataset | What It Shows |
|---------|---------------|
| `telephony.get.edges` | Edge registration status, firmware, connectivity |
| `telephony.get.trunks` | SIP trunks: inService flag, provider, maxConcurrentCalls |
| `telephony.get.trunk.metrics.summary` | Trunk utilisation: currentCalls vs maxConcurrentCalls |
| `stations.get.stations` | Station registrations — softphone/hardware phone status |
| `conversations.get.active.calls` | Currently active voice calls vs. trunk capacity |

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| Edge `statusCode != 'ACTIVE'` | Failover condition; check firmware and network path |
| Trunk `inService=false` | Provider circuit down or PSTN gateway misconfiguration |
| `trunk.currentCalls / trunk.maxConcurrentCalls > 0.85` | Capacity saturation risk |
| Stations with `registered=false` spike | Network or DNS issue affecting softphone registration |
| Edge `onlineStatus=DISCONNECTED` | Peer connection lost; check management network |

**Enrich with:** `alerting.get.alerts` (active telephony alerts), `alerting.get.rules` (confirm trunk capacity alert thresholds)

---

## 22. Queue Saturation & Staffing Analysis

**Voice engineer playbook | Subject:** One `queueId` (real-time + near-real-time)  
**Use case:** Real-time diagnosis of queue congestion — waiting callers, on-queue agents, EWT, and
abandon trends. Used when a queue is hot and supervisors need to act within minutes.

### Datasets (ordered)

| Dataset | What It Shows |
|---------|---------------|
| `analytics.query.queue.observations.real.time.stats` | oInteracting, oWaiting, oOnQueueUsers, oOffQueueUsers |
| `routing-queue-members` | Members with live routing status and presence |
| `analytics.query.user.observations.real.time.status` | Per-agent presence and routing status |
| `analytics.query.conversation.aggregates.queue.performance` | Historical handle time for context |
| `analytics.query.conversation.aggregates.abandon.metrics` | Abandon volume and timing in last hour |

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| `oWaiting > 0` + `oOnQueueUsers = 0` | No agents staffed; escalate immediately |
| `oOffQueueUsers` high vs `oOnQueueUsers` | Agents logged in but not ready; presence audit needed |
| `nAbandoned spike` in last hour | Callers abandoning; correlate with EWT to confirm cause |
| `oInteracting / oOnQueueUsers > 0.9` | Agents fully occupied; queue will build |
| Presence 'On Queue' + routingStatus `NOT_RESPONDING` | Ghost agents; check station registration |

**Enrich with:** `users` (resolve userId to name for supervisor view), `analytics.query.user.aggregates.login.activity` (confirm agents are on-shift), `workforce.get.management.unit.adherence` (check if off-queue agents are on scheduled break)

---

## 23. Flow & IVR Diagnostics

**Voice engineer playbook | Subject:** All flows or specific `flowId`  
**Use case:** Architect IVR and bot flow execution health — identifying flows with high failure rates,
stuck executions, or unexpected exit paths. Used for post-deployment validation and self-service outage
root-cause.

### Datasets (ordered)

| Dataset | What It Shows |
|---------|---------------|
| `flows.get.all.flows` | Flow definitions: type, published version, description |
| `flows.get.flow.outcomes` | Exit condition labels for failed-outcome analysis |
| `flows.get.flow.milestones` | Key-step completion checkpoints |
| `analytics.query.flow.aggregates.execution.metrics` | nFlow, nFlowOutcome, nFlowOutcomeFailed, nFlowMilestone |
| `analytics.query.flow.observations` | Real-time active flow executions |

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| `nFlowOutcomeFailed` spike | IVR routing error, missing menu option, or backend API timeout |
| `nFlowMilestone` count lower than baseline | Callers abandoning mid-flow |
| `oFlow` high with zero queue activity | Calls stuck in flow loop or dead-end branch |
| Flow outcome 'Default Exit' > 5% | Unmatched input causing fallthrough to default branch |
| Bot flow `nFlowOutcomeFailed / nFlow > 0.10` | NLU model degradation; retest utterances |

---

## 24. Recording Compliance Audit (by Queue)

**Voice engineer playbook | Subject:** `queueId` or `agentUserId` + time window  
**Use case:** Verify recording and QM evaluation coverage. Confirms recordings are captured per policy.
Used for compliance audits and archival verification.

### Datasets (ordered)

| Dataset | What It Shows |
|---------|---------------|
| `analytics-conversation-details-query` | All connected conversations in scope |
| `conversations.get.conversation.recording.metadata` | Recording existence and archival status |
| `conversations.get.recordings` | Recording objects with fileState and duration |
| `quality.get.published.evaluation.forms` | Evaluation form definitions — form coverage per queue |
| `quality.get.evaluations.query` | Individual evaluations with scores and form reference |
| `quality.get.agents.activity` | Per-agent evaluation counts — identify agents with no evaluations |
| `audit-logs` | Recording policy change events (service=Recording) |

**Derived metric:** `recordingCoverageRate% = conversationsWithRecordings / nConnected`  
**Derived metric:** `evaluationCoverageRate% = conversationsWithEvaluations / nConnected`

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| conversationId in analytics but no recording | Recording policy not triggering; check queue recording rules |
| `recording.fileState = 'ERROR'` | Edge storage issue or retention policy conflict |
| `recording.duration << conversation.tTalk` | Recording stopped early; hold gap or disconnection |
| `evalCount = 0` for an agent in full window | QM evaluation rotation gap |
| audit-logs `action=DELETE` on recordings | Recordings removed before retention period — compliance risk |

**Audit log filter:** `service=Recording`, action in `[CREATE, UPDATE, DELETE, BULK_DELETE]`

---

## 25. Routing Architecture Audit

**Voice engineer playbook | Subject:** Organisation or division  
**Use case:** Complete routing configuration audit — skill definitions, skill groups, language routing,
queue member rosters. Used after routing changes, during new queue onboarding, or when investigating
misrouted calls. Provides the definitive picture of 'who can receive what call'.

### Datasets (ordered)

| Dataset | What It Shows |
|---------|---------------|
| `routing.get.all.routing.skills` | Complete skill catalogue |
| `routing.get.skill.groups` | Skill groups with member counts and division assignments |
| `routing.get.all.languages` | Language routing options available |
| `routing-queues` | All queues: name, divisionId, scoringMethod |
| `routing.get.single.queue.config` | Full queue config: ACW settings, DNIS, skill evaluation mode |
| `routing.get.queue.wrapup.codes.by.queue` | Valid wrapup codes per queue |
| `routing-queue-members` | Live member roster with routing status |
| `routing.get.user.utilization` | Per-agent channel capacity limits |
| `users.get.user.routing.skills` | Per-agent skill proficiency ratings |

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| `scoringMethod=SKILLS_ROUTING` + zero agents with required skill | Queue will never connect calls |
| `enableAutoAnswer=false` | Agents must manually accept; may cause tAlerting spikes |
| `acwSettings.timeoutMs=0` | No ACW enforced; agents may skip wrapup |
| `routing-queue-members` empty | Queue configured but has no members; calls queue forever |
| `maxCapacity=0` for a mediaType | Agent blocked from receiving that media type |

**Enrich with:** `analytics.query.conversation.aggregates.queue.performance` (validate nConnected given member count), `analytics.query.conversation.aggregates.abandon.metrics` (high abandons on a queue with few skilled agents)

---

## 26. Presence & Routing Status Audit

**Voice engineer playbook | Subject:** Organisation-wide (point-in-time + historical window)  
**Use case:** Agent presence and routing status audit — maps all defined presence states (custom and
system) against live agent status to identify why agents are off-queue. Answers the supervisor question
'where are my agents?' and identifies ghost agents, stale presence states, and agents in non-productive
states during peak hours.

### Datasets (ordered)

| Dataset | What It Shows |
|---------|---------------|
| `presence.get.system.presence.definitions` | Built-in presence states (Available, Busy, Away, etc.) |
| `presence.get.organization.presence.definitions` | Custom presence states created by the org |
| `users` | Full user list with current presence and routing status |
| `users.get.bulk.user.presences` | Bulk presence snapshot for all agents |
| `users.get.bulk.user.presences.genesys.cloud` | Genesys Cloud-specific presence variant |
| `analytics.query.user.observations.real.time.status` | Real-time oUserPresence, oUserRoutingStatus |
| `users.get.agent.current.routing.status` | Per-agent routing state: IDLE / INTERACTING / NOT_RESPONDING |
| `analytics.query.user.aggregates.login.activity` | tOnQueueTime, tOffQueueTime, tIdleTime over window |

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| System presence 'On Queue' + routingStatus `NOT_RESPONDING` | Ghost agent; station may be disconnected |
| `lastModifiedDate > 4h` ago with presence `AWAY` during shift | Stale presence; connectivity loss |
| `tOffQueue / tLoggedIn > 0.4` across multiple agents | Systematic off-queue pattern; check break schedule vs adherence |
| `oUserRoutingStatus=IDLE` + `oUserPresence=AVAILABLE` for > 30 min | Possible routing configuration not delivering interactions |

**Enrich with:** `workforce.get.management.unit.adherence` (compare actual presence to scheduled activity), `audit-logs` (service=UserManagement to detect presence state changes by admin)

---

## 27. Multi-Channel Active Contact Centre Snapshot

**Voice engineer playbook | Subject:** Organisation-wide (real-time, polling)  
**Use case:** Real-time multi-media snapshot of all active interactions across voice, chat, email, and
callback channels. Pairs live conversation counts with queue observations and agent presence for a
complete right-now picture. Use as a live wall board feed or as a starting point for drilldown
investigations of overloaded queues.

**Polling interval:** 15 seconds

### Datasets (ordered)

| Dataset | What It Shows |
|---------|---------------|
| `conversations.get.active.calls` | Currently active voice calls |
| `conversations.get.active.callbacks` | Active scheduled callbacks |
| `conversations.get.active.chats` | Active digital chat interactions |
| `conversations.get.active.emails` | Active email interactions |
| `conversations.get.active.conversations` | All active interactions (any media type) |
| `analytics.query.queue.observations.real.time.stats` | oInteracting, oWaiting, oOnQueueUsers per queue |
| `analytics.query.conversation.activity.real.time` | oInteracting, oWaiting, oLongestWaiting per queue × mediaType |
| `analytics.query.user.observations.real.time.status` | Per-agent oUserPresence, oUserRoutingStatus |
| `users.get.bulk.user.presences` | Bulk presence lookup for all agents |
| `telephony.get.trunk.metrics.summary` | Trunk utilisation vs. capacity ceiling |

### Diagnostic Signals

| Signal | Interpretation |
|--------|----------------|
| `conversations.get.active.calls` count >> `oInteracting` | Orphaned calls not in a queue; check BYOI or direct-dial flows |
| `conversations.get.active.callbacks` count > `oWaiting` | Callbacks queued but no observation visible; callback queue misconfigured |
| `oWaiting > 0` + `oOnQueueUsers = 0` | Unstaffed queue; immediate supervisor action required |
| `currentCalls / maxConcurrentCalls > 0.85` on trunk | Trunk saturation imminent |
| `oLongestWaiting > SLA target` | SLA breach already occurring for oldest waiting customer |

**Drilldown:** `users.get.agent.active.conversations` (click an agent to see their active interactions), `users.get.agent.current.routing.status` (confirm agent is INTERACTING, not IDLE with ghost call)

---

## 28. Dataset Combination Reference Matrix

`●` = primary use, `○` = optional/conditional, blank = not applicable.

| Dataset Key | Conv Deep Dive | Queue Inv | Division Inv | Agent Inv | Call History | Copilot | BYOI Inv | Exec Rollup | Voice Eng |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `analytics.get.single.conversation.analytics` | ● | | | | | | ● | | ● |
| `analytics.get.multiple.conversations.by.ids` | | | | | ● | | | | |
| `analytics-conversation-details-query` | | ● | | ● | ● | ● | | | ○ |
| `analytics-conversation-timeline-analysis` | | | | | ● | | | | |
| `analytics.query.conversation.aggregates.abandon.metrics` | | ● | | | | | | ● | ● |
| `analytics.query.conversation.aggregates.agent.performance` | | | ● | | | | | ● | |
| `analytics.query.conversation.aggregates.digital.channels` | | | | | | | | ● | |
| `analytics.query.conversation.aggregates.queue.performance` | | ● | ● | | | | | ● | ● |
| `analytics.query.conversation.aggregates.transfer.metrics` | | ● | | | | | | ● | |
| `analytics.query.conversation.aggregates.wrapup.distribution` | | ● | ● | | | | | ● | |
| `analytics.query.conversation.activity.real.time` | | | | | | | | | ● |
| `analytics.query.flow.aggregates.execution.metrics` | | | | | | | | ● | ● |
| `analytics.query.flow.observations` | | | | | | | | | ● |
| `analytics.query.queue.aggregates.service.level` | | ● | | | | | | ● | |
| `analytics.query.queue.observations.real.time.stats` | | | | | | | | | ● |
| `analytics.query.rate.limit.aggregates` | | | | | | | | ● | |
| `analytics.query.user.aggregates.login.activity` | | | ● | ● | | | | ● | ● |
| `analytics.query.user.aggregates.performance.metrics` | | | ● | ● | | | | ● | |
| `analytics.query.user.details.activity.report` | | | ● | ● | | | | | |
| `analytics.query.user.observations.real.time.status` | | | | ○ | | | | | ● |
| `analytics.get.agent.active.status` | | | | ○ | | | | | ○ |
| `analytics.post.transcripts.aggregates.query` | | | | | | | | ● | |
| `alerting.get.alerts` | | | | | | | | ● | ● |
| `alerting.get.rules` | | | | | | | | ● | ● |
| `audit-logs` | | | | ● | | | | ○ | ● |
| `audits.get.audit.query.results` | | | | ○ | | | | ○ | |
| `audits.get.service.mapping` | | | | | | | | ○ | |
| `authorization.get.all.divisions` | | | ● | | | | | | |
| `authorization.get.roles` | | | | | | | | ● | |
| `authorization.list.division.queues` | | ○ | ● | | | | | | |
| `coaching.get.appointments` | | | ● | ● | | | | ● | |
| `conversations.get.active.callbacks` | | | | | | | | | ● |
| `conversations.get.active.calls` | | | | | | | | | ● |
| `conversations.get.active.chats` | | | | | | | | | ● |
| `conversations.get.active.conversations` | | | | | | | | | ● |
| `conversations.get.active.emails` | | | | | | | | | ● |
| `conversations.get.call.history` | | | | | ● | | | | |
| `conversations.get.conversation.customattributes` | ● | | | | ● | | ● | | |
| `conversations.get.conversation.object` | ● | | | | | | ● | | ● |
| `conversations.get.conversation.recording.metadata` | ● | | | | ● | | ● | | ● |
| `conversations.get.conversation.suggestion.detail` | ○ | | | | | ● | | | |
| `conversations.get.conversation.suggestions` | ○ | | | | | ● | | | |
| `conversations.get.recordings` | ● | | | | | | ● | | ● |
| `conversations.get.speech.text.analytics` | ● | | | | | ● | ● | | |
| `conversations.search.customattributes` | ○ | | | | ● | | | | |
| `conversations.search.participant.attributes` | ● | | | | ● | | ● | | |
| `flows.get.all.flows` | | | | | | | | ● | ● |
| `flows.get.flow.milestones` | | | | | | | | ● | ● |
| `flows.get.flow.outcomes` | | | | | | | | ● | ● |
| `journey.get.action.maps` | | | | | ● | | | | |
| `oauth.get.authorizations` | | | | | | | | ● | |
| `oauth.get.client.usage.query.results` | | | | | | | | ● | |
| `oauth.get.clients` | | | | | | | | ● | |
| `oauth.post.client.usage.query` | | | | | | | | ● | |
| `organization.get.organization.details` | | | | | | | | ● | |
| `organization.get.organization.limits` | | | | | | | | ● | |
| `outbound.get.campaigns` | | | | | | | | ● | |
| `outbound.get.contact.lists` | | | | | | | | ● | |
| `outbound.get.events` | | | | | | | | ● | |
| `outbound.get.messaging.campaigns` | | | | | | | | ● | |
| `presence.get.organization.presence.definitions` | | | | | | | | | ● |
| `presence.get.system.presence.definitions` | | | | | | | | | ● |
| `quality.get.agents.activity` | | | ● | ● | | | | ● | ● |
| `quality.get.evaluations.query` | ● | ○ | ● | ● | | ● | ● | ● | ● |
| `quality.get.published.evaluation.forms` | | | | | | ● | | ● | ● |
| `quality.get.surveys` | ● | | | | | | | ● | |
| `routing-queue-members` | | ● | | | | | | | ● |
| `routing-queues` | | ● | | | | | | ● | ● |
| `routing.get.all.languages` | | | | | | | | ● | ● |
| `routing.get.all.routing.skills` | | | | | | | | ● | ● |
| `routing.get.all.wrapup.codes` | | ○ | | | | | | ● | |
| `routing.get.queue.wrapup.codes.by.queue` | | ● | | | | | | | ● |
| `routing.get.single.queue.config` | | ● | | | | | | ● | ● |
| `routing.get.skill.groups` | | | | | | | | ● | ● |
| `routing.get.user.utilization` | | | | ● | | | | ● | ● |
| `speech.and.text.analytics.get.sentiment.for.conversation` | ○ | | | | | ● | | | |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | ○ | | | | | | | | |
| `speechandtextanalytics.get.topics` | | | | | | | | ● | |
| `stations.get.stations` | | | | | | | | | ● |
| `telephony.get.edge.performance.metrics` | ○ | | | | | | | | ● |
| `telephony.get.edges` | | | | | | | | | ● |
| `telephony.get.sip.messages.for.conversation` | ○ | | | | | | ● | | ● |
| `telephony.get.trunk.metrics.summary` | | | | | | | | ○ | ● |
| `telephony.get.trunks` | | | | | | | | | ● |
| `usage.get.api.usage.by.client` | | | | | | | | ● | |
| `usage.get.api.usage.by.user` | | | | | | | | ● | |
| `usage.get.api.usage.organization.summary` | | | | | | | | ● | |
| `users` | | | | | | | | | ● |
| `users.division.analysis.get.users.with.division.info` | | | ● | | | | | ● | |
| `users.get.agent.active.conversations` | | | | ○ | | | | | ● |
| `users.get.agent.current.routing.status` | | | | ○ | | | | | ● |
| `users.get.bulk.user.presences` | | | | | | | | | ● |
| `users.get.bulk.user.presences.genesys.cloud` | | | | | | | | | ● |
| `users.get.user.details.with.full.expansion` | | | | ● | | | | | |
| `users.get.user.queue.memberships` | | | | ● | | | | | |
| `users.get.user.routing.skills` | | | | ● | | | | ● | ● |
| `users.search.users.by.name.or.email` | | | | ○ | | | | | |
| `workforce.get.business.units` | | | | | | | | ● | |
| `workforce.get.management.unit.adherence` | | | | ● | | | | ● | ● |
| `workforce.get.management.unit.users` | | | | ● | | | | ● | |
| `workforce.get.management.units` | | | | | | | | ● | |

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
| `nBlindTransferred` | Conversations blind-transferred | Routing quality indicator |
| `nConsultTransferred` | Consultative transfers | Warm-transfer volume |
| `oServiceLevel` | Current SLA percentage | Real-time SLA |
| `nOverSla` | Conversations that exceeded SLA threshold | SLA misses |
| `oInteracting` | Agents currently on interactions | Active agents |
| `oWaiting` | Interactions waiting in queue | Queue depth |
| `oLongestWaiting` | Seconds the longest-waiting customer has waited | Worst-case wait |
| `tAgentRoutingStatus` | Time in each routing status | On-queue vs off-queue time |
| `tSystemPresence` | Time in each system presence | Available, Busy, Away, Offline |
| `oSentimentScore` | Aggregate sentiment score (S&TA) | Voice-of-customer indicator |
| `nSpeechTextAnalyzedConversations` | Conversations with S&TA analysis | S&TA coverage |
| `adherencePct` | Schedule adherence percentage | WFM compliance |
| `nOverLimit` | Rate-limit breach events | API governance indicator |
| `suggestionAcceptanceRate%` | Accepted suggestions / offered | Copilot effectiveness |
| `containmentRate%` | Flow successful exits / total executions | IVR self-service effectiveness |
| `recordingCoverageRate%` | Conversations with recordings / nConnected | Recording compliance |
| `evaluationCoverageRate%` | Conversations with evaluations / nConnected | QM compliance |

---

*All dataset keys in this document map directly to entries in `catalog/genesys.catalog.json`.*  
*All endpoint paths are Genesys Cloud API v2 (`/api/v2/...`).*  
*Refer to [INVESTIGATIONS.md](INVESTIGATIONS.md) for the investigation composer contract.*
