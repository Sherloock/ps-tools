# Core helper functions used by other modules
# These are internal utilities - excluded from '??' dashboard

# ============================================================================
# FILE HELPERS
# ============================================================================

function Get-FlattenUniqueFileName {
    <#
    .SYNOPSIS
        Generates a unique filename by appending counter if file exists.
    #>
    param(
        [string]$TargetFolder,
        [string]$FileName
    )

    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $Extension = [System.IO.Path]::GetExtension($FileName)
    $NewFileName = $FileName
    $Counter = 1

    while (Test-Path -LiteralPath (Join-Path -Path $TargetFolder -ChildPath $NewFileName)) {
        $NewFileName = "$BaseName-$Counter$Extension"
        $Counter++
    }

    return $NewFileName
}

# ============================================================================
# SIZE HELPERS
# ============================================================================

function Get-ReadableSize {
    <#
    .SYNOPSIS
        Converts bytes into a human-readable format (GB, MB, KB).
    #>
    param([long]$Bytes)

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1GB) { return ($Bytes / 1GB).ToString("F2", $inv) + " GB" }
    if ($Bytes -ge 1MB) { return ($Bytes / 1MB).ToString("F2", $inv) + " MB" }
    if ($Bytes -ge 1KB) { return ($Bytes / 1KB).ToString("F2", $inv) + " KB" }
    return "$Bytes B"
}

# ============================================================================
# TIMER HELPERS
# ============================================================================

# Timer data file path (shared across timer functions)
$script:TimerDataFile = Join-Path $env:TEMP "ps-timers.json"
# Cache for watch mode optimization
$script:TimerDataCache = $null
$script:TimerDataCacheTime = [DateTime]::MinValue

function ConvertTo-Seconds {
    <#
    .SYNOPSIS
        Converts time string (1h20m, 90s, etc.) to seconds.
    #>
    param([string]$Time)

    $seconds = 0
    if ($Time -match '(\d+)h') { $seconds += [int]$matches[1] * 3600 }
    if ($Time -match '(\d+)m') { $seconds += [int]$matches[1] * 60 }
    if ($Time -match '(\d+)s') { $seconds += [int]$matches[1] }
    if ($Time -match '^\d+$') { $seconds = [int]$Time }

    return $seconds
}

function New-TimerId {
    <#
    .SYNOPSIS
        Generates a sequential timer ID (1, 2, 3, ...).
    #>
    $timers = @(Get-TimerData)
    if ($timers.Count -eq 0) {
        return "1"
    }

    # Find highest numeric ID
    $maxId = 0
    foreach ($t in $timers) {
        if ($t.Id -match '^\d+$') {
            $num = [int]$t.Id
            if ($num -gt $maxId) { $maxId = $num }
        }
    }

    return [string]($maxId + 1)
}

function Get-TimerData {
    <#
    .SYNOPSIS
        Loads timer metadata from JSON file.
    #>
    if (Test-Path -LiteralPath $script:TimerDataFile) {
        try {
            $content = Get-Content -LiteralPath $script:TimerDataFile -Raw -ErrorAction Stop
            if ($content) {
                $data = $content | ConvertFrom-Json
                # Handle nested value structures from ConvertTo-Json
                $result = @()
                foreach ($item in $data) {
                    if ($item.PSObject.Properties.Name -contains 'Id') {
                        $result += $item
                    }
                }
                return $result
            }
        }
        catch {
            # File corrupted or empty, return empty array
        }
    }
    return @()
}

