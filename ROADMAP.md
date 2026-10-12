# Genesys.Core roadmap

Updated 2026-10-12. This is the priority entry point. Detailed implementation history and
release gates remain in [docs/ROADMAP.md](docs/ROADMAP.md). Business rationale is in
[Product value](docs/PRODUCT_VALUE.md), and reconciliation evidence is in
[Repository reconciliation](docs/REPOSITORY_RECONCILIATION.md).

## Current product

Governed Genesys Cloud collection, subject-based investigations, and portable evidence
packages. The highest-value existing workflow is conversation investigation and evidence
export. The React Genesys Data Client is the preferred foundation for future web features;
the Windows ConversationAnalyzer retains distinct case storage and reporting capabilities.

## Product priority: NOC investigations

The Data Client is the operations frontend that brings together OpsConsole,
GenesysInterrogator and ConversationAnalyzer. Prioritize composed investigations and
operational findings; endpoint browsing is supporting diagnostics.

- [x] Put conversation investigation ahead of raw endpoints in navigation/onboarding.
- [x] Add run-scoped entity labels and distinguish current user-Division membership.
- [x] Preserve flow IDs and endpoint packet observations for incident cohorts.
- [ ] Inventory every job/transaction family and bind supported submissions to status,
      terminal validation and complete results paging with failure/partial tests.
- [ ] Implement the mass-disconnect Ops composer and incident workspace: error cohort,
      affected entities, quality/time buckets, incident/baseline queue metrics,
      historical NOT_RESPONDING segments and time-aligned audit changes.
- [ ] Validate the investigation against a real tenant and operations-team pilot.

[Implementation and acceptance contract](docs/NOC_INCIDENT_INVESTIGATIONS.md).
The queue-change work below is a component of this direction; no open work is removed.

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

## Investigation suite: monthly voice volume reconciliation

Scope agreed 2026-10-11. Compare four independent collection paths; differences are
investigation evidence, not automatic proof of a script defect. Detailed contract:
[Monthly voice volume reconciliation](docs/MONTHLY_VOICE_VOLUME_RECONCILIATION.md).

- [x] Record the four-source comparison and acceptance contract.
- [x] Implement catalog-driven collection for details query, details jobs, aggregates query,
      and aggregates jobs, including complete paging and async result retrieval.
- [x] Produce source-specific totals, metric definitions, coverage, and pairwise differences.
- [x] Add a thin MonthlyMetrics launcher and standalone HTML/JSON/CSV frontend over Ops.
- [ ] Add Data Client comparison and conversation drilldown where IDs are available.
- [x] Validate equal, divergent, partial, and unavailable sources with synthetic fixtures.
- [ ] Add automatic interval partitioning for source limits, with explicit attribution checks.
- [ ] Audit remaining aggregate catalog aliases for inappropriate detail-paging profiles.
- [ ] Collect all four sources on a real tenant for the same month and document observed
      differences; mock agreement does not close this gate.

## Investigation suite: conversation population analysis

- [x] Adapt the reference conversation profiler into shared Genesys.Ops functions.
- [x] Collect an interval by queue, user, Division, media, or advanced query through Core.
- [x] Provide interactive field filters, sorting, grouping, and full-population statistics.
- [x] Include error occurrence counts, conversation timelines, and scoped JSON/CSV exports.
- [x] Validate synthetic collection, partial coverage, browser interaction, and accessibility.
- [x] Integrate the shared workbench into both Data Client skins with retained in-session state.
- [x] Resolve entity names through Core/Ops with explicit missing/access-denied coverage.
- [ ] Validate permissions, field semantics, and completeness against a real tenant.
- [x] Benchmark 50k/100k engine populations and 50k browser artifacts; cache search,
      stream group aggregation, cap initial breakdown rows, reuse serialization and reduce restore copies.
- [ ] Add background indexing/worker or indexed storage if tenant populations exceed the
      measured envelope; improve remaining large-bundle skin restore cost.

See [conversation population analysis](docs/CONVERSATION_POPULATION_ANALYSIS.md).
Local validation does not close tenant or operator acceptance.

## Following opportunities

1. Repeat-contact, transfer-loop, and failed-handoff analysis.
2. Scheduled business-unit scorecards with stable KPI definitions.
3. Configuration drift and division-access evidence.
4. Bot/AI outcome and cost assurance.
5. Voice/integration incident triage and an evidence-grounded investigation assistant.

Catalog recipes and remote proposals remain design inputs until implemented and tested.
Local fixture, browser, and static checks do not close tenant, Windows UI, or operator gates.
