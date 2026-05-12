# Investigation Package

- Investigation: `agent-investigation`
- Subject: `agent` / `agent-demo-001`
- Run ID: `demo-run`
- Window: ``2026-04-01T00:00:00.0000000Z`` -> ``2026-04-08T00:00:00.0000000Z``
- Generated: `2026-05-12T11:18:49.1089101Z`

## Overview

| GeneratedAtUtc | Investigation | SubjectType | SubjectId | RunId | StartedAtUtc | FinishedAtUtc | SinceUtc | UntilUtc | StepCount | FailedSteps | RecordsCollected | SectionCount |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-12T11:18:49.1089101Z | agent-investigation | agent | agent-demo-001 | demo-run | 2026-05-12T11:18:47.7364224Z | 2026-05-12T11:18:48.0086163Z | 2026-04-01T00:00:00.0000000Z | 2026-04-08T00:00:00.0000000Z | 11 | 0 | 15 | 11 |

## Step status

| StepName | DatasetKey | ValidationStatus | RecordCount | Required | Status | ErrorMessage |
| --- | --- | --- | --- | --- | --- | --- |
| identity | users.get.user.details.with.full.expansion | unvalidated | 1 | True | ok | — |
| division | (derived) | unvalidated | 1 | False | ok | — |
| skills | users.get.user.routing.skills | unvalidated | 2 | False | ok | — |
| queues | users.get.user.queue.memberships | unvalidated | 2 | False | ok | — |
| presence | users.get.bulk.user.presences | unvalidated | 1 | False | ok | — |
| routingStatus | users.get.agent.current.routing.status | unvalidated | 1 | False | ok | — |
| utilization | routing.get.user.utilization | unvalidated | 1 | False | ok | — |
| activity | analytics.query.user.details.activity.report | unvalidated | 1 | False | ok | — |
| activeConversations | users.get.agent.active.conversations | unvalidated | 2 | False | ok | — |
| conversations | analytics-conversation-details-query | unvalidated | 2 | False | ok | — |
| auditAccountChanges | audit-logs | unvalidated | 1 | False | ok | — |

## agent

| id | name | email | state | division |
| --- | --- | --- | --- | --- |
| agent-demo-001 | Jane Doe | jane.doe@example.invalid | ACTIVE | {"id":"div-demo-1","name":"CustomerCare"} |

## division

| id | userId | division |
| --- | --- | --- |
| agent-demo-001 | agent-demo-001 | {"id":"div-demo-1","name":"CustomerCare"} |

## skills

| id | userId | name | state |
| --- | --- | --- | --- |
| sk-demo-1 | agent-demo-001 | English | active |
| sk-demo-2 | agent-demo-001 | Billing | active |

## queues

| id | userId | name | joined |
| --- | --- | --- | --- |
| queue-demo-1 | agent-demo-001 | Support | True |
| queue-demo-2 | agent-demo-001 | Escalations | True |

## presence

| userId | presence |
| --- | --- |
| agent-demo-001 | AVAILABLE |

## routingStatus

| userId | status | startTime |
| --- | --- | --- |
| agent-demo-001 | INTERACTING | 2026-04-02T10:15:00.0000000Z |

## utilization

| userId | call | callback |
| --- | --- | --- |
| agent-demo-001 | {"maximumCapacity":1,"utilizedCapacity":1} | {"maximumCapacity":1,"utilizedCapacity":0} |

## activity

| userId | loginMinutes | onQueueMinutes | interactingMinutes |
| --- | --- | --- | --- |
| agent-demo-001 | 420 | 340 | 285 |

## activeConversations

| id | userId | mediaType | state |
| --- | --- | --- | --- |
| active-conv-demo-1 | agent-demo-001 | voice | connected |
| active-conv-demo-2 | agent-demo-001 | message | connected |

## conversations

| conversationId | participants |
| --- | --- |
| conv-demo-A | {"userId":"agent-demo-001","role":"agent"} |
| conv-demo-B | {"userId":"agent-demo-001","role":"agent"} |

## auditAccountChanges

| id | entityId | entityType | action | serviceName | timestamp |
| --- | --- | --- | --- | --- | --- |
| audit-demo-1 | agent-demo-001 | User | update | directory | 2026-04-02T01:00:00.0000000Z |

