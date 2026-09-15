# Investigation Composition — Design

> Status: Design proposal, approved 2026-04-28; release shape refined 2026-04-29
> Tracking: [ROADMAP.md § Release 1.0 Track B](ROADMAP.md#track-b--composition-the-value-step)
>
> Release shape: Agent Investigation shipped in 1.0 (proves the composition
> model). Conversation Investigation shipped in 1.1 with redaction hardening.
> Queue Investigation shipped in 1.2 with reporting-contract cleanup.
> Campaign Investigation extends the same contract for outbound operations.
> Their designs are documented here in full so the contract stays explicit.

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
| `investigationKey` | string | Stable key, matches the output directory name (`agent-investigation`, `campaign-investigation`, `conversation-investigation`, `queue-investigation`) |
| `runId` | string | Unique per-run identifier; same value as the directory segment |
| `subjectType` | string | `agent`, `campaign`, `conversation`, or `queue` |
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

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| identity | `users.get.user.details.with.full.expansion` | seed | Name, email, state, manager, expanded user details |
| division | `(derived)` | `userId` | Division details carried by the scoped identity response |
| skills | `users.get.user.routing.skills` | `userId` | Skill assignments + proficiency |
| queues | `users.get.user.queue.memberships` | `userId` | Queue memberships |
| presence | `users.get.bulk.user.presences` (single-user query) | `userId` | Current PureCloud presence for the user |
| routingStatus | `users.get.agent.current.routing.status` (single-user query) | `userId` | Current ACD routing status for the user |
| utilization | `routing.get.user.utilization` (single-user query) | `userId` | Current channel-capacity utilization snapshot |
| activity | `analytics.query.user.details.activity.report` (user/window body filter) | `userId` | Login/logout/on-queue activity in the requested window |
| activeConversations | `users.get.agent.active.conversations` (single-user query) | `userId` | Current live interactions owned by the agent |
| conversations | `analytics-conversation-details-query` (user/window segment filter) | `userId` | Conversations the agent touched |
| auditAccountChanges | `audit-logs` (EntityType=`User`, EntityId=`userId`) | `userId` | Audit changes made to the agent account |

### 4.2 Conversation investigation _(Release 1.1)_

**Cmdlet:** `Get-GenesysConversationInvestigation -ConversationId <x>`
**InvestigationKey:** `conversation-investigation`

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| conversationLookup | `conversations.get.specific.conversation.details` | seed | Get conversation start/end times for the required analytics interval |
| conversation | `analytics-conversation-details-query` | `conversationId` | Full participant timeline using the interval derived from `conversationLookup` |
| participants | (derived from conversation) | seed | Extract participant userIds |
| agents | `users` (per participant) | `userId` | Identity for each agent |
| divisions | `users.division.analysis.get.users.with.division.info` | `userId` | Division/location at time of contact |
| skills | `routing.get.all.routing.skills` (filtered) | `userId` | Skills at time of contact |
| recordings | `conversations.get.recordings` | `conversationId` | Recording metadata if present |
| evaluations | `quality.get.evaluations.query` | `conversationId` | Evaluation outcomes if present |
| surveys | `quality.get.surveys` (filtered by `conversationId`) | `conversationId` | Post-contact CSAT / NPS outcomes if present |

### 4.3 Queue investigation _(Release 1.2)_

**Cmdlet:** `Get-GenesysQueueInvestigation -QueueId <x> -Since <window>`
**InvestigationKey:** `queue-investigation`

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| queue | `routing.get.single.queue.config` (single-queue query) | seed | Queue configuration and metadata |
| members | `routing-queue-members` (parameterised by queueId) | `queueId` | Current membership with routing status |
| wrapupCodes | `routing.get.queue.wrapup.codes.by.queue` (single-queue query) | `queueId` | Queue-specific wrap-up labels |
| observations | `analytics.query.queue.observations.real.time.stats` (queue body filter) | `queueId` | Real-time waiting/interacting/on-queue state |
| sla | `analytics.query.conversation.aggregates.queue.performance` (queue/window body filter) | `queueId` | Offered, answered, and handle-time metrics in the requested window |
| abandons | `analytics.query.conversation.aggregates.abandon.metrics` (queue/window body filter) | `queueId` | Abandon and short-abandon metrics in the requested window |
| transfers | `analytics.query.conversation.aggregates.transfer.metrics` (queue/window body filter) | `queueId` | Blind/consult transfer rates for the queue |
| wrapupDistribution | `analytics.query.conversation.aggregates.wrapup.distribution` (queue/window body filter) | `queueId` | Wrap-up-code distribution and handle time |
| activeAgents | `analytics.query.user.observations.real.time.status` (member-scoped body filter) | `queueId` | Current queue-member activity snapshot |

The `routing-queue-members` catalog dataset added in 1.2 wraps
`routing.get.queue.members.with.status` (membership + presence). The
`queue-investigation-members` redaction profile strips the deep contact
fields carried over by user records embedded under each membership entry.

### 4.4 Campaign investigation

**Cmdlet:** `Get-GenesysCampaignInvestigation -CampaignId <x> -Since <window>`
**InvestigationKey:** `campaign-investigation`

| Step | DatasetKey | JoinOn | Purpose |
| --- | --- | --- | --- |
| campaign | `outbound.get.campaigns` | seed | Campaign status, dialing mode, queue, caller ID, and configured abandon threshold |
| contactList | `outbound.get.contact.lists` | `contactListId` | Contact-list identity and size for reconciliation context |
| queue | `routing.get.single.queue.config` | `queueId` | Connected queue metadata for answer-handling context |
| diagnostics | `outbound.get.campaign.diagnostics.summary` | `campaignId` | Live outbound diagnostics snapshot for pacing / health triage |
| outboundEvents | `outbound.get.events` | `campaignId` | Dialer events and dispositions for the campaign |
| auditChanges | `audit-logs` (EntityId=`campaignId`) | `campaignId` | Recent audit changes affecting the campaign |
| conversationAnalytics | `analytics-conversation-details-query` (campaign/window body filter) | `campaignId` | Conversation analytics rows tied to the campaign in the requested window |
| outboundAbandons | `(derived)` | `campaignId` | Derived abandon-focused evidence extracted from outbound events |

## 5. Sample outputs

Deterministic sample outputs are committed for review and demos:

- `samples/demo-agent-investigation/` — standard run artifacts for the enriched Agent Investigation.
- `samples/demo-campaign-investigation/` — standard run artifacts for the Campaign Investigation.
- `samples/demo-conversation-investigation-run/` — standard run artifacts for the Conversation Investigation.
- `samples/demo-conversation-investigation/` — packaged conversation-investigation deliverable (HTML/XLSX/CSV/PCAP-oriented example).
- `samples/demo-queue-investigation/` — standard run artifacts for the enriched Queue Investigation.

## 6. Dependencies

Track B is gated by Track A. Each flagship investigation cannot be marked done
until the datasets it composes have `Live Invoke-Dataset acceptance passed`
under Track A.

| Investigation | Datasets that must pass `Live Invoke-Dataset acceptance passed` first |
| --- | --- |
| Agent | `users.get.user.details.with.full.expansion`, `users.get.user.routing.skills`, `users.get.user.queue.memberships`, bulk presences with one-user query parameters, user activity report with a user/window body, `analytics-conversation-details-query` with a user/window body, `audit-logs` with EntityType/EntityId filters |
| Conversation | `conversations.get.specific.conversation.details`, `analytics-conversation-details-query`, `users`, division-info, skills, recordings, evaluations |
| Queue | `routing-queues`, queue members, queue observations, queue performance aggregates, abandon aggregates, user observations |

The mirror-catalog cutover should also land before any investigation references
catalog keys, to avoid a double rename when the deprecated stub is removed.

## 7. Redaction

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

## 8. Testing

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

## 9. Relationship to existing composers

Two ad-hoc composers already exist in `Genesys.Ops`:

- `Get-GenesysQueueHealthSnapshot` (queue observations + SLA + queue list)
- `Invoke-GenesysOperationsReport` (multi-section daily ops report)

These predate this design. Disposition resolved in **Release 1.2**:

- `Get-GenesysQueueHealthSnapshot` is retained — it is a _multi-queue_
  snapshot ranking, not a subject-centred investigation. Re-implementing it
  on top of `Invoke-Investigation` would invert its shape (one investigation
  per queue × N queues) for no operator benefit. Source carries a one-line
  cross-reference to `Get-GenesysQueueInvestigation` for the single-queue
  drilldown case.
- `Invoke-GenesysOperationsReport` is retained — multi-subject daily roll-up
  (queues + edges + alerts + WebRTC), not a single-subject investigation.
  Source likewise carries a one-line cross-reference.

No existing cmdlet is renamed or removed by this work.

## 10. Open questions

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
