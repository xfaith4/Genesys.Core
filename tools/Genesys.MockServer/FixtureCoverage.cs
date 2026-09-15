namespace Genesys.MockServer;

/// <summary>
/// How faithfully the mock server can serve a given route.
/// Ordered loosely from richest to thinnest so clients can rank what is worth exercising.
/// </summary>
public enum CoverageKind
{
    /// <summary>Served verbatim from a demo fixture file.</summary>
    Fixture,

    /// <summary>Served from fixtures across two pages using pageNumber/nextUri paging.</summary>
    PagedFixture,

    /// <summary>Served from fixtures across two pages using opaque cursor paging.</summary>
    CursorFixture,

    /// <summary>Creates an async job and returns its identifier.</summary>
    AsyncSubmit,

    /// <summary>Polls an async job, walking QUEUED then RUNNING then FULFILLED.</summary>
    AsyncPoll,

    /// <summary>Answered from a value synthesized in code rather than a fixture file.</summary>
    Inline,

    /// <summary>No demo data. Returns a shape-correct but empty skeleton envelope.</summary>
    Generated
}

/// <summary>
/// One declarative rule describing a route family the mock server handles specially.
/// Rules are evaluated in declaration order and the first match wins, so ordering is significant.
/// </summary>
/// <param name="Id">Stable identifier, surfaced through the metadata API.</param>
/// <param name="Method">HTTP method the rule applies to, or null for any method.</param>
/// <param name="Exact">Full path that must match exactly (trailing slashes ignored).</param>
/// <param name="Contains">Every fragment here must appear somewhere in the path.</param>
/// <param name="EndsWith">Fragment the path must end with.</param>
/// <param name="Excludes">No fragment here may appear in the path.</param>
/// <param name="Kind">How the route is served.</param>
/// <param name="Summary">Human-readable explanation shown in the demo client.</param>
/// <param name="Fixtures">Fixture files backing the rule, in page order.</param>
/// <param name="ItemsProperty">Envelope property holding the array of records.</param>
/// <param name="RouteParam">Route value carrying the job id, for async poll rules.</param>
/// <param name="AsyncKind">Job family created by async submit rules.</param>
/// <param name="IdProperty">Property name carrying the new job id in a submit response.</param>
public sealed record CoverageRule(
    string Id,
    string? Method,
    string? Exact,
    string[] Contains,
    string? EndsWith,
    string[] Excludes,
    CoverageKind Kind,
    string Summary,
    string[] Fixtures,
    string? ItemsProperty = null,
    string? RouteParam = null,
    AsyncJobKind AsyncKind = AsyncJobKind.Analytics,
    string? IdProperty = null)
{
    /// <summary>Returns true when this rule claims the given method and concrete request path.</summary>
    public bool Matches(string method, string path)
    {
        if (Method is not null && !string.Equals(Method, method, StringComparison.OrdinalIgnoreCase))
            return false;

        foreach (var ex in Excludes)
            if (path.Contains(ex, StringComparison.OrdinalIgnoreCase))
                return false;

        if (Exact is not null &&
            !string.Equals(path.TrimEnd('/'), Exact.TrimEnd('/'), StringComparison.OrdinalIgnoreCase))
            return false;

        if (EndsWith is not null && !path.EndsWith(EndsWith, StringComparison.OrdinalIgnoreCase))
            return false;

        foreach (var frag in Contains)
            if (!path.Contains(frag, StringComparison.OrdinalIgnoreCase))
                return false;

        return true;
    }
}

/// <summary>
/// The single source of truth for which routes the mock server backs with demo data.
/// <see cref="RouteDispatcher"/> executes these rules and the metadata API reports them, so the
/// endpoint outline shown in the demo client can never drift from what the server actually serves.
/// </summary>
public static class FixtureCoverage
{
    private static readonly string[] None = Array.Empty<string>();

