# Readiness Review

## Review date

- 2026-02-22

## Scope reviewed

- Dataset entrypoint and routing behavior
- Retry and rate-limit behavior
- Paging strategy behavior and termination safeguards
- Async transaction/job behavior
- Output artifact contract
- Redaction behavior
- End-user onboarding and workflow usability

## Findings

### Ready now

- `Invoke-Dataset` is functional for catalog-backed dataset execution and writes deterministic run artifacts (`manifest.json`, `events.jsonl`, `summary.json`, `data/*.jsonl`).
- Runtime supports paging profiles `none`, `nextUri`, `pageNumber`, `cursor`, `bodyPaging`, and `transactionResults` via profile-driven dispatch.
- Retry behavior handles HTTP 429 using `Retry-After` header and message parsing (`Retry the request in [x] seconds`) with bounded retries and jitter.
- Async submit/poll/results flows are implemented and exercised for audit and analytics job patterns.
- Request and record redaction exists for common sensitive fields/token-like values.
- Current catalog and dispatch breadth is materially broader than initial baseline:
  - 31 dataset keys in catalog
  - 4 curated dataset handlers (`audit-logs`, `analytics-conversation-details`, `users`, `routing-queues`)
  - generic catalog-driven execution for additional dataset keys

### Partially ready / operational caveats

- This repository is a Core runtime, not a packaged MCP server today.
- Direct script invocation (`pwsh -File ./modules/Genesys.Core/Public/Invoke-Dataset.ps1`) supports `-Headers`, `-BaseUri`, and `-DatasetParameters`; module invocation is still recommended for interactive sessions.
- Included GitHub workflows are currently scoped to `audit-logs` and require environment-specific auth wiring before production use.
- Legacy catalog shims still exist for one deprecation cycle, while runtime defaults target `catalog/genesys.catalog.json`.
- Redaction policy is heuristic and not yet fully profile-driven by dataset/endpoint sensitivity class.

## Recommendation

- Use for controlled external client usage where:
  - callers use module invocation with explicit auth headers
  - consumers rely on run artifacts under `out/<datasetKey>/<runId>/`
  - workflow auth is explicitly implemented per environment
- Continue roadmap execution for:
  - onboarding hardening for workflow/script auth ergonomics
  - catalog mirror retirement
  - redaction policy expansion
  - endpoint coverage expansion listed in `docs/ROADMAP.md`

