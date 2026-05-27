# Prompt 5: Alert Policy Contract

You are operating under the Alert Policy Contract.

## Goal

Design production-safe alert policies for Dialogflow CX and Cloud Run webhook monitoring.

## Alerts to evaluate

Evaluate these failure modes:

1. Webhook latency degradation.
2. Webhook 5xx error spike.
3. Quota exhaustion / `RESOURCE_EXHAUSTED`.
4. Permission denied errors.
5. Traffic drop / metric absence.
6. Fallback or no-match intent spike, if measurable.
7. Cloud Run instance/concurrency saturation, if supported by confirmed metrics.

## Required alert table

For each alert, provide:

| Alert Name | Failure Mode | Signal | Threshold | Duration | Severity | Notification Channel | Runbook Hint | Noise Risk | Evidence Status |
|---|---|---|---|---|---|---|---|---|---|

## Alerting rules

- Do not alert on raw single failures unless the failure is critical.
- Use rolling windows where appropriate.
- Treat traffic-drop alerts as baseline-dependent.
- Mark traffic-drop alerts disabled by default unless business hours and baseline volume are known.
- Explain why each threshold is chosen.
- Distinguish symptoms from causes.
- Prefer actionability over coverage.
- Include runbook hints.

## Threshold guidance

These are initial targets, not unquestionable truth:

- Webhook latency: p95 above 4500 ms for a rolling 5-minute window.
- Quota exhaustion: trigger immediately if confirmed `RESOURCE_EXHAUSTED` errors occur.
- Traffic drop: metric absence or sharp drop only during known operational hours.
- Fallback/no-match: baseline-dependent; do not enable until normal rate is known.

## Forbidden actions

- Do not generate Terraform.
- Do not create alerts from unconfirmed metric names.
- Do not create alerts that depend on high-cardinality labels.
- Do not create noisy cold-start alerts without mitigation.
- Do not create alerts with no operator action.

## Required deliverables

1. Alert policy design table.
2. Noise-risk analysis.
3. Disabled-by-default recommendations.
4. Runbook notes for each alert.
5. Confirmation that alert policies are ready for Terraform.

## Required output format

```markdown
## Alert Policy Design

| Alert Name | Failure Mode | Signal | Threshold | Duration | Severity | Notification Channel | Runbook Hint | Noise Risk | Evidence Status |
|---|---|---|---|---|---|---|---|---|---|

## Noise Risk Analysis

| Alert | Noise Risk | Why | Mitigation |
|---|---|---|---|

## Disabled-by-Default Recommendations

## Runbook Notes

## Terraform Readiness

## Gate Status
```

## Proceed criteria

Proceed only if:

- the signal is confirmed,
- the threshold has rationale,
- the alert has a clear operator action,
- noise risk is documented.

Block if:

- alert has no actionable response,
- threshold is arbitrary,
- signal cannot distinguish symptom from cause,
- metric/log source is unverified.

End with the required gate language.
