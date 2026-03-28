<#
.SYNOPSIS
    One-liner installer for Windows System Toolkit.
.DESCRIPTION
    Downloads and installs the toolkit from GitHub. Run with:
      irm https://raw.githubusercontent.com/Xza85hrf/Windows-System-Toolkit/master/remote-install.ps1 | iex

    Default install location: $HOME\Windows-System-Toolkit
    Override with: $env:WST_INSTALL_DIR = "C:\MyPath" before running.
#>

$ErrorActionPreference = "Stop"

$repo = "Xza85hrf/Windows-System-Toolkit"
$branch = "master"
$defaultDir = Join-Path $HOME "Windows-System-Toolkit"
$installDir = if ($env:WST_INSTALL_DIR) { $env:WST_INSTALL_DIR } else { $defaultDir }
$zipUrl = "https://github.com/$repo/archive/refs/heads/$branch.zip"
$tempZip = Join-Path $env:TEMP "wst-install.zip"
$tempExtract = Join-Path $env:TEMP "wst-extract"

Write-Host ""
Write-Host "  Windows System Toolkit - Remote Installer" -ForegroundColor Magenta
Write-Host "  =============================================================" -ForegroundColor Gray
Write-Host ""
Write-Host "  Source:  github.com/$repo" -ForegroundColor Cyan
Write-Host "  Install: $installDir" -ForegroundColor Cyan
Write-Host ""

# Check if already installed
if (Test-Path (Join-Path $installDir "wst.ps1")) {
    Write-Host "  [!] Toolkit already installed at $installDir" -ForegroundColor Yellow
    Write-Host "  [*] To update, run: cd '$installDir' && git pull" -ForegroundColor Cyan
    Write-Host "  [*] To reinstall, delete the directory first." -ForegroundColor Cyan
    Write-Host ""
    return
}

# Download
Write-Host "  [1/4] Downloading from GitHub..." -ForegroundColor Yellow
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
    Write-Host "    [+] Downloaded" -ForegroundColor Green
} catch {
    Write-Host "    [-] Download failed: $_" -ForegroundColor Red
    Write-Host "    [*] Check your internet connection and try again." -ForegroundColor Cyan
    return
}

# Extract
Write-Host "  [2/4] Extracting..." -ForegroundColor Yellow
try {
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

    # Find the extracted folder (named repo-branch)
    $extracted = Get-ChildItem $tempExtract -Directory | Select-Object -First 1
    if (-not $extracted) { throw "No directory found in archive" }

    # Move to install location
    if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
    $parentDir = Split-Path $installDir
    if (-not (Test-Path $parentDir)) { New-Item -Path $parentDir -ItemType Directory -Force | Out-Null }
    Move-Item -Path $extracted.FullName -Destination $installDir -Force
    Write-Host "    [+] Extracted to $installDir" -ForegroundColor Green
} catch {
    Write-Host "    [-] Extraction failed: $_" -ForegroundColor Red
    return
} finally {
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
}

# Install (PATH + completion)
Write-Host "  [3/4] Setting up PATH and tab completion..." -ForegroundColor Yellow
try {
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$installDir", "User")
        $env:Path = "$env:Path;$installDir"
        Write-Host "    [+] Added to PATH" -ForegroundColor Green
    } else {
        Write-Host "    [*] Already in PATH" -ForegroundColor Cyan
    }

    # Tab completion
    $completionScript = Join-Path $installDir "completions\wst.completion.ps1"
    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path $profilePath
    if (-not (Test-Path $profileDir)) { New-Item -Path $profileDir -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $profilePath)) { New-Item -Path $profilePath -ItemType File -Force | Out-Null }
    $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if (-not $profileContent -or $profileContent -notmatch [regex]::Escape($completionScript)) {
        Add-Content -Path $profilePath -Value "`n# Windows System Toolkit tab completion"
        Add-Content -Path $profilePath -Value ". `"$completionScript`""
        Write-Host "    [+] Tab completion added to profile" -ForegroundColor Green
    }
} catch {
    Write-Host "    [!] PATH setup failed: $_" -ForegroundColor Yellow
    Write-Host "    [*] You can run install.ps1 manually later." -ForegroundColor Cyan
}

# First-run setup
Write-Host "  [4/4] Running hardware detection..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installDir "Setup.ps1") -Auto

Write-Host ""
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host "    Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "    Restart your terminal, then run:" -ForegroundColor Yellow
Write-Host "      wst.ps1 help          " -NoNewline -ForegroundColor White; Write-Host "show all commands" -ForegroundColor Gray
Write-Host "      wst.ps1 monitor       " -NoNewline -ForegroundColor White; Write-Host "system health check" -ForegroundColor Gray
Write-Host "      wst.ps1 status        " -NoNewline -ForegroundColor White; Write-Host "quick overview" -ForegroundColor Gray
Write-Host "      wst.ps1 diag          " -NoNewline -ForegroundColor White; Write-Host "full diagnostics" -ForegroundColor Gray
Write-Host ""
Write-Host "    Installed to: $installDir" -ForegroundColor Gray
Write-Host "  =============================================================" -ForegroundColor Magenta
Write-Host ""
