# Genesys Interrogator

A lightweight WPF validator for `Genesys.Core`. One window, one list of every dataset in the catalog, one JSON parameter editor, one results grid. The catalog drives the dataset list; each endpoint's declared defaults drive the parameter form; the response shape drives the grid columns.

The app has a single purpose: **prove that each dataset in the catalog can be queried end-to-end and show the response in a logical way.** It is not an analytics tool, not a case store, not a reporting app.

## Run

From the repo root:

```powershell
Set-Location .\apps\GenesysInterrogator
.\App.ps1
```

Requires Windows PowerShell 5.1 or PowerShell 7.x (on Windows) — WPF only.

## Workflow

1. Paste a Genesys Cloud bearer token (or set `GENESYS_BEARER_TOKEN` before launching), pick a region, click **Connect**.
2. Use the filter to find a dataset, or scroll the left-hand list. Every dataset defined in `catalog/genesys.catalog.json` is shown, grouped by the endpoint's `group:` note.
3. The **Dataset parameters** editor is pre-populated from the endpoint's `defaultQueryParams` and any `defaultBody:` note. Edit freely — it is passed verbatim as the `-DatasetParameters` hashtable to `Invoke-Dataset`.
4. The app auto-selects the first dataset on launch so the parameter editor is ready immediately. If `GENESYS_BEARER_TOKEN` is set, the header tells you a bearer token is already available before you click **Bearer**.
5. Click **Run dataset**. The dataset run starts in a background runspace, the footer status updates as the run folder appears, and the **Live events** tab tails `events.jsonl` while the run is in progress. Results appear in three tabs:
   - **Rows** — auto-generated DataGrid columns from the first-level properties of each response row. Nested objects/arrays are rendered as compact JSON so every row is visible.
   - **Summary & manifest** — contents of `summary.json` and `manifest.json` from the run folder.
   - **Raw JSON (first rows)** — compact JSONL preview of the first 50 records, with a pointer to the full JSONL file.

The full run output (manifest, summary, events, data) is written under `apps/GenesysInterrogator/out/<dataset-key>/<runId>/` by `Genesys.Core` itself. Click **Open run folder** to inspect it. If you started the wrong dataset or parameters, click **Cancel run** to stop the active run.

## Design notes

- `App.CoreAdapter.psm1` is the **only** module that imports `Genesys.Core` and `Genesys.Auth`, in line with every other app in the repo.
- The UI is deliberately minimal: four panels, one DataGrid, no XAML resource dictionaries, no styles, no MVVM. Controls are found by name and wired with `Add_Click` / `Add_SelectionChanged`.
- `Invoke-Dataset` runs in a background runspace. The UI stays responsive, shows live event progress, and can cancel the active run. Keep runs narrow anyway: this is still a validator, not a bulk extraction tool.
- Nothing is cached. Each run is a fresh Core invocation and a fresh read from disk.

## Settings

`App.Settings.psd1` holds relative paths to Core, Auth, catalog, and schema, plus the region list and preview row cap. Adjust the cap (`Ui.PreviewRows`, default 500) if you need to see more or fewer rows in the grid.
