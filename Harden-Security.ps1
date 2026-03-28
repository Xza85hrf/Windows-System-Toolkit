<#
.SYNOPSIS
    Audits system security: firewall, RDP, SSH, open ports, and more.
.DESCRIPTION
    Performs a comprehensive security audit including Sunshine encryption,
    firewall profiles, RDP/NLA, SSH keys, open ports, Tailscale, and
    Windows Defender status. Requires Administrator privileges.
.PARAMETER Auto
    Run without pausing for user input. Use for scheduled tasks.
.PARAMETER FixSunshine
    Automatically fix insecure Sunshine encryption settings.
.PARAMETER ReportOnly
    Generate a report without applying any fixes.
.PARAMETER Detailed
    Show extra details (Tailscale peers, Defender timestamps, etc).
.EXAMPLE
    .\Harden-Security.ps1 -ReportOnly
    Audit-only mode - shows issues without changing anything.
.EXAMPLE
    .\Harden-Security.ps1 -FixSunshine
    Audit and automatically fix Sunshine encryption settings.
.EXAMPLE
    .\Harden-Security.ps1 -Detailed
    Verbose audit with extended information.
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$FixSunshine,
    [switch]$ReportOnly,
    [switch]$Detailed
)
$ErrorActionPreference = "Continue"

