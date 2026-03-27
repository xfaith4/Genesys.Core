### BEGIN: ModuleBootstrap
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
