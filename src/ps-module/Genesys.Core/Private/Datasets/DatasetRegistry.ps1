function Get-DatasetRegistry {
    [CmdletBinding()]
    param()

    return @{
        'audit-logs' = 'Invoke-AuditLogsDataset'
        'users' = 'Invoke-UsersDataset'
        'routing-queues' = 'Invoke-RoutingQueuesDataset'
    }
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

        [scriptblock]$RequestInvoker
    )

    $registry = Get-DatasetRegistry
    if (-not $registry.ContainsKey($Dataset)) {
        throw "Unsupported dataset '$($Dataset)'. Available datasets: $([string]::Join(', ', $registry.Keys))."
    }

    $commandName = $registry[$Dataset]
    & $commandName -RunContext $RunContext -Catalog $Catalog -BaseUri $BaseUri -Headers $Headers -RequestInvoker $RequestInvoker
}