# --- Load shared modules ---
. (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
. (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
$logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot

if (-not (Test-IsAdmin)) {
    Write-Banner -Title "Security Audit and Hardening"
    Write-Bad "This script requires Administrator privileges."
    Write-Info "Right-click PowerShell and select 'Run as Administrator', then re-run this script."
    exit 2
}

$criticalCount = 0
$warningCount = 0
$okCount = 0
$totalSteps = 10

Write-Banner -Title "Security Audit and Hardening"
Add-Content -Path $logFile -Value "=== Harden-Security Audit Started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

Write-Step -Step 1 -Total $totalSteps -Title "Sunshine Encryption Audit"
$sunshineConf = Get-ProfileValue $config "Paths.SunshineConfig" (Join-Path $env:ProgramFiles "Sunshine\config\sunshine.conf")
if (Test-Path $sunshineConf) {
    try {
        $content = Get-Content $sunshineConf -Raw
        if ($content -match 'wan_encryption_mode\s*=\s*(\d+)') { $wanEnc = [int]$matches[1] }
        if ($content -match 'lan_encryption_mode\s*=\s*(\d+)') { $lanEnc = [int]$matches[1] }
        if ($null -ne $wanEnc) {
            if ($wanEnc -eq 0) { Write-Bad "CRITICAL: wan_encryption_mode is disabled (0)"; $criticalCount++ }
            else { Write-Good "wan_encryption_mode is set to $wanEnc"; $okCount++ }
        }
        if ($null -ne $lanEnc) {
            if ($lanEnc -eq 0) { Write-Warn "lan_encryption_mode is disabled (0)"; $warningCount++ }
            else { Write-Good "lan_encryption_mode is set to $lanEnc"; $okCount++ }
        }
        if ($FixSunshine -and -not $ReportOnly -and ($wanEnc -eq 0 -or $lanEnc -eq 0)) {
            $backup = "$sunshineConf.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $sunshineConf $backup -Force
            $newContent = $content
            if ($wanEnc -eq 0) { $newContent = $newContent -replace 'wan_encryption_mode\s*=\s*\d+', 'wan_encryption_mode = 2' }
            if ($lanEnc -eq 0) { $newContent = $newContent -replace 'lan_encryption_mode\s*=\s*\d+', 'lan_encryption_mode = 1' }
            Set-Content -Path $sunshineConf -Value $newContent -Force
            Write-Good "Applied encryption fix, backed up to $backup"
        }
    } catch { Write-Warn "Failed to parse sunshine.conf: $_" }
} else { Write-Info "Sunshine not installed at $sunshineConf" }

Write-Step -Step 2 -Total $totalSteps -Title "Sunshine WebUI Binding"
if (Test-Path $sunshineConf) {
    try {
        $content = Get-Content $sunshineConf -Raw
        if ($content -match 'address\s*=\s*([^\s#]+)') {
            $addr = $matches[1].Trim()
            if ($addr -eq "0.0.0.0") { Write-Warn "Sunshine WebUI bound to 0.0.0.0 (all interfaces)"; $warningCount++ }
            else { Write-Good "Sunshine WebUI bound to $addr"; $okCount++ }
        } else { Write-Info "No address binding found in sunshine.conf" }
    } catch { Write-Warn "Failed to parse address binding: $_" }
}

Write-Step -Step 3 -Total $totalSteps -Title "Sunshine Firewall Rules"
$rules = Get-NetFirewallRule -DisplayName "*Sunshine*" -ErrorAction SilentlyContinue
if ($rules) {
    foreach ($rule in $rules) {
        $profile = ($rule | Get-NetFirewallProfile).Name -join ", "
        if ($profile -match "Public") { Write-Warn "Firewall rule '$($rule.DisplayName)' enabled on Public profile"; $warningCount++ }
        else { Write-Good "Firewall rule '$($rule.DisplayName)' profiles: $profile"; $okCount++ }
    }
} else { Write-Info "No Sunshine firewall rules found" }

Write-Step -Step 4 -Total $totalSteps -Title "Windows Defender Status"
try {
    $def = Get-MpComputerStatus -ErrorAction Stop
    if ($def.AntivirusEnabled) { Write-Good "Antivirus Enabled: True"; $okCount++ }
    else { Write-Bad "Antivirus Enabled: False"; $criticalCount++ }
    if ($def.RealTimeProtectionEnabled) { Write-Good "Real-Time Protection: Enabled"; $okCount++ }
    else { Write-Warn "Real-Time Protection: Disabled"; $warningCount++ }
    $sigAge = $def.AntivirusSignatureAge
    $sigMaxAge = Get-ProfileValue $config "Windows.defenderSignature.maxAgeDays" 7
    if ($sigAge -le $sigMaxAge) { Write-Good "Signature Age: $sigAge days"; $okCount++ }
    else { Write-Warn "Signature Age: $sigAge days (older than $sigMaxAge days)"; $warningCount++ }
    if ($Detailed) { Write-Data "Antivirus Last Scan: $($def.AntivirusLastScanTimestamp)" }
} catch { Write-Warn "Could not retrieve Windows Defender status: $_" }

Write-Step -Step 5 -Total $totalSteps -Title "RDP Security"
try {
    $rdpReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -ErrorAction Stop
    if ($rdpReg.fDenyTSConnections -eq 0) { Write-Good "RDP is enabled (fDenyTSConnections=0)"; $okCount++ }
    else { Write-Info "RDP is disabled (fDenyTSConnections=1)" }
    $auth = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -ErrorAction Stop
    if ($auth.UserAuthentication -eq 1) { Write-Good "Network Level Authentication (NLA) is required"; $okCount++ }
    else { Write-Bad "Network Level Authentication (NLA) is NOT required"; $criticalCount++ }
} catch { Write-Warn "Could not check RDP settings: $_" }

Write-Step -Step 6 -Total $totalSteps -Title "Firewall Profiles"
$profiles = Get-NetFirewallProfile
foreach ($p in $profiles) {
    if ($p.Enabled) { Write-Good "$($p.Name) firewall enabled"; $okCount++ }
    else { Write-Bad "$($p.Name) firewall disabled"; $criticalCount++ }
}

Write-Step -Step 7 -Total $totalSteps -Title "SSH Keys Audit"
$sshDir = Join-Path $env:USERPROFILE ".ssh"
if (Test-Path $sshDir) {
    $keys = Get-ChildItem $sshDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(pem|pub|key)$' -or $_.Name -match '^id_' }
    if ($keys) {
        Write-Good "Found $($keys.Count) SSH key(s) in $sshDir"
        foreach ($k in $keys) { Write-Data "$($k.Name) - LastWriteTime: $($k.LastWriteTime)" }
    } else { Write-Warn "No SSH key files found in $sshDir"; $warningCount++ }
} else { Write-Info "No .ssh directory found for user" }

Write-Step -Step 8 -Total $totalSteps -Title "Open Ports Audit"
$listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
$grouped = $listeners | Group-Object -Property LocalAddress
$zeroBind = $false
foreach ($g in $grouped) {
    if ($g.Name -eq "0.0.0.0") {
        $zeroBind = $true
        $ports = $g.Group | Select-Object -ExpandProperty LocalPort
        Write-Warn "Listening on 0.0.0.0: $($ports -join ', ')"
    }
}
if ($zeroBind) { $warningCount++ }
$byProc = $listeners | Group-Object -Property OwningProcess
foreach ($pg in $byProc) {
    $proc = Get-Process -Id $pg.Name -ErrorAction SilentlyContinue
    $procName = if ($proc) { $proc.ProcessName } else { "Unknown" }
    $ports = ($pg.Group | Select-Object -ExpandProperty LocalPort) -join ", "
    Write-Data "PID $procName ($($pg.Name)): $ports"
}
Write-Good "Found $($listeners.Count) listening ports"

Write-Step -Step 9 -Total $totalSteps -Title "Tailscale Status"
try {
    $ts = tailscale status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Good "Tailscale is running"
        if ($Detailed) {
            $tsLines = $ts -split "`n" | Select-Object -First 10
            foreach ($line in $tsLines) { Write-Data $line }
        }
        $okCount++
    } else { Write-Warn "Tailscale command failed or not running"; $warningCount++ }
} catch { Write-Info "Tailscale not installed or not in PATH" }

Write-Step -Step 10 -Total $totalSteps -Title "Security Report - Summary"
Write-Summary -Title "SECURITY AUDIT SUMMARY" -OK $okCount -Warnings $warningCount -Errors $criticalCount -LogPath $logFile

if ($criticalCount -gt 0) {
    Write-Bad "ACTION REQUIRED: Address critical issues immediately."
}
if ($warningCount -gt 0) {
    Write-Warn "Review warnings for recommended improvements."
}

Wait-OrExit -Auto:$Auto
Add-Content -Path $logFile -Value "=== Audit Completed: Critical=$criticalCount, Warnings=$warningCount, Passed=$okCount ==="
