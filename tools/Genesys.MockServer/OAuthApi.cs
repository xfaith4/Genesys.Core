using System.Net;
using System.Text;

namespace Genesys.MockServer;

/// <summary>
/// The demo authorization server's HTTP surface, shaped like the Genesys Cloud endpoints at
/// <c>login.{region}</c> so a client needs only a different base URL to talk to a real org.
///
///   GET  /oauth/authorize   consent screen, then redirect back with ?code=&amp;state=
///   POST /oauth/authorize   the consent decision
///   POST /oauth/token       authorization_code | refresh_token | client_credentials
///   GET  /oauth/userinfo    the demo identity behind a bearer token
///   POST /oauth/revoke      drop a token
/// </summary>
public static class OAuthApi
{
    public static void MapOAuthApi(this WebApplication app)
    {
        var oauth = app.Services.GetRequiredService<DemoOAuth>();

        // ─── Authorization endpoint ──────────────────────────────────────────
        app.MapGet("/oauth/authorize", (HttpContext ctx) =>
        {
            var q = ctx.Request.Query;
            var responseType = q["response_type"].ToString();
            var clientId = q["client_id"].ToString();
            var redirectUri = q["redirect_uri"].ToString();
            var challenge = q["code_challenge"].ToString();
            var method = q["code_challenge_method"].ToString();
            var state = q["state"].ToString();
            var scope = q["scope"].ToString();

            // Parameters that identify where to send the user must be validated before we are
            // willing to redirect anywhere, so these fail as a page rather than as a redirect.
            if (string.IsNullOrWhiteSpace(clientId))
                return Html(400, ErrorPage("invalid_request", "client_id is required."));
            if (string.IsNullOrWhiteSpace(redirectUri) || !Uri.TryCreate(redirectUri, UriKind.Absolute, out _))
                return Html(400, ErrorPage("invalid_request", "A valid absolute redirect_uri is required."));

            if (!string.Equals(responseType, "code", StringComparison.Ordinal))
                return Redirect(redirectUri, error: "unsupported_response_type",
                    description: "Only response_type=code is supported.", state: state);

            if (string.IsNullOrWhiteSpace(challenge))
                return Redirect(redirectUri, error: "invalid_request",
                    description: "code_challenge is required. This server only accepts PKCE authorizations.",
                    state: state);

            if (!string.Equals(method, "S256", StringComparison.Ordinal))
                return Redirect(redirectUri, error: "invalid_request",
                    description: "code_challenge_method must be S256.", state: state);

            Console.WriteLine($"[MockServer] GET /oauth/authorize → consent for client '{clientId}'");
            return Html(200, ConsentPage(clientId, redirectUri, challenge, state, scope));
        });

        // ─── Consent decision ────────────────────────────────────────────────
        app.MapPost("/oauth/authorize", async (HttpContext ctx) =>
        {
            var form = await ctx.Request.ReadFormAsync();
            var clientId = form["client_id"].ToString();
            var redirectUri = form["redirect_uri"].ToString();
            var challenge = form["code_challenge"].ToString();
            var state = form["state"].ToString();
            var scope = form["scope"].ToString();
            var decision = form["decision"].ToString();

            if (string.IsNullOrWhiteSpace(redirectUri) || !Uri.TryCreate(redirectUri, UriKind.Absolute, out _))
                return Html(400, ErrorPage("invalid_request", "A valid absolute redirect_uri is required."));

            if (!string.Equals(decision, "approve", StringComparison.Ordinal))
            {
                Console.WriteLine("[MockServer] POST /oauth/authorize → denied");
                return Redirect(redirectUri, error: "access_denied",
                    description: "The user declined the authorization request.", state: state);
            }

            var code = oauth.IssueCode(clientId, redirectUri, challenge, string.IsNullOrWhiteSpace(scope) ? null : scope);
            Console.WriteLine($"[MockServer] POST /oauth/authorize → code issued to '{clientId}'");

            var target = new StringBuilder(redirectUri);
            target.Append(redirectUri.Contains('?') ? '&' : '?');
            target.Append("code=").Append(WebUtility.UrlEncode(code));
            if (!string.IsNullOrEmpty(state)) target.Append("&state=").Append(WebUtility.UrlEncode(state));
            return Results.Redirect(target.ToString());
        });

        // ─── Token endpoint ──────────────────────────────────────────────────
        app.MapPost("/oauth/token", async (HttpContext ctx) =>
        {
            // Genesys accepts form-encoded token requests; so do we.
            var form = ctx.Request.HasFormContentType
                ? await ctx.Request.ReadFormAsync()
                : (IFormCollection)new FormCollection(new Dictionary<string, Microsoft.Extensions.Primitives.StringValues>());

            var grantType = form["grant_type"].ToString();

            switch (grantType)
            {
                case "authorization_code":
                {
                    var issued = oauth.RedeemCode(
                        form["code"].ToString(),
                        form["client_id"].ToString(),
                        form["redirect_uri"].ToString(),
                        form["code_verifier"].ToString(),
                        out var error,
                        out var description);

                    if (issued is null)
                    {
                        Console.WriteLine($"[MockServer] POST /oauth/token → {error}: {description}");
                        return OAuthError(error!, description!);
                    }

                    Console.WriteLine("[MockServer] POST /oauth/token → PKCE code exchanged");
                    return TokenResponse(issued);
                }

                case "refresh_token":
                {
                    var issued = oauth.Refresh(form["refresh_token"].ToString(), out var error, out var description);
                    if (issued is null)
                    {
                        Console.WriteLine($"[MockServer] POST /oauth/token → {error}: {description}");
                        return OAuthError(error!, description!);
                    }

                    Console.WriteLine("[MockServer] POST /oauth/token → token refreshed");
                    return TokenResponse(issued);
                }

                // Retained so existing scripts and the PowerShell modules keep working unchanged.
                case "client_credentials":
                case "":
                    Console.WriteLine("[MockServer] POST /oauth/token → static demo token issued");
                    return Results.Ok(new
                    {
                        access_token = RouteDispatcher.DemoBearerToken,
                        token_type = "bearer",
                        expires_in = 86400,
                        scope = "all"
                    });

                default:
                    return OAuthError("unsupported_grant_type", $"grant_type '{grantType}' is not supported.");
            }
        });

        // ─── Identity behind a token ─────────────────────────────────────────
        app.MapGet("/oauth/userinfo", (HttpContext ctx) =>
        {
            var token = BearerOf(ctx);
            if (token is null || !(token == RouteDispatcher.DemoBearerToken || oauth.IsValidAccessToken(token)))
                return Results.Json(new { error = "invalid_token", error_description = "Bearer token is missing or not valid." }, statusCode: 401);

            return Results.Ok(new
            {
                sub = DemoOAuth.SubjectId,
                name = DemoOAuth.SubjectName,
                email = DemoOAuth.SubjectEmail,
                organization = new { id = "demo-org-0001", name = "Genesys Demo Organization" }
            });
        });

        // ─── Revocation ──────────────────────────────────────────────────────
        app.MapPost("/oauth/revoke", async (HttpContext ctx) =>
        {
            var form = ctx.Request.HasFormContentType ? await ctx.Request.ReadFormAsync() : null;
            var token = form?["token"].ToString() ?? BearerOf(ctx);
            if (!string.IsNullOrEmpty(token)) oauth.Revoke(token);
            // RFC 7009: revocation always reports success.
            return Results.Ok(new { revoked = true });
        });
    }

