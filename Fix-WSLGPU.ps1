<#
.SYNOPSIS
    Diagnoses and fixes WSL2 GPU passthrough for NVIDIA hardware.
.DESCRIPTION
    Checks the Windows NVIDIA driver, WSL2 version, .wslconfig, /dev/dxg
    device, CUDA libraries, PyTorch CUDA visibility, and the NVIDIA display
    service. Applies fixes for common issues: missing gpuSupport in
    .wslconfig, excessive WSL memory allocation that exhausts GPU BAR
    mapping, missing LD_LIBRARY_PATH entry for WSL CUDA libs, and stopped
    NVIDIA services. Diagnostics run without admin; fixes require admin.
.PARAMETER Auto
    Run without pausing for user input.
.PARAMETER ReportOnly
    Show diagnostics only, do not apply any fixes.
.PARAMETER FixAll
    Apply all available fixes without prompting (requires admin).
.PARAMETER QuickTest
    Short path - only verifies nvidia-smi on Windows, in WSL2, and PyTorch
    CUDA visibility. Skips full diagnostics.
.EXAMPLE
    .\Fix-WSLGPU.ps1
    Run diagnostics and prompt before applying fixes.
.EXAMPLE
    .\Fix-WSLGPU.ps1 -ReportOnly
    Diagnostic-only mode - safe to run, changes nothing.
.EXAMPLE
    .\Fix-WSLGPU.ps1 -FixAll
    Apply every recommended fix without prompting.
.EXAMPLE
    .\Fix-WSLGPU.ps1 -QuickTest
    Quick GPU visibility test (Windows, WSL2, PyTorch).
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$ReportOnly,
    [switch]$FixAll,
    [switch]$QuickTest
)
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$null = chcp 65001 2>$null

# --- Load shared modules ---
. (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
. (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
$logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot

$isAdmin = Test-IsAdmin

Write-Banner -Title "WSL2 GPU Passthrough Diagnostics & Fix" -ShowAdminNote

# ============================================================
# Quick test mode - short-circuit with visibility checks only
# ============================================================
if ($QuickTest) {
    Write-Step -Step 1 -Total 3 -Title "Windows nvidia-smi"
    $winSmi = & nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>$null
    if ($LASTEXITCODE -eq 0 -and $winSmi) {
        $gpus = @($winSmi -split "`n" | Where-Object { $_ -match "\S" })
        Write-Good "nvidia-smi on Windows works ($($gpus.Count) GPU(s))"
        foreach ($g in $gpus) { Write-Data $g.Trim() }
    } else {
        Write-Bad "nvidia-smi failed on Windows side"
        Write-Info "Install or repair the NVIDIA driver, then re-run."
        exit 1
    }

    Write-Step -Step 2 -Total 3 -Title "WSL2 nvidia-smi"
    $wslSmi = & wsl -e nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>$null
    if ($LASTEXITCODE -eq 0 -and $wslSmi) {
        $gpus = @($wslSmi -split "`n" | Where-Object { $_ -match "\S" })
        Write-Good "nvidia-smi inside WSL2 works ($($gpus.Count) GPU(s))"
        foreach ($g in $gpus) { Write-Data $g.Trim() }
    } else {
        Write-Bad "nvidia-smi failed inside WSL2"
        Write-Info "Re-run without -QuickTest for full diagnostics."
        exit 1
    }

    Write-Step -Step 3 -Total 3 -Title "PyTorch CUDA in WSL2"
    $pyOut = & wsl -e python3 -c "import torch; avail=torch.cuda.is_available(); devs=torch.cuda.device_count(); print(f'cuda_available={avail}, devices={devs}'); [print(f'  GPU {i}: {torch.cuda.get_device_name(i)}') for i in range(devs)]" 2>&1 | Out-String
    if ($pyOut -match "cuda_available=True") {
        Write-Good "PyTorch sees CUDA GPUs"
        $pyOut -split "`n" | Where-Object { $_ -match "\S" } | ForEach-Object { Write-Data $_.Trim() }
    } elseif ($pyOut -match "cuda_available=False") {
        Write-Bad "PyTorch installed but CUDA not available"
        Write-Info "Re-run without -QuickTest to identify the cause."
        exit 1
    } else {
        Write-Warn "PyTorch not installed or CUDA check failed"
        $preview = $pyOut.Trim()
        if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) }
        Write-Data $preview
    }

    Write-Summary -Title "QUICK TEST COMPLETE" -OK 3 -Warnings 0 -Errors 0 -LogPath $logFile
    Wait-OrExit -Auto:$Auto
    exit 0
}

