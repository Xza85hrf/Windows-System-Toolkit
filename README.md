# Windows System Toolkit

Comprehensive Windows 11 system maintenance, security hardening, and automation toolkit with a unified CLI.

## Quick Start

```powershell
# First run — auto-detects your hardware
.\wst.ps1 setup

# Check system health
.\wst.ps1 monitor

# Full diagnostics (health + network + security)
.\wst.ps1 diag

# Quick system overview
.\wst.ps1 status
```

Or double-click **System-Launcher.bat** for an interactive menu.

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
