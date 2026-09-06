using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Genesys.MockServer.Tests;

/// <summary>
/// Unit and integration tests for the Genesys.MockServer demo server.
/// These tests resolve the catalog and fixtures from the repo root,
/// matching how the server is configured when launched from the repository.
/// </summary>
public sealed class MockServerTests : IClassFixture<MockServerFactory>
{
    private readonly HttpClient _client;
    private readonly MockServerFactory _factory;

    /// <summary>
    /// The OAuth tests assert on redirects themselves, so this client must not follow them -
    /// otherwise the assertion sees the status of the redirect target instead of the 302.
    /// </summary>
    private readonly HttpClient _noRedirect;

    public MockServerTests(MockServerFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _noRedirect = factory.CreateClient(new Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    // ─── Auth tests ──────────────────────────────────────────────────────────

    [Fact]
    public async Task Health_endpoint_returns_ok_without_auth()
    {
        var response = await _client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.Equal("ok", body?["status"]?.GetValue<string>());
    }

    [Fact]
    public async Task Api_endpoint_without_auth_returns_401()
    {
        // No Authorization header
        var response = await _client.GetAsync("/api/v2/users");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Api_endpoint_with_wrong_token_returns_401()
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, "/api/v2/users");
        req.Headers.Add("Authorization", "Bearer not-the-demo-token");
        var response = await _client.SendAsync(req);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Oauth_token_endpoint_issues_demo_token()
    {
        var formData = new FormUrlEncodedContent(new[]
        {
            new KeyValuePair<string, string>("grant_type", "client_credentials"),
            new KeyValuePair<string, string>("client_id", "any-id"),
            new KeyValuePair<string, string>("client_secret", "any-secret")
        });
        var response = await _client.PostAsync("/oauth/token", formData);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.Equal(RouteDispatcher.DemoBearerToken, body?["access_token"]?.GetValue<string>());
        Assert.Equal("bearer", body?["token_type"]?.GetValue<string>());
    }

    // ─── Users ───────────────────────────────────────────────────────────────

    [Fact]
    public async Task Users_page1_returns_entities_with_nextUri()
    {
        var req = AuthedGet("/api/v2/users");
        var response = await _client.SendAsync(req);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.NotNull(body);
        var entities = body["entities"]?.AsArray();
        Assert.NotNull(entities);
        Assert.True(entities.Count > 0, "Expected at least one user on page 1");
        Assert.NotNull(body["nextUri"]);
    }

    [Fact]
    public async Task Users_page2_returns_entities_with_null_nextUri()
    {
        var req = AuthedGet("/api/v2/users?pageNumber=2");
        var response = await _client.SendAsync(req);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.NotNull(body);
        var entities = body["entities"]?.AsArray();
        Assert.NotNull(entities);
        Assert.True(entities.Count > 0, "Expected at least one user on page 2");
        Assert.True(body["nextUri"] is null || body["nextUri"]?.GetValueKind() == System.Text.Json.JsonValueKind.Null,
            "nextUri should be null on final page");
    }

    // ─── Routing queues ──────────────────────────────────────────────────────

    [Fact]
    public async Task RoutingQueues_returns_entities()
    {
        var req = AuthedGet("/api/v2/routing/queues");
        var response = await _client.SendAsync(req);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        var entities = body?["entities"]?.AsArray();
        Assert.NotNull(entities);
        Assert.True(entities.Count > 0);
    }

    // ─── Audit logs async flow ───────────────────────────────────────────────

    [Fact]
    public async Task AuditLogs_submit_poll_results_lifecycle()
    {
        // 1. Submit
        var submitReq = new HttpRequestMessage(HttpMethod.Post, "/api/v2/audits/query");
        submitReq.Headers.Add("Authorization", $"Bearer {RouteDispatcher.DemoBearerToken}");
        submitReq.Content = new StringContent("{}", System.Text.Encoding.UTF8, "application/json");
        var submitResp = await _client.SendAsync(submitReq);
        Assert.Equal(HttpStatusCode.OK, submitResp.StatusCode);
        var submitBody = await submitResp.Content.ReadFromJsonAsync<JsonObject>();
        var txId = submitBody?["id"]?.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(txId));

        // 2. Poll until FULFILLED (up to 5 attempts)
        string? state = null;
        for (var i = 0; i < 5; i++)
        {
            var pollReq = AuthedGet($"/api/v2/audits/query/{txId}");
            var pollResp = await _client.SendAsync(pollReq);
            Assert.Equal(HttpStatusCode.OK, pollResp.StatusCode);
            var pollBody = await pollResp.Content.ReadFromJsonAsync<JsonObject>();
            state = pollBody?["state"]?.GetValue<string>();
            if (state == "FULFILLED") break;
        }
        Assert.Equal("FULFILLED", state);

        // 3. Fetch results page 1
        var resultsReq = AuthedGet($"/api/v2/audits/query/{txId}/results");
        var resultsResp = await _client.SendAsync(resultsReq);
        Assert.Equal(HttpStatusCode.OK, resultsResp.StatusCode);
        var resultsBody = await resultsResp.Content.ReadFromJsonAsync<JsonObject>();
        var results = resultsBody?["results"]?.AsArray();
        Assert.NotNull(results);
        Assert.True(results.Count > 0);
        Assert.NotNull(resultsBody?["nextUri"]);
    }

    // ─── Analytics jobs async flow ───────────────────────────────────────────

    [Fact]
    public async Task Analytics_submit_poll_results_lifecycle()
    {
        // 1. Submit
        var submitReq = new HttpRequestMessage(HttpMethod.Post, "/api/v2/analytics/conversations/details/jobs");
        submitReq.Headers.Add("Authorization", $"Bearer {RouteDispatcher.DemoBearerToken}");
        submitReq.Content = new StringContent("{\"interval\":\"2026-02-01T00:00:00.000Z/2026-02-28T23:59:59.999Z\"}",
            System.Text.Encoding.UTF8, "application/json");
        var submitResp = await _client.SendAsync(submitReq);
        Assert.Equal(HttpStatusCode.OK, submitResp.StatusCode);
        var submitBody = await submitResp.Content.ReadFromJsonAsync<JsonObject>();
        var jobId = submitBody?["jobId"]?.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(jobId));

        // 2. Poll until FULFILLED
        string? state = null;
        for (var i = 0; i < 5; i++)
        {
            var pollReq = AuthedGet($"/api/v2/analytics/conversations/details/jobs/{jobId}");
            var pollResp = await _client.SendAsync(pollReq);
            var pollBody = await pollResp.Content.ReadFromJsonAsync<JsonObject>();
            state = pollBody?["state"]?.GetValue<string>();
            if (state == "FULFILLED") break;
        }
        Assert.Equal("FULFILLED", state);

        // 3. Fetch results — page 1
        var resultsReq = AuthedGet($"/api/v2/analytics/conversations/details/jobs/{jobId}/results");
        var resultsResp = await _client.SendAsync(resultsReq);
        Assert.Equal(HttpStatusCode.OK, resultsResp.StatusCode);
        var resultsBody = await resultsResp.Content.ReadFromJsonAsync<JsonObject>();
        var convs = resultsBody?["conversations"]?.AsArray();
        Assert.NotNull(convs);
        Assert.True(convs.Count > 0);
    }

