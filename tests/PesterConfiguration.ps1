$configuration = New-PesterConfiguration
$configuration.Run.Path = './tests'
$configuration.Output.Verbosity = 'Detailed'
$configuration
