<#
.SYNOPSIS
    Diagnoses and fixes network stack issues including NLA/NCSI problems.
.DESCRIPTION
    Checks network adapters, route metrics, DHCP/IP configuration,
    protocol bindings, connectivity, and NLA/NCSI status. Can auto-fix
    common issues like stale NLA cache, wrong adapter priority, and
    stuck Wi-Fi. Diagnostics run without admin; fixes require admin.
.PARAMETER Auto
    Run without pausing for user input.
.PARAMETER ReportOnly
    Show diagnostics only, do not apply any fixes.
.PARAMETER FixAll
    Apply all available fixes automatically (requires admin).
.EXAMPLE
    .\Fix-NetworkStack.ps1
    Run diagnostics. Fixes applied only if issues found and admin.
.EXAMPLE
    .\Fix-NetworkStack.ps1 -ReportOnly
    Diagnostic-only mode - safe to run, changes nothing.
.EXAMPLE
    .\Fix-NetworkStack.ps1 -FixAll
    Force all fixes (Ethernet priority, DNS flush, NLA reset, etc).
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$ReportOnly,
    [switch]$FixAll
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

Write-Banner -Title "Network Stack Diagnostics & Fix" -ShowAdminNote

$warnings = 0
$errors = 0
$okCount = 0
$fixes = 0
$totalSteps = 7

# ============================================================
# Step 1: Adapter Inventory
# ============================================================
$step = 1
Write-Step -Step $step -Total $totalSteps -Title "Network Adapter Inventory"

$allAdapters = Get-NetAdapter | Sort-Object Status
foreach ($adapter in $allAdapters) {
    $status = $adapter.Status
    $color = switch ($status) {
        "Up"          { "Green" }
        "Disabled"    { "Gray" }
        "Disconnected" { "Yellow" }
        default       { "Red" }
    }
    $metric = ""
    if ($status -eq "Up") {
        $ipIface = Get-NetIPInterface -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ipIface) { $metric = " | Metric: $($ipIface.InterfaceMetric)" }
    }
    Write-Data "$($adapter.Name) [$($adapter.InterfaceDescription)] - $status - $($adapter.LinkSpeed)$metric"
}

$upAdapters = @($allAdapters | Where-Object { $_.Status -eq "Up" })
Write-Info "$($upAdapters.Count) adapters up, $(@($allAdapters | Where-Object { $_.Status -ne 'Up' }).Count) down/disabled"

# Flag problematic virtual adapters that are Up
$virtualDisruptors = @($upAdapters | Where-Object {
    $_.InterfaceDescription -match "VirtualBox|VMware|Hyper-V Virtual Ethernet Adapter$" -and
    $_.InterfaceDescription -notmatch "Container|WSL"
})
if ($virtualDisruptors.Count -gt 0) {
    foreach ($v in $virtualDisruptors) {
        Write-Warn "Virtual adapter '$($v.Name)' is Up and may disrupt routing"
    }
    $warnings += $virtualDisruptors.Count
} else {
    Write-Good "No problematic virtual adapters detected"
    $okCount++
}

# ============================================================
# Step 2: Route Metric Analysis
# ============================================================
$step = 2
Write-Step -Step $step -Total $totalSteps -Title "Default Route & Metric Analysis"

$defaultRoutes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object { $_.InterfaceMetric + $_.RouteMetric }