    // ─── Unknown endpoint ─────────────────────────────────────────────────────

    [Fact]
    public async Task Unknown_path_returns_404_with_genesys_error_shape()
    {
        var req = AuthedGet("/api/v2/totally/unknown/endpoint/that/doesnt/exist");
        var response = await _client.SendAsync(req);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.Equal(404, body?["status"]?.GetValue<int>());
        Assert.Equal("not.found", body?["code"]?.GetValue<string>());
    }

    // ─── CatalogLoader unit tests ─────────────────────────────────────────────

    [Fact]
    public void CatalogLoader_loads_endpoints_from_catalog()
    {
        var loader = _factory.GetCatalogLoader();
        Assert.True(loader.Endpoints.Count > 0, "Expected at least one endpoint in catalog");
    }

    [Fact]
    public void CatalogLoader_matches_users_endpoint()
    {
        var loader = _factory.GetCatalogLoader();
        var match = loader.Match("GET", "/api/v2/users");
        Assert.NotNull(match);
        Assert.Equal("GET", match.Method);
    }

    [Fact]
    public void CatalogLoader_matches_parameterized_paths()
    {
        var loader = _factory.GetCatalogLoader();
        var match = loader.Match("GET", "/api/v2/audits/query/some-transaction-id-123");
        Assert.NotNull(match);
    }

