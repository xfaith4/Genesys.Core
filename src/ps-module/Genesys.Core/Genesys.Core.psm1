### BEGIN: ModuleBootstrap
$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
Get-ChildItem -Path $publicPath -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}
### END: ModuleBootstrap
