# Investigation Composition — Design

> Status: Design proposal, approved 2026-04-28; release shape refined 2026-04-29
> Tracking: [ROADMAP.md § Release 1.0 Track B](ROADMAP.md#track-b--composition-the-value-step)
>
> Release shape: Agent Investigation ships in 1.0 to prove the composition
> model. Conversation Investigation ships in 1.1 with redaction hardening.
> Queue Investigation ships in 1.2 with reporting-contract cleanup. Their
> designs are documented here in full so the contract is settled before
> implementation begins.

## 1. Purpose

Existing per-dataset queries answer narrow questions ("list all queues",
"list conversations in window", "list users with division"). Operators
investigating an incident — agent performance review, escalation root-cause,
queue health drilldown — currently have to run several queries by hand and
join them in their head or in a spreadsheet.

An **investigation** is a named, subject-centred composition of existing
datasets that:

- Takes a subject (agent ID, conversation ID, queue ID) and a time window
- Runs N catalog datasets to gather identity, attributes, and activity
- Joins their outputs on declared keys
- Emits the standard run-artifact set: `out/<investigationKey>/<runId>/{manifest,events,summary,data}`

Investigations are **datasets that join other datasets**. They are not a new
output format, not a new module, and not a new abstraction beyond a single
join helper.

## 2. Non-goals

- A query DSL. The shape of each investigation is fixed in code, not
  expressed in JSON or in user input.
- A new module. Investigations live in `Genesys.Ops` and call existing
  `Invoke-GenesysDataset` plumbing in `Genesys.Core`.
- A new artifact format. Investigations write the same files
  `Invoke-Dataset` writes today.
- Cross-tenant or multi-org joins. One investigation, one auth context.
- Backwards-compatibility shims. There is no prior investigation contract
  to preserve.

## 3. Contract

### 3.1 Composer signature

A single private helper in `Genesys.Ops`:

```powershell
Invoke-Investigation `
    -InvestigationKey <string> `
    -Subject <hashtable> `
    -Window <hashtable> `
    -Steps <Step[]>
```

- `InvestigationKey` — used as the output directory name under `out/`.
- `Subject` — the join keys, e.g. `@{ UserId = '...' }`.
- `Window` — `@{ Since = (Get-Date).AddDays(-7); Until = Get-Date }` or
  equivalent. Defaults applied per investigation.
- `Steps` — ordered array of step descriptors (below).

### 3.2 Step descriptor

Each step describes one dataset call and how its output joins to the
investigation's accumulated record set.

```powershell
@{
    Name        = 'identity'                  # section name in summary.json
    DatasetKey  = 'users'                     # existing catalog dataset key
    Parameters  = @{ id = $Subject.UserId }   # passed to Invoke-Dataset
    JoinOn      = $null                       # $null for the seed step
    EmitAs      = 'agent'                     # key under summary.json sections
    Required    = $true                       # if false, step failure logs but does not abort
}
```

Subsequent steps may declare `JoinOn = @{ Left = 'userId'; Right = 'agent.id' }`
to align rows by a shared key. Joins are inner by default; left-joins are
opt-in via `JoinKind = 'Left'` to keep the helper small.

### 3.3 Output

Investigations emit the same run-artifact contract as datasets:

```text
out/agent-investigation/<runId>/
├── manifest.json     # subject, window, steps, durations, dataset versions
├── events.jsonl      # per-step start/finish/error events (redacted)
├── summary.json      # joined record set, grouped by step EmitAs
└── data/
    ├── identity.jsonl
    ├── skills.jsonl
    ├── queues.jsonl
    └── conversations.jsonl
```

`summary.json` is the joined view; `data/*.jsonl` preserves each step's
raw output for re-analysis without re-running.

### 3.4 Manifest contract

Every investigation's `manifest.json` records a fixed shape so downstream
tooling (CI, audit, reporting, the Conversation Analysis SPA) can consume
any investigation uniformly without dispatching on `investigationKey`. The
schema lives at `catalog/schema/investigation.manifest.schema.json` and is
validated at the end of each run; an invalid manifest fails the run.

Required fields:

| Field | Type | Description |
| --- | --- | --- |
| `investigationKey` | string | Stable key, matches the output directory name (`agent-investigation`, `conversation-investigation`, `queue-investigation`) |
| `runId` | string | Unique per-run identifier; same value as the directory segment |
| `subjectType` | string | `agent`, `conversation`, or `queue` |
| `subjectId` | string | Resolved GUID. Name-based inputs are resolved by the Ops cmdlet wrapper before reaching the composer |
| `window.since` | ISO-8601 string \| null | `null` for point-in-time investigations (e.g. Conversation) |
| `window.until` | ISO-8601 string \| null | Same |
| `datasetsInvoked` | array | One entry per step. See sub-shape below |
| `joinPlan` | array | One entry per join. See sub-shape below |
| `redactionProfile` | object | `{ datasets: { <datasetKey>: <profileName> }, composerOverrides: [...] }` |
| `outputArtifacts` | object | `{ manifestPath, eventsPath, summaryPath, dataPaths: { <stepName>: <path> } }`, all relative to repo root |
| `startedAt` / `finishedAt` | ISO-8601 strings | Composer-level timing |
| `composerVersion` | string | Semver tag of `Genesys.Ops` at run time |

`datasetsInvoked[]` shape:

```json
{
  "stepName": "identity",
  "datasetKey": "users",
  "runId": "<dataset run id>",
  "validationStatus": "live-validated | fixture-validated | offline-runtime-tested | live-probed | unvalidated",
  "recordCount": 1,
  "required": true,
  "status": "ok | failed | skipped",
  "errorMessage": null
}
```

`joinPlan[]` shape:

```json
{
  "stepName": "division",
  "leftSource": "identity",
  "leftKey": "agent.id",
  "rightKey": "userId",
  "joinKind": "Inner | Left"
}
```

The seed step has `joinPlan` entries with `leftSource: null`. `recordCount`
in `datasetsInvoked` reflects rows the dataset returned; the joined row
count for the investigation as a whole is recorded under `summary.json`,
not the manifest.

## 4. Flagship investigations

### 4.1 Agent investigation _(Release 1.0 — first flagship)_

**Cmdlet:** `Get-GenesysAgentInvestigation -UserId <x> -Since <window>`
**InvestigationKey:** `agent-investigation`

**Core steps (shipped in 1.0):**

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| identity | `users` | seed | Name, email, state, manager |
| division | `users.division.analysis.get.users.with.division.info` | `userId` | Division + location |
| skills | `routing.get.all.routing.skills` (filtered) | `userId` | Skill assignments + proficiency |
| queues | `routing-queues` (filtered to memberships) | `userId` | Queue memberships |
| presence | `users.get.bulk.user.presences` | `userId` | Presence in window |
| activity | `analytics.query.user.details.activity.report` | `userId` | Login/logout/on-queue |
| conversations | `analytics-conversation-details-query` (filtered by participant) | `userId` | Conversations the agent touched |

**Enrichment steps (optional, added in 1.3):**

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| profile | `users.get.user.details.with.full.expansion` | `userId` | Full profile: department, manager chain, primary station |
| queueMemberships | `users.get.user.s.queue.memberships` | `userId` | Per-agent queue join state and alert settings |
| routingStatus | `users.get.user.routing.status` | `userId` | Point-in-time routing status at investigation time |
| utilization | `routing.get.user.utilization` | `userId` | Max concurrent channel capacity configuration |
| performanceMetrics | `analytics.query.user.aggregates.performance.metrics` | `userId` | Handle time, ACW, connected count in window |
| loginActivity | `analytics.query.user.aggregates.login.activity` | `userId` | On-queue vs. off-queue vs. idle time totals |
| qualityActivity | `quality.get.agents.activity` | `userId` | Evaluation scores, highest/average/lowest |
| coaching | `coaching.get.appointments` (filtered) | `userId` | Scheduled and completed coaching sessions |
| wfmUnit | `workforce.get.agent.management.unit` | `userId` | WFM management unit assignment |
| adherence | `workforce.get.adherence.bulk` (filtered) | `userId` | Schedule adherence: scheduled vs. actual state |

> Division is a grouping that spans queues. Agents in the same division share authorization scope and object access regardless of queue membership. The `division` + `queueMemberships` combination reveals the full cross-queue footprint of an agent within their authorization boundary.

### 4.2 Conversation investigation _(Release 1.1)_

**Cmdlet:** `Get-GenesysConversationInvestigation -ConversationId <x>`
**InvestigationKey:** `conversation-investigation`

**Core steps (shipped in 1.1):**

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| conversation | `analytics-conversation-details` | seed | Full participant timeline, segments, and metrics |
| participants | (derived from conversation) | seed | Extract participant userIds |
| agents | `users` (per participant) | `userId` | Identity for each agent participant |
| divisions | `users.division.analysis.get.users.with.division.info` | `userId` | Division/location at time of contact |
| skills | `routing.get.all.routing.skills` (filtered) | `userId` | Skills at time of contact |
| recordings | `conversations.get.recordings` | `conversationId` | Recording list with media references |
| evaluations | `quality.get.evaluations.query` | `conversationId` | Evaluation outcomes and scores |

**Enrichment steps (optional, added in 1.3):**

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| conversationState | `conversations.get.specific.conversation.details` | `conversationId` | Conversation API state: direction, media type, connected/disconnected times |
| recordingMetadata | `conversations.get.conversation.recording.metadata` | `conversationId` | Recording inventory without downloading media |
| aiSummary | `conversations.get.conversation.summaries` | `conversationId` | Genesys AI: reason for call, resolution, follow-up |
| speechCategories | `speechandtextanalytics.get.conversation.categories` | `conversationId` | Detected topic categories (billing, complaint, escalation…) |
| nlpSummary | `speechandtextanalytics.get.conversation.summaries.detail` | `conversationId` | NLP-derived resolution and sentiment from transcript |
| transcriptUrls | `speechandtextanalytics.get.conversation.transcript.urls` | `communicationId` | Pre-signed S3 transcript URLs per leg |
| survey | `quality.get.conversation.surveys` | `conversationId` | Post-call CSAT/NPS survey response |
| sipTrace | `telephony.get.sip.message.for.conversation` | `conversationId` | SIP signaling trace for voice engineer diagnosis |

> `sipTrace` is the key enrichment for **voice engineers**. The INVITE→180→200→BYE sequence with timestamps immediately isolates whether a call failure was SIP setup, media negotiation, or carrier. Pair with `recordingMetadata` to confirm whether audio was captured before troubleshooting further.

### 4.3 Queue investigation _(Release 1.2)_

**Cmdlet:** `Get-GenesysQueueInvestigation -QueueId <x> -Since <window>`
**InvestigationKey:** `queue-investigation`

**Core steps (shipped in 1.2):**

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| queue | `routing.get.queue.details` | seed | Queue config: name, division, flow assignment, ACW settings |
| members | `routing.get.queue.members` | `queueId` | Current agent roster with join state |
| observations | `analytics.query.queue.observations.real.time.stats` | `queueId` | Real-time oWaiting, oInteracting, oOnQueueUsers |
| sla | `analytics.query.queue.aggregates.service.level` | `queueId` | SLA compliance: nAnsweredIn20/30/60, tServiceLevel |
| abandons | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon counts and tAbandoned |
| activeAgents | `analytics.query.user.observations.real.time.status` | `queueId` | Agents currently on-queue with routing status |

**Enrichment steps (optional, added in 1.3):**

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| wrapupCodes | `routing.get.queue.wrapup.codes` | `queueId` | Valid dispositions assigned to this queue |
| estimatedWaitTime | `routing.get.queue.estimated.wait.time` | `queueId` | Real-time EWT in seconds — leading indicator of pressure |
| transfers | `analytics.query.conversation.aggregates.transfer.metrics` | `queueId` | Blind and consult transfer rates |
| wrapupDistribution | `analytics.query.conversation.aggregates.wrapup.distribution` | `queueId` | Disposition breakdown by wrapup code |
| agentPerformance | `analytics.query.conversation.aggregates.agent.performance` | `queueId` | Per-agent handle/talk/ACW within this queue |
| conversations | `analytics-conversation-details-query` (filtered by queue) | `queueId` | All conversations routed through this queue in window |

### 4.4 Division investigation _(Release 1.3 candidate)_

**Cmdlet:** `Get-GenesysDivisionInvestigation -DivisionId <x> -Since <window>`
**InvestigationKey:** `division-investigation`

A division is an authorization boundary that spans queues, flows, and users.
Multiple queues can share a division; multiple agents can belong to the same
division while being on different queues. This investigation answers:
"What is the full footprint and performance of this division?"

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| division | `authorization.get.division.details` | seed | Division name, description, home-org flag |
| objects | `authorization.search.division.objects` | `divisionId` | All resources scoped to this division (queues, flows, trunks) |
| grants | `authorization.get.division.grants` | `divisionId` | Roles granted within the division — for access review |
| agents | `users` (filtered by division) | `divisionId` | All agents in the division with identity |
| queues | `routing-queues` (filtered by division) | `divisionId` | All queues in the division with config |
| queuePerformance | `analytics.query.conversation.aggregates.queue.performance` | `queueId` | Aggregated SLA, volume, and AHT per queue in division |
| abandons | `analytics.query.conversation.aggregates.abandon.metrics` | `queueId` | Abandon metrics per queue in division |
| agentPerformance | `analytics.query.user.aggregates.performance.metrics` | `userId` | Performance metrics for all agents in division |
| qualityScores | `quality.get.evaluations.query` (filtered by division agents) | `userId` | Quality evaluation outcomes for agents in division |

## 5. Dependencies

Track B is gated by Track A. Each flagship investigation cannot be marked done
until the datasets it composes have `Live Invoke-Dataset acceptance passed`
under Track A.

| Investigation | Datasets that must pass `Live Invoke-Dataset acceptance passed` first |
| --- | --- |
| Agent | `users`, division-info, skills, `routing-queues`, bulk presences, user activity report, `analytics-conversation-details-query` |
| Conversation | `analytics-conversation-details`, `users`, division-info, skills, recordings, evaluations |
| Queue | `routing.get.queue.details`, `routing.get.queue.members`, queue observations, queue aggregates (service level, abandons), user observations |
| Division | `authorization.get.division.details`, `authorization.search.division.objects`, `authorization.get.division.grants`, `users`, `routing-queues`, conversation aggregates, user aggregates, evaluations |

**Enrichment dataset dependencies (1.3):**

Enrichment steps are optional (`Required = $false`) and their failure logs but
does not abort the parent investigation. Each enrichment dataset still requires
live validation before the enrichment step can be marked production-ready.

| Enrichment Group | Datasets |
| --- | --- |
| Conversation voice/AI | `conversations.get.specific.conversation.details`, `conversations.get.conversation.recording.metadata`, `conversations.get.conversation.summaries`, `speechandtextanalytics.get.conversation.categories`, `speechandtextanalytics.get.conversation.summaries.detail`, `speechandtextanalytics.get.conversation.transcript.urls`, `telephony.get.sip.message.for.conversation`, `quality.get.conversation.surveys` |
| Agent WFM/quality | `users.get.user.details.with.full.expansion`, `users.get.user.s.queue.memberships`, `users.get.user.routing.status`, `routing.get.user.utilization`, `analytics.query.user.aggregates.performance.metrics`, `analytics.query.user.aggregates.login.activity`, `quality.get.agents.activity`, `coaching.get.appointments`, `workforce.get.agent.management.unit`, `workforce.get.adherence.bulk` |
| Queue disposition/transfer | `routing.get.queue.wrapup.codes`, `routing.get.queue.estimated.wait.time`, `analytics.query.conversation.aggregates.transfer.metrics`, `analytics.query.conversation.aggregates.wrapup.distribution`, `analytics.query.conversation.aggregates.agent.performance` |

The mirror-catalog cutover should also land before any investigation references
catalog keys, to avoid a double rename when the deprecated stub is removed.

## 6. Redaction

Investigations are the point at which redaction policy stops being a per-dataset
concern and becomes a composed-record concern. A user record is low risk on its
own; joined to a conversation transcript or recording URL it is materially more
sensitive.

Implications for the Track A redaction milestone:

- The redaction profile for each dataset must be expressible at the dataset
  level (already in scope) **and** apply when that dataset is consumed as a
  step inside an investigation. The composer must not bypass dataset-level
  redaction.
- Free-text fields surfaced through the Conversation investigation
  (transcripts, evaluation comments, wrap-up notes) need explicit allow/deny
  rules before the investigation can be declared production-ready.
- `events.jsonl` for an investigation must redact subject identifiers in the
  same way per-dataset events do today.

If the redaction milestone slips, the Conversation investigation slips with it.
The Agent and Queue investigations have lower exposure and can ship on the
existing redaction baseline.

## 7. Testing

Investigations get the same testing treatment as datasets:

- **Unit:** `Invoke-Investigation` join helper has table-driven tests for
  inner join, left join, missing-key handling, empty-step handling, and
  required-vs-optional step failure semantics.
- **Integration:** each flagship investigation has a fixture-driven test that
  feeds a known subject ID, runs the composer against recorded dataset
  responses, and asserts the shape and contents of `summary.json`. Mirrors the
  existing dataset integration test pattern under
  `tests/integration/`.
- **Live validation:** each flagship is exercised against live Genesys Cloud
  with a known agent/conversation/queue once during release validation, and
  the run artifact is attached to the readiness review. The datasets it
  composes require `Live Invoke-Dataset acceptance passed`; the investigation
  workflow itself requires `Production workflow validated`.

## 8. Relationship to existing composers

Two ad-hoc composers already exist in `Genesys.Ops`:

- `Get-GenesysQueueHealthSnapshot` (queue observations + SLA + queue list)
- `Invoke-GenesysOperationsReport` (multi-section daily ops report)

These predate this design. Disposition is deferred to **Release 1.2** alongside
the Queue Investigation, because that is when the join logic overlap becomes
concrete:

- `Get-GenesysQueueHealthSnapshot` overlaps the Queue investigation. In 1.2,
  either re-implement on top of `Invoke-Investigation` or leave in place with
  a one-line note in source pointing to `Get-GenesysQueueInvestigation`.
- `Invoke-GenesysOperationsReport` is a multi-subject report rather than a
  single-subject investigation. It stays as-is through 1.2 unless its join
  logic accumulates further.

Releases 1.0 and 1.1 leave both functions untouched. No other existing cmdlet
is renamed or removed by this work.

## 9. Open questions

- **Parameter expansion vs. dataset filtering.** Some catalog datasets
  ("filtered by participant", "filtered to memberships") need a parameter
  surface they do not currently expose. Each one is a small Track A item;
  list them under live validation as they are discovered, do not pre-empt
  here.
- **Time-of-contact attributes.** The Conversation investigation describes
  joining a participant's division/skills "at time of contact". Today's
  endpoints return current state, not historical. For 1.0, document this as
  current-state and revisit historical attribution in 1.1 only if a concrete
  use case names it.
- **Subject-by-name lookups.** Operators often know an agent by name, not by
  GUID. Resolution belongs in the Ops cmdlet wrapper (e.g.
  `Get-GenesysAgentInvestigation -UserName 'Jane Doe'`), not in the composer.
  The composer always takes resolved IDs.
