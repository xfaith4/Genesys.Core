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

If schema or normalization version fields are absent, the importer proceeds and stores the raw
`manifest.json` and `summary.json` as provenance on the `core_runs` row.

## Import Flow

1. Validate the run folder and resolve import metadata.
2. Register or refresh the `core_runs` provenance row for the active case.
3. Create a new `imports` row in `pending` state.
4. Mark prior completed imports for the same `case_id + run_id` as `superseded`.
5. Delete prior conversation rows for the same `case_id + run_id`.
6. Read `data/*.jsonl` line-by-line, map each normalized record into the flat conversation store shape,
   and write batches inside a single transaction.
7. Mark the import `complete` with final counts, or `failed` if the transaction aborts.

## Row Semantics

- Duplicate `conversation_id + case_id` rows are replaced.
- `source_file` and `source_offset` preserve the original JSONL provenance for each imported row.
- `participants_json` and `attributes_json` retain nested detail for later drilldown.
- Malformed JSONL rows are counted as failed rows and do not abort the entire import unless the database
  transaction itself fails.

## Current Limits

- The importer stores conversation-level projections only; participants and segments do not yet have
  dedicated relational tables.
- The main analysis UI still browses run artifacts directly. Querying the case store is the next pivot-UX
  phase.