# ============================================================
# Full diagnostics
# ============================================================
$warnings = 0
$errors = 0
$okCount = 0
$fixes = 0
$totalSteps = 7
$issues = @()

# ------------------------------------------------------------
# Step 1: Windows NVIDIA Driver
# ------------------------------------------------------------
$step = 1
Write-Step -Step $step -Total $totalSteps -Title "Windows NVIDIA Driver"

$winSmi = $null
try {
    $winSmi = & nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>$null
    if ($LASTEXITCODE -eq 0 -and $winSmi) {
        $gpus = @($winSmi -split "`n" | Where-Object { $_ -match "\S" })
        Write-Good "nvidia-smi works ($($gpus.Count) GPU(s) detected)"
        $okCount++
        foreach ($gpu in $gpus) { Write-Data $gpu.Trim() }

        $driverVersion = ($gpus[0] -split ",")[1].Trim()
        $majorVersion = [int]($driverVersion -split "\.")[0]
        if ($majorVersion -ge 525) {
            Write-Good "Driver version $driverVersion (>= 525.60 required for WSL2)"
            $okCount++
        } else {
            Write-Bad "Driver version $driverVersion is too old (need >= 525.60)"
            Write-Info "Download latest driver from https://www.nvidia.com/Download/index.aspx"
            $issues += "DRIVER_OLD"
            $errors++
        }
    } else {
        Write-Bad "nvidia-smi failed or returned empty output"
        Write-Info "Install the NVIDIA driver before continuing."
        $issues += "NO_DRIVER"
        $errors++
    }
} catch {
    Write-Bad "nvidia-smi not found - NVIDIA driver not installed"
    Write-Info "Download from https://www.nvidia.com/Download/index.aspx"
    $issues += "NO_DRIVER"
    $errors++
}

# ------------------------------------------------------------
# Step 2: WSL2 Version
# ------------------------------------------------------------
$step = 2
Write-Step -Step $step -Total $totalSteps -Title "WSL2 Version"

$prevEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::Unicode
$wslVersion = & wsl --version 2>$null
[Console]::OutputEncoding = $prevEncoding

if ($wslVersion) {
    $versionLines = @($wslVersion -split "`n" | Where-Object { $_ -match "\S" } | ForEach-Object { ($_ -replace "\x00", "").Trim() })
    foreach ($line in $versionLines) { Write-Data $line }
    $kernelLine = $versionLines | Where-Object { $_ -match "[Kk]ernel" } | Select-Object -First 1
    if ($kernelLine) {
        Write-Good "WSL2 kernel detected"
        $okCount++
    } else {
        Write-Warn "Could not identify WSL2 kernel line"
        $warnings++
    }
} else {
    Write-Bad "Could not get WSL version - is WSL2 installed?"
    Write-Info "Run: wsl --install"
    $issues += "WSL_VERSION"
    $errors++
}

Write-Info "Checking for WSL updates..."
$updateCheck = & wsl --update --web-download 2>&1 | Out-String
if ($updateCheck -match "No updates") {
    Write-Good "WSL is up to date"
    $okCount++
} elseif ($updateCheck -match "Downloading") {
    Write-Warn "WSL update available - restart required after fix"
    $issues += "WSL_UPDATED"
    $warnings++
} else {
    $preview = $updateCheck.Trim()
    if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) }
    if ($preview) { Write-Data $preview }
}

# ------------------------------------------------------------
# Step 3: .wslconfig
# ------------------------------------------------------------
$step = 3
Write-Step -Step $step -Total $totalSteps -Title ".wslconfig"

