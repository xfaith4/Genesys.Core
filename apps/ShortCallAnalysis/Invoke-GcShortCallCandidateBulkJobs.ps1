#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [datetime]$StartDateUtc,

    [Parameter(Mandatory = $true)]
    [datetime]$EndDateUtc,

    [string]$Region = 'usw2.pure.cloud',

    [ValidateRange(0.001, 300)]
    [double]$ThresholdSeconds = 5,

    [string]$OutputRoot = '.\short-call-candidates',

    [ValidateRange(1, 300)]
    [int]$JobPollSeconds = 10,

    [ValidateRange(1, 1440)]
    [int]$JobPollTimeoutMinutes = 60,

    [ValidateRange(1, 1000)]
    [int]$PageSize = 100,

    [ValidateRange(0, 10)]
    [int]$ApiMaxRetryCount = 5,

    [ValidateRange(1, 120)]
    [int]$ApiRetryBaseDelaySeconds = 2,

    [ValidateSet('None', 'Last4', 'Hash')]
    [string]$ReportNumberMaskMode = 'Last4',

    [ValidateRange(0, 12)]
    [int]$ReportMaskKeepRight = 4,

    [switch]$IncludeOutbound,

    [switch]$ResetDay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ArtifactVersion = '2026-05-14.1'
$script:DetectionRuleName = 'ExternalLatestCompletedNonWrapupVoiceSegmentEndUnderThresholdFromConversationStart'
$script:DetectionRuleVersion = 'v2'
$script:ClassificationVersion = 'v2'
$script:PipelineName = 'GenesysCloudShortCallCandidateAnalytics'
$script:ScriptName = 'Invoke-GcShortCallCandidateBulkJobs.ps1'

#region BEGIN Utility Functions
function New-DirectoryIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not [System.IO.Directory]::Exists($Path)) {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    }
}

function Remove-FileIfExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.File]::Exists($Path)) {
        [System.IO.File]::Delete($Path)
    }
}

function Get-GcBearerToken {
    [CmdletBinding()]
    param()

    $token = [string]$env:GENESYS_BEARER_TOKEN

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'GENESYS_BEARER_TOKEN environment variable is required.'
    }

    return $token
}

function Test-HasPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $false
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $false
    }

    if ($null -eq $property.Value) {
        return $false
    }

    return $true
}

function Get-PropertyString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if (-not (Test-HasPropertyValue -InputObject $InputObject -Name $name)) {
            continue
        }

        $value = [string]$InputObject.PSObject.Properties[$name].Value
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return ''
}

function ConvertTo-JsonLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    return ($InputObject | ConvertTo-Json -Depth 100 -Compress)
}

function Write-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $InputObject | ConvertTo-Json -Depth 100 | Set-Content -Path $Path -Encoding UTF8
}

function Add-JsonLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($null -eq $Items) {
        return
    }

    $lineBuffer = New-Object System.Collections.Generic.List[string]

    foreach ($item in $Items) {
        if ($null -eq $item) {
            continue
        }

        $lineBuffer.Add((ConvertTo-JsonLine -InputObject $item)) | Out-Null
    }

    if ($lineBuffer.Count -gt 0) {
        Add-Content -Path $Path -Value $lineBuffer -Encoding UTF8
    }
}

function ConvertTo-ObjectArray {
    [CmdletBinding()]
    param(
        $InputObject
    )

    if ($null -eq $InputObject) {
        return @()
    }

    if ($InputObject -is [System.Array]) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) {
            $items.Add($item) | Out-Null
        }

        return $items.ToArray()
    }

    return @($InputObject)
}

function Read-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not [System.IO.File]::Exists($Path)) {
        return $null
    }

    $content = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }

    return ($content | ConvertFrom-Json)
}

function Get-FirstNonEmptyString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Values
    )

    if ($null -eq $Values) {
        return $null
    }

    foreach ($value in $Values) {
        $text = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
    }

    return $null
}

function Copy-JsonLineFiles {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$SourcePaths,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Remove-FileIfExists -Path $DestinationPath

    foreach ($sourcePath in $SourcePaths) {
        if ([string]::IsNullOrWhiteSpace($sourcePath)) {
            continue
        }

        if (-not [System.IO.File]::Exists($sourcePath)) {
            continue
        }

        foreach ($line in [System.IO.File]::ReadLines($sourcePath)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            Add-Content -Path $DestinationPath -Value $line -Encoding UTF8
        }
    }
}

function Try-ParseDateTimeOffset {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parsed = [datetimeoffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal

    if ([datetimeoffset]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function ConvertTo-UtcDateString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetimeoffset]$Value
    )

    return $Value.UtcDateTime.ToString('o')
}

function Get-NormalizedDateUtc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Value
    )

    switch ($Value.Kind) {
        'Utc' {
            return $Value
        }
        'Local' {
            return [datetime]::SpecifyKind($Value.ToUniversalTime(), [System.DateTimeKind]::Utc)
        }
        default {
            return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        }
    }
}

function Get-DayStartUtc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Value
    )

    $utc = Get-NormalizedDateUtc -Value $Value
    return [datetime]::SpecifyKind($utc.Date, [System.DateTimeKind]::Utc)
}

function Get-ExternalSelectionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Purpose
    )

    if ([string]::IsNullOrWhiteSpace($Purpose)) {
        return 'Unspecified'
    }

    $normalized = $Purpose.Trim().ToLowerInvariant()

    switch ($normalized) {
        'customer' { return 'ExplicitCustomerOrExternalPurpose' }
        'external' { return 'ExplicitCustomerOrExternalPurpose' }
        default { return 'FallbackNonAgentVoiceParticipant' }
    }
}

function Get-MaskedReportValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [int]$KeepRight
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    switch ($Mode) {
        'None' {
            return $Value
        }
        'Last4' {
            $chars = $Value.ToCharArray()
            $digitCount = 0

            foreach ($char in $chars) {
                if ([char]::IsDigit($char)) {
                    $digitCount++
                }
            }

            $visibleDigits = [Math]::Min($KeepRight, $digitCount)
            $maskDigitsBefore = $digitCount - $visibleDigits
            $maskedChars = New-Object System.Collections.Generic.List[char]
            $digitsSeen = 0

            foreach ($char in $chars) {
                if ([char]::IsDigit($char)) {
                    if ($digitsSeen -lt $maskDigitsBefore) {
                        $maskedChars.Add('*') | Out-Null
                    }
                    else {
                        $maskedChars.Add($char) | Out-Null
                    }

                    $digitsSeen++
                }
                else {
                    $maskedChars.Add($char) | Out-Null
                }
            }

            return (-join $maskedChars.ToArray())
        }
        'Hash' {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
                $hash = $sha.ComputeHash($bytes)
                $hex = [System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
                return ('sha256:{0}' -f $hex.Substring(0, 12))
            }
            finally {
                $sha.Dispose()
            }
        }
        default {
            return $Value
        }
    }
}

function Get-UniqueStringArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Values
    )

    $set = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if ($null -ne $Values) {
        foreach ($value in $Values) {
            $text = [string]$value
            if ([string]::IsNullOrWhiteSpace($text)) {
                continue
            }

            [void]$set.Add($text)
        }
    }

    return $set.ToArray()
}

function Get-IntervalRawCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawFolder,

        [Parameter(Mandatory = $true)]
        [string]$IntervalLabel
    )

    return [System.IO.Path]::Combine($RawFolder, "interval-candidates-$IntervalLabel.jsonl")
}

function Test-IsExplicitExternalPurpose {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Purpose
    )

    if ([string]::IsNullOrWhiteSpace($Purpose)) {
        return $false
    }

    return $Purpose.Equals('customer', [System.StringComparison]::OrdinalIgnoreCase) -or
        $Purpose.Equals('external', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-IsFallbackExternalPurpose {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Purpose
    )

    if ([string]::IsNullOrWhiteSpace($Purpose)) {
        return $true
    }

    $excluded = @('agent', 'acd', 'ivr', 'workflow', 'dialer', 'campaign', 'user', 'station')

    foreach ($name in $excluded) {
        if ($Purpose.Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    return $true
}

function Invoke-MemoryCleanup {
    [CmdletBinding()]
    param()

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
}
#endregion END Utility Functions

#region BEGIN Genesys API Functions
function Get-RetryDelaySeconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$AttemptNumber,

        [Parameter(Mandatory = $true)]
        [int]$BaseDelaySeconds
    )

    $power = [Math]::Min($AttemptNumber - 1, 6)
    $delay = [Math]::Pow(2, $power) * $BaseDelaySeconds
    $delay = [Math]::Min([double]$delay, 120.0)
    return [int][Math]::Ceiling($delay)
}

