# Transfer Report Findings

## Current Session

- No prior task_plan.md, progress.md, or findings.md existed in the repo root.
- Worktree already contains many modified files; changes must stay scoped to the requested phase.
- `apps/AuditLogsConsole/App.Database.psm1` does not exist; the Session 15/16 report pattern is in `apps/ConversationAnalyser/modules/App.Database.psm1` and companion ConversationAnalyser files.
- `apps/ConversationAnalyser/modules/App.Database.psm1` already has `$script:SchemaVersion = 7`, v7 `report_transfer_flows` and `report_transfer_chains` DDL/indexes, `Import-TransferReport`, `Get-TransferFlowRows`, `Get-TransferChainRows`, `Get-TransferSummary`, and exports.
- `apps/ConversationAnalyser/modules/App.CoreAdapter.psm1` already has `Get-TransferReport` following the Session 14/15 report folder-map pattern.
- Catalog `analytics.query.conversation.aggregates.transfer.metrics` emits `nTransferred`, `nBlindTransferred`, `nConsultTransferred`, and `nConnected`; the import denominator now prefers `nOffered` when available, then `nConnected`, then `nTransferred`.
