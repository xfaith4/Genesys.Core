# Genesys.Ops Dataset Coverage Report

Generated: 2026-05-01  
Catalog: `catalog/genesys.catalog.json`

## Summary

| Metric | Count |
|--------|-------|
| Total public functions | 79 |
| Composite/reporting functions | 16 |
| Dataset-backed functions | 63 |
| Valid catalog-backed functions | 79 |
| Missing/Unsupported dataset keys | 0 |
| Functions relying on default body (Medium risk) | 11 |
| Functions requiring parameter/body override work | 11 |

All 79 mapped functions have dataset keys that resolve in the active catalog.
11 functions rely on catalog default request bodies — these work but lack runtime parameterisation for operational filtering.

---

## Function Coverage Table

| FunctionName | DatasetKey | IsInCatalog | HasRequiredBody | InvocationRisk | Notes |
|---|---|---|---|---|---|
| Get-GenesysOrganization | organization.get.organization.details | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysOrganizationLimit | organization.get.organization.limits | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysDivision | authorization.get.all.divisions | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysAgent | users | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysAgentPresence | users.get.bulk.user.presences.genesys.cloud | ✅ | No | Low | Dataset key validated in catalog. |
| Find-GenesysUser | users.search.users.by.name.or.email | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysUserWithDivision | users.division.analysis.get.users.with.division.info | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysSystemPresence | presence.get.system.presence.definitions | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysCustomPresence | presence.get.organization.presence.definitions | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysQueue | routing-queues | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysRoutingSkill | routing.get.all.routing.skills | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysWrapupCode | routing.get.all.wrapup.codes | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysLanguage | routing.get.all.languages | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysActiveConversation | conversations.get.active.conversations | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysActiveCall | conversations.get.active.calls | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysActiveChat | conversations.get.active.chats | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysActiveEmail | conversations.get.active.emails | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysActiveCallback | conversations.get.active.callbacks | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysCallHistory | conversations.get.call.history | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysConversationDetail | analytics-conversation-details | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysAuditEvent | audit-logs | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysApiUsage | usage.get.api.usage.organization.summary | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysApiUsageByClient | usage.get.api.usage.by.client | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysApiUsageByUser | usage.get.api.usage.by.user | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysNotificationTopic | notifications.get.available.notification.topics | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysNotificationSubscription | notifications.get.notification.subscriptions | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysOAuthClient | oauth.get.clients | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysOAuthAuthorization | oauth.get.authorizations | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysRateLimitEvent | analytics.query.rate.limit.aggregates | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysOutboundCampaign | outbound.get.campaigns | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysOutboundContactList | outbound.get.contact.lists | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysOutboundEvent | outbound.get.events | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysMessagingCampaign | outbound.get.messaging.campaigns | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysFlow | flows.get.all.flows | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysFlowOutcome | flows.get.flow.outcomes | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysFlowMilestone | flows.get.flow.milestones | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysFlowAggregate | analytics.query.flow.aggregates.execution.metrics | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysFlowObservation | analytics.query.flow.observations | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysAgentPerformance | analytics.query.user.aggregates.performance.metrics | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysUserActivity | analytics.query.user.details.activity.report | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysAgentVoiceQuality | analytics-conversation-details | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysEdge | telephony.get.edges | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysTrunk | telephony.get.trunks | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysTrunkMetrics | telephony.get.trunk.metrics.summary | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysStation | stations.get.stations | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysQueueAbandonRate | analytics.query.conversation.aggregates.abandon.metrics | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysQueueServiceLevel | analytics.query.queue.aggregates.service.level | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysTransferAnalysis | analytics.query.conversation.aggregates.transfer.metrics | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysWrapupDistribution | analytics.query.conversation.aggregates.wrapup.distribution | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysDigitalChannelVolume | analytics.query.conversation.aggregates.digital.channels | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysEvaluation | quality.get.evaluations.query | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysSurvey | quality.get.surveys | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysAlertingRule | alerting.get.rules | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysAlert | alerting.get.alerts | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysAgentLoginActivity | analytics.query.user.aggregates.login.activity | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysQueueObservation | analytics.query.queue.observations.real.time.stats | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysUserObservation | analytics.query.user.observations.real.time.status | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysQueuePerformance | analytics.query.conversation.aggregates.queue.performance | ✅ | **Yes** | **Medium** | Uses catalog default request body — add parameters or body override for operational use. |
| Get-GenesysWorkforceManagementUnit | workforce.get.management.units | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysJourneyActionMap | journey.get.action.maps | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysSentimentTrend | analytics-conversation-details | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysLongHandleConversation | analytics-conversation-details | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysRepeatCaller | analytics-conversation-details | ✅ | No | Low | Dataset key validated in catalog. |
| Get-GenesysContactCentreStatus | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Invoke-GenesysDailyHealthReport | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Export-GenesysConfigurationSnapshot | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysEdgeHealthSnapshot | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysWebRtcDisconnectSummary | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysConversationLatencyTrend | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysAgentAcwAnomaly | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysChangeAuditFeed | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysAbandonRateDashboard | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysQueueHealthSnapshot | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysAgentQualitySnapshot | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Invoke-GenesysOperationsReport | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysPeakHourLoad | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysOutboundCampaignPerformance | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysFlowOutcomeKpiCorrelation | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |
| Get-GenesysAgentInvestigation | (composite) | ✅ | No | Low | Composite function — calls multiple child cmdlets. Risk depends on children. |

---

## Functions Requiring Parameter / Body Override Work

These 11 functions currently rely on the catalog default request body.
They will call the dataset successfully only if the catalog default body is appropriate.
To make them operationally useful (filter by queue/user/time), Genesys.Core must support body overrides via `Invoke-Dataset -BodyOverride`.

