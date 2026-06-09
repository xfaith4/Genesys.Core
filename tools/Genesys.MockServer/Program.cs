using System.Text.Json;
using System.Text.Json.Nodes;
using Genesys.MockServer;

// ─── Configuration ───────────────────────────────────────────────────────────
var port = int.TryParse(Environment.GetEnvironmentVariable("MOCK_PORT"), out var p) ? p : 7777;
var pageSizeEnv = int.TryParse(Environment.GetEnvironmentVariable("MOCK_PAGE_SIZE"), out var ps) ? ps : 25;
var pollingRoundsEnv = int.TryParse(Environment.GetEnvironmentVariable("MOCK_POLLING_ROUNDS"), out var pr) ? pr : 2;

// Catalog and fixtures paths
var repoRoot = ResolveRepoRoot();
var catalogPath = Environment.GetEnvironmentVariable("MOCK_CATALOG_PATH")
    ?? Path.Combine(repoRoot, "catalog", "genesys.catalog.json");
var fixturesRoot = Environment.GetEnvironmentVariable("MOCK_FIXTURES_PATH")
    ?? Path.Combine(repoRoot, "tests", "fixtures", "demo");

Console.WriteLine($"[Genesys.MockServer] Starting on http://localhost:{port}");
Console.WriteLine($"[Genesys.MockServer] Catalog  : {catalogPath}");
Console.WriteLine($"[Genesys.MockServer] Fixtures : {fixturesRoot}");
Console.WriteLine($"[Genesys.MockServer] Demo token: {RouteDispatcher.DemoBearerToken}");
Console.WriteLine();

// ─── DI Services ─────────────────────────────────────────────────────────────
var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls($"http://localhost:{port}");

builder.Services.AddSingleton(new CatalogLoader(catalogPath));
builder.Services.AddSingleton(new AsyncJobEngine(pollingRoundsEnv));
builder.Services.AddSingleton(new PagingEngine(pageSizeEnv));
builder.Services.AddSingleton(sp =>
    new RouteDispatcher(fixturesRoot, sp.GetRequiredService<AsyncJobEngine>(), sp.GetRequiredService<PagingEngine>()));

var app = builder.Build();

var catalog = app.Services.GetRequiredService<CatalogLoader>();
var dispatcher = app.Services.GetRequiredService<RouteDispatcher>();

var jsonOptions = new JsonSerializerOptions
{
    WriteIndented = false,
    PropertyNamingPolicy = null
};

// ─── OAuth token endpoint (no auth required) ─────────────────────────────────
app.MapPost("/oauth/token", (HttpContext ctx) =>
{
    Console.WriteLine($"[MockServer] POST /oauth/token → demo token issued");
    return Results.Ok(new
    {
        access_token = RouteDispatcher.DemoBearerToken,
        token_type = "bearer",
        expires_in = 86400,
        scope = "all"
    });
});

// ─── Health / readiness probe ─────────────────────────────────────────────────
app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    server = "Genesys.MockServer",
    version = "1.0.0",
    endpoints = catalog.Endpoints.Count,
    demoToken = RouteDispatcher.DemoBearerToken
}));

// ─── Catalog-driven route registration ───────────────────────────────────────
// Register one route per unique (method, path) pair from the catalog.
// Route parameters like {transactionId} are preserved as ASP.NET route params.
var registeredCount = 0;
foreach (var ep in catalog.UniqueRoutes())
{
    var capturedKey = ep.Key;
    var capturedMethod = ep.Method;
    var capturedPath = ep.Path;

    app.MapMethods(ep.Path, new[] { ep.Method }, async (HttpContext ctx) =>
    {
        // Auth check — skip OPTIONS and health
        var authError = RouteDispatcher.ValidateAuth(ctx);
        if (authError is not null)
        {
            ctx.Response.StatusCode = 401;
            await ctx.Response.WriteAsJsonAsync(new
            {
                status = 401,
                code = "authentication.required",
                message = authError
            }, jsonOptions);
            return;
        }

        Console.WriteLine($"[MockServer] {capturedMethod} {ctx.Request.Path}{ctx.Request.QueryString}");

        var routeValues = ctx.Request.RouteValues;
        var (statusCode, body) = await dispatcher.DispatchAsync(
            ctx, capturedKey, capturedMethod, ctx.Request.Path, routeValues);

        ctx.Response.StatusCode = statusCode;
        if (statusCode != 204 && body is not string { Length: 0 })
        {
            await ctx.Response.WriteAsJsonAsync(body, jsonOptions);
        }
    });

    registeredCount++;
}

// ─── Catchall for unregistered paths ─────────────────────────────────────────
app.MapFallback(async (HttpContext ctx) =>
{
    var method = ctx.Request.Method.ToUpperInvariant();
    var path = ctx.Request.Path.ToString();
    Console.WriteLine($"[MockServer] 404 {method} {path}");
    ctx.Response.StatusCode = 404;
    await ctx.Response.WriteAsJsonAsync(new
    {
        status = 404,
        code = "not.found",
        message = $"No demo route registered for {method} {path}. Ensure the endpoint is in genesys.catalog.json.",
        correlationId = Guid.NewGuid().ToString()
    }, jsonOptions);
});

Console.WriteLine($"[Genesys.MockServer] {registeredCount} routes registered from catalog.");
Console.WriteLine($"[Genesys.MockServer] Listening — press Ctrl+C to stop.");
Console.WriteLine();

app.Run();

// ─── Helper ──────────────────────────────────────────────────────────────────
static string ResolveRepoRoot()
{
    // Walk up from the executable until we find the catalog directory.
    var dir = AppContext.BaseDirectory;
    for (var i = 0; i < 10; i++)
    {
        if (Directory.Exists(Path.Combine(dir, "catalog")) &&
            File.Exists(Path.Combine(dir, "catalog", "genesys.catalog.json")))
            return dir;

        var parent = Directory.GetParent(dir);
        if (parent is null) break;
        dir = parent.FullName;
    }

    // Fallback: assume working directory is repo root
    return Directory.GetCurrentDirectory();
}

// Make the generated Program class public for WebApplicationFactory in tests
public partial class Program { }
