Align delivery workflows and onboarding docs with current operational reality.

Files:
- `.github/workflows/audit-logs.scheduled.yml`
- `.github/workflows/audit-logs.on-demand.yml`
- `README.md`
- `docs/ONBOARDING.md`
- `docs/READINESS_REVIEW.md`
- `TESTING.md`

Requirements:
- Keep artifact upload scoped to `out/<datasetKey>/<runId>/`.
- Keep unique artifact names and configurable retention.
- Preserve current scheduled/on-demand windows and inputs.
- Document auth expectations honestly:
  - module invocation requires valid auth headers for live runs
  - workflow auth bootstrap is environment-specific unless explicitly implemented
- Ensure docs match actual script/module behavior (especially standalone script parameter limitations).

Acceptance:
- Workflow YAML validates.
- Docs are internally consistent and do not overstate capabilities.
- New users can follow onboarding docs to run at least one authenticated dataset end-to-end.
