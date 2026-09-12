# Changelog

## 2026-09-12 (catalog — digital work investigation, voicemail and bot-flow enrichment)

### Added

- **New curated catalog endpoints** in `catalog/genesys.catalog.json`: `voicemail.get.queue.messages`,
  `analytics.get.botflow.sessions`, `analytics.get.botflow.divisions.reportingturns`, and the
  Task Management work-item surface (`taskmanagement.create.workitems.query.job`,
  `taskmanagement.get.workitems.query.job.status`, `taskmanagement.get.workitems.query.job.results`,
  `taskmanagement.get.workitem`, `taskmanagement.get.workitem.history`,
  `taskmanagement.get.workitem.wrapups`). All raw endpoints already existed in the auto-mirrored
  catalog; these are the hand-curated, paging/retry-annotated aliases used by combination recipes.
- **New `taskmanagement.query.workitems` dataset** and `workitems_query_jobs` transaction/paging
  profiles, following the same async submit/poll/results shape as `audit-logs` and
  `analytics-conversation-details`. Marked `validationStatus: unvalidated` pending Track A live
  validation, consistent with every other not-yet-exercised dataset in the catalog.
- **New `digital-work-investigation` investigation recipe** and **`digital-work-throughput-and-cycle-time`
  executive playbook** — the non-conversational counterpart to the Queue and Division investigations,
  covering Task Management work items (cases/tickets/back-office work) by queue or division:
  backlog, cycle time, overdue rate, and per-assignee throughput.
- **`voicemail-fallback` step added to the `queue-investigation` recipe** — reconciles
  `nAbandoned` against voicemail messages left for the queue so abandon-rate KPIs are not
  overstated for queues with a working voicemail fallback.
- **Bot Flow diagnostics added to the `flow-and-ivr-diagnostics` playbook** —
  `analytics.get.botflow.sessions` and `analytics.get.botflow.divisions.reportingturns` for
  self-service containment root-cause when the flow is a Bot Flow rather than a classic
  Architect inbound flow.
- **`docs/ENDPOINT_COMBINATIONS.md`** gained a new numbered Pattern 10 (Digital Work / Task
  Management Investigation), a voicemail-fallback subsection under Pattern 2, a bot-flow
  diagnostics subsection under Pattern 5, an eighth column (`Digital Work Investigation`) and six
  new rows in the dataset combination reference matrix, and six new metric glossary entries
  (`nVoicemail`, `nWorkitemsCreated`, `nWorkitemsClosed`, `backlogCount`, `avgCycleTimeHours`,
  `nOverdue`).

Schema-validated (`catalog/schema/genesys.catalog.schema.json`) and cross-checked so every
`dataset`/`datasetsInOrder` reference in `combinations` resolves to a real `datasets` or
`endpoints` key — no dangling references introduced.

## 2026-09-05 (test suite repair)

### Fixed

- **`tests/integration/MockServer.Integration.Tests.ps1` could not run at all.** Its
  whole `Describe` aborted in `BeforeAll`, taking 13 tests with it. Four separate
  defects, all pre-existing:
  - `Start-MockServer` and `Stop-MockServer` were defined at script level. Pester
    v5 evaluates a file's body during discovery and runs blocks in a separate
    scope, so they were gone by the time `BeforeAll` called them. Configuration
    and helpers now live inside `BeforeAll`, assigned with `$script:` so the `It`
    blocks can still reach them.
  - The auth header was the literal string `"******"` — real source overwritten
    by a secret-redaction pass, the same corruption found earlier in
    `MockServerTests.cs`. Restored to `Bearer $($script:DemoToken)`, from the
    token the file already declares.
  - The manifest assertions named `dataset` and `totalItems`. `Invoke-Dataset`
    writes `datasetKey`, `runId`, `startedAtUtc`, `endedAtUtc`, `gitSha`,
    `counts` and `warnings`, and always has. Verified against a real run.
  - `$path | Get-Content` cannot bind: `Get-Content -Path` is
    `ValueFromPipelineByPropertyName` only, so a bare string from the pipeline
    raises a parameter-binding error. Pester does not stop on it, so the variable
    was silently `$null` and the failure read as a missing property rather than a
    failed read. Now `Get-Content -LiteralPath`.

  That file now passes **13/13**.
- **The static accessibility analyzer crashed on any page with no inline
  `<style>` block.** `Get-CssRuleBlock` returns nothing for such a page, which
  unwraps to `$null` and fails to bind to the `[AllowEmptyCollection()]`
  `-CssBlocks` parameter. Normalized with `@()`, along with the `-Nodes`
  argument beside it.
- **The surface-manifest test swept up vendored and generated files**, demanding
  WCAG declarations for `node_modules` and `dist`. Discovery now skips
  `node_modules`, `dist`, `build` and `coverage`.
- **`scripts/Start-MockServer.ps1` printed unusable instructions** — the same
  `"******"` corruption, in the help text and in the "quick connect" snippet it
  tells operators to copy. Both restored.
- **CI reported green with 14 failing tests.** `tests/PesterConfiguration.ps1`
  never set `Run.Exit`, so `Invoke-Pester` exited 0 regardless of results. Now
  set, and verified to exit 0 on a green suite and 1 on a red one.

### Added

- `apps/GenesysDataClient/index.html` is now a declared WCAG surface. React
  renders the page, so the static analyzer sees only the shell — but the shell
  still owns the page language, the document title and a zoomable viewport, and
  those are enforced. The four rules describing the rendered DOM (`A11Y004`,
  `A11Y006`, `A11Y019`, `A11Y024`) are excluded for this surface and audited
  instead against the running application by the axe-core gate.
- Per-surface `excludeRules` in `config/accessibility-surfaces.json`, honoured by
  both the audit script and the Pester test, plus a guard test requiring every
  exclusion to carry a written `$excludeReason`. An exclusion is a claim that a
  rule cannot apply, not a way to silence a finding, so the claim has to be
  reviewable. The guard was verified to fail when the justification is removed.

### Verified

- Pester **279 passed, 0 failed, 1 skipped** (was 264 passed, 14 failed).
- Static WCAG audit: **8 surfaces, 0 violations** (was 7).

