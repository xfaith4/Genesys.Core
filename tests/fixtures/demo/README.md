# Demo Fixtures

Static JSON fixture files that match the exact Genesys Cloud API response schema for
each dataset. Used by `New-DemoRequestInvoker` (in-process mocking) and by the
`Genesys.MockServer` HTTP demo server.

## Fixture Files

### Tier 1 — Core Datasets

| File | Dataset | Description |
|------|---------|-------------|
| `users.page1.json` | `users` | Users page 1 — 4 agents |
| `users.page2.json` | `users` | Users page 2 — 6 more users |
| `routing-queues.page1.json` | `routing-queues` | Queues page 1 — 3 queues |
| `routing-queues.page2.json` | `routing-queues` | Queues page 2 — 2 queues |
| `audit-logs.servicemapping.json` | `audit-logs` | Service name list for audit scope selection |
| `audit-logs.submit.json` | `audit-logs` | Async job submit response (`{ "id": "..." }`) |
| `audit-logs.results.page1.json` | `audit-logs` | Audit results page 1 — 10 events |
| `audit-logs.results.page2.json` | `audit-logs` | Audit results page 2 — 10 events, `nextUri: null` |
| `analytics-conversation-details.submit.json` | `analytics-conversation-details` | Async job submit (`{ "jobId": "..." }`) |
| `analytics-conversation-details.results.page1.json` | `analytics-conversation-details` | Conversation page 1 — 3 conversations, `cursor` set |
| `analytics-conversation-details.results.page2.json` | `analytics-conversation-details` | Conversation page 2 — 2 conversations, `cursor: null` |
| `analytics-conversation-details-query.page1.json` | `analytics-conversation-details-query` | Direct POST query page 1 (body paging) |

### Tier 2 — Expanded Datasets

| File | Dataset | Description |
|------|---------|-------------|
| `conversations.active.json` | `conversations.get.active.conversations` | 2 active conversations (voice + chat) |
| `speechandtextanalytics.topics.json` | `speechandtextanalytics.get.topics` | 3 speech topics with phrases |
| `conversations.recordings.json` | `conversations.get.recordings` | 2 recording metadata records |
| `authorization.roles.json` | `authorization.get.roles` | 4 authorization roles |
| `oauth.clients.json` | `oauth.get.clients` | 3 OAuth client registrations |

## Cross-Dataset Coherence

Fixture data is intentionally cross-referenced so that IDs line up across datasets:

- **User IDs** in `users.page*.json` match `participants[].userId` in conversation details
- **Queue IDs** in `routing-queues.page*.json` match `sessions[].queueId` in conversation details
- **Queue names** in routing queues match audit log context `entityName` fields
- **User emails** in users match audit log `userEmail` fields

This makes demo runs tell a coherent story: you can trace Alice Support (agent) across
conversations, queues, and audit events.

## Schema Fidelity Rules

- Field names match developer.genesys.com documentation exactly (camelCase)
- Required fields are always populated
- Date fields use ISO 8601 UTC format (`2026-02-14T09:00:00.000Z`)
- IDs are deterministic strings (not random GUIDs) for reproducible test assertions
- Numeric metrics use plausible values (handle times 30–600 s, etc.)

## Adding New Fixtures

1. Name the file using the pattern `{dataset-key}.{page|variant}.json`
2. Match the exact API response schema from developer.genesys.com
3. Reference existing IDs where cross-dataset links apply
4. Update `New-DemoRequestInvoker.ps1` to route to the new fixture
