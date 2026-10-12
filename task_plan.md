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
| Conversation investigation package review | complete | Hardened chronological conversation/SIP timeline generation, regenerated sample package, confirmed live command path, and reran package/full validation. |
| Conversation package API PCAP export | complete | Removed the live `-SipTracePath` requirement, derived the analytics interval from `GET /api/v2/conversations/{conversationId}`, added SIP metadata/PCAP API export, regenerated the sample package, and reran targeted/full validation. |
| Session 20 temporal trend reporting | complete | Backend foundation and WPF Trend surface are now wired: two-window pull/import, comparison/delta accessors, regression/improvement panels, hourly overlay, incident-summary export, and case-date-range defaults. |
| Release 1.3 Edge Alarms & Event Feed | complete | Added Edge log-job catalog datasets and exported `Get-GenesysEdgeEvent` as a normalized NOC feed over Edge, trunk, alert, and optional Edge log-job status signals. Live endpoint acceptance remains a separate Track A gate. |

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
- For the package review, keep changes scoped to package generation, tests, docs, demo script, and sample artifacts.

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| Initial parser command contained a NUL byte due malformed shell quoting | Parse attempt 1 | Reran parser with explicit `$tokens`/`$errors` variables; all parse checks passed. |
| SQLite smoke path skipped native database runtime | Invoke-AllTests | Existing environment lacks `e_sqlite3` native library; test runner marked SMK-10 SKIP while overall suite passed. |
| In-place LF normalization failed inside sandbox with read-only temp-file error | Line-ending cleanup | Reran the mechanical normalization command with escalation; `git diff --check` is now clean on touched files. |
| Persisted `C:\Users\...` paths resolved as app-relative paths under WSL | Config/output investigation | Added config and Core output-root normalization so Windows drive paths map to `/mnt/<drive>/...` and relative backslash paths resolve correctly. |
| Offline demo PCAP hook still attempted signed URL DNS lookup | Demo package rerun | Fixed binary download handling so PowerShell-enumerated byte arrays from test/demo download hooks are written as `.pcap` bytes instead of falling through to `Invoke-WebRequest`. |

## 2026-09-15 Repository reconciliation and product assessment

- [x] Inspect divergence and preserve tracked/untracked work and Git merge metadata in external recovery archive.
- [x] Reconcile unfinished merge and latest origin/main, retaining unique modern work.
- [x] Remove proven legacy duplication and generated debris; repair documentation authority.
- [x] Run applicable Core, app, and mock-server checks.
- [x] Record current feature value and ranked future opportunities with sources and proof boundaries.

Recovery archive: /mnt/f/Development/20_Staging/GenesysCloud/Genesys.Core-recovery-20260915T045511Z

Publication: blocked by absent GitHub HTTPS credentials; local reconciliation is complete. No remote changes made.

## 2026-10-11 Adaptive endpoint pacing

- [x] Inspect retry and paging entry points; preserve unrelated edits.
- [x] Implement per-endpoint 429 learning, shared server cooldown, and telemetry.
- [x] Verify deterministic timing, isolation, retry safety, and existing Core tests.
- [x] Document scope and limitations.

## 2026-10-11 Browser demo audit and corrections

- [x] Start the real mock server and web client; establish browser control.
- [x] Walk through sign-in, data exploration, filtering, reports, exports, endpoint discovery, and responsive layout; collect evidence.
- [x] Correct reproduced issues and validate the changes.
- [x] Save a reviewable report and screenshots with exact proof boundaries.

## Monthly voice-volume reconciliation (2026-10-11)

- [x] Verify four-source collection contracts and catalog metadata.
- [x] Implement Core-backed reconciliation with source coverage and portable output.
- [x] Test equal/divergent/partial/unavailable results and paging through Core.
- [x] Document usage and synchronize roadmap with landed work.
- [ ] Live tenant acceptance (requires real tenant execution; separate gate).

## Conversation incident workbench (2026-10-11)

- [x] Adapt the supplied pure profiling function into Ops with explicit field definitions.
- [x] Add Core-backed interval/queue/user/Division/custom-query collection and artifact export.
- [x] Build an interactive frontend over Ops profiles with full-filtered-set count/avg/max,
      grouping, error statistics, pagination, drilldown and faithful exports.
- [x] Validate profiling semantics, Core request scope, browser workflows and accessibility.
- [x] Document provenance, usage, limits, and remaining live acceptance.

Visual thesis: a restrained investigation ledger, white workspace, navy typography and one
warm accent. Content: scope/coverage, filters and summary, population table, detail drawer.
Interaction: fast filter-to-summary updates, sticky table headers, brief drawer reveal with
reduced-motion support. No decorative imagery or hero is needed for this engineering tool.

## Data Client conversation integration (2026-10-11)

- [x] Add a shared-workbench route and navigation in both skins without duplicating Ops logic.
- [x] Preserve the loaded analysis and view through navigation and skin changes in memory.
- [x] Validate imports, statistics, exports, mobile layout, and accessibility in the client.
- [x] Update roadmap and usage; retain entity names, scale, and tenant gates separately.

Visual thesis: reuse the existing investigation ledger inside the established application shell.
Content: collection command, analysis import, filters/statistics, timeline and exports.
Interaction: retain investigation state through navigation; use existing reduced-motion behavior.

## Entity labels and population scale (2026-10-12)

- [x] Ignore generated logs without removing tracked evidence.
- [x] Add Core-backed run-scoped lookup coverage for queues/users/Divisions/wrap-up/skills/languages.
- [x] Expose labels alongside stable IDs; keep ambiguity and missing/access-denied evidence explicit.
- [x] Benchmark realistic large populations, optimize measured hotspots, and bound rendered breakdowns.
- [x] Validate Ops joins, engine semantics and browser workflows; record measured limits.

## NOC product direction (user clarification, 2026-10-12)

- [x] Reorient client onboarding/navigation around investigations rather than raw endpoint execution.
- [x] Add operational foundations: flow IDs, packet observations and current user-Division joins.
- [x] Record the mass-disconnect composer, complete async-family contract and acceptance gates.
- [ ] Implement cross-source mass-disconnect composer, historical state/baseline/audit joins and live NOC workspace (next release work; not claimed complete).


Documentation synchronization (2026-10-12): updated main/app entry points, onboarding, architecture status, product priorities, changelog, accessibility and testing evidence for population analysis, entity resolution, scale and monthly reconciliation. Kept NOC composition and live acceptance open. Verified catalog totals: 112 datasets / 3,389 endpoints.