    private static string? BearerOf(HttpContext ctx)
    {
        var header = ctx.Request.Headers.Authorization.ToString();
        return header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? header[7..].Trim() : null;
    }

    private static IResult TokenResponse(DemoOAuth.IssuedToken issued) => Results.Ok(new
    {
        access_token = issued.AccessToken,
        refresh_token = issued.RefreshToken,
        token_type = "bearer",
        expires_in = issued.ExpiresInSeconds,
        scope = issued.Scope ?? ""
    });

    private static IResult OAuthError(string error, string description) =>
        Results.Json(new { error, error_description = description }, statusCode: 400);

    private static IResult Html(int status, string body) =>
        Results.Content(body, "text/html; charset=utf-8", Encoding.UTF8, status);

    private static IResult Redirect(string redirectUri, string error, string description, string state)
    {
        var target = new StringBuilder(redirectUri);
        target.Append(redirectUri.Contains('?') ? '&' : '?');
        target.Append("error=").Append(WebUtility.UrlEncode(error));
        target.Append("&error_description=").Append(WebUtility.UrlEncode(description));
        if (!string.IsNullOrEmpty(state)) target.Append("&state=").Append(WebUtility.UrlEncode(state));
        return Results.Redirect(target.ToString());
    }

    private static string Esc(string? value) => WebUtility.HtmlEncode(value ?? string.Empty);

