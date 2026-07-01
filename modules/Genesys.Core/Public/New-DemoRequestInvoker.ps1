<#
.SYNOPSIS
    Returns a RequestInvoker scriptblock backed by static demo fixture files.

.DESCRIPTION
    New-DemoRequestInvoker builds a RequestInvoker closure that intercepts every
    HTTP call that Invoke-Dataset would otherwise make to the real Genesys Cloud
    API, and instead returns realistic demo data from the JSON fixture files
    stored in tests/fixtures/demo/.

    The invoker handles:
      - Simple GET/POST endpoints returning a single fixture page
      - nextUri paging (users, routing-queues)
      - Async job flows (analytics conversation details, audit logs)
        submit → poll (QUEUED → RUNNING → FULFILLED) → cursor/nextUri results paging

    No live Genesys Cloud credentials are required. Any BaseUri value is accepted;
    the invoker matches paths only, not the host.

.PARAMETER FixturesPath
    Optional. Absolute path to the directory containing the demo fixture JSON files.
    Defaults to the tests/fixtures/demo folder relative to the repo root.

.PARAMETER BaseUri
    Optional. The BaseUri that will be passed to Invoke-Dataset (used only for
    display purposes in error messages). Defaults to 'http://localhost:7777'.

.PARAMETER PollingRoundsBeforeFulfilled
    Optional. Number of poll calls that return a non-terminal state before the
    async job transitions to FULFILLED. Default is 2 (first poll = QUEUED,
    second poll = RUNNING, third poll = FULFILLED).

.OUTPUTS
    [scriptblock] A closure compatible with the -RequestInvoker parameter of
    Invoke-Dataset.

.EXAMPLE
    $invoker = New-DemoRequestInvoker
    Invoke-Dataset -Dataset 'users' -RequestInvoker $invoker -OutputRoot './out'

.EXAMPLE
    # Override fixtures path (e.g., for a test that provides custom fixtures)
    $invoker = New-DemoRequestInvoker -FixturesPath './my-fixtures'
    Invoke-Dataset -Dataset 'audit-logs' -RequestInvoker $invoker -OutputRoot './out'
