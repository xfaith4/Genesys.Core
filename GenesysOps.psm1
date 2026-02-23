#Requires -Version 5.1
<#
.SYNOPSIS
    IT Operations wrapper around Genesys.Core for day-to-day Genesys Cloud administration.
.DESCRIPTION
    GenesysOps provides high-level operational commands built on Genesys.Core datasets.
    Every function returns parsed PSCustomObjects ready for filtering, pipeline composition,
    CSV export, and monitoring scripts.

    Typical session:

        Import-Module .\GenesysOps.psd1
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
        [string] $ArtifactPath
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
        Explicit path to genesys-core.catalog.json.  When omitted the module
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
                (Join-Path $PSScriptRoot  'src/ps-module/Genesys.Core/Genesys.Core.psd1'),
                (Join-Path $PSScriptRoot  '../src/ps-module/Genesys.Core/Genesys.Core.psd1'),
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

    # ---- Resolve catalog ----
    $resolvedCatalog = $CatalogPath
    if (-not $resolvedCatalog) {
        $catalogCandidates = @(
            (Join-Path $PSScriptRoot  'genesys-core.catalog.json'),
            (Join-Path $PSScriptRoot  '../genesys-core.catalog.json')
        )
        $resolvedCatalog = $catalogCandidates |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
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
        $results = $results | Where-Object { $_.division.name -like $DivisionName }
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
        [switch] $KeepArtifacts,
        [string] $ArtifactPath
    )

    Assert-GenesysConnected
    $keep = $KeepArtifacts -or ($ArtifactPath -ne '')
    Invoke-GenesysDataset -Dataset 'analytics-conversation-details' `
        -KeepArtifacts:$keep `
        -ArtifactPath  $ArtifactPath
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
        [string] $EntityType
    )

    Assert-GenesysConnected
    $results = Invoke-GenesysDataset -Dataset 'audit-logs'

    if ($Action)     { $results = $results | Where-Object { $_.action                     -like $Action     } }
    if ($Username)   { $results = $results | Where-Object { $_.user.email                 -like $Username   } }
    if ($EntityType) { $results = $results | Where-Object { $_.serviceContext.entityType  -eq   $EntityType } }

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
    param()

    Assert-GenesysConnected

    Write-Verbose 'Fetching agents...'
    $agents   = Get-GenesysAgent

    Write-Verbose 'Fetching queues...'
    $queues   = Get-GenesysQueue

    Write-Verbose 'Fetching active conversations...'
    $calls     = Get-GenesysActiveCall
    $chats     = Get-GenesysActiveChat
    $emails    = Get-GenesysActiveEmail
    $callbacks = Get-GenesysActiveCallback

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
        ActiveCallbacks     = $callbacks.Count
        TotalActiveContacts = $calls.Count + $chats.Count + $emails.Count + $callbacks.Count
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
    .PARAMETER OutputPath
        If specified, the report is serialised as UTF-8 JSON to this path.
    .PARAMETER PassThru
        Return the report object even when -OutputPath is used.
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
        [switch] $PassThru
    )

    Assert-GenesysConnected

    Write-Verbose 'Collecting organisation details...'
    $org    = Get-GenesysOrganization

    Write-Verbose 'Collecting agent roster...'
    $agents = Get-GenesysAgent

    Write-Verbose 'Collecting queue details...'
    $queues = Get-GenesysQueue

    Write-Verbose 'Collecting API usage...'
    $usage  = Get-GenesysApiUsage

    Write-Verbose 'Collecting recent audit events...'
    $audit  = Get-GenesysAuditEvent

    $presenceBreakdown = $agents |
        Group-Object presence |
        Sort-Object Count -Descending |
        ForEach-Object { [PSCustomObject]@{ Presence = $_.Name; Count = $_.Count } }

    $report = [PSCustomObject]@{
        GeneratedAt  = Get-Date -Format 'o'
        Organisation = [PSCustomObject]@{
            Name            = $org.name
            Id              = $org.id
            DefaultLanguage = $org.defaultLanguage
        }
        Agents       = [PSCustomObject]@{
            Total             = $agents.Count
            Active            = @($agents | Where-Object { $_.state         -eq 'ACTIVE'                    }).Count
            OnQueue           = @($agents | Where-Object { $_.routingStatus -in @('IDLE','INTERACTING')      }).Count
            PresenceBreakdown = $presenceBreakdown
        }
        Queues       = [PSCustomObject]@{
            Total        = $queues.Count
            EmptyCount   = @($queues | Where-Object { $_.memberCount -eq 0 }).Count
            TopByMembers = ($queues | Sort-Object memberCount -Descending | Select-Object -First 5 |
                               Select-Object name, memberCount)
        }
        ApiUsage     = $usage
        RecentAudit  = [PSCustomObject]@{
            TotalEvents  = $audit.Count
            LoginCount   = @($audit | Where-Object { $_.action -like '*LOGIN*'   }).Count
            DeleteCount  = @($audit | Where-Object { $_.action -like 'DELETE_*'  }).Count
        }
    }

    if ($OutputPath) {
        $report | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Verbose "Report saved: $OutputPath"
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
    .PARAMETER OutputFolder
        Folder to write CSV files into.  Created if it does not exist.
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
        [string] $OutputFolder
    )

    Assert-GenesysConnected

    if ($PSCmdlet.ShouldProcess($OutputFolder, 'Write configuration snapshot CSVs')) {
        if (-not (Test-Path $OutputFolder)) {
            $null = New-Item -ItemType Directory -Path $OutputFolder -Force
        }

        $stamp = Get-Date -Format 'o'

        Write-Verbose 'Exporting queues...'
        Get-GenesysQueue |
            Select-Object id, name, divisionId, memberCount |
            Export-Csv (Join-Path $OutputFolder 'queues.csv') -NoTypeInformation

        Write-Verbose 'Exporting routing skills...'
        Get-GenesysRoutingSkill |
            Select-Object id, name |
            Export-Csv (Join-Path $OutputFolder 'routing-skills.csv') -NoTypeInformation

        Write-Verbose 'Exporting wrapup codes...'
        Get-GenesysWrapupCode |
            Select-Object id, name |
            Export-Csv (Join-Path $OutputFolder 'wrapup-codes.csv') -NoTypeInformation

        Write-Verbose 'Exporting languages...'
        Get-GenesysLanguage |
            Select-Object id, name |
            Export-Csv (Join-Path $OutputFolder 'languages.csv') -NoTypeInformation

        Write-Verbose 'Exporting divisions...'
        Get-GenesysDivision |
            Select-Object id, name |
            Export-Csv (Join-Path $OutputFolder 'divisions.csv') -NoTypeInformation

        Write-Verbose 'Exporting agents...'
        Get-GenesysAgent |
            Select-Object id, name, email, state |
            Export-Csv (Join-Path $OutputFolder 'agents.csv') -NoTypeInformation

        # Write manifest
        [PSCustomObject]@{
            SnapshotTimestamp = $stamp
            OutputFolder      = (Resolve-Path $OutputFolder).Path
            Files             = (Get-ChildItem $OutputFolder -Filter '*.csv').Name
        } | ConvertTo-Json | Set-Content (Join-Path $OutputFolder 'manifest.json') -Encoding UTF8

        Write-Verbose "Snapshot complete: $OutputFolder"

        [PSCustomObject]@{
            OutputFolder = (Resolve-Path $OutputFolder).Path
            Files        = (Get-ChildItem $OutputFolder -Filter '*.csv').Name
        }
    }
}

#endregion
