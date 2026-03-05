<#
.SYNOPSIS
    Runs all registered datasets against rich mock API responses and writes real output
    artifacts to $OutputRoot for visual inspection and downstream schema validation.

.DESCRIPTION
    No live credentials required. The requestInvoker scriptblock intercepts every
    HTTP call and returns realistic Genesys-shaped payloads including:
      - Multi-page audit log results with PII fields (email, userId) that show
        redaction in action.
      - Multi-page analytics conversation details with cursor paging, multiple
        participants and segments across voice/chat/email media types.
      - Users with presence/routingStatus, normalized to flat records.
      - Routing queues with division and memberCount.
      - Analytics conversation details via direct POST query (body paging).

    Arrays that contain a single element use the unary-comma prefix ,([item])
    so they serialize correctly as [...] rather than collapsing to plain objects.

    After the run, the script prints a structured report showing every output file
    path and a preview of each summary.json so the design can be evaluated quickly.

.PARAMETER OutputRoot
    Destination folder for run artifacts. Defaults to 'out-mock' in the repo root.

.PARAMETER Datasets
    Optional dataset keys to run. Defaults to all datasets with built-in mock invokers.

.PARAMETER NoRedact
    When set, PII fields are written to output files without redaction. Useful for
    inspecting the full data shape during design. Omit for the default safe output.

.PARAMETER NoReport
    When set, skip the detailed artifact report section and print only run status.

.EXAMPLE
    pwsh -NoProfile -File ./scripts/Invoke-MockRun.ps1
    pwsh -NoProfile -File ./scripts/Invoke-MockRun.ps1 -NoRedact
    pwsh -NoProfile -File ./scripts/Invoke-MockRun.ps1 -OutputRoot ./out/mock-custom
