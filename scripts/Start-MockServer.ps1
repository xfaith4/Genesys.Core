<#
.SYNOPSIS
    Starts the Genesys.MockServer HTTP demo server on localhost:7777.

.DESCRIPTION
    Launches the Genesys.MockServer ASP.NET Core 8 application, which listens on
    http://localhost:7777 and responds to Genesys Cloud API requests with static
    demo fixture data. No live Genesys Cloud credentials are required.

    The server provides:
      - POST /oauth/token  → issues a fixed demo bearer token
      - GET  /api/v2/users/me → connectivity probe (returns Demo Admin user)
      - All catalog endpoints from genesys.catalog.json → fixture or skeleton responses
      - GET  /health → server status and endpoint count

    To authenticate, use:
      ****** demo-bearer-token-genesys-testplatform

    To stop the server, press Ctrl+C in this terminal.

.PARAMETER Port
    TCP port to listen on. Default: 7777.

.PARAMETER FixturesPath
    Path to the folder containing demo fixture JSON files.
    Default: tests/fixtures/demo relative to the repo root.

.PARAMETER CatalogPath
    Path to genesys.catalog.json.
    Default: catalog/genesys.catalog.json relative to the repo root.

.PARAMETER PollingRounds
    Number of poll calls an async job returns a non-terminal state before
    transitioning to FULFILLED. Default: 2.

.PARAMETER DotnetArgs
    Additional arguments to pass to 'dotnet run'. For example: '--no-build'.

.EXAMPLE
    # Start with defaults (port 7777, repo-local catalog and fixtures)
    pwsh -NoProfile -File ./scripts/Start-MockServer.ps1

.EXAMPLE
    # Start on a different port
    pwsh -NoProfile -File ./scripts/Start-MockServer.ps1 -Port 8888

.EXAMPLE
    # Use custom fixtures and fast polling (1 round before FULFILLED)
    pwsh -NoProfile -File ./scripts/Start-MockServer.ps1 -PollingRounds 1

.EXAMPLE
    # Connect Genesys.Core to the demo server
    Import-Module ./modules/Genesys.Core/Genesys.Core.psd1 -Force
    $headers = @{ Authorization = '******' }
    Invoke-Dataset -Dataset 'users' -BaseUri 'http://localhost:7777' -Headers $headers -OutputRoot './out'
#>
[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 7777,

    [string]$FixturesPath,

    [string]$CatalogPath,

    [ValidateRange(1, 20)]
    [int]$PollingRounds = 2,

    [string[]]$DotnetArgs = @()
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# Resolve paths
$effectiveCatalog = if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    Join-Path -Path $repoRoot -ChildPath 'catalog/genesys.catalog.json'
} else {
    $CatalogPath
}

$effectiveFixtures = if ([string]::IsNullOrWhiteSpace($FixturesPath)) {
    Join-Path -Path $repoRoot -ChildPath 'tests/fixtures/demo'
} else {
    $FixturesPath
}

if (-not (Test-Path $effectiveCatalog)) {
    throw "Catalog not found: $effectiveCatalog"
}

if (-not (Test-Path $effectiveFixtures)) {
    throw "Fixtures directory not found: $effectiveFixtures"
}

$projectPath = Join-Path -Path $repoRoot -ChildPath 'tools/Genesys.MockServer/Genesys.MockServer.csproj'
if (-not (Test-Path $projectPath)) {
    throw "MockServer project not found: $projectPath"
}

# Set environment variables consumed by Program.cs
$env:MOCK_PORT             = $Port.ToString()
$env:MOCK_CATALOG_PATH     = $effectiveCatalog
$env:MOCK_FIXTURES_PATH    = $effectiveFixtures
$env:MOCK_POLLING_ROUNDS   = $PollingRounds.ToString()

Write-Host ''
Write-Host '  Genesys.MockServer' -ForegroundColor Cyan
Write-Host '  ==================' -ForegroundColor DarkGray
Write-Host "  Port           : $Port" -ForegroundColor DarkGray
Write-Host "  Catalog        : $effectiveCatalog" -ForegroundColor DarkGray
Write-Host "  Fixtures       : $effectiveFixtures" -ForegroundColor DarkGray
Write-Host "  Polling rounds : $PollingRounds" -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Demo bearer token:' -ForegroundColor White
Write-Host "    demo-bearer-token-genesys-testplatform" -ForegroundColor Yellow
Write-Host ''
Write-Host '  Quick connect from Genesys.Core:' -ForegroundColor White
Write-Host '    $headers = @{ Authorization = "******" }' -ForegroundColor Gray
Write-Host "    Invoke-Dataset -Dataset users -BaseUri http://localhost:$Port -Headers `$headers" -ForegroundColor Gray
Write-Host ''
Write-Host '  Press Ctrl+C to stop.' -ForegroundColor DarkYellow
Write-Host ''

$dotnetCmd = @('run', '--project', $projectPath) + $DotnetArgs
& dotnet @dotnetCmd
