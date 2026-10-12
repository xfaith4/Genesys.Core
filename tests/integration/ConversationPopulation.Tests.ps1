BeforeAll {
    Import-Module "$PSScriptRoot/../../modules/Genesys.Ops/Genesys.Ops.psd1" -Force
    function New-ProfileFixture {
        $raw = @{
            conversationId='profile-1';conversationStart='2026-09-01T00:00:00Z';conversationEnd='2026-09-01T00:01:00Z'
            divisionIds=@('division-a','division-b');mediaStatsMinConversationMos=4.1234
            participants=@(
                @{purpose='customer';participantName='PRIVATE NAME';sessions=@(@{mediaType='voice';ani='PRIVATE NUMBER';metrics=@(@{name='tHandle';value=999999});segments=@(@{segmentType='interact';errorCode='E1';disconnectType='error'})})},
                @{purpose='agent';userId='agent-1';sessions=@(@{mediaType='voice';mediaEndpointStats=@(@{minMos=3.7;maxLatencyMs=50;codecs=@('opus')},@{minMos=2.5;maxLatencyMs=120;codecs=@('pcmu')});metrics=@(@{name='tHandle';value=10000},@{name='tHeld';value=0});segments=@(
                    @{segmentType='interact';segmentStart='2026-09-01T00:00:20Z';segmentEnd='2026-09-01T00:00:40Z';queueId='q2';errorCode='E1';disconnectType='transfer'},
                    @{segmentType='interact';segmentStart='2026-09-01T00:00:10Z';segmentEnd='2026-09-01T00:00:20Z';queueId='q1';errorCode='E2';disconnectType='client'},
                    @{segmentType='interact';segmentStart='2026-09-01T00:00:40Z';segmentEnd='2026-09-01T00:01:00Z';disconnectType='endpoint'},
                    @{segmentType='wrapup';segmentStart='2026-09-01T00:01:00Z';segmentEnd='2026-09-01T00:01:10Z';wrapUpCode='wrap-1';disconnectType='system'})})},
                @{purpose='agent';userId='alert-only';sessions=@(@{mediaType='voice';segments=@(@{segmentType='alert'})})}
            )
        }
        return $raw | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    }
}
Describe 'Conversation profile semantics adapted from supplied reference' {
    It 'counts every segment error and distinct codes across all participants' {
        $profile=New-ProfileFixture | Get-GenesysConversationProfile
        $profile.ErrorSegmentCount | Should -Be 3
        $profile.ErrorCodes.Count | Should -Be 2
        $profile.HasErrorCodeProperty | Should -BeTrue
        @($profile.ErrorEvents | Where-Object Code -eq E1).Count | Should -Be 2
    }
    It 'keeps precise summary MOS separate from literal endpoint minimum' {
        $profile=New-ProfileFixture | Get-GenesysConversationProfile
        $profile.MinMos | Should -Be 4.1234
        $profile.EndpointMinMos | Should -Be 2.5
        $profile.MaxLatencyMs | Should -Be 120
        $profile.Codecs | Should -Contain 'opus'
    }
    It 'restricts agent work metrics, retains zero and leaves absent metrics null' {
        $profile=New-ProfileFixture | Get-GenesysConversationProfile
        $profile.tHandleSec | Should -Be 10
        $profile.tHeldSec | Should -Be 0
        $profile.tTalkSec | Should -BeNullOrEmpty
        $profile.DurationSec | Should -Be 60
    }
    It 'orders queue paths and excludes alert-only agents and wrapup disconnects' {
        $profile=New-ProfileFixture | Get-GenesysConversationProfile
        $profile.QueueIds | Should -Be @('q1','q2')
        $profile.AgentKeys | Should -Be @('agent-1')
        $profile.UserIds | Should -Contain 'alert-only'
        $profile.Timeline[0].QueueId | Should -Be 'q1'
        $profile.DisconnectType | Should -Be 'endpoint'
        $profile.DivisionIds.Count | Should -Be 2
    }
    It 'omits customer identifiers and tolerates absent optional fields' {
        $profile=New-ProfileFixture | Get-GenesysConversationProfile
        ($profile | ConvertTo-Json -Depth 30) | Should -Not -Match 'PRIVATE'
        $empty=[pscustomobject]@{conversationId='empty'} | Get-GenesysConversationProfile
        $empty.MinMos | Should -BeNullOrEmpty
        $empty.QueueCount | Should -Be 0
    }
}
Describe 'Conversation population collection and evidence' {
    It 'exports a self-contained report with complete scoped predicates and valid denominators' {
        $bodies=[System.Collections.Generic.List[object]]::new()
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01T00:00:00Z' -Until '2026-10-01T00:00:00Z' -QueueId q1 -UserId u1 -DivisionId d1 -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset,$Body,$OutputRoot)
            $bodies.Add($Body)
            return @{Records=@((New-ProfileFixture),([pscustomobject]@{conversationId='missing'}));Status='complete';Events=@()}
        }
        $bundle.profiles.Count | Should -Be 2
        $bodies[0].segmentFilters[0].predicates[0].value | Should -Be q1
        $bodies[0].segmentFilters[1].predicates[0].value | Should -Be u1
        $bodies[0].conversationFilters[0].predicates[0].value | Should -Be d1
        $bundle.statistics.tHandleSec.validCount | Should -Be 1
        $bundle.statistics.tHandleSec.missingCount | Should -Be 1
        $bundle.statistics.tHandleSec.average | Should -Be 10
        $html=Get-Content (Join-Path $bundle.runFolder 'report.html') -Raw
        $html | Should -Not -Match '<script src=' 
        $html | Should -Not -Match '/\*__GC_ANALYSIS__\*/null'
        $html | Should -Match 'profile-1'
        Test-Path (Join-Path $bundle.runFolder 'data/profiles.jsonl') | Should -BeTrue
    }
    It 'preserves custom filters and refuses ambiguous query intervals' {
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -QueryBody @{conversationFilters=@(@{type='and';predicates=@(@{dimension='conversationId';value='abc'})})} -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset,$Body,$OutputRoot)
            return @{Records=@();Status='complete';Events=@()}
        }
        $bundle.request.conversationFilters[0].predicates[0].value | Should -Be 'abc'
        { Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -QueueId q1 -QueryBody @{order='desc'} -OutputRoot $TestDrive } | Should -Throw '*cannot be combined*'
        { Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -QueryBody @{interval='other'} -OutputRoot $TestDrive } | Should -Throw '*Omit interval*'
    }
    It 'deduplicates IDs, flags partial paging, and escapes embedded script termination' {
        $raw=New-ProfileFixture
        $raw.participants[1].sessions[0] | Add-Member -NotePropertyName flow -NotePropertyValue @{flowName='</script><img src=x onerror=alert(1)>'}
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -OutputRoot $TestDrive -DatasetInvoker {
            param($Dataset,$Body,$OutputRoot)
            return @{Records=@($raw,$raw);Status='complete';Events=@(@{eventType='paging.terminated.duplicateCursor'})}
        }
        $bundle.profiles.Count | Should -Be 1
        $bundle.coverage.duplicateRows | Should -Be 1
        $bundle.coverage.status | Should -Be 'partial'
        $html=Get-Content (Join-Path $bundle.runFolder 'report.html') -Raw
        $html | Should -Not -Match '</script><img'
        $html | Should -Match '\\u003c/script'
    }
    It 'labels imports unverified and computes empty statistics as null' {
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -InputObject @() -OutputRoot $TestDrive
        $bundle.coverage.status | Should -Be 'unverified'
        $bundle.statistics.MinMos.average | Should -BeNullOrEmpty
    }
}
Describe 'Conversation analysis actual Core collection' {
    It 'collects both cursor pages with matching server-side scope' {
        $requests=[System.Collections.Generic.List[object]]::new()
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -QueueId 'q1' -UserId 'u1' -DivisionId 'd1' -OutputRoot $TestDrive -RequestInvoker {
            param($request)
            $requests.Add($request)
            $uri=[string]$request.Uri
            $payload=if($uri -match '/jobs$'){@{jobId='profile-job'}}
            elseif($uri -match '/jobs/profile-job$'){@{state='FULFILLED'}}
            elseif($uri -match '/results\?cursor='){@{conversations=@(@{conversationId='second';participants=@()})}}
            elseif($uri -match '/results$'){@{conversations=@((New-ProfileFixture));cursor='profile-page-2'}}
            else {throw 'Unexpected request'}
            return [pscustomobject]@{Result=($payload|ConvertTo-Json -Depth 30|ConvertFrom-Json)}
        }
        $bundle.profiles.Count | Should -Be 2
        $bundle.coverage.pageCount | Should -Be 2
        $bundle.coverage.status | Should -Be 'complete'
        $body=$requests[0].Body|ConvertFrom-Json
        $body.segmentFilters[0].predicates[0].value | Should -Be 'q1'
        $body.segmentFilters[1].predicates[0].value | Should -Be 'u1'
        $body.conversationFilters[0].predicates[0].value | Should -Be 'd1'
        $bundle.profiles[0].tHandleSec | Should -Be 10
    }
    It 'does not export a successful report for a failed platform job' {
        {Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -OutputRoot $TestDrive -RequestInvoker {
            param($request)
            $payload=if($request.Uri -match '/jobs$'){@{jobId='failed'}}else{@{state='FAILED'}}
            return [pscustomobject]@{Result=[pscustomobject]$payload}
        }} | Should -Throw '*FAILED*'
    }
}

