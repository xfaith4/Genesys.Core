# Engineer Integrations: Genesys Authentication + UI Wrapper Patterns

## Purpose

This document defines how authentication works across the Auth/Core/Ops lane architecture
and gives production-oriented integration patterns for UI applications (HTML/JS, PowerShell, .NET, Go).

Goal: any wrapper app should have a simple, stable path to run catalog-driven datasets without re-implementing Genesys API logic.

## Lane Auth Ownership

### `Genesys.Auth` (owns token lifecycle)

- Location: `modules/Genesys.Auth/Genesys.Auth.psd1`
- **This is the only module that calls Genesys login endpoints.**
- Provides:
  - `Connect-GenesysCloud -AccessToken -Region` — stores token in memory, returns **AuthContext**
  - `Connect-GenesysCloudApp -ClientId -ClientSecret -Region` — client credentials OAuth flow, returns **AuthContext** + persists via DPAPI
  - `Connect-GenesysCloudPkce -ClientId -Region` — PKCE browser flow, returns **AuthContext**
  - `Get-GenesysAuthContext` — returns current AuthContext (or `$null`)
  - `Test-GenesysConnection`, `Get-ConnectionInfo`, `Clear-StoredToken`
- **AuthContext** object shape: `{ Token, ExpiresAt, Region, BaseUri, Headers }`

### `Genesys.Core` (consumes credentials)

- Primary runtime entrypoint: `Invoke-Dataset` (`modules/Genesys.Core/Public/Invoke-Dataset.ps1`)
- Auth model:
  - Accepts caller-supplied `-Headers` and `-BaseUri`
  - If `-Headers` are omitted, falls back to `GENESYS_BEARER_TOKEN` environment variable
- Core does **not** own OAuth login lifecycle; it consumes credentials provided by caller.

### `Genesys.Ops` (convenience layer, delegates to Auth)

- Location: `modules/Genesys.Ops/Genesys.Ops.psd1`
- `Connect-GenesysCloud` in Ops accepts `-AccessToken`, stores state for `Get-Genesys*` cmdlets.
- Ops does **not** duplicate OAuth code; full OAuth flows must go through `Genesys.Auth`.
- Root shim entrypoints are retained temporarily for compatibility, but canonical imports are `./modules/Genesys.Ops/Genesys.Ops.psd1`.

### Practical Rule

- Use `Genesys.Auth` to obtain credentials, then pass the resulting `AuthContext.Headers` and `AuthContext.BaseUri` directly to `Invoke-Dataset` — this is the recommended default for app wrappers.
- Use `Genesys.Ops` when you want operator-friendly session commands and aggregated operational functions.
- Use `scripts/Invoke-GenesysCoreBridge.ps1` for non-PowerShell wrappers.

## Authentication Flow Diagram

```text
OAuth token source (Genesys.Auth module)
  Connect-GenesysCloudApp / Connect-GenesysCloudPkce / Connect-GenesysCloud
    |
    v
  AuthContext { Token, ExpiresAt, Region, BaseUri, Headers }
    |
    +-> Option A: Core direct
    |      Invoke-Dataset -BaseUri $authCtx.BaseUri -Headers $authCtx.Headers
    |
    +-> Option B: Ops session
    |      Connect-GenesysCloud -AccessToken $authCtx.Token -Region $authCtx.Region
    |      Get-Genesys* / Invoke-Genesys*
    |
    `-> Option C: env var only
           $env:GENESYS_BEARER_TOKEN = $token
           Invoke-Dataset -BaseUri ... (no -Headers needed)