## 2026-09-05 (build hygiene — recursive output copy)

### Fixed

- **`Genesys.MockServer` copied its own test project into its build output, one
  level deeper on every build.** The xUnit project lives at
  `tools/Genesys.MockServer/tests/Genesys.MockServer.Tests`, inside the server
  project's directory, so the Web SDK's default `Content` glob (`**/*.json`,
  copied to the output directory) swept up the test project's `bin/` and `obj/`.
  The test project references the server, so its build copied that output
  straight back — adding one directory level per cycle. It had reached 12 levels
  and 648-character paths, past what Windows and git can open:

  ```text
  error: unable to index file 'tools/Genesys.MockServer/bin/Debug/net8.0/tests/
  Genesys.MockServer.Tests/bin/Debug/net8.0/...': Filename too long
  fatal: adding files failed
  ```

  The project's existing `<Compile Remove="tests/**" />` only covered `.cs`
  files. It is replaced by
  `<DefaultItemExcludes>$(DefaultItemExcludes);tests/**</DefaultItemExcludes>`,
  which drops `tests/**` from every default glob at once — `Compile`, `Content`,
  `None` and `EmbeddedResource`. MSBuild reported 124 `Content` items sourced
  from `tests/` before the change and 0 after; the server's `bin/` went from 121
  files to the 7 it should hold, and two further build cycles added none.
- **`.gitignore` never covered .NET build output**, so 61 generated files were
  tracked, including the nested copies. `bin/` and `obj/` are now ignored and
  those files are untracked (`git rm --cached`, so nothing left the working
  tree). `core.longpaths` is enabled locally so git can operate on what is
  already committed.

### Added

- `BuildOutputDoesNotRecursivelyNestTheTestProject` — a regression guard that
  fails at the first level of recursion instead of the twelfth. Verified to fail
  when the condition is planted and pass when it is not, so it cannot pass
  vacuously. Path length is measured relative to the output directory, so the
  assertion does not depend on where the repository is cloned.

### Not fixed

- The nested paths reached **two levels (178 characters)** in committed history,
  in `dd9b040` and `1ce0f96`. That still clones on Windows, but with little
  headroom. Removing it would mean rewriting shared history, which has not been
  requested.

## 2026-09-05 (third pass — authentication)

### Added

- **OAuth 2.0 Authorization Code with PKCE** in the Genesys Data Client
  (`src/core/auth.ts`, `src/app/AuthProvider.tsx`, `src/features/SignIn.tsx`).
  One flow serves both destinations: the demo authorization server and a live
  Genesys org. Only the base URL differs; the client code is identical.
  - Verifier is 32 random bytes as base64url, challenge is `S256`, matching
    `modules/Genesys.Auth/Genesys.Auth.psm1` so both consumers work against the
    same OAuth client registration. The derivation is pinned to the RFC 7636
    Appendix B worked example by test.
  - `state` generated per request and checked on return; a mismatch aborts.
  - The verifier never travels in a URL — it is held in `sessionStorage` across
    the redirect and cleared on return.
  - Tokens live in `sessionStorage` (tab-scoped, cleared on close); only
    non-secret preferences go to `localStorage`.
  - Automatic refresh ~2 minutes before expiry with the same 30-second margin
    `Genesys.Auth` uses, plus manual refresh, sign-out and revocation.
  - The application no longer renders anything before there is a session, and it
    never displays a whole token — only a short prefix.
  - Region picker covering the common Genesys regions plus a free-text entry, so
    a region missing from the list never blocks a sign-in.
- **Demo authorization server on `Genesys.MockServer`** (`DemoOAuth.cs`,
  `OAuthApi.cs`), shaped like `login.{region}`: `GET/POST /oauth/authorize`,
  `POST /oauth/token` (`authorization_code`, `refresh_token`,
  `client_credentials`), `GET /oauth/userinfo`, `POST /oauth/revoke`.
  **The identity is fake; the protocol is real.** It verifies
  `BASE64URL(SHA256(ASCII(code_verifier)))` in constant time, refuses `plain`,
  refuses a request with no challenge, binds codes to their client and redirect
  URI, consumes a code on the first redemption attempt even when the verifier was
  wrong, rotates refresh tokens, and returns RFC 6749 error shapes. Demo mode
  therefore exercises the client's real PKCE path rather than stubbing it.
  - The consent screen collects **no credentials** — no username or password
    field — and says so. It makes the authorization step visible; it does not
    imitate a sign-in.
- 26 new tests: 16 client PKCE units, 11 client-against-server integration tests
  (wrong verifier, code replay, refresh rotation, denial, non-PKCE and `plain`
  rejection, untrusted `redirect_uri`, revocation), and 13 mock server xUnit
  tests covering the same ground server-side.

### Changed

- API requests accept either the fixed demo token or any unexpired token minted
  through the PKCE flow, so existing scripts and the PowerShell modules keep
  working unchanged.
- The CoreClient's bearer and API base are now derived from the authenticated
  session, so signing in or out — or a token refresh — reconfigures every data
  source without anything else being touched.
- The accessibility gate now covers the sign-in screen and the demo consent
  screen: **15 surfaces, 0 violations**.

### Not verified

- The live Genesys path has not been exercised against a real org; no tenant was
  available. The flow is verified end to end against the demo authorization
  server, and its parameters match the PowerShell implementation that does run
  against live orgs.

## 2026-09-05 (second pass)

### Fixed

Second-pass review of the Genesys Data Client. Every item below was reproduced
before it was changed.

- **CSV exports were not machine-reusable.** Rows were written with display
  formatting, so timestamps came out locale-formatted (`Feb 14, 2026, 04:00:00 AM`),
  durations as prose (`14m 27s`) and numbers with thousands separators
  (`1,234,567`) — none of which parse or aggregate. Added
  `formatForExport`: CSV now emits ISO 8601 UTC timestamps, durations as raw
  milliseconds and unformatted numbers, with units stated in the provenance
  header. Markdown, which is meant to be read, keeps the friendly rendering.
