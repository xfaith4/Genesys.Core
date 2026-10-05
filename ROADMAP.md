# Genesys.Core roadmap

Updated 2026-09-15. This is the priority entry point. Detailed implementation history and
release gates remain in [docs/ROADMAP.md](docs/ROADMAP.md). Business rationale is in
[Product value](docs/PRODUCT_VALUE.md), and reconciliation evidence is in
[Repository reconciliation](docs/REPOSITORY_RECONCILIATION.md).

## Current product

Governed Genesys Cloud collection, subject-based investigations, and portable evidence
packages. The highest-value existing workflow is conversation investigation and evidence
export. The React Genesys Data Client is the preferred foundation for future web features;
the Windows ConversationAnalyzer retains distinct case storage and reporting capabilities.

## Repository consolidation

- [x] Preserve the interrupted merge and local files in an external recovery archive.
- [x] Resolve the merge and incorporate GitHub main through `65e39c5`.
- [x] Restore the modern Data Client and upstream cleanup of duplicated Core/build outputs.
- [x] Inventory unmerged branches and preserve recent proposals with explicit status.
- [x] Replace unrelated site-starter roadmap content and correct obsolete app paths.
- [ ] Publish the reviewed reconciliation to GitHub.

## Next release: queue incident evidence

- [ ] Validate current Core/investigation endpoints, permissions and output against a tenant.
- [ ] Implement audit-change / queue-performance correlation with a comparable baseline.

  Implementation contract (so the item can be built and reviewed without guessing):
  - **Entry point:** `Get-GenesysQueueChangeCorrelation` in `modules/Genesys.Ops/Genesys.Ops.psm1`,
    following the `Get-GenesysQueueInvestigation` pattern (run-artifact set, manifest,
    `-DatasetInvoker` test seam so no live calls are needed).
  - **Inputs:** `-QueueId` (required), `-IncidentStart`/`-IncidentEnd` (UTC), `-BaselineStart`/
    `-BaselineEnd` (optional; default is the same length and weekday alignment immediately
    before the incident), `-DisplayTimeZone` (display only; all joins use UTC).
  - **Data sources (existing catalog datasets only):** `audits.query.audit.logs.user.actions`
    (Queue/Flow/RoutingQueue/Authorization changes), `routing-queues`,
    `analytics.query.conversation.aggregates.queue.performance`,
    `analytics.query.queue.aggregates.service.level`,
    `analytics.query.conversation.aggregates.abandon.metrics` — see
    `investigationRecipes.change-to-incident-correlation` in `catalog/genesys.catalog.json`.
  - **Output (`summary.json`):** per candidate change — audit record ID, actor, timestamp,
    property before/after, baseline vs incident `nOffered`, `nConnected`, `tHandle` (divided by
    its own count), service level and abandon rate, sample sizes, and an `association` field
    labelled `hypothesis`, never `cause`. Missing or permission-denied sources are listed in
    `warnings[]`, never silently dropped.
  - **Fixtures and tests:** `tests/integration/QueueChangeCorrelation.Tests.ps1` covers no
    incident, related change, unrelated change, late data, partial permissions, repeated
    collection (byte-equivalent output after stripping run IDs/timestamps), and a timezone/DST
    boundary — the first acceptance gate in [Product value](docs/PRODUCT_VALUE.md).
  - **Out of scope:** Data Client UI (next item), export packaging (item after), tenant
    validation (first item; needs credentials), flow-triggered correlation.
  - **Done means:** the Pester file above passes, existing suites still pass, and the
    catalog/`Catalog.CombinationReferences` test is unchanged and green.
- [ ] Add incident selection and evidence drilldown to the Data Client.
- [ ] Export timestamps, filters, metric denominators, missing-source warnings and evidence.
- [ ] Complete a pilot measuring operator investigation time and evidence completeness.

See [acceptance gates](docs/PRODUCT_VALUE.md#recommended-next-release-explain-what-changed-when-service-deteriorated).

## Following opportunities

1. Repeat-contact, transfer-loop, and failed-handoff analysis.
2. Scheduled business-unit scorecards with stable KPI definitions.
3. Configuration drift and division-access evidence.
4. Bot/AI outcome and cost assurance.
5. Voice/integration incident triage and an evidence-grounded investigation assistant.

Catalog recipes and remote proposals remain design inputs until implemented and tested.
Local fixture, browser, and static checks do not close tenant, Windows UI, or operator gates.
