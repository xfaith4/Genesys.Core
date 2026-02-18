Describe 'Swagger coverage' {
    It 'covers all swagger operationIds in catalog endpoints when swagger is available' {
        $repoRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
        $swaggerPath = Join-Path -Path $repoRoot -ChildPath 'generated/swagger/swagger.json'
        if (-not (Test-Path -Path $swaggerPath)) {
            Set-ItResult -Skipped -Because 'generated/swagger/swagger.json not found; run scripts/Update-CatalogFromSwagger.ps1 to enable coverage checks.'
            return
        }

        $swagger = Get-Content -Path $swaggerPath -Raw | ConvertFrom-Json -Depth 100
        $denylistPath = Join-Path -Path $repoRoot -ChildPath 'generated/swagger/denylist.operationIds.txt'

        $denylist = @{}
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
        foreach ($pathProperty in $swagger.paths.PSObject.Properties) {
            foreach ($methodProperty in $pathProperty.Value.PSObject.Properties) {
                $methodName = ([string]$methodProperty.Name).ToLowerInvariant()
                if (@('get', 'post', 'put', 'patch', 'delete') -notcontains $methodName) {
                    continue
                }

                $operationId = [string]$methodProperty.Value.operationId
                if ([string]::IsNullOrWhiteSpace($operationId)) {
                    continue
                }

                if ($denylist.ContainsKey($operationId)) {
                    continue
                }

                $operationIds.Add($operationId) | Out-Null
            }
        }

        $catalogPath = Join-Path -Path $repoRoot -ChildPath 'genesys-core.catalog.json'
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -Depth 100
        $endpointKeys = @{}
        foreach ($endpointProperty in $catalog.endpoints.PSObject.Properties) {
            $endpointKeys[$endpointProperty.Name] = $true
        }

        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($operationId in $operationIds) {
            if (-not $endpointKeys.ContainsKey($operationId)) {
                $missing.Add($operationId) | Out-Null
            }
        }

        @($missing).Count | Should -Be 0 -Because "Missing operationIds: $([string]::Join(', ', @($missing)))"
    }
}