if ($defaultRoutes) {
    foreach ($route in $defaultRoutes) {
        $totalMetric = $route.InterfaceMetric + $route.RouteMetric
        Write-Data "$($route.InterfaceAlias) -> $($route.NextHop) (Total metric: $totalMetric)"
    }

    # Check if Ethernet exists and has lowest metric
    $ethernetRoute = $defaultRoutes | Where-Object { $_.InterfaceAlias -eq "Ethernet" }
    $wifiRoute = $defaultRoutes | Where-Object { $_.InterfaceAlias -eq "Wi-Fi" }

    if ($ethernetRoute -and $wifiRoute) {
        $ethMetric = ($ethernetRoute | Select-Object -First 1).InterfaceMetric + ($ethernetRoute | Select-Object -First 1).RouteMetric
        $wifiMetric = ($wifiRoute | Select-Object -First 1).InterfaceMetric + ($wifiRoute | Select-Object -First 1).RouteMetric
        if ($ethMetric -ge $wifiMetric) {
            Write-Warn "Ethernet metric ($ethMetric) >= Wi-Fi metric ($wifiMetric) - Wi-Fi may be preferred over Ethernet"
            $warnings++
        } else {
            Write-Good "Ethernet has priority over Wi-Fi (Eth: $ethMetric, Wi-Fi: $wifiMetric)"
            $okCount++
        }
    } elseif ($ethernetRoute) {
        Write-Good "Ethernet is the only default route"
        $okCount++
    } else {
        Write-Warn "No Ethernet default route found"
        $warnings++
    }
} else {
    Write-Bad "No default routes found - no internet connectivity"
    $errors++
}

# ============================================================
# Step 3: DHCP & IP Configuration
# ============================================================
$step = 3
Write-Step -Step $step -Total $totalSteps -Title "DHCP & IP Configuration"

foreach ($adapterName in @("Ethernet", "Wi-Fi")) {
    $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
    if (-not $adapter) { continue }

    Write-Info "--- $adapterName ---"

    $ipv4 = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $ipv6 = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Where-Object { $_.PrefixOrigin -ne "WellKnown" }
    $dhcp4 = (Get-NetIPInterface -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp
    $dhcp6 = (Get-NetIPInterface -InterfaceAlias $adapterName -AddressFamily IPv6 -ErrorAction SilentlyContinue).Dhcp

    if ($ipv4) {
        $ip = $ipv4.IPAddress
        Write-Data "IPv4: $ip/$($ipv4.PrefixLength) (DHCP: $dhcp4)"

        # Check for APIPA (169.254.x.x) - means DHCP failed
        if ($ip -match "^169\.254\.") {
            Write-Bad "$adapterName has APIPA address ($ip) - DHCP server unreachable"
            $errors++
        } else {
            Write-Good "$adapterName has valid IPv4 address"
            $okCount++
        }
    } else {
        if ($adapter.Status -eq "Up") {
            Write-Bad "$adapterName is Up but has no IPv4 address"
            $errors++
        } else {
            Write-Data "No IPv4 (adapter is $($adapter.Status))"
        }
    }

    if ($ipv6) {
        Write-Data "IPv6: $($ipv6[0].IPAddress) (DHCP: $dhcp6)"
    }

    # DNS check
    $dns = Get-DnsClientServerAddress -InterfaceAlias $adapterName -ErrorAction SilentlyContinue
    $dns4 = ($dns | Where-Object { $_.AddressFamily -eq 2 }).ServerAddresses
    if ($dns4 -and $dns4.Count -gt 0) {
        Write-Data "DNS: $($dns4 -join ', ')"
    } else {
        if ($adapter.Status -eq "Up") {
            Write-Warn "$adapterName has no DNS servers configured"
            $warnings++
        }
    }

    # Gateway check
    $gw = Get-NetRoute -InterfaceAlias $adapterName -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
    if ($gw) {
        Write-Data "Gateway: $($gw.NextHop)"
    } else {
        if ($adapter.Status -eq "Up" -and $ipv4 -and $ipv4.IPAddress -notmatch "^169\.254\.") {
            Write-Warn "$adapterName has no default gateway"
            $warnings++
        }
    }
}

# ============================================================
# Step 4: Protocol Bindings
# ============================================================
$step = 4
Write-Step -Step $step -Total $totalSteps -Title "Protocol Bindings Check"

foreach ($adapterName in @("Ethernet", "Wi-Fi")) {
    $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
    if (-not $adapter) { continue }

    Write-Info "--- $adapterName ---"

    $bindings = Get-NetAdapterBinding -Name $adapterName -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "TCP/IPv4|TCP/IPv6|Client for|File and Printer" }

    foreach ($b in $bindings) {
        $state = if ($b.Enabled) { "[ON]" } else { "[OFF]" }
        if ($b.Enabled) {
            Write-Data "$state $($b.DisplayName)"
        } else {
            Write-Warn "$state $($b.DisplayName) - disabled"
            $warnings++
        }
    }
}

