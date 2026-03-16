function Get-AuditServiceMapping {
    [CmdletBinding()]
    param(
        [string]$CatalogPath,
        [string]$BaseUri = 'https://api.mypurecloud.com',
        [hashtable]$Headers,
        [scriptblock]$RequestInvoker,
        [switch]$StrictCatalog
    )

    $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../catalog/schema/genesys.catalog.schema.json'
    $catalogResolution = Resolve-Catalog -CatalogPath $CatalogPath -SchemaPath $schemaPath -StrictCatalog:$StrictCatalog
    $catalog = $catalogResolution.catalogObject
    $endpoint = Get-CatalogEndpointByKey -Catalog $catalog -Key 'audits.get.service.mapping'
    $response = Invoke-CoreEndpoint -EndpointSpec $endpoint -InitialUri (Join-EndpointUri -BaseUri $BaseUri -Path $endpoint.path) -Headers $Headers -RequestInvoker $RequestInvoker

    $services = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($response.Items)) {
        if ($null -eq $item) {
            continue
        }

        $serviceItems = if ($item -is [string]) {
            @([pscustomobject]@{ name = [string]$item; entities = @() })
        }
        elseif ($item.PSObject.Properties.Name -contains 'services') {
            @($item.services)
        }
        else {
            @($item)
        }

        foreach ($serviceItem in $serviceItems) {
            if ($null -eq $serviceItem) {
                continue
            }

            $serviceName = if ($serviceItem -is [string]) {
                [string]$serviceItem
            }
            elseif ($serviceItem.PSObject.Properties.Name -contains 'name') {
                [string]$serviceItem.name
            }
            elseif ($serviceItem.PSObject.Properties.Name -contains 'serviceName') {
                [string]$serviceItem.serviceName
            }
            else {
                ''
            }

            if ([string]::IsNullOrWhiteSpace($serviceName)) {
                continue
            }

            $entities = @()
            if ($serviceItem.PSObject.Properties.Name -contains 'entities') {
                $entities = @($serviceItem.entities | ForEach-Object {
                    if ($null -eq $_) {
                        return
                    }

                    if ($_ -is [string]) {
                        return [pscustomobject]@{
                            Name    = [string]$_
                            Actions = @()
                        }
                    }

                    return [pscustomobject]@{
                        Name    = if ($_.PSObject.Properties.Name -contains 'name') { [string]$_.name } else { '' }
                        Actions = @($_.actions | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
                    }
                })
            }

            $actions = @($entities | ForEach-Object { @($_.Actions) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            $services.Add([pscustomobject]@{
                ServiceName = $serviceName
                Actions     = $actions
                Entities    = @($entities)
            }) | Out-Null
        }
    }

    return @($services | Sort-Object ServiceName -Unique)
}
