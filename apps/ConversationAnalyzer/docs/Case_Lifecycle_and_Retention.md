# Case Lifecycle and Retention

## Purpose

Case workflow state exists to preserve analyst momentum across multiple sessions while keeping local data
retention explicit and purgeable.

## States

- `active`: default working state
- `closed`: investigation work has ended, but local data remains present
- `expiring`: derived status for a case whose `expires_utc` is in the past while the stored state is still active or closed
- `archived`: imported run data has been cleared, but analyst work product remains
- `purge_ready`: case is marked for purge by policy or operator intent
- `purged`: imported data and analyst work product have been cleared; the case shell and audit trail remain

## Workflow State Stored Per Case

- notes
- tags
- bookmarks
- findings
- saved views
- report snapshots

## Retention Rules

1. `expires_utc` is the operator-controlled retention checkpoint.
2. When `expires_utc` is in the past, the derived retention status becomes `expiring` unless the case is
   already archived, purge-ready, or purged.
3. `Archive-Case` removes imported runs, imports, and conversations, but keeps workflow state and audit.
4. `Purge-Case` removes imported data plus workflow state. Audit remains so the operator can verify what
   was removed and when.

## Audit

Every case workflow action writes a row to `case_audit`, including:

- case creation
- state changes
- notes updates
- tag updates
- saved view creation and deletion
- imports
- archive
- purge

The application surfaces those audit rows in the case-management dialog.
