#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:AppDir     = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..'))
$script:ConfigDir  = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'GenesysConversationAnalysis')
$script:ConfigFile = [System.IO.Path]::Combine($script:ConfigDir, 'config.json')

# Nested layout: app lives at <repo>/apps/ConversationAnalyser/ inside Genesys.Core.
# modules/ is 3 levels below the repo root (modules → ConversationAnalyser → apps → root).
$script:_CoreSiblingRoot      = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))
$script:DefaultCoreModulePath = [System.IO.Path]::Combine($script:_CoreSiblingRoot, 'modules', 'Genesys.Core', 'Genesys.Core.psd1')
$script:DefaultCatalogPath    = [System.IO.Path]::Combine($script:_CoreSiblingRoot, 'catalog', 'genesys.catalog.json')
$script:DefaultSchemaPath     = [System.IO.Path]::Combine($script:_CoreSiblingRoot, 'catalog', 'schema', 'genesys.catalog.schema.json')

$script:LegacyCoreModuleSuffix = [string]([System.IO.Path]::Combine('Genesys.Core', 'modules', 'Genesys.Core', 'Genesys.Core.psd1'))
$script:LegacyCatalogSuffix    = [string]([System.IO.Path]::Combine('Genesys.Core', 'catalog', 'genesys.catalog.json'))
$script:LegacySchemaSuffix     = [string]([System.IO.Path]::Combine('Genesys.Core', 'catalog', 'schema', 'genesys.catalog.schema.json'))

function _GetFullPathSafe {
    param([string]$Path)
    try {
        return [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $Path
    }
}

function _NormalizeConfigPathInput {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

    $value = $Path.Trim()
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        return $value
    }

    if ($value -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest  = ($Matches[2] -replace '\\', '/').TrimStart('/')
        return "/mnt/$drive/$rest"
    }

    return ($value -replace '\\', '/')
}

