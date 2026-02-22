# Comparison Report (as of 2026-02-22) #

I compared your local Genesys Core repo (`g:\Development\20_Staging\Genesys.Core`) with `MakingChatbots/genesys-cloud-mcp-server` at commit `b0ca3a0` (2025-12-04).

Note: this report was generated before the documentation reconciliation pass completed on 2026-02-22. Any documentation-gap findings below should be read as historical unless still explicitly listed as open.

## **Surface Area Summary** ##

- Local Genesys Core: 31 datasets in catalog, mapping to 29 unique dataset API paths; 74 endpoint definitions total (61 unique paths) from `genesys-core.catalog.json` (parsed locally).
- MakingChatbots MCP: 10 MCP tools, 17 unique API paths from `docs/tools.md` and `manifest.json`.

## **Similar Endpoints (Direct overlap at dataset/tool surface)** ##

1. `GET /api/v2/routing/queues`
   - Local: `routing-queues`
   - MCP: `search_queues`
2. `POST /api/v2/analytics/conversations/details/jobs`
   - Local: `analytics-conversation-details`
   - MCP: `query_queue_volumes`, `sample_conversations_by_queue`
3. `POST /api/v2/analytics/conversations/details/query`
   - Local: `analytics-conversation-details-query`
   - MCP: `search_voice_conversations`
4. `GET /api/v2/analytics/conversations/details`
   - Local: `analytics.get.multiple.conversations.by.ids`
   - MCP: `voice_call_quality`
5. `GET /api/v2/authorization/divisions`
   - Local: `authorization.get.all.divisions`
   - MCP: `oauth_clients`

## **Additional overlap in local catalog (not exposed as dataset keys)** ##

- `GET /api/v2/analytics/conversations/{conversationId}/details`
- `GET /api/v2/analytics/conversations/details/jobs/{jobId}`
- `GET /api/v2/analytics/conversations/details/jobs/{jobId}/results`
- `GET /api/v2/speechandtextanalytics/conversations/{conversationId}`

## **Unique Endpoints** ##

Remote MCP unique (not found in local endpoint catalog):

1. `GET /api/v2/authorization/roles`
2. `GET /api/v2/conversations/{conversationId}/recordings`
3. `GET /api/v2/oauth/clients`
4. `POST /api/v2/oauth/clients/{clientId}/usage/query`
5. `GET /api/v2/oauth/clients/{clientId}/usage/query/results/{executionId}`
6. `GET /api/v2/speechandtextanalytics/topics`
7. `POST /api/v2/analytics/transcripts/aggregates/query`
8. `GET /api/v2/speechandtextanalytics/conversations/{conversationId}/communications/{communicationId}/transcripturl`

Local dataset-surface unique (not used by remote MCP tools):

1. `POST /api/v2/audits/query`
2. `GET /api/v2/audits/query`
3. `GET /api/v2/audits/query/servicemapping`
4. `GET /api/v2/conversations`
5. `GET /api/v2/conversations/callbacks`
6. `GET /api/v2/conversations/calls`
7. `GET /api/v2/conversations/calls/history`
8. `GET /api/v2/conversations/chats`
9. `GET /api/v2/conversations/emails`
10. `GET /api/v2/notifications/availabletopics`
11. `GET /api/v2/notifications/channels`
12. `GET /api/v2/organizations/me`
13. `GET /api/v2/organizations/limits/namespaces`
14. `GET /api/v2/presencedefinitions`
15. `GET /api/v2/systempresences`
16. `GET /api/v2/routing/languages`
17. `GET /api/v2/routing/skills`
18. `GET /api/v2/routing/wrapupcodes`
19. `GET /api/v2/usage/query/organization`
20. `GET /api/v2/usage/query/clients`
21. `GET /api/v2/usage/query/users`
22. `GET /api/v2/users`
23. `GET /api/v2/users/presences/purecloud/bulk`
24. `GET /api/v2/users/search`