    // ─── AsyncJobEngine unit tests ────────────────────────────────────────────

    [Fact]
    public void AsyncJobEngine_submit_poll_lifecycle()
    {
        var engine = new AsyncJobEngine(pollingRoundsBeforeFulfilled: 2);
        var jobId = engine.CreateJob(AsyncJobKind.Analytics);
        Assert.False(string.IsNullOrWhiteSpace(jobId));

        var poll1 = engine.PollJob(jobId);
        Assert.NotEqual("FULFILLED", poll1);

        var poll2 = engine.PollJob(jobId);
        Assert.Equal("FULFILLED", poll2);
    }

    [Fact]
    public void AsyncJobEngine_unknown_job_returns_NOT_FOUND()
    {
        var engine = new AsyncJobEngine();
        var state = engine.PollJob("nonexistent-job-id");
        Assert.Equal("NOT_FOUND", state);
    }

    // ─── Fixture coverage table ───────────────────────────────────────────────

    [Fact]
    public void Every_coverage_rule_matches_at_least_one_catalog_endpoint()
    {
        var loader = _factory.GetCatalogLoader();
        var dead = new List<string>();

        foreach (var rule in FixtureCoverage.Rules)
        {
            var matches = loader.Endpoints.Values
                .Any(e => FixtureCoverage.FindForTemplate(e.Method, e.Path)?.Id == rule.Id);
            if (!matches) dead.Add(rule.Id);
        }

        Assert.True(dead.Count == 0,
            $"Coverage rules match no catalog endpoint (dead rules): {string.Join(", ", dead)}");
    }

    [Fact]
    public void Every_fixture_referenced_by_a_coverage_rule_exists_on_disk()
    {
        var dispatcher = _factory.Services.GetRequiredService<RouteDispatcher>();
        var missing = FixtureCoverage.Rules
            .SelectMany(r => r.Fixtures.Select(f => new { r.Id, File = f }))
            .Where(x => !dispatcher.FixtureExists(x.File))
            .Select(x => $"{x.Id} -> {x.File}")
            .ToList();

        Assert.True(missing.Count == 0,
            $"Coverage rules reference missing fixtures: {string.Join(", ", missing)}");
    }

    [Fact]
    public void Coverage_lookup_is_consistent_between_template_and_concrete_path()
    {
        // A parameterized template must resolve to the same rule as a real request path.
        var viaTemplate = FixtureCoverage.FindForTemplate("GET", "/api/v2/conversations/{conversationId}/recordings");
        var viaConcrete = FixtureCoverage.Find("GET", "/api/v2/conversations/conv-v001-voice-inbound/recordings");

        Assert.NotNull(viaTemplate);
        Assert.NotNull(viaConcrete);
        Assert.Equal(viaTemplate.Id, viaConcrete.Id);
        Assert.Equal("conversations.recordings", viaConcrete.Id);
    }

    [Fact]
    public void Audit_results_rule_wins_over_audit_poll_rule()
    {
        // Rule order matters: the results path also contains the poll path prefix.
        var poll = FixtureCoverage.Find("GET", "/api/v2/audits/query/tx-123");
        var results = FixtureCoverage.Find("GET", "/api/v2/audits/query/tx-123/results");

        Assert.Equal("audits.query-poll", poll?.Id);
        Assert.Equal("audits.query-results", results?.Id);
    }

    // ─── Metadata API ─────────────────────────────────────────────────────────

    [Fact]
    public async Task Meta_overview_is_reachable_without_auth()
    {
        var response = await _client.GetAsync("/__meta");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.Equal("Genesys.MockServer", body?["server"]?.GetValue<string>());
        Assert.True(body?["counts"]?["endpoints"]?.GetValue<int>() > 0);
        Assert.True(body?["counts"]?["withDemoData"]?.GetValue<int>() > 0);
    }

