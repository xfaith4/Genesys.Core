### BEGIN: ModuleBootstrap
# Capture module root at load time. Functions dot-sourced from Public/ cannot
# rely on $PSScriptRoot at call time — it reflects the caller's scope, not the
# file that originally defined the function. Everything that needs a path back
# to the repo root should use $script:GcModuleRoot instead.
$script:GcModuleRoot = $PSScriptRoot   # = modules/Genesys.Core/

$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

# Load private subsystems in dependency order.
. (Join-Path $privatePath 'Catalog.ps1')
. (Join-Path $privatePath 'Redaction.ps1')
. (Join-Path $privatePath 'RunArtifacts.ps1')
. (Join-Path $privatePath 'Transport.ps1')
. (Join-Path $privatePath 'Paging.ps1')
. (Join-Path $privatePath 'Async.ps1')
. (Join-Path $privatePath 'Datasets.ps1')

$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
Get-ChildItem -Path $publicPath -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}
### END: ModuleBootstrap
