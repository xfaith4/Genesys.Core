Describe 'Dataset runtime parameter resolution' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Datasets/Resolve-DatasetRuntime.ps1"
    }

    It 'builds interval from StartUtc/EndUtc' {
        $interval = Resolve-DatasetInterval -DatasetParameters @{ StartUtc = '2026-02-20T00:00:00Z'; EndUtc = '2026-02-20T01:00:00Z' } -DefaultLookbackHours 24
        $interval | Should -Be '2026-02-20T00:00:00.0000000Z/2026-02-20T01:00:00.0000000Z'
    }

    It 'rejects invalid lookback hours' {
        { Resolve-DatasetInterval -DatasetParameters @{ LookbackHours = 0 } -DefaultLookbackHours 24 } | Should -Throw '*LookbackHours must be between 1 and 720*'
    }

    It 'returns plain map for hashtable and PSCustomObject query input' {
        $a = ConvertTo-PlainOrderedMap -InputObject @{ pageSize = 100; state = 'inactive' }
        $a.pageSize | Should -Be 100
        $a.state | Should -Be 'inactive'

        $b = ConvertTo-PlainOrderedMap -InputObject ([pscustomobject]@{ pageSize = 50; state = 'active' })
        $b.pageSize | Should -Be 50
        $b.state | Should -Be 'active'
    }
}

