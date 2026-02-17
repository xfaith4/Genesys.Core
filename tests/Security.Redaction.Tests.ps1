Describe 'Request logging redaction' {
    BeforeAll {
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1"
        . "$PSScriptRoot/../src/ps-module/Genesys.Core/Private/Invoke-GcRequest.ps1"
    }

    It 'redacts sensitive headers and query parameters in request events' {
        Mock -CommandName Invoke-RestMethod -MockWith {
            return [pscustomobject]@{ ok = $true }
        }

        $runEvents = [System.Collections.Generic.List[object]]::new()

        $null = Invoke-GcRequest -Uri 'https://api.test.local/api/v2/example?token=abc123&name=ok' -Method 'GET' -Headers @{
            Authorization = 'Bearer super-secret-token'
            'Client-Id' = 'public-client'
        } -RunEvents $runEvents -MaxRetries 0

        $requestEvent = @($runEvents | Where-Object { $_.eventType -eq 'request.invoked' }) | Select-Object -First 1

        $requestEvent | Should -Not -BeNullOrEmpty
        $requestEvent.headers.Authorization | Should -Be '[REDACTED]'
        $requestEvent.headers.'Client-Id' | Should -Be 'public-client'
        $requestEvent.uri | Should -Match 'token=\[REDACTED\]'
        $requestEvent.uri | Should -Match 'name=ok'
    }
}
