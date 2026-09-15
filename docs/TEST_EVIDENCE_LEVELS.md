# Test Evidence Levels

This document defines the evidence labels used when reporting Genesys.Core test
and validation results. The goal is to avoid ambiguous claims such as
"endpoint passed" when the test only proved catalog shape, mocked pagination, or
fixture artifact generation.

Use the most specific evidence label that matches what was actually exercised.
Do not collapse lower-level checks into live API readiness.

## Reporting Rule

Every test report, readiness table, release note, or checklist that says a
dataset or endpoint passed must name the evidence level.

Good:

- `users: Dataset pagination test passed with mocked nextUri responses.`
- `routing-queues: Live catalog probe returned expected $.entities shape.`
- `audit-logs: Fixture run artifact contract passed.`

Avoid:

- `users endpoint passed`
- `all endpoints tested`
- `live validated`

## Evidence Matrix

| Evidence label | Scope | API traffic | Proves | Does not prove |
|---|---|---:|---|---|
| `Catalog shape passed` | `catalog/genesys.catalog.json`, schema, required fields, profile references | No | Catalog entries are structurally valid and internally referential. | Endpoint exists in Genesys Cloud, permissions are sufficient, response shape is current. |
| `Catalog resolution passed` | Runtime catalog loader and dataset/endpoint resolution | No | `Resolve-Catalog`, dataset lookup, endpoint lookup, and profile inheritance behave as expected. | Live endpoint behavior or `Invoke-Dataset` response processing. |
| `Dataset route construction passed` | `Invoke-Dataset` request construction using mocked `RequestInvoker` | No | Method, URL, route values, query values, body defaults, and parameter overrides are built as expected. | Live API accepts the request or returns the expected shape. |
| `Dataset pagination test passed` | Paging functions and dataset runner using mocked responses | No | Configured paging strategy handles fixture pages, next links, page numbers, cursors, body paging, max-page guards, and termination conditions covered by the test. | Live API paging behavior for every org/data state. |
| `Dataset response processing passed` | `itemsPath`, normalizer, redaction, and JSONL writing using mocked responses | No | The dataset runner can extract records from fixture responses and write expected sanitized records. | Live response contains the same fields or enough records. |
| `Run artifact contract passed` | Run folder contract using mocked or fixture data | No | `manifest.json`, `events.jsonl`, `summary.json`, and `data/*.jsonl` are created and shaped correctly. | Live API connectivity or permissions. |
| `Fixture integration passed` | Multi-component workflow using local fixture/mocked data | No | Components interoperate across module boundaries with deterministic local inputs. | Live API acceptance, live data shape, org-specific permissions. |
| `Smoke run passed` | Small offline run through selected entrypoints with stubbed API responses | No | Basic module load, catalog validation, and selected dataset artifact flows still work. | Full test suite coverage or live readiness. |
| `Live auth passed` | OAuth token acquisition or bearer-token acceptance | Yes, auth endpoint only | Credentials can obtain or use a token for the target region. | Any platform API endpoint works. |
| `Live catalog probe completed` | Bounded direct live probe of catalog endpoint metadata | Yes, platform API | The live endpoint is reachable or classified, and the high-level response shape matches the expected `itemsPath` when successful. | `Invoke-Dataset` execution, full paging, normalizers, artifact output, or complete records. |
| `Live Invoke-Dataset acceptance passed` | `Invoke-Dataset` against live API with bounded parameters and sanitized artifacts | Yes, platform API | The real dataset entrypoint can call the live API, process the response, and produce valid run artifacts. | Exhaustive data completeness, every parameter combination, or downstream app interpretation. |
| `Production workflow validated` | End-to-end operator workflow in the target environment | Yes, platform API | The intended user workflow works with real auth, real parameters, real output handling, and expected operational constraints. | General correctness outside the validated workflow and environment. |

## Dataset Promotion Path

A dataset may only move through these validation states in order:

| validationStatus | Minimum evidence required | Meaning |
|---|---|---|
| `unvalidated` | Catalog entry exists | Dataset is defined but has not been accepted against live Genesys Cloud through `Invoke-Dataset`. |
| `offline-runtime-tested` | `Dataset route construction passed`, `Dataset pagination test passed`, `Dataset response processing passed`, and `Run artifact contract passed` where applicable | The local runtime path works against mocked or fixture responses. |
| `fixture-validated` | `Fixture integration passed` | A composed or multi-component path works against known fixture data. This is not live validation. |
| `live-probed` | `Live auth passed` and `Live catalog probe completed` | A bounded live probe reached or classified the endpoint, but live `Invoke-Dataset` processing has not been proven. |
| `live-validated` | `Live Invoke-Dataset acceptance passed` | The real `Invoke-Dataset` path called the live API, processed the response, and produced sanitized run artifacts. |
| `workflow-validated` | `Production workflow validated` | A named operator workflow completed successfully in the target environment. |

Do not promote a catalog entry to `live-validated` based on mocked tests,
fixture tests, smoke runs, or live catalog probes alone.

## Required Evidence for Release Gates

When a release gate claims a dataset is validated, the gate must identify:

- dataset key
- command run
- UTC timestamp
- environment or region when live
- evidence label
- status
- skipped checks, if any
- whether live data was touched
- sanitized artifact location, when artifacts were produced

For Release 1.0 Agent Investigation, each composed dataset requires
`Live Invoke-Dataset acceptance passed`. The Agent Investigation workflow itself
requires `Production workflow validated`.

## Live Invoke-Dataset Acceptance Command

Use `Live Invoke-Dataset acceptance passed` only when the real `Invoke-Dataset`
path is run against a live Genesys Cloud org and produces sanitized artifacts.

