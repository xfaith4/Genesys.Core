Implement the request engine with deterministic retry/backoff.

Files:
- src/ps-module/Genesys.Core/Private/Invoke-GcRequest.ps1
- src/ps-module/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1
- tests/Retry.Tests.ps1

Requirements:
- Handles 429 using Retry-After header when present.
- Also parses error messages containing: "Retry the request in [x] seconds".
- Bounded retries, jitter, emits run events (as objects; writer implemented later).
- GET retries allowed; POST should be configurable (default: retry safe/idempotent only).

Acceptance:
- Unit tests cover parsing and bounded retry behavior.
