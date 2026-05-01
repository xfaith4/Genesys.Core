#Requires -Modules Pester
<#
.SYNOPSIS
    Pester unit tests for Genesys.Ops hardening (Phase 1 — no live API required).
.DESCRIPTION
    Covers:
    1.  Module imports cleanly under PowerShell 5.1-compatible syntax.
    2.  Test-GenesysOpsDatasetCoverage detects missing/valid dataset keys.
    3.  Invoke-GenesysOpsDataset returns Status=Unsupported for missing catalog keys.
    4.  ConvertFrom-ObservationResult handles missing group/data/metrics safely.
    5.  ConvertFrom-AggregateResult handles missing stats safely.
    6.  Safe-property helpers work correctly under Set-StrictMode -Version Latest.
    7.  Public cmdlets return records, not envelopes, unless -IncludeDiagnostics is used.
    8.  Composite commands return partial results when child sections fail.
    9.  Agent investigation uses only valid dataset keys from the active catalog.
#>

BeforeAll {
    $script:ModuleManifestPath = Join-Path $PSScriptRoot '../../modules/Genesys.Ops/Genesys.Ops.psd1'
    $script:CatalogPath        = Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json'
    $script:OpsModule = Import-Module -Name $script:ModuleManifestPath -Force -PassThru
}

