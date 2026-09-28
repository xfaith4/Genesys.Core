using System.Text.Json;
using System.Text.Json.Nodes;

namespace Genesys.MockServer;

/// <summary>
/// Loads fixture JSON files from the fixtures directory and serves them as API responses.
/// Route handling is driven entirely by <see cref="FixtureCoverage.Rules"/> so that the demo
/// client's endpoint outline describes exactly what this dispatcher does.
/// Falls back to a generated skeleton when no rule claims the request.
/// </summary>
public sealed class RouteDispatcher
{
    private readonly string _fixturesRoot;
    private readonly AsyncJobEngine _asyncJobEngine;
    private readonly JsonSerializerOptions _jsonOptions;

    // Demo token accepted as a valid bearer
    public const string DemoBearerToken = "demo-bearer-token-genesys-testplatform";

    public RouteDispatcher(string fixturesRoot, AsyncJobEngine asyncJobEngine)
    {
        _fixturesRoot = fixturesRoot;
        _asyncJobEngine = asyncJobEngine;
        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = false,
            PropertyNamingPolicy = null
        };
    }

    /// <summary>Directory the demo fixtures are read from.</summary>
    public string FixturesRoot => _fixturesRoot;

    /// <summary>Returns true when the fixture file backing a coverage rule is present on disk.</summary>
    public bool FixtureExists(string fileName) => File.Exists(Path.Combine(_fixturesRoot, fileName));

    /// <summary>
    /// Validates the Authorization header. Returns null if valid, or an error message.
    ///
    /// Two kinds of bearer are accepted: the fixed demo token, which keeps scripts and the
    /// PowerShell modules working without an OAuth round trip, and any unexpired token minted by
    /// the demo authorization server through the PKCE flow.
    /// </summary>
    public static string? ValidateAuth(HttpContext ctx, DemoOAuth? oauth = null)
    {
        if (!ctx.Request.Headers.TryGetValue("Authorization", out var authHeader))
            return "Missing Authorization header.";
        var val = authHeader.ToString();
        if (!val.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return "Authorization must use the Bearer scheme.";

        var token = val[7..].Trim();
        if (string.Equals(token, DemoBearerToken, StringComparison.Ordinal)) return null;
        if (oauth is not null && oauth.IsValidAccessToken(token)) return null;

        return "Bearer token is not valid. Obtain one from /oauth/authorize (PKCE) or " +
               $"/oauth/token, or use the demo token: {DemoBearerToken}";
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

        var rule = FixtureCoverage.Find(method, requestPath);
        if (rule is null)
            return GenerateSkeleton(endpointKey, method, requestPath);

        switch (rule.Kind)
        {
            case CoverageKind.Fixture:
                return await ServeFixtureAsync(rule.Fixtures[0]);

            case CoverageKind.PagedFixture:
                return await ServePagedFixtureAsync(
                    rule.Fixtures[0], rule.Fixtures[1],
                    pageNumber, rule.ItemsProperty ?? "entities",
                    requestBaseUrl, requestPath);

            case CoverageKind.CursorFixture:
                return await ServeCursorFixtureAsync(
                    rule.Fixtures[0], rule.Fixtures[1],
                    rule.ItemsProperty ?? "entities", cursor);

            case CoverageKind.AsyncSubmit:
            {
                var newJobId = _asyncJobEngine.CreateJob(rule.AsyncKind);
                var payload = new JsonObject { [rule.IdProperty ?? "id"] = newJobId };
                return (200, payload);
            }

            case CoverageKind.AsyncPoll:
            {
                var jobId = routeValues[rule.RouteParam ?? "jobId"]?.ToString() ?? "unknown";
                var state = _asyncJobEngine.PollJob(jobId);
                return (200, (object)new JsonObject { ["state"] = state });
            }

            case CoverageKind.Inline when rule.Id == "users.me":
                return (200, (object)new JsonObject
                {
                    ["id"] = "demo-user-me-0001",
                    ["name"] = "Demo Admin",
                    ["email"] = "demo.admin@genesys-testplatform.local",
                    ["state"] = "active",
                    ["selfUri"] = "/api/v2/users/demo-user-me-0001"
                });

            default:
                return GenerateSkeleton(endpointKey, method, requestPath);
        }
    }

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

    private async Task<(int, object)> ServeCursorFixtureAsync(
        string page1File, string page2File,
        string itemsProp, string? cursor)
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
