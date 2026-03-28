#Requires -Version 5.1
<#
.SYNOPSIS
    Configuration wizard for Windows System Toolkit.
.DESCRIPTION
    Auto-detects hardware (CPU, RAM, GPUs, drives, WSL, installed services),
    prompts for threshold overrides and preferences, and generates
    config/system-profile.json. Re-runnable: preserves existing customizations.
.PARAMETER Auto
    Skip all interactive prompts. Use detected values and defaults.
.PARAMETER DetectOnly
    Detect hardware and display results without saving a profile.
.EXAMPLE
    .\Setup.ps1
    Interactive setup - detects hardware then prompts for threshold customization.
.EXAMPLE
    .\Setup.ps1 -Auto
    Non-interactive setup - detect and save with all defaults.
.EXAMPLE
    .\Setup.ps1 -DetectOnly
    Show detected hardware without creating or modifying the config file.
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$DetectOnly
)
$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'lib\Load-Profile.ps1')

$profileDir  = Join-Path $PSScriptRoot 'config'
$profilePath = Join-Path $profileDir 'system-profile.json'

if (-not (Test-Path $profileDir)) {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
}

# --- Load existing profile or defaults ---
$config = Initialize-Profile -ProfilePath $profilePath

# Backup existing profile before modifying
if (Test-Path $profilePath) {
    $backupPath = "$profilePath.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $profilePath $backupPath -Force
    Write-Host "  [*] Backed up existing profile to $backupPath" -ForegroundColor Cyan
}

Write-Host ''
Write-Host '  =============================================================' -ForegroundColor Magenta
Write-Host '    WINDOWS SYSTEM TOOLKIT - Setup Wizard                       ' -ForegroundColor Magenta
Write-Host '  =============================================================' -ForegroundColor Magenta
Write-Host ''

# ═══════════════════════════════════════════════════
# AUTO-DETECT (no prompts)
# ═══════════════════════════════════════════════════
Write-Host '  [1/4] Auto-detecting hardware...' -ForegroundColor Yellow
Write-Host "  $('-' * 50)" -ForegroundColor Gray

# Computer name & OS
$config['System']['computerName'] = $env:COMPUTERNAME
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $config['System']['osVersion'] = "$($osInfo.Caption) ($($osInfo.Version))"
} catch { }

# CPU
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
    $config['System']['cpu']['name']              = $cpu.Name
    $config['System']['cpu']['cores']             = $cpu.NumberOfCores
    $config['System']['cpu']['logicalProcessors'] = $cpu.NumberOfLogicalProcessors
    Write-Host "    [+] CPU: $($cpu.Name) ($($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T)" -ForegroundColor Green
} catch {
    Write-Host '    [!] Could not detect CPU' -ForegroundColor Yellow
}

# RAM
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $config['System']['ram']['totalGB'] = $totalGB
    Write-Host "    [+] RAM: $totalGB GB" -ForegroundColor Green
} catch {
    Write-Host '    [!] Could not detect RAM' -ForegroundColor Yellow
}

# GPUs
$gpuList = @()
try {
    $nvidiaSmi = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null
    if ($nvidiaSmi) {
        foreach ($line in $nvidiaSmi) {
            $parts = $line -split ','
            if ($parts.Count -ge 2) {
                $gpuList += @{ name = $parts[0].Trim(); memoryMB = [int]$parts[1].Trim() }
                Write-Host "    [+] GPU: $($parts[0].Trim()) ($($parts[1].Trim()) MB)" -ForegroundColor Green
            }
        }
    }
} catch { }
if ($gpuList.Count -eq 0) {
    try {
        $wmiGpus = Get-CimInstance Win32_VideoController -ErrorAction Stop
        foreach ($g in $wmiGpus) {
            $memMB = [math]::Round($g.AdapterRAM / 1MB, 0)
            $gpuList += @{ name = $g.Name; memoryMB = $memMB }
            Write-Host "    [+] GPU: $($g.Name) ($memMB MB)" -ForegroundColor Green
        }
    } catch { }
}
$config['System']['gpus'] = $gpuList

