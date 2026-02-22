You are working in an existing repo: `genesys-core`.

Goal: continue development from the current baseline without re-bootstrap work.

Current baseline (must be preserved):
- Canonical runtime catalog: `./genesys-core.catalog.json` (legacy mirror still exists at `./catalog/genesys-core.catalog.json`).
- Module entrypoint: `Invoke-Dataset`; exported functions are `Invoke-Dataset` and `Assert-Catalog`.
- Run output contract already implemented:
  - `out/<datasetKey>/<runId>/manifest.json`
  - `out/<datasetKey>/<runId>/events.jsonl`
  - `out/<datasetKey>/<runId>/summary.json`
  - `out/<datasetKey>/<runId>/data/*.jsonl`
- Curated dataset handlers implemented:
  - `audit-logs`
  - `analytics-conversation-details`
  - `users`
  - `routing-queues`
- Generic catalog-driven dispatch is available for additional dataset keys.
- Retry, paging, async, and redaction test suites already exist and should remain passing.

Conventions:
- PowerShell 5.1 + 7+ compatible.
- No secrets in logs or test fixtures.
- Use `### BEGIN / ### END` markers for drop-in replacements.
- Avoid colon-after-variable parsing issues in strings (`$($var):` pattern).
- Keep behavior deterministic and artifact paths stable.

Acceptance for any follow-on prompt:
- Existing tests still pass.
- No regression to output contract or redaction behavior.
- Documentation and implementation remain consistent.
