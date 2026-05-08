# Endpoint Combinations — Investigation Playbooks and Executive Reporting

> Status: Approved catalog additions and combination patterns, 2026-05-08  
> Relates to: [INVESTIGATIONS.md](INVESTIGATIONS.md), [ROADMAP.md](ROADMAP.md)

---

## Overview

This document defines how catalog datasets combine into complete investigations and
executive rollup views. Each combination answers a specific operational question without
overwhelming the consumer with a raw data dump.

Three investigation subjects drive the design:

| Subject | Anchor Dataset | Primary Purpose |
|---------|---------------|-----------------|
| **Single Conversation** | `conversation.analytics.single` | Root-cause a customer interaction |
| **Queue** | `routing.get.queue.details` + `routing-queues` | Assess queue health and capacity |
| **Agent / Division** | `users.get.user.details` + `users` | Investigate agent behavior and performance |

Divisions are cross-queue organizational groups — an agent's division assignment applies
across every queue they serve, making division the correct lens for multi-queue agent
investigations.

---

## Part 1 — Single Conversation Investigation

**When to use:** Escalation root-cause, customer complaint, quality dispute, compliance
review of one specific interaction.

### 1.1 Minimum viable investigation (voice engineer)

```
Step 1 — ANCHOR (run first, required)
  conversation.analytics.single
    → GET /api/v2/analytics/conversations/{conversationId}/details
    → Provides: full participant timeline, segment durations, queue routing path,
                media type, wrapup codes, outcome, hold events, transfer events

Step 2 — RECORDING INDEX
  conversation.recording.metadata
    → GET /api/v2/conversations/{conversationId}/recordingmetadata
    → Provides: recording IDs, channel assignment, duration, media type
    → Use recording IDs to fetch audio or transcripts

Step 3 — RECORDINGS (parallel with Step 2 derivation)
  conversations.get.recordings
    → GET /api/v2/conversations/{conversationId}/recordings
    → Provides: full recording objects, playback metadata
```

**Join keys:** `conversationId` threads all three steps.  
**Output:** Conversation timeline + which recordings exist and how long they are.

### 1.2 Full conversation investigation (complete enrichment)

Run steps in the order listed. Steps marked (optional) are skipped if the
feature (STA, Quality) is not licensed or has no data.

```
Step 1 — ANCHOR
  conversation.analytics.single
    → Fields to extract: participantIds[], communicationIds[], queueId, userId (for each agent participant)

Step 2 — RECORDING LAYER
  conversation.recording.metadata            (parallel with Step 3)
  conversations.get.recordings               (parallel with Step 2)

Step 3 — SPEECH & TEXT ANALYTICS (optional, requires STA license)
  speechandtextanalytics.get.conversation
    → GET /api/v2/speechandtextanalytics/conversations/{conversationId}
    → Provides: overall sentiment (agent/customer), STA program match status
    
  speechandtextanalytics.get.conversation.categories
    → GET /api/v2/speechandtextanalytics/conversations/{conversationId}/categories
    → Join with: speechandtextanalytics.get.categories (category name lookup)
    
  speechandtextanalytics.get.conversation.summaries
    → GET /api/v2/speechandtextanalytics/conversations/{conversationId}/summaries
    → Provides: AI-generated reason for contact, resolution, follow-up actions, entities

Step 4 — QUALITY LAYER (optional, requires WFO license)
  quality.get.evaluations.query
    → GET /api/v2/quality/evaluations/query?conversationId={id}
    → Provides: evaluation scores, form used, evaluator identity, score breakdown

  quality.get.conversation.surveys
    → GET /api/v2/quality/conversations/{conversationId}/surveys
    → Provides: customer CSAT/NPS survey responses for this conversation

Step 5 — AGENT IDENTITY (for each agent participantId extracted in Step 1)
  users.get.user.details
    → GET /api/v2/users/{userId}
    → Provides: agent name, email, division, department

  users.get.user.station
    → GET /api/v2/users/{userId}/station
    → Provides: station type and edge assignment (needed for voice quality investigation)

Step 6 — AUDITS (for compliance and change tracking)
  audit-logs
    → POST /api/v2/audits/query/submit  (filter by conversationId)
    → Provides: who touched this conversation, when, what changed
```

**Join map:**