function Test-ShouldRetryException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )

    $message = [string]$Exception.Message

    if ($message -match '429|408|500|502|503|504|temporar|timeout|timed out|connection reset|connection closed') {
        return $true
    }

    if ($Exception.PSObject.Properties['Response']) {
        $response = $Exception.Response
        if ($null -ne $response -and $response.PSObject.Properties['StatusCode']) {
            $statusCode = [int]$response.StatusCode
            if ($statusCode -eq 408 -or $statusCode -eq 429 -or $statusCode -ge 500) {
                return $true
            }
        }
    }

    if ($Exception.InnerException -ne $null) {
        return (Test-ShouldRetryException -Exception $Exception.InnerException)
    }

    return $false
}

function Invoke-GcApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        $Body = $null,

        [Parameter(Mandatory = $true)]
        [int]$MaxRetryCount,

        [Parameter(Mandatory = $true)]
        [int]$RetryBaseDelaySeconds
    )

    $headers = @{
        Authorization = "Bearer $(Get-GcBearerToken)"
    }

    $bodyJson = $null
    if ($null -ne $Body) {
        $bodyJson = $Body | ConvertTo-Json -Depth 100
    }

    for ($attempt = 1; $attempt -le ($MaxRetryCount + 1); $attempt++) {
        try {
            if ($null -ne $bodyJson) {
                return Invoke-RestMethod `
                    -Method $Method `
                    -Uri $Uri `
                    -Headers $headers `
                    -ContentType 'application/json' `
                    -Body $bodyJson
            }

            return Invoke-RestMethod `
                -Method $Method `
                -Uri $Uri `
                -Headers $headers
        }
        catch {
            if ($attempt -gt $MaxRetryCount -or -not (Test-ShouldRetryException -Exception $_.Exception)) {
                throw
            }

            $delaySeconds = Get-RetryDelaySeconds -AttemptNumber $attempt -BaseDelaySeconds $RetryBaseDelaySeconds
            Write-Warning ("Retrying {0} {1}. Attempt {2}/{3}. Waiting {4}s. Error: {5}" -f $Method, $Uri, $attempt, ($MaxRetryCount + 1), $delaySeconds, $_.Exception.Message)
            Start-Sleep -Seconds $delaySeconds
        }
    }

    throw "Unexpected retry loop termination for $Method $Uri"
}

function Get-DayIntervalsUtc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DayUtc
    )

    $dayStart = Get-DayStartUtc -Value $DayUtc
    $items = New-Object System.Collections.Generic.List[object]

    for ($hour = 0; $hour -lt 24; $hour += 4) {
        $start = $dayStart.AddHours([double]$hour)
        $end = $start.AddHours([double]4)
        $items.Add([pscustomobject]@{
            StartUtc = $start
            EndUtc = $end
            Interval = ('{0}/{1}' -f $start.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'), $end.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))
            Label = ('{0:yyyyMMdd-HHmm}-{1:HHmm}Z' -f $start, $end)
        }) | Out-Null
    }

    return $items.ToArray()
}

function New-ConversationDetailsJobBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Interval,

        [switch]$IncludeOutbound
    )

    $directionPredicates = New-Object System.Collections.Generic.List[object]
    $directionPredicates.Add([ordered]@{
        type = 'dimension'
        dimension = 'originatingDirection'
        operator = 'matches'
        value = 'inbound'
    }) | Out-Null

    if ($IncludeOutbound) {
        $directionPredicates.Add([ordered]@{
            type = 'dimension'
            dimension = 'originatingDirection'
            operator = 'matches'
            value = 'outbound'
        }) | Out-Null
    }

    return [ordered]@{
        interval = $Interval
        order = 'asc'
        orderBy = 'conversationStart'
        conversationFilters = @(
            [ordered]@{
                type = 'or'
                predicates = @($directionPredicates.ToArray())
            }
        )
        segmentFilters = @(
            [ordered]@{
                type = 'and'
                predicates = @(
                    [ordered]@{
                        type = 'dimension'
                        dimension = 'mediaType'
                        operator = 'matches'
                        value = 'voice'
                    }
                )
            }
        )
    }
}