AfterAll {
    if ($script:OpsModule) {
        Remove-Module -Name $script:OpsModule.Name -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
Describe 'Module import — PowerShell 5.1 compatible syntax' {

    It 'imports without errors' {
        $script:OpsModule | Should -Not -BeNullOrEmpty
    }

    It 'exports Test-GenesysOpsDatasetCoverage' {
        $script:OpsModule.ExportedCommands.Keys | Should -Contain 'Test-GenesysOpsDatasetCoverage'
    }

    It 'does not duplicate exported function names' {
        $exports = @($script:OpsModule.ExportedCommands.Keys)
        ($exports | Select-Object -Unique).Count | Should -Be $exports.Count
    }

    It 'has a valid module manifest' {
        $manifest = Import-PowerShellDataFile -Path $script:ModuleManifestPath
        $manifest.PowerShellVersion | Should -Be '5.1'
    }
}

# ---------------------------------------------------------------------------
Describe 'Safe property helpers under StrictMode' {

    It 'Test-Property returns $false for null input' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            Test-Property -InputObject $null -Name 'foo' | Should -BeFalse
        }
    }

    It 'Test-Property returns $true when property exists' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $obj = [PSCustomObject]@{ alpha = 'a' }
            Test-Property -InputObject $obj -Name 'alpha' | Should -BeTrue
        }
    }

    It 'Test-Property returns $false when property does not exist' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $obj = [PSCustomObject]@{ alpha = 'a' }
            Test-Property -InputObject $obj -Name 'missing' | Should -BeFalse
        }
    }

    It 'Get-PropertyValue returns default for null input' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            Get-PropertyValue -InputObject $null -Name 'x' -Default 'fallback' | Should -Be 'fallback'
        }
    }

    It 'Get-PropertyValue returns property value when present' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $obj = [PSCustomObject]@{ beta = 42 }
            Get-PropertyValue -InputObject $obj -Name 'beta' | Should -Be 42
        }
    }

    It 'Get-PropertyValue returns default when property is missing' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $obj = [PSCustomObject]@{ beta = 42 }
            Get-PropertyValue -InputObject $obj -Name 'nope' -Default 99 | Should -Be 99
        }
    }

    It 'Get-NestedPropertyValue traverses path correctly' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $obj = [PSCustomObject]@{
                user = [PSCustomObject]@{ email = 'ops@example.com' }
            }
            Get-NestedPropertyValue -InputObject $obj -Path 'user.email' | Should -Be 'ops@example.com'
        }
    }

    It 'Get-NestedPropertyValue returns default when intermediate node is null' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $obj = [PSCustomObject]@{ user = $null }
            Get-NestedPropertyValue -InputObject $obj -Path 'user.email' -Default 'none' | Should -Be 'none'
        }
    }

    It 'Get-NestedPropertyValue returns default when path segment is missing' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $obj = [PSCustomObject]@{ other = 'value' }
            Get-NestedPropertyValue -InputObject $obj -Path 'user.email' -Default 'none' | Should -Be 'none'
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'ConvertFrom-ObservationResult — StrictMode safety' {

    It 'returns empty when input is null' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $result = @($null | ConvertFrom-ObservationResult)
            $result.Count | Should -Be 0
        }
    }

    It 'returns record with no fields when group and data are missing' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $input = [PSCustomObject]@{}
            { $input | ConvertFrom-ObservationResult } | Should -Not -Throw
        }
    }

    It 'flattens group dimensions and metric counts correctly' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $input = [PSCustomObject]@{
                group = [PSCustomObject]@{ queueId = 'q1'; mediaType = 'voice' }
                data  = @(
                    [PSCustomObject]@{
                        interval = '2026-01-01T00:00:00.000Z'
                        metrics  = @(
                            [PSCustomObject]@{
                                metric = 'oWaiting'
                                stats  = [PSCustomObject]@{ count = 5 }
                            }
                        )
                    }
                )
            }
            $result = $input | ConvertFrom-ObservationResult
            $result.queueId   | Should -Be 'q1'
            $result.mediaType | Should -Be 'voice'
            $result.oWaiting  | Should -Be 5
        }
    }

    It 'handles missing stats without throwing' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $input = [PSCustomObject]@{
                group = [PSCustomObject]@{ queueId = 'q2' }
                data  = @(
                    [PSCustomObject]@{
                        interval = 'T'
                        metrics  = @( [PSCustomObject]@{ metric = 'oWaiting'; stats = $null } )
                    }
                )
            }
            { $input | ConvertFrom-ObservationResult } | Should -Not -Throw
            $result = $input | ConvertFrom-ObservationResult
            $result.oWaiting | Should -BeNullOrEmpty
        }
    }

    It 'handles empty data array without throwing' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $input = [PSCustomObject]@{ group = [PSCustomObject]@{ queueId = 'q3' }; data = @() }
            { $input | ConvertFrom-ObservationResult } | Should -Not -Throw
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'ConvertFrom-AggregateResult — StrictMode safety' {

    It 'returns empty when input has no data property' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $input  = [PSCustomObject]@{ group = [PSCustomObject]@{ userId = 'u1' } }
            $result = @($input | ConvertFrom-AggregateResult)
            $result.Count | Should -Be 0
        }
    }

    It 'flattens metrics with count/sum correctly' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $input = [PSCustomObject]@{
                group = [PSCustomObject]@{ userId = 'u1'; mediaType = 'voice' }
                data  = @(
                    [PSCustomObject]@{
                        interval = 'T'
                        metrics  = @(
                            [PSCustomObject]@{
                                metric = 'nConnected'
                                stats  = [PSCustomObject]@{ count = 10; sum = 100; min = 1; max = 20 }
                            }
                        )
                    }
                )
            }
            $result = $input | ConvertFrom-AggregateResult
            $result.nConnected_count | Should -Be 10
            $result.nConnected_sum   | Should -Be 100
        }
    }

    It 'handles null stats without throwing' {
        InModuleScope 'Genesys.Ops' {
            Set-StrictMode -Version Latest
            $input = [PSCustomObject]@{
                group = [PSCustomObject]@{ userId = 'u2' }
                data  = @(
                    [PSCustomObject]@{
                        interval = 'T'
                        metrics  = @( [PSCustomObject]@{ metric = 'nConnected'; stats = $null } )
                    }
                )
            }
            { $input | ConvertFrom-AggregateResult } | Should -Not -Throw
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GenesysOpsDataset — catalog pre-validation' {

    It 'returns Status=Unsupported when catalog key is missing' {
        InModuleScope 'Genesys.Ops' {
            param($cp)
            $script:GC = @{ Connected = $false; CatalogPath = $cp }
            $result = Invoke-GenesysOpsDataset -Dataset 'this.key.does.not.exist' `
                          -FunctionName 'TestFunc' -IncludeDiagnostics
            $result.Status      | Should -Be 'Unsupported'
            $result.DatasetKey  | Should -Be 'this.key.does.not.exist'
        } -Parameters @{ cp = (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') }
    }

    It 'returns empty array (not envelope) when catalog key is missing and no -IncludeDiagnostics' {
        InModuleScope 'Genesys.Ops' {
            param($cp)
            $script:GC = @{ Connected = $false; CatalogPath = $cp }
            $result = @(Invoke-GenesysOpsDataset -Dataset 'this.key.does.not.exist' -FunctionName 'TestFunc')
            $result.Count | Should -Be 0
        } -Parameters @{ cp = (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') }
    }

    It 'returns Status=Succeeded when dataset key is valid and stub returns records' {
        InModuleScope 'Genesys.Ops' {
            param($cp)
            $script:GC = @{ Connected = $true; CatalogPath = $cp }
            # Stub Invoke-GenesysDataset
            function script:Invoke-GenesysDataset { param([string]$Dataset) return @([PSCustomObject]@{ id='r1' }) }
            $result = Invoke-GenesysOpsDataset -Dataset 'users' -FunctionName 'TestFunc' -IncludeDiagnostics
            $result.Status      | Should -Be 'Succeeded'
            $result.RecordCount | Should -Be 1
        } -Parameters @{ cp = (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') }
    }

    It 'returns Status=Empty when dataset key is valid but stub returns nothing' {
        InModuleScope 'Genesys.Ops' {
            param($cp)
            $script:GC = @{ Connected = $true; CatalogPath = $cp }
            function script:Invoke-GenesysDataset { param([string]$Dataset) return @() }
            $result = Invoke-GenesysOpsDataset -Dataset 'users' -FunctionName 'TestFunc' -IncludeDiagnostics -AllowEmpty
            $result.Status      | Should -Be 'Empty'
            $result.RecordCount | Should -Be 0
        } -Parameters @{ cp = (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') }
    }
}

# ---------------------------------------------------------------------------
Describe 'Test-GenesysOpsDatasetCoverage' {

    It 'returns records for all mapped functions' {
        InModuleScope 'Genesys.Ops' {
            param($cp)
            $script:GC = @{ Connected = $false; CatalogPath = $cp }
            $results = @(Test-GenesysOpsDatasetCoverage -CatalogPath $cp)
            $results.Count | Should -BeGreaterThan 30
        } -Parameters @{ cp = (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') }
    }

    It 'marks composite functions as Low risk with IsInCatalog=$true' {
        InModuleScope 'Genesys.Ops' {
            param($cp)
            $script:GC = @{ Connected = $false; CatalogPath = $cp }
            $results   = @(Test-GenesysOpsDatasetCoverage -CatalogPath $cp)
            $composite = @($results | Where-Object { $_.DatasetKey -eq '(composite)' })
            $composite.Count | Should -BeGreaterThan 0
            foreach ($r in $composite) {
                $r.InvocationRisk | Should -Be 'Low'
                $r.IsInCatalog    | Should -BeTrue
            }
        } -Parameters @{ cp = (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') }
    }

    It 'marks Get-GenesysAgent as IsInCatalog=$true with Low risk' {
        InModuleScope 'Genesys.Ops' {
            param($cp)
            $script:GC = @{ Connected = $false; CatalogPath = $cp }
            $results   = @(Test-GenesysOpsDatasetCoverage -CatalogPath $cp)
            $agentRow  = @($results | Where-Object { $_.FunctionName -eq 'Get-GenesysAgent' }) | Select-Object -First 1
            $agentRow | Should -Not -BeNullOrEmpty
            $agentRow.IsInCatalog    | Should -BeTrue
            $agentRow.InvocationRisk | Should -Be 'Low'
        } -Parameters @{ cp = (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') }
    }

    It 'returns Unsupported risk when catalog does not contain the key' {
        InModuleScope 'Genesys.Ops' {
            param($tmpCatalog)
            '{"datasets":{"dummy.key":{"description":"d","endpoint":"d","paging":{"profile":"none"},"retry":{"profile":"default"}}}}' |
                Set-Content -Path $tmpCatalog -Encoding UTF8
            $script:GC = @{ Connected = $false; CatalogPath = $tmpCatalog }
            $results     = @(Test-GenesysOpsDatasetCoverage -CatalogPath $tmpCatalog)
            $unsupported = @($results | Where-Object { $_.InvocationRisk -eq 'Unsupported' })
            $unsupported.Count | Should -BeGreaterThan 0
        } -Parameters @{ tmpCatalog = ([System.IO.Path]::GetTempFileName() + '.json') }
    }

    It 'returns result with required output properties' {
        InModuleScope 'Genesys.Ops' {
            param($cp)
            $script:GC = @{ Connected = $false; CatalogPath = $cp }
            $first = Test-GenesysOpsDatasetCoverage -CatalogPath $cp | Select-Object -First 1
            $first.PSObject.Properties.Name | Should -Contain 'FunctionName'
            $first.PSObject.Properties.Name | Should -Contain 'DatasetKey'
            $first.PSObject.Properties.Name | Should -Contain 'IsInCatalog'
            $first.PSObject.Properties.Name | Should -Contain 'InvocationRisk'
            $first.PSObject.Properties.Name | Should -Contain 'Notes'
        } -Parameters @{ cp = (Join-Path $PSScriptRoot '../../catalog/genesys.catalog.json') }
    }
}

# ---------------------------------------------------------------------------
Describe 'Get-GenesysContactCentreStatus — partial success' {

    It 'returns partial status when the callback section throws' {
        InModuleScope 'Genesys.Ops' {
            $script:GC = @{ Connected = $true; CatalogPath = $null }
            function script:Get-GenesysAgent        { return @([PSCustomObject]@{ routingStatus='IDLE'; presence='AVAILABLE' }) }
            function script:Get-GenesysQueue        { return @([PSCustomObject]@{ memberCount=1 }) }
            function script:Get-GenesysActiveCall   { return @() }
            function script:Get-GenesysActiveChat   { return @() }
            function script:Get-GenesysActiveEmail  { return @() }
            function script:Get-GenesysActiveCallback { throw 'Simulated callback failure' }

            $status = Get-GenesysContactCentreStatus

            $status              | Should -Not -BeNullOrEmpty
            $status.TotalAgents  | Should -Be 1
            $status.TotalQueues  | Should -Be 1
            # ActiveCallbacks should be null due to failure
            $status.ActiveCallbacks | Should -BeNullOrEmpty
            # Diagnostics section must capture the failure
            $failed = @($status.Diagnostics | Where-Object { $_.Status -eq 'Failed' })
            $failed.Count   | Should -BeGreaterThan 0
            $failed[0].Section | Should -Be 'ActiveCallbacks'
        }
    }

    It 'includes successful data even when one section fails' {
        InModuleScope 'Genesys.Ops' {
            $script:GC = @{ Connected = $true; CatalogPath = $null }
            function script:Get-GenesysAgent        { return @([PSCustomObject]@{ routingStatus='IDLE'; presence='AVAILABLE' }, [PSCustomObject]@{ routingStatus='IDLE'; presence='OFFLINE' }) }
            function script:Get-GenesysQueue        { return @([PSCustomObject]@{ memberCount=5 }) }
            function script:Get-GenesysActiveCall   { return @([PSCustomObject]@{ id='c1' }) }
            function script:Get-GenesysActiveChat   { return @() }
            function script:Get-GenesysActiveEmail  { return @() }
            function script:Get-GenesysActiveCallback { throw 'Callback error' }

            $status = Get-GenesysContactCentreStatus

            $status.TotalAgents     | Should -Be 2
            $status.AgentsAvailable | Should -Be 1
            $status.ActiveCalls     | Should -Be 1
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Invoke-GenesysDailyHealthReport — partial success' {

    It 'returns report with null Agents when agent section fails' {
        InModuleScope 'Genesys.Ops' {
            $script:GC = @{ Connected = $true; CatalogPath = $null }
            function script:Get-GenesysOrganization { return [PSCustomObject]@{ name='TestOrg'; id='org1'; defaultLanguage='en-US' } }
            function script:Get-GenesysAgent        { throw 'Agents unavailable' }
            function script:Get-GenesysQueue        { return @([PSCustomObject]@{ memberCount=1; name='Q1' }) }
            function script:Get-GenesysApiUsage     { return @() }
            function script:Get-GenesysAuditEvent   { return @() }

            $report = Invoke-GenesysDailyHealthReport -PassThru

            $report           | Should -Not -BeNullOrEmpty
            $report.Agents    | Should -BeNullOrEmpty
            $report.Queues    | Should -Not -BeNullOrEmpty

            $failed = @($report.Diagnostics | Where-Object { $_.Status -eq 'Failed' })
            $failed.Count   | Should -BeGreaterThan 0
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Export-GenesysConfigurationSnapshot — partial success' {

    It 'returns section diagnostics when a section fails and continues' {
        InModuleScope 'Genesys.Ops' {
            param($folder)
            $script:GC = @{ Connected = $true; CatalogPath = $null }
            function script:Get-GenesysQueue        { return @([PSCustomObject]@{ id='q1'; name='Q1'; divisionId='d1'; memberCount=3 }) }
            function script:Get-GenesysRoutingSkill { throw 'Skills API unavailable' }
            function script:Get-GenesysWrapupCode   { return @([PSCustomObject]@{ id='w1'; name='W1' }) }
            function script:Get-GenesysLanguage     { return @([PSCustomObject]@{ id='l1'; name='L1' }) }
            function script:Get-GenesysDivision     { return @([PSCustomObject]@{ id='d1'; name='D1' }) }
            function script:Get-GenesysAgent        { return @([PSCustomObject]@{ id='a1'; name='A1'; email='a@b.com'; state='ACTIVE' }) }

            $result = Export-GenesysConfigurationSnapshot -OutputFolder $folder

            $result | Should -Not -BeNullOrEmpty
            $failed = @($result.Sections | Where-Object { $_.Status -eq 'Failed' })
            $failed.Count   | Should -Be 1
            $failed[0].Section | Should -Be 'RoutingSkills'

            $ok = @($result.Sections | Where-Object { $_.Status -eq 'OK' })
            $ok.Count | Should -BeGreaterThan 0
        } -Parameters @{ folder = (Join-Path ([System.IO.Path]::GetTempPath()) ('GenesysOpsTest_' + [System.Guid]::NewGuid().ToString('N'))) }
    }
}

# ---------------------------------------------------------------------------
Describe 'Agent investigation step definitions — catalog key validation' {

    It 'all step DatasetKey values exist in the active catalog' {
        $catalogRaw  = Get-Content -Path $script:CatalogPath -Raw | ConvertFrom-Json
        $catalogKeys = $catalogRaw.datasets.PSObject.Properties.Name

        # Get step definitions via InModuleScope since the function is private
        $steps = InModuleScope 'Genesys.Ops' {
            Get-GenesysAgentInvestigationStepDefinition -UserId 'dummy-user-id' `
                -Since (Get-Date).AddDays(-1) -Until (Get-Date)
        }

        foreach ($step in $steps) {
            $key = $step.DatasetKey
            $catalogKeys | Should -Contain $key `
                -Because "step '$($step.Name)' uses dataset key '$($key)' which must be in the catalog"
        }
    }
}
