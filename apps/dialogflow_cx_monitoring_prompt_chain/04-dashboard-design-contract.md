# Prompt 4: Dashboard Design Contract

You are operating under the Dashboard Design Contract.

## Goal

Design a decision-driven monitoring dashboard for Dialogflow CX and Cloud Run webhook operations.

## Dashboard structure

Use three operational tiers:

1. Executive Summary
2. Operational Detail
3. Diagnostic Detail

## Design rules

- Every widget must answer an operational question.
- Every widget must use:
  - a confirmed metric,
  - a confirmed log source,
  - an existing custom log-based metric,
  - or an explicitly identified required custom log-based metric.
- Mark unconfirmed widgets as `candidate only`.
- Avoid high-cardinality labels.
- Prefer rates, ratios, percentiles, grouped summaries, and service-level indicators over raw event spam.
- Avoid decorative widgets.

## Required widget table

For every widget, provide:

| Widget Name | Tier | Data Source | Metric or Log Filter | Visual Type | Grouping Labels | Operational Question Answered | Evidence Status |
|---|---|---|---|---|---|---|---|

## Suggested dashboard tiers

### Executive Summary

Possible operational questions:

- Are interactions flowing?
- Is latency within SLA?
- Are webhook errors increasing?
- Is traffic unexpectedly absent?
- Are quota or permission failures occurring?

### Operational Detail

Possible operational questions:

- Which channel or platform is driving traffic?
- Is Cloud Run scaling normally?
- Are latency spikes correlated with concurrency or instance startup?
- Are failures isolated to the webhook or Dialogflow API layer?

### Diagnostic Detail

Possible operational questions:

- What exact error categories are occurring?
- Are no-match/fallback outcomes increasing?
- Are denied/security events visible?
- Are there payload patterns that indicate a bad deployment or bad intent configuration?

## Forbidden actions

- Do not generate Terraform.
- Do not include unverified metric names in production-ready resources.
- Do not create widgets that do not answer an operational question.
- Do not use dynamic IDs as grouping labels.

## Required deliverables

1. Dashboard layout.
2. Widget specification table.
3. Data-source readiness table.
4. Required custom log-based metric list.
5. Recommendation for which widgets should be included in v1.
6. Candidate widgets to defer.

## Required output format

```markdown
## Dashboard Layout

## Widget Specification

| Widget Name | Tier | Data Source | Metric or Log Filter | Visual Type | Grouping Labels | Operational Question Answered | Evidence Status |
|---|---|---|---|---|---|---|---|

## Data Source Readiness

| Data Source | Confirmed? | Used By | Risk | Action Needed |
|---|---:|---|---|---|

## Required Custom Log-Based Metrics

| Metric Name | Source Log Filter | Labels | Cardinality Risk | Purpose |
|---|---|---|---|---|

## v1 Dashboard Recommendation

## Candidate Widgets to Defer

## Gate Status
```

## Proceed criteria

Proceed only if v1 widgets are tied to confirmed telemetry or clearly marked as requiring custom metrics.

End with the required gate language.
