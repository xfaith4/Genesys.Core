# Prompt 3: Interpretation Contract

You are operating under the Interpretation Contract.

## Goal

Explain what the discovered Dialogflow CX and Cloud Run telemetry means operationally.

## Required outputs

### 1. Dialogflow CX logging behavior

Explain, based on available evidence:

- interaction logging,
- audit logging,
- detectIntent-related activity,
- webhook request/response visibility,
- permission and quota error visibility,
- what is not logged by default,
- what requires custom metrics or additional logging.

### 2. Cloud Run webhook observability

Explain, based on available evidence:

- request count,
- request latency,
- 4xx and 5xx errors,
- instance count,
- container startup behavior,
- concurrency behavior,
- cold-start interpretation,
- timeout behavior.

### 3. Detectable failure modes

Explain which of these are detectable with current telemetry:

- Dialogflow API permission failures,
- webhook timeout,
- Cloud Run cold-start latency,
- Cloud Run 5xx errors,
- Cloud Run 4xx errors,
- `RESOURCE_EXHAUSTED`,
- fallback/no-match intent trends,
- sudden traffic drops,
- centralized logging gaps.

### 4. Custom metric needs

Identify what requires custom log-based metrics, such as:

- intent-level trends,
- fallback/no-match trends,
- platform/channel grouping,
- Dialogflow-specific error categories,
- webhook business-logic failures,
- session outcomes.

## Forbidden actions

- Do not generate code.
- Do not propose final alert thresholds unless telemetry availability is confirmed.
- Do not recommend high-cardinality labels.
- Do not claim unsupported observability coverage.

## Required deliverable

A concise operational interpretation report with:

1. Confirmed behavior.
2. Evidence-backed inferences.
3. Unknowns.
4. Monitoring implications.
5. Recommended next step.

## Required output format

```markdown
## Confirmed Operational Behavior

## Evidence-Backed Inferences

## Unknowns and Blind Spots

## Detectable Failure Modes

| Failure Mode | Detectable Now? | Telemetry Source | Notes |
|---|---:|---|---|

## Custom Metric Requirements

| Desired Signal | Native? | Custom Metric Needed? | Cardinality Risk | Notes |
|---|---:|---:|---|---|

## Monitoring Implications

## Gate Status
```

End with the required gate language.