function Start-GcConversationDetailsJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUri,

        [Parameter(Mandatory = $true)]
        $Body,

        [Parameter(Mandatory = $true)]
        [int]$MaxRetryCount,

        [Parameter(Mandatory = $true)]
        [int]$RetryBaseDelaySeconds
    )

    $response = Invoke-GcApi `
        -Method POST `
        -Uri "$BaseUri/api/v2/analytics/conversations/details/jobs" `
        -Body $Body `
        -MaxRetryCount $MaxRetryCount `
        -RetryBaseDelaySeconds $RetryBaseDelaySeconds

    $jobId = Get-PropertyString -InputObject $response -Names @('jobId', 'id')
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        throw "Conversation details job response did not include jobId/id. Response: $(ConvertTo-JsonLine -InputObject $response)"
    }

    return [pscustomobject]@{
        JobId = $jobId
        Response = $response
    }
}

function Wait-GcConversationDetailsJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUri,

        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter(Mandatory = $true)]
        [int]$PollSeconds,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMinutes,

        [Parameter(Mandatory = $true)]
        [int]$MaxRetryCount,

        [Parameter(Mandatory = $true)]
        [int]$RetryBaseDelaySeconds
    )

    $statusUri = "$BaseUri/api/v2/analytics/conversations/details/jobs/$JobId"
    $deadline = [datetimeoffset]::UtcNow.AddMinutes($TimeoutMinutes)

    while ([datetimeoffset]::UtcNow -lt $deadline) {
        $status = Invoke-GcApi `
            -Method GET `
            -Uri $statusUri `
            -MaxRetryCount $MaxRetryCount `
            -RetryBaseDelaySeconds $RetryBaseDelaySeconds

        $state = Get-PropertyString -InputObject $status -Names @('state', 'status')
        Write-Verbose ("Job {0} state: {1}" -f $JobId, $state)

        if ($state -match 'FULFILLED|COMPLETED|COMPLETE|SUCCESS|SUCCEEDED') {
            return $status
        }

        if ($state -match 'FAILED|CANCELLED|CANCELED|ERROR') {
            throw "Conversation details job $JobId failed. Status: $(ConvertTo-JsonLine -InputObject $status)"
        }

        Start-Sleep -Seconds $PollSeconds
    }

    throw "Timed out waiting for conversation details job $JobId after $TimeoutMinutes minute(s)."
}

function Get-ResultConversationCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Result
    )

    foreach ($name in @('conversations', 'results', 'entities')) {
        if (Test-HasPropertyValue -InputObject $Result -Name $name) {
            return (ConvertTo-ObjectArray -InputObject $Result.PSObject.Properties[$name].Value)
        }
    }

    return @()
}

function Get-ResultCursor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Result
    )

    return (Get-PropertyString -InputObject $Result -Names @('cursor', 'nextCursor', 'nextPage', 'nextUri'))
}

function Get-GcConversationDetailsJobResultPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUri,

        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter(Mandatory = $true)]
        [int]$PageSize,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Cursor,

        [Parameter(Mandatory = $true)]
        [int]$MaxRetryCount,

        [Parameter(Mandatory = $true)]
        [int]$RetryBaseDelaySeconds
    )

    $uri = "$BaseUri/api/v2/analytics/conversations/details/jobs/$JobId/results?pageSize=$PageSize"

    if (-not [string]::IsNullOrWhiteSpace($Cursor)) {
        $uri = "{0}&cursor={1}" -f $uri, [System.Uri]::EscapeDataString($Cursor)
    }

    $result = Invoke-GcApi `
        -Method GET `
        -Uri $uri `
        -MaxRetryCount $MaxRetryCount `
        -RetryBaseDelaySeconds $RetryBaseDelaySeconds

    return [pscustomobject]@{
        Result = $result
        Conversations = (Get-ResultConversationCollection -Result $result)
        NextCursor = Get-ResultCursor -Result $result
    }
}
#endregion END Genesys API Functions

#region BEGIN Detection Functions
function Get-GcFlattenedVoiceSegments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Conversation
    )

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($participant in @($Conversation.participants)) {
        if ($null -eq $participant) {
            continue
        }

        foreach ($session in @($participant.sessions)) {
            if ($null -eq $session) {
                continue
            }

            $mediaType = [string]$session.mediaType
            if (-not [string]::IsNullOrWhiteSpace($mediaType) -and -not $mediaType.Equals('voice', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            foreach ($segment in @($session.segments)) {
                if ($null -eq $segment) {
                    continue
                }

                $rows.Add([pscustomobject]@{
                    ConversationId = [string]$Conversation.conversationId
                    ParticipantId = [string]$participant.participantId
                    ParticipantName = [string]$participant.participantName
                    Purpose = [string]$participant.purpose
                    SessionId = [string]$session.sessionId
                    MediaType = [string]$session.mediaType
                    SessionDirection = [string]$session.direction
                    Ani = [string]$session.ani
                    Dnis = [string]$session.dnis
                    ProtocolCallId = [string]$session.protocolCallId
                    PeerId = [string]$session.peerId
                    Provider = [string]$session.provider
                    Remote = [string]$session.remote
                    SegmentType = [string]$segment.segmentType
                    SegmentStart = [string]$segment.segmentStart
                    SegmentEnd = [string]$segment.segmentEnd
                    DisconnectType = [string]$segment.disconnectType
                    QueueId = [string]$segment.queueId
                    UserId = [string]$segment.userId
                    WrapUpCode = [string]$segment.wrapUpCode
                }) | Out-Null
            }
        }
    }

    return $rows.ToArray()
}

function Get-ConversationAgentTalkMetricsSecondary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Conversation
    )

    $talkMs = [int64]0
    $participantIds = New-Object System.Collections.Generic.List[string]
    $sessionIds = New-Object System.Collections.Generic.List[string]

    foreach ($participant in @($Conversation.participants)) {
        if ($null -eq $participant) {
            continue
        }

        $isAgent = ([string]$participant.purpose).Equals('agent', [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $isAgent) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$participant.participantId)) {
            $participantIds.Add([string]$participant.participantId) | Out-Null
        }

        foreach ($session in @($participant.sessions)) {
            if ($null -eq $session) {
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$session.sessionId)) {
                $sessionIds.Add([string]$session.sessionId) | Out-Null
            }

            foreach ($metric in @($session.metrics)) {
                if ($null -eq $metric) {
                    continue
                }

                if ([string]$metric.name -eq 'tTalk' -and $null -ne $metric.value) {
                    $talkMs += [int64]$metric.value
                }
            }
        }
    }

    $uniqueParticipantIds = Get-UniqueStringArray -Values $participantIds
    $uniqueSessionIds = Get-UniqueStringArray -Values $sessionIds

    return [pscustomobject]@{
        AgentParticipantPresent = ($uniqueParticipantIds.Length -gt 0)
        AgentParticipantIds = $uniqueParticipantIds
        AgentSessionIds = $uniqueSessionIds
        AgentTalkMetricMsSecondary = $talkMs
        HasAgentTalkMetricSecondary = ($talkMs -gt 0)
    }
}

function Compare-NullableDateTimeOffset {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [datetimeoffset]$Left,

        [AllowNull()]
        [datetimeoffset]$Right
    )

    if ($null -eq $Left -and $null -eq $Right) {
        return 0
    }

    if ($null -eq $Left) {
        return 1
    }

    if ($null -eq $Right) {
        return -1
    }

    return [datetimeoffset]::Compare($Left, $Right)
}

function Compare-StringsOrdinal {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Left,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Right
    )

    if ($null -eq $Left) {
        $Left = ''
    }

    if ($null -eq $Right) {
        $Right = ''
    }

    return [string]::CompareOrdinal($Left, $Right)
}

function Select-ShortCallClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $AgentEvidence
    )

    if (-not $AgentEvidence.AgentParticipantPresent -and -not $AgentEvidence.HasAgentTalkMetricSecondary) {
        return 'ExternalDisconnectedUnderThreshold_NoAgentParticipant'
    }

    if ($AgentEvidence.AgentParticipantPresent -and -not $AgentEvidence.HasAgentTalkMetricSecondary) {
        return 'ExternalDisconnectedUnderThreshold_AgentPresentNoTalk'
    }

    if ($AgentEvidence.AgentParticipantPresent -and $AgentEvidence.HasAgentTalkMetricSecondary) {
        return 'ExternalDisconnectedUnderThreshold_AgentTalkObserved'
    }

    return 'ExternalDisconnectedUnderThreshold_AmbiguousAgentEvidence'
}

function Select-ShortCallCandidatesFromConversations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Conversations,

        [Parameter(Mandatory = $true)]
        [double]$ThresholdSeconds,

        [Parameter(Mandatory = $true)]
        [string]$SourceIntervalStartUtc,

        [Parameter(Mandatory = $true)]
        [string]$SourceIntervalEndUtc,

        [Parameter(Mandatory = $true)]
        [int]$SourcePageNumber
    )

    $thresholdMs = [int64][Math]::Round($ThresholdSeconds * 1000.0, 0)
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($conversation in $Conversations) {
        if ($null -eq $conversation) {
            continue
        }

        $conversationId = [string]$conversation.conversationId
        if ([string]::IsNullOrWhiteSpace($conversationId)) {
            continue
        }

        $conversationStart = Try-ParseDateTimeOffset -Value ([string]$conversation.conversationStart)
        if ($null -eq $conversationStart) {
            continue
        }

        $conversationEnd = Try-ParseDateTimeOffset -Value ([string]$conversation.conversationEnd)
        if ($null -eq $conversationEnd) {
            continue
        }

        $segments = @(Get-GcFlattenedVoiceSegments -Conversation $conversation)
        if ($segments.Length -eq 0) {
            continue
        }

        $explicitExternalSegments = New-Object System.Collections.Generic.List[object]
        $fallbackExternalSegments = New-Object System.Collections.Generic.List[object]

        foreach ($segment in $segments) {
            $purpose = [string]$segment.Purpose

            if (Test-IsExplicitExternalPurpose -Purpose $purpose) {
                $explicitExternalSegments.Add($segment) | Out-Null
                continue
            }

            if (Test-IsFallbackExternalPurpose -Purpose $purpose) {
                $fallbackExternalSegments.Add($segment) | Out-Null
            }
        }

        $externalSegments = @()
        $selectionRule = ''

        if ($explicitExternalSegments.Count -gt 0) {
            $externalSegments = @($explicitExternalSegments)
            $selectionRule = 'ExplicitCustomerOrExternalPurpose'
        }
        elseif ($fallbackExternalSegments.Count -gt 0) {
            $externalSegments = @($fallbackExternalSegments)
            $selectionRule = 'FallbackNonAgentVoiceParticipant'
        }
        else {
            continue
        }

        $completedNonWrapupExternalSegments = New-Object System.Collections.Generic.List[object]

        foreach ($segment in $externalSegments) {
            $segmentType = [string]$segment.SegmentType
            if ($segmentType.Equals('wrapup', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $segmentEnd = Try-ParseDateTimeOffset -Value ([string]$segment.SegmentEnd)
            if ($null -eq $segmentEnd) {
                continue
            }

            $completedNonWrapupExternalSegments.Add([pscustomobject]@{
                Segment = $segment
                SegmentEnd = $segmentEnd
                SegmentStart = (Try-ParseDateTimeOffset -Value ([string]$segment.SegmentStart))
            }) | Out-Null
        }

        if ($completedNonWrapupExternalSegments.Count -eq 0) {
            continue
        }

        $latestCompletedExternal = $null
        $earliestExternalSegmentStart = $null

        foreach ($item in $completedNonWrapupExternalSegments) {
            if ($null -ne $item.SegmentStart) {
                if ($null -eq $earliestExternalSegmentStart -or $item.SegmentStart -lt $earliestExternalSegmentStart) {
                    $earliestExternalSegmentStart = $item.SegmentStart
                }
            }

            if ($null -eq $latestCompletedExternal -or $item.SegmentEnd -gt $latestCompletedExternal.SegmentEnd) {
                $latestCompletedExternal = $item
            }
        }

        if ($null -eq $latestCompletedExternal) {
            continue
        }

        $externalLatestCompletedSegmentEnd = $latestCompletedExternal.SegmentEnd
        $detectionWindowMs = [int64][Math]::Round(($externalLatestCompletedSegmentEnd - $conversationStart).TotalMilliseconds, 0)

        if ($detectionWindowMs -lt 0) {
            continue
        }

        if ($detectionWindowMs -ge $thresholdMs) {
            continue
        }

        $agentEvidence = Get-ConversationAgentTalkMetricsSecondary -Conversation $conversation
        $classification = Select-ShortCallClassification -AgentEvidence $agentEvidence

        $externalParticipantIds = Get-UniqueStringArray -Values ($externalSegments | ForEach-Object { $_.ParticipantId })
        $externalSessionIds = Get-UniqueStringArray -Values ($externalSegments | ForEach-Object { $_.SessionId })
        $externalProtocolCallIds = Get-UniqueStringArray -Values ($externalSegments | ForEach-Object { $_.ProtocolCallId })
        $externalDisconnectTypes = Get-UniqueStringArray -Values ($completedNonWrapupExternalSegments | ForEach-Object { $_.Segment.DisconnectType })
        $externalSegmentTypes = Get-UniqueStringArray -Values ($externalSegments | ForEach-Object { $_.SegmentType })
        $externalPeerIds = Get-UniqueStringArray -Values ($externalSegments | ForEach-Object { $_.PeerId })
        $externalPurposes = Get-UniqueStringArray -Values ($externalSegments | ForEach-Object { $_.Purpose })
        $externalAnis = Get-UniqueStringArray -Values ($externalSegments | ForEach-Object { $_.Ani })
        $externalDnises = Get-UniqueStringArray -Values ($externalSegments | ForEach-Object { $_.Dnis })

        $primaryAni = Get-FirstNonEmptyString -Values ($externalSegments | ForEach-Object { $_.Ani })
        $primaryDnis = Get-FirstNonEmptyString -Values ($externalSegments | ForEach-Object { $_.Dnis })
        $primaryProtocolCallId = Get-FirstNonEmptyString -Values ($externalSegments | ForEach-Object { $_.ProtocolCallId })

        $results.Add([pscustomobject]@{
            ArtifactVersion = $script:ArtifactVersion
            PipelineName = $script:PipelineName
            DetectionRuleName = $script:DetectionRuleName
            DetectionRuleVersion = $script:DetectionRuleVersion
            ClassificationVersion = $script:ClassificationVersion
            ConversationId = $conversationId
            OriginatingDirection = [string]$conversation.originatingDirection
            ConversationStartUtc = (ConvertTo-UtcDateString -Value $conversationStart)
            ConversationEndUtc = (ConvertTo-UtcDateString -Value $conversationEnd)
            ExternalSelectionRule = $selectionRule
            ExternalParticipantIds = $externalParticipantIds
            ExternalSessionIds = $externalSessionIds
            ExternalPurposes = $externalPurposes
            ExternalAni = $primaryAni
            ExternalDnis = $primaryDnis
            ExternalAniValues = $externalAnis
            ExternalDnisValues = $externalDnises
            ProtocolCallIdPrimary = $primaryProtocolCallId
            ProtocolCallIds = $externalProtocolCallIds
            ExternalPeerIds = $externalPeerIds
            ExternalEarliestSegmentStartUtc = if ($null -ne $earliestExternalSegmentStart) { ConvertTo-UtcDateString -Value $earliestExternalSegmentStart } else { $null }
            ExternalLatestCompletedSegmentEndUtc = (ConvertTo-UtcDateString -Value $externalLatestCompletedSegmentEnd)
            ExternalCompletedSegmentDisconnectTypes = $externalDisconnectTypes
            ExternalObservedSegmentTypes = $externalSegmentTypes
            DetectionWindowMs = $detectionWindowMs
            DetectionWindowSeconds = [Math]::Round(($detectionWindowMs / 1000.0), 3)
            DetectionThresholdMs = $thresholdMs
            DetectionThresholdSeconds = $ThresholdSeconds
            AgentParticipantPresent = $agentEvidence.AgentParticipantPresent
            AgentParticipantIds = $agentEvidence.AgentParticipantIds
            AgentSessionIds = $agentEvidence.AgentSessionIds
            AgentTalkMetricMsSecondary = $agentEvidence.AgentTalkMetricMsSecondary
            HasAgentTalkMetricSecondary = $agentEvidence.HasAgentTalkMetricSecondary
            ShortCallClassification = $classification
            SourceIntervalStartUtc = $SourceIntervalStartUtc
            SourceIntervalEndUtc = $SourceIntervalEndUtc
            SourcePageNumber = $SourcePageNumber
            ExtractedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
        }) | Out-Null
    }

    return $results.ToArray()
}
#endregion END Detection Functions

#region BEGIN Dedupe And Report Functions
function Compare-CandidatePreference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Left,

        [Parameter(Mandatory = $true)]
        $Right
    )

    $leftConversationStart = Try-ParseDateTimeOffset -Value ([string]$Left.ConversationStartUtc)
    $rightConversationStart = Try-ParseDateTimeOffset -Value ([string]$Right.ConversationStartUtc)
    $result = Compare-NullableDateTimeOffset -Left $leftConversationStart -Right $rightConversationStart
    if ($result -ne 0) {
        return $result
    }

    $leftIntervalStart = Try-ParseDateTimeOffset -Value ([string]$Left.SourceIntervalStartUtc)
    $rightIntervalStart = Try-ParseDateTimeOffset -Value ([string]$Right.SourceIntervalStartUtc)
    $result = Compare-NullableDateTimeOffset -Left $leftIntervalStart -Right $rightIntervalStart
    if ($result -ne 0) {
        return $result
    }

    $leftPage = 0
    if ($null -ne $Left.SourcePageNumber) {
        $leftPage = [int]$Left.SourcePageNumber
    }

    $rightPage = 0
    if ($null -ne $Right.SourcePageNumber) {
        $rightPage = [int]$Right.SourcePageNumber
    }

    if ($leftPage -lt $rightPage) {
        return -1
    }

    if ($leftPage -gt $rightPage) {
        return 1
    }

    $leftEnd = Try-ParseDateTimeOffset -Value ([string]$Left.ExternalLatestCompletedSegmentEndUtc)
    $rightEnd = Try-ParseDateTimeOffset -Value ([string]$Right.ExternalLatestCompletedSegmentEndUtc)
    $result = Compare-NullableDateTimeOffset -Left $leftEnd -Right $rightEnd
    if ($result -ne 0) {
        return $result
    }

    $result = Compare-StringsOrdinal -Left ([string]$Left.ProtocolCallIdPrimary) -Right ([string]$Right.ProtocolCallIdPrimary)
    if ($result -ne 0) {
        return $result
    }

    $leftJson = ConvertTo-JsonLine -InputObject $Left
    $rightJson = ConvertTo-JsonLine -InputObject $Right
    return (Compare-StringsOrdinal -Left $leftJson -Right $rightJson)
}

function Get-CandidateSortKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Candidate
    )

    $conversationStart = [string]$Candidate.ConversationStartUtc
    $conversationId = [string]$Candidate.ConversationId
    $protocolCallId = [string]$Candidate.ProtocolCallIdPrimary
    $pageNumber = [string]$Candidate.SourcePageNumber

    return '{0}|{1}|{2}|{3}' -f $conversationStart, $conversationId, $protocolCallId, $pageNumber
}

function Invoke-DailyCandidateDedupe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawCandidatePath,

        [Parameter(Mandatory = $true)]
        [string]$DedupedCandidatePath
    )

    $bestByConversationId = @{}
    $rawCount = 0
    $duplicateCount = 0

    Remove-FileIfExists -Path $DedupedCandidatePath

    if (-not [System.IO.File]::Exists($RawCandidatePath)) {
        return [pscustomobject]@{
            RawCount = 0
            DedupedCount = 0
            DuplicateCount = 0
        }
    }

    foreach ($line in [System.IO.File]::ReadLines($RawCandidatePath)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $rawCount++
        $candidate = $line | ConvertFrom-Json
        $conversationId = [string]$candidate.ConversationId

        if ([string]::IsNullOrWhiteSpace($conversationId)) {
            continue
        }

        if (-not $bestByConversationId.ContainsKey($conversationId)) {
            $bestByConversationId[$conversationId] = $candidate
            continue
        }

        $duplicateCount++
        $comparison = Compare-CandidatePreference -Left $candidate -Right $bestByConversationId[$conversationId]
        if ($comparison -lt 0) {
            $bestByConversationId[$conversationId] = $candidate
        }
    }

    $ordered = @(
        $bestByConversationId.Values |
            Sort-Object `
                @{ Expression = { [string]$_.ConversationStartUtc } ; Ascending = $true }, `
                @{ Expression = { [string]$_.ConversationId } ; Ascending = $true }, `
                @{ Expression = { [string]$_.ProtocolCallIdPrimary } ; Ascending = $true }, `
                @{ Expression = { [int]$_.SourcePageNumber } ; Ascending = $true }
    )

    Add-JsonLines -Items $ordered -Path $DedupedCandidatePath

    return [pscustomobject]@{
        RawCount = $rawCount
        DedupedCount = $ordered.Length
        DuplicateCount = $duplicateCount
    }
}

function Read-JsonLinesObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $items = New-Object System.Collections.Generic.List[object]

    if (-not [System.IO.File]::Exists($Path)) {
        return $items.ToArray()
    }

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $items.Add(($line | ConvertFrom-Json)) | Out-Null
    }

    return $items.ToArray()
}

function Get-GroupedCountRows {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [scriptblock]$KeySelector,

        [Parameter(Mandatory = $true)]
        [string]$KeyName,

        [int]$Top = 0
    )

    $groups = @(
        $Items |
            Group-Object $KeySelector |
            Sort-Object -Property Count, Name -Descending
    )

    if ($Top -gt 0 -and $groups.Length -gt $Top) {
        $groups = @($groups | Select-Object -First $Top)
    }

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($group in $groups) {
        $rows.Add([pscustomobject]@{
            $KeyName = if ([string]::IsNullOrWhiteSpace([string]$group.Name)) { '(blank)' } else { [string]$group.Name }
            Count = [int]$group.Count
        }) | Out-Null
    }

    return $rows.ToArray()
}

function New-ShortCallTrendReportData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Summary,

        [Parameter(Mandatory = $true)]
        [object[]]$Candidates,

        [Parameter(Mandatory = $true)]
        [string]$MaskMode,

        [Parameter(Mandatory = $true)]
        [int]$MaskKeepRight
    )

    $byHour = New-Object System.Collections.Generic.List[object]
    foreach ($group in @(
        $Candidates |
            Group-Object {
                $value = Try-ParseDateTimeOffset -Value ([string]$_.ConversationStartUtc)
                if ($null -eq $value) {
                    return 'Unknown'
                }

                return $value.ToString('yyyy-MM-dd HH:00Z')
            } |
            Sort-Object Name
    )) {
        $byHour.Add([pscustomobject]@{
            Hour = $group.Name
            Count = [int]$group.Count
        }) | Out-Null
    }

    $byClassification = Get-GroupedCountRows `
        -Items $Candidates `
        -KeySelector { [string]$_.ShortCallClassification } `
        -KeyName 'Classification'

    $byDisconnectType = Get-GroupedCountRows `
        -Items $Candidates `
        -KeySelector { ([string[]]$_.ExternalCompletedSegmentDisconnectTypes) -join ';' } `
        -KeyName 'DisconnectTypes'

    $byMaskedAni = Get-GroupedCountRows `
        -Items $Candidates `
        -KeySelector { Get-MaskedReportValue -Value ([string]$_.ExternalAni) -Mode $MaskMode -KeepRight $MaskKeepRight } `
        -KeyName 'MaskedAni' `
        -Top 25

    $byMaskedDnis = Get-GroupedCountRows `
        -Items $Candidates `
        -KeySelector { Get-MaskedReportValue -Value ([string]$_.ExternalDnis) -Mode $MaskMode -KeepRight $MaskKeepRight } `
        -KeyName 'MaskedDnis' `
        -Top 25

    return [pscustomobject]@{
        schemaVersion = '1.0'
        generatedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
        reportType = 'short-call-trend-report'
        dayUtc = [string]$Summary.DayUtc
        thresholdSeconds = [double]$Summary.ThresholdSeconds
        maskMode = $MaskMode
        maskKeepRight = $MaskKeepRight
        summary = [pscustomobject]@{
            rawCandidateCount = [int]$Summary.RawCandidateCount
            dedupedCandidateCount = [int]$Summary.DedupedCandidateCount
            duplicateCandidateCount = [int]$Summary.DuplicateCandidateCount
        }
        byInterval = @($Summary.IntervalSummaries)
        byHour = @($byHour)
        byClassification = @($byClassification)
        byExternalDisconnectType = @($byDisconnectType)
        byMaskedAni = @($byMaskedAni)
        byMaskedDnis = @($byMaskedDnis)
    }
}

function New-ShortCallAnalyticsProcessDoc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Summary,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$MaskMode
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Short-Call Candidate Analytics Process') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Business Goal') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('Identify voice conversations where the external/customer leg reaches Genesys Cloud and disconnects within the configured threshold after conversationStart, before agent involvement is likely. This is intended as a troubleshooting signal for SBC and carrier correlation, not a root-cause verdict.') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Detection Contract') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('A conversation is a short-call candidate only when all of the following are true:') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('1. `conversationStart` exists.') | Out-Null
    $lines.Add('2. `conversationEnd` exists, so incomplete conversations are excluded.') | Out-Null
    $lines.Add('3. An external/customer voice participant can be identified, preferring explicit `customer` or `external` participant purpose values.') | Out-Null
    $lines.Add('4. The latest completed external non-wrapup voice segment end exists.') | Out-Null
    $lines.Add('5. `latestCompletedExternalNonWrapupVoiceSegmentEnd - conversationStart < threshold`.') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('`tTalk` is not part of the predicate. Agent talk metrics are retained only as secondary classification evidence in the output.') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Daily Processing Model') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('Each UTC day is split into six four-hour Analytics Conversation Details jobs. Each page is processed independently, candidates are appended to the raw JSONL file immediately, and page/job collections are released before the next page continues.') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Resumability') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('- Completed interval manifests are skipped on rerun.') | Out-Null
    $lines.Add('- If a fulfilled job already exists for an incomplete interval, paging resumes from the saved cursor and page number.') | Out-Null
    $lines.Add('- If an interval must restart, its interval raw JSONL is replaced and the daily raw JSONL is rebuilt from interval raw files to avoid duplicate daily rows.') | Out-Null
    $lines.Add('- Daily dedupe runs after all intervals are complete and collapses duplicates by `conversationId` deterministically.') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Output Contract') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('- `manifests/day-manifest.json`: day-level execution state and artifact pointers.') | Out-Null
    $lines.Add('- `manifests/interval-<label>.json`: per-interval resumability and job/page counts.') | Out-Null
    $lines.Add('- `raw/job-body-<label>.json`: posted analytics job body.') | Out-Null
    $lines.Add('- `raw/job-status-<label>-<jobId>.json`: final job status payload.') | Out-Null
    $lines.Add('- `raw/interval-candidates-<label>.jsonl`: append-only per-interval raw candidate rows used for deterministic rebuild and resumability.') | Out-Null
    $lines.Add('- `short-call-candidates-<day>.raw.jsonl`: append-only raw candidate rows.') | Out-Null
    $lines.Add('- `short-call-candidates-<day>.deduped.jsonl`: deterministic day-level deduped candidate rows.') | Out-Null
    $lines.Add('- `reports/short-call-trend-report-<day>.json`: structured trend report data.') | Out-Null
    $lines.Add('- `reports/short-call-trend-report-<day>.md`: analyst-facing daily trend summary.') | Out-Null
    $lines.Add('- `reports/analytics-process-<day>.md`: this process description.') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Privacy') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add(('Report masking mode: `{0}`. Raw JSONL files preserve full ANI/DNIS for carrier and SBC correlation. Report files apply masking only.' -f $MaskMode)) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Future Refactor Alignment') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('The artifact layout is intentionally close to a run-artifact model: stable day root, manifest files, raw data files, deduped data files, and report files with explicit schema/version fields.') | Out-Null

    $lines | Set-Content -Path $Path -Encoding UTF8
}

function New-ShortCallTrendReportMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Summary,

        [Parameter(Mandatory = $true)]
        $TrendData,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Short-Call Candidate Trend Report') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Summary') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Metric | Value |') | Out-Null
    $lines.Add('|---|---:|') | Out-Null
    $lines.Add("| Day | $($Summary.DayUtc) |") | Out-Null
    $lines.Add("| Raw candidates | $($Summary.RawCandidateCount) |") | Out-Null
    $lines.Add("| Deduped candidates | $($Summary.DedupedCandidateCount) |") | Out-Null
    $lines.Add("| Duplicate candidates removed | $($Summary.DuplicateCandidateCount) |") | Out-Null
    $lines.Add("| Threshold seconds | $($Summary.ThresholdSeconds) |") | Out-Null
    $lines.Add("| Report number masking | $($TrendData.maskMode) |") | Out-Null
    $lines.Add('') | Out-Null

    $lines.Add('## Candidates by Four-Hour Job Interval') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Interval | Status | Conversations | Candidates | Pages | JobId |') | Out-Null
    $lines.Add('|---|---|---:|---:|---:|---|') | Out-Null

    foreach ($interval in @($Summary.IntervalSummaries)) {
        $lines.Add("| $($interval.Interval) | $($interval.Status) | $($interval.ConversationCount) | $($interval.CandidateCount) | $($interval.PageCount) | `$($interval.JobId)` |") | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Candidates by Hour') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Hour | Count |') | Out-Null
    $lines.Add('|---|---:|') | Out-Null
    foreach ($row in @($TrendData.byHour)) {
        $lines.Add("| $($row.Hour) | $($row.Count) |") | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Candidates by Classification') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Classification | Count |') | Out-Null
    $lines.Add('|---|---:|') | Out-Null
    foreach ($row in @($TrendData.byClassification)) {
        $lines.Add("| $($row.Classification) | $($row.Count) |") | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Candidates by External Disconnect Type') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Disconnect Types | Count |') | Out-Null
    $lines.Add('|---|---:|') | Out-Null
    foreach ($row in @($TrendData.byExternalDisconnectType)) {
        $lines.Add("| $($row.DisconnectTypes) | $($row.Count) |") | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Top Masked ANI') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Masked ANI | Count |') | Out-Null
    $lines.Add('|---|---:|') | Out-Null
    foreach ($row in @($TrendData.byMaskedAni)) {
        $lines.Add("| $($row.MaskedAni) | $($row.Count) |") | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Top Masked DNIS') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Masked DNIS | Count |') | Out-Null
    $lines.Add('|---|---:|') | Out-Null
    foreach ($row in @($TrendData.byMaskedDnis)) {
        $lines.Add("| $($row.MaskedDnis) | $($row.Count) |") | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Interpretation') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('These candidates show short external-leg dwell time inside Genesys Cloud. Use `conversationId`, `protocolCallId`, ANI, DNIS, participant IDs, session IDs, timestamps, and disconnect types to correlate against SBC, carrier, and SIP trace evidence before assigning cause.') | Out-Null

    $lines | Set-Content -Path $Path -Encoding UTF8
}
#endregion END Dedupe And Report Functions

#region BEGIN Manifest And Processing Functions
function New-DayManifestObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DayLabel,

        [Parameter(Mandatory = $true)]
        [string]$DayFolder,

        [Parameter(Mandatory = $true)]
        [string]$RawCandidatePath,

        [Parameter(Mandatory = $true)]
        [string]$DedupedCandidatePath
    )

    return [pscustomobject]@{
        artifactVersion = $script:ArtifactVersion
        pipelineName = $script:PipelineName
        scriptName = $script:ScriptName
        schemaVersion = '1.0'
        status = 'InProgress'
        dayUtc = $DayLabel
        dayFolder = $DayFolder
        rawCandidatePath = $RawCandidatePath
        dedupedCandidatePath = $DedupedCandidatePath
        startedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
        completedAtUtc = $null
        intervalCountExpected = 6
        intervalCountCompleted = 0
        intervalLabelsCompleted = @()
        generatedReports = @()
    }
}

function New-IntervalManifestObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Interval,

        [Parameter(Mandatory = $true)]
        [string]$CandidateRawPath
    )

    return [pscustomobject]@{
        artifactVersion = $script:ArtifactVersion
        pipelineName = $script:PipelineName
        schemaVersion = '1.0'
        status = 'Pending'
        interval = [string]$Interval.Interval
        intervalLabel = [string]$Interval.Label
        startUtc = $Interval.StartUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        endUtc = $Interval.EndUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        jobId = $null
        startedAtUtc = $null
        completedAtUtc = $null
        pageCount = 0
        conversationCount = 0
        candidateCount = 0
        lastCompletedPageNumber = 0
        nextCursor = $null
        candidateRawPath = $CandidateRawPath
        intervalRawCandidatePath = $null
        jobBodyPath = $null
        jobStatusPath = $null
        notes = @()
    }
}

function Save-IntervalManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-JsonFile -InputObject $Manifest -Path $Path
}

function Save-DayManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-JsonFile -InputObject $Manifest -Path $Path
}

function Get-IntervalManifestSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    return [pscustomobject]@{
        Interval = [string]$Manifest.interval
        IntervalLabel = [string]$Manifest.intervalLabel
        Status = [string]$Manifest.status
        JobId = [string]$Manifest.jobId
        PageCount = [int]$Manifest.pageCount
        ConversationCount = [int]$Manifest.conversationCount
        CandidateCount = [int]$Manifest.candidateCount
        CandidateRawPath = [string]$Manifest.candidateRawPath
        IntervalRawCandidatePath = [string]$Manifest.intervalRawCandidatePath
        JobBodyPath = [string]$Manifest.jobBodyPath
        JobStatusPath = [string]$Manifest.jobStatusPath
        StartedAtUtc = [string]$Manifest.startedAtUtc
        CompletedAtUtc = [string]$Manifest.completedAtUtc
    }
}

function Invoke-DayShortCallProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DayUtc,

        [Parameter(Mandatory = $true)]
        [string]$BaseUri,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot,

        [Parameter(Mandatory = $true)]
        [string]$Region,

        [Parameter(Mandatory = $true)]
        [double]$ThresholdSeconds,

        [Parameter(Mandatory = $true)]
        [int]$JobPollSeconds,

        [Parameter(Mandatory = $true)]
        [int]$JobPollTimeoutMinutes,

        [Parameter(Mandatory = $true)]
        [int]$PageSize,

        [Parameter(Mandatory = $true)]
        [int]$ApiMaxRetryCount,

        [Parameter(Mandatory = $true)]
        [int]$ApiRetryBaseDelaySeconds,

        [Parameter(Mandatory = $true)]
        [string]$ReportNumberMaskMode,

        [Parameter(Mandatory = $true)]
        [int]$ReportMaskKeepRight,

        [switch]$IncludeOutbound,

        [switch]$ResetDay
    )

    $dayLabel = $DayUtc.ToString('yyyy-MM-dd')
    $dayFolder = [System.IO.Path]::Combine($OutputRoot, $dayLabel)
    $manifestFolder = [System.IO.Path]::Combine($dayFolder, 'manifests')
    $rawFolder = [System.IO.Path]::Combine($dayFolder, 'raw')
    $reportFolder = [System.IO.Path]::Combine($dayFolder, 'reports')
    $candidateRawPath = [System.IO.Path]::Combine($dayFolder, "short-call-candidates-$dayLabel.raw.jsonl")
    $candidateDedupePath = [System.IO.Path]::Combine($dayFolder, "short-call-candidates-$dayLabel.deduped.jsonl")
    $dayManifestPath = [System.IO.Path]::Combine($manifestFolder, 'day-manifest.json')
    $summaryPath = [System.IO.Path]::Combine($reportFolder, "short-call-summary-$dayLabel.json")
    $analyticsDocPath = [System.IO.Path]::Combine($reportFolder, "analytics-process-$dayLabel.md")
    $trendReportJsonPath = [System.IO.Path]::Combine($reportFolder, "short-call-trend-report-$dayLabel.json")
    $trendReportMarkdownPath = [System.IO.Path]::Combine($reportFolder, "short-call-trend-report-$dayLabel.md")

    New-DirectoryIfMissing -Path $dayFolder
    New-DirectoryIfMissing -Path $manifestFolder
    New-DirectoryIfMissing -Path $rawFolder
    New-DirectoryIfMissing -Path $reportFolder

    if ($ResetDay) {
        Remove-FileIfExists -Path $candidateRawPath
        Remove-FileIfExists -Path $candidateDedupePath
        Remove-FileIfExists -Path $dayManifestPath

        foreach ($interval in @(Get-DayIntervalsUtc -DayUtc $DayUtc)) {
            $intervalManifestPath = [System.IO.Path]::Combine($manifestFolder, "interval-$($interval.Label).json")
            $intervalRawCandidatePath = Get-IntervalRawCandidatePath -RawFolder $rawFolder -IntervalLabel ([string]$interval.Label)
            Remove-FileIfExists -Path $intervalManifestPath
            Remove-FileIfExists -Path $intervalRawCandidatePath
        }
    }

    $dayManifest = New-DayManifestObject `
        -DayLabel $dayLabel `
        -DayFolder $dayFolder `
        -RawCandidatePath $candidateRawPath `
        -DedupedCandidatePath $candidateDedupePath
    Save-DayManifest -Manifest $dayManifest -Path $dayManifestPath

    $intervals = @(Get-DayIntervalsUtc -DayUtc $DayUtc)

    if (-not $ResetDay) {
        $existingIntervalRawPaths = New-Object System.Collections.Generic.List[string]

        foreach ($interval in $intervals) {
            $intervalRawCandidatePath = Get-IntervalRawCandidatePath -RawFolder $rawFolder -IntervalLabel ([string]$interval.Label)
            if ([System.IO.File]::Exists($intervalRawCandidatePath)) {
                $existingIntervalRawPaths.Add($intervalRawCandidatePath) | Out-Null
            }
        }

        Copy-JsonLineFiles -SourcePaths $existingIntervalRawPaths.ToArray() -DestinationPath $candidateRawPath
    }

    $intervalSummaries = New-Object System.Collections.Generic.List[object]

    foreach ($interval in $intervals) {
        $intervalManifestPath = [System.IO.Path]::Combine($manifestFolder, "interval-$($interval.Label).json")
        $intervalManifest = $null
        $intervalRawCandidatePath = Get-IntervalRawCandidatePath -RawFolder $rawFolder -IntervalLabel ([string]$interval.Label)

        if ([System.IO.File]::Exists($intervalManifestPath)) {
            $intervalManifest = Read-JsonFile -Path $intervalManifestPath
        }
        else {
            $intervalManifest = New-IntervalManifestObject -Interval $interval -CandidateRawPath $candidateRawPath
        }

        if ($null -eq $intervalManifest) {
            $intervalManifest = New-IntervalManifestObject -Interval $interval -CandidateRawPath $candidateRawPath
        }

        if (-not (Test-HasPropertyValue -InputObject $intervalManifest -Name 'intervalRawCandidatePath') -or [string]::IsNullOrWhiteSpace([string]$intervalManifest.intervalRawCandidatePath)) {
            $intervalManifest | Add-Member -NotePropertyName intervalRawCandidatePath -NotePropertyValue $intervalRawCandidatePath -Force
        }
        else {
            $intervalRawCandidatePath = [string]$intervalManifest.intervalRawCandidatePath
        }

        if ([string]$intervalManifest.status -eq 'Completed') {
            Write-Host ("Skipping completed interval {0}" -f $interval.Interval)
            $intervalSummaries.Add((Get-IntervalManifestSummary -Manifest $intervalManifest)) | Out-Null
            continue
        }

        $resumeExistingJob = $false
        $hasJobId = -not [string]::IsNullOrWhiteSpace([string]$intervalManifest.jobId)
        $hasJobStatusFile = -not [string]::IsNullOrWhiteSpace([string]$intervalManifest.jobStatusPath) -and [System.IO.File]::Exists([string]$intervalManifest.jobStatusPath)
        $hasIntervalRawFile = [System.IO.File]::Exists($intervalRawCandidatePath)

        if ($hasJobId -and $hasJobStatusFile) {
            if ([string]::IsNullOrWhiteSpace([string]$intervalManifest.nextCursor) -and [int]$intervalManifest.pageCount -gt 0) {
                $intervalManifest.status = 'Completed'
                if ([string]::IsNullOrWhiteSpace([string]$intervalManifest.completedAtUtc)) {
                    $intervalManifest.completedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
                }

                Save-IntervalManifest -Manifest $intervalManifest -Path $intervalManifestPath
                Write-Host ("Marking interval {0} completed from existing manifest state." -f $interval.Interval)
                $intervalSummaries.Add((Get-IntervalManifestSummary -Manifest $intervalManifest)) | Out-Null
                continue
            }

            $resumeExistingJob = $true
        }

        if (-not $resumeExistingJob -and $hasIntervalRawFile) {
            Remove-FileIfExists -Path $intervalRawCandidatePath

            $remainingIntervalRawPaths = New-Object System.Collections.Generic.List[string]
            foreach ($otherInterval in $intervals) {
                $otherPath = Get-IntervalRawCandidatePath -RawFolder $rawFolder -IntervalLabel ([string]$otherInterval.Label)
                if ([System.IO.File]::Exists($otherPath)) {
                    $remainingIntervalRawPaths.Add($otherPath) | Out-Null
                }
            }

            Copy-JsonLineFiles -SourcePaths $remainingIntervalRawPaths.ToArray() -DestinationPath $candidateRawPath
        }

        Write-Host ("Processing {0} interval {1}" -f $dayLabel, $interval.Interval)

        $intervalManifest.status = 'Running'
        if ([string]::IsNullOrWhiteSpace([string]$intervalManifest.startedAtUtc)) {
            $intervalManifest.startedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
        }
        $intervalManifest.completedAtUtc = $null

        if (-not $resumeExistingJob) {
            $intervalManifest.pageCount = 0
            $intervalManifest.conversationCount = 0
            $intervalManifest.candidateCount = 0
            $intervalManifest.lastCompletedPageNumber = 0
            $intervalManifest.nextCursor = $null
            $intervalManifest.jobId = $null
            $intervalManifest.jobStatusPath = $null
        }

        Save-IntervalManifest -Manifest $intervalManifest -Path $intervalManifestPath

        try {
            if (-not $resumeExistingJob) {
                $body = New-ConversationDetailsJobBody -Interval $interval.Interval -IncludeOutbound:$IncludeOutbound
                $bodyPath = [System.IO.Path]::Combine($rawFolder, "job-body-$($interval.Label).json")
                Write-JsonFile -InputObject $body -Path $bodyPath
                $intervalManifest.jobBodyPath = $bodyPath
                Save-IntervalManifest -Manifest $intervalManifest -Path $intervalManifestPath

                $jobStart = Start-GcConversationDetailsJob `
                    -BaseUri $BaseUri `
                    -Body $body `
                    -MaxRetryCount $ApiMaxRetryCount `
                    -RetryBaseDelaySeconds $ApiRetryBaseDelaySeconds

                $jobId = [string]$jobStart.JobId
                $intervalManifest.jobId = $jobId
                Save-IntervalManifest -Manifest $intervalManifest -Path $intervalManifestPath

                $jobStatus = Wait-GcConversationDetailsJob `
                    -BaseUri $BaseUri `
                    -JobId $jobId `
                    -PollSeconds $JobPollSeconds `
                    -TimeoutMinutes $JobPollTimeoutMinutes `
                    -MaxRetryCount $ApiMaxRetryCount `
                    -RetryBaseDelaySeconds $ApiRetryBaseDelaySeconds

                $statusPath = [System.IO.Path]::Combine($rawFolder, "job-status-$($interval.Label)-$jobId.json")
                Write-JsonFile -InputObject $jobStatus -Path $statusPath
                $intervalManifest.jobStatusPath = $statusPath
                Save-IntervalManifest -Manifest $intervalManifest -Path $intervalManifestPath
            }
            else {
                $jobId = [string]$intervalManifest.jobId
                Write-Host ("Resuming interval {0} from page {1}." -f $interval.Interval, ([int]$intervalManifest.lastCompletedPageNumber + 1))
            }

            $cursor = [string]$intervalManifest.nextCursor
            $pageNumber = [int]$intervalManifest.lastCompletedPageNumber

            while ($true) {
                $pageNumber++
                $page = Get-GcConversationDetailsJobResultPage `
                    -BaseUri $BaseUri `
                    -JobId $jobId `
                    -PageSize $PageSize `
                    -Cursor $cursor `
                    -MaxRetryCount $ApiMaxRetryCount `
                    -RetryBaseDelaySeconds $ApiRetryBaseDelaySeconds

                $conversations = @($page.Conversations)
                $intervalManifest.pageCount = [int]$intervalManifest.pageCount + 1
                $intervalManifest.lastCompletedPageNumber = $pageNumber
                $intervalManifest.conversationCount = [int]$intervalManifest.conversationCount + $conversations.Length

                $candidates = @(Select-ShortCallCandidatesFromConversations `
                    -Conversations $conversations `
                    -ThresholdSeconds $ThresholdSeconds `
                    -SourceIntervalStartUtc $interval.StartUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') `
                    -SourceIntervalEndUtc $interval.EndUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') `
                    -SourcePageNumber $pageNumber)

                Add-JsonLines -Items $candidates -Path $candidateRawPath
                Add-JsonLines -Items $candidates -Path $intervalRawCandidatePath
                $intervalManifest.candidateCount = [int]$intervalManifest.candidateCount + $candidates.Length
                $intervalManifest.nextCursor = $page.NextCursor
                $intervalManifest.intervalRawCandidatePath = $intervalRawCandidatePath
                Save-IntervalManifest -Manifest $intervalManifest -Path $intervalManifestPath

                Remove-Variable -Name conversations -ErrorAction SilentlyContinue
                Remove-Variable -Name candidates -ErrorAction SilentlyContinue
                Remove-Variable -Name page -ErrorAction SilentlyContinue
                Invoke-MemoryCleanup

                $cursor = [string]$intervalManifest.nextCursor
                if ([string]::IsNullOrWhiteSpace($cursor)) {
                    break
                }
            }

            $intervalManifest.status = 'Completed'
            $intervalManifest.completedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
            $intervalManifest.nextCursor = $null
            Save-IntervalManifest -Manifest $intervalManifest -Path $intervalManifestPath
        }
        catch {
            $intervalManifest.status = 'Failed'
            $intervalManifest.completedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
            $intervalManifest.notes = @(([string]$_.Exception.Message))
            Save-IntervalManifest -Manifest $intervalManifest -Path $intervalManifestPath
            throw
        }
        finally {
            Remove-Variable -Name body -ErrorAction SilentlyContinue
            Remove-Variable -Name jobStart -ErrorAction SilentlyContinue
            Remove-Variable -Name jobStatus -ErrorAction SilentlyContinue
            Invoke-MemoryCleanup
        }

        $intervalSummaries.Add((Get-IntervalManifestSummary -Manifest $intervalManifest)) | Out-Null
    }

    $dedupeResult = Invoke-DailyCandidateDedupe `
        -RawCandidatePath $candidateRawPath `
        -DedupedCandidatePath $candidateDedupePath

    $summary = [pscustomobject]@{
        schemaVersion = '1.0'
        artifactVersion = $script:ArtifactVersion
        pipelineName = $script:PipelineName
        scriptName = $script:ScriptName
        dayUtc = $dayLabel
        dayStartUtc = $DayUtc.ToString('yyyy-MM-ddT00:00:00.000Z')
        dayEndUtcExclusive = $DayUtc.AddDays([double]1).ToString('yyyy-MM-ddT00:00:00.000Z')
        region = $Region
        thresholdSeconds = $ThresholdSeconds
        pageSize = $PageSize
        includeOutbound = [bool]$IncludeOutbound
        reportNumberMaskMode = $ReportNumberMaskMode
        reportMaskKeepRight = $ReportMaskKeepRight
        rawCandidateCount = $dedupeResult.RawCount
        dedupedCandidateCount = $dedupeResult.DedupedCount
        duplicateCandidateCount = $dedupeResult.DuplicateCount
        rawCandidatePath = $candidateRawPath
        dedupedCandidatePath = $candidateDedupePath
        manifestsFolder = $manifestFolder
        rawFolder = $rawFolder
        reportFolder = $reportFolder
        intervalSummaries = @($intervalSummaries | Sort-Object IntervalLabel)
        generatedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
    }

    Write-JsonFile -InputObject $summary -Path $summaryPath

    $dedupedCandidates = @(Read-JsonLinesObjects -Path $candidateDedupePath)
    $trendData = New-ShortCallTrendReportData `
        -Summary $summary `
        -Candidates $dedupedCandidates `
        -MaskMode $ReportNumberMaskMode `
        -MaskKeepRight $ReportMaskKeepRight

    Write-JsonFile -InputObject $trendData -Path $trendReportJsonPath

    New-ShortCallAnalyticsProcessDoc `
        -Summary $summary `
        -Path $analyticsDocPath `
        -MaskMode $ReportNumberMaskMode

    New-ShortCallTrendReportMarkdown `
        -Summary $summary `
        -TrendData $trendData `
        -Path $trendReportMarkdownPath

    $dayManifest.status = 'Completed'
    $dayManifest.completedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
    $dayManifest.intervalCountCompleted = @($summary.intervalSummaries | Where-Object { $_.Status -eq 'Completed' }).Length
    $dayManifest.intervalLabelsCompleted = @($summary.intervalSummaries | Where-Object { $_.Status -eq 'Completed' } | ForEach-Object { $_.IntervalLabel })
    $dayManifest.generatedReports = @($summaryPath, $trendReportJsonPath, $trendReportMarkdownPath, $analyticsDocPath)
    Save-DayManifest -Manifest $dayManifest -Path $dayManifestPath

    return [pscustomobject]@{
        DayUtc = $dayLabel
        DayFolder = $dayFolder
        DayManifestPath = $dayManifestPath
        SummaryPath = $summaryPath
        AnalyticsDocPath = $analyticsDocPath
        TrendReportJsonPath = $trendReportJsonPath
        TrendReportMarkdownPath = $trendReportMarkdownPath
        RawCandidatePath = $candidateRawPath
        DedupedCandidatePath = $candidateDedupePath
        RawCandidateCount = $dedupeResult.RawCount
        DedupedCandidateCount = $dedupeResult.DedupedCount
        DuplicateCount = $dedupeResult.DuplicateCount
    }
}
#endregion END Manifest And Processing Functions

