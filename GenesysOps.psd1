@{
    RootModule        = 'GenesysOps.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f2c1e7-84b6-4d29-9f53-1c8e7d3b0a5f'
    Author            = 'Genesys.Core'
    CompanyName       = 'Genesys.Core'
    Description       = 'Deprecated back-compat shim. Use modules/Genesys.Ops/Genesys.Ops.psd1.'
    Copyright         = '(c) Genesys.Core. All rights reserved.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('*')
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Genesys', 'GenesysCloud', 'Ops', 'Shim', 'Deprecated')
            ProjectUri   = 'https://github.com/xfaith4/Genesys.Core'
            ReleaseNotes = 'Root GenesysOps manifest is retained as a deprecation shim; import modules/Genesys.Ops/Genesys.Ops.psd1 instead.'
        }
    }
}
