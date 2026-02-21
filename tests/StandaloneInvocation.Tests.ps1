Describe 'Standalone Invoke-Dataset.ps1 Invocation' {
    BeforeAll {
        $tempDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { '/tmp' }
        $script:testOutputRoot = Join-Path -Path $tempDir -ChildPath "genesys-core-test-$(Get-Random)"
    }

    AfterAll {
        if (Test-Path -Path $script:testOutputRoot) {
            Remove-Item -Path $script:testOutputRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'loads required private functions when invoked standalone' {
        # Invoke the script in a fresh PowerShell session to ensure module functions are not pre-loaded
        $script = @'
. ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1

$functionNames = @('Write-RunEvent', 'New-RunContext', 'Resolve-Catalog', 'Invoke-RegisteredDataset', 'Write-Manifest')
$allPresent = $true
foreach ($name in $functionNames) {
    if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
        Write-Host "Missing function: $name"
        $allPresent = $false
    }
}
exit ([int](-not $allPresent))
'@
        $output = & pwsh -NoProfile -Command $script 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "All required functions should be available after dot-sourcing the script"
    }

    It 'creates output directory structure when run in WhatIf mode' {
        $output = & pwsh -NoProfile -File ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 -Dataset audit-logs -OutputRoot $script:testOutputRoot -WhatIf 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'WhatIf'
        ($output | Out-String) | Should -Match 'manifest/events/summary/data'
    }

    It 'does not throw function not found errors when invoked with pwsh -File' {
        $output = & pwsh -NoProfile -File ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1 -Dataset audit-logs -OutputRoot $script:testOutputRoot -WhatIf 2>&1
        $outputStr = $output | Out-String
        
        $outputStr | Should -Not -Match 'Write-RunEvent.*is not recognized'
        $outputStr | Should -Not -Match 'New-RunContext.*is not recognized'
        $outputStr | Should -Not -Match 'Resolve-Catalog.*is not recognized'
        $outputStr | Should -Not -Match 'Invoke-RegisteredDataset.*is not recognized'
        $outputStr | Should -Not -Match 'Write-Manifest.*is not recognized'
    }

    It 'passes Authorization header from GENESYS_BEARER_TOKEN env var when set' {
        $script = @'
. ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1

$script:capturedHeaders = $null
$requestInvoker = {
    param($request)
    $script:capturedHeaders = $request.Headers
    throw 'stop-after-capture'
}

$env:GENESYS_BEARER_TOKEN = 'test-token-value'
try {
    Invoke-Dataset -Dataset 'audit-logs' -BaseUri 'https://api.test.local' -OutputRoot ([System.IO.Path]::GetTempPath()) -RequestInvoker $requestInvoker
} catch {}

if ($null -eq $script:capturedHeaders -or $script:capturedHeaders['Authorization'] -ne 'Bearer test-token-value') {
    Write-Host "Authorization header not set correctly: $($script:capturedHeaders['Authorization'])"
    exit 1
}
exit 0
'@
        $output = & pwsh -NoProfile -Command $script 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "Authorization header should be set from GENESYS_BEARER_TOKEN env var"
    }

    It 'does not set Authorization header when GENESYS_BEARER_TOKEN env var is absent' {
        $script = @'
. ./src/ps-module/Genesys.Core/Public/Invoke-Dataset.ps1

$script:capturedHeaders = $null
$requestInvoker = {
    param($request)
    $script:capturedHeaders = $request.Headers
    throw 'stop-after-capture'
}

$env:GENESYS_BEARER_TOKEN = ''
try {
    Invoke-Dataset -Dataset 'audit-logs' -BaseUri 'https://api.test.local' -OutputRoot ([System.IO.Path]::GetTempPath()) -RequestInvoker $requestInvoker
} catch {}

if ($null -ne $script:capturedHeaders -and $script:capturedHeaders['Authorization']) {
    Write-Host "Authorization header unexpectedly set: $($script:capturedHeaders['Authorization'])"
    exit 1
}
exit 0
'@
        $savedToken = $env:GENESYS_BEARER_TOKEN
        $env:GENESYS_BEARER_TOKEN = ''
        try {
            $output = & pwsh -NoProfile -Command $script 2>&1
        } finally {
            $env:GENESYS_BEARER_TOKEN = $savedToken
        }
        $LASTEXITCODE | Should -Be 0 -Because "Authorization header should not be set when GENESYS_BEARER_TOKEN is absent"
    }
}
