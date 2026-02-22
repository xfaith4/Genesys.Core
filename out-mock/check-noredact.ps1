Import-Module 'G:\Development\20_Staging\Genesys.Core\src\ps-module\Genesys.Core\Genesys.Core.psd1' -Force

$requestInvoker = {
    param($request)
    $uri    = [string]$request.Uri
    $method = [string]$request.Method

    if ($method -eq 'GET' -and $uri -like '*/audits/query/servicemapping') {
        return [pscustomobject]@{ Result = @('routing') }
    }
    if ($method -eq 'POST' -and $uri -like '*/audits/query') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ transactionId = 'test-tx' } }
    }
    if ($method -eq 'GET' -and $uri -like '*/audits/query/test-tx' -and $uri -notlike '*/results*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{ state = 'FULFILLED' } }
    }
    if ($method -eq 'GET' -and $uri -like '*/audits/query/test-tx/results*') {
        return [pscustomobject]@{ Result = [pscustomobject]@{
            results = @(
                [pscustomobject]@{ id = 'r1'; userId = 'real-user-id'; userEmail = 'real@email.com'; action = 'CREATE'; serviceName = 'routing' }
            )
            nextUri = $null
            totalHits = 1
        } }
    }
    throw "Unexpected: $method $uri"
}

$outputRoot = 'G:\Development\20_Staging\Genesys.Core\out-mock\noredact-test'

# Run WITH redaction (default)
Invoke-Dataset -Dataset 'audit-logs' -CatalogPath 'G:\Development\20_Staging\Genesys.Core\catalog\genesys-core.catalog.json' -OutputRoot "$outputRoot\redacted" -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker | Out-Null
$script:auditPolled = $false

# Run WITHOUT redaction
Invoke-Dataset -Dataset 'audit-logs' -CatalogPath 'G:\Development\20_Staging\Genesys.Core\catalog\genesys-core.catalog.json' -OutputRoot "$outputRoot\unredacted" -BaseUri 'https://api.test.local' -RequestInvoker $requestInvoker -NoRedact | Out-Null

# Check results
$redactedRun   = Get-ChildItem "$outputRoot\redacted\audit-logs" -Directory | Select-Object -First 1
$unredactedRun = Get-ChildItem "$outputRoot\unredacted\audit-logs" -Directory | Select-Object -First 1

$rRec = (Get-Content (Join-Path $redactedRun.FullName 'data/audit.jsonl')   | ConvertFrom-Json)
$uRec = (Get-Content (Join-Path $unredactedRun.FullName 'data/audit.jsonl') | ConvertFrom-Json)

Write-Host ''
Write-Host 'With redaction (default):'
Write-Host "  userId    = $($rRec.userId)"
Write-Host "  userEmail = $($rRec.userEmail)"
Write-Host ''
Write-Host 'With -NoRedact:'
Write-Host "  userId    = $($uRec.userId)"
Write-Host "  userEmail = $($uRec.userEmail)"