    private const string PageStyle = """
        <style>
          :root { color-scheme: light; }
          body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
                 background:#f4f6f8; font-family:'Segoe UI',system-ui,-apple-system,Arial,sans-serif; color:#16202a; }
          .card { width:min(560px,92vw); background:#fff; border:1px solid #dbe2e8; border-radius:10px;
                  box-shadow:0 8px 32px rgb(16 32 42 / 10%); overflow:hidden; }
          .card__head { padding:18px 22px; border-bottom:1px solid #dbe2e8; border-top:4px solid #cf4019; }
          h1 { margin:0; font-size:18px; }
          .sub { margin:4px 0 0; color:#5d6976; font-size:13px; }
          .card__body { padding:18px 22px; }
          .notice { padding:10px 12px; border-left:3px solid #8a5a00; background:#fdf1dc; color:#6d4700;
                    border-radius:5px; font-size:13px; margin-bottom:16px; }
          dl { display:grid; grid-template-columns:150px 1fr; gap:6px 12px; margin:0 0 18px; font-size:13px; }
          dt { color:#5d6976; }
          dd { margin:0; font-family:'Cascadia Mono',Consolas,monospace; font-size:12px; overflow-wrap:anywhere; }
          .actions { display:flex; gap:10px; justify-content:flex-end; }
          button { font:inherit; padding:8px 16px; border-radius:6px; cursor:pointer; }
          .approve { background:#cf4019; border:1px solid #cf4019; color:#fff; font-weight:600; }
          .deny { background:#fff; border:1px solid #c2ccd6; color:#3d4b58; }
          .foot { padding:12px 22px; border-top:1px solid #dbe2e8; background:#f8fafb; color:#5d6976; font-size:12px; }
          code { font-family:'Cascadia Mono',Consolas,monospace; }
        </style>
        """;

    /// <summary>
    /// The consent screen. It deliberately collects nothing: there are no username or password
    /// fields, and the page states plainly that no credentials are checked. It exists to make the
    /// authorization step of the PKCE flow visible, not to imitate a real sign-in.
    /// </summary>
    private static string ConsentPage(string clientId, string redirectUri, string challenge, string state, string scope) => $"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Demo authorization — Genesys.MockServer</title>
          {PageStyle}
        </head>
        <body>
          <main class="card">
            <div class="card__head">
              <h1>Demo authorization</h1>
              <p class="sub">Genesys.MockServer · offline OAuth 2.0 + PKCE</p>
            </div>
            <div class="card__body">
              <p class="notice">
                <strong>This is not a sign-in page.</strong> No credentials are requested or checked.
                Approving simply issues a demo authorization code so the PKCE exchange can be
                exercised offline. Every authorization resolves to the fixed demo identity below.
              </p>
              <dl>
                <dt>Application</dt><dd>{Esc(clientId)}</dd>
                <dt>Redirect URI</dt><dd>{Esc(redirectUri)}</dd>
                <dt>Scope</dt><dd>{Esc(string.IsNullOrWhiteSpace(scope) ? "(none requested)" : scope)}</dd>
                <dt>Challenge method</dt><dd>S256</dd>
                <dt>Code challenge</dt><dd>{Esc(challenge)}</dd>
                <dt>Signing in as</dt><dd>{Esc(DemoOAuth.SubjectName)} &lt;{Esc(DemoOAuth.SubjectEmail)}&gt;</dd>
              </dl>
              <form method="post" action="/oauth/authorize">
                <input type="hidden" name="client_id" value="{Esc(clientId)}" />
                <input type="hidden" name="redirect_uri" value="{Esc(redirectUri)}" />
                <input type="hidden" name="code_challenge" value="{Esc(challenge)}" />
                <input type="hidden" name="state" value="{Esc(state)}" />
                <input type="hidden" name="scope" value="{Esc(scope)}" />
                <div class="actions">
                  <button class="deny" type="submit" name="decision" value="deny">Cancel</button>
                  <button class="approve" type="submit" name="decision" value="approve" autofocus>
                    Authorize
                  </button>
                </div>
              </form>
            </div>
            <p class="foot">
              The authorization code returned here can only be redeemed by presenting the
              <code>code_verifier</code> whose SHA-256 matches the challenge above.
            </p>
          </main>
        </body>
        </html>
        """;

    private static string ErrorPage(string error, string description) => $"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Authorization error — Genesys.MockServer</title>
          {PageStyle}
        </head>
        <body>
          <main class="card">
            <div class="card__head">
              <h1>Authorization error</h1>
              <p class="sub">Genesys.MockServer</p>
            </div>
            <div class="card__body">
              <dl>
                <dt>error</dt><dd>{Esc(error)}</dd>
                <dt>description</dt><dd>{Esc(description)}</dd>
              </dl>
              <p class="sub">
                The request was rejected before any redirect, because the parameters that decide
                where to send you were not trustworthy.
              </p>
            </div>
          </main>
        </body>
        </html>
        """;
}
