@{
    CoreModuleRelativePath = '..\..\modules\Genesys.Core\Genesys.Core.psd1'
    AuthModuleRelativePath = '..\..\modules\Genesys.Auth\Genesys.Auth.psd1'
    CatalogRelativePath    = '..\..\catalog\genesys.catalog.json'
    SchemaRelativePath     = '..\..\catalog\schema\genesys.catalog.schema.json'
    OutputRelativePath     = '.\out'

    OAuth = @{
        PkceClientId    = ''
        PkceRedirectUri = 'http://localhost:8085/callback'
    }

    Ui = @{
        DefaultRegion = 'usw2.pure.cloud'
        Regions = @(
            'usw2.pure.cloud'
            'mypurecloud.com'
            'cac1.pure.cloud'
            'euw2.pure.cloud'
            'aps1.pure.cloud'
            'apne2.pure.cloud'
        )
        PreviewRows = 500
    }
}
