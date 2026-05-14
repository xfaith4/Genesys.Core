#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$DryRun,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
}

function Get-DefaultConfigPath {
    $repoRoot = Get-RepoRoot
    return [System.IO.Path]::Combine($repoRoot, 'config', 'short-voice-conversation-rollup.example.json')
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) {
        throw "Config file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw -Encoding UTF8
    return ($raw | ConvertFrom-Json -Depth 100)
}

function Merge-EnvOverrides {
    param([Parameter(Mandatory = $true)]$Config)

    if (-not $Config.Genesys) { $Config | Add-Member -NotePropertyName Genesys -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $Config.Query) { $Config | Add-Member -NotePropertyName Query -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $Config.Output) { $Config | Add-Member -NotePropertyName Output -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $Config.Elastic) { $Config | Add-Member -NotePropertyName Elastic -NotePropertyValue ([pscustomobject]@{}) -Force }

    if ($env:GENESYS_REGION) { $Config.Genesys | Add-Member -NotePropertyName Region -NotePropertyValue $env:GENESYS_REGION -Force }
    if ($env:GENESYS_SHORT_CALLS_THRESHOLD_SECONDS) { $Config.Query | Add-Member -NotePropertyName ThresholdSeconds -NotePropertyValue ([double]$env:GENESYS_SHORT_CALLS_THRESHOLD_SECONDS) -Force }
    if ($env:GENESYS_SHORT_CALLS_LOOKBACK_MINUTES) { $Config.Query | Add-Member -NotePropertyName LookbackMinutes -NotePropertyValue ([int]$env:GENESYS_SHORT_CALLS_LOOKBACK_MINUTES) -Force }
    if ($env:GENESYS_SHORT_CALLS_ARTIFACT_ROOT) { $Config.Output | Add-Member -NotePropertyName ArtifactRoot -NotePropertyValue $env:GENESYS_SHORT_CALLS_ARTIFACT_ROOT -Force }
    if ($env:GENESYS_SHORT_CALLS_ELASTIC_URI) { $Config.Elastic | Add-Member -NotePropertyName Uri -NotePropertyValue $env:GENESYS_SHORT_CALLS_ELASTIC_URI -Force }
    if ($env:GENESYS_SHORT_CALLS_ELASTIC_INDEX) { $Config.Elastic | Add-Member -NotePropertyName IndexName -NotePropertyValue $env:GENESYS_SHORT_CALLS_ELASTIC_INDEX -Force }

    return $Config
}