function Get-TimerDataIfChanged {
    <#
    .SYNOPSIS
        Returns timer data only if the JSON file was modified since last read.
    .DESCRIPTION
        Optimized for watch mode - avoids unnecessary file reads by checking
        the file's LastWriteTime against a cached timestamp.
    .PARAMETER Force
        If set, always reads the file regardless of modification time.
    .RETURNS
        Hashtable with Keys: Data (array), Changed (bool)
    #>
    param([switch]$Force)

    if (-not (Test-Path -LiteralPath $script:TimerDataFile)) {
        $script:TimerDataCache = @()
        $script:TimerDataCacheTime = [DateTime]::MinValue
        return @{ Data = @(); Changed = $true }
    }

    $fileInfo = Get-Item -LiteralPath $script:TimerDataFile -ErrorAction SilentlyContinue
    if (-not $fileInfo) {
        return @{ Data = @(); Changed = $false }
    }

    $lastWrite = $fileInfo.LastWriteTime

    # Check if file was modified since last cache
    if (-not $Force -and $script:TimerDataCache -ne $null -and $lastWrite -le $script:TimerDataCacheTime) {
        return @{ Data = $script:TimerDataCache; Changed = $false }
    }

    # File changed or no cache - read fresh data
    $script:TimerDataCache = @(Get-TimerData)
    $script:TimerDataCacheTime = $lastWrite

    return @{ Data = $script:TimerDataCache; Changed = $true }
}

function Save-TimerData {
    <#
    .SYNOPSIS
        Saves timer metadata to JSON file.
    #>
    param([array]$Timers)

    if ($Timers.Count -eq 0) {
        if (Test-Path -LiteralPath $script:TimerDataFile) {
            Remove-Item -LiteralPath $script:TimerDataFile -Force
        }
        return
    }

    # Flatten and clean the array before saving
    $clean = @()
    foreach ($t in $Timers) {
        if ($t.PSObject.Properties.Name -contains 'Id') {
            $obj = [PSCustomObject]@{
                Id               = $t.Id
                Duration         = $t.Duration
                Seconds          = [int]$t.Seconds
                Message          = $t.Message
                StartTime        = $t.StartTime
                EndTime          = $t.EndTime
                RepeatTotal      = [int]$t.RepeatTotal
                RepeatRemaining  = [int]$t.RepeatRemaining
                CurrentRun       = [int]$t.CurrentRun
                State            = $t.State
                RemainingSeconds = if ($t.RemainingSeconds) { [int]$t.RemainingSeconds } else { $null }
                IsSequence       = if ($t.IsSequence) { $true } else { $false }
            }

            # Add sequence-specific fields if present
            if ($t.IsSequence) {
                $obj | Add-Member -NotePropertyName 'SequencePattern' -NotePropertyValue $t.SequencePattern
                $obj | Add-Member -NotePropertyName 'Phases' -NotePropertyValue $t.Phases
                $obj | Add-Member -NotePropertyName 'CurrentPhase' -NotePropertyValue ([int]$t.CurrentPhase)
                $obj | Add-Member -NotePropertyName 'TotalPhases' -NotePropertyValue ([int]$t.TotalPhases)
                $obj | Add-Member -NotePropertyName 'PhaseLabel' -NotePropertyValue $t.PhaseLabel
                $obj | Add-Member -NotePropertyName 'TotalSeconds' -NotePropertyValue ([int]$t.TotalSeconds)
            }

            $clean += $obj
        }
    }

    ConvertTo-Json -InputObject $clean -Depth 10 | Set-Content -LiteralPath $script:TimerDataFile -Force
}

function Format-Duration {
    <#
    .SYNOPSIS
        Formats seconds into readable duration (1h 20m 30s).
    #>
    param([int]$Seconds)

    $h = [math]::Floor($Seconds / 3600)
    $m = [math]::Floor(($Seconds % 3600) / 60)
    $s = $Seconds % 60

    $parts = @()
    if ($h -gt 0) { $parts += "${h}h" }
    if ($m -gt 0) { $parts += "${m}m" }
    if ($s -gt 0 -or $parts.Count -eq 0) { $parts += "${s}s" }

    return $parts -join ' '
}

