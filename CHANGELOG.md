# Changelog

## [2.0.0] - 2026-03-28

### Added
- **lib/Write-Helpers.ps1** — shared output and logging module
  - Write-Step, Write-Good, Write-Bad, Write-Warn, Write-Info, Write-Data functions
  - Write-Banner for consistent script headers
  - Write-Summary for consistent colored summary blocks
  - Initialize-Log for standardized log file creation
  - Test-IsAdmin and Wait-OrExit utilities
- **NLA/NCSI diagnostics** in Fix-NetworkStack.ps1 (new Step 6)
  - Detects stale NLA cache (LocalNetwork when internet works)
  - Tests Windows NCSI probe (msftconnecttest.com/connecttest.txt)
  - Auto-fix: adapter toggle to force NLA re-detection
- **Network connectivity profiles** in Monitor-SystemHealth.ps1
  - Shows Internet/LocalNetwork status per adapter via Get-NetConnectionProfile
  - Warns on LocalNetwork (NLA not detecting internet)
- **Network config defaults** in Load-Profile.ps1
  - NCSI probe URL and expected content (configurable)
  - Adapter priority metrics (Ethernet: 10, Wi-Fi: 50)
- **System-Launcher.bat** improvements
  - "Run All Diagnostics" option (Monitor + Network + Security in sequence)
  - Setup Wizard option added to menu
  - Alphanumeric menu keys (S for Status, L for Logs)
  - Version display in title bar

### Fixed
- **Repair-WindowsHealth.ps1** — `$scanDaysWarn` scoping bug in Defender scan step
  - Variable was defined inside `if ($FullScan)` block but referenced in `elseif`
  - Moved before the conditional so it's always available
- **Update-AllPackages.ps1** — log filename format inconsistency
  - Changed from `HHmmss_scriptname.log` to `scriptname_HHmmss.log` (matches all other scripts)

### Changed
- All scripts refactored to use shared `lib/Write-Helpers.ps1` module
  - Removed ~30 lines of duplicated helper functions from each script
  - Consistent output formatting across all scripts
  - Standardized banner, summary, and exit behavior
- Fix-NetworkStack.ps1 expanded from 6 to 7 steps (NLA/NCSI added)

## [1.1.0] - 2026-03-24

### Added
- Fix-NetworkStack.ps1 — network diagnostics and auto-fix tool
  - Adapter inventory with virtual adapter disruption detection
  - Route metric analysis (Ethernet vs Wi-Fi priority)
  - DHCP & IP configuration audit (detects APIPA/failed leases)
  - Protocol binding checks (IPv4/IPv6, Client for Microsoft Networks)
  - Connectivity tests (gateway, internet, DNS resolution)
  - Auto-fixes (admin): set Ethernet priority, deprioritize Wi-Fi, disable disruptive virtual adapters, reset stuck Wi-Fi, flush DNS
  - ISP router guidance when DHCP issues are beyond local fix

### Changed
- System-Launcher.bat — added Network Stack Fix as option [7], renumbered remaining options

## [1.0.0] - 2026-02-27

### Added
- Monitor-SystemHealth.ps1 — system health dashboard (CPU, RAM, GPU, disk, network, services, WSL)
- Update-AllPackages.ps1 — Winget + WSL apt + pip package updates with exclusion list
- Repair-WindowsHealth.ps1 — DISM, SFC, temp cleanup, Defender scans, disk health
- Harden-Security.ps1 — Sunshine encryption audit, firewall, RDP, SSH, open ports, Tailscale
- Optimize-WSL.ps1 — wsl.conf setup, service optimization, Node.js install via NVM
- Install-ScheduledTasks.ps1 — Task Scheduler automation (daily/weekly/monthly)
- System-Launcher.bat — interactive menu-driven launcher
- WSL helper scripts (update-packages.sh, optimize-services.sh, setup-wsl-conf.sh, install-node.sh)
