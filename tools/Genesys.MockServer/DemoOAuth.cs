using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;

namespace Genesys.MockServer;

/// <summary>
/// A demo OAuth 2.0 authorization server implementing the Authorization Code grant with PKCE,
/// mirroring the shape Genesys Cloud exposes at <c>login.{region}</c>.
///
/// The identity is fake - no credentials are collected or checked, and the consent screen says so.
/// The <em>protocol</em> is real: the code challenge is verified with SHA-256, codes are single-use
/// and bound to the client and redirect URI they were issued for, and the error responses use the
/// RFC 6749 shape. That matters because it means the client's PKCE code path is genuinely
/// exercised offline rather than stubbed, so the same code runs unchanged against a live org.
/// </summary>
public sealed class DemoOAuth
{
    private readonly ConcurrentDictionary<string, AuthorizationCode> _codes = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, IssuedToken> _tokens = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, string> _refreshTokens = new(StringComparer.Ordinal);

    /// <summary>Lifetime of an authorization code. Deliberately short, as in a real server.</summary>
    public static readonly TimeSpan CodeLifetime = TimeSpan.FromMinutes(5);

    public static readonly TimeSpan TokenLifetime = TimeSpan.FromHours(8);

    /// <summary>The demo identity every authorization resolves to.</summary>
    public const string SubjectId = "demo-user-me-0001";
    public const string SubjectName = "Demo Admin";
    public const string SubjectEmail = "demo.admin@genesys-testplatform.local";

    /// <summary>Base64url without padding, as RFC 7636 requires.</summary>
    public static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    /// <summary>S256 transform: BASE64URL(SHA256(ASCII(verifier))).</summary>
    public static string ComputeS256Challenge(string verifier) =>
        Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));

    private static string RandomToken(int bytes = 32)
    {
        var buffer = new byte[bytes];
        RandomNumberGenerator.Fill(buffer);
        return Base64Url(buffer);
    }

    /// <summary>
    /// Records an approved authorization and returns a single-use code bound to the request.
    /// </summary>
    public string IssueCode(string clientId, string redirectUri, string codeChallenge, string? scope)
    {
        var code = RandomToken(24);
        _codes[code] = new AuthorizationCode(
            code,
            clientId,
            redirectUri,
            codeChallenge,
            scope,
            DateTimeOffset.UtcNow.Add(CodeLifetime));
        return code;
    }

    /// <summary>
    /// Redeems an authorization code. Returns null and an OAuth error code on any failure.
    /// The code is consumed on the first attempt, successful or not, so a leaked code cannot be
    /// replayed after an attacker's failed verifier guess.
    /// </summary>
    public IssuedToken? RedeemCode(
        string code,
        string clientId,
        string redirectUri,
        string codeVerifier,
        out string? error,
        out string? errorDescription)
    {
        error = null;
        errorDescription = null;

        if (!_codes.TryRemove(code, out var record))
        {
            error = "invalid_grant";
            errorDescription = "Authorization code is unknown, already used, or expired.";
            return null;
        }

        if (record.ExpiresAt < DateTimeOffset.UtcNow)
        {
            error = "invalid_grant";
            errorDescription = "Authorization code has expired.";
            return null;
        }

        if (!string.Equals(record.ClientId, clientId, StringComparison.Ordinal))
        {
            error = "invalid_grant";
            errorDescription = "client_id does not match the one the code was issued to.";
            return null;
        }

        if (!string.Equals(record.RedirectUri, redirectUri, StringComparison.Ordinal))
        {
            error = "invalid_grant";
            errorDescription = "redirect_uri does not match the one the code was issued to.";
            return null;
        }

        if (string.IsNullOrEmpty(codeVerifier))
        {
            error = "invalid_request";
            errorDescription = "code_verifier is required for a PKCE authorization.";
            return null;
        }

        // The whole point of PKCE: only the holder of the verifier can redeem the code.
        var computed = ComputeS256Challenge(codeVerifier);
        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.ASCII.GetBytes(computed),
                Encoding.ASCII.GetBytes(record.CodeChallenge)))
        {
            error = "invalid_grant";
            errorDescription = "code_verifier does not match the code_challenge.";
            return null;
        }

        return Issue(record.ClientId, record.Scope);
    }

    /// <summary>Issues an access token and a rotating refresh token.</summary>
    public IssuedToken Issue(string clientId, string? scope)
    {
        var accessToken = $"demo-pkce-{RandomToken(24)}";
        var refreshToken = $"demo-refresh-{RandomToken(24)}";
        var issued = new IssuedToken(
            accessToken,
            refreshToken,
            clientId,
            scope,
            DateTimeOffset.UtcNow.Add(TokenLifetime));

        _tokens[accessToken] = issued;
        _refreshTokens[refreshToken] = accessToken;
        return issued;
    }

    /// <summary>Exchanges a refresh token for a new pair, invalidating the old one.</summary>
    public IssuedToken? Refresh(string refreshToken, out string? error, out string? errorDescription)
    {
        error = null;
        errorDescription = null;

        if (!_refreshTokens.TryRemove(refreshToken, out var previousAccessToken))
        {
            error = "invalid_grant";
            errorDescription = "Refresh token is unknown or already used.";
            return null;
        }

        _tokens.TryRemove(previousAccessToken, out var previous);
        return Issue(previous?.ClientId ?? "unknown", previous?.Scope);
    }

    /// <summary>True when the bearer token was issued here and has not expired.</summary>
    public bool IsValidAccessToken(string token)
    {
        if (!_tokens.TryGetValue(token, out var issued)) return false;
        if (issued.ExpiresAt >= DateTimeOffset.UtcNow) return true;

        _tokens.TryRemove(token, out _);
        return false;
    }

    public void Revoke(string token)
    {
        if (_tokens.TryRemove(token, out var issued))
            _refreshTokens.TryRemove(issued.RefreshToken, out _);
    }

    /// <summary>Counts, surfaced through the metadata API for the demo client to display.</summary>
    public (int Codes, int Tokens) Stats => (_codes.Count, _tokens.Count);

    public sealed record AuthorizationCode(
        string Code,
        string ClientId,
        string RedirectUri,
        string CodeChallenge,
        string? Scope,
        DateTimeOffset ExpiresAt);

    public sealed record IssuedToken(
        string AccessToken,
        string RefreshToken,
        string ClientId,
        string? Scope,
        DateTimeOffset ExpiresAt)
    {
        public int ExpiresInSeconds =>
            Math.Max(0, (int)(ExpiresAt - DateTimeOffset.UtcNow).TotalSeconds);
    }
}