#>
[CmdletBinding()]
param(
    [string]$OutputRoot = 'out/mock',
    [string[]]$Datasets,
    [switch]$NoRedact,
    [switch]$NoReport
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Import-Module "$repoRoot/modules/Genesys.Core/Genesys.Core.psd1" -Force

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
function Write-Section ([string]$Title) {
    Write-Host ''
    Write-Host ("  $Title") -ForegroundColor Cyan
    Write-Host ("  " + ('-' * ($Title.Length))) -ForegroundColor DarkGray
}

function Write-Ok    ([string]$Msg) { Write-Host "    [OK]  $Msg" -ForegroundColor Green  }
function Write-Info  ([string]$Msg) { Write-Host "    [>>]  $Msg" -ForegroundColor Gray   }
function Write-Warn  ([string]$Msg) { Write-Host "    [!!]  $Msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Mock timestamps (fixed window so output is deterministic)
# ---------------------------------------------------------------------------
$d = '2026-02-'   # date prefix shorthand

# ---------------------------------------------------------------------------
# AUDIT LOGS — mock requestInvoker
# ---------------------------------------------------------------------------
$auditRequestInvoker = {
    param($request)
    $uri    = [string]$request.Uri
    $method = [string]$request.Method

    # Service mapping
    if ($method -eq 'GET' -and $uri -like '*/audits/query/servicemapping') {
        return [pscustomobject]@{ Result = @(
            [pscustomobject]@{ serviceName = 'routing'   }
            [pscustomobject]@{ serviceName = 'quality'   }
            [pscustomobject]@{ serviceName = 'architect' }
            [pscustomobject]@{ serviceName = 'platform'  }
        ) }
    }

    # Submit async audit query — any POST body accepted
    if ($method -eq 'POST' -and $uri -like '*/audits/query') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'mock-audit-tx-001' } }
    }

    # Status polling — return RUNNING once, then FULFILLED
    if ($method -eq 'GET' -and $uri -like '*/audits/query/mock-audit-tx-001' -and $uri -notlike '*/results*') {
        if (-not $script:auditPolled) {
            $script:auditPolled = $true
            return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'RUNNING' } }
        }
        return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
    }

    # Results page 1
    if ($method -eq 'GET' -and $uri -like '*/audits/query/mock-audit-tx-001/results' -and $uri -notlike '*pageNumber=2*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            results = @(
                [pscustomobject]@{
                    id          = 'audit-r001'
                    timestamp   = "${d}13T08:14:22.000Z"
                    serviceName = 'routing'
                    action      = 'CREATE'
                    userId      = 'a1b2c3d4-0001-0001-0001-aabbccddeeff'
                    userEmail   = 'jane.admin@corp.example.com'
                    userName    = 'Jane Admin'
                    remoteIp    = '10.0.1.42'
                    context     = [pscustomobject]@{
                        entityId   = 'queueid-0001-0001-0001-aabbccddeeff'
                        entityName = 'Tier-1 Support'
                        type       = 'Queue'
                    }
                }
                [pscustomobject]@{
                    id          = 'audit-r002'
                    timestamp   = "${d}14T09:31:05.000Z"
                    serviceName = 'quality'
                    action      = 'CREATE'
                    userId      = 'a1b2c3d4-0002-0002-0002-aabbccddeeff'
                    userEmail   = 'bob.qm@corp.example.com'
                    userName    = 'Bob QM'
                    remoteIp    = '10.0.1.55'
                    context     = [pscustomobject]@{
                        entityId   = 'evalid-0002-0002-0002-aabbccddeeff'
                        entityName = 'Agent Call Review'
                        type       = 'EvaluationForm'
                    }
                }
                [pscustomobject]@{
                    id          = 'audit-r003'
                    timestamp   = "${d}15T11:02:44.000Z"
                    serviceName = 'routing'
                    action      = 'UPDATE'
                    userId      = 'a1b2c3d4-0001-0001-0001-aabbccddeeff'
                    userEmail   = 'jane.admin@corp.example.com'
                    userName    = 'Jane Admin'
                    remoteIp    = '10.0.1.42'
                    context     = [pscustomobject]@{
                        entityId   = 'queueid-0001-0001-0001-aabbccddeeff'
                        entityName = 'Tier-1 Support'
                        type       = 'Queue'
                        # unary comma keeps single-element changes as JSON array [...]
                        changes    = ,([pscustomobject]@{ field = 'memberCount'; before = '8'; after = '10' })
                    }
                }
                [pscustomobject]@{
                    id          = 'audit-r004'
                    timestamp   = "${d}16T13:47:18.000Z"
                    serviceName = 'architect'
                    action      = 'UPDATE'
                    userId      = 'a1b2c3d4-0003-0003-0003-aabbccddeeff'
                    userEmail   = 'carol.dev@corp.example.com'
                    userName    = 'Carol Dev'
                    remoteIp    = '10.0.2.11'
                    context     = [pscustomobject]@{
                        entityId   = 'flowid-0003-0003-0003-aabbccddeeff'
                        entityName = 'Inbound Main IVR'
                        type       = 'InboundCallFlow'
                    }
                }
            )
            nextUri   = "$($uri)?pageNumber=2"
            totalHits = 6
        } }
    }

    # Results page 2
    if ($method -eq 'GET' -and $uri -like '*pageNumber=2*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            results = @(
                [pscustomobject]@{
                    id            = 'audit-r005'
                    timestamp     = "${d}18T16:22:09.000Z"
                    serviceName   = 'platform'
                    action        = 'DELETE'
                    userId        = 'a1b2c3d4-0004-0004-0004-aabbccddeeff'
                    userEmail     = 'svc.automation@corp.example.com'
                    userName      = 'Automation Service'
                    remoteIp      = '10.0.3.200'
                    authorization = 'Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.PAYLOAD.SIGNATURE'
                    context       = [pscustomobject]@{
                        entityId   = 'sessionid-0004-0004-aabbccddeeff'
                        entityName = 'OAuth Session'
                        type       = 'OAuthSession'
                    }
                }
                [pscustomobject]@{
                    id          = 'audit-r006'
                    timestamp   = "${d}20T07:55:33.000Z"
                    serviceName = 'routing'
                    action      = 'VIEW'
                    userId      = 'a1b2c3d4-0005-0005-0005-aabbccddeeff'
                    userEmail   = 'dan.supervisor@corp.example.com'
                    userName    = 'Dan Supervisor'
                    remoteIp    = '10.0.1.88'
                    context     = [pscustomobject]@{
                        entityId   = 'queueid-0001-0001-0001-aabbccddeeff'
                        entityName = 'Tier-1 Support'
                        type       = 'Queue'
                    }
                }
            )
            nextUri   = $null
            totalHits = 6
        } }
    }

    throw "Unexpected audit mock request: $method $uri"
}

