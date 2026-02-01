# Timer-specific helper functions
# Loaded after Helpers.ps1, before Timer.ps1

# ============================================================================
# ANSI COLORS
# ============================================================================

function Get-AnsiColors {
    <#
    .SYNOPSIS
        Returns a hashtable of ANSI color escape codes for console output.
    #>
    $esc = [char]27
    return @{
        Esc        = $esc
        Reset      = "$esc[0m"
        Bold       = "$esc[1m"
        Dim        = "$esc[2m"
        Cyan       = "$esc[36m"
        DarkCyan   = "$esc[36m"
        Green      = "$esc[32m"
        Yellow     = "$esc[33m"
        Red        = "$esc[31m"
        Magenta    = "$esc[35m"
        White      = "$esc[97m"
        Gray       = "$esc[90m"
        InvertCyan = "$esc[30;46m"  # Black text on cyan background
    }
}

# ============================================================================
# TIME FORMATTING
# ============================================================================

function Format-RemainingTime {
    <#
    .SYNOPSIS
        Formats a TimeSpan as HH:MM:SS string.
    .PARAMETER Remaining
        The TimeSpan to format.
    .RETURNS
        String in format "HH:MM:SS" or "00:00:00" if negative.
    #>
    param([TimeSpan]$Remaining)

    if ($Remaining.TotalSeconds -lt 0) {
        return "00:00:00"
    }
    return "{0:D2}:{1:D2}:{2:D2}" -f [int]$Remaining.Hours, $Remaining.Minutes, $Remaining.Seconds
}

# ============================================================================
# STATE HELPERS
# ============================================================================

function Get-TimerStateColor {
    <#
    .SYNOPSIS
        Returns the display color for a timer state.
    .PARAMETER State
        The timer state (Running, Paused, Completed, Lost).
    .PARAMETER Ansi
        If set, returns ANSI escape code instead of color name.
    #>
    param(
        [string]$State,
        [switch]$Ansi
    )

    $colorName = switch ($State) {
        'Running'   { 'Green' }
        'Completed' { 'DarkGray' }
        'Paused'    { 'Yellow' }
        'Lost'      { 'Red' }
        default     { 'Gray' }
    }

    if ($Ansi) {
        $colors = Get-AnsiColors
        $result = switch ($colorName) {
            'Green'    { $colors.Green }
            'DarkGray' { $colors.Gray }
            'Yellow'   { $colors.Yellow }
            'Red'      { $colors.Red }
            default    { $colors.Gray }
        }
        return $result
    }

    return $colorName
}

# ============================================================================
# PROGRESS CALCULATION
# ============================================================================

function Get-TimerProgress {
    <#
    .SYNOPSIS
        Calculates the progress percentage for a timer.
    .PARAMETER Timer
        The timer object with StartTime, EndTime, Seconds, and State.
    .RETURNS
        Double percentage (0-100), or -1 if not applicable.
    #>
    param([PSCustomObject]$Timer)

    if ($Timer.State -eq 'Completed') {
        return [double]100
    }

    if ($Timer.State -eq 'Paused') {
        # Calculate progress based on remaining seconds
        $remaining = if ($Timer.RemainingSeconds) { $Timer.RemainingSeconds } else { $Timer.Seconds }
        $elapsed = $Timer.Seconds - $remaining
        $percent = [math]::Min(100, [math]::Max(0, ($elapsed / $Timer.Seconds) * 100))
        return [double]$percent
    }

    if ($Timer.State -ne 'Running') {
        return [double]-1
    }

    $now = Get-Date
    $startTime = [DateTime]::Parse($Timer.StartTime)
    $elapsed = ($now - $startTime).TotalSeconds
    
    # Force double precision before division
    $percent = ([double]$elapsed / $Timer.Seconds) * 100
    $percent = [math]::Min(100.0, [math]::Max(0.0, $percent))

    return $percent
}

# ============================================================================
# TEXT HELPERS
# ============================================================================

function Get-TruncatedMessage {
    <#
    .SYNOPSIS
        Truncates a message to a maximum length with ellipsis.
    .PARAMETER Message
        The message to truncate.
    .PARAMETER MaxLength
        Maximum length (default 20).
    #>
    param(
        [string]$Message,
        [int]$MaxLength = 20
    )

    if ($Message.Length -gt $MaxLength) {
        return $Message.Substring(0, $MaxLength - 3) + "..."
    }
    return $Message
}

