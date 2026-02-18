# Testing Guide for Genesys.Core

This document provides comprehensive instructions for testing the Genesys.Core PowerShell module in various environments.

## Table of Contents
- [Quick Start](#quick-start)
- [Local Development Testing](#local-development-testing)
- [Production Environment Testing](#production-environment-testing)
- [Test Suite Overview](#test-suite-overview)
- [Variable Passing and Context](#variable-passing-and-context)
- [CI/CD Integration](#cicd-integration)

## Quick Start

### Prerequisites
- PowerShell 5.1 or PowerShell 7+
- Pester 5.x (for unit tests)
- Valid Genesys Cloud credentials (for production testing)

### Running All Tests
```powershell
# Load test configuration and run all tests
$config = . ./tests/PesterConfiguration.ps1
Invoke-Pester -Configuration $config
```

### Running Smoke Tests
```powershell
# Quick validation without real API calls
pwsh -NoProfile -File ./scripts/Invoke-Smoke.ps1
```

## Local Development Testing

### Unit Tests
The test suite includes comprehensive coverage of core functionality:

```powershell
# Run specific test files
Invoke-Pester -Path ./tests/CatalogSchema.Tests.ps1
Invoke-Pester -Path ./tests/Paging.Tests.ps1
Invoke-Pester -Path ./tests/Retry.Tests.ps1
```

### Test Categories

1. **Catalog Validation** (`CatalogSchema.Tests.ps1`)
   - Validates catalog structure against JSON schema
   - Ensures all datasets have required fields
   - Checks paging and retry profile consistency

2. **Catalog Resolution** (`CatalogResolution.Tests.ps1`)
   - Tests precedence between root and legacy catalog locations
   - Validates strict mode behavior
   - Tests catalog conflict detection

3. **Paging Strategies** (`Paging.Tests.ps1`)
   - NextUri pagination
   - PageNumber pagination  
   - Cursor pagination
   - BodyPaging with totalHits
   - ItemsPath resolution

4. **Retry Logic** (`Retry.Tests.ps1`)
   - 429 rate limit handling
   - Retry-After header parsing
   - Exponential backoff with jitter
   - POST retry behavior (disabled by default)

5. **Dataset Execution** (`AuditLogs.Dataset.Tests.ps1`, `AdditionalDatasets.Tests.ps1`)
   - Async transaction flow (submit → poll → results)
   - Data normalization
   - Output file generation
   - Redaction of sensitive data

6. **Security & Redaction** (`Security.Redaction.Tests.ps1`)
   - Sensitive field detection (email, token, password, etc.)
   - Bearer token redaction
   - JWT redaction
   - Request logging sanitization

7. **Run Contract** (`RunContract.Tests.ps1`)
   - Output folder structure validation
   - Manifest file generation
   - Events logging
   - Summary file creation

## Production Environment Testing

### Authentication Setup

Before running tests against a production Genesys Cloud environment, set up authentication:

```powershell
# Option 1: OAuth Client Credentials
$clientId = 'your-client-id'
$clientSecret = 'your-client-secret'
$authUrl = 'https://login.mypurecloud.com/oauth/token'

$body = @{
    grant_type = 'client_credentials'
    client_id = $clientId
    client_secret = $clientSecret
}

$authResponse = Invoke-RestMethod -Uri $authUrl -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'
$accessToken = $authResponse.access_token

$headers = @{
    Authorization = "Bearer $accessToken"
}

# Option 2: Use existing token
$headers = @{
    Authorization = "Bearer YOUR_EXISTING_TOKEN"
}
```

### Running Production Tests

#### Dry Run (WhatIf)
```powershell
Import-Module ./src/ps-module/Genesys.Core/Genesys.Core.psd1 -Force

# Preview what would happen without making API calls
Invoke-Dataset -Dataset 'users' -WhatIf
Invoke-Dataset -Dataset 'audit-logs' -WhatIf
Invoke-Dataset -Dataset 'routing-queues' -WhatIf
```

#### Actual Execution
```powershell
# Run against production with authentication
$baseUri = 'https://api.mypurecloud.com'  # Or your region's API endpoint
$outputRoot = './out'

# Execute users dataset
Invoke-Dataset -Dataset 'users' -OutputRoot $outputRoot -BaseUri $baseUri -Headers $headers

# Execute audit logs dataset
Invoke-Dataset -Dataset 'audit-logs' -OutputRoot $outputRoot -BaseUri $baseUri -Headers $headers

# Execute routing queues dataset
Invoke-Dataset -Dataset 'routing-queues' -OutputRoot $outputRoot -BaseUri $baseUri -Headers $headers
```

### Validating Output

After execution, verify the output structure:

```powershell
# Check output structure for a dataset run
$datasetKey = 'users'
$runFolders = Get-ChildItem -Path "./out/$datasetKey" -Directory | Sort-Object Name -Descending
$latestRun = $runFolders[0].FullName

# Validate required files exist
Test-Path "$latestRun/manifest.json"     # Should be True
Test-Path "$latestRun/events.jsonl"      # Should be True
Test-Path "$latestRun/summary.json"      # Should be True
Test-Path "$latestRun/data"              # Should be True

# Inspect manifest
$manifest = Get-Content "$latestRun/manifest.json" -Raw | ConvertFrom-Json
Write-Host "Dataset: $($manifest.datasetKey)"
Write-Host "Run ID: $($manifest.runId)"
Write-Host "Started: $($manifest.startedAtUtc)"
Write-Host "Completed: $($manifest.completedAtUtc)"
Write-Host "Item Count: $($manifest.counts.itemCount)"

# Inspect events
$events = Get-Content "$latestRun/events.jsonl" | ForEach-Object { $_ | ConvertFrom-Json }
$events | Group-Object eventType | Select-Object Name, Count

# Inspect summary
$summary = Get-Content "$latestRun/summary.json" -Raw | ConvertFrom-Json
$summary | ConvertTo-Json -Depth 5
```

## Variable Passing and Context

### RunContext Structure
The `RunContext` object is the primary mechanism for passing state through the execution pipeline:

```powershell
# RunContext is created by Invoke-Dataset and contains:
@{
    datasetKey     = 'users'                                    # Dataset identifier
    runId          = '20260218T120000Z'                         # ISO 8601 timestamp
    outputRoot     = 'out'                                      # Base output directory
    runFolder      = 'out/users/20260218T120000Z'              # Full run path
    dataFolder     = 'out/users/20260218T120000Z/data'         # Data files path
    manifestPath   = 'out/users/20260218T120000Z/manifest.json'
    eventsPath     = 'out/users/20260218T120000Z/events.jsonl'
    summaryPath    = 'out/users/20260218T120000Z/summary.json'
    startedAtUtc   = '2026-02-18T12:00:00.000Z'
}
```

### Context Passing Flow
1. **Invoke-Dataset** → Creates RunContext
2. **Invoke-RegisteredDataset** → Receives RunContext, routes to dataset handler
3. **Dataset Handler** (e.g., Invoke-UsersDataset) → Uses RunContext for output paths
4. **Invoke-CoreEndpoint** → Receives RunEvents list (passed by reference)
5. **Paging Functions** → Append events to RunEvents
6. **Write-DatasetOutputs** → Uses RunContext to write files

### Variable Scoping Notes
- All context is passed **explicitly via parameters** (no global variables)
- `RunEvents` uses `List<object>` passed by reference for efficient event collection
- Catalog and Headers are passed through the call chain
- Scriptblocks in tests should use `$script:` scope for variables modified inside the block

### Example: Custom Dataset Handler
```powershell
function Invoke-CustomDataset {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RunContext,          # Run metadata and paths
        
        [Parameter(Mandatory = $true)]
        [psobject]$Catalog,             # Catalog object with endpoints
        
        [string]$BaseUri = 'https://api.mypurecloud.com',
        [hashtable]$Headers,            # Authentication headers
        [scriptblock]$RequestInvoker    # Optional mock for testing
    )
    
    # RunContext provides all output paths
    $dataPath = Join-Path -Path $RunContext.dataFolder -ChildPath 'custom.jsonl'
    
    # Events are collected and written to RunContext.eventsPath
    Write-RunEvent -RunContext $RunContext -EventType 'custom.started' -Payload @{}
    
    # ... dataset logic ...
    
    Write-Manifest -RunContext $RunContext -Counts @{ itemCount = $count }
}
```

## CI/CD Integration

### GitHub Actions
The repository includes example workflows in `.github/workflows/`:

- `ci.yml` - Runs Pester tests on PR and push
- `audit-logs.scheduled.yml` - Scheduled dataset execution
- `audit-logs.on-demand.yml` - Manual workflow dispatch

### Environment Variables
```yaml
env:
  GENESYS_CLIENT_ID: ${{ secrets.GENESYS_CLIENT_ID }}
  GENESYS_CLIENT_SECRET: ${{ secrets.GENESYS_CLIENT_SECRET }}
  GENESYS_REGION: 'mypurecloud.com'
```

### Artifact Upload
```yaml
- name: Upload run artifacts
  uses: actions/upload-artifact@v3
  with:
    name: audit-logs-${{ env.RUN_ID }}
    path: out/audit-logs/**/*
    retention-days: 7
```

## Troubleshooting

### Common Issues

**Issue:** Tests fail with "Assert-Catalog is not recognized"
- **Solution:** Ensure module is imported with `-Force`: `Import-Module ./src/ps-module/Genesys.Core/Genesys.Core.psd1 -Force`

**Issue:** Paging profile not found (e.g., "nextUri_auditResults")
- **Solution:** This is fixed in the latest version. The code now normalizes variant profiles (nextUri_* → nexturi)

**Issue:** Retry tests fail with attempt count mismatch
- **Solution:** Use `$script:` scope for variables modified inside scriptblocks

**Issue:** Network errors in CI
- **Solution:** Expected for tests that make real HTTP calls. Use `RequestInvoker` parameter to mock HTTP calls:
```powershell
$mockInvoker = {
    param($request)
    return [pscustomobject]@{ Result = @(...) }
}
Invoke-Dataset -Dataset 'users' -RequestInvoker $mockInvoker
```

## Best Practices

1. **Always use WhatIf** before production runs
2. **Validate authentication** before executing datasets
3. **Check output artifacts** after each run
4. **Monitor events.jsonl** for retry behavior and errors
5. **Use RequestInvoker mocks** for repeatable testing
6. **Set GITHUB_SHA** environment variable for run traceability
7. **Configure appropriate artifact retention** for production runs

## Support

For issues or questions:
- Review AGENTS.md for architectural guidelines
- Check existing tests for usage examples
- Ensure catalog is valid: `Assert-Catalog -SchemaPath ./catalog/schema/genesys-core.catalog.schema.json`
