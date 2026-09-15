# Prompt 2: Evidence Contract

You are operating under the Evidence Contract.

## Goal

Review the discovery evidence I provide and classify what is confirmed, missing, ambiguous, or unsafe to assume.

## Inputs

Use only:

- discovery command output pasted or attached by me,
- project identifiers I provide,
- service names I provide,
- agent IDs I provide,
- regions I provide,
- official Google Cloud metric/log documentation if needed.

## Required analysis

Classify findings into these categories:

### 1. Confirmed resources

- Dialogflow CX agents
- Cloud Run services
- Existing log-based metrics
- Existing dashboards
- Existing alert policies
- Notification channels
- Logging sinks or centralized logging destinations

### 2. Confirmed telemetry sources

- Native Cloud Monitoring metrics
- Cloud Logging entries
- Audit logs
- Custom log-based metrics
- Metric labels
- Monitored resource types

### 3. Missing or unavailable telemetry

- Metrics not present
- Logs not enabled
- Labels not available
- Fields that require custom log-based metrics
- Permissions not available
- Centralized logs not queryable from the project

### 4. Risk flags

- High-cardinality labels
- Sparse traffic
- Centralized logging buckets
- Incomplete retention
- Sampling or aggregation concerns
- Permission gaps
- Unknown notification channels
- Unclear business hours or traffic baseline

## Forbidden actions

- Do not write Terraform.
- Do not design final alert policies.
- Do not treat unverified fields as production-ready.
- Do not infer resource names not present in the evidence.

## Required deliverables

Provide:

1. Evidence summary table.
2. Confirmed metric descriptor table.
3. Confirmed log source table.
4. Missing evidence list.
5. Risk flag table.
6. Recommendation on whether we are ready to design the dashboard.

## Required output format

```markdown
## Evidence Summary

| Area | Confirmed | Evidence | Notes |
|---|---:|---|---|

## Confirmed Metric Descriptors

| Metric Type | Monitored Resource | Labels Confirmed | Evidence | Usable For |
|---|---|---|---|---|

## Confirmed Log Sources

| Log Name / Filter | Resource Type | Fields Confirmed | Evidence | Usable For |
|---|---|---|---|---|

## Missing Evidence

## Risk Flags

| Risk | Severity | Why It Matters | Mitigation |
|---|---|---|---|

## Readiness Recommendation

## Gate Status
```

## Proceed criteria

Only proceed if each proposed dashboard or alert data source can be tied to confirmed evidence.

End with the required gate language.
