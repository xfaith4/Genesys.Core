function ConvertTo-NormalizedUserRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$InputObject)

    return [ordered]@{
        recordType = 'user'
        id = $InputObject.id
        name = $InputObject.name
        email = $InputObject.email
        state = $InputObject.state
        presence = $(if ($null -ne $InputObject.presence) { $InputObject.presence.presenceDefinition.systemPresence } else { $null })
        routingStatus = $(if ($null -ne $InputObject.routingStatus) { $InputObject.routingStatus.status } else { $null })
    }
}

function Invoke-UsersDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker
    )

    Invoke-SimpleCollectionDataset -RunContext $RunContext -Catalog $Catalog -DatasetKey 'users' -DataFileName 'users.jsonl' -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -Normalizer ${function:ConvertTo-NormalizedUserRecord}
}