# ---------------------------------------------------------------------------
# ANALYTICS CONVERSATION DETAILS — mock requestInvoker
#
# Unary comma prefix ,([pscustomobject]@{...}) forces single-element arrays
# to stay typed as Object[] so ConvertTo-Json outputs [...] not {...}
# ---------------------------------------------------------------------------
$analyticsRequestInvoker = {
    param($request)
    $uri    = [string]$request.Uri
    $method = [string]$request.Method

    # Submit async job
    if ($method -eq 'POST' -and $uri -like '*/analytics/conversations/details/jobs') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ jobId = 'mock-conv-job-001' } }
    }

    # Status polling
    if ($method -eq 'GET' -and $uri -like '*/details/jobs/mock-conv-job-001' -and $uri -notlike '*/results*') {
        if (-not $script:analyticsPolled) {
            $script:analyticsPolled = $true
            return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'RUNNING' } }
        }
        return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
    }

    # Results page 1 (no cursor yet) — 3 conversations
    if ($method -eq 'GET' -and $uri -like '*/details/jobs/mock-conv-job-001/results' -and $uri -notlike '*cursor=*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            conversations = @(

                # --- Voice: inbound, IVR hand-off to agent ---
                [pscustomobject]@{
                    conversationId       = 'conv-v001-voice-inbound'
                    conversationStart    = "${d}14T09:00:00.000Z"
                    conversationEnd      = "${d}14T09:14:27.000Z"
                    originatingDirection = 'inbound'
                    participants         = @(
                        [pscustomobject]@{
                            participantId   = 'part-v001-ivr'
                            participantName = 'IVR'
                            purpose         = 'ivr'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-v001-ivr'
                                mediaType = 'voice'
                                direction = 'inbound'
                                dnis      = '+18005551000'
                                ani       = '+14155550101'
                                segments  = ,([pscustomobject]@{
                                    segmentStart = "${d}14T09:00:00.000Z"
                                    segmentEnd   = "${d}14T09:01:15.000Z"
                                    segmentType  = 'system'
                                })
                            })
                        }
                        [pscustomobject]@{
                            participantId   = 'part-v001-customer'
                            participantName = 'Customer'
                            purpose         = 'customer'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-v001-customer'
                                mediaType = 'voice'
                                direction = 'inbound'
                                dnis      = '+18005551000'
                                ani       = '+14155550101'
                                segments  = ,([pscustomobject]@{
                                    segmentStart   = "${d}14T09:00:00.000Z"
                                    segmentEnd     = "${d}14T09:14:27.000Z"
                                    segmentType    = 'interact'
                                    disconnectType = 'client'
                                })
                            })
                        }
                        [pscustomobject]@{
                            participantId   = 'part-v001-agent'
                            participantName = 'Alice Support'
                            purpose         = 'agent'
                            userId          = 'user-agent-0001-alice'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-v001-agent'
                                mediaType = 'voice'
                                direction = 'inbound'
                                segments  = @(
                                    [pscustomobject]@{ segmentStart = "${d}14T09:01:15.000Z"; segmentEnd = "${d}14T09:11:42.000Z"; segmentType = 'interact' }
                                    [pscustomobject]@{ segmentStart = "${d}14T09:11:42.000Z"; segmentEnd = "${d}14T09:14:27.000Z"; segmentType = 'wrap-up'  }
                                )
                            })
                        }
                    )
                }

                # --- Chat: inbound, transferred between two agents ---
                [pscustomobject]@{
                    conversationId       = 'conv-c002-chat-transfer'
                    conversationStart    = "${d}15T13:30:00.000Z"
                    conversationEnd      = "${d}15T14:01:05.000Z"
                    originatingDirection = 'inbound'
                    participants         = @(
                        [pscustomobject]@{
                            participantId   = 'part-c002-customer'
                            participantName = 'Customer'
                            purpose         = 'customer'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-c002-customer'
                                mediaType = 'chat'
                                direction = 'inbound'
                                segments  = ,([pscustomobject]@{
                                    segmentStart   = "${d}15T13:30:00.000Z"
                                    segmentEnd     = "${d}15T14:01:05.000Z"
                                    segmentType    = 'interact'
                                    disconnectType = 'client'
                                })
                            })
                        }
                        [pscustomobject]@{
                            participantId   = 'part-c002-agent1'
                            participantName = 'Bob Chat'
                            purpose         = 'agent'
                            userId          = 'user-agent-0002-bob'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-c002-agent1'
                                mediaType = 'chat'
                                direction = 'inbound'
                                segments  = @(
                                    [pscustomobject]@{ segmentStart = "${d}15T13:30:00.000Z"; segmentEnd = "${d}15T13:48:20.000Z"; segmentType = 'interact' }
                                    [pscustomobject]@{ segmentStart = "${d}15T13:48:20.000Z"; segmentEnd = "${d}15T13:50:00.000Z"; segmentType = 'wrap-up'  }
                                )
                            })
                        }
                        [pscustomobject]@{
                            participantId   = 'part-c002-agent2'
                            participantName = 'Carol Specialist'
                            purpose         = 'agent'
                            userId          = 'user-agent-0003-carol'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-c002-agent2'
                                mediaType = 'chat'
                                direction = 'inbound'
                                segments  = ,([pscustomobject]@{
                                    segmentStart = "${d}15T13:50:00.000Z"
                                    segmentEnd   = "${d}15T14:01:05.000Z"
                                    segmentType  = 'interact'
                                })
                            })
                        }
                    )
                }

                # --- Voice: outbound, agent-initiated, customer put on hold ---
                [pscustomobject]@{
                    conversationId       = 'conv-v003-voice-outbound'
                    conversationStart    = "${d}17T10:05:00.000Z"
                    conversationEnd      = "${d}17T10:23:12.000Z"
                    originatingDirection = 'outbound'
                    participants         = @(
                        [pscustomobject]@{
                            participantId   = 'part-v003-customer'
                            participantName = 'Customer'
                            purpose         = 'customer'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-v003-customer'
                                mediaType = 'voice'
                                direction = 'outbound'
                                segments  = ,([pscustomobject]@{
                                    segmentStart   = "${d}17T10:05:00.000Z"
                                    segmentEnd     = "${d}17T10:23:12.000Z"
                                    segmentType    = 'interact'
                                    disconnectType = 'endpoint'
                                })
                            })
                        }
                        [pscustomobject]@{
                            participantId   = 'part-v003-agent'
                            participantName = 'Dan Outreach'
                            purpose         = 'agent'
                            userId          = 'user-agent-0004-dan'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-v003-agent'
                                mediaType = 'voice'
                                direction = 'outbound'
                                segments  = @(
                                    [pscustomobject]@{ segmentStart = "${d}17T10:05:00.000Z"; segmentEnd = "${d}17T10:14:00.000Z"; segmentType = 'interact' }
                                    [pscustomobject]@{ segmentStart = "${d}17T10:14:00.000Z"; segmentEnd = "${d}17T10:16:30.000Z"; segmentType = 'hold'     }
                                    [pscustomobject]@{ segmentStart = "${d}17T10:16:30.000Z"; segmentEnd = "${d}17T10:23:12.000Z"; segmentType = 'interact' }
                                )
                            })
                        }
                    )
                }
            )
            cursor = 'cursor-page-2-mock'
        } }
    }

    # Results page 2 (cursor present) — 2 conversations
    if ($method -eq 'GET' -and $uri -like '*cursor=cursor-page-2-mock*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            conversations = @(

                # --- Email: inbound, single agent reply ---
                [pscustomobject]@{
                    conversationId       = 'conv-e004-email-inbound'
                    conversationStart    = "${d}19T11:00:00.000Z"
                    conversationEnd      = "${d}19T11:38:45.000Z"
                    originatingDirection = 'inbound'
                    participants         = @(
                        [pscustomobject]@{
                            participantId   = 'part-e004-customer'
                            participantName = 'Customer'
                            purpose         = 'customer'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-e004-customer'
                                mediaType = 'email'
                                direction = 'inbound'
                                segments  = ,([pscustomobject]@{
                                    segmentStart   = "${d}19T11:00:00.000Z"
                                    segmentEnd     = "${d}19T11:38:45.000Z"
                                    segmentType    = 'interact'
                                    disconnectType = 'client'
                                })
                            })
                        }
                        [pscustomobject]@{
                            participantId   = 'part-e004-agent'
                            participantName = 'Eve Email'
                            purpose         = 'agent'
                            userId          = 'user-agent-0005-eve'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-e004-agent'
                                mediaType = 'email'
                                direction = 'inbound'
                                segments  = ,([pscustomobject]@{
                                    segmentStart = "${d}19T11:05:00.000Z"
                                    segmentEnd   = "${d}19T11:38:45.000Z"
                                    segmentType  = 'interact'
                                })
                            })
                        }
                    )
                }

                # --- Voice: abandoned in queue, no agent answered ---
                [pscustomobject]@{
                    conversationId       = 'conv-v005-voice-abandoned'
                    conversationStart    = "${d}20T08:45:00.000Z"
                    conversationEnd      = "${d}20T08:47:22.000Z"
                    originatingDirection = 'inbound'
                    participants         = @(
                        [pscustomobject]@{
                            participantId   = 'part-v005-customer'
                            participantName = 'Customer'
                            purpose         = 'customer'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-v005-customer'
                                mediaType = 'voice'
                                direction = 'inbound'
                                segments  = ,([pscustomobject]@{
                                    segmentStart   = "${d}20T08:45:00.000Z"
                                    segmentEnd     = "${d}20T08:47:22.000Z"
                                    segmentType    = 'alert'
                                    disconnectType = 'client'
                                })
                            })
                        }
                        [pscustomobject]@{
                            participantId   = 'part-v005-acd'
                            participantName = 'Tier-1 Support'
                            purpose         = 'acd'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-v005-acd'
                                mediaType = 'voice'
                                direction = 'inbound'
                                segments  = ,([pscustomobject]@{
                                    segmentStart = "${d}20T08:45:00.000Z"
                                    segmentEnd   = "${d}20T08:47:22.000Z"
                                    segmentType  = 'alert'
                                })
                            })
                        }
                    )
                }
            )
            cursor = $null
        } }
    }

    throw "Unexpected analytics mock request: $method $uri"
}

