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

    # ---- Resolve catalog ----
    $resolvedCatalog = $CatalogPath
    if (-not $resolvedCatalog) {
        $catalogCandidates = @(
            (Join-Path $PSScriptRoot  '../../catalog/genesys.catalog.json'),
            (Join-Path $PSScriptRoot  '../catalog/genesys.catalog.json')
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

# ---------------------------------------------------------------------------
#region Private normalizers — analytics result flatteners (not exported)
# ---------------------------------------------------------------------------

function ConvertFrom-ObservationResult {
    <#
    Private. Flattens a Genesys analytics observation result record
    { group:{dimA, dimB}, data:[{interval, metrics:[{metric, stats:{count}}]}] }
    into a single PSCustomObject with group dimensions + each metric as a named
    property (using the raw metric name, e.g. oInteracting, oWaiting).
    #>
    param(
        [Parameter(ValueFromPipeline)]
        [object] $InputObject
    )
    process {
        $r = $InputObject
        $props = [ordered]@{}
        if ($r.group) {
            $r.group.psobject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
        }
        if ($r.data -and $r.data.Count -gt 0) {
            $props['Interval'] = $r.data[0].interval
            foreach ($m in @($r.data[0].metrics)) {
                $props[$m.metric] = $m.stats.count
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
    #>
    param(
        [Parameter(ValueFromPipeline)]
        [object] $InputObject
    )
    process {
        $r = $InputObject
        foreach ($d in @($r.data)) {
            $props = [ordered]@{ Interval = $d.interval }
            if ($r.group) {
                $r.group.psobject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
            }
            foreach ($m in @($d.metrics)) {
                $key = $m.metric
                $props["${key}_count"] = $m.stats.count
                $props["${key}_sum"]   = $m.stats.sum
                $props["${key}_min"]   = $m.stats.min
                $props["${key}_max"]   = $m.stats.max
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

        Note: the catalog default body filters on a specific queueId.  Update the
        catalog entry or request body to query all queues or a specific subset.
    .EXAMPLE
        # Current queue floor view
        Get-GenesysQueueObservation | Sort-Object oWaiting -Descending | Format-Table QueueId, oWaiting, oInteracting, oOnQueueUsers
    .EXAMPLE
        # Alert if any queue has more than 10 contacts waiting
        Get-GenesysQueueObservation | Where-Object { $_.oWaiting -gt 10 } |
            ForEach-Object { Write-Warning "Queue $($_.QueueId): $($_.oWaiting) waiting" }
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'analytics.query.queue.observations.real.time.stats' |
        ConvertFrom-ObservationResult
}

function Get-GenesysUserObservation {
    <#
    .SYNOPSIS
        Returns real-time agent observation records (presence and routing status).
    .DESCRIPTION
        Returns one record per agent with current oUserPresence and oUserRoutingStatus.
        More granular than the users dataset — useful for event-driven monitoring
        scripts where you need raw observation values rather than normalised labels.

            UserId             — Genesys user GUID
            Interval           — observation snapshot timestamp
            oUserPresence      — current presence state count
            oUserRoutingStatus — current routing status count

        Note: the catalog default body filters on a specific userId.  Update for
        organisation-wide observation.
    .EXAMPLE
        Get-GenesysUserObservation | Format-Table UserId, Interval, oUserPresence, oUserRoutingStatus
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'analytics.query.user.observations.real.time.status' |
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
    .EXAMPLE
        $perf = Get-GenesysQueuePerformance
        $perf | Select-Object queueId, Interval, nConnected_count,
            @{ n='AvgHandleSec'; e={ if ($_.nConnected_count) { [int]($_.tHandle_sum / $_.nConnected_count / 1000) } } } |
            Format-Table
    .EXAMPLE
        # Find queues where avg handle time > 600 s
        Get-GenesysQueuePerformance |
            Where-Object { $_.nConnected_count -and ($_.tHandle_sum / $_.nConnected_count / 1000) -gt 600 } |
            Format-Table queueId, nConnected_count
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.queue.performance' |
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

        Note: the catalog default body filters on a specific flowType.  Update the
        catalog entry for broader observation coverage.
    .EXAMPLE
        Get-GenesysFlowObservation | Where-Object { $_.oFlowDisconnect -gt 0 } |
            Format-Table flowId, oFlow, oFlowDisconnect
    #>
    [CmdletBinding()]
    param()

    Assert-GenesysConnected
    Invoke-GenesysDataset -Dataset 'analytics.query.flow.observations' |
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
        [int] $MinConversations = 0
    )

    Assert-GenesysConnected

    $raw = Invoke-GenesysDataset -Dataset 'analytics.query.user.aggregates.performance.metrics'

    $records = foreach ($r in @($raw)) {
        foreach ($d in @($r.data)) {
            $mHash = @{}
            foreach ($m in @($d.metrics)) { $mHash[$m.metric] = $m.stats }

            $handled = if ($mHash['nConnected']) { $mHash['nConnected'].count } else { 0 }
            $handleMs = if ($mHash['tHandle'])   { $mHash['tHandle'].sum    } else { $null }
            $talkMs   = if ($mHash['tTalk'])     { $mHash['tTalk'].sum      } else { $null }
            $acwMs    = if ($mHash['tAcw'])      { $mHash['tAcw'].sum       } else { $null }
            $ansMs    = if ($mHash['tAnswered'])  { $mHash['tAnswered'].sum  } else { $null }

            [PSCustomObject]@{
                UserId               = $r.group.userId
                MediaType            = $r.group.mediaType
                Interval             = $d.interval
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

    if ($MinConversations -gt 0) {
        $records = $records | Where-Object { $_.ConversationsHandled -ge $MinConversations }
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
            @(Invoke-GenesysDataset -Dataset 'analytics-conversation-details' `
                -KeepArtifacts:($KeepArtifacts -or ($ArtifactPath -ne '')) `
                -ArtifactPath $ArtifactPath)
        }

        foreach ($conv in $conversations) {
            $convMos   = $conv.mediaStatsMinConversationMos
            $divId     = if ($conv.divisionIds -and $conv.divisionIds.Count -gt 0) { $conv.divisionIds[0] } else { $null }

            foreach ($p in @($conv.participants)) {
                # Only agent legs (users) on voice
                if ($p.purpose -ne 'agent' -and $p.purpose -ne 'user') { continue }
                if (-not $p.userId) { continue }

                foreach ($sess in @($p.sessions)) {
                    if ($sess.mediaType -ne 'voice') { continue }

                    $segments     = @(if ($sess.segments) { $sess.segments } else { @() })
                    $lastSeg      = if ($segments.Count -gt 0) { $segments[-1] } else { $null }

                    # Last segment that carries an errorCode
                    $errorSeg     = $segments | Where-Object { $_.errorCode } | Select-Object -Last 1

                    # Queue from first ACD segment
                    $acdSeg       = $segments | Where-Object { $_.queueId } | Select-Object -First 1

                    $sessionMos   = $sess.mediaStatsMinConversationMos
                    $effectiveMos = if ($null -ne $sessionMos)  { $sessionMos }
                                   elseif ($null -ne $convMos)  { $convMos    }
                                   else                         { $null       }

                    [PSCustomObject]@{
                        ConversationId    = $conv.conversationId
                        ConversationStart = $conv.conversationStart
                        AgentUserId       = $p.userId
                        ParticipantId     = $p.participantId
                        SessionId         = $sess.sessionId
                        Provider          = $sess.provider
                        MediaType         = $sess.mediaType
                        SessionMos        = $sessionMos
                        ConversationMos   = $convMos
                        MosCategory       = Get-MosCategory $effectiveMos
                        RFactor           = $sess.mediaStatsMinConversationRFactor
                        DisconnectType    = if ($lastSeg) { $lastSeg.disconnectType } else { $null }
                        ErrorCode         = if ($errorSeg) { $errorSeg.errorCode } else { $null }
                        SegmentCount      = $segments.Count
                        QueueId           = if ($acdSeg)  { $acdSeg.queueId   } else { $null }
                        QueueName         = if ($acdSeg)  { $acdSeg.queueName } else { $null }
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
    param()

    Assert-GenesysConnected

    $raw = @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.abandon.metrics' |
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
    param()

    Assert-GenesysConnected

    $raw = @(Invoke-GenesysDataset -Dataset 'analytics.query.queue.aggregates.service.level' |
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
    param()

    Assert-GenesysConnected

    $raw = @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.transfer.metrics' |
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
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.wrapup.distribution' |
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
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'analytics.query.conversation.aggregates.digital.channels' |
      ConvertFrom-AggregateResult)
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
    param()

    Assert-GenesysConnected

    $conversations = @(Invoke-GenesysDataset -Dataset 'analytics-conversation-details')

    foreach ($conv in $conversations) {
        # Collect sentiment scores across all participants
        $scores = foreach ($p in @($conv.participants)) {
            foreach ($sess in @($p.sessions)) {
                if ($null -ne $sess.sentimentScore) { $sess.sentimentScore }
            }
        }
        $avgScore = if ($scores.Count -gt 0) {
            [math]::Round(($scores | Measure-Object -Average).Average, 3)
        } else { $null }

        [PSCustomObject]@{
            ConversationId    = $conv.conversationId
            ConversationStart = $conv.conversationStart
            OverallScore      = $avgScore
            ParticipantCount  = @($conv.participants).Count
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
    param()

    Assert-GenesysConnected
    @(Invoke-GenesysDataset -Dataset 'analytics.query.user.aggregates.login.activity' |
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
            @(Invoke-GenesysDataset -Dataset 'analytics-conversation-details')
        }

        foreach ($conv in $conversations) {
            foreach ($p in @($conv.participants)) {
                if ($p.purpose -ne 'agent' -and $p.purpose -ne 'user') { continue }
                if (-not $p.userId) { continue }

                foreach ($sess in @($p.sessions)) {
                    $segs   = @(if ($sess.segments) { $sess.segments } else { @() })
                    $acdSeg = $segs | Where-Object { $_.queueId } | Select-Object -First 1

                    # Sum segment durations for this session
                    $handleMs = 0
                    foreach ($seg in $segs) {
                        if ($seg.segmentStart -and $seg.segmentEnd) {
                            try {
                                $start = [datetime]::Parse($seg.segmentStart, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                                $end   = [datetime]::Parse($seg.segmentEnd,   $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                                $handleMs += ($end - $start).TotalMilliseconds
                            } catch { }
                        }
                    }

                    $handleSec = [math]::Round($handleMs / 1000, 1)
                    if ($handleSec -ge $ThresholdSeconds) {
                        [PSCustomObject]@{
                            ConversationId    = $conv.conversationId
                            ConversationStart = $conv.conversationStart
                            AgentUserId       = $p.userId
                            HandleSec         = $handleSec
                            QueueId           = if ($acdSeg) { $acdSeg.queueId } else { $null }
                            MediaType         = $sess.mediaType
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
            @(Invoke-GenesysDataset -Dataset 'analytics-conversation-details')
        }

        # Extract ANI from customer participants
        $byAni = @{}
        foreach ($conv in $conversations) {
            $custPart = @($conv.participants) | Where-Object { $_.purpose -eq 'customer' } | Select-Object -First 1
            if (-not $custPart) { continue }

            $ani = $null
            foreach ($sess in @($custPart.sessions)) {
                if ($sess.ani)  { $ani = $sess.ani;  break }
                if ($sess.dnis) { $ani = $sess.dnis; break }
            }
            if (-not $ani) { continue }

            if (-not $byAni.ContainsKey($ani)) {
                $byAni[$ani] = [System.Collections.Generic.List[object]]::new()
            }
            $byAni[$ani].Add([PSCustomObject]@{
                ConversationId    = $conv.conversationId
                ConversationStart = $conv.conversationStart
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
        [ValidateSet('HIGH','MEDIUM','LOW')]
        [string] $Risk
    )

    Assert-GenesysConnected

    $filterParams = @{}
    if ($EntityType) { $filterParams['EntityType'] = $EntityType }

    $events = @(Get-GenesysAuditEvent @filterParams)
    if ($events.Count -eq 0) { return }

    # Entity types considered sensitive for risk elevation
    $highRiskEntities = @('USER','FLOW','OAUTH_CLIENT','DIVISION','ROLE')
    $mediumRiskEntities = @('QUEUE','ROUTING_SKILL','WRAPUP_CODE','SCHEDULE','STATION')

    foreach ($ev in $events) {
        $action     = [string]$ev.action
        $entityType = [string]$ev.serviceContext.entityType
        $entityName = [string]$ev.serviceContext.entityName

        # Classify risk
        $riskLevel = 'LOW'
        $isHighAction   = $action -like 'DELETE_*' -or $action -like 'REVOKE_*'
        $isMediumAction = $action -like 'CREATE_*' -or $action -like 'UPDATE_*' -or $action -like 'ADD_*'

        if ($isHighAction -and $entityType -in $highRiskEntities)    { $riskLevel = 'HIGH'   }
        elseif ($isHighAction)                                         { $riskLevel = 'MEDIUM' }
        elseif ($isMediumAction -and $entityType -in $highRiskEntities){ $riskLevel = 'MEDIUM' }
        elseif ($isMediumAction -and $entityType -in $mediumRiskEntities) { $riskLevel = 'LOW' }

        # Compose summary
        $actor   = if ($ev.user -and $ev.user.email) { $ev.user.email } else { 'unknown' }
        $summary = "$action on $entityType '$entityName' by $actor"

        $record = [PSCustomObject]@{
            Timestamp  = $ev.timestamp
            Risk       = $riskLevel
            Action     = $action
            EntityType = $entityType
            EntityName = $entityName
            Actor      = $actor
            Summary    = $summary
            IpAddress  = $ev.user.ipAddress
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
    param()

    Assert-GenesysConnected

    $abandonData  = @(Get-GenesysQueueAbandonRate)
    $observations = @(Get-GenesysQueueObservation)
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
    param()

    Assert-GenesysConnected

    $observations = @(Get-GenesysQueueObservation)
    $sla          = @(Get-GenesysQueueServiceLevel)
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
    param()

    Assert-GenesysConnected
    @(Get-GenesysAgentPerformance)
}

function Invoke-GenesysOperationsReport {
    <#
    .SYNOPSIS
        Generates an enhanced operations report including abandon rate, SLA, and edge health.
    .DESCRIPTION
        Extends the standard daily health report with new KPI sections:
          - Queue abandon rates
          - Service level (SLA) compliance
          - Edge and trunk infrastructure health
          - Active platform alerts
          - WebRTC disconnect summary

        Use -OutputPath to write the report as UTF-8 JSON for downstream
        consumption (dashboards, ticketing, log aggregation).
    .PARAMETER OutputPath
        If specified, the report is serialised to this path as UTF-8 JSON.
    .PARAMETER PassThru
        Return the report object even when -OutputPath is used.
    .EXAMPLE
        Invoke-GenesysOperationsReport | ConvertTo-Json -Depth 8
    .EXAMPLE
        Invoke-GenesysOperationsReport -OutputPath "D:\Reports\OpsReport-$(Get-Date -f yyyyMMdd).json" -PassThru
    #>
    [CmdletBinding()]
    param(
        [string] $OutputPath,
        [switch] $PassThru
    )

    Assert-GenesysConnected

    Write-Verbose 'Collecting organisation details...'
    $org = Get-GenesysOrganization

    Write-Verbose 'Collecting contact centre status...'
    $ccStatus = Get-GenesysContactCentreStatus

    Write-Verbose 'Collecting queue abandon rates...'
    $abandon = @(Get-GenesysQueueAbandonRate)

    Write-Verbose 'Collecting queue service levels...'
    $sla = @(Get-GenesysQueueServiceLevel)

    Write-Verbose 'Collecting edge health...'
    $edgeSnap = Get-GenesysEdgeHealthSnapshot

    Write-Verbose 'Collecting active alerts...'
    $alerts = @(Get-GenesysAlert)

    Write-Verbose 'Collecting voice quality / WebRTC disconnects...'
    $webrtcSummary = @(Get-GenesysWebRtcDisconnectSummary)

    $highAbandon = @($abandon | Where-Object { $_.AbandonRate -gt 10 })
    $avgAbandon  = if ($abandon.Count -gt 0) {
        [math]::Round(($abandon | Measure-Object AbandonRate -Average).Average, 1)
    } else { $null }

    $belowSla = @($sla | Where-Object { $_.nOffered -gt 0 -and $_.ServiceLevel30Pct -lt 80 })
    $avgSla   = if ($sla.Count -gt 0) {
        [math]::Round(($sla | Where-Object ServiceLevel30Pct | Measure-Object ServiceLevel30Pct -Average).Average, 1)
    } else { $null }

    $report = [PSCustomObject]@{
        GeneratedAt   = Get-Date -Format 'o'
        Organisation  = [PSCustomObject]@{
            Name = $org.name
            Id   = $org.id
        }
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
        ActiveAlerts  = [PSCustomObject]@{
            Count  = $alerts.Count
            Alerts = $alerts | Select-Object -First 10 | ForEach-Object { $_.name }
        }
        WebRtcDisconnects = [PSCustomObject]@{
            TotalErrorEvents = ($webrtcSummary | Measure-Object Count -Sum).Sum
            ByErrorCode      = $webrtcSummary |
                Group-Object ErrorCode |
                Select-Object Name, @{n='Count';e={($_.Group|Measure-Object Count -Sum).Sum}} |
                Sort-Object Count -Descending
        }
    }

    if ($OutputPath) {
        $report | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Verbose "Report saved: $OutputPath"
    }

    if ($PassThru -or -not $OutputPath) { $report }
}

#endregion

# ---------------------------------------------------------------------------
#region Investigations (Release 1.0 Track B)
# ---------------------------------------------------------------------------

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
        $stepName    = [string]$step.Name
        $datasetKey  = [string]$step.DatasetKey
        $emitAs      = if ($step.ContainsKey('EmitAs') -and $step.EmitAs) { [string]$step.EmitAs } else { $stepName }
        $required    = if ($step.ContainsKey('Required')) { [bool]$step.Required } else { $true }
        $joinKind    = if ($step.ContainsKey('JoinKind') -and $step.JoinKind) { [string]$step.JoinKind } else { 'Inner' }
        $sortKey     = if ($step.ContainsKey('SortKey') -and $step.SortKey) { [string]$step.SortKey } else { 'id' }
        $joinOn      = if ($step.ContainsKey('JoinOn')) { $step.JoinOn } else { $null }

        $datasetProfiles[$datasetKey] = Resolve-DatasetRedactionProfileName -DatasetKey $datasetKey -Catalog $catalog

        $joinPlan.Add([ordered]@{
            stepName   = $stepName
            leftSource = if ($joinOn -and $joinOn.ContainsKey('Left')) { $joinOn.Left } else { $null }
            leftKey    = if ($joinOn -and $joinOn.ContainsKey('Left')) { $joinOn.Left } else { $null }
            rightKey   = if ($joinOn -and $joinOn.ContainsKey('Right')) { $joinOn.Right } else { $null }
            joinKind   = $joinKind
        }) | Out-Null

        & $writeEvent 'step.started' @{
            stepName   = $stepName
            datasetKey = $datasetKey
            required   = $required
        }

        $stepResult = $null
        try {
            if ($DatasetInvoker) {
                $stepResult = & $DatasetInvoker $step $Subject $Window
            } else {
                $invokeArgs = @{ Dataset = $datasetKey }
                if ($step.ContainsKey('Parameters') -and $step.Parameters) {
                    $invokeArgs['DatasetParameters'] = $step.Parameters
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

        $records = if ($stepResult -and $stepResult.records) { @($stepResult.records) } else { @() }

        if ($step.ContainsKey('SubjectFilter') -and $step.SubjectFilter -and $stepResult.status -eq 'ok') {
            $filter = [scriptblock]$step.SubjectFilter
            $records = @($records | Where-Object { & $filter $_ $Subject })
        }

        $records = Sort-RecordsForDeterminism -Records $records -SortKey $sortKey

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

    $idMatchesUser  = { param($r, $s) ($r.PSObject.Properties['id']     -and $r.id     -eq $s.UserId) }
    $userIdMatches  = { param($r, $s) ($r.PSObject.Properties['userId'] -and $r.userId -eq $s.UserId) }
    $userMembership = { param($r, $s)
        if ($r.PSObject.Properties['memberCount'] -and $r.PSObject.Properties['members']) {
            return ($r.members | Where-Object { $_.id -eq $s.UserId }).Count -gt 0
        }
        $true
    }
    $participantMatchesUser = { param($r, $s)
        if (-not $r.PSObject.Properties['participants']) { return $false }
        return ($r.participants | Where-Object { $_.userId -eq $s.UserId }).Count -gt 0
    }

    @(
        @{
            Name          = 'identity'
            DatasetKey    = 'users'
            SubjectFilter = $idMatchesUser
            EmitAs        = 'agent'
            Required      = $true
            JoinKind      = 'Seed'
            JoinOn        = @{ Left = $null; Right = 'id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'division'
            DatasetKey    = 'users.division.analysis.get.users.with.division.info'
            SubjectFilter = $idMatchesUser
            EmitAs        = 'division'
            Required      = $true
            JoinKind      = 'Inner'
            JoinOn        = @{ Left = 'agent.id'; Right = 'id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'skills'
            DatasetKey    = 'routing.get.all.routing.skills'
            EmitAs        = 'skills'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'id'
        }
        @{
            Name          = 'queues'
            DatasetKey    = 'routing-queues'
            SubjectFilter = $userMembership
            EmitAs        = 'queues'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'members.id' }
            SortKey       = 'id'
        }
        @{
            Name          = 'presence'
            DatasetKey    = 'users.get.bulk.user.presences'
            SubjectFilter = $userIdMatches
            EmitAs        = 'presence'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'userId'
        }
        @{
            Name          = 'activity'
            DatasetKey    = 'analytics.query.user.details.activity.report'
            SubjectFilter = $userIdMatches
            EmitAs        = 'activity'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'userId' }
            SortKey       = 'userId'
        }
        @{
            Name          = 'conversations'
            DatasetKey    = 'analytics-conversation-details-query'
            SubjectFilter = $participantMatchesUser
            EmitAs        = 'conversations'
            Required      = $false
            JoinKind      = 'Left'
            JoinOn        = @{ Left = 'agent.id'; Right = 'participants.userId' }
            SortKey       = 'conversationId'
        }
    )
}

function Get-GenesysAgentInvestigation {
    <#
    .SYNOPSIS
        Run the Agent Investigation flagship — joins identity, division, skills,
        queue memberships, presence, activity, and conversations for one agent.
    .DESCRIPTION
        Composes seven catalog datasets via Invoke-Investigation and emits the
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

#endregion