Required report fields:

- dataset key
- command run
- UTC timestamp
- region
- evidence level: `Live Invoke-Dataset acceptance passed`
- status: `passed | failed | skipped`
- artifact root path
- manifest present: yes/no
- events present: yes/no
- summary present: yes/no
- data JSONL present: yes/no
- sanitized record count
- reason, if failed or skipped

Do not include raw records, org-specific identifiers, request URLs with values,
supplied parameter values, response bodies, or raw exception text.

## Approved Claim Templates

Use these patterns in release notes, readiness tables, and checklist updates.

- `<datasetKey>: Catalog shape passed via <command>. No live API traffic was used.`
- `<datasetKey>: Dataset pagination test passed with mocked <pagingProfile> responses. No live API traffic was used.`
- `<datasetKey>: Live catalog probe completed. Probe status: <Working|Empty|Unsupported|Needs Parameters|Shape Mismatch>. This does not prove Invoke-Dataset acceptance.`
- `<datasetKey>: Live Invoke-Dataset acceptance passed. Sanitized artifacts were produced under <artifactRoot>.`
- `<workflowName>: Production workflow validated in <environment>. Covered datasets: <dataset list>.`

## Live Catalog Probe Status Vocabulary

These statuses apply only to `Live catalog probe completed` evidence. They are
not valid catalog `validationStatus` values and are not release-gate states.

Use these status values for live catalog probe reports:

| Status | Meaning |
|---|---|
| `Working` | The live probe received a successful response and the configured `itemsPath` contained one or more items. |
| `Empty` | The live probe received a successful response and the configured `itemsPath` existed, but contained no items. |
| `Unsupported` | The endpoint, method, permission set, or async/transaction behavior is not supported by the current probe. |
| `Needs Parameters` | The dataset requires route values, query values, body values, or filters that the bounded probe did not have. |
| `Shape Mismatch` | The response did not match the catalog `itemsPath`, returned an unexpected non-success response, or the probe could not classify it more specifically. |

These statuses describe the live probe only. They are not substitutes for
`Live Invoke-Dataset acceptance passed`.

## Current Repo Mapping

| Area | Evidence labels it can support |
|---|---|
| `tests/unit/CatalogSchema.Tests.ps1` | `Catalog shape passed` |
| `tests/unit/CatalogResolution.Tests.ps1` | `Catalog resolution passed` |
| `tests/unit/Paging.Tests.ps1` | `Dataset pagination test passed` |
| `tests/unit/Retry.Tests.ps1` | Retry behavior passed for mocked HTTP outcomes |
| `tests/unit/AuditLogs.Dataset.Tests.ps1` | `Dataset route construction passed`, `Dataset pagination test passed`, `Dataset response processing passed`, `Run artifact contract passed` for mocked audit-log flows |
| `tests/unit/AnalyticsConversationDetails.Dataset.Tests.ps1` | `Dataset route construction passed`, `Dataset response processing passed`, `Run artifact contract passed` for mocked analytics flows |
| `tests/unit/AdditionalDatasets.Tests.ps1` | `Dataset route construction passed`, `Dataset pagination test passed`, `Dataset response processing passed`, `Run artifact contract passed` for mocked users, routing-queues, and generic catalog datasets |
| `tests/unit/RunContract.Tests.ps1` | `Run artifact contract passed` |
| `tests/unit/Security.Redaction.Tests.ps1` | Security/redaction behavior passed for mocked records and request logs |
| `tests/integration/AgentInvestigation.Tests.ps1` | `Fixture integration passed` |
| `scripts/Invoke-Smoke.ps1` | `Smoke run passed` |
| `tests/integration/Invoke-LiveCatalogDatasetPass.ps1` | `Live auth passed` and `Live catalog probe completed` |

## Interpreting "All Tests Pass"

`All tests pass` only means all selected checks completed successfully. It must
be paired with the command that ran and the evidence levels covered.

Examples:

- `pwsh -NoProfile -File ./scripts/Invoke-Tests.ps1`
  means the default unit suite passed. It does not mean live Genesys Cloud
  endpoints were exercised.
- `pwsh -NoProfile -File ./scripts/Invoke-Smoke.ps1`
  means a small offline smoke run passed with stubbed API responses.
- `GENESYS_LIVE_CATALOG_PASS=1 Invoke-Pester -Path ./tests/integration/LiveCatalogDatasets.Tests.ps1`
  means the live catalog probe ran and produced sanitized status classifications.
  It does not mean `Invoke-Dataset` processed live responses.

When reporting a release or readiness gate, include:

- command run
- date/time
- environment, if live
- evidence labels covered
- skipped checks
- whether live data was touched

## Live Data Handling

Live validation must not write or share raw Genesys Cloud data outside the
operator's local environment unless explicitly approved for that specific run.

Shareable reports should include only:

- dataset key
- endpoint key
- method
- evidence level
- status
- HTTP status code when useful
- high-level item signal such as `present`, `empty`, or `n/a`
- sanitized reason text

Shareable reports must omit:

- OAuth tokens
- request URLs with live parameter values
- supplied parameter values
- response bodies
- JSONL records
- raw exception text
- organization-specific names, IDs, emails, phone numbers, queue names, user names, or conversation IDs

## Promotion Guidance

Do not update catalog or roadmap language from `unvalidated` to
`live-validated` based on mocked tests or the live catalog probe alone.

A dataset should only be described as `live-validated` after a
`Live Invoke-Dataset acceptance passed` run, or after an explicitly documented
production workflow validation that includes the dataset through `Invoke-Dataset`.
