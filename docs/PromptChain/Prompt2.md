Harden and extend retry/runtime behavior from the existing implementation.

Files:
- `src/ps-module/Genesys.Core/Private/Invoke-GcRequest.ps1`
- `src/ps-module/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1`
- `src/ps-module/Genesys.Core/Private/Retry/Resolve-RetryRuntimeSettings.ps1`
- `tests/Retry.Tests.ps1`

Current behavior already implemented (must remain):
- HTTP 429 handling via `Retry-After` header (seconds or date).
- Message parsing: `Retry the request in [x] seconds`.
- Bounded retries with jitter and structured retry events.
- POST retry is explicit/controlled.

Enhancement targets:
- Verify deterministic behavior when random seed is provided.
- Ensure RetrySettings profile merging precedence is documented and tested.
- Expand coverage for non-retryable status handling and terminal failure events.
- Keep request logging sanitized (no auth headers, no token-bearing query values).

Acceptance:
- Existing retry tests remain green.
- New tests cover profile-precedence and deterministic jitter behavior.