- **CSV formula injection.** Exported cells beginning with `=`, `+`, `-` or `@`
  were written verbatim, so Genesys data a person can type (participant names,
  wrap-up notes) would be evaluated as a formula on open. Such cells are now
  prefixed with an apostrophe; genuine numbers are left alone so negatives stay
  numeric.
- **Expanded rows followed the row position, not the record.** Disclosure state
  was keyed by array index while sorting and filtering reorder rows in place, so
  re-sorting left the detail open on whichever record landed in that slot. Keyed
  by record identity, with a stable React key derived from the record's own id.
- **Date aggregates rendered as epoch milliseconds.** `min`/`max` over a
  timestamp field displayed and exported as `1771059600000`. Aggregates now
  inherit their field's type unless the aggregate is a plain tally.
- **The Genesys skin's back button kept a private history stack** that desynced
  from browser back/forward once hash routing existed. It now delegates to the
  browser.
- **A panel claimed coverage it never checked.** The explorer's provenance panel
  rendered a hardcoded green "Demo data" badge for every endpoint. It now shows
  the catalog key; coverage remains the server's to report.
- **Saved views could not see new fields.** A view stored before a source gained
  a field left that field permanently invisible. Column layouts are now
  reconciled against the current field set on load.
- **WCAG 2.1 AA violations in the rendered application.** axe-core found
  insufficient contrast on the avatar, primary buttons, active pills, accent
  text and muted badges. Introduced solved accent palettes
  (`src/core/accents.ts`) splitting graphical (`--accent`) from text-safe
  (`--accent-strong`, `--accent-text`) shades per theme, neutralized
  accent-tinted backgrounds so ratios no longer depend on the chosen accent,
  darkened `--ink-3` to clear 4.5:1 on the darkest surface it is used on, and
  fixed a specificity bug where `:hover` on an active segmented control
  overrode its label colour. **13 surfaces — both skins, both themes, all five
  accents — now report 0 violations.**

### Added

- `npm run test:a11y` — a WCAG 2.1 AA gate that drives a real browser and runs
  axe-core against every skin, theme and accent. The repository's PowerShell
  analyzer only sees static HTML and cannot audit a React-rendered surface, so
  this closes that gap. Wired into the `data-client-integration` CI job.
- `reconcileColumns` for saved-view/field reconciliation, and `formatForExport`
  for machine-readable serialization.

### Removed

- `tools/Genesys.MockServer/PagingEngine.cs`. `BuildPagedResponse` was never
  called by any dispatcher path — verified against the committed baseline, so
  this was pre-existing dead code rather than fallout from the coverage-table
  refactor. Its DI registration, the unused `RouteDispatcher` constructor
  dependency and the now-meaningless `MOCK_PAGE_SIZE` environment variable went
  with it.

### Changed

- Panel boards group consecutive normal panels into a CSS multi-column run, so a
  short panel beside a tall one no longer leaves dead space. Wide panels still
  span the full width and reading order is preserved.

## 2026-09-05

### Added

- **Genesys Data Client** (`apps/GenesysDataClient/`) — a customizable data
  exploration, analysis, reporting and visualization application built on
  Genesys.Core, with its own isolated Vite + React + TypeScript toolchain.
  Node stays a dependency of this application only; Genesys.Core itself remains
  free of any frontend toolchain, and `dist/` is produced by CI rather than
  committed.
  - Reusable Data Client primitives in `src/core/contracts.ts`: `DataSource`,
    `QueryDefinition`, `ViewDefinition`, `ReportDefinition`,
    `DashboardDefinition`, `ExportDefinition` and `Workspace`.
  - Engine layer (`src/engine/`): type-aware filtering and sorting, faceting,
    ad-hoc grouping and aggregation, CSV/JSON/NDJSON/Markdown export with
    provenance, and persisted workspace state.
  - Nine data sources covering conversations (full async job lifecycle with
    cursor paging), conversation segments, active conversations, users, routing
    queues, audit logs, roles, OAuth clients and speech & text topics.
  - Two skins: **Genesys**, reproducing the productized unified navigation
    experience including its fixed layout and light-only theme; and **Atlas**,
    the same data with the interface under user control — light/dark/system
    theme, configurable accent and density, movable and collapsible panels,
    sortable/filterable/reorderable/resizable columns, ad-hoc reports and
    saved views.
  - Endpoint explorer that renders the server's endpoint outline live from the
    discovery API and can run any endpoint in place.
  - 38 tests: engine units, hash routing, and integration tests that drive every
    data source over HTTP against a running demo server.
- **Discovery API on `Genesys.MockServer`** — unauthenticated `/__meta`,
  `/__meta/groups`, `/__meta/endpoints`, `/__meta/endpoints/{key}`,
  `/__meta/coverage` and `/__meta/datasets`, so a client can render an accurate
  outline of what the server can exercise without bundling the 1.6 MB catalog.
- **`FixtureCoverage`** — a declarative coverage table that is now the single
  source of truth for which routes the mock server backs with demo data.
  `RouteDispatcher` executes it and the discovery API reports it, so the client's
  endpoint outline cannot drift from what the dispatcher actually serves.
- CORS on the mock server (`MOCK_CORS_ORIGINS`, permissive by default) and
  optional static hosting of a built Data Client from
  `apps/GenesysDataClient/dist` (`MOCK_STATIC_ROOT`), with SPA fallback that
  leaves `/api`, `/__meta` and `/oauth` answering as JSON.
- 9 mock server tests covering the coverage table and discovery API, including
  guards against dead coverage rules and missing fixtures.

### Fixed

- **`tools/Genesys.MockServer` tests were failing before this change.** A
  secret-redaction pass had rewritten real source: the test auth helper sent the
  literal string `******` as its `Authorization` header, so five tests failed
  with 401. `RouteDispatcher.ValidateAuth` carried the same corruption in an
  error message. Restored the `Bearer` scheme in both, and made
  `Api_endpoint_with_wrong_token_returns_401` exercise the token comparison
  rather than passing by accident on a malformed scheme. Suite went from
  10/15 to 15/15 before the new tests were added.

### Changed