All options execute catalog-driven runtime in Genesys.Core (catalog/genesys.catalog.json).
```

## Standard Integration Contract (Recommended)

Use the bridge script: `scripts/Invoke-GenesysCoreBridge.ps1`

This provides one stable CLI contract for non-PowerShell wrappers (modules/Genesys.Core is loaded internally).

### Inputs

- `-Dataset` (required)
- `-Region` (defaults to `mypurecloud.com`; also accepts full API URL)
- `-OutputRoot` (defaults to `out`)
- `-CatalogPath` (optional; defaults to `catalog/genesys.catalog.json`)
- `-DatasetParameters` (optional hashtable)
- `-AccessToken` (optional; preferred to pass via env var)
- `-StrictCatalog`, `-NoRedact`, `-WhatIf`

### Auth resolution inside bridge

1. Use `-AccessToken` if provided.
2. Else use `GENESYS_BEARER_TOKEN` env var.
3. Else run unauthenticated (works for `-WhatIf`; live calls will fail upstream).

### Output

JSON to stdout:

- `ok`, `dataset`, `baseUri`, `whatIf`
- run paths (`runFolder`, `summaryPath`, `manifestPath`, `eventsPath`, `dataFolder`)
- parsed `summary` when available
- on error: `ok=false` + `message`, exit code `1`

## Security Guidance (Do This)

- Prefer secret managers or server-side env vars over passing tokens in command-line args.
- Never expose client secrets in browser code.
- Keep token acquisition on server/backend layers (use `Genesys.Auth`).
- Keep UI wrappers narrow: do not allow arbitrary PowerShell execution from user input.
- Continue relying on Core redaction for logged run events, but still treat outputs as sensitive.

## Integration Examples

## 1. PowerShell (Auth + Core Direct)

```powershell
Import-Module ./modules/Genesys.Auth/Genesys.Auth.psd1 -Force
Import-Module ./modules/Genesys.Core/Genesys.Core.psd1 -Force

$authCtx = Connect-GenesysCloudApp `
    -ClientId     $env:GENESYS_CLIENT_ID `
    -ClientSecret $env:GENESYS_CLIENT_SECRET `
    -Region       'usw2.pure.cloud'

$run = Invoke-Dataset -Dataset 'users' -OutputRoot './out' `
    -BaseUri $authCtx.BaseUri -Headers $authCtx.Headers
$run | Format-List
```

## 2. PowerShell (Bridge Contract)

```powershell
$env:GENESYS_BEARER_TOKEN = '<token>'

$resultJson = pwsh -NoProfile -File ./scripts/Invoke-GenesysCoreBridge.ps1 `
  -Dataset 'users' `
  -Region 'usw2.pure.cloud' `
  -OutputRoot './out'

$result = $resultJson | ConvertFrom-Json
if (-not $result.ok) { throw $result.message }
$result.summary
```

## 3. PowerShell (Ops Session Wrapper)

```powershell
Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1 -Force
Connect-GenesysCloud -AccessToken $env:GENESYS_BEARER_TOKEN -Region 'usw2.pure.cloud'

$status = Get-GenesysContactCentreStatus
$status | Format-List

Disconnect-GenesysCloud
```

## 4. HTML/JS UI + Node Backend

Browser UI should call your backend API, not Genesys OAuth directly.

### Frontend snippet

```html
<button id="runUsers">Run Users Dataset</button>
<script>
  document.getElementById('runUsers').addEventListener('click', async () => {
    const res = await fetch('/api/genesys/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ dataset: 'users', region: 'usw2.pure.cloud' })
    });
    const payload = await res.json();
    console.log(payload);
  });
</script>
```

### Node/Express backend snippet

```js
import express from "express";
import { spawn } from "node:child_process";

const app = express();
app.use(express.json());

app.post("/api/genesys/run", (req, res) => {
  const { dataset, region } = req.body;

  const ps = spawn("pwsh", [
    "-NoProfile",
    "-File",
    "./scripts/Invoke-GenesysCoreBridge.ps1",
    "-Dataset", dataset,
    "-Region", region || "mypurecloud.com",
    "-OutputRoot", "./out"
  ], {
    env: {
      ...process.env,
      GENESYS_BEARER_TOKEN: process.env.GENESYS_BEARER_TOKEN
    }
  });

  let stdout = "";
  let stderr = "";
  ps.stdout.on("data", d => stdout += d.toString());
  ps.stderr.on("data", d => stderr += d.toString());

  ps.on("close", (code) => {
    if (code !== 0) {
      return res.status(500).json({ ok: false, code, stderr, stdout });
    }
    try {
      return res.json(JSON.parse(stdout));
    } catch {
      return res.status(500).json({ ok: false, message: "Invalid JSON from bridge", stdout, stderr });
    }
  });
});
```

