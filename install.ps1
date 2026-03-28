<#
.SYNOPSIS
    Installs Windows System Toolkit to your PATH and sets up tab completion.
.DESCRIPTION
    Adds the toolkit directory to your user PATH so you can run wst.ps1 from
    any directory. Also adds tab completion to your PowerShell profile.
    Does not require Administrator privileges.
.PARAMETER Uninstall
    Remove the toolkit from PATH and profile instead of installing.
.EXAMPLE
    .\install.ps1
    Add toolkit to PATH and set up tab completion.
.EXAMPLE
    .\install.ps1 -Uninstall
    Remove toolkit from PATH and profile.
#>
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$toolkitDir = $PSScriptRoot
$completionScript = Join-Path $toolkitDir "completions\wst.completion.ps1"
$profileLine = ". `"$completionScript`""

Write-Host ""
Write-Host "  Windows System Toolkit - Installer" -ForegroundColor Magenta
Write-Host "  =============================================================" -ForegroundColor Gray
Write-Host ""

if ($Uninstall) {
    # Remove from PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -like "*$toolkitDir*") {
        $newPath = ($currentPath -split ";" | Where-Object { $_ -ne $toolkitDir }) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "    [+] Removed from PATH: $toolkitDir" -ForegroundColor Green
    } else {
        Write-Host "    [*] Not in PATH, nothing to remove" -ForegroundColor Cyan
    }

    # Remove from profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if ((Test-Path $profilePath) -and (Get-Content $profilePath -Raw) -match [regex]::Escape($completionScript)) {
        $content = Get-Content $profilePath | Where-Object { $_ -notmatch [regex]::Escape($completionScript) }
        Set-Content -Path $profilePath -Value $content
        Write-Host "    [+] Removed tab completion from profile" -ForegroundColor Green
    } else {
        Write-Host "    [*] Tab completion not in profile, nothing to remove" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "    Uninstall complete. Restart your terminal for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
    return
}

# --- Add to PATH ---
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -like "*$toolkitDir*") {
    Write-Host "    [*] Already in PATH: $toolkitDir" -ForegroundColor Cyan
} else {
    $newPath = "$currentPath;$toolkitDir"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "    [+] Added to PATH: $toolkitDir" -ForegroundColor Green
    # Also update current session
    $env:Path = "$env:Path;$toolkitDir"
}

# --- Set up tab completion ---
$profilePath = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path $profilePath

if (-not (Test-Path $profileDir)) {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $profilePath)) {
    New-Item -Path $profilePath -ItemType File -Force | Out-Null
    Write-Host "    [+] Created PowerShell profile: $profilePath" -ForegroundColor Green
}

$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if ($profileContent -match [regex]::Escape($completionScript)) {
    Write-Host "    [*] Tab completion already in profile" -ForegroundColor Cyan
} else {
    Add-Content -Path $profilePath -Value "`n# Windows System Toolkit tab completion"
    Add-Content -Path $profilePath -Value $profileLine
    Write-Host "    [+] Added tab completion to profile: $profilePath" -ForegroundColor Green
}

Write-Host ""
Write-Host "    Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "    You can now run from anywhere:" -ForegroundColor Yellow
Write-Host "      wst.ps1 help" -ForegroundColor White
Write-Host "      wst.ps1 monitor" -ForegroundColor White
Write-Host "      wst.ps1 status" -ForegroundColor White
Write-Host ""
Write-Host "    Restart your terminal for PATH changes to take effect." -ForegroundColor Yellow
Write-Host ""
