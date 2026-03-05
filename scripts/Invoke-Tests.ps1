[CmdletBinding()]
param(
    [string]$Path = 'tests/unit',
    [switch]$InstallDependencies,
    [switch]$IncludeIntegration,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed'
)

$pesterCommand = Get-Command -Name Invoke-Pester -ErrorAction SilentlyContinue
if ($null -eq $pesterCommand -and $InstallDependencies) {
    $installParams = @{
        Name = 'Pester'
        Scope = 'CurrentUser'
        Force = $true
        ErrorAction = 'Stop'
    }

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $installParams['SkipPublisherCheck'] = $true
    }

    Install-Module @installParams
    Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop
}

$pesterCommand = Get-Command -Name Invoke-Pester -ErrorAction SilentlyContinue
if ($null -eq $pesterCommand) {
    throw "Invoke-Pester was not found. Re-run with -InstallDependencies, or install Pester manually."
}

$unitResult = Invoke-Pester -Path $Path -Output $Output -PassThru

$hasIntegrationSecrets =
    (-not [string]::IsNullOrWhiteSpace($env:GENESYS_BEARER_TOKEN)) -or
    (
        (-not [string]::IsNullOrWhiteSpace($env:GENESYS_CLIENT_ID)) -and
        (-not [string]::IsNullOrWhiteSpace($env:GENESYS_CLIENT_SECRET))
    )

if ($IncludeIntegration -or $hasIntegrationSecrets) {
    if (Test-Path 'tests/integration') {
        Write-Host "Running integration tests from tests/integration..." -ForegroundColor Cyan
        $integrationResult = Invoke-Pester -Path 'tests/integration' -Output $Output -PassThru
        if ($integrationResult.FailedCount -gt 0) {
            throw "Integration tests failed: $($integrationResult.FailedCount)."
        }
    }
}
else {
    Write-Host 'Skipping integration tests. Set GENESYS_BEARER_TOKEN (or CLIENT_ID/CLIENT_SECRET) or pass -IncludeIntegration.' -ForegroundColor DarkYellow
}

if ($unitResult.FailedCount -gt 0) {
    throw "Unit tests failed: $($unitResult.FailedCount)."
}
