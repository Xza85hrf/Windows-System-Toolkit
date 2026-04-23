#Requires -Version 5.1
<#
.SYNOPSIS
    Shared output and logging helpers for Windows System Toolkit.
.DESCRIPTION
    Provides consistent colored output with automatic log file writing.
    All scripts dot-source this file after setting $logFile in their scope.

    Usage in scripts:
        . (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
        # ... set up $logFile ...
        Write-Good "Something worked"
#>

function Write-Step {
    param([int]$Step, [int]$Total, [string]$Title)
    Write-Host ""
    Write-Host "  Step $Step of $Total : $Title" -ForegroundColor Yellow
    Write-Host "  $("-" * 50)" -ForegroundColor Gray
    if ($logFile) { Add-Content -Path $logFile -Value "`n=== Step $Step of $Total : $Title ===" }
}

function Write-Good {
    param([string]$msg)
    Write-Host "    [+] $msg" -ForegroundColor Green
    if ($logFile) { Add-Content -Path $logFile -Value "[+] $msg" }
}

function Write-Bad {
    param([string]$msg)
    Write-Host "    [-] $msg" -ForegroundColor Red
    if ($logFile) { Add-Content -Path $logFile -Value "[-] $msg" }
}

function Write-Warn {
    param([string]$msg)
    Write-Host "    [!] $msg" -ForegroundColor Yellow
    if ($logFile) { Add-Content -Path $logFile -Value "[!] $msg" }
}

function Write-Info {
    param([string]$msg)
    Write-Host "    [*] $msg" -ForegroundColor Cyan
    if ($logFile) { Add-Content -Path $logFile -Value "[*] $msg" }
}

function Write-Data {
    param([string]$msg)
    Write-Host "      $msg" -ForegroundColor Gray
    if ($logFile) { Add-Content -Path $logFile -Value "    $msg" }
}

function Clear-HostSafe {
    # Clear-Host manipulates the console cursor, which throws
    # "The handle is invalid" under non-interactive hosts (scheduled
    # tasks, redirected I/O, CI). Swallow the failure there.
    try { Clear-Host } catch { }
}

function Write-Banner {
    param(
        [string]$Title,
        [string]$Subtitle = "Run on: $env:COMPUTERNAME",
        [switch]$ShowAdminNote
    )
    Clear-HostSafe
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host "    WINDOWS SYSTEM TOOLKIT - $Title" -ForegroundColor Magenta
    Write-Host "    $Subtitle" -ForegroundColor Magenta
    if ($ShowAdminNote) {
        $admin = Test-IsAdmin
        if (-not $admin) {
            Write-Host "    NOTE: Run as Admin for full capabilities" -ForegroundColor Yellow
        }
    }
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Summary {
    param(
        [string]$Title = "SUMMARY",
        [int]$OK = 0,
        [int]$Warnings = 0,
        [int]$Errors = 0,
        [int]$Fixes = 0,
        [string]$LogPath
    )
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host "    $Title" -ForegroundColor Magenta
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host ""

    $summaryColor = if ($Errors -gt 0) { "Red" } elseif ($Warnings -gt 0) { "Yellow" } else { "Green" }
    $summaryIcon = if ($Errors -gt 0) { "[-]" } elseif ($Warnings -gt 0) { "[!]" } else { "[+]" }

    $parts = @("OK: $OK", "Warnings: $Warnings", "Errors: $Errors")
    if ($Fixes -gt 0) { $parts += "Fixes applied: $Fixes" }
    Write-Host "    $summaryIcon  $($parts -join '  |  ')" -ForegroundColor $summaryColor
    Write-Host ""

    if ($LogPath) {
        Write-Host "    Log: $LogPath" -ForegroundColor Gray
        Write-Host ""
    }

    if ($logFile) {
        Add-Content -Path $logFile -Value "=== Summary: OK=$OK, Warnings=$Warnings, Errors=$Errors, Fixes=$Fixes ==="
    }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Initialize-Log {
    param([string]$ScriptPath, [string]$RootPath)
    if (-not $RootPath) { $RootPath = Split-Path $ScriptPath }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $dir = Join-Path (Join-Path $RootPath "logs") (Get-Date -Format "yyyy-MM-dd")
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    return Join-Path $dir "${name}_$(Get-Date -Format 'HHmmss').log"
}

function Wait-OrExit {
    param([switch]$Auto)
    if (-not $Auto) {
        Write-Host "  Press any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
