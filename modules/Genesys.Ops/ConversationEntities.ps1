# Run-scoped entity labels; collection, paging and redaction remain owned by Core.
function Resolve-GcConversationEntities {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Profiles, [string]$OutputRoot,
        [switch]$Enabled, [scriptblock]$LookupInvoker, [scriptblock]$RequestInvoker)
    if (-not $Enabled) { return @{enabled=$false;entities=@{};coverage=@{};warnings=@();nameAsOfUtc=$null;definition='Name resolution not requested; IDs remain authoritative.'} }
    $specs = @(
        @{kind='queues';dataset='routing-queues';fields=@('QueueIds');names=@('QueueNames')},
        @{kind='users';dataset='users';fields=@('AgentKeys','UserIds');names=@('AgentNames','UserNames')},
        @{kind='divisions';dataset='authorization.get.all.divisions';fields=@('DivisionIds','UserDivisionIds','AgentDivisionIds');names=@('DivisionNames','UserDivisionNames','AgentDivisionNames')},
        @{kind='wrapupCodes';dataset='routing.get.all.wrapup.codes';fields=@('WrapUpCodeId');names=@('WrapUpName')},
        @{kind='skills';dataset='routing.get.all.routing.skills';fields=@('SkillIds');names=@('SkillNames')},
        @{kind='languages';dataset='routing.get.all.languages';fields=@('LanguageIds');names=@('LanguageNames')}
    )
    $userDivisions = @{}
    $entities = @{}; $coverage = @{}; $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($spec in $specs) {
        $wanted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($row in $Profiles) { foreach ($field in $spec.fields) {
            foreach ($id in @(Get-GcVolumeProperty $row $field @())) { if (-not [string]::IsNullOrWhiteSpace([string]$id)) { $null=$wanted.Add([string]$id) } }
        } }
        $map = @{}; $entities[$spec.kind] = $map
        $state = 'not-requested'; $evidence = $null; $records = @(); $events = @()
        if ($Enabled -and $wanted.Count) {
            try {
                if ($LookupInvoker) {
                    $result = & $LookupInvoker -Kind $spec.kind -Dataset $spec.dataset -Ids @($wanted | Sort-Object) -OutputRoot $OutputRoot
                    $records = @(Get-GcVolumeProperty $result 'Records' @())
                    $state = [string](Get-GcVolumeProperty $result 'Status' 'unverified')
                    if ($state -notin @('complete','partial','unverified','access-denied','failed')) { throw 'Invalid lookup status.' }
                    $events = @(Get-GcVolumeProperty $result 'Events' @())
                    $evidence = Get-GcVolumeProperty $result 'EvidencePath'
                }
                else {
                    $arguments = @{Dataset=$spec.dataset;OutputRoot=$OutputRoot;BaseUri=$script:GC.BaseUri;Headers=$script:GC.Headers;ErrorAction='Stop'}
                    if ($script:GC.CatalogPath) { $arguments.CatalogPath=$script:GC.CatalogPath }
                    if ($RequestInvoker) { $arguments.RequestInvoker=$RequestInvoker }
                    $context = Invoke-Dataset @arguments
                    $evidence = $context.runFolder
                    $records = @(foreach ($file in @(Get-ChildItem $context.dataFolder -Filter '*.jsonl')) {
                        foreach ($line in [IO.File]::ReadLines($file.FullName)) { if ($line.Trim()) { $line | ConvertFrom-Json } }
                    })
                    $events = @(Get-Content $context.eventsPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
                    $state = 'complete'
                }
                foreach ($event in $events) {
                    $payload=Get-GcVolumeProperty $event 'payload' $event
                    if ((Get-GcVolumeProperty $payload 'eventType' '') -like 'paging.terminated.*') { $state='partial' }
                }
                if ($state -in @('access-denied','failed')) { $records=@() }
                foreach ($record in $records) {
                    $id=[string](Get-GcVolumeProperty $record 'id' '')
                    if (-not $wanted.Contains($id)) { continue }
                    if ($spec.kind -eq 'users') {
                        $divisionId=[string](Get-GcVolumeProperty (Get-GcVolumeProperty $record 'division') 'id' '')
                        if ($divisionId) {
                            if ($userDivisions.ContainsKey($id) -and $userDivisions[$id] -ne $divisionId) { $userDivisions[$id]=$null; $state='partial' }
                            elseif (-not $userDivisions.ContainsKey($id)) { $userDivisions[$id]=$divisionId }
                        }
                    }
                    $name=[string](Get-GcVolumeProperty $record 'name' '')
                    if ([string]::IsNullOrWhiteSpace($name) -or $name -eq '[REDACTED]') { continue }
                    if ($map.ContainsKey($id) -and $map[$id] -ne $name) { $state='partial'; $map[$id]=$null }
                    elseif (-not $map.ContainsKey($id)) { $map[$id]=$name }
                }
            }
            catch {
                $state=if ($_.Exception.Message -match '\b(401|403)\b') {'access-denied'} else {'failed'}
                # Do not serialize an exception that may include a URL, headers or response body.
                $warnings.Add("Entity lookup $($spec.kind): $state. IDs remain available.")
            }
        }
        elseif ($Enabled) { $state='not-needed' }
        $missing = @($wanted | Where-Object { -not $map.ContainsKey($_) -or $null -eq $map[$_] } | Sort-Object)
        foreach ($id in @($map.Keys)) { if ($null -eq $map[$id]) { $map.Remove($id) } }
        if ($Enabled -and $wanted.Count -and ($missing.Count -or $state -ne 'complete')) {
            $warnings.Add("Entity labels $($spec.kind): $state; $($wanted.Count - $missing.Count)/$($wanted.Count) referenced IDs resolved. Missing labels may reflect permissions, deleted entities or incomplete data.")
        }
        $coverage[$spec.kind]=@{status=$state;dataset=$spec.dataset;requested=$wanted.Count;resolved=$wanted.Count-$missing.Count;unresolvedIds=$missing;evidencePath=$evidence}
        if ($Enabled) {
            if ($spec.kind -eq 'users') {
                foreach ($row in $Profiles) { foreach ($pair in @(@{ids='UserIds';divisions='UserDivisionIds'},@{ids='AgentKeys';divisions='AgentDivisionIds'})) {
                    $divisions=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    foreach ($id in @(Get-GcVolumeProperty $row $pair.ids @())) { if ($userDivisions.ContainsKey([string]$id) -and $userDivisions[[string]$id]) { $null=$divisions.Add($userDivisions[[string]$id]) } }
                    $row | Add-Member -NotePropertyName $pair.divisions -NotePropertyValue @($divisions | Sort-Object) -Force
                } }
                $unknownMembership=@($wanted | Where-Object { -not $userDivisions.ContainsKey($_) -or -not $userDivisions[$_] } | Sort-Object)
                $coverage.currentUserDivisionMembership=@{status=if ($unknownMembership.Count) {'partial'} else {'complete'};requestedUsers=$wanted.Count;resolvedUsers=$wanted.Count-$unknownMembership.Count;unresolvedUserIds=$unknownMembership;asOf='directory lookup time, not incident time'}
                if ($unknownMembership.Count) { $warnings.Add("Current user-Division membership is unavailable for $($unknownMembership.Count) referenced users; historical membership is unverified.") }
            }
            foreach ($row in $Profiles) { for ($i=0; $i -lt $spec.fields.Count; $i++) {
                $labels=@(foreach ($id in @(Get-GcVolumeProperty $row $spec.fields[$i] @())) {
                    if ([string]::IsNullOrWhiteSpace([string]$id)) { continue }
                    if ($map.ContainsKey([string]$id)) { $map[[string]$id] } else { [string]$id }
                })
                $value=if ($spec.fields[$i] -eq 'WrapUpCodeId') { if ($labels.Count) {$labels[0]} else {$null} } else { ,$labels }
                $row | Add-Member -NotePropertyName $spec.names[$i] -NotePropertyValue $value -Force
            } }
        }
    }
    return @{enabled=[bool]$Enabled;entities=$entities;currentUserDivisions=$userDivisions;coverage=$coverage;warnings=@($warnings.ToArray());nameAsOfUtc=[datetime]::UtcNow.ToString('o');definition='Current entity labels at collection time; IDs remain authoritative. Missing names retain the ID. Names are not historical identity evidence.'}
}