# ============================================================================
# PICKER OPTIONS BUILDER
# ============================================================================

function Get-TimerPickerOptions {
    <#
    .SYNOPSIS
        Builds options array for Show-MenuPicker from timer list.
    .PARAMETER Timers
        Array of timer objects.
    .PARAMETER FilterState
        Filter timers by state ('Running', 'Paused'). Null for all.
    .PARAMETER ShowRemaining
        Show remaining time in label.
    .PARAMETER IncludeAllOption
        Add "all" option at the end.
    .PARAMETER IncludeDoneOption
        Add "done" option (for completed/lost timers).
    .PARAMETER AllOptionLabel
        Custom label for the "all" option.
    .PARAMETER AllOptionColor
        Color for the "all" option.
    #>
    param(
        [array]$Timers,
        [string]$FilterState,
        [switch]$ShowRemaining,
        [switch]$IncludeAllOption,
        [switch]$IncludeDoneOption,
        [string]$AllOptionLabel,
        [string]$AllOptionColor = 'Yellow'
    )

    $options = @()

    # Filter timers if state specified
    $filteredTimers = $Timers
    if ($FilterState) {
        $filteredTimers = @($Timers | Where-Object { $_.State -eq $FilterState })
    }

    # Build individual timer options
    foreach ($t in $filteredTimers) {
        $color = Get-TimerStateColor -State $t.State

        # Build label
        if ($ShowRemaining) {
            if ($t.State -eq 'Running') {
                $remaining = ([DateTime]::Parse($t.EndTime) - (Get-Date))
                $remainingStr = Format-RemainingTime -Remaining $remaining
                $label = "[$($t.Id)] $($t.Message) - $remainingStr remaining"
            }
            elseif ($t.State -eq 'Paused') {
                $remaining = if ($t.RemainingSeconds) { $t.RemainingSeconds } else { $t.Seconds }
                $remainingStr = Format-Duration -Seconds $remaining
                $label = "[$($t.Id)] $($t.Message) - $remainingStr remaining"
            }
            else {
                $label = "[$($t.Id)] $($t.Message) ($($t.State))"
            }
        }
        else {
            $label = "[$($t.Id)] $($t.Message) ($($t.State))"
        }

        $options += @{
            Id    = $t.Id
            Label = $label
            Color = $color
        }
    }

    # Add "done" option if requested
    if ($IncludeDoneOption) {
        $doneCount = @($Timers | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Lost' }).Count
        if ($doneCount -gt 0) {
            $options += @{
                Id    = 'done'
                Label = "Remove all finished ($doneCount completed/lost)"
                Color = 'Cyan'
            }
        }
    }

    # Add "all" option if requested and multiple timers exist
    if ($IncludeAllOption -and $filteredTimers.Count -gt 1) {
        $label = if ($AllOptionLabel) { $AllOptionLabel } else { "All ($($filteredTimers.Count) total)" }
        $options += @{
            Id    = 'all'
            Label = $label
            Color = $AllOptionColor
        }
    }

    return $options
}

# ============================================================================
# TIMER SEQUENCE HELPERS
# ============================================================================

# Timer presets - loaded from config.ps1
# See config.example.ps1 for documentation
$script:TimerPresets = if ($global:Config -and $global:Config.TimerPresets) {
    $global:Config.TimerPresets
} else {
    @{}
}

function Test-TimerSequence {
    <#
    .SYNOPSIS
        Checks if a string is a timer sequence pattern (contains grouping or comma).
    .DESCRIPTION
        Returns $true if the input looks like a sequence pattern rather than simple time.
        Sequences contain: parentheses, commas, or 'x' multiplier.
    .PARAMETER Pattern
        The input string to test.
    #>
    param([string]$Pattern)
    
    # Check for preset name first
    if ($script:TimerPresets.ContainsKey($Pattern)) {
        return $true
    }
    
    # Check for sequence syntax: parentheses, comma separators, or xN multiplier
    if ($Pattern -match '\(' -or $Pattern -match ',' -or $Pattern -match '\)x\d+') {
        return $true
    }
    
    return $false
}

function ConvertFrom-TimerSequence {
    <#
    .SYNOPSIS
        Parses a timer sequence string into structured phase data.
    .DESCRIPTION
        Supports syntax:
        - Simple: 25m, 25m work
        - Groups: (25m work, 5m rest)x4
        - Nested: ((25m work, 5m rest)x4, 30m break)x2
        - Mixed: (25m work, 5m rest)x4, 30m 'long break'
    .PARAMETER Pattern
        The sequence pattern string to parse.
    .RETURNS
        Array of phase objects with: Seconds, Label, GroupId, LoopIndex
    .EXAMPLE
        ConvertFrom-TimerSequence "(25m work, 5m rest)x4"
    #>
    param([string]$Pattern)
    
    # Resolve preset if applicable
    if ($script:TimerPresets.ContainsKey($Pattern)) {
        $Pattern = $script:TimerPresets[$Pattern].Pattern
    }
    
    # Tokenize the pattern
    $tokens = @()
    $i = 0
    $len = $Pattern.Length
    
    while ($i -lt $len) {
        $char = $Pattern[$i]
        
        # Skip whitespace
        if ($char -match '\s') {
            $i++
            continue
        }
        
        # Parentheses
        if ($char -eq '(') {
            $tokens += @{ Type = 'LPAREN'; Value = '(' }
            $i++
            continue
        }
        if ($char -eq ')') {
            $tokens += @{ Type = 'RPAREN'; Value = ')' }
            $i++
            continue
        }
        
        # Comma
        if ($char -eq ',') {
            $tokens += @{ Type = 'COMMA'; Value = ',' }
            $i++
            continue
        }
        
        # Multiplier (xN)
        if ($char -eq 'x' -and $i + 1 -lt $len -and $Pattern[$i + 1] -match '\d') {
            $numStr = ''
            $i++  # Skip 'x'
            while ($i -lt $len -and $Pattern[$i] -match '\d') {
                $numStr += $Pattern[$i]
                $i++
            }
            $tokens += @{ Type = 'MULT'; Value = [int]$numStr }
            continue
        }
        
        # Quoted string (label)
        if ($char -eq "'" -or $char -eq '"') {
            $quote = $char
            $str = ''
            $i++  # Skip opening quote
            while ($i -lt $len -and $Pattern[$i] -ne $quote) {
                $str += $Pattern[$i]
                $i++
            }
            $i++  # Skip closing quote
            $tokens += @{ Type = 'LABEL'; Value = $str }
            continue
        }
        
        # Duration (e.g., 25m, 1h30m, 90s)
        if ($char -match '\d') {
            $durStr = ''
            while ($i -lt $len -and $Pattern[$i] -match '[\dhms]') {
                $durStr += $Pattern[$i]
                $i++
            }
            $tokens += @{ Type = 'DURATION'; Value = $durStr }
            continue
        }
        
        # Word (unquoted label)
        if ($char -match '[a-zA-Z]') {
            $word = ''
            while ($i -lt $len -and $Pattern[$i] -match '[a-zA-Z0-9_-]') {
                $word += $Pattern[$i]
                $i++
            }
            # Check if it's not 'x' followed by number (multiplier)
            $tokens += @{ Type = 'LABEL'; Value = $word }
            continue
        }
        
        # Unknown character, skip
        $i++
    }
    
    # Parse tokens into AST
    $ast = ParseSequence -Tokens $tokens -Index ([ref]0)
    
    # Expand AST into flat phase list
    $phases = Expand-TimerSequence -Ast $ast
    
    return $phases
}

function ParseSequence {
    <#
    .SYNOPSIS
        Internal recursive parser for sequence tokens.
    #>
    param(
        [array]$Tokens,
        [ref]$Index
    )
    
    $items = @()
    
    while ($Index.Value -lt $Tokens.Count) {
        $token = $Tokens[$Index.Value]
        
        if ($token.Type -eq 'LPAREN') {
            # Start of group
            $Index.Value++
            $groupItems = ParseSequence -Tokens $Tokens -Index $Index
            
            # Check for multiplier after closing paren
            $mult = 1
            if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Type -eq 'MULT') {
                $mult = $Tokens[$Index.Value].Value
                $Index.Value++
            }
            
            $items += @{
                Type     = 'GROUP'
                Items    = $groupItems
                Multiply = $mult
            }
        }
        elseif ($token.Type -eq 'RPAREN') {
            # End of group
            $Index.Value++
            break
        }
        elseif ($token.Type -eq 'COMMA') {
            # Separator, skip
            $Index.Value++
        }
        elseif ($token.Type -eq 'DURATION') {
            # Single phase
            $seconds = ConvertTo-Seconds -Time $token.Value
            $label = "Timer"
            $Index.Value++
            
            # Check for label
            if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Type -eq 'LABEL') {
                $label = $Tokens[$Index.Value].Value
                $Index.Value++
            }
            
            $items += @{
                Type    = 'PHASE'
                Seconds = $seconds
                Label   = $label
                Duration = $token.Value
            }
        }
        else {
            # Skip unknown
            $Index.Value++
        }
    }
    
    return $items
}

