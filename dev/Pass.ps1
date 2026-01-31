# Password generation utilities

function Pass {
    <#
    .SYNOPSIS
        Generates a secure password. Use: Pass 32 -Complex
    .PARAMETER Length
        Length of password (default 24).
    .PARAMETER Complex
        Switch to add symbols.
    #>
    param (
        [int]$Length = 24,
        [switch]$Complex
    )

    $Charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $Status = "Alphanumeric"

    if ($Complex) {
        $Charset += "!@#$%^&*()-_=+[]{}|;:,.<>?"
        $Status = "Complex (with symbols)"
    }

    $Password = -join (1..$Length | ForEach-Object {
        $Charset[(Get-Random -Minimum 0 -Maximum $Charset.Length)]
    })

    # Enhanced Output
    Write-Host "`n[ PASSWORD GENERATED ]" -ForegroundColor Cyan
    Write-Host "Length:  $Length characters"
    Write-Host "Type:    $Status"
    Write-Host ("-" * 20)
    Write-Host $Password -ForegroundColor Green
    Write-Host ("-" * 20)
    
    $Password | clip
    Write-Host "Result copied to clipboard!`n" -ForegroundColor Gray
}