# ---------------------------------------------------------------------------
# USERS — mock requestInvoker
# User IDs match analytics participant userIds for cross-dataset coherence.
# Normalizer projects: recordType, id, name, email, state, presence, routingStatus
# ---------------------------------------------------------------------------
$usersRequestInvoker = {
    param($request)
    $uri    = [string]$request.Uri
    $method = [string]$request.Method

    if ($method -eq 'GET' -and $uri -like '*/api/v2/users*' -and $uri -notlike '*pageNumber=2*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            entities = @(
                [pscustomobject]@{
                    id    = 'user-agent-0001-alice'
                    name  = 'Alice Support'
                    email = 'alice.support@corp.example.com'
                    state = 'active'
                    presence = [pscustomobject]@{
                        presenceDefinition = [pscustomobject]@{ systemPresence = 'AVAILABLE' }
                    }
                    routingStatus = [pscustomobject]@{ status = 'IDLE' }
                }
                [pscustomobject]@{
                    id    = 'user-agent-0002-bob'
                    name  = 'Bob Chat'
                    email = 'bob.chat@corp.example.com'
                    state = 'active'
                    presence = [pscustomobject]@{
                        presenceDefinition = [pscustomobject]@{ systemPresence = 'BUSY' }
                    }
                    routingStatus = [pscustomobject]@{ status = 'INTERACTING' }
                }
                [pscustomobject]@{
                    id    = 'user-agent-0003-carol'
                    name  = 'Carol Specialist'
                    email = 'carol.specialist@corp.example.com'
                    state = 'active'
                    presence = [pscustomobject]@{
                        presenceDefinition = [pscustomobject]@{ systemPresence = 'AVAILABLE' }
                    }
                    routingStatus = [pscustomobject]@{ status = 'IDLE' }
                }
            )
            nextUri = 'https://api.mock.local/api/v2/users?pageNumber=2'
        } }
    }

    if ($method -eq 'GET' -and $uri -like '*/api/v2/users*' -and $uri -like '*pageNumber=2*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            entities = @(
                [pscustomobject]@{
                    id    = 'user-agent-0004-dan'
                    name  = 'Dan Outreach'
                    email = 'dan.outreach@corp.example.com'
                    state = 'active'
                    presence = [pscustomobject]@{
                        presenceDefinition = [pscustomobject]@{ systemPresence = 'AWAY' }
                    }
                    routingStatus = [pscustomobject]@{ status = 'OFF_QUEUE' }
                }
                [pscustomobject]@{
                    id       = 'user-agent-0005-eve'
                    name     = 'Eve Email'
                    email    = 'eve.email@corp.example.com'
                    state    = 'inactive'
                    presence = $null
                    routingStatus = $null
                }
            )
            nextUri = $null
        } }
    }

    throw "Unexpected users mock request: $method $uri"
}