function Expand-TimerSequence {
    <#
    .SYNOPSIS
        Expands AST into flat phase list with loop metadata.
    .DESCRIPTION
        Takes parsed AST and returns array of phases with:
        - Seconds: duration in seconds
        - Label: phase label
        - Duration: original duration string
        - LoopId: unique identifier for the loop this phase belongs to
        - LoopIteration: which iteration of the loop (1-based)
        - LoopTotal: total iterations in this loop
    #>
    param(
        [array]$Ast,
        [string]$ParentLoopId = '',
        [int]$ParentIteration = 1,
        [int]$ParentTotal = 1
    )
    
    $phases = @()
    $groupCounter = 0
    
    foreach ($item in $Ast) {
        if ($item.Type -eq 'PHASE') {
            $phases += [PSCustomObject]@{
                Seconds       = $item.Seconds
                Label         = $item.Label
                Duration      = $item.Duration
                LoopId        = $ParentLoopId
                LoopIteration = $ParentIteration
                LoopTotal     = $ParentTotal
            }
        }
        elseif ($item.Type -eq 'GROUP') {
            $groupCounter++
            $loopId = if ($ParentLoopId) { "${ParentLoopId}.${groupCounter}" } else { [string]$groupCounter }
            
            for ($iter = 1; $iter -le $item.Multiply; $iter++) {
                $expanded = Expand-TimerSequence -Ast $item.Items -ParentLoopId $loopId -ParentIteration $iter -ParentTotal $item.Multiply
                $phases += $expanded
            }
        }
    }
    
    return $phases
}

