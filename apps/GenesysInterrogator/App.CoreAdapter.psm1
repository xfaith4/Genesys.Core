#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:Core = [ordered]@{
    Initialized   = $false
    CorePath      = $null
    AuthPath      = $null
    CatalogPath   = $null
    SchemaPath    = $null
    OutputRoot    = $null
    CatalogObject = $null
}

function Initialize-CoreIntegration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CoreModulePath,
        [Parameter(Mandatory)][string]$AuthModulePath,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$OutputRoot
    )

    foreach ($p in @($CoreModulePath, $AuthModulePath, $CatalogPath, $SchemaPath)) {
        if (-not [System.IO.File]::Exists($p)) { throw "Required file was not found: $p" }
    }

    Import-Module $AuthModulePath -Force -ErrorAction Stop
    Import-Module $CoreModulePath -Force -ErrorAction Stop
    Assert-Catalog -CatalogPath $CatalogPath -SchemaPath $SchemaPath -ErrorAction Stop | Out-Null

    if (-not [System.IO.Directory]::Exists($OutputRoot)) {
        [System.IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
    }

    $raw = [System.IO.File]::ReadAllText($CatalogPath, [System.Text.Encoding]::UTF8)
    $script:Core.CatalogObject = $raw | ConvertFrom-Json
    $script:Core.Initialized   = $true
    $script:Core.CorePath      = $CoreModulePath
    $script:Core.AuthPath      = $AuthModulePath
    $script:Core.CatalogPath   = $CatalogPath
    $script:Core.SchemaPath    = $SchemaPath
    $script:Core.OutputRoot    = $OutputRoot

    return [pscustomobject]@{
        Ready       = $true
        CatalogPath = $CatalogPath
        OutputRoot  = $OutputRoot
    }
}

function Connect-InterrogatorSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AccessToken,
        [string]$Region = 'usw2.pure.cloud'
    )

    if (-not $script:Core.Initialized) { throw 'Core integration has not been initialized.' }

    $r = $Region
    if ($r -match '^https?://api\.') { $r = $r -replace '^https?://api\.', '' }
    elseif ($r -match '^api\.')      { $r = $r -replace '^api\.', '' }

    return Connect-GenesysCloud -AccessToken $AccessToken -Region $r
}

function Connect-InterrogatorSessionPkce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [string]$Region = 'usw2.pure.cloud',
        [string]$RedirectUri = 'http://localhost:8085/callback',
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    if (-not $script:Core.Initialized) { throw 'Core integration has not been initialized.' }

    $r = $Region
    if ($r -match '^https?://api\.') { $r = $r -replace '^https?://api\.', '' }
    elseif ($r -match '^api\.')      { $r = $r -replace '^api\.', '' }

    return Connect-GenesysCloudPkce -ClientId $ClientId -Region $r -RedirectUri $RedirectUri -CancellationToken $CancellationToken
}

function Get-InterrogatorSession {
    if (Get-Command -Name Get-GenesysAuthContext -ErrorAction SilentlyContinue) {
        return Get-GenesysAuthContext
    }
    return $null
}

function Get-CatalogDatasets {
    [CmdletBinding()]
    param()

    if (-not $script:Core.Initialized) { throw 'Core integration has not been initialized.' }

    $cat = $script:Core.CatalogObject
    $datasets  = $cat.datasets
    $endpoints = $cat.endpoints

    $endpointNames = @($endpoints.PSObject.Properties.Name)
    $list = New-Object System.Collections.Generic.List[object]

    foreach ($prop in $datasets.PSObject.Properties) {
        $key = $prop.Name
        $ds = $prop.Value
        $epKey = [string]$ds.endpoint
        $ep = if ($epKey -and ($endpointNames -contains $epKey)) { $endpoints.$epKey } else { $null }

        $group = ''
        if ($null -ne $ep -and $ep.PSObject.Properties['notes'] -and $null -ne $ep.notes) {
            foreach ($n in $ep.notes) {
                if ([string]$n -match '^\s*group:\s*(.+?)\s*$') { $group = $Matches[1]; break }
            }
        }
        if ([string]::IsNullOrWhiteSpace($group)) { $group = 'Uncategorised' }

        $list.Add([pscustomobject]@{
            Key           = $key
            Description   = [string]$ds.description
            Endpoint      = $epKey
            Method        = if ($ep) { [string]$ep.method } else { '' }
            Path          = if ($ep) { [string]$ep.path }   else { '' }
            Group         = $group
            PagingProfile = if ($ds.paging -and $ds.paging.PSObject.Properties['profile']) { [string]$ds.paging.profile } else { '' }
            RetryProfile  = if ($ds.retry  -and $ds.retry.PSObject.Properties['profile'])  { [string]$ds.retry.profile }  else { '' }
            Transaction   = if ($ds.PSObject.Properties['transaction'] -and $ds.transaction.PSObject.Properties['profile']) { [string]$ds.transaction.profile } else { '' }
            ItemsPath     = [string]$ds.itemsPath
            EndpointDef   = $ep
            DatasetDef    = $ds
        })
    }

    return @($list.ToArray() | Sort-Object Group, Key)
}