#region BEGIN Main Execution
$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-DirectoryIfMissing -Path $resolvedOutputRoot

$baseUri = "https://api.$Region"

$startDay = Get-DayStartUtc -Value $StartDateUtc
$endDayExclusive = Get-DayStartUtc -Value $EndDateUtc

if ($EndDateUtc.TimeOfDay.TotalSeconds -gt 0) {
    $endDayExclusive = $endDayExclusive.AddDays([double]1)
}

if ($EndDateUtc.TimeOfDay.TotalSeconds -eq 0 -and $EndDateUtc.Date -ge $StartDateUtc.Date) {
    $endDayExclusive = $endDayExclusive.AddDays([double]1)
}

if ($endDayExclusive -lt $startDay) {
    throw 'EndDateUtc must be greater than or equal to StartDateUtc.'
}

$runSummary = New-Object System.Collections.Generic.List[object]
$currentDay = $startDay

while ($currentDay -lt $endDayExclusive) {
    $dayResult = Invoke-DayShortCallProcessing `
        -DayUtc $currentDay `
        -BaseUri $baseUri `
        -OutputRoot $resolvedOutputRoot `
        -Region $Region `
        -ThresholdSeconds $ThresholdSeconds `
        -JobPollSeconds $JobPollSeconds `
        -JobPollTimeoutMinutes $JobPollTimeoutMinutes `
        -PageSize $PageSize `
        -ApiMaxRetryCount $ApiMaxRetryCount `
        -ApiRetryBaseDelaySeconds $ApiRetryBaseDelaySeconds `
        -ReportNumberMaskMode $ReportNumberMaskMode `
        -ReportMaskKeepRight $ReportMaskKeepRight `
        -IncludeOutbound:$IncludeOutbound `
        -ResetDay:$ResetDay

    $runSummary.Add($dayResult) | Out-Null
    Remove-Variable -Name dayResult -ErrorAction SilentlyContinue
    Invoke-MemoryCleanup

    $currentDay = $currentDay.AddDays([double]1)
}

$overallSummary = [pscustomobject]@{
    schemaVersion = '1.0'
    artifactVersion = $script:ArtifactVersion
    pipelineName = $script:PipelineName
    scriptName = $script:ScriptName
    baseUri = $baseUri
    outputRoot = $resolvedOutputRoot
    startDateUtc = $startDay.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    endDateUtcExclusive = $endDayExclusive.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    thresholdSeconds = $ThresholdSeconds
    includeOutbound = [bool]$IncludeOutbound
    reportNumberMaskMode = $ReportNumberMaskMode
    reportMaskKeepRight = $ReportMaskKeepRight
    generatedAtUtc = [datetimeoffset]::UtcNow.ToString('o')
    days = @($runSummary)
}

$overallSummaryPath = [System.IO.Path]::Combine($resolvedOutputRoot, 'bulk-short-call-run-summary.json')
Write-JsonFile -InputObject $overallSummary -Path $overallSummaryPath
#endregion END Main Execution
