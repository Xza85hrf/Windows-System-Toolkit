<#
.SYNOPSIS
    Updates packages across Winget, WSL apt, and pip.
.DESCRIPTION
    Runs package upgrades across all configured package managers.
    Supports exclusion lists and dry-run mode. Requires Administrator.
.PARAMETER Auto
    Run without pausing for user input. Use for scheduled tasks.
.PARAMETER DryRun
    Show what would be upgraded without making changes.
.PARAMETER ExclusionFile
    Path to a JSON file listing package names to skip.
    Default: config\excluded-packages.json
.EXAMPLE
    .\Update-AllPackages.ps1 -DryRun
    Preview available updates without installing anything.
.EXAMPLE
    .\Update-AllPackages.ps1 -Auto
    Upgrade all packages silently (for scheduled tasks).
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$DryRun,
    [string]$ExclusionFile
)

$ErrorActionPreference = 'Continue'

# --- Load shared modules ---
. (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
. (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
$logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot

Write-Banner -Title "Update All Packages"
Add-Content -Path $logFile -Value "=== Update-AllPackages started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

if (-not (Test-IsAdmin)) {
    Write-Bad "Administrator privileges required."
    Write-Info "Right-click PowerShell and select 'Run as Administrator', then re-run this script."
    exit 2
}

$exclusions = @()
try {
    Write-Step 1 6 "Loading exclusion list"
    if ($ExclusionFile) {
        $exclusionPath = $ExclusionFile
    } else {
        $exFile = Get-ProfileValue $config "Packages.exclusionsFile" "config\excluded-packages.json"
        $exclusionPath = Join-Path $PSScriptRoot $exFile
    }
    if (Test-Path $exclusionPath) {
        $exclusions = Get-Content $exclusionPath -Raw | ConvertFrom-Json
        Write-Good "Exclusions loaded from $exclusionPath"
        Write-Data "Excluded packages: $($exclusions -join ', ')"
    } else {
        Write-Info "No exclusion file found at $exclusionPath"
    }
} catch {
    Write-Bad "Failed to load exclusions: $_"
}

$wingetUpgrades = 0
$wingetEnabled = Get-ProfileValue $config "Packages.winget.enabled" $true
try {
    Write-Step 2 6 "Checking/Upgrading winget packages"
    if (-not $wingetEnabled) { Write-Info "Winget updates disabled in profile"; throw "skip" }
    if ($DryRun) {
        Write-Info "Dry run - listing available upgrades"
        winget upgrade --all --include-unknown --accept-source-agreements
    } else {
        if ($exclusions.Count -gt 0) {
            Write-Info "Upgrading packages with exclusions"
            # Parse winget text table (--output json is unreliable)
            $upgradeText = (winget upgrade --include-unknown --accept-source-agreements 2>$null) | Out-String
            $tableLines = $upgradeText -split "`r?`n"
            $headerIdx = -1
            for ($i = 0; $i -lt $tableLines.Count; $i++) {
                if ($tableLines[$i] -match '^Name\s+Id\s+Version\s+Available') { $headerIdx = $i; break }
            }
            if ($headerIdx -ge 0) {
                $header = $tableLines[$headerIdx]
                $idStart = $header.IndexOf('Id')
                $verStart = $header.IndexOf('Version')
                for ($i = $headerIdx + 2; $i -lt $tableLines.Count; $i++) {
                    $line = $tableLines[$i]
                    if ($line -match '^\d+ upgrades? available' -or $line.Trim() -eq '') { break }
                    if ($line.Length -gt $verStart) {
                        $pkgName = $line.Substring(0, $idStart).Trim()
                        $pkgId = $line.Substring($idStart, $verStart - $idStart).Trim()
                        if ($pkgId -and $pkgName -notin $exclusions) {
                            Write-Data "Upgrading: $pkgName ($pkgId)"
                            winget upgrade --id $pkgId --accept-source-agreements --accept-package-agreements --silent
                            $wingetUpgrades++
                        } elseif ($pkgName -in $exclusions) {
                            Write-Data "Skipped (excluded): $pkgName"
                        }
                    }
                }
            }
        } else {
            Write-Info "Upgrading all packages"
            winget upgrade --all --accept-source-agreements --accept-package-agreements --silent
        }
    }
    Write-Good "Winget step completed"
} catch {
    Write-Bad "Winget step failed: $_"
}

$wslUpgrades = 0
$wslEnabled = Get-ProfileValue $config "Packages.wsl.enabled" $true
try {
    Write-Step 3 6 "Checking/Upgrading WSL packages"
    if (-not $wslEnabled) { Write-Info "WSL updates disabled in profile"; throw "skip" }
    # wsl.exe --list outputs UTF-16LE; temporarily set console encoding so PowerShell decodes it correctly
    $prevEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $distro = (wsl --list --quiet 2>$null) | Where-Object { $_.Trim() } | Select-Object -First 1
    [Console]::OutputEncoding = $prevEncoding
    if ($distro) { $distro = $distro.Trim() }
    if ($distro) {
        $scriptPath = Join-Path $PSScriptRoot "wsl\update-packages.sh"
        Write-Info "Converting path for WSL: $scriptPath"
        $wslPath = wsl -d $distro wslpath ($scriptPath -replace '\\', '/')
        if (-not $wslPath) {
            Write-Bad "wslpath conversion failed for $scriptPath"
        } elseif ($DryRun) {
            Write-Info "Dry run - would run: wsl -d $distro -u root bash $wslPath"
        } else {
            Write-Info "Running updates in $distro (as root)..."
            # Use -u root instead of sudo to avoid interactive password prompt
            $result = wsl -d $distro -u root bash $wslPath 2>&1
            $result | ForEach-Object { Write-Data $_ }
            $upgradeLine = $result | Select-String "upgraded" | Select-Object -First 1
            if ($upgradeLine -and $upgradeLine.ToString() -match '^(\d+)') {
                $wslUpgrades = [int]$Matches[1]
            }
        }
        Write-Good "WSL step completed"
    } else {
        Write-Info "No WSL distribution found"
    }
} catch {
    Write-Bad "WSL step failed: $_"
}

$pipUpgrades = 0
$pipEnabled = Get-ProfileValue $config "Packages.pip.enabled" $true
try {
    Write-Step 4 6 "Upgrading outdated pip packages"
    if (-not $pipEnabled) { Write-Info "Pip updates disabled in profile"; throw "skip" }
    $pipOutdated = python -m pip list --outdated --format=json 2>$null | ConvertFrom-Json
    if ($pipOutdated) {
        foreach ($pkg in $pipOutdated) {
            Write-Data "$($pkg.name) $($pkg.version) -> $($pkg.latest_version)"
            if (-not $DryRun) {
                python -m pip install --upgrade $pkg.name --quiet 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Good "Upgraded: $($pkg.name)"
                    $pipUpgrades++
                } else {
                    Write-Warn "Failed to upgrade: $($pkg.name)"
                }
            }
        }
    } else {
        Write-Info "All pip packages are up to date"
    }
    Write-Good "Pip step completed"
} catch {
    Write-Bad "Pip step failed: $_"
}

Write-Step 5 6 "Summary"
Write-Info "Winget upgrades: $wingetUpgrades"
Write-Info "WSL upgrades: $wslUpgrades"
Write-Info "Pip upgrades: $pipUpgrades / $(if ($pipOutdated) { $pipOutdated.Count } else { 0 }) outdated"

try {
    Write-Step 6 6 "Cleaning up old logs"
    $logRoot = Join-Path $PSScriptRoot "logs"
    $retentionDays = Get-ProfileValue $config "Logging.retentionDays" 30
    $cutoff = (Get-Date).AddDays(-$retentionDays)
    Get-ChildItem $logRoot -Directory | Where-Object { $_.CreationTime -lt $cutoff } | Remove-Item -Recurse -Force
    Write-Good "Log cleanup completed"
} catch {
    Write-Bad "Log cleanup failed: $_"
}

Write-Host ""
Write-Info "Log file: $logFile"
Wait-OrExit -Auto:$Auto
