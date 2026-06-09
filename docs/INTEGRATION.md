# INTEGRATION GUIDE — Genesys.Core + Genesys.MockServer

This guide shows how to wire `Genesys.Core` to the `Genesys.MockServer` HTTP demo server so
that `Invoke-Dataset` (and `GenesysInterrogator`) work without a live Genesys Cloud API key.

---

## Prerequisites

| Requirement | Minimum Version |
|---|---|
| .NET SDK | 8.0+ |
| PowerShell | 7.2+ |
| Genesys.Core module | any |

---

## Quick Start (HTTP Server)

### 1 — Start the demo server

```powershell
pwsh -NoProfile -File ./scripts/Start-MockServer.ps1
```

This starts the server on `http://localhost:7777` and prints:

```
  Genesys.MockServer
  ==================
  Port           : 7777
  Demo bearer token:
    demo-bearer-token-genesys-testplatform

  Quick connect from Genesys.Core:
    $headers = @{ Authorization = "******" }
    Invoke-Dataset -Dataset users -BaseUri http://localhost:7777 -Headers $headers
```

### 2 — Run Invoke-Dataset against the demo server

```powershell
Import-Module ./modules/Genesys.Core/Genesys.Core.psd1 -Force

$headers = @{ Authorization = '******' }
$params  = @{
    BaseUri    = 'http://localhost:7777'
    Headers    = $headers
    OutputRoot = './out/demo'
}

# Run individual datasets
Invoke-Dataset -Dataset 'users'                              @params
Invoke-Dataset -Dataset 'routing-queues'                     @params
Invoke-Dataset -Dataset 'audit-logs'                         @params
Invoke-Dataset -Dataset 'analytics-conversation-details'     @params
Invoke-Dataset -Dataset 'analytics-conversation-details-query' @params
```

---

## Quick Start (In-Process, No Server Required)

For unit-test scenarios where starting a server is undesirable, use `New-DemoRequestInvoker`:

```powershell
Import-Module ./modules/Genesys.Core/Genesys.Core.psd1 -Force

$invoker = New-DemoRequestInvoker

Invoke-Dataset -Dataset 'users' `
    -RequestInvoker $invoker `
    -OutputRoot './out/demo-inprocess'
```

This requires no network, no credentials, and no server process.

---

## GenesysInterrogator Integration

To run `GenesysInterrogator` against the demo server:

1. Start the demo server:
   ```powershell
   pwsh -NoProfile -File ./scripts/Start-MockServer.ps1
   ```

2. In the GenesysInterrogator UI, configure a new connection:
   - **Region / Base URI:** `http://localhost:7777`
   - **Auth type:** ****** (manual)
   - ******** `demo-bearer-token-genesys-testplatform`

3. Run any dataset from the GenesysInterrogator UI as normal.

---

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `MOCK_PORT` | TCP port to listen on | `7777` |
| `MOCK_CATALOG_PATH` | Path to `genesys.catalog.json` | `catalog/genesys.catalog.json` in repo root |
| `MOCK_FIXTURES_PATH` | Path to demo fixture JSON files | `tests/fixtures/demo` in repo root |
| `MOCK_POLLING_ROUNDS` | Polls before async job becomes FULFILLED | `2` |
| `MOCK_PAGE_SIZE` | Default page size for paged responses | `25` |

---

## Authentication

The demo server uses a fixed bearer token:

```
demo-bearer-token-genesys-testplatform
```

**OAuth token endpoint** (`POST /oauth/token`) accepts any `client_credentials` grant and returns
this token — no real credentials required.

**All `/api/v2/*` endpoints** require the `Authorization: ****** header.
Requests without a valid token return `401`.

---

## Running Integration Tests

Integration tests require the mock server to be available. They are skipped unless the
`-IncludeIntegration` flag is passed to the test runner:

```powershell
pwsh -NoProfile -File ./scripts/Invoke-Tests.ps1 -IncludeIntegration
```

The integration test suite (`tests/integration/MockServer.Integration.Tests.ps1`):

1. Starts `Genesys.MockServer` as a background process on port `7778`
2. Waits up to 30 seconds for the server to become ready
3. Runs `Invoke-Dataset` against the five Tier 1 datasets
4. Validates output file structure, manifest.json, and events.jsonl
5. Stops the server after all tests complete

---

## CI / CD

To run integration tests in CI without a real Genesys API key:

```yaml
- name: Start MockServer and run integration tests
  run: |
    dotnet build tools/Genesys.MockServer/Genesys.MockServer.csproj -c Release
    pwsh -NoProfile -File ./scripts/Invoke-Tests.ps1 -IncludeIntegration
```

No environment secrets are required.

---

## xUnit Tests for the Mock Server Itself

The mock server has its own test suite in `tools/Genesys.MockServer/tests/`:

```powershell
dotnet test tools/Genesys.MockServer/tests/Genesys.MockServer.Tests/Genesys.MockServer.Tests.csproj
```

These tests cover:
- Route coverage (every catalog endpoint has a registered route)
- Fixture schema validation (all fixture files round-trip through expected schema)
- Async job lifecycle (submit → poll → results)
- Paging correctness (nextUri and pageNumber profiles return correct totals)
- Auth validation (valid token → 200; missing/invalid token → 401)

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `dotnet: command not found` | Install .NET SDK 8+ from https://dot.net |
| Port 7777 already in use | Use `-Port 8888` parameter on Start-MockServer.ps1 |
| `401 Unauthorized` | Include `Authorization: ****** header |
| `404 Not Found` on a known endpoint | Verify the endpoint is in `catalog/genesys.catalog.json` |
| Empty fixture response | The endpoint has no fixture file; a skeleton response is returned automatically |
| Server not ready within 30 s | Increase timeout in integration test `Start-MockServer` function |
