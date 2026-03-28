<#
.SYNOPSIS
    Repairs Windows health using DISM, SFC, and system cleanup.
.DESCRIPTION
    Performs system maintenance: DISM image repair, System File Checker,
    temp file cleanup, Windows Update cache, disk health, and Defender scans.
    Requires Administrator privileges.
.PARAMETER Auto
    Run without pausing for user input. Use for scheduled tasks.
.PARAMETER QuickOnly
    Skip DISM and SFC (the slow parts). Only run cleanup and checks.
.PARAMETER FullScan
    Run a full Windows Defender scan instead of a quick scan.
.PARAMETER CleanBrowserCache
    Also clear Chrome and Edge browser caches.
.PARAMETER DryRun
    Show what would be done without making any changes.
.EXAMPLE
    .\Repair-WindowsHealth.ps1
    Full repair with DISM + SFC + cleanup (may take 15-20 minutes).
.EXAMPLE
    .\Repair-WindowsHealth.ps1 -DryRun
    Preview all steps without running repairs or deleting files.
.EXAMPLE
    .\Repair-WindowsHealth.ps1 -QuickOnly
    Quick cleanup only - skips DISM/SFC, runs in under 2 minutes.
.EXAMPLE
    .\Repair-WindowsHealth.ps1 -Auto -QuickOnly
    Scheduled task mode - quick cleanup, no prompts.
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$QuickOnly,
    [switch]$FullScan,
    [switch]$CleanBrowserCache,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# --- Load shared modules ---
