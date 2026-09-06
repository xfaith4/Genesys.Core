# Genesys Data Client

Customizable data exploration, analysis, reporting and visualization built on Genesys.Core.

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
npm run build
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
| Export | — | CSV, JSON, NDJSON, Markdown, with provenance |
| Saved views | — | Filters, sort and column layout, remembered |

The Genesys skin is modelled on the publicly documented behaviour of the new Genesys Cloud
unified navigation: a unified global menu, a top bar carrying consistent page titles, a back
button and relocated Collaborate, Inbox and User Avatar elements, and a global search that
returns menu pages alongside people, groups and locations. Genesys has not published the visual
specification, so it is an approximation of that described structure, not a pixel-accurate copy.

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
