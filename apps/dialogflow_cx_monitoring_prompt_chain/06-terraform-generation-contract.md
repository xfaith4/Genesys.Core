# Prompt 6: Terraform Generation Contract

You are operating under the Terraform Generation Contract.

## Goal

Generate production-ready Terraform for the confirmed dashboard, notification channels, custom log-based metrics, and alert policies.

## Inputs required

Use only confirmed or explicitly approved inputs:

- confirmed dashboard design table,
- confirmed alert policy table,
- confirmed metric descriptors,
- confirmed log filters,
- project ID,
- region,
- notification channel details,
- Cloud Run service name,
- Dialogflow CX agent ID,
- environment name.

## Terraform requirements

Generate:

1. `main.tf`
2. `variables.tf`
3. `outputs.tf`
4. `terraform.tfvars.example`

Use the Google Terraform provider.

Use variables for:

- `project_id`
- `region`
- `environment`
- `notification_email`
- `cloud_run_service_name`
- `dialogflow_cx_agent_id`
- any other environment-specific value

Include resources as appropriate:

- `google_monitoring_dashboard`
- `google_monitoring_notification_channel`
- `google_monitoring_alert_policy`
- `google_logging_metric`, only if required and evidence-backed

## Required comments

Above each meaningful resource, include comments explaining:

1. What operational question the resource supports.
2. What evidence justified the metric or log filter.
3. Whether the resource is production-ready or baseline-dependent.
4. Any noise/cardinality risk.

## Safety requirements

- Include safe defaults.
- Mark baseline-dependent alerts as disabled by default.
- Avoid unbounded cardinality in metric labels.
- Do not include candidate/unverified metrics.
- Do not use placeholders silently.
- All placeholders must be obvious.
- Do not omit validation instructions.

## Forbidden actions

- Do not include candidate metrics unless explicitly marked and disabled.
- Do not include unverified monitored resource types.
- Do not include guessed labels.
- Do not create enabled traffic-drop alerts without baseline/business-hour evidence.
- Do not omit Terraform validation commands.

## Required deliverables

1. `main.tf`
2. `variables.tf`
3. `outputs.tf`
4. `terraform.tfvars.example`
5. Validation commands:
   - `terraform fmt`
   - `terraform validate`
   - `terraform plan`
6. Post-deployment verification commands.

## Required output format

```markdown
## Terraform Files

### main.tf

```hcl
...
```

### variables.tf

```hcl
...
```

### outputs.tf

```hcl
...
```

### terraform.tfvars.example

```hcl
...
```

## Validation Commands

## Post-Deployment Verification

## Known Limitations

## Gate Status
```

## Proceed criteria

Terraform is ready only if:

- all resources are tied to confirmed evidence,
- variables cover environment-specific values,
- validation instructions are included,
- baseline-dependent alerts are disabled by default,
- custom metrics avoid high-cardinality labels.

End with the required gate language.