- `CatalogLoader` now exposes `operationId`, `summary`, `description`, `tags`,
  a resolved `Group`, `defaultBody`, `defaultQueryParams` and the catalog
  `datasets` node, so the discovery API can describe endpoints usefully.
- `.github/workflows/ci.yml` gained `data-client` (typecheck, tests, build,
  `dist` artifact) and `data-client-integration` (mock server tests, then the
  Data Client integration suite against a live mock server) jobs.

## 2026-09-02

### Added

- **WCAG 2.1 Level AA conformance** across all seven shipped HTML surfaces.
  - `tools/Genesys.Accessibility` — a dependency-free static analyzer
    (25 rules) exporting `Test-HtmlAccessibility`, `Get-ContrastRatio`,
    `Get-RelativeLuminance`, `ConvertFrom-CssColor`, and
    `Get-GenesysAccessibilityRule`. Runs on Windows PowerShell 5.1 and
    PowerShell 7+ with no Node/npm toolchain.
  - `scripts/Invoke-AccessibilityAudit.ps1` — audit CLI with an optional JSON
    report; exits non-zero when violations remain.
  - `config/accessibility-surfaces.json` — the canonical surface manifest.
  - `tests/unit/Accessibility.Wcag21.Tests.ps1` — 17 tests covering the
    analyzer itself, all shipped surfaces, design-token contrast, runtime
    generated markup, and the PowerShell HTML generators.
  - `accessibility` job in `.github/workflows/ci.yml`.
  - `docs/ACCESSIBILITY.md` — conformance statement, rule catalogue, and the
    manual checklist for criteria requiring a rendered viewport.

### Changed

- Operator consoles (`apps/OpsConsole`, `apps/InvestigationConsole`,
  `apps/ConversationAnalysis`), `catalog/catalog-browser.html`,
  `docs/architecture.html`, and `docs/training/genesys-onboarding.html`:
  added skip links and named `main` landmarks, a single `<h1>` per page,
  visible `:focus-visible` indicators, WAI-ARIA tab wiring with Arrow/Home/End
  keyboard navigation, `aria-pressed` on every filter toggle, scoped table
  headers with captions and `aria-sort`, accessible names on all charts, live
  regions for status messages, and `aria-hidden` on decorative glyphs.
  Clickable `div`/`span` controls became real `<button>` elements.
- Split colour tokens into graphical (`--accent`, `--ok`, `--warn`,
  `--danger`, held to 3:1 per SC 1.4.11) and text-safe (`--accent-text`,
  `--ok-text`, `--warn-text`, `--danger-text`, held to 4.5:1 per SC 1.4.3).
  White text now sits on `--accent-dk` (5.35:1) rather than `--accent`
  (3.39:1). `catalog/catalog-browser.html` darkened `--text-muted` and
  lightened the header text colours for the same reason.
- `ConvertTo-GenesysHtmlTable` now emits `<caption>` and `<th scope="col">`
  and takes a `-Caption` parameter. Both `Genesys.Ops` package templates and
  `Export-AuditHtml` in `apps/AuditLogsConsole/App.Export.psm1` now emit a
  viewport meta, a skip link, a named `main` landmark, and a focus indicator.
- Regenerated `samples/demo-conversation-investigation/demo-conversation-investigation.html`
  from the updated generator.

### Fixed

- `docs/architecture.html`: the "HTTP Request Lifecycle with Retry" diagram
  used `classDef call`, and `call` is a reserved mermaid keyword, so the
  diagram failed to parse and rendered as an error box. Renamed to
  `classDef invoke`; all 16 diagrams now render.
- `apps/ConversationAnalysis/index.html`: removed `outline: none` from the
  search box, page-size select, and attribute filter, which had suppressed the
  keyboard focus ring entirely.

## 2026-08-15

### Fixed

- Corrected a malformed endpoint key in `catalog/genesys.catalog.json`'s
  `combinations.investigationRecipes.division-investigation` recipe:
  `analytics.division.analysis.conversation.aggregates.by.division.oct.15.dec.8`
  (a stray literal date range baked into the operationId, with `itemsPath` set
  to `$.conversations` instead of the aggregates endpoint's actual
  `$.results` root) is renamed to
  `analytics.query.conversation.aggregates.division.performance` with a
  corrected `itemsPath`, consistent with its sibling
  `analytics.query.conversation.aggregates.*` endpoints. The
  `conversation-aggregates-by-division` recipe step now references the
  corrected key.

### Added

- Added two investigation recipes to `catalog/genesys.catalog.json`'s
  `combinations.investigationRecipes` for parity with the patterns already
  documented in `docs/ENDPOINT_COMBINATIONS.md`:
  `real-time-operations-monitoring` (point-in-time queue/agent/flow/trunk
  observation steps for a NOC wallboard, with single-agent drilldown steps
  marked separately from the polling loop) and `byoi-conversation-enrichment`
  (BYOI provenance and external-attribute steps that run alongside
  `single-conversation-investigation` for conversations injected via the
  BYOI provider API). All dataset references in both new recipes resolve to
  existing `datasets` or `endpoints` entries in the same catalog file — a
  reference-integrity audit walked every `dataset` field across all seven
  `investigationRecipes` and confirmed each resolves to a real catalog
  entry; the division-performance key above was the one genuine break
  found (17 other references that don't exist under `datasets` are
  intentional references to raw `endpoints` operationIds and were already
  correct).
- Cross-referenced the JSON `combinations` recipes from
  `docs/ENDPOINT_COMBINATIONS.md` so the human-readable patterns and the
  machine-readable catalog recipes are discoverable from each other.

## 2026-06-08

### Changed

- Hardened `tests/unit/GenesysOps.Phase5Exports.Tests.ps1` so the
  source-definition assertion accepts indented function declarations in
  `modules/Genesys.Ops/Genesys.Ops.psm1`; this removes a false-negative failure
  in the unit suite while preserving the export-surface verification intent.
- Hardened dropped-file ingestion in `apps/InvestigationConsole/index.html` by
  replacing placeholder manifest synthesis with summary-derived run identities
  and guarded JSON parse handling; malformed dropped files are now skipped with
  operator-visible warning details instead of aborting import.