    /// <summary>Ordered rule table. First match wins.</summary>
    public static readonly IReadOnlyList<CoverageRule> Rules = new[]
    {
        new CoverageRule(
            Id: "audits.service-mapping",
            Method: null,
            Exact: null,
            Contains: new[] { "/audits/query/servicemapping" },
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.Fixture,
            Summary: "Audit service mapping - which services and entity types can be audited.",
            Fixtures: new[] { "audit-logs.servicemapping.json" }),

        new CoverageRule(
            Id: "audits.query-results",
            Method: null,
            Exact: null,
            Contains: new[] { "/audits/query", "/results" },
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.PagedFixture,
            Summary: "Audit query results, two pages linked by nextUri.",
            Fixtures: new[] { "audit-logs.results.page1.json", "audit-logs.results.page2.json" },
            ItemsProperty: "results"),

        new CoverageRule(
            Id: "audits.query-poll",
            Method: "GET",
            Exact: null,
            Contains: new[] { "/audits/query/" },
            EndsWith: null,
            Excludes: new[] { "/results" },
            Kind: CoverageKind.AsyncPoll,
            Summary: "Poll an audit query transaction until it reaches FULFILLED.",
            Fixtures: None,
            RouteParam: "transactionId"),

        new CoverageRule(
            Id: "audits.query-submit",
            Method: "POST",
            Exact: null,
            Contains: None,
            EndsWith: "/audits/query",
            Excludes: None,
            Kind: CoverageKind.AsyncSubmit,
            Summary: "Submit an audit query and receive a transaction id.",
            Fixtures: None,
            AsyncKind: AsyncJobKind.Audit,
            IdProperty: "id"),

        new CoverageRule(
            Id: "analytics.conversation-details-job-results",
            Method: null,
            Exact: null,
            Contains: new[] { "/analytics/conversations/details/jobs", "/results" },
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.CursorFixture,
            Summary: "Conversation detail job results, two pages linked by an opaque cursor.",
            Fixtures: new[]
            {
                "analytics-conversation-details.results.page1.json",
                "analytics-conversation-details.results.page2.json"
            },
            ItemsProperty: "conversations"),

        new CoverageRule(
            Id: "analytics.conversation-details-job-poll",
            Method: "GET",
            Exact: null,
            Contains: new[] { "/analytics/conversations/details/jobs/" },
            EndsWith: null,
            Excludes: new[] { "/results" },
            Kind: CoverageKind.AsyncPoll,
            Summary: "Poll a conversation detail job until it reaches FULFILLED.",
            Fixtures: None,
            RouteParam: "jobId"),

        new CoverageRule(
            Id: "analytics.conversation-details-job-submit",
            Method: "POST",
            Exact: null,
            Contains: None,
            EndsWith: "/analytics/conversations/details/jobs",
            Excludes: None,
            Kind: CoverageKind.AsyncSubmit,
            Summary: "Submit a conversation detail job and receive a job id.",
            Fixtures: None,
            AsyncKind: AsyncJobKind.Analytics,
            IdProperty: "jobId"),

        new CoverageRule(
            Id: "analytics.conversation-details-query",
            Method: "POST",
            Exact: null,
            Contains: new[] { "/analytics/conversations/details/query" },
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.Fixture,
            Summary: "Synchronous conversation detail query returning fully expanded conversations.",
            Fixtures: new[] { "analytics-conversation-details-query.page1.json" },
            ItemsProperty: "conversations"),

        new CoverageRule(
            Id: "users.list",
            Method: "GET",
            Exact: "/api/v2/users",
            Contains: None,
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.PagedFixture,
            Summary: "Organization users with presence, routing status and skills, across two pages.",
            Fixtures: new[] { "users.page1.json", "users.page2.json" },
            ItemsProperty: "entities"),

        new CoverageRule(
            Id: "routing.queues",
            Method: "GET",
            Exact: "/api/v2/routing/queues",
            Contains: None,
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.PagedFixture,
            Summary: "Routing queues with media settings, across two pages.",
            Fixtures: new[] { "routing-queues.page1.json", "routing-queues.page2.json" },
            ItemsProperty: "entities"),

        new CoverageRule(
            Id: "conversations.active",
            Method: "GET",
            Exact: "/api/v2/conversations",
            Contains: None,
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.Fixture,
            Summary: "Conversations currently in progress with live participant state.",
            Fixtures: new[] { "conversations.active.json" },
            ItemsProperty: "entities"),

        new CoverageRule(
            Id: "speechandtextanalytics.topics",
            Method: "GET",
            Exact: "/api/v2/speechandtextanalytics/topics",
            Contains: None,
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.Fixture,
            Summary: "Speech and text analytics topics with phrase definitions.",
            Fixtures: new[] { "speechandtextanalytics.topics.json" },
            ItemsProperty: "entities"),

        new CoverageRule(
            Id: "conversations.recordings",
            Method: "GET",
            Exact: null,
            Contains: new[] { "/conversations/" },
            EndsWith: "/recordings",
            Excludes: None,
            Kind: CoverageKind.Fixture,
            Summary: "Recording metadata for a conversation.",
            Fixtures: new[] { "conversations.recordings.json" }),

        new CoverageRule(
            Id: "authorization.roles",
            Method: "GET",
            Exact: "/api/v2/authorization/roles",
            Contains: None,
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.Fixture,
            Summary: "Authorization roles and their permission policies.",
            Fixtures: new[] { "authorization.roles.json" },
            ItemsProperty: "entities"),

        new CoverageRule(
            Id: "oauth.clients",
            Method: "GET",
            Exact: "/api/v2/oauth/clients",
            Contains: None,
            EndsWith: null,
            Excludes: None,
            Kind: CoverageKind.Fixture,
            Summary: "OAuth clients registered in the demo organization.",
            Fixtures: new[] { "oauth.clients.json" },
            ItemsProperty: "entities"),

        new CoverageRule(
            Id: "users.me",
            Method: "GET",
            Exact: null,
            Contains: None,
            EndsWith: "/users/me",
            Excludes: None,
            Kind: CoverageKind.Inline,
            Summary: "Connectivity probe returning the demo administrator identity.",
            Fixtures: None)
    };

    /// <summary>Finds the first rule claiming this method and concrete path, or null.</summary>
    public static CoverageRule? Find(string method, string path)
    {
        foreach (var rule in Rules)
            if (rule.Matches(method, path))
                return rule;
        return null;
    }

    /// <summary>
    /// Replaces route placeholders with a sample segment so a catalog path template can be tested
    /// against the rule table.
    /// </summary>
    public static string Concretize(string pathTemplate)
    {
        if (!pathTemplate.Contains('{')) return pathTemplate;

        var parts = pathTemplate.Split('/');
        for (var i = 0; i < parts.Length; i++)
            if (parts[i].StartsWith('{') && parts[i].EndsWith('}'))
                parts[i] = "sample";
        return string.Join('/', parts);
    }

    /// <summary>Resolves the coverage a catalog path template would receive at request time.</summary>
    public static CoverageRule? FindForTemplate(string method, string pathTemplate) =>
        Find(method, Concretize(pathTemplate));
}
