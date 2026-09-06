using System.Text.Json.Nodes;

namespace Genesys.MockServer;

/// <summary>
/// Unauthenticated discovery API describing the demo server itself: which catalog endpoints exist,
/// how they are grouped, and how much real demo data backs each one.
///
/// This exists so a client can render an accurate, self-updating outline of what the server can
/// exercise without shipping a copy of the 1.6 MB catalog or hard-coding an endpoint list.
/// Everything here is metadata about the demo server, never Genesys data, so it needs no bearer token.
/// </summary>
public static class MetaApi
{
    /// <summary>Stable wire name for a coverage kind.</summary>
    public static string CoverageName(CoverageKind kind) => kind switch
    {
        CoverageKind.Fixture => "fixture",
        CoverageKind.PagedFixture => "paged-fixture",
        CoverageKind.CursorFixture => "cursor-fixture",
        CoverageKind.AsyncSubmit => "async-submit",
        CoverageKind.AsyncPoll => "async-poll",
        CoverageKind.Inline => "inline",
        _ => "generated"
    };

    public static void MapMetaApi(this WebApplication app, string catalogPath, string fixturesRoot)
    {
        var catalog = app.Services.GetRequiredService<CatalogLoader>();
        var dispatcher = app.Services.GetRequiredService<RouteDispatcher>();

        // Resolve coverage once at startup; the rule table and catalog are both immutable.
        var coverageByKey = new Dictionary<string, CoverageRule?>(StringComparer.OrdinalIgnoreCase);
        foreach (var ep in catalog.Endpoints.Values)
            coverageByKey[ep.Key] = FixtureCoverage.FindForTemplate(ep.Method, ep.Path);

        object Summarize(EndpointEntry ep)
        {
            var rule = coverageByKey[ep.Key];
            return new
            {
                key = ep.Key,
                method = ep.Method,
                path = ep.Path,
                group = ep.Group,
                tags = ep.Tags ?? (IReadOnlyList<string>)Array.Empty<string>(),
                title = ep.Title ?? ep.OperationId ?? ep.Key,
                operationId = ep.OperationId,
                pagingProfile = ep.PagingProfile,
                retryProfile = ep.RetryProfile,
                itemsPath = ep.ItemsPath,
                curated = ep.IsCurated,
                hasDefaultBody = ep.DefaultBody is not null,
                hasDefaultQueryParams = ep.DefaultQueryParams is not null,
                coverage = rule is null ? "generated" : CoverageName(rule.Kind),
                coverageId = rule?.Id,
                coverageSummary = rule?.Summary,
                hasDemoData = rule is not null,
                itemsProperty = rule?.ItemsProperty,
                fixtures = rule?.Fixtures ?? Array.Empty<string>()
            };
        }

        // ─── Server overview ─────────────────────────────────────────────────
        app.MapGet("/__meta", () =>
        {
            var covered = coverageByKey.Values.Count(r => r is not null);
            return Results.Ok(new
            {
                server = "Genesys.MockServer",
                version = "1.0.0",
                demoToken = RouteDispatcher.DemoBearerToken,
                tokenEndpoint = "/oauth/token",
                catalog = new
                {
                    path = catalogPath,
                    version = catalog.Version,
                    generatedAt = catalog.GeneratedAt
                },
                fixturesRoot,
                counts = new
                {
                    endpoints = catalog.Endpoints.Count,
                    routes = catalog.UniqueRoutes().Count(),
                    withDemoData = covered,
                    curated = catalog.Endpoints.Values.Count(e => e.IsCurated),
                    groups = catalog.Endpoints.Values.Select(e => e.Group).Distinct().Count(),
                    coverageRules = FixtureCoverage.Rules.Count
                },
                links = new
                {
                    groups = "/__meta/groups",
                    endpoints = "/__meta/endpoints",
                    coverage = "/__meta/coverage",
                    datasets = "/__meta/datasets",
                    health = "/health"
                }
            });
        });

        // ─── Group outline ───────────────────────────────────────────────────
        app.MapGet("/__meta/groups", () =>
        {
            var groups = catalog.Endpoints.Values
                .GroupBy(e => e.Group, StringComparer.OrdinalIgnoreCase)
                .Select(g => new
                {
                    group = g.Key,
                    endpoints = g.Count(),
                    withDemoData = g.Count(e => coverageByKey[e.Key] is not null),
                    curated = g.Count(e => e.IsCurated),
                    methods = g.Select(e => e.Method).Distinct().OrderBy(m => m).ToArray()
                })
                .OrderByDescending(g => g.withDemoData)
                .ThenBy(g => g.group, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            return Results.Ok(new { total = groups.Length, items = groups });
        });

        // ─── Endpoint list, filterable ───────────────────────────────────────
        app.MapGet("/__meta/endpoints", (
            string? group,
            string? coverage,
            string? method,
            string? q,
            bool? curated,
            bool? demoData,
            int? limit,
            int? offset) =>
        {
            IEnumerable<EndpointEntry> query = catalog.Endpoints.Values;

            if (!string.IsNullOrWhiteSpace(group))
                query = query.Where(e => string.Equals(e.Group, group, StringComparison.OrdinalIgnoreCase));

            if (!string.IsNullOrWhiteSpace(method))
                query = query.Where(e => string.Equals(e.Method, method, StringComparison.OrdinalIgnoreCase));

            if (!string.IsNullOrWhiteSpace(coverage))
                query = query.Where(e =>
                {
                    var rule = coverageByKey[e.Key];
                    var name = rule is null ? "generated" : CoverageName(rule.Kind);
                    return string.Equals(name, coverage, StringComparison.OrdinalIgnoreCase);
                });

            if (curated is true) query = query.Where(e => e.IsCurated);
            if (demoData is true) query = query.Where(e => coverageByKey[e.Key] is not null);
            if (demoData is false) query = query.Where(e => coverageByKey[e.Key] is null);

            if (!string.IsNullOrWhiteSpace(q))
            {
                var needle = q.Trim();
                query = query.Where(e =>
                    e.Key.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
                    e.Path.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
                    (e.Title?.Contains(needle, StringComparison.OrdinalIgnoreCase) ?? false) ||
                    (e.OperationId?.Contains(needle, StringComparison.OrdinalIgnoreCase) ?? false));
            }

            // Endpoints that actually return demo data sort first - that is what a demo wants to run.
            var ordered = query
                .OrderByDescending(e => coverageByKey[e.Key] is not null)
                .ThenByDescending(e => e.IsCurated)
                .ThenBy(e => e.Group, StringComparer.OrdinalIgnoreCase)
                .ThenBy(e => e.Path, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            var take = Math.Clamp(limit ?? 250, 1, 5000);
            var skip = Math.Max(offset ?? 0, 0);

            return Results.Ok(new
            {
                total = ordered.Length,
                offset = skip,
                limit = take,
                items = ordered.Skip(skip).Take(take).Select(Summarize).ToArray()
            });
        });

        // ─── Single endpoint detail ──────────────────────────────────────────
        app.MapGet("/__meta/endpoints/{key}", (string key) =>
        {
            if (!catalog.Endpoints.TryGetValue(key, out var ep))
                return Results.NotFound(new { status = 404, code = "not.found", message = $"No catalog endpoint '{key}'." });

            var rule = coverageByKey[ep.Key];
            return Results.Ok(new
            {
                key = ep.Key,
                method = ep.Method,
                path = ep.Path,
                group = ep.Group,
                tags = ep.Tags ?? (IReadOnlyList<string>)Array.Empty<string>(),
                title = ep.Title ?? ep.OperationId ?? ep.Key,
                description = ep.Description,
                operationId = ep.OperationId,
                pagingProfile = ep.PagingProfile,
                retryProfile = ep.RetryProfile,
                itemsPath = ep.ItemsPath,
                curated = ep.IsCurated,
                notes = ep.Notes,
                defaultBody = ep.DefaultBody,
                defaultQueryParams = ep.DefaultQueryParams,
                defaultRouteValues = ep.DefaultRouteValues,
                coverage = rule is null ? "generated" : CoverageName(rule.Kind),
                coverageId = rule?.Id,
                coverageSummary = rule?.Summary,
                hasDemoData = rule is not null,
                itemsProperty = rule?.ItemsProperty,
                fixtures = (rule?.Fixtures ?? Array.Empty<string>())
                    .Select(f => new { file = f, present = dispatcher.FixtureExists(f) })
                    .ToArray()
            });
        });

        // ─── Coverage rule table ─────────────────────────────────────────────
        app.MapGet("/__meta/coverage", () =>
        {
            var rules = FixtureCoverage.Rules.Select(r =>
            {
                var matching = catalog.Endpoints.Values
                    .Where(e => coverageByKey[e.Key]?.Id == r.Id)
                    .Select(e => new { e.Key, e.Method, e.Path })
                    .OrderBy(e => e.Path, StringComparer.OrdinalIgnoreCase)
                    .ToArray();

                return new
                {
                    id = r.Id,
                    kind = CoverageName(r.Kind),
                    summary = r.Summary,
                    method = r.Method,
                    itemsProperty = r.ItemsProperty,
                    fixtures = r.Fixtures
                        .Select(f => new { file = f, present = dispatcher.FixtureExists(f) })
                        .ToArray(),
                    endpoints = matching
                };
            }).ToArray();

            return Results.Ok(new { total = rules.Length, items = rules });
        });

        // ─── Catalog datasets ────────────────────────────────────────────────
        app.MapGet("/__meta/datasets", () => Results.Ok(catalog.Datasets ?? new JsonObject()));
    }
}
