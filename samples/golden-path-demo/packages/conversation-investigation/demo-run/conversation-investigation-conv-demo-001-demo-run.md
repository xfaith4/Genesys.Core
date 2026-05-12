# Investigation Package

- Investigation: `conversation-investigation`
- Subject: `conversation` / `conv-demo-001`
- Run ID: `demo-run`
- Window: Not scoped
- Generated: `2026-05-12T11:18:49.4816923Z`

## Overview

| GeneratedAtUtc | Investigation | SubjectType | SubjectId | RunId | StartedAtUtc | FinishedAtUtc | SinceUtc | UntilUtc | StepCount | FailedSteps | RecordsCollected | SectionCount |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-12T11:18:49.4816923Z | conversation-investigation | conversation | conv-demo-001 | demo-run | 2026-05-12T11:18:48.2547066Z | 2026-05-12T11:18:48.4547747Z | — | — | 9 | 0 | 9 | 9 |

## Step status

| StepName | DatasetKey | ValidationStatus | RecordCount | Required | Status | ErrorMessage |
| --- | --- | --- | --- | --- | --- | --- |
| conversationLookup | conversations.get.specific.conversation.details | unvalidated | 1 | True | ok | — |
| conversation | analytics-conversation-details-query | unvalidated | 1 | True | ok | — |
| participants | (derived) | unvalidated | 1 | True | ok | — |
| agents | users | unvalidated | 1 | False | ok | — |
| divisions | users.division.analysis.get.users.with.division.info | unvalidated | 0 | False | ok | — |
| skills | routing.get.all.routing.skills | unvalidated | 2 | False | ok | — |
| recordings | conversations.get.recordings | unvalidated | 1 | False | ok | — |
| evaluations | quality.get.evaluations.query | unvalidated | 1 | False | ok | — |
| surveys | quality.get.surveys | unvalidated | 1 | False | ok | — |

## conversationLookup

| conversationId | conversationStart | conversationEnd | participants |
| --- | --- | --- | --- |
| conv-demo-001 | 2026-04-05T13:10:00.0000000Z | 2026-04-05T13:27:00.0000000Z | [{"userId":"agent-demo-001","purpose":"agent","queueId":"queue-demo-1","divisionId":"div-demo-1"},{"purpose":"customer"}] |

## conversation

| conversationId | participants |
| --- | --- |
| conv-demo-001 | {"userId":"agent-demo-001","role":"agent"} |

## participants

| userId | purpose |
| --- | --- |
| agent-demo-001 | — |

## agents

| id | name | division |
| --- | --- | --- |
| agent-demo-001 | Jane Doe | {"id":"div-demo-1","name":"CustomerCare"} |

## divisions

_No records._

## skills

| id | userId | name |
| --- | --- | --- |
| skill-demo-1 | agent-demo-001 | Billing |
| skill-demo-2 | agent-demo-001 | Retention |

## recordings

| id | conversationId | mediaType | status |
| --- | --- | --- | --- |
| rec-demo-1 | conv-demo-001 | voice | available |

## evaluations

| id | conversation | totalScore |
| --- | --- | --- |
| eval-demo-1 | {"id":"conv-demo-001"} | 91 |

## surveys

| id | conversationId | npsScore | csatScore | comment |
| --- | --- | --- | --- | --- |
| survey-demo-1 | conv-demo-001 | 10 | 4.9 | Agent resolved the issue quickly. |

