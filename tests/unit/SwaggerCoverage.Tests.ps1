Describe 'Swagger coverage' {
    It 'covers all swagger operationIds in catalog endpoints when swagger is available' {
        $repoRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
        $swaggerPath = Join-Path -Path $repoRoot -ChildPath 'generated/swagger/swagger.json'
        if (-not (Test-Path -Path $swaggerPath)) {
            Set-ItResult -Skipped -Because 'generated/swagger/swagger.json not found; run scripts/Update-CatalogFromSwagger.ps1 to enable coverage checks.'
            return
        }

        $convertCommand = Get-Command -Name ConvertFrom-Json
        if (-not $convertCommand.Parameters.ContainsKey('AsHashTable')) {
            Set-ItResult -Skipped -Because 'generated swagger contains case-only duplicate keys and requires PowerShell 7+ ConvertFrom-Json -AsHashTable.'
            return
        }

        $swagger = Get-Content -Path $swaggerPath -Raw | ConvertFrom-Json -Depth 100 -AsHashTable
        $denylistPath = Join-Path -Path $repoRoot -ChildPath 'generated/swagger/denylist.operationIds.txt'

        $denylist = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::Ordinal)
        if (Test-Path -Path $denylistPath) {
            foreach ($line in Get-Content -Path $denylistPath) {
                $trimmed = ([string]$line).Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed)) {
                    continue
                }
                if ($trimmed.StartsWith('#')) {
                    continue
                }

                $denylist[$trimmed] = $true
            }
        }

        $operationIds = New-Object System.Collections.Generic.List[string]
        $seenOperationIds = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $caseCollisionSkipped = New-Object System.Collections.Generic.List[string]
        foreach ($pathKey in $swagger['paths'].Keys) {
            $pathValue = $swagger['paths'][$pathKey]
            foreach ($methodKey in $pathValue.Keys) {
                $methodProperty = $pathValue[$methodKey]
                $methodName = ([string]$methodKey).ToLowerInvariant()
                if (@('get', 'post', 'put', 'patch', 'delete') -notcontains $methodName) {
                    continue
                }

                $operationId = [string]$methodProperty['operationId']
                if ([string]::IsNullOrWhiteSpace($operationId)) {
                    continue
                }

                if ($denylist.ContainsKey($operationId)) {
                    continue
                }

                if ($seenOperationIds.ContainsKey($operationId)) {
                    $existingOperationId = $seenOperationIds[$operationId]
                    if ($existingOperationId -cne $operationId) {
                        $caseCollisionSkipped.Add($operationId) | Out-Null
                        continue
                    }
                }
                else {
                    $seenOperationIds[$operationId] = $operationId
                }

                $operationIds.Add($operationId) | Out-Null
            }
        }

        $catalogPath = Join-Path -Path $repoRoot -ChildPath 'catalog/genesys.catalog.json'
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
        $endpointKeys = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $exactEndpointKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($endpointProperty in $catalog.endpoints.PSObject.Properties) {
            $endpointKeys[$endpointProperty.Name] = $true
            $exactEndpointKeys.Add($endpointProperty.Name) | Out-Null
        }

        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($operationId in $operationIds) {
            if (-not $endpointKeys.ContainsKey($operationId)) {
                $missing.Add($operationId) | Out-Null
            }
        }

        @($missing).Count | Should -Be 0 -Because "Missing operationIds: $([string]::Join(', ', @($missing)))"
        foreach ($operationId in $caseCollisionSkipped) {
            $exactEndpointKeys.Contains($operationId) | Should -BeFalse -Because "Case-only duplicate operationId '$operationId' should not be written to the PowerShell-compatible catalog endpoint map."
        }
    }
}


