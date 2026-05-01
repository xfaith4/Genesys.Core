@{
    # Module identity
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f2c1e7-84b6-4d29-9f53-1c8e7d3b0a5f'
    Author            = 'IT Operations'
    CompanyName       = ''
    Description       = 'IT Operations wrapper around Genesys.Core for day-to-day Genesys Cloud administration.'
    Copyright         = '(c) Genesys.Core contributors. All rights reserved.'

    # Runtime requirements
    PowerShellVersion = '5.1'
    RootModule        = 'Genesys.Ops.psm1'

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

        # Edge / Telephony Telemetry  (Roadmap ideas 1–5)
        'Get-GenesysEdge'
        'Get-GenesysTrunk'
        'Get-GenesysTrunkMetrics'
        'Get-GenesysStation'
        'Get-GenesysEdgeHealthSnapshot'

        # Queue KPIs — Abandon Rate, SLA, Transfer, Wrapup  (Roadmap ideas 6–10)
        'Get-GenesysQueueAbandonRate'
        'Get-GenesysQueueServiceLevel'
        'Get-GenesysTransferAnalysis'
        'Get-GenesysWrapupDistribution'
        'Get-GenesysDigitalChannelVolume'

        # Quality & CSAT  (Roadmap ideas 11–13)
        'Get-GenesysEvaluation'
        'Get-GenesysSurvey'
        'Get-GenesysSentimentTrend'

        # Alerting  (Roadmap ideas 14–15)
        'Get-GenesysAlertingRule'
        'Get-GenesysAlert'

        # Agent Insights  (Roadmap ideas 16–18)
        'Get-GenesysAgentLoginActivity'
        'Get-GenesysLongHandleConversation'
        'Get-GenesysRepeatCaller'

        # WebRTC & Media Quality Trending  (Roadmap ideas 19–20)
        'Get-GenesysWebRtcDisconnectSummary'
        'Get-GenesysConversationLatencyTrend'

        # ACW Anomaly Detection  (Roadmap idea 21)
        'Get-GenesysAgentAcwAnomaly'

        # Phase 5 Visibility Dashboard  (Roadmap ideas 24–30)
        # Idea 24 — Workforce Management Unit Visibility
        'Get-GenesysWorkforceManagementUnit'

        # Idea 25 — Journey Action Map Inventory
        'Get-GenesysJourneyActionMap'

        # Idea 26 — Enhanced Operations Report
        'Get-GenesysAbandonRateDashboard'
        'Get-GenesysQueueHealthSnapshot'
        'Get-GenesysAgentQualitySnapshot'
        'Invoke-GenesysOperationsReport'

        # Idea 27 — Peak Hour Load Analysis
        'Get-GenesysPeakHourLoad'

        # Idea 28 — Configuration Change Audit Feed
        'Get-GenesysChangeAuditFeed'

        # Idea 29 — Outbound Campaign Performance Dashboard
        'Get-GenesysOutboundCampaignPerformance'

        # Idea 30 — Flow Outcome KPI Correlation
        'Get-GenesysFlowOutcomeKpiCorrelation'

        # Investigations (Release 1.0 Track B)
        'Get-GenesysAgentInvestigation'

        # Dataset coverage audit
        'Test-GenesysOpsDatasetCoverage'
    )

    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Genesys', 'GenesysCloud', 'ContactCentre', 'ITOps')
            ProjectUri   = 'https://github.com/your-org/Genesys.Core'
            ReleaseNotes = 'Initial release — wraps Genesys.Core datasets with IT Operations-focused cmdlets.'
        }
    }
}
