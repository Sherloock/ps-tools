# User-specific configuration
# Copy this file to config.ps1 and customize your paths

$global:Config = @{
    # Paths for the Movies function (media library statistics)
    MediaPaths = @(
        "D:\movies",
        "D:\shows"
    )

    # Bookmarks for the Go function (quick navigation)
    Bookmarks = [ordered]@{
        "c"       = "C:\"
        "d"       = "D:\"
        "docs"    = "$env:USERPROFILE\Documents"
        "proj"    = "D:\Projects"
    }
}