| FunctionName | DatasetKey | RecommendedFix |
|---|---|---|
| Get-GenesysFlowObservation | analytics.query.flow.observations | Add `-FlowType`, `-FlowId`, `-Interval` parameters and pass body override to Invoke-Dataset. |
| Get-GenesysAgentPerformance | analytics.query.user.aggregates.performance.metrics | Add `-UserId`, `-MediaType`, `-Since`, `-Until`, `-Granularity` parameters. |
| Get-GenesysQueueAbandonRate | analytics.query.conversation.aggregates.abandon.metrics | Add `-QueueId`, `-MediaType`, `-Since`, `-Until` parameters. |
| Get-GenesysQueueServiceLevel | analytics.query.queue.aggregates.service.level | Add `-QueueId`, `-MediaType`, `-Since`, `-Until` parameters. |
| Get-GenesysTransferAnalysis | analytics.query.conversation.aggregates.transfer.metrics | Add `-QueueId`, `-Since`, `-Until` parameters. |
| Get-GenesysWrapupDistribution | analytics.query.conversation.aggregates.wrapup.distribution | Add `-QueueId`, `-WrapupCodeId`, `-Since`, `-Until` parameters. |
| Get-GenesysDigitalChannelVolume | analytics.query.conversation.aggregates.digital.channels | Add `-Since`, `-Until`, `-MediaType` parameters. |
| Get-GenesysAgentLoginActivity | analytics.query.user.aggregates.login.activity | Add `-UserId`, `-Since`, `-Until` parameters. |
| Get-GenesysQueueObservation | analytics.query.queue.observations.real.time.stats | Add `-QueueId`, `-MediaType` parameters. |
| Get-GenesysUserObservation | analytics.query.user.observations.real.time.status | Add `-UserId` parameter. |
| Get-GenesysQueuePerformance | analytics.query.conversation.aggregates.queue.performance | Add `-QueueId`, `-MediaType`, `-Since`, `-Until`, `-Granularity` parameters. |

> **Blocker**: Until `Invoke-Dataset` accepts a `-BodyOverride` parameter, these functions cannot be operationally parameterised without bypassing the Genesys.Core contract. A Genesys.Core enhancement is required.

---

## Key Inconsistency: Presence Dataset Keys

Two distinct dataset keys exist for bulk user presences:

| Key | Redaction Profile | Used By |
|-----|-------------------|---------|
| `users.get.bulk.user.presences` | `agent-investigation-presences` | Agent Investigation steps |
| `users.get.bulk.user.presences.genesys.cloud` | (none) | `Get-GenesysAgentPresence` |

Both keys are valid entries in the active catalog. They target different endpoints and schemas.
`Get-GenesysAgentPresence` intentionally uses the `.genesys.cloud` variant (no redaction profile needed for the public cmdlet).
Agent Investigation correctly uses the investigation-specific key with its redaction profile.
**No change required** — the inconsistency is intentional by design.

---

## Implementation Summary

### Fixed Dataset Keys
- All 63 dataset-backed functions resolve in the active catalog (`genesys.catalog.json`).
- Presence dataset key inconsistency documented above; both are intentional.

### Hardening Changes Delivered

| Area | Change |
|------|--------|
| Private helpers | Added `Test-Property`, `Get-PropertyValue`, `Get-NestedPropertyValue` for StrictMode-safe nested property access |
| `Invoke-GenesysOpsDataset` | New hardened private helper: catalog pre-validation, diagnostic envelope, `Status` field (`Succeeded`/`Empty`/`Failed`/`Unsupported`), `-IncludeDiagnostics` switch |
| `Connect-GenesysCloud` | Expanded catalog candidate paths to include `genesys-core.catalog.json` and parent directory variants |
| `ConvertFrom-ObservationResult` | Safe stats access using `Get-PropertyValue` — no StrictMode crash on missing `stats`, `group`, or `data` |
| `ConvertFrom-AggregateResult` | Safe stats access using `Get-PropertyValue` — no StrictMode crash on missing `stats` |
| `Get-GenesysAgentVoiceQuality` | Safe access for `mediaStatsMinConversationMos`, `divisionIds[0]` |
| `Get-GenesysAuditEvent` | Safe access for `user.email`, `serviceContext.entityType` |
| `Get-GenesysUserWithDivision` | Safe access for `division.name` in filter |
| `Get-GenesysChangeAuditFeed` | Safe access for nested service context fields |
| `Get-GenesysContactCentreStatus` | Partial success: each section independently try-caught; `Diagnostics[]` in output |
| `Invoke-GenesysDailyHealthReport` | Partial success: `Invoke-ReportSection` helper; `Diagnostics[]` in output; `-FailFast` switch |
| `Export-GenesysConfigurationSnapshot` | Partial success: `Export-Section` helper; `Sections[]` in manifest; `-FailFast` switch; `[System.IO.Path]` safe folder resolution |
| `Invoke-GenesysOperationsReport` | Partial success: `Invoke-OpsSection` helper; `Diagnostics[]` in output; `-FailFast` switch |
| `Test-GenesysOpsDatasetCoverage` | New public cmdlet: audits all mapped functions against the active catalog |

### Functions Still Blocked by Genesys.Core Limitations
The 11 Medium-risk functions listed above require `Invoke-Dataset -BodyOverride` support from Genesys.Core before they can expose runtime query parameters.

### Test Results
- 139 unit tests pass (0 failures, 1 skipped — swagger coverage, requires `generated/swagger/swagger.json`)
- New `tests/unit/GenesysOps.Hardening.Tests.ps1`: 35 tests covering safe property helpers, observation/aggregate flatteners, dataset catalog pre-validation, composite partial-success, and coverage audit
