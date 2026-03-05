# Genesys.Core — AGENTS.md

This file is the standing instruction set for any agent (Codex/LLM/human) contributing to this repo.

## Mission

Build a catalog-driven "Genesys Core" that executes governed datasets via GitHub Actions and produces deterministic, auditable artifacts.
UIs must be clients of the Core—not reimplementations of the Core.

## Non-Negotiables (Read This Twice)

1) **Catalog is source of truth.** Endpoint behavior (itemsPath, paging, async flow, retry profile, redaction policy) is defined in `genesys-core.catalog.json`.
2) **No surprises.** Pagination + retry must be deterministic, tested, and observable.
3) **No secret leakage.** Never log tokens, client secrets, Authorization headers, or raw PII-heavy payloads.
4) **PS 5.1 + 7+ compatibility.** Avoid features that break Windows PowerShell 5.1.
5) **Colon-after-variable gotcha.** In PowerShell strings, use `$($var):` not `$var:` (scope parsing bug).
6) **Drop-in markers.** When providing drop-ins or replacements:
   - `### BEGIN: <Name>`
   - `### END: <Name>`

## Repo Structure (Target)

- `genesys-core.catalog.json`                # Catalog (source of truth)
- `catalog/schema/genesys-core.catalog.schema.json`  # JSON Schema for catalog
- `src/ps-module/Genesys.Core/`             # Module code
  - `Public/`                               # Public entrypoints (Invoke-Dataset etc.)
  - `Private/`                              # Internal engines (retry/paging/async/run)
- `.github/workflows/`                      # Scheduled + on-demand dataset runs
- `tests/`                                  # Pester tests

## Output Contract (Runs)

All runs write under:
`out/<datasetKey>/<runId>/`

Minimum files:

- `manifest.json`   (datasetKey, time window, git sha, start/end, counts, warnings)
- `events.jsonl`    (structured run events: retries, 429 backoffs, paging progress, async poll states)
- `summary.json`    (fast "coffee view")
- `data/*.jsonl` or `data/*.jsonl.gz`  (normalized + redacted dataset records)

Artifacts uploaded by workflows must:

- Only include `out/<datasetKey>/<runId>/...`
- Be uniquely named per runId
- Use retention controls (short by default)

## Core Engine Requirements

### Request + Retry

- Supports 429 backoff using:
  - `Retry-After` header (preferred)
  - message parsing: "Retry the request in [x] seconds"
- Bounded retries with jitter
- Emits structured events per attempt
- POST retry policy must be explicit (default: do NOT retry unless known-safe)

### Pagination Plugins (Strategy Pattern)

Implement paging as separate functions with a common interface:

- `nextUri`
- `pageNumber`
- `cursor` (future)
- `bodyPaging/totalHits`
- `transactionResults` (submit -> poll -> fetch results)

No endpoint-specific paging logic in the dataset runner. The runner selects a profile from the catalog.

### Async Transaction Pattern (Audit Logs)

- POST creates `transactionId`
- Poll status endpoint until terminal
- Fetch results using configured paging strategy
- Emit progress events (state transitions, poll counts, wait times)

## Data Safety / Redaction

- Default outputs should be normalized and redacted.
- Raw payload storage is opt-in and must be:
  - gated by an explicit flag
  - redacted before persistence
  - minimized (only what is required)

## Testing (Pester)

Minimum test gates:

1) Catalog validates against schema.
2) Every endpoint has:
   - method, path, itemsPath
   - paging profile (or explicit `none`)
   - retry profile
3) Retry parsing tests (429 behavior).
4) Paging termination tests (no infinite loops).

## Pull Request Checklist

- [ ] Catalog entry added/updated with schema-valid fields
- [ ] Paging profile exists and is tested/mocked
- [ ] No secrets/PII in logs
- [ ] PS 5.1 + 7+ compatible
- [ ] Run outputs follow contract and artifact upload only includes the run folder
