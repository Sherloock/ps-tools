# Bálint's PowerShell Toolkit

Modular PowerShell environment for Full Stack development and System Management.

## Structure

- `loader.ps1`: The loader script (copy content to your Windows Profile path).
- `core/`: Basic system utilities (IP, Disk, Timer, Dashboard).
- `dev/`: Development tools (Node cleanup, Port kill, Passwords, Navigation).
- `media/`: Movie and show library management.

## Installation

1. Clone this repo to `f:\Fejlesztes\projects\my\ps-tools`.
2. Run `Win + R` -> `notepad $PROFILE`.
3. Paste the content from `loader.ps1` into your profile.
4. Restart PowerShell or run `. $PROFILE` to reload.

## Usage

Type `??` in PowerShell to see all available commands with descriptions.

## Functions

### Core
- `Show-IP` - Network dashboard with local and public IP info
- `Disk-Space` - Disk usage dashboard with color-coded warnings
- `Fast` - Internet speed test using Speedtest CLI
- `timer` / `btimer` / `timer-bg` - Countdown timers (foreground/background)

### Dev
- `Pass` - Secure password generator
- `Port-Kill` - Kill process by port number
- `Clean-Node` - Find and remove node_modules folders
- `go` - Quick navigation bookmarks

### Media
- `List-Size` - List files/folders sorted by size
- `List-Video` - Aggregate video library statistics
