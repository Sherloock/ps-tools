# Quick navigation bookmarks

function Go {
    <#
    .SYNOPSIS
        Jumps to bookmarked paths. Type 'go' without params to see the list.
    .PARAMETER Target
        The shortcut name.
    #>
    param($Target)

    # Load bookmarks from config, fallback to basic defaults
    $Bookmarks = if ($global:Config.Bookmarks) {
        $global:Config.Bookmarks
    } else {
        [ordered]@{
            "c" = "C:\"
            "d" = "D:\"
        }
    }

    # If no target or invalid target, show the "Menu"
    if (-not $Target -or -not $Bookmarks.Contains($Target)) {
        Write-Host "`n--- GO BOOKMARKS ---" -ForegroundColor Cyan
        $Bookmarks.GetEnumerator() | Sort-Object Name | ForEach-Object {
            Write-Host (" {0,-10}" -f $_.Name) -ForegroundColor Yellow -NoNewline
            Write-Host "-> $($_.Value)" -ForegroundColor Gray
        }
        Write-Host "--------------------`n"
        return
    }

    # Jump to the destination
    $Dest = $Bookmarks[$Target]
    if (Test-Path $Dest) {
        Set-Location $Dest
        Write-Host "Arrived at: $Dest" -ForegroundColor Green
    } else {
        Write-Host "Error: Path not found -> $Dest" -ForegroundColor Red
    }
}
