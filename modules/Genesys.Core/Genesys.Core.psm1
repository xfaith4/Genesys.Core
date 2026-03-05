### BEGIN: ModuleBootstrap
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
Get-ChildItem -Path $publicPath -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}
### END: ModuleBootstrap
