# ConversationAnalyser Reporting Phase Plan

Goal: finish the current ConversationAnalyser reporting phases, review and harden recent changes, and proceed through the next roadmap release slice.

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| Study Session 15 patterns | complete | Confirmed report pattern in ConversationAnalyser CoreAdapter/Database; XAML/UI still only contain Session 14/15 tabs. |
| Step 2 database changes | complete | v7 transfer tables/import/accessors were present; denominator handling was corrected for transfer metrics catalog fields. |
| Verify | complete | Parser checks passed; Invoke-AllTests passed 159 PASS / 0 FAIL / 1 SKIP. |
| Documentation | complete | Updated ROADMAP.md and CHANGELOG.md for Session 16 database foundation status. |
| Review and harden Session 16 foundation | complete | Fixed name-only queue transfer flow key collision risk. |
| Complete Session 16 UI release slice | complete | Added Transfer & Escalation tab and handlers following Queue/Agent report patterns. |
| Final verification | complete | Parse checks and Invoke-AllTests passed: 179 PASS / 0 FAIL / 1 SKIP. |
| Release docs update | complete | Updated roadmap/changelog/planning notes; Session 16 now delivered. |
| Code review latest changes | complete | Hardened stale report-tab state, weighted Flow summary rates, robust flow-to-queue correlation, and line-ending cleanliness. |
| Session 17 roadmap phase | complete | Implemented IVR and Flow Containment report using the established CoreAdapter/Database/XAML/UI/test/doc pattern. |
| Conversation display investigation | complete | Traced API run completion through output folder discovery, config path resolution, async job polling, indexing, and grid display. |
| Conversation display fix | complete | Patched path resolution, run-folder selection, and async terminal-state handling; parser/tests/diff checks passed. |
| Product-purpose reorientation P0/P1 foundation | complete | Implemented canonical filter state, full-filtered-set DB reports, SQL-backed column filtering, canonical raw JSON drilldown, lineage, derived analysis columns, bridge tables, analytics helpers, tests, saved-view restore, and README updates. |
| Core contract fixture hardening | complete | Added real Core-output fixture validation, tightened importer contract checks/reconciliation, improved Analyzer/Core alignment, documented the contract gate, and ran feasible fixture/runtime tests. |
| Session 19 roadmap phase | complete | Implemented quality evaluations/surveys/topic overlay import, case-window normalization, Quality tab UI, low-score drillthrough, and test/doc updates. |
| Release 1.0 Agent Investigation Track B follow-up | complete | Evaluated the current roadmap pivot, hardened Agent Investigation composer edge cases, repaired fixture integration coverage, and synchronized roadmap/readiness/onboarding docs after 105 unit and 12 integration tests passed. |

## Current Task Scope

User goal: move ConversationAnalyser from a page-row viewer toward a Core-backed investigation workbench with trustworthy full-population analysis, faithful drilldown, provenance, and analytical schema support.

Current user goal: use readiness findings to test against real/Core-shaped output fixtures and harden the Analyzer/Core contract so imported Core conversations display reliably in the UI.

Execution strategy:

1. P0 correctness first: canonical filter object, DB report/page independence, SQL-backed column filters, raw JSON drilldown, import lineage.
2. P1 database foundation next: derived columns, many-to-many bridge tables, analytics query helpers for summaries/facets/representatives.
3. P2 UI/report/documentation where feasible in this turn: scope bar/population summary/representative path and README purpose update.
4. Preserve the Core boundary: no direct Genesys REST outside `App.CoreAdapter.psm1`.

## Constraints

- Preserve existing unrelated worktree modifications.
- Keep changes aligned with local AuditLogsConsole patterns.

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| Initial parser command contained a NUL byte due malformed shell quoting | Parse attempt 1 | Reran parser with explicit `$tokens`/`$errors` variables; all parse checks passed. |
| SQLite smoke path skipped native database runtime | Invoke-AllTests | Existing environment lacks `e_sqlite3` native library; test runner marked SMK-10 SKIP while overall suite passed. |
| In-place LF normalization failed inside sandbox with read-only temp-file error | Line-ending cleanup | Reran the mechanical normalization command with escalation; `git diff --check` is now clean on touched files. |
| Persisted `C:\Users\...` paths resolved as app-relative paths under WSL | Config/output investigation | Added config and Core output-root normalization so Windows drive paths map to `/mnt/<drive>/...` and relative backslash paths resolve correctly. |
