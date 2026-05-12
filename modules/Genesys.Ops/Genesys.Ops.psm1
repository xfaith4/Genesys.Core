#Requires -Version 5.1
<#
.SYNOPSIS
    IT Operations wrapper around Genesys.Core for day-to-day Genesys Cloud administration.
.DESCRIPTION
    GenesysOps provides high-level operational commands built on Genesys.Core datasets.
    Every function returns parsed PSCustomObjects ready for filtering, pipeline composition,
    CSV export, and monitoring scripts.

    Typical session:

        Import-Module .\modules\Genesys.Ops\Genesys.Ops.psd1
        $token = (Get-Secret GenesysToken).GetNetworkCredential().Password
        Connect-GenesysCloud -AccessToken $token -Region 'usw2.pure.cloud'

        # How many agents are on queue right now?
        (Get-GenesysAgent -OnQueue).Count

        # Which queues have no agents joined?
        Get-GenesysQueue | Where-Object { $_.memberCount -eq 0 } | Format-Table name, id

        # Morning health report
        Invoke-GenesysDailyHealthReport -OutputPath '.\health.json'

        Disconnect-GenesysCloud
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#region Module state
# ---------------------------------------------------------------------------

$script:GC = [ordered]@{
    Connected      = $false
    BaseUri        = 'https://api.usw2.pure.cloud'
    Headers        = @{}
    CatalogPath    = $null
    CoreModulePath = $null
}

#endregion

# ---------------------------------------------------------------------------
#region Module initialization
# ---------------------------------------------------------------------------

# Load Genesys.Core at import time so that Invoke-Dataset is available before
# Connect-GenesysCloud is called.  The check prevents double-loading.
if (-not (Get-Module -Name 'Genesys.Core')) {
    $script:_gcoreCandidates = @(
        (Join-Path $PSScriptRoot '../Genesys.Core/Genesys.Core.psd1'),
        (Join-Path $PSScriptRoot '../../modules/Genesys.Core/Genesys.Core.psd1'),
        (Join-Path $PSScriptRoot 'Genesys.Core/Genesys.Core.psd1')
    )
    $script:_gcoreFound = $script:_gcoreCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($script:_gcoreFound) {
        Import-Module $script:_gcoreFound -ErrorAction Stop
    } else {
        Import-Module 'Genesys.Core' -ErrorAction Stop
    }
    Remove-Variable -Name '_gcoreCandidates', '_gcoreFound' -Scope Script -ErrorAction SilentlyContinue
}

#endregion

# ---------------------------------------------------------------------------
#region Private helpers
# ---------------------------------------------------------------------------

function Assert-GenesysConnected {
    if (-not $script:GC.Connected) {
        throw 'Not connected to Genesys Cloud.  Call Connect-GenesysCloud first.'
    }
}

function Invoke-GenesysDataset {
    <#
    .SYNOPSIS
        Internal helper — runs Invoke-Dataset in an isolated temp folder and returns
        parsed records as an array of PSCustomObjects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Dataset,

        [switch] $KeepArtifacts,

        # When provided the caller owns the folder lifecycle; KeepArtifacts is implied.
        [string] $ArtifactPath,

        # Forwarded to Invoke-Dataset.  Use the 'Body' key to override the request body
        # for POST analytics endpoints; 'Query' for query-string overrides; etc.
        [hashtable] $DatasetParameters
    )

    $ownedTmp  = -not $ArtifactPath
    $outputRoot = if ($ArtifactPath) { $ArtifactPath }
                  else               { Join-Path $env:TEMP "GenesysOps-$(New-Guid)" }

    try {
        $invokeParams = @{
            Dataset     = $Dataset
            OutputRoot  = $outputRoot
            BaseUri     = $script:GC.BaseUri
            Headers     = $script:GC.Headers
            ErrorAction = 'Stop'
        }
        if ($script:GC.CatalogPath) {
            $invokeParams['CatalogPath'] = $script:GC.CatalogPath
        }
        if ($PSBoundParameters.ContainsKey('DatasetParameters') -and $null -ne $DatasetParameters) {
            $invokeParams['DatasetParameters'] = $DatasetParameters
        }

        $null = Invoke-Dataset @invokeParams

        # Locate the data directory: $outputRoot\<DatasetKey>\<RunId>\data\
        $dataDir = Get-ChildItem (Join-Path $outputRoot $Dataset) `
                       -Recurse -Directory -Filter 'data' -ErrorAction SilentlyContinue |
                   Select-Object -First 1

        if (-not $dataDir) { return , @() }

        $records = [System.Collections.Generic.List[object]]::new()
        Get-ChildItem $dataDir.FullName -Filter '*.jsonl' -ErrorAction SilentlyContinue |
            ForEach-Object {
                Get-Content $_.FullName |
                    Where-Object { $_.Trim() } |
                    ForEach-Object { $records.Add(($_ | ConvertFrom-Json)) }
            }

        return , $records.ToArray()
    }
    finally {
        if ($ownedTmp -and -not $KeepArtifacts -and (Test-Path $outputRoot)) {
            Remove-Item $outputRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-GenesysAnalyticsInterval {
    <#
    .SYNOPSIS
        Builds an ISO-8601 interval string ("<start>/<end>") for analytics POST bodies.
    .DESCRIPTION
        When neither bound is supplied, returns a default lookback window ending at
        the current UTC time.  Both bounds must be provided together if either is
        supplied.
    #>
    [CmdletBinding()]
    param(
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [int] $DefaultLookbackHours = 24
    )

    if ($null -eq $Since -and $null -eq $Until) {
        $endUtc = [DateTime]::UtcNow
        $startUtc = $endUtc.AddHours(-1 * $DefaultLookbackHours)
        return "$($startUtc.ToString('o'))/$($endUtc.ToString('o'))"
    }

    if ($null -eq $Since) {
        throw 'Since is required when Until is provided.'
    }

    if ($null -eq $Until) {
        throw 'Until is required when Since is provided.'
    }

    return "$($Since.Value.ToUniversalTime().ToString('o'))/$($Until.Value.ToUniversalTime().ToString('o'))"
}

function New-GenesysAnalyticsFilter {
    <#
    .SYNOPSIS
        Builds an analytics query filter block from one-or-more dimension values.
    .DESCRIPTION
        Input is a hashtable of dimensionName -> value-or-array.  Empty/null values
        are skipped.  Returns:
          - $null when no dimensions yield predicates (caller must omit 'filter').
          - A single { type:'and'|'or', predicates:[...] } filter for a single
            dimension (and for 1 value, or for multiple values).
          - A compound { type:'and', clauses:[ ... ] } filter when multiple
            dimensions are present, with one OR/AND sub-clause per dimension.
    #>
    [CmdletBinding()]
    param(
        [hashtable] $DimensionValues
    )

    if ($null -eq $DimensionValues -or $DimensionValues.Count -eq 0) {
        return $null
    }

    $perDimension = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $DimensionValues.Keys) {
        $raw = $DimensionValues[$key]
        if ($null -eq $raw) {
            continue
        }

        $values = @(@($raw) |
            ForEach-Object { [string]$_ } |
            Where-Object   { -not [string]::IsNullOrWhiteSpace($_) })

        if ($values.Count -eq 0) {
            continue
        }

        $predicates = @($values | ForEach-Object {
            [ordered]@{
                type      = 'dimension'
                dimension = [string]$key
                operator  = 'matches'
                value     = $_
            }
        })

        $perDimension.Add([pscustomobject]@{
            Dimension  = $key
            Predicates = $predicates
        }) | Out-Null
    }

    if ($perDimension.Count -eq 0) {
        return $null
    }

    if ($perDimension.Count -eq 1) {
        $only = $perDimension[0]
        $type = if (@($only.Predicates).Count -gt 1) { 'or' } else { 'and' }
        return [ordered]@{
            type       = $type
            predicates = @($only.Predicates)
        }
    }

    $clauses = @($perDimension | ForEach-Object {
        $clauseType = if (@($_.Predicates).Count -gt 1) { 'or' } else { 'and' }
        [ordered]@{
            type       = $clauseType
            predicates = @($_.Predicates)
        }
    })

    return [ordered]@{
        type    = 'and'
        clauses = $clauses
    }
}

function New-GenesysConversationDetailDatasetParameters {
    [CmdletBinding()]
    param(
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string[]] $QueueId,
        [string[]] $UserId,
        [string] $MediaType,
        [string] $ConversationId,
        [string[]] $DivisionId
    )

    $datasetParameters = @{}
    if ($Since.HasValue) { $datasetParameters['StartUtc'] = $Since.Value.ToUniversalTime().ToString('o') }
    if ($Until.HasValue) { $datasetParameters['EndUtc'] = $Until.Value.ToUniversalTime().ToString('o') }
    if ($QueueId) { $datasetParameters['QueueIds'] = @($QueueId) }
    if ($UserId) { $datasetParameters['UserIds'] = @($UserId) }
    if (-not [string]::IsNullOrWhiteSpace($MediaType)) { $datasetParameters['MediaTypes'] = @($MediaType) }
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) { $datasetParameters['ConversationId'] = $ConversationId }
    if ($DivisionId) { $datasetParameters['DivisionIds'] = @($DivisionId) }
    return $datasetParameters
}

#endregion

# ---------------------------------------------------------------------------
#region Private safe-property helpers (StrictMode-compatible)
# ---------------------------------------------------------------------------

function Test-Property {
    # Returns $true when $InputObject has a PSObject property named $Name.
    param([object]$InputObject, [string]$Name)
    if ($null -eq $InputObject) { return $false }
    return [bool]($InputObject.PSObject.Properties[$Name])
}

function Get-PropertyValue {
    # Returns a property value from $InputObject, or $Default if missing/null.
    param([object]$InputObject, [string]$Name, [object]$Default = $null)
    if ($null -eq $InputObject) { return $Default }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Get-NestedPropertyValue {
    # Traverses a dot-separated path (e.g. 'user.email') without throwing on
    # missing segments or null intermediate values under Set-StrictMode -Version Latest.
    param([object]$InputObject, [string]$Path, [object]$Default = $null)
    if ($null -eq $InputObject) { return $Default }
    $current = $InputObject
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) { return $Default }
        $prop = $current.PSObject.Properties[$segment]
        if (-not $prop) { return $Default }
        $current = $prop.Value
    }
    if ($null -ne $current) { $current } else { $Default }
}

function Test-AnyNestedPropertyValue {
    param(
        [object]$InputObject,
        [string[]]$Paths,
        [object]$Expected,
        [switch]$KeepWhenMissing
    )

    $foundValue = $false
    foreach ($path in @($Paths)) {
        $value = Get-NestedPropertyValue $InputObject $path
        if ($null -eq $value) { continue }

        $foundValue = $true
        if ([string]$value -eq [string]$Expected) {
            return $true
        }
    }

    return ($KeepWhenMissing -and -not $foundValue)
}

#endregion

# ---------------------------------------------------------------------------
#region Hardened private dataset helper
# ---------------------------------------------------------------------------

function Invoke-GenesysOpsDataset {
    <#
    .SYNOPSIS
        Hardened internal dataset helper. Validates the dataset key against the
        active catalog before calling Invoke-GenesysDataset and returns a
        diagnostic envelope or plain records.
    .PARAMETER Dataset
        Catalog dataset key.
    .PARAMETER FunctionName
        Calling public function name — included in diagnostic messages.
    .PARAMETER AllowEmpty
        When set, an empty result is Status='Empty' rather than a warning.
    .PARAMETER IncludeDiagnostics
        Return the full diagnostic envelope instead of just records.
    .PARAMETER KeepArtifacts
        Passed through to Invoke-GenesysDataset.
    .PARAMETER ArtifactPath
        Passed through to Invoke-GenesysDataset.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Dataset,

        [string] $FunctionName,
        [switch] $AllowEmpty,
        [switch] $IncludeDiagnostics,
        [switch] $KeepArtifacts,
        [string] $ArtifactPath
    )

    $callerName = if ($FunctionName) { $FunctionName } else { '<unknown>' }

    $envelope = [PSCustomObject][ordered]@{
        DatasetKey   = $Dataset
        FunctionName = $callerName
        Status       = 'Failed'
        Records      = @()
        RecordCount  = 0
        RunFolder    = $null
        ManifestPath = $null
        DataFolder   = $null
        Error        = $null
    }

    # Pre-validate dataset key against the active catalog when available.
    $catalogPath = $script:GC.CatalogPath
    if ($catalogPath -and (Test-Path $catalogPath)) {
        try {
            $catalogObj    = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json
            $datasetsNode  = Get-PropertyValue $catalogObj 'datasets'
            if ($datasetsNode) {
                $datasetEntry = Get-PropertyValue $datasetsNode $Dataset
                if (-not $datasetEntry) {
                    $msg = "$($callerName): Dataset key '$($Dataset)' not found in catalog '$($catalogPath)'."
                    $envelope.Status = 'Unsupported'
                    $envelope.Error  = $msg
                    if ($IncludeDiagnostics) { return $envelope }
                    Write-Warning $msg
                    return @()
                }
            }
        } catch {
            Write-Verbose "$($callerName): Catalog pre-validation skipped — $($_)"
        }
    }

    # Invoke the dataset via the established Genesys.Core contract.
    try {
        $invokeParams = @{ Dataset = $Dataset }
        if ($KeepArtifacts) { $invokeParams['KeepArtifacts'] = $true }
        if ($ArtifactPath)  { $invokeParams['ArtifactPath']  = $ArtifactPath }

        $records = Invoke-GenesysDataset @invokeParams

        # Normalize using a List to guarantee a non-null System.Object[] even for empty results.
        # Direct @($records) collapses to $null under PowerShell 5.1 when records is null/empty.
        $recordList = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $records) {
            foreach ($item in @($records)) { if ($null -ne $item) { $recordList.Add($item) } }
        }
        $envelope.Records     = $recordList.ToArray()
        $envelope.RecordCount = $recordList.Count
        $envelope.Status      = if ($envelope.RecordCount -eq 0) { 'Empty' } else { 'Succeeded' }

        if ($envelope.Status -eq 'Empty' -and -not $AllowEmpty) {
            Write-Verbose "$($callerName): Dataset '$($Dataset)' returned 0 records."
        }
    } catch {
        $msg = "$($callerName): Dataset '$($Dataset)' failed — $_"
        $envelope.Status = 'Failed'
        $envelope.Error  = $msg
        if ($IncludeDiagnostics) { return $envelope }
        throw $msg
    }

    if ($IncludeDiagnostics) { return $envelope }
    # Return a guaranteed non-null array so callers can safely use @() wrapping or .Count.
    return , $envelope.Records
}

#endregion

# ---------------------------------------------------------------------------
#region Authentication & Session
# ---------------------------------------------------------------------------

function Connect-GenesysCloud {
    <#
    .SYNOPSIS
        Establishes a Genesys Cloud session for this PowerShell session.
    .DESCRIPTION
        Stores the bearer token and region so subsequent Get-Genesys* commands
        authenticate automatically.  The token is held in memory only; it is not
        written to disk or the registry.

        Supported regions (API hostname suffixes):
            mypurecloud.com      US East (default)
            usw2.pure.cloud      US West 2
            cac1.pure.cloud      Canada Central
            euw2.pure.cloud      EU West 2 (London)
            euc1.pure.cloud      EU Central 1 (Frankfurt)
            aps1.pure.cloud      AP South 1 (Mumbai)
            apse2.pure.cloud     AP Southeast 2 (Sydney)
            apne1.pure.cloud     AP Northeast 1 (Tokyo)
            sae1.pure.cloud      SA East 1 (São Paulo)
    .PARAMETER AccessToken
        OAuth2 bearer token from a Client Credentials, Authorization Code, or
        Implicit grant.  Treat this as a secret — do not log or display it.
    .PARAMETER Region
        Genesys Cloud region hostname suffix.  Defaults to 'mypurecloud.com'.
    .PARAMETER CatalogPath
        Explicit path to catalog/genesys.catalog.json.  When omitted the module
        searches relative to its own location.
    .PARAMETER CoreModulePath
        Explicit path to Genesys.Core.psd1.  Required only when the module is
        not on PSModulePath and not co-located with this file.
    .EXAMPLE
        # Retrieve token from SecretManagement and connect to US West 2
        $token = (Get-Secret -Name 'GenesysToken').GetNetworkCredential().Password
        Connect-GenesysCloud -AccessToken $token -Region 'usw2.pure.cloud'
    .EXAMPLE
        # CI/CD pipeline — token from environment variable
        Connect-GenesysCloud -AccessToken $env:GC_BEARER_TOKEN
    .EXAMPLE
        # Multi-org script — connect, run, disconnect, repeat
        foreach ($env in $environments) {
            Connect-GenesysCloud -AccessToken $env.Token -Region $env.Region
            $queues = Get-GenesysQueue
            Disconnect-GenesysCloud
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $AccessToken,

        [ValidateNotNullOrEmpty()]
        [string] $Region = 'usw2.pure.cloud',

        [string] $CatalogPath,

        [string] $CoreModulePath
    )

    # ---- Load Genesys.Core if not already imported ----
    if (-not (Get-Module -Name 'Genesys.Core')) {
        if ($CoreModulePath) {
            Import-Module $CoreModulePath -ErrorAction Stop
        }
        else {
            $candidates = @(
                (Join-Path $PSScriptRoot  '../Genesys.Core/Genesys.Core.psd1'),
                (Join-Path $PSScriptRoot  '../../modules/Genesys.Core/Genesys.Core.psd1'),
                (Join-Path $PSScriptRoot  'Genesys.Core/Genesys.Core.psd1')
            )
            $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($found) {
                Import-Module $found -ErrorAction Stop
            }
            else {
                Import-Module 'Genesys.Core' -ErrorAction Stop
            }
        }
    }

    # ---- Resolve catalog — search likely Genesys.Core catalog locations ----
    $resolvedCatalog = $CatalogPath
    if (-not $resolvedCatalog) {
        $catalogCandidates = @(
            (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json'),
            (Join-Path $PSScriptRoot '../../catalog/genesys-core.catalog.json'),
            (Join-Path $PSScriptRoot '../catalog/genesys.catalog.json'),
            (Join-Path $PSScriptRoot '../catalog/genesys-core.catalog.json'),
            (Join-Path $PSScriptRoot 'catalog/genesys.catalog.json'),
            (Join-Path $PSScriptRoot 'catalog/genesys-core.catalog.json')
        )
        $resolvedCatalog = $catalogCandidates |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
    }
    if (-not $resolvedCatalog) {
        Write-Warning "Connect-GenesysCloud: Catalog not found. Dataset key pre-validation will be skipped. Pass -CatalogPath to resolve manually."
    }

    $script:GC.BaseUri       = "https://api.$Region"
    $script:GC.Headers       = @{ Authorization = "Bearer $AccessToken" }
    $script:GC.CatalogPath   = $resolvedCatalog
    $script:GC.CoreModulePath = $CoreModulePath
    $script:GC.Connected     = $true

    Write-Verbose "Connected — BaseUri: $($script:GC.BaseUri)  Catalog: $($script:GC.CatalogPath)"

    [PSCustomObject]@{
        Connected   = $true
        BaseUri     = $script:GC.BaseUri
        CatalogPath = $script:GC.CatalogPath
    }
}

function Disconnect-GenesysCloud {
    <#
    .SYNOPSIS
        Clears the active Genesys Cloud session from memory.
    .DESCRIPTION
        Removes the cached bearer token and resets all connection state.
        Call this at the end of any script that handles sensitive tokens to
        minimise the window during which the credential lives in memory.
    .EXAMPLE
        try {
            Connect-GenesysCloud -AccessToken $token
            # ... operations ...
        }
        finally {
            Disconnect-GenesysCloud
        }
    #>
    [CmdletBinding()]
    param()

    $script:GC.Connected    = $false
    $script:GC.Headers      = @{}
    $script:GC.BaseUri      = 'https://api.usw2.pure.cloud'
    $script:GC.CatalogPath  = $null
    Write-Verbose 'Genesys Cloud session disconnected and token cleared.'
}

function Test-GenesysConnection {
    <#
    .SYNOPSIS
        Validates the active session by retrieving organisation details.
    .DESCRIPTION
        Returns a connection-status object.  Use as a fast-fail guard at the
        top of automation scripts before running long dataset pulls.
    .EXAMPLE
        $health = Test-GenesysConnection
        if (-not $health.IsConnected) { throw "Genesys connection failed: $($health.Reason)" }
    .EXAMPLE
        # Validate silently in a monitoring loop
        if ((Test-GenesysConnection).IsConnected) { Write-Host 'OK' } else { Write-Warning 'DOWN' }
    #>
    [CmdletBinding()]
    param()

    if (-not $script:GC.Connected) {
        return [PSCustomObject]@{
            IsConnected = $false
            Reason      = 'Not connected.  Run Connect-GenesysCloud.'
        }
    }

    try {
        $org = Get-GenesysOrganization -ErrorAction Stop
        [PSCustomObject]@{
            IsConnected = $true
            OrgName     = $org.name
            OrgId       = $org.id
            BaseUri     = $script:GC.BaseUri
        }
    }
    catch {
        [PSCustomObject]@{
            IsConnected = $false
            Reason      = $_.Exception.Message
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Organisation & Administration
# ---------------------------------------------------------------------------

function Get-GenesysOrganization {
    <#
    .SYNOPSIS
        Returns the organisation record for the connected Genesys Cloud org.
    .DESCRIPTION
        Useful for confirming you are targeting the correct organisation before
        running bulk operations — especially important in multi-org environments.
    .EXAMPLE
        Get-GenesysOrganization | Select-Object name, id, defaultLanguage
    .EXAMPLE
        # Confirm target org at the top of a migration script
        $org = Get-GenesysOrganization
        Write-Host "Target org: $($org.name)  [$($org.id)]"
        if ($org.name -ne 'Contoso-Production') { throw 'Wrong org — aborting.' }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    $records = Invoke-GenesysDataset -Dataset 'organization.get.organization.details'
    if ($records.Count -gt 0) { $records[0] } else { $null }
}

function Get-GenesysOrganizationLimit {
    <#
    .SYNOPSIS
        Returns platform limits for the connected organisation.
    .DESCRIPTION
        Shows configured ceilings (max queues, max skills, max users, etc.).
        Compare against current object counts to detect when the org is
        approaching a limit before it triggers an operational incident.
    .EXAMPLE
        Get-GenesysOrganizationLimit | Format-Table namespace, name, value, defaultValue
    .EXAMPLE
        # Alert when queue count exceeds 80% of the platform limit
        $limit = (Get-GenesysOrganizationLimit | Where-Object name -eq 'routing.queues.max').value
        $count = (Get-GenesysQueue).Count
        if ($count / $limit -gt 0.8) {
            Write-Warning "Queue count ($count) is over 80% of the org limit ($limit)"
        }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'organization.get.organization.limits'
}

function Get-GenesysDivision {
    <#
    .SYNOPSIS
        Lists all divisions in the organisation.
    .DESCRIPTION
        Divisions are the top-level permission and resource grouping in Genesys Cloud.
        Use this to map division IDs (seen in user, queue, and audit records) to
        human-readable names without an extra API call per record.
    .PARAMETER Name
        Wildcard filter on division name.
    .EXAMPLE
        Get-GenesysDivision | Format-Table id, name
    .EXAMPLE
        # Build a reusable ID-to-name lookup for enriching reports
        $divMap = Get-GenesysDivision | Group-Object id -AsHashTable -AsString
        $queues = Get-GenesysQueue
        $queues | Select-Object name, @{ n='Division'; e={ $divMap[$_.divisionId].name } } | Format-Table
    .EXAMPLE
        Get-GenesysDivision -Name 'APAC*'
    #>
    [CmdletBinding()]
    param(
        [string] $Name
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'authorization.get.all.divisions'
    if ($Name) { $results = $results | Where-Object { $_.name -like $Name } }
    $results
}

#endregion

# ---------------------------------------------------------------------------
#region Users & Agents
# ---------------------------------------------------------------------------

function Get-GenesysAgent {
    <#
    .SYNOPSIS
        Returns agents with their current presence and routing status.
    .DESCRIPTION
        Pulls the normalised users dataset which includes routing-status and
        presence state for every licensed user.  Use -OnQueue or -PresenceStatus
        to focus on operationally relevant subsets.

        Returned fields per record:
            id            — Genesys user GUID
            name          — Display name
            email         — Primary email address
            state         — Account state (ACTIVE / INACTIVE / DELETED)
            presence      — Primary presence label (AVAILABLE, AWAY, BUSY, OFFLINE, …)
            routingStatus — ACD routing status (IDLE, INTERACTING, OFF_QUEUE, NOT_RESPONDING)
    .PARAMETER Name
        Wildcard filter on display name.
    .PARAMETER Email
        Wildcard filter on email address.
    .PARAMETER PresenceStatus
        Return only agents with this primary presence value.
    .PARAMETER OnQueue
        Return only agents whose routing status is IDLE or INTERACTING (visible to ACD).
    .PARAMETER State
        Filter by account state.  Defaults to ACTIVE.
    .EXAMPLE
        # How many agents are currently answering contacts?
        (Get-GenesysAgent -OnQueue).Count
    .EXAMPLE
        # Live roster — agents available but not yet assigned a contact
        Get-GenesysAgent -PresenceStatus AVAILABLE |
            Where-Object routingStatus -eq 'IDLE' |
            Sort-Object name | Format-Table name, email
    .EXAMPLE
        # Identify agents marked AVAILABLE but with routing OFF_QUEUE (config issue)
        Get-GenesysAgent | Where-Object {
            $_.presence -eq 'AVAILABLE' -and $_.routingStatus -eq 'OFF_QUEUE'
        } | Format-Table name, email, routingStatus
    .EXAMPLE
        # Export full agent roster for an access review
        Get-GenesysAgent -State ACTIVE | Export-Csv .\agents-$(Get-Date -f yyyyMMdd).csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [string] $Name,
        [string] $Email,
        [string] $PresenceStatus,
        [switch] $OnQueue,
        [ValidateSet('ACTIVE', 'INACTIVE', 'DELETED')]
        [string] $State = 'ACTIVE'
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'users'

    if ($State)          { $results = $results | Where-Object { $_.state          -eq  $State          } }
    if ($Name)           { $results = $results | Where-Object { $_.name           -like $Name          } }
    if ($Email)          { $results = $results | Where-Object { $_.email          -like $Email         } }
    if ($PresenceStatus) { $results = $results | Where-Object { $_.presence       -eq  $PresenceStatus } }
    if ($OnQueue)        { $results = $results | Where-Object { $_.routingStatus  -in  @('IDLE','INTERACTING') } }

    $results
}

function Get-GenesysAgentPresence {
    <#
    .SYNOPSIS
        Returns bulk presence records for all agents via the Genesys Cloud presence endpoint.
    .DESCRIPTION
        Lighter-weight alternative to Get-GenesysAgent when full user details are
        not needed.  Returns raw presence objects from the bulk presence API.
    .EXAMPLE
        # Presence distribution at a glance
        Get-GenesysAgentPresence |
            Group-Object { $_.presenceDefinition.systemPresence } |
            Select-Object Name, Count | Sort-Object Count -Descending | Format-Table
    .EXAMPLE
        # Spot agents in an unknown or unmapped presence state
        $known = 'AVAILABLE','AWAY','BUSY','BREAK','MEAL','MEETING','TRAINING','OFFLINE'
        Get-GenesysAgentPresence |
            Where-Object { $_.presenceDefinition.systemPresence -notin $known } |
            Select-Object userId, @{n='State';e={$_.presenceDefinition.systemPresence}}
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    # NOTE: Both 'users.get.bulk.user.presences' and 'users.get.bulk.user.presences.genesys.cloud'
    # exist in the catalog. The Agent Investigation steps use 'users.get.bulk.user.presences'
    # (with agent-investigation-presences redaction profile). This public cmdlet uses the
    # '.genesys.cloud' variant which maps to the same endpoint without a redaction profile.
    Invoke-GenesysDataset -Dataset 'users.get.bulk.user.presences.genesys.cloud'
}

function Find-GenesysUser {
    <#
    .SYNOPSIS
        Searches for a user by name or email fragment.
    .DESCRIPTION
        Queries the user search endpoint and then applies an additional client-side
        filter for precision.  More efficient than Get-GenesysAgent for point-lookups.
    .PARAMETER Query
        Partial name or email to match.
    .EXAMPLE
        Find-GenesysUser -Query 'jane.doe'
    .EXAMPLE
        # Resolve a user ID before querying their conversation history
        $userId = (Find-GenesysUser -Query 'John Smith').id
        Write-Host "Agent ID: $userId"
    .EXAMPLE
        # Check whether a leaver account still exists
        $departed = Find-GenesysUser -Query 'bob.jones@contoso.com'
        if ($departed) { Write-Warning "Account still active: $($departed.name)" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Query
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'users.search.users.by.name.or.email'
    $results | Where-Object { $_.name -like "*$Query*" -or $_.email -like "*$Query*" }
}

function Get-GenesysUserWithDivision {
    <#
    .SYNOPSIS
        Returns users with their division membership expanded inline.
    .DESCRIPTION
        Ideal for access-reviews and compliance reports — avoids a separate
        Get-GenesysDivision lookup by embedding division name alongside user data.
    .PARAMETER DivisionName
        Wildcard to filter users by their division name.
    .EXAMPLE
        Get-GenesysUserWithDivision | Format-Table name, email, division.name
    .EXAMPLE
        # Access review: all users in the Finance division
        Get-GenesysUserWithDivision -DivisionName 'Finance' |
            Export-Csv .\finance-users.csv -NoTypeInformation
    .EXAMPLE
        # Find users not assigned to any division (possible provisioning gap)
        Get-GenesysUserWithDivision | Where-Object { -not $_.division }
    #>
    [CmdletBinding()]
    param(
        [string] $DivisionName
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'users.division.analysis.get.users.with.division.info'
    if ($DivisionName) {
        # Use Get-NestedPropertyValue to avoid StrictMode failures when division is null.
        $results = $results | Where-Object { (Get-NestedPropertyValue $_ 'division.name') -like $DivisionName }
    }
    $results
}

#endregion

# ---------------------------------------------------------------------------
#region Presence Definitions
# ---------------------------------------------------------------------------

function Get-GenesysSystemPresence {
    <#
    .SYNOPSIS
        Returns the built-in system presence definitions.
    .DESCRIPTION
        System presences (AVAILABLE, AWAY, BUSY, OFFLINE, etc.) are the canonical
        states Genesys Cloud maps all custom presences to.  Use this list as a
        reference when validating presence data in reports.
    .EXAMPLE
        Get-GenesysSystemPresence | Select-Object id, systemPresence | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'presence.get.system.presence.definitions'
}

function Get-GenesysCustomPresence {
    <#
    .SYNOPSIS
        Returns organisation-defined custom presence states.
    .DESCRIPTION
        Custom presences extend the built-in states.  Enumerate these when building
        dashboards or validating that agent-selected states map to expected system
        presence values.
    .EXAMPLE
        Get-GenesysCustomPresence | Format-Table id, name, @{n='System';e={$_.systemPresence}}
    .EXAMPLE
        # Find custom presences that map to AVAILABLE — useful for SLA calculations
        Get-GenesysCustomPresence | Where-Object systemPresence -eq 'AVAILABLE' | Format-Table name
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'presence.get.organization.presence.definitions'
}

#endregion

# ---------------------------------------------------------------------------
#region Routing Configuration
# ---------------------------------------------------------------------------

function Get-GenesysQueue {
    <#
    .SYNOPSIS
        Returns routing queues with member counts and configuration details.
    .DESCRIPTION
        Normalised fields per record:
            id          — Queue GUID
            name        — Queue display name
            divisionId  — Owning division
            memberCount — Number of agents currently joined to the queue
            joined      — Whether the authenticated user is joined (if applicable)

        Combine with Get-GenesysActiveConversation for a full operational picture.
    .PARAMETER Name
        Wildcard filter on queue name.
    .PARAMETER MinMembers
        Return only queues with at least this many joined members.
    .EXAMPLE
        # Top 10 busiest queues by member count
        Get-GenesysQueue | Sort-Object memberCount -Descending | Select-Object -First 10 | Format-Table
    .EXAMPLE
        # Alert on queues with no agents — contacts will queue indefinitely
        $empty = Get-GenesysQueue | Where-Object { $_.memberCount -eq 0 }
        if ($empty) {
            Write-Warning "Unmanned queues detected:"
            $empty | Format-Table name, id
        }
    .EXAMPLE
        Get-GenesysQueue -Name 'Support*' -MinMembers 1 | Format-Table name, memberCount
    #>
    [CmdletBinding()]
    param(
        [string] $Name,
        [int]    $MinMembers
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'routing-queues'

    if ($Name)       { $results = $results | Where-Object { $_.name        -like $Name      } }
    if ($MinMembers) { $results = $results | Where-Object { $_.memberCount -ge   $MinMembers } }

    $results
}

function Get-GenesysRoutingSkill {
    <#
    .SYNOPSIS
        Returns all routing skills defined in the organisation.
    .DESCRIPTION
        Skills are assigned to agents and used by routing rules to direct contacts
        to the most capable available agent.  Enumerate these for skills audits,
        documentation, or to validate IVR flow configuration.
    .PARAMETER Name
        Wildcard filter on skill name.
    .EXAMPLE
        Get-GenesysRoutingSkill | Measure-Object | Select-Object Count
    .EXAMPLE
        # Find all Spanish-language skills
        Get-GenesysRoutingSkill -Name '*Spanish*' | Format-Table id, name
    .EXAMPLE
        # Export full skill catalogue
        Get-GenesysRoutingSkill | Select-Object id, name |
            Export-Csv .\skills-$(Get-Date -f yyyyMMdd).csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [string] $Name
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'routing.get.all.routing.skills'
    if ($Name) { $results = $results | Where-Object { $_.name -like $Name } }
    $results
}

function Get-GenesysWrapupCode {
    <#
    .SYNOPSIS
        Returns all wrap-up codes defined in the organisation.
    .DESCRIPTION
        Wrapup codes allow agents to categorise conversations after they end.
        Audit these periodically to retire stale codes and ensure consistent
        reporting taxonomy across queues and divisions.
    .PARAMETER Name
        Wildcard filter on code name.
    .EXAMPLE
        Get-GenesysWrapupCode | Measure-Object | Select-Object Count
    .EXAMPLE
        # Alphabetical catalogue grouped by first letter
        Get-GenesysWrapupCode |
            Group-Object { $_.name.Substring(0,1).ToUpper() } |
            Sort-Object Name | Format-Table Name, Count
    .EXAMPLE
        # Find codes that have never been used (requires joining analytics data)
        $allCodes = Get-GenesysWrapupCode
        Write-Host "Total wrap-up codes: $($allCodes.Count)"
    #>
    [CmdletBinding()]
    param(
        [string] $Name
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'routing.get.all.wrapup.codes'
    if ($Name) { $results = $results | Where-Object { $_.name -like $Name } }
    $results
}

function Get-GenesysLanguage {
    <#
    .SYNOPSIS
        Returns all routing languages defined in the organisation.
    .DESCRIPTION
        Routing languages work like skills and are used to match multilingual
        contacts to appropriately qualified agents.
    .EXAMPLE
        Get-GenesysLanguage | Format-Table id, name
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'routing.get.all.languages'
}

#endregion

# ---------------------------------------------------------------------------
#region Active Conversations (real-time)
# ---------------------------------------------------------------------------

function Get-GenesysActiveConversation {
    <#
    .SYNOPSIS
        Returns all active (in-flight) conversations across every channel.
    .DESCRIPTION
        Provides a real-time snapshot of the contact centre floor.  Each object
        includes the conversation ID, participants, and routing information.
        Use for live dashboards, incident triage, or overflow monitoring.
    .EXAMPLE
        Get-GenesysActiveConversation | Measure-Object | Select-Object Count
    .EXAMPLE
        # Continuous monitor — print contact count every 30 s
        while ($true) {
            $n = (Get-GenesysActiveConversation).Count
            Write-Host "$(Get-Date -f 'HH:mm:ss')  Active contacts: $n"
            Start-Sleep 30
        }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'conversations.get.active.conversations'
}

function Get-GenesysActiveCall {
    <#
    .SYNOPSIS
        Returns active voice calls.
    .DESCRIPTION
        Filters the active conversations feed to voice channel only.
        Use for telephony-focused operational monitoring.
    .EXAMPLE
        $calls = Get-GenesysActiveCall
        Write-Host "Live voice calls: $($calls.Count)"
    .EXAMPLE
        # Show caller ID and queue for each live call
        Get-GenesysActiveCall |
            Select-Object id,
                @{ n='Queue';    e={ ($_.participants | Where-Object purpose -eq 'acd')[0].queueName } },
                @{ n='Duration'; e={ [int]((Get-Date) - [datetime]$_.startTime).TotalSeconds } } |
            Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'conversations.get.active.calls'
}

function Get-GenesysActiveChat {
    <#
    .SYNOPSIS
        Returns active web-chat conversations.
    .EXAMPLE
        $chats = Get-GenesysActiveChat
        Write-Host "Live chats: $($chats.Count)"
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'conversations.get.active.chats'
}

function Get-GenesysActiveEmail {
    <#
    .SYNOPSIS
        Returns active email conversations awaiting agent response.
    .EXAMPLE
        $emails = Get-GenesysActiveEmail
        if ($emails.Count -gt 100) {
            Write-Warning "Email queue is high: $($emails.Count) in-flight"
        }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'conversations.get.active.emails'
}

function Get-GenesysActiveCallback {
    <#
    .SYNOPSIS
        Returns active callback conversations.
    .DESCRIPTION
        Callbacks are queued return-call requests.  Monitor this count during
        high-volume periods to detect build-up before it becomes a service failure.
    .EXAMPLE
        $callbacks = Get-GenesysActiveCallback
        if ($callbacks.Count -gt 50) {
            Write-Warning "Callback queue elevated: $($callbacks.Count) pending"
        }
    .EXAMPLE
        # Callback age distribution — are any older than 30 minutes?
        Get-GenesysActiveCallback |
            Select-Object id, @{ n='AgeMinutes'; e={ [int]((Get-Date) - [datetime]$_.startTime).TotalMinutes } } |
            Where-Object AgeMinutes -gt 30 |
            Sort-Object AgeMinutes -Descending | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'conversations.get.active.callbacks'
}

function Get-GenesysCallHistory {
    <#
    .SYNOPSIS
        Returns recent call history records.
    .DESCRIPTION
        Provides the most recent completed voice interactions.  Useful for a
        quick post-incident review without waiting for an async analytics job.
    .EXAMPLE
        Get-GenesysCallHistory | Select-Object -First 20 | Format-Table id, startTime, endTime
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'conversations.get.call.history'
}

#endregion

# ---------------------------------------------------------------------------
#region Analytics (async jobs)
# ---------------------------------------------------------------------------

function Get-GenesysConversationDetail {
    <#
    .SYNOPSIS
        Retrieves detailed conversation analytics for the past 24 hours.
    .DESCRIPTION
        Submits an async analytics job, polls to completion, and returns all
        conversation detail records.  May take 1–5 minutes for large orgs.

        Each record includes: conversationId, conversationStart/End, mediaType,
        participants (with segments, talk time, hold time, ACW, wrapup code),
        queue assignments, and outcome flags.

        Use -ArtifactPath to preserve the raw JSONL output for downstream ETL
        or to hand off to a data pipeline without re-pulling from the API.
    .PARAMETER KeepArtifacts
        Retain the run folder (manifest, events, data) after the call returns.
        The path is printed to the Verbose stream.
    .PARAMETER ArtifactPath
        Write run artifacts to this specific folder.  Implies -KeepArtifacts.
    .EXAMPLE
        # Quick daily summary
        $details = Get-GenesysConversationDetail
        Write-Host "Conversations in last 24 h: $($details.Count)"
    .EXAMPLE
        # Find all conversations handled by a specific agent
        $agentId = (Find-GenesysUser -Query 'Jane Doe').id
        Get-GenesysConversationDetail |
            Where-Object { $_.participants.userId -contains $agentId }
    .EXAMPLE
        # SLA analysis — export with queue name derived from ACD participant
        Get-GenesysConversationDetail |
            Select-Object conversationId, conversationStart, conversationEnd,
                @{ n='QueueName'; e={
                    ($_.participants | Where-Object purpose -eq 'acd' | Select-Object -First 1).queueName
                }} |
            Export-Csv ".\conversations-$(Get-Date -f yyyyMMdd).csv" -NoTypeInformation
    .EXAMPLE
        # Persist artifacts for a nightly ETL job
        Get-GenesysConversationDetail -ArtifactPath 'D:\ETL\genesys\today' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string[]] $QueueId,
        [string[]] $UserId,
        [string] $MediaType,
        [string] $ConversationId,
        [string[]] $DivisionId,
        [switch] $KeepArtifacts,
        [string] $ArtifactPath
    )

    Assert-GenesysConnected
    $keep = $KeepArtifacts -or (-not [string]::IsNullOrWhiteSpace($ArtifactPath))
    $datasetParameters = New-GenesysConversationDetailDatasetParameters -Since $Since -Until $Until -QueueId $QueueId -UserId $UserId -MediaType $MediaType -ConversationId $ConversationId -DivisionId $DivisionId
    $invokeParams = @{
        Dataset       = 'analytics-conversation-details'
        KeepArtifacts = $keep
        ArtifactPath  = $ArtifactPath
    }
    if ($datasetParameters.Count -gt 0) { $invokeParams['DatasetParameters'] = $datasetParameters }
    Invoke-GenesysDataset @invokeParams
}

#endregion

# ---------------------------------------------------------------------------
#region Audit Logs
# ---------------------------------------------------------------------------

function Get-GenesysAuditEvent {
    <#
    .SYNOPSIS
        Returns audit log events for the past hour.
    .DESCRIPTION
        Submits an async audit query, polls for completion, and returns structured
        audit events.  Each event captures: timestamp, actor (user/client), action,
        entity type, entity ID/name, IP address, and contextual details.

        The default time window is the last 1 hour (current catalog configuration).
        For broader historical searches use the Genesys Cloud web UI or direct API.
    .PARAMETER Action
        Wildcard filter on the action field (e.g. 'USER_LOGIN', 'QUEUE_*', 'DELETE_*').
    .PARAMETER Username
        Wildcard filter on the actor's email address.
    .PARAMETER EntityType
        Filter by entity type (USER, QUEUE, FLOW, ROUTING_SKILL, DIVISION, …).
    .EXAMPLE
        # Who logged in during the last hour?
        Get-GenesysAuditEvent -Action '*LOGIN*' | Format-Table timestamp, user.name, user.email
    .EXAMPLE
        # Security alert — any DELETE actions in the past hour?
        $deletes = Get-GenesysAuditEvent | Where-Object { $_.action -like 'DELETE_*' }
        if ($deletes) {
            Write-Warning "DELETE actions detected!"
            $deletes | Format-Table timestamp, user.email, action, entityType, entityName
        }
    .EXAMPLE
        # Audit all changes to routing queues
        Get-GenesysAuditEvent -EntityType 'QUEUE' | Sort-Object timestamp | Format-Table
    .EXAMPLE
        # SIEM integration — append hourly audit JSON to a log file
        Get-GenesysAuditEvent |
            ConvertTo-Json -Depth 5 |
            Out-File ".\audit-$(Get-Date -f 'yyyyMMddHH').json" -Encoding UTF8
    .EXAMPLE
        # Investigate actions by a specific user (e.g. following an HR alert)
        Get-GenesysAuditEvent -Username 'bob.jones@contoso.com' |
            Sort-Object timestamp | Format-Table timestamp, action, entityType, entityName
    #>
    [CmdletBinding()]
    param(
        [string] $Action,
        [string] $Username,
        [string] $EntityType,
        [string] $EntityId,
        [string] $UserId,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected
    $datasetParameters = @{}
    if ($Since.HasValue) { $datasetParameters['StartUtc'] = $Since.Value.ToUniversalTime().ToString('o') }
    if ($Until.HasValue) { $datasetParameters['EndUtc'] = $Until.Value.ToUniversalTime().ToString('o') }
    if ($EntityType) { $datasetParameters['EntityTypes'] = @($EntityType) }
    if ($EntityId) { $datasetParameters['EntityIds'] = @($EntityId) }
    if ($UserId) { $datasetParameters['UserIds'] = @($UserId) }
    if ($Action -and $EntityType -and $Action -notmatch '[*?]') { $datasetParameters['Actions'] = @($Action) }

    $invokeParams = @{ Dataset = 'audit-logs' }
    if ($datasetParameters.Count -gt 0) { $invokeParams['DatasetParameters'] = $datasetParameters }
    $results = Invoke-GenesysDataset @invokeParams

    # Use safe nested property access to avoid StrictMode failures when
    # user or serviceContext sub-objects are absent from a record.
    if ($Action)     { $results = $results | Where-Object { (Get-PropertyValue $_ 'action')                                -like $Action     } }
    if ($Username)   { $results = $results | Where-Object { (Get-NestedPropertyValue $_ 'user.email')                     -like $Username   } }
    if ($EntityType) { $results = $results | Where-Object { Test-AnyNestedPropertyValue $_ @('serviceContext.entityType', 'entity.type', 'entityType') $EntityType -KeepWhenMissing } }
    if ($EntityId)   { $results = $results | Where-Object { Test-AnyNestedPropertyValue $_ @('serviceContext.entityId', 'serviceContext.entity.id', 'entity.id', 'entityId') $EntityId -KeepWhenMissing } }
    if ($UserId)     { $results = $results | Where-Object { Test-AnyNestedPropertyValue $_ @('user.id', 'userId', 'actor.id') $UserId -KeepWhenMissing } }

    $results
}

#endregion

# ---------------------------------------------------------------------------
#region API Usage
# ---------------------------------------------------------------------------

function Get-GenesysApiUsage {
    <#
    .SYNOPSIS
        Returns the organisation-level API usage summary.
    .DESCRIPTION
        Shows total request counts and quota consumption for the billing period.
        Use to detect applications approaching rate limits before they cause
        operational failures, or to verify a new integration is not generating
        unexpected traffic.
    .EXAMPLE
        Get-GenesysApiUsage | Format-List
    .EXAMPLE
        # Alert when over 80% of daily quota consumed
        $usage = Get-GenesysApiUsage
        if ($usage.requestCount -and $usage.quota) {
            $pct = [int]($usage.requestCount / $usage.quota * 100)
            if ($pct -gt 80) { Write-Warning "API quota at ${pct}% — review client activity." }
        }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    $records = Invoke-GenesysDataset -Dataset 'usage.get.api.usage.organization.summary'
    if ($records.Count -gt 0) { $records[0] } else { $null }
}

function Get-GenesysApiUsageByClient {
    <#
    .SYNOPSIS
        Returns API request counts broken down by OAuth client.
    .DESCRIPTION
        Identifies which integrations, bots, or scripts are making the most API
        calls.  Use to right-size rate-limit strategies, detect rogue processes,
        or attribute usage costs back to business teams.
    .PARAMETER SortByCount
        Sort descending by request count (most active client first).
    .EXAMPLE
        Get-GenesysApiUsageByClient -SortByCount | Select-Object -First 10 |
            Format-Table clientId, name, requestCount
    .EXAMPLE
        # Identify any client exceeding 10,000 requests in the period
        Get-GenesysApiUsageByClient |
            Where-Object requestCount -gt 10000 |
            Format-Table name, clientId, requestCount
    #>
    [CmdletBinding()]
    param(
        [switch] $SortByCount
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'usage.get.api.usage.by.client'
    if ($SortByCount) { $results = $results | Sort-Object requestCount -Descending }
    $results
}

function Get-GenesysApiUsageByUser {
    <#
    .SYNOPSIS
        Returns API request counts broken down by user account.
    .DESCRIPTION
        Identifies individual users (or named service accounts) generating the
        highest API traffic.  Useful for security reviews and spotting accounts
        that may be running unauthorised automation.
    .EXAMPLE
        Get-GenesysApiUsageByUser |
            Sort-Object requestCount -Descending |
            Select-Object -First 20 | Format-Table userName, userId, requestCount
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'usage.get.api.usage.by.user'
}

#endregion

# ---------------------------------------------------------------------------
#region Notifications
# ---------------------------------------------------------------------------

function Get-GenesysNotificationTopic {
    <#
    .SYNOPSIS
        Lists available notification topics for real-time WebSocket subscriptions.
    .DESCRIPTION
        Genesys Cloud delivers real-time events (agent presence changes, conversation
        updates, queue statistics, etc.) via WebSocket notification channels.
        Enumerate topics here when building event-driven integrations or monitoring
        systems so you subscribe to exactly the right feed.
    .PARAMETER Filter
        Wildcard filter on topic ID (e.g. 'v2.conversations.*').
    .EXAMPLE
        Get-GenesysNotificationTopic | Measure-Object | Select-Object Count
    .EXAMPLE
        # Find all conversation-related notification topics
        Get-GenesysNotificationTopic -Filter 'v2.conversations.*' |
            Select-Object id, description | Format-Table
    .EXAMPLE
        # Topics relevant to queue monitoring
        Get-GenesysNotificationTopic -Filter '*queue*' | Format-Table id, description
    #>
    [CmdletBinding()]
    param(
        [string] $Filter
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'notifications.get.available.notification.topics'
    if ($Filter) { $results = $results | Where-Object { $_.id -like $Filter } }
    $results
}

function Get-GenesysNotificationSubscription {
    <#
    .SYNOPSIS
        Returns active notification subscriptions for the authenticated client.
    .DESCRIPTION
        Useful when debugging a WebSocket integration — confirms which topics the
        current OAuth client is subscribed to.
    .EXAMPLE
        Get-GenesysNotificationSubscription | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'notifications.get.notification.subscriptions'
}

#endregion

# ---------------------------------------------------------------------------
#region Composite Operational Commands
# ---------------------------------------------------------------------------

function Get-GenesysContactCentreStatus {
    <#
    .SYNOPSIS
        Returns a real-time contact centre health snapshot in a single object.
    .DESCRIPTION
        Aggregates agents, queues, and active conversation counts into one
        summary object.  Designed for IT Ops dashboards, alerting scripts, or
        chat-ops bots that post a floor health update on a schedule.

        Each section is collected independently.  When a section fails, its
        fields in the output are $null and a Diagnostics property is populated
        with per-section status.  Pass -ErrorAction Stop to abort on first failure.
    .PARAMETER FailFast
        Stop immediately if any section fails (equivalent to -ErrorAction Stop
        for each internal call).
    .EXAMPLE
        Get-GenesysContactCentreStatus | Format-List
    .EXAMPLE
        # Post status to a Teams channel via webhook every 5 minutes
        while ($true) {
            $s = Get-GenesysContactCentreStatus
            $text = "Agents on-queue: $($s.AgentsOnQueue)  |  " +
                    "Active contacts: $($s.TotalActiveContacts)  |  " +
                    "Empty queues: $($s.EmptyQueues)"
            Invoke-RestMethod -Uri $env:TEAMS_WEBHOOK_URI -Method Post `
                -Body (@{ text = $text } | ConvertTo-Json) `
                -ContentType 'application/json'
            Start-Sleep 300
        }
    .EXAMPLE
        # Alert if more than 5 queues are unmanned
        $status = Get-GenesysContactCentreStatus
        if ($status.EmptyQueues -gt 5) {
            Write-Warning "$($status.EmptyQueues) queues have no agents joined"
        }
    #>
    [CmdletBinding()]
    param(
        [switch] $FailFast
    )

    Assert-GenesysConnected

    $diag = [System.Collections.Generic.List[object]]::new()

    # Collect each section independently; failures populate $diag but do not abort.
    function Add-Diag {
        param([string]$Section, [string]$Status, $Count, [string]$Error)
        $diag.Add([PSCustomObject]@{ Section = $Section; Status = $Status; Count = $Count; Error = $Error })
    }

    Write-Verbose 'Fetching agents...'
    $agents = [System.Object[]]@()
    try {
        $agents = [System.Object[]]@(Get-GenesysAgent)
        Add-Diag 'Agents' 'OK' $agents.Count $null
    } catch { Add-Diag 'Agents' 'Failed' $null "$($_.Exception.Message)"; Write-Warning "Agents: $_"; if ($FailFast) { throw } }

    Write-Verbose 'Fetching queues...'
    $queues = [System.Object[]]@()
    try {
        $queues = [System.Object[]]@(Get-GenesysQueue)
        Add-Diag 'Queues' 'OK' $queues.Count $null
    } catch { Add-Diag 'Queues' 'Failed' $null "$($_.Exception.Message)"; Write-Warning "Queues: $_"; if ($FailFast) { throw } }

    Write-Verbose 'Fetching active calls...'
    $calls = [System.Object[]]@()
    try {
        $calls = [System.Object[]]@(Get-GenesysActiveCall)
        Add-Diag 'ActiveCalls' 'OK' $calls.Count $null
    } catch { Add-Diag 'ActiveCalls' 'Failed' $null "$($_.Exception.Message)"; Write-Warning "ActiveCalls: $_"; if ($FailFast) { throw } }

    Write-Verbose 'Fetching active chats...'
    $chats = [System.Object[]]@()
    try {
        $chats = [System.Object[]]@(Get-GenesysActiveChat)
        Add-Diag 'ActiveChats' 'OK' $chats.Count $null
    } catch { Add-Diag 'ActiveChats' 'Failed' $null "$($_.Exception.Message)"; Write-Warning "ActiveChats: $_"; if ($FailFast) { throw } }

    Write-Verbose 'Fetching active emails...'
    $emails = [System.Object[]]@()
    try {
        $emails = [System.Object[]]@(Get-GenesysActiveEmail)
        Add-Diag 'ActiveEmails' 'OK' $emails.Count $null
    } catch { Add-Diag 'ActiveEmails' 'Failed' $null "$($_.Exception.Message)"; Write-Warning "ActiveEmails: $_"; if ($FailFast) { throw } }

    Write-Verbose 'Fetching active callbacks...'
    $callbacks = [System.Object[]]@()
    $callbackFailed = $false
    try {
        $callbacks = [System.Object[]]@(Get-GenesysActiveCallback)
        Add-Diag 'ActiveCallbacks' 'OK' $callbacks.Count $null
    } catch {
        $callbackFailed = $true
        Add-Diag 'ActiveCallbacks' 'Failed' $null "$($_.Exception.Message)"
        Write-Warning "ActiveCallbacks: $_"
        if ($FailFast) { throw }
    }

    $callbackCount          = if ($callbackFailed) { 0 } else { $callbacks.Count }
    $activeCallbacksValue   = if ($callbackFailed) { $null } else { $callbackCount }
    $callbackCountForTotal  = $callbackCount

    [PSCustomObject]@{
        Timestamp           = Get-Date -Format 'o'
        TotalAgents         = $agents.Count
        AgentsOnQueue       = @($agents | Where-Object { $_.routingStatus -in @('IDLE','INTERACTING') }).Count
        AgentsAvailable     = @($agents | Where-Object { $_.presence -eq 'AVAILABLE'                 }).Count
        AgentsOffline       = @($agents | Where-Object { $_.presence -eq 'OFFLINE'                   }).Count
        TotalQueues         = $queues.Count
        EmptyQueues         = @($queues | Where-Object { $_.memberCount -eq 0                        }).Count
        ActiveCalls         = $calls.Count
        ActiveChats         = $chats.Count
        ActiveEmails        = $emails.Count
        ActiveCallbacks     = $activeCallbacksValue
        TotalActiveContacts = $calls.Count + $chats.Count + $emails.Count + $callbackCountForTotal
        Diagnostics         = $diag.ToArray()
    }
}

function Invoke-GenesysDailyHealthReport {
    <#
    .SYNOPSIS
        Generates a daily operations health report.
    .DESCRIPTION
        Runs multiple dataset pulls in sequence and produces a structured report
        covering organisation details, agent headcount and presence distribution,
        queue roster, API quota consumption, and recent audit events.

        Designed to run as a scheduled task each morning or at shift handover.
        Use -OutputPath to write the report as JSON for downstream consumption
        (dashboards, ticketing systems, log aggregators).

        Each section is collected independently.  When a section fails its data
        is $null in the report and Diagnostics shows the section error.
    .PARAMETER OutputPath
        If specified, the report is serialised as UTF-8 JSON to this path.
    .PARAMETER PassThru
        Return the report object even when -OutputPath is used.
    .PARAMETER FailFast
        Abort the report on the first failed section.
    .EXAMPLE
        # Morning check — display in console
        Invoke-GenesysDailyHealthReport | ConvertTo-Json -Depth 5
    .EXAMPLE
        # Scheduled task — write daily report file
        Invoke-GenesysDailyHealthReport -OutputPath "D:\Reports\GenesysHealth-$(Get-Date -f yyyyMMdd).json"
    .EXAMPLE
        # Programmatic alerting based on report contents
        $report = Invoke-GenesysDailyHealthReport -PassThru
        if ($report.Queues.EmptyCount -gt 0) {
            Write-Warning "$($report.Queues.EmptyCount) queues have no agents joined."
        }
        if ($report.RecentAudit.DeleteCount -gt 0) {
            Write-Warning "$($report.RecentAudit.DeleteCount) DELETE audit events in the last hour!"
        }
    #>
    [CmdletBinding()]
    param(
        [string] $OutputPath,
        [switch] $PassThru,
        [switch] $FailFast
    )

    Assert-GenesysConnected

    $diag = [System.Collections.Generic.List[object]]::new()

    function Invoke-ReportSection {
        param([string]$Name, [scriptblock]$Action)
        try {
            $r = & $Action
            $diag.Add([PSCustomObject]@{ Section = $Name; Status = 'OK'; Error = $null })
            return $r
        } catch {
            $msg = "$($Name): $_"
            $diag.Add([PSCustomObject]@{ Section = $Name; Status = 'Failed'; Error = $msg })
            Write-Warning $msg
            if ($FailFast) { throw $msg }
            return $null
        }
    }

    Write-Verbose 'Collecting organisation details...'
    $org    = Invoke-ReportSection 'Organisation' { Get-GenesysOrganization }

    Write-Verbose 'Collecting agent roster...'
    $agents = Invoke-ReportSection 'Agents' { @(Get-GenesysAgent) }

    Write-Verbose 'Collecting queue details...'
    $queues = Invoke-ReportSection 'Queues' { @(Get-GenesysQueue) }

    Write-Verbose 'Collecting API usage...'
    $usage  = Invoke-ReportSection 'ApiUsage' { Get-GenesysApiUsage }

    Write-Verbose 'Collecting recent audit events...'
    $audit  = Invoke-ReportSection 'Audit' { @(Get-GenesysAuditEvent) }

    $presenceBreakdown = if ($agents) {
        $agents |
            Group-Object presence |
            Sort-Object Count -Descending |
            ForEach-Object { [PSCustomObject]@{ Presence = $_.Name; Count = $_.Count } }
    } else { $null }

    $report = [PSCustomObject]@{
        GeneratedAt  = Get-Date -Format 'o'
        Organisation = if ($org) {
            [PSCustomObject]@{
                Name            = (Get-PropertyValue $org 'name')
                Id              = (Get-PropertyValue $org 'id')
                DefaultLanguage = (Get-PropertyValue $org 'defaultLanguage')
            }
        } else { $null }
        Agents       = if ($agents) {
            [PSCustomObject]@{
                Total             = $agents.Count
                Active            = @($agents | Where-Object { $_.state         -eq 'ACTIVE'               }).Count
                OnQueue           = @($agents | Where-Object { $_.routingStatus -in @('IDLE','INTERACTING') }).Count
                PresenceBreakdown = $presenceBreakdown
            }
        } else { $null }
        Queues       = if ($queues) {
            [PSCustomObject]@{
                Total        = $queues.Count
                EmptyCount   = @($queues | Where-Object { $_.memberCount -eq 0 }).Count
                TopByMembers = ($queues | Sort-Object memberCount -Descending | Select-Object -First 5 |
                                   Select-Object name, memberCount)
            }
        } else { $null }
        ApiUsage     = $usage
        RecentAudit  = if ($audit) {
            [PSCustomObject]@{
                TotalEvents  = $audit.Count
                LoginCount   = @($audit | Where-Object { (Get-PropertyValue $_ 'action') -like '*LOGIN*'  }).Count
                DeleteCount  = @($audit | Where-Object { (Get-PropertyValue $_ 'action') -like 'DELETE_*' }).Count
            }
        } else { $null }
        Diagnostics  = $diag.ToArray()
    }

    if ($OutputPath) {
        $report | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Verbose "Report saved: $($OutputPath)"
    }

    if ($PassThru -or -not $OutputPath) { $report }
}

function Export-GenesysConfigurationSnapshot {
    <#
    .SYNOPSIS
        Exports a complete configuration snapshot (queues, skills, wrapup codes,
        languages, divisions) to a folder as individual CSV files.
    .DESCRIPTION
        Run before and after planned changes as a change-management baseline, or
        schedule weekly to track configuration drift.  Each entity type is written
        to its own CSV so the files can be diff-ed independently.

        Sections that fail are noted in the returned manifest with Status='Failed'.
        A FailFast switch stops on the first section failure.
    .PARAMETER OutputFolder
        Folder to write CSV files into.  Created if it does not exist.
    .PARAMETER FailFast
        Abort on the first section export failure.
    .EXAMPLE
        Export-GenesysConfigurationSnapshot -OutputFolder '.\config-baseline-20260223'
    .EXAMPLE
        # Before/after change comparison
        $before = '.\config-before'
        $after  = '.\config-after'
        Export-GenesysConfigurationSnapshot -OutputFolder $before
        # ... make changes ...
        Export-GenesysConfigurationSnapshot -OutputFolder $after

        # Compare queue counts
        $b = Import-Csv "$before\queues.csv"
        $a = Import-Csv "$after\queues.csv"
        Compare-Object $b $a -Property name -PassThru | Format-Table SideIndicator, name
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $OutputFolder,

        [switch] $FailFast
    )

    Assert-GenesysConnected

    if ($PSCmdlet.ShouldProcess($OutputFolder, 'Write configuration snapshot CSVs')) {
        $resolvedFolder = if ([System.IO.Path]::IsPathRooted($OutputFolder)) {
            [System.IO.Path]::GetFullPath($OutputFolder)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputFolder))
        }
        if (-not (Test-Path $resolvedFolder)) {
            $null = New-Item -ItemType Directory -Path $resolvedFolder -Force
        }

        $stamp    = Get-Date -Format 'o'
        $sections = [System.Collections.Generic.List[object]]::new()

        function Export-Section {
            param([string]$Name, [string]$File, [scriptblock]$Action, [string[]]$Fields)
            $csvPath = Join-Path $resolvedFolder $File
            try {
                $data = & $Action
                $data | Select-Object $Fields | Export-Csv $csvPath -NoTypeInformation
                $sections.Add([PSCustomObject]@{ Section = $Name; File = $File; Status = 'OK';     Count = @($data).Count; Error = $null })
            } catch {
                $msg = "$($Name): $_"
                $sections.Add([PSCustomObject]@{ Section = $Name; File = $File; Status = 'Failed'; Count = $null;          Error = $msg  })
                Write-Warning $msg
                if ($FailFast) { throw $msg }
            }
        }

        Write-Verbose 'Exporting queues...'
        Export-Section 'Queues'         'queues.csv'         { Get-GenesysQueue }         @('id','name','divisionId','memberCount')

        Write-Verbose 'Exporting routing skills...'
        Export-Section 'RoutingSkills'  'routing-skills.csv' { Get-GenesysRoutingSkill }  @('id','name')

        Write-Verbose 'Exporting wrapup codes...'
        Export-Section 'WrapupCodes'    'wrapup-codes.csv'   { Get-GenesysWrapupCode }    @('id','name')

        Write-Verbose 'Exporting languages...'
        Export-Section 'Languages'      'languages.csv'      { Get-GenesysLanguage }      @('id','name')

        Write-Verbose 'Exporting divisions...'
        Export-Section 'Divisions'      'divisions.csv'      { Get-GenesysDivision }      @('id','name')

        Write-Verbose 'Exporting agents...'
        Export-Section 'Agents'         'agents.csv'         { Get-GenesysAgent }         @('id','name','email','state')

        # Write manifest
        $csvFiles = (Get-ChildItem $resolvedFolder -Filter '*.csv').Name
        $manifest = [PSCustomObject]@{
            SnapshotTimestamp = $stamp
            OutputFolder      = $resolvedFolder
            Files             = $csvFiles
            Sections          = $sections.ToArray()
        }
        $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $resolvedFolder 'manifest.json') -Encoding UTF8

        Write-Verbose "Snapshot complete: $($resolvedFolder)"

        [PSCustomObject]@{
            OutputFolder = $resolvedFolder
            Files        = $csvFiles
            Sections     = $sections.ToArray()
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Private normalizers — analytics result flatteners (not exported)
# ---------------------------------------------------------------------------

function ConvertFrom-ObservationResult {
    <#
    Private. Flattens a Genesys analytics observation result record
    { group:{dimA, dimB}, data:[{interval, metrics:[{metric, stats:{count}}]}] }
    into a single PSCustomObject with group dimensions + each metric as a named
    property (using the raw metric name, e.g. oInteracting, oWaiting).
    Uses safe property access to avoid StrictMode failures on partial API results.
    #>
    param(
        [Parameter(ValueFromPipeline)]
        [object] $InputObject
    )
    process {
        $r = $InputObject
        if ($null -eq $r) { return }
        $props = [ordered]@{}
        $group = Get-PropertyValue $r 'group'
        if ($group) {
            $group.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
        }
        $data = Get-PropertyValue $r 'data'
        if ($data -and @($data).Count -gt 0) {
            $firstData = @($data)[0]
            $props['Interval'] = Get-PropertyValue $firstData 'interval'
            $metrics = Get-PropertyValue $firstData 'metrics'
            if ($metrics) {
                foreach ($m in @($metrics)) {
                    $metricName = Get-PropertyValue $m 'metric'
                    if (-not $metricName) { continue }
                    $stats = Get-PropertyValue $m 'stats'
                    $props[$metricName] = if ($stats) { Get-PropertyValue $stats 'count' } else { $null }
                }
            }
        }
        [PSCustomObject]$props
    }
}

function ConvertFrom-AggregateResult {
    <#
    Private. Flattens a Genesys analytics aggregate result record
    { group:{dimA, dimB}, data:[{interval, metrics:[{metric, stats:{count,sum,min,max}}]}] }
    into one PSCustomObject per group+interval with columns:
        <metric>_count, <metric>_sum, <metric>_min, <metric>_max
    Uses safe property access to avoid StrictMode failures on partial API results.
    #>
    param(
        [Parameter(ValueFromPipeline)]
        [object] $InputObject
    )
    process {
        $r = $InputObject
        if ($null -eq $r) { return }
        $group = Get-PropertyValue $r 'group'
        $data  = Get-PropertyValue $r 'data'
        if (-not $data) { return }
        foreach ($d in @($data)) {
            if ($null -eq $d) { continue }
            $props = [ordered]@{ Interval = Get-PropertyValue $d 'interval' }
            if ($group) {
                $group.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
            }
            $metrics = Get-PropertyValue $d 'metrics'
            if ($metrics) {
                foreach ($m in @($metrics)) {
                    if ($null -eq $m) { continue }
                    $key   = Get-PropertyValue $m 'metric'
                    if (-not $key) { continue }
                    $stats = Get-PropertyValue $m 'stats'
                    $props["${key}_count"] = if ($stats) { Get-PropertyValue $stats 'count' } else { $null }
                    $props["${key}_sum"]   = if ($stats) { Get-PropertyValue $stats 'sum'   } else { $null }
                    $props["${key}_min"]   = if ($stats) { Get-PropertyValue $stats 'min'   } else { $null }
                    $props["${key}_max"]   = if ($stats) { Get-PropertyValue $stats 'max'   } else { $null }
                }
            }
            [PSCustomObject]$props
        }
    }
}

function Get-MosCategory ([object]$Mos) {
    if ($null -eq $Mos) { return 'Unknown' }
    $v = [double]$Mos
    if ($v -ge 4.0) { return 'Good' }
    if ($v -ge 3.6) { return 'Fair' }
    if ($v -ge 3.1) { return 'Poor' }
    return 'Bad'
}

#endregion

# ---------------------------------------------------------------------------
#region Operational Events — Observations & Aggregates
# ---------------------------------------------------------------------------

function Get-GenesysQueueObservation {
    <#
    .SYNOPSIS
        Returns real-time queue observation metrics.
    .DESCRIPTION
        Queries the analytics observations endpoint and returns one flattened record
        per queue/mediaType combination.  Each record contains instantaneous counts:

            QueueId        — Genesys queue GUID
            MediaType      — voice, chat, email, etc.
            Interval       — observation snapshot timestamp
            oInteracting   — agents currently interacting with a contact
            oWaiting       — contacts waiting in queue
            oOnQueueUsers  — agents joined and on-queue
            oOffQueueUsers — agents joined but off-queue (e.g. in ACW)
            oActiveUsers   — agents in an active state

        With no parameters, returns observations for all queues.  Provide -QueueId
        and/or -MediaType to scope the query.
    .PARAMETER QueueId
        One or more queue GUIDs to filter on.
    .PARAMETER MediaType
        Single media type (e.g. voice, chat, email) to filter on.
    .EXAMPLE
        # Current queue floor view
        Get-GenesysQueueObservation | Sort-Object oWaiting -Descending | Format-Table QueueId, oWaiting, oInteracting, oOnQueueUsers
    .EXAMPLE
        Get-GenesysQueueObservation -QueueId '11111111-2222-3333-4444-555555555555' -MediaType voice
    #>
    [CmdletBinding()]
    param(
        [string[]] $QueueId,
        [string]   $MediaType
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        metrics = @('oInteracting', 'oWaiting', 'oOnQueueUsers', 'oOffQueueUsers', 'oActiveUsers')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{
        queueId   = $QueueId
        mediaType = $MediaType
    }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    Invoke-GenesysDataset -Dataset 'analytics.query.queue.observations.real.time.stats' `
                          -DatasetParameters @{ Body = $body } |
        ConvertFrom-ObservationResult
}

function Get-GenesysUserObservation {
    <#
    .SYNOPSIS
        Returns real-time agent observation records (presence and routing status).
    .DESCRIPTION
        Returns one record per agent with current oUserPresence and oUserRoutingStatus.

            UserId             — Genesys user GUID
            Interval           — observation snapshot timestamp
            oUserPresence      — current presence state count
            oUserRoutingStatus — current routing status count

        With no parameters, returns organisation-wide observations.  Provide -UserId
        to filter to specific agents.
    .PARAMETER UserId
        One or more user GUIDs to filter on.
    .EXAMPLE
        Get-GenesysUserObservation | Format-Table UserId, Interval, oUserPresence, oUserRoutingStatus
    #>
    [CmdletBinding()]
    param(
        [string[]] $UserId
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        metrics = @('oUserPresence', 'oUserRoutingStatus')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{ userId = $UserId }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    Invoke-GenesysDataset -Dataset 'analytics.query.user.observations.real.time.status' `
                          -DatasetParameters @{ Body = $body } |
        ConvertFrom-ObservationResult
}

function Get-GenesysQueuePerformance {
    <#
    .SYNOPSIS
        Returns historical queue conversation aggregate metrics.
    .DESCRIPTION
        Fetches the conversation aggregates dataset grouped by queue and returns
        flattened records ready for performance reporting.  Each record covers one
        queue+mediaType+interval combination with columns for each metric:

            queueId                  — queue GUID
            mediaType                — voice, chat, email, etc.
            Interval                 — aggregate time bucket
            nConnected_count         — number of connected conversations
            tHandle_sum              — total handle time (ms)
            tTalk_sum                — total talk time (ms)
            tAcw_sum                 — total after-call work time (ms)
            tAnswered_sum            — total time to answer (ms)
            nOffered_count           — contacts offered to queue

        Derive averages: tHandle_sum / nConnected_count / 1000 = avg handle seconds.

    .PARAMETER QueueId
        Filter to a specific queue GUID.
    .PARAMETER MediaType
        Filter by media type.
    .PARAMETER Since
        Inclusive start of the aggregation interval.
    .PARAMETER Until
        Exclusive end of the aggregation interval.
    .PARAMETER Granularity
        Time bucket granularity (e.g. PT1H, PT15M).
    .EXAMPLE
        $perf = Get-GenesysQueuePerformance
        $perf | Select-Object queueId, Interval, nConnected_count,
            @{ n='AvgHandleSec'; e={ if ($_.nConnected_count) { [int]($_.tHandle_sum / $_.nConnected_count / 1000) } } } |
            Format-Table
    #>
    [CmdletBinding()]
    param(
        [string[]]           $QueueId,
        [string]             $MediaType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string]             $Granularity
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        interval = New-GenesysAnalyticsInterval -Since $Since -Until $Until -DefaultLookbackHours 24
        groupBy  = @('queueId')
        metrics  = @('nConnected', 'tHandle', 'tTalk', 'tAcw', 'tAnswered', 'nOffered')
    }

    if (-not [string]::IsNullOrWhiteSpace($Granularity)) {
        $body.granularity = $Granularity
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{
        queueId   = $QueueId
        mediaType = $MediaType
    }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.queue.performance' `
                          -DatasetParameters @{ Body = $body } |
        ConvertFrom-AggregateResult
}

#endregion

# ---------------------------------------------------------------------------
#region OAuth Clients & Authorizations
# ---------------------------------------------------------------------------

function Get-GenesysOAuthClient {
    <#
    .SYNOPSIS
        Returns all OAuth client applications registered in the organisation.
    .DESCRIPTION
        OAuth clients represent integrations, bots, or service accounts that
        authenticate to Genesys Cloud via the API.  Audit this list to:
          - Identify stale or unknown client IDs
          - Review which grant types are in use (client_credentials, code, implicit)
          - Confirm clients are not over-scoped

        Key fields per record:
            id            — Client GUID (the clientId used in token requests)
            name          — Display name
            description   — Free-text description
            authorizedGrantTypes — Array of OAuth grant types
            scope         — Approved API scopes
            registeredRedirectUri — Redirect URIs for code/implicit grants
            createdDate   — When the client was registered
    .PARAMETER Name
        Wildcard filter on client display name.
    .PARAMETER GrantType
        Filter by grant type (client_credentials, authorization_code, implicit, etc.).
    .EXAMPLE
        Get-GenesysOAuthClient | Format-Table id, name, authorizedGrantTypes
    .EXAMPLE
        # Find all client-credentials service accounts (no user interaction)
        Get-GenesysOAuthClient -GrantType 'client_credentials' |
            Format-Table id, name, createdDate
    .EXAMPLE
        # Security review — export all OAuth clients
        Get-GenesysOAuthClient | Select-Object id, name, authorizedGrantTypes, createdDate |
            Export-Csv .\oauth-clients-$(Get-Date -f yyyyMMdd).csv -NoTypeInformation
    .EXAMPLE
        # Find clients with no description (undocumented integrations)
        Get-GenesysOAuthClient | Where-Object { -not $_.description } | Format-Table id, name
    #>
    [CmdletBinding()]
    param(
        [string] $Name,
        [string] $GrantType
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'oauth.get.clients'
    if ($Name)      { $results = $results | Where-Object { $_.name -like $Name } }
    if ($GrantType) { $results = $results | Where-Object { $_.authorizedGrantTypes -contains $GrantType } }
    $results
}

function Get-GenesysOAuthAuthorization {
    <#
    .SYNOPSIS
        Returns active OAuth authorization grants issued to users.
    .DESCRIPTION
        An authorization represents a user's consent for an OAuth client to act
        on their behalf.  Review this list to identify:
          - Users who have authorized third-party apps you don't recognise
          - Authorizations for clients that have since been decommissioned
          - Unexpectedly broad scope grants

        Key fields per record:
            client.id     — OAuth client GUID
            client.name   — Client display name
            scope         — Scopes the user consented to
            dateCreated   — When the user granted authorization
    .EXAMPLE
        Get-GenesysOAuthAuthorization | Format-Table client.name, scope, dateCreated
    .EXAMPLE
        # Find all authorizations for a specific client (e.g. investigating a compromised client)
        $clientId = (Get-GenesysOAuthClient -Name 'Reporting Bot').id
        Get-GenesysOAuthAuthorization | Where-Object { $_.client.id -eq $clientId }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'oauth.get.authorizations'
}

function Get-GenesysRateLimitEvent {
    <#
    .SYNOPSIS
        Returns API rate-limit aggregate data (errors and over-limit events).
    .DESCRIPTION
        Queries the rate-limit aggregates analytics endpoint.  Returns flattened
        records with columns:

            userId           — User or client that hit the limit
            Interval         — Time bucket
            nError_count     — Number of error responses in the interval
            nOverLimit_count — Number of 429 rate-limit responses

        Use this to identify which users or automated scripts are generating the
        most rate-limit pressure, enabling proactive throttling or backoff tuning.
    .EXAMPLE
        Get-GenesysRateLimitEvent | Where-Object { $_.nOverLimit_count -gt 0 } |
            Sort-Object nOverLimit_count -Descending | Format-Table
    .EXAMPLE
        # Combine with OAuth client data for enriched reporting
        $limits = Get-GenesysRateLimitEvent
        $clients = Get-GenesysApiUsageByClient
        $limits | Select-Object userId, Interval, nOverLimit_count |
            Sort-Object nOverLimit_count -Descending | Select-Object -First 10 | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'analytics.query.rate.limit.aggregates' |
        ConvertFrom-AggregateResult
}

#endregion

# ---------------------------------------------------------------------------
#region Outbound Campaigns & Events
# ---------------------------------------------------------------------------

function Get-GenesysOutboundCampaign {
    <#
    .SYNOPSIS
        Returns outbound dialing campaigns with current status and configuration.
    .DESCRIPTION
        Each record describes one campaign.  Key fields:

            id              — Campaign GUID
            name            — Campaign display name
            campaignStatus  — on / off / complete / stopping / invalid
            dialingMode     — preview, power, progressive, agentless, etc.
            contactListId   — Associated contact list
            queueId         — Destination queue for connected calls
            callerName      — Caller ID name presented to contacts
            callerAddress   — Caller ID number
            noAnswerTimeout — Seconds before no-answer disposition
            abandonRate     — Maximum acceptable abandon rate (%)
    .PARAMETER Name
        Wildcard filter on campaign name.
    .PARAMETER Status
        Filter by campaignStatus (on, off, complete, stopping, invalid).
    .EXAMPLE
        # Which campaigns are currently running?
        Get-GenesysOutboundCampaign -Status 'on' | Format-Table name, dialingMode, callerAddress
    .EXAMPLE
        # Campaigns that completed — ready for reconciliation
        Get-GenesysOutboundCampaign -Status 'complete' | Select-Object name, id | Format-Table
    .EXAMPLE
        Get-GenesysOutboundCampaign | Sort-Object campaignStatus | Format-Table name, campaignStatus, dialingMode
    #>
    [CmdletBinding()]
    param(
        [string] $Name,
        [ValidateSet('on','off','complete','stopping','invalid')]
        [string] $Status
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'outbound.get.campaigns'
    if ($Name)   { $results = $results | Where-Object { $_.name           -like $Name   } }
    if ($Status) { $results = $results | Where-Object { $_.campaignStatus -eq   $Status } }
    $results
}

function Get-GenesysOutboundContactList {
    <#
    .SYNOPSIS
        Returns outbound contact list definitions.
    .DESCRIPTION
        Contact lists hold the records dialled by outbound campaigns.  Each list
        definition includes:

            id              — Contact list GUID
            name            — Display name
            columnNames     — Data columns in the list (phone, firstName, etc.)
            phoneNumberColumns — Which columns are phone-number fields
            size            — Number of contacts in the list
            importStatus    — Whether the most recent import succeeded
    .PARAMETER Name
        Wildcard filter on contact list name.
    .EXAMPLE
        Get-GenesysOutboundContactList | Format-Table id, name, size, importStatus.importState
    .EXAMPLE
        # Find lists that failed to import — potential data pipeline issue
        Get-GenesysOutboundContactList |
            Where-Object { $_.importStatus.importState -eq 'Failed' } |
            Format-Table name, id
    #>
    [CmdletBinding()]
    param(
        [string] $Name
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'outbound.get.contact.lists'
    if ($Name) { $results = $results | Where-Object { $_.name -like $Name } }
    $results
}

function Get-GenesysOutboundEvent {
    <#
    .SYNOPSIS
        Returns outbound dialer events — campaign and contact disposition records.
    .DESCRIPTION
        Dialer events capture each attempt outcome: connected, no-answer, busy,
        voicemail, etc.  Use for campaign reconciliation, compliance auditing, and
        contact-attempt frequency analysis.

        Key fields:
            id              — Event GUID
            type            — Event type (e.g. campaignStart, contactCallCompleted)
            campaignId      — Source campaign
            timestamp       — When the event occurred
            contactId       — The contact record that was dialled
            callResult      — Attempt outcome (Connected, NoAnswer, Busy, etc.)
    .PARAMETER EventType
        Wildcard filter on event type.
    .EXAMPLE
        Get-GenesysOutboundEvent | Group-Object callResult | Select-Object Name, Count | Sort-Object Count -Descending
    .EXAMPLE
        # Find all connected outbound calls for reconciliation
        Get-GenesysOutboundEvent | Where-Object { $_.callResult -eq 'Connected' } | Format-Table timestamp, campaignId, contactId
    #>
    [CmdletBinding()]
    param(
        [string] $EventType
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'outbound.get.events'
    if ($EventType) { $results = $results | Where-Object { $_.type -like $EventType } }
    $results
}

function Get-GenesysMessagingCampaign {
    <#
    .SYNOPSIS
        Returns outbound messaging (SMS / digital) campaigns.
    .DESCRIPTION
        Messaging campaigns send proactive outbound messages via SMS or other
        digital channels.  Key fields:

            id              — Campaign GUID
            name            — Campaign display name
            campaignStatus  — on / off / complete / stopping
            messagesPerMinute — Send rate
            contactListId   — Source contact list
            smsConfig       — SMS-specific configuration (sender, contentTemplate)
    .PARAMETER Name
        Wildcard filter on campaign name.
    .PARAMETER Status
        Filter by campaignStatus (on, off, complete, stopping).
    .EXAMPLE
        Get-GenesysMessagingCampaign | Format-Table name, campaignStatus, messagesPerMinute
    .EXAMPLE
        Get-GenesysMessagingCampaign -Status 'on' | Select-Object name, smsConfig | Format-Table
    #>
    [CmdletBinding()]
    param(
        [string] $Name,
        [string] $Status
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'outbound.get.messaging.campaigns'
    if ($Name)   { $results = $results | Where-Object { $_.name           -like $Name   } }
    if ($Status) { $results = $results | Where-Object { $_.campaignStatus -eq   $Status } }
    $results
}

#endregion

# ---------------------------------------------------------------------------
#region Flow / Architect Performance
# ---------------------------------------------------------------------------

function Get-GenesysFlow {
    <#
    .SYNOPSIS
        Returns all Architect flow definitions.
    .DESCRIPTION
        Architect flows control the routing logic for inbound calls, outbound calls,
        in-queue music/messaging, bots, and more.  Each record includes:

            id              — Flow GUID
            name            — Flow name
            type            — inboundcall, outboundcall, inqueuecall, bot, etc.
            publishedVersion.id — Currently published version GUID
            activeVersion.id    — Active (potentially unpublished) version GUID
            locked          — Whether the flow is locked for editing
    .PARAMETER Name
        Wildcard filter on flow name.
    .PARAMETER FlowType
        Filter by flow type (inboundcall, outboundcall, inqueuecall, bot, etc.).
    .EXAMPLE
        Get-GenesysFlow | Group-Object type | Select-Object Name, Count | Format-Table
    .EXAMPLE
        # Find all inbound IVR flows
        Get-GenesysFlow -FlowType 'inboundcall' | Format-Table name, id
    .EXAMPLE
        # Export flow inventory for documentation
        Get-GenesysFlow | Select-Object id, name, type, @{n='Version';e={$_.publishedVersion.id}} |
            Export-Csv .\flows-$(Get-Date -f yyyyMMdd).csv -NoTypeInformation
    .EXAMPLE
        # Find flows without a published version (draft / broken)
        Get-GenesysFlow | Where-Object { -not $_.publishedVersion } | Format-Table name, type, id
    #>
    [CmdletBinding()]
    param(
        [string] $Name,
        [string] $FlowType
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'flows.get.all.flows'
    if ($Name)     { $results = $results | Where-Object { $_.name -like $Name     } }
    if ($FlowType) { $results = $results | Where-Object { $_.type -eq   $FlowType } }
    $results
}

function Get-GenesysFlowOutcome {
    <#
    .SYNOPSIS
        Returns flow outcome definitions.
    .DESCRIPTION
        Flow outcomes are configurable labels applied when a contact exits an
        Architect flow.  They appear in analytics as nFlowOutcome and can be
        used to measure self-service success rates.

        Key fields: id, name, description, divisionId
    .PARAMETER Name
        Wildcard filter on outcome name.
    .EXAMPLE
        Get-GenesysFlowOutcome | Format-Table id, name, description
    .EXAMPLE
        # Build a lookup table for enriching flow aggregate reports
        $outcomeMap = Get-GenesysFlowOutcome | Group-Object id -AsHashTable -AsString
    #>
    [CmdletBinding()]
    param(
        [string] $Name
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'flows.get.flow.outcomes'
    if ($Name) { $results = $results | Where-Object { $_.name -like $Name } }
    $results
}

function Get-GenesysFlowMilestone {
    <#
    .SYNOPSIS
        Returns flow milestone definitions.
    .DESCRIPTION
        Flow milestones are named checkpoints placed inside Architect flows to
        track how far through a self-service journey each contact progresses.
        Analytics count them as nFlowMilestone.

        Key fields: id, name, description, divisionId
    .EXAMPLE
        Get-GenesysFlowMilestone | Format-Table id, name, description
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'flows.get.flow.milestones'
}

function Get-GenesysFlowAggregate {
    <#
    .SYNOPSIS
        Returns Architect flow execution aggregate metrics.
    .DESCRIPTION
        Fetches flow aggregates and returns flattened records — one per
        flowId+flowType+interval combination.  Metric columns:

            flowId                  — Architect flow GUID
            flowType                — inboundcall, bot, etc.
            Interval                — Time bucket
            nFlow_count             — Conversations that entered the flow
            nFlowOutcome_count      — Exits with a defined outcome
            nFlowOutcomeFailed_count — Exits with a FAILED outcome
            nFlowMilestone_count    — Milestone events triggered

        Self-service rate = nFlowOutcome_count / nFlow_count (where outcome ≠ transfer)
        Failure rate      = nFlowOutcomeFailed_count / nFlow_count
    .EXAMPLE
        $agg = Get-GenesysFlowAggregate
        $agg | Select-Object flowId, Interval, nFlow_count, nFlowOutcomeFailed_count,
            @{ n='FailRate%'; e={ if ($_.nFlow_count) { [int]($_.nFlowOutcomeFailed_count / $_.nFlow_count * 100) } else { 0 } } } |
            Sort-Object 'FailRate%' -Descending | Format-Table
    .EXAMPLE
        # Enrich with flow names
        $flowMap = Get-GenesysFlow | Group-Object id -AsHashTable -AsString
        Get-GenesysFlowAggregate |
            Select-Object @{n='FlowName';e={$flowMap[$_.flowId].name}}, nFlow_count, nFlowOutcomeFailed_count |
            Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'analytics.query.flow.aggregates.execution.metrics' |
        ConvertFrom-AggregateResult
}

function Get-GenesysFlowObservation {
    <#
    .SYNOPSIS
        Returns real-time Architect flow observation metrics.
    .DESCRIPTION
        Returns current execution counts for flows: oFlow (contacts currently
        executing), oFlowDisconnect (contacts that disconnected inside the flow).

            flowId          — Architect flow GUID
            flowType        — Flow category
            Interval        — Observation snapshot timestamp
            oFlow           — Contacts currently executing this flow
            oFlowDisconnect — Contacts disconnected mid-flow (self-service abandons)

        Provide -FlowType and/or -FlowId to scope the query.
    .PARAMETER FlowType
        Single flow type (e.g. inboundcall, outboundcall, workflow) to filter on.
    .PARAMETER FlowId
        One or more Architect flow GUIDs to filter on.
    .PARAMETER Interval
        Optional pre-built ISO-8601 interval string (the observations endpoint accepts
        an explicit interval to constrain disconnect counts).
    .EXAMPLE
        Get-GenesysFlowObservation | Where-Object { $_.oFlowDisconnect -gt 0 } |
            Format-Table flowId, oFlow, oFlowDisconnect
    #>
    [CmdletBinding()]
    param(
        [string]   $FlowType,
        [string[]] $FlowId,
        [string]   $Interval
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        metrics = @('oFlow', 'oFlowDisconnect')
    }

    if (-not [string]::IsNullOrWhiteSpace($Interval)) {
        $body.interval = $Interval
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{
        flowType = $FlowType
        flowId   = $FlowId
    }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    Invoke-GenesysDataset -Dataset 'analytics.query.flow.observations' `
                          -DatasetParameters @{ Body = $body } |
        ConvertFrom-ObservationResult
}

#endregion

# ---------------------------------------------------------------------------
#region Agent Performance & Voice Quality
# ---------------------------------------------------------------------------

function Get-GenesysAgentPerformance {
    <#
    .SYNOPSIS
        Returns historical agent performance metrics from conversation aggregates.
    .DESCRIPTION
        Fetches the user-aggregates dataset and returns one record per
        userId+mediaType+interval with all handle-time metrics pre-calculated:

            userId                   — Agent GUID
            mediaType                — voice, chat, email, etc.
            Interval                 — Aggregate time bucket (from catalog body)
            ConversationsHandled     — nConnected count (calls answered)
            TotalHandleMs            — Total handle time (ms)
            TotalTalkMs              — Total talk time in-segment (ms)
            TotalAcwMs               — Total after-call work (ms)
            TotalAnsweredMs          — Total time from offer to answer (ms)
            AvgHandleSec             — Average handle time (seconds) — derived
            AvgTalkSec               — Average talk time (seconds)   — derived
            AvgAcwSec                — Average ACW (seconds)         — derived

        All Ms fields are in milliseconds as returned by the API.
        Avg columns are rounded integers for easy display.
    .PARAMETER MinConversations
        Only return agents who handled at least this many conversations.
    .PARAMETER UserId
        Filter to a specific agent GUID.
    .PARAMETER MediaType
        Filter by media type (voice, chat, email, etc.).
    .PARAMETER Since
        Inclusive start of the aggregation interval.
    .PARAMETER Until
        Exclusive end of the aggregation interval.
    .PARAMETER Granularity
        Time bucket granularity (e.g. PT1H, PT15M).
    .EXAMPLE
        # Who handled the most calls?
        Get-GenesysAgentPerformance |
            Sort-Object ConversationsHandled -Descending |
            Select-Object -First 20 | Format-Table userId, ConversationsHandled, AvgHandleSec
    .EXAMPLE
        # Agents with average handle time over 10 minutes — coaching candidates
        Get-GenesysAgentPerformance |
            Where-Object { $_.AvgHandleSec -gt 600 -and $_.ConversationsHandled -ge 5 } |
            Sort-Object AvgHandleSec -Descending | Format-Table
    .EXAMPLE
        # Enrich with agent names
        $agents = Get-GenesysAgent | Group-Object id -AsHashTable -AsString
        Get-GenesysAgentPerformance |
            Select-Object @{n='Name';e={$agents[$_.userId].name}},
                          ConversationsHandled, AvgHandleSec, AvgTalkSec, AvgAcwSec |
            Sort-Object ConversationsHandled -Descending | Format-Table
    #>
    [CmdletBinding()]
    param(
        [int] $MinConversations = 0,

        [string[]]           $UserId,
        [string]             $MediaType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string]             $Granularity
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        interval = New-GenesysAnalyticsInterval -Since $Since -Until $Until -DefaultLookbackHours 24
        groupBy  = @('userId')
        metrics  = @('nConnected', 'tHandle', 'tTalk', 'tAcw', 'tAnswered', 'nOffered')
    }

    if (-not [string]::IsNullOrWhiteSpace($Granularity)) {
        $body.granularity = $Granularity
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{
        userId    = $UserId
        mediaType = $MediaType
    }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    $raw = Invoke-GenesysDataset -Dataset 'analytics.query.user.aggregates.performance.metrics' `
                                 -DatasetParameters @{ Body = $body }

    $records = foreach ($r in @($raw)) {
        # Use safe property access to avoid StrictMode failures on partial records.
        $group = Get-PropertyValue $r 'group'
        $data  = Get-PropertyValue $r 'data'
        foreach ($d in @($data)) {
            if ($null -eq $d) { continue }
            $mHash = @{}
            foreach ($m in @(Get-PropertyValue $d 'metrics')) {
                if ($null -eq $m) { continue }
                $mName  = Get-PropertyValue $m 'metric'
                $mStats = Get-PropertyValue $m 'stats'
                if ($mName) { $mHash[$mName] = $mStats }
            }

            $handled  = if ($mHash['nConnected']) { [int](Get-PropertyValue $mHash['nConnected'] 'count') } else { 0 }
            $handleMs = if ($mHash['tHandle'])    { Get-PropertyValue $mHash['tHandle']   'sum' } else { $null }
            $talkMs   = if ($mHash['tTalk'])      { Get-PropertyValue $mHash['tTalk']     'sum' } else { $null }
            $acwMs    = if ($mHash['tAcw'])       { Get-PropertyValue $mHash['tAcw']      'sum' } else { $null }
            $ansMs    = if ($mHash['tAnswered'])   { Get-PropertyValue $mHash['tAnswered'] 'sum' } else { $null }

            [PSCustomObject]@{
                UserId               = if ($group) { Get-PropertyValue $group 'userId'    } else { $null }
                MediaType            = if ($group) { Get-PropertyValue $group 'mediaType' } else { $null }
                Interval             = Get-PropertyValue $d 'interval'
                ConversationsHandled = $handled
                TotalHandleMs        = $handleMs
                TotalTalkMs          = $talkMs
                TotalAcwMs           = $acwMs
                TotalAnsweredMs      = $ansMs
                AvgHandleSec         = if ($handled -and $handleMs) { [int]($handleMs / $handled / 1000) } else { $null }
                AvgTalkSec           = if ($handled -and $talkMs)   { [int]($talkMs   / $handled / 1000) } else { $null }
                AvgAcwSec            = if ($handled -and $acwMs)    { [int]($acwMs    / $handled / 1000) } else { $null }
            }
        }
    }

    if ($MinConversations -gt 0) { $records = $records | Where-Object { $_.ConversationsHandled -ge $MinConversations } }
    if ($UserId)   { $records = $records | Where-Object { $_.UserId    -eq $UserId   } }
    if ($MediaType){ $records = $records | Where-Object { $_.MediaType -eq $MediaType } }

    if ($IncludeDiagnostics) {
        # Wrap in a diagnostic envelope for consistency
        return [PSCustomObject][ordered]@{
            DatasetKey   = 'analytics.query.user.aggregates.performance.metrics'
            FunctionName = 'Get-GenesysAgentPerformance'
            Status       = if (@($records).Count -gt 0) { 'Succeeded' } else { 'Empty' }
            Records      = @($records)
            RecordCount  = @($records).Count
            RunFolder    = $null
            ManifestPath = $null
            DataFolder   = $null
            Error        = $null
        }
    }
    $records
}

function Get-GenesysUserActivity {
    <#
    .SYNOPSIS
        Returns detailed agent activity records (presence state timeline).
    .DESCRIPTION
        Pulls the user details analytics dataset which contains a full presence
        and routing-status timeline for each agent across the query interval.

        Each record represents one user's activity detail block.  The raw
        presenceDetail, routingStatusDetail, and primaryPresenceSummary arrays
        are preserved for downstream processing.

        Use this for:
          - Adherence monitoring (was agent in the right state at the right time?)
          - Absence reporting (total time in OFFLINE state)
          - Compliance audit trails
    .EXAMPLE
        $activity = Get-GenesysUserActivity
        # Total time each agent spent AVAILABLE
        $activity | ForEach-Object {
            $avail = ($_.primaryPresenceSummary | Where-Object systemPresence -eq 'AVAILABLE').durationMs
            [PSCustomObject]@{ UserId = $_.userId; AvailableMs = $avail }
        } | Sort-Object AvailableMs -Descending | Format-Table
    .EXAMPLE
        Get-GenesysUserActivity | Select-Object userId, @{n='Records';e={@($_.presenceDetail).Count}} | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'analytics.query.user.details.activity.report'
}

function Get-GenesysAgentVoiceQuality {
    <#
    .SYNOPSIS
        Extracts per-session voice quality metrics (MOS, WebRTC errors, disconnect
        codes, latency indicators) from conversation detail records.
    .DESCRIPTION
        Processes conversation detail records — either supplied via the pipeline from
        a prior Get-GenesysConversationDetail call, or fetched fresh if no input is
        provided.

        For every voice session belonging to an agent (purpose = 'agent', mediaType
        = 'voice'), the function emits a flat record:

            ConversationId    — Conversation GUID
            ConversationStart — Start timestamp (ISO-8601 string)
            AgentUserId       — Agent's Genesys user GUID
            ParticipantId     — Participant GUID within the conversation
            SessionId         — Session GUID (one per leg)
            Provider          — Transport layer: WebRTC, SIP, PSTN, Edge, etc.
            MediaType         — voice (always for this function)
            SessionMos        — mediaStatsMinConversationMos at session level
            ConversationMos   — mediaStatsMinConversationMos at conversation level
                                (minimum across all participants — use as fallback)
            MosCategory       — Derived quality band:
                                  Good  ≥ 4.0   (ITU-T P.800 acceptable)
                                  Fair  ≥ 3.6
                                  Poor  ≥ 3.1
                                  Bad   < 3.1   (unacceptable — investigate)
                                  Unknown — no MOS data in the record
            RFactor           — mediaStatsMinConversationRFactor (R-factor score)
            DisconnectType    — How the agent leg disconnected:
                                  client, server, transfer, endpoint, peer, other
            ErrorCode         — Last segment error code, if any:
                                  webrtc, ice, stun, turn, rtp, media, sip, etc.
            SegmentCount      — Number of segments in this session
            QueueId           — Queue from the first ACD segment (if present)
            QueueName         — Queue display name (if present in segment)
            DivisionId        — First division ID on the conversation

        Records with Provider = 'WebRTC' and MosCategory = 'Bad' or 'Poor' are
        the primary candidates for WebRTC quality investigation.

        Records with non-empty ErrorCode indicate a technical failure in the media
        path — STUN/TURN/ICE errors point to network/firewall issues; RTP errors
        indicate codec or bandwidth problems.
    .PARAMETER InputObject
        Conversation detail records from Get-GenesysConversationDetail (pipeline).
        When omitted the function fetches the last-24-hours dataset internally.
    .PARAMETER KeepArtifacts
        Passed through to Get-GenesysConversationDetail when fetching internally.
    .PARAMETER ArtifactPath
        Passed through to Get-GenesysConversationDetail when fetching internally.
    .EXAMPLE
        # All voice quality records for the last 24 hours
        Get-GenesysAgentVoiceQuality | Format-Table ConversationId, AgentUserId, Provider, SessionMos, MosCategory
    .EXAMPLE
        # Bad MOS — conversations needing immediate investigation
        Get-GenesysAgentVoiceQuality | Where-Object MosCategory -eq 'Bad' |
            Select-Object ConversationId, AgentUserId, SessionMos, Provider, ErrorCode, DisconnectType |
            Export-Csv .\bad-mos-$(Get-Date -f yyyyMMdd).csv -NoTypeInformation
    .EXAMPLE
        # WebRTC-specific error analysis
        Get-GenesysAgentVoiceQuality |
            Where-Object { $_.Provider -eq 'WebRTC' -and $_.ErrorCode } |
            Group-Object ErrorCode | Select-Object Name, Count | Sort-Object Count -Descending | Format-Table
    .EXAMPLE
        # MOS distribution by provider
        Get-GenesysAgentVoiceQuality |
            Group-Object Provider, MosCategory |
            Select-Object Name, Count | Sort-Object Name | Format-Table
    .EXAMPLE
        # Pipeline from an existing fetch — avoids pulling conversation details twice
        $convs = Get-GenesysConversationDetail
        $mosIssues = $convs | Get-GenesysAgentVoiceQuality | Where-Object { $_.SessionMos -lt 3.1 }
        $disconnects = $convs | Get-GenesysAgentVoiceQuality | Where-Object { $_.ErrorCode -match 'webrtc|ice|stun|turn' }
    .EXAMPLE
        # Enrich with agent names for a management report
        $agents = Get-GenesysAgent | Group-Object id -AsHashTable -AsString
        Get-GenesysAgentVoiceQuality |
            Where-Object { $_.MosCategory -in @('Poor','Bad') } |
            Select-Object @{n='AgentName';e={$agents[$_.AgentUserId].name}},
                          ConversationStart, SessionMos, MosCategory, Provider, ErrorCode |
            Sort-Object SessionMos | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object[]] $InputObject,

        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string[]] $QueueId,
        [string[]] $UserId,
        [string] $MediaType = 'voice',
        [string[]] $DivisionId,
        [switch] $KeepArtifacts,
        [string] $ArtifactPath
    )

    begin {
        $buffer = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($null -ne $InputObject) {
            foreach ($item in $InputObject) { $buffer.Add($item) }
        }
    }

    end {
        # If nothing piped in, fetch internally
        $conversations = if ($buffer.Count -gt 0) {
            $buffer.ToArray()
        }
        else {
            Assert-GenesysConnected
            $keepArtifactsForFetch = $KeepArtifacts -or (-not [string]::IsNullOrWhiteSpace($ArtifactPath))
            @(Get-GenesysConversationDetail -Since $Since -Until $Until -QueueId $QueueId -UserId $UserId -MediaType $MediaType -DivisionId $DivisionId -KeepArtifacts:$keepArtifactsForFetch -ArtifactPath $ArtifactPath)
        }

        foreach ($conv in $conversations) {
            # Use safe property access for optional fields that may be absent
            # from the API response under StrictMode -Version Latest.
            $convMos = Get-PropertyValue $conv 'mediaStatsMinConversationMos'
            $divIds  = Get-PropertyValue $conv 'divisionIds'
            $divId   = if ($divIds -and @($divIds).Count -gt 0) { @($divIds)[0] } else { $null }

            foreach ($p in @(Get-PropertyValue $conv 'participants')) {
                if ($null -eq $p) { continue }
                $purpose = Get-PropertyValue $p 'purpose'
                $userId  = Get-PropertyValue $p 'userId'
                # Only agent legs (users) on voice
                if ($purpose -ne 'agent' -and $purpose -ne 'user') { continue }
                if (-not $userId) { continue }

                foreach ($sess in @(Get-PropertyValue $p 'sessions')) {
                    if ($null -eq $sess) { continue }
                    if ((Get-PropertyValue $sess 'mediaType') -ne 'voice') { continue }

                    $segmentsRaw  = Get-PropertyValue $sess 'segments'
                    $segments     = @(if ($segmentsRaw) { $segmentsRaw } else { @() })
                    $lastSeg      = if ($segments.Count -gt 0) { $segments[-1] } else { $null }

                    # Last segment that carries an errorCode
                    $errorSeg     = $segments | Where-Object { Get-PropertyValue $_ 'errorCode' } | Select-Object -Last 1

                    # Queue from first ACD segment
                    $acdSeg       = $segments | Where-Object { Get-PropertyValue $_ 'queueId' } | Select-Object -First 1

                    $sessionMos   = Get-PropertyValue $sess 'mediaStatsMinConversationMos'
                    $effectiveMos = if ($null -ne $sessionMos) { $sessionMos }
                                   elseif ($null -ne $convMos) { $convMos    }
                                   else                        { $null       }

                    [PSCustomObject]@{
                        ConversationId    = Get-PropertyValue $conv 'conversationId'
                        ConversationStart = Get-PropertyValue $conv 'conversationStart'
                        AgentUserId       = $userId
                        ParticipantId     = Get-PropertyValue $p    'participantId'
                        SessionId         = Get-PropertyValue $sess  'sessionId'
                        Provider          = Get-PropertyValue $sess  'provider'
                        MediaType         = Get-PropertyValue $sess  'mediaType'
                        SessionMos        = $sessionMos
                        ConversationMos   = $convMos
                        MosCategory       = Get-MosCategory $effectiveMos
                        RFactor           = Get-PropertyValue $sess  'mediaStatsMinConversationRFactor'
                        DisconnectType    = if ($lastSeg)  { Get-PropertyValue $lastSeg  'disconnectType' } else { $null }
                        ErrorCode         = if ($errorSeg) { Get-PropertyValue $errorSeg 'errorCode'      } else { $null }
                        SegmentCount      = $segments.Count
                        QueueId           = if ($acdSeg)  { Get-PropertyValue $acdSeg 'queueId'   } else { $null }
                        QueueName         = if ($acdSeg)  { Get-PropertyValue $acdSeg 'queueName' } else { $null }
                        DivisionId        = $divId
                    }
                }
            }
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Edge / Telephony Telemetry  (Roadmap ideas 1–5)
# ---------------------------------------------------------------------------

function Get-GenesysEdge {
    <#
    .SYNOPSIS
        Returns all Edge appliances with registration and connectivity status.
    .DESCRIPTION
        Fetches the Edge list from the telephony providers API.  Each record
        contains the edge GUID, name, edge group, software version, online
        state, and whether the edge is currently in a managed state.

        Use for:
          - Edge health dashboards (are all edges online / registered?)
          - Pre-flight checks before routing changes
          - Inventory snapshots for large multi-site deployments

        Key fields returned:
            id             — Edge GUID
            name           — Display name
            state          — ACTIVE | INACTIVE | DELETED
            onlineStatus   — ONLINE | OFFLINE
            edgeGroup      — Associated edge group name/id
            softwareVersion — Installed Edge software version
            managed        — Whether centrally managed
    .EXAMPLE
        # Show all offline edges
        Get-GenesysEdge | Where-Object { $_.onlineStatus -ne 'ONLINE' } | Format-Table name, onlineStatus, state
    .EXAMPLE
        # Count edges per edge group
        Get-GenesysEdge | Group-Object { $_.edgeGroup.name } | Select-Object Name, Count | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'telephony.get.edges')
}

function Get-GenesysTrunk {
    <#
    .SYNOPSIS
        Returns all SIP trunks across the organisation.
    .DESCRIPTION
        Lists every trunk defined under the Edge telephony provider.  Useful for
        monitoring SIP trunk health, capacity, and connectivity across all sites.

        Key fields returned:
            id             — Trunk GUID
            name           — Display name
            trunkType      — EXTERNAL | PHONE | EDGE
            state          — ACTIVE | INACTIVE
            edge           — Edge the trunk belongs to
            trunkBase      — Trunk base configuration reference
    .EXAMPLE
        # Show only active external trunks
        Get-GenesysTrunk | Where-Object { $_.trunkType -eq 'EXTERNAL' -and $_.state -eq 'ACTIVE' } | Format-Table name, edge
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'telephony.get.trunks')
}

function Get-GenesysTrunkMetrics {
    <#
    .SYNOPSIS
        Returns aggregate SIP trunk utilisation and capacity metrics.
    .DESCRIPTION
        Calls the trunk metrics summary endpoint which provides organisation-wide
        counts of:
            - Total available channels
            - Channels currently in use (active calls)
            - Calls in setup/alerting state
            - Number of trunks in error state

        Use alongside Get-GenesysTrunk for a trunk health and capacity dashboard.
    .EXAMPLE
        $m = Get-GenesysTrunkMetrics
        $m | Format-List
    .EXAMPLE
        # Alert on near-capacity
        $m = Get-GenesysTrunkMetrics
        foreach ($t in $m) {
            if ($t.logicalInterfaceId -and $t.callsIn + $t.callsOut -gt 80) {
                Write-Warning "Trunk $($t.name) nearing capacity"
            }
        }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'telephony.get.trunk.metrics.summary')
}

function Get-GenesysStation {
    <#
    .SYNOPSIS
        Returns all station (phone/softphone) registrations and statuses.
    .DESCRIPTION
        Fetches the organisation's station inventory.  Stations represent physical
        phones, WebRTC softphones, and Genesys Cloud WebRTC media helper devices.

        Key fields returned:
            id             — Station GUID
            name           — Display name
            type           — inin_webrtc_softphone | inin_remote | ...
            status         — AVAILABLE | ON_CALL | RINGING | OFF_HOOK
            userId         — Associated user GUID (if assigned)
            lineAppearance — Assigned line number
    .EXAMPLE
        # How many stations are available vs on a call?
        Get-GenesysStation | Group-Object status | Select-Object Name, Count | Format-Table
    .EXAMPLE
        # Find all unassigned stations
        Get-GenesysStation | Where-Object { -not $_.userId } | Format-Table id, name, type
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'stations.get.stations')
}

function Get-GenesysEdgeHealthSnapshot {
    <#
    .SYNOPSIS
        Returns a combined edge + trunk health summary suitable for a dashboard widget.
    .DESCRIPTION
        Aggregates edge online status and trunk state into a single summary object
        for at-a-glance visibility into telephony infrastructure health.

        Returns:
            Timestamp         — Snapshot time
            EdgesTotal        — Total Edge appliances
            EdgesOnline       — Edges reporting ONLINE
            EdgesOffline      — Edges reporting OFFLINE
            TrunksTotal       — Total SIP trunks
            TrunksActive      — Active/registered trunks
            TrunksInactive    — Trunks not in ACTIVE state
            OfflineEdgeNames  — List of offline edge names (for alerting)
    .EXAMPLE
        Get-GenesysEdgeHealthSnapshot | Format-List
    .EXAMPLE
        # Alert if any edge is offline
        $snap = Get-GenesysEdgeHealthSnapshot
        if ($snap.EdgesOffline -gt 0) {
            Write-Warning "ALERT: $($snap.EdgesOffline) edges offline: $($snap.OfflineEdgeNames -join ', ')"
        }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected

    $edges  = @(Get-GenesysEdge)
    $trunks = @(Get-GenesysTrunk)

    $offlineEdges = @($edges | Where-Object { $_.onlineStatus -ne 'ONLINE' })

    [PSCustomObject]@{
        Timestamp        = Get-Date -Format 'o'
        EdgesTotal       = $edges.Count
        EdgesOnline      = @($edges | Where-Object { $_.onlineStatus -eq 'ONLINE'  }).Count
        EdgesOffline     = $offlineEdges.Count
        TrunksTotal      = $trunks.Count
        TrunksActive     = @($trunks | Where-Object { $_.state -eq 'ACTIVE'        }).Count
        TrunksInactive   = @($trunks | Where-Object { $_.state -ne 'ACTIVE'        }).Count
        OfflineEdgeNames = $offlineEdges | ForEach-Object { $_.name }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Queue KPIs — Abandon Rate, SLA, Transfer, Wrapup  (Roadmap ideas 6–10)
# ---------------------------------------------------------------------------

function Get-GenesysQueueAbandonRate {
    <#
    .SYNOPSIS
        Returns per-queue abandon rate metrics for a given interval.
    .DESCRIPTION
        Queries conversation aggregates and derives abandon rate (%) for each
        queue+mediaType+interval combination.  The AbandonRate field is:

            AbandonRate = nAbandoned / nOffered * 100

        All raw counts are also included for custom calculations:

            QueueId        — Queue GUID
            MediaType      — voice, chat, email, etc.
            Interval       — Aggregate time bucket
            nOffered       — Contacts offered (entered queue)
            nAbandoned     — Contacts who abandoned before answer
            nConnected     — Contacts connected to an agent
            AbandonRate    — Abandon percentage (0–100, rounded to 1 dp)
            AvgAbandonSec  — Average time in queue before abandon (seconds)
    .EXAMPLE
        # Current-day abandon rate per queue
        Get-GenesysQueueAbandonRate | Sort-Object AbandonRate -Descending |
            Select-Object QueueId, MediaType, nOffered, nAbandoned, AbandonRate |
            Format-Table
    .EXAMPLE
        # Alert on queues with abandon rate > 10%
        Get-GenesysQueueAbandonRate |
            Where-Object { $_.AbandonRate -gt 10 } |
            ForEach-Object { Write-Warning "Queue $($_.QueueId) abandon rate: $($_.AbandonRate)%" }
    #>
    [CmdletBinding()]
    param(
        [string[]]           $QueueId,
        [string]             $MediaType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        interval = New-GenesysAnalyticsInterval -Since $Since -Until $Until -DefaultLookbackHours 24
        groupBy  = @('queueId')
        metrics  = @('nOffered', 'nAbandoned', 'nConnected', 'tAbandoned')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{
        queueId   = $QueueId
        mediaType = $MediaType
    }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    $raw = @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.abandon.metrics' `
                                   -DatasetParameters @{ Body = $body } |
             ConvertFrom-AggregateResult)

    foreach ($r in $raw) {
        $offered   = if ($r.nOffered_count)    { $r.nOffered_count    } else { 0 }
        $abandoned = if ($r.nAbandoned_count)  { $r.nAbandoned_count  } else { 0 }
        $connected = if ($r.nConnected_count)  { $r.nConnected_count  } else { 0 }
        $tAbandon  = if ($r.tAbandoned_sum)    { $r.tAbandoned_sum    } else { $null }

        $rate = if ($offered -gt 0) { [math]::Round($abandoned / $offered * 100, 1) } else { 0.0 }
        $avgAbandonSec = if ($abandoned -gt 0 -and $null -ne $tAbandon) {
            [math]::Round($tAbandon / $abandoned / 1000, 1)
        } else { $null }

        [PSCustomObject]@{
            QueueId       = $r.queueId
            MediaType     = $r.mediaType
            Interval      = $r.Interval
            nOffered      = $offered
            nAbandoned    = $abandoned
            nConnected    = $connected
            AbandonRate   = $rate
            AvgAbandonSec = $avgAbandonSec
        }
    }
}

function Get-GenesysQueueServiceLevel {
    <#
    .SYNOPSIS
        Returns queue service level (SLA) metrics — percentage answered within threshold.
    .DESCRIPTION
        Fetches conversation aggregates with answer-speed metrics and computes the
        percentage of contacts answered within 20, 30, and 60 seconds.

            QueueId            — Queue GUID
            MediaType          — voice, chat, email, etc.
            Interval           — Aggregate time bucket
            nOffered           — Contacts offered
            nAnsweredIn20      — Answered in ≤ 20 s
            nAnsweredIn30      — Answered in ≤ 30 s
            nAnsweredIn60      — Answered in ≤ 60 s
            ServiceLevel20Pct  — % answered in 20 s
            ServiceLevel30Pct  — % answered in 30 s (common SLA threshold)
            ServiceLevel60Pct  — % answered in 60 s
    .EXAMPLE
        Get-GenesysQueueServiceLevel |
            Select-Object QueueId, nOffered, ServiceLevel20Pct, ServiceLevel30Pct |
            Sort-Object ServiceLevel30Pct | Format-Table
    .EXAMPLE
        # Flag queues missing 80% SLA target at 30 s
        Get-GenesysQueueServiceLevel |
            Where-Object { $_.ServiceLevel30Pct -lt 80 -and $_.nOffered -gt 0 } |
            Format-Table QueueId, nOffered, ServiceLevel30Pct
    #>
    [CmdletBinding()]
    param(
        [string[]]           $QueueId,
        [string]             $MediaType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        interval = New-GenesysAnalyticsInterval -Since $Since -Until $Until -DefaultLookbackHours 24
        groupBy  = @('queueId')
        metrics  = @('nOffered', 'nAnsweredIn20', 'nAnsweredIn30', 'nAnsweredIn60')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{
        queueId   = $QueueId
        mediaType = $MediaType
    }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    $raw = @(Invoke-GenesysDataset -Dataset 'analytics.query.queue.aggregates.service.level' `
                                   -DatasetParameters @{ Body = $body } |
             ConvertFrom-AggregateResult)

    foreach ($r in $raw) {
        $offered = if ($r.nOffered_count) { $r.nOffered_count } else { 0 }

        $in20 = if ($r.nAnsweredIn20_count) { $r.nAnsweredIn20_count } else { 0 }
        $in30 = if ($r.nAnsweredIn30_count) { $r.nAnsweredIn30_count } else { 0 }
        $in60 = if ($r.nAnsweredIn60_count) { $r.nAnsweredIn60_count } else { 0 }

        $sl20 = if ($offered -gt 0) { [math]::Round($in20 / $offered * 100, 1) } else { $null }
        $sl30 = if ($offered -gt 0) { [math]::Round($in30 / $offered * 100, 1) } else { $null }
        $sl60 = if ($offered -gt 0) { [math]::Round($in60 / $offered * 100, 1) } else { $null }

        [PSCustomObject]@{
            QueueId           = $r.queueId
            MediaType         = $r.mediaType
            Interval          = $r.Interval
            nOffered          = $offered
            nAnsweredIn20     = $in20
            nAnsweredIn30     = $in30
            nAnsweredIn60     = $in60
            ServiceLevel20Pct = $sl20
            ServiceLevel30Pct = $sl30
            ServiceLevel60Pct = $sl60
        }
    }
}

function Get-GenesysTransferAnalysis {
    <#
    .SYNOPSIS
        Returns transfer rate metrics (blind, consult) per queue.
    .DESCRIPTION
        Fetches conversation aggregates with transfer counts and derives the
        transfer rate as a percentage of connected conversations.

            QueueId               — Queue GUID
            MediaType             — voice, chat, email, etc.
            Interval              — Aggregate time bucket
            nConnected            — Conversations connected to agent
            nTransferred          — Total transfers initiated
            nBlindTransferred     — Blind (cold) transfers
            nConsultTransferred   — Consult (warm) transfers
            TransferRate          — nTransferred / nConnected * 100
    .EXAMPLE
        Get-GenesysTransferAnalysis | Sort-Object TransferRate -Descending | Format-Table
    .EXAMPLE
        # Identify queues with high blind transfer rate (potential training need)
        Get-GenesysTransferAnalysis |
            Where-Object { $_.nConnected -gt 0 -and $_.nBlindTransferred / $_.nConnected -gt 0.15 } |
            Format-Table QueueId, nConnected, nBlindTransferred, TransferRate
    #>
    [CmdletBinding()]
    param(
        [string[]]           $QueueId,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        interval = New-GenesysAnalyticsInterval -Since $Since -Until $Until -DefaultLookbackHours 24
        groupBy  = @('queueId')
        metrics  = @('nConnected', 'nTransferred', 'nBlindTransferred', 'nConsultTransferred')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{ queueId = $QueueId }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    $raw = @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.transfer.metrics' `
                                   -DatasetParameters @{ Body = $body } |
             ConvertFrom-AggregateResult)

    foreach ($r in $raw) {
        $connected  = if ($r.nConnected_count)          { $r.nConnected_count          } else { 0 }
        $xfer       = if ($r.nTransferred_count)        { $r.nTransferred_count        } else { 0 }
        $blind      = if ($r.nBlindTransferred_count)   { $r.nBlindTransferred_count   } else { 0 }
        $consult    = if ($r.nConsultTransferred_count) { $r.nConsultTransferred_count } else { 0 }

        $rate = if ($connected -gt 0) { [math]::Round($xfer / $connected * 100, 1) } else { 0.0 }

        [PSCustomObject]@{
            QueueId             = $r.queueId
            MediaType           = $r.mediaType
            Interval            = $r.Interval
            nConnected          = $connected
            nTransferred        = $xfer
            nBlindTransferred   = $blind
            nConsultTransferred = $consult
            TransferRate        = $rate
        }
    }
}

function Get-GenesysWrapupDistribution {
    <#
    .SYNOPSIS
        Returns wrapup code usage distribution per queue.
    .DESCRIPTION
        Queries conversation aggregates grouped by queue and wrapup code.  Useful
        for understanding outcome patterns, training needs, and process compliance.

            QueueId            — Queue GUID
            WrapUpCode         — Wrapup code GUID or name from groupBy dimension
            Interval           — Aggregate time bucket (daily by default)
            nConnected_count   — Conversations with this wrapup code
            tHandle_sum        — Total handle time for this wrapup group (ms)
    .EXAMPLE
        $dist = Get-GenesysWrapupDistribution
        $dist | Group-Object WrapUpCode | Sort-Object { ($_.Group | Measure-Object nConnected_count -Sum).Sum } -Descending |
            Select-Object -First 10 Name, Count | Format-Table
    .EXAMPLE
        # Export for a weekly report
        Get-GenesysWrapupDistribution | Export-Csv .\wrapup-$(Get-Date -f yyyyMMdd).csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [string[]]           $QueueId,
        [string[]]           $WrapupCodeId,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        interval = New-GenesysAnalyticsInterval -Since $Since -Until $Until -DefaultLookbackHours 24
        groupBy  = @('queueId', 'wrapUpCode')
        metrics  = @('nConnected', 'tHandle')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{
        queueId    = $QueueId
        wrapUpCode = $WrapupCodeId
    }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.wrapup.distribution' `
                            -DatasetParameters @{ Body = $body } |
      ConvertFrom-AggregateResult)
}

function Get-GenesysDigitalChannelVolume {
    <#
    .SYNOPSIS
        Returns conversation volume trends broken down by media type (channel).
    .DESCRIPTION
        Queries conversation aggregates grouped by mediaType and queueId.  Returns
        hourly or daily volume per channel — voice, chat, email, messaging, callback.

            QueueId            — Queue GUID
            MediaType          — voice | chat | email | message | callback
            Interval           — Time bucket
            nOffered_count     — Contacts offered
            nConnected_count   — Contacts connected to agent
            nAbandoned_count   — Contacts abandoned
            tHandle_sum        — Total handle time (ms)
    .EXAMPLE
        # Compare voice vs digital volume over the last week
        Get-GenesysDigitalChannelVolume |
            Group-Object MediaType |
            Select-Object Name, @{n='TotalOffered';e={($_.Group|Measure-Object nOffered_count -Sum).Sum}} |
            Sort-Object TotalOffered -Descending | Format-Table
    #>
    [CmdletBinding()]
    param(
        [string]             $MediaType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        interval = New-GenesysAnalyticsInterval -Since $Since -Until $Until -DefaultLookbackHours 24
        groupBy  = @('mediaType', 'queueId')
        metrics  = @('nOffered', 'nConnected', 'nAbandoned', 'tHandle')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{ mediaType = $MediaType }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.digital.channels' `
                            -DatasetParameters @{ Body = $body } |
      ConvertFrom-AggregateResult)
}

function Export-GenesysMonthlyChannelVolume {
    <#
    .SYNOPSIS
        Exports monthly conversation volume by media type and originating direction.
    .DESCRIPTION
        Uses the conversations aggregates endpoint with monthly granularity and
        groups results by mediaType and originatingDirection.  The CSV includes
        offered, connected, outbound, and abandoned counts plus a normalized
        Volume field suitable for monthly inbound/outbound channel reporting.

        For inbound rows, Volume prefers nOffered_count.  For outbound rows,
        Volume prefers nOutbound_count and falls back to nOffered_count or
        nConnected_count when Genesys does not return nOutbound for that media.
    .PARAMETER Since
        Inclusive start of the reporting interval.
    .PARAMETER Until
        Exclusive end of the reporting interval.
    .PARAMETER OutputPath
        CSV path to write.  Parent folders are created when missing.
    .PARAMETER MediaType
        Optional media type filter, for example voice or message.
    .PARAMETER OriginatingDirection
        Optional originating direction filter, for example inbound or outbound.
    .PARAMETER QueueId
        Optional queue GUID filter.
    .PARAMETER PassThru
        Emit the exported row objects in addition to writing the CSV.
    .EXAMPLE
        Export-GenesysMonthlyChannelVolume -Since '2026-01-01' -Until '2026-05-01' `
            -OutputPath '.\exports\monthly-channel-volume.csv' -MediaType voice,message
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [Nullable[datetime]] $Since,

        [Parameter(Mandatory)]
        [Nullable[datetime]] $Until,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [string[]] $MediaType,

        [ValidateSet('inbound', 'outbound')]
        [string[]] $OriginatingDirection,

        [string[]] $QueueId,

        [switch] $PassThru
    )

    Assert-GenesysConnected

    $sinceDate = [datetime]$Since
    $untilDate = [datetime]$Until

    if ($sinceDate -ge $untilDate) {
        throw 'Until must be later than Since.'
    }

    $body = [ordered]@{
        interval    = "$($sinceDate.ToUniversalTime().ToString('o'))/$($untilDate.ToUniversalTime().ToString('o'))"
        granularity = 'P1M'
        groupBy     = @('mediaType', 'originatingDirection')
        metrics     = @('nOffered', 'nConnected', 'nOutbound', 'nAbandoned')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{
        mediaType            = $MediaType
        originatingDirection = $OriginatingDirection
        queueId              = $QueueId
    }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    $aggregateRows = @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.queue.performance' `
                                             -DatasetParameters @{ Body = $body } |
                       ConvertFrom-AggregateResult)

    $rows = @($aggregateRows | ForEach-Object {
        $interval = [string](Get-PropertyValue $_ 'Interval' '')
        $intervalStart = ''
        $month = ''
        if (-not [string]::IsNullOrWhiteSpace($interval)) {
            $intervalStart = @($interval -split '/', 2)[0]
            try {
                $month = ([datetime]::Parse(
                    $intervalStart,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AssumeUniversal
                )).ToUniversalTime().ToString('yyyy-MM')
            } catch {
                $month = if ($intervalStart.Length -ge 7) { $intervalStart.Substring(0, 7) } else { $intervalStart }
            }
        }

        $media = [string](Get-PropertyValue $_ 'mediaType' '')
        $direction = [string](Get-PropertyValue $_ 'originatingDirection' '')
        $offered = [long](Get-PropertyValue $_ 'nOffered_count' 0)
        $connected = [long](Get-PropertyValue $_ 'nConnected_count' 0)
        $outbound = [long](Get-PropertyValue $_ 'nOutbound_count' 0)
        $abandoned = [long](Get-PropertyValue $_ 'nAbandoned_count' 0)
        $volume = if ($direction -eq 'outbound' -and $outbound -gt 0) {
            $outbound
        } elseif ($offered -gt 0) {
            $offered
        } else {
            $connected
        }

        [PSCustomObject]@{
            Month                = $month
            IntervalStartUtc     = $intervalStart
            Interval             = $interval
            MediaType            = $media
            OriginatingDirection = $direction
            Volume               = $volume
            Offered              = $offered
            Connected            = $connected
            Outbound             = $outbound
            Abandoned            = $abandoned
        }
    })

    $resolvedPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        [System.IO.Path]::GetFullPath($OutputPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputPath))
    }

    if ($PSCmdlet.ShouldProcess($resolvedPath, 'Export monthly Genesys channel volume CSV')) {
        $parent = Split-Path -Parent $resolvedPath
        if ($parent -and -not (Test-Path $parent)) {
            $null = New-Item -ItemType Directory -Path $parent -Force
        }

        Export-GenesysOpsRowsCsv -Rows $rows -Path $resolvedPath
    }

    if ($PassThru) {
        return $rows
    }

    [PSCustomObject]@{
        OutputPath  = $resolvedPath
        RecordCount = $rows.Count
        Since       = $sinceDate.ToUniversalTime()
        Until       = $untilDate.ToUniversalTime()
        DatasetKey  = 'analytics.query.conversation.aggregates.queue.performance'
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Quality & CSAT  (Roadmap ideas 11–13)
# ---------------------------------------------------------------------------

function Get-GenesysEvaluation {
    <#
    .SYNOPSIS
        Returns quality evaluations for agent interactions.
    .DESCRIPTION
        Queries the quality evaluations endpoint.  Each record represents one
        completed evaluation form scored against a specific conversation.

        Key fields returned:
            id                — Evaluation GUID
            conversation      — Associated conversation reference
            evaluator         — Evaluator user reference
            agent             — Evaluated agent reference
            evaluationForm    — Form name/id used
            totalScore        — Numeric total score
            totalCriticalScore — Score on critical questions
            status            — FINISHED | INPROGRESS | CALIBRATION_IN_PROGRESS
            releaseDate       — When the evaluation was released to the agent
    .EXAMPLE
        # Average score by evaluator
        $evals = Get-GenesysEvaluation
        $evals | Group-Object { $_.evaluator.name } |
            Select-Object Name, @{n='AvgScore';e={($_.Group|Measure-Object totalScore -Average).Average}} |
            Sort-Object AvgScore | Format-Table
    .EXAMPLE
        # Flag evaluations with critical score below 70
        Get-GenesysEvaluation | Where-Object { $_.totalCriticalScore -lt 70 } |
            Select-Object id, conversation, agent, totalScore, totalCriticalScore | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'quality.get.evaluations.query')
}

function Get-GenesysSurvey {
    <#
    .SYNOPSIS
        Returns post-call customer survey results (CSAT / NPS).
    .DESCRIPTION
        Fetches completed customer surveys.  Each record contains the survey
        response, linked conversation, agent, queue, and individual question
        scores — ready for CSAT/NPS trending dashboards.

        Key fields returned:
            id                — Survey GUID
            conversation      — Linked conversation reference
            agent             — Agent associated with the survey
            queue             — Queue where the conversation took place
            surveyForm        — Survey form reference
            status            — PENDING | SENT | IN_PROGRESS | FINISHED | PENDING_NO_INVITATION
            completedDate     — When the customer completed the survey
            npsScore          — Net Promoter Score (if configured)
    .EXAMPLE
        # Average NPS by queue
        Get-GenesysSurvey | Where-Object { $_.npsScore -ne $null } |
            Group-Object { $_.queue.name } |
            Select-Object Name, @{n='AvgNPS';e={($_.Group|Measure-Object npsScore -Average).Average}} |
            Sort-Object AvgNPS | Format-Table
    .EXAMPLE
        # Response rate — completed vs total sent
        $surveys = Get-GenesysSurvey
        $total     = $surveys.Count
        $completed = @($surveys | Where-Object { $_.status -eq 'FINISHED' }).Count
        "Response rate: $([math]::Round($completed/$total*100,1))%"
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'quality.get.surveys')
}

function Get-GenesysSentimentTrend {
    <#
    .SYNOPSIS
        Returns speech-analytics sentiment data for recent conversations.
    .DESCRIPTION
        Derives per-conversation sentiment scores from conversation detail records.
        Each record contains the aggregate sentiment score across all participants.

        Each record contains:
            ConversationId    — Conversation GUID
            ConversationStart — Start timestamp
            OverallScore      — Average sentiment score (-1.0 to +1.0)
            ParticipantCount  — Participants with sentiment data

        Requires speech and text analytics to be enabled and transcription
        configured on the queue(s) of interest.
    .EXAMPLE
        $sentiments = Get-GenesysSentimentTrend
        $sentiments | Measure-Object OverallScore -Average | Select-Object Average
    .EXAMPLE
        # Show most negative conversations first
        Get-GenesysSentimentTrend | Sort-Object OverallScore | Select-Object -First 10 | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string[]] $QueueId,
        [string[]] $UserId,
        [string] $MediaType,
        [string[]] $DivisionId
    )

    Assert-GenesysConnected

    $conversations = @(Get-GenesysConversationDetail -Since $Since -Until $Until -QueueId $QueueId -UserId $UserId -MediaType $MediaType -DivisionId $DivisionId)

    foreach ($conv in $conversations) {
        # Collect sentiment scores across all participants using safe property access.
        $participants = Get-PropertyValue $conv 'participants'
        $scores = foreach ($p in @($participants)) {
            if ($null -eq $p) { continue }
            foreach ($sess in @(Get-PropertyValue $p 'sessions')) {
                if ($null -eq $sess) { continue }
                $score = Get-PropertyValue $sess 'sentimentScore'
                if ($null -ne $score) { $score }
            }
        }
        $avgScore = if ($scores -and @($scores).Count -gt 0) {
            [math]::Round((@($scores) | Measure-Object -Average).Average, 3)
        } else { $null }

        [PSCustomObject]@{
            ConversationId    = Get-PropertyValue $conv 'conversationId'
            ConversationStart = Get-PropertyValue $conv 'conversationStart'
            OverallScore      = $avgScore
            ParticipantCount  = @($participants).Count
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Alerting  (Roadmap ideas 14–15)
# ---------------------------------------------------------------------------

function Get-GenesysAlertingRule {
    <#
    .SYNOPSIS
        Returns all configured alerting rules (threshold definitions).
    .DESCRIPTION
        Lists every alerting rule in the organisation.  Rules define the KPI,
        threshold, and notification targets for automated platform alerts.

        Key fields returned:
            id             — Rule GUID
            name           — Display name
            alertTypes     — Metrics monitored (e.g. WAITING_CALLS, ABANDON_RATE)
            enabled        — Whether the rule is active
            inAlarm        — Whether the rule is currently in alarm state
            conditions     — Threshold conditions list
    .EXAMPLE
        # Show only enabled rules currently in alarm
        Get-GenesysAlertingRule | Where-Object { $_.enabled -and $_.inAlarm } | Format-Table name, alertTypes
    .EXAMPLE
        # List all disabled rules (potential oversight)
        Get-GenesysAlertingRule | Where-Object { -not $_.enabled } | Select-Object name, id | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'alerting.get.rules')
}

function Get-GenesysAlert {
    <#
    .SYNOPSIS
        Returns all currently firing platform alerts.
    .DESCRIPTION
        Fetches active alerts from the alerting engine.  Each record represents
        a threshold breach still in an active/un-cleared state.

        Key fields returned:
            id              — Alert GUID
            name            — Alert name
            alertTypes      — Metric category
            startDate       — When the alert first triggered
            endDate         — When the alert cleared (null if still active)
            unread          — Whether the alert has been acknowledged
            ruleId          — Associated alerting rule GUID
    .EXAMPLE
        # Show all unacknowledged active alerts
        Get-GenesysAlert | Where-Object { $_.unread -and -not $_.endDate } |
            Sort-Object startDate | Format-Table name, alertTypes, startDate
    .EXAMPLE
        # Count active alerts by type
        Get-GenesysAlert | Group-Object alertTypes | Select-Object Name, Count | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'alerting.get.alerts')
}

#endregion

# ---------------------------------------------------------------------------
#region Agent Insights  (Roadmap ideas 16–18)
# ---------------------------------------------------------------------------

function Get-GenesysAgentLoginActivity {
    <#
    .SYNOPSIS
        Returns per-agent login and queue-time activity metrics.
    .DESCRIPTION
        Queries user aggregate analytics for on-queue, off-queue, idle, and
        not-responding time.  Useful for staffing adherence analysis, scheduling
        validation, and identifying agents who are frequently off-queue.

            UserId                 — Agent user GUID
            Interval               — Aggregate time bucket
            tOnQueueTime_sum       — Total on-queue time (ms)
            tOffQueueTime_sum      — Total off-queue time (ms)
            tIdleTime_sum          — Total idle time on-queue (ms)
            tNotRespondingTime_sum — Time in not-responding state (ms)
            nConnected_count       — Conversations handled

        Derive utilisation: tOnQueueTime_sum / (tOnQueueTime_sum + tOffQueueTime_sum)
    .EXAMPLE
        $activity = Get-GenesysAgentLoginActivity
        $activity | Select-Object UserId, Interval,
            @{n='OnQueueMin'; e={ [int]($_.tOnQueueTime_sum / 60000) }},
            @{n='IdleMin';    e={ [int]($_.tIdleTime_sum    / 60000) }} |
            Format-Table
    .EXAMPLE
        # Find agents with more than 50% idle time
        Get-GenesysAgentLoginActivity |
            Where-Object {
                $_.tOnQueueTime_sum -gt 0 -and
                $_.tIdleTime_sum / $_.tOnQueueTime_sum -gt 0.5
            } | Format-Table UserId, Interval
    #>
    [CmdletBinding()]
    param(
        [string[]]           $UserId,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected

    $body = [ordered]@{
        interval = New-GenesysAnalyticsInterval -Since $Since -Until $Until -DefaultLookbackHours 24
        groupBy  = @('userId')
        metrics  = @('tOnQueueTime', 'tOffQueueTime', 'tIdleTime', 'tNotRespondingTime', 'nConnected')
    }

    $filter = New-GenesysAnalyticsFilter -DimensionValues @{ userId = $UserId }
    if ($null -ne $filter) {
        $body.filter = $filter
    }

    @(Invoke-GenesysDataset -Dataset 'analytics.query.user.aggregates.login.activity' `
                            -DatasetParameters @{ Body = $body } |
      ConvertFrom-AggregateResult)
}

function Get-GenesysLongHandleConversation {
    <#
    .SYNOPSIS
        Returns conversations whose total handle time exceeds a threshold.
    .DESCRIPTION
        Scans the 24-hour conversation detail dataset and flags any conversation
        where the agent leg handle duration exceeds -ThresholdSeconds.

        Useful for:
          - Identifying calls that may need supervisor review
          - Detecting stuck/frozen agent states
          - Feeding handle-time anomaly dashboards

        Each record includes:
            ConversationId    — Conversation GUID
            ConversationStart — Start timestamp
            AgentUserId       — Agent's user GUID
            HandleSec         — Actual handle time in seconds
            QueueId           — Queue from the first ACD segment
            MediaType         — Media type of the session
    .PARAMETER ThresholdSeconds
        Minimum handle time (in seconds) to include in results.  Default: 600 (10 min).
    .PARAMETER InputObject
        Conversation detail records from Get-GenesysConversationDetail (pipeline).
    .EXAMPLE
        # Conversations over 15 minutes
        Get-GenesysLongHandleConversation -ThresholdSeconds 900 | Format-Table ConversationId, AgentUserId, HandleSec
    .EXAMPLE
        # Use existing data to avoid a second fetch
        $convs = Get-GenesysConversationDetail
        $convs | Get-GenesysLongHandleConversation -ThresholdSeconds 600 | Format-Table
    #>
    [CmdletBinding()]
    param(
        [int] $ThresholdSeconds = 600,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string[]] $QueueId,
        [string[]] $UserId,
        [string] $MediaType,
        [string[]] $DivisionId,

        [Parameter(ValueFromPipeline)]
        [object[]] $InputObject
    )

    begin {
        $buffer = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $InputObject) {
            foreach ($item in $InputObject) { $buffer.Add($item) }
        }
    }
    end {
        $conversations = if ($buffer.Count -gt 0) {
            $buffer.ToArray()
        } else {
            Assert-GenesysConnected
            @(Get-GenesysConversationDetail -Since $Since -Until $Until -QueueId $QueueId -UserId $UserId -MediaType $MediaType -DivisionId $DivisionId)
        }

        foreach ($conv in $conversations) {
            foreach ($p in @(Get-PropertyValue $conv 'participants')) {
                if ($null -eq $p) { continue }
                $purpose = Get-PropertyValue $p 'purpose'
                $userId  = Get-PropertyValue $p 'userId'
                if ($purpose -ne 'agent' -and $purpose -ne 'user') { continue }
                if (-not $userId) { continue }

                foreach ($sess in @(Get-PropertyValue $p 'sessions')) {
                    if ($null -eq $sess) { continue }
                    $segsRaw = Get-PropertyValue $sess 'segments'
                    $segs    = @(if ($segsRaw) { $segsRaw } else { @() })
                    $acdSeg  = $segs | Where-Object { Get-PropertyValue $_ 'queueId' } | Select-Object -First 1

                    # Sum segment durations for this session
                    $handleMs = 0
                    foreach ($seg in $segs) {
                        $segStart = Get-PropertyValue $seg 'segmentStart'
                        $segEnd   = Get-PropertyValue $seg 'segmentEnd'
                        if ($segStart -and $segEnd) {
                            try {
                                $start = [datetime]::Parse($segStart, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                                $end   = [datetime]::Parse($segEnd,   $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                                $handleMs += ($end - $start).TotalMilliseconds
                            } catch { }
                        }
                    }

                    $handleSec = [math]::Round($handleMs / 1000, 1)
                    if ($handleSec -ge $ThresholdSeconds) {
                        [PSCustomObject]@{
                            ConversationId    = Get-PropertyValue $conv 'conversationId'
                            ConversationStart = Get-PropertyValue $conv 'conversationStart'
                            AgentUserId       = $userId
                            HandleSec         = $handleSec
                            QueueId           = if ($acdSeg) { Get-PropertyValue $acdSeg 'queueId' } else { $null }
                            MediaType         = Get-PropertyValue $sess 'mediaType'
                        }
                    }
                }
            }
        }
    }
}

function Get-GenesysRepeatCaller {
    <#
    .SYNOPSIS
        Detects customers who contacted the centre more than once within a window.
    .DESCRIPTION
        Groups the 24-hour conversation details dataset by the customer's ANI
        (caller ID / DNIS) and returns any caller that appears more than once —
        a proxy for First Contact Resolution (FCR) failures.

        Each record contains:
            CallerAni         — Customer phone number / ANI
            CallCount         — Number of contacts in the window
            ConversationIds   — List of conversation GUIDs for the caller
            FirstContact      — Timestamp of the first contact
            LastContact       — Timestamp of the most recent contact

        This is a statistical proxy only — the same ANI may represent a different
        person on a shared line.  Use in conjunction with conversationId details
        for deeper investigation.
    .PARAMETER MinCallCount
        Minimum number of contacts before a caller is included.  Default: 2.
    .PARAMETER InputObject
        Conversation detail records from Get-GenesysConversationDetail (pipeline).
    .EXAMPLE
        # Find all repeat callers in the last 24 hours
        Get-GenesysRepeatCaller | Sort-Object CallCount -Descending | Format-Table CallerAni, CallCount
    .EXAMPLE
        # Top 10 most frequent callers
        Get-GenesysRepeatCaller | Sort-Object CallCount -Descending | Select-Object -First 10 | Format-Table
    #>
    [CmdletBinding()]
    param(
        [int] $MinCallCount = 2,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string[]] $QueueId,
        [string[]] $UserId,
        [string] $MediaType,
        [string[]] $DivisionId,

        [Parameter(ValueFromPipeline)]
        [object[]] $InputObject
    )

    begin {
        $buffer = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $InputObject) {
            foreach ($item in $InputObject) { $buffer.Add($item) }
        }
    }
    end {
        $conversations = if ($buffer.Count -gt 0) {
            $buffer.ToArray()
        } else {
            Assert-GenesysConnected
            @(Get-GenesysConversationDetail -Since $Since -Until $Until -QueueId $QueueId -UserId $UserId -MediaType $MediaType -DivisionId $DivisionId)
        }

        # Extract ANI from customer participants using safe property access.
        $byAni = @{}
        foreach ($conv in $conversations) {
            $allParts = Get-PropertyValue $conv 'participants'
            $custPart = @($allParts) | Where-Object { (Get-PropertyValue $_ 'purpose') -eq 'customer' } | Select-Object -First 1
            if (-not $custPart) { continue }

            $ani = $null
            foreach ($sess in @(Get-PropertyValue $custPart 'sessions')) {
                if ($null -eq $sess) { continue }
                $aniVal  = Get-PropertyValue $sess 'ani'
                $dnisVal = Get-PropertyValue $sess 'dnis'
                if ($aniVal)  { $ani = $aniVal;  break }
                if ($dnisVal) { $ani = $dnisVal; break }
            }
            if (-not $ani) { continue }

            if (-not $byAni.ContainsKey($ani)) {
                $byAni[$ani] = [System.Collections.Generic.List[object]]::new()
            }
            $byAni[$ani].Add([PSCustomObject]@{
                ConversationId    = Get-PropertyValue $conv 'conversationId'
                ConversationStart = Get-PropertyValue $conv 'conversationStart'
            })
        }

        foreach ($ani in $byAni.Keys) {
            $records = @($byAni[$ani])
            if ($records.Count -ge $MinCallCount) {
                $sorted = $records | Sort-Object ConversationStart
                [PSCustomObject]@{
                    CallerAni       = $ani
                    CallCount       = $records.Count
                    ConversationIds = $records | ForEach-Object { $_.ConversationId }
                    FirstContact    = $sorted[0].ConversationStart
                    LastContact     = $sorted[-1].ConversationStart
                }
            }
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region WebRTC & Media Quality Trending  (Roadmap ideas 19–20)
# ---------------------------------------------------------------------------

function Get-GenesysWebRtcDisconnectSummary {
    <#
    .SYNOPSIS
        Summarises WebRTC disconnect events by error code and time bucket.
    .DESCRIPTION
        Processes agent voice quality records and produces a summary of WebRTC
        disconnect events grouped by ErrorCode and hour.  Use this as the
        backing data for a WebRTC disconnect heatmap or trend chart.

        Each record contains:
            Hour            — Truncated conversation start (YYYY-MM-DDTHH:00)
            ErrorCode       — webrtc | ice | stun | turn | rtp | media | sip | etc.
            DisconnectType  — client | server | transfer | endpoint | peer | other
            Count           — Number of sessions with this error in this hour
    .PARAMETER InputObject
        Voice quality records from Get-GenesysAgentVoiceQuality (pipeline).
        When omitted, data is fetched internally.
    .EXAMPLE
        # WebRTC disconnect trend for the last 24 hours
        Get-GenesysWebRtcDisconnectSummary | Sort-Object Hour, Count -Descending | Format-Table
    .EXAMPLE
        # Feed from an existing quality pull to avoid double-fetching
        $q = Get-GenesysConversationDetail | Get-GenesysAgentVoiceQuality
        $q | Get-GenesysWebRtcDisconnectSummary | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object[]] $InputObject
    )

    begin {
        $buffer = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $InputObject) {
            foreach ($item in $InputObject) { $buffer.Add($item) }
        }
    }
    end {
        $qualityRecords = if ($buffer.Count -gt 0) {
            $buffer.ToArray()
        } else {
            Assert-GenesysConnected
            @(Get-GenesysAgentVoiceQuality)
        }

        # Filter to WebRTC sessions with an error code
        $errored = $qualityRecords | Where-Object {
            $_.Provider -eq 'WebRTC' -and $_.ErrorCode
        }

        $groups = $errored | Group-Object {
            # Truncate to hour
            try {
                $dt = [datetime]::Parse($_.ConversationStart, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $dt.ToString('yyyy-MM-ddTHH:00')
            } catch { $_.ConversationStart }
        }, ErrorCode, DisconnectType

        foreach ($g in $groups) {
            $parts = $g.Name -split ', '
            [PSCustomObject]@{
                Hour           = if ($parts.Count -ge 1) { $parts[0] } else { $g.Name }
                ErrorCode      = if ($parts.Count -ge 2) { $parts[1] } else { $null }
                DisconnectType = if ($parts.Count -ge 3) { $parts[2] } else { $null }
                Count          = $g.Count
            }
        }
    }
}

function Get-GenesysConversationLatencyTrend {
    <#
    .SYNOPSIS
        Returns hourly conversation latency (handle time, talk time, ACW) trends.
    .DESCRIPTION
        Queries conversation aggregates and flattens queue-level performance into
        hourly latency buckets.  Use as the data source for a "latency trending"
        line chart or sparkline.

        Each record contains:
            QueueId        — Queue GUID
            MediaType      — voice, chat, email, etc.
            Interval       — Hour bucket (PT1H granularity)
            AvgHandleSec   — Average handle time in seconds
            AvgTalkSec     — Average talk time in seconds
            AvgAcwSec      — Average after-call work time in seconds
            AvgAnswerSec   — Average speed of answer (time to connect)
            nConnected     — Conversations connected
    .EXAMPLE
        $trend = Get-GenesysConversationLatencyTrend
        $trend | Sort-Object Interval | Select-Object QueueId, Interval, AvgHandleSec | Format-Table
    .EXAMPLE
        # Find the peak handle-time hour across all queues
        Get-GenesysConversationLatencyTrend | Sort-Object AvgHandleSec -Descending | Select-Object -First 5 | Format-Table
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected

    $raw = @(Get-GenesysQueuePerformance)

    foreach ($r in $raw) {
        $n = if ($r.nConnected_count) { $r.nConnected_count } else { 0 }

        $avgHandle = if ($n -gt 0 -and $r.tHandle_sum)   { [math]::Round($r.tHandle_sum   / $n / 1000, 1) } else { $null }
        $avgTalk   = if ($n -gt 0 -and $r.tTalk_sum)     { [math]::Round($r.tTalk_sum     / $n / 1000, 1) } else { $null }
        $avgAcw    = if ($n -gt 0 -and $r.tAcw_sum)      { [math]::Round($r.tAcw_sum      / $n / 1000, 1) } else { $null }
        $avgAnswer = if ($n -gt 0 -and $r.tAnswered_sum) { [math]::Round($r.tAnswered_sum / $n / 1000, 1) } else { $null }

        [PSCustomObject]@{
            QueueId      = $r.queueId
            MediaType    = $r.mediaType
            Interval     = $r.Interval
            AvgHandleSec = $avgHandle
            AvgTalkSec   = $avgTalk
            AvgAcwSec    = $avgAcw
            AvgAnswerSec = $avgAnswer
            nConnected   = $n
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region ACW Anomaly Detection  (Roadmap idea 21)
# ---------------------------------------------------------------------------

function Get-GenesysAgentAcwAnomaly {
    <#
    .SYNOPSIS
        Identifies agents with unusually high after-call work (ACW) time.
    .DESCRIPTION
        Computes average ACW per agent from the agent performance dataset and
        flags agents whose ACW exceeds the organisation-wide mean by more than
        the specified standard deviation multiplier.

        Each record contains:
            UserId         — Agent user GUID
            AvgAcwSec      — Agent's mean ACW duration in seconds
            OrgAvgAcwSec   — Organisation-wide mean ACW in seconds
            DeviationPct   — How far above the mean (%)
            nHandled       — Conversations handled in the window

        Agents far above the mean may need coaching, or their ACW reason codes
        (wrapup) may reveal process complexity in certain queues.
    .PARAMETER StdDevMultiplier
        How many multiples of the population standard deviation above the mean
        to use as the alert threshold.  Default: 2.0.
    .EXAMPLE
        Get-GenesysAgentAcwAnomaly | Sort-Object DeviationPct -Descending | Format-Table UserId, AvgAcwSec, OrgAvgAcwSec, DeviationPct
    .EXAMPLE
        Get-GenesysAgentAcwAnomaly -StdDevMultiplier 1.5 | Format-Table
    #>
    [CmdletBinding()]
    param(
        [double] $StdDevMultiplier = 2.0
    )

    Assert-GenesysConnected

    $perf = @(Get-GenesysAgentPerformance | Where-Object { $_.ConversationsHandled -gt 0 })
    if ($perf.Count -eq 0) { return }

    $agentAcw = foreach ($a in $perf) {
        $avgAcwSec = if ($a.AvgAcwSec) { $a.AvgAcwSec } else { 0.0 }
        [PSCustomObject]@{ UserId = $a.UserId; AvgAcwSec = $avgAcwSec; nHandled = $a.ConversationsHandled }
    }

    $mean     = ($agentAcw | Measure-Object AvgAcwSec -Average).Average
    $variance = ($agentAcw | ForEach-Object { [math]::Pow($_.AvgAcwSec - $mean, 2) } | Measure-Object -Average).Average
    $stdDev   = [math]::Sqrt($variance)
    $threshold = $mean + $StdDevMultiplier * $stdDev

    foreach ($a in $agentAcw) {
        $deviation = if ($mean -gt 0) { [math]::Round(($a.AvgAcwSec - $mean) / $mean * 100, 1) } else { 0.0 }
        if ($a.AvgAcwSec -ge $threshold) {
            [PSCustomObject]@{
                UserId       = $a.UserId
                AvgAcwSec    = [math]::Round($a.AvgAcwSec, 1)
                OrgAvgAcwSec = [math]::Round($mean, 1)
                DeviationPct = $deviation
                nHandled     = $a.nHandled
            }
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Workforce Management  (Roadmap idea 22)
# ---------------------------------------------------------------------------

function Get-GenesysWorkforceManagementUnit {
    <#
    .SYNOPSIS
        Returns WFM management units (team groupings for scheduling).
    .DESCRIPTION
        Fetches all workforce management units in the organisation.  Management
        units contain agents, scheduling rules, and adherence settings.

        Key fields returned:
            id             — Management unit GUID
            name           — Display name
            timezone       — Timezone for scheduling
            division       — Associated division reference
            agentCount     — Number of agents in the unit
    .EXAMPLE
        Get-GenesysWorkforceManagementUnit | Format-Table name, timezone, agentCount
    .EXAMPLE
        # Find management units with no agents
        Get-GenesysWorkforceManagementUnit | Where-Object { $_.agentCount -eq 0 } | Format-Table name, id
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'workforce.get.management.units')
}

#endregion

# ---------------------------------------------------------------------------
#region Journey / Predictive Engagement  (Roadmap idea 23)
# ---------------------------------------------------------------------------

function Get-GenesysJourneyActionMap {
    <#
    .SYNOPSIS
        Returns Journey action maps (predictive engagement triggers).
    .DESCRIPTION
        Lists all action maps in the Journey platform.  Action maps define
        the conditions under which proactive engagement actions (chat offers,
        callbacks, content cards) are triggered for web visitors.

        Key fields returned:
            id             — Action map GUID
            displayName    — Display name
            trigger        — Trigger type (e.g. VISIT_COUNT, WAIT_TIME)
            action         — Action type (CHAT_OFFER, CONTENT_OFFER, etc.)
            isActive       — Whether the action map is enabled
            startDate      — Activation start date
            endDate        — Activation end date
    .EXAMPLE
        # List all active action maps
        Get-GenesysJourneyActionMap | Where-Object { $_.isActive } | Format-Table displayName, trigger, action
    .EXAMPLE
        # Find action maps that have expired
        $now = Get-Date
        Get-GenesysJourneyActionMap | Where-Object {
            $_.endDate -and [datetime]$_.endDate -lt $now
        } | Format-Table displayName, endDate
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'journey.get.action.maps')
}

#endregion

# ---------------------------------------------------------------------------
#region Peak Hour Load Analysis  (Roadmap idea 27)
# ---------------------------------------------------------------------------

function Get-GenesysPeakHourLoad {
    <#
    .SYNOPSIS
        Identifies peak traffic intervals (staffing-gap hotspots) across queues.
    .DESCRIPTION
        Analyses historical queue performance data to surface the time intervals
        with the highest offered volume or longest handle time.  Use this to feed
        WFM scheduling reviews and identify recurring staffing gaps.

        Each record contains:
            QueueId      — Queue GUID
            MediaType    — voice, chat, email, etc.
            Interval     — Time bucket (PT1H granularity by default)
            nConnected   — Conversations connected in the interval
            AvgHandleSec — Average handle time in seconds
            AvgTalkSec   — Average talk time in seconds
            AvgAcwSec    — Average after-call work time in seconds
            Rank         — 1 = busiest interval for this queue

        Note: granularity is PT1H from the default catalog profile.  For PT15M
        resolution, use Invoke-Dataset directly with a custom DatasetParameters
        body containing "granularity": "PT15M" against the
        analytics.query.conversation.aggregates.queue.performance endpoint.
    .PARAMETER TopN
        Number of peak intervals to return per queue.  Default: 5.
    .PARAMETER SortBy
        Metric to rank intervals by.  Default: nConnected (highest offered volume).
        Use AvgHandleSec to rank by longest handling time instead.
    .EXAMPLE
        # Show top 5 peak hours across all queues
        Get-GenesysPeakHourLoad | Format-Table QueueId, Interval, nConnected, Rank
    .EXAMPLE
        # Top 3 by avg handle time — find when agents are most stretched
        Get-GenesysPeakHourLoad -TopN 3 -SortBy AvgHandleSec |
            Sort-Object QueueId, Rank | Format-Table
    .EXAMPLE
        # Filter to voice only and get the single busiest hour per queue
        Get-GenesysPeakHourLoad -TopN 1 |
            Where-Object MediaType -eq 'voice' |
            Sort-Object nConnected -Descending | Format-Table
    #>
    [CmdletBinding()]
    param(
        [int]    $TopN   = 5,
        [ValidateSet('nConnected','AvgHandleSec','AvgTalkSec')]
        [string] $SortBy = 'nConnected'
    )

    Assert-GenesysConnected

    $trend = @(Get-GenesysConversationLatencyTrend)
    if ($trend.Count -eq 0) { return }

    # Group by queue+media and rank intervals within each group
    $groups = $trend | Group-Object QueueId, MediaType

    foreach ($g in $groups) {
        $sorted = @($g.Group | Sort-Object $SortBy -Descending)
        $top    = if ($sorted.Count -le $TopN) { $sorted } else { $sorted[0..($TopN - 1)] }
        $rank   = 1
        foreach ($r in $top) {
            [PSCustomObject]@{
                QueueId      = $r.QueueId
                MediaType    = $r.MediaType
                Interval     = $r.Interval
                nConnected   = $r.nConnected
                AvgHandleSec = $r.AvgHandleSec
                AvgTalkSec   = $r.AvgTalkSec
                AvgAcwSec    = $r.AvgAcwSec
                Rank         = $rank
            }
            $rank++
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Configuration Change Audit Feed  (Roadmap idea 28)
# ---------------------------------------------------------------------------

function Get-GenesysChangeAuditFeed {
    <#
    .SYNOPSIS
        Returns a risk-categorised feed of recent admin configuration changes.
    .DESCRIPTION
        Wraps Get-GenesysAuditEvent to surface configuration-changing actions
        with a Risk field so NOC/governance dashboards and ChatOps bots can
        prioritise response.

        Risk levels:
            HIGH    — DELETE or REVOKE actions on users, flows, or OAuth clients
            MEDIUM  — CREATE or UPDATE on flows, queues, or user roles
            LOW     — All other configuration changes

        Each record adds:
            Risk        — HIGH / MEDIUM / LOW
            Summary     — Human-readable one-liner

        Note: the underlying dataset covers the last hour (catalog default).
        For broader windows use Get-GenesysAuditEvent directly and call this
        function's classification logic on the results.
    .PARAMETER EntityType
        Filter by Genesys entity type (USER, QUEUE, FLOW, DIVISION, …).
    .PARAMETER Risk
        Return only events at or above this risk level
        (HIGH returns HIGH only; MEDIUM returns HIGH + MEDIUM; LOW returns all).
    .EXAMPLE
        # Show all high-risk changes in the past hour
        Get-GenesysChangeAuditFeed -Risk HIGH | Format-Table timestamp, Risk, Summary
    .EXAMPLE
        # Governance feed — all changes to flows
        Get-GenesysChangeAuditFeed -EntityType FLOW | Sort-Object timestamp | Format-Table
    .EXAMPLE
        # Pipe into a ChatOps alert
        Get-GenesysChangeAuditFeed -Risk HIGH |
            ForEach-Object { Send-Teams -Message "⚠️ $($_.Risk): $($_.Summary)" }
    #>
    [CmdletBinding()]
    param(
        [string] $EntityType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [ValidateSet('HIGH','MEDIUM','LOW')]
        [string] $Risk
    )

    Assert-GenesysConnected

    $filterParams = @{}
    if ($EntityType) { $filterParams['EntityType'] = $EntityType }
    if ($Since.HasValue) { $filterParams['Since'] = $Since }
    if ($Until.HasValue) { $filterParams['Until'] = $Until }

    $events = @(Get-GenesysAuditEvent @filterParams)
    if ($events.Count -eq 0) { return }

    # Entity types considered sensitive for risk elevation
    $highRiskEntities = @('USER','FLOW','OAUTH_CLIENT','DIVISION','ROLE')
    $mediumRiskEntities = @('QUEUE','ROUTING_SKILL','WRAPUP_CODE','SCHEDULE','STATION')

    foreach ($ev in $events) {
        # Use safe property access to avoid StrictMode failures when serviceContext or user is absent.
        $action     = [string](Get-PropertyValue $ev 'action')
        $entityType = [string](Get-NestedPropertyValue $ev 'serviceContext.entityType')
        $entityName = [string](Get-NestedPropertyValue $ev 'serviceContext.entityName')

        # Classify risk
        $riskLevel = 'LOW'
        $isHighAction   = $action -like 'DELETE_*' -or $action -like 'REVOKE_*'
        $isMediumAction = $action -like 'CREATE_*' -or $action -like 'UPDATE_*' -or $action -like 'ADD_*'

        if ($isHighAction -and $entityType -in $highRiskEntities)    { $riskLevel = 'HIGH'   }
        elseif ($isHighAction)                                         { $riskLevel = 'MEDIUM' }
        elseif ($isMediumAction -and $entityType -in $highRiskEntities){ $riskLevel = 'MEDIUM' }
        elseif ($isMediumAction -and $entityType -in $mediumRiskEntities) { $riskLevel = 'LOW' }

        # Compose summary using safe access for user sub-object
        $actor   = Get-NestedPropertyValue $ev 'user.email'
        $actor   = if ($actor) { $actor } else { 'unknown' }
        $summary = "$($action) on $($entityType) '$($entityName)' by $($actor)"

        $record = [PSCustomObject]@{
            Timestamp  = Get-PropertyValue $ev 'timestamp'
            Risk       = $riskLevel
            Action     = $action
            EntityType = $entityType
            EntityName = $entityName
            Actor      = $actor
            Summary    = $summary
            IpAddress  = Get-NestedPropertyValue $ev 'user.ipAddress'
        }

        # Apply risk filter if requested
        $include = $true
        if ($Risk) {
            $include = switch ($Risk) {
                'HIGH'   { $riskLevel -eq 'HIGH' }
                'MEDIUM' { $riskLevel -in @('HIGH','MEDIUM') }
                'LOW'    { $true }
            }
        }

        if ($include) { $record }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Outbound Campaign Performance  (Roadmap idea 29)
# ---------------------------------------------------------------------------

function Get-GenesysOutboundCampaignPerformance {
    <#
    .SYNOPSIS
        Returns a per-campaign performance KPI snapshot.
    .DESCRIPTION
        Combines outbound campaign configuration with dialer event disposition
        counts to produce a ready-to-display performance record for each campaign.

        Each record contains:
            CampaignId       — Campaign GUID
            CampaignName     — Campaign display name
            Status           — on / off / complete / stopping / invalid
            DialingMode      — preview, power, progressive, agentless, etc.
            TotalEvents      — Total dialer events in the dataset
            Connected        — Contacts that connected (live answer)
            NoAnswer         — Attempts resulting in no-answer
            Busy             — Attempts reaching busy tone
            Voicemail        — Attempts reaching voicemail (answering machine)
            Other            — Remaining dispositions
            ConnectRate      — Connected / TotalAttempts (%)
            NoAnswerRate     — NoAnswer / TotalAttempts (%)
            AbandonRateLimit — Maximum configured abandon rate for the campaign
    .PARAMETER Name
        Wildcard filter on campaign name.
    .PARAMETER Status
        Filter by campaign status (on, off, complete, stopping, invalid).
    .EXAMPLE
        Get-GenesysOutboundCampaignPerformance | Sort-Object ConnectRate -Descending | Format-Table
    .EXAMPLE
        # Only running campaigns
        Get-GenesysOutboundCampaignPerformance -Status on | Format-Table CampaignName, ConnectRate, NoAnswerRate
    .EXAMPLE
        # Campaigns with connect rate below 10% — potential list quality issue
        Get-GenesysOutboundCampaignPerformance |
            Where-Object { $_.TotalEvents -gt 0 -and $_.ConnectRate -lt 10 } |
            Format-Table CampaignName, TotalEvents, ConnectRate
    #>
    [CmdletBinding()]
    param(
        [string] $Name,
        [ValidateSet('on','off','complete','stopping','invalid')]
        [string] $Status
    )

    Assert-GenesysConnected

    $campaignParams = @{}
    if ($Name)   { $campaignParams['Name']   = $Name }
    if ($Status) { $campaignParams['Status'] = $Status }

    $campaigns = @(Get-GenesysOutboundCampaign @campaignParams)
    if ($campaigns.Count -eq 0) { return }

    $events = @(Get-GenesysOutboundEvent)

    # Index events by campaignId
    $eventIndex = @{}
    foreach ($ev in $events) {
        $cid = [string]$ev.campaignId
        if (-not $eventIndex.ContainsKey($cid)) {
            $eventIndex[$cid] = [System.Collections.Generic.List[object]]::new()
        }
        $eventIndex[$cid].Add($ev) | Out-Null
    }

    foreach ($c in $campaigns) {
        $cid   = [string]$c.id
        $cEvts = if ($eventIndex.ContainsKey($cid)) { @($eventIndex[$cid]) } else { @() }

        # Tally dispositions — only attempt events carry callResult
        $attempts  = @($cEvts | Where-Object { $null -ne $_.callResult })
        $total     = $attempts.Count
        $connected = ($attempts | Where-Object { $_.callResult -eq 'Connected'    }).Count
        $noAnswer  = ($attempts | Where-Object { $_.callResult -eq 'NoAnswer'     }).Count
        $busy      = ($attempts | Where-Object { $_.callResult -eq 'Busy'         }).Count
        $voicemail = ($attempts | Where-Object { $_.callResult -like '*Voicemail*' -or $_.callResult -like '*Machine*' }).Count
        $other     = $total - $connected - $noAnswer - $busy - $voicemail

        $connectRate = if ($total -gt 0) { [math]::Round($connected / $total * 100, 1) } else { $null }
        $naRate      = if ($total -gt 0) { [math]::Round($noAnswer  / $total * 100, 1) } else { $null }

        [PSCustomObject]@{
            CampaignId       = $cid
            CampaignName     = $c.name
            Status           = $c.campaignStatus
            DialingMode      = $c.dialingMode
            TotalEvents      = $cEvts.Count
            TotalAttempts    = $total
            Connected        = $connected
            NoAnswer         = $noAnswer
            Busy             = $busy
            Voicemail        = $voicemail
            Other            = if ($other -ge 0) { $other } else { 0 }
            ConnectRate      = $connectRate
            NoAnswerRate     = $naRate
            AbandonRateLimit = $c.abandonRate
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Flow Outcome KPI Correlation  (Roadmap idea 30)
# ---------------------------------------------------------------------------

function Get-GenesysFlowOutcomeKpiCorrelation {
    <#
    .SYNOPSIS
        Correlates IVR / bot flow outcomes with CSAT scores and handle time.
    .DESCRIPTION
        Joins flow aggregate execution metrics with CSAT/NPS survey scores and
        queue handle-time aggregates to identify flows where self-service drop-off
        leads to poorer downstream customer experience.

        Each record contains:
            FlowId                — Architect flow GUID
            FlowName              — Flow display name (if resolved)
            FlowType              — inboundcall, bot, inboundchat, etc.
            Interval              — Time bucket
            nFlow                 — Contacts that entered the flow
            nFlowOutcome          — Contacts with a defined outcome
            nFlowOutcomeFailed    — Contacts with a FAILED outcome
            SelfServeRate         — nFlowOutcome / nFlow (%) — completions
            FailureRate           — nFlowOutcomeFailed / nFlow (%)
            AvgSurveyScore        — Mean CSAT/NPS score from surveys in window
            SurveyCount           — Number of surveys correlated
            AvgHandleSec          — Queue avg handle time for the survey window

        Flows with high failure rates and low CSAT scores are the primary
        self-service drop-off candidates for IVR tuning.
    .EXAMPLE
        Get-GenesysFlowOutcomeKpiCorrelation |
            Sort-Object FailureRate -Descending |
            Select-Object FlowName, FailureRate, AvgSurveyScore |
            Format-Table
    .EXAMPLE
        # Flag flows with failure > 20% AND low CSAT
        Get-GenesysFlowOutcomeKpiCorrelation |
            Where-Object { $_.FailureRate -gt 20 -and $null -ne $_.AvgSurveyScore -and $_.AvgSurveyScore -lt 7 } |
            Format-Table FlowName, FailureRate, AvgSurveyScore
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected

    $flowAgg  = @(Get-GenesysFlowAggregate)
    $flows    = @(Get-GenesysFlow)
    $surveys  = @(Get-GenesysSurvey)
    $qPerf    = @(Get-GenesysQueuePerformance)

    # Build flow name lookup
    $flowNames = @{}
    foreach ($f in $flows) { $flowNames[$f.id] = $f.name }

    # Aggregate surveys into a single mean score (no per-flow mapping available
    # from the survey dataset without conversation join; use org-wide mean as proxy)
    $surveyScores = @($surveys | Where-Object { $null -ne $_.totalScore })
    $orgAvgSurvey = if ($surveyScores.Count -gt 0) {
        [math]::Round(($surveyScores | Measure-Object totalScore -Average).Average, 2)
    } else { $null }

    # Aggregate queue performance into a single org-wide avg handle time
    $qPerfWithData = @($qPerf | Where-Object { $_.nConnected_count -gt 0 -and $_.tHandle_sum })
    $orgAvgHandle  = if ($qPerfWithData.Count -gt 0) {
        $totalHandle = ($qPerfWithData | Measure-Object tHandle_sum -Sum).Sum
        $totalConn   = ($qPerfWithData | Measure-Object nConnected_count -Sum).Sum
        if ($totalConn -gt 0) { [math]::Round($totalHandle / $totalConn / 1000, 1) } else { $null }
    } else { $null }

    foreach ($fa in $flowAgg) {
        $n        = if ($fa.nFlow_count)            { [int]$fa.nFlow_count            } else { 0 }
        $nOut     = if ($fa.nFlowOutcome_count)     { [int]$fa.nFlowOutcome_count     } else { 0 }
        $nFailed  = if ($fa.nFlowOutcomeFailed_count){ [int]$fa.nFlowOutcomeFailed_count } else { 0 }

        $selfServeRate = if ($n -gt 0) { [math]::Round($nOut    / $n * 100, 1) } else { $null }
        $failureRate   = if ($n -gt 0) { [math]::Round($nFailed / $n * 100, 1) } else { $null }

        [PSCustomObject]@{
            FlowId             = $fa.flowId
            FlowName           = $flowNames[$fa.flowId]
            FlowType           = $fa.flowType
            Interval           = $fa.Interval
            nFlow              = $n
            nFlowOutcome       = $nOut
            nFlowOutcomeFailed = $nFailed
            SelfServeRate      = $selfServeRate
            FailureRate        = $failureRate
            AvgSurveyScore     = $orgAvgSurvey
            SurveyCount        = $surveyScores.Count
            AvgHandleSec       = $orgAvgHandle
        }
    }
}

#endregion

# ---------------------------------------------------------------------------
#region Composite Dashboard Snapshots  (Roadmap ideas 24–30)
# ---------------------------------------------------------------------------

function Get-GenesysAbandonRateDashboard {
    <#
    .SYNOPSIS
        Returns a multi-queue abandon rate dashboard snapshot.
    .DESCRIPTION
        Combines real-time queue observations with historical abandon aggregates
        to produce a dashboard-ready per-queue KPI record.

        Each record contains:
            QueueId           — Queue GUID
            QueueName         — Queue display name (if found in queue list)
            MediaType         — voice, chat, email, etc.
            Interval          — Aggregate time bucket
            nOffered          — Contacts offered
            nAbandoned        — Contacts abandoned
            AbandonRate       — Abandon % (nAbandoned / nOffered)
            oWaiting          — Contacts currently waiting (real-time)
            oInteracting      — Agents currently interacting (real-time)
    .EXAMPLE
        Get-GenesysAbandonRateDashboard | Sort-Object AbandonRate -Descending | Format-Table
    .EXAMPLE
        # Alert on any queue > 8% abandon
        Get-GenesysAbandonRateDashboard |
            Where-Object { $_.AbandonRate -gt 8 } |
            ForEach-Object { Write-Warning "HIGH ABANDON: $($_.QueueName) — $($_.AbandonRate)%" }
    #>
    [CmdletBinding()]
    param(
        [string[]] $QueueId,
        [string] $MediaType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected

    $abandonData  = @(Get-GenesysQueueAbandonRate -QueueId $QueueId -MediaType $MediaType -Since $Since -Until $Until)
    $observations = @(Get-GenesysQueueObservation -QueueId $QueueId -MediaType $MediaType)
    $queues       = @(Get-GenesysQueue)

    # Index observations by queueId+mediaType
    $obsIndex = @{}
    foreach ($o in $observations) {
        $key = "$($o.QueueId)|$($o.MediaType)"
        $obsIndex[$key] = $o
    }

    # Index queue names by id
    $queueNames = @{}
    foreach ($q in $queues) { $queueNames[$q.id] = $q.name }

    foreach ($a in $abandonData) {
        $key = "$($a.QueueId)|$($a.MediaType)"
        $obs = $obsIndex[$key]

        [PSCustomObject]@{
            QueueId      = $a.QueueId
            QueueName    = $queueNames[$a.QueueId]
            MediaType    = $a.MediaType
            Interval     = $a.Interval
            nOffered     = $a.nOffered
            nAbandoned   = $a.nAbandoned
            AbandonRate  = $a.AbandonRate
            oWaiting     = if ($obs) { $obs.oWaiting     } else { $null }
            oInteracting = if ($obs) { $obs.oInteracting } else { $null }
        }
    }
}

function Get-GenesysQueueHealthSnapshot {
    <#
    .SYNOPSIS
        Returns a multi-queue health snapshot combining observations and SLA.
    .DESCRIPTION
        Multi-queue, no run-artifacts. For a single-queue investigation that
        emits the standard manifest/events/summary/data set, use
        Get-GenesysQueueInvestigation.

        Merges real-time queue observations (waiting, interacting, on-queue agents)
        with service level performance into a single per-queue health record.

        Fields:
            QueueId           — Queue GUID
            QueueName         — Display name
            MediaType         — voice, chat, email, etc.
            oWaiting          — Contacts currently waiting
            oInteracting      — Agents currently interacting
            oOnQueueUsers     — Agents on-queue
            ServiceLevel30Pct — % answered in 30 s (historical SLA)
            nOffered          — Offered count (from SLA window)
            HealthStatus      — GREEN (SL ≥ 80%, oWaiting < 5)
                                AMBER (SL 60–80% or oWaiting 5–10)
                                RED   (SL < 60% or oWaiting > 10)
    .EXAMPLE
        Get-GenesysQueueHealthSnapshot | Sort-Object HealthStatus | Format-Table
    .EXAMPLE
        # Show only queues in RED
        Get-GenesysQueueHealthSnapshot | Where-Object HealthStatus -eq 'RED' | Format-Table QueueName, oWaiting, ServiceLevel30Pct
    #>
    [CmdletBinding()]
    param(
        [string[]] $QueueId,
        [string] $MediaType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until
    )

    Assert-GenesysConnected

    $observations = @(Get-GenesysQueueObservation -QueueId $QueueId -MediaType $MediaType)
    $sla          = @(Get-GenesysQueueServiceLevel -QueueId $QueueId -MediaType $MediaType -Since $Since -Until $Until)
    $queues       = @(Get-GenesysQueue)

    $queueNames = @{}
    foreach ($q in $queues) { $queueNames[$q.id] = $q.name }

    $slaIndex = @{}
    foreach ($s in $sla) {
        $key = "$($s.QueueId)|$($s.MediaType)"
        if (-not $slaIndex.ContainsKey($key)) { $slaIndex[$key] = $s }
    }

    foreach ($o in $observations) {
        $key    = "$($o.QueueId)|$($o.MediaType)"
        $slaRec = $slaIndex[$key]

        $waiting = if ($o.oWaiting) { [int]$o.oWaiting } else { 0 }
        $sl30    = if ($slaRec)     { $slaRec.ServiceLevel30Pct } else { $null }

        $health = 'GREEN'
        if     ($null -ne $sl30 -and $sl30 -lt 60) { $health = 'RED'   }
        elseif ($waiting -gt 10)                    { $health = 'RED'   }
        elseif ($null -ne $sl30 -and $sl30 -lt 80)  { $health = 'AMBER' }
        elseif ($waiting -ge 5)                     { $health = 'AMBER' }

        [PSCustomObject]@{
            QueueId           = $o.QueueId
            QueueName         = $queueNames[$o.QueueId]
            MediaType         = $o.MediaType
            oWaiting          = $o.oWaiting
            oInteracting      = $o.oInteracting
            oOnQueueUsers     = $o.oOnQueueUsers
            ServiceLevel30Pct = $sl30
            nOffered          = if ($slaRec) { $slaRec.nOffered } else { $null }
            HealthStatus      = $health
        }
    }
}

function Get-GenesysAgentQualitySnapshot {
    <#
    .SYNOPSIS
        Returns a per-agent quality KPI snapshot combining performance metrics.
    .DESCRIPTION
        Returns agent performance aggregates (handle time, ACW, talk time)
        ready for an agent quality leaderboard or coaching priority list.

        Fields:
            UserId               — Agent user GUID
            ConversationsHandled — Conversations handled in window
            AvgHandleSec         — Average handle time in seconds
            AvgAcwSec            — Average ACW in seconds
            AvgTalkSec           — Average talk time in seconds
    .EXAMPLE
        Get-GenesysAgentQualitySnapshot | Sort-Object AvgHandleSec -Descending | Format-Table
    .EXAMPLE
        Get-GenesysAgentQualitySnapshot | Export-Csv .\agent-quality-$(Get-Date -f yyyyMMdd).csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [int] $MinConversations = 0,
        [string[]] $UserId,
        [string] $MediaType,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string] $Granularity
    )

    Assert-GenesysConnected
    @(Get-GenesysAgentPerformance -MinConversations $MinConversations -UserId $UserId -MediaType $MediaType -Since $Since -Until $Until -Granularity $Granularity)
}

function Invoke-GenesysOperationsReport {
    <#
    .SYNOPSIS
        Generates an enhanced operations report including abandon rate, SLA, and edge health.
    .DESCRIPTION
        Multi-subject daily report. For a single-queue investigation under the
        standard run-artifact contract, use Get-GenesysQueueInvestigation; this
        cmdlet remains the cross-queue/edge/alerts roll-up.

        Extends the standard daily health report with new KPI sections:
          - Queue abandon rates
          - Service level (SLA) compliance
          - Edge and trunk infrastructure health
          - Active platform alerts
          - WebRTC disconnect summary

        Sections are collected independently.  A failure in one section does not
        abort the report unless -FailFast is specified.

        Use -OutputPath to write the report as UTF-8 JSON for downstream
        consumption (dashboards, ticketing, log aggregation).
    .PARAMETER OutputPath
        If specified, the report is serialised to this path as UTF-8 JSON.
    .PARAMETER PassThru
        Return the report object even when -OutputPath is used.
    .PARAMETER FailFast
        Stop immediately if any section fails.
    .EXAMPLE
        Invoke-GenesysOperationsReport | ConvertTo-Json -Depth 8
    .EXAMPLE
        Invoke-GenesysOperationsReport -OutputPath "D:\Reports\OpsReport-$(Get-Date -f yyyyMMdd).json" -PassThru
    #>
    [CmdletBinding()]
    param(
        [string] $OutputPath,
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [string[]] $QueueId,
        [string] $MediaType,
        [switch] $PassThru,
        [switch] $FailFast
    )

    Assert-GenesysConnected

    $diag = [System.Collections.Generic.List[object]]::new()

    function Invoke-OpsSection {
        param([string]$Name, [scriptblock]$Action)
        try {
            $r = & $Action
            $diag.Add([PSCustomObject]@{ Section = $Name; Status = 'OK';     Count = @($r).Count; Error = $null })
            return $r
        } catch {
            $msg = "$($Name): $_"
            $diag.Add([PSCustomObject]@{ Section = $Name; Status = 'Failed'; Count = $null;        Error = $msg  })
            Write-Warning $msg
            if ($FailFast) { throw $msg }
            return $null
        }
    }

    Write-Verbose 'Collecting organisation details...'
    $org = Invoke-OpsSection 'Organisation' { Get-GenesysOrganization }

    Write-Verbose 'Collecting contact centre status...'
    $ccStatus = Invoke-OpsSection 'ContactCentre' { Get-GenesysContactCentreStatus }

    Write-Verbose 'Collecting queue abandon rates...'
    $abandon = Invoke-OpsSection 'AbandonRate' { @(Get-GenesysQueueAbandonRate -QueueId $QueueId -MediaType $MediaType -Since $Since -Until $Until) }

    Write-Verbose 'Collecting queue service levels...'
    $sla = Invoke-OpsSection 'ServiceLevel' { @(Get-GenesysQueueServiceLevel -QueueId $QueueId -MediaType $MediaType -Since $Since -Until $Until) }

    Write-Verbose 'Collecting edge health...'
    $edgeSnap = Invoke-OpsSection 'EdgeHealth' { Get-GenesysEdgeHealthSnapshot }

    Write-Verbose 'Collecting active alerts...'
    $alerts = Invoke-OpsSection 'ActiveAlerts' { @(Get-GenesysAlert) }

    Write-Verbose 'Collecting voice quality / WebRTC disconnects...'
    $webrtcSummary = Invoke-OpsSection 'WebRtcDisconnects' { @(Get-GenesysWebRtcDisconnectSummary) }

    $highAbandon = if ($abandon) { @($abandon | Where-Object { $_.AbandonRate -gt 10 }) } else { @() }
    $avgAbandon  = if ($abandon -and @($abandon).Count -gt 0) {
        [math]::Round((@($abandon) | Measure-Object AbandonRate -Average).Average, 1)
    } else { $null }

    $belowSla = if ($sla) { @($sla | Where-Object { $_.nOffered -gt 0 -and $_.ServiceLevel30Pct -lt 80 }) } else { @() }
    $avgSla   = if ($sla -and @($sla).Count -gt 0) {
        $slaWithData = @($sla | Where-Object { $null -ne $_.ServiceLevel30Pct })
        if ($slaWithData.Count -gt 0) { [math]::Round(($slaWithData | Measure-Object ServiceLevel30Pct -Average).Average, 1) } else { $null }
    } else { $null }

    $report = [PSCustomObject]@{
        GeneratedAt   = Get-Date -Format 'o'
        Organisation  = if ($org) {
            [PSCustomObject]@{ Name = (Get-PropertyValue $org 'name'); Id = (Get-PropertyValue $org 'id') }
        } else { $null }
        ContactCentre = $ccStatus
        AbandonRate   = [PSCustomObject]@{
            AverageAbandonPct   = $avgAbandon
            QueuesAbove10Pct    = $highAbandon.Count
            HighAbandonQueueIds = $highAbandon | ForEach-Object { $_.QueueId }
        }
        ServiceLevel  = [PSCustomObject]@{
            AverageSL30Pct      = $avgSla
            QueuesBelowTarget   = $belowSla.Count
            BelowTargetQueueIds = $belowSla | ForEach-Object { $_.QueueId }
        }
        EdgeHealth    = $edgeSnap
        ActiveAlerts  = if ($alerts) {
            [PSCustomObject]@{
                Count  = @($alerts).Count
                Alerts = @($alerts) | Select-Object -First 10 | ForEach-Object { Get-PropertyValue $_ 'name' }
            }
        } else { $null }
        WebRtcDisconnects = if ($webrtcSummary) {
            [PSCustomObject]@{
                TotalErrorEvents = (@($webrtcSummary) | Measure-Object Count -Sum).Sum
                ByErrorCode      = @($webrtcSummary) |
                    Group-Object ErrorCode |
                    Select-Object Name, @{n='Count';e={($_.Group|Measure-Object Count -Sum).Sum}} |
                    Sort-Object Count -Descending
            }
        } else { $null }
        Diagnostics   = $diag.ToArray()
    }

    if ($OutputPath) {
        $report | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Verbose "Report saved: $($OutputPath)"
    }

    if ($PassThru -or -not $OutputPath) { $report }
}

function Invoke-GenesysNotRespondingReport {
    <#
    .SYNOPSIS
        Identifies agents who consistently enter NOT_RESPONDING and the conversations
        active when they did so.
    .DESCRIPTION
        Composes two async analytics jobs to build a frequency-and-pattern report:

          1. analytics.post.users.details.jobs filtered to routingStatus = NOT_RESPONDING
             over the requested window. Returns one record per user with all of their
             NR routingStatusDetail segments.

          2. (Optional, when -IncludeConversations) analytics-conversation-details
             filtered by segmentFilters userId IN (top-N NR users), so conversations
             that were alerting when each agent went NR are joined to the user record.

        Per-user aggregates: transition count, total NR seconds, average NR seconds,
        active-day count (distinct UTC days the user had any routing activity),
        transitions-per-active-day, and a per-day breakdown. Users meeting the
        -MinTransitionsPerDay threshold are flagged Consistent.
    .PARAMETER Since
        Window start (UTC). Defaults to 14 days before -Until.
    .PARAMETER Until
        Window end (UTC). Defaults to now.
    .PARAMETER MinTransitionsPerDay
        Threshold for the Consistent flag: TransitionCount / ActiveDays >= this value.
        Default 1.0 (at least one NR per active day).
    .PARAMETER TopN
        Cap on TopUsers in the returned report and on the userId list passed to the
        conversation-details join. Default 25.
    .PARAMETER IncludeConversations
        Pull the conversation-details job for the top-N users and attach the set of
        ConversationIds each appeared in. Adds 30s-2min depending on volume.
    .PARAMETER OutputPath
        If specified, the report is written as UTF-8 JSON.
    .PARAMETER PassThru
        Return the report object even when -OutputPath is used.
    .EXAMPLE
        # Last 14 days, default 1.0/day threshold
        Invoke-GenesysNotRespondingReport | Format-Table -AutoSize
    .EXAMPLE
        # Stricter: only flag users averaging 3+ NR per active day, include conversations
        Invoke-GenesysNotRespondingReport -MinTransitionsPerDay 3 -IncludeConversations
    .EXAMPLE
        # Save for tracking
        Invoke-GenesysNotRespondingReport -OutputPath ".\nr-$(Get-Date -f yyyyMMdd).json"
    #>
    [CmdletBinding()]
    param(
        [Nullable[datetime]] $Since,
        [Nullable[datetime]] $Until,
        [double]             $MinTransitionsPerDay = 1.0,
        [int]                $TopN = 25,
        [switch]             $IncludeConversations,
        [string]             $OutputPath,
        [switch]             $PassThru
    )

    Assert-GenesysConnected

    $untilUtc = if ($Until.HasValue) { $Until.Value.ToUniversalTime() } else { [datetime]::UtcNow }
    $sinceUtc = if ($Since.HasValue) { $Since.Value.ToUniversalTime() } else { $untilUtc.AddDays(-14) }
    $interval = '{0}/{1}' -f `
        $sinceUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'), `
        $untilUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

    Write-Verbose "Submitting user-details NR job over $interval"
    $userJobBody = [ordered]@{
        interval             = $interval
        routingStatusFilters = @(
            [ordered]@{
                type       = 'and'
                predicates = @(
                    [ordered]@{
                        dimension = 'routingStatus'
                        operator  = 'matches'
                        value     = 'NOT_RESPONDING'
                    }
                )
            }
        )
    }

    $userDetails = @(Invoke-GenesysDataset `
        -Dataset 'analytics.post.users.details.jobs' `
        -DatasetParameters @{ Body = $userJobBody })

    Write-Verbose "User-details job returned $($userDetails.Count) user records"

    $perUser = New-Object System.Collections.Generic.List[object]
    foreach ($u in $userDetails) {
        $userId = Get-PropertyValue $u 'userId'
        if (-not $userId) { continue }

        $segments = @(Get-PropertyValue $u 'routingStatusDetail')
        $nrSegments = @($segments | Where-Object {
            (Get-PropertyValue $_ 'routingStatus') -eq 'NOT_RESPONDING'
        })
        if ($nrSegments.Count -eq 0) { continue }

        $totalNrMs = 0.0
        $nrTimestamps = New-Object System.Collections.Generic.List[datetime]
        foreach ($seg in $nrSegments) {
            $startStr = Get-PropertyValue $seg 'startTime'
            if (-not $startStr) { continue }
            $start = [datetime]::Parse($startStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            $nrTimestamps.Add($start)
            $endStr = Get-PropertyValue $seg 'endTime'
            if ($endStr) {
                $end = [datetime]::Parse($endStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                $totalNrMs += ($end - $start).TotalMilliseconds
            }
        }

        $allDayBuckets = @{}
        foreach ($seg in $segments) {
            $startStr = Get-PropertyValue $seg 'startTime'
            if (-not $startStr) { continue }
            $d = [datetime]::Parse($startStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal).Date
            $allDayBuckets[$d.ToString('yyyy-MM-dd')] = $true
        }
        $activeDays = [Math]::Max(1, $allDayBuckets.Count)

        $byDay = $nrTimestamps |
            Group-Object { $_.Date.ToString('yyyy-MM-dd') } |
            ForEach-Object { [pscustomobject]@{ Date = $_.Name; Count = $_.Count } } |
            Sort-Object Date

        $count = $nrSegments.Count
        $tpd   = [math]::Round($count / $activeDays, 2)
        $avgMs = if ($count -gt 0) { $totalNrMs / $count } else { 0 }

        $perUser.Add([pscustomobject]@{
            UserId                  = $userId
            Name                    = $null
            Division                = $null
            TransitionCount         = $count
            ActiveDays              = $activeDays
            TransitionsPerActiveDay = $tpd
            TotalNrSeconds          = [int]([math]::Round($totalNrMs / 1000))
            AvgNrSeconds            = [int]([math]::Round($avgMs / 1000))
            DailyBreakdown          = @($byDay)
            Flag                    = if ($tpd -ge $MinTransitionsPerDay) { 'Consistent' } else { '' }
            ConversationIds         = @()
            NrStartTimes            = @($nrTimestamps | ForEach-Object { $_.ToString('o') })
        }) | Out-Null
    }

    $sorted = @($perUser | Sort-Object TransitionsPerActiveDay, TransitionCount -Descending)

    if ($IncludeConversations -and $sorted.Count -gt 0) {
        $topIds = @($sorted | Select-Object -First $TopN | ForEach-Object { $_.UserId })
        Write-Verbose "Pulling conversation-details for top $($topIds.Count) NR users"
        $convJobBody = [ordered]@{
            interval       = $interval
            segmentFilters = @(
                [ordered]@{
                    type       = 'or'
                    predicates = @(
                        $topIds | ForEach-Object {
                            [ordered]@{
                                dimension = 'userId'
                                operator  = 'matches'
                                value     = $_
                            }
                        }
                    )
                }
            )
        }

        try {
            $conversations = @(Invoke-GenesysDataset `
                -Dataset 'analytics-conversation-details' `
                -DatasetParameters @{ Body = $convJobBody })
        } catch {
            Write-Warning "Conversation-details job failed: $($_.Exception.Message). Continuing without conversation join."
            $conversations = @()
        }

        $convsByUser = @{}
        foreach ($conv in $conversations) {
            $convId = Get-PropertyValue $conv 'conversationId'
            if (-not $convId) { continue }
            foreach ($p in @(Get-PropertyValue $conv 'participants')) {
                if ($null -eq $p) { continue }
                $uid = Get-PropertyValue $p 'userId'
                if (-not $uid) { continue }
                if (-not $convsByUser.ContainsKey($uid)) {
                    $convsByUser[$uid] = New-Object System.Collections.Generic.HashSet[string]
                }
                [void]$convsByUser[$uid].Add($convId)
            }
        }
        foreach ($u in $sorted) {
            if ($convsByUser.ContainsKey($u.UserId)) {
                $u.ConversationIds = @($convsByUser[$u.UserId] | Sort-Object)
            }
        }
    }

    if ($sorted.Count -gt 0) {
        Write-Verbose 'Enriching with name/division'
        try {
            $roster = @(Get-GenesysAgent -State ACTIVE)
            $nameById = @{}
            foreach ($a in $roster) {
                $id = Get-PropertyValue $a 'id'
                if ($id) { $nameById[$id] = $a }
            }
            foreach ($u in $sorted) {
                if ($nameById.ContainsKey($u.UserId)) {
                    $info = $nameById[$u.UserId]
                    $u.Name     = Get-PropertyValue $info 'name'
                    $div        = Get-PropertyValue $info 'division'
                    $u.Division = if ($div) { Get-PropertyValue $div 'name' } else { $null }
                }
            }
        } catch {
            Write-Warning "Name/division enrichment failed: $($_.Exception.Message)"
        }
    }

    $flaggedCount = @($sorted | Where-Object { $_.Flag -eq 'Consistent' }).Count

    $report = [pscustomobject]@{
        GeneratedAt           = (Get-Date).ToUniversalTime().ToString('o')
        Window                = [pscustomobject]@{
            Since = $sinceUtc.ToString('o')
            Until = $untilUtc.ToString('o')
            Days  = [math]::Round(($untilUtc - $sinceUtc).TotalDays, 2)
        }
        Threshold             = [pscustomobject]@{
            MinTransitionsPerDay = $MinTransitionsPerDay
        }
        UsersWithNotResponding = $sorted.Count
        UsersFlaggedConsistent = $flaggedCount
        TotalNrTransitions     = (@($sorted | Measure-Object TransitionCount -Sum).Sum)
        TopUsers               = @($sorted | Select-Object -First $TopN |
            Select-Object UserId, Name, Division,
                          TransitionCount, ActiveDays, TransitionsPerActiveDay,
                          TotalNrSeconds, AvgNrSeconds, Flag,
                          DailyBreakdown, ConversationIds)
        AllUsers               = @($sorted)
    }

    if ($OutputPath) {
        $report | ConvertTo-Json -Depth 12 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Verbose "Report saved: $OutputPath"
    }

    if ($PassThru -or -not $OutputPath) { $report }
}

#endregion

# ---------------------------------------------------------------------------
#region Dataset Coverage Audit
# ---------------------------------------------------------------------------

function Test-GenesysOpsDatasetCoverage {
    <#
    .SYNOPSIS
        Audits Genesys.Ops public cmdlets against the active Genesys.Core catalog.
    .DESCRIPTION
        Inspects the built-in cmdlet-to-dataset map and validates each dataset
        key against the active catalog.  Returns one record per public cmdlet:

            FunctionName     — Cmdlet name
            DatasetKey       — Primary dataset key (or comma-separated for composites)
            IsInCatalog      — $true when the dataset key exists in the catalog
            HasRequiredBody  — $true when the catalog entry has a defaultBody
            InvocationRisk   — Low | Medium | High | Unsupported
            Notes            — Explanation of risk/status

        InvocationRisk:
            Low         — Dataset in catalog, key validated, no body concerns
            Medium      — Dataset in catalog but relies on default body params
            High        — Dataset unvalidated or relies heavily on catalog defaults
            Unsupported — Dataset key not found in the catalog

        Composite functions that call multiple child cmdlets are listed with
        DatasetKey = '(composite)' and reflect the aggregate risk.

    .PARAMETER CatalogPath
        Override the catalog path.  Defaults to the path resolved during
        Connect-GenesysCloud.
    .EXAMPLE
        Test-GenesysOpsDatasetCoverage | Format-Table FunctionName, IsInCatalog, InvocationRisk
    .EXAMPLE
        # Show only unsupported or high-risk functions
        Test-GenesysOpsDatasetCoverage | Where-Object { $_.InvocationRisk -in @('Unsupported','High') } |
            Format-Table FunctionName, DatasetKey, Notes
    #>
    [CmdletBinding()]
    param(
        [string] $CatalogPath
    )

    # Cmdlet-to-dataset map.  Composite functions are listed with DatasetKey = '(composite)'.
    $map = @(
        @{ Function = 'Get-GenesysOrganization';            Dataset = 'organization.get.organization.details' }
        @{ Function = 'Get-GenesysOrganizationLimit';       Dataset = 'organization.get.organization.limits' }
        @{ Function = 'Get-GenesysDivision';                Dataset = 'authorization.get.all.divisions' }
        @{ Function = 'Get-GenesysAgent';                   Dataset = 'users' }
        @{ Function = 'Get-GenesysAgentPresence';           Dataset = 'users.get.bulk.user.presences.genesys.cloud' }
        @{ Function = 'Find-GenesysUser';                   Dataset = 'users.search.users.by.name.or.email' }
        @{ Function = 'Get-GenesysUserWithDivision';        Dataset = 'users.division.analysis.get.users.with.division.info' }
        @{ Function = 'Get-GenesysSystemPresence';          Dataset = 'presence.get.system.presence.definitions' }
        @{ Function = 'Get-GenesysCustomPresence';          Dataset = 'presence.get.organization.presence.definitions' }
        @{ Function = 'Get-GenesysQueue';                   Dataset = 'routing-queues' }
        @{ Function = 'Get-GenesysRoutingSkill';            Dataset = 'routing.get.all.routing.skills' }
        @{ Function = 'Get-GenesysWrapupCode';              Dataset = 'routing.get.all.wrapup.codes' }
        @{ Function = 'Get-GenesysLanguage';                Dataset = 'routing.get.all.languages' }
        @{ Function = 'Get-GenesysActiveConversation';      Dataset = 'conversations.get.active.conversations' }
        @{ Function = 'Get-GenesysActiveCall';              Dataset = 'conversations.get.active.calls' }
        @{ Function = 'Get-GenesysActiveChat';              Dataset = 'conversations.get.active.chats' }
        @{ Function = 'Get-GenesysActiveEmail';             Dataset = 'conversations.get.active.emails' }
        @{ Function = 'Get-GenesysActiveCallback';          Dataset = 'conversations.get.active.callbacks' }
        @{ Function = 'Get-GenesysCallHistory';             Dataset = 'conversations.get.call.history' }
        @{ Function = 'Get-GenesysConversationDetail';      Dataset = 'analytics-conversation-details' }
        @{ Function = 'Get-GenesysAuditEvent';              Dataset = 'audit-logs' }
        @{ Function = 'Get-GenesysApiUsage';                Dataset = 'usage.get.api.usage.organization.summary' }
        @{ Function = 'Get-GenesysApiUsageByClient';        Dataset = 'usage.get.api.usage.by.client' }
        @{ Function = 'Get-GenesysApiUsageByUser';          Dataset = 'usage.get.api.usage.by.user' }
        @{ Function = 'Get-GenesysNotificationTopic';       Dataset = 'notifications.get.available.notification.topics' }
        @{ Function = 'Get-GenesysNotificationSubscription';Dataset = 'notifications.get.notification.subscriptions' }
        @{ Function = 'Get-GenesysOAuthClient';             Dataset = 'oauth.get.clients' }
        @{ Function = 'Get-GenesysOAuthAuthorization';      Dataset = 'oauth.get.authorizations' }
        @{ Function = 'Get-GenesysRateLimitEvent';          Dataset = 'analytics.query.rate.limit.aggregates' }
        @{ Function = 'Get-GenesysOutboundCampaign';        Dataset = 'outbound.get.campaigns' }
        @{ Function = 'Get-GenesysOutboundContactList';     Dataset = 'outbound.get.contact.lists' }
        @{ Function = 'Get-GenesysOutboundEvent';           Dataset = 'outbound.get.events' }
        @{ Function = 'Get-GenesysMessagingCampaign';       Dataset = 'outbound.get.messaging.campaigns' }
        @{ Function = 'Get-GenesysFlow';                    Dataset = 'flows.get.all.flows' }
        @{ Function = 'Get-GenesysFlowOutcome';             Dataset = 'flows.get.flow.outcomes' }
        @{ Function = 'Get-GenesysFlowMilestone';           Dataset = 'flows.get.flow.milestones' }
        @{ Function = 'Get-GenesysFlowAggregate';           Dataset = 'analytics.query.flow.aggregates.execution.metrics' }
        @{ Function = 'Get-GenesysFlowObservation';         Dataset = 'analytics.query.flow.observations'; DefaultBody = $true }
        @{ Function = 'Get-GenesysAgentPerformance';        Dataset = 'analytics.query.user.aggregates.performance.metrics'; DefaultBody = $true }
        @{ Function = 'Get-GenesysUserActivity';            Dataset = 'analytics.query.user.details.activity.report' }
        @{ Function = 'Get-GenesysAgentVoiceQuality';       Dataset = 'analytics-conversation-details' }
        @{ Function = 'Get-GenesysEdge';                    Dataset = 'telephony.get.edges' }
        @{ Function = 'Get-GenesysTrunk';                   Dataset = 'telephony.get.trunks' }
        @{ Function = 'Get-GenesysTrunkMetrics';            Dataset = 'telephony.get.trunk.metrics.summary' }
        @{ Function = 'Get-GenesysStation';                 Dataset = 'stations.get.stations' }
        @{ Function = 'Get-GenesysQueueAbandonRate';        Dataset = 'analytics.query.conversation.aggregates.abandon.metrics'; DefaultBody = $true }
        @{ Function = 'Get-GenesysQueueServiceLevel';       Dataset = 'analytics.query.queue.aggregates.service.level'; DefaultBody = $true }
        @{ Function = 'Get-GenesysTransferAnalysis';        Dataset = 'analytics.query.conversation.aggregates.transfer.metrics'; DefaultBody = $true }
        @{ Function = 'Get-GenesysWrapupDistribution';      Dataset = 'analytics.query.conversation.aggregates.wrapup.distribution'; DefaultBody = $true }
        @{ Function = 'Get-GenesysDigitalChannelVolume';    Dataset = 'analytics.query.conversation.aggregates.digital.channels'; DefaultBody = $true }
        @{ Function = 'Export-GenesysMonthlyChannelVolume'; Dataset = 'analytics.query.conversation.aggregates.queue.performance'; DefaultBody = $true }
        @{ Function = 'Get-GenesysEvaluation';              Dataset = 'quality.get.evaluations.query' }
        @{ Function = 'Get-GenesysSurvey';                  Dataset = 'quality.get.surveys' }
        @{ Function = 'Get-GenesysAlertingRule';            Dataset = 'alerting.get.rules' }
        @{ Function = 'Get-GenesysAlert';                   Dataset = 'alerting.get.alerts' }
        @{ Function = 'Get-GenesysAgentLoginActivity';      Dataset = 'analytics.query.user.aggregates.login.activity'; DefaultBody = $true }
        @{ Function = 'Get-GenesysQueueObservation';        Dataset = 'analytics.query.queue.observations.real.time.stats'; DefaultBody = $true }
        @{ Function = 'Get-GenesysUserObservation';         Dataset = 'analytics.query.user.observations.real.time.status'; DefaultBody = $true }
        @{ Function = 'Get-GenesysQueuePerformance';        Dataset = 'analytics.query.conversation.aggregates.queue.performance'; DefaultBody = $true }
        @{ Function = 'Get-GenesysWorkforceManagementUnit'; Dataset = 'workforce.get.management.units' }
        @{ Function = 'Get-GenesysJourneyActionMap';        Dataset = 'journey.get.action.maps' }
        # Composite/enriched functions
        @{ Function = 'Get-GenesysContactCentreStatus';        Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Invoke-GenesysDailyHealthReport';       Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Export-GenesysConfigurationSnapshot';   Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysEdgeHealthSnapshot';         Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysQueueAbandonRate';           Dataset = 'analytics.query.conversation.aggregates.abandon.metrics'; DefaultBody = $true }
        @{ Function = 'Get-GenesysSentimentTrend';             Dataset = 'analytics-conversation-details' }
        @{ Function = 'Get-GenesysLongHandleConversation';     Dataset = 'analytics-conversation-details' }
        @{ Function = 'Get-GenesysRepeatCaller';               Dataset = 'analytics-conversation-details' }
        @{ Function = 'Get-GenesysWebRtcDisconnectSummary';    Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysConversationLatencyTrend';   Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysAgentAcwAnomaly';            Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysChangeAuditFeed';            Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysAbandonRateDashboard';       Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysQueueHealthSnapshot';        Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysAgentQualitySnapshot';       Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Invoke-GenesysOperationsReport';        Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysPeakHourLoad';               Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysOutboundCampaignPerformance';Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysFlowOutcomeKpiCorrelation';  Dataset = '(composite)'; Composite = $true }
        @{ Function = 'Get-GenesysAgentInvestigation';         Dataset = '(composite)'; Composite = $true }
    )

    # Resolve catalog
    $resolvedCatalog = $CatalogPath
    if (-not $resolvedCatalog -and $script:GC.CatalogPath) { $resolvedCatalog = $script:GC.CatalogPath }
    if (-not $resolvedCatalog) {
        $candidates = @(
            (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json'),
            (Join-Path $PSScriptRoot '../../catalog/genesys-core.catalog.json'),
            (Join-Path $PSScriptRoot '../catalog/genesys.catalog.json'),
            (Join-Path $PSScriptRoot '../catalog/genesys-core.catalog.json')
        )
        $resolvedCatalog = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    $catalogDatasets = $null
    if ($resolvedCatalog -and (Test-Path $resolvedCatalog)) {
        try {
            $catalogObj     = Get-Content -Path $resolvedCatalog -Raw | ConvertFrom-Json
            $catalogDatasets = Get-PropertyValue $catalogObj 'datasets'
        } catch {
            Write-Warning "Test-GenesysOpsDatasetCoverage: Could not load catalog '$($resolvedCatalog)' — $($_)"
        }
    } else {
        Write-Warning "Test-GenesysOpsDatasetCoverage: No catalog found. Set -CatalogPath or call Connect-GenesysCloud first."
    }

    # De-duplicate by function name (take first entry)
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $deduped = foreach ($entry in $map) {
        if ($seen.Add($entry.Function)) { $entry }
    }

    foreach ($entry in $deduped) {
        $dataset     = [string]$entry.Dataset
        $isComposite = $entry.ContainsKey('Composite') -and $entry.Composite
        $hasBody     = $entry.ContainsKey('DefaultBody') -and $entry.DefaultBody

        if ($isComposite) {
            [PSCustomObject]@{
                FunctionName    = $entry.Function
                DatasetKey      = '(composite)'
                IsInCatalog     = $true   # Composites call child functions; no direct dataset
                HasRequiredBody = $false
                InvocationRisk  = 'Low'
                Notes           = 'Composite function — calls multiple child cmdlets. Risk depends on children.'
            }
            continue
        }

        $inCatalog = $false
        if ($catalogDatasets) {
            $inCatalog = [bool]($catalogDatasets.PSObject.Properties[$dataset])
        }

        $risk = if (-not $catalogDatasets) {
            'Medium'
        } elseif (-not $inCatalog) {
            'Unsupported'
        } elseif ($hasBody) {
            'Medium'
        } else {
            'Low'
        }

        $notes = switch ($risk) {
            'Unsupported' { "Dataset key '$($dataset)' not found in catalog '$($resolvedCatalog)'." }
            'Medium'      { if ($hasBody) { "Uses catalog default request body — add parameters or body override for operational use." } else { "Catalog not loaded; risk indeterminate." } }
            'Low'         { "Dataset key validated in catalog." }
            default       { '' }
        }

        [PSCustomObject]@{
            FunctionName    = $entry.Function
            DatasetKey      = $dataset
            IsInCatalog     = $inCatalog
            HasRequiredBody = $hasBody
            InvocationRisk  = $risk
            Notes           = $notes
        }
    }
}

#endregion

$script:GcOpsComposerVersion = '1.0.0'

function ConvertTo-IsoUtcTimestamp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Value
    )

    if ($Value -is [DateTime]) {
        return ([DateTime]$Value).ToUniversalTime().ToString('o')
    }

    $parsed = [DateTime]::Parse([string]$Value)
    return $parsed.ToUniversalTime().ToString('o')
}

function Resolve-DatasetValidationStatus {
    [CmdletBinding()]
    param(
        [string] $DatasetKey,
        [object] $Catalog
    )

    if (-not $Catalog) { return 'unvalidated' }

    $datasetsProp = $Catalog.PSObject.Properties | Where-Object { $_.Name -eq 'datasets' } | Select-Object -First 1
    if (-not $datasetsProp) { return 'unvalidated' }

    $dataset = $datasetsProp.Value.PSObject.Properties | Where-Object { $_.Name -eq $DatasetKey } | Select-Object -First 1
    if (-not $dataset) { return 'unvalidated' }

    $statusProp = $dataset.Value.PSObject.Properties | Where-Object { $_.Name -eq 'validationStatus' } | Select-Object -First 1
    if ($statusProp -and $statusProp.Value) { return [string]$statusProp.Value }
    return 'unvalidated'
}

function Resolve-DatasetRedactionProfileName {
    [CmdletBinding()]
    param(
        [string] $DatasetKey,
        [object] $Catalog
    )

    if (-not $Catalog) { return $null }
    $datasetsProp = $Catalog.PSObject.Properties | Where-Object { $_.Name -eq 'datasets' } | Select-Object -First 1
    if (-not $datasetsProp) { return $null }
    $dataset = $datasetsProp.Value.PSObject.Properties | Where-Object { $_.Name -eq $DatasetKey } | Select-Object -First 1
    if (-not $dataset) { return $null }
    $rpProp = $dataset.Value.PSObject.Properties | Where-Object { $_.Name -eq 'redactionProfile' } | Select-Object -First 1
    if ($rpProp -and $rpProp.Value) { return [string]$rpProp.Value }
    return $null
}

function Get-OpsCatalog {
    [CmdletBinding()]
    param()

    $catalogPath = $script:GC.CatalogPath
    if (-not $catalogPath) {
        $candidate = Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json'
        if (Test-Path $candidate) { $catalogPath = (Resolve-Path $candidate).Path }
    }
    if (-not $catalogPath -or -not (Test-Path $catalogPath)) { return $null }
    return (Get-Content -Path $catalogPath -Raw | ConvertFrom-Json)
}

function Sort-RecordsForDeterminism {
    [CmdletBinding()]
    param(
        [object[]] $Records,
        [string] $SortKey
    )

    if (-not $Records -or $Records.Count -eq 0) { return @() }
    if (-not $SortKey) { $SortKey = 'id' }

    $keyed = foreach ($r in $Records) {
        $value = $null
        $cursor = $r
        foreach ($segment in $SortKey -split '\.') {
            if ($null -eq $cursor) { break }
            $prop = $cursor.PSObject.Properties | Where-Object { $_.Name -eq $segment } | Select-Object -First 1
            if (-not $prop) { $cursor = $null; break }
            $cursor = $prop.Value
        }
        $value = if ($null -ne $cursor) { [string]$cursor } else { '' }
        [pscustomobject]@{ key = $value; record = $r }
    }

    $sorted = $keyed | Sort-Object -Property key -Stable
    return @($sorted | ForEach-Object { $_.record })
}

function Invoke-Investigation {
    <#
    .SYNOPSIS
        Internal composer — runs a sequence of catalog datasets and emits the
        standard investigation run-artifact set.
    .DESCRIPTION
        Implements the Investigation Manifest Contract defined in
        docs/INVESTIGATIONS.md. Designed to be called by a public flagship
        cmdlet (e.g. Get-GenesysAgentInvestigation) which has already resolved
        any name-based subject input to a stable identifier.

        For tests, pass -DatasetInvoker to inject synthetic step records and
        bypass live API calls. The injected scriptblock receives the step
        descriptor and returns a hashtable with keys: records, runId, status,
        errorMessage.
    .PARAMETER DatasetInvoker
        Optional scriptblock that overrides the default Invoke-GenesysDataset
        path. Receives ($Step, $Subject, $Window) and must return:
            @{ records = @(...); runId = '<id>'; status = 'ok'|'failed'|'skipped'; errorMessage = $null|<text> }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z][a-z0-9-]*$')]
        [string] $InvestigationKey,

        [Parameter(Mandatory)]
        [ValidateSet('agent', 'conversation', 'queue')]
        [string] $SubjectType,

        [Parameter(Mandatory)]
        [hashtable] $Subject,

        [hashtable] $Window,

        [Parameter(Mandatory)]
        [object[]] $Steps,

        [string] $OutputRoot = 'out',

        [string] $RunId,

        [scriptblock] $DatasetInvoker
    )

    if (-not $RunId) { $RunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') }

    $resolvedOutputRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
        [System.IO.Path]::GetFullPath($OutputRoot)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $OutputRoot))
    }

    $runFolder    = Join-Path $resolvedOutputRoot (Join-Path $InvestigationKey $RunId)
    $dataFolder   = Join-Path $runFolder 'data'
    $manifestPath = Join-Path $runFolder 'manifest.json'
    $eventsPath   = Join-Path $runFolder 'events.jsonl'
    $summaryPath  = Join-Path $runFolder 'summary.json'

    New-Item -Path $dataFolder -ItemType Directory -Force | Out-Null

    $catalog = Get-OpsCatalog
    $startedAt = [DateTime]::UtcNow
    $startedAtIso = $startedAt.ToString('o')

    $writeEvent = {
        param($type, $payload)
        $entry = [ordered]@{
            timestampUtc     = [DateTime]::UtcNow.ToString('o')
            investigationKey = $InvestigationKey
            runId            = $RunId
            eventType        = $type
            payload          = $payload
        }
        Add-Content -Path $eventsPath -Value ($entry | ConvertTo-Json -Depth 100 -Compress) -Encoding utf8
    }

    & $writeEvent 'investigation.started' @{
        subjectType = $SubjectType
        subjectId   = $Subject.SubjectId
        window      = $Window
        stepCount   = $Steps.Count
    }

    $summarySections = [ordered]@{}
    $datasetsInvoked = New-Object System.Collections.Generic.List[object]
    $joinPlan        = New-Object System.Collections.Generic.List[object]
    $dataPaths       = [ordered]@{}
    $datasetProfiles = [ordered]@{}
    $aborted         = $false
    $abortReason     = $null

    foreach ($step in $Steps) {
        $stepName    = [string]$step['Name']
        $isDerived   = $step.ContainsKey('RecordDeriver') -and $step['RecordDeriver']
        $datasetKey  = if ($isDerived) { '(derived)' } else { [string]$step['DatasetKey'] }
        $emitAs      = if ($step.ContainsKey('EmitAs') -and $step['EmitAs']) { [string]$step['EmitAs'] } else { $stepName }
        $required    = if ($step.ContainsKey('Required')) { [bool]$step['Required'] } else { $true }
        $joinKind    = if ($step.ContainsKey('JoinKind') -and $step['JoinKind']) { [string]$step['JoinKind'] } else { 'Inner' }
        $sortKey     = if ($step.ContainsKey('SortKey') -and $step['SortKey']) { [string]$step['SortKey'] } else { 'id' }
        $joinOn      = if ($step.ContainsKey('JoinOn')) { $step['JoinOn'] } else { $null }

        if (-not $isDerived) {
            $datasetProfiles[$datasetKey] = Resolve-DatasetRedactionProfileName -DatasetKey $datasetKey -Catalog $catalog
        }

        $leftSource = $null
        if ($joinOn -and $joinOn.ContainsKey('Source')) {
            $leftSource = $joinOn.Source
        } elseif ($joinOn -and $joinOn.ContainsKey('Left') -and $joinOn.Left) {
            $leftSource = 'identity'
        }

        $joinPlan.Add([ordered]@{
            stepName   = $stepName
            leftSource = $leftSource
            leftKey    = if ($joinOn -and $joinOn.ContainsKey('Left')) { $joinOn.Left } else { $null }
            rightKey   = if ($joinOn -and $joinOn.ContainsKey('Right')) { $joinOn.Right } else { $null }
            joinKind   = $joinKind
        }) | Out-Null

        & $writeEvent 'step.started' @{
            stepName   = $stepName
            datasetKey = $datasetKey
            required   = $required
        }

        $resolvedDatasetParameters = $null
        if (-not $isDerived -and $step.ContainsKey('Parameters') -and $step['Parameters']) {
            $parameterSource = $step['Parameters']
            if ($parameterSource -is [scriptblock]) {
                $resolvedDatasetParameters = & $parameterSource $Subject $summarySections $Window
            } else {
                $resolvedDatasetParameters = $parameterSource
            }
        }

        $stepResult = $null
        if ($isDerived) {
            try {
                $derived = @(& $step['RecordDeriver'] $summarySections $Subject)
                $stepResult = @{ records = $derived; runId = $null; status = 'ok'; errorMessage = $null }
            } catch {
                $stepResult = @{ records = @(); runId = $null; status = 'failed'; errorMessage = $_.Exception.Message }
            }
        } else {
            try {
                if ($DatasetInvoker) {
                    $stepForInvoker = @{}
                    foreach ($key in $step.Keys) { $stepForInvoker[$key] = $step[$key] }
                    if ($null -ne $resolvedDatasetParameters) {
                        $stepForInvoker['DatasetParameters'] = $resolvedDatasetParameters
                    }
                    $stepResult = & $DatasetInvoker $stepForInvoker $Subject $Window
                } else {
                    $invokeArgs = @{ Dataset = $datasetKey }
                    if ($null -ne $resolvedDatasetParameters) {
                        $invokeArgs['DatasetParameters'] = $resolvedDatasetParameters
                    }
                    $records = Invoke-GenesysDataset @invokeArgs
                    $stepResult = @{
                        records      = @($records)
                        runId        = $null
                        status       = 'ok'
                        errorMessage = $null
                    }
                }
            } catch {
                $stepResult = @{
                    records      = @()
                    runId        = $null
                    status       = 'failed'
                    errorMessage = $_.Exception.Message
                }
            }
        }

        $records = if ($stepResult -and $stepResult.records) { @($stepResult.records) } else { @() }

        if ($step.ContainsKey('SubjectFilter') -and $step['SubjectFilter'] -and $stepResult.status -eq 'ok') {
            $filter = [scriptblock]$step['SubjectFilter']
            $records = @($records | Where-Object { & $filter $_ $Subject })
        }

        $records = @(Sort-RecordsForDeterminism -Records $records -SortKey $sortKey)

        $stepDataPath = Join-Path $dataFolder ("$stepName.jsonl")
        if ($records.Count -gt 0) {
            $records | ForEach-Object {
                Add-Content -Path $stepDataPath -Value ($_ | ConvertTo-Json -Depth 100 -Compress) -Encoding utf8
            }
        } else {
            New-Item -Path $stepDataPath -ItemType File -Force | Out-Null
        }
        $dataPaths[$stepName] = $stepDataPath

        $summarySections[$emitAs] = $records

        if ($step.ContainsKey('SubjectUpdater') -and $step['SubjectUpdater']) {
            $updates = & $step['SubjectUpdater'] $records $Subject
            if ($updates) {
                foreach ($k in $updates.Keys) { $Subject[$k] = $updates[$k] }
            }
        }

        $datasetsInvoked.Add([ordered]@{
            stepName         = $stepName
            datasetKey       = $datasetKey
            runId            = $stepResult.runId
            validationStatus = (Resolve-DatasetValidationStatus -DatasetKey $datasetKey -Catalog $catalog)
            recordCount      = $records.Count
            required         = $required
            status           = $stepResult.status
            errorMessage     = $stepResult.errorMessage
        }) | Out-Null

        if ($stepResult.status -eq 'failed') {
            & $writeEvent 'step.failed' @{
                stepName     = $stepName
                datasetKey   = $datasetKey
                errorMessage = $stepResult.errorMessage
            }
            if ($required) {
                $aborted = $true
                $abortReason = "Required step '$stepName' (dataset '$datasetKey') failed: $($stepResult.errorMessage)"
                break
            }
        } else {
            & $writeEvent 'step.finished' @{
                stepName    = $stepName
                datasetKey  = $datasetKey
                recordCount = $records.Count
            }
        }
    }

    $finishedAt = [DateTime]::UtcNow
    $finishedAtIso = $finishedAt.ToString('o')

    $sinceIso = $null
    $untilIso = $null
    if ($Window -and $Window.ContainsKey('Since') -and $null -ne $Window.Since) {
        $sinceIso = ConvertTo-IsoUtcTimestamp $Window.Since
    }
    if ($Window -and $Window.ContainsKey('Until') -and $null -ne $Window.Until) {
        $untilIso = ConvertTo-IsoUtcTimestamp $Window.Until
    }

    $windowObj = [ordered]@{ since = $sinceIso; until = $untilIso }
    $redactionObj = [ordered]@{ datasets = $datasetProfiles; composerOverrides = @() }
    $artifactsObj = [ordered]@{
        manifestPath = $manifestPath
        eventsPath   = $eventsPath
        summaryPath  = $summaryPath
        dataPaths    = $dataPaths
    }

    $datasetsInvokedArray = $datasetsInvoked.ToArray()
    $joinPlanArray = $joinPlan.ToArray()
    $subjectIdString = [string]$Subject['SubjectId']

    $manifest = [ordered]@{}
    $manifest['investigationKey'] = $InvestigationKey
    $manifest['runId']            = $RunId
    $manifest['subjectType']      = $SubjectType
    $manifest['subjectId']        = $subjectIdString
    $manifest['window']           = $windowObj
    $manifest['datasetsInvoked']  = $datasetsInvokedArray
    $manifest['joinPlan']         = $joinPlanArray
    $manifest['redactionProfile'] = $redactionObj
    $manifest['outputArtifacts']  = $artifactsObj
    $manifest['startedAt']        = $startedAtIso
    $manifest['finishedAt']       = $finishedAtIso
    $manifest['composerVersion']  = $script:GcOpsComposerVersion

    Set-Content -Path $manifestPath -Value ($manifest | ConvertTo-Json -Depth 100) -Encoding utf8

    # Schema validation — fail the run on shape violation.
    $schemaPath = Join-Path $PSScriptRoot '../../catalog/schema/investigation.manifest.schema.json'
    if (Test-Path $schemaPath) {
        $schemaRaw = Get-Content -Path $schemaPath -Raw
        $manifestRaw = Get-Content -Path $manifestPath -Raw
        try {
            $valid = $manifestRaw | Test-Json -Schema $schemaRaw -ErrorAction Stop
        } catch {
            $valid = $false
            & $writeEvent 'manifest.schema.invalid' @{ message = $_.Exception.Message }
        }
        if (-not $valid) {
            throw "Investigation manifest failed schema validation: $manifestPath"
        }
    }

    if ($aborted) {
        & $writeEvent 'investigation.failed' @{ reason = $abortReason }
        throw $abortReason
    }

    # Custom serializer — every summary section is an array, even when it has 0 or 1 records.
    # ConvertTo-Json unwraps single-element arrays in PS5.1, so build the JSON manually.
    $sectionParts = foreach ($entry in $summarySections.GetEnumerator()) {
        $arr = @($entry.Value)
        if ($arr.Count -eq 0) {
            $body = '[]'
        } elseif ($arr.Count -eq 1) {
            $body = '[' + ($arr[0] | ConvertTo-Json -Depth 100 -Compress) + ']'
        } else {
            $body = $arr | ConvertTo-Json -Depth 100 -Compress
        }
        '"' + $entry.Key + '":' + $body
    }
    $summaryJson = '{' + ($sectionParts -join ',') + '}'
    Set-Content -Path $summaryPath -Value $summaryJson -Encoding utf8

    $totalRecords = 0
    foreach ($entry in $datasetsInvoked) { $totalRecords += [int]$entry['recordCount'] }
    & $writeEvent 'investigation.finished' @{ recordCount = $totalRecords }

    return [pscustomobject]@{
        InvestigationKey = $InvestigationKey
        RunId            = $RunId
        RunFolder        = $runFolder
        ManifestPath     = $manifestPath
        EventsPath       = $eventsPath
        SummaryPath      = $summaryPath
        DataFolder       = $dataFolder
        Sections         = $summarySections
    }
}

function Get-GenesysAgentInvestigationStepDefinition {
    <#
    .SYNOPSIS
        Returns the ordered step descriptors for the Agent Investigation flagship.
    .DESCRIPTION
        Centralised so the public cmdlet and integration tests share the same
        contract.  Designed for the investigation composer — each step is a
        hashtable consumed by Invoke-Investigation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $UserId,

        [datetime] $Since,

        [datetime] $Until
    )

    $idMatchesUser  = { param($r, $s) ($r.PSObject.Properties['id']     -and $r.id     -eq $s['UserId']) }
    $userIdMatches  = { param($r, $s) ($r.PSObject.Properties['userId'] -and $r.userId -eq $s['UserId']) }
    $participantMatchesUser = { param($r, $s)
        if (-not $r.PSObject.Properties['participants']) { return $false }
        return @($r.participants | Where-Object { $_.userId -eq $s['UserId'] }).Count -gt 0
    }
    $singleUserRouteParameters = {
        param($subject, $sections, $window)
        @{ Query = @{ userId = [string]$subject['UserId'] } }
    }
    $singleUserPresenceParameters = {
        param($subject, $sections, $window)
        @{ Query = @{ id = [string]$subject['UserId'] } }
    }
    $deriveDivisionFromIdentity = {
        param($sections, $subject)

        $agent = @($sections['agent'] | Select-Object -First 1)
        if ($agent.Count -eq 0) { return @() }

        $divisionProp = $agent[0].PSObject.Properties['division']
        if (-not $divisionProp -or -not $divisionProp.Value) { return @() }

        [pscustomobject]@{
            id       = [string]$subject['UserId']
            userId   = [string]$subject['UserId']
            division = $divisionProp.Value
        }
    }
    $userDetailsActivityParameters = {
        param($subject, $sections, $window)

        $sinceIso = ConvertTo-IsoUtcTimestamp $window['Since']
        $untilIso = ConvertTo-IsoUtcTimestamp $window['Until']
        @{
            Body = [ordered]@{
                interval    = "$sinceIso/$untilIso"
                order       = 'asc'
                orderBy     = 'userId'
                paging      = [ordered]@{ pageSize = 100; pageNumber = 1 }
                userFilters = @(
                    [ordered]@{
                        type       = 'or'
                        predicates = @(
                            [ordered]@{
                                type      = 'dimension'
                                dimension = 'userId'
                                operator  = 'matches'
                                value     = [string]$subject['UserId']
                            }
                        )
                    }
                )
            }
        }
    }
    $conversationDetailsParameters = {
        param($subject, $sections, $window)

        $sinceIso = ConvertTo-IsoUtcTimestamp $window['Since']
        $untilIso = ConvertTo-IsoUtcTimestamp $window['Until']
        @{
            Body = [ordered]@{
                interval       = "$sinceIso/$untilIso"
                order          = 'asc'
                orderBy        = 'conversationStart'
                paging         = [ordered]@{ pageSize = 100; pageNumber = 1 }
                segmentFilters = @(
                    [ordered]@{
                        type       = 'or'
                        predicates = @(
                            [ordered]@{
                                type      = 'dimension'
                                dimension = 'userId'
                                operator  = 'matches'
                                value     = [string]$subject['UserId']
                            }
                        )
                    }
                )
            }
        }
    }
    $auditAccountChangeParameters = {
        param($subject, $sections, $window)
        @{
            StartUtc    = ConvertTo-IsoUtcTimestamp $window['Since']
            EndUtc      = ConvertTo-IsoUtcTimestamp $window['Until']
            EntityTypes = @('User')
            EntityIds   = @([string]$subject['UserId'])
        }
    }

    @(
        @{
            Name          = 'identity'
            DatasetKey    = 'users.get.user.details.with.full.expansion'
            Parameters    = $singleUserRouteParameters
            SubjectFilter = $idMatchesUser
            EmitAs        = 'agent'
            Required      = $true
            JoinKind      = 'Seed'
            JoinOn        = @{ Left = $null; Right = 'id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'division'
            RecordDeriver = $deriveDivisionFromIdentity
            EmitAs        = 'division'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'userId'
        }
        @{
            Name          = 'skills'
            DatasetKey    = 'users.get.user.routing.skills'
            Parameters    = $singleUserRouteParameters
            EmitAs        = 'skills'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'id'
        }
        @{
            Name          = 'queues'
            DatasetKey    = 'users.get.user.queue.memberships'
            Parameters    = $singleUserRouteParameters
            EmitAs        = 'queues'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'id'
        }
        @{
            Name          = 'presence'
            DatasetKey    = 'users.get.bulk.user.presences'
            Parameters    = $singleUserPresenceParameters
            SubjectFilter = $userIdMatches
            EmitAs        = 'presence'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'userId'
        }
        @{
            Name          = 'routingStatus'
            DatasetKey    = 'users.get.agent.current.routing.status'
            Parameters    = $singleUserRouteParameters
            SubjectFilter = $userIdMatches
            EmitAs        = 'routingStatus'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'userId'
        }
        @{
            Name          = 'utilization'
            DatasetKey    = 'routing.get.user.utilization'
            Parameters    = $singleUserRouteParameters
            SubjectFilter = $userIdMatches
            EmitAs        = 'utilization'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'userId'
        }
        @{
            Name          = 'activity'
            DatasetKey    = 'analytics.query.user.details.activity.report'
            Parameters    = $userDetailsActivityParameters
            SubjectFilter = $userIdMatches
            EmitAs        = 'activity'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'userId'
        }
        @{
            Name          = 'activeConversations'
            DatasetKey    = 'users.get.agent.active.conversations'
            Parameters    = $singleUserRouteParameters
            EmitAs        = 'activeConversations'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'id'
        }
        @{
            Name          = 'conversations'
            DatasetKey    = 'analytics-conversation-details-query'
            Parameters    = $conversationDetailsParameters
            SubjectFilter = $participantMatchesUser
            EmitAs        = 'conversations'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'participants.userId' }
            SortKey       = 'conversationId'
        }
        @{
            Name          = 'auditAccountChanges'
            DatasetKey    = 'audit-logs'
            Parameters    = $auditAccountChangeParameters
            EmitAs        = 'auditAccountChanges'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'entity.id' }
            SortKey       = 'timestamp'
        }
    )
}

function Get-GenesysAgentInvestigation {
    <#
    .SYNOPSIS
        Run the Agent Investigation flagship — joins identity, derived division,
        skills, queue memberships, presence, current routing status,
        utilization, activity, active conversations, conversations, and audit
        account changes for one agent.
    .DESCRIPTION
        Composes scoped catalog datasets via Invoke-Investigation and emits the
        standard run-artifact set under out/agent-investigation/<runId>/.

        Resolves -UserName to a UserId before invoking the composer. Use
        -DatasetInvoker (a scriptblock returning fixture data) to drive
        determinism / integration tests without touching the live API.
    .PARAMETER UserId
        Resolved Genesys user GUID. Required if -UserName is not supplied.
    .PARAMETER UserName
        Display-name fragment passed to Find-GenesysUser. The first match is
        used; ambiguous matches throw.
    .PARAMETER Since
        Inclusive start of the investigation window. Defaults to 7 days ago.
    .PARAMETER Until
        Exclusive end of the investigation window. Defaults to now.
    .PARAMETER OutputRoot
        Root for the run-artifact tree. Defaults to 'out'.
    .PARAMETER RunId
        Override the auto-generated run identifier. Use only for deterministic
        tests; do not set in production.
    .PARAMETER DatasetInvoker
        Test seam — see Invoke-Investigation. When supplied, no live API calls
        are made and Connect-GenesysCloud is not required.
    .EXAMPLE
        Get-GenesysAgentInvestigation -UserId 'a1b2c3...' -Since (Get-Date).AddDays(-7)
    .EXAMPLE
        Get-GenesysAgentInvestigation -UserName 'Jane Doe'
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string] $UserId,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string] $UserName,

        [datetime] $Since,
        [datetime] $Until,
        [string]   $OutputRoot = 'out',
        [string]   $RunId,
        [scriptblock] $DatasetInvoker
    )

    if (-not $Until) { $Until = Get-Date }
    if (-not $Since) { $Since = $Until.AddDays(-7) }

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        if (-not $DatasetInvoker) { Assert-GenesysConnected }
        $matches = @(Find-GenesysUser -Query $UserName)
        if ($matches.Count -eq 0) { throw "No Genesys user matched '$UserName'." }
        if ($matches.Count -gt 1) {
            $names = ($matches | ForEach-Object { "$($_.name) <$($_.email)>" }) -join '; '
            throw "Ambiguous user name '$UserName' — $($matches.Count) matches: $names"
        }
        $UserId = $matches[0].id
    }

    if (-not $DatasetInvoker) { Assert-GenesysConnected }

    $steps = Get-GenesysAgentInvestigationStepDefinition -UserId $UserId -Since $Since -Until $Until

    Invoke-Investigation `
        -InvestigationKey 'agent-investigation' `
        -SubjectType      'agent' `
        -Subject          @{ SubjectId = $UserId; UserId = $UserId } `
        -Window           @{ Since = $Since; Until = $Until } `
        -Steps            $steps `
        -OutputRoot       $OutputRoot `
        -RunId            $RunId `
        -DatasetInvoker   $DatasetInvoker
}

function Get-GenesysConversationInvestigationStepDefinition {
    <#
    .SYNOPSIS
        Returns the ordered step descriptors for the Conversation Investigation flagship.
    .DESCRIPTION
        Centralised so the public cmdlet and integration tests share the same
        contract.  Designed for the investigation composer — each step is a
        hashtable consumed by Invoke-Investigation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConversationId
    )

    $isTargetConversation = { param($r, $s)
        $cid = $r.PSObject.Properties['conversationId']
        if (-not $cid) { $cid = $r.PSObject.Properties['id'] }
        return $cid -and [string]$cid.Value -eq $s.ConversationId
    }
    $isParticipantById = { param($r, $s)
        if (-not $s.ContainsKey('ParticipantUserIds')) { return $false }
        $pid = $r.PSObject.Properties['id']
        return $pid -and ([string]$pid.Value -in $s.ParticipantUserIds)
    }
    $isConversationEvaluation = { param($r, $s)
        $conv = $r.PSObject.Properties['conversation']
        if (-not $conv) { return $false }
        $cid = $conv.Value.PSObject.Properties['id']
        return $cid -and [string]$cid.Value -eq $s.ConversationId
    }

    $deriveParticipants = {
        param($sections, $subject)
        $conversations = @($sections['conversation'])
        if (-not $conversations -or $conversations.Count -eq 0) { return @() }
        $seen   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($conv in $conversations) {
            $partsProp = $conv.PSObject.Properties['participants']
            if (-not $partsProp) { continue }
            foreach ($p in @($partsProp.Value)) {
                $uidProp = $p.PSObject.Properties['userId']
                if (-not $uidProp -or -not $uidProp.Value) { continue }
                $uid = [string]$uidProp.Value
                if ($seen.Add($uid)) {
                    $purpose = $null
                    $purposeProp = $p.PSObject.Properties['purpose']
                    if ($purposeProp) { $purpose = [string]$purposeProp.Value }
                    $result.Add([pscustomobject]@{ userId = $uid; purpose = $purpose })
                }
            }
        }
        $result.ToArray()
    }
    $updateSubjectWithParticipants = {
        param($records, $subject)
        $ids = @($records | ForEach-Object { $_.userId } | Where-Object { $_ })
        @{ ParticipantUserIds = $ids }
    }
    $updateSubjectWithConversationWindow = {
        param($records, $subject)
        $conversation = @($records | Select-Object -First 1)
        if ($conversation.Count -eq 0) { return @{} }

        $start = $null
        foreach ($name in @('conversationStart', 'startTime', 'startTimeUtc', 'start')) {
            $prop = $conversation[0].PSObject.Properties[$name]
            if ($prop -and $prop.Value) { $start = $prop.Value; break }
        }

        $end = $null
        foreach ($name in @('conversationEnd', 'endTime', 'endTimeUtc', 'end')) {
            $prop = $conversation[0].PSObject.Properties[$name]
            if ($prop -and $prop.Value) { $end = $prop.Value; break }
        }

        if (-not $start) { throw "Conversation '$($subject.ConversationId)' did not include a start time required for analytics interval derivation." }
        if (-not $end) { $end = [DateTime]::UtcNow }

        $startUtc = ([DateTime]::Parse([string]$start)).ToUniversalTime()
        $endUtc = ([DateTime]::Parse([string]$end)).ToUniversalTime()
        if ($endUtc -le $startUtc) {
            $endUtc = $startUtc.AddSeconds(1)
        }

        @{
            ConversationStartUtc = $startUtc.ToString('o')
            ConversationEndUtc   = $endUtc.ToString('o')
            AnalyticsInterval    = "$($startUtc.ToString('o'))/$($endUtc.ToString('o'))"
        }
    }
    $conversationLookupParameters = {
        param($subject, $sections, $window)
        @{ Query = @{ conversationId = $subject.ConversationId } }
    }
    $analyticsConversationParameters = {
        param($subject, $sections, $window)
        if (-not $subject.ContainsKey('AnalyticsInterval') -or [string]::IsNullOrWhiteSpace([string]$subject.AnalyticsInterval)) {
            throw "Conversation '$($subject.ConversationId)' does not have a derived analytics interval. The conversation lookup step must run first."
        }

        @{
            ConversationId = $subject.ConversationId
            Interval       = $subject.AnalyticsInterval
        }
    }

    @(
        @{
            Name          = 'conversationLookup'
            DatasetKey    = 'conversations.get.specific.conversation.details'
            Parameters    = $conversationLookupParameters
            SubjectFilter = $isTargetConversation
            SubjectUpdater = $updateSubjectWithConversationWindow
            EmitAs        = 'conversationLookup'
            Required      = $true
            JoinKind      = 'Seed'
            JoinOn        = @{ Left = $null; Right = 'id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'conversation'
            DatasetKey    = 'analytics-conversation-details-query'
            Parameters    = $analyticsConversationParameters
            SubjectFilter = $isTargetConversation
            EmitAs        = 'conversation'
            Required      = $true
            JoinKind      = 'Seed'
            JoinOn        = @{ Left = $null; Right = 'conversationId' }
            SortKey       = 'conversationId'
        }
        @{
            Name           = 'participants'
            RecordDeriver  = $deriveParticipants
            SubjectUpdater = $updateSubjectWithParticipants
            EmitAs         = 'participants'
            Required       = $true
            JoinKind       = 'Seed'
            JoinOn         = @{ Left = $null; Right = 'userId' }
            SortKey        = 'userId'
        }
        @{
            Name          = 'agents'
            DatasetKey    = 'users'
            SubjectFilter = $isParticipantById
            EmitAs        = 'agents'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'participants.userId'; Right = 'id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'divisions'
            DatasetKey    = 'users.division.analysis.get.users.with.division.info'
            SubjectFilter = $isParticipantById
            EmitAs        = 'divisions'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'participants.userId'; Right = 'id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'skills'
            DatasetKey    = 'routing.get.all.routing.skills'
            EmitAs        = 'skills'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'participants.userId'; Right = $null }
            SortKey       = 'id'
        }
        @{
            Name          = 'recordings'
            DatasetKey    = 'conversations.get.recordings'
            Parameters    = @{ conversationId = $ConversationId }
            SubjectFilter = $isTargetConversation
            EmitAs        = 'recordings'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'conversation.conversationId'; Right = 'conversationId' }
            SortKey       = 'id'
        }
        @{
            Name          = 'evaluations'
            DatasetKey    = 'quality.get.evaluations.query'
            Parameters    = @{ conversationId = $ConversationId }
            SubjectFilter = $isConversationEvaluation
            EmitAs        = 'evaluations'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'conversation.conversationId'; Right = 'conversation.id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'surveys'
            DatasetKey    = 'quality.get.surveys'
            Parameters    = @{ conversationId = $ConversationId }
            SubjectFilter = $isTargetConversation
            EmitAs        = 'surveys'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'conversation.conversationId'; Right = 'conversationId' }
            SortKey       = 'id'
        }
    )
}

function Get-GenesysConversationInvestigation {
    <#
    .SYNOPSIS
        Run the Conversation Investigation flagship — joins conversation detail,
        participants, agent identities, divisions, skills, recordings,
        evaluations, and surveys for one conversation.
    .DESCRIPTION
        Composes nine steps (eight catalog datasets plus one derived participants
        step) via Invoke-Investigation and emits the standard run-artifact set
        under out/conversation-investigation/<runId>/.

        Use -DatasetInvoker (a scriptblock returning fixture data) to drive
        determinism / integration tests without touching the live API.
    .PARAMETER ConversationId
        Genesys conversation GUID to investigate.
    .PARAMETER OutputRoot
        Root for the run-artifact tree. Defaults to 'out'.
    .PARAMETER RunId
        Override the auto-generated run identifier. Use only for deterministic
        tests; do not set in production.
    .PARAMETER DatasetInvoker
        Test seam — see Invoke-Investigation. When supplied, no live API calls
        are made and Connect-GenesysCloud is not required.
    .EXAMPLE
        Get-GenesysConversationInvestigation -ConversationId 'a1b2c3...'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConversationId,

        [string]      $OutputRoot = 'out',
        [string]      $RunId,
        [scriptblock] $DatasetInvoker
    )

    if (-not $DatasetInvoker) { Assert-GenesysConnected }

    $steps = Get-GenesysConversationInvestigationStepDefinition -ConversationId $ConversationId

    Invoke-Investigation `
        -InvestigationKey 'conversation-investigation' `
        -SubjectType      'conversation' `
        -Subject          @{ SubjectId = $ConversationId; ConversationId = $ConversationId } `
        -Window           @{ Since = $null; Until = $null } `
        -Steps            $steps `
        -OutputRoot       $OutputRoot `
        -RunId            $RunId `
        -DatasetInvoker   $DatasetInvoker
}

function Get-GenesysOpsPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $InputObject,
        [Parameter(Mandatory)][string[]] $Names,
        [AllowNull()][object] $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($name in $Names) {
            if ($InputObject.Contains($name) -and $null -ne $InputObject[$name]) {
                return $InputObject[$name]
            }
        }
        return $Default
    }

    foreach ($name in $Names) {
        $prop = $InputObject.PSObject.Properties[$name]
        if ($prop -and $null -ne $prop.Value) {
            return $prop.Value
        }
    }

    return $Default
}

function ConvertTo-GenesysOpsText {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o') }
    if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [string]$Value
    }

    try {
        return ($Value | ConvertTo-Json -Depth 20 -Compress)
    } catch {
        return [string]$Value
    }
}

function ConvertTo-GenesysOpsUtcText {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o') }

    $text = ConvertTo-GenesysOpsText -Value $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    $parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed.ToUniversalTime().ToString('o')
    }

    return $text
}

function ConvertTo-GenesysOpsHtmlText {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    return [System.Net.WebUtility]::HtmlEncode((ConvertTo-GenesysOpsText -Value $Value))
}

function ConvertTo-GenesysOpsXmlText {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    return [System.Security.SecurityElement]::Escape((ConvertTo-GenesysOpsText -Value $Value))
}

function Import-GenesysOpsJsonLines {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path $Path)) { return @() }

    $records = [System.Collections.Generic.List[object]]::new()
    Get-Content -Path $Path | Where-Object { $_.Trim() } | ForEach-Object {
        $records.Add(($_ | ConvertFrom-Json)) | Out-Null
    }

    return $records.ToArray()
}

function Get-GenesysOpsSipHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory)][string[]] $Names
    )

    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $match = $Lines | Where-Object { $_ -match "^\s*$escaped\s*:" } | Select-Object -First 1
        if ($match) {
            return ($match -replace "^\s*$escaped\s*:\s*", '').Trim()
        }
    }

    return $null
}

function Get-GenesysOpsSipLineTimestamp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines)

    $patterns = @(
        '^\s*\[?(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[\.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?)\]?\s+',
        '^\s*\[?(?<timestamp>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:[\.,]\d+)?)\]?\s+'
    )

    foreach ($line in $Lines) {
        foreach ($pattern in $patterns) {
            if ($line -match $pattern) {
                $raw = $matches['timestamp']
                $normalized = $raw.Replace(',', '.')
                $parsed = [datetime]::MinValue
                $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
                if ([datetime]::TryParse($normalized, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
                    return [pscustomobject]@{
                        Raw = $raw
                        Utc = $parsed.ToUniversalTime().ToString('o')
                    }
                }
            }
        }
    }

    return $null
}

function Remove-GenesysOpsSipLineTimestamp {
    [CmdletBinding()]
    param([AllowNull()][string] $Line)

    if ($null -eq $Line) { return '' }

    $text = $Line.Trim()
    $patterns = @(
        '^\s*\[?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[\.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\]?\s+',
        '^\s*\[?\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:[\.,]\d+)?\]?\s+'
    )

    foreach ($pattern in $patterns) {
        $text = $text -replace $pattern, ''
    }

    return $text.Trim()
}

function Get-GenesysOpsSipStartLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines)

    $firstNonEmpty = $null
    foreach ($line in $Lines) {
        $candidate = Remove-GenesysOpsSipLineTimestamp -Line $line
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (-not $firstNonEmpty) { $firstNonEmpty = $candidate }
        if ($candidate -match '^SIP/2.0\s+\d{3}\s+' -or $candidate -match '^(INVITE|ACK|BYE|CANCEL|OPTIONS|REGISTER|PRACK|UPDATE|REFER|INFO|SUBSCRIBE|NOTIFY|MESSAGE)\s+') {
            return $candidate
        }
    }

    return $firstNonEmpty
}

function New-GenesysOpsApiUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [hashtable] $RouteValues,
        [hashtable] $Query
    )

    $base = $script:GC.BaseUri.TrimEnd('/')
    $resolvedPath = $Path
    if ($RouteValues) {
        foreach ($key in $RouteValues.Keys) {
            $resolvedPath = $resolvedPath.Replace("{$key}", [uri]::EscapeDataString([string]$RouteValues[$key]))
        }
    }

    $uriBuilder = [System.Text.StringBuilder]::new()
    [void]$uriBuilder.Append($base)
    if (-not $resolvedPath.StartsWith('/')) { [void]$uriBuilder.Append('/') }
    [void]$uriBuilder.Append($resolvedPath)

    if ($Query -and $Query.Count -gt 0) {
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($key in ($Query.Keys | Sort-Object)) {
            $value = $Query[$key]
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { continue }
            $parts.Add(('{0}={1}' -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$value))) | Out-Null
        }
        if ($parts.Count -gt 0) {
            [void]$uriBuilder.Append('?')
            [void]$uriBuilder.Append(($parts.ToArray() -join '&'))
        }
    }

    return $uriBuilder.ToString()
}

function Invoke-GenesysOpsApiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [hashtable] $RouteValues,
        [hashtable] $Query,
        [AllowNull()][object] $Body,
        [scriptblock] $ApiInvoker
    )

    $uri = New-GenesysOpsApiUri -Path $Path -RouteValues $RouteValues -Query $Query
    $bodyJson = $null
    if ($null -ne $Body) {
        $bodyJson = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 100 }
    }

    $request = [pscustomobject]@{
        Method  = $Method
        Uri     = $uri
        Path    = $Path
        Query   = $Query
        Body    = $bodyJson
        Headers = $script:GC.Headers
    }

    if ($ApiInvoker) {
        return & $ApiInvoker $request
    }

    Assert-GenesysConnected
    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $script:GC.Headers
        ErrorAction = 'Stop'
    }
    if ($null -ne $bodyJson) {
        $invokeParams['Body'] = $bodyJson
        $invokeParams['ContentType'] = 'application/json'
    }

    Invoke-RestMethod @invokeParams
}

function Get-GenesysOpsResponseRows {
    [CmdletBinding()]
    param([AllowNull()][object] $Response)

    if ($null -eq $Response) { return @() }
    foreach ($name in @('data', 'entities', 'results', 'items')) {
        $prop = $Response.PSObject.Properties[$name]
        if ($prop -and $null -ne $prop.Value) {
            return @($prop.Value)
        }
    }

    return @($Response)
}

function Save-GenesysOpsBinaryDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][string] $Path,
        [scriptblock] $DownloadInvoker
    )

    if ($DownloadInvoker) {
        $result = & $DownloadInvoker ([pscustomobject]@{ Uri = $Uri; Path = $Path })
        if ($result -is [byte[]]) {
            [System.IO.File]::WriteAllBytes($Path, $result)
            return
        }
        if ($result -is [string]) {
            [System.IO.File]::WriteAllText($Path, $result)
            return
        }
        if ($result -is [System.Array]) {
            $byteValues = @($result | Where-Object { $_ -is [byte] })
            if ($byteValues.Count -eq $result.Count) {
                [System.IO.File]::WriteAllBytes($Path, [byte[]]$byteValues)
                return
            }
        }
        if (Test-Path $Path) { return }
    }

    Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing -ErrorAction Stop | Out-Null
}

function ConvertFrom-GenesysOpsSipMetadata {
    [CmdletBinding()]
    param([object[]] $Rows)

    $index = 0
    foreach ($row in @($Rows)) {
        $index++
        $method = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('method'))
        $replyReason = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('replyReason', 'reason'))
        $responseCode = $null
        $responseText = $null
        if ($replyReason -match '^\s*(\d{3})\s*(.*)$') {
            $responseCode = $matches[1]
            $responseText = $matches[2].Trim()
        }

        $startLine = if (-not [string]::IsNullOrWhiteSpace($method)) {
            $method
        } elseif ($responseCode) {
            "SIP/2.0 $responseCode $responseText".Trim()
        } else {
            ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('msg', 'type'))
        }

        [pscustomobject]@{
            MessageIndex   = $index
            ObservedTimeUtc = ConvertTo-GenesysOpsUtcText (Get-GenesysOpsPropertyValue $row @('date'))
            RawTimestamp   = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('date'))
            MessageType    = if ($responseCode) { 'Response' } else { 'Metadata' }
            StartLine      = $startLine
            Method         = $method
            ResponseCode   = $responseCode
            ResponseText   = $responseText
            CallID         = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('callid', 'callId'))
            From           = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('fromUser'))
            To             = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('toUser'))
            Contact        = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('contactUser'))
            UserAgent      = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('userAgent'))
            CSeq           = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('cseq'))
            Via            = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('via1'))
            MediaIP        = ''
            AudioPort      = ''
            AudioCodecs    = ''
            MediaDirection = ''
            SourceIP       = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('sourceIp'))
            SourcePort     = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('sourcePort'))
            DestinationIP  = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('destinationIp'))
            DestinationPort = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('destinationPort'))
            CorrelationID  = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('correlationId'))
            ConversationId = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('conversationId'))
        }
    }
}

function Export-GenesysOpsConversationPcap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ConversationId,
        [Parameter(Mandatory)][string] $StartUtc,
        [Parameter(Mandatory)][string] $EndUtc,
        [Parameter(Mandatory)][string] $OutputDirectory,
        [Parameter(Mandatory)][string] $PackageName,
        [scriptblock] $ApiInvoker,
        [scriptblock] $DownloadInvoker,
        [int] $MaxSignedUrlPolls = 10,
        [int] $SignedUrlPollSeconds = 2
    )

    $query = @{
        conversationId = $ConversationId
        dateStart      = $StartUtc
        dateEnd        = $EndUtc
    }

    $metadataResponse = Invoke-GenesysOpsApiJson -Method GET -Path '/api/v2/telephony/siptraces' -Query $query -ApiInvoker $ApiInvoker
    $metadataRows = @(Get-GenesysOpsResponseRows -Response $metadataResponse)

    $downloadResponse = Invoke-GenesysOpsApiJson -Method POST -Path '/api/v2/telephony/siptraces/download' -Body $query -ApiInvoker $ApiInvoker
    $downloadId = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $downloadResponse @('downloadId', 'documentId', 'id'))
    $signedUrlResponse = $null
    $signedUrl = $null
    $pcapPath = $null

    if (-not [string]::IsNullOrWhiteSpace($downloadId)) {
        for ($attempt = 1; $attempt -le $MaxSignedUrlPolls; $attempt++) {
            $signedUrlResponse = Invoke-GenesysOpsApiJson -Method GET -Path '/api/v2/telephony/siptraces/download/{downloadId}' -RouteValues @{ downloadId = $downloadId } -ApiInvoker $ApiInvoker
            $signedUrl = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $signedUrlResponse @('url', 'downloadUrl', 'href'))
            if (-not [string]::IsNullOrWhiteSpace($signedUrl)) { break }
            if (-not $ApiInvoker -and $attempt -lt $MaxSignedUrlPolls) {
                Start-Sleep -Seconds $SignedUrlPollSeconds
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($signedUrl)) {
            $pcapPath = Join-Path $OutputDirectory "$PackageName.pcap"
            Save-GenesysOpsBinaryDownload -Uri $signedUrl -Path $pcapPath -DownloadInvoker $DownloadInvoker
        }
    }

    [pscustomobject]@{
        MetadataRows      = $metadataRows
        SipRows           = @(ConvertFrom-GenesysOpsSipMetadata -Rows $metadataRows)
        DownloadId        = $downloadId
        SignedUrlReceived = -not [string]::IsNullOrWhiteSpace($signedUrl)
        PcapPath          = $pcapPath
        Request           = [pscustomobject]$query
    }
}

function ConvertFrom-GenesysOpsSipTrace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path $Path)) {
        throw "SIP trace file not found: $Path"
    }

    $content = Get-Content -Path $Path -Raw
    $messages = @($content -split '(?:\r?\n){2,}' | Where-Object {
        $_ -match 'SIP/2.0|INVITE|ACK|BYE|CANCEL|OPTIONS|REGISTER|PRACK|UPDATE|REFER|INFO|SUBSCRIBE|NOTIFY|MESSAGE'
    })

    $index = 0
    foreach ($message in $messages) {
        $index++
        $lines = @($message -split '\r?\n')
        if ($lines.Count -eq 0) { continue }
        $startLine = Get-GenesysOpsSipStartLine -Lines $lines
        if ([string]::IsNullOrWhiteSpace($startLine)) { continue }
        $timestamp = Get-GenesysOpsSipLineTimestamp -Lines $lines

        $messageType = 'Unknown'
        $sipMethod = $null
        $responseCode = $null
        $responseText = $null

        if ($startLine -match '^SIP/2.0\s+(\d{3})\s+(.*)$') {
            $messageType = 'Response'
            $responseCode = $matches[1]
            $responseText = $matches[2]
        } elseif ($startLine -match '^(INVITE|ACK|BYE|CANCEL|OPTIONS|REGISTER|PRACK|UPDATE|REFER|INFO|SUBSCRIBE|NOTIFY|MESSAGE)\s+') {
            $messageType = 'Request'
            $sipMethod = $matches[1]
        }

        $connectionLine = $lines | Where-Object { $_ -match '^c=IN\s+IP[46]\s+(.+)$' } | Select-Object -First 1
        $audioLine = $lines | Where-Object { $_ -match '^m=audio\s+(\d+)\s+\S+\s+(.+)$' } | Select-Object -First 1
        $directionLine = $lines | Where-Object { $_ -match '^a=(sendrecv|sendonly|recvonly|inactive)$' } | Select-Object -First 1

        $mediaIp = $null
        $audioPort = $null
        $audioCodecs = $null
        $mediaDirection = $null

        if ($connectionLine -and $connectionLine -match '^c=IN\s+IP[46]\s+(.+)$') { $mediaIp = $matches[1].Trim() }
        if ($audioLine -and $audioLine -match '^m=audio\s+(\d+)\s+\S+\s+(.+)$') {
            $audioPort = $matches[1]
            $audioCodecs = $matches[2].Trim()
        }
        if ($directionLine -and $directionLine -match '^a=(sendrecv|sendonly|recvonly|inactive)$') { $mediaDirection = $matches[1] }

        [pscustomobject]@{
            MessageIndex   = $index
            ObservedTimeUtc = if ($timestamp) { $timestamp.Utc } else { $null }
            RawTimestamp   = if ($timestamp) { $timestamp.Raw } else { $null }
            MessageType    = $messageType
            StartLine      = $startLine
            Method         = $sipMethod
            ResponseCode   = $responseCode
            ResponseText   = $responseText
            CallID         = Get-GenesysOpsSipHeader -Lines $lines -Names @('Call-ID', 'i')
            From           = Get-GenesysOpsSipHeader -Lines $lines -Names @('From', 'f')
            To             = Get-GenesysOpsSipHeader -Lines $lines -Names @('To', 't')
            Contact        = Get-GenesysOpsSipHeader -Lines $lines -Names @('Contact', 'm')
            UserAgent      = Get-GenesysOpsSipHeader -Lines $lines -Names @('User-Agent', 'Server')
            CSeq           = Get-GenesysOpsSipHeader -Lines $lines -Names @('CSeq')
            Via            = Get-GenesysOpsSipHeader -Lines $lines -Names @('Via', 'v')
            MediaIP        = $mediaIp
            AudioPort      = $audioPort
            AudioCodecs    = $audioCodecs
            MediaDirection = $mediaDirection
        }
    }
}

function ConvertTo-GenesysConversationTimeline {
    [CmdletBinding()]
    param([object[]] $ConversationRecords)

    $rows = [System.Collections.Generic.List[object]]::new()
    $sequence = 0

    foreach ($conversation in @($ConversationRecords)) {
        $conversationId = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $conversation @('conversationId', 'id'))
        $conversationStart = Get-GenesysOpsPropertyValue $conversation @('conversationStart', 'startTime')
        $conversationEnd = Get-GenesysOpsPropertyValue $conversation @('conversationEnd', 'endTime')
        $mediaType = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $conversation @('mediaType'))

        if ($conversationStart) {
            $sequence++
            $rows.Add([pscustomobject]@{
                Sequence       = $sequence
                Source         = 'Conversation Detail'
                TimeUtc        = ConvertTo-GenesysOpsUtcText $conversationStart
                EventType      = 'conversation.start'
                Participant    = ''
                Purpose        = ''
                MediaType      = $mediaType
                Direction      = ''
                Queue          = ''
                DisconnectType = ''
                Detail         = "Conversation $conversationId started"
            }) | Out-Null
        }

        foreach ($participant in @(Get-GenesysOpsPropertyValue $conversation @('participants') @())) {
            $purpose = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $participant @('purpose'))
            $participantId = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $participant @('participantId', 'id', 'userId'))
            $participantName = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $participant @('participantName', 'name', 'userId'))
            if ([string]::IsNullOrWhiteSpace($participantName)) { $participantName = $participantId }

            foreach ($session in @(Get-GenesysOpsPropertyValue $participant @('sessions') @())) {
                $sessionMedia = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $session @('mediaType'))
                if ([string]::IsNullOrWhiteSpace($sessionMedia)) { $sessionMedia = $mediaType }
                $direction = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $session @('direction'))
                $ani = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $session @('ani'))
                $dnis = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $session @('dnis'))

                foreach ($segment in @(Get-GenesysOpsPropertyValue $session @('segments') @())) {
                    $sequence++
                    $segmentStart = Get-GenesysOpsPropertyValue $segment @('segmentStart', 'startTime')
                    $segmentEnd = Get-GenesysOpsPropertyValue $segment @('segmentEnd', 'endTime')
                    $segmentType = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $segment @('segmentType', 'type'))
                    $queueName = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $segment @('queueName', 'queueId'))
                    $disconnect = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $segment @('disconnectType'))
                    $wrapUp = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $segment @('wrapUpCode', 'wrapUpCodeName'))
                    $errorCode = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $segment @('errorCode'))

                    $detailParts = @()
                    if (-not [string]::IsNullOrWhiteSpace((ConvertTo-GenesysOpsText $segmentEnd))) { $detailParts += "end=$(ConvertTo-GenesysOpsUtcText $segmentEnd)" }
                    if (-not [string]::IsNullOrWhiteSpace($ani)) { $detailParts += "ani=$ani" }
                    if (-not [string]::IsNullOrWhiteSpace($dnis)) { $detailParts += "dnis=$dnis" }
                    if (-not [string]::IsNullOrWhiteSpace($wrapUp)) { $detailParts += "wrapUp=$wrapUp" }
                    if (-not [string]::IsNullOrWhiteSpace($errorCode)) { $detailParts += "error=$errorCode" }

                    $rows.Add([pscustomobject]@{
                        Sequence       = $sequence
                        Source         = 'Conversation Detail'
                        TimeUtc        = ConvertTo-GenesysOpsUtcText $segmentStart
                        EventType      = $segmentType
                        Participant    = $participantName
                        Purpose        = $purpose
                        MediaType      = $sessionMedia
                        Direction      = $direction
                        Queue          = $queueName
                        DisconnectType = $disconnect
                        Detail         = ($detailParts -join '; ')
                    }) | Out-Null
                }
            }
        }

        if ($conversationEnd) {
            $sequence++
            $rows.Add([pscustomobject]@{
                Sequence       = $sequence
                Source         = 'Conversation Detail'
                TimeUtc        = ConvertTo-GenesysOpsUtcText $conversationEnd
                EventType      = 'conversation.end'
                Participant    = ''
                Purpose        = ''
                MediaType      = $mediaType
                Direction      = ''
                Queue          = ''
                DisconnectType = ''
                Detail         = "Conversation $conversationId ended"
            }) | Out-Null
        }
    }

    return $rows.ToArray()
}

function ConvertTo-GenesysSipTimeline {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]] $SipRows,
        [int] $StartingSequence = 0
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $sequence = $StartingSequence

    foreach ($sip in @($SipRows)) {
        $sequence++
        $eventType = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $sip @('Method'))
        $responseCode = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $sip @('ResponseCode'))
        $responseText = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $sip @('ResponseText'))
        if ([string]::IsNullOrWhiteSpace($eventType)) {
            $eventType = if ([string]::IsNullOrWhiteSpace($responseCode)) { 'sip.message' } else { "SIP $responseCode" }
        }

        $detailParts = @()
        foreach ($name in @('StartLine', 'CallID', 'CSeq', 'UserAgent', 'MediaIP', 'AudioPort', 'MediaDirection', 'SourceIP', 'SourcePort', 'DestinationIP', 'DestinationPort', 'CorrelationID')) {
            $value = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $sip @($name))
            if (-not [string]::IsNullOrWhiteSpace($value)) { $detailParts += "$name=$value" }
        }
        if (-not [string]::IsNullOrWhiteSpace($responseText)) { $detailParts += "ResponseText=$responseText" }

        $rows.Add([pscustomobject]@{
            Sequence       = $sequence
            Source         = 'SIP Trace'
            TimeUtc        = ConvertTo-GenesysOpsUtcText (Get-GenesysOpsPropertyValue $sip @('ObservedTimeUtc'))
            EventType      = $eventType
            Participant    = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $sip @('From'))
            Purpose        = ''
            MediaType      = 'voice'
            Direction      = ''
            Queue          = ''
            DisconnectType = ''
            Detail         = ($detailParts -join '; ')
        }) | Out-Null
    }

    return $rows.ToArray()
}

function Sort-GenesysConversationPackageTimeline {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]] $Rows)

    $sortableRows = [System.Collections.Generic.List[object]]::new()
    $originalIndex = 0
    foreach ($row in @($Rows)) {
        $originalIndex++
        $timeText = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('TimeUtc'))
        $parsed = [datetime]::MinValue
        $hasTime = $false
        $sortTime = [datetime]::MaxValue
        if (-not [string]::IsNullOrWhiteSpace($timeText)) {
            $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
            if ([datetime]::TryParse($timeText, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
                $hasTime = $true
                $sortTime = $parsed.ToUniversalTime()
            }
        }

        $sortableRows.Add([pscustomobject]@{
            Row           = $row
            HasTime       = $hasTime
            SortTime      = $sortTime
            OriginalIndex = $originalIndex
        }) | Out-Null
    }

    $sequence = 0
    foreach ($entry in @($sortableRows | Sort-Object -Property @{ Expression = 'HasTime'; Descending = $true }, SortTime, OriginalIndex)) {
        $sequence++
        $row = $entry.Row
        [pscustomobject]@{
            Sequence       = $sequence
            Source         = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('Source'))
            TimeUtc        = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('TimeUtc'))
            EventType      = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('EventType'))
            Participant    = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('Participant'))
            Purpose        = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('Purpose'))
            MediaType      = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('MediaType'))
            Direction      = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('Direction'))
            Queue          = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('Queue'))
            DisconnectType = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('DisconnectType'))
            Detail         = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $row @('Detail'))
        }
    }
}

function New-GenesysConversationPackageFindings {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]] $TimelineRows,
        [AllowEmptyCollection()][object[]] $SipRows,
        [AllowEmptyCollection()][object[]] $RecordingRows,
        [AllowEmptyCollection()][object[]] $EvaluationRows
    )

    $findings = [System.Collections.Generic.List[object]]::new()

    foreach ($row in @($TimelineRows | Where-Object { -not [string]::IsNullOrWhiteSpace((ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $_ @('DisconnectType')))) })) {
        $findings.Add([pscustomobject]@{
            Severity = 'Info'
            Source   = 'Conversation Detail'
            Finding  = 'Disconnect marker present'
            Evidence = "Sequence $($row.Sequence): $($row.Participant) $($row.DisconnectType)"
        }) | Out-Null
    }

    foreach ($sip in @($SipRows)) {
        $codeText = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $sip @('ResponseCode'))
        $code = 0
        if ([int]::TryParse($codeText, [ref]$code) -and $code -ge 400) {
            $findings.Add([pscustomobject]@{
                Severity = if ($code -ge 500) { 'High' } else { 'Medium' }
                Source   = 'SIP Trace'
                Finding  = "SIP error response $code"
                Evidence = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $sip @('StartLine'))
            }) | Out-Null
        }
    }

    if (@($RecordingRows).Count -eq 0) {
        $findings.Add([pscustomobject]@{
            Severity = 'Info'
            Source   = 'Recordings'
            Finding  = 'No recordings returned by the investigation'
            Evidence = 'Recordings section is empty'
        }) | Out-Null
    }

    if (@($EvaluationRows).Count -eq 0) {
        $findings.Add([pscustomobject]@{
            Severity = 'Info'
            Source   = 'Evaluations'
            Finding  = 'No quality evaluations returned by the investigation'
            Evidence = 'Evaluations section is empty'
        }) | Out-Null
    }

    return $findings.ToArray()
}

function Export-GenesysOpsRowsCsv {
    [CmdletBinding()]
    param(
        [object[]] $Rows,
        [Parameter(Mandatory)][string] $Path
    )

    $rowsArray = @($Rows)
    if ($rowsArray.Count -eq 0) {
        [pscustomobject]@{ Message = 'No records' } | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        return
    }

    $normalizedRows = foreach ($row in $rowsArray) {
        if ($null -eq $row) {
            [pscustomobject]@{ Value = '' }
            continue
        }

        $properties = @($row.PSObject.Properties)
        if ($properties.Count -eq 0) {
            [pscustomobject]@{ Value = (ConvertTo-GenesysOpsText -Value $row) }
            continue
        }

        $normalized = [ordered]@{}
        foreach ($property in $properties) {
            $normalized[$property.Name] = ConvertTo-GenesysOpsText -Value $property.Value
        }

        [pscustomobject]$normalized
    }

    $normalizedRows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function ConvertTo-GenesysExcelColumnName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int] $Index)

    $name = ''
    $value = $Index
    while ($value -gt 0) {
        $mod = ($value - 1) % 26
        $name = [char](65 + $mod) + $name
        $value = [math]::Floor(($value - $mod) / 26)
    }
    return $name
}

function Add-GenesysZipTextEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Zip,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Content
    )

    $entry = $Zip.CreateEntry($Name)
    $stream = $entry.Open()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }
}

function ConvertTo-GenesysWorksheetXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Rows
    )

    $rowsArray = @($Rows)
    if ($rowsArray.Count -eq 0) {
        $rowsArray = @([pscustomobject]@{ Message = 'No records' })
    }

    $columns = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $rowsArray) {
        foreach ($prop in $row.PSObject.Properties) {
            if (-not $columns.Contains($prop.Name)) { $columns.Add($prop.Name) | Out-Null }
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
    [void]$sb.Append('<row r="1">')
    for ($c = 0; $c -lt $columns.Count; $c++) {
        $cellRef = "$(ConvertTo-GenesysExcelColumnName -Index ($c + 1))1"
        [void]$sb.Append("<c r=`"$cellRef`" t=`"inlineStr`"><is><t>")
        [void]$sb.Append((ConvertTo-GenesysOpsXmlText $columns[$c]))
        [void]$sb.Append('</t></is></c>')
    }
    [void]$sb.Append('</row>')

    $r = 1
    foreach ($row in $rowsArray) {
        $r++
        [void]$sb.Append("<row r=`"$r`">")
        for ($c = 0; $c -lt $columns.Count; $c++) {
            $cellRef = "$(ConvertTo-GenesysExcelColumnName -Index ($c + 1))$r"
            $value = Get-GenesysOpsPropertyValue $row @($columns[$c])
            [void]$sb.Append("<c r=`"$cellRef`" t=`"inlineStr`"><is><t>")
            [void]$sb.Append((ConvertTo-GenesysOpsXmlText $value))
            [void]$sb.Append('</t></is></c>')
        }
        [void]$sb.Append('</row>')
    }

    [void]$sb.Append('</sheetData></worksheet>')
    return $sb.ToString()
}

function Export-GenesysOpsWorkbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][object[]] $Sheets
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    if (Test-Path $Path) { Remove-Item -Path $Path -Force }

    $fileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    $zip = [System.IO.Compression.ZipArchive]::new($fileStream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Add-GenesysZipTextEntry $zip '[Content_Types].xml' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>'
        Add-GenesysZipTextEntry $zip '_rels/.rels' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'

        $workbookSheets = [System.Text.StringBuilder]::new()
        $workbookRels = [System.Text.StringBuilder]::new()
        [void]$workbookRels.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')

        $sheetIndex = 0
        foreach ($sheet in @($Sheets)) {
            $sheetIndex++
            $sheetName = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $sheet @('Name'))
            if ([string]::IsNullOrWhiteSpace($sheetName)) { $sheetName = "Sheet$sheetIndex" }
            if ($sheetName.Length -gt 31) { $sheetName = $sheetName.Substring(0, 31) }
            $sheetRows = @(Get-GenesysOpsPropertyValue $sheet @('Rows') @())
            $escapedName = ConvertTo-GenesysOpsXmlText $sheetName
            [void]$workbookSheets.Append("<sheet name=`"$escapedName`" sheetId=`"$sheetIndex`" r:id=`"rId$sheetIndex`"/>")
            [void]$workbookRels.Append("<Relationship Id=`"rId$sheetIndex`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet`" Target=`"worksheets/sheet$sheetIndex.xml`"/>")
            Add-GenesysZipTextEntry $zip "xl/worksheets/sheet$sheetIndex.xml" (ConvertTo-GenesysWorksheetXml -Rows $sheetRows)
        }

        [void]$workbookRels.Append('</Relationships>')
        Add-GenesysZipTextEntry $zip 'xl/_rels/workbook.xml.rels' $workbookRels.ToString()
        Add-GenesysZipTextEntry $zip 'xl/workbook.xml' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' + $workbookSheets.ToString() + '</sheets></workbook>')
    } finally {
        $zip.Dispose()
        $fileStream.Dispose()
    }
}

function ConvertTo-GenesysHtmlTable {
    [CmdletBinding()]
    param(
        [object[]] $Rows,
        [int] $Limit = 100
    )

    $rowsArray = @($Rows | Select-Object -First $Limit)
    if ($rowsArray.Count -eq 0) { return '<p class="empty">No records.</p>' }

    $columns = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $rowsArray) {
        foreach ($prop in $row.PSObject.Properties) {
            if (-not $columns.Contains($prop.Name)) { $columns.Add($prop.Name) | Out-Null }
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<table><thead><tr>')
    foreach ($column in $columns) { [void]$sb.Append('<th>' + (ConvertTo-GenesysOpsHtmlText $column) + '</th>') }
    [void]$sb.Append('</tr></thead><tbody>')
    foreach ($row in $rowsArray) {
        [void]$sb.Append('<tr>')
        foreach ($column in $columns) {
            [void]$sb.Append('<td>' + (ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $row @($column))) + '</td>')
        }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table>')

    if (@($Rows).Count -gt $Limit) {
        [void]$sb.Append('<p class="empty">Showing first ' + $Limit + ' rows.</p>')
    }

    return $sb.ToString()
}

function New-GenesysConversationPackageHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Overview,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Findings,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $TimelineRows,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $SipRows,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $EvidenceRows
    )

    $generatedAt = ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $Overview @('GeneratedAtUtc'))
    $conversationId = ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $Overview @('ConversationId'))
    $runId = ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $Overview @('RunId'))
    $timelineCount = ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $Overview @('TimelineEvents'))
    $sipCount = ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $Overview @('SipMessages'))
    $recordingCount = ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $Overview @('Recordings'))
    $evaluationCount = ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $Overview @('Evaluations'))
    $pcapDownloaded = ConvertTo-GenesysOpsHtmlText (Get-GenesysOpsPropertyValue $Overview @('PcapDownloaded'))

    return @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Conversation Investigation Package - $conversationId</title>
<style>
:root { color-scheme: light; font-family: "Segoe UI", Arial, sans-serif; color: #17202a; background: #f7f8fa; }
body { margin: 0; }
header { background: #17202a; color: #fff; padding: 28px 36px; }
header h1 { margin: 0 0 8px; font-size: 28px; font-weight: 650; letter-spacing: 0; }
header p { margin: 0; color: #d7dee8; font-size: 14px; }
main { padding: 28px 36px 40px; }
section { margin: 0 0 28px; }
h2 { font-size: 18px; margin: 0 0 12px; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-top: 20px; }
.metric { background: #fff; border: 1px solid #dce2ea; border-radius: 8px; padding: 14px; }
.metric .label { color: #576372; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
.metric .value { font-size: 24px; margin-top: 4px; font-weight: 650; }
table { border-collapse: collapse; width: 100%; background: #fff; border: 1px solid #dce2ea; border-radius: 8px; overflow: hidden; font-size: 13px; }
th, td { border-bottom: 1px solid #e7ebf0; padding: 8px 10px; text-align: left; vertical-align: top; }
th { background: #eef2f6; color: #2a3542; font-size: 12px; }
tr:last-child td { border-bottom: 0; }
.empty { color: #6b7582; font-style: italic; }
.meta { color: #576372; font-size: 13px; margin-bottom: 18px; }
</style>
</head>
<body>
<header>
<h1>Conversation Investigation Package</h1>
<p>Conversation $conversationId | Run $runId | Generated $generatedAt</p>
</header>
<main>
<section>
<h2>Investigation Summary</h2>
<div class="grid">
<div class="metric"><div class="label">Timeline Events</div><div class="value">$timelineCount</div></div>
<div class="metric"><div class="label">SIP Messages</div><div class="value">$sipCount</div></div>
<div class="metric"><div class="label">Recordings</div><div class="value">$recordingCount</div></div>
<div class="metric"><div class="label">Evaluations</div><div class="value">$evaluationCount</div></div>
<div class="metric"><div class="label">PCAP Downloaded</div><div class="value">$pcapDownloaded</div></div>
</div>
</section>
<section>
<h2>Findings</h2>
$(ConvertTo-GenesysHtmlTable -Rows $Findings -Limit 50)
</section>
<section>
<h2>Conversation and SIP Timeline</h2>
<p class="meta">Rows combine conversation segments from Genesys analytics detail with parsed SIP trace messages when a trace file is supplied.</p>
$(ConvertTo-GenesysHtmlTable -Rows $TimelineRows -Limit 200)
</section>
<section>
<h2>SIP Trace Breakdown</h2>
$(ConvertTo-GenesysHtmlTable -Rows $SipRows -Limit 100)
</section>
<section>
<h2>Evidence Sections</h2>
$(ConvertTo-GenesysHtmlTable -Rows $EvidenceRows -Limit 200)
</section>
</main>
</body>
</html>
"@
}

function Export-GenesysConversationInvestigationPackage {
    <#
    .SYNOPSIS
        Builds an HTML/CSV/XLSX/JSON investigation package from a conversation investigation run.
    .DESCRIPTION
        Packages the artifact contract produced by Get-GenesysConversationInvestigation.
        Existing run folders can be packaged offline with -RunFolder. Passing
        -ConversationId runs the investigation first, then packages the output.

        When connected to Genesys Cloud, the package automatically queries SIP
        trace metadata and requests the matching PCAP download using the
        conversation start/end window. A SIP trace text file can still be
        attached with -SipTracePath for offline/manual packaging. The package
        includes SIP details, a combined conversation/SIP timeline, a findings
        table, an HTML report, CSV exports, a workbook, PCAP output when
        available, and metadata.
    .EXAMPLE
        $run = Get-GenesysConversationInvestigation -ConversationId '<conversation-guid>' -OutputRoot './out'
        Export-GenesysConversationInvestigationPackage -RunFolder $run.RunFolder -OutputDirectory './out/conversation-package' -Force
    .EXAMPLE
        Export-GenesysConversationInvestigationPackage -ConversationId '<conversation-guid>' -OutputRoot './out' -OutputDirectory './out/conversation-package' -Force
    #>
    [CmdletBinding(DefaultParameterSetName = 'FromRun')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'FromRun')]
        [string] $RunFolder,

        [Parameter(Mandatory, ParameterSetName = 'FromConversation')]
        [string] $ConversationId,

        [Parameter(ParameterSetName = 'FromConversation')]
        [string] $OutputRoot = 'out',

        [Parameter(ParameterSetName = 'FromConversation')]
        [string] $RunId,

        [Parameter(ParameterSetName = 'FromConversation')]
        [scriptblock] $DatasetInvoker,

        [string] $SipTracePath,
        [string] $OutputDirectory,
        [string] $PackageName = 'conversation-investigation',
        [scriptblock] $ApiInvoker,
        [scriptblock] $DownloadInvoker,
        [switch] $SkipPcapDownload,
        [switch] $Force
    )

    if ($PSCmdlet.ParameterSetName -eq 'FromConversation') {
        $run = Get-GenesysConversationInvestigation -ConversationId $ConversationId -OutputRoot $OutputRoot -RunId $RunId -DatasetInvoker $DatasetInvoker
        $RunFolder = $run.RunFolder
    }

    $resolvedRunFolder = (Resolve-Path -Path $RunFolder -ErrorAction Stop).Path
    $manifestPath = Join-Path $resolvedRunFolder 'manifest.json'
    $summaryPath = Join-Path $resolvedRunFolder 'summary.json'
    $dataFolder = Join-Path $resolvedRunFolder 'data'

    if (-not (Test-Path $manifestPath)) { throw "Conversation investigation manifest was not found: $manifestPath" }
    if (-not (Test-Path $summaryPath)) { throw "Conversation investigation summary was not found: $summaryPath" }
    if (-not (Test-Path $dataFolder)) { throw "Conversation investigation data folder was not found: $dataFolder" }

    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json

    if (-not $OutputDirectory) {
        $OutputDirectory = Join-Path $resolvedRunFolder 'package'
    }
    if ((Test-Path $OutputDirectory) -and -not $Force) {
        throw "Output directory already exists. Use -Force to overwrite package files: $OutputDirectory"
    }
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

    $conversationRows = @(Get-GenesysOpsPropertyValue $summary @('conversation') @())
    if ($conversationRows.Count -eq 0) {
        $conversationRows = @(Import-GenesysOpsJsonLines -Path (Join-Path $dataFolder 'conversation.jsonl'))
    }
    $participantRows = @(Get-GenesysOpsPropertyValue $summary @('participants') @())
    $agentRows = @(Get-GenesysOpsPropertyValue $summary @('agents') @())
    $divisionRows = @(Get-GenesysOpsPropertyValue $summary @('divisions') @())
    $skillRows = @(Get-GenesysOpsPropertyValue $summary @('skills') @())
    $recordingRows = @(Get-GenesysOpsPropertyValue $summary @('recordings') @())
    $evaluationRows = @(Get-GenesysOpsPropertyValue $summary @('evaluations') @())
    $conversationLookupRows = @(Get-GenesysOpsPropertyValue $summary @('conversationLookup') @())

    $conversationTimeline = @(ConvertTo-GenesysConversationTimeline -ConversationRecords $conversationRows)
    $sipRows = @()
    $pcapInfo = $null
    $pcapMetadataRows = @()
    $packageWarnings = [System.Collections.Generic.List[string]]::new()
    if ($SipTracePath) {
        $resolvedSipTracePath = (Resolve-Path -Path $SipTracePath -ErrorAction Stop).Path
        $sipRows = @(ConvertFrom-GenesysOpsSipTrace -Path $resolvedSipTracePath)
    } else {
        $resolvedSipTracePath = $null
    }

    $conversationIdValue = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('subjectId'))
    if ([string]::IsNullOrWhiteSpace($conversationIdValue) -and $conversationRows.Count -gt 0) {
        $conversationIdValue = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $conversationRows[0] @('conversationId', 'id'))
    }

    if (-not $SipTracePath -and -not $SkipPcapDownload) {
        $windowRecord = $null
        if ($conversationLookupRows.Count -gt 0) {
            $windowRecord = $conversationLookupRows[0]
        } elseif ($conversationRows.Count -gt 0) {
            $windowRecord = $conversationRows[0]
        }

        $pcapStartUtc = ConvertTo-GenesysOpsUtcText (Get-GenesysOpsPropertyValue $windowRecord @('conversationStart', 'startTime', 'startTimeUtc', 'start'))
        $pcapEndUtc = ConvertTo-GenesysOpsUtcText (Get-GenesysOpsPropertyValue $windowRecord @('conversationEnd', 'endTime', 'endTimeUtc', 'end'))

        if ([string]::IsNullOrWhiteSpace($pcapEndUtc) -and $conversationRows.Count -gt 0) {
            $pcapEndUtc = ConvertTo-GenesysOpsUtcText (Get-GenesysOpsPropertyValue $conversationRows[0] @('conversationEnd', 'endTime', 'endTimeUtc', 'end'))
        }

        if ([string]::IsNullOrWhiteSpace($conversationIdValue) -or [string]::IsNullOrWhiteSpace($pcapStartUtc) -or [string]::IsNullOrWhiteSpace($pcapEndUtc)) {
            $packageWarnings.Add('PCAP download skipped because conversationId, start time, or end time was not available in the run artifacts.') | Out-Null
        } elseif (-not $ApiInvoker -and -not $script:GC.Connected) {
            $packageWarnings.Add('PCAP download skipped because no Genesys Cloud session is connected. Run Connect-GenesysCloud or pass -SipTracePath for offline packaging.') | Out-Null
        } else {
            try {
                $pcapInfo = Export-GenesysOpsConversationPcap `
                    -ConversationId $conversationIdValue `
                    -StartUtc $pcapStartUtc `
                    -EndUtc $pcapEndUtc `
                    -OutputDirectory $OutputDirectory `
                    -PackageName $PackageName `
                    -ApiInvoker $ApiInvoker `
                    -DownloadInvoker $DownloadInvoker
                $pcapMetadataRows = @($pcapInfo.MetadataRows)
                $sipRows = @($pcapInfo.SipRows)
                if (-not $pcapInfo.PcapPath) {
                    $packageWarnings.Add('PCAP download was requested but no signed download URL was returned before polling completed.') | Out-Null
                }
            } catch {
                $packageWarnings.Add("PCAP download failed: $($_.Exception.Message)") | Out-Null
            }
        }
    }

    $sipTimeline = @(ConvertTo-GenesysSipTimeline -SipRows $sipRows -StartingSequence $conversationTimeline.Count)
    $combinedTimeline = @()
    $combinedTimeline += $conversationTimeline
    $combinedTimeline += $sipTimeline
    $combinedTimeline = @(Sort-GenesysConversationPackageTimeline -Rows $combinedTimeline)
    $findings = @(New-GenesysConversationPackageFindings -TimelineRows @($combinedTimeline | Where-Object { $_.Source -eq 'Conversation Detail' }) -SipRows $sipRows -RecordingRows $recordingRows -EvaluationRows $evaluationRows)

    $overview = [pscustomobject]@{
        GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
        Investigation  = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('investigationKey'))
        RunId          = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('runId'))
        ConversationId = $conversationIdValue
        Participants   = $participantRows.Count
        Agents         = $agentRows.Count
        Divisions      = $divisionRows.Count
        Skills         = $skillRows.Count
        Recordings     = $recordingRows.Count
        Evaluations    = $evaluationRows.Count
        TimelineEvents = $combinedTimeline.Count
        SipMessages    = $sipRows.Count
        PcapDownloaded = ($pcapInfo -and $pcapInfo.PcapPath -and (Test-Path $pcapInfo.PcapPath))
    }

    $evidenceRows = @(
        foreach ($pair in @(
            @{ Name = 'conversationLookup'; Rows = $conversationLookupRows },
            @{ Name = 'participants'; Rows = $participantRows },
            @{ Name = 'agents'; Rows = $agentRows },
            @{ Name = 'divisions'; Rows = $divisionRows },
            @{ Name = 'skills'; Rows = $skillRows },
            @{ Name = 'recordings'; Rows = $recordingRows },
            @{ Name = 'evaluations'; Rows = $evaluationRows }
        )) {
            foreach ($row in @($pair.Rows)) {
                [pscustomobject]@{
                    Section = $pair.Name
                    Json    = ConvertTo-GenesysOpsText $row
                }
            }
        }
    )

    $htmlPath = Join-Path $OutputDirectory "$PackageName.html"
    $timelineCsvPath = Join-Path $OutputDirectory "$PackageName.timeline.csv"
    $sipCsvPath = Join-Path $OutputDirectory "$PackageName.sip-trace.csv"
    $pcapMetadataCsvPath = Join-Path $OutputDirectory "$PackageName.pcap-metadata.csv"
    $findingsCsvPath = Join-Path $OutputDirectory "$PackageName.findings.csv"
    $workbookPath = Join-Path $OutputDirectory "$PackageName.xlsx"
    $packageJsonPath = Join-Path $OutputDirectory "$PackageName.package.json"

    Set-Content -Path $htmlPath -Value (New-GenesysConversationPackageHtml -Overview $overview -Findings $findings -TimelineRows $combinedTimeline -SipRows $sipRows -EvidenceRows $evidenceRows) -Encoding utf8
    Export-GenesysOpsRowsCsv -Rows $combinedTimeline -Path $timelineCsvPath
    Export-GenesysOpsRowsCsv -Rows $sipRows -Path $sipCsvPath
    if ($pcapMetadataRows.Count -gt 0) {
        Export-GenesysOpsRowsCsv -Rows $pcapMetadataRows -Path $pcapMetadataCsvPath
    }
    Export-GenesysOpsRowsCsv -Rows $findings -Path $findingsCsvPath
    $workbookSheets = @(
        [pscustomobject]@{ Name = 'Overview'; Rows = @($overview) }
        [pscustomobject]@{ Name = 'Findings'; Rows = $findings }
        [pscustomobject]@{ Name = 'Timeline'; Rows = $combinedTimeline }
        [pscustomobject]@{ Name = 'SIP Trace'; Rows = $sipRows }
        [pscustomobject]@{ Name = 'Evidence'; Rows = $evidenceRows }
    )
    if ($pcapMetadataRows.Count -gt 0) {
        $workbookSheets += [pscustomobject]@{ Name = 'PCAP Metadata'; Rows = $pcapMetadataRows }
    }
    Export-GenesysOpsWorkbook -Path $workbookPath -Sheets $workbookSheets

    $package = [ordered]@{
        packageType        = 'conversation-investigation'
        generatedAtUtc     = $overview.GeneratedAtUtc
        conversationId     = $overview.ConversationId
        runId              = $overview.RunId
        sourceSipTraceName = if ($resolvedSipTracePath) { Split-Path -Path $resolvedSipTracePath -Leaf } else { $null }
        pcapDownloadId     = if ($pcapInfo) { $pcapInfo.DownloadId } else { $null }
        warnings           = $packageWarnings.ToArray()
        counts             = [ordered]@{
            participants   = $overview.Participants
            agents         = $overview.Agents
            recordings     = $overview.Recordings
            evaluations    = $overview.Evaluations
            timelineEvents = $overview.TimelineEvents
            sipMessages    = $overview.SipMessages
            pcapMetadataRows = $pcapMetadataRows.Count
            findings       = $findings.Count
        }
        files              = [ordered]@{
            html        = (Split-Path -Path $htmlPath -Leaf)
            timelineCsv = (Split-Path -Path $timelineCsvPath -Leaf)
            sipTraceCsv = (Split-Path -Path $sipCsvPath -Leaf)
            pcapMetadataCsv = if (Test-Path $pcapMetadataCsvPath) { Split-Path -Path $pcapMetadataCsvPath -Leaf } else { $null }
            pcap        = if ($pcapInfo -and $pcapInfo.PcapPath -and (Test-Path $pcapInfo.PcapPath)) { Split-Path -Path $pcapInfo.PcapPath -Leaf } else { $null }
            findingsCsv = (Split-Path -Path $findingsCsvPath -Leaf)
            workbook    = (Split-Path -Path $workbookPath -Leaf)
            packageJson = (Split-Path -Path $packageJsonPath -Leaf)
        }
        overview           = $overview
        findings           = $findings
    }
    Set-Content -Path $packageJsonPath -Value ($package | ConvertTo-Json -Depth 100) -Encoding utf8

    return [pscustomobject]@{
        RunFolder       = $resolvedRunFolder
        OutputDirectory = (Resolve-Path -Path $OutputDirectory).Path
        HtmlPath        = $htmlPath
        TimelineCsvPath = $timelineCsvPath
        SipTraceCsvPath = $sipCsvPath
        FindingsCsvPath = $findingsCsvPath
        WorkbookPath    = $workbookPath
        PackageJsonPath = $packageJsonPath
        PcapPath        = if ($pcapInfo) { $pcapInfo.PcapPath } else { $null }
        PcapMetadataCsvPath = if (Test-Path $pcapMetadataCsvPath) { $pcapMetadataCsvPath } else { $null }
        Overview        = $overview
    }
}

function ConvertTo-GenesysMarkdownCellText {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    $text = ConvertTo-GenesysOpsText -Value $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '—' }
    $text = $text -replace '\|', '\|'
    $text = $text -replace '\r?\n', '<br/>'
    return $text
}

function ConvertTo-GenesysMarkdownTable {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]] $Rows,
        [int] $Limit = 25
    )

    $rowsArray = @($Rows)
    if ($rowsArray.Count -eq 0) { return '_No records._' }

    $rowsArray = @($rowsArray | Select-Object -First $Limit)
    $columns = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $rowsArray) {
        foreach ($prop in $row.PSObject.Properties) {
            if (-not $columns.Contains($prop.Name)) { $columns.Add($prop.Name) | Out-Null }
        }
    }
    if ($columns.Count -eq 0) { return '_No records._' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('| ' + (($columns.ToArray()) -join ' | ') + ' |')
    [void]$sb.AppendLine()
    [void]$sb.Append('| ' + ((@($columns.ToArray() | ForEach-Object { '---' })) -join ' | ') + ' |')

    foreach ($row in $rowsArray) {
        [void]$sb.AppendLine()
        $cells = foreach ($column in $columns) {
            ConvertTo-GenesysMarkdownCellText -Value (Get-GenesysOpsPropertyValue $row @($column))
        }
        [void]$sb.Append('| ' + (@($cells) -join ' | ') + ' |')
    }

    if (@($Rows).Count -gt $Limit) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine()
        [void]$sb.Append('_Showing first ' + $Limit + ' rows._')
    }

    return $sb.ToString()
}

function ConvertTo-GenesysInvestigationSectionRows {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @([pscustomobject]@{ Value = $Value })
    }
    if ($Value -is [System.Collections.IDictionary]) { return @([pscustomobject]$Value) }
    if ($Value -is [System.Collections.IEnumerable]) { return @($Value) }
    if ($Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0) { return @($Value) }
    return @([pscustomobject]@{ Value = $Value })
}

function ConvertTo-GenesysPackageName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Manifest,
        [string] $PackageName
    )

    $rawName = if (-not [string]::IsNullOrWhiteSpace($PackageName)) {
        $PackageName
    } else {
        '{0}-{1}-{2}' -f (ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $Manifest @('investigationKey'))), (ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $Manifest @('subjectId'))), (ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $Manifest @('runId')))
    }

    $sanitized = ($rawName -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($sanitized)) { return 'investigation-package' }
    return $sanitized
}

function Protect-GenesysDiagnosticText {
    [CmdletBinding()]
    param([AllowNull()][string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

    $redacted = $Text
    $redacted = [regex]::Replace($redacted, '(?im)authorization\s*:\s*[^\r\n]+', '[redacted-auth-header]')
    $redacted = [regex]::Replace($redacted, 'Bearer\s+[A-Za-z0-9._-]+', 'Bearer [redacted]')
    $redacted = [regex]::Replace($redacted, '(?i)(client_secret|api[_-]?key|token|secret|password)=([^&\s]+)', '$1=[redacted]')
    return $redacted
}

function Protect-GenesysDiagnosticValue {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (Protect-GenesysDiagnosticText -Text $Value) }
    if (
        $Value -is [bool] -or
        $Value -is [byte] -or
        $Value -is [int16] -or
        $Value -is [int32] -or
        $Value -is [int64] -or
        $Value -is [uint16] -or
        $Value -is [uint32] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal] -or
        $Value -is [datetime] -or
        $Value -is [guid]
    ) {
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            if ([string]$key -match '(?i)authorization|api[_-]?key|token|secret|password|client[_-]?secret') { continue }
            $result[[string]$key] = Protect-GenesysDiagnosticValue -Value $Value[$key]
        }
        return [pscustomobject]$result
    }
    $customProperties = @()
    if ($Value.PSObject) {
        $customProperties = @(
            $Value.PSObject.Properties |
                Where-Object {
                    $_.MemberType -eq 'NoteProperty' -or
                    $_.MemberType -eq 'AliasProperty' -or
                    $_.MemberType -eq 'ScriptProperty'
                }
        )
    }
    if ($customProperties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($prop in $customProperties) {
            if ($prop.Name -match '(?i)authorization|api[_-]?key|token|secret|password|client[_-]?secret') { continue }
            $result[$prop.Name] = Protect-GenesysDiagnosticValue -Value $prop.Value
        }
        return [pscustomobject]$result
    }
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { Protect-GenesysDiagnosticValue -Value $_ })
    }
    return $Value
}

function New-GenesysInvestigationPackageMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object] $Manifest,
        [Parameter(Mandatory)][object] $Overview,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $StepRows,
        [Parameter(Mandatory)] $Sections,
        [AllowEmptyCollection()][object[]] $Warnings = @()
    )

    $investigationKey = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $Manifest @('investigationKey'))
    $subjectType = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $Manifest @('subjectType'))
    $subjectId = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $Manifest @('subjectId'))
    $runId = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $Manifest @('runId'))
    $window = Get-GenesysOpsPropertyValue $Manifest @('window')
    $since = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $window @('since'))
    $until = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $window @('until'))
    $windowText = if ([string]::IsNullOrWhiteSpace($since) -and [string]::IsNullOrWhiteSpace($until)) {
        'Not scoped'
    } else {
        '``{0}`` -> ``{1}``' -f $(if ([string]::IsNullOrWhiteSpace($since)) { '—' } else { $since }), $(if ([string]::IsNullOrWhiteSpace($until)) { '—' } else { $until })
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Investigation Package')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("- Investigation: ``$investigationKey``")
    [void]$sb.AppendLine("- Subject: ``$subjectType`` / ``$subjectId``")
    [void]$sb.AppendLine("- Run ID: ``$runId``")
    [void]$sb.AppendLine("- Window: $windowText")
    [void]$sb.AppendLine("- Generated: ``$(ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $Overview @('GeneratedAtUtc')))``")

    if (@($Warnings).Count -gt 0) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('## Warnings')
        [void]$sb.AppendLine()
        foreach ($warning in @($Warnings)) {
            [void]$sb.AppendLine('- ' + (ConvertTo-GenesysOpsText $warning))
        }
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Overview')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine((ConvertTo-GenesysMarkdownTable -Rows @($Overview) -Limit 10))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Step status')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine((ConvertTo-GenesysMarkdownTable -Rows $StepRows -Limit 50))

    foreach ($section in $Sections.GetEnumerator()) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('## ' + $section.Key)
        [void]$sb.AppendLine()
        [void]$sb.AppendLine((ConvertTo-GenesysMarkdownTable -Rows @($section.Value) -Limit 25))
    }

    return $sb.ToString()
}

function Export-GenesysInvestigationPackage {
    <#
    .SYNOPSIS
        Builds a generic Markdown and Excel package from any investigation run folder.
    .DESCRIPTION
        Reads the standard investigation artifact contract from a run folder and
        writes a demo/operator-friendly package containing raw artifacts, per-section
        CSVs, an XLSX workbook, a Markdown summary, and a package manifest.
    .EXAMPLE
        Export-GenesysInvestigationPackage -RunFolder './out/agent-investigation/demo-run' -OutputDirectory './out/agent-package' -Force
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunFolder,

        [string] $OutputDirectory,

        [string] $PackageName,

        [switch] $Force
    )

    $resolvedRunFolder = (Resolve-Path -Path $RunFolder -ErrorAction Stop).Path
    $manifestPath = Join-Path $resolvedRunFolder 'manifest.json'
    $summaryPath = Join-Path $resolvedRunFolder 'summary.json'
    $eventsPath = Join-Path $resolvedRunFolder 'events.jsonl'
    $dataFolder = Join-Path $resolvedRunFolder 'data'

    if (-not (Test-Path $manifestPath)) { throw "Investigation manifest was not found: $manifestPath" }
    if (-not (Test-Path $summaryPath)) { throw "Investigation summary was not found: $summaryPath" }

    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json

    $resolvedPackageName = ConvertTo-GenesysPackageName -Manifest $manifest -PackageName $PackageName
    if (-not $OutputDirectory) {
        $OutputDirectory = Join-Path $resolvedRunFolder 'package'
    }

    if (Test-Path $OutputDirectory) {
        if (-not $Force) {
            throw "Output directory already exists. Use -Force to overwrite package files: $OutputDirectory"
        }
        Remove-Item -Path $OutputDirectory -Recurse -Force
    }
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

    Copy-Item -Path $manifestPath -Destination (Join-Path $OutputDirectory 'manifest.json') -Force
    Copy-Item -Path $summaryPath -Destination (Join-Path $OutputDirectory 'summary.json') -Force
    if (Test-Path $eventsPath) {
        Copy-Item -Path $eventsPath -Destination (Join-Path $OutputDirectory 'events.jsonl') -Force
    }
    if (Test-Path $dataFolder) {
        Copy-Item -Path $dataFolder -Destination (Join-Path $OutputDirectory 'data') -Recurse -Force
    }

    $sectionRows = [ordered]@{}
    foreach ($prop in $summary.PSObject.Properties) {
        $sectionRows[$prop.Name] = @(ConvertTo-GenesysInvestigationSectionRows -Value $prop.Value)
    }

    $stepRows = @(
        foreach ($step in @(Get-GenesysOpsPropertyValue $manifest @('datasetsInvoked') @())) {
            [pscustomobject]@{
                StepName         = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('stepName'))
                DatasetKey       = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('datasetKey'))
                ValidationStatus = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('validationStatus'))
                RecordCount      = Get-GenesysOpsPropertyValue $step @('recordCount') 0
                Required         = Get-GenesysOpsPropertyValue $step @('required') $false
                Status           = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('status'))
                ErrorMessage     = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('errorMessage'))
            }
        }
    )

    $overview = [pscustomobject]@{
        GeneratedAtUtc  = [DateTime]::UtcNow.ToString('o')
        Investigation   = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('investigationKey'))
        SubjectType     = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('subjectType'))
        SubjectId       = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('subjectId'))
        RunId           = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('runId'))
        StartedAtUtc    = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('startedAt'))
        FinishedAtUtc   = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('finishedAt'))
        SinceUtc        = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue (Get-GenesysOpsPropertyValue $manifest @('window')) @('since'))
        UntilUtc        = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue (Get-GenesysOpsPropertyValue $manifest @('window')) @('until'))
        StepCount       = $stepRows.Count
        FailedSteps     = @($stepRows | Where-Object { $_.Status -and $_.Status -ne 'ok' }).Count
        RecordsCollected = @($stepRows | Measure-Object -Property RecordCount -Sum).Sum
        SectionCount    = $sectionRows.Count
    }

    $csvDirectory = Join-Path $OutputDirectory 'csv'
    New-Item -Path $csvDirectory -ItemType Directory -Force | Out-Null
    $csvFiles = [ordered]@{}
    foreach ($sectionName in $sectionRows.Keys) {
        $csvPath = Join-Path $csvDirectory ("$resolvedPackageName.$sectionName.csv")
        Export-GenesysOpsRowsCsv -Rows @($sectionRows[$sectionName]) -Path $csvPath
        $csvFiles[$sectionName] = (Split-Path -Path $csvPath -Leaf)
    }

    $markdownPath = Join-Path $OutputDirectory "$resolvedPackageName.md"
    $workbookPath = Join-Path $OutputDirectory "$resolvedPackageName.xlsx"
    $packageJsonPath = Join-Path $OutputDirectory "$resolvedPackageName.package.json"

    Set-Content -Path $markdownPath -Value (New-GenesysInvestigationPackageMarkdown -Manifest $manifest -Overview $overview -StepRows $stepRows -Sections $sectionRows) -Encoding utf8

    $workbookSheets = @(
        [pscustomobject]@{ Name = 'Overview'; Rows = @($overview) }
        [pscustomobject]@{ Name = 'Steps'; Rows = $stepRows }
    )
    foreach ($sectionName in $sectionRows.Keys) {
        $workbookSheets += [pscustomobject]@{ Name = $sectionName; Rows = @($sectionRows[$sectionName]) }
    }
    Export-GenesysOpsWorkbook -Path $workbookPath -Sheets $workbookSheets

    $package = [ordered]@{
        packageType      = 'investigation-package'
        generatedAtUtc   = $overview.GeneratedAtUtc
        investigationKey = $overview.Investigation
        subjectType      = $overview.SubjectType
        subjectId        = $overview.SubjectId
        runId            = $overview.RunId
        counts           = [ordered]@{
            steps    = $overview.StepCount
            failed   = $overview.FailedSteps
            records  = $overview.RecordsCollected
            sections = $overview.SectionCount
        }
        files            = [ordered]@{
            markdown  = (Split-Path -Path $markdownPath -Leaf)
            workbook  = (Split-Path -Path $workbookPath -Leaf)
            manifest  = 'manifest.json'
            summary   = 'summary.json'
            events    = if (Test-Path $eventsPath) { 'events.jsonl' } else { $null }
            csv       = $csvFiles
            dataFolder = if (Test-Path $dataFolder) { 'data' } else { $null }
            packageJson = (Split-Path -Path $packageJsonPath -Leaf)
        }
        overview         = $overview
        sections         = @(
            foreach ($sectionName in $sectionRows.Keys) {
                [pscustomobject]@{ Name = $sectionName; RecordCount = @($sectionRows[$sectionName]).Count }
            }
        )
    }
    Set-Content -Path $packageJsonPath -Value ($package | ConvertTo-Json -Depth 100) -Encoding utf8

    return [pscustomobject]@{
        RunFolder       = $resolvedRunFolder
        OutputDirectory = (Resolve-Path -Path $OutputDirectory).Path
        MarkdownPath    = $markdownPath
        WorkbookPath    = $workbookPath
        PackageJsonPath = $packageJsonPath
        CsvDirectory    = $csvDirectory
        Overview        = $overview
    }
}

function Export-GenesysInvestigationDiagnosticsBundle {
    <#
    .SYNOPSIS
        Builds a redacted support bundle from one-or-more investigation run folders.
    .DESCRIPTION
        Collects manifest metadata, step status, counts, and recent failure-oriented
        event excerpts from the supplied run folders. Secret-like keys and token-shaped
        strings are removed or redacted before the JSON bundle is emitted.
    .EXAMPLE
        Export-GenesysInvestigationDiagnosticsBundle -RunFolder @('./out/agent-investigation/demo-run','./out/queue-investigation/demo-run') -OutputPath './out/diagnostics.json'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $RunFolder,

        [string] $OutputPath,

        [switch] $PassThru
    )

    $bundledRuns = @(
        foreach ($folder in @($RunFolder)) {
            $resolvedRunFolder = (Resolve-Path -Path $folder -ErrorAction Stop).Path
            $manifestPath = Join-Path $resolvedRunFolder 'manifest.json'
            $eventsPath = Join-Path $resolvedRunFolder 'events.jsonl'

            if (-not (Test-Path $manifestPath)) { throw "Investigation manifest was not found: $manifestPath" }
            $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json

            $recentEvents = @()
            if (Test-Path $eventsPath) {
                $recentEvents = @(
                    Get-Content -Path $eventsPath |
                        Where-Object { $_.Trim() } |
                        ForEach-Object {
                            try { $_ | ConvertFrom-Json } catch { [pscustomobject]@{ raw = $_ } }
                        } |
                        Where-Object {
                            $_.eventType -match '\.failed$' -or
                            (Get-GenesysOpsPropertyValue $_ @('payload') | ForEach-Object { Get-GenesysOpsPropertyValue $_ @('errorMessage') })
                        } |
                        Select-Object -Last 10 |
                        ForEach-Object { Protect-GenesysDiagnosticValue -Value $_ }
                )
            }

            [pscustomobject]@{
                investigationKey = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('investigationKey'))
                runId            = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('runId'))
                subjectType      = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('subjectType'))
                subjectId        = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('subjectId'))
                window           = Protect-GenesysDiagnosticValue -Value (Get-GenesysOpsPropertyValue $manifest @('window'))
                startedAt        = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('startedAt'))
                finishedAt       = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('finishedAt'))
                composerVersion  = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $manifest @('composerVersion'))
                steps            = @(
                    foreach ($step in @(Get-GenesysOpsPropertyValue $manifest @('datasetsInvoked') @())) {
                        [pscustomobject]@{
                            stepName         = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('stepName'))
                            datasetKey       = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('datasetKey'))
                            validationStatus = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('validationStatus'))
                            recordCount      = Get-GenesysOpsPropertyValue $step @('recordCount') 0
                            required         = Get-GenesysOpsPropertyValue $step @('required') $false
                            status           = ConvertTo-GenesysOpsText (Get-GenesysOpsPropertyValue $step @('status'))
                            errorMessage     = Protect-GenesysDiagnosticValue -Value (Get-GenesysOpsPropertyValue $step @('errorMessage'))
                        }
                    }
                )
                redactionProfile = Protect-GenesysDiagnosticValue -Value (Get-GenesysOpsPropertyValue $manifest @('redactionProfile'))
                recentEvents     = $recentEvents
            }
        }
    )

    $bundle = [pscustomobject]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        runCount       = $bundledRuns.Count
        runs           = $bundledRuns
    }
    $json = $bundle | ConvertTo-Json -Depth 100

    $resolvedOutputPath = $null
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
            [System.IO.Path]::GetFullPath($OutputPath)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputPath))
        }
        $parent = Split-Path -Path $resolvedOutputPath -Parent
        if ($parent -and -not (Test-Path $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
        Set-Content -Path $resolvedOutputPath -Value $json -Encoding utf8
    }

    if ($PassThru) {
        return [pscustomobject]@{
            OutputPath = $resolvedOutputPath
            Json       = $json
            Bundle     = $bundle
        }
    }

    return [pscustomobject]@{
        OutputPath = $resolvedOutputPath
        Json       = $json
    }
}

function Get-GenesysQueueInvestigationStepDefinition {
    <#
    .SYNOPSIS
        Returns the ordered step descriptors for the Queue Investigation flagship.
    .DESCRIPTION
        Centralised so the public cmdlet and integration tests share the same
        contract. Designed for the investigation composer — each step is a
        hashtable consumed by Invoke-Investigation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $QueueId,

        [datetime] $Since,

        [datetime] $Until
    )

    $idMatchesQueue = { param($r, $s)
        ($r.PSObject.Properties['id'] -and [string]$r.id -eq $s.QueueId)
    }
    $queueIdMatches = { param($r, $s)
        $qp = $r.PSObject.Properties['queueId']
        $qp -and [string]$qp.Value -eq $s.QueueId
    }
    $singleQueueRouteParameters = {
        param($subject, $sections, $window)
        @{ Query = @{ queueId = [string]$subject['QueueId'] } }
    }
    $queueObservationsParameters = {
        param($subject, $sections, $window)
        @{
            Body = [ordered]@{
                filter = [ordered]@{
                    type       = 'and'
                    predicates = @(
                        [ordered]@{
                            dimension = 'queueId'
                            value     = [string]$subject['QueueId']
                        }
                    )
                }
                metrics = @('oInteracting','oWaiting','oOnQueueUsers','oOffQueueUsers','oActiveUsers')
            }
        }
    }
    $queuePerformanceParameters = {
        param($subject, $sections, $window)
        $sinceIso = ConvertTo-IsoUtcTimestamp $window['Since']
        $untilIso = ConvertTo-IsoUtcTimestamp $window['Until']
        @{
            Body = [ordered]@{
                interval    = "$sinceIso/$untilIso"
                granularity = 'PT1H'
                groupBy     = @('queueId','mediaType')
                metrics     = @('nConnected','tHandle','tTalk','tAcw','tAnswered','tHeld','nOffered','nOutbound')
                filter      = [ordered]@{
                    type       = 'and'
                    predicates = @(
                        [ordered]@{
                            dimension = 'queueId'
                            value     = [string]$subject['QueueId']
                        }
                    )
                }
            }
        }
    }
    $queueAbandonParameters = {
        param($subject, $sections, $window)
        $sinceIso = ConvertTo-IsoUtcTimestamp $window['Since']
        $untilIso = ConvertTo-IsoUtcTimestamp $window['Until']
        @{
            Body = [ordered]@{
                interval    = "$sinceIso/$untilIso"
                granularity = 'PT1H'
                groupBy     = @('queueId','mediaType')
                metrics     = @('nOffered','nConnected','tAbandon','tShortAbandon')
                filter      = [ordered]@{
                    type       = 'and'
                    predicates = @(
                        [ordered]@{
                            dimension = 'queueId'
                            value     = [string]$subject['QueueId']
                        }
                    )
                }
            }
        }
    }
    $queueTransfersParameters = {
        param($subject, $sections, $window)
        $sinceIso = ConvertTo-IsoUtcTimestamp $window['Since']
        $untilIso = ConvertTo-IsoUtcTimestamp $window['Until']
        @{
            Body = [ordered]@{
                interval    = "$sinceIso/$untilIso"
                granularity = 'PT1H'
                groupBy     = @('queueId','mediaType')
                metrics     = @('nTransferred','nBlindTransferred','nConsultTransferred','nConnected')
                filter      = [ordered]@{
                    type       = 'and'
                    predicates = @(
                        [ordered]@{
                            dimension = 'queueId'
                            value     = [string]$subject['QueueId']
                        }
                    )
                }
            }
        }
    }
    $queueWrapupDistributionParameters = {
        param($subject, $sections, $window)
        $sinceIso = ConvertTo-IsoUtcTimestamp $window['Since']
        $untilIso = ConvertTo-IsoUtcTimestamp $window['Until']
        @{
            Body = [ordered]@{
                interval    = "$sinceIso/$untilIso"
                granularity = 'PT1D'
                groupBy     = @('queueId','wrapUpCode')
                metrics     = @('nConnected','tHandle')
                filter      = [ordered]@{
                    type       = 'and'
                    predicates = @(
                        [ordered]@{
                            dimension = 'queueId'
                            value     = [string]$subject['QueueId']
                        }
                    )
                }
            }
        }
    }
    $activeAgentParameters = {
        param($subject, $sections, $window)

        $memberIds = @(
            @($sections['members']) |
                ForEach-Object {
                    if ($_.PSObject.Properties['userId'] -and -not [string]::IsNullOrWhiteSpace([string]$_.userId)) {
                        [string]$_.userId
                    }
                    elseif ($_.PSObject.Properties['id'] -and -not [string]::IsNullOrWhiteSpace([string]$_.id)) {
                        [string]$_.id
                    }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )

        if ($memberIds.Count -eq 0) {
            $memberIds = @('__no-members__')
        }

        $filterType = if ($memberIds.Count -gt 1) { 'or' } else { 'and' }
        @{
            Body = [ordered]@{
                filter = [ordered]@{
                    type       = $filterType
                    predicates = @(
                        $memberIds | ForEach-Object {
                            [ordered]@{
                                dimension = 'userId'
                                value     = [string]$_
                            }
                        }
                    )
                }
                metrics = @('oActiveQueues','oMemberQueues')
            }
        }
    }

    @(
        @{
            Name          = 'queue'
            DatasetKey    = 'routing.get.single.queue.config'
            Parameters    = $singleQueueRouteParameters
            SubjectFilter = $idMatchesQueue
            EmitAs        = 'queue'
            Required      = $true
            JoinKind      = 'Seed'
            JoinOn        = @{ Left = $null; Right = 'id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'members'
            DatasetKey    = 'routing-queue-members'
            Parameters    = @{ queueId = $QueueId }
            EmitAs        = 'members'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'queue.id'; Right = 'queueId' }
            SortKey       = 'id'
        }
        @{
            Name          = 'wrapupCodes'
            DatasetKey    = 'routing.get.queue.wrapup.codes.by.queue'
            Parameters    = $singleQueueRouteParameters
            SubjectFilter = $queueIdMatches
            EmitAs        = 'wrapupCodes'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'queue.id'; Right = 'queueId' }
            SortKey       = 'id'
        }
        @{
            Name          = 'observations'
            DatasetKey    = 'analytics.query.queue.observations.real.time.stats'
            Parameters    = $queueObservationsParameters
            SubjectFilter = $queueIdMatches
            EmitAs        = 'observations'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'queue.id'; Right = 'queueId' }
            SortKey       = 'queueId'
        }
        @{
            Name          = 'sla'
            DatasetKey    = 'analytics.query.conversation.aggregates.queue.performance'
            Parameters    = $queuePerformanceParameters
            SubjectFilter = $queueIdMatches
            EmitAs        = 'sla'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'queue.id'; Right = 'queueId' }
            SortKey       = 'queueId'
        }
        @{
            Name          = 'abandons'
            DatasetKey    = 'analytics.query.conversation.aggregates.abandon.metrics'
            Parameters    = $queueAbandonParameters
            SubjectFilter = $queueIdMatches
            EmitAs        = 'abandons'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'queue.id'; Right = 'queueId' }
            SortKey       = 'queueId'
        }
        @{
            Name          = 'transfers'
            DatasetKey    = 'analytics.query.conversation.aggregates.transfer.metrics'
            Parameters    = $queueTransfersParameters
            SubjectFilter = $queueIdMatches
            EmitAs        = 'transfers'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'queue.id'; Right = 'queueId' }
            SortKey       = 'queueId'
        }
        @{
            Name          = 'wrapupDistribution'
            DatasetKey    = 'analytics.query.conversation.aggregates.wrapup.distribution'
            Parameters    = $queueWrapupDistributionParameters
            SubjectFilter = $queueIdMatches
            EmitAs        = 'wrapupDistribution'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'queue.id'; Right = 'queueId' }
            SortKey       = 'queueId'
        }
        @{
            Name          = 'activeAgents'
            DatasetKey    = 'analytics.query.user.observations.real.time.status'
            Parameters    = $activeAgentParameters
            SubjectFilter = $queueIdMatches
            EmitAs        = 'activeAgents'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'queue.id'; Right = 'queueId' }
            SortKey       = 'userId'
        }
    )
}

function Get-GenesysQueueInvestigation {
    <#
    .SYNOPSIS
        Run the Queue Investigation flagship — joins queue config, members, real-time
        observations, wrap-up labels, SLA / queue performance, abandon metrics,
        transfer metrics, wrap-up distribution, and currently-active agents for
        one queue.
    .DESCRIPTION
        Composes nine catalog datasets via Invoke-Investigation and emits the
        standard run-artifact set under out/queue-investigation/<runId>/.

        Resolves -QueueName to a QueueId before invoking the composer. Use
        -DatasetInvoker (a scriptblock returning fixture data) to drive
        determinism / integration tests without touching the live API.
    .PARAMETER QueueId
        Resolved Genesys queue GUID. Required if -QueueName is not supplied.
    .PARAMETER QueueName
        Display-name fragment used to look up a single queue via Get-GenesysQueue.
        The first exact-name match is used; ambiguous matches throw.
    .PARAMETER Since
        Inclusive start of the investigation window. Defaults to 7 days ago.
    .PARAMETER Until
        Exclusive end of the investigation window. Defaults to now.
    .PARAMETER OutputRoot
        Root for the run-artifact tree. Defaults to 'out'.
    .PARAMETER RunId
        Override the auto-generated run identifier. Use only for deterministic
        tests; do not set in production.
    .PARAMETER DatasetInvoker
        Test seam — see Invoke-Investigation. When supplied, no live API calls
        are made and Connect-GenesysCloud is not required.
    .EXAMPLE
        Get-GenesysQueueInvestigation -QueueId 'q1b2c3...' -Since (Get-Date).AddDays(-7)
    .EXAMPLE
        Get-GenesysQueueInvestigation -QueueName 'Support'
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string] $QueueId,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string] $QueueName,

        [datetime] $Since,
        [datetime] $Until,
        [string]   $OutputRoot = 'out',
        [string]   $RunId,
        [scriptblock] $DatasetInvoker
    )

    if (-not $Until) { $Until = Get-Date }
    if (-not $Since) { $Since = $Until.AddDays(-7) }

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        if (-not $DatasetInvoker) { Assert-GenesysConnected }
        $matches = @(Get-GenesysQueue | Where-Object { $_.name -eq $QueueName })
        if ($matches.Count -eq 0) { throw "No Genesys queue matched '$QueueName'." }
        if ($matches.Count -gt 1) {
            $ids = ($matches | ForEach-Object { "$($_.name) <$($_.id)>" }) -join '; '
            throw "Ambiguous queue name '$QueueName' — $($matches.Count) matches: $ids"
        }
        $QueueId = $matches[0].id
    }

    if (-not $DatasetInvoker) { Assert-GenesysConnected }

    $steps = Get-GenesysQueueInvestigationStepDefinition -QueueId $QueueId -Since $Since -Until $Until

    Invoke-Investigation `
        -InvestigationKey 'queue-investigation' `
        -SubjectType      'queue' `
        -Subject          @{ SubjectId = $QueueId; QueueId = $QueueId } `
        -Window           @{ Since = $Since; Until = $Until } `
        -Steps            $steps `
        -OutputRoot       $OutputRoot `
        -RunId            $RunId `
        -DatasetInvoker   $DatasetInvoker
}

#endregion