# Drives
$driveList = @()
try {
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter
    foreach ($vol in $volumes) {
        $sizeGB = [math]::Round($vol.Size / 1GB, 1)
        $driveList += @{ letter = [string]$vol.DriveLetter; label = $vol.FileSystemLabel; sizeGB = $sizeGB }
        Write-Host "    [+] Drive $($vol.DriveLetter): $($vol.FileSystemLabel) ($sizeGB GB)" -ForegroundColor Green
    }
} catch { }
$config['System']['drives'] = $driveList

# Detect installed services
Write-Host ''
Write-Host '  [2/4] Detecting installed services...' -ForegroundColor Yellow
Write-Host "  $('-' * 50)" -ForegroundColor Gray

$knownServices = @(
    @{ name = 'SunshineService'; label = 'Sunshine'; processName = 'sunshine' }
    @{ name = 'Tailscale'; label = 'Tailscale'; processName = 'tailscale' }
    @{ name = 'com.docker.service'; label = 'Docker Desktop'; processName = 'docker' }
    @{ name = 'OllamaService'; label = 'Ollama'; processName = 'ollama' }
)

$detectedServices = @()
foreach ($svc in $knownServices) {
    $installed = $false
    $service = Get-Service -Name $svc.name -ErrorAction SilentlyContinue
    if ($service) { $installed = $true }
    if (-not $installed) {
        $proc = Get-Process -Name "$($svc.processName)*" -ErrorAction SilentlyContinue
        if ($proc) { $installed = $true }
    }
    $existing = $config['Services']['monitoring'] | Where-Object { $_.name -eq $svc.name }
    $enabled = if ($existing) { $existing.enabled } else { $installed }
    $detectedServices += @{
        name        = $svc.name
        label       = $svc.label
        processName = $svc.processName
        enabled     = $enabled
    }
    $statusText = if ($installed) { 'Installed' } else { 'Not found' }
    $color = if ($installed) { 'Green' } else { 'Gray' }
    Write-Host "    [$(if ($installed) {'+' } else {'*'})] $($svc.label): $statusText (enabled=$enabled)" -ForegroundColor $color
}
$config['Services']['monitoring'] = $detectedServices

# WSL detection
$wslAvailable = $false
try {
    $prevEnc = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $wslCheck = wsl --list --quiet 2>$null
    [Console]::OutputEncoding = $prevEnc
    if ($wslCheck) { $wslAvailable = $true }
} catch { }
$config['WSL']['enabled'] = $wslAvailable
$wslStatus = if ($wslAvailable) { 'Available' } else { 'Not available' }
Write-Host "    [$(if ($wslAvailable) {'+' } else {'*'})] WSL: $wslStatus" -ForegroundColor $(if ($wslAvailable) { 'Green' } else { 'Gray' })

