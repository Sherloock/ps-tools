# LOADER: Paste this into Win+R -> notepad $PROFILE
$global:ToolKitDir = $PSScriptRoot

# Load user config if exists
$configPath = Join-Path $ToolKitDir "config.ps1"
if (Test-Path -LiteralPath $configPath) {
    . $configPath
}

# Load Helpers.ps1 first (required by other modules)
$helpersPath = Join-Path $ToolKitDir "core\Helpers.ps1"
if (Test-Path -LiteralPath $helpersPath) {
    . $helpersPath
}

# Load remaining .ps1 files (exclude loader, Helpers, and config files)
Get-ChildItem -Path $ToolKitDir -Filter "*.ps1" -Recurse | Where-Object {
    $_.Name -ne "loader.ps1" -and $_.Name -ne "Helpers.ps1" -and $_.Name -notlike "config*.ps1"
} | ForEach-Object {
    . $_.FullName
}

Write-Host "Balint's Toolkit Loaded ($((Get-ChildItem $ToolKitDir -Filter *.ps1 -Recurse).Count) modules)" -ForegroundColor Green

# Hot-reload function for development
function global:Reload {
    . "$ToolKitDir\loader.ps1"
}

# Show dashboard on load
??