    [Fact]
    public async Task Meta_endpoints_can_be_filtered_to_those_with_demo_data()
    {
        var response = await _client.GetAsync("/__meta/endpoints?demoData=true&limit=500");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        var items = body?["items"]?.AsArray();
        Assert.NotNull(items);
        Assert.True(items.Count > 0, "Expected at least one endpoint backed by demo data");

        // Every returned endpoint must genuinely claim demo data.
        foreach (var item in items)
        {
            Assert.True(item?["hasDemoData"]?.GetValue<bool>());
            Assert.NotEqual("generated", item?["coverage"]?.GetValue<string>());
        }
    }

    [Fact]
    public async Task Meta_endpoint_detail_reports_coverage_and_fixture_presence()
    {
        // Locate whichever catalog key the users.list rule claims rather than assuming one.
        var list = await _client.GetFromJsonAsync<JsonObject>("/__meta/endpoints?demoData=true&limit=500");
        var target = list?["items"]?.AsArray()
            .FirstOrDefault(i => i?["coverageId"]?.GetValue<string>() == "users.list");
        Assert.NotNull(target);

        var key = target["key"]?.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(key));

        var response = await _client.GetAsync($"/__meta/endpoints/{key}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.Equal("paged-fixture", body?["coverage"]?.GetValue<string>());
        Assert.Equal("users.list", body?["coverageId"]?.GetValue<string>());

        var fixtures = body?["fixtures"]?.AsArray();
        Assert.NotNull(fixtures);
        Assert.True(fixtures.Count > 0);
        Assert.All(fixtures, f => Assert.True(f?["present"]?.GetValue<bool>()));
    }

    [Fact]
    public async Task Meta_endpoint_detail_returns_404_for_unknown_key()
    {
        var response = await _client.GetAsync("/__meta/endpoints/no-such-endpoint-key");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Meta_groups_summarize_the_catalog()
    {
        var response = await _client.GetAsync("/__meta/groups");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        var items = body?["items"]?.AsArray();
        Assert.NotNull(items);
        Assert.True(items.Count > 0);
        Assert.All(items, g => Assert.False(string.IsNullOrWhiteSpace(g?["group"]?.GetValue<string>())));
    }

    // ─── Demo OAuth: PKCE ─────────────────────────────────────────────────────

    [Fact]
    public void S256_challenge_matches_the_RFC_7636_worked_example()
    {
        // RFC 7636 Appendix B. If this drifts, a real Genesys org would reject our exchanges.
        const string verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        const string expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";

        Assert.Equal(expected, DemoOAuth.ComputeS256Challenge(verifier));
    }

    [Fact]
    public async Task Authorize_without_a_code_challenge_is_refused()
    {
        var response = await _noRedirect.GetAsync(
            "/oauth/authorize?response_type=code&client_id=demo&redirect_uri=http%3A%2F%2Flocalhost%2F");

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var location = response.Headers.Location!.ToString();
        Assert.Contains("error=invalid_request", location);
        Assert.Contains("code_challenge", location);
    }

    [Fact]
    public async Task Authorize_with_an_unusable_redirect_uri_does_not_redirect()
    {
        // Refusing as a page rather than a redirect: the parameter that decides where to send the
        // user is exactly the one that cannot be trusted here.
        var response = await _noRedirect.GetAsync(
            "/oauth/authorize?response_type=code&client_id=demo&redirect_uri=not-a-url&code_challenge=x&code_challenge_method=S256");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Null(response.Headers.Location);
    }

    [Fact]
    public async Task Consent_screen_collects_no_credentials()
    {
        var response = await _noRedirect.GetAsync(
            "/oauth/authorize?response_type=code&client_id=demo&redirect_uri=http%3A%2F%2Flocalhost%2F" +
            "&code_challenge=abc&code_challenge_method=S256&state=xyz");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var html = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("type=\"password\"", html);
        Assert.DoesNotContain("name=\"username\"", html);
        Assert.Contains("No credentials are requested or checked", html);
    }

    [Fact]
    public async Task Full_pkce_lifecycle_issues_a_token_that_authorizes_the_api()
    {
        var (verifier, challenge) = NewPkcePair();
        var code = await ApproveAsync(challenge, "state-1");

        var token = await ExchangeAsync(code, verifier);
        Assert.Equal(HttpStatusCode.OK, token.Status);
        var accessToken = token.Body?["access_token"]?.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(accessToken));
        Assert.False(string.IsNullOrWhiteSpace(token.Body?["refresh_token"]?.GetValue<string>()));

        using var apiReq = new HttpRequestMessage(HttpMethod.Get, "/api/v2/users");
        apiReq.Headers.Add("Authorization", $"Bearer {accessToken}");
        var apiResp = await _client.SendAsync(apiReq);
        Assert.Equal(HttpStatusCode.OK, apiResp.StatusCode);
    }

