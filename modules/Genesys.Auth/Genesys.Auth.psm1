#Requires -Version 5.1
Set-StrictMode -Version Latest

# Gate E: All auth logic isolated here. Invoke-RestMethod only against login.{region} OAuth endpoints.
# No /api/v2/ literal is present in this file.

Add-Type -AssemblyName System.Security

$script:AuthDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'GenesysConversationAnalysis')
$script:AuthFile = [System.IO.Path]::Combine($script:AuthDir, 'auth.dat')

$script:StoredHeaders = $null
$script:ConnectionInfo = $null

# ── DPAPI helpers ────────────────────────────────────────────────────────────

function _ProtectString {
    param([string]$Plain)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Plain)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Convert]::ToBase64String($encrypted)
}

function _UnprotectString {
    param([string]$Cipher)
    $encrypted = [System.Convert]::FromBase64String($Cipher)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function _SaveTokenPayload {
    param([hashtable]$Payload)
    if (-not [System.IO.Directory]::Exists($script:AuthDir)) {
        [System.IO.Directory]::CreateDirectory($script:AuthDir) | Out-Null
    }
    $json = $Payload | ConvertTo-Json -Compress
    $protected = _ProtectString -Plain $json
    [System.IO.File]::WriteAllText($script:AuthFile, $protected, [System.Text.Encoding]::ASCII)
}

function _LoadTokenPayload {
    if (-not [System.IO.File]::Exists($script:AuthFile)) { return $null }
    try {
        $protected = [System.IO.File]::ReadAllText($script:AuthFile, [System.Text.Encoding]::ASCII)
        $json = _UnprotectString -Cipher $protected
        return $json | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

# ── Private AuthContext builder ───────────────────────────────────────────────

function _NewAuthContext {
    param(
        [string]$Token,
        [datetime]$ExpiresAt,
        [string]$Region,
        [string]$Flow
    )
    $headers = @{ Authorization = "Bearer $Token" }
    return [pscustomobject]@{
        Token     = $Token
        ExpiresAt = $ExpiresAt
        Region    = $Region
        BaseUri   = "https://api.$Region"
        Flow      = $Flow
        Headers   = $headers
    }
}

# ── Public functions ─────────────────────────────────────────────────────────

function Connect-GenesysCloud {
    <#
    .SYNOPSIS
        Establishes an in-memory Genesys Cloud session from a pre-obtained bearer token.
    .DESCRIPTION
        Stores the supplied bearer token and region in module-scoped state and returns
        a stable AuthContext object (Token, ExpiresAt, Region, BaseUri, Headers).
        Token lifecycle (expiry, refresh) is the caller's responsibility.
        For full OAuth flows use Connect-GenesysCloudApp (client_credentials) or
        Connect-GenesysCloudPkce (Authorization Code + PKCE).
    .PARAMETER AccessToken
        A valid Genesys Cloud OAuth2 bearer token.
    .PARAMETER Region
        Genesys Cloud region API hostname suffix (e.g. usw2.pure.cloud).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AccessToken,

        [string]$Region = 'usw2.pure.cloud'
    )

    # Bearer tokens from Genesys Cloud are valid for 86400 s by default; assume 24 h.
    $expiresAt = [datetime]::UtcNow.AddHours(24)

    $script:StoredHeaders = @{ Authorization = "Bearer $AccessToken" }
    $script:ConnectionInfo = [pscustomobject]@{
        Region    = $Region
        Flow      = 'bearer'
        ExpiresAt = $expiresAt
    }

    return _NewAuthContext -Token $AccessToken -ExpiresAt $expiresAt -Region $Region -Flow 'bearer'
}

function Get-GenesysAuthContext {
    <#
    .SYNOPSIS
        Returns the current AuthContext if a valid session exists, otherwise $null.
    #>
    [CmdletBinding()]
    param()

    $headers = Get-StoredHeaders
    if ($null -eq $headers) { return $null }

    $token = ($headers['Authorization'] -replace '^Bearer ', '')
    $expiry = if ($null -ne $script:ConnectionInfo) { $script:ConnectionInfo.ExpiresAt } else { [datetime]::UtcNow }
    $region = if ($null -ne $script:ConnectionInfo) { $script:ConnectionInfo.Region }  else { 'unknown' }
    $flow = if ($null -ne $script:ConnectionInfo) { $script:ConnectionInfo.Flow }    else { 'unknown' }

    return _NewAuthContext -Token $token -ExpiresAt $expiry -Region $region -Flow $flow
}

function Connect-GenesysCloudApp {
    <#
    .SYNOPSIS
        Authenticates using OAuth 2.0 client credentials flow.
    .DESCRIPTION
        POSTs to login.{Region}/oauth/token with Basic credentials.
        Stores the resulting bearer token via DPAPI.
    #>
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$Region
    )
    $loginUrl = "https://login.$($Region)/oauth/token"
    $encoded = [System.Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes("$($ClientId):$($ClientSecret)"))
    $body = 'grant_type=client_credentials'
    $headers = @{
        Authorization  = "Basic $encoded"
        'Content-Type' = 'application/x-www-form-urlencoded'
    }

    $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop
    $token = $response.access_token
    $expiresAt = [datetime]::UtcNow.AddSeconds([int]$response.expires_in - 30)

    _SaveTokenPayload @{
        token     = $token
        expiresAt = $expiresAt.ToString('o')
        region    = $Region
        flow      = 'client_credentials'
    }
    $script:StoredHeaders = @{ Authorization = "Bearer $token" }
    $script:ConnectionInfo = [pscustomobject]@{
        Region    = $Region
        Flow      = 'client_credentials'
        ExpiresAt = $expiresAt
    }
    return _NewAuthContext -Token $token -ExpiresAt $expiresAt -Region $Region -Flow 'client_credentials'
}
### BEGIN: PKCE_TwoStep_Helpers (Genesys.Auth)
function New-GenesysPkceChallenge {
    <#
    .SYNOPSIS
        Creates a PKCE verifier/challenge + state bundle.
    .DESCRIPTION
        Use this when RedirectUri is not loopback (localhost) and your wrapper/app
        must capture the auth code itself. You generate the PKCE bundle, build the
        authorize URL, then complete token exchange with the returned code.
    .OUTPUTS
        PSCustomObject: { Verifier, Challenge, State, CreatedAtUtc }
    #>
    [CmdletBinding()]
    param(
        [int]$VerifierBytes = 32
    )

    $vb = New-Object byte[] $VerifierBytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($vb)

    $verifier = [System.Convert]::ToBase64String($vb).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $challengeBytes = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))
    $challenge = [System.Convert]::ToBase64String($challengeBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    [pscustomobject]@{
        Verifier     = $verifier
        Challenge    = $challenge
        State        = [System.Guid]::NewGuid().ToString('N')
        CreatedAtUtc = [datetime]::UtcNow
    }
}

