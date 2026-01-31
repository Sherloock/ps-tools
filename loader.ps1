# LOADER: Paste this into Win+R -> notepad $PROFILE
$ToolKitDir = "f:\Fejlesztes\projects\my\ps-tools"

# Automatically load all .ps1 files from subdirectories
Get-ChildItem -Path $ToolKitDir -Filter "*.ps1" -Recurse | ForEach-Object {
    . $_.FullName
}

Write-Host "Bálint's Toolkit Loaded ($((Get-ChildItem $ToolKitDir -Filter *.ps1 -Recurse).Count) modules)" -ForegroundColor Green
