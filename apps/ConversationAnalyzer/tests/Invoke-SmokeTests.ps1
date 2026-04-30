#Requires -Version 5.1

param(
    [string]$AppRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Results = New-Object System.Collections.Generic.List[object]
$script:SmokeDbCaseId = ''

function SmokeCheck {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$Test
    )

    try {
        $result = & $Test
        if ($result -is [pscustomobject] -and $result.PSObject.Properties['Result'] -and $result.Result -eq 'SKIP') {
            Write-Host "  [SKIP] $Id  $Description  ($($result.Detail))" -ForegroundColor Yellow
            $script:Results.Add([pscustomobject]@{ Id = $Id; Description = $Description; Result = 'SKIP'; Detail = $result.Detail }) | Out-Null
            return
        }

        if ($result -eq $true) {
            Write-Host "  [PASS] $Id  $Description" -ForegroundColor Green
            $script:Results.Add([pscustomobject]@{ Id = $Id; Description = $Description; Result = 'PASS'; Detail = '' }) | Out-Null
            return
        }

        Write-Host "  [FAIL] $Id  $Description  (got: $result)" -ForegroundColor Red
        $script:Results.Add([pscustomobject]@{ Id = $Id; Description = $Description; Result = 'FAIL'; Detail = [string]$result }) | Out-Null
    } catch {
        Write-Host "  [FAIL] $Id  $Description  (exception: $_)" -ForegroundColor Red
        $script:Results.Add([pscustomobject]@{ Id = $Id; Description = $Description; Result = 'FAIL'; Detail = [string]$_ }) | Out-Null
    }
}

function Import-AppModule {
    param([string]$Name)
    Import-Module (Join-Path $AppRoot $Name) -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
}

function New-SmokeConversation {
    param(
        [string]$ConversationId,
        [string]$Direction,
        [string]$MediaType,
        [string]$QueueName,
        [string]$QueueId,
        [string]$AgentId,
        [string]$DivisionId,
        [string]$ConversationStart,
        [string]$ConversationEnd,
        [hashtable]$Attributes = @{},
        [string]$DisconnectType = 'client',
        [string]$Ani = '15551234567',
        [string]$Dnis = '18005550100'
    )

    return [pscustomobject]@{
        conversationId    = $ConversationId
        conversationStart = $ConversationStart
        conversationEnd   = $ConversationEnd
        divisionIds       = @($DivisionId)
        attributes        = [pscustomobject]$Attributes
        participants      = @(
            [pscustomobject]@{
                purpose  = 'customer'
                sessions = @(
                    [pscustomobject]@{
                        mediaType = $MediaType
                        direction = $Direction
                        ani       = $Ani
                        dnis      = $Dnis
                        metrics   = @(
                            [pscustomobject]@{
                                name  = 'rFactorMos'
                                stats = [pscustomobject]@{
                                    min   = 3.1
                                    max   = 4.4
                                    sum   = 7.5
                                    count = 2
                                }
                            }
                        )
                        segments  = @(
                            [pscustomobject]@{
                                segmentType    = 'interact'
                                disconnectType = $DisconnectType
                                queueName      = $QueueName
                                queueId        = $QueueId
                                segmentStart   = $ConversationStart
                                segmentEnd     = $ConversationEnd
                            }
                        )
                    }
                )
            },
            [pscustomobject]@{
                purpose  = 'agent'
                userId   = $AgentId
                sessions = @(
                    [pscustomobject]@{
                        mediaType = $MediaType
                        segments  = @(
                            [pscustomobject]@{
                                segmentType  = 'hold'
                                queueName    = $QueueName
                                queueId      = $QueueId
                                segmentStart = $ConversationStart
                                segmentEnd   = $ConversationStart
                            }
                        )
                    }
                )
            }
        )
    }
}