function Get-ConfigValue {
    param($Object, [string]$Name, $Default)

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Get-IsoIntervalFromLookback {
    param([int]$LookbackMinutes)

    $end = [DateTimeOffset]::UtcNow
    $start = $end.AddMinutes(-1 * [Math]::Abs($LookbackMinutes))
    return [pscustomobject]@{
        Interval = ("{0}/{1}" -f $start.ToString('o'), $end.ToString('o'))
        Start = $start.ToString('o')
        End = $end.ToString('o')
    }
}

function Build-ShortVoiceBody {
    param(
        [Parameter(Mandatory = $true)][string]$Interval,
        [Parameter(Mandatory = $true)][string[]]$Directions,
        [Parameter(Mandatory = $true)]$Query
    )

    $convPredicates = New-Object System.Collections.Generic.List[object]
    $convPredicates.Add([ordered]@{ type='dimension'; dimension='mediaType'; operator='matches'; value='voice' }) | Out-Null

    $validDirections = @($Directions | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { $_ -eq 'inbound' -or $_ -eq 'outbound' })
    if (@($validDirections).Count -gt 0) {
        $dirPredicates = @()
        foreach ($direction in @($validDirections)) {
            $dirPredicates += [ordered]@{ type='dimension'; dimension='originatingDirection'; operator='matches'; value=$direction }
        }
        $convFilterDirection = [ordered]@{ type='or'; predicates=$dirPredicates }
    }
    else {
        $convFilterDirection = $null
    }

    $conversationFilters = New-Object System.Collections.Generic.List[object]
    $conversationFilters.Add([ordered]@{ type='and'; predicates=@($convPredicates.ToArray()) }) | Out-Null
    if ($null -ne $convFilterDirection) { $conversationFilters.Add($convFilterDirection) | Out-Null }

    $segmentPredicates = New-Object System.Collections.Generic.List[object]
    $queue = [string](Get-ConfigValue -Object $Query -Name 'Queue' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($queue)) {
        $segmentPredicates.Add([ordered]@{ type='dimension'; dimension='queueName'; operator='contains'; value=$queue }) | Out-Null
    }

    $division = [string](Get-ConfigValue -Object $Query -Name 'Division' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($division)) {
        $segmentPredicates.Add([ordered]@{ type='dimension'; dimension='divisionId'; operator='matches'; value=$division }) | Out-Null
    }

    $user = [string](Get-ConfigValue -Object $Query -Name 'User' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($user)) {
        $segmentPredicates.Add([ordered]@{ type='dimension'; dimension='userId'; operator='matches'; value=$user }) | Out-Null
    }

    $campaign = [string](Get-ConfigValue -Object $Query -Name 'Campaign' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($campaign)) {
        $segmentPredicates.Add([ordered]@{ type='dimension'; dimension='campaignId'; operator='matches'; value=$campaign }) | Out-Null
    }

    $disconnectType = [string](Get-ConfigValue -Object $Query -Name 'DisconnectType' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($disconnectType)) {
        $segmentPredicates.Add([ordered]@{ type='dimension'; dimension='disconnectType'; operator='matches'; value=$disconnectType }) | Out-Null
    }

    $wrapUpCode = [string](Get-ConfigValue -Object $Query -Name 'WrapUpCode' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($wrapUpCode)) {
        $segmentPredicates.Add([ordered]@{ type='dimension'; dimension='wrapUpCode'; operator='matches'; value=$wrapUpCode }) | Out-Null
    }

    $ani = [string](Get-ConfigValue -Object $Query -Name 'Ani' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($ani)) {
        $segmentPredicates.Add([ordered]@{ type='dimension'; dimension='ani'; operator='contains'; value=$ani }) | Out-Null
    }

    $dnis = [string](Get-ConfigValue -Object $Query -Name 'Dnis' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($dnis)) {
        $segmentPredicates.Add([ordered]@{ type='dimension'; dimension='dnis'; operator='contains'; value=$dnis }) | Out-Null
    }

    $externalContact = [string](Get-ConfigValue -Object $Query -Name 'ExternalContact' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($externalContact)) {
        $conversationFilters.Add([ordered]@{ type='or'; predicates=@([ordered]@{ type='dimension'; dimension='externalContactId'; operator='matches'; value=$externalContact }) }) | Out-Null
    }

    $body = [ordered]@{
        interval = $Interval
        order = 'asc'
        orderBy = 'conversationStart'
        conversationFilters = @($conversationFilters.ToArray())
    }

    if (@($segmentPredicates).Count -gt 0) {
        $body.segmentFilters = @([ordered]@{ type='and'; predicates=@($segmentPredicates.ToArray()) })
    }

    return $body
}

try {
    $repoRoot = Get-RepoRoot
    $effectiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Get-DefaultConfigPath } else { $ConfigPath }
    if (-not [System.IO.Path]::IsPathRooted($effectiveConfigPath)) {
        $effectiveConfigPath = [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath $effectiveConfigPath))
    }

    $cfg = Merge-EnvOverrides -Config (Read-JsonFile -Path $effectiveConfigPath)

    $region = [string](Get-ConfigValue -Object $cfg.Genesys -Name 'Region' -Default 'mypurecloud.com')
    $datasetKey = [string](Get-ConfigValue -Object $cfg.Genesys -Name 'DatasetKey' -Default 'analytics-conversation-details')
    $lookbackMinutes = [int](Get-ConfigValue -Object $cfg.Query -Name 'LookbackMinutes' -Default 70)
    $threshold = [double](Get-ConfigValue -Object $cfg.Query -Name 'ThresholdSeconds' -Default 5)
    $directions = @((Get-ConfigValue -Object $cfg.Query -Name 'Directions' -Default @('inbound','outbound')))

    $outputRoot = [string](Get-ConfigValue -Object $cfg.Output -Name 'ArtifactRoot' -Default '.artifacts/short-voice-conversations')
    if (-not [System.IO.Path]::IsPathRooted($outputRoot)) {
        $outputRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath $outputRoot))
    }

    if (-not [System.IO.Directory]::Exists($outputRoot)) {
        [System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null
    }

    $interval = Get-IsoIntervalFromLookback -LookbackMinutes $lookbackMinutes
    $body = Build-ShortVoiceBody -Interval $interval.Interval -Directions $directions -Query $cfg.Query

    $coreManifest = [System.IO.Path]::Combine($repoRoot, 'modules', 'Genesys.Core', 'Genesys.Core.psd1')
    $shortModule = [System.IO.Path]::Combine($repoRoot, 'apps', 'ConversationAnalyzer', 'modules', 'App.ShortVoice.psm1')
    $catalogPath = [System.IO.Path]::Combine($repoRoot, 'catalog', 'genesys.catalog.json')

    Import-Module $coreManifest -Force -ErrorAction Stop
    Import-Module $shortModule -Force -ErrorAction Stop

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($env:GENESYS_BEARER_TOKEN)) {
        $headers['Authorization'] = "Bearer $($env:GENESYS_BEARER_TOKEN)"
    }

    $invokeParams = @{
        Dataset = $datasetKey
        CatalogPath = $catalogPath
        OutputRoot = $outputRoot
        BaseUri = "https://api.$region"
        DatasetParameters = @{ Body = ($body | ConvertTo-Json -Depth 30) }
    }
    if (@($headers.Keys).Count -gt 0) {
        $invokeParams['Headers'] = $headers
    }

    if ($DryRun) {
        Write-Verbose "DryRun enabled; using Invoke-Dataset -WhatIf"
        $runContext = Invoke-Dataset @invokeParams -WhatIf
        Write-Output $runContext
        exit 0
    }

    $runContext = Invoke-Dataset @invokeParams

    if ($null -eq $runContext -or -not $runContext.PSObject.Properties['runFolder']) {
        throw 'Dataset run did not return a runFolder.'
    }

    $elastic = $cfg.Elastic
    $elasticEnabled = [bool](Get-ConfigValue -Object $elastic -Name 'Enabled' -Default $false)
    $elasticConfig = @{
        Enabled = $elasticEnabled
        Uri = [string](Get-ConfigValue -Object $elastic -Name 'Uri' -Default '')
        IndexName = [string](Get-ConfigValue -Object $elastic -Name 'IndexName' -Default 'genesys-short-voice-conversations-rollup')
        UseDailyIndexSuffix = [bool](Get-ConfigValue -Object $elastic -Name 'UseDailyIndexSuffix' -Default $true)
        AuthMode = [string](Get-ConfigValue -Object $elastic -Name 'AuthMode' -Default 'ApiKey')
        ApiKeyEnvironmentVariable = [string](Get-ConfigValue -Object $elastic -Name 'ApiKeyEnvironmentVariable' -Default 'GENESYS_SHORT_CALLS_ELASTIC_API_KEY')
        UsernameEnvironmentVariable = [string](Get-ConfigValue -Object $elastic -Name 'UsernameEnvironmentVariable' -Default 'GENESYS_SHORT_CALLS_ELASTIC_USERNAME')
        PasswordEnvironmentVariable = [string](Get-ConfigValue -Object $elastic -Name 'PasswordEnvironmentVariable' -Default 'GENESYS_SHORT_CALLS_ELASTIC_PASSWORD')
        ValidateTls = [bool](Get-ConfigValue -Object $elastic -Name 'ValidateTls' -Default $true)
        DryRun = [bool](Get-ConfigValue -Object $elastic -Name 'DryRun' -Default $false)
        BulkBatchSize = [int](Get-ConfigValue -Object $elastic -Name 'BulkBatchSize' -Default 500)
        OrgName = [string](Get-ConfigValue -Object $cfg.Genesys -Name 'OrgName' -Default '')
        OrgId = [string](Get-ConfigValue -Object $cfg.Genesys -Name 'OrgId' -Default '')
        Region = $region
        IntervalStart = $interval.Start
        IntervalEnd = $interval.End
    }

    $postProcessParams = @{
        RunFolder = $runContext.runFolder
        ThresholdSeconds = $threshold
        Directions = $directions
        IncludeIncompleteConversations = [bool](-not [bool](Get-ConfigValue -Object $cfg.Query -Name 'ExcludeIncompleteConversations' -Default $true))
        Queue = [string](Get-ConfigValue -Object $cfg.Query -Name 'Queue' -Default '')
        Division = [string](Get-ConfigValue -Object $cfg.Query -Name 'Division' -Default '')
        User = [string](Get-ConfigValue -Object $cfg.Query -Name 'User' -Default '')
        Campaign = [string](Get-ConfigValue -Object $cfg.Query -Name 'Campaign' -Default '')
        DisconnectType = [string](Get-ConfigValue -Object $cfg.Query -Name 'DisconnectType' -Default '')
        WrapUpCode = [string](Get-ConfigValue -Object $cfg.Query -Name 'WrapUpCode' -Default '')
        Ani = [string](Get-ConfigValue -Object $cfg.Query -Name 'Ani' -Default '')
        Dnis = [string](Get-ConfigValue -Object $cfg.Query -Name 'Dnis' -Default '')
        ExternalContact = [string](Get-ConfigValue -Object $cfg.Query -Name 'ExternalContact' -Default '')
        ExportMarkdown = [bool](Get-ConfigValue -Object $cfg.Output -Name 'ExportMarkdown' -Default $true)
        ExportJson = [bool](Get-ConfigValue -Object $cfg.Output -Name 'ExportJson' -Default $true)
        ExportCsv = [bool](Get-ConfigValue -Object $cfg.Output -Name 'ExportCsv' -Default $true)
        ExportExcel = [bool](Get-ConfigValue -Object $cfg.Output -Name 'ExportExcel' -Default $true)
        ElasticEnabled = $elasticEnabled
        ElasticConfig = $elasticConfig
    }
    $analysisResult = Invoke-ShortVoiceConversationPostProcess @postProcessParams

    Write-Output $analysisResult
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
