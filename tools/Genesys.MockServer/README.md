# Genesys.MockServer

A high-fidelity **offline implementation of the interface applications normally receive from
Genesys Cloud**. It is not a toy stub: applications move between real Genesys Cloud and this
server without knowing or caring which side is supplying the data.

```text
Genesys Cloud                  Genesys.Core Mock
     ↕                                ↕
Genesys.Core          or        Application
     ↕
Application
```

## Running

```bash
dotnet run --project tools/Genesys.MockServer
```

Listens on `http://localhost:7777`. Every `/api/**` route requires the demo bearer token:

```text
Authorization: Bearer demo-bearer-token-genesys-testplatform
```

`POST /oauth/token` with `grant_type=client_credentials` still returns that fixed token, so
existing scripts and the PowerShell modules keep working. Browser clients should use the PKCE flow
below instead, which issues per-session tokens.

## Demo authorization server (OAuth 2.0 + PKCE)

Shaped like the Genesys Cloud endpoints at `login.{region}`, so a client needs only a different
base URL to talk to a real org.

| Route | Purpose |
| --- | --- |
| `GET /oauth/authorize` | Consent screen; validates `code_challenge` and `code_challenge_method=S256` |
| `POST /oauth/authorize` | The consent decision; redirects with `?code=&state=` or `?error=` |
| `POST /oauth/token` | `authorization_code`, `refresh_token`, `client_credentials` |
| `GET /oauth/userinfo` | The demo identity behind a bearer token |
| `POST /oauth/revoke` | Drops a token |

**The identity is fake; the protocol is real.** The server verifies
`BASE64URL(SHA256(ASCII(code_verifier)))` against the stored challenge in constant time, refuses
`plain`, refuses a request carrying no challenge, binds each code to the client and redirect URI it
was issued for, consumes a code on the first redemption attempt even when the verifier was wrong,
and rotates refresh tokens. Errors use the RFC 6749 `{error, error_description}` shape.

That matters because it means a client's PKCE code path is genuinely exercised offline rather than
stubbed out.

The consent screen collects **no credentials** — it has no username or password field and states
plainly that nothing is checked. It exists to make the authorization step visible, not to imitate
a sign-in.

API requests accept either the fixed demo token or any unexpired token minted through this flow.

### Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `MOCK_PORT` | `7777` | Listen port |
| `MOCK_CATALOG_PATH` | `catalog/genesys.catalog.json` | Endpoint catalog |
| `MOCK_FIXTURES_PATH` | `tests/fixtures/demo` | Demo fixtures |
| `MOCK_POLLING_ROUNDS` | `2` | Polls before an async job reaches `FULFILLED` |
| `MOCK_CORS_ORIGINS` | `*` | Comma-separated allowed origins |
| `MOCK_STATIC_ROOT` | `apps/GenesysDataClient/dist` | Optional static app to host |

## What it serves

All 3,389 catalog endpoints are registered. **48 of them return real demo data**; the rest answer
with a shape-correct empty envelope, which still exercises paging, auth and error handling.

Which routes are backed by data is declared once, in
[`FixtureCoverage.cs`](FixtureCoverage.cs). `RouteDispatcher` executes that table and the
discovery API reports it, so a client's endpoint outline can never drift from what the
dispatcher actually does.

| Coverage | Meaning |
| --- | --- |
| `fixture` | Served verbatim from a demo fixture |
| `paged-fixture` | Two pages linked by `nextUri` |
| `cursor-fixture` | Two pages linked by an opaque cursor |
| `async-submit` | Creates a job and returns its id |
| `async-poll` | Walks `QUEUED` → `RUNNING` → `FULFILLED` |
| `inline` | Synthesized in code rather than from a fixture |
| `generated` | No demo data; shape-correct empty envelope |

## Discovery API

Unauthenticated, because it describes the server rather than exposing Genesys data. This is how a
client renders an accurate endpoint outline without bundling the 1.6 MB catalog.

| Route | Returns |
| --- | --- |
| `GET /health` | Liveness probe |
| `GET /__meta` | Server, catalog and coverage counts |
| `GET /__meta/groups` | Endpoint groups with per-group demo-data counts |
| `GET /__meta/endpoints` | Filterable endpoint list (`group`, `coverage`, `method`, `q`, `demoData`, `limit`, `offset`) |
| `GET /__meta/endpoints/{key}` | One endpoint with notes, default body and fixture presence |
| `GET /__meta/coverage` | The coverage rule table and the endpoints each rule claims |
| `GET /__meta/datasets` | Catalog dataset definitions |

Endpoints backed by demo data sort first, because those are the ones worth exercising.

```bash
curl -s localhost:7777/__meta | jq .counts
curl -s 'localhost:7777/__meta/endpoints?demoData=true&limit=5' | jq '.items[].path'
```

## Hosting the Genesys Data Client

When `apps/GenesysDataClient/dist/index.html` exists, the server also hosts it at `/`, so the
whole demo runs from one process with no Node at runtime. Client-side routes fall through to the
SPA shell while `/api`, `/__meta` and `/oauth` keep answering as JSON.

This is an integration convenience only — the frontend is never part of the server. See
[docs/GenesysDataClient.md](../../docs/GenesysDataClient.md).

## Tests

```bash
dotnet test tools/Genesys.MockServer/tests/Genesys.MockServer.Tests/Genesys.MockServer.Tests.csproj
```

24 tests covering auth, paging, both async lifecycles, the coverage table (including guards
against dead rules and missing fixtures) and the discovery API.