function New-SmokeRunFolder {
    param([string]$Root)

    $runFolder = Join-Path $Root 'analytics-conversation-details-query'
    $runFolder = Join-Path $runFolder 'run-smoke-001'
    $dataDir   = Join-Path $runFolder 'data'

    [System.IO.Directory]::CreateDirectory($dataDir) | Out-Null

    $manifest = [pscustomobject]@{
        run_id                = 'run-smoke-001'
        dataset_key           = 'analytics-conversation-details-query'
        status                = 'complete'
        extraction_start      = '2026-03-01T00:00:00Z'
        extraction_end        = '2026-03-01T23:59:59Z'
        schema_version        = '1.0.0'
        normalization_version = '1.0.0'
    }
    $summary = [pscustomobject]@{
        run_id                = 'run-smoke-001'
        dataset_key           = 'analytics-conversation-details-query'
        status                = 'complete'
        extraction_start      = '2026-03-01T00:00:00Z'
        extraction_end        = '2026-03-01T23:59:59Z'
        schema_version        = '1.0.0'
        normalization_version = '1.0.0'
    }
    $events = @(
        [pscustomobject]@{ type = 'run.started';   at = '2026-03-01T00:00:00Z' },
        [pscustomobject]@{ type = 'run.complete';  at = '2026-03-01T00:10:00Z' }
    )

    $recordsA = @(
        (New-SmokeConversation -ConversationId 'conv-002' -Direction 'inbound'  -MediaType 'voice' -QueueName 'Support' -QueueId 'queue-support' -AgentId 'agent-002' -DivisionId 'division-b' -ConversationStart '2026-03-01T10:00:00Z' -ConversationEnd '2026-03-01T10:10:00Z' -Attributes @{ priority = 'high' }),
        (New-SmokeConversation -ConversationId 'conv-001' -Direction 'inbound'  -MediaType 'voice' -QueueName 'Support' -QueueId 'queue-support' -AgentId 'agent-001' -DivisionId 'division-a' -ConversationStart '2026-03-01T09:00:00Z' -ConversationEnd '2026-03-01T09:05:00Z' -Attributes @{ caseId = 'CASE-123'; priority = 'medium' })
    )
    $recordsB = @(
        (New-SmokeConversation -ConversationId 'conv-003' -Direction 'outbound' -MediaType 'chat'  -QueueName 'Billing' -QueueId 'queue-billing' -AgentId 'agent-003' -DivisionId 'division-a' -ConversationStart '2026-03-01T11:00:00Z' -ConversationEnd '2026-03-01T11:15:00Z' -Attributes @{ locale = 'en-US' } -DisconnectType 'system')
    )

    [System.IO.File]::WriteAllText((Join-Path $runFolder 'manifest.json'), ($manifest | ConvertTo-Json -Depth 10), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $runFolder 'summary.json'),  ($summary  | ConvertTo-Json -Depth 10), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $runFolder 'events.jsonl'), (($events | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $dataDir 'part-001.jsonl'), (($recordsA | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }) -join [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $dataDir 'part-002.jsonl'), (($recordsB | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }) -join [Environment]::NewLine), [System.Text.Encoding]::UTF8)

    return $runFolder
}

function New-SmokeEnvelopeRunFolder {
    param([string]$Root)

    $runFolder = Join-Path $Root 'analytics-conversation-details-query'
    $runFolder = Join-Path $runFolder 'run-smoke-envelope-001'
    $dataDir = Join-Path $runFolder 'data'
    [System.IO.Directory]::CreateDirectory($dataDir) | Out-Null

    $manifest = [pscustomobject]@{
        run_id = 'run-smoke-envelope-001'
        dataset_key = 'analytics-conversation-details-query'
        status = 'complete'
        schema_version = '1.0.0'
        normalization_version = '1.0.0'
        counts = [pscustomobject]@{ itemCount = 2 }
    }
    $summary = [pscustomobject]@{
        run_id = 'run-smoke-envelope-001'
        dataset_key = 'analytics-conversation-details-query'
        status = 'complete'
        totals = [pscustomobject]@{ totalRecords = 2 }
    }

    $records = @(
        [pscustomobject]@{
            item = (New-SmokeConversation -ConversationId 'env-001' -Direction 'inbound' -MediaType 'voice' -QueueName 'Envelope Queue' -QueueId 'queue-envelope' -AgentId 'agent-env-001' -DivisionId 'division-env' -ConversationStart '2026-03-02T09:00:00Z' -ConversationEnd '2026-03-02T09:04:00Z')
        },
        [pscustomobject]@{
            record = (New-SmokeConversation -ConversationId 'env-002' -Direction 'outbound' -MediaType 'chat' -QueueName 'Envelope Queue' -QueueId 'queue-envelope' -AgentId 'agent-env-002' -DivisionId 'division-env' -ConversationStart '2026-03-02T10:00:00Z' -ConversationEnd '2026-03-02T10:08:00Z')
        }
    )

    [System.IO.File]::WriteAllText((Join-Path $runFolder 'manifest.json'), ($manifest | ConvertTo-Json -Depth 10), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $runFolder 'summary.json'), ($summary | ConvertTo-Json -Depth 10), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $dataDir 'part-envelope.jsonl'), (($records | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 }) -join [Environment]::NewLine), [System.Text.Encoding]::UTF8)

    return $runFolder
}

