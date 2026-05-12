# Investigation Package

- Investigation: `queue-investigation`
- Subject: `queue` / `queue-demo-1`
- Run ID: `demo-run`
- Window: ``2026-04-01T00:00:00.0000000Z`` -> ``2026-04-08T00:00:00.0000000Z``
- Generated: `2026-05-12T11:18:49.6554042Z`

## Overview

| GeneratedAtUtc | Investigation | SubjectType | SubjectId | RunId | StartedAtUtc | FinishedAtUtc | SinceUtc | UntilUtc | StepCount | FailedSteps | RecordsCollected | SectionCount |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-12T11:18:49.6554042Z | queue-investigation | queue | queue-demo-1 | demo-run | 2026-05-12T11:18:48.6351695Z | 2026-05-12T11:18:48.9217453Z | 2026-04-01T00:00:00.0000000Z | 2026-04-08T00:00:00.0000000Z | 9 | 0 | 13 | 9 |

## Step status

| StepName | DatasetKey | ValidationStatus | RecordCount | Required | Status | ErrorMessage |
| --- | --- | --- | --- | --- | --- | --- |
| queue | routing.get.single.queue.config | unvalidated | 1 | True | ok | — |
| members | routing-queue-members | unvalidated | 2 | False | ok | — |
| wrapupCodes | routing.get.queue.wrapup.codes.by.queue | unvalidated | 2 | False | ok | — |
| observations | analytics.query.queue.observations.real.time.stats | unvalidated | 1 | False | ok | — |
| sla | analytics.query.conversation.aggregates.queue.performance | unvalidated | 1 | False | ok | — |
| abandons | analytics.query.conversation.aggregates.abandon.metrics | unvalidated | 1 | False | ok | — |
| transfers | analytics.query.conversation.aggregates.transfer.metrics | unvalidated | 1 | False | ok | — |
| wrapupDistribution | analytics.query.conversation.aggregates.wrapup.distribution | unvalidated | 2 | False | ok | — |
| activeAgents | analytics.query.user.observations.real.time.status | unvalidated | 2 | False | ok | — |

## queue

| id | name | mediaSettings |
| --- | --- | --- |
| queue-demo-1 | Support | {"call":{"alertingTimeoutSeconds":30}} |

## members

| id | queueId | name | joined |
| --- | --- | --- | --- |
| agent-demo-001 | queue-demo-1 | Jane Doe | True |
| agent-demo-002 | queue-demo-1 | John Smith | True |

## wrapupCodes

| id | queueId | name |
| --- | --- | --- |
| wu-demo-1 | queue-demo-1 | Resolved |
| wu-demo-2 | queue-demo-1 | Escalated |

## observations

| queueId | mediaType | oWaiting | oInteracting | oOnQueueUsers |
| --- | --- | --- | --- | --- |
| queue-demo-1 | voice | 3 | 5 | 7 |

## sla

| queueId | mediaType | nOffered | nAnswered | tHandle |
| --- | --- | --- | --- | --- |
| queue-demo-1 | voice | 120 | 110 | 4500 |

## abandons

| queueId | nAbandoned | tAbandoned | nOffered |
| --- | --- | --- | --- |
| queue-demo-1 | 4 | 32 | 120 |

## transfers

| queueId | mediaType | nTransferred | nBlindTransferred | nConsultTransferred | nConnected |
| --- | --- | --- | --- | --- | --- |
| queue-demo-1 | voice | 6 | 2 | 4 | 110 |

## wrapupDistribution

| queueId | wrapUpCode | nConnected | tHandle |
| --- | --- | --- | --- |
| queue-demo-1 | Resolved | 82 | 3100 |
| queue-demo-1 | Escalated | 28 | 1400 |

## activeAgents

| queueId | userId | oUserPresence |
| --- | --- | --- |
| queue-demo-1 | agent-demo-001 | AVAILABLE |
| queue-demo-1 | agent-demo-002 | BUSY |

