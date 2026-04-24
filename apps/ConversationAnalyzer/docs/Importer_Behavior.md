# Importer Behavior

## Supported Input

The importer accepts a single `Genesys.Core` run folder with this contract:

- `manifest.json`
- `summary.json`
- `data/*.jsonl`

`events.jsonl` remains part of the run artifact set for diagnostics, but it is not imported into SQLite by
the current pipeline.

Supported dataset keys:

- `analytics-conversation-details-query`
- `analytics-conversation-details`

## Compatibility Checks

The importer rejects a run when:

- required artifacts are missing
- the dataset key is missing or unsupported
- an explicit schema or normalization version declares a major version other than `1`
- `manifest.json` and `summary.json` disagree on dataset key or run id
- `manifest.counts.itemCount` and `summary.totals.totalConversations` / `summary.totals.totalRecords`
  disagree when both are present
- the Core expected count does not match the number of non-empty records in `data/*.jsonl`
- any JSONL record is malformed
- any data record is missing `conversationId`

If schema or normalization version fields are absent, the importer proceeds and stores the raw
`manifest.json` and `summary.json` as provenance on the `core_runs` row.

Use `Test-CoreRunArtifactContract -RunFolder <path>` to validate a run folder without opening SQLite.
`Import-RunFolderToCase` calls the same validator with `-ThrowOnError` before any database writes.

## Import Flow

1. Validate the run folder and resolve import metadata.
2. Validate the Core run artifact contract and reconcile manifest/summary/data counts.
3. Register or refresh the `core_runs` provenance row for the active case.
4. Create a new `imports` row in `pending` state.
5. Mark prior completed imports for the same `case_id + run_id` as `superseded`.
6. Delete prior conversation rows for the same `case_id + run_id`.
7. Read `data/*.jsonl` line-by-line, map each normalized record into the flat conversation store shape,
   and write batches inside a single transaction.
8. Reconcile inserted row count against the validated Core data-record count.
9. Mark the import `complete` with final counts, or `failed` if contract validation, parsing,
   reconciliation, or the database transaction fails.

## Row Semantics

- Duplicate `conversation_id + case_id` rows are replaced.
- `source_file` and `source_offset` preserve the original JSONL provenance for each imported row.
- `raw_json` stores the canonical Core conversation payload for DB drilldown and export fidelity.
- `payload_hash` stores a SHA-256 hash of the canonical payload.
- `conversation_versions` preserves every imported version with `import_id`, `run_id`, source file,
  source offset, import timestamp, payload hash, and raw JSON.
- `participants_json` and `attributes_json` are retained as side-car projections for compatibility.
- Malformed JSONL rows or missing `conversationId` values fail the import before database mutation.

## Current Limits

- The importer stores flattened conversation projections plus bridge tables for agents, queues,
  divisions, flows, and wrapups. Participants and segments do not yet have full normalized row tables.
- Runtime database smoke tests require the native SQLite dependency for the host platform.