function Get-GenesysPkceAuthorizeUrl {
    <#
    .SYNOPSIS
        Builds the login.{region}/oauth/authorize URL for PKCE.
    .PARAMETER ClientId
        OAuth client id for the PKCE application.
    .PARAMETER Region
        Genesys Cloud region suffix (e.g. usw2.pure.cloud).
    .PARAMETER RedirectUri
        Redirect URI registered for the PKCE OAuth app (may be non-loopback).
    .PARAMETER Pkce
        Object returned from New-GenesysPkceChallenge.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$RedirectUri,
        [Parameter(Mandatory)][object]$Pkce
    )

    "https://login.$($Region)/oauth/authorize" +
    "?response_type=code" +
    "&client_id=$($ClientId)" +
    "&redirect_uri=$([System.Uri]::EscapeDataString($RedirectUri))" +
    "&code_challenge=$($Pkce.Challenge)" +
    "&code_challenge_method=S256" +
    "&state=$($Pkce.State)"
}

function Complete-GenesysPkceAuth {
    <#
    .SYNOPSIS
        Exchanges an authorization code for an access token using PKCE.
    .DESCRIPTION
        Use after your wrapper/app captures the code from the redirect handler.
        Validates state (if provided).
    .PARAMETER Code
        Authorization code returned to the redirect URI.
    .PARAMETER ClientId
        OAuth client id for the PKCE application.
    .PARAMETER Region
        Genesys Cloud region suffix (e.g. usw2.pure.cloud).
    .PARAMETER RedirectUri
        Redirect URI registered for the PKCE OAuth app.
    .PARAMETER Pkce
        Object returned from New-GenesysPkceChallenge.
    .PARAMETER ReturnedState
        Optional: state value returned alongside the code. If supplied, must match Pkce.State.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$RedirectUri,
        [Parameter(Mandatory)][object]$Pkce,
        [string]$ReturnedState
    )

    if ($ReturnedState -and ($ReturnedState -ne $Pkce.State)) {
        throw "PKCE state mismatch. Expected '$($Pkce.State)' but received '$ReturnedState'."
    }

    $tokenUrl = "https://login.$($Region)/oauth/token"
    $body = "grant_type=authorization_code" +
    "&code=$([System.Uri]::EscapeDataString($Code))" +
    "&redirect_uri=$([System.Uri]::EscapeDataString($RedirectUri))" +
    "&client_id=$([System.Uri]::EscapeDataString($ClientId))" +
    "&code_verifier=$([System.Uri]::EscapeDataString($Pkce.Verifier))"
    $headers = @{ 'Content-Type' = 'application/x-www-form-urlencoded' }

    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop
    $token = $response.access_token
    $expiresAt = [datetime]::UtcNow.AddSeconds([int]$response.expires_in - 30)

    _SaveTokenPayload @{
        token     = $token
        expiresAt = $expiresAt.ToString('o')
        region    = $Region
        flow      = 'pkce'
    }
    $script:StoredHeaders = @{ Authorization = "Bearer $token" }
    $script:ConnectionInfo = [pscustomobject]@{
        Region    = $Region
        Flow      = 'pkce'
        ExpiresAt = $expiresAt
    }

    return _NewAuthContext -Token $token -ExpiresAt $expiresAt -Region $Region -Flow 'pkce'
}
### END: PKCE_TwoStep_Helpers (Genesys.Auth)
### BEGIN: Connect-GenesysCloudPkce_DetectAndSplit
function Connect-GenesysCloudPkce {
    <#
    .SYNOPSIS
        Authenticates using OAuth 2.0 Authorization Code + PKCE flow.
    .DESCRIPTION
        If RedirectUri is loopback (localhost/127.0.0.1), runs fully automated:
        opens browser + listens for callback + exchanges code.

        If RedirectUri is NOT loopback (e.g., custom scheme or remote https), this function
        will not attempt to host a local listener. Instead, use:
          - New-GenesysPkceChallenge
          - Get-GenesysPkceAuthorizeUrl
          - Complete-GenesysPkceAuth
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$Region,
        [string]$RedirectUri = 'http://localhost:8080/callback',
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    # If redirect is not loopback, we cannot auto-capture the code with HttpListener.
    $ru = [System.Uri]$RedirectUri
    $isLoopbackHttp = $ru.IsLoopback -and ($ru.Scheme -in @('http', 'https'))

    if (-not $isLoopbackHttp) {
        $msg = @"
RedirectUri '$RedirectUri' is not a loopback HTTP(S) URI, so this module will not start a local HttpListener.

Use the two-step PKCE helpers instead:

  `$pkce = New-GenesysPkceChallenge
  `$url  = Get-GenesysPkceAuthorizeUrl -ClientId '$ClientId' -Region '$Region' -RedirectUri '$RedirectUri' -Pkce `$pkce
  Start-Process `$url

  # Your wrapper/app must capture the 'code' (and ideally 'state') from the redirect.
  `$ctx = Complete-GenesysPkceAuth -Code `<code>` -ReturnedState `<state>` -ClientId '$ClientId' -Region '$Region' -RedirectUri '$RedirectUri' -Pkce `$pkce
"@
        throw $msg
    }

    # Build PKCE verifier + challenge
    $pkce = New-GenesysPkceChallenge

    $authUrl = Get-GenesysPkceAuthorizeUrl -ClientId $ClientId -Region $Region -RedirectUri $RedirectUri -Pkce $pkce

    Start-Process $authUrl

    # Listen for callback on redirect URI (loopback only)
    $listener = New-Object System.Net.HttpListener
    $prefix = if ($RedirectUri.EndsWith('/')) { $RedirectUri } else { "$RedirectUri/" }
    $listener.Prefixes.Add($prefix)
    $listener.Start()

    $code = $null
    $returnedState = $null
    $err = $null
    $errDesc = $null

    try {
        while (-not $CancellationToken.IsCancellationRequested) {
            $ctxTask = $listener.GetContextAsync()
            while (-not $ctxTask.IsCompleted -and -not $CancellationToken.IsCancellationRequested) {
                Start-Sleep -Milliseconds 150
            }
            if ($CancellationToken.IsCancellationRequested) { break }

            $ctx = $ctxTask.Result
            $rawQuery = $ctx.Request.Url.Query.TrimStart('?')
            $pairs = if ($rawQuery) { $rawQuery -split '&' } else { @() }
            $qp = @{}

            foreach ($p in $pairs) {
                $kv = $p -split '=', 2
                if ($kv.Count -eq 2) { $qp[$kv[0]] = [System.Uri]::UnescapeDataString($kv[1]) }
            }

            $code = $qp['code']
            $returnedState = $qp['state']
            $err = $qp['error']
            $errDesc = $qp['error_description']

            # Always respond with a friendly page
            $respHtml = if ($err) {
                "<html><body><h2>Authentication error</h2><pre>$err</pre><pre>$errDesc</pre></body></html>"
            }
            else {
                "<html><body><h2>Authentication complete. You may close this tab.</h2></body></html>"
            }

            $respBytes = [System.Text.Encoding]::UTF8.GetBytes($respHtml)
            $ctx.Response.ContentType = 'text/html'
            $ctx.Response.ContentLength64 = $respBytes.Length
            $ctx.Response.OutputStream.Write($respBytes, 0, $respBytes.Length)
            $ctx.Response.OutputStream.Close()

            break
        }
    }
    finally {
        $listener.Stop()
    }

    if ($CancellationToken.IsCancellationRequested) {
        throw 'PKCE authorization was cancelled.'
    }

    if ($err) {
        throw "PKCE authorization failed: $err $errDesc"
    }

    if (-not $code) {
        throw 'PKCE authorization did not return a code.'
    }

    if ($returnedState -and ($returnedState -ne $pkce.State)) {
        throw "PKCE state mismatch. Expected '$($pkce.State)' but received '$returnedState'."
    }

    # Exchange code for token (same helper as non-loopback path)
    return Complete-GenesysPkceAuth -Code $code -ReturnedState $returnedState -ClientId $ClientId -Region $Region -RedirectUri $RedirectUri -Pkce $pkce
}
### END: Connect-GenesysCloudPkce_DetectAndSplit
function Get-StoredHeaders {
    <#
    .SYNOPSIS
        Returns cached or stored-on-disk bearer headers if the token has not expired.
    #>
    if ($null -ne $script:StoredHeaders) { return $script:StoredHeaders }

    $payload = _LoadTokenPayload
    if ($null -eq $payload) { return $null }

    try {
        $expiresAt = [datetime]::Parse($payload.expiresAt)
    } catch {
        return $null
    }
    if ([datetime]::UtcNow -ge $expiresAt) { return $null }

    $script:StoredHeaders = @{ Authorization = "Bearer $($payload.token)" }
    $script:ConnectionInfo = [pscustomobject]@{
        Region    = $payload.region
        Flow      = $payload.flow
        ExpiresAt = $expiresAt
    }
    return $script:StoredHeaders
}

function Test-GenesysConnection {
    <#
    .SYNOPSIS
        Returns $true if a valid (non-expired) stored token exists.
    #>
    $h = Get-StoredHeaders
    return ($null -ne $h)
}

function Get-ConnectionInfo {
    <#
    .SYNOPSIS
        Returns connection metadata (Region, Flow, ExpiresAt) or $null.
    #>
    Get-StoredHeaders | Out-Null
    return $script:ConnectionInfo
}

function Clear-StoredToken {
    <#
    .SYNOPSIS
        Removes the in-memory token and deletes the DPAPI-encrypted auth.dat file.
    #>
    $script:StoredHeaders = $null
    $script:ConnectionInfo = $null
    if ([System.IO.File]::Exists($script:AuthFile)) {
        [System.IO.File]::Delete($script:AuthFile)
    }
}

Export-ModuleMember -Function Connect-GenesysCloud, Get-GenesysAuthContext, `
    Connect-GenesysCloudApp, Connect-GenesysCloudPkce, `
    Get-StoredHeaders, Test-GenesysConnection, Get-ConnectionInfo, Clear-StoredToken
