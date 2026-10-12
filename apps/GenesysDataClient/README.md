# Genesys Data Client

An operations investigation frontend built on Genesys.Core collection and Genesys.Ops analysis.

Start with **Conversation investigation** (`#/investigation`) to import an Ops `analysis.json`,
filter incident cohorts, summarize the entire filtered population and inspect timelines.
The home page organizes work around Investigate, Measure and Explain; endpoint discovery
supports raw diagnostics. Monthly reconciliation currently runs through its
[PowerShell launcher](../MonthlyMetrics/README.md), rather than a dedicated client page.

The browser generates collection commands; run them in a connected Ops PowerShell session.
Its direct API client does not automatically inherit Core PowerShell adaptive pacing.
See the [population guide](../../docs/CONVERSATION_POPULATION_ANALYSIS.md) and
[measured performance limits](../../docs/CONVERSATION_POPULATION_PERFORMANCE.md).

It deliberately does **not** reproduce the agent, supervisor or administrative workflows of the
native Genesys Cloud client. It centres on the data instead:

```text
                       DATA
                        │
        ┌───────────────┼───────────────┐
        │               │               │
     Explore         Analyze          Build
        │               │               │
    records          metrics         reports
    objects          trends          dashboards
    APIs             correlations    exports
    events           anomalies       views
```

## Node is not a Genesys.Core dependency

This application owns its frontend toolchain. Genesys.Core stays free of Node, npm, React and
Vite; `node_modules/` and `dist/` are both git-ignored, and CI produces `dist/` as a release
artifact. See [docs/GenesysDataClient.md](../../docs/GenesysDataClient.md) for the architecture
decision behind this.

## Running it

Use Node.js 24 LTS (`nvm use` in this directory) and .NET SDK 8 for the demo server.

Start the offline Genesys.Core implementation from the repository root:

```bash
dotnet run --project tools/Genesys.MockServer
```

Then either develop against it with hot reload:

```bash
cd apps/GenesysDataClient
npm install
npm run dev          # http://localhost:5173, proxied to the demo server
```

…or build once and let the demo server host the result, which needs no Node at runtime:

```bash
# From apps/GenesysDataClient:
npm run build
cd ../..
dotnet run --project tools/Genesys.MockServer
# open http://localhost:7777
```

The demo server serves `apps/GenesysDataClient/dist/` automatically when that folder contains an
`index.html`. Override the location with `MOCK_STATIC_ROOT`.

## Authentication

One flow, two destinations: **OAuth 2.0 Authorization Code with PKCE**. There is no client secret
anywhere in this application, which is the point of PKCE for a browser client.

| | Demo | Live Genesys org |
| --- | --- | --- |
| Authorize | `/oauth/authorize` on the demo server | `https://login.{region}/oauth/authorize` |
| Token | `/oauth/token` on the demo server | `https://login.{region}/oauth/token` |
| API | same origin | `https://api.{region}` |
| Identity | fixed demo user, no credentials collected | your org's sign-in |
| Client code | identical | identical |

The demo authorization server implements PKCE **for real**: it verifies `BASE64URL(SHA256(verifier))`
against the stored challenge, refuses `plain`, refuses a request with no challenge, treats
authorization codes as single-use, and rotates refresh tokens. A wrong verifier is rejected. Demo
mode therefore exercises the same code path that runs against a live org rather than bypassing it.

What the demo server does **not** do is authenticate anybody. Its consent screen has no username or
password field and says so; approving simply issues a code bound to the challenge.

### Implementation notes

- The verifier is 32 random bytes as base64url and the challenge is `S256`, matching
  [`modules/Genesys.Auth`](../../modules/Genesys.Auth/Genesys.Auth.psm1) so both consumers work
  against the same OAuth client registration. `tests/auth.test.ts` pins the derivation to the
  RFC 7636 Appendix B worked example.
- The verifier never travels in a URL. It is held in `sessionStorage` for the duration of the
  redirect and cleared on return.
- `state` is generated per request and checked on return; a mismatch aborts the sign-in.
- Tokens live in `sessionStorage`, so they are scoped to the tab and cleared when it closes. Only
  non-secret preferences (environment, client id) go to `localStorage`.
- Access tokens are refreshed automatically ~2 minutes before expiry when a refresh token is held,
  with the same 30-second expiry margin `Genesys.Auth` applies.
- The UI never renders a whole token — only a short prefix, verified by the browser suite.

### Connecting to a real org

Register a **Token Implicit Grant (Code)** OAuth client in Genesys Cloud with PKCE enabled and add
this application's origin (for example `http://localhost:7777/`) as an authorized redirect URI.
Then pick the region on the sign-in screen and enter the client id. Any region suffix can be typed
in if it is not in the built-in list.

Untested against a live org — no tenant was available. The flow is verified end to end against the
demo authorization server, and the parameters match the PowerShell implementation that does run
against live orgs.

## Architecture

Three layers, deliberately separated so the application cannot collapse into a pile of
hard-coded screens.

| Layer | Knows | Lives in |
| --- | --- | --- |
| Genesys.Core | How to talk to Genesys Cloud | The repository outside this app |
| Data Client engine | What a user can do with data | `src/engine/`, `src/components/` |
| Feature modules | A particular problem domain | `src/features/` |

### The primitives

Defined in [`src/core/contracts.ts`](src/core/contracts.ts). Getting these right is what lets the
existing purpose-built consoles donate capabilities to this application over time.