## 5. .NET (C# backend/service)

```csharp
using System.Diagnostics;
using System.Text.Json;

var psi = new ProcessStartInfo
{
    FileName = "pwsh",
    Arguments = "-NoProfile -File ./scripts/Invoke-GenesysCoreBridge.ps1 -Dataset users -Region usw2.pure.cloud -OutputRoot ./out",
    RedirectStandardOutput = true,
    RedirectStandardError = true,
    UseShellExecute = false,
};
psi.Environment["GENESYS_BEARER_TOKEN"] = Environment.GetEnvironmentVariable("GENESYS_BEARER_TOKEN") ?? "";

using var p = Process.Start(psi)!;
string stdout = await p.StandardOutput.ReadToEndAsync();
string stderr = await p.StandardError.ReadToEndAsync();
await p.WaitForExitAsync();

if (p.ExitCode != 0)
    throw new Exception($"Bridge failed: {stderr}\n{stdout}");

using var doc = JsonDocument.Parse(stdout);
bool ok = doc.RootElement.GetProperty("ok").GetBoolean();
if (!ok)
    throw new Exception(doc.RootElement.GetProperty("message").GetString());

string runFolder = doc.RootElement.GetProperty("runFolder").GetString()!;
Console.WriteLine($"Run completed: {runFolder}");
```

## 6. Go backend/service

```go
package main

import (
    "encoding/json"
    "fmt"
    "os"
    "os/exec"
)

type BridgeResult struct {
    Ok        bool   `json:"ok"`
    Message   string `json:"message"`
    RunFolder string `json:"runFolder"`
}

func main() {
    cmd := exec.Command("pwsh", "-NoProfile", "-File", "./scripts/Invoke-GenesysCoreBridge.ps1",
        "-Dataset", "users",
        "-Region", "usw2.pure.cloud",
        "-OutputRoot", "./out",
    )

    cmd.Env = append(os.Environ(),
        "GENESYS_BEARER_TOKEN="+os.Getenv("GENESYS_BEARER_TOKEN"),
    )

    out, err := cmd.CombinedOutput()
    if err != nil {
        panic(fmt.Sprintf("bridge failed: %v\n%s", err, string(out)))
    }

    var result BridgeResult
    if err := json.Unmarshal(out, &result); err != nil {
        panic(err)
    }

    if !result.Ok {
        panic(result.Message)
    }

    fmt.Println("Run completed:", result.RunFolder)
}
```

## Easy Path for Any Wrapper App

1. Import `Genesys.Auth` and call `Connect-GenesysCloudApp` (or `Connect-GenesysCloud` for pre-existing token).
2. Pass `$authCtx.BaseUri` and `$authCtx.Headers` to `Invoke-Dataset`.
   OR set `GENESYS_BEARER_TOKEN` env var and call `scripts/Invoke-GenesysCoreBridge.ps1`.
3. Parse JSON response / read `summary.json` / `data/*.jsonl` from returned run paths.

This keeps wrappers thin and preserves the catalog-driven execution model.

## Operational Extensions (Ops Layer)

If your UI needs contact-center operations views (not just datasets), call explicit `Genesys.Ops` cmdlets from a controlled backend endpoint:

- `Get-GenesysContactCentreStatus`
- `Invoke-GenesysDailyHealthReport`
- `Export-GenesysConfigurationSnapshot`

Do not expose arbitrary `Get-Genesys*` command text from end users.

## Related Files

- `modules/Genesys.Auth/Genesys.Auth.psm1`
- `modules/Genesys.Core/Public/Invoke-Dataset.ps1`
- `modules/Genesys.Core/Genesys.Core.psd1`
- `modules/Genesys.Ops/Genesys.Ops.psm1`
- `modules/Genesys.Ops/Genesys.Ops.psd1`
- `catalog/genesys.catalog.json`
- `scripts/Invoke-GenesysCoreBridge.ps1`
- `docs/ONBOARDING.md`
- `docs/REPO_SCHEMATIC.md`

