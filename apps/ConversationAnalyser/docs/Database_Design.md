# Database Design

## Purpose

The local SQLite database is the application's durable case store.

It exists to support multi-day investigation workflows over Core-produced artifacts without re-querying
Genesys Cloud for every pivot. The database is a case-oriented analytical cache, not a source-of-truth
warehouse and not a replacement for `Genesys.Core`.

## Why SQLite

- Embedded and zero-admin for engineer desktops
- Good fit for a single-user local case file
- Strong enough indexing and transaction support for repeated pivot workflows
- Easy to purge or recreate on demand

## Scope

Schema v2 centers on four primary operational entities:

- `cases`: case identity, lifecycle state, notes, and expiry fields
- `core_runs`: provenance for imported `Genesys.Core` run folders
- `imports`: per-import lifecycle rows and final counts
- `conversations`: flat analytical projection of normalized conversation records plus side-car JSON

The conversation table intentionally stores only the columns needed for early pivots. Nested detail that is
still useful for drilldown is preserved in `participants_json` and `attributes_json`.

Schema v2 also adds case-workflow tables:

- `case_tags`
- `bookmarks`
- `findings`
- `saved_views`
- `report_snapshots`
- `case_audit`

## Non-Goals

- No duplication of Genesys Cloud extraction logic
- No mutation of Core run artifacts
- No attempt to become the canonical warehouse for conversation data
- No long-term retention by default; case data must remain purgeable

## Lifecycle

The intended lifecycle is:

1. Create or select a case.
2. Run extraction through `Genesys.Core`.
3. Import the produced run folder into SQLite.
4. Pivot, annotate, export, and close the case.
5. Purge local data when the investigation is complete or expired.

Archive keeps the case shell, notes, findings, saved views, report snapshots, and audit history, but clears
imported run data. Purge clears imported data plus analyst-created workflow state while preserving the case
shell and audit history so operators can still see what action occurred and when.
