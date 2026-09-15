# Product value and next opportunities

Assessment date: 2026-09-15. Priorities are engineering/product judgments based on the
repository and current Genesys documentation, not customer-validated demand or ROI claims.

## Highest-value current feature: conversation investigation and evidence export

**Turn a conversation ID into an explainable investigation package.** The strongest
current business outcome is reducing the work needed to investigate a failed interaction,
customer complaint, unexplained transfer, or voice incident. Genesys.Ops joins conversation,
agent, queue, quality and survey context; its package exporter assembles a chronological
HTML report, CSV/XLSX evidence, findings, and optional SIP/PCAP evidence. Operators can hand
the same evidence to supervisors, telecom engineers, and support teams.

Evidence in the repository:

- `modules/Genesys.Ops/Genesys.Ops.psm1`: `Get-GenesysConversationInvestigation` and
  `Export-GenesysConversationInvestigationPackage`.
- `tests/integration/ConversationInvestigation.Tests.ps1` and
  `ConversationInvestigationPackage.Tests.ps1`: fixture-backed composer/export checks.
- `docs/CONVERSATION_INVESTIGATION_PACKAGE.md`: invocation and evidence contract.
- `samples/demo-conversation-investigation/`: reviewable example output.

The governed Core is the enabling foundation: consistent paging/retry, run manifests,
redaction, and dataset provenance. The React **Genesys Data Client** is the preferred
foundation for future web UX, with reusable filters, aggregation, export, endpoint discovery,
and PKCE authentication. Its modern framework alone does not make it the most valuable
business feature. Its mock-backed demo is not proof of live tenant acceptance.

**Scope limits:** SIP applies to voice, and permissions, retention, deployment and media
support affect available evidence. Incomplete collections must remain visibly incomplete.
No measured reduction in investigation time has been established yet. Existing Windows
Analyzer functionality is retained because its SQLite cases and report tabs are not
replaced by the React client.

## Ranked future features

| Rank | Feature and primary buyer | Business outcome / smallest useful release | Reach | Effort | Confidence |
| --- | --- | --- | --- | --- | --- |
| 1 | Change-to-incident correlation — operations/platform admins | Join audit changes to queue/flow/telephony failures and before/after KPIs; deliver one timestamped incident packet with affected queues and conversations. | Broad | Medium | High fit; demand unmeasured |
| 2 | Repeat-contact and failed-handoff analysis — CX/operations leaders | Find repeat contacts, transfer loops, abandoned callbacks and channel switches; show affected cohorts and recoverable work with conversation drilldown. | Broad | Medium–large | Medium; identity/outcome data dependent |
| 3 | Scheduled business-unit scorecards — operations directors | Versioned KPI definitions, comparable periods, division/queue drilldown, and scheduled evidence-linked exports. | Broad | Medium | High fit |
| 4 | Configuration drift and access evidence — platform/security teams | Snapshot queue/flow/routing configuration and division grants; show changes, responsible actor where available, and scheduled review evidence. | Broad | Medium | High fit; coverage must be verified |
| 5 | Bot/AI outcome and cost assurance — automation owners | Compare containment with later recontact, escalation, quality, and configured cost inputs; identify automation that merely shifts work. | AI-enabled tenants | Large | Medium; licensing and attribution dependent |
| 6 | Voice and integration incident triage — telecom/NOC teams | Cluster SIP failures, disconnects, Edge/trunk signals and API throttling; attach representative evidence and candidate causes. | Voice/integration-heavy tenants | Medium–large | High technical fit |
| 7 | Evidence-grounded investigation assistant — analysts | Summarize an existing evidence packet with links to every claim, explicit missing data, and human review. | Broad | Medium–large | Medium; evaluate accuracy before rollout |

The ranking favors reuse of existing tested collection and investigation capabilities,
breadth of business use, and a measurable operational outcome. It does not imply that all
contact centers need the same feature or that a catalog recipe is an implemented composer.

## Recommended next release: explain what changed when service deteriorated

Start with a **read-only queue incident investigation** in the Data Client:

1. Select queue(s), incident interval, and a comparable baseline; show timezone and filters.
2. Collect audit changes, queue metrics, and representative conversations through Core.
3. Align UTC timelines and identify candidate changes associated with deterioration.
4. Show sample sizes, missing collectors, permission failures, and collection timestamps.
5. Export the evidence package with exact KPI definitions and provenance.

Acceptance gates:

- [ ] Fixtures cover no incident, a related change, an unrelated change, late data,
      partial permissions, repeated collection, and timezone boundaries.
- [ ] Audit/metric joins preserve IDs and time windows; temporal association is labelled
      as a hypothesis rather than a proven cause.
- [ ] Aggregations use the full filtered population. Distinct conversations are not
      confused with queue offers; average handle time uses the metric's actual count.
- [ ] Customer-specific business-unit mapping is explicit; a division is not assumed to
      equal a business unit, and transferred contacts are not silently double-counted.
- [ ] One tenant pilot validates permissions, endpoint contracts, retention, and exports.
- [ ] Operators compare investigation completion time and evidence completeness against
      their current workflow before any ROI claim is published.

## Position against native Genesys capabilities

Genesys already provides analytics, journey tooling, and AI supervisor capabilities.
Prioritize reproducible cross-domain evidence, custom business definitions, integration
with a customer's incident process, and transparent collection gaps. A generic dashboard,
transcript summarizer or supervisor copilot would have substantial native overlap.

Sources checked on 2026-09-15:

- [Genesys AI for Supervisors overview](https://www.genesys.com/resources/genesys-cloud-ai-for-supervisors-product-overview):
  native supervisor assistance and evaluation automation support the overlap assessment.
- [Journey Management overview](https://help.genesys.cloud/?p=307689): native journey
  analysis means repeat-contact work should focus on custom outcomes and evidence joins.
- [Analytics and recording retention](https://help.genesys.cloud/articles/retention-period-for-analytics-data-and-recording/):
  SIP PCAP retention is 21 days; other evidence has different retention and retrieval
  conditions. Collection availability must be recorded per source.

These sources establish platform context. The feature rankings and proposed release are
inferences from that context and the repository, not claims made by Genesys.
