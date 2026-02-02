# File Operations Utilities

function Flatten {
    <#
    .SYNOPSIS
    Flatten directory structure - move/copy all files from subfolders to one folder.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string]$RootFolder,

        [Parameter(Position = 1)]
        [string]$OutputFolder,

        [Parameter()]
        [switch]$Move,

        [Parameter()]
        [switch]$Copy,

        [Parameter()]
        [switch]$Force
    )

    # Prompt for RootFolder if not provided
    if (-not $RootFolder) {
        $RootFolder = Read-Host "Enter the path of the folder to flatten"
    }

    # Verify the root folder exists
    if (-not (Test-Path -LiteralPath $RootFolder -PathType Container)) {
        Write-Host "Error: The specified folder '$RootFolder' does not exist." -ForegroundColor Red
        return
    }

    $RootFolder = (Get-Item -LiteralPath $RootFolder).FullName

    # Prompt for OutputFolder if not provided
    if (-not $OutputFolder) {
        $OutputFolder = Read-Host "Enter output folder (leave empty to flatten in place)"
        if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
            $OutputFolder = $RootFolder
        }
    }

    # If the output folder doesn't exist, ask whether to create it
    if (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
        if ($Force) {
            New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
            Write-Host "Created output folder '$OutputFolder'." -ForegroundColor Green
        }
        else {
            $createOutput = Read-Host "Output folder '$OutputFolder' does not exist. Create it? (Y/N)"
            if ($createOutput -match '^[Yy]') {
                try {
                    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
                    Write-Host "Created output folder '$OutputFolder'." -ForegroundColor Green
                }
                catch {
                    Write-Host "Error: Failed to create output folder '$OutputFolder'." -ForegroundColor Red
                    return
                }
            }
            else {
                Write-Host "Aborting." -ForegroundColor Yellow
                return
            }
        }
    }

    $OutputFolder = (Get-Item -LiteralPath $OutputFolder).FullName

    # Determine operation mode
    $DeleteOriginal = $false
    if ($Move) {
        $DeleteOriginal = $true
    }
    elseif ($Copy) {
        $DeleteOriginal = $false
    }
    else {
        $response = Read-Host "Operation mode: 'move' (delete originals) or 'copy' (keep originals)?"
        if ($response -match '^m') {
            $DeleteOriginal = $true
        }
    }

    # Count files to process
    if ($RootFolder -eq $OutputFolder) {
        $files = Get-ChildItem -LiteralPath $RootFolder -Recurse -File | Where-Object { $_.DirectoryName -ne $RootFolder }
    }
    else {
        $files = Get-ChildItem -LiteralPath $RootFolder -Recurse -File
    }

    $fileCount = ($files | Measure-Object).Count

    if ($fileCount -eq 0) {
        Write-Host "No files found in subdirectories to flatten." -ForegroundColor Yellow
        return
    }

    # Display summary and confirm
    Write-Host ""
    Write-Host "=== Flatten Directory ===" -ForegroundColor Cyan
    Write-Host "  Source : $RootFolder"
    Write-Host "  Output : $OutputFolder"
    Write-Host "  Files  : $fileCount"
    Write-Host "  Mode   : $(if ($DeleteOriginal) { 'MOVE (delete originals)' } else { 'COPY (keep originals)' })"
    Write-Host "=========================" -ForegroundColor Cyan

    if (-not $Force) {
        $proceed = Read-Host "Proceed? (Y/N)"
        if ($proceed -notmatch '^[Yy]') {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Process files
    $processed = 0
    $errors = 0

    foreach ($file in $files) {
        $UniqueFileName = Get-FlattenUniqueFileName -TargetFolder $OutputFolder -FileName $file.Name
        $DestinationPath = Join-Path -Path $OutputFolder -ChildPath $UniqueFileName

        try {
            if ($DeleteOriginal) {
                Move-Item -LiteralPath $file.FullName -Destination $DestinationPath -Force
            }
            else {
                Copy-Item -LiteralPath $file.FullName -Destination $DestinationPath -Force
            }
            $processed++
        }
        catch {
            Write-Host "Error: $($file.Name) - $_" -ForegroundColor Red
            $errors++
        }
    }

    # Cleanup empty directories (only if moving)
    $removedDirs = 0
    if ($DeleteOriginal) {
        Write-Host "Cleaning up empty directories..." -ForegroundColor Cyan

        $directories = Get-ChildItem -LiteralPath $RootFolder -Recurse -Directory | Sort-Object -Property FullName -Descending

        foreach ($dir in $directories) {
            # Skip output folder if it's inside root
            if ($dir.FullName -eq $OutputFolder -or $OutputFolder.StartsWith($dir.FullName + [System.IO.Path]::DirectorySeparatorChar)) {
                continue
            }
            try {
                $items = Get-ChildItem -LiteralPath $dir.FullName -Recurse -Force | Where-Object { -not $_.PSIsContainer }
                if ($items.Count -eq 0) {
                    Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    $removedDirs++
                }
            }
            catch {
                # Ignore directory removal errors
            }
        }
    }

    # Summary
    Write-Host ""
    $operation = if ($DeleteOriginal) { "moved" } else { "copied" }
    Write-Host "Flatten complete: $processed files $operation" -ForegroundColor Green
    if ($removedDirs -gt 0) {
        Write-Host "Removed $removedDirs empty directories" -ForegroundColor Green
    }
    if ($errors -gt 0) {
        Write-Host "$errors errors occurred" -ForegroundColor Red
    }
}

# Alias for quick access
Set-Alias -Name flat -Value Flatten -Scope Global