#>
function New-DemoRequestInvoker {
    [CmdletBinding()]
    [OutputType([scriptblock])]
    param(
        [string]$FixturesPath,

        [string]$BaseUri = 'http://localhost:7777',

        [ValidateRange(1, 20)]
        [int]$PollingRoundsBeforeFulfilled = 2
    )

    # Resolve fixtures directory
    $resolvedFixturesPath = $FixturesPath
    if ([string]::IsNullOrWhiteSpace($resolvedFixturesPath)) {
        # Walk up from this file's location to find repo root (modules/Genesys.Core/Public/)
        $repoRoot = if ($null -ne $script:GcModuleRoot) {
            [System.IO.Path]::GetFullPath((Join-Path -Path $script:GcModuleRoot -ChildPath '../..'))
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../../..'))
        }
        $resolvedFixturesPath = Join-Path -Path $repoRoot -ChildPath 'tests/fixtures/demo'
    }

    if (-not (Test-Path -Path $resolvedFixturesPath -PathType Container)) {
        throw "Demo fixtures directory not found: '$resolvedFixturesPath'. Ensure the repo is intact."
    }

    # Helper: load a fixture file and parse it
    $loadFixture = {
        param([string]$FilePath)
        if (-not (Test-Path -Path $FilePath)) {
            throw "Demo fixture file not found: '$FilePath'."
        }
        return Get-Content -Path $FilePath -Raw | ConvertFrom-Json -Depth 50
    }

    # State tables for async job simulation (keyed by jobId/transactionId)
    $asyncJobPollCounts  = [System.Collections.Generic.Dictionary[string, int]]::new()
    $pollingThreshold    = $PollingRoundsBeforeFulfilled

    # Build and return the invoker closure
    $fixtures = $resolvedFixturesPath
    $invoker = {
        param($request)

        $uri    = [string]$request.Uri
        $method = ([string]$request.Method).ToUpperInvariant()

        # ---- Helpers --------------------------------------------------------
        function Get-UriPath ([string]$u) {
            try {
                return ([System.Uri]::new($u)).AbsolutePath
            }
            catch {
                $idx = $u.IndexOf('?')
                return if ($idx -ge 0) { $u.Substring(0, $idx) } else { $u }
            }
        }

        function Get-QueryParam ([string]$u, [string]$name) {
            try {
                $q = ([System.Uri]::new($u)).Query.TrimStart('?')
            }
            catch {
                $idx = $u.IndexOf('?')
                $q = if ($idx -ge 0 -and $idx -lt $u.Length - 1) { $u.Substring($idx + 1) } else { '' }
            }
            foreach ($pair in $q -split '&') {
                $parts = $pair -split '=', 2
                if ($parts.Count -eq 2 -and [System.Uri]::UnescapeDataString($parts[0]) -eq $name) {
                    return [System.Uri]::UnescapeDataString($parts[1])
                }
            }
            return $null
        }

        function Load-Fixture ([string]$name) {
            $path = Join-Path -Path $fixtures -ChildPath $name
            if (-not (Test-Path -Path $path)) {
                throw "Demo fixture file not found: '$path'."
            }
            return Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 50
        }

        function Make-Result ([object]$data) {
            return [pscustomobject]@{ Result = $data }
        }

        $path = Get-UriPath $uri

        # ====================================================================
        # AUDIT LOGS
        # ====================================================================

        # Service mapping
        if ($method -eq 'GET' -and $path -like '*/audits/query/servicemapping') {
            return Make-Result (Load-Fixture 'audit-logs.servicemapping.json')
        }

        # Results — page 2 (must be tested before page 1 generic match)
        if ($method -eq 'GET' -and $path -like '*/audits/query/*/results' -and (Get-QueryParam $uri 'pageNumber') -eq '2') {
            return Make-Result (Load-Fixture 'audit-logs.results.page2.json')
        }

        # Results — page 1
        if ($method -eq 'GET' -and $path -like '*/audits/query/*/results') {
            $data = Load-Fixture 'audit-logs.results.page1.json'
            # Rewrite nextUri to use the actual host from the request
            $txId  = ($path -split '/')[-2]
            $base  = $uri -replace '/api/v2/.*$', ''
            $data.nextUri = "$($base)/api/v2/audits/query/$txId/results?pageNumber=2"
            return Make-Result $data
        }

        # Status polling
        if ($method -eq 'GET' -and $path -like '*/audits/query/*' -and $path -notlike '*/results') {
            $jobId = ($path -split '/')[-1]
            if (-not $asyncJobPollCounts.ContainsKey($jobId)) {
                $asyncJobPollCounts[$jobId] = 0
            }
            $asyncJobPollCounts[$jobId]++
            if ($asyncJobPollCounts[$jobId] -lt $pollingThreshold) {
                return Make-Result ([pscustomobject]@{ state = 'RUNNING' })
            }
            return Make-Result ([pscustomobject]@{ state = 'FULFILLED' })
        }

        # Submit
        if ($method -eq 'POST' -and $path -like '*/audits/query') {
            return Make-Result (Load-Fixture 'audit-logs.submit.json')
        }

        # ====================================================================
        # ANALYTICS — CONVERSATION DETAILS (async jobs)
        # ====================================================================

        # Job results — page 2 (cursor present)
        if ($method -eq 'GET' -and $path -like '*/analytics/conversations/details/jobs/*/results' -and
            (-not [string]::IsNullOrWhiteSpace((Get-QueryParam $uri 'cursor')))) {
            return Make-Result (Load-Fixture 'analytics-conversation-details.results.page2.json')
        }

        # Job results — page 1
        if ($method -eq 'GET' -and $path -like '*/analytics/conversations/details/jobs/*/results') {
            return Make-Result (Load-Fixture 'analytics-conversation-details.results.page1.json')
        }

        # Job status polling
        if ($method -eq 'GET' -and $path -like '*/analytics/conversations/details/jobs/*' -and
            $path -notlike '*/results') {
            $jobId = ($path -split '/')[-1]
            if (-not $asyncJobPollCounts.ContainsKey($jobId)) {
                $asyncJobPollCounts[$jobId] = 0
            }
            $asyncJobPollCounts[$jobId]++
            if ($asyncJobPollCounts[$jobId] -lt $pollingThreshold) {
                return Make-Result ([pscustomobject]@{ state = 'QUEUED' })
            }
            return Make-Result ([pscustomobject]@{ state = 'FULFILLED' })
        }

        # Job submit
        if ($method -eq 'POST' -and $path -like '*/analytics/conversations/details/jobs') {
            return Make-Result (Load-Fixture 'analytics-conversation-details.submit.json')
        }

        # ====================================================================
        # ANALYTICS — CONVERSATION DETAILS QUERY (direct POST, body paging)
        # ====================================================================
        if ($method -eq 'POST' -and $path -like '*/analytics/conversations/details/query') {
            $pageNumber = 1
            if ($null -ne $request.Body) {
                try {
                    $body = [string]$request.Body | ConvertFrom-Json
                    if ($null -ne $body -and $body.PSObject.Properties.Name -contains 'pageNumber') {
                        $pageNumber = [int]$body.pageNumber
                    }
                }
                catch { }
            }
            if ($pageNumber -le 1) {
                return Make-Result (Load-Fixture 'analytics-conversation-details-query.page1.json')
            }
            # No additional pages — return empty to signal completion
            return Make-Result ([pscustomobject]@{ conversations = @(); totalHits = 2 })
        }

        # ====================================================================
        # USERS (GET, nextUri paging)
        # ====================================================================
        if ($method -eq 'GET' -and $path -like '*/api/v2/users') {
            $pageNumber = Get-QueryParam $uri 'pageNumber'
            if ($pageNumber -eq '2') {
                return Make-Result (Load-Fixture 'users.page2.json')
            }
            $data = Load-Fixture 'users.page1.json'
            $base = $uri -replace '/api/v2/.*$', ''
            $data.nextUri = "$($base)/api/v2/users?pageNumber=2"
            return Make-Result $data
        }

        # ====================================================================
        # ROUTING QUEUES (GET, nextUri paging)
        # ====================================================================
        if ($method -eq 'GET' -and $path -like '*/api/v2/routing/queues') {
            $pageNumber = Get-QueryParam $uri 'pageNumber'
            if ($pageNumber -eq '2') {
                return Make-Result (Load-Fixture 'routing-queues.page2.json')
            }
            $data = Load-Fixture 'routing-queues.page1.json'
            $base = $uri -replace '/api/v2/.*$', ''
            $data.nextUri = "$($base)/api/v2/routing/queues?pageNumber=2"
            return Make-Result $data
        }

        # ====================================================================
        # ACTIVE CONVERSATIONS (GET, no paging)
        # ====================================================================
        if ($method -eq 'GET' -and $path -like '*/api/v2/conversations' -and
            $path -notlike '*/conversations/*') {
            return Make-Result (Load-Fixture 'conversations.active.json')
        }

        # ====================================================================
        # SPEECH & TEXT ANALYTICS TOPICS (GET, pageNumber paging)
        # ====================================================================
        if ($method -eq 'GET' -and $path -like '*/speechandtextanalytics/topics') {
            return Make-Result (Load-Fixture 'speechandtextanalytics.topics.json')
        }

        # ====================================================================
        # CONVERSATION RECORDINGS (GET, returns array at root $)
        # ====================================================================
        if ($method -eq 'GET' -and $path -like '*/conversations/*/recordings') {
            return Make-Result (Load-Fixture 'conversations.recordings.json')
        }

        # ====================================================================
        # AUTHORIZATION ROLES (GET, pageNumber paging)
        # ====================================================================
        if ($method -eq 'GET' -and $path -like '*/authorization/roles') {
            return Make-Result (Load-Fixture 'authorization.roles.json')
        }

        # ====================================================================
        # OAUTH CLIENTS (GET, nextUri paging)
        # ====================================================================
        if ($method -eq 'GET' -and $path -like '*/oauth/clients') {
            return Make-Result (Load-Fixture 'oauth.clients.json')
        }

        # ====================================================================
        # Fallback — unknown endpoint
        # ====================================================================
        throw "New-DemoRequestInvoker: No demo fixture registered for $method $path (full URI: $uri). Add a fixture file and routing entry to New-DemoRequestInvoker.ps1."

    }.GetNewClosure()

    return $invoker
}
