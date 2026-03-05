Describe 'Request logging redaction' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Retry/Invoke-WithRetry.ps1"
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Invoke-GcRequest.ps1"
    }

    It 'redacts sensitive headers and query parameters in request events' {
        Mock -CommandName Invoke-WithRetry -MockWith {
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
        $requestEvent.uri | Should -Match 'token=(\[REDACTED\]|%5BREDACTED%5D)'
        $requestEvent.uri | Should -Match 'name=ok'
    }
}


Describe 'Record payload redaction hardening' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Redaction/Protect-RecordData.ps1"
    }

    It 'redacts embedded bearer and query token strings while preserving non-sensitive text' {
        $record = [pscustomobject]@{
            message = 'Authorization: Bearer top-secret-token'
            callback = 'https://example.local/callback?access_token=abc123&name=ok'
            note = 'safe text'
        }

        $sanitized = Protect-RecordData -InputObject $record

        $sanitized.message | Should -Be 'Authorization: Bearer [REDACTED]'
        $sanitized.callback | Should -Be 'https://example.local/callback?access_token=[REDACTED]&name=ok'
        $sanitized.note | Should -Be 'safe text'
    }
}