**Which is easier for another application to utilize (design)?**

- For MCP-native apps (Claude/Gemini/OpenAI MCP clients): `MakingChatbots/genesys-cloud-mcp-server` is easier.
  - It is an actual MCP server with `registerTool` calls and stdio transport (`.tmp_compare/genesys-cloud-mcp-server/src/index.ts:49`, `.tmp_compare/genesys-cloud-mcp-server/src/index.ts:177`).
  - It provides install-ready packaging via npm + MCP bundle (`.tmp_compare/genesys-cloud-mcp-server/README.md:23`, `.tmp_compare/genesys-cloud-mcp-server/manifest.json:26`).
- For governed data pipeline integration: local Genesys Core is easier.
  - Catalog-driven execution, deterministic artifacts, structured events, retry/paging profiles, PS 5.1 support (`README.md:15`, `README.md:20`, `src/ps-module/Genesys.Core/Private/Invoke-CoreEndpoint.ps1:56`, `src/ps-module/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1:33`, `src/ps-module/Genesys.Core/Genesys.Core.psd1:9`).

Inference: local repo is currently a Core engine rather than a packaged MCP server (no MCP server classes/registration in `src/`).

**Documentation and usability quality**

- MakingChatbots MCP strengths:
  - Clear per-tool docs with inputs, permissions, and exact API endpoints (`.tmp_compare/genesys-cloud-mcp-server/docs/tools.md:5`, `.tmp_compare/genesys-cloud-mcp-server/docs/tools.md:21`, `.tmp_compare/genesys-cloud-mcp-server/docs/tools.md:25`).
  - Practical setup for Claude and Gemini (`.tmp_compare/genesys-cloud-mcp-server/README.md:23`, `.tmp_compare/genesys-cloud-mcp-server/README.md:58`).
- MakingChatbots MCP gaps:
  - Project explicitly marked “Under active development” (`.tmp_compare/genesys-cloud-mcp-server/README.md:99`).
  - Async polling/retry logic is tool-specific and fixed-attempt based rather than centrally policy-driven (`queryQueueVolumes.ts:18`, `queryQueueVolumes.ts:102`; `sampleConversationsByQueue.ts:18`, `sampleConversationsByQueue.ts:98`).
- Local Genesys Core strengths:
  - Strong governance/testing posture (schema validation, paging/retry/redaction/run-contract tests) (`TESTING.md:47`, `TESTING.md:57`, `TESTING.md:64`, `TESTING.md:76`, `TESTING.md:82`).
  - Centralized retry/paging engine behavior with profile-based routing (`src/ps-module/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1:53`, `src/ps-module/Genesys.Core/Private/Invoke-CoreEndpoint.ps1:56`).
- Local Genesys Core gaps:
  - Workflow auth ergonomics still require environment-specific wiring before production automation.
  - Standalone script-level invocation does not currently expose `-Headers` and `-BaseUri` parameters.

**Bottom line**

- If your target consumer is an MCP client application today, the MakingChatbots server is the easier integration.
- If your target is governed, auditable, repeatable data extraction workflows (and you can wrap a tool layer yourself), your local Genesys Core design is stronger and broader.

**External source links used**

- <https://github.com/MakingChatbots/genesys-cloud-mcp-server>
- <https://github.com/MakingChatbots/genesys-cloud-mcp-server/blob/b0ca3a0cd38e81a37f059fbcb746d9073650e352/README.md>
- <https://github.com/MakingChatbots/genesys-cloud-mcp-server/blob/b0ca3a0cd38e81a37f059fbcb746d9073650e352/docs/tools.md>
- <https://github.com/MakingChatbots/genesys-cloud-mcp-server/blob/b0ca3a0cd38e81a37f059fbcb746d9073650e352/src/index.ts>
- <https://github.com/MakingChatbots/genesys-cloud-mcp-server/blob/b0ca3a0cd38e81a37f059fbcb746d9073650e352/manifest.json>
