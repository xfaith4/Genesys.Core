using System.Text.Json;
using System.Text.Json.Nodes;

namespace Genesys.MockServer;

/// <summary>
/// Loads fixture JSON files from the fixtures directory and serves them as API responses.
/// Falls back to a generated skeleton when no fixture file exists for an endpoint.
/// </summary>
public sealed class RouteDispatcher
{
    private readonly string _fixturesRoot;
    private readonly AsyncJobEngine _asyncJobEngine;
    private readonly PagingEngine _pagingEngine;
    private readonly JsonSerializerOptions _jsonOptions;

    // Demo token accepted as a valid bearer
    public const string DemoBearerToken = "demo-bearer-token-genesys-testplatform";

    public RouteDispatcher(string fixturesRoot, AsyncJobEngine asyncJobEngine, PagingEngine pagingEngine)
    {
        _fixturesRoot = fixturesRoot;
        _asyncJobEngine = asyncJobEngine;
        _pagingEngine = pagingEngine;
        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = false,
            PropertyNamingPolicy = null
        };
    }

    /// <summary>Validates the Authorization header. Returns null if valid, or an error message.</summary>
    public static string? ValidateAuth(HttpContext ctx)
    {
        if (!ctx.Request.Headers.TryGetValue("Authorization", out var authHeader))
            return "Missing Authorization header.";
        var val = authHeader.ToString();
        if (!val.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return "Authorization must use ******";
        var token = val[7..].Trim();
        if (!string.Equals(token, DemoBearerToken, StringComparison.Ordinal))
            return $"Unknown bearer token. Use the demo token: {DemoBearerToken}";
        return null;
    }

    /// <summary>
    /// Handles a request by routing it to the appropriate fixture, async job handler, or generated response.
    /// </summary>
    public async Task<(int StatusCode, object Body)> DispatchAsync(
        HttpContext ctx,
        string endpointKey,
        string method,
        string requestPath,
        RouteValueDictionary routeValues)
    {
        var requestBaseUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}";
        var pageNumberStr = ctx.Request.Query["pageNumber"].FirstOrDefault();
        int.TryParse(pageNumberStr, out var pageNumber);
        if (pageNumber < 1) pageNumber = 1;
        var cursor = ctx.Request.Query["cursor"].FirstOrDefault();

        // --- Audit log paths ---
        if (requestPath.Contains("/audits/query/servicemapping", StringComparison.OrdinalIgnoreCase))
            return await ServeFixtureAsync("audit-logs.servicemapping.json");

        if (requestPath.Contains("/audits/query", StringComparison.OrdinalIgnoreCase) &&
            requestPath.Contains("/results", StringComparison.OrdinalIgnoreCase))
        {
            return await ServePagedFixtureAsync(
                "audit-logs.results.page1.json", "audit-logs.results.page2.json",
                pageNumber, "results", requestBaseUrl, requestPath);
        }

        if (method == "GET" && requestPath.Contains("/audits/query/", StringComparison.OrdinalIgnoreCase) &&
            !requestPath.Contains("/results", StringComparison.OrdinalIgnoreCase))
        {
            var jobId = routeValues["transactionId"]?.ToString() ?? "unknown";
            var state = _asyncJobEngine.PollJob(jobId);
            return (200, (object)new { state });
        }

        if (method == "POST" && requestPath.EndsWith("/audits/query", StringComparison.OrdinalIgnoreCase))
        {
            var txId = _asyncJobEngine.CreateJob(AsyncJobKind.Audit);
            return (200, (object)new { id = txId });
        }

        // --- Analytics conversation details async jobs ---
        if (requestPath.Contains("/analytics/conversations/details/jobs", StringComparison.OrdinalIgnoreCase) &&
            requestPath.Contains("/results", StringComparison.OrdinalIgnoreCase))
        {
            return await ServePagedCursorFixtureAsync(
                "analytics-conversation-details.results.page1.json",
                "analytics-conversation-details.results.page2.json",
                "conversations", cursor, requestBaseUrl, requestPath);
        }

        if (method == "GET" && requestPath.Contains("/analytics/conversations/details/jobs/", StringComparison.OrdinalIgnoreCase) &&
            !requestPath.Contains("/results", StringComparison.OrdinalIgnoreCase))
        {
            var jobId = routeValues["jobId"]?.ToString() ?? "unknown";
            var state = _asyncJobEngine.PollJob(jobId);
            return (200, (object)new { state });
        }

        if (method == "POST" && requestPath.EndsWith("/analytics/conversations/details/jobs", StringComparison.OrdinalIgnoreCase))
        {
            var jobId = _asyncJobEngine.CreateJob(AsyncJobKind.Analytics);
            return (200, (object)new { jobId });
        }

        // --- Analytics conversation details query (direct POST) ---
        if (method == "POST" && requestPath.Contains("/analytics/conversations/details/query", StringComparison.OrdinalIgnoreCase))
        {
            int bodyPage = 1;
            try
            {
                var body = await ctx.Request.ReadFromJsonAsync<JsonObject>();
                if (body?.TryGetPropertyValue("pageNumber", out var pn) == true)
                    int.TryParse(pn?.ToString(), out bodyPage);
            }
            catch { }
            return await ServeFixtureAsync("analytics-conversation-details-query.page1.json");
        }

        // --- Users ---
        if (method == "GET" && IsExactPath(requestPath, "/api/v2/users"))
        {
            return await ServePagedFixtureAsync(
                "users.page1.json", "users.page2.json",
                pageNumber, "entities", requestBaseUrl, requestPath);
        }

        // --- Routing queues ---
        if (method == "GET" && IsExactPath(requestPath, "/api/v2/routing/queues"))
        {
            return await ServePagedFixtureAsync(
                "routing-queues.page1.json", "routing-queues.page2.json",
                pageNumber, "entities", requestBaseUrl, requestPath);
        }

        // --- Active conversations ---
        if (method == "GET" && IsExactPath(requestPath, "/api/v2/conversations"))
            return await ServeFixtureAsync("conversations.active.json");

        // --- Speech & text analytics topics ---
        if (method == "GET" && IsExactPath(requestPath, "/api/v2/speechandtextanalytics/topics"))
            return await ServeFixtureAsync("speechandtextanalytics.topics.json");

        // --- Conversation recordings ---
        if (method == "GET" && requestPath.Contains("/conversations/", StringComparison.OrdinalIgnoreCase) &&
            requestPath.EndsWith("/recordings", StringComparison.OrdinalIgnoreCase))
            return await ServeFixtureAsync("conversations.recordings.json");

        // --- Authorization roles ---
        if (method == "GET" && IsExactPath(requestPath, "/api/v2/authorization/roles"))
            return await ServeFixtureAsync("authorization.roles.json");

        // --- OAuth clients ---
        if (method == "GET" && IsExactPath(requestPath, "/api/v2/oauth/clients"))
            return await ServeFixtureAsync("oauth.clients.json");

        // --- GET /api/v2/users/me (connectivity probe) ---
        if (method == "GET" && requestPath.EndsWith("/users/me", StringComparison.OrdinalIgnoreCase))
        {
            return (200, (object)new
            {
                id = "demo-user-me-0001",
                name = "Demo Admin",
                email = "demo.admin@genesys-testplatform.local",
                state = "active",
                selfUri = "/api/v2/users/demo-user-me-0001"
            });
        }

        // --- Fallback: generated skeleton response ---
        return GenerateSkeleton(endpointKey, method, requestPath);
    }

    private static bool IsExactPath(string requestPath, string expectedPath) =>
        string.Equals(requestPath.TrimEnd('/'), expectedPath.TrimEnd('/'), StringComparison.OrdinalIgnoreCase);

    private async Task<(int, object)> ServeFixtureAsync(string fileName)
    {
        var path = Path.Combine(_fixturesRoot, fileName);
        if (!File.Exists(path))
            return (404, (object)GenesysError(404, "not.found", $"Demo fixture '{fileName}' not found."));

        var json = await File.ReadAllTextAsync(path);
        var node = JsonNode.Parse(json);
        return (200, node!);
    }

    private async Task<(int, object)> ServePagedFixtureAsync(
        string page1File, string page2File,
        int pageNumber, string itemsProp,
        string baseUrl, string path)
    {
        var fileName = pageNumber >= 2 ? page2File : page1File;
        var fixturePath = Path.Combine(_fixturesRoot, fileName);
        if (!File.Exists(fixturePath))
            return (200, (object)new JsonObject { [itemsProp] = new JsonArray(), ["nextUri"] = null });

        var json = await File.ReadAllTextAsync(fixturePath);
        var node = JsonNode.Parse(json)?.AsObject();
        if (node is null) return (200, (object)new JsonObject());

        // Rewrite nextUri to point to this server
        if (node.ContainsKey("nextUri") && node["nextUri"] is not null && pageNumber < 2)
            node["nextUri"] = $"{baseUrl}{path}?pageNumber=2";
        else if (node.ContainsKey("nextUri") && pageNumber >= 2)
            node["nextUri"] = null;

        return (200, node);
    }

    private async Task<(int, object)> ServePagedCursorFixtureAsync(
        string page1File, string page2File,
        string itemsProp, string? cursor,
        string baseUrl, string path)
    {
        var fileName = !string.IsNullOrWhiteSpace(cursor) ? page2File : page1File;
        var fixturePath = Path.Combine(_fixturesRoot, fileName);
        if (!File.Exists(fixturePath))
            return (200, (object)new JsonObject { [itemsProp] = new JsonArray(), ["cursor"] = null });

        var json = await File.ReadAllTextAsync(fixturePath);
        var node = JsonNode.Parse(json);
        return (200, node!);
    }

    private static (int, object) GenerateSkeleton(string endpointKey, string method, string requestPath)
    {
        if (method == "DELETE")
            return (204, (object)string.Empty);

        if (method == "POST" || method == "PUT" || method == "PATCH")
        {
            return (200, (object)new JsonObject
            {
                ["id"] = $"demo-{endpointKey}-{Guid.NewGuid():N}",
                ["selfUri"] = requestPath
            });
        }

        // Default GET skeleton
        return (200, (object)new JsonObject
        {
            ["entities"] = new JsonArray(),
            ["nextUri"] = null,
            ["pageNumber"] = 1,
            ["pageSize"] = 25,
            ["total"] = 0,
            ["pageCount"] = 0
        });
    }

    private static object GenesysError(int status, string code, string message) => new
    {
        status,
        code,
        message,
        correlationId = Guid.NewGuid().ToString()
    };
}
