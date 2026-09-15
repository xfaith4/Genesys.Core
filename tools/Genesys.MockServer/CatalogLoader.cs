using System.Text.Json;
using System.Text.Json.Nodes;

namespace Genesys.MockServer;

/// <summary>
/// Loads genesys.catalog.json and exposes a lookup map of (METHOD, /path/template) → endpoint key.
/// </summary>
public sealed class CatalogLoader
{
    private readonly Dictionary<string, EndpointEntry> _endpointsByKey;

    public CatalogLoader(string catalogPath)
    {
        if (!File.Exists(catalogPath))
            throw new FileNotFoundException($"Catalog not found: {catalogPath}");

        var json = File.ReadAllText(catalogPath);
        var doc = JsonNode.Parse(json) ?? throw new InvalidDataException("Catalog JSON is null.");
        var endpoints = doc["endpoints"]?.AsObject()
            ?? throw new InvalidDataException("Catalog missing 'endpoints' node.");

        _endpointsByKey = new Dictionary<string, EndpointEntry>(StringComparer.OrdinalIgnoreCase);

        foreach (var kv in endpoints)
        {
            var key = kv.Key;
            var ep = kv.Value?.AsObject();
            if (ep is null) continue;

            var method = ep["method"]?.GetValue<string>();
            var path = ep["path"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(method) || string.IsNullOrWhiteSpace(path)) continue;

            var itemsPath = ep["itemsPath"]?.GetValue<string>() ?? "$.results";
            var pagingProfile = ep["pagingProfile"]?.GetValue<string>() ?? "none";
            var retryProfile = ep["retryProfile"]?.GetValue<string>() ?? "default";
            var notes = ep["notes"]?.AsArray()?.Select(n => n?.GetValue<string>() ?? "").ToList()
                        ?? new List<string>();

            _endpointsByKey[key] = new EndpointEntry(key, method.ToUpperInvariant(), path, itemsPath, pagingProfile, retryProfile, notes);
        }
    }

    public IReadOnlyDictionary<string, EndpointEntry> Endpoints => _endpointsByKey;

    /// <summary>
    /// Returns every distinct (Method, Path) pair registered in the catalog.
    /// Deduplicates paths that appear under multiple endpoint keys.
    /// </summary>
    public IEnumerable<EndpointEntry> UniqueRoutes()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var ep in _endpointsByKey.Values)
        {
            var key = $"{ep.Method}:{ep.Path}";
            if (seen.Add(key))
                yield return ep;
        }
    }

    /// <summary>
    /// Finds the endpoint entry whose method and path template best match the incoming request path.
    /// Route parameters like {jobId} are treated as wildcards.
    /// </summary>
    public EndpointEntry? Match(string method, string requestPath)
    {
        method = method.ToUpperInvariant();
        foreach (var ep in _endpointsByKey.Values)
        {
            if (!string.Equals(ep.Method, method, StringComparison.OrdinalIgnoreCase)) continue;
            if (PathMatches(ep.Path, requestPath))
                return ep;
        }
        return null;
    }

    private static bool PathMatches(string template, string requestPath)
    {
        var tParts = template.TrimEnd('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var rParts = requestPath.TrimEnd('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (tParts.Length != rParts.Length) return false;
        for (var i = 0; i < tParts.Length; i++)
        {
            if (tParts[i].StartsWith('{') && tParts[i].EndsWith('}')) continue;
            if (!string.Equals(tParts[i], rParts[i], StringComparison.OrdinalIgnoreCase)) return false;
        }
        return true;
    }
}

public sealed record EndpointEntry(
    string Key,
    string Method,
    string Path,
    string ItemsPath,
    string PagingProfile,
    string RetryProfile,
    IReadOnlyList<string> Notes);