    [Fact]
    public async Task Exchange_with_the_wrong_verifier_is_rejected()
    {
        var (_, challenge) = NewPkcePair();
        var (otherVerifier, _) = NewPkcePair();
        var code = await ApproveAsync(challenge, "state-2");

        var result = await ExchangeAsync(code, otherVerifier);
        Assert.Equal(HttpStatusCode.BadRequest, result.Status);
        Assert.Equal("invalid_grant", result.Body?["error"]?.GetValue<string>());
    }

    [Fact]
    public async Task An_authorization_code_cannot_be_redeemed_twice()
    {
        var (verifier, challenge) = NewPkcePair();
        var code = await ApproveAsync(challenge, "state-3");

        Assert.Equal(HttpStatusCode.OK, (await ExchangeAsync(code, verifier)).Status);
        Assert.Equal(HttpStatusCode.BadRequest, (await ExchangeAsync(code, verifier)).Status);
    }

    [Fact]
    public async Task A_code_is_consumed_even_when_the_verifier_was_wrong()
    {
        // A leaked code must not stay redeemable after an attacker's failed guess.
        var (verifier, challenge) = NewPkcePair();
        var (wrongVerifier, _) = NewPkcePair();
        var code = await ApproveAsync(challenge, "state-4");

        Assert.Equal(HttpStatusCode.BadRequest, (await ExchangeAsync(code, wrongVerifier)).Status);
        Assert.Equal(HttpStatusCode.BadRequest, (await ExchangeAsync(code, verifier)).Status);
    }

    [Fact]
    public async Task Denying_consent_redirects_with_access_denied_and_no_code()
    {
        var (_, challenge) = NewPkcePair();
        var response = await PostFormAsync("/oauth/authorize", new Dictionary<string, string>
        {
            ["client_id"] = "demo",
            ["redirect_uri"] = "http://localhost/",
            ["code_challenge"] = challenge,
            ["state"] = "state-5",
            ["decision"] = "deny"
        });

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var location = response.Headers.Location!.ToString();
        Assert.Contains("error=access_denied", location);
        Assert.Contains("state=state-5", location);
        Assert.DoesNotContain("code=", location);
    }

    [Fact]
    public async Task Refresh_tokens_rotate_and_the_spent_one_is_refused()
    {
        var (verifier, challenge) = NewPkcePair();
        var code = await ApproveAsync(challenge, "state-6");
        var first = await ExchangeAsync(code, verifier);
        var refreshToken = first.Body?["refresh_token"]?.GetValue<string>()!;

        var refreshed = await PostFormAsync("/oauth/token", new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken
        });
        Assert.Equal(HttpStatusCode.OK, refreshed.StatusCode);

