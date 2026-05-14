#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$TaskName = 'Genesys-ShortVoiceConversationRollup',
    [ValidateSet('Every15Minutes', 'Hourly')]
    [string]$Frequency = 'Hourly',
    [string]$StartTime = '00:05',
    [string]$ConfigPath = 'config/short-voice-conversation-rollup.example.json',
    [switch]$Unregister,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
}

function New-TaskTriggerForFrequency {
    param(
        [ValidateSet('Every15Minutes', 'Hourly')][string]$Frequency,
        [string]$StartTime
    )

    $today = [DateTime]::Today
    $parts = $StartTime.Split(':')
    if (@($parts).Count -lt 2) {
        throw "Invalid StartTime format. Use HH:mm, for example 00:05."
    }

    $start = $today.AddHours([double]$parts[0]).AddMinutes([double]$parts[1])
    if ($start -lt [DateTime]::Now) {
        $start = $start.AddDays(1)
    }

    if ($Frequency -eq 'Every15Minutes') {
        return New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration ([TimeSpan]::MaxValue)
    }

    return New-ScheduledTaskTrigger -Daily -At $start
}

$repoRoot = Get-RepoRoot
$scriptPath = [System.IO.Path]::Combine($repoRoot, 'scripts', 'Start-ShortVoiceConversationRollupJob.ps1')
if (-not [System.IO.File]::Exists($scriptPath)) {
    throw "Runner script not found: $scriptPath"
}

if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath $ConfigPath))
}

if ($Unregister) {
    if ($WhatIf) {
        Write-Host "[WhatIf] Would unregister scheduled task '$TaskName'."
        exit 0
    }

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Unregistered task '$TaskName'."
    exit 0
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -ConfigPath \"{1}\"" -f $scriptPath, $ConfigPath)
$trigger = New-TaskTriggerForFrequency -Frequency $Frequency -StartTime $StartTime
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)

if ($WhatIf) {
    Write-Host "[WhatIf] Would register task '$TaskName' with frequency '$Frequency' start '$StartTime'."
    Write-Host "Action: powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$scriptPath\" -ConfigPath \"$ConfigPath\""
    exit 0
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description 'Runs the Genesys short voice conversation rollup workflow.' -Force | Out-Null
Write-Host "Registered task '$TaskName'."
