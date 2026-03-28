# Contributing

Thanks for your interest in Windows System Toolkit!

## How to Contribute

1. **Fork** the repo
2. **Clone** your fork: `git clone https://github.com/YOUR-USERNAME/Windows-System-Toolkit`
3. **Create a branch**: `git checkout -b my-feature`
4. **Make changes** and test locally
5. **Run tests**: `Invoke-Pester -Path ./tests`
6. **Commit**: `git commit -m "feat: description of change"`
7. **Push**: `git push origin my-feature`
8. **Open a PR** against `master`

## Code Style

- PowerShell 5.1 compatible (no PS7+ features)
- Use shared helpers from `lib/Write-Helpers.ps1` (Write-Good, Write-Bad, etc.)
- Use `lib/Load-Profile.ps1` for configuration access
- Add comment-based help (`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`) to new scripts
- Follow existing patterns for logging and error handling

## Adding a New Script

1. Create `Your-Script.ps1` in the root directory
2. Use the standard header:
   ```powershell
   . (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
   . (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
   $config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
   $logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot
   ```
3. Add it to the `$commands` map in `wst.ps1`
4. Add a test in `tests/Toolkit.Tests.ps1`
5. Update `README.md` and `CHANGELOG.md`

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` new features
- `fix:` bug fixes
- `docs:` documentation
- `test:` tests
- `chore:` maintenance

## Reporting Issues

Use the [issue templates](https://github.com/Xza85hrf/Windows-System-Toolkit/issues/new/choose) for bug reports and feature requests.