$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$haveWslConfig = Test-Path $wslConfigPath
if ($haveWslConfig) {
    $wslConfig = Get-Content $wslConfigPath -Raw
    Write-Good "Found $wslConfigPath"
    $okCount++
    Write-Info "Current contents:"
    Get-Content $wslConfigPath | ForEach-Object { Write-Data $_ }

    if ($wslConfig -match "nestedVirtualization\s*=\s*true") {
        Write-Warn "nestedVirtualization=true can conflict with GPU passthrough"
        $issues += "NESTED_VIRT"
        $warnings++
    }

    if ($wslConfig -notmatch "gpuSupport") {
        Write-Warn "gpuSupport not explicitly set (defaults to true, but explicit is safer)"
        $issues += "NO_GPU_SUPPORT"
        $warnings++
    } elseif ($wslConfig -match "gpuSupport\s*=\s*false") {
        Write-Bad "gpuSupport=false - GPU is explicitly disabled"
        Write-Info "Fix will set gpuSupport=true"
        $issues += "GPU_DISABLED"
        $errors++
    } else {
        Write-Good "gpuSupport explicitly enabled"
        $okCount++
    }

    if ($wslConfig -match "memory\s*=\s*(\d+)GB") {
        $memGB = [int]$Matches[1]
        if ($memGB -gt 128) {
            Write-Warn "memory=${memGB}GB is very high - can exhaust GPU BAR mapping"
            $issues += "HIGH_MEMORY"
            $warnings++
        } else {
            Write-Good "memory=${memGB}GB is within safe range"
            $okCount++
        }
    }
} else {
    Write-Warn "No .wslconfig found at $wslConfigPath"
    Write-Info "Fix will create one with gpuSupport=true"
    $issues += "NO_WSLCONFIG"
    $warnings++
}

# ------------------------------------------------------------
# Step 4: WSL2 GPU Device
# ------------------------------------------------------------
$step = 4
Write-Step -Step $step -Total $totalSteps -Title "WSL2 GPU Device Check"

$dxgCheck = & wsl -e sh -c "ls -la /dev/dxg 2>&1" 2>$null
if ($dxgCheck -match "No such file") {
    Write-Bad "/dev/dxg does not exist - GPU passthrough broken"
    Write-Info "Common causes: stale .wslconfig, old kernel, nestedVirtualization=true"
    $issues += "NO_DXG"
    $errors++
} elseif ($dxgCheck) {
    Write-Good "/dev/dxg present"
    Write-Data $dxgCheck.Trim()
    $okCount++
} else {
    Write-Warn "Could not probe /dev/dxg (WSL not running?)"
    $warnings++
}

$nvdevCheck = & wsl -e sh -c "ls /dev/nvidia* 2>&1" 2>$null
if ($nvdevCheck -match "No such file" -or $nvdevCheck -match "no matches") {
    Write-Info "/dev/nvidia* devices not present (normal for WSL2 - uses /dev/dxg)"
} elseif ($nvdevCheck) {
    Write-Data "NVIDIA char devices: $nvdevCheck"
}

$wslNvidiaSmi = & wsl -e nvidia-smi 2>&1 | Out-String
if ($wslNvidiaSmi -match "blocked") {
    Write-Bad "WSL2: GPU access blocked by the operating system"
    Write-Info "Driver/kernel mismatch - update both Windows driver and WSL kernel"
    $issues += "GPU_BLOCKED"
    $errors++
} elseif ($wslNvidiaSmi -match "NVIDIA-SMI") {
    Write-Good "WSL2: nvidia-smi works"
    $okCount++
    $wslNvidiaSmi -split "`n" | Select-Object -First 6 | ForEach-Object { if ($_.Trim()) { Write-Data $_.Trim() } }
} else {
    Write-Bad "WSL2: nvidia-smi failed"
    $preview = $wslNvidiaSmi.Trim()
    if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) }
    if ($preview) { Write-Data $preview }
    $issues += "WSL_NVIDIA_FAIL"
    $errors++
}

# ------------------------------------------------------------
# Step 5: CUDA Libraries in WSL2
# ------------------------------------------------------------
$step = 5
Write-Step -Step $step -Total $totalSteps -Title "CUDA Libraries in WSL2"

$cudaLibs = & wsl -e sh -c "ls /usr/lib/wsl/lib/libcuda.so* 2>&1" 2>$null
if ($cudaLibs -match "libcuda.so") {
    Write-Good "CUDA libraries present in /usr/lib/wsl/lib/"
    $okCount++
} else {
    Write-Bad "CUDA libraries missing from /usr/lib/wsl/lib/"
    Write-Info "This folder is auto-populated by the Windows driver - reinstall it"
    $issues += "NO_CUDA_LIBS"
    $errors++
}