# ---------------------------------------------------------------------------
# ROUTING QUEUES — mock requestInvoker
# Queue IDs and names match audit context fields for cross-dataset coherence.
# Normalizer projects: recordType, id, name, divisionId, memberCount, joined
# ---------------------------------------------------------------------------
$queuesRequestInvoker = {
    param($request)
    $uri    = [string]$request.Uri
    $method = [string]$request.Method

    if ($method -eq 'GET' -and $uri -like '*/api/v2/routing/queues*' -and $uri -notlike '*pageNumber=2*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            entities = @(
                [pscustomobject]@{
                    id          = 'queueid-0001-0001-0001-aabbccddeeff'
                    name        = 'Tier-1 Support'
                    division    = [pscustomobject]@{ id = 'div-main-0001-aabbccddeeff'; name = 'Main Division' }
                    memberCount = 12
                    joined      = $true
                }
                [pscustomobject]@{
                    id          = 'queueid-0002-0002-0002-aabbccddeeff'
                    name        = 'Tier-2 Escalation'
                    division    = [pscustomobject]@{ id = 'div-main-0001-aabbccddeeff'; name = 'Main Division' }
                    memberCount = 5
                    joined      = $true
                }
                [pscustomobject]@{
                    id          = 'queueid-0003-0003-0003-aabbccddeeff'
                    name        = 'Chat Support'
                    division    = [pscustomobject]@{ id = 'div-digital-0002-aabbccddeeff'; name = 'Digital Division' }
                    memberCount = 8
                    joined      = $false
                }
            )
            nextUri = 'https://api.mock.local/api/v2/routing/queues?pageNumber=2'
        } }
    }

    if ($method -eq 'GET' -and $uri -like '*/api/v2/routing/queues*' -and $uri -like '*pageNumber=2*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            entities = @(
                [pscustomobject]@{
                    id          = 'queueid-0004-0004-0004-aabbccddeeff'
                    name        = 'Callback Queue'
                    division    = $null
                    memberCount = 0
                    joined      = $false
                }
            )
            nextUri = $null
        } }
    }

    throw "Unexpected queues mock request: $method $uri"
}

