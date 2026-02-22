Maintain the paging strategy engine and keep termination behavior deterministic.

Files:
- `src/ps-module/Genesys.Core/Private/Invoke-CoreEndpoint.ps1`
- `src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingNextUri.ps1`
- `src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingPageNumber.ps1`
- `src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingCursor.ps1`
- `src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingBodyPaging.ps1`
- `tests/Paging.Tests.ps1`

Current supported paging profiles (must remain):
- `none`
- `nextUri`
- `pageNumber`
- `cursor`
- `bodyPaging`
- `transactionResults` (orchestration path via async job flow)

Requirements:
- Preserve shared interface:
  - input: endpoint spec + uri/body + headers + retry/runtime settings
  - output: item collection + paging telemetry + run events
- Keep termination safeguards:
  - duplicate `nextUri` detection
  - empty-page and/or `totalHits` stop conditions
  - cursor-missing termination
- Keep profile normalization behavior (`nextUri_*`, etc.) stable and tested.

Acceptance:
- Paging tests verify enumeration, telemetry, and termination for all supported profile types.
