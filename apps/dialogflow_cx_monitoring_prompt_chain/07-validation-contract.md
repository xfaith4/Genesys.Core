# Prompt 7: Validation Contract

You are operating under the Validation Contract.

## Goal

Validate that the generated Terraform and monitoring configuration are correct, deployable, and operationally useful.

## Required checks

1. Terraform syntax validation.
2. Provider compatibility check.
3. Metric filter sanity check.
4. Dashboard widget data availability check.
5. Alert policy simulation or reasoning check.
6. Notification channel verification.
7. Rollback plan.

## Required commands

Provide exact commands for:

```bash
terraform fmt
terraform validate
terraform plan
terraform apply
gcloud monitoring dashboards list
gcloud alpha monitoring policies list
gcloud logging metrics list
gcloud monitoring channels list
```

Adjust commands as needed for the actual GCP environment.

## Required analysis

Explain how to interpret:

- successful Terraform validation,
- failed provider validation,
- empty dashboard widgets,
- alerts that do not evaluate,
- notification channels that need verification,
- missing metric data,
- permission errors.

## Forbidden actions

- Do not claim deployment success unless deployment evidence is provided.
- Do not claim widgets are populated unless data is visible or queryable.
- Do not ignore empty charts.
- Do not treat `terraform validate` as proof that Monitoring filters are semantically correct.
- Do not skip rollback guidance.

## Required deliverables

1. Validation checklist.
2. Exact commands to run.
3. Expected successful outputs.
4. Common failure modes and fixes.
5. Final deployment readiness verdict.
6. Rollback plan.

## Required output format

```markdown
## Validation Checklist

| Check | Command | Expected Result | Failure Meaning |
|---|---|---|---|

## Commands to Run

## Expected Successful Outputs

## Common Failure Modes and Fixes

| Symptom | Likely Cause | Fix |
|---|---|---|

## Empty Widget Interpretation

## Alert Verification

## Notification Channel Verification

## Rollback Plan

## Final Readiness Verdict

## Gate Status
```

End with the required gate language.
