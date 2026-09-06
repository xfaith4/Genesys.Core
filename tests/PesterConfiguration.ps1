$configuration = New-PesterConfiguration
$configuration.Run.Path = './tests'
$configuration.Output.Verbosity = 'Detailed'

# Without this, Invoke-Pester reports failures but still exits 0, so the CI step passes while
# tests are red - which is how 14 failing tests went unnoticed. Exit non-zero on failure.
$configuration.Run.Exit = $true

$configuration