function New-CoreConversationRunFixture {
    param([string]$Root)

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $AppRoot '..\..'))
    $coreModule = Join-Path $repoRoot 'modules/Genesys.Core/Genesys.Core.psd1'
    $catalogPath = Join-Path $repoRoot 'catalog/genesys.catalog.json'
    Import-Module $coreModule -Force -ErrorAction Stop

    $outputRoot = Join-Path $Root 'core-out'
    $script:CoreFixturePage = 0
    $requestInvoker = {
        param($request)
        $script:CoreFixturePage++
        if ($request.Method -eq 'POST' -and $request.Uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/query') {
            $body = $request.Body | ConvertFrom-Json
            if ($body.pageNumber -eq 1) {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    conversations = @(
                        [pscustomobject]@{
                            conversationId = 'core-fixture-001'
                            conversationStart = '2026-04-01T09:00:00Z'
                            conversationEnd = '2026-04-01T09:07:00Z'
                            divisionIds = @('division-core-a')
                            participants = @(
                                [pscustomobject]@{
                                    purpose = 'customer'
                                    sessions = @(
                                        [pscustomobject]@{
                                            mediaType = 'voice'
                                            direction = 'inbound'
                                            ani = '15550000001'
                                            dnis = '18005550100'
                                            segments = @(
                                                [pscustomobject]@{
                                                    segmentType = 'interact'
                                                    queueId = 'queue-core-support'
                                                    queueName = 'Core Support'
                                                    disconnectType = 'client'
                                                    segmentStart = '2026-04-01T09:00:00Z'
                                                    segmentEnd = '2026-04-01T09:07:00Z'
                                                }
                                            )
                                        }
                                    )
                                },
                                [pscustomobject]@{
                                    purpose = 'agent'
                                    userId = 'agent-core-001'
                                    name = 'Core Agent One'
                                    sessions = @(
                                        [pscustomobject]@{
                                            mediaType = 'voice'
                                            segments = @(
                                                [pscustomobject]@{
                                                    segmentType = 'hold'
                                                    queueId = 'queue-core-support'
                                                    queueName = 'Core Support'
                                                    segmentStart = '2026-04-01T09:02:00Z'
                                                    segmentEnd = '2026-04-01T09:03:00Z'
                                                }
                                            )
                                        }
                                    )
                                }
                            )
                        }
                    )
                    totalHits = 2
                } }
            }

            return [pscustomobject]@{ Result = [pscustomobject]@{
                conversations = @(
                    [pscustomobject]@{
                        conversationId = 'core-fixture-002'
                        conversationStart = '2026-04-01T10:00:00Z'
                        conversationEnd = '2026-04-01T10:12:00Z'
                        divisionIds = @('division-core-b')
                        participants = @(
                            [pscustomobject]@{
                                purpose = 'customer'
                                sessions = @(
                                    [pscustomobject]@{
                                        mediaType = 'chat'
                                        direction = 'inbound'
                                        ani = '15550000002'
                                        segments = @(
                                            [pscustomobject]@{
                                                segmentType = 'interact'
                                                queueId = 'queue-core-billing'
                                                queueName = 'Core Billing'
                                                disconnectType = 'system'
                                                segmentStart = '2026-04-01T10:00:00Z'
                                                segmentEnd = '2026-04-01T10:12:00Z'
                                            }
                                        )
                                    }
                                )
                            }
                        )
                    }
                )
                totalHits = 2
            } }
        }

        throw "Unexpected Core fixture request: $($request.Method) $($request.Uri)"
    }

    $run = Invoke-Dataset `
        -Dataset 'analytics-conversation-details-query' `
        -CatalogPath $catalogPath `
        -OutputRoot $outputRoot `
        -BaseUri 'https://api.test.local' `
        -RequestInvoker $requestInvoker `
        -NoRedact

    return $run.runFolder
}

$tempRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('gca-smoke-' + [System.Guid]::NewGuid().ToString('N')))
$oldLocalAppData = $env:LOCALAPPDATA
$runFolder = $null
$dbAvailable = $false