- Added `tests/unit/InvestigationConsole.ImportHardening.Tests.ps1` to lock in
  the hardened import behavior (no placeholder manifest keys, guarded parse
  path, and investigation-kind inference).
- Added `tests/unit/ConversationAnalyzer.TrendCheckpoint.Tests.ps1` and
  `docs/READINESS_REVIEW.md` Section 10 (`J-01`, `J-02`) as a Release 1.3
  checkpoint slice so Session 20 trend contract + docs alignment are asserted
  in the main unit suite.
- Closed the Release 1.3 checkpoint backlog by adding
  `docs/RELEASE_1_3_TREND_EVIDENCE.md` (command-level trend checkpoint evidence
  + sign-off checklist), extending
  `tests/unit/ConversationAnalyzer.TrendCheckpoint.Tests.ps1` to assert the
  evidence references, and promoting readiness criterion `J-03` in
  `docs/READINESS_REVIEW.md`.
- Updated `docs/ROADMAP.md` to a status-board format with explicit `Completed`,
  `Active`, `Next`, and `Maintenance` sections plus an operational sustainment
  checklist for scheduled tests, dependency checks, docs review, CI review, and
  live-validation evidence gates.

## 2026-05-13

### Added

- **Release 1.3 Edge Alarms & Event Feed:**
  - Added Edge log-job catalog datasets for creating a log job, reading log-job status, and requesting an upload from a specific Edge.
  - Added `Get-GenesysEdgeEvent` to `Genesys.Ops`, normalizing Edge inventory, trunk state, active alerts, and optional Edge log-job status into a flat NOC feed.
  - Added unit coverage for the NOC feed contract, Edge log-job dataset parameter forwarding, and the `-LogJobId`/`-EdgeId` guard.

### Changed

- Recorded Session 20 Trend UI as delivered after validating the WPF Trend tab, regression/improvement panels, hourly overlay, and case-date-range default wiring through the ConversationAnalyzer test harness.
- Hardened `apps/MonthlyMetrics/Get-GenesysMonthlyMetrics.ps1` for recurring monthly reporting: previous-month year/month defaults now align across January boundaries, conversation volume detail uses `originatingDirection`, the workbook now includes `Monthly_Totals` and `Voice_PeakConcurrent` sheets, and response expansion tolerates missing optional aggregate/page fields under strict mode.
- Hardened ConversationAnalyzer post-run display: the run panel now shows the exact saved run/data folders, and completed runs with saved conversation rows automatically clear stale grid filters if those filters would otherwise hide every returned conversation.
- Hardened `analytics-conversation-details` empty-result artifacts: blank JSONL runs now include request-shape diagnostics in `summary.json`, explicit `analytics.conversationDetails.zeroResults`/request events, and a manifest warning so operators can distinguish a valid zero-result API response from a display or writer failure.

## 2026-05-12

### Added

- **Release 1.4 operator console + demo-ready productization:**
  - Added `apps/InvestigationConsole/index.html`, a single-file offline console for Agent, Conversation, and Queue investigations with summary KPIs, investigation-specific views, run history, and a diagnostics pane.
  - Added generic package exports in `Genesys.Ops`: `Export-GenesysInvestigationPackage` writes Markdown/CSV/XLSX deliverables and `Export-GenesysInvestigationDiagnosticsBundle` writes redacted support JSON.
  - Added wrapper scripts `scripts/Export-InvestigationPackage.ps1`, `scripts/Copy-InvestigationDiagnosticsBundle.ps1`, and `scripts/Invoke-GoldenPathDemo.ps1` to package runs, hand off diagnostics, and assemble the golden-path demo scenario.
  - Added focused Pester coverage for the new 1.4 packaging and diagnostics workflows.

- **Investigation enrichment + demo outputs:**
  - `Get-GenesysAgentInvestigation` now includes `routingStatus`, `utilization`, and `activeConversations` sections sourced from user-scoped Genesys endpoints.
  - `Get-GenesysConversationInvestigation` now includes `surveys` so a single investigation can surface CSAT / NPS alongside recordings and evaluations.
  - `Get-GenesysQueueInvestigation` now seeds from `routing.get.single.queue.config` and adds `wrapupCodes`, `transfers`, and `wrapupDistribution`, while explicitly parameterizing queue/window aggregate queries.
  - Added deterministic demo generators: `scripts/New-DemoAgentInvestigation.ps1`, `scripts/New-DemoConversationInvestigation.ps1`, and `scripts/New-DemoQueueInvestigation.ps1`.
  - Added committed sample outputs under `samples/demo-agent-investigation/`, `samples/demo-conversation-investigation-run/`, and `samples/demo-queue-investigation/`.

- **ConversationAnalyzer Session 20 backend foundation:**
  - `Get-TrendReport` added to `apps/ConversationAnalyzer/modules/App.CoreAdapter.psm1` to pull queue-performance, abandon, and service-level aggregates for two comparison windows (`WindowA`, `WindowB`).
  - Schema bumped to **v12** with `report_trend_windows`, `report_trend_comparison`, and the `report_trend_delta` view in `apps/ConversationAnalyzer/modules/App.Database.psm1`.
  - `Import-TrendReport`, `Get-TrendComparisonRows`, `Get-TrendChangeLeaders`, `Get-IncidentImpactSummary`, and `Export-IncidentImpactSummary` added to establish comparative reporting and briefing export before the WPF Trend tab is wired.
  - `apps/ConversationAnalyzer/tests/Invoke-AllTests.ps1` now asserts the trend-report backend surface.

### Changed

- `docs/ROADMAP.md`, `apps/ConversationAnalyzer/docs/ConversationAnalytics_Roadmap.md`, `progress.md`, and `task_plan.md` updated to record Session 20 as partially delivered: backend foundation complete, UI/charting still open.

## 2026-05-07

### Changed