$ldPath = & wsl -e sh -c 'echo $LD_LIBRARY_PATH' 2>$null
if ($ldPath -match "/usr/lib/wsl/lib") {
    Write-Good "LD_LIBRARY_PATH includes /usr/lib/wsl/lib"
    $okCount++
} else {
    Write-Warn "LD_LIBRARY_PATH missing /usr/lib/wsl/lib"
    Write-Info "Fix will add it to ~/.bashrc and ~/.zshrc"
    $issues += "LD_PATH_MISSING"
    $warnings++
}

# ------------------------------------------------------------
# Step 6: PyTorch CUDA check
# ------------------------------------------------------------
$step = 6
Write-Step -Step $step -Total $totalSteps -Title "PyTorch CUDA in WSL2"

$pytorchCheck = & wsl -e python3 -c "import torch; print(f'torch={torch.__version__}, cuda={torch.cuda.is_available()}, devices={torch.cuda.device_count()}')" 2>$null
if ($pytorchCheck -match "cuda=True") {
    Write-Good "PyTorch sees CUDA: $pytorchCheck"
    $okCount++
    $gpuList = & wsl -e python3 -c "import torch; [print(f'  GPU {i}: {torch.cuda.get_device_name(i)} ({torch.cuda.get_device_properties(i).total_mem // 1024**3}GB)') for i in range(torch.cuda.device_count())]" 2>$null
    if ($gpuList) {
        $gpuList -split "`n" | Where-Object { $_ -match "\S" } | ForEach-Object { Write-Data $_.Trim() }
    }
} elseif ($pytorchCheck -match "cuda=False") {
    Write-Bad "PyTorch installed but CUDA not available: $pytorchCheck"
    Write-Info "Install the CUDA build: pip install torch --index-url https://download.pytorch.org/whl/cu121"
    $issues += "PYTORCH_NO_CUDA"
    $errors++
} else {
    Write-Warn "PyTorch not installed or check failed (non-fatal)"
    $warnings++
}

# ------------------------------------------------------------
# Step 7: Windows GPU services
# ------------------------------------------------------------
$step = 7
Write-Step -Step $step -Total $totalSteps -Title "Windows GPU Services"

$nvService = Get-Service -Name "NVDisplay.ContainerLocalSystem" -ErrorAction SilentlyContinue
if ($nvService) {
    if ($nvService.Status -eq "Running") {
        Write-Good "NVIDIA Display Container: Running"
        $okCount++
    } else {
        Write-Bad "NVIDIA Display Container: $($nvService.Status)"
        Write-Info "Fix will start the service"
        $issues += "NV_SERVICE_DOWN"
        $errors++
    }
} else {
    Write-Warn "NVIDIA Display Container service not found"
    $warnings++
}

$hypervCheck = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
if ($hypervCheck -and $hypervCheck.State -eq "Enabled") {
    Write-Info "Hyper-V is enabled (normal for WSL2)"
}

# ============================================================
# Apply fixes
# ============================================================
$needsRestart = $false