function Sync-TimerData {
    <#
    .SYNOPSIS
        Syncs timer data with actual scheduled task states.
    .DESCRIPTION
        Checks if scheduled tasks exist for running timers.
        Only marks as Lost if task is missing AND end time has passed.
    #>
    $timers = @(Get-TimerData)
    $changed = $false

    foreach ($timer in $timers) {
        if ($timer.State -ne 'Running') { continue }

        $taskName = "PSTimer_$($timer.Id)"
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        if ($task) {
            # Task exists - timer is still active, check if it ran
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
            if ($taskInfo -and $taskInfo.LastRunTime -and $taskInfo.LastRunTime -gt [DateTime]::MinValue) {
                # Task has run - the script should have updated the JSON
                # Re-read to get any changes made by the scheduled task
                $freshTimers = @(Get-TimerData)
                $freshTimer = $freshTimers | Where-Object { $_.Id -eq $timer.Id }
                if ($freshTimer -and $freshTimer.State -ne $timer.State) {
                    return $freshTimers  # Return updated data
                }
            }
            # Task exists and hasn't run yet - timer is valid
        }
        else {
            # Task not found - check if timer should have ended
            try {
                $endTime = [DateTime]::Parse($timer.EndTime)
                $remaining = [int]($endTime - (Get-Date)).TotalSeconds

                if ($remaining -le 0) {
                    # Timer expired without task - mark as lost
                    $timer.State = 'Lost'
                    # Save 0 remaining (cycle expired)
                    $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue 0 -Force
                    $changed = $true
                }
                # Otherwise, task might still be scheduling - give it a moment
                # If still no task after end time, mark as lost with remaining time
            }
            catch {
                # Invalid EndTime format - mark as lost
                $timer.State = 'Lost'
                $timer | Add-Member -NotePropertyName 'RemainingSeconds' -NotePropertyValue $timer.Seconds -Force
                $changed = $true
            }
        }
    }

    if ($changed) {
        Save-TimerData -Timers $timers
    }

    return $timers
}