- **Conversation Investigation package hardening:**
  - `Get-GenesysConversationInvestigation` now starts with
    `GET /api/v2/conversations/{conversationId}` to derive the conversation
    start/end window before calling `analytics-conversation-details-query`.
  - `Export-GenesysConversationInvestigationPackage` no longer requires
    `-SipTracePath` for live use; it queries SIP metadata, requests the PCAP
    download, polls the signed URL, and writes the `.pcap` into the package.
  - Added `docs/CONVERSATION_INVESTIGATION_PACKAGE.md` with the exact live
    command, API sequence, output files, and PCAP permissions.

## 2026-04-30

### Changed

- **Release 1.0 Track B — Agent Investigation hardening:**
  - Hardened `Invoke-Investigation` so empty optional steps remain empty arrays
    instead of becoming `$null` and failing `.Count` checks.
  - Hardened Agent Investigation subject filters for scalar PowerShell pipeline
    output from single queue memberships or single conversation participants.
  - Corrected the investigation manifest join plan so `leftSource` records the
    source step (`identity`) rather than duplicating the left key path.
  - Strengthened `tests/integration/AgentInvestigation.Tests.ps1` to assert the
    join-plan shape and repaired the name-resolution mock.
  - Updated `README.md`, `docs/ONBOARDING.md`, `docs/training/Training.md`,
    `docs/ROADMAP.md`, and `docs/READINESS_REVIEW.md` so investigations are
    documented as first-class and the verified Track B gates are current.

## 2026-04-29

### Changed

- **Mirror-catalog consolidation / canonical catalog cutover (Release 1.0 Track A):**
  - `catalog/genesys.catalog.json` is now the single canonical catalog for Genesys.Core,
    Genesys.Ops, scripts, tests, docs, and examples. The deprecated
    `genesys-core.catalog.json` stub and its legacy auto-discovery fallback in
    `Resolve-Catalog` have been retired. If no catalog is found at the canonical path
    (and no explicit `-CatalogPath` is given) `Resolve-Catalog` throws.
  - `-StrictCatalog` is retained on `Resolve-Catalog`, `Assert-Catalog`, `Invoke-Dataset`,
    `Get-AuditServiceMapping`, and bridge/smoke scripts as a backward-compatible no-op;
    it may be removed in a future major version.
  - Updated `catalog/schema/genesys.catalog.schema.json` `$id` to match the canonical
    file name (`genesys.catalog.schema.json`).
  - Updated `.agents/AGENTS.md`, builder skill, and `apps/App_Builder_Template.md` to
    reference `catalog/genesys.catalog.json` and `catalog/schema/genesys.catalog.schema.json`.
  - Updated `TESTING.md` catalog-resolution test-category description to reflect
    canonical-only behavior.
  - Marked mirror-catalog consolidation done in `docs/ROADMAP.md`.

- **Track A — Workflow auth wiring (Release 1.0):**
  - Added `.github/workflows/dataset.on-demand.yml` — a live-credential on-demand workflow
    that authenticates via the OAuth 2.0 client-credentials grant (`GENESYS_CLIENT_ID`,
    `GENESYS_CLIENT_SECRET`, `GENESYS_REGION` repository secrets), runs any catalog dataset
    via `Invoke-Dataset`, and uploads the run artifact. Distinct from the CI mock run.
  - Workflow validates that all required secrets are present before attempting authentication
    and emits a clear error message listing missing secrets.

- **Track A — Redaction baseline coverage (Release 1.0):**
  - Five named redaction profiles added to `catalog/genesys.catalog.json`
    (`profiles.redaction`): `agent-investigation-users`, `agent-investigation-division`,
    `agent-investigation-presences`, `agent-investigation-activity`, and
    `agent-investigation-conversations`.
  - All seven Agent Investigation datasets now carry `redactionProfile` and
    `validationStatus: "unvalidated"` fields in the catalog:
    `users`, `users.division.analysis.get.users.with.division.info`,
    `routing.get.all.routing.skills`, `routing-queues`,
    `users.get.bulk.user.presences`, `analytics.query.user.details.activity.report`,
    and `analytics-conversation-details-query`.
  - `Protect-RecordData` in `Genesys.Core/Private/Redaction.ps1` extended with an optional
    `-Profile` parameter (hashtable with `removeFields`). Profile-driven removal takes
    precedence over the heuristic field-name check; existing callers that pass no profile
    are unaffected.
  - `Resolve-DatasetRedactionProfile` helper added to `Redaction.ps1` — looks up a
    dataset's named profile from `catalog.profiles.redaction` and returns it as a
    hashtable.
  - All three `Protect-RecordData` call sites in `Datasets.ps1` (`Invoke-AuditLogsDataset`,
    `Invoke-SimpleCollectionDataset`, `Invoke-AnalyticsConversationDetailsDataset`) now
    resolve and pass the catalog redaction profile.
  - Profile-driven redaction tests and `Resolve-DatasetRedactionProfile` tests added to
    `tests/unit/Security.Redaction.Tests.ps1`.

- **Track A — Formal production-readiness gate (Release 1.0):**
  - `docs/READINESS_REVIEW.md` rewritten as a verifiable per-criterion checklist
    (nine categories, 30+ criteria) covering auth, dataset execution, paging, retry,
    redaction, artifact contract, workflow/CI, live validation, and the Track B gate.
    Each criterion carries a status (✅ / ⚠️ / ❌ / 🔒) and a "verifiable by" action
    for reviewers. The previous narrative review is archived at the bottom of the file.

- **Track A — OAuth async orchestration decision (Release 1.0):**
  - Explicit deferral recorded in `ROADMAP.md`: the `oauth.post.client.usage.query` /
    `oauth.get.client.usage.query.results` two-step is adequately served by sequencing
    the existing generic catalog dataset pair; no curated handler is needed for 1.0.



### Added