| Left dataset | Left key | Right dataset | Right key | Purpose |
|---|---|---|---|---|
| `conversation.analytics.single` | `participants[].userId` | `users.get.user.details` | `id` | Agent identity |
| `conversation.analytics.single` | `participants[].userId` | `users.get.user.station` | `associatedUser.id` | Station lookup |
| `speechandtextanalytics.get.conversation.categories` | `categories[].id` | `speechandtextanalytics.get.categories` | `id` | Category names |
| `conversation.analytics.single` | `conversationId` | `quality.get.evaluations.query` | `conversation.id` | Evaluations |

### 1.3 What each layer adds

| Layer | Signal added | Investigation value |
|---|---|---|
| Analytics detail | Timeline, durations, routing path, wrapups | Proves what happened and in what order |
| Recordings | Recording IDs, channels, duration | Locates audio evidence |
| STA sentiment | Agent/customer sentiment scores | Identifies emotionally charged interactions |
| STA categories | Compliance/topic hits | Flags regulatory or product mentions |
| STA summaries | Reason for contact, resolution | Enables bulk review without listening |
| Quality evaluations | QM score, form, evaluator | Establishes evaluated quality at point of contact |
| Quality surveys | CSAT/NPS | Ties internal QM to customer perception |
| Agent station | Station type, edge | Needed for voice quality / RTP investigation |
| Audit logs | Change history | Who accessed/modified the conversation record |

---

## Part 2 — Queue Investigation

**When to use:** Queue health check, SLA review, staffing analysis, volume spike
investigation, capacity planning.

### 2.1 Real-time queue health snapshot

```
Step 1 — QUEUE CONFIGURATION ANCHOR
  routing.get.queue.details
    → GET /api/v2/routing/queues/{queueId}
    → Provides: media types, routing mode, ACW settings, skills required, hours of operation

Step 2 — REAL-TIME OBSERVATION (run in parallel with Step 3)
  analytics.query.queue.observations.real.time.stats
    → POST /api/v2/analytics/queues/observations/query (filter: queueId)
    → Metrics: oInteracting, oWaiting, oOnQueueUsers, oOffQueueUsers
    
Step 3 — AGENT STATUS (run in parallel with Step 2)
  analytics.query.agents.status.bulk
    → POST /api/v2/analytics/agents/status/query (filter: queueId)
    → Provides: per-agent routing status, active sessions, presence
    
  analytics.query.user.observations.real.time.status
    → POST /api/v2/analytics/users/observations/query (filter: queueId)
    → Metrics: oUserPresence, oUserRoutingStatus, oInteracting per agent

Step 4 — QUEUE ROSTER
  routing.get.queue.members
    → GET /api/v2/routing/queues/{queueId}/members
    → Provides: all members with ring order and join date
    → Cross-reference with Step 3 to identify which members are off-queue or inactive
```

**Key question answered:** How many agents are available right now, how many customers
are waiting, and are there configuration issues causing queues to mis-route?

### 2.2 Historical queue performance investigation

```
Step 1 — QUEUE ANCHOR + LOOKUP TABLES
  routing.get.queue.details             (configuration)
  routing.get.queue.wrapupcodes         (wrapup ID → name lookup)
  routing.get.queue.members             (member roster)

Step 2 — AGGREGATE METRICS (all POST requests, all parallel)
  analytics.query.conversation.aggregates.queue.performance
    → Metrics: nConnected, tHandle, tTalk, tAcw, tAnswered, nOffered
    
  analytics.query.queue.aggregates.service.level
    → Metrics: nAnsweredIn20, nAnsweredIn30, nAnsweredIn60, tServiceLevel
    
  analytics.query.conversation.aggregates.abandon.metrics
    → Metrics: nAbandoned, tAbandoned, nOffered, nTransferred
    
  analytics.query.conversation.aggregates.transfer.metrics
    → Metrics: nTransferred, nBlindTransferred, nConsultTransferred

Step 3 — CONVERSATION DETAIL (for drilldown beyond aggregates)
  analytics-conversation-details-query
    → POST /api/v2/analytics/conversations/details/query
    → Filter: queueId, time window
    → Provides: per-conversation detail for every interaction in this queue

Step 4 — WRAPUP DISTRIBUTION
  analytics.query.conversation.aggregates.wrapup.distribution
    → Metrics: nConnected grouped by wrapUpCode
    → Join wrapUpCode IDs with: routing.get.queue.wrapupcodes

Step 5 — VOICEMAIL BACKLOG (optional)
  voicemail.get.queue.messages
    → GET /api/v2/voicemail/queues/{queueId}/messages
    → Identifies unread voicemails left during the investigation window
```

