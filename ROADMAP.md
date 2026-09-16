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
- [ ] Add incident selection and evidence drilldown to the Data Client.
- [ ] Export timestamps, filters, metric denominators, missing-source warnings and evidence.
- [ ] Complete a pilot measuring operator investigation time and evidence completeness.

See [acceptance gates](docs/PRODUCT_VALUE.md#recommended-next-release-explain-what-changed-when-service-deteriorated).

## Following opportunities

1. Repeat-contact, transfer-loop, and failed-handoff analysis. Catalog pattern documented
   (`transfer-loop-and-failed-handoff-analysis`, `transfer-loop-and-escalation-kpis`,
   `transfer-chain-and-failed-handoff-forensics` in `catalog/genesys.catalog.json` /
   [ENDPOINT_COMBINATIONS.md §10a](docs/ENDPOINT_COMBINATIONS.md#10a-transfer-loop-and-failed-handoff-analysis));
   not yet wired into a runtime cmdlet or app feature.
2. Scheduled business-unit scorecards with stable KPI definitions.
3. Configuration drift and division-access evidence.
4. Bot/AI outcome and cost assurance.
5. Voice/integration incident triage and an evidence-grounded investigation assistant.

Catalog recipes and remote proposals remain design inputs until implemented and tested.
Local fixture, browser, and static checks do not close tenant, Windows UI, or operator gates.
