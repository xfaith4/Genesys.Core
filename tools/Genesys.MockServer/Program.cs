using System.Text.Json;
using System.Text.Json.Nodes;
using Genesys.MockServer;

// ─── Configuration ───────────────────────────────────────────────────────────
var port = int.TryParse(Environment.GetEnvironmentVariable("MOCK_PORT"), out var p) ? p : 7777;
var pollingRoundsEnv = int.TryParse(Environment.GetEnvironmentVariable("MOCK_POLLING_ROUNDS"), out var pr) ? pr : 2;

// Catalog and fixtures paths
var repoRoot = ResolveRepoRoot();
var catalogPath = Environment.GetEnvironmentVariable("MOCK_CATALOG_PATH")
    ?? Path.Combine(repoRoot, "catalog", "genesys.catalog.json");
var fixturesRoot = Environment.GetEnvironmentVariable("MOCK_FIXTURES_PATH")
    ?? Path.Combine(repoRoot, "tests", "fixtures", "demo");

// Optional static hosting for the Genesys Data Client build output.
// This is an integration convenience only - the frontend is never part of the server.
// Set MOCK_STATIC_ROOT to override, or drop a build into apps/GenesysDataClient/dist.
var staticRootEnv = Environment.GetEnvironmentVariable("MOCK_STATIC_ROOT");
var defaultStaticRoot = Path.Combine(repoRoot, "apps", "GenesysDataClient", "dist");
var staticRoot = !string.IsNullOrWhiteSpace(staticRootEnv) ? staticRootEnv : defaultStaticRoot;
var staticRootAvailable = File.Exists(Path.Combine(staticRoot, "index.html"));

// Browser clients are served from a different origin during development (Vite on :5173),
// so the demo server allows cross-origin reads. It holds no real data and no credentials.
var corsOrigins = (Environment.GetEnvironmentVariable("MOCK_CORS_ORIGINS") ?? "*")
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

Console.WriteLine($"[Genesys.MockServer] Starting on http://localhost:{port}");
Console.WriteLine($"[Genesys.MockServer] Catalog  : {catalogPath}");
Console.WriteLine($"[Genesys.MockServer] Fixtures : {fixturesRoot}");
Console.WriteLine($"[Genesys.MockServer] Demo token: {RouteDispatcher.DemoBearerToken}");
Console.WriteLine($"[Genesys.MockServer] Static UI : {(staticRootAvailable ? staticRoot : "(not built - run npm run build in apps/GenesysDataClient)")}");
Console.WriteLine();

// ─── DI Services ─────────────────────────────────────────────────────────────
var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls($"http://localhost:{port}");

builder.Services.AddSingleton(new CatalogLoader(catalogPath));
builder.Services.AddSingleton(new AsyncJobEngine(pollingRoundsEnv));
builder.Services.AddSingleton(new DemoOAuth());
builder.Services.AddSingleton(sp =>
    new RouteDispatcher(fixturesRoot, sp.GetRequiredService<AsyncJobEngine>()));

builder.Services.AddCors(options =>
{
    options.AddPolicy("demo", policy =>
    {
        if (corsOrigins.Length == 1 && corsOrigins[0] == "*")
            policy.AllowAnyOrigin();
        else
            policy.WithOrigins(corsOrigins).AllowCredentials();

        policy.AllowAnyHeader()
              .AllowAnyMethod()
              .WithExposedHeaders("Content-Type", "Location");
    });
});

var app = builder.Build();

app.UseCors("demo");

if (staticRootAvailable)
{
    var fileOptions = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(Path.GetFullPath(staticRoot));
    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = fileOptions });
    app.UseStaticFiles(new StaticFileOptions { FileProvider = fileOptions });
}

var catalog = app.Services.GetRequiredService<CatalogLoader>();
var dispatcher = app.Services.GetRequiredService<RouteDispatcher>();
var demoOAuth = app.Services.GetRequiredService<DemoOAuth>();

var jsonOptions = new JsonSerializerOptions
{
    WriteIndented = false,
    PropertyNamingPolicy = null
};

// ─── Demo authorization server (OAuth 2.0 + PKCE, no auth required) ──────────
// Shaped like the Genesys Cloud endpoints at login.{region} so the client's PKCE code path
// is genuinely exercised offline rather than stubbed.
app.MapOAuthApi();

// ─── Health / readiness probe ─────────────────────────────────────────────────
app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    server = "Genesys.MockServer",
    version = "1.0.0",
    endpoints = catalog.Endpoints.Count,
    demoToken = RouteDispatcher.DemoBearerToken
}));

// ─── Discovery API (unauthenticated) ─────────────────────────────────────────
// Lets a client render an accurate outline of what this server can exercise.
app.MapMetaApi(catalogPath, fixturesRoot);

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
        var authError = RouteDispatcher.ValidateAuth(ctx, demoOAuth);
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

    // Client-side routes fall through to the SPA shell, but API paths must still 404 as JSON.
    if (staticRootAvailable &&
        method == "GET" &&
        !path.StartsWith("/api/", StringComparison.OrdinalIgnoreCase) &&
        !path.StartsWith("/__meta", StringComparison.OrdinalIgnoreCase) &&
        !path.StartsWith("/oauth/", StringComparison.OrdinalIgnoreCase) &&
        ctx.Request.Headers.Accept.ToString().Contains("text/html", StringComparison.OrdinalIgnoreCase))
    {
        ctx.Response.ContentType = "text/html; charset=utf-8";
        await ctx.Response.SendFileAsync(Path.Combine(staticRoot, "index.html"));
        return;
    }

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
