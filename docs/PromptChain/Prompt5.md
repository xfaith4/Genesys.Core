Implement Dataset: audit-logs.

Catalog entries required for:
- GET  /api/v2/audits/query/servicemapping
- POST /api/v2/audits/query
- GET  /api/v2/audits/query/{transactionId}
- GET  /api/v2/audits/query/{transactionId}/results

Implement transactionResults paging profile:
- submit -> transactionId
- poll status until terminal
- fetch results using configured paging strategy (likely nextUri or pageNumber depending on response shape)

Files:
- src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1
- src/ps-module/Genesys.Core/Private/Datasets/Invoke-AuditLogsDataset.ps1
- src/ps-module/Genesys.Core/Private/Async/Invoke-AuditTransaction.ps1
- tests/AuditLogs.Dataset.Tests.ps1 (use mocked HTTP)

Outputs:
- data/audit.jsonl(.gz optional later)
- summary.json with counts by action/serviceName and basic totals

Acceptance:
- Pester passes with mocked transaction flow and paged results.