Describe 'Run-scoped conversation entity resolution' {
    It 'resolves once per family, keeps stable IDs, retains missing IDs, and omits unrelated directory records' {
        $calls=[System.Collections.Generic.List[object]]::new()
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -InputObject @((New-ProfileFixture)) -OutputRoot $TestDrive -ResolveEntityNames -EntityLookupInvoker {
            param($Kind,$Dataset,$Ids,$OutputRoot)
            $calls.Add(@{Kind=$Kind;Ids=$Ids})
            $records=switch($Kind){
                queues {@(@{id='q1';name='Shared label'},@{id='q2';name='Shared label'},@{id='unrelated';name='PRIVATE DIRECTORY RECORD'})}
                users {@(@{id='agent-1';name='Engineer One';email='PRIVATE EMAIL';division=@{id='user-division'}})}
                divisions {@(@{id='division-a';name='North'},@{id='user-division';name='User Division'})}
                wrapupCodes {@(@{id='wrap-1';name='Resolved'})}
            }
            return @{Records=@($records);Status='complete'}
        }
        $calls.Count | Should -Be 4
        @($calls | Where-Object Kind -eq users).Count | Should -Be 1
        ($calls | Where-Object Kind -eq users).Ids.Count | Should -Be 2
        $bundle.profiles[0].QueueIds | Should -Be @('q1','q2')
        $bundle.profiles[0].QueueNames | Should -Be @('Shared label','Shared label')
        $bundle.profiles[0].UserNames | Should -Contain 'alert-only'
        $bundle.profiles[0].AgentNames | Should -Be @('Engineer One')
        $bundle.profiles[0].DivisionNames | Should -Contain 'division-b'
        $bundle.profiles[0].WrapUpName | Should -Be 'Resolved'
        $bundle.profiles[0].UserDivisionIds | Should -Be @('user-division')
        $bundle.profiles[0].UserDivisionNames | Should -Be @('User Division')
        $bundle.entityResolution.coverage.currentUserDivisionMembership.unresolvedUserIds | Should -Contain 'alert-only'
        $bundle.entityResolution.coverage.divisions.unresolvedIds | Should -Contain 'division-b'
        $bundle.entityResolution.entities.queues.Count | Should -Be 2
        ($bundle.entityResolution | ConvertTo-Json -Depth 20) | Should -Not -Match 'PRIVATE'
        $bundle.coverage.status | Should -Be 'unverified'
        $bundle.statistics.tHandleSec.average | Should -Be 10
    }
    It 'keeps lookup permission failure separate from population completeness without leaking exception bodies' {
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -InputObject @((New-ProfileFixture)) -OutputRoot $TestDrive -ResolveEntityNames -EntityLookupInvoker {
            param($Kind)
            if($Kind -eq 'users'){throw 'HTTP 403 SECRET_RESPONSE_TOKEN'}
            return @{Records=@();Status='complete'}
        }
        $bundle.entityResolution.coverage.users.status | Should -Be 'access-denied'
        $bundle.profiles[0].AgentNames | Should -Be @('agent-1')
        $bundle.coverage.status | Should -Be 'unverified'
        ($bundle | ConvertTo-Json -Depth 40) | Should -Not -Match 'SECRET_RESPONSE_TOKEN'
    }
    It 'discloses truncated lookups and conflicting names rather than selecting an arbitrary label' {
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -InputObject @((New-ProfileFixture)) -OutputRoot $TestDrive -ResolveEntityNames -EntityLookupInvoker {
            return @{Records=@(@{id='q1';name='One'},@{id='q1';name='Two'});Status='complete';Events=@(@{payload=@{eventType='paging.terminated.safetyCap'}})}
        }
        $bundle.entityResolution.coverage.queues.status | Should -Be 'partial'
        $bundle.entityResolution.coverage.queues.unresolvedIds | Should -Contain 'q1'
        $bundle.profiles[0].QueueNames | Should -Be @('q1','q2')
    }
    It 'never infers live lookups from offline records or synthetic collectors' {
        {Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -InputObject @() -ResolveEntityNames -OutputRoot $TestDrive} | Should -Throw '*Offline*'
        {Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -DatasetInvoker {} -ResolveEntityNames -OutputRoot $TestDrive} | Should -Throw '*Synthetic*'
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -InputObject @() -OutputRoot $TestDrive
        $bundle.entityResolution.enabled | Should -BeFalse
    }
    It 'uses Core catalog paging for directory lookup and maps only referenced IDs' {
        $requests=[System.Collections.Generic.List[string]]::new()
        $bundle=Get-GenesysConversationAnalysis -Since '2026-09-01Z' -Until '2026-10-01Z' -ResolveEntityNames -OutputRoot $TestDrive -RequestInvoker {
            param($request)
            $uri=[string]$request.Uri;$requests.Add($uri)
            $payload=if($uri -match '/conversations/details/jobs$'){@{jobId='entity-job'}}
            elseif($uri -match '/jobs/entity-job$'){@{state='FULFILLED'}}
            elseif($uri -match '/results'){@{conversations=@(@{conversationId='entity-test';divisionIds=@('d1');participants=@(@{purpose='agent';userId='u1';sessions=@(@{mediaType='voice';segments=@(@{segmentType='interact';queueId='q1'})})})})}}
            elseif($uri -match '/users\?'){@{entities=@(@{id='u1';name='User One';email='PRIVATE EMAIL'})}}
            elseif($uri -match '/routing/queues.*pageNumber=2'){@{entities=@(@{id='q1';name='Queue One'})}}
            elseif($uri -match '/routing/queues'){@{entities=@(@{id='unreferenced';name='Other'});nextUri='/api/v2/routing/queues?pageNumber=2'}}
            elseif($uri -match '/authorization/divisions'){@{entities=@(@{id='d1';name='Division One'})}}
            else{throw "Unexpected request $uri"}
            return [pscustomobject]@{Result=($payload|ConvertTo-Json -Depth 30|ConvertFrom-Json)}
        }
        @($requests | Where-Object {$_ -match '/routing/queues'}).Count | Should -Be 2
        $bundle.profiles[0].QueueNames | Should -Be @('Queue One')
        $bundle.profiles[0].AgentNames | Should -Be @('User One')
        $bundle.profiles[0].DivisionNames | Should -Be @('Division One')
        $bundle.entityResolution.coverage.queues.status | Should -Be 'complete'
        Test-Path $bundle.entityResolution.coverage.queues.evidencePath | Should -BeTrue
    }
}

