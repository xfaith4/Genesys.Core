Implement paging strategies with a common interface.

Files:
- src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingNextUri.ps1
- src/ps-module/Genesys.Core/Private/Paging/Invoke-PagingPageNumber.ps1
- src/ps-module/Genesys.Core/Private/Invoke-CoreEndpoint.ps1
- tests/Paging.Tests.ps1

Interface:
- Input: endpoint spec + initial uri/body + headers + retry profile
- Output: streamed items and paging telemetry
- Must emit progress events like: page=, nextUri=, totalHits= if known

Acceptance:
- Tests with mocked responses verify correct enumeration and termination.
