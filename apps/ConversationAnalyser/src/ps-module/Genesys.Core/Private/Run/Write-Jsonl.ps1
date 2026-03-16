function Write-Jsonl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    $line = $InputObject | ConvertTo-Json -Depth 100 -Compress
    Add-Content -Path $Path -Value $line -Encoding utf8
}
