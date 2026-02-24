function Get-DatasetRegistry {
    [CmdletBinding()]
    param()

    return @{
        'audit-logs'                        = 'Invoke-AuditLogsDataset'
        'analytics-conversation-details'    = 'Invoke-AnalyticsConversationDetailsDataset'
        'users'                             = 'Invoke-UsersDataset'
        'routing-queues'                    = 'Invoke-RoutingQueuesDataset'
    }
}

function ConvertTo-DatasetDataFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Dataset
    )

    $safeName = [System.Text.RegularExpressions.Regex]::Replace($Dataset, '[^A-Za-z0-9._-]', '-')
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'dataset'
    }

    return "$($safeName).jsonl"
}

function ConvertTo-IdentityRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    return $InputObject
}

function Invoke-RegisteredDataset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Dataset,

        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,

        [string]$BaseUri = 'https://api.mypurecloud.com',

        [hashtable]$Headers,

        [scriptblock]$RequestInvoker,

        [hashtable]$DatasetParameters,

        [switch]$NoRedact
    )

    $registry = Get-DatasetRegistry
    if ($registry.ContainsKey($Dataset)) {
        $commandName = $registry[$Dataset]
        & $commandName -RunContext $RunContext -Catalog $Catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -NoRedact:$NoRedact
        return
    }

    if ($null -ne $Catalog.datasets -and $Catalog.datasets.ContainsKey($Dataset)) {
        $dataFileName = ConvertTo-DatasetDataFileName -Dataset $Dataset
        Invoke-SimpleCollectionDataset -RunContext $RunContext -Catalog $Catalog -DatasetKey $Dataset -DataFileName $dataFileName -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker -DatasetParameters $DatasetParameters -Normalizer ${function:ConvertTo-IdentityRecord} -NoRedact:$NoRedact
        return
    }

    throw "Unsupported dataset '$($Dataset)'. Available datasets: $([string]::Join(', ', $registry.Keys))."
}
