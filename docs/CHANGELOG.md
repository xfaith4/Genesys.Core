# Changelog

## 2026-02-22

### Changed

- Reconciled repository documentation with current runtime behavior and catalog coverage.
- Updated `README.md` to reflect current dataset/endpoint counts and clarified that the repo is a Core runtime (not a packaged MCP server).
- Added explicit onboarding guide at `docs/ONBOARDING.md` with authenticated module-first usage.
- Updated readiness review to reflect current implemented scope and current operational caveats.
- Updated roadmap status and added planned endpoint backlog:
  - `GET /api/v2/authorization/roles`
  - `GET /api/v2/conversations/{conversationId}/recordings`
  - `GET /api/v2/oauth/clients`
  - `POST /api/v2/oauth/clients/{clientId}/usage/query`
  - `GET /api/v2/oauth/clients/{clientId}/usage/query/results/{executionId}`
  - `GET /api/v2/speechandtextanalytics/topics`
  - `POST /api/v2/analytics/transcripts/aggregates/query`
  - `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/communications/{communicationId}/transcripturl`
- Updated testing documentation with onboarding references and current workflow/artifact/auth caveats.

## 2026-02-18

### Added

- Added dataset implementations for `users` and `routing-queues` with catalog registration, paging-aware ingestion, normalization, and tests.
- Added smoke script `scripts/Invoke-Smoke.ps1` to run catalog validation and fixture-backed dataset ingests.

### Changed

- Introduced unified catalog loader (`Resolve-Catalog`) and canonical in-memory normalization.
- Canonical runtime precedence is now root `genesys-core.catalog.json`; `catalog/genesys-core.catalog.json` is treated as compatibility mirror.
- Added strict catalog mode (`-StrictCatalog`) to fail when root and mirror catalogs diverge.

### Migration notes

- Reconcile legacy mirror from canonical root:
  - `Copy-Item ./genesys-core.catalog.json ./catalog/genesys-core.catalog.json -Force`
- Existing callers passing `-CatalogPath` remain supported.