function Get-DefaultDatasetParameters {
    [CmdletBinding()]
    param([AllowNull()][object]$Endpoint)

    $result = [ordered]@{}
    if ($null -eq $Endpoint) { return $result }

    if ($Endpoint.PSObject.Properties['defaultQueryParams'] -and $null -ne $Endpoint.defaultQueryParams) {
        foreach ($p in $Endpoint.defaultQueryParams.PSObject.Properties) {
            $result[$p.Name] = $p.Value
        }
    }

    if ($Endpoint.PSObject.Properties['notes'] -and $null -ne $Endpoint.notes) {
        foreach ($n in $Endpoint.notes) {
            $s = [string]$n
            if ($s.StartsWith('defaultBody:')) {
                $body = $s.Substring('defaultBody:'.Length).Trim()
                try {
                    $parsed = $body | ConvertFrom-Json
                    $result['Body'] = $parsed
                }
                catch {
                    $result['Body'] = $body
                }
            }
        }
    }

    return $result
}

function Invoke-InterrogatorRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatasetKey,
        [hashtable]$DatasetParameters
    )

    if (-not $script:Core.Initialized) { throw 'Core integration has not been initialized.' }

    $session = Get-InterrogatorSession
    if ($null -eq $session) { throw 'No active Genesys session. Connect first.' }

    $invokeParams = @{
        Dataset     = $DatasetKey
        CatalogPath = $script:Core.CatalogPath
        OutputRoot  = $script:Core.OutputRoot
        BaseUri     = $session.BaseUri
        Headers     = $session.Headers
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('DatasetParameters') -and $DatasetParameters -and $DatasetParameters.Count -gt 0) {
        $invokeParams.DatasetParameters = $DatasetParameters
    }

    return Invoke-Dataset @invokeParams
}

function Get-RunResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunFolder,
        [int]$MaxRows = 500
    )

    $manifest = $null
    $summary  = $null

    $mPath = [System.IO.Path]::Combine($RunFolder, 'manifest.json')
    $sPath = [System.IO.Path]::Combine($RunFolder, 'summary.json')

    if ([System.IO.File]::Exists($mPath)) {
        $manifest = [System.IO.File]::ReadAllText($mPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    if ([System.IO.File]::Exists($sPath)) {
        $summary = [System.IO.File]::ReadAllText($sPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }

    $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
    $rows = New-Object System.Collections.Generic.List[object]

    if ([System.IO.Directory]::Exists($dataDir)) {
        $files = [System.IO.Directory]::GetFiles($dataDir, '*.jsonl') | Sort-Object
        foreach ($f in $files) {
            if ($rows.Count -ge $MaxRows) { break }
            $fs = [System.IO.FileStream]::new($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
            try {
                while (-not $sr.EndOfStream -and $rows.Count -lt $MaxRows) {
                    $line = $sr.ReadLine()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    try { $rows.Add(($line | ConvertFrom-Json)) } catch { }
                }
            }
            finally {
                $sr.Dispose()
                $fs.Dispose()
            }
        }
    }

    return [pscustomobject]@{
        Manifest = $manifest
        Summary  = $summary
        Rows     = $rows.ToArray()
        DataDir  = $dataDir
    }
}

function ConvertTo-FlatRows {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Rows)

    if ($null -eq $Rows -or $Rows.Count -eq 0) { return @() }

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Rows) {
        $flat = [ordered]@{}
        if ($row -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $row.PSObject.Properties) {
                $v = $p.Value
                if ($null -eq $v) {
                    $flat[$p.Name] = ''
                }
                elseif ($v -is [string] -or $v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [bool] -or $v -is [datetime]) {
                    $flat[$p.Name] = $v
                }
                else {
                    try { $flat[$p.Name] = ($v | ConvertTo-Json -Compress -Depth 4) }
                    catch { $flat[$p.Name] = [string]$v }
                }
            }
        }
        else {
            $flat['value'] = [string]$row
        }
        $result.Add([pscustomobject]$flat)
    }
    return $result.ToArray()
}

Export-ModuleMember -Function `
    Initialize-CoreIntegration, `
    Connect-InterrogatorSession, Connect-InterrogatorSessionPkce, Get-InterrogatorSession, `
    Get-CatalogDatasets, Get-DefaultDatasetParameters, `
    Invoke-InterrogatorRun, Get-RunResults, ConvertTo-FlatRows
