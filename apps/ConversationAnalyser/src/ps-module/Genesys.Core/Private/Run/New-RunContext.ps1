function New-RunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DatasetKey,

        [ValidateNotNullOrEmpty()]
        [string]$OutputRoot = 'out',

        [ValidateNotNullOrEmpty()]
        [string]$RunId = ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
    )

    $runFolder = Join-Path -Path $OutputRoot -ChildPath (Join-Path -Path $DatasetKey -ChildPath $RunId)
    $dataFolder = Join-Path -Path $runFolder -ChildPath 'data'

    New-Item -Path $dataFolder -ItemType Directory -Force | Out-Null

    [pscustomobject]@{
        datasetKey = $DatasetKey
        runId = $RunId
        outputRoot = $OutputRoot
        runFolder = $runFolder
        dataFolder = $dataFolder
        manifestPath = (Join-Path -Path $runFolder -ChildPath 'manifest.json')
        eventsPath = (Join-Path -Path $runFolder -ChildPath 'events.jsonl')
        summaryPath = (Join-Path -Path $runFolder -ChildPath 'summary.json')
        startedAtUtc = [DateTime]::UtcNow
    }
}
