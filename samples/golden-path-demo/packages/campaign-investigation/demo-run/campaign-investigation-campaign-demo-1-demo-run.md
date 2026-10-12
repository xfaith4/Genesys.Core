# Investigation Package

- Investigation: `campaign-investigation`
- Subject: `campaign` / `campaign-demo-1`
- Run ID: `demo-run`
- Window: ``2026-05-01T00:00:00.0000000Z`` -> ``2026-05-12T00:00:00.0000000Z``
- Generated: `2026-10-11T14:50:06.7076439Z`

## Overview

| GeneratedAtUtc | Investigation | SubjectType | SubjectId | RunId | StartedAtUtc | FinishedAtUtc | SinceUtc | UntilUtc | StepCount | FailedSteps | RecordsCollected | SectionCount |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-11T14:50:06.7076439Z | campaign-investigation | campaign | campaign-demo-1 | demo-run | 2026-10-11T14:50:04.9128118Z | 2026-10-11T14:50:05.2644643Z | 2026-05-01T00:00:00.0000000Z | 2026-05-12T00:00:00.0000000Z | 8 | 0 | 11 | 8 |

## Step status

| StepName | DatasetKey | ValidationStatus | RecordCount | Required | Status | ErrorMessage |
| --- | --- | --- | --- | --- | --- | --- |
| campaign | outbound.get.campaigns | unvalidated | 1 | True | ok | — |
| contactList | outbound.get.contact.lists | unvalidated | 1 | False | ok | — |
| queue | routing.get.single.queue.config | unvalidated | 1 | False | ok | — |
| diagnostics | outbound.get.campaign.diagnostics.summary | unvalidated | 1 | False | ok | — |
| outboundEvents | outbound.get.events | unvalidated | 4 | False | ok | — |
| auditChanges | audit-logs | unvalidated | 1 | False | ok | — |
| conversationAnalytics | analytics-conversation-details-query | unvalidated | 1 | False | ok | — |
| outboundAbandons | outbound.get.events | unvalidated | 1 | False | ok | — |

## campaign

| id | name | campaignStatus | dialingMode | contactListId | queueId | callerName | callerAddress | abandonRate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| campaign-demo-1 | Spring Renewal | on | power | contact-list-demo-1 | queue-demo-1 | Genesys Cloud | +15551234567 | 3 |

## contactList

| id | name | size | columnNames |
| --- | --- | --- | --- |
| contact-list-demo-1 | Renewals Q2 | 2400 | ["phone","firstName"] |

## queue

| id | name | mediaSettings |
| --- | --- | --- |
| queue-demo-1 | Outbound Sales | {"call":{"alertingTimeoutSeconds":25}} |

## diagnostics

| campaignId | health | pacingMode | errorCount | contactableRate |
| --- | --- | --- | --- | --- |
| campaign-demo-1 | healthy | power | 0 | 78.1 |

## outboundEvents

| id | campaignId | timestamp | type | callResult |
| --- | --- | --- | --- | --- |
| evt-1 | campaign-demo-1 | 2026-05-10T14:00:00.0000000Z | campaignStart | — |
| evt-2 | campaign-demo-1 | 2026-05-10T14:01:00.0000000Z | contactCallCompleted | Connected |
| evt-3 | campaign-demo-1 | 2026-05-10T14:02:00.0000000Z | contactCallCompleted | NoAnswer |
| evt-4 | campaign-demo-1 | 2026-05-10T14:03:00.0000000Z | contactCallAbandon | OutboundAbandon |

## auditChanges

| id | entityId | entityType | action | serviceName | timestamp |
| --- | --- | --- | --- | --- | --- |
| audit-1 | campaign-demo-1 | Campaign | UPDATE_OUTBOUND_CAMPAIGN | outbound | 2026-05-10T13:45:00.0000000Z |

## conversationAnalytics

| conversationId | originatingDirection | participants |
| --- | --- | --- |
| conv-campaign-1 | outbound | {"purpose":"agent","userId":"agent-demo-001","campaignId":"campaign-demo-1","sessions":[{"mediaType":"voice","segments":[{"segmentType":"interact","campaignId":"campaign-demo-1","queueId":"queue-demo-1","disconnectType":"client"}]}]} |

## outboundAbandons

| id | campaignId | timestamp | type | callResult |
| --- | --- | --- | --- | --- |
| evt-4 | campaign-demo-1 | 2026-05-10T14:03:00.0000000Z | contactCallAbandon | OutboundAbandon |

