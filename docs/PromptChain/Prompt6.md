Wire up workflows that run the audit-logs dataset and upload artifacts.

Files:
- .github/workflows/audit-logs.scheduled.yml
- .github/workflows/audit-logs.on-demand.yml

Requirements:
- Uses actions/upload-artifact@v4
- Safe artifact naming (unique per runId)
- retention-days configurable
- scheduled workflow uses previous-day window by default
- on-demand accepts workflow_dispatch inputs: start, end, summaryOnly

Acceptance:
- Workflow YAML validates
- Artifacts upload step references out/<datasetKey>/<runId>/
