Describe 'Phase 4 endpoint expansion catalog coverage' {
    BeforeAll {
        $catalogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../catalog/genesys.catalog.json'
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
    }

    It 'contains planned Phase 4 endpoints with schema-compatible metadata' {
        $expectedEndpoints = @(
            'authorization.get.roles',
            'conversations.get.recordings',
            'oauth.get.clients',
            'oauth.post.client.usage.query',
            'oauth.get.client.usage.query.results',
            'speechandtextanalytics.get.topics',
            'analytics.post.transcripts.aggregates.query',
            'speechandtextanalytics.get.conversation.communication.transcripturl'
        )

        foreach ($endpointKey in $expectedEndpoints) {
            $catalog.endpoints.PSObject.Properties.Name | Should -Contain $endpointKey
            $endpoint = $catalog.endpoints.$endpointKey
            [string]::IsNullOrWhiteSpace([string]$endpoint.method) | Should -BeFalse
            [string]::IsNullOrWhiteSpace([string]$endpoint.path) | Should -BeFalse
            [string]::IsNullOrWhiteSpace([string]$endpoint.itemsPath) | Should -BeFalse
            [string]::IsNullOrWhiteSpace([string]$endpoint.pagingProfile) | Should -BeFalse
            [string]::IsNullOrWhiteSpace([string]$endpoint.retryProfile) | Should -BeFalse
        }
    }

    It 'registers Phase 4 datasets with deterministic paging and retry profiles' {
        $expectedDatasets = @(
            'authorization.get.roles',
            'conversations.get.recordings',
            'oauth.get.clients',
            'oauth.post.client.usage.query',
            'oauth.get.client.usage.query.results',
            'speechandtextanalytics.get.topics',
            'analytics.post.transcripts.aggregates.query',
            'speechandtextanalytics.get.conversation.communication.transcripturl'
        )

        foreach ($datasetKey in $expectedDatasets) {
            $catalog.datasets.PSObject.Properties.Name | Should -Contain $datasetKey
            $dataset = $catalog.datasets.$datasetKey
            $catalog.endpoints.PSObject.Properties.Name | Should -Contain $dataset.endpoint
            $catalog.profiles.paging.PSObject.Properties.Name | Should -Contain $dataset.paging.profile
            $catalog.profiles.retry.PSObject.Properties.Name | Should -Contain $dataset.retry.profile
        }
    }
}