# ============================================================
# Step 5: Connectivity Tests
# ============================================================
$step = 5
Write-Step -Step $step -Total $totalSteps -Title "Connectivity Tests"

# Test gateway ping
$defaultGw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Sort-Object { $_.InterfaceMetric + $_.RouteMetric } | Select-Object -First 1).NextHop

if ($defaultGw) {
    $gwPing = Test-Connection -ComputerName $defaultGw -Count 2 -Quiet -ErrorAction SilentlyContinue
    if ($gwPing) {
        Write-Good "Default gateway ($defaultGw) reachable"
        $okCount++
    } else {
        Write-Bad "Default gateway ($defaultGw) unreachable"
        $errors++
    }
}

# Test internet
$inetPing = Test-Connection -ComputerName 8.8.8.8 -Count 2 -Quiet -ErrorAction SilentlyContinue
if ($inetPing) {
    Write-Good "Internet reachable (8.8.8.8)"
    $okCount++
} else {
    Write-Bad "Internet unreachable (8.8.8.8)"
    $errors++
}

# Test DNS resolution
try {
    $resolved = Resolve-DnsName "google.com" -ErrorAction Stop | Select-Object -First 1
    Write-Good "DNS resolution working (google.com -> $($resolved.IPAddress))"
    $okCount++
} catch {
    Write-Bad "DNS resolution failed for google.com"
    $errors++
}

