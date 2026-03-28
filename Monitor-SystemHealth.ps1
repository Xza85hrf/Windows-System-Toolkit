<#
.SYNOPSIS
    Monitors system health: CPU, RAM, GPU, disk, network, services, and WSL.
.DESCRIPTION
    Runs a comprehensive system health check with color-coded output.
    Does NOT require Administrator privileges. Safe to run anytime.
.PARAMETER Auto
    Run without pausing for user input at the end. Use for scheduled tasks.
.PARAMETER Report
    Save a detailed report to the log file.
.PARAMETER Json
    Output health data as JSON to the console.
.EXAMPLE
    .\Monitor-SystemHealth.ps1
    Interactive mode - pauses at the end for review.
.EXAMPLE
    .\Monitor-SystemHealth.ps1 -Auto -Report
    Automated mode - runs silently and saves a detailed log.
.EXAMPLE
    .\Monitor-SystemHealth.ps1 -Json | ConvertFrom-Json
    Outputs structured health data for scripting.
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$Report,
    [switch]$Json
)
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$null = chcp 65001 2>$null

# --- Load shared modules ---
. (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
. (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
$logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot

$healthData = @{}

Write-Banner -Title "System Health Monitor"

$warnings = 0
$errors = 0
$okCount = 0
$totalSteps = 8

$step = 1
Write-Step -Step $step -Total $totalSteps -Title "CPU Usage & Temperature"
try {
    $cpu = Get-CimInstance Win32_Processor
    $cpuName = $cpu.Name
    $cpuCores = $cpu.NumberOfCores
    $cpuLogical = $cpu.NumberOfLogicalProcessors
    $cpuLoad = $cpu.LoadPercentage
    Write-Data "Processor: $cpuName"
    Write-Data "Cores: $cpuCores | Logical: $cpuLogical | Load: $cpuLoad%"
    $okCount++
    $healthData.CPU = @{
        Name = $cpuName
        Cores = $cpuCores
        Logical = $cpuLogical
        LoadPercentage = $cpuLoad
    }
} catch {
    Write-Warn "Failed to retrieve CPU info"
    $healthData.CPU = $null
}
try {
    $temp = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop
    $celsius = ($temp.CurrentTemperature - 2732) / 10
    Write-Data "Temperature: $([math]::Round($celsius, 1))$([char]176)C"
    $healthData.CPU.Temperature = [math]::Round($celsius, 1)
    $cpuTempWarn = Get-ProfileValue $config "Thresholds.CPU.temperatureWarning" 80
    if ($celsius -gt $cpuTempWarn) {
        Write-Warn "CPU temperature above $cpuTempWarn$([char]176)C"
        $warnings++
    } else {
        Write-Good "CPU temperature OK"
    }
} catch {
    Write-Warn "CPU temperature not available"
    $healthData.CPU.Temperature = $null
}

$step = 2
Write-Step -Step $step -Total $totalSteps -Title "RAM Usage"
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedRAM = $totalRAM - $freeRAM
    $pctUsed = [math]::Round(($usedRAM / $totalRAM) * 100, 1)
    Write-Data "Total: $totalRAM GB"
    Write-Data "Used: $usedRAM GB | Free: $freeRAM GB"
    Write-Data "Usage: $pctUsed%"
    $healthData.RAM = @{
        TotalGB = $totalRAM
        UsedGB = $usedRAM
        FreeGB = $freeRAM
        PercentUsed = $pctUsed
    }
    $ramWarn = Get-ProfileValue $config "Thresholds.RAM.usageWarning" 85
    if ($pctUsed -gt $ramWarn) {
        Write-Warn "RAM usage above $ramWarn%"
        $warnings++
    } else {
        Write-Good "RAM OK"
        $okCount++
    }
} catch {
    Write-Warn "Failed to retrieve RAM info"
    $healthData.RAM = $null
}

$step = 3
Write-Step -Step $step -Total $totalSteps -Title "GPU Temperature & Utilization"
$gpuList = @()
try {
    $nvidiaSmi = & nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null
    if ($nvidiaSmi) {
        foreach ($line in $nvidiaSmi) {
            $parts = $line -split ','
            if ($parts.Count -ge 5) {
                $gpuName = $parts[0].Trim()
                $gpuTemp = [int]$parts[1].Trim()
                $gpuUtil = [int]$parts[2].Trim()
                $gpuMemUsed = [int]$parts[3].Trim()
                $gpuMemTotal = [int]$parts[4].Trim()
                Write-Data "GPU: $gpuName"
                Write-Data "Temp: ${gpuTemp}$([char]176)C | Util: $gpuUtil% | VRAM: $gpuMemUsed/$gpuMemTotal MB"
                $gpuList += @{
                    Name = $gpuName
                    Temperature = $gpuTemp
                    Utilization = $gpuUtil
                    MemoryUsedMB = $gpuMemUsed
                    MemoryTotalMB = $gpuMemTotal
                }
                $gpuTempWarn = Get-ProfileValue $config "Thresholds.GPU.temperatureWarning" 80
                if ($gpuTemp -gt $gpuTempWarn) {
                    Write-Warn "GPU temperature above $gpuTempWarn$([char]176)C"
                    $warnings++
                } else {
                    Write-Good "GPU OK"
                    $okCount++
                }
            }
        }
    } else {
        Write-Warn "NVIDIA GPU monitoring unavailable"
    }
} catch {
    Write-Warn "NVIDIA GPU monitoring unavailable"
}
$healthData.GPU = $gpuList

$step = 4
Write-Step -Step $step -Total $totalSteps -Title "Disk Space"
$diskList = @()
try {
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter
    foreach ($vol in $volumes) {
        $driveLetter = $vol.DriveLetter
        $label = $vol.FileSystemLabel
        $sizeGB = [math]::Round($vol.Size / 1GB, 1)
        $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
        $pctFree = [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1)
        Write-Data "Drive ${driveLetter}: $label | Total: ${sizeGB}GB | Free: ${freeGB}GB ($pctFree%)"
        $diskList += @{
            DriveLetter = $driveLetter
            Label = $label
            SizeGB = $sizeGB
            FreeGB = $freeGB
            PercentFree = $pctFree
        }
        $diskCritical = Get-ProfileValue $config "Thresholds.Disk.criticalFreePercent" 5
        $diskWarn = Get-ProfileValue $config "Thresholds.Disk.warningFreePercent" 10
        if ($pctFree -lt $diskCritical) {
            Write-Bad "CRITICAL"
            $errors++
        } elseif ($pctFree -lt $diskWarn) {
            Write-Warn "LOW"
            $warnings++
        } else {
            Write-Good "OK"
            $okCount++
        }
    }
} catch {
    Write-Warn "Failed to retrieve disk info"
}
$healthData.Disks = $diskList

$step = 5
Write-Step -Step $step -Total $totalSteps -Title "Network Adapters"
$netList = @()
try {
    $adapters = Get-NetAdapter | Where-Object Status -eq 'Up'
    foreach ($adapter in $adapters) {
        $name = $adapter.Name
        $status = $adapter.Status
        $linkSpeed = $adapter.LinkSpeed
        $mac = $adapter.MacAddress
        Write-Data "Adapter: $name | Status: $status | Speed: $linkSpeed | MAC: $mac"
        $netList += @{
            Name = $name
            Status = $status
            LinkSpeed = $linkSpeed
            MacAddress = $mac
        }
        $okCount++
    }
} catch {
    Write-Warn "Failed to retrieve network adapters"
}
# Connection profiles (NLA status)
try {
    $connProfiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    foreach ($prof in $connProfiles) {
        $connectivity = $prof.IPv4Connectivity
        if ($connectivity -eq "Internet") {
            Write-Good "$($prof.InterfaceAlias): $connectivity"
        } elseif ($connectivity -eq "LocalNetwork") {
            Write-Warn "$($prof.InterfaceAlias): $connectivity (NLA not detecting internet)"
            $warnings++
        } else {
            Write-Data "$($prof.InterfaceAlias): $connectivity"
        }
    }
} catch {
    Write-Warn "Could not retrieve connection profiles"
}
$healthData.Network = $netList

$step = 6
Write-Step -Step $step -Total $totalSteps -Title "Key Services"
$serviceList = @()
$servicesToCheck = @()
$configServices = Get-ProfileValue $config "Services.monitoring" @()
foreach ($cs in $configServices) {
    if ($cs.enabled -eq $false) { continue }
    $servicesToCheck += @{ Name = $cs.name; Label = $cs.label; Process = $cs.processName }
}
foreach ($svc in $servicesToCheck) {
    $found = $false
    try {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            $found = $true
            if ($service.Status -eq 'Running') {
                Write-Good "$($svc.Label) is Running"
                $serviceList += @{Name = $svc.Label; Status = "Running"; Type = "Service"}
                $okCount++
            } else {
                Write-Warn "$($svc.Label) is Stopped"
                $serviceList += @{Name = $svc.Label; Status = "Stopped"; Type = "Service"}
                $warnings++
            }
        }
    } catch { }
    if (-not $found -and $svc.Process) {
        $proc = Get-Process -Name "$($svc.Process)*" -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Good "$($svc.Label) is running (process)"
            $serviceList += @{Name = $svc.Label; Status = "Running"; Type = "Process"}
            $okCount++
        } else {
            Write-Data "$($svc.Label) not installed"
            $serviceList += @{Name = $svc.Label; Status = "Not Installed"; Type = "Process"}
        }
    }
}
$healthData.Services = $serviceList

