# Changelog

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
