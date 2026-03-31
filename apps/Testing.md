# Validation Testing

## Quick module validation (Genesys.Ops)

```powershell
Import-Module .\modules\Genesys.Ops\Genesys.Ops.psd1 -Force
Connect-GenesysCloud -AccessToken $env:GENESYS_BEARER_TOKEN -Region 'usw2.pure.cloud'
Get-GenesysQueue | Select-Object -First 5 name, memberCount
```

---

## Interactive validation menu (Genesys.Core direct)

Loads Genesys.Core directly — no Genesys.Ops layer.  Use this first to confirm
catalog resolution, module load, and live API connectivity before testing
anything higher.

### Setup

```powershell
# Option A: bearer token (fastest)
$env:GENESYS_BEARER_TOKEN  = '<your-token>'

# Option B: client credentials (script obtains token automatically)
$env:GENESYS_CLIENT_ID     = '<client-id>'
$env:GENESYS_CLIENT_SECRET = '<client-secret>'

# Region (defaults to usw2.pure.cloud if omitted)
$env:GENESYS_REGION = 'usw2.pure.cloud'
```

### Run (from any directory)

```powershell
pwsh .\scripts\Invoke-ValidationMenu.ps1
```

### What it does

1. Imports `modules/Genesys.Core/Genesys.Core.psd1` directly
2. Resolves credentials from env vars
3. Reads the catalog and groups all ~70 datasets by category
4. Presents a numbered menu: pick category → pick dataset → runs it live
5. Displays the summary JSON + first 5 records on success, or the raw error on failure

### Optional parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-Region` | `$env:GENESYS_REGION` or `usw2.pure.cloud` | Override region |
| `-OutputRoot` | `$env:TEMP\GenesysValidation` | Where run artifacts are written |
| `-PreviewRows` | `5` | How many records to display after a successful run |

```powershell
# Example: different region, show 10 rows
pwsh .\scripts\Invoke-ValidationMenu.ps1 -Region mypurecloud.com -PreviewRows 10
```
