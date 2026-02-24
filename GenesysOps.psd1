@{
    # Module identity
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f2c1e7-84b6-4d29-9f53-1c8e7d3b0a5f'
    Author            = 'IT Operations'
    CompanyName       = 'Contoso'
    Description       = 'IT Operations wrapper around Genesys.Core for day-to-day Genesys Cloud administration.'
    Copyright         = '(c) Contoso. All rights reserved.'

    # Runtime requirements
    PowerShellVersion = '5.1'
    RootModule        = 'GenesysOps.psm1'

    # Genesys.Core must be importable (either on PSModulePath or passed to Connect-GenesysCloud -CoreModulePath)
    # RequiredModules = @('Genesys.Core')   # Uncomment if Genesys.Core is installed system-wide

    # Exported commands — all public functions
    FunctionsToExport = @(
        # Session
        'Connect-GenesysCloud'
        'Disconnect-GenesysCloud'
        'Test-GenesysConnection'

        # Organisation
        'Get-GenesysOrganization'
        'Get-GenesysOrganizationLimit'
        'Get-GenesysDivision'

        # Users & Agents
        'Get-GenesysAgent'
        'Get-GenesysAgentPresence'
        'Find-GenesysUser'
        'Get-GenesysUserWithDivision'

        # Presence definitions
        'Get-GenesysSystemPresence'
        'Get-GenesysCustomPresence'

        # Routing configuration
        'Get-GenesysQueue'
        'Get-GenesysRoutingSkill'
        'Get-GenesysWrapupCode'
        'Get-GenesysLanguage'

        # Active conversations (real-time)
        'Get-GenesysActiveConversation'
        'Get-GenesysActiveCall'
        'Get-GenesysActiveChat'
        'Get-GenesysActiveEmail'
        'Get-GenesysActiveCallback'
        'Get-GenesysCallHistory'

        # Analytics
        'Get-GenesysConversationDetail'

        # Audit
        'Get-GenesysAuditEvent'

        # API usage
        'Get-GenesysApiUsage'
        'Get-GenesysApiUsageByClient'
        'Get-GenesysApiUsageByUser'

        # Notifications
        'Get-GenesysNotificationTopic'
        'Get-GenesysNotificationSubscription'

        # Composite / operational
        'Get-GenesysContactCentreStatus'
        'Invoke-GenesysDailyHealthReport'
        'Export-GenesysConfigurationSnapshot'

        # Operational events — observations & aggregates
        'Get-GenesysQueueObservation'
        'Get-GenesysUserObservation'
        'Get-GenesysQueuePerformance'

        # OAuth clients & authorizations
        'Get-GenesysOAuthClient'
        'Get-GenesysOAuthAuthorization'
        'Get-GenesysRateLimitEvent'

        # Outbound campaigns & events
        'Get-GenesysOutboundCampaign'
        'Get-GenesysOutboundContactList'
        'Get-GenesysOutboundEvent'
        'Get-GenesysMessagingCampaign'

        # Flow / Architect performance
        'Get-GenesysFlow'
        'Get-GenesysFlowOutcome'
        'Get-GenesysFlowMilestone'
        'Get-GenesysFlowAggregate'
        'Get-GenesysFlowObservation'

        # Agent performance & voice quality
        'Get-GenesysAgentPerformance'
        'Get-GenesysUserActivity'
        'Get-GenesysAgentVoiceQuality'
    )

    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Genesys', 'GenesysCloud', 'ContactCentre', 'ITOps')
            ProjectUri   = 'https://github.com/xfaith4/Genesys.Core'
            ReleaseNotes = 'Initial release — wraps Genesys.Core datasets with IT Operations-focused cmdlets.'
        }
    }
}