**Join map:**

| Left dataset | Left key | Right dataset | Right key | Purpose |
|---|---|---|---|---|
| `analytics.query.conversation.aggregates.wrapup.distribution` | `group.wrapUpCode` | `routing.get.queue.wrapupcodes` | `id` | Wrapup name resolution |
| `analytics-conversation-details-query` | `participants[].queueId` | `routing.get.queue.details` | `id` | Queue config context |
| `routing.get.queue.members` | `id` | `analytics.query.agents.status.bulk` | `userId` | Live status per member |

### 2.3 Division as a queue group

Divisions group agents across queues. To investigate a division rather than a single queue:

```
Step 1 — DIVISION ANCHOR
  authorization.get.division.details
    → GET /api/v2/authorization/divisions/{divisionId}
    → Provides: name, description, object counts

Step 2 — AGENTS IN DIVISION
  users.division.analysis.get.users.with.division.info
    → Filtered by divisionId
    → Provides: all agents in this division with their profile data
    
Step 3 — QUEUES IN DIVISION (derive from all-queues list)
  routing-queues
    → Filter results by division.id = divisionId
    → Provides: all queues assigned to this division

Step 4 — DIVISION GRANTS (who controls this division)
  authorization.get.division.grants
    → GET /api/v2/authorization/divisions/{divisionId}/grants
    → Provides: roles assigned within this division
    → Join with: authorization.get.roles for role names

Step 5 — AGGREGATE METRICS ACROSS ALL DIVISION QUEUES
  Run Steps 2.2 for each queueId derived in Step 3
  analytics.query.conversation.aggregates.queue.performance  (filter: division)
  analytics.query.user.aggregates.performance.metrics        (filter: division)
```

---

## Part 3 — Agent / Division Investigation

**When to use:** Performance review, attendance investigation, routing anomaly,
coaching preparation, disciplinary support.

### 3.1 Agent identity and configuration

```
Step 1 — IDENTITY ANCHOR
  users.get.user.details
    → GET /api/v2/users/{userId}
    → Provides: name, email, division, department, title, account state

Step 2 — CONFIGURATION (parallel)
  users.get.user.station
    → GET /api/v2/users/{userId}/station
    → Provides: station type, edge (for voice quality investigation)
    
  users.get.user.routing.skills
    → GET /api/v2/users/{userId}/routingskills
    → Provides: skill assignments and proficiency levels
    → Cross-reference with routing-skill-based routing decisions in conversation data
    
  routing.get.queues.for.user
    → GET /api/v2/users/{userId}/queues
    → Provides: all queues this agent serves
    → This is the definition of the agent's scope across all divisions

Step 3 — DIVISION MEMBERSHIP
  users.division.analysis.get.users.with.division.info
    → Filtered to this userId
    → Provides: division assignment, division name, location context
```

### 3.2 Agent activity and performance investigation

```
Step 1 — REAL-TIME STATUS
  analytics.get.agent.status
    → GET /api/v2/analytics/agents/{userId}/status
    → Provides: current routing status, presence, active sessions
    
Step 2 — ACTIVITY HISTORY (time-windowed)
  analytics.query.user.details.activity.report
    → POST /api/v2/analytics/routing/activity/query (filter: userId)
    → Provides: login/logout events, on-queue time, off-queue time, idle time

Step 3 — PERFORMANCE AGGREGATES
  analytics.query.user.aggregates.performance.metrics
    → POST /api/v2/analytics/users/aggregates/query (filter: userId)
    → Metrics: tHandle, tTalk, tAcw, nConnected, nOffered, nNotResponding
    
  analytics.query.users.aggregates
    → POST /api/v2/analytics/users/aggregates/query (same endpoint, different grouping)
    → Group by: userId + queueId to see per-queue performance

Step 4 — CONVERSATIONS (filter by agent participation)
  analytics-conversation-details-query
    → POST /api/v2/analytics/conversations/details/query
    → Filter: participants[].userId = {userId}
    → Provides: every conversation the agent participated in during the window

Step 5 — QUALITY LAYER (optional)
  quality.get.agents.activity
    → GET /api/v2/quality/agents/activity?agentUserId={userId}
    → Provides: evaluation count, average score, trend
    
  quality.get.evaluations.query
    → GET /api/v2/quality/evaluations/query?agentUserId={userId}
    → Provides: individual evaluation records with scores

Step 6 — PRESENCE HISTORY
  users.get.bulk.user.presences
    → Provides: presence history for the time window

Step 7 — WFM ADHERENCE (optional, requires WFM license)
  workforcemanagement.get.adherence
    → GET /api/v2/workforcemanagement/adherence?userId={userId}
    → Provides: real-time adherence status
    
  workforcemanagement.post.adherence.historical.bulk  (submit job)
  workforcemanagement.get.adherence.historical.bulk.job  (fetch results)
    → Provides: adherence percentage, exception types, scheduled vs. actual

Step 8 — VOICEMAIL (optional)
  voicemail.get.user.messages
    → GET /api/v2/voicemail/users/{userId}/messages
    → Identifies unclaimed or unread voicemails during the investigation window
```

