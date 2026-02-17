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
