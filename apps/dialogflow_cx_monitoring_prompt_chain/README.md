# Dialogflow CX Monitoring Agent Prompt Chain

This prompt kit is designed for a Gemini coding agent or similar coding/ops agent tasked with diagnosing a Google Cloud Dialogflow CX + Cloud Run environment and generating a production-grade monitoring dashboard and alerting framework.

The key design principle is **evidence-first execution**:

> Do not generate dashboard Terraform, alert policies, or custom metrics until the agent has verified the relevant GCP project telemetry sources.

## Recommended usage order

1. `00-system-prompt.md`
2. `01-discovery-contract.md`
3. `02-evidence-contract.md`
4. `03-interpretation-contract.md`
5. `04-dashboard-design-contract.md`
6. `05-alert-policy-contract.md`
7. `06-terraform-generation-contract.md`
8. `07-validation-contract.md`

## How to use

Paste `00-system-prompt.md` as the agent/system instruction if your coding environment supports a system or custom instruction layer.

Then run each numbered prompt in sequence.

Do not skip directly to Terraform generation unless the evidence and design gates have passed.

## Gate language

Each phase should end with one of these:

```text
Gate status: PASS
Ready for next phase: YES
```

or:

```text
Gate status: BLOCKED
Reason: <specific reason>
Needed evidence: <specific command/output required>
Ready for next phase: NO
```

## Design intent

This chain is built to prevent:

- hallucinated Google Cloud metric names
- invalid Monitoring filters
- noisy alert policies
- dashboard widgets that do not answer operational questions
- Terraform generated before environment discovery
- high-cardinality custom metrics
- unverified assumptions about Dialogflow CX, Cloud Run, or centralized logging
