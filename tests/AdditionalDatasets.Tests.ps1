Describe 'Additional dataset implementations' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../src/ps-module/Genesys.Core/Genesys.Core.psd1" -Force
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Datasets/DatasetRegistry.ps1"
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../genesys-core.catalog.json'
    }

    It 'registers users and routing-queues datasets' {
        $registry = Get-DatasetRegistry
        $registry.ContainsKey('users') | Should -BeTrue
        $registry.ContainsKey('routing-queues') | Should -BeTrue
    }

    It 'runs users dataset with nextUri paging and normalized output' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-users'
        $requestInvoker = {
            param($request)
            if ($request.Uri -eq 'https://api.test.local/api/v2/users') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @(
                        [pscustomobject]@{ id='u1'; name='User One'; email='u1@example.com'; state='active'; presence=[pscustomobject]@{ presenceDefinition=[pscustomobject]@{ systemPresence='AVAILABLE' } }; routingStatus=[pscustomobject]@{ status='IDLE' } }
                    )
                    nextUri = 'https://api.test.local/api/v2/users?pageNumber=2'
                } }
            }
            if ($request.Uri -eq 'https://api.test.local/api/v2/users?pageNumber=2') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @(
                        [pscustomobject]@{ id='u2'; name='User Two'; email='u2@example.com'; state='inactive'; presence=[pscustomobject]@{ presenceDefinition=[pscustomobject]@{ systemPresence='OFFLINE' } }; routingStatus=[pscustomobject]@{ status='NOT_RESPONDING' } }
                    )
                    nextUri = $null
                } }
            }
            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'users' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null
        $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'users') -Directory | Select-Object -First 1
        $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/users.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        $records.Count | Should -Be 2
        $records[0].recordType | Should -Be 'user'
        $records[0].presence | Should -Be 'AVAILABLE'

        $events = Get-Content -Path (Join-Path $runFolder.FullName 'events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        (@($events | Where-Object { $_.eventType -eq 'paging.progress' })).Count | Should -Be 2
    }

    It 'runs routing-queues dataset and normalizes records' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-queues'
        $requestInvoker = {
            param($request)
            if ($request.Uri -eq 'https://api.test.local/api/v2/routing/queues') {
                return [pscustomobject]@{ Result = [pscustomobject]@{
                    entities = @(
                        [pscustomobject]@{ id='q1'; name='Support'; memberCount=12; joined=$true; division=[pscustomobject]@{ id='d1' } }
                    )
                    nextUri = $null
                } }
            }
            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'routing-queues' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null
        $runFolder = Get-ChildItem -Path (Join-Path $outputRoot 'routing-queues') -Directory | Select-Object -First 1
        $records = Get-Content -Path (Join-Path $runFolder.FullName 'data/routing-queues.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
        $records.Count | Should -Be 1
        $records[0].recordType | Should -Be 'routingQueue'
        $records[0].divisionId | Should -Be 'd1'
    }
}