# Test WiFi to ISP router specifically (if WiFi is up)
$wifiAdapter = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
if ($wifiAdapter -and $wifiAdapter.Status -eq "Up") {
    $wifiIp = (Get-NetIPAddress -InterfaceAlias "Wi-Fi" -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($wifiIp -match "^169\.254\.") {
        Write-Bad "Wi-Fi has APIPA address - ISP router DHCP not responding to this adapter"
        Write-Info "Possible causes:"
        Write-Data "- ISP router MAC filtering or device limit"
        Write-Data "- Stale DHCP lease on ISP router"
        Write-Data "- ISP router needs reboot after outage"
        $errors++
    }
}

# ============================================================
# Step 6: NLA / NCSI Connectivity Detection
# ============================================================
$step = 6
Write-Step -Step $step -Total $totalSteps -Title "NLA / NCSI Connectivity Status"

$nlaIssues = @()
try {
    $connProfiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    foreach ($prof in $connProfiles) {
        $connectivity = $prof.IPv4Connectivity
        $alias = $prof.InterfaceAlias
        Write-Data "${alias}: IPv4=$connectivity | Network=$($prof.Name) | Category=$($prof.NetworkCategory)"

        if ($connectivity -eq "Internet") {
            Write-Good "$alias has internet connectivity (NLA OK)"
            $okCount++
        } elseif ($connectivity -eq "LocalNetwork") {
            Write-Warn "$alias shows LocalNetwork - NLA may be stale or NCSI probe blocked"
            $nlaIssues += $alias
            $warnings++
        } elseif ($connectivity -eq "NoTraffic") {
            # Virtual adapters like Tailscale often show NoTraffic - not a real issue
            if ($alias -notmatch "Tailscale|Loopback|vEthernet") {
                Write-Warn "$alias shows NoTraffic"
                $warnings++
            } else {
                Write-Data "${alias}: NoTraffic (expected for virtual adapter)"
            }
        } else {
            Write-Data "${alias}: $connectivity"
        }
    }
} catch {
    Write-Warn "Could not retrieve NLA connection profiles"
}

# NCSI probe test - this is what Windows uses to determine connectivity
$ncsiUrl = Get-ProfileValue $config "Network.ncsiProbeUrl" "http://www.msftconnecttest.com/connecttest.txt"
$ncsiExpected = Get-ProfileValue $config "Network.ncsiExpectedContent" "Microsoft Connect Test"
try {
    Write-Info "Testing NCSI probe: $ncsiUrl"
    $ncsiResponse = Invoke-WebRequest -Uri $ncsiUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    if ($ncsiResponse.StatusCode -eq 200 -and $ncsiResponse.Content.Trim() -eq $ncsiExpected) {
        Write-Good "NCSI probe successful - internet is reachable"
        $okCount++
        if ($nlaIssues.Count -gt 0) {
            Write-Warn "NLA shows LocalNetwork but NCSI probe works - stale NLA cache detected"
            Write-Info "Fix: Adapter toggle (disable/enable) forces NLA re-detection"
        }
    } else {
        Write-Warn "NCSI probe returned unexpected content (status $($ncsiResponse.StatusCode))"
        Write-Data "Expected: '$ncsiExpected'"
        Write-Data "Got: '$($ncsiResponse.Content.Trim())'"
        $warnings++
    }
} catch {
    Write-Bad "NCSI probe failed: $($_.Exception.Message)"
    Write-Info "Possible causes:"
    Write-Data "- Router/firewall blocking HTTP to msftconnecttest.com"
    Write-Data "- DNS not resolving msftconnecttest.com"
    Write-Data "- No actual internet connectivity"
    $errors++
}

# ============================================================
# Step 7: Automatic Fixes (Admin required)
# ============================================================
$step = 7
Write-Step -Step $step -Total $totalSteps -Title "Automatic Fixes"

if (-not $isAdmin) {
    Write-Warn "Skipping fixes - rerun as Administrator for auto-fix capabilities"
    Write-Info "Fixes available with -FixAll flag (admin):"
    Write-Data "- Set Ethernet as primary adapter (metric 10)"
    Write-Data "- Deprioritize Wi-Fi (metric 50)"
    Write-Data "- Disable disruptive virtual adapters (VirtualBox, VMware)"
    Write-Data "- Re-enable disabled protocol bindings (Client for Microsoft Networks, File and Printer Sharing)"
    Write-Data "- Reset Wi-Fi adapter to recover from DHCP failures"
    Write-Data "- Flush DNS cache"
} elseif ($ReportOnly) {
    Write-Info "Report-only mode - no fixes applied"
} else {
    $needsFix = ($FixAll -or $Auto -or $warnings -gt 0 -or $errors -gt 0)

    if (-not $needsFix) {
        Write-Good "No fixes needed - network stack is healthy"
        $okCount++
    } else {
        # Fix 1: Set Ethernet as primary
        $ethIface = Get-NetIPInterface -InterfaceAlias "Ethernet" -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ethIface -and $ethIface.InterfaceMetric -ne 10) {
            Set-NetIPInterface -InterfaceAlias "Ethernet" -AddressFamily IPv4 -InterfaceMetric 10
            Set-NetIPInterface -InterfaceAlias "Ethernet" -AddressFamily IPv6 -InterfaceMetric 10
            Write-Good "Set Ethernet metric to 10 (highest priority)"
            $fixes++
        }

        # Fix 2: Deprioritize Wi-Fi
        $wifiIface = Get-NetIPInterface -InterfaceAlias "Wi-Fi" -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($wifiIface -and $wifiIface.InterfaceMetric -lt 50) {
            Set-NetIPInterface -InterfaceAlias "Wi-Fi" -AddressFamily IPv4 -InterfaceMetric 50
            Set-NetIPInterface -InterfaceAlias "Wi-Fi" -AddressFamily IPv6 -InterfaceMetric 50
            Write-Good "Set Wi-Fi metric to 50 (lower priority than Ethernet)"
            $fixes++
        }

        # Fix 3: Disable disruptive virtual adapters
        $disruptors = Get-NetAdapter | Where-Object {
            $_.Status -eq "Up" -and
            $_.InterfaceDescription -match "VirtualBox|VMware" -and
            $_.InterfaceDescription -notmatch "Container|WSL"
        }
        foreach ($d in $disruptors) {
            Disable-NetAdapter -Name $d.Name -Confirm:$false
            Write-Good "Disabled disruptive adapter: $($d.Name) [$($d.InterfaceDescription)]"
            $fixes++
        }

        # Fix 4: Re-enable disabled protocol bindings
        foreach ($adapterName in @("Ethernet", "Wi-Fi")) {
            $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
            if (-not $adapter -or $adapter.Status -ne "Up") { continue }

            $disabledBindings = Get-NetAdapterBinding -Name $adapterName -ErrorAction SilentlyContinue |
                Where-Object { -not $_.Enabled -and $_.DisplayName -match "Client for Microsoft Networks|File and Printer Sharing" }

            foreach ($b in $disabledBindings) {
                Enable-NetAdapterBinding -Name $adapterName -DisplayName $b.DisplayName
                Write-Good "Re-enabled '$($b.DisplayName)' on $adapterName"
                $fixes++
            }
        }

        # Fix 5: Reset Wi-Fi if it has APIPA address
        $wifiIp = (Get-NetIPAddress -InterfaceAlias "Wi-Fi" -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        if ($wifiIp -match "^169\.254\.") {
            Write-Info "Wi-Fi has APIPA address - resetting adapter..."
            Disable-NetAdapter -Name "Wi-Fi" -Confirm:$false
            Start-Sleep -Seconds 3
            Enable-NetAdapter -Name "Wi-Fi" -Confirm:$false
            Start-Sleep -Seconds 8

            # Check if it recovered
            $newIp = (Get-NetIPAddress -InterfaceAlias "Wi-Fi" -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            if ($newIp -and $newIp -notmatch "^169\.254\.") {
                Write-Good "Wi-Fi recovered - new IP: $newIp"
                $fixes++
            } else {
                Write-Bad "Wi-Fi still has no valid IP after reset"
                Write-Info "Manual action needed on ISP router:"
                Write-Data "1. Check MAC filtering for: $((Get-NetAdapter -Name 'Wi-Fi').MacAddress)"
                Write-Data "2. Clear DHCP lease table and reboot ISP router"
                Write-Data "3. Check device connection limit"
            }
        }

        # Fix 6: Reset stale NLA via adapter toggle
        if ($nlaIssues.Count -gt 0) {
            foreach ($nlaAdapter in $nlaIssues) {
                # Only toggle physical adapters, not virtual ones
                $adapterObj = Get-NetAdapter -Name $nlaAdapter -ErrorAction SilentlyContinue
                if ($adapterObj -and $adapterObj.InterfaceDescription -notmatch "Tailscale|Loopback|Virtual|vEthernet") {
                    Write-Info "Toggling $nlaAdapter to force NLA re-detection..."
                    Disable-NetAdapter -Name $nlaAdapter -Confirm:$false
                    Start-Sleep -Seconds 3
                    Enable-NetAdapter -Name $nlaAdapter -Confirm:$false
                    Start-Sleep -Seconds 10

                    $newProfile = Get-NetConnectionProfile -InterfaceAlias $nlaAdapter -ErrorAction SilentlyContinue
                    if ($newProfile -and $newProfile.IPv4Connectivity -eq "Internet") {
                        Write-Good "$nlaAdapter NLA recovered - now shows Internet"
                        $fixes++
                    } else {
                        Write-Warn "$nlaAdapter still shows $($newProfile.IPv4Connectivity) after toggle"
                        Write-Info "May need router-level investigation (NCSI probe blocked on port 80)"
                    }
                }
            }
        }

        # Fix 7: Flush DNS
        Clear-DnsClientCache
        Write-Good "Flushed DNS cache"
        $fixes++
    }
}

# ============================================================
# Summary
# ============================================================
Write-Summary -Title "NETWORK STACK SUMMARY" -OK $okCount -Warnings $warnings -Errors $errors -Fixes $fixes -LogPath $logFile

if ($errors -gt 0) {
    Write-Host "    Persistent issues may require:" -ForegroundColor Yellow
    Write-Data "- ISP router reboot / DHCP lease clear"
    Write-Data "- Check ISP router MAC filtering or device limits"
    Write-Data "- Check if router blocks NCSI probe (HTTP to msftconnecttest.com)"
    Write-Host ""
    exit 1
}
exit 0
