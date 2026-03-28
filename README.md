# Windows-System-Toolkit

Comprehensive Windows 11 system maintenance, security hardening, and automation toolkit.

## Features

- **System Health Monitoring** — CPU, RAM, GPU, disk, network, services dashboard
- **Package Updates** — Winget + WSL apt + pip update automation
- **Windows Health Repair** — DISM, SFC, temp cleanup, Defender scans
- **Security Hardening** — Sunshine encryption, firewall audit, open ports, SSH keys
- **WSL Optimization** — wsl.conf setup, service optimization, Node.js install
- **Network Stack Fix** — Adapter inventory, route metrics, DHCP, NLA/NCSI diagnostics, auto-fix
- **Scheduled Tasks** — Automated daily/weekly/monthly maintenance
- **Run All Diagnostics** — One-click health + network + security audit

## Quick Start

1. Double-click `System-Launcher.bat` for the interactive menu
2. Or run individual scripts in PowerShell (Admin for most):
   ```powershell
   # No admin needed
   .\Monitor-SystemHealth.ps1

   # Admin required
   .\Update-AllPackages.ps1 -Auto
   .\Repair-WindowsHealth.ps1 -Auto
   .\Harden-Security.ps1 -ReportOnly
   .\Optimize-WSL.ps1 -InstallNode
   .\Fix-NetworkStack.ps1 -FixAll        # Admin for fixes, no admin for diagnostics
   .\Install-ScheduledTasks.ps1 -Action Install

   # First-time setup
   .\Setup.ps1
   ```

## Requirements

- Windows 11 Pro
- PowerShell 5.1+
- Administrator access (for most scripts)
- WSL2 with Ubuntu (for WSL scripts)

## Architecture

```
System-Launcher.bat          # Interactive menu (entry point)
Setup.ps1                    # Configuration wizard
├── lib/
│   ├── Load-Profile.ps1     # Config loader (JSON profile + defaults)
│   └── Write-Helpers.ps1    # Shared output/logging helpers
├── config/
│   └── system-profile.json  # Machine-specific profile (gitignored)
├── wsl/                     # WSL helper scripts
└── logs/                    # Organized by date (auto-cleaned)
```

## Scheduled Tasks

| Task | Script | Frequency | Time |
|------|--------|-----------|------|
| WST-UpdatePackages | Update-AllPackages.ps1 | Daily | 3 AM |
| WST-RepairHealth | Repair-WindowsHealth.ps1 | Weekly (Sun) | 4 AM |
| WST-SecurityAudit | Harden-Security.ps1 | Monthly (1st) | 2 AM |
| WST-HealthMonitor | Monitor-SystemHealth.ps1 | Daily | 8 AM |

## Contributing

Contributions welcome. Open an issue or submit a PR.

## License

MIT License. See [LICENSE](LICENSE) for details.