function Show-MenuPicker {
    <#
    .SYNOPSIS
        Shows an interactive menu picker with arrow key navigation.
    .PARAMETER Title
        Title to display above the menu.
    .PARAMETER Options
        Array of options. Each option should have 'Id', 'Label', and optionally 'Color' and 'Description'.
    .PARAMETER AllowCancel
        If true, Escape key cancels (returns $null).
    .RETURNS
        The selected option's Id, or $null if cancelled.
    .EXAMPLE
        $options = @(
            @{ Id = '1'; Label = 'First option' },
            @{ Id = '2'; Label = 'Second option'; Color = 'Yellow' }
        )
        $selected = Show-MenuPicker -Title 'Pick one' -Options $options
    #>
    param(
        [string]$Title,
        [array]$Options,
        [switch]$AllowCancel
    )

    if ($Options.Count -eq 0) {
        return $null
    }

    $selectedIndex = 0
    $optionCount = $Options.Count

    # Selection indicator
    $selector = [char]0x25B6  # ▶

    # ANSI color codes for flicker-free rendering
    $c = Get-AnsiColors

    # Map color names to ANSI codes
    $colorMap = @{
        'White'      = $c.White
        'Yellow'     = $c.Yellow
        'Green'      = $c.Green
        'Red'        = $c.Red
        'Cyan'       = $c.Cyan
        'Magenta'    = $c.Magenta
        'Gray'       = $c.Gray
        'DarkGray'   = $c.Dim
        'DarkYellow' = $c.Yellow
    }

    [Console]::CursorVisible = $false

    try {
        while ($true) {
            # Build entire output in StringBuilder to avoid flicker
            $sb = [System.Text.StringBuilder]::new()

            [void]$sb.AppendLine("")
            if ($Title) {
                [void]$sb.AppendLine("$($c.Cyan)  $Title$($c.Reset)")
                [void]$sb.AppendLine("$($c.DarkCyan)  $('-' * $Title.Length)$($c.Reset)")
            }
            [void]$sb.AppendLine("")

            # Draw options
            for ($i = 0; $i -lt $optionCount; $i++) {
                $opt = $Options[$i]
                $isSelected = ($i -eq $selectedIndex)
                $baseColorCode = if ($opt.Color -and $colorMap[$opt.Color]) { $colorMap[$opt.Color] } else { $c.White }

                if ($isSelected) {
                    # Selected: cyan selector with inverted colors (cyan bg, black text)
                    [void]$sb.AppendLine("$($c.Cyan)  $selector $($c.Reset)$($c.InvertCyan)$($opt.Label)$($c.Reset)")
                    # Show description for selected item (if present)
                    if ($opt.Description) {
                        [void]$sb.AppendLine("      $($c.Dim)$($opt.Description)$($c.Reset)")
                    }
                }
                else {
                    [void]$sb.AppendLine("    ${baseColorCode}$($opt.Label)$($c.Reset)")
                }
            }

            [void]$sb.AppendLine("")
            $cancelText = if ($AllowCancel) { ", Esc=cancel" } else { "" }
            [void]$sb.AppendLine("$($c.Yellow)  [Up/Down]$($c.Dim) navigate  $($c.Green)[Enter]$($c.Dim) select$cancelText$($c.Reset)")

            # Clear and write atomically
            Clear-Host
            [Console]::Write($sb.ToString())

            # Wait for keypress
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    if ($selectedIndex -gt 0) {
                        $selectedIndex--
                    }
                    else {
                        $selectedIndex = $optionCount - 1  # Wrap to bottom
                    }
                }
                'DownArrow' {
                    if ($selectedIndex -lt $optionCount - 1) {
                        $selectedIndex++
                    }
                    else {
                        $selectedIndex = 0  # Wrap to top
                    }
                }
                'Enter' {
                    Clear-Host
                    return $Options[$selectedIndex].Id
                }
                'Escape' {
                    if ($AllowCancel) {
                        Clear-Host
                        return $null
                    }
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

function Start-TimerJob {
    <#
    .SYNOPSIS
        Internal function to start a timer using Windows Scheduled Task.
    .DESCRIPTION
        Uses Scheduled Tasks instead of PowerShell jobs so timers survive terminal closure.
    #>
    param([PSCustomObject]$Timer)

    $taskName = "PSTimer_$($Timer.Id)"
    $dataFile = Join-Path $env:TEMP "ps-timers.json"

    # Calculate trigger time
    $triggerTime = (Get-Date).AddSeconds($Timer.Seconds)

    # Build the notification script that runs when timer fires
    # This script is self-contained and runs independently of the terminal
    $script = @"
`$timerId = '$($Timer.Id)'
`$message = '$($Timer.Message -replace "'", "''")'
`$duration = '$($Timer.Duration)'
`$repeatTotal = $($Timer.RepeatTotal)
`$currentRun = $($Timer.CurrentRun)
`$timerSeconds = $($Timer.Seconds)
`$dataFile = '$dataFile'
`$logFile = "`$env:TEMP\PSTimer_`$timerId.log"

try {
    # Beep notification
    [console]::beep(440, 500)

    # Update timer data FIRST (before popup, so tl shows correct state)
    if (Test-Path -LiteralPath `$dataFile) {
        `$jsonContent = Get-Content -LiteralPath `$dataFile -Raw -ErrorAction Stop
        `$parsed = `$jsonContent | ConvertFrom-Json

        # Ensure we have an array
        `$timers = @()
        if (`$parsed -is [array]) {
            `$timers = @(`$parsed)
        } else {
            `$timers = @(`$parsed)
        }

        # Find timer by ID (compare as strings)
        `$timerIndex = -1
        for (`$i = 0; `$i -lt `$timers.Count; `$i++) {
            if ([string]`$timers[`$i].Id -eq [string]`$timerId) {
                `$timerIndex = `$i
                break
            }
        }

        if (`$timerIndex -ge 0) {
            `$timer = `$timers[`$timerIndex]
            `$repeatRemaining = [int]`$timer.RepeatRemaining

            if (`$repeatRemaining -gt 0) {
                # More repeats to go - schedule next run
                `$newRepeatRemaining = `$repeatRemaining - 1
                `$newCurrentRun = [int]`$timer.RepeatTotal - `$newRepeatRemaining
                `$newStart = (Get-Date).ToString('o')
                `$newEnd = (Get-Date).AddSeconds(`$timerSeconds).ToString('o')

                # Create updated timer object
                `$updatedTimer = [PSCustomObject]@{
                    Id              = `$timer.Id
                    Duration        = `$timer.Duration
                    Seconds         = [int]`$timer.Seconds
                    Message         = `$timer.Message
                    StartTime       = `$newStart
                    EndTime         = `$newEnd
                    RepeatTotal     = [int]`$timer.RepeatTotal
                    RepeatRemaining = `$newRepeatRemaining
                    CurrentRun      = `$newCurrentRun
                    State           = 'Running'
                    RemainingSeconds = `$null
                }
                `$timers[`$timerIndex] = `$updatedTimer

                # Save BEFORE scheduling next task
                ConvertTo-Json -InputObject `$timers -Depth 10 | Set-Content -LiteralPath `$dataFile -Force

                # Schedule next run
                `$nextTrigger = (Get-Date).AddSeconds(`$timerSeconds)
                `$scriptPath = "`$env:TEMP\PSTimer_`$timerId.ps1"
                `$nextAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File ```"`$scriptPath```""
                `$nextTriggerObj = New-ScheduledTaskTrigger -Once -At `$nextTrigger
                `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

                Unregister-ScheduledTask -TaskName "PSTimer_`$timerId" -Confirm:`$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName "PSTimer_`$timerId" -Action `$nextAction -Trigger `$nextTriggerObj -Settings `$settings -Force | Out-Null

                `$currentRun = `$newCurrentRun
            } else {
                # All done - create completed timer
                `$updatedTimer = [PSCustomObject]@{
                    Id              = `$timer.Id
                    Duration        = `$timer.Duration
                    Seconds         = [int]`$timer.Seconds
                    Message         = `$timer.Message
                    StartTime       = `$timer.StartTime
                    EndTime         = `$timer.EndTime
                    RepeatTotal     = [int]`$timer.RepeatTotal
                    RepeatRemaining = 0
                    CurrentRun      = [int]`$timer.RepeatTotal
                    State           = 'Completed'
                    RemainingSeconds = `$null
                }
                `$timers[`$timerIndex] = `$updatedTimer

                ConvertTo-Json -InputObject `$timers -Depth 10 | Set-Content -LiteralPath `$dataFile -Force

                Unregister-ScheduledTask -TaskName "PSTimer_`$timerId" -Confirm:`$false -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath "`$env:TEMP\PSTimer_`$timerId.ps1" -Force -ErrorAction SilentlyContinue
            }
        }
    }
} catch {
    # Log error for debugging
    "`$(Get-Date -Format 'o') ERROR: `$(`$_.Exception.Message)" | Add-Content -LiteralPath `$logFile -Force
}

# Show popup (after state update, so it can block without affecting tl display)
`$endStr = (Get-Date).ToString('HH:mm:ss')
`$body = @("Timer #`$timerId completed!", "", "Duration: `$duration", "Finished: `$endStr")
if (`$repeatTotal -gt 1) { `$body += "Run:      `$currentRun of `$repeatTotal" }
`$popup = New-Object -ComObject WScript.Shell
`$popup.Popup((`$body -join [char]10), 0, `$message, 64) | Out-Null
"@

    # Write script to temp file (scheduled tasks work better with script files)
    $scriptPath = Join-Path $env:TEMP "PSTimer_$($Timer.Id).ps1"
    $script | Set-Content -LiteralPath $scriptPath -Force -Encoding UTF8

    # Remove any existing task with same name
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    # Create scheduled task
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At $triggerTime
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
}

function Stop-TimerTask {
    <#
    .SYNOPSIS
        Stops and unregisters a timer's scheduled task.
    #>
    param([int]$TimerId)

    $taskName = "PSTimer_$TimerId"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    # Also clean up the script file
    $scriptPath = Join-Path $env:TEMP "PSTimer_$TimerId.ps1"
    Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# DUPLICATE DETECTION HELPERS
# ============================================================================

function Get-LinkType {
    <#
    .SYNOPSIS
        Determines the relationship between two files.
    .DESCRIPTION
        Returns whether two files are duplicates, hard links, or symlinks.
    .PARAMETER Path1
        First file path.
    .PARAMETER Path2
        Second file path.
    .RETURNS
        String: "DUPE", "HARDLINK", or "SYMLINK"
    #>
    param(
        [string]$Path1,
        [string]$Path2
    )

    try {
        $item1 = Get-Item -LiteralPath $Path1 -ErrorAction Stop
        $item2 = Get-Item -LiteralPath $Path2 -ErrorAction Stop

        # Check if either is a symlink/junction
        $isSymlink1 = ($item1.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
        $isSymlink2 = ($item2.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint

        if ($isSymlink1 -or $isSymlink2) {
            return "SYMLINK"
        }

        # Check if hard links using fsutil
        $fsutilOutput = & cmd /c "fsutil hardlink list `"$Path1`" 2>nul"
        if ($LASTEXITCODE -eq 0 -and $fsutilOutput) {
            # Normalize Path2 for comparison
            $normalizedPath2 = (Resolve-Path -LiteralPath $Path2).Path.ToLower().TrimEnd('\')
            
            # Check each line from fsutil output
            foreach ($line in $fsutilOutput) {
                $trimmedLine = $line.Trim()
                if ($trimmedLine) {
                    # fsutil returns paths relative to drive root (e.g., \downloads\file.mkv)
                    # Convert to full path
                    $drive = Split-Path -Qualifier $Path1
                    $fullPath = Join-Path $drive $trimmedLine
                    
                    try {
                        $resolvedPath = (Resolve-Path -LiteralPath $fullPath -ErrorAction SilentlyContinue).Path.ToLower().TrimEnd('\')
                        if ($resolvedPath -eq $normalizedPath2) {
                            return "HARDLINK"
                        }
                    } catch {}
                }
            }
        }

        # Default: actual duplicate (different files with same content)
        return "DUPE"
    }
    catch {
        # If we can't determine, assume it's a duplicate
        return "DUPE"
    }
}

function Get-FileHashPartial {
    <#
    .SYNOPSIS
        Computes hash of first and last N bytes of a file for quick comparison.
    .PARAMETER FilePath
        Path to the file.
    .PARAMETER BytesToRead
        Number of bytes to read from start and end (default: 64KB).
    #>
    param(
        [string]$FilePath,
        [long]$BytesToRead = 64KB
    )

    try {
        $fileSize = (Get-Item -LiteralPath $FilePath).Length
        if ($fileSize -eq 0) { return $null }

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::OpenRead($FilePath)

        try {
            # Read first N bytes - cast BytesToRead to long to handle large files
            $firstBytes = New-Object byte[] ([Math]::Min([long]$BytesToRead, $fileSize))
            $stream.Read($firstBytes, 0, $firstBytes.Length) | Out-Null
            $sha256.TransformBlock($firstBytes, 0, $firstBytes.Length, $firstBytes, 0) | Out-Null

            # Read last N bytes if file is larger than BytesToRead
            if ($fileSize -gt $BytesToRead) {
                $stream.Seek([Math]::Max([long]0, $fileSize - $BytesToRead), [System.IO.SeekOrigin]::Begin) | Out-Null
                $lastBytes = New-Object byte[] ([Math]::Min([long]$BytesToRead, $fileSize - $BytesToRead))
                $stream.Read($lastBytes, 0, $lastBytes.Length) | Out-Null
                $sha256.TransformFinalBlock($lastBytes, 0, $lastBytes.Length) | Out-Null
            } else {
                $sha256.TransformFinalBlock(@(), 0, 0) | Out-Null
            }

            return [BitConverter]::ToString($sha256.Hash).Replace("-", "").ToLower()
        }
        finally {
            $stream.Close()
            $sha256.Dispose()
        }
    }
    catch {
        return $null
    }
}

function Get-FilesFromPath {
    <#
    .SYNOPSIS
        Gets all files from a path recursively with size filtering.
    .PARAMETER Path
        Root path to scan.
    .PARAMETER MinSizeBytes
        Minimum file size in bytes (default: 100MB).
    #>
    param(
        [string]$Path,
        [long]$MinSizeBytes = 100MB
    )

    if (-not (Test-Path $Path)) {
        return @()
    }

    return Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge $MinSizeBytes } |
        Select-Object FullName, Name, Length, @{N="RelativePath"; E={ $_.FullName.Substring($Path.Length).TrimStart("\") }}
}

function Find-DuplicateFiles {
    <#
    .SYNOPSIS
        Finds duplicate files between downloads folder and media folders.
    .PARAMETER DownloadsPath
        Path to downloads folder.
    .PARAMETER MediaPaths
        Array of media folder paths.
    .PARAMETER MinSizeBytes
        Minimum file size to check (default: 100MB).
    #>
    param(
        [string]$DownloadsPath,
        [array]$MediaPaths,
        [long]$MinSizeBytes = 100MB
    )

    Write-Host "" -ForegroundColor Cyan
    Write-Host "  Scanning for duplicates..." -ForegroundColor Cyan
    Write-Host "  Minimum file size: $(Get-ReadableSize -Bytes $MinSizeBytes)" -ForegroundColor Gray

    $duplicates = @()

    # Build index of all media files by size
    Write-Host "  Indexing media libraries..." -ForegroundColor Gray
    $mediaFilesBySize = @{}
    $totalMediaFiles = 0

    foreach ($mediaPath in $MediaPaths) {
        if (-not (Test-Path $mediaPath)) {
            Write-Host "    Skipping missing path: $mediaPath" -ForegroundColor DarkGray
            continue
        }

        $files = Get-ChildItem -LiteralPath $mediaPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -ge $MinSizeBytes }

        foreach ($file in $files) {
            $size = $file.Length
            if (-not $mediaFilesBySize.ContainsKey($size)) {
                $mediaFilesBySize[$size] = @()
            }
            $mediaFilesBySize[$size] += $file
            $totalMediaFiles++
        }
    }

    Write-Host "    Indexed $totalMediaFiles media files." -ForegroundColor Gray

    # Get downloads files
    $downloadsFiles = @(Get-FilesFromPath -Path $DownloadsPath -MinSizeBytes $MinSizeBytes)

    if ($downloadsFiles.Count -eq 0) {
        Write-Host "  No files found in downloads folder (>= $(Get-ReadableSize -Bytes $MinSizeBytes))." -ForegroundColor Yellow
        return $duplicates
    }

    Write-Host "  Found $($downloadsFiles.Count) files in downloads." -ForegroundColor Gray

    # Find duplicates by checking downloads against media index
    $checkedCount = 0
    $hashMatchCount = 0

    foreach ($dlFile in $downloadsFiles) {
        $size = $dlFile.Length

        # Check if any media files have the same size
        if ($mediaFilesBySize.ContainsKey($size)) {
            $candidates = $mediaFilesBySize[$size]

            foreach ($mediaFile in $candidates) {
                $checkedCount++

                # Compare partial hash
                $dlHash = Get-FileHashPartial -FilePath $dlFile.FullName
                $mediaHash = Get-FileHashPartial -FilePath $mediaFile.FullName

                if ($dlHash -and $mediaHash -and $dlHash -eq $mediaHash) {
                    $hashMatchCount++
                    $linkType = Get-LinkType -Path1 $dlFile.FullName -Path2 $mediaFile.FullName
                    $duplicates += [PSCustomObject]@{
                        DownloadFile = $dlFile.FullName
                        DownloadSize = $dlFile.Length
                        MediaFile    = $mediaFile.FullName
                        MediaSize    = $mediaFile.Length
                        Hash         = $dlHash
                        Type         = $linkType
                    }
                    $typeColor = switch ($linkType) {
                        "HARDLINK" { "Green" }
                        "SYMLINK"  { "Cyan" }
                        default    { "Green" }
                    }
                    Write-Host "    Found $linkType`: $($dlFile.Name)" -ForegroundColor $typeColor
                }

                if ($checkedCount % 100 -eq 0) {
                    Write-Host "    Checked $checkedCount potential matches..." -ForegroundColor DarkGray
                }
            }
        }
    }

    Write-Host "  Checked $checkedCount size matches, found $hashMatchCount hash duplicates." -ForegroundColor Gray
    return $duplicates
}

function Write-DuplicateReport {
    <#
    .SYNOPSIS
        Displays a formatted report of duplicate files.
    .PARAMETER Duplicates
        Array of duplicate file objects.
    #>
    param([array]$Duplicates)

    Write-Host "" -ForegroundColor Cyan
    Write-Host $("=" * 60) -ForegroundColor Cyan
    Write-Host "  DUPLICATE FILES REPORT" -ForegroundColor Cyan
    Write-Host $("=" * 60) -ForegroundColor Cyan

    if (-not $Duplicates -or $Duplicates.Count -eq 0) {
        Write-Host "  No duplicates found!" -ForegroundColor Green
        Write-Host "" -ForegroundColor Cyan
        return
    }

    Write-Host "  Found $($Duplicates.Count) duplicate file(s):" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Cyan

    $totalWastedSpace = 0
    $counts = @{
        DUPE = 0
        HARDLINK = 0
        SYMLINK = 0
    }

    foreach ($dup in $Duplicates) {
        $sizeStr = Get-ReadableSize -Bytes $dup.DownloadSize
        $type = if ($dup.Type) { $dup.Type } else { "DUPE" }
        $counts[$type]++

        # Only count wasted space for actual duplicates
        if ($type -eq "DUPE") {
            $totalWastedSpace += $dup.DownloadSize
        }

        # Set color based on type
        $tagColor = switch ($type) {
            "HARDLINK" { "Green" }
            "SYMLINK"  { "Cyan" }
            default    { "Red" }
        }

        Write-Host "  [$type]" -ForegroundColor $tagColor -NoNewline
        Write-Host " $sizeStr" -ForegroundColor Yellow
        Write-Host "    Downloads: " -ForegroundColor DarkGray -NoNewline
        Write-Host $dup.DownloadFile -ForegroundColor Gray
        Write-Host "    Media:     " -ForegroundColor DarkGray -NoNewline
        Write-Host $dup.MediaFile -ForegroundColor Gray
        Write-Host "    Hash:      " -ForegroundColor DarkGray -NoNewline
        Write-Host $dup.Hash.Substring(0, [Math]::Min(16, $dup.Hash.Length))"..." -ForegroundColor DarkGray
        Write-Host "" -ForegroundColor Cyan
    }

    Write-Host $("-" * 60) -ForegroundColor DarkGray
    Write-Host "  Total items:         " -ForegroundColor Cyan -NoNewline
    Write-Host $Duplicates.Count -ForegroundColor Yellow
    Write-Host "  Duplicates:          " -ForegroundColor Cyan -NoNewline
    Write-Host "$($counts.DUPE) ($(Get-ReadableSize -Bytes $totalWastedSpace) wasted)" -ForegroundColor Red
    Write-Host "  Hard links:          " -ForegroundColor Cyan -NoNewline
    Write-Host "$($counts.HARDLINK) (already optimized)" -ForegroundColor Green
    Write-Host "  Symlinks:            " -ForegroundColor Cyan -NoNewline
    Write-Host $counts.SYMLINK -ForegroundColor Cyan
    Write-Host $("=" * 60) -ForegroundColor Cyan
    Write-Host ""
}
