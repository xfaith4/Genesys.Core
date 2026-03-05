### BEGIN: LegacyShim
Write-Warning '[Genesys.Core] src/ps-module path is deprecated. Use ./modules/Genesys.Core/Genesys.Core.psd1'
$modulePath = Join-Path $PSScriptRoot '../../../modules/Genesys.Core/Genesys.Core.psd1'
if (-not (Test-Path $modulePath)) {
    throw "Genesys.Core module not found at '$modulePath'."
}
Import-Module $modulePath -Global -Force -ErrorAction Stop
### END: LegacyShim
