# DEMO DATA — Genesys.MockServer Fixture Catalog

This document describes all demo fixture files used by the `Genesys.MockServer` and the
`New-DemoRequestInvoker` in-process stub.  Every fixture matches the **exact Genesys Cloud API
response schema** documented at [developer.genesys.com](https://developer.genesys.com).

---

## Quick Reference

| Dataset Key | Fixture File(s) | Paging Profile | Records |
|---|---|---|---|
| `users` | `users.page1.json`, `users.page2.json` | `nextUri` | 10 total (4 + 6) |
| `routing-queues` | `routing-queues.page1.json`, `routing-queues.page2.json` | `nextUri_default` | 5 total (3 + 2) |
| `audit-logs` (service mapping) | `audit-logs.servicemapping.json` | single page | 6 service names |
| `audit-logs` (submit) | `audit-logs.submit.json` | async job | `{ "id": "demo-audit-tx-001" }` |
| `audit-logs` (results p1) | `audit-logs.results.page1.json` | `nextUri` | 10 events |
| `audit-logs` (results p2) | `audit-logs.results.page2.json` | `nextUri` final | 10 events |
| `analytics-conversation-details` (submit) | `analytics-conversation-details.submit.json` | async job | `{ "jobId": "demo-conv-job-001" }` |
| `analytics-conversation-details` (results p1) | `analytics-conversation-details.results.page1.json` | cursor | 3 conversations |
| `analytics-conversation-details` (results p2) | `analytics-conversation-details.results.page2.json` | cursor final | 2 conversations |
| `analytics-conversation-details-query` | `analytics-conversation-details-query.page1.json` | `analytics_details_query` | 2 conversations |
| `conversations.get.active.conversations` | `conversations.active.json` | single page | 2 conversations |
| `speechandtextanalytics.get.topics` | `speechandtextanalytics.topics.json` | single page | 3 topics |
| `conversations.get.recordings` | `conversations.recordings.json` | single page | 2 recordings |
| `authorization.get.roles` | `authorization.roles.json` | single page | 4 roles |
| `oauth.get.clients` | `oauth.clients.json` | single page | 3 OAuth clients |

---

## Demo Identity Coherence

All fixtures share a common set of synthetic IDs so data is cross-referenceable.

### Users

| ID | Name | Email | Role |
|---|---|---|---|
| `user-demo-001` | Alex Rivera | alex.rivera@demo.example.com | Supervisor |
| `user-demo-002` | Jordan Lee | jordan.lee@demo.example.com | Agent |
| `user-demo-003` | Morgan Kim | morgan.kim@demo.example.com | Agent |
| `user-demo-004` | Casey Patel | casey.patel@demo.example.com | Agent |
| `user-demo-005` | Sam Chen | sam.chen@demo.example.com | Admin |
| `user-demo-006` | Taylor Brooks | taylor.brooks@demo.example.com | Agent |
| `user-demo-007` | Jamie Wolf | jamie.wolf@demo.example.com | Agent |
| `user-demo-008` | Drew Santos | drew.santos@demo.example.com | Agent |
| `user-demo-009` | Avery Stone | avery.stone@demo.example.com | WFM Analyst |
| `user-demo-010` | Robin Park | robin.park@demo.example.com | Supervisor |

### Queues

| ID | Name | Media Type |
|---|---|---|
| `queue-demo-001` | Support — Tier 1 | voice, chat |
| `queue-demo-002` | Support — Tier 2 | voice |
| `queue-demo-003` | Sales — Inbound | voice, callback |
| `queue-demo-004` | Billing | voice, email |
| `queue-demo-005` | Technical Support | voice, chat, email |

### Conversations

| ID | Type | Participants |
|---|---|---|
| `conv-demo-001` | voice | `user-demo-002`, `user-demo-003` |
| `conv-demo-002` | chat | `user-demo-004` |
| `conv-demo-003` | voice | `user-demo-002` |
| `conv-demo-004` | email | `user-demo-007` |
| `conv-demo-005` | voice | `user-demo-004`, `user-demo-006` |

---

## Schema Fidelity Rules

1. **Field names** match `developer.genesys.com` exactly (camelCase, no underscores)
2. **Required fields** always populated
3. **Optional fields** present in ≥ 50% of synthetic records
4. **Date fields** use ISO 8601 UTC (`2026-02-15T10:00:00.000Z`)
5. **IDs** are synthetic GUIDs matching the cross-reference table above
6. **Handle times** are realistic (30–600 seconds)
7. **`selfUri`** fields use `/api/v2/...` paths matching the actual endpoint

---

## Async Job ID Format

| Pattern | Format |
|---|---|
| Audit logs | `demo-audit-tx-{uuid}` — response field: `id` |
| Analytics jobs | `demo-conv-job-{uuid}` — response field: `jobId` |

> **Important:** The audit log submit endpoint returns `{ "id": "..." }` (NOT `transactionId`).
> The `New-DemoRequestInvoker` and `RouteDispatcher` both use the field name `id` to match the
> real Genesys Cloud API schema used by `Invoke-Dataset`'s `transactionIdPath: "$.id"`.

---

## Adding New Fixtures

To add a fixture for a new dataset:

1. Add a JSON file to `tests/fixtures/demo/` named `{dataset-key}.json` (single page)
   or `{dataset-key}.page1.json` / `{dataset-key}.page2.json` (paged)
2. The schema must match the real Genesys Cloud API response for that endpoint
3. For async job datasets, add `{dataset-key}.submit.json` and `{dataset-key}.results.page*.json`
4. Update `New-DemoRequestInvoker.ps1` to route the new endpoint key to the fixture files
5. `Genesys.MockServer` picks up new fixtures automatically if the endpoint is in `genesys.catalog.json`

---

## Tier Coverage Status

| Tier | Datasets | Status |
|---|---|---|
| **Tier 1** | users, routing-queues, audit-logs, analytics-conversation-details, analytics-conversation-details-query | ✅ Fully populated |
| **Tier 2** | conversations active, speech topics, recordings, authorization roles, OAuth clients | ✅ Populated |
| **Tier 3** | Remaining 101 datasets | ⚠️ Skeleton responses (empty entities, valid schema shape) |

Tier 3 skeleton responses are generated dynamically by `RouteDispatcher.cs` for any dataset endpoint
that does not have a corresponding fixture file. They return a valid response shape but with no data.
