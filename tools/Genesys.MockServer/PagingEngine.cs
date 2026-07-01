using System.Text.Json;
using System.Text.Json.Nodes;

namespace Genesys.MockServer;

/// <summary>
/// Slices fixture arrays into pages and constructs paged API responses.
/// Supports nextUri, pageNumber, and cursor paging profiles.
/// </summary>
public sealed class PagingEngine
{
    private readonly int _pageSize;

    public PagingEngine(int pageSize = 25)
    {
        _pageSize = pageSize;
    }

    /// <summary>
    /// Wraps a list of items in a response envelope using the given paging profile.
    /// </summary>
    public JsonObject BuildPagedResponse(
        JsonArray allItems,
        int pageNumber,
        string? cursor,
        string? requestBaseUrl,
        string? requestPath,
        string pagingProfile,
        string itemsPropertyName)
    {
        var totalItems = allItems.Count;
        var skip = (pageNumber - 1) * _pageSize;
        var pageItems = allItems.Skip(skip).Take(_pageSize).Select(n => n?.DeepClone()).ToArray();
        var hasMore = skip + pageItems.Length < totalItems;

        var result = new JsonObject();
        var itemsArray = new JsonArray(pageItems.Select(i => JsonNode.Parse(i?.ToJsonString() ?? "null")).ToArray());
        result[itemsPropertyName] = itemsArray;
        result["pageNumber"] = pageNumber;
        result["pageSize"] = _pageSize;
        result["total"] = totalItems;
        result["pageCount"] = (int)Math.Ceiling((double)totalItems / _pageSize);

        switch (pagingProfile.ToLowerInvariant())
        {
            case "nexturi":
            case "nexturi_default":
            case "nexturi_auditresults":
                result["nextUri"] = hasMore
                    ? $"{requestBaseUrl}{requestPath}?pageNumber={pageNumber + 1}"
                    : null;
                break;
            case "pagenumber":
            case "pagenumber_default":
                result["nextUri"] = null;
                break;
            case "analytics_details_query":
                result["totalHits"] = totalItems;
                result.Remove("pageNumber");
                result.Remove("pageSize");
                result.Remove("pageCount");
                break;
            case "analytics_jobs":
                result["cursor"] = hasMore ? $"demo-cursor-page-{pageNumber + 1}" : null;
                result.Remove("nextUri");
                result.Remove("pageNumber");
                result.Remove("pageSize");
                result.Remove("pageCount");
                break;
            default:
                result["nextUri"] = hasMore
                    ? $"{requestBaseUrl}{requestPath}?pageNumber={pageNumber + 1}"
                    : null;
                break;
        }

        return result;
    }
}
