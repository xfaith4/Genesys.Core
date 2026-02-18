function ConvertTo-NormalizedQueueRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$InputObject)

    return [ordered]@{
        recordType = 'routingQueue'
        id = $InputObject.id
        name = $InputObject.name
        divisionId = $(if ($null -ne $InputObject.division) { $InputObject.division.id } else { $null })
        memberCount = $InputObject.memberCount
        joined = $InputObject.joined
    }
}

function Invoke-RoutingQueuesDataset {
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

    Invoke-SimpleCollectionDataset -RunContext $RunContext -Catalog $Catalog -DatasetKey 'routing-queues' -DataFileName 'routing-queues.jsonl' -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -Normalizer ${function:ConvertTo-NormalizedQueueRecord}
}