| Primitive | Purpose |
| --- | --- |
| `DataSource` | A named, retrievable collection of Genesys records plus its field metadata |
| `QueryDefinition` | What to retrieve, and how to search, filter, sort and group it |
| `ViewDefinition` | A saved query plus a column layout |
| `ReportDefinition` | An ad-hoc aggregation: group by anything, aggregate anything |
| `DashboardDefinition` | Tiles referencing saved views and reports |
| `ExportDefinition` | Format, column selection, scope and provenance for an extract |
| `Workspace` | Everything the user personalized, persisted between sessions |

### Adding a data source

Adding an explorer means adding a `DataSource` to `src/core/sources.ts` — never a new screen. The
generic explorer, the filter and column pickers, the report builder, export, saved views and both
skins' navigation all derive from the source's `FieldDefinition[]`.

## The two skins

The same application, the same data, two interface philosophies. Switch from the header.

| | **Genesys** | **Atlas** |
| --- | --- | --- |
| Navigation | Unified global menu, top bar with page title and back button | Collapsible, filterable rail |
| Theme | Light only | Light, dark or system |
| Layout | Fixed — the product's arrangement | Panels move and collapse; order persists |
| Columns | Sort and filter | Sort, filter, reorder, resize, hide |
| Reporting | — | Ad-hoc grouping and aggregation |
| Export | — | CSV, JSON, Markdown with optional provenance; NDJSON data rows |
| Saved views | — | Filters, sort and column layout, remembered |

The Genesys skin uses a unified global menu, page titles, working Back navigation,
page search and a Help shortcut to Getting started. It approximates Genesys-inspired
navigation without exposing agent queue controls, collaboration or an inbox.

Its constraints are intentional. It exposes no theme, density or layout control, which is the
baseline Atlas is measured against.

## Endpoint explorer

The endpoint outline is read live from the demo server's `/__meta` discovery API rather than
being hard-coded or bundled from the 1.6 MB catalog. The server derives that metadata from the
same coverage table its dispatcher executes, so the outline can never claim demo data the server
would not actually return. Any endpoint can be run in place, with route parameters and request
bodies prefilled from the catalog.

## Tests

```bash
npm test          # unit + integration
npm run test:a11y # WCAG 2.1 AA gate, needs a build and a running demo server
```

- `tests/query.test.ts` — engine behaviour: filtering, type-aware sorting, aggregation, export
- `tests/export-fidelity.test.ts` — CSV is a machine-reuse artifact: ISO 8601 timestamps, raw
  millisecond durations, unformatted numbers, and formula-injection neutralization
- `tests/auth.test.ts` — PKCE derivation against the RFC 7636 vector, authorize URL shape,
  environment resolution, redirect parsing
- `tests/auth.integration.test.ts` — the client's own PKCE functions driven against the demo
  authorization server, including wrong-verifier, code-replay, refresh-rotation and denial cases
- `tests/route.test.ts` — hash routing
- `tests/sources.integration.test.ts` — every data source driven over HTTP against a running
  demo server, including the async job lifecycle and cursor paging
- `tests/accessibility.mjs` — axe-core against the rendered application across both skins, both
  themes and all five accents

Both the integration and accessibility suites **skip visibly** when no demo server is reachable,
so they can never pass without asserting anything. Point them elsewhere with `GDC_MOCK_SERVER`.

## Export formats

CSV and Markdown are deliberately different artifacts. CSV is for machine reuse — ISO 8601 UTC
timestamps, durations as raw milliseconds, numbers without separators, units declared in the
provenance header — so it parses and aggregates in a spreadsheet or a notebook. Markdown is for
reading and keeps the friendly rendering (`14m 27s`). JSON and NDJSON carry the untouched values.

Cells that a spreadsheet would evaluate as a formula are neutralized with a leading apostrophe,
because Genesys data includes free text a person can type.

## Accessibility

The repository's PowerShell analyzer audits static HTML and cannot see this application, whose
markup only exists after React renders. `npm run test:a11y` covers it instead, and the accent
palettes in [`src/core/accents.ts`](src/core/accents.ts) are solved for contrast rather than
picked by eye — each accent ships a graphical shade for fills and separate text-safe shades per
theme.

## Browser demo review

The [2026-10-11 browser review](../../docs/DEMO_BROWSER_REVIEW.md) records the demo
walkthrough, reproduced defects, corrections, screenshots and validation results.
Explorer filters, column selections and report definitions now survive skin and
page changes within the open application. Saved views persist across reloads;
unsaved working drafts stay in memory and reset on reload.


### Conversation investigation

Both skins include **Conversation investigation** (`#/investigation`). Open `analysis.json`
produced by `Get-GenesysConversationAnalysis` to filter, group, summarize and drill into
conversation timelines using the shared portable workbench. The analysis and view remain
in memory through page navigation and skin changes; export before reloading the tab.
Collection commands run in your connected Ops PowerShell session. See
[collection and field definitions](../../docs/CONVERSATION_POPULATION_ANALYSIS.md).


The product direction is composed operations investigations: error cohorts, affected
entities, metric changes and timestamped evidence. See the
[NOC investigation contract](../../docs/NOC_INCIDENT_INVESTIGATIONS.md) for the next
mass-disconnect workflow and complete job/transaction-family gates. Name-resolution
coverage and current user-Division membership are available in Ops analysis artifacts;
historical membership and automated cross-source incident correlation remain open.