        var reused = await PostFormAsync("/oauth/token", new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken
        });
        Assert.Equal(HttpStatusCode.BadRequest, reused.StatusCode);
    }

    [Fact]
    public async Task Revoked_tokens_stop_authorizing_the_api()
    {
        var (verifier, challenge) = NewPkcePair();
        var code = await ApproveAsync(challenge, "state-7");
        var accessToken = (await ExchangeAsync(code, verifier)).Body?["access_token"]?.GetValue<string>()!;

        using var before = new HttpRequestMessage(HttpMethod.Get, "/api/v2/users");
        before.Headers.Add("Authorization", $"Bearer {accessToken}");
        Assert.Equal(HttpStatusCode.OK, (await _client.SendAsync(before)).StatusCode);

        await PostFormAsync("/oauth/revoke", new Dictionary<string, string> { ["token"] = accessToken });

        using var after = new HttpRequestMessage(HttpMethod.Get, "/api/v2/users");
        after.Headers.Add("Authorization", $"Bearer {accessToken}");
        Assert.Equal(HttpStatusCode.Unauthorized, (await _client.SendAsync(after)).StatusCode);
    }

    [Fact]
    public async Task The_static_demo_token_still_works_so_existing_scripts_do_not_break()
    {
        var response = await PostFormAsync("/oauth/token", new Dictionary<string, string>
        {
            ["grant_type"] = "client_credentials"
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.Equal(RouteDispatcher.DemoBearerToken, body?["access_token"]?.GetValue<string>());
    }

    [Fact]
    public async Task Unsupported_grant_types_return_an_oauth_error()
    {
        var response = await PostFormAsync("/oauth/token", new Dictionary<string, string>
        {
            ["grant_type"] = "password"
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.Equal("unsupported_grant_type", body?["error"]?.GetValue<string>());
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static (string Verifier, string Challenge) NewPkcePair()
    {
        var bytes = new byte[32];
        System.Security.Cryptography.RandomNumberGenerator.Fill(bytes);
        var verifier = DemoOAuth.Base64Url(bytes);
        return (verifier, DemoOAuth.ComputeS256Challenge(verifier));
    }

    private Task<HttpResponseMessage> PostFormAsync(string url, Dictionary<string, string> fields) =>
        _noRedirect.PostAsync(url, new FormUrlEncodedContent(fields));

    /// <summary>Approves a consent request and returns the issued authorization code.</summary>
    private async Task<string> ApproveAsync(string challenge, string state)
    {
        var response = await PostFormAsync("/oauth/authorize", new Dictionary<string, string>
        {
            ["client_id"] = "demo",
            ["redirect_uri"] = "http://localhost/",
            ["code_challenge"] = challenge,
            ["state"] = state,
            ["decision"] = "approve"
        });

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var query = System.Web.HttpUtility.ParseQueryString(response.Headers.Location!.Query);
        Assert.Equal(state, query["state"]);
        return query["code"]!;
    }

    private async Task<(HttpStatusCode Status, JsonObject? Body)> ExchangeAsync(string code, string verifier)
    {
        var response = await PostFormAsync("/oauth/token", new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
            ["client_id"] = "demo",
            ["redirect_uri"] = "http://localhost/",
            ["code_verifier"] = verifier
        });
        return (response.StatusCode, await response.Content.ReadFromJsonAsync<JsonObject>());
    }


    /// <summary>
    /// This project sits inside the server project's directory, so the Web SDK's default Content
    /// glob (**/*.json, copied to output) once swept this project's own bin/ and obj/ into the
    /// server's output. This project references the server, so its build copied that straight back -
    /// one directory level deeper every cycle, until paths outgrew MAX_PATH and git refused to index
    /// them. Genesys.MockServer.csproj now excludes tests/** from the default globs; this test fails
    /// at the first level of recursion rather than the twelfth.
    /// </summary>
    [Fact]
    public void BuildOutputDoesNotRecursivelyNestTheTestProject()
    {
        var output = AppContext.BaseDirectory;

        Assert.False(
            Directory.Exists(Path.Combine(output, "tests")),
            $"Build output contains a nested 'tests' directory ({output}). The server project is " +
            "globbing this test project back into its own output - check DefaultItemExcludes in " +
            "Genesys.MockServer.csproj.");

        // Measured relative to the output directory so the assertion does not depend on where the
        // repository happens to be cloned. Each level of the old recursion added roughly 47 chars.
        var longestRelative = Directory
            .EnumerateFileSystemEntries(output, "*", SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(output, path))
            .OrderByDescending(relative => relative.Length)
            .FirstOrDefault() ?? string.Empty;

        Assert.True(
            longestRelative.Length < 200,
            $"A build output path is {longestRelative.Length} characters below the output directory, " +
            $"which suggests the copy loop has returned: {longestRelative}");
    }

    private static HttpRequestMessage AuthedGet(string url)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Add("Authorization", $"Bearer {RouteDispatcher.DemoBearerToken}");
        return req;
    }
}