. (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
. (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
$logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot

Write-Banner -Title "Repair Windows Health"

if (-not (Test-IsAdmin)) {
    Write-Bad "This script requires Administrator privileges."
    Write-Info "Right-click PowerShell and select 'Run as Administrator', then re-run this script."
    Write-Info "Or use the System Launcher (System-Launcher.bat) which elevates automatically."
    exit 2
}
Write-Good "Running as Administrator"
if ($DryRun) { Write-Warn "DRY RUN MODE - no changes will be made" }

$totalSteps = 8
$repairsCount = 0
$issuesFound = 0
$cleanedMB = 0

Write-Step -Step 1 -Total $totalSteps -Title "DISM Health Restore"
if ($DryRun) {
    Write-Info "[DryRun] Would run: DISM /Online /Cleanup-Image /RestoreHealth"
} elseif (-not $QuickOnly) {
    Write-Info "Running DISM /Online /Cleanup-Image /RestoreHealth..."
    Write-Info "This may take 10-15 minutes. Progress will be shown below."
    $dismStart = Get-Date
    & DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | ForEach-Object {
        $line = $_.ToString().Trim()
        Add-Content -Path $logFile -Value $line
        if ($line -match '\[=+') {
            Write-Host "`r    [*] $line" -ForegroundColor Cyan -NoNewline
        }
    }
    Write-Host ""
    $dismDuration = [math]::Round(((Get-Date) - $dismStart).TotalMinutes, 1)
    if ($LASTEXITCODE -eq 0) {
        Write-Good "DISM completed successfully ($dismDuration min)"
        $repairsCount++
    } else {
        Write-Bad "DISM failed with exit code $LASTEXITCODE ($dismDuration min)"
        Write-Info "Try: DISM /Online /Cleanup-Image /StartComponentCleanup"
        $issuesFound++
    }
} elseif ($QuickOnly) {
    Write-Info "Skipping DISM (QuickOnly mode)"
}

Write-Step -Step 2 -Total $totalSteps -Title "System File Checker"
if ($DryRun) {
    Write-Info "[DryRun] Would run: sfc /scannow"
} elseif (-not $QuickOnly) {
    Write-Info "Running sfc /scannow..."
    Write-Info "This may take 5-10 minutes. Progress will be shown below."
    $sfcStart = Get-Date
    & sfc /scannow 2>&1 | ForEach-Object {
        $line = $_.ToString().Trim()
        Add-Content -Path $logFile -Value $line
        if ($line -match '^\d+%|Verification|Beginning') {
            Write-Host "`r    [*] $line" -ForegroundColor Cyan -NoNewline
        }
    }
    Write-Host ""
    $sfcDuration = [math]::Round(((Get-Date) - $sfcStart).TotalMinutes, 1)
    if ($LASTEXITCODE -eq 0) {
        Write-Good "System file checker completed ($sfcDuration min)"
        $repairsCount++
    } else {
        Write-Bad "System file checker found violations or errors"
        $issuesFound++
    }
} else {
    Write-Info "Skipping SFC (QuickOnly mode)"
}

Write-Step -Step 3 -Total $totalSteps -Title "Clear Temp Files"
$tempPaths = @($env:TEMP, (Join-Path $env:SystemRoot "Temp"), (Join-Path $env:SystemRoot "Prefetch"))
if ($CleanBrowserCache) {
    $chromeCache = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache"
    $edgeCache = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache"
    if (Test-Path $chromeCache) { $tempPaths += $chromeCache }
    if (Test-Path $edgeCache) { $tempPaths += $edgeCache }
}
foreach ($path in $tempPaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue -File
        $count = $files.Count
        $size = ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $sizeInMB = [math]::Round($size / 1MB, 2)
        if ($DryRun) {
            Write-Info "[DryRun] Would clear $path - $count files, $sizeInMB MB"
        } else {
            Write-Info "Clearing $path - $count files, $sizeInMB MB"
            Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        $cleanedMB += $sizeInMB
    } else {
        Write-Warn "Path not found: $path"
    }
}

Write-Step -Step 4 -Total $totalSteps -Title "Windows Update Cache"
$softwareDistributionPath = Join-Path $env:SystemRoot "SoftwareDistribution\Download"
if (Test-Path $softwareDistributionPath) {
    $cacheSize = (Get-ChildItem -Path $softwareDistributionPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    $cacheSizeMB = [math]::Round($cacheSize / 1MB, 2)
    Write-Info "Windows Update cache size: $cacheSizeMB MB"
    $cacheLimitMB = Get-ProfileValue $config "Windows.updateCache.sizeThresholdMB" 500
    if ($cacheSize -gt ($cacheLimitMB * 1MB)) {
        if ($DryRun) {
            Write-Info "[DryRun] Would clear Windows Update cache ($cacheSizeMB MB)"
        } else {
            Write-Warn "Cache size exceeds ${cacheLimitMB}MB, clearing..."
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$softwareDistributionPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Write-Good "Windows Update cache cleared"
            $repairsCount++
            $cleanedMB += $cacheSizeMB
        }
    } else {
        Write-Info "Cache size within acceptable range"
    }
} else {
    Write-Warn "SoftwareDistribution folder not found"
}

Write-Step -Step 5 -Total $totalSteps -Title "Disk Health"
Import-Module Storage -ErrorAction SilentlyContinue
$physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
if ($physicalDisks) {
    foreach ($disk in $physicalDisks) {
        $diskInfo = "$($disk.FriendlyName) ($($disk.MediaType)) - Status: $($disk.HealthStatus) - Size: $([math]::Round($disk.Size/1GB,2)) GB"
        if ($disk.HealthStatus -eq "Healthy") {
            Write-Good $diskInfo
        } else {
            Write-Bad $diskInfo
            $issuesFound++
        }
    }
} else {
    Write-Warn "Unable to retrieve physical disk information"
}

Write-Step -Step 6 -Total $totalSteps -Title "Windows Defender Scan"
$defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($defenderStatus) {
    $sigAge = $defenderStatus.AntivirusSignatureAge
    $lastQuick = $defenderStatus.QuickScanEndTime
    $daysSinceQuick = if ($lastQuick) { ((Get-Date) - $lastQuick).Days } else { -1 }
    Write-Data "Antivirus signature age: $sigAge days"
    Write-Data "Last quick scan: $lastQuick ($daysSinceQuick days ago)"
    $scanDaysWarn = Get-ProfileValue $config "Windows.defenderScan.daysBeforeWarning" 7
    if ($DryRun) {
        $scanType = if ($FullScan) { "Full" } elseif ($daysSinceQuick -gt $scanDaysWarn) { "Quick" } else { "None needed" }
        Write-Info "[DryRun] Would run: $scanType Defender scan"
    } elseif ($FullScan) {
        Write-Info "Starting full scan..."
        Start-MpScan -ScanType FullScan -ErrorAction SilentlyContinue
        Write-Good "Full scan started"
        $repairsCount++
    } elseif ($daysSinceQuick -gt $scanDaysWarn -and $daysSinceQuick -ge 0) {
        Write-Info "Starting quick scan..."
        Start-MpScan -ScanType QuickScan -ErrorAction SilentlyContinue
        Write-Good "Quick scan started"
        $repairsCount++
    } else {
        Write-Info "Quick scan is up to date (less than $scanDaysWarn days old)"
    }
} else {
    Write-Warn "Windows Defender not available"
}

Write-Step -Step 7 -Total $totalSteps -Title "Windows Update Status"
$hotFixes = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5
if ($hotFixes) {
    foreach ($hf in $hotFixes) {
        Write-Data "HotFix $($hf.HotFixID) - $($hf.Description) - Installed on $($hf.InstalledOn)"
    }
} else {
    Write-Warn "No hotfixes found"
}

Write-Step -Step 8 -Total $totalSteps -Title "Summary"
Write-Summary -Title "REPAIR SUMMARY" -OK $repairsCount -Warnings $issuesFound -Errors 0 -LogPath $logFile
Write-Info "MB cleaned: $cleanedMB"
Wait-OrExit -Auto:$Auto
