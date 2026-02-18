[CmdletBinding()]
param(
    [string]$OutputRoot = 'out-smoke',
    [switch]$StrictCatalog
)

Import-Module "$PSScriptRoot/../src/ps-module/Genesys.Core/Genesys.Core.psd1" -Force
$schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../catalog/schema/genesys-core.catalog.schema.json'

Write-Host 'Running catalog validation...'
Assert-Catalog -SchemaPath $schemaPath -StrictCatalog:$StrictCatalog | Out-Null

$requestInvoker = {
    param($request)
    $uri = [string]$request.Uri
    $method = [string]$request.Method

    if ($method -eq 'GET' -and $uri -eq 'https://api.smoke.local/api/v2/audits/query/servicemapping') {
        return [pscustomobject]@{ Result = @('routing') }
    }
    if ($method -eq 'POST' -and $uri -eq 'https://api.smoke.local/api/v2/audits/query') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'smoke-tx' } }
    }
    if ($method -eq 'GET' -and $uri -eq 'https://api.smoke.local/api/v2/audits/query/smoke-tx') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
    }
    if ($method -eq 'GET' -and $uri -eq 'https://api.smoke.local/api/v2/audits/query/smoke-tx/results') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ results = @([pscustomobject]@{ id='a1'; action='create'; serviceName='routing'; authorization='Bearer token' }); nextUri = $null } }
    }
    if ($method -eq 'GET' -and $uri -eq 'https://api.smoke.local/api/v2/users') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ entities = @([pscustomobject]@{ id='u1'; name='Smoke User'; email='smoke@example.com'; state='active' }); nextUri = $null } }
    }
    if ($method -eq 'GET' -and $uri -eq 'https://api.smoke.local/api/v2/routing/queues') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ entities = @([pscustomobject]@{ id='q1'; name='Smoke Queue'; memberCount=1; joined=$true; division=[pscustomobject]@{ id='d1' } }); nextUri = $null } }
    }

    throw "Unexpected smoke request: $($method) $($uri)"
}

foreach ($dataset in @('audit-logs', 'users', 'routing-queues')) {
    Write-Host "Running dry-run ingest for $($dataset)..."
    Invoke-Dataset -Dataset $dataset -OutputRoot $OutputRoot -BaseUri 'https://api.smoke.local' -RequestInvoker $requestInvoker | Out-Null
}

Write-Host "Smoke run complete at '$($OutputRoot)'."
