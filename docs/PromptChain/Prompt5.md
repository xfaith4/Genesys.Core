Implement the next endpoint-expansion wave from roadmap backlog.

Target endpoints:
1. `GET /api/v2/authorization/roles`
2. `GET /api/v2/conversations/{conversationId}/recordings`
3. `GET /api/v2/oauth/clients`
4. `POST /api/v2/oauth/clients/{clientId}/usage/query`
5. `GET /api/v2/oauth/clients/{clientId}/usage/query/results/{executionId}`
6. `GET /api/v2/speechandtextanalytics/topics`
7. `POST /api/v2/analytics/transcripts/aggregates/query`
8. `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/communications/{communicationId}/transcripturl`

Files:
- `genesys.catalog.json`
- `catalog/genesys.catalog.json` (legacy mirror update until retirement)
- `tests/CatalogSchema.Tests.ps1`
- `tests/AdditionalDatasets.Tests.ps1` (or targeted new dataset tests)

Requirements:
- Add schema-valid endpoint definitions with method/path/itemsPath/paging/retry.
- Add dataset keys where simple collection behavior is sufficient.
- For multi-step flows (usage query + results, transcript retrieval patterns), decide:
  - curated handler, or
  - transaction profile + generic orchestration
- Keep retry/paging deterministic and observable through run events.
- Ensure no secret/token leakage in logs or output artifacts.

Acceptance:
- Catalog validation passes.
- Dataset execution for new keys is covered by mocked tests.
- No regressions to existing curated datasets.

