#Requires -Version 5.1
[CmdletBinding()]
param(
    [string] $Destination,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Destination) {
    $Destination = Join-Path $repoRoot 'samples\golden-path-demo'
}

if ((Test-Path $Destination) -and $Force) {
    Remove-Item -Path $Destination -Recurse -Force
}

$runsRoot = Join-Path $Destination 'runs'
$packagesRoot = Join-Path $Destination 'packages'
$diagnosticsRoot = Join-Path $Destination 'diagnostics'
New-Item -Path $runsRoot -ItemType Directory -Force | Out-Null
New-Item -Path $packagesRoot -ItemType Directory -Force | Out-Null
New-Item -Path $diagnosticsRoot -ItemType Directory -Force | Out-Null

$agentRun = Join-Path $runsRoot 'agent-investigation'
$conversationRun = Join-Path $runsRoot 'conversation-investigation'
$queueRun = Join-Path $runsRoot 'queue-investigation'

& (Join-Path $PSScriptRoot 'New-DemoAgentInvestigation.ps1') -Destination $agentRun
& (Join-Path $PSScriptRoot 'New-DemoConversationInvestigation.ps1') -Destination $conversationRun
& (Join-Path $PSScriptRoot 'New-DemoQueueInvestigation.ps1') -Destination $queueRun

$genericPackages = & (Join-Path $PSScriptRoot 'Export-InvestigationPackage.ps1') -RunFolder @($agentRun, $conversationRun, $queueRun) -DestinationRoot $packagesRoot -Force
$specialConversationPackage = & (Join-Path $PSScriptRoot 'New-DemoConversationInvestigationPackage.ps1') -OutputDirectory (Join-Path $packagesRoot 'conversation-specialized') -Force:$Force
$diagnostics = & (Join-Path $PSScriptRoot 'Copy-InvestigationDiagnosticsBundle.ps1') -RunFolder @($agentRun, $conversationRun, $queueRun) -OutputPath (Join-Path $diagnosticsRoot 'support-bundle.json') -PassThru

$scenarioPath = Join-Path $Destination 'scenario.md'
$scenarioLines = @(
    '# Golden-Path Demo Scenario',
    '',
    '1. Open `apps/InvestigationConsole/index.html` in a browser and import the run artifacts from `samples/golden-path-demo/runs/` (or use **Load Demo** for the embedded offline fixtures).',
    '2. Walk the operator through the Overview dashboard, then the Agent, Conversation, and Queue tabs.',
    '3. Show the generic Markdown/XLSX packages under `samples/golden-path-demo/packages/` for offline handoff.',
    '4. Show the specialized conversation package under `samples/golden-path-demo/packages/conversation-specialized/` for SIP/PCAP evidence packaging.',
    '5. Hand off the diagnostics JSON from `samples/golden-path-demo/diagnostics/support-bundle.json`.',
    '',
    'Generated artifacts:',
    "- Runs: $runsRoot",
    "- Generic packages: $packagesRoot",
    "- Diagnostics: $(Join-Path $diagnosticsRoot 'support-bundle.json')"
)
Set-Content -Path $scenarioPath -Value $scenarioLines -Encoding utf8

return [pscustomobject]@{
    Destination                   = (Resolve-Path $Destination).Path
    ScenarioPath                  = $scenarioPath
    RunFolders                    = @($agentRun, $conversationRun, $queueRun)
    GenericPackages               = @($genericPackages)
    SpecializedConversationPackage = $specialConversationPackage
    Diagnostics                   = $diagnostics
}
