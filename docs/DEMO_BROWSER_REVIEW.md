# Browser demo review — 2026-10-11

Completed an interactive walkthrough in headed Chromium, reproduced defects, applied
corrective changes, and repeated the affected flows. This is local demo evidence using
the real mock server, not live Genesys Cloud acceptance.

## What was demonstrated

1. Sign in through the mock authorization consent page using the actual PKCE exchange.
2. Retrieve all 10 demo users across two pages; search for Alice and expand a record.
3. Change columns, switch between Genesys and Atlas, and save/apply a filtered view.
4. Create an aggregate report, change its metric field, group by department, and download JSON.
5. Retrieve five conversations through the async job and both cursor result pages; download CSV.
6. Discover an endpoint, inspect its details and execute `GET /api/v2/users/me` (HTTP 200).
7. Inject a discovery HTTP 503, check error presentation, remove the injection and retry.
8. Exercise Back/Forward, Help, search feedback, and both menus at 390 × 844.
9. Open the standalone conversation investigation report and inspect its summary,
   findings, timeline, SIP breakdown and evidence sections at desktop/mobile widths.

## Issues and corrective changes

| Issue reproduced | Correction | Evidence after correction |
| --- | --- | --- |
| Switching skins changed a filtered selection from 1/10 users to 10/10 and reset report/column state. | Workspace-owned in-memory drafts retain each source's query, columns, view name and report definition across page/skin remounts. | Both skin directions retain Alice, the hidden Name column and the report metric; saved-view application restores the filter. |
| Back remained disabled after menu navigation. | App owns the history index; navigation uses `pushState` and responds to browser hash history. | Back returns from Routing queues to Users; browser Forward returns to Routing queues. |
| Changing an Average metric from a numeric field to Name displayed Count in the selector but still calculated Average of Name with an empty result. | Normalize numeric-only aggregates to Count when selecting a nonnumeric field. | Selector, heading and exported metric all agree on Count of Name = 1 for the filtered record. |
| JSON exports omitted active filters; report JSON also omitted collection evidence, warnings, metric definitions and the filtered population. | Shared JSON provenance includes filters, units, row count and collection metadata. Report JSON also includes metric definitions and total input records. Explorer passes actual filters to the report export. | Downloaded JSON files were parsed and checked for Alice's filter, requests/warnings, one input record and an identifiable Count metric. Three regression tests cover the serializer contract. |
| A discovery outage silently retained results from the previous filter, along with its old request runner. | Explicit loading/error/retry states clear stale results and detail; obsolete detail requests are cancelled. | Injected 503 shows an error and Try again, without old users/me results or runner. Retry retrieves routing queue endpoints using the current filter. |
| Mobile navigation labels stayed hidden regardless of the expansion control. | Both skins use an expandable overlay at narrow widths, with explicit accessible destination names; selecting a destination closes the menu. | Both menus visibly expand at 390px; navigation succeeds without page-level horizontal overflow. |
| Header search advertised people/groups although it only searched pages; Help/Inbox/Collaborate were inert and queue status was only a local toggle. | Label the search as Search pages, show empty-result feedback, make Help open Getting started, and remove the unsupported agent controls. | Alice yields an explicit no-pages message; Help navigates; unsupported buttons are absent. |
| Data Client requested a missing favicon on a fresh visit. | Add an inline SVG favicon. | Corrected-client console errors during the final walkthrough were only the two deliberately injected 503 responses. |
| Standalone report's wide SIP/evidence tables forced the whole page to scroll horizontally. | The generator and supplied sample use named, keyboard-focusable horizontal scrolling regions around tables, with narrow-screen padding and header wrapping. | Page width stays within both 1440px and 390px viewports. Package export tests and fresh demo generation pass. |
| Build-and-host instructions ran the root-relative mock project command while still in the app directory. | Return to the repository root before starting the server; align help/docs with supported controls and draft lifetime. | README command paths and navigation descriptions match the corrected implementation. |

Saved-view application also restores the saved density preference.

## Validation

| Check | Result |
| --- | --- |
| Data Client unit/integration suite against the running mock | **78 passed**, 6 files |
| TypeScript check and production build | **Passed** |
| Existing rendered axe audit | **15 surfaces, 0 violations** |
| Conversation package integration suite | **7 passed** |
| Fresh offline conversation package generation | **Passed**; HTML, JSON, CSV, XLSX and demo PCAP artifacts produced |
| Browser assertions | Passed for explorer/report state, navigation/mobile menus, discovery error/retry, async paging, downloads and standalone report widths |
| Download contents | **1** filtered user; **1** grouped report input record with Count metric; **5** conversation CSV records |
| Changed-file whitespace checks | **Passed** with the repository's CRLF convention |

The accessibility audit covers the app's existing 15 desktop surfaces. Narrow-screen
checks here exercised navigation, visible labels and overflow; they are not a complete
mobile accessibility audit.

## Review the artifacts

Artifacts are local under [`output/playwright`](../output/playwright/).

- [Corrected filtered Users screen](../output/playwright/35-demo-final.png)
- [Corrected grouped report](../output/playwright/27-report-after.png)
- [Mobile menu before](../output/playwright/07-mobile-before.png) and [Atlas menu after](../output/playwright/20-atlas-mobile-after.png)
- [Genesys mobile menu after](../output/playwright/19-genesys-mobile-after.png)
- [Discovery outage handling](../output/playwright/22-discovery-outage-after.png) and [successful recovery](../output/playwright/23-discovery-recovered-after.png)
- [Standalone report before](../output/playwright/30-static-conversation-report.png), [desktop after](../output/playwright/32-static-report-after.png), and [mobile after](../output/playwright/33-static-report-mobile-after.png)
- [Filtered user JSON](../output/playwright/users-filtered-after.json), [report JSON](../output/playwright/users-report-after.json), and [conversation CSV](../output/playwright/conversations-after.csv)
- [Download validation](../output/playwright/download-validation.json)
- [Freshly generated conversation package](../output/playwright/generated-conversation-package/demo-conversation-investigation.html)

`verify-explorer.js`, `verify-navigation.js`, `verify-discovery.js`, `verify-downloads.js`
and `verify-static-report.js` in that directory record the assertions used in this
browser session. They are walkthrough artifacts with scenario-specific starting states,
not a new CI browser suite. Before/after accessibility snapshots are retained alongside them.

## Environment and boundaries

Used the installed Windows .NET 8 SDK and Windows Node 24.13.1 because the existing
frontend dependency tree contains Windows native bindings. The first Linux Vite start
failed on its missing Linux rolldown binding; the dependencies and lockfile were preserved.
A temporary TCP forward let headed Linux Chromium reach Windows Vite at
`http://localhost:5173`. The generic sample HTTP server is on WSL localhost:8787.

The first accessibility invocation checked the API-only mock origin because an environment
variable did not cross WSL/Windows. Rerunning with the frontend origin explicitly set in
Windows Node passed. The sample HTTP server's automatic favicon request returns a cosmetic
404; this does not occur in the corrected Data Client.

Unsaved drafts remain in memory and reset on a full reload; saved views persist. The
Genesys skin intentionally keeps a restricted layout, while Atlas exposes reports and
exports. NDJSON retains its existing record-stream contract without embedded provenance.

This walkthrough did not validate a real tenant, deployed application, physical mobile
device or every catalog endpoint. The PowerShell Core's adaptive rate limiter remains
separate from the browser client's direct fetch path. No live rate-limit acceptance is
claimed by this browser review. Existing unrelated workspace edits were preserved; no
commit, publication or deployment was performed.
