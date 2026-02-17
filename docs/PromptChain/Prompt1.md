Implement a real catalog schema and validation tests.

Files:
- catalog/schema/genesys-core.catalog.schema.json
- tests/CatalogSchema.Tests.ps1
- src/ps-module/Genesys.Core/Private/Assert-Catalog.ps1

Schema must require per endpoint:
- key, method, path
- itemsPath
- paging.profile (enum: none,nextUri,pageNumber,cursor,bodyPaging,transactionResults)
- retry.profile (enum: standard, rateLimitAware)
- optional transaction.profile (enum: none, auditTransaction)

Tests:
- Fail if any endpoint lacks itemsPath or paging.profile.
- Provide a small example catalog entry in catalog/genesys-core.catalog.json.

Acceptance:
- Pester fails on missing required fields.
- Pester passes with the sample entry.