# ---------------------------------------------------------------------------
# ANALYTICS CONVERSATION DETAILS QUERY — mock requestInvoker
# Direct POST with body paging (pageNumber in body, totalHits termination).
# Uses same conversation shape as the async jobs flow for schema consistency.
# ---------------------------------------------------------------------------
$analyticsQueryRequestInvoker = {
    param($request)
    $uri    = [string]$request.Uri
    $method = [string]$request.Method

    if ($method -eq 'POST' -and $uri -like '*/analytics/conversations/details/query') {
        $body = $request.Body | ConvertFrom-Json
        $pageNumber = if ($null -ne $body -and $null -ne $body.pageNumber) { [int]$body.pageNumber } else { 1 }

        if ($pageNumber -le 1) {
            return [pscustomobject]@{ Result = [pscustomobject]@{
                conversations = @(
                    [pscustomobject]@{
                        conversationId       = 'conv-v001-voice-inbound'
                        conversationStart    = "${d}14T09:00:00.000Z"
                        conversationEnd      = "${d}14T09:14:27.000Z"
                        originatingDirection = 'inbound'
                        participants         = @(
                            [pscustomobject]@{
                                participantId   = 'part-v001-agent'
                                participantName = 'Alice Support'
                                purpose         = 'agent'
                                userId          = 'user-agent-0001-alice'
                                sessions        = ,([pscustomobject]@{
                                    sessionId = 'sess-v001-agent'
                                    mediaType = 'voice'
                                    direction = 'inbound'
                                    segments  = @(
                                        [pscustomobject]@{ segmentStart = "${d}14T09:01:15.000Z"; segmentEnd = "${d}14T09:11:42.000Z"; segmentType = 'interact' }
                                        [pscustomobject]@{ segmentStart = "${d}14T09:11:42.000Z"; segmentEnd = "${d}14T09:14:27.000Z"; segmentType = 'wrap-up'  }
                                    )
                                })
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
                    conversationId       = 'conv-c002-chat-transfer'
                    conversationStart    = "${d}15T13:30:00.000Z"
                    conversationEnd      = "${d}15T14:01:05.000Z"
                    originatingDirection = 'inbound'
                    participants         = @(
                        [pscustomobject]@{
                            participantId   = 'part-c002-agent2'
                            participantName = 'Carol Specialist'
                            purpose         = 'agent'
                            userId          = 'user-agent-0003-carol'
                            sessions        = ,([pscustomobject]@{
                                sessionId = 'sess-c002-agent2'
                                mediaType = 'chat'
                                direction = 'inbound'
                                segments  = ,([pscustomobject]@{
                                    segmentStart = "${d}15T13:50:00.000Z"
                                    segmentEnd   = "${d}15T14:01:05.000Z"
                                    segmentType  = 'interact'
                                })
                            })
                        }
                    )
                }
            )
            totalHits = 2
        } }
    }

    throw "Unexpected analytics-query mock request: $method $uri"
}

# ---------------------------------------------------------------------------
# Run datasets
# ---------------------------------------------------------------------------
$catalogPath = Join-Path -Path $repoRoot -ChildPath 'catalog/genesys.catalog.json'
$baseUri     = 'https://api.mock.local'
$availableMockDatasets = @(
    'audit-logs'
    'analytics-conversation-details'
    'users'
    'routing-queues'
    'analytics-conversation-details-query'
)

if ($PSBoundParameters.ContainsKey('Datasets') -and $null -ne $Datasets) {
    $selectedDatasets = @(
        @($Datasets) |
            ForEach-Object { [string]$_ } |
            Where-Object { [string]::IsNullOrWhiteSpace([string]$_) -eq $false } |
            Select-Object -Unique
    )
}
else {
    $selectedDatasets = @($availableMockDatasets)
}

$unsupportedDatasets = @($selectedDatasets | Where-Object { $availableMockDatasets -notcontains $_ })
if ($unsupportedDatasets.Count -gt 0) {
    throw "Unsupported mock dataset(s): $([string]::Join(', ', $unsupportedDatasets)). Supported values: $([string]::Join(', ', $availableMockDatasets))."
}

if ($selectedDatasets.Count -eq 0) {
    throw "No datasets selected for mock run."
}

Write-Host ''
Write-Host '  Genesys.Core — Mock Run' -ForegroundColor White
Write-Host '  ========================' -ForegroundColor DarkGray
Write-Host "  Output root : $OutputRoot" -ForegroundColor DarkGray
Write-Host "  Catalog     : $catalogPath" -ForegroundColor DarkGray
Write-Host "  Datasets    : $([string]::Join(', ', $selectedDatasets))" -ForegroundColor DarkGray
if ($NoRedact) {
    Write-Host '  Mode        : NO REDACTION (PII fields visible)' -ForegroundColor Yellow
}

foreach ($dataset in $selectedDatasets) {
    switch ($dataset) {
        'audit-logs' {
            Write-Section 'audit-logs  (async transaction -> nextUri results paging)'
            $script:auditPolled = $false
            Invoke-Dataset -Dataset 'audit-logs' `
                -CatalogPath $catalogPath `
                -OutputRoot $OutputRoot `
                -BaseUri $baseUri `
                -RequestInvoker $auditRequestInvoker `
                -NoRedact:$NoRedact | Out-Null
            continue
        }
        'analytics-conversation-details' {
            Write-Section 'analytics-conversation-details  (async job -> cursor results paging)'
            $script:analyticsPolled = $false
            Invoke-Dataset -Dataset 'analytics-conversation-details' `
                -CatalogPath $catalogPath `
                -OutputRoot $OutputRoot `
                -BaseUri $baseUri `
                -RequestInvoker $analyticsRequestInvoker `
                -NoRedact:$NoRedact | Out-Null
            continue
        }
        'users' {
            Write-Section 'users  (GET collection -> nextUri paging, normalized records)'
            Invoke-Dataset -Dataset 'users' `
                -CatalogPath $catalogPath `
                -OutputRoot $OutputRoot `
                -BaseUri $baseUri `
                -RequestInvoker $usersRequestInvoker `
                -NoRedact:$NoRedact | Out-Null
            continue
        }
        'routing-queues' {
            Write-Section 'routing-queues  (GET collection -> nextUri paging, normalized records)'
            Invoke-Dataset -Dataset 'routing-queues' `
                -CatalogPath $catalogPath `
                -OutputRoot $OutputRoot `
                -BaseUri $baseUri `
                -RequestInvoker $queuesRequestInvoker `
                -NoRedact:$NoRedact | Out-Null
            continue
        }
        'analytics-conversation-details-query' {
            Write-Section 'analytics-conversation-details-query  (POST -> body paging)'
            Invoke-Dataset -Dataset 'analytics-conversation-details-query' `
                -CatalogPath $catalogPath `
                -OutputRoot $OutputRoot `
                -BaseUri $baseUri `
                -RequestInvoker $analyticsQueryRequestInvoker `
                -NoRedact:$NoRedact | Out-Null
            continue
        }
    }
}

# ---------------------------------------------------------------------------
# Report — locate run folders and show file layout + previews
# ---------------------------------------------------------------------------
if (-not $NoReport) {
    Write-Host ''
    Write-Host '  Output artifacts' -ForegroundColor White
    Write-Host '  =================' -ForegroundColor DarkGray

    $reportDatasets = @($selectedDatasets)

    foreach ($datasetKey in $reportDatasets) {
        Write-Section $datasetKey

        $datasetDir = Join-Path -Path $OutputRoot -ChildPath $datasetKey
        $runFolder  = Get-ChildItem -Path $datasetDir -Directory |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1

        if (-not $runFolder) {
            Write-Warn "No run folder found under $datasetDir"
            continue
        }

        Write-Info "Run folder: $($runFolder.FullName)"

        # File inventory
        foreach ($file in @('manifest.json', 'summary.json', 'events.jsonl')) {
            $filePath = Join-Path -Path $runFolder.FullName -ChildPath $file
            if (Test-Path -Path $filePath) {
                $sizeKb = [Math]::Round((Get-Item -Path $filePath).Length / 1KB, 1)
                Write-Ok "$file  (${sizeKb} KB)"
            } else {
                Write-Warn "$file  MISSING"
            }
        }

        $dataFolder = Join-Path -Path $runFolder.FullName -ChildPath 'data'
        foreach ($dataFile in (Get-ChildItem -Path $dataFolder -Filter '*.jsonl' -ErrorAction SilentlyContinue)) {
            $lines  = @(Get-Content -Path $dataFile.FullName)
            $sizeKb = [Math]::Round($dataFile.Length / 1KB, 1)
            Write-Ok "data/$($dataFile.Name)  ($($lines.Count) records, ${sizeKb} KB)"
        }

        # summary.json preview
        $summaryPath = Join-Path -Path $runFolder.FullName -ChildPath 'summary.json'
        if (Test-Path -Path $summaryPath) {
            Write-Host ''
            Write-Host '    summary.json:' -ForegroundColor DarkCyan
            Get-Content -Path $summaryPath | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        }

        # Event type breakdown
        $eventsPath = Join-Path -Path $runFolder.FullName -ChildPath 'events.jsonl'
        if (Test-Path -Path $eventsPath) {
            $events  = @(Get-Content -Path $eventsPath | ForEach-Object { $_ | ConvertFrom-Json })
            $grouped = $events | Group-Object -Property eventType | Sort-Object Count -Descending
            Write-Host ''
            Write-Host '    Event types recorded:' -ForegroundColor DarkCyan
            foreach ($g in $grouped) {
                Write-Host ("      {0,-38} x {1}" -f $g.Name, $g.Count) -ForegroundColor DarkGray
            }
        }

        # Redaction spot-check on first data record
        $dataFile = Get-ChildItem -Path $dataFolder -Filter '*.jsonl' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($dataFile) {
            $firstRecord = Get-Content -Path $dataFile.FullName | Select-Object -First 1 | ConvertFrom-Json
            if ($firstRecord) {
                $redactedFields = $firstRecord.PSObject.Properties |
                    Where-Object { $_.Value -is [string] -and $_.Value -eq '[REDACTED]' } |
                    ForEach-Object { $_.Name }

                if ($redactedFields.Count -gt 0) {
                    Write-Host ''
                    Write-Host '    Redacted top-level fields in first record:' -ForegroundColor DarkCyan
                    foreach ($f in $redactedFields) {
                        Write-Host "      $f = [REDACTED]" -ForegroundColor DarkGray
                    }
                }
            }
        }
    }
}

Write-Host ''
Write-Host '  Mock run complete.' -ForegroundColor White
Write-Host "  Inspect artifacts at: $(Resolve-Path -Path $OutputRoot)" -ForegroundColor Cyan
Write-Host ''


