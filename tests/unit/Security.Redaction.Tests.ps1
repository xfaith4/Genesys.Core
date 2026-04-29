Describe 'Request logging redaction' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Transport.ps1"
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
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Redaction.ps1"
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

Describe 'Profile-driven record redaction' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Redaction.ps1"
    }

    It 'removes fields listed in profile removeFields' {
        $profile = @{
            removeFields = @('chat', 'addresses', 'biography')
        }
        $record = [pscustomobject]@{
            id        = 'user-guid-123'
            name      = 'Jane Doe'
            chat      = @{ jabberId = 'jane@chat.local' }
            addresses = @()
            biography = 'Ten years in contact centre ops.'
            department = 'Support'
        }

        $sanitized = Protect-RecordData -InputObject $record -Profile $profile

        $sanitized.id        | Should -Be 'user-guid-123'
        $sanitized.name      | Should -Be 'Jane Doe'
        $sanitized.department | Should -Be 'Support'
        $sanitized.chat      | Should -Be '[REDACTED]'
        $sanitized.addresses | Should -Be '[REDACTED]'
        $sanitized.biography | Should -Be '[REDACTED]'
    }

    It 'applies heuristic redaction for fields not listed in profile' {
        $profile = @{
            removeFields = @('chat')
        }
        $record = [pscustomobject]@{
            id    = 'user-guid-456'
            email = 'jane@example.com'
            chat  = 'chat-handle'
            note  = 'safe'
        }

        $sanitized = Protect-RecordData -InputObject $record -Profile $profile

        # 'email' is caught by the heuristic even though it is not in removeFields
        $sanitized.email | Should -Be '[REDACTED]'
        # 'chat' is caught by the profile
        $sanitized.chat  | Should -Be '[REDACTED]'
        $sanitized.note  | Should -Be 'safe'
    }

    It 'behaves identically to no-profile call when Profile is null' {
        $record = [pscustomobject]@{
            id    = 'user-guid-789'
            email = 'bob@example.com'
            note  = 'safe'
        }

        $withNull    = Protect-RecordData -InputObject $record -Profile $null
        $withoutParam = Protect-RecordData -InputObject $record

        $withNull.email    | Should -Be '[REDACTED]'
        $withoutParam.email | Should -Be '[REDACTED]'
        $withNull.note     | Should -Be 'safe'
        $withoutParam.note | Should -Be 'safe'
    }

    It 'threads the profile through nested objects' {
        $profile = @{
            removeFields = @('participantName', 'address')
        }
        $record = [pscustomobject]@{
            conversationId = 'conv-001'
            participants   = @(
                [pscustomobject]@{
                    participantName = 'Agent Smith'
                    address         = 'sip:agent@example.com'
                    purpose         = 'agent'
                }
            )
        }

        $sanitized = Protect-RecordData -InputObject $record -Profile $profile

        $sanitized.conversationId | Should -Be 'conv-001'
        $p = $sanitized.participants[0]
        $p.participantName | Should -Be '[REDACTED]'
        $p.address         | Should -Be '[REDACTED]'
        $p.purpose         | Should -Be 'agent'
    }
}

Describe 'Resolve-DatasetRedactionProfile' {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Genesys.Core/Private/Redaction.ps1"
    }

    It 'returns null when catalog is null' {
        Resolve-DatasetRedactionProfile -Catalog $null -DatasetKey 'users' | Should -BeNullOrEmpty
    }

    It 'returns null when dataset has no redactionProfile field' {
        $catalog = [pscustomobject]@{
            datasets = @{
                'no-profile-dataset' = [pscustomobject]@{ endpoint = 'x'; itemsPath = '$' }
            }
            profiles = [pscustomobject]@{
                redaction = [pscustomobject]@{}
            }
        }
        Resolve-DatasetRedactionProfile -Catalog $catalog -DatasetKey 'no-profile-dataset' | Should -BeNullOrEmpty
    }

    It 'returns the named profile when declared on the dataset entry' {
        $catalog = [pscustomobject]@{
            datasets = @{
                'my-dataset' = [pscustomobject]@{
                    endpoint         = 'x'
                    itemsPath        = '$'
                    redactionProfile = 'my-profile'
                }
            }
            profiles = [pscustomobject]@{
                redaction = [pscustomobject]@{
                    'my-profile' = [pscustomobject]@{
                        removeFields = @('secret', 'token')
                    }
                }
            }
        }
        $profile = Resolve-DatasetRedactionProfile -Catalog $catalog -DatasetKey 'my-dataset'
        $profile              | Should -Not -BeNullOrEmpty
        $profile['removeFields'] | Should -Contain 'secret'
        $profile['removeFields'] | Should -Contain 'token'
    }
}