function _IsPathUnderDirectory {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$FullPath
    )

    $base = (_GetFullPathSafe $BasePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $full = _GetFullPathSafe $FullPath
    if ($full.Equals($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $prefix = $base + [System.IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function _GetRelativePathPortable {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$FullPath
    )
    $hasGetRelative = [System.IO.Path].GetMethods() |
        Where-Object { $_.Name -eq 'GetRelativePath' -and $_.IsStatic }
    if ($hasGetRelative) {
        return [System.IO.Path]::GetRelativePath($BasePath, $FullPath)
    }

    $base = (_GetFullPathSafe $BasePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $full = _GetFullPathSafe $FullPath
    $baseWithSep = $base + [System.IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($baseWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($baseWithSep.Length)
    }
    return $FullPath
}

function _ResolveConfigPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $normalized = _NormalizeConfigPathInput -Path $Path
    if ([System.IO.Path]::IsPathRooted($normalized)) {
        return (_GetFullPathSafe $normalized)
    }
    return (_GetFullPathSafe ([System.IO.Path]::Combine($script:AppDir, $normalized)))
}

function _CollapseConfigPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $normalized = _NormalizeConfigPathInput -Path $Path
    if (-not [System.IO.Path]::IsPathRooted($normalized)) { return $normalized }

    $full = _GetFullPathSafe $normalized
    if (-not (_IsPathUnderDirectory -BasePath $script:AppDir -FullPath $full) -and
        -not (_IsPathUnderDirectory -BasePath $script:_CoreSiblingRoot -FullPath $full)) {
        return $full
    }

    $rel  = _GetRelativePathPortable -BasePath $script:AppDir -FullPath $full
    if (-not [string]::IsNullOrWhiteSpace($rel) -and -not [System.IO.Path]::IsPathRooted($rel)) {
        return $rel
    }
    return $full
}

function _ResolveRecentRuns {
    param([object[]]$RecentRuns)
    $resolved = @()
    foreach ($run in @($RecentRuns)) {
        if ([string]::IsNullOrWhiteSpace([string]$run)) { continue }
        $resolved += ,(_ResolveConfigPath -Path ([string]$run))
    }
    return ,@($resolved)
}

function _HasLegacySuffix {
    param(
        [string]$Path,
        [string]$Suffix
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Suffix)) { return $false }
    $normalizedPath   = $Path.Replace('/', '\').Trim()
    $normalizedSuffix = $Suffix.Replace('/', '\').Trim()
    return $normalizedPath.EndsWith($normalizedSuffix, [System.StringComparison]::OrdinalIgnoreCase)
}

function _MigrateLegacyPathDefaults {
    param([pscustomobject]$Config)

    $corePath = [string]$Config.CoreModulePath
    if ((_HasLegacySuffix -Path $corePath -Suffix $script:LegacyCoreModuleSuffix) -and
        -not ([System.IO.Path]::IsPathRooted($corePath) -and [System.IO.File]::Exists($corePath))) {
        $Config | Add-Member -NotePropertyName 'CoreModulePath' -NotePropertyValue $script:DefaultCoreModulePath -Force
    }
    $catalogPath = [string]$Config.CatalogPath
    if ((_HasLegacySuffix -Path $catalogPath -Suffix $script:LegacyCatalogSuffix) -and
        -not ([System.IO.Path]::IsPathRooted($catalogPath) -and [System.IO.File]::Exists($catalogPath))) {
        $Config | Add-Member -NotePropertyName 'CatalogPath' -NotePropertyValue $script:DefaultCatalogPath -Force
    }
    $schemaPath = [string]$Config.SchemaPath
    if ((_HasLegacySuffix -Path $schemaPath -Suffix $script:LegacySchemaSuffix) -and
        -not ([System.IO.Path]::IsPathRooted($schemaPath) -and [System.IO.File]::Exists($schemaPath))) {
        $Config | Add-Member -NotePropertyName 'SchemaPath' -NotePropertyValue $script:DefaultSchemaPath -Force
    }
}

function _ResolveConfigPaths {
    param([pscustomobject]$Config)

    $Config | Add-Member -NotePropertyName 'CoreModulePath' -NotePropertyValue (_ResolveConfigPath $Config.CoreModulePath) -Force
    $Config | Add-Member -NotePropertyName 'CatalogPath'    -NotePropertyValue (_ResolveConfigPath $Config.CatalogPath)    -Force
    $Config | Add-Member -NotePropertyName 'SchemaPath'     -NotePropertyValue (_ResolveConfigPath $Config.SchemaPath)     -Force
    $Config | Add-Member -NotePropertyName 'OutputRoot'     -NotePropertyValue (_ResolveConfigPath $Config.OutputRoot)     -Force
    $Config | Add-Member -NotePropertyName 'DatabasePath'   -NotePropertyValue (_ResolveConfigPath $Config.DatabasePath)   -Force
    $Config | Add-Member -NotePropertyName 'SqliteDllPath'  -NotePropertyValue (_ResolveConfigPath $Config.SqliteDllPath)  -Force
    $Config | Add-Member -NotePropertyName 'RecentRuns'     -NotePropertyValue (_ResolveRecentRuns $Config.RecentRuns)     -Force
    return $Config
}

function _GetDefaultOutputRoot {
    return [System.IO.Path]::Combine($env:LOCALAPPDATA, 'GenesysConversationAnalysis', 'runs')
}

function _GetDefaultDatabasePath {
    return [System.IO.Path]::Combine($env:LOCALAPPDATA, 'GenesysConversationAnalysis', 'cases.sqlite')
}

function Get-AppConfig {
    <#
    .SYNOPSIS
        Returns the merged application configuration (persisted file + defaults).
    #>
    $defaults = [ordered]@{
        CoreModulePath  = $script:DefaultCoreModulePath
        CatalogPath     = $script:DefaultCatalogPath
        SchemaPath      = $script:DefaultSchemaPath
        OutputRoot      = _GetDefaultOutputRoot
        DatabasePath    = _GetDefaultDatabasePath
        SqliteDllPath   = ''          # empty = use env:SQLITE_DLL or .\lib\System.Data.SQLite.dll
        ActiveCaseId    = ''          # last selected case; restored at startup
        Region          = 'mypurecloud.com'
        PageSize        = 50
        PreviewPageSize = 25
        MaxRecentRuns   = 20
        RecentRuns      = @()
        LastStartDate   = ''
        LastEndDate     = ''
        LastStartTime   = '00:00:00'
        LastEndTime     = '23:59:59'
        PkceClientId    = ''
        PkceRedirectUri = 'http://localhost:8080/callback'
    }

    if (-not [System.IO.File]::Exists($script:ConfigFile)) {
        return (_ResolveConfigPaths -Config ([pscustomobject]$defaults))
    }

    try {
        $raw = [System.IO.File]::ReadAllText($script:ConfigFile, [System.Text.Encoding]::UTF8)
        $obj = $raw | ConvertFrom-Json
    } catch {
        Write-Warning "Config file unreadable; using defaults. Error: $_"
        return (_ResolveConfigPaths -Config ([pscustomobject]$defaults))
    }

    # Merge: fill any missing keys with defaults
    foreach ($key in $defaults.Keys) {
        if ($null -eq $obj.PSObject.Properties[$key]) {
            $obj | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
        }
    }

    _MigrateLegacyPathDefaults -Config $obj
    return (_ResolveConfigPaths -Config $obj)
}

function Save-AppConfig {
    <#
    .SYNOPSIS
        Persists a config object to disk.
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $portable = [ordered]@{}
    foreach ($prop in $Config.PSObject.Properties) {
        $portable[$prop.Name] = $prop.Value
    }

    foreach ($key in @('CoreModulePath', 'CatalogPath', 'SchemaPath', 'OutputRoot', 'DatabasePath', 'SqliteDllPath')) {
        if ($portable.Contains($key)) {
            $portable[$key] = _CollapseConfigPath -Path ([string]$portable[$key])
        }
    }

    if ($portable.Contains('RecentRuns')) {
        $runs = @()
        foreach ($run in @($portable['RecentRuns'])) {
            if ([string]::IsNullOrWhiteSpace([string]$run)) { continue }
            $runs += ,(_CollapseConfigPath -Path ([string]$run))
        }
        $portable['RecentRuns'] = @($runs)
    }

    if (-not [System.IO.Directory]::Exists($script:ConfigDir)) {
        [System.IO.Directory]::CreateDirectory($script:ConfigDir) | Out-Null
    }
    $json = [pscustomobject]$portable | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($script:ConfigFile, $json, [System.Text.Encoding]::UTF8)
}

function Update-AppConfig {
    <#
    .SYNOPSIS
        Updates a single config key and persists.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][object]$Value
    )
    $cfg = Get-AppConfig
    $cfg | Add-Member -NotePropertyName $Key -NotePropertyValue $Value -Force
    Save-AppConfig -Config $cfg
}

function Add-RecentRun {
    <#
    .SYNOPSIS
        Prepends a run folder to the recent-runs list and trims to MaxRecentRuns.
    #>
    param(
        [Parameter(Mandatory)][string]$RunFolder
    )
    $cfg  = Get-AppConfig
    $runs = @($cfg.RecentRuns) | Where-Object { $_ -ne $RunFolder }
    $runs = @($RunFolder) + @($runs)
    $max  = if ($cfg.MaxRecentRuns -gt 0) { $cfg.MaxRecentRuns } else { 20 }
    if ($runs.Count -gt $max) {
        $runs = $runs[0..($max - 1)]
    }
    $cfg | Add-Member -NotePropertyName 'RecentRuns' -NotePropertyValue $runs -Force
    Save-AppConfig -Config $cfg
}

function Get-RecentRuns {
    <#
    .SYNOPSIS
        Returns the persisted list of recent run folders.
    #>
    $cfg = Get-AppConfig
    return @($cfg.RecentRuns)
}

function Get-CoreSiblingRoot {
    <#
    .SYNOPSIS
        Returns the expected sibling Genesys.Core directory (used by the bootstrap).
    #>
    return $script:_CoreSiblingRoot
}

Export-ModuleMember -Function Get-AppConfig, Save-AppConfig, Update-AppConfig, Add-RecentRun, Get-RecentRuns, Get-CoreSiblingRoot