$step = 7
Write-Step -Step $step -Total $totalSteps -Title "WSL Distros"
$wslList = @()
try {
    $rawWsl = (wsl --list --verbose 2>$null | Out-String) -replace "`0", ""
    if ($rawWsl) {
        $lines = $rawWsl -split "`r?`n" | Where-Object { $_.Trim() -ne "" }
        $headerSkipped = $false
        foreach ($line in $lines) {
            if ($line -match "NAME") { $headerSkipped = $true; continue }
            if ($headerSkipped) {
                $clean = $line.TrimStart("* ").Trim()
                $parts = $clean -split "\s{2,}"
                if ($parts.Count -ge 3) {
                    $distroName = $parts[0]
                    $distroState = $parts[1]
                    $distroVersion = $parts[2]
                    Write-Data "Distro: $distroName | State: $distroState | Version: $distroVersion"
                    $wslList += @{
                        Name = $distroName
                        State = $distroState
                        Version = $distroVersion
                    }
                }
            }
        }
        if ($wslList.Count -gt 0) {
            $okCount++
        } else {
            Write-Warn "No WSL distributions found"
        }
    } else {
        Write-Warn "WSL not available"
    }
} catch {
    Write-Warn "WSL not available"
}
$healthData.WSL = $wslList

$step = 8
Write-Step -Step $step -Total $totalSteps -Title "Summary Dashboard"
Write-Summary -Title "SYSTEM HEALTH SUMMARY" -OK $okCount -Warnings $warnings -Errors $errors -LogPath $logFile

if ($Report) { Write-Good "Report saved to: $logFile" }
if ($Json) { $healthData | ConvertTo-Json -Depth 5 }
Wait-OrExit -Auto:$Auto