- **ConversationAnalyser Session 19 — Quality and Voice-of-Customer Overlay:**
  - `Get-QualityOverlayReport` added to `App.CoreAdapter.psm1` — pulls `quality.get.evaluations.query` (fan-out by case agent), `quality.get.surveys`, `speechandtextanalytics.get.topics`, and `analytics.post.transcripts.aggregates.query` into a `report-quality-<timestamp>` folder map.
  - Schema bumped to **v11** with `report_evaluations`, `report_surveys`, and `report_quality_topics` plus supporting indexes.
  - `Get-CaseAgentUserIds`, `Import-QualityOverlayReport`, `Get-QualitySummary`, `Get-QualityAgentScoreRows`, `Get-QualitySurveyQueueRows`, `Get-LowScoreConversationRows`, `Get-QualityCorrelationSummary`, and `Get-LowScoreTopicRows` added to `App.Database.psm1`.
  - Evaluation scores normalize to a 0–100 scale from available form totals; survey import extracts NPS, CSAT-style totals, and free-text verbatim answers; transcript topic overlays stay optional and local to the case store.
  - **"Quality" tab** added to `MainWindow.xaml`: Pull Report button, KPI summary bar, agent score distribution grid, queue survey grid, low-score conversation grid, correlation panel, and low-score topic grid.
  - `_StartQualityOverlayReportJob`, `_RenderQualityGrid`, and `_OpenLowScoreConversation` added to `App.UI.ps1`; low-score conversations drill into the existing conversation detail workspace.
  - Quality-specific compliance and architecture checks added to the ConversationAnalyser test runner.

## 2026-04-17

### Added

- **ConversationAnalyser Session 17 — IVR and Flow Containment Report:**
  - `Get-FlowContainmentReport` added to `App.CoreAdapter.psm1` — pulls `analytics.query.flow.aggregates.execution.metrics`, `flows.get.all.flows`, `flows.get.flow.outcomes`, and `flows.get.flow.milestones` into a report folder map.
  - Schema bumped to **v8** with `report_flow_perf` and `report_flow_milestone_distribution` plus supporting indexes.
  - `Import-FlowContainmentReport`, `Get-FlowPerfRows`, `Get-FlowMilestoneRows`, `Get-FlowContainmentSummary`, and `Get-FlowQueueRouteRows` added to `App.Database.psm1`.
  - Containment and failure summaries are weighted by flow entries; queue correlation reads already-imported conversation detail data without adding a frontend API path.
  - **"Flow & IVR" tab** added to `MainWindow.xaml`: Pull Report button, flow-type filter, summary bar, flow performance grid, milestone grid, and queues-reached grid.
  - `_StartFlowContainmentReportJob`, `_RenderFlowContainmentGrid`, and `_RenderSelectedFlowDetail` added to `App.UI.ps1`; Transfer and Flow tabs now clear stale rows when the case store is offline or no active case is selected.
  - Flow-specific compliance and architecture checks added to the ConversationAnalyser test runner.

- **ConversationAnalyser Session 16 — Transfer and Escalation Chain Intel:**
  - Schema bumped to **v7** with `report_transfer_flows` and `report_transfer_chains` plus supporting indexes.
  - `Import-TransferReport` added to `App.Database.psm1` — imports the transfer aggregate run folder, derives transfer chains from stored `participants_json`, classifies blind versus consult transfers, and upserts flow and chain rows.
  - `Get-TransferFlowRows`, `Get-TransferChainRows`, and `Get-TransferSummary` added for grid reads and summary roll-ups.
  - Transfer import denominator handling now matches the catalog-backed metrics: it supports `nOffered` when present, otherwise falls back to `nConnected`, then `nTransferred`, then local hop totals.
  - Hardened transfer flow aggregation so name-only queue touches use stable `name:<queueName>` row keys instead of collapsing into one empty-ID bucket.
  - **"Transfer & Escalation" tab** added to `MainWindow.xaml`: Pull Report button, blind/consult filter, summary bar, flow grid, top destination grid, and multi-hop conversation grid.
  - `_StartTransferReportJob`, `_RenderTransferGrid`, and `_OpenTransferChainConversation` added to `App.UI.ps1`; selecting a multi-hop conversation opens the existing drilldown view.
  - Transfer-specific compliance and architecture checks added to the ConversationAnalyser test runner.

## 2026-04-15

### Added

- **ConversationAnalyser Session 15 — Agent Performance Aggregate Report:**
  - `Get-AgentPerformanceReport` added to `App.CoreAdapter.psm1` — pulls `analytics.query.conversation.aggregates.agent.performance`, `analytics.query.user.aggregates.performance.metrics`, and `analytics.query.user.aggregates.login.activity` for the case time window and returns an `{AgentPerfFolder, UserPerfFolder, LoginActivityFolder}` hashtable.
  - `Import-AgentPerformanceReport` added to `App.Database.psm1` — merges the three JSONL outputs by `userId`, resolves user names, emails, departments, and division names from ref tables, resolves handled queue names from the conversations store, computes `talk_ratio_pct` (tTalk / tHandle × 100), `acw_ratio_pct` (tAcw / tHandle × 100), and `idle_ratio_pct` (tIdle / totalTime × 100), and upserts into `report_agent_perf`.
  - `Get-AgentPerfRows` and `Get-AgentPerfSummary` added to `App.Database.psm1` for grid reads and summary-bar roll-ups.
  - Schema bumped to **v6** — adds `report_agent_perf` table with three indexes.
  - **"Agent Performance" tab** added to `MainWindow.xaml`: header card with Pull Report button and Division filter, summary bar (Agents, Connected, Avg Handle, Avg Talk %, Avg ACW %, Avg Idle %), 16-column `DgAgentPerf` DataGrid with ⚠ flag column (talk ratio < 50 % or ACW ratio > 30 %).
  - `_StartAgentPerfReportJob`, `_RenderAgentPerfGrid`, `_PopulateAgentPerfDivisionFilter` added to `App.UI.ps1`; division filter repopulates from the database after each import and on case activation.


### Added