if ($DetectOnly) {
    Write-Host ''
    Write-Host '  DetectOnly mode — skipping prompts.' -ForegroundColor Cyan
} elseif ($Auto) {
    Write-Host ''
    Write-Host '  Auto mode — using defaults for all prompts.' -ForegroundColor Cyan
} else {
    # ═══════════════════════════════════════════════════
    # INTERACTIVE PROMPTS
    # ═══════════════════════════════════════════════════
    Write-Host ''
    Write-Host '  [3/4] Configuration preferences...' -ForegroundColor Yellow
    Write-Host "  $('-' * 50)" -ForegroundColor Gray
    Write-Host '  Press Enter to keep current value shown in [brackets].' -ForegroundColor Gray
    Write-Host ''

    # Thresholds
    $input = Read-Host "    CPU temp warning (C) [$($config['Thresholds']['CPU']['temperatureWarning'])]"
    if ($input) { $config['Thresholds']['CPU']['temperatureWarning'] = [int]$input }

    $input = Read-Host "    RAM usage warning (%) [$($config['Thresholds']['RAM']['usageWarning'])]"
    if ($input) { $config['Thresholds']['RAM']['usageWarning'] = [int]$input }

    $input = Read-Host "    GPU temp warning (C) [$($config['Thresholds']['GPU']['temperatureWarning'])]"
    if ($input) { $config['Thresholds']['GPU']['temperatureWarning'] = [int]$input }

    $input = Read-Host "    Disk warning free (%) [$($config['Thresholds']['Disk']['warningFreePercent'])]"
    if ($input) { $config['Thresholds']['Disk']['warningFreePercent'] = [int]$input }

    $input = Read-Host "    Disk critical free (%) [$($config['Thresholds']['Disk']['criticalFreePercent'])]"
    if ($input) { $config['Thresholds']['Disk']['criticalFreePercent'] = [int]$input }

    $input = Read-Host "    Update cache threshold (MB) [$($config['Windows']['updateCache']['sizeThresholdMB'])]"
    if ($input) { $config['Windows']['updateCache']['sizeThresholdMB'] = [int]$input }

    $input = Read-Host "    Defender scan warning (days) [$($config['Windows']['defenderScan']['daysBeforeWarning'])]"
    if ($input) { $config['Windows']['defenderScan']['daysBeforeWarning'] = [int]$input }

    $input = Read-Host "    Log retention (days) [$($config['Logging']['retentionDays'])]"
    if ($input) { $config['Logging']['retentionDays'] = [int]$input }

    # Service toggles
    Write-Host ''
    Write-Host '  Service monitoring (y/n to toggle):' -ForegroundColor Cyan
    for ($i = 0; $i -lt $config['Services']['monitoring'].Count; $i++) {
        $svc = $config['Services']['monitoring'][$i]
        $current = if ($svc.enabled) { 'y' } else { 'n' }
        $input = Read-Host "    Monitor $($svc.label)? [$current]"
        if ($input -eq 'y') { $config['Services']['monitoring'][$i]['enabled'] = $true }
        elseif ($input -eq 'n') { $config['Services']['monitoring'][$i]['enabled'] = $false }
    }

    # Scheduled task times
    Write-Host ''
    Write-Host '  Scheduled task times:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $config['ScheduledTasks']['tasks'].Count; $i++) {
        $task = $config['ScheduledTasks']['tasks'][$i]
        $input = Read-Host "    $($task.name) time [$($task.trigger.time)]"
        if ($input) { $config['ScheduledTasks']['tasks'][$i]['trigger']['time'] = $input }
    }

    # Package managers
    Write-Host ''
    Write-Host '  Package managers (y/n):' -ForegroundColor Cyan
    foreach ($pm in @('winget', 'wsl', 'pip')) {
        $current = if ($config['Packages'][$pm]['enabled']) { 'y' } else { 'n' }
        $input = Read-Host "    Enable $pm updates? [$current]"
        if ($input -eq 'y') { $config['Packages'][$pm]['enabled'] = $true }
        elseif ($input -eq 'n') { $config['Packages'][$pm]['enabled'] = $false }
    }
}

# ═══════════════════════════════════════════════════
# SAVE PROFILE
# ═══════════════════════════════════════════════════
Write-Host ''
Write-Host '  [4/4] Saving profile...' -ForegroundColor Yellow
Write-Host "  $('-' * 50)" -ForegroundColor Gray

$config | ConvertTo-Json -Depth 10 | Set-Content -Path $profilePath -Encoding UTF8
Write-Host "    [+] Profile saved to: $profilePath" -ForegroundColor Green

Write-Host ''
Write-Host '  =============================================================' -ForegroundColor Magenta
Write-Host '    Setup complete! All toolkit scripts will use this profile.  ' -ForegroundColor Magenta
Write-Host '    Re-run Setup.ps1 anytime to update settings.               ' -ForegroundColor Magenta
Write-Host '  =============================================================' -ForegroundColor Magenta
Write-Host ''

if (-not $Auto -and -not $DetectOnly) {
    Write-Host '  Press any key to exit...' -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