if ($ReportOnly) {
    if ($issues.Count -gt 0) {
        Write-Host ""
        Write-Host "    ReportOnly mode - $($issues.Count) issue(s) detected, no fixes applied." -ForegroundColor Yellow
    }
} elseif ($issues.Count -gt 0) {
    if (-not $isAdmin -and -not $FixAll) {
        Write-Host ""
        Write-Warn "Fixes require Administrator privileges"
        Write-Info "Re-run from an elevated shell, or use 'wst.ps1 wslgpu' which auto-elevates"
    } else {
        Write-Host ""
        Write-Step -Step 0 -Total 0 -Title "Applying Fixes"

        # Fix: .wslconfig GPU support / memory
        if ($issues -contains "NO_WSLCONFIG" -or $issues -contains "NO_GPU_SUPPORT" -or
            $issues -contains "GPU_DISABLED" -or $issues -contains "HIGH_MEMORY") {

            if ($haveWslConfig) {
                $backup = "$wslConfigPath.bak"
                Copy-Item $wslConfigPath $backup -Force
                Write-Info "Backed up existing config to $backup"
            }

            $cfg = if ($haveWslConfig) { Get-Content $wslConfigPath -Raw } else { "" }

            if ($cfg -notmatch "\[wsl2\]") {
                $cfg = "[wsl2]`r`n" + $cfg
            }

            if ($cfg -match "gpuSupport\s*=") {
                $cfg = $cfg -replace "gpuSupport\s*=\s*\w+", "gpuSupport=true"
            } else {
                $cfg = $cfg -replace "(\[wsl2\])", "`$1`r`ngpuSupport=true"
            }

            if ($issues -contains "HIGH_MEMORY") {
                $cfg = $cfg -replace "memory\s*=\s*\d+GB", "memory=64GB"
                Write-Info "Reduced WSL memory to 64GB to avoid GPU BAR exhaustion"
            }

            $cfg | Set-Content $wslConfigPath -Encoding UTF8
            Write-Good "Updated $wslConfigPath"
            $fixes++
            Get-Content $wslConfigPath | ForEach-Object { Write-Data $_ }
            $needsRestart = $true
        }

        # Fix: LD_LIBRARY_PATH in WSL shell configs
        if ($issues -contains "LD_PATH_MISSING") {
            $ldExport = 'export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH'
            & wsl -e sh -c "grep -q '/usr/lib/wsl/lib' ~/.bashrc 2>/dev/null || echo '$ldExport' >> ~/.bashrc"
            & wsl -e sh -c "grep -q '/usr/lib/wsl/lib' ~/.zshrc 2>/dev/null || echo '$ldExport' >> ~/.zshrc"
            Write-Good "Added /usr/lib/wsl/lib to LD_LIBRARY_PATH in ~/.bashrc and ~/.zshrc"
            $fixes++
        }

        # Fix: restart NVIDIA service
        if ($issues -contains "NV_SERVICE_DOWN") {
            try {
                Start-Service "NVDisplay.ContainerLocalSystem" -ErrorAction Stop
                Write-Good "Started NVIDIA Display Container service"
                $fixes++
            } catch {
                Write-Bad "Could not start NVIDIA Display Container service: $($_.Exception.Message)"
                Write-Info "Try restarting Windows and running this script again."
            }
        }

        # Driver guidance (manual)
        if ($issues -contains "NO_DRIVER" -or $issues -contains "DRIVER_OLD") {
            Write-Host ""
            Write-Warn "MANUAL ACTION REQUIRED: install or update the NVIDIA driver"
            Write-Data "Download: https://www.nvidia.com/Download/index.aspx"
            Write-Data "Pick your GPU, Windows, Game Ready or Studio driver, install, re-run."
        }

        # Restart WSL if config changed
        if ($needsRestart) {
            $doRestart = $FixAll
            if (-not $doRestart -and -not $Auto) {
                Write-Host ""
                $ans = Read-Host "    Restart WSL now to apply changes? (y/n)"
                if ($ans -eq "y") { $doRestart = $true }
            }
            if ($doRestart) {
                Write-Info "Shutting down WSL..."
                & wsl --shutdown
                Start-Sleep -Seconds 3
                Write-Good "WSL shut down - it will restart on next wsl command"
                $fixes++

                Write-Step -Step 0 -Total 0 -Title "Post-Fix Verification"
                Start-Sleep -Seconds 2
                $postCheck = & wsl -e nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>&1 | Out-String
                if ($postCheck -match "blocked" -or $postCheck -match "Failed") {
                    Write-Bad "GPU still not accessible after fix"
                    Write-Info "Try a full Windows restart, then re-run with -QuickTest"
                    $errors++
                } else {
                    Write-Good "GPU accessible after fix"
                    $okCount++
                    $postCheck -split "`n" | Where-Object { $_ -match "\S" } | ForEach-Object { Write-Data $_.Trim() }
                }
            } else {
                Write-Info "Run 'wsl --shutdown' manually when ready to apply changes."
            }
        }
    }
}

# ============================================================
# Summary
# ============================================================
Write-Summary -Title "WSL2 GPU SUMMARY" -OK $okCount -Warnings $warnings -Errors $errors -Fixes $fixes -LogPath $logFile

Wait-OrExit -Auto:$Auto

if ($errors -gt 0) { exit 1 }
exit 0
