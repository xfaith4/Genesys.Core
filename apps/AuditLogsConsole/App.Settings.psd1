@{
    CoreModuleRelativePath = '..\..\modules\Genesys.Core\Genesys.Core.psd1'
    AuthModuleRelativePath = '..\..\modules\Genesys.Auth\Genesys.Auth.psd1'
    CatalogRelativePath    = '..\..\catalog\genesys.catalog.json'
    SchemaRelativePath     = '..\..\catalog\schema\genesys.catalog.schema.json'
    OutputRelativePath     = '.\out'

    DatasetKeys = @{
        Default = 'audit-logs'
        Preview = 'audit-logs'
        Full    = 'audit-logs'
    }

    Preview = @{
        MaxWindowHours      = 6
        DefaultLimit        = 250
        DefaultLookbackHours = 1
    }

    OAuth = @{
        PkceClientId    = ''
        PkceRedirectUri = 'http://localhost:8080/callback'
    }

    Ui = @{
        PageSize      = 100
        MaxRecentRuns = 20
        DefaultRegion = 'usw2.pure.cloud'
        Regions       = @(
            'usw2.pure.cloud'
            'mypurecloud.com'
            'cac1.pure.cloud'
            'euw2.pure.cloud'
            'aps1.pure.cloud'
            'apne2.pure.cloud'
        )
    }
}