- **ConversationAnalyser Session 14 — Queue Performance Aggregate Report:**
  - `Get-QueuePerformanceReport` added to `App.CoreAdapter.psm1` — pulls `analytics.query.conversation.aggregates.queue.performance`, `analytics.query.conversation.aggregates.abandon.metrics`, and `analytics.query.queue.aggregates.service.level` for the case time window and returns a `{QueuePerfFolder, AbandonFolder, ServiceLevelFolder}` hashtable.
  - `Import-QueuePerformanceReport` added to `App.Database.psm1` — merges the three JSONL outputs by `queueId|intervalStart`, resolves queue and division names from ref tables, computes `abandon_rate_pct` and `service_level_pct`, and upserts into `report_queue_perf`.
  - `Get-QueuePerfRows` and `Get-QueuePerfSummary` added to `App.Database.psm1` for grid reads and summary-bar roll-ups.
  - Schema bumped to **v5** — adds `report_queue_perf` table with four indexes.
  - **"Queue Performance" tab** added to `MainWindow.xaml`: header card with Pull Report button and Division filter, summary bar (Queues, Offered, Abandoned, Avg Abandon %, Avg SLA 30s %, Avg Handle), 13-column `DgQueuePerf` DataGrid.
  - `_StartQueuePerfReportJob`, `_RenderQueuePerfGrid`, `_PopulateQueuePerfDivisionFilter` added to `App.UI.ps1`; division filter repopulates from the database after each import and on case activation.



### Added

- **Genesys.Ops — Phase 5 Ideas 27–30:** Four new composite cmdlets completing the Phase 5 Visibility Dashboard roadmap:
  - `Get-GenesysPeakHourLoad` — ranks queue+media intervals by volume or handle time to surface WFM scheduling gaps (PT1H granularity; PT15M documented as future direct catalog body override).
  - `Get-GenesysChangeAuditFeed` — risk-classified (HIGH/MEDIUM/LOW) feed of admin configuration changes from the audit log; enriches each event with a human-readable `Summary` and `Risk` field.
  - `Get-GenesysOutboundCampaignPerformance` — per-campaign KPI snapshot combining campaign configuration with dialer event dispositions (ConnectRate, NoAnswerRate, TotalAttempts, etc.).
  - `Get-GenesysFlowOutcomeKpiCorrelation` — correlates Architect flow aggregate execution metrics with org-wide CSAT scores and queue handle time to identify IVR self-service drop-off candidates.

- **ConversationAnalyser Session 13 — Reference Data Foundation:**
  - `Refresh-ReferenceData` added to `App.CoreAdapter.psm1` — invokes `Invoke-Dataset` for all nine reference datasets (`routing-queues`, `users`, `authorization.get.all.divisions`, `routing.get.all.wrapup.codes`, `routing.get.all.routing.skills`, `routing.get.all.languages`, `flows.get.all.flows`, `flows.get.flow.outcomes`, `flows.get.flow.milestones`) and returns a folder map.
  - `Import-ReferenceDataToCase` added to `App.Database.psm1` — upserts reference records into eight new reference tables scoped by `case_id` with `refreshed_at` timestamps; audits the refresh event.
  - `Get-ResolvedName` helper added to `App.Database.psm1` — pure SQLite ID→name lookup with `-Type` (queue, user, division, wrapupCode, skill, flow, flowOutcome, flowMilestone) and `-Id` parameters.
  - Schema v4 adds eight reference tables and their indexes to the SQLite case store.
  - "Refresh Reference Data" button added to the case management panel in `MainWindow.xaml`; wired via `_StartRefreshReferenceDataJob` in `App.UI.ps1` which runs the fetch in a background runspace and shows record counts in the status bar on completion.

### Changed

- `ROADMAP.md` — Phase 5 Ideas 27–30 marked ✅ Delivered with cmdlet names and notes.
- `ConversationAnalytics_Roadmap.md` — Session 13 marked **COMPLETE** with delivery summary.



### Changed

- Documentation modernization pass (Batch 1):
  - Updated `README.md` repository layout to match actual structure (added `Genesys.Auth`, `Genesys.Ops`, `apps/ConversationAnalysis`; corrected test paths to `tests/unit/`); removed non-doc "Topics to Add on GitHub" and "Alternative Names" sections; added cross-link to `TESTING.md`; fixed `AGENTS.md` reference path.
  - Updated `TESTING.md` test file paths from `tests/` to `tests/unit/`; corrected stale caveat about script-level parameter exposure; fixed `AGENTS.md` link.
  - Updated `docs/ONBOARDING.md` with Table of Contents and a new Conversation Analysis app section.
  - Rewrote `docs/REPO_SCHEMATIC.md` tree to match actual repository structure (removed phantom root shims, added `apps/`, `Public/Assert-Catalog.ps1`, `Http/`; added Conversation Analysis to Canonical Defaults).
  - Updated `docs/READINESS_REVIEW.md` to correct stale caveat about script-level `-Headers`/`-BaseUri` exposure.



### Changed

- Reconciled repository documentation with current runtime behavior and catalog coverage.
- Updated `README.md` to reflect current dataset/endpoint counts and clarified that the repo is a Core runtime (not a packaged MCP server).
- Added explicit onboarding guide at `docs/ONBOARDING.md` with authenticated module-first usage.
- Updated readiness review to reflect current implemented scope and current operational caveats.
- Updated roadmap status and added planned endpoint backlog:
  - `GET /api/v2/authorization/roles`
  - `GET /api/v2/conversations/{conversationId}/recordings`
  - `GET /api/v2/oauth/clients`
  - `POST /api/v2/oauth/clients/{clientId}/usage/query`
  - `GET /api/v2/oauth/clients/{clientId}/usage/query/results/{executionId}`
  - `GET /api/v2/speechandtextanalytics/topics`
  - `POST /api/v2/analytics/transcripts/aggregates/query`
  - `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/communications/{communicationId}/transcripturl`
- Updated testing documentation with onboarding references and current workflow/artifact/auth caveats.

## 2026-02-18

### Added

- Added dataset implementations for `users` and `routing-queues` with catalog registration, paging-aware ingestion, normalization, and tests.
- Added smoke script `scripts/Invoke-Smoke.ps1` to run catalog validation and fixture-backed dataset ingests.

### Changed

- Introduced unified catalog loader (`Resolve-Catalog`) and canonical in-memory normalization.
- Canonical runtime precedence is now `catalog/genesys.catalog.json`.
- Added strict catalog mode (`-StrictCatalog`) to fail when canonical catalog is missing.

### Migration notes

- Ensure the canonical catalog is present:
  - `catalog/genesys.catalog.json`
- Existing callers passing `-CatalogPath` remain supported.