**Join map:**

| Left dataset | Left key | Right dataset | Right key | Purpose |
|---|---|---|---|---|
| `analytics-conversation-details-query` | `participants[].userId` | `users.get.user.details` | `id` | Agent name in results |
| `analytics.query.users.aggregates` | `group.userId` | `routing.get.queues.for.user` | `id` | Queue name per aggregate row |
| `quality.get.evaluations.query` | `conversation.id` | `analytics-conversation-details-query` | `conversationId` | Quality ↔ interaction cross-reference |

### 3.3 Voice engineer investigation (audio path focus)

A voice engineer investigating a call quality complaint needs the following sequence:

```
Step 1 — CONVERSATION ANALYTICS ANCHOR
  conversation.analytics.single
    → Segment durations, hold events, transfer events, media type confirmation

Step 2 — RECORDING INDEX
  conversation.recording.metadata
    → Recording IDs per channel, duration, media type

Step 3 — AGENT STATION
  users.get.user.station  (for each agent participant)
    → Station type (hardware SIP / WebRTC softphone / Genesys Cloud Voice)
    → Edge ID → link to telephony.get.edges for edge status

Step 4 — EDGE AND TRUNK STATE (at time of call)
  telephony.get.edges
    → Edge registration status, software version, region

  telephony.get.trunks
    → SIP trunk configuration and current status
    
  telephony.get.trunk.metrics.summary
    → Capacity utilisation, active calls, error rate

Step 5 — AUDIT TRAIL (call configuration changes)
  audit-logs
    → Filter: entity = conversation OR station OR edge, time = call window ± 1h
    → Identifies configuration changes that might have affected the call
```

This combination lets a voice engineer answer:
- Was the call established on hardware SIP or WebRTC?
- Which edge processed the call?
- Was the trunk at capacity during the call?
- Were any edge or trunk changes made around the time of the complaint?

---

## Part 4 — Executive Rollup Reporting

Executive dashboards need pre-aggregated rollup metrics that avoid per-record data.
All combinations below use aggregate endpoints only — no conversation detail datasets.

### 4.1 Daily / weekly operations summary

**Frequency:** Daily scheduled run  
**Audience:** Contact center director, VP of Operations

```
Queue performance tier:
  analytics.query.conversation.aggregates.queue.performance
    → Metrics: nOffered, nConnected, tHandle, tTalk, tAcw, tAnswered
    → Group by: queueId, interval (DAY)
    
  analytics.query.queue.aggregates.service.level
    → Metrics: nAnsweredIn20, nAnsweredIn30, nAnsweredIn60, tServiceLevel
    → Group by: queueId, interval (DAY)
    
  analytics.query.conversation.aggregates.abandon.metrics
    → Metrics: nAbandoned, nOffered, tAbandoned
    → Group by: queueId, interval (DAY)

Agent performance tier:
  analytics.query.user.aggregates.performance.metrics
    → Metrics: tHandle, tTalk, tAcw, nConnected, nOffered
    → Group by: userId, interval (DAY)
    
  analytics.query.user.aggregates.login.activity
    → Metrics: tOnQueueTime, tOffQueueTime, tIdleTime
    → Group by: userId, interval (DAY)

Lookup tables (run once per session):
  routing-queues       → queue name per queueId
  users                → agent name per userId
  routing.get.all.wrapup.codes  → wrapup name per code
```

