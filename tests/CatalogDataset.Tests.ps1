Describe 'Catalog-driven datasets' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../src/ps-module/Genesys.Core/Genesys.Core.psd1" -Force
    }

    It 'runs audit-service-mapping dataset through generic runner' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../catalog/genesys-core.catalog.json'

        $requestInvoker = {
            param($request)

            if ($request.Method -eq 'GET' -and $request.Uri -eq 'https://api.test.local/api/v2/audits/query/servicemapping') {
                return [pscustomobject]@{ Result = @('routing', 'platform') }
            }

            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'audit-service-mapping' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null

        $datasetFolder = Join-Path -Path $outputRoot -ChildPath 'audit-service-mapping'
        $runFolder = Get-ChildItem -Path $datasetFolder -Directory | Select-Object -First 1
        $dataPath = Join-Path -Path $runFolder.FullName -ChildPath 'data/service-mapping.jsonl'
        Test-Path -Path $dataPath | Should -BeTrue

        $records = @(Get-Content -Path $dataPath)
        $records.Count | Should -Be 2

        $summaryPath = Join-Path -Path $runFolder.FullName -ChildPath 'summary.json'
        $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json
        $summary.totals.totalRecords | Should -Be 2
    }

    It 'runs bodyPaging dataset with nested paging path from catalog' {
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../catalog/genesys-core.catalog.json'
        $requestBodies = [System.Collections.Generic.List[object]]::new()

        $requestInvoker = {
            param($request)

            if ($request.Method -eq 'POST' -and $request.Uri -eq 'https://api.test.local/api/v2/analytics/conversations/details/query') {
                $body = ConvertFrom-Json -InputObject $request.Body
                $requestBodies.Add($body) | Out-Null

                if ($body.paging.pageNumber -eq 1) {
                    return [pscustomobject]@{ Result = [pscustomobject]@{ conversations = @('c1', 'c2'); totalHits = 3 } }
                }

                if ($body.paging.pageNumber -eq 2) {
                    return [pscustomobject]@{ Result = [pscustomobject]@{ conversations = @('c3'); totalHits = 3 } }
                }
            }

            throw "Unexpected request: $($request.Method) $($request.Uri)"
        }

        Invoke-Dataset -Dataset 'analytics-conversation-details' -CatalogPath $catalogPath -OutputRoot $outputRoot -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null

        $datasetFolder = Join-Path -Path $outputRoot -ChildPath 'analytics-conversation-details'
        $runFolder = Get-ChildItem -Path $datasetFolder -Directory | Select-Object -First 1
        $dataPath = Join-Path -Path $runFolder.FullName -ChildPath 'data/analytics-conversation-details.jsonl'
        Test-Path -Path $dataPath | Should -BeTrue

        $records = @(Get-Content -Path $dataPath)
        $records.Count | Should -Be 3
        $requestBodies.Count | Should -Be 2
        $requestBodies[0].paging.pageNumber | Should -Be 1
        $requestBodies[1].paging.pageNumber | Should -Be 2
    }
}
