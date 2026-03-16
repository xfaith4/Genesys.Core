function Write-RunEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EventType,

        [AllowNull()]
        [object]$Payload
    )

    $event = [ordered]@{
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        datasetKey = $RunContext.datasetKey
        runId = $RunContext.runId
        eventType = $EventType
        payload = $Payload
    }

    Write-Jsonl -Path $RunContext.eventsPath -InputObject $event
    return [pscustomobject]$event
}
