# SereneHarmony Site Starter Roadmap

## Status

![Build Status](https://img.shields.io/badge/build-passing-brightgreen) ![Coverage](https://img.shields.io/badge/coverage-95%25-success)

## Release Index

### v1.0: Initial Release

- [x] Setup basic UI framework
- [x] Finalize homepage design
- [x] Implement primary navigation
- [x] Test responsive layout

### v1.1: User Engagement

- [x] Enable user login/authentication
- [x] Implement user profile management
- [x] Set up email notification system
- [x] Integrate basic user analytics

## Active Release: v1.2

**Goal:** Enhance Accessibility and Performance

- [x] Attain WCAG 2.1 compliance — 2026-09-02
- [ ] Reduce image load times by 30%
- [ ] Integrate lazy loading for offscreen assets
- [ ] Conduct comprehensive performance audit

**Acceptance Criteria:**

- WCAG 2.1 compliance verified with automated tests.
- Image load reduction measured via Lighthouse.
- Lazy load functionality confirmed through network inspection.
- Performance audit results: all critical issues resolved.

### WCAG 2.1 compliance — delivered 2026-09-02

All seven shipped HTML surfaces conform to **WCAG 2.1 Level AA** under the
repository's automated gate. 175 violations were remediated.

| Deliverable | Location |
| --- | --- |
| Static analyzer (25 rules, no Node/npm dependency) | `tools/Genesys.Accessibility/` |
| Audit CLI (non-zero exit on violations) | `scripts/Invoke-AccessibilityAudit.ps1` |
| Surface manifest | `config/accessibility-surfaces.json` |
| Test suite (17 tests) | `tests/unit/Accessibility.Wcag21.Tests.ps1` |
| CI gate | `.github/workflows/ci.yml` → `accessibility` job |
| Conformance statement + manual checklist | `docs/ACCESSIBILITY.md` |

**Verification:**

```powershell
pwsh -NoProfile -File ./scripts/Invoke-AccessibilityAudit.ps1
# PASS - 7 surface(s) conform to WCAG 2.1 Level AA under static analysis.

pwsh -NoProfile -File ./scripts/Invoke-Tests.ps1
# Tests Passed: 203, Failed: 0, Skipped: 1
```

Surfaces were also driven in a real browser to confirm no functional regression:
demo-data load, tab keyboard navigation, filter toggles, table sorting, row
expansion, and diagram rendering.

**Non-blockers carried forward:**

- [non-blocker] Reflow (1.4.10), text spacing (1.4.12), and rendered chart
  contrast (1.4.11) are on the manual checklist in `docs/ACCESSIBILITY.md`;
  they require a rendered viewport that static analysis cannot evaluate.
- [non-blocker] Translucent (`rgba` alpha < 1) backgrounds are skipped by the
  contrast rules because the composited colour depends on an unresolvable
  ancestor. The affected rules were verified by hand and are listed in
  `docs/ACCESSIBILITY.md`.
- [non-blocker] No screen-reader pass has been run; add one NVDA/Narrator pass
  per console before claiming certified conformance.
- [non-blocker] **Pre-existing, unrelated to this work:**
  `tests/integration/MockServer.Integration.Tests.ps1` fails with
  `The term 'Start-MockServer' is not recognized` (13 failures). Verified
  against a clean tree at `77f6c53`: 0 passed / 13 failed before any
  accessibility change. `tests/PesterConfiguration.ps1` sets
  `Run.Path = './tests'`, so the `pester` CI job runs these and is red for this
  reason. The mock-server helper functions are not exported where the test
  expects them.

### Genesys Data Client — delivered 2026-09-05

A customizable data exploration, analysis, reporting and visualization application
built on Genesys.Core, with two skins, per the architecture in
`docs/GenesysDataClient.md`.

| Deliverable | Location |
| --- | --- |
| Application (Vite + React + TypeScript, isolated toolchain) | `apps/GenesysDataClient/` |
| Reusable Data Client primitives | `apps/GenesysDataClient/src/core/contracts.ts` |
| Engine: filter, sort, group, aggregate, export, workspace | `apps/GenesysDataClient/src/engine/` |
| Genesys skin (productized unified navigation) | `apps/GenesysDataClient/src/skins/GenesysSkin.tsx` |
| Atlas skin (user-controlled interface) | `apps/GenesysDataClient/src/skins/AtlasSkin.tsx` |
| Declarative fixture coverage table | `tools/Genesys.MockServer/FixtureCoverage.cs` |
| Discovery API (`/__meta`) | `tools/Genesys.MockServer/MetaApi.cs` |
| CI build + integration jobs | `.github/workflows/ci.yml` |

**Verification:**

```bash
dotnet test tools/Genesys.MockServer/tests/Genesys.MockServer.Tests/Genesys.MockServer.Tests.csproj
# Passed! - Failed: 0, Passed: 24

cd apps/GenesysDataClient && npm test
# Test Files 3 passed (3), Tests 38 passed (38)
```

Driven in a real browser against the built application: 23/23 checks covering both
skins, the endpoint outline and runner, the async job lifecycle, dark mode, accent
and density, column sort and filter, ad-hoc reporting, panel reordering, and
persistence across reload. No page errors.

**Non-blockers carried forward:**

- [non-blocker] The two-tier template structure described in
  `docs/GenesysDataClient.md` (`apps/templates/basic/` and
  `apps/templates/web-react/`) has not been created. The existing
  `apps/App_Builder_Template.md` is untouched. This was scoped as a separate
  concern from the Data Client itself.
- [non-blocker] `DashboardDefinition` is defined as a primitive and persisted in
  the workspace, but no dashboard feature module consumes it yet. Tiles
  referencing saved views and reports are the natural next increment.
- [non-blocker] Column widths are mouse-only. The resize grip has no keyboard
  equivalent; showing, hiding and reordering columns are fully keyboard-operable
  through the Columns panel.
- [non-blocker] Everything is retrieved and processed in the browser. This is
  correct for the demo fixtures and wrong for production Genesys volumes — see
  "Scaling beyond the demo" below.

### Second pass — 2026-09-05

Reviewed the Data Client again and fixed eight defects, each reproduced first.
Details in `docs/CHANGELOG.md`.

| Area | Defect | Resolution |
| --- | --- | --- |
| Export | CSV carried display formatting, so timestamps, durations and numbers did not parse or aggregate | `formatForExport`: ISO 8601, raw milliseconds, unformatted numbers, units declared |
| Export | Cells beginning `=`, `+`, `-`, `@` were written verbatim (formula injection) | Neutralized with a leading apostrophe; genuine numbers untouched |
| Grid | Row expansion keyed by index, so re-sorting showed the wrong record's detail | Keyed by record identity |
| Reports | `min`/`max` of a timestamp rendered as epoch milliseconds | Aggregates inherit their field's type unless they are a tally |
| Navigation | Genesys skin's private history stack desynced from browser back/forward | Delegates to browser history |
| Explorer | Provenance panel showed a hardcoded "Demo data" badge for every endpoint | Shows the catalog key; coverage stays the server's to report |
| Views | A saved view could never see fields added later | `reconcileColumns` merges against the current field set |
| Accessibility | axe-core found contrast failures across both skins | Solved accent palettes, neutral tints, darker `--ink-3`, `:hover` specificity fix |

**Accessibility is now gated.** `npm run test:a11y` drives a browser and runs
axe-core over 13 surfaces — both skins, both themes, all five accents — and
reports **0 violations**. It runs in the `data-client-integration` CI job.

**Verification after the second pass:**

```bash
dotnet test tools/Genesys.MockServer/tests/Genesys.MockServer.Tests/Genesys.MockServer.Tests.csproj
# Passed! - Failed: 0, Passed: 24

cd apps/GenesysDataClient
npm test          # Test Files 4 passed, Tests 48 passed
npm run test:a11y # PASS - 13 surface(s) audited, 0 violation(s)
```

### Third pass — authentication, 2026-09-05

The Data Client now authenticates with **OAuth 2.0 Authorization Code + PKCE**,
and `Genesys.MockServer` gained a demo authorization server so that flow is
exercised offline rather than stubbed.

| Deliverable | Location |
| --- | --- |
| PKCE implementation (challenge, authorize URL, exchange, refresh, storage) | `apps/GenesysDataClient/src/core/auth.ts` |
| Session lifecycle, auto-refresh, redirect completion | `apps/GenesysDataClient/src/app/AuthProvider.tsx` |
| Sign-in screen with region picker | `apps/GenesysDataClient/src/features/SignIn.tsx` |
| Demo authorization server | `tools/Genesys.MockServer/DemoOAuth.cs`, `OAuthApi.cs` |

The client's parameters match `modules/Genesys.Auth/Genesys.Auth.psm1`, so a single
OAuth client registration serves both the PowerShell and browser consumers.

**Verification:**

```bash
dotnet test tools/Genesys.MockServer/tests/Genesys.MockServer.Tests/Genesys.MockServer.Tests.csproj
# Passed! - Failed: 0, Passed: 37

cd apps/GenesysDataClient
npm test          # Test Files 6 passed, Tests 75 passed
npm run test:a11y # PASS - 15 surface(s) audited, 0 violation(s)
```

Driven in a browser: 22/22 auth checks (challenge and state on the authorize URL,
verifier absent from the URL, verifier in sessionStorage only, consent screen with
no credential fields, return authenticated, params stripped, data loading on the
PKCE token, session surviving reload, sign-out clearing token storage while keeping
non-secret preferences) plus the existing 23/23 application checks. No page errors.

**Non-blockers carried forward:**

- [non-blocker] **The live Genesys path is unverified.** No tenant was available, so
  only the demo authorization server has been exercised end to end. The parameters
  match the PowerShell implementation that does run against live orgs, and the
  RFC 7636 test vector pins the challenge derivation, but a first real sign-in
  should still be treated as the actual test. Expect the OAuth client to need
  **Token Implicit Grant (Code)** with PKCE enabled and this app's origin
  registered as a redirect URI.
- [non-blocker] Refresh tokens are held in `sessionStorage`. That is the usual SPA
  compromise and is tab-scoped, but a service-worker or in-memory-only strategy
  would reduce exposure further if this is ever hosted somewhere untrusted.
- [non-blocker] A 401 from an API call does not yet force re-authentication; the
  session is only re-evaluated on the expiry timer. Worth wiring the CoreClient's
  401 path into the AuthProvider.
- [non-blocker] The endpoint explorer depends on `/__meta`, which a live org does
  not serve. It degrades with an explanation rather than failing, but it is a
  demo-server feature.

### Scaling beyond the demo

The current design retrieves a whole dataset and filters, sorts and aggregates it
in the browser. That is the right shape for fixtures numbering in the tens and the
wrong shape for production Genesys volumes. Before this application is pointed at
a live tenant, the following is a redesign rather than a fix:

- [ ] Virtualize the grid; today every row is in the DOM.
- [ ] Push filter, sort and paging into `QueryDefinition` execution so a source
      can choose to satisfy them server-side instead of after retrieval.
- [ ] Stream retrieval incrementally rather than resolving every page before the
      first render.
- [ ] Move aggregation off the main thread once row counts pass a few thousand.
- [ ] Replace the module-level client singleton in `core/sources.ts` with
      injection through context; it is currently global mutable state that only
      works because there is exactly one client.
- [ ] Make saved views, reports and dashboards shareable rather than
      `localStorage`-only.
- [ ] Build the dashboard feature module against the existing
      `DashboardDefinition` primitive.

## Future Releases

### v1.3: Community Features

- [ ] Develop user forums
- [ ] Implement article comment sections
- [ ] Create like/dislike interaction system

### v1.4: Content Library Expansion

- [ ] Add 50 diverse articles
- [ ] Implement content recommendation system
- [ ] Include multimedia content with transcription

### v1.5: Mobile App Launch

- [ ] Develop iOS/Android mobile app
- [ ] Integrate real-time web synchronization
- [ ] Ensure seamless user session transition between app and web.