**Derived metrics (compute at reporting layer):**
- SLA % = nAnsweredIn30 / nOffered × 100
- Abandon Rate % = nAbandoned / nOffered × 100
- Avg Handle Time = tHandle / nConnected (in seconds → minutes)
- Occupancy % = (tTalk + tAcw) / tOnQueueTime × 100

### 4.2 Quality and customer satisfaction rollup

**Frequency:** Weekly  
**Audience:** QM Manager, VP of Customer Experience

```
  analytics.query.evaluations.aggregates
    → Metrics: nEvaluations, oQualityCompliance, vScore
    → Group by: queueId OR userId, interval (WEEK)
    
  analytics.query.surveys.aggregates
    → Metrics: nSurveysSent, nSurveysCompleted, vPromoterScore
    → Group by: queueId OR userId, interval (WEEK)
    
  quality.get.agents.activity
    → Per-agent evaluation summary (count, avg score, trend)
    → Supplement with user lookup for agent names
    
  quality.get.evaluations.query
    → Filter: low-scoring evaluations (vScore < threshold)
    → Drill-down list for coaching prioritization
```

**Derived metrics:**
- QM Compliance % = oQualityCompliance × 100
- Survey Completion Rate % = nSurveysCompleted / nSurveysSent × 100
- NPS Score = vPromoterScore (range -100 to +100)

### 4.3 Digital channel breakdown

**Frequency:** Daily  
**Audience:** Omnichannel manager, digital CX lead

```
  analytics.query.conversation.aggregates.digital.channels
    → Metrics: nOffered, nConnected, nAbandoned
    → Group by: mediaType (VOICE, CHAT, EMAIL, CALLBACK, SOCIAL), interval (DAY)
    
  analytics.query.conversation.aggregates.transfer.metrics
    → Metrics: nTransferred, nBlindTransferred, nConsultTransferred
    → Group by: mediaType, interval (DAY)
    
  analytics.post.transcripts.aggregates.query
    → Transcript volume metrics by language and media type
    
  analytics.query.flow.aggregates.execution.metrics
    → Flow execution: nFlow, nFlowOutcome, nFlowOutcomeFailed
    → Group by: flowId, interval (DAY)
    → Join with: flows.get.all.flows for flow names
```

### 4.4 Trunk and telephony capacity summary

**Frequency:** Daily or on-demand during incidents  
**Audience:** Voice engineer, IT Operations, NOC

```
  telephony.get.trunk.metrics.summary
    → Aggregate SIP trunk capacity: active calls, registered trunks, error count
    
  telephony.get.trunks
    → All SIP trunk configurations and current state
    
  telephony.get.edges
    → Edge appliance registration status, software version

  stations.get.stations
    → Station registration counts and type breakdown (hardware vs. WebRTC)
    
  alerting.get.alerts
    → Currently firing threshold alerts (correlate with trunk/edge issues)
    
  analytics.query.conversation.aggregates.queue.performance
    → Concurrent call volume (nConnected at interval level) to correlate with trunk capacity
```

### 4.5 WFM adherence executive summary

**Frequency:** Weekly  
**Audience:** WFM Manager, HR, Operations Director

```
  workforcemanagement.post.adherence.historical.bulk  (submit job for rolling week)
  workforcemanagement.get.adherence.historical.bulk.job  (fetch results)
    → Per-agent: scheduled minutes, adherence %, exception count, exception types
    
  workforce.get.management.units
    → Management unit names per unit ID
    
  analytics.query.user.aggregates.login.activity
    → tOnQueueTime, tOffQueueTime (actual vs. scheduled cross-check)
    
  users
    → Agent names and division for result labeling
```

**Derived metrics:**
- Adherence % = (scheduled minutes in adherence / total scheduled minutes) × 100
- Schedule Exception Rate % = exception minutes / scheduled minutes × 100

---

## Part 5 — Lookup Tables (Run Once Per Investigation Session)

The following datasets are not investigation-specific — they resolve IDs to names and
should be fetched once and reused across all steps:

