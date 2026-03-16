@{
    RootModule        = 'Genesys.Core.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'fb166f7d-0538-4dd8-9ada-0fb5e45295a4'
    Author            = 'Genesys.Core'
    CompanyName       = 'Genesys.Core'
    Copyright         = '(c) Genesys.Core. All rights reserved.'
    Description       = 'Catalog-driven Genesys Core PowerShell module bootstrap.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-Dataset', 'Assert-Catalog')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
