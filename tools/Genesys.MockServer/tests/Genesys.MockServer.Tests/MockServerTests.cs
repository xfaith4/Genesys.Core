using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
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

    public MockServerTests(MockServerFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
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
        req.Headers.Add("Authorization", "******");
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
        submitReq.Headers.Add("Authorization", $"******");
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
        submitReq.Headers.Add("Authorization", $"******");
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

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static HttpRequestMessage AuthedGet(string url)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Add("Authorization", $"******");
        return req;
    }
}
