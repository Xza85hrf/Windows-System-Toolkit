# Security Policy

## Scope

This toolkit runs with Administrator privileges for many operations (DISM, SFC, network adapter changes, scheduled tasks). Security is taken seriously.

## What the Toolkit Does

- **Reads** system state (CPU, RAM, disk, network, services)
- **Modifies** Windows settings only when explicitly requested (network metrics, firewall, temp files)
- **Does not transmit user data.** Two outbound HTTP requests are made,
  both limited to public non-PII endpoints:
  - `Fix-NetworkStack.ps1` probes Microsoft's Network Connectivity
    Status Indicator URL (`http://www.msftconnecttest.com/connecttest.txt`
    by default, overridable via `Network.ncsiProbeUrl` in config) to
    verify internet reachability — same mechanism Windows itself uses.
  - `remote-install.ps1` downloads the toolkit zip from this GitHub
    repo when bootstrapping installation on a fresh machine.
- **Never** stores credentials or secrets
- **Logs** all operations to local files in `logs/`

## Reporting a Vulnerability

If you discover a security issue, please report it responsibly:

1. **Do NOT** open a public issue
2. Email the maintainer or use [GitHub Security Advisories](https://github.com/Xza85hrf/Windows-System-Toolkit/security/advisories/new)
3. Include steps to reproduce and potential impact

## Best Practices for Users

- Review scripts before running with Administrator privileges
- Use `-DryRun` or `-ReportOnly` flags to preview changes
- Keep `config/system-profile.json` in `.gitignore` (it is by default)
- Do not commit `config/*.local.json` files (they may contain secrets)