| Dataset | Resolves | Used by |
|---------|---------|---------|
| `routing-queues` | `queueId → queue name, division` | All investigations |
| `users` | `userId → agent name, email, division` | Agent, conversation, queue |
| `routing.get.all.wrapup.codes` | `wrapUpCode → name` | Queue, executive |
| `routing.get.all.routing.skills` | `skillId → skill name` | Agent investigation |
| `authorization.get.all.divisions` | `divisionId → division name` | All investigations |
| `flows.get.all.flows` | `flowId → flow name` | Flow, digital channel |
| `flows.get.flow.outcomes` | `outcomeId → outcome name` | Flow investigation |
| `flows.get.flow.milestones` | `milestoneId → milestone name` | Flow investigation |
| `speechandtextanalytics.get.categories` | `categoryId → category name` | Conversation STA |
| `speechandtextanalytics.get.topics` | `topicId → topic name` | Conversation STA |
| `presence.get.system.presence.definitions` | `presenceId → presence name` | Agent, queue |
| `authorization.get.roles` | `roleId → role name` | Division investigation |

---

## Part 6 — Endpoint Combination Reference

### 6.1 Anchor → enrichment dependencies

```
conversation.analytics.single  ──┬──► conversation.recording.metadata
  (provides conversationId,       ├──► conversations.get.recordings
   participantIds,                ├──► speechandtextanalytics.get.conversation
   communicationIds,              ├──► speechandtextanalytics.get.conversation.categories
   queueId, userId)               ├──► speechandtextanalytics.get.conversation.summaries
                                  ├──► quality.get.conversation.surveys
                                  ├──► quality.get.evaluations.query (filter)
                                  └──► audit-logs (filter)

routing.get.queue.details  ──────┬──► routing.get.queue.members
  (provides queueId)             ├──► routing.get.queue.wrapupcodes
                                 ├──► voicemail.get.queue.messages
                                 ├──► analytics.query.queue.observations.real.time.stats
                                 ├──► analytics.query.conversation.aggregates.queue.performance
                                 ├──► analytics.query.queue.aggregates.service.level
                                 ├──► analytics.query.conversation.aggregates.abandon.metrics
                                 └──► analytics-conversation-details-query (filter by queue)

users.get.user.details  ─────────┬──► users.get.user.station
  (provides userId)              ├──► users.get.user.routing.skills
                                 ├──► routing.get.queues.for.user
                                 ├──► analytics.get.agent.status
                                 ├──► analytics.query.user.details.activity.report
                                 ├──► analytics.query.users.aggregates (filter by userId)
                                 ├──► quality.get.agents.activity (filter by userId)
                                 ├──► voicemail.get.user.messages
                                 ├──► workforcemanagement.get.adherence
                                 └──► analytics-conversation-details-query (filter by userId)
```

### 6.2 Datasets that cannot be called without a prior anchor result

| Dataset | Requires from anchor |
|---------|---------------------|
| `conversation.recording.metadata` | `conversationId` from conversation anchor |
| `conversations.get.recordings` | `conversationId` |
| `speechandtextanalytics.get.conversation` | `conversationId` |
| `speechandtextanalytics.get.conversation.categories` | `conversationId` |
| `speechandtextanalytics.get.conversation.summaries` | `conversationId` |
| `speechandtextanalytics.get.conversation.communication.transcripturl` | `conversationId`, `communicationId` |
| `quality.get.conversation.surveys` | `conversationId` |
| `routing.get.queue.details` | `queueId` |
| `routing.get.queue.members` | `queueId` |
| `routing.get.queue.wrapupcodes` | `queueId` |
| `voicemail.get.queue.messages` | `queueId` |
| `users.get.user.details` | `userId` |
| `users.get.user.station` | `userId` |
| `users.get.user.routing.skills` | `userId` |
| `routing.get.queues.for.user` | `userId` |
| `analytics.get.agent.status` | `userId` |
| `voicemail.get.user.messages` | `userId` |
| `workforcemanagement.get.adherence` | `userId[]` |
| `authorization.get.division.details` | `divisionId` |
| `authorization.get.division.grants` | `divisionId` |

### 6.3 Async dataset pairs (submit + poll)

| Submit | Poll/Results | Pattern |
|--------|-------------|---------|
| `audit-logs` (POST submit) | `audits.get.audit.query.results` | auditTransaction |
| `analytics-conversation-details` (POST job) | `analytics.get.conversation.details.job.status` → `analytics.get.conversation.details.job.results` | analytics_jobs |
| `workforcemanagement.post.adherence.historical.bulk` | `workforcemanagement.get.adherence.historical.bulk.job` | poll then fetch |
| `oauth.post.client.usage.query` | `oauth.get.client.usage.query.results` | usage_query |

