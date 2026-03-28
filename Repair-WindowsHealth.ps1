[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$QuickOnly,
    [switch]$FullScan,
    [switch]$CleanBrowserCache
)

$ErrorActionPreference = "Continue"

# --- Load shared modules ---
. (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
. (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
$logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot

Write-Banner -Title "Repair Windows Health"

if (-not (Test-IsAdmin)) {
    Write-Bad "This script must be run as Administrator."
    exit 1
}
Write-Good "Running as Administrator"

$totalSteps = 8
$repairsCount = 0
$issuesFound = 0
$cleanedMB = 0

Write-Step -Step 1 -Total $totalSteps -Title "DISM Health Restore"
if (-not $QuickOnly) {
    Write-Info "Running DISM /Online /Cleanup-Image /RestoreHealth..."
    $dismOutput = & DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String
    Add-Content -Path $logFile -Value $dismOutput
    if ($LASTEXITCODE -eq 0) {
        Write-Good "DISM completed successfully"
        $repairsCount++
    } else {
        Write-Bad "DISM failed with exit code $LASTEXITCODE"
        $issuesFound++
    }
} else {
    Write-Info "Skipping DISM (QuickOnly mode)"
}

Write-Step -Step 2 -Total $totalSteps -Title "System File Checker"
if (-not $QuickOnly) {
    Write-Info "Running sfc /scannow..."
    $sfcOutput = & sfc /scannow 2>&1 | Out-String
    Add-Content -Path $logFile -Value $sfcOutput
    if ($LASTEXITCODE -eq 0) {
        Write-Good "System file checker completed successfully"
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
        Write-Info "Clearing $path - $count files, $sizeInMB MB"
        Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
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
        Write-Warn "Cache size exceeds ${cacheLimitMB}MB, clearing..."
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$softwareDistributionPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Write-Good "Windows Update cache cleared"
        $repairsCount++
        $cleanedMB += $cacheSizeMB
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
    if ($FullScan) {
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
