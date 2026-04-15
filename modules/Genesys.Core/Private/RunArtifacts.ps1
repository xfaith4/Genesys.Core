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
    $apiLogPath = Join-Path -Path $runFolder -ChildPath 'api-calls.log'

    New-Item -Path $dataFolder -ItemType Directory -Force | Out-Null
    New-Item -Path $apiLogPath -ItemType File -Force | Out-Null

    [pscustomobject]@{
        datasetKey = $DatasetKey
        runId = $RunId
        outputRoot = $OutputRoot
        runFolder = $runFolder
        dataFolder = $dataFolder
        manifestPath = (Join-Path -Path $runFolder -ChildPath 'manifest.json')
        eventsPath = (Join-Path -Path $runFolder -ChildPath 'events.jsonl')
        summaryPath = (Join-Path -Path $runFolder -ChildPath 'summary.json')
        apiLogPath = $apiLogPath
        startedAtUtc = [DateTime]::UtcNow
    }
}

function Write-Jsonl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    $line = $InputObject | ConvertTo-Json -Depth 100 -Compress
    Add-Content -Path $Path -Value $line -Encoding utf8
}

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

function Write-ApiCallLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$RunContext,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Event
    )

    $payload = $Event.payload
    if ($null -eq $payload) {
        return
    }

    $apiLogPath = $RunContext.apiLogPath
    if ([string]::IsNullOrWhiteSpace([string]$apiLogPath)) {
        $apiLogPath = Join-Path -Path $RunContext.runFolder -ChildPath 'api-calls.log'
    }

    $logEntry = [ordered]@{
        timestampUtc = $Event.timestampUtc
        datasetKey = $RunContext.datasetKey
        runId = $RunContext.runId
        eventType = $Event.eventType
        endpointKey = $payload.endpointKey
        method = $payload.method
        uri = $payload.uri
        success = $payload.success
        statusCode = $payload.statusCode
        durationMs = $payload.durationMs
        attempts = $payload.attempts
        responseBytes = $payload.responseBytes
        responseItemCount = $payload.responseItemCount
        errorMessage = $payload.errorMessage
    }

    Write-Jsonl -Path $apiLogPath -InputObject $logEntry
}

function Write-Manifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$RunContext,

        [datetime]$EndedAtUtc = ([DateTime]::UtcNow),

        [hashtable]$Counts = @{},

        [string[]]$Warnings = @()
    )

    $gitSha = $null
    foreach ($varName in @('GITHUB_SHA', 'BUILD_SOURCEVERSION', 'CI_COMMIT_SHA')) {
        $envValue = [Environment]::GetEnvironmentVariable($varName)
        if ($envValue) {
            $gitSha = $envValue
            break
        }
    }

    $manifest = [ordered]@{
        datasetKey = $RunContext.datasetKey
        runId = $RunContext.runId
        startedAtUtc = ([DateTime]$RunContext.startedAtUtc).ToString('o')
        endedAtUtc = $EndedAtUtc.ToString('o')
        gitSha = $gitSha
        counts = $Counts
        warnings = $Warnings
    }

    $manifestJson = $manifest | ConvertTo-Json -Depth 100
    Set-Content -Path $RunContext.manifestPath -Value $manifestJson -Encoding utf8

    return [pscustomobject]$manifest
}
