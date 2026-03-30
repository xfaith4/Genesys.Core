Import-Module .\modules\Genesys.Ops\Genesys.Ops.psd1 -Force
Connect-GenesysCloud -AccessToken $env:GENESYS_BEARER_TOKEN -Region 'usw2.pure.cloud'
Get-GenesysQueue | Select-Object -First 5 name, memberCount
