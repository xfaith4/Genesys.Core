# Prompt 1: Discovery Contract

You are operating under the Discovery Contract.

## Goal

Determine what Dialogflow CX, Cloud Run, logging, metrics, dashboards, alerting, and notification resources exist in the target GCP project.

## Inputs currently known

```text
Project ID: [REPLACE_WITH_PROJECT_ID]
Region: [REPLACE_WITH_REGION]
Dialogflow CX Agent ID: [REPLACE_WITH_AGENT_ID_OR_UNKNOWN]
Cloud Run service name: [REPLACE_WITH_SERVICE_OR_UNKNOWN]
```

## Allowed actions

- Ask for missing identifiers.
- Provide exact `gcloud`, `bq`, or Terraform inspection commands.
- Explain what each command proves.
- Identify what evidence is required for later dashboard and alert generation.

## Forbidden actions

- Do not generate Terraform.
- Do not invent metric names.
- Do not invent monitored resource types.
- Do not invent log payload fields.
- Do not design final dashboard widgets yet.
- Do not create alert policies yet.

## Discovery targets

Check for:

1. Active Dialogflow CX agents in the project.
2. Whether Dialogflow CX interaction logging appears to be enabled.
3. Dialogflow-related audit logs.
4. Cloud Run webhook services with names containing:
   - `dialogflow`
   - `webhook`
   - `genai-app`
   - other likely backend names
5. Existing custom log-based metrics.
6. Existing dashboards.
7. Existing alert policies.
8. Existing notification channels.
9. Whether logs appear to be centralized at folder or organization level.
10. Metric descriptors relevant to:
    - Dialogflow CX
    - Cloud Run
    - API/request counts
    - latency
    - error rates
    - quota/resource exhaustion

## Required deliverables

Provide:

1. A discovery command set.
2. A table mapping each command to the evidence it collects.
3. A list of expected outputs/files I should return.
4. A short list of blocking questions.
5. A brief explanation of how the discovery evidence will shape dashboard and alert design.

## Required output format

Use these sections:

```markdown
## Discovery Commands

## What Each Command Proves

| Command | Evidence Collected | Why It Matters |
|---|---|---|

## Evidence I Should Return

## Blocking Questions

## How This Evidence Will Be Used

## Gate Status
```

## Proceed criteria

You may only proceed to the Evidence Contract after I provide command output or confirm that direct project inspection is available.

End with the required gate language.
