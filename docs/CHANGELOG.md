# Changelog

## 2026-03-07

### Changed

- Documentation modernization pass (Batch 1):
  - Updated `README.md` repository layout to match actual structure (added `Genesys.Auth`, `Genesys.Ops`, `apps/ConversationAnalysis`; corrected test paths to `tests/unit/`); removed non-doc "Topics to Add on GitHub" and "Alternative Names" sections; added cross-link to `TESTING.md`; fixed `AGENTS.md` reference path.
  - Updated `TESTING.md` test file paths from `tests/` to `tests/unit/`; corrected stale caveat about script-level parameter exposure; fixed `AGENTS.md` link.
  - Updated `docs/ONBOARDING.md` with Table of Contents and a new Conversation Analysis app section.
  - Rewrote `docs/REPO_SCHEMATIC.md` tree to match actual repository structure (removed phantom root shims, added `apps/`, `Public/Assert-Catalog.ps1`, `Http/`; added Conversation Analysis to Canonical Defaults).
  - Updated `docs/READINESS_REVIEW.md` to correct stale caveat about script-level `-Headers`/`-BaseUri` exposure.



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
- Canonical runtime precedence is now `catalog/genesys.catalog.json`.
- Added strict catalog mode (`-StrictCatalog`) to fail when canonical catalog is missing.

### Migration notes

- Ensure the canonical catalog is present:
  - `catalog/genesys.catalog.json`
- Existing callers passing `-CatalogPath` remain supported.

