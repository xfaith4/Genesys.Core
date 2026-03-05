@{
    RootModule = 'Genesys.Auth.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c2a1b3d4-e5f6-4789-abcd-ef0123456789'
    Author = 'Genesys.Core'
    CompanyName = 'Genesys.Core'
    Description = 'Authentication lane for Genesys Cloud. Owns OAuth flows, token lifecycle, and AuthContext.'
    Copyright = '(c) Genesys.Core. All rights reserved.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'New-GenesysPkceChallenge'
        'Get-GenesysPkceAuthorizeUrl'
        'Complete-GenesysPkceAuth'
        'Connect-GenesysCloud'

        # AuthContext accessor
        'Get-GenesysAuthContext'

        # Full OAuth flows
        'Connect-GenesysCloudApp'
        'Connect-GenesysCloudPkce'

        # Legacy header helpers (preserved for back-compat)
        'Get-StoredHeaders'
        'Test-GenesysConnection'
        'Get-ConnectionInfo'
        'Clear-StoredToken'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

PrivateData = @{
    PSData = @{
        Tags = @('Genesys', 'GenesysCloud', 'Auth', 'OAuth')
        ProjectUri = 'https://github.com/xfaith4/Genesys.Core'
    }
}
}
