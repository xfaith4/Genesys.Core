@{
    RootModule        = 'Genesys.Accessibility.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '6c0b8a2e-9d41-4f4a-b6c7-2e1f5a7d3b90'
    Author            = 'Genesys.Core'
    CompanyName       = 'Genesys.Core'
    Copyright         = '(c) Genesys.Core. All rights reserved.'
    Description       = 'Dependency-free static WCAG 2.1 (A/AA) conformance analyzer for the Genesys.Core HTML surfaces.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Test-HtmlAccessibility',
        'Get-GenesysAccessibilityRule',
        'Get-ContrastRatio',
        'Get-RelativeLuminance',
        'ConvertFrom-CssColor'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
