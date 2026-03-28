# Windows System Toolkit

[![CI](https://github.com/Xza85hrf/Windows-System-Toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/Xza85hrf/Windows-System-Toolkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)

Comprehensive Windows 11 system maintenance, security hardening, and automation toolkit with a unified CLI.

## Install

**One-liner** (no download needed):
```powershell
irm https://raw.githubusercontent.com/Xza85hrf/Windows-System-Toolkit/master/remote-install.ps1 | iex
```

**Scoop**:
```powershell
scoop bucket add wst https://github.com/Xza85hrf/Windows-System-Toolkit
scoop install wst
```

**Git clone**:
```powershell
git clone https://github.com/Xza85hrf/Windows-System-Toolkit.git
cd Windows-System-Toolkit
.\install.ps1    # adds to PATH + tab completion
.\wst.ps1 setup  # auto-detect hardware
```

**Manual**: [Download ZIP](https://github.com/Xza85hrf/Windows-System-Toolkit/archive/refs/heads/master.zip), extract, run `wst.ps1`.

## Quick Start

```powershell
wst.ps1 monitor       # system health check
wst.ps1 diag          # full diagnostics suite
wst.ps1 status        # instant system overview
wst.ps1 help          # all commands
```

Or double-click **System-Launcher.bat** for an interactive menu.

## What It Looks Like

**`.\wst.ps1 status`** - instant system overview:
```
  SYSTEM
    Computer:  MYPC
    Admin:     No
    CPU:       AMD Ryzen 9 7950X 16-Core Processor
    RAM:       72.9GB free / 191.2GB (62% used)

  DISKS
    C:  1938GB free (52%)    D:  4985GB free (67%)

  NETWORK
    Ethernet:  Internet

  CONFIG
    Profile:   Configured (0d ago)
    Last run:  Monitor-SystemHealth (0.2h ago)
```

**`.\wst.ps1 monitor`** - full health dashboard:
```
  Step 1 of 8 : CPU Usage & Temperature
  --------------------------------------------------
      Processor: AMD Ryzen 9 7950X (16C/32T) | Load: 12%
    [+] CPU temperature OK

  Step 3 of 8 : GPU Temperature & Utilization
  --------------------------------------------------
      GPU: NVIDIA GeForce RTX 5060 Ti
      Temp: 42C | Util: 11% | VRAM: 15961/16311 MB
    [+] GPU OK

  Step 5 of 8 : Network Adapters
  --------------------------------------------------
    [+] Ethernet: Internet
    [!] Tailscale: LocalNetwork (NLA not detecting internet)

  SYSTEM HEALTH SUMMARY
    [!]  OK: 18  |  Warnings: 2  |  Errors: 0
```

**`.\wst.ps1 help`** - all commands at a glance:
```
  USAGE:
    .\wst.ps1 <command> [options]

  COMMANDS:
    Diagnostics (no admin needed):
      monitor       system health dashboard
      network       network stack diagnostics
      diag          run all diagnostics at once
      status        quick system overview

    Maintenance (admin auto-elevated):
      update        update Winget, apt, pip packages
      repair        DISM, SFC, cleanup, Defender
      security      security audit and hardening
```

## Commands

| Command | Description | Admin |
|---------|-------------|-------|
| `wst monitor` | System health dashboard (CPU, RAM, GPU, disk, network) | No |
| `wst network` | Network diagnostics, NLA/NCSI detection, auto-fix | No* |
| `wst diag` | Run all diagnostics at once | No* |
| `wst status` | Quick system overview | No |
| `wst update` | Update Winget + WSL apt + pip packages | Yes |
| `wst repair` | DISM, SFC, temp cleanup, Defender scans | Yes |
| `wst security` | Security audit (firewall, RDP, SSH, ports) | Yes |
| `wst wsl` | WSL2 optimization and configuration | Yes |
| `wst tasks` | Manage scheduled maintenance tasks | Yes |
| `wst setup` | Configuration wizard (hardware detection) | No |
| `wst logs` | View recent logs with error/warning counts | No |
| `wst help` | Show all commands and options | No |

*\*Auto-elevates to admin when fixes are needed.*

## Common Options

```powershell
.\wst.ps1 update -DryRun          # Preview updates without installing
.\wst.ps1 repair -QuickOnly       # Skip DISM/SFC, just cleanup
.\wst.ps1 security -ReportOnly    # Audit only, change nothing
.\wst.ps1 network -FixAll         # Apply all network fixes
.\wst.ps1 security -Detailed      # Extra verbose output
.\wst.ps1 monitor -Auto -Report   # Scheduled task mode
```

Every script supports `Get-Help`:
```powershell
Get-Help .\wst.ps1 -Full
Get-Help .\Monitor-SystemHealth.ps1 -Examples
```

## Features

- **Color-coded output** — Green = OK, Yellow = Warning, Red = Error
- **Automatic logging** — All runs saved to `logs/YYYY-MM-DD/`
- **Smart elevation** — Admin commands auto-elevate via UAC
- **First-run detection** — Setup wizard runs automatically on first use
- **Config-driven** — JSON profile with auto-detection and customizable thresholds
- **Progress feedback** — Long operations (DISM, SFC) show live progress
- **Actionable errors** — Every error tells you what to do next

## Requirements

- Windows 11 (or Windows 10 with PowerShell 5.1+)
- Administrator access for maintenance and fix commands
- WSL2 with Ubuntu (optional, for WSL optimization)

## Architecture

```
wst.ps1                      # Unified CLI entry point
System-Launcher.bat          # Double-click launcher (calls wst.ps1)
Setup.ps1                    # Configuration wizard
│
├── Monitor-SystemHealth.ps1 # Health dashboard
├── Update-AllPackages.ps1   # Package updates
├── Repair-WindowsHealth.ps1 # System repair
├── Harden-Security.ps1      # Security audit
├── Optimize-WSL.ps1         # WSL optimization
├── Fix-NetworkStack.ps1     # Network diagnostics
├── Install-ScheduledTasks.ps1 # Task scheduler
│
├── lib/
│   ├── Load-Profile.ps1     # Config loader (JSON + defaults)
│   └── Write-Helpers.ps1    # Shared output/logging helpers
├── config/
│   ├── system-profile.json  # Machine profile (gitignored, auto-generated)
│   └── excluded-packages.json # Packages to skip during updates
├── wsl/                     # WSL helper scripts
└── logs/                    # Auto-organized by date
```

## Scheduled Tasks

```powershell
# Install automated maintenance
.\wst.ps1 tasks -Action Install

# Check task status
.\wst.ps1 tasks
```

| Task | Runs | Time |
|------|------|------|
| WST-UpdatePackages | Daily | 3 AM |
| WST-RepairHealth | Weekly (Sun) | 4 AM |
| WST-SecurityAudit | Monthly | 2 AM |
| WST-HealthMonitor | Daily | 8 AM |

## Contributing

Contributions welcome. Open an issue or submit a PR.

## License

MIT License. See [LICENSE](LICENSE) for details.
