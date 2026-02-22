Strengthen catalog integrity checks for the current mixed catalog model.

Files:
- `catalog/schema/genesys-core.catalog.schema.json`
- `tests/CatalogSchema.Tests.ps1`
- `src/ps-module/Genesys.Core/Private/Assert-Catalog.ps1`
- `tests/CatalogResolution.Tests.ps1`

Requirements:
- Preserve compatibility for both endpoint shapes:
  - keyed object (`endpoints.<operationId>`)
  - canonical array shape used after runtime normalization
- Validate that each dataset has:
  - `endpoint`
  - `itemsPath`
  - `paging.profile`
  - `retry.profile`
- Validate that every dataset endpoint reference resolves to an endpoint definition.
- Keep strict-mode behavior for root-vs-legacy catalog mismatch.
- Do not over-constrain profile names to a hardcoded enum; profile keys are catalog-defined.

Tests:
- Add negative tests for missing/invalid dataset endpoint references.
- Keep tests for missing required dataset and endpoint fields.
- Ensure catalog resolution precedence behavior remains covered.

Acceptance:
- Pester fails on unresolved endpoint references and missing required fields.
- Pester passes for current canonical catalog and legacy compatibility shape.
