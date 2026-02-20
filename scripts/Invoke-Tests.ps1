[CmdletBinding()]
param(
    [string]$Path = 'tests',
    [switch]$InstallDependencies,
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

Invoke-Pester -Path $Path -Output $Output