Describe 'Operational media evidence' {
    It 'retains flow IDs and packet observations without inventing network loss or double-counting components' {
        $record=New-ProfileFixture
        $record.participants[1].sessions[0] | Add-Member -NotePropertyName flow -NotePropertyValue @{flowId='flow-1';flowName='IVR One'}
        $record.participants[1].sessions[0].mediaEndpointStats=@(
            @{discardedPackets=4;receivedPackets=100;overrunPackets=2;underrunPackets=2;eventTime='2026-09-01T00:00:20Z'},
            @{discardedPackets=0;receivedPackets=100},@{minMos=4})
        $profile=$record | Get-GenesysConversationProfile
        $profile.FlowIds | Should -Be @('flow-1')
        $profile.AvgDiscardedPackets | Should -Be 2
        $profile.MaxDiscardedPackets | Should -Be 4
        $profile.DiscardedPacketSamples | Should -Be 2
        $profile.EndpointStats.Count | Should -Be 3
        $profile.EndpointStats[0].OverrunPackets | Should -Be 2
        $profile.PSObject.Properties.Name | Should -Not -Contain 'PacketLossRate'
        $empty=[pscustomobject]@{conversationId='no-media'} | Get-GenesysConversationProfile
        $empty.AvgDiscardedPackets | Should -BeNullOrEmpty
        $empty.DiscardedPacketSamples | Should -Be 0
    }
}