try {
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    $runFolder = New-SmokeRunFolder -Root $tempRoot
    $envelopeRunFolder = New-SmokeEnvelopeRunFolder -Root $tempRoot

    Write-Host "`n--- Config ---" -ForegroundColor DarkCyan

    SmokeCheck 'SMK-01' 'App.Config.psm1 round-trips portable paths through config.json' {
        $env:LOCALAPPDATA = Join-Path $tempRoot 'localappdata'
        Import-AppModule 'modules\App.Config.psm1'

        $cfg = Get-AppConfig
        $cfg | Add-Member -NotePropertyName 'OutputRoot' -NotePropertyValue (Join-Path $AppRoot 'tests/smoke-output') -Force
        $cfg | Add-Member -NotePropertyName 'RecentRuns' -NotePropertyValue @($runFolder) -Force
        Save-AppConfig -Config $cfg

        $configFile = Join-Path (Join-Path $env:LOCALAPPDATA 'GenesysConversationAnalysis') 'config.json'
        $saved = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $reloaded = Get-AppConfig

        $winOutputRoot = 'C:\Users\Example\AppData\Local\GenesysConversationAnalysis\runs'
        $rawPortable = [ordered]@{
            OutputRoot     = $winOutputRoot
            CoreModulePath = '..\..\modules\Genesys.Core\Genesys.Core.psd1'
            RecentRuns     = @('C:\Users\Example\AppData\Local\GenesysConversationAnalysis\runs\analytics-conversation-details\20260417T120000Z')
        }
        [System.IO.File]::WriteAllText($configFile, ([pscustomobject]$rawPortable | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
        $winReloaded = Get-AppConfig
        $expectedWinOutputRoot = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
            $winOutputRoot
        } else {
            '/mnt/c/Users/Example/AppData/Local/GenesysConversationAnalysis/runs'
        }

        (-not [System.IO.Path]::IsPathRooted([string]$saved.OutputRoot)) -and
        ($reloaded.OutputRoot -eq (Join-Path $AppRoot 'tests/smoke-output')) -and
        ($reloaded.RecentRuns.Count -eq 1) -and
        ($reloaded.RecentRuns[0] -eq $runFolder) -and
        ($winReloaded.OutputRoot -eq $expectedWinOutputRoot) -and
        ([System.IO.File]::Exists($winReloaded.CoreModulePath))
    }

    Write-Host "`n--- Run Folder ---" -ForegroundColor DarkCyan

    Import-AppModule 'modules\App.CoreAdapter.psm1'
    Import-AppModule 'modules\App.Index.psm1'
    Import-AppModule 'modules\App.Export.psm1'
    Import-AppModule 'modules\App.Reporting.psm1'

    SmokeCheck 'SMK-02' 'Get-DiagnosticsText reads manifest, summary, and events from a run folder' {
        $diag = Get-DiagnosticsText -RunFolder $runFolder
        ($diag -match 'run-smoke-001') -and ($diag -match 'run.complete')
    }

    SmokeCheck 'SMK-03' 'Build-RunIndex indexes all synthetic conversations' {
        $idx = Build-RunIndex -RunFolder $runFolder
        ($idx.Count -eq 3) -and ((Get-RunTotalCount -RunFolder $runFolder) -eq 3)
    }

    SmokeCheck 'SMK-04' 'Get-FilteredIndex supports direction, queue, and user pivots' {
        $inbound = @(Get-FilteredIndex -RunFolder $runFolder -Direction 'inbound')
        $support = @(Get-FilteredIndex -RunFolder $runFolder -Queue 'Support')
        $agent   = @(Get-FilteredIndex -RunFolder $runFolder -UserId 'agent-003')
        ($inbound.Count -eq 2) -and ($support.Count -eq 2) -and ($agent.Count -eq 1) -and ($agent[0].id -eq 'conv-003')
    }

    SmokeCheck 'SMK-05' 'Get-IndexedPage preserves requested cross-file record order' {
        $idx = Load-RunIndex -RunFolder $runFolder
        $page = @(Get-IndexedPage -RunFolder $runFolder -IndexEntries @($idx[2], $idx[0], $idx[1]))
        (($page | ForEach-Object { $_.conversationId }) -join ',') -eq 'conv-003,conv-002,conv-001'
    }

    SmokeCheck 'SMK-06' 'Get-ConversationRecord retrieves a full conversation by id' {
        $record = Get-ConversationRecord -RunFolder $runFolder -ConversationId 'conv-001'
        ($null -ne $record) -and ($record.attributes.caseId -eq 'CASE-123')
    }

    SmokeCheck 'SMK-06A' 'Build-RunIndex indexes envelope records with item/record conversation payloads' {
        $idx = @(Build-RunIndex -RunFolder $envelopeRunFolder)
        ($idx.Count -eq 2) -and
        (($idx | ForEach-Object { $_.id }) -join ',') -eq 'env-001,env-002' -and
        (($idx | Where-Object { $_.id -eq 'env-001' } | Select-Object -First 1).queue -eq 'Envelope Queue')
    }

    SmokeCheck 'SMK-06B' 'Get-ConversationRecord returns the unwrapped full conversation record' {
        $record = Get-ConversationRecord -RunFolder $envelopeRunFolder -ConversationId 'env-002'
        ($null -ne $record) -and
        ($record.conversationId -eq 'env-002') -and
        ($record.participants.Count -gt 0) -and
        (-not $record.PSObject.Properties['record'])
    }

    Import-AppModule 'modules\App.Database.psm1'

    SmokeCheck 'SMK-06C' 'Core artifact contract accepts supported envelope record shapes' {
        $contract = Test-CoreRunArtifactContract -RunFolder $envelopeRunFolder
        $contract.IsValid -and
        ($contract.DataRecordCount -eq 2) -and
        ($contract.ExpectedRecordCount -eq 2)
    }

    SmokeCheck 'SMK-06D' 'Drilldown resolver can load a record from run-folder fallback' {
        $resolved = Resolve-ConversationDrilldownRecord -RunFolder $envelopeRunFolder -ConversationId 'env-001'
        $resolved.Found -and
        ($resolved.Source -eq 'run-folder.jsonl') -and
        ($resolved.Record.conversationId -eq 'env-001')
    }

    Write-Host "`n--- Export ---" -ForegroundColor DarkCyan

    SmokeCheck 'SMK-07' 'Export-PageToCsv keeps a stable union of attribute columns' {
        $idx = Load-RunIndex -RunFolder $runFolder
        $records = @(Get-IndexedPage -RunFolder $runFolder -IndexEntries @($idx[0], $idx[2]))
        $csvPath = Join-Path $tempRoot 'page.csv'
        Export-PageToCsv -Records $records -OutputPath $csvPath -IncludeAttributes
        $rows = @(Import-Csv -Path $csvPath)
        ($rows.Count -eq 2) -and
        ($rows[0].PSObject.Properties['attr_priority']) -and
        ($rows[0].PSObject.Properties['attr_locale']) -and
        ($rows[0].attr_priority -eq 'high') -and
        ($rows[1].attr_locale -eq 'en-US')
    }

    SmokeCheck 'SMK-08' 'Export-RunToCsv keeps a stable union of attribute columns across files' {
        $csvPath = Join-Path $tempRoot 'run.csv'
        Export-RunToCsv -RunFolder $runFolder -OutputPath $csvPath -IncludeAttributes
        $rows = @(Import-Csv -Path $csvPath)
        ($rows.Count -eq 3) -and
        ($rows[0].PSObject.Properties['attr_caseId']) -and
        ($rows[0].PSObject.Properties['attr_priority']) -and
        ($rows[0].PSObject.Properties['attr_locale']) -and
        (($rows | Where-Object { $_.conversationId -eq 'conv-001' } | Select-Object -First 1).attr_caseId -eq 'CASE-123') -and
        (($rows | Where-Object { $_.conversationId -eq 'conv-003' } | Select-Object -First 1).attr_locale -eq 'en-US')
    }

    Write-Host "`n--- Reporting ---" -ForegroundColor DarkCyan

    SmokeCheck 'SMK-09' 'New-ImpactReport aggregates divisions, queues, agents, and time window' {
        $idx = Load-RunIndex -RunFolder $runFolder
        $report = New-ImpactReport -FilteredIndex $idx -ReportTitle 'Smoke Report'
        ($report.TotalConversations -eq 3) -and
        ($report.ImpactByDivision.Count -eq 2) -and
        ($report.ImpactByQueue.Count -eq 2) -and
        ($report.AffectedAgents.Count -eq 3) -and
        ($report.TimeWindow.Start -eq '2026-03-01T09:00:00.0000000Z') -and
        ($report.TimeWindow.End   -eq '2026-03-01T11:00:00.0000000Z')
    }

    Write-Host "`n--- Core Contract Fixture ---" -ForegroundColor DarkCyan

    Import-AppModule 'modules\App.Database.psm1'
    $coreRunFolder = New-CoreConversationRunFixture -Root $tempRoot

    SmokeCheck 'SMK-09A' 'Analyzer validates real Core conversation run artifact contract' {
        $contract = Test-CoreRunArtifactContract -RunFolder $coreRunFolder
        $manifest = Get-Content -Raw (Join-Path $coreRunFolder 'manifest.json') | ConvertFrom-Json
        $summary = Get-Content -Raw (Join-Path $coreRunFolder 'summary.json') | ConvertFrom-Json
        $dataPath = Join-Path $coreRunFolder 'data/analytics-conversation-details-query.jsonl'
        $contract.IsValid -and
        ($contract.DatasetKey -eq 'analytics-conversation-details-query') -and
        ($contract.ExpectedRecordCount -eq 2) -and
        ($contract.DataRecordCount -eq 2) -and
        ($manifest.counts.itemCount -eq 2) -and
        ($summary.totals.totalRecords -eq 2) -and
        (Test-Path $dataPath)
    }

    SmokeCheck 'SMK-09B' 'Analyzer index/display path consumes Core-produced conversation JSONL' {
        $idx = @(Build-RunIndex -RunFolder $coreRunFolder)
        $page = @(Get-IndexedPage -RunFolder $coreRunFolder -IndexEntries $idx)
        $display = @($idx | ForEach-Object { Get-ConversationDisplayRow -IndexEntry $_ })
        ($idx.Count -eq 2) -and
        (($page | ForEach-Object { $_.conversationId }) -join ',') -eq 'core-fixture-001,core-fixture-002' -and
        (($display | Where-Object { $_.ConversationId -eq 'core-fixture-001' } | Select-Object -First 1).Queue -eq 'Core Support') -and
        (($display | Where-Object { $_.ConversationId -eq 'core-fixture-002' } | Select-Object -First 1).MediaType -eq 'chat')
    }

    SmokeCheck 'SMK-09C' 'Analyzer rejects Core artifact count drift before import' {
        $badRoot = Join-Path $tempRoot 'bad-core-contract'
        Copy-Item -Path $coreRunFolder -Destination $badRoot -Recurse
        $manifestPath = Join-Path $badRoot 'manifest.json'
        $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
        $manifest.counts.itemCount = 99
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 20), [System.Text.Encoding]::UTF8)
        try {
            Test-CoreRunArtifactContract -RunFolder $badRoot -ThrowOnError | Out-Null
            return $false
        } catch {
            return ([string]$_ -match 'count mismatch')
        }
    }

    Write-Host "`n--- Database ---" -ForegroundColor DarkCyan

    $dbPath = Join-Path $tempRoot 'cases.sqlite'
    try {
        Initialize-Database -DatabasePath $dbPath -SqliteDllPath (Join-Path $AppRoot 'lib/System.Data.SQLite.dll') -AppDir $AppRoot
        $dbAvailable = $true
    } catch {
        $dbAvailable = $false
        $dbInitError = $_.Exception.Message
    }

    SmokeCheck 'SMK-10' 'Initialize-Database is available for runtime case-store tests' {
        if ($dbAvailable) { return $true }
        return [pscustomobject]@{
            Result = 'SKIP'
            Detail = $dbInitError
        }
    }

    if ($dbAvailable) {
        SmokeCheck 'SMK-11' 'Import-RunFolderToCase imports a synthetic run into the case store' {
            $caseId = New-Case -Name 'Smoke Case' -Description 'Runtime smoke'
            $script:SmokeDbCaseId = $caseId
            $import = Import-RunFolderToCase -CaseId $caseId -RunFolder $runFolder -BatchSize 2
            $count = Get-ConversationCount -CaseId $caseId
            ($import.RecordCount -eq 3) -and ($count -eq 3)
        }

        SmokeCheck 'SMK-11A' 'Import-RunFolderToCase imports Core-produced conversation artifacts with reconciled counts' {
            $caseId = New-Case -Name 'Core Fixture Case' -Description 'Core output contract runtime smoke'
            $import = Import-RunFolderToCase -CaseId $caseId -RunFolder $coreRunFolder -BatchSize 1
            $count = Get-ConversationCount -CaseId $caseId
            $support = Get-ConversationCount -CaseId $caseId -Queue 'Core Support'
            $row = Get-ConversationById -CaseId $caseId -ConversationId 'core-fixture-001'
            ($import.RecordCount -eq 2) -and
            ($import.ExpectedRecordCount -eq 2) -and
            ($import.DataRecordCount -eq 2) -and
            ($count -eq 2) -and
            ($support -eq 1) -and
            ($row.raw_json -match 'core-fixture-001') -and
            (-not [string]::IsNullOrWhiteSpace([string]$row.payload_hash))
        }

        SmokeCheck 'SMK-12' 'Re-import supersedes the prior import without duplicating conversations' {
            $caseId = $script:SmokeDbCaseId
            $second = Import-RunFolderToCase -CaseId $caseId -RunFolder $runFolder -BatchSize 2
            $imports = @(Get-Imports -CaseId $caseId)
            $count = Get-ConversationCount -CaseId $caseId
            ($second.RecordCount -eq 3) -and ($count -eq 3) -and (($imports | Where-Object { $_.status -eq 'superseded' }).Count -ge 1)
        }

        SmokeCheck 'SMK-13' 'Update-Finding preserves unmodified fields when changing status only' {
            $caseId = $script:SmokeDbCaseId
            $findingId = New-Finding -CaseId $caseId -Title 'Queue issue' -Summary 'Original summary' -Severity 'medium'
            Update-Finding -CaseId $caseId -FindingId $findingId -Status 'closed'
            $finding = Get-Findings -CaseId $caseId | Where-Object { $_.finding_id -eq $findingId } | Select-Object -First 1
            ($finding.status -eq 'closed') -and ($finding.summary -eq 'Original summary')
        }

        SmokeCheck 'SMK-14' 'DB population reports are independent of page changes' {
            $caseId = $script:SmokeDbCaseId
            $filter = [pscustomobject]@{
                StartDateTimeUtc = '2026-03-01T00:00:00Z'
                EndDateTimeUtc   = '2026-03-01T23:59:59Z'
                Direction        = 'inbound'
                MediaType        = 'voice'
                QueueText        = 'Support'
                ConversationId   = ''
                SearchText       = ''
                DisconnectType   = ''
                AgentName        = ''
                Ani              = ''
                DivisionId       = ''
                ColumnFilters    = @{}
                SortBy           = 'conversation_start'
                SortDirection    = 'ASC'
            }
            $page1 = @(Get-ConversationsPage -CaseId $caseId -FilterState $filter -PageNumber 1 -PageSize 1)
            $page2 = @(Get-ConversationsPage -CaseId $caseId -FilterState $filter -PageNumber 2 -PageSize 1)
            $rowsA = @(Get-ConversationPopulationRows -CaseId $caseId -FilterState $filter)
            $rowsB = @(Get-ConversationPopulationRows -CaseId $caseId -FilterState $filter)
            $reportA = New-PopulationReport -Rows $rowsA -FilterState $filter -Summary (Get-ConversationPopulationSummary -CaseId $caseId -FilterState $filter)
            $reportB = New-PopulationReport -Rows $rowsB -FilterState $filter -Summary (Get-ConversationPopulationSummary -CaseId $caseId -FilterState $filter)
            ($page1.Count -eq 1) -and ($page2.Count -eq 1) -and
            ($reportA.TotalConversations -eq 2) -and ($reportB.TotalConversations -eq 2)
        }

        SmokeCheck 'SMK-15' 'SQL-backed column filters keep counts and pages aligned' {
            $caseId = $script:SmokeDbCaseId
            $filter = [pscustomobject]@{
                StartDateTimeUtc = ''
                EndDateTimeUtc   = ''
                Direction        = ''
                MediaType        = ''
                QueueText        = ''
                ConversationId   = ''
                SearchText       = ''
                DisconnectType   = ''
                AgentName        = ''
                Ani              = ''
                DivisionId       = ''
                ColumnFilters    = @{ Queue = 'Support' }
                SortBy           = 'conversation_start'
                SortDirection    = 'ASC'
            }
            $count = Get-ConversationCount -CaseId $caseId -FilterState $filter
            $page = @(Get-ConversationsPage -CaseId $caseId -FilterState $filter -PageNumber 1 -PageSize 10)
            ($count -eq 2) -and ($page.Count -eq 2) -and (@($page | Where-Object { $_.queue_name -ne 'Support' }).Count -eq 0)
        }

        SmokeCheck 'SMK-16' 'DB drilldown source row stores canonical raw JSON' {
            $caseId = $script:SmokeDbCaseId
            $row = Get-ConversationById -CaseId $caseId -ConversationId 'conv-001'
            $raw = $row.raw_json | ConvertFrom-Json
            ($raw.conversationId -eq 'conv-001') -and (-not [string]::IsNullOrWhiteSpace([string]$row.payload_hash))
        }

        SmokeCheck 'SMK-16A' 'Get-ConversationsPage and display row expose a non-empty ConversationId after import' {
            $caseId = $script:SmokeDbCaseId
            $page = @(Get-ConversationsPage -CaseId $caseId -PageNumber 1 -PageSize 1)
            $display = Get-DbConversationDisplayRow -DbRow $page[0]
            ($page.Count -eq 1) -and
            (-not [string]::IsNullOrWhiteSpace([string]$display.ConversationId))
        }

        SmokeCheck 'SMK-16B' 'Drilldown resolver can load a record from DB raw_json' {
            $caseId = $script:SmokeDbCaseId
            $resolved = Resolve-ConversationDrilldownRecord -CaseId $caseId -RunFolder $runFolder -ConversationId 'conv-001'
            $resolved.Found -and
            ($resolved.Source -eq 'database.raw_json') -and
            ($resolved.Record.conversationId -eq 'conv-001')
        }

        SmokeCheck 'SMK-17' 'Reimports preserve conversation lineage versions' {
            $caseId = $script:SmokeDbCaseId
            $versions = @(Get-ConversationVersions -CaseId $caseId -ConversationId 'conv-001')
            ($versions.Count -ge 2) -and (@($versions | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.payload_hash) }).Count -eq 0)
        }

        SmokeCheck 'SMK-18' 'Saved views can restore identical filter state and result count' {
            $caseId = $script:SmokeDbCaseId
            $filter = [pscustomobject]@{
                StartDateTimeUtc = ''
                EndDateTimeUtc   = ''
                Direction        = ''
                MediaType        = ''
                QueueText        = 'Billing'
                ConversationId   = ''
                SearchText       = ''
                DisconnectType   = ''
                AgentName        = ''
                Ani              = ''
                DivisionId       = 'division-a'
                ColumnFilters    = @{}
                SortBy           = 'conversation_start'
                SortDirection    = 'DESC'
            }
            $expected = Get-ConversationCount -CaseId $caseId -FilterState $filter
            New-SavedView -CaseId $caseId -Name 'Billing division view' -ViewDefinition ([pscustomobject]@{ canonical_filter = $filter }) | Out-Null
            $saved = Get-SavedViews -CaseId $caseId | Where-Object { $_.name -eq 'Billing division view' } | Select-Object -First 1
            $restored = ($saved.filters_json | ConvertFrom-Json).canonical_filter
            $actual = Get-ConversationCount -CaseId $caseId -FilterState $restored
            ($expected -eq 1) -and ($actual -eq $expected)
        }

        SmokeCheck 'SMK-19' 'Core DB analytics helpers stay responsive on warm smoke data' {
            $caseId = $script:SmokeDbCaseId
            $filter = [pscustomobject]@{
                StartDateTimeUtc = ''
                EndDateTimeUtc   = ''
                Direction        = ''
                MediaType        = ''
                QueueText        = ''
                ConversationId   = ''
                SearchText       = ''
                DisconnectType   = ''
                AgentName        = ''
                Ani              = ''
                DivisionId       = ''
                ColumnFilters    = @{}
                SortBy           = 'conversation_start'
                SortDirection    = 'DESC'
            }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $count = Get-ConversationCount -CaseId $caseId -FilterState $filter
            $page = @(Get-ConversationsPage -CaseId $caseId -FilterState $filter -PageNumber 1 -PageSize 50)
            $summary = Get-ConversationPopulationSummary -CaseId $caseId -FilterState $filter
            $sw.Stop()
            ($count -eq 3) -and ($page.Count -eq 3) -and ($summary.total_conversations -eq 3) -and ($sw.ElapsedMilliseconds -lt 1000)
        }
    }
} finally {
    if ($null -ne $oldLocalAppData) {
        $env:LOCALAPPDATA = $oldLocalAppData
    } else {
        Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
    }

    if ([System.IO.Directory]::Exists($tempRoot)) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

return $script:Results.ToArray()
