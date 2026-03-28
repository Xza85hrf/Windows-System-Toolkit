[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$InstallNode,
    [switch]$SetupCron,
    [switch]$ReportOnly
)
$ErrorActionPreference = "Continue"

# --- Load shared modules ---
. (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
. (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
$logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot

Write-Banner -Title "Optimize WSL2"

if (-not (Test-IsAdmin)) {
    Write-Bad "This script must be run as Administrator."
    exit 1
}
Write-Good "Administrator privileges confirmed."

$totalSteps = 8
$wslConfCreated = $false
$defaultDistro = $null

# Step 1
Write-Step -Step 1 -Total $totalSteps -Title "Detect WSL Distros"
# wsl.exe --list outputs UTF-16LE; temporarily set console encoding so PowerShell decodes it correctly
$prevEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::Unicode
$wslRaw = wsl --list --verbose 2>$null
[Console]::OutputEncoding = $prevEncoding

if ($LASTEXITCODE -ne 0 -or $wslRaw -eq $null) {
    Write-Bad "WSL is not installed or not responding."
    exit 1
}
$wslRaw | ForEach-Object { Write-Data $_ }

$distros = @()
$lines = $wslRaw -split "`n"
foreach ($line in $lines) {
    $line = $line.Trim()
    if ($line -match "^\*") {
        $parts = ($line -replace "^\*\s*", "") -split "\s+"
        $parts = $parts | Where-Object { $_ -ne "" }
        if ($parts.Count -ge 3) {
            $defaultDistro = $parts[0]
            $distros += [PSCustomObject]@{ Name = $parts[0]; State = $parts[1]; Version = $parts[2]; Default = $true }
            Write-Good "Default Distro: $defaultDistro"
        }
    } elseif ($line -match "^\S" -and $line -notmatch "^NAME") {
        $parts = $line -split "\s+"
        $parts = $parts | Where-Object { $_ -ne "" }
        if ($parts.Count -ge 3) {
            $distros += [PSCustomObject]@{ Name = $parts[0]; State = $parts[1]; Version = $parts[2]; Default = $false }
        }
    }
}

if (-not $defaultDistro) {
    Write-Warn "No default distro marked with *. Attempting to use first available."
    if ($distros.Count -gt 0) {
        $defaultDistro = $distros[0].Name
    }
}

if (-not $defaultDistro) {
    Write-Bad "No WSL distros found."
    exit 1
}

# Step 2
Write-Step -Step 2 -Total $totalSteps -Title "Setup wsl.conf"
$wslScript = Join-Path $PSScriptRoot "wsl" "setup-wsl-conf.sh"
$wslConfCheck = wsl -d $defaultDistro test -f /etc/wsl.conf 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Good "wsl.conf already configured"
} else {
    if (-not $ReportOnly) {
        if (Test-Path $wslScript) {
            Write-Info "Running setup script: $wslScript"
            $wslScriptContent = Get-Content $wslScript -Raw
            $tempScript = "/tmp/setup-wsl-conf.sh"
            wsl -d $defaultDistro sh -c "echo '$wslScriptContent' > $tempScript"
            wsl -d $defaultDistro sh $tempScript
            $wslConfCreated = $true
            Write-Good "wsl.conf created/updated. Restart required."
        } else {
            Write-Warn "Setup script not found at $wslScript"
        }
    } else {
        Write-Warn "wsl.conf missing. (ReportOnly mode)"
    }
}

# Step 3
Write-Step -Step 3 -Total $totalSteps -Title "WSL Kernel Version"
$kernelVer = wsl -d $defaultDistro uname -r
Write-Data "Kernel: $kernelVer"
if ($kernelVer -match "^(\d+)\.(\d+)\.(\d+)") {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $minMajor = Get-ProfileValue $config "WSL.kernel.minimumMajor" 5
    $minMinor = Get-ProfileValue $config "WSL.kernel.minimumMinor" 15
    if ($major -lt $minMajor -or ($major -eq $minMajor -and $minor -lt $minMinor)) {
        Write-Warn "Kernel version is old (< $minMajor.$minMinor). Consider running 'wsl --update'."
    } else {
        Write-Good "Kernel version is recent."
    }
}

# Step 4
Write-Step -Step 4 -Total $totalSteps -Title "WSL Disk Usage"
$dfOutput = wsl -d $defaultDistro df -h /
Write-Data $dfOutput
$dfLine = ($dfOutput -split "`n" | Where-Object { $_ -match "/dev/sd" -or $_ -match "/dev/root" }) | Select-Object -First 1
if ($dfLine -match "(\d+)%") {
    $usage = [int]$Matches[1]
    $wslDiskWarn = Get-ProfileValue $config "WSL.disk.usageWarning" 80
    if ($usage -gt $wslDiskWarn) {
        Write-Warn "Disk usage inside WSL is above $wslDiskWarn%."
    } else {
        Write-Good "Disk usage is healthy."
    }
}

Write-Info "Checking Windows side vhdx size..."
$vhdxPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
if (Test-Path $vhdxPath) {
    Get-ChildItem -Path $vhdxPath -Filter "*.vhdx" -ErrorAction SilentlyContinue | ForEach-Object {
        $sizeGB = [math]::Round($_.Length / 1GB, 2)
        Write-Data "$($_.Name): $sizeGB GB"
    }
}

# Step 5
Write-Step -Step 5 -Total $totalSteps -Title "Optimize Services"
$svcScript = Join-Path $PSScriptRoot "wsl" "optimize-services.sh"
if (-not $ReportOnly) {
    if (Test-Path $svcScript) {
        Write-Info "Running service optimization..."
        $svcContent = Get-Content $svcScript -Raw
        wsl -d $defaultDistro sh -c $svcContent
        Write-Good "Service optimization complete."
    } else {
        Write-Warn "Service script not found: $svcScript"
    }
} else {
    Write-Info "Service optimization skipped (ReportOnly)."
}

# Step 6
Write-Step -Step 6 -Total $totalSteps -Title "Install Node.js"
if ($InstallNode) {
    $nodeScript = Join-Path $PSScriptRoot "wsl" "install-node.sh"
    if (Test-Path $nodeScript) {
        Write-Info "Running Node.js install script..."
        $nodeContent = Get-Content $nodeScript -Raw
        wsl -d $defaultDistro sh -c $nodeContent
        Write-Good "Node.js installation complete."
    } else {
        Write-Warn "Node install script not found: $nodeScript"
    }
} else {
    Write-Info "Node.js install skipped (use -InstallNode to enable)"
}

# Step 7
Write-Step -Step 7 -Total $totalSteps -Title "Review .wslconfig"
$wslconfig = Join-Path $env:USERPROFILE ".wslconfig"
if (Test-Path $wslconfig) {
    Write-Good ".wslconfig found at $wslconfig"
    Write-Data "--- Current Configuration ---"
    Get-Content $wslconfig | ForEach-Object { Write-Data $_ }
    Write-Data "----------------------------"
} else {
    Write-Info "No .wslconfig found at $wslconfig"
    Write-Info "Suggestion: Create a .wslconfig in your user profile to limit memory/CPU (e.g., memory=4GB, processors=2)"
}

# Step 8
Write-Step -Step 8 -Total $totalSteps -Title "Summary"
Write-Good "Optimization check completed."
if ($wslConfCreated) {
    Write-Warn "WSL restart required for wsl.conf changes: Run 'wsl --shutdown' in PowerShell"
}

Write-Host ""
Write-Info "Log saved to: $logFile"
Wait-OrExit -Auto:$Auto