---

## Part 7 — Genesys BYOI and Embeddable Framework Integration

When integrating with Genesys Embedded Client (EC) or BYOI conversation injection:

### 7.1 Active conversation monitoring
```
conversations.get.active.conversations    → currently active (all media)
conversations.get.active.calls           → voice only
conversations.get.active.callbacks       → scheduled callbacks
conversations.get.active.chats           → digital chat
conversations.get.active.emails          → email queue
```

These surface active state. After a conversation ends, it transitions to analytics:
```
conversation.analytics.single            → post-call analytics detail
conversations.get.recordings             → post-call recording
```

### 7.2 Injected conversation enrichment
When a BYOI or third-party conversation is injected, the `conversationId` returned by
the injection endpoint becomes the anchor key for all enrichment datasets. The full
conversation investigation sequence in Part 1 applies without modification.

---

## Appendix — New Datasets Added (Release 1.0.x)

This release added 29 datasets to the catalog (catalog version 1.0.0, updated 2026-05-08):

| Dataset Key | Endpoint | Group | Role |
|---|---|---|---|
| `conversation.analytics.single` | `analytics.get.single.conversation.analytics` | conversation | anchor |
| `conversation.recording.metadata` | `getConversationRecordingmetadata` | conversation | enrichment |
| `speechandtextanalytics.get.conversation` | `getSpeechandtextanalyticsConversation` | conversation | enrichment |
| `speechandtextanalytics.get.conversation.categories` | `getSpeechandtextanalyticsConversationCategories` | conversation | enrichment |
| `speechandtextanalytics.get.conversation.summaries` | `getSpeechandtextanalyticsConversationSummaries` | conversation | enrichment |
| `speechandtextanalytics.get.categories` | `getSpeechandtextanalyticsCategories` | conversation | lookup |
| `quality.get.conversation.surveys` | `getQualityConversationSurveys` | conversation | enrichment |
| `routing.get.queue.details` | `getRoutingQueue` | queue | anchor |
| `routing.get.queue.members` | `getRoutingQueueMembers` | queue | enrichment |
| `routing.get.queue.wrapupcodes` | `getRoutingQueueWrapupcodes` | queue | lookup |
| `routing.get.queues.for.user` | `getUserQueues` | agent | enrichment |
| `users.get.user.details` | `getUser` | agent | anchor |
| `users.get.user.station` | `getUserStation` | agent | enrichment |
| `users.get.user.routing.skills` | `getUserRoutingskills` | agent | enrichment |
| `analytics.get.agent.status` | `getAnalyticsAgentStatus` | agent | enrichment |
| `analytics.query.agents.status.bulk` | `postAnalyticsAgentsStatusQuery` | agent | enrichment |
| `analytics.query.users.aggregates` | `postAnalyticsUsersAggregatesQuery` | agent | aggregates |
| `analytics.query.users.observations` | `postAnalyticsUsersObservationsQuery` | agent | enrichment |
| `authorization.get.division.details` | `getAuthorizationDivision` | division | anchor |
| `authorization.get.division.grants` | `getAuthorizationDivisionGrants` | division | enrichment |
| `quality.get.agents.activity` | `getQualityAgentsActivity` | quality | enrichment |
| `quality.get.calibrations` | `getQualityCalibrations` | quality | enrichment |
| `analytics.query.evaluations.aggregates` | `postAnalyticsEvaluationsAggregatesQuery` | quality | aggregates |
| `analytics.query.surveys.aggregates` | `postAnalyticsSurveysAggregatesQuery` | quality | aggregates |
| `voicemail.get.user.messages` | `getVoicemailUserMessages` | agent | enrichment |
| `voicemail.get.queue.messages` | `getVoicemailQueueMessages` | queue | enrichment |
| `workforcemanagement.get.adherence` | `getWorkforcemanagementAdherence` | agent | enrichment |
| `workforcemanagement.post.adherence.historical.bulk` | `postWorkforcemanagementAdherenceHistoricalBulk` | agent | async-submit |
| `workforcemanagement.get.adherence.historical.bulk.job` | `getWorkforcemanagementAdherenceHistoricalBulkJob` | agent | async-results |