function Get-SequenceSummary {
    <#
    .SYNOPSIS
        Returns summary information about a timer sequence.
    .PARAMETER Phases
        Array of expanded phases from Expand-TimerSequence.
    .RETURNS
        Object with: TotalSeconds, TotalDuration, PhaseCount, Description
    #>
    param([array]$Phases)
    
    $totalSeconds = 0
    foreach ($p in $Phases) {
        $totalSeconds += $p.Seconds
    }
    
    # Build description from unique labels
    $labelCounts = @{}
    foreach ($p in $Phases) {
        if (-not $labelCounts.ContainsKey($p.Label)) {
            $labelCounts[$p.Label] = 0
        }
        $labelCounts[$p.Label]++
    }
    
    $descParts = @()
    foreach ($label in $labelCounts.Keys) {
        $count = $labelCounts[$label]
        if ($count -gt 1) {
            $descParts += "${count}x $label"
        }
        else {
            $descParts += $label
        }
    }
    
    return [PSCustomObject]@{
        TotalSeconds  = $totalSeconds
        TotalDuration = Format-Duration -Seconds $totalSeconds
        PhaseCount    = $Phases.Count
        Description   = $descParts -join ', '
    }
}

function Start-SequenceTimerJob {
    <#
    .SYNOPSIS
        Internal function to start a sequence timer phase using Windows Scheduled Task.
    .DESCRIPTION
        Similar to Start-TimerJob but handles phase transitions for sequences.
        Each phase completion triggers the next phase until all phases are done.
    #>
    param([PSCustomObject]$Timer)

    $taskName = "PSTimer_$($Timer.Id)"
    $dataFile = Join-Path $env:TEMP "ps-timers.json"
    
    # Calculate trigger time for current phase
    $triggerTime = (Get-Date).AddSeconds($Timer.Seconds)
    
    # Build the notification script - reads from JSON to get current state
    # This approach avoids nested heredocs and keeps the script self-contained
    $scriptLines = @(
        "`$timerId = $($Timer.Id)"
        "`$dataFile = '$dataFile'"
        ""
        "# Read current timer state from JSON"
        "if (-not (Test-Path -LiteralPath `$dataFile)) { exit }"
        "`$jsonContent = Get-Content -LiteralPath `$dataFile -Raw -ErrorAction SilentlyContinue"
        "`$parsed = `$jsonContent | ConvertFrom-Json"
        "`$timers = New-Object System.Collections.ArrayList"
        "`$parsed | ForEach-Object { [void]`$timers.Add(`$_) }"
        "`$timer = `$timers | Where-Object { `$_.Id -eq `$timerId }"
        ""
        "if (-not `$timer -or -not `$timer.IsSequence) { exit }"
        ""
        "`$currentPhase = [int]`$timer.CurrentPhase"
        "`$totalPhases = [int]`$timer.TotalPhases"
        "`$phaseLabel = `$timer.PhaseLabel"
        ""
        "# Beep notification - different tones for phase vs completion"
        "if (`$currentPhase -eq `$totalPhases - 1) {"
        "    [console]::beep(523, 200); [console]::beep(659, 200); [console]::beep(784, 400)"
        "} else {"
        "    [console]::beep(440, 300)"
        "}"
        ""
        "`$nextPhaseIdx = `$currentPhase + 1"
        ""
        "if (`$nextPhaseIdx -lt `$totalPhases) {"
        "    # More phases to go"
        "    `$phases = `$timer.Phases"
        "    `$nextPhase = `$phases[`$nextPhaseIdx]"
        "    `$nextSeconds = [int]`$nextPhase.Seconds"
        "    `$nextLabel = `$nextPhase.Label"
        "    "
        "    `$timer.CurrentPhase = `$nextPhaseIdx"
        "    `$timer.PhaseLabel = `$nextLabel"
        "    `$timer.Seconds = `$nextSeconds"
        "    `$timer.Message = `$nextLabel"
        "    `$timer.StartTime = (Get-Date).ToString('o')"
        "    `$timer.EndTime = (Get-Date).AddSeconds(`$nextSeconds).ToString('o')"
        "    `$timer.State = 'Running'"
        "    "
        "    # Schedule next phase"
        "    `$nextTrigger = (Get-Date).AddSeconds(`$nextSeconds)"
        "    `$nextAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument `"-WindowStyle Hidden -ExecutionPolicy Bypass -File ```"`$env:TEMP\PSTimer_`$timerId.ps1```"`""
        "    `$nextTriggerObj = New-ScheduledTaskTrigger -Once -At `$nextTrigger"
        "    `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable"
        "    Unregister-ScheduledTask -TaskName `"PSTimer_`$timerId`" -Confirm:`$false -ErrorAction SilentlyContinue"
        "    Register-ScheduledTask -TaskName `"PSTimer_`$timerId`" -Action `$nextAction -Trigger `$nextTriggerObj -Settings `$settings -Force | Out-Null"
        "} else {"
        "    # All phases done"
        "    `$timer.State = 'Completed'"
        "    `$timer.CurrentPhase = `$totalPhases"
        "    Unregister-ScheduledTask -TaskName `"PSTimer_`$timerId`" -Confirm:`$false -ErrorAction SilentlyContinue"
        "    Remove-Item -LiteralPath `"`$env:TEMP\PSTimer_`$timerId.ps1`" -Force -ErrorAction SilentlyContinue"
        "}"
        ""
        "ConvertTo-Json -InputObject `$timers -Depth 10 | Set-Content -LiteralPath `$dataFile -Force"
        ""
        "# Show popup"
        "`$phaseNum = `$currentPhase + 1"
        "`$endStr = (Get-Date).ToString('HH:mm:ss')"
        "if (`$currentPhase -eq `$totalPhases - 1) {"
        "    `$body = @(`"Sequence completed!`", `"`", `"All `$totalPhases phases done`", `"Finished: `$endStr`")"
        "    `$title = `"Sequence Complete!`""
        "} else {"
        "    `$nextPhaseNum = `$phaseNum + 1"
        "    `$body = @(`"Phase `$phaseNum/`$totalPhases done: `$phaseLabel`", `"`", `"Next: Phase `$nextPhaseNum`", `"Time: `$endStr`")"
        "    `$title = `"Phase Complete`""
        "}"
        "`$popup = New-Object -ComObject WScript.Shell"
        "`$popup.Popup((`$body -join [char]10), 0, `$title, 64) | Out-Null"
    )
    
    $script = $scriptLines -join "`r`n"
    
    # Write script to temp file
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
