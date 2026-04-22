<#
.SYNOPSIS
    Windows System Toolkit - unified command-line interface.
.DESCRIPTION
    Single entry point for all toolkit operations. Use subcommands to run
    specific tools, or run without arguments for an interactive menu.

    Subcommands:
      monitor   - System health dashboard (CPU, RAM, GPU, disk, network)
      update    - Update packages (Winget, WSL apt, pip)
      repair    - Windows health repair (DISM, SFC, cleanup)
      security  - Security audit and hardening
      network   - Network diagnostics and NLA/NCSI fix
      wsl       - WSL2 optimization
      tasks     - Scheduled tasks manager
      setup     - Configuration wizard
      diag      - Run all diagnostics (monitor + network + security)
      status    - Quick system status overview
      logs      - View recent log files
      help      - Show this help message
.PARAMETER Command
    The subcommand to run. If omitted, shows interactive menu.
.PARAMETER Args
    Arguments passed through to the subcommand script.
.EXAMPLE
    .\wst.ps1 monitor
    Run the system health monitor interactively.
.EXAMPLE
    .\wst.ps1 update -DryRun
    Preview package updates without installing.
.EXAMPLE
    .\wst.ps1 repair -QuickOnly
    Quick repair (skip DISM/SFC).
.EXAMPLE
    .\wst.ps1 diag
    Run full diagnostics suite (monitor + network + security).
.EXAMPLE
    .\wst.ps1 status
    Quick overview of system state and config.
.EXAMPLE
    .\wst.ps1 logs -Days 3
    Show logs from the last 3 days.
.EXAMPLE
    .\wst.ps1
    Launch interactive menu.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ArgumentCompleter({
        param($cmd, $param, $word)
        @('monitor','update','repair','security','network','wsl','wslgpu',
          'tasks','setup','diag','status','logs','help') |
            Where-Object { $_ -like "$word*" }
    })]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$PassArgs
)

$ErrorActionPreference = "Continue"
$WST_VERSION = "2.2.0"
$WST_ROOT = $PSScriptRoot

# --- Load shared modules ---
. (Join-Path $WST_ROOT "lib\Load-Profile.ps1")
. (Join-Path $WST_ROOT "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $WST_ROOT "config\system-profile.json")

# ============================================================
# Command map
# ============================================================
$commands = [ordered]@{
    monitor  = @{ Script = "Monitor-SystemHealth.ps1";   Desc = "System health dashboard";           Admin = $false }
    update   = @{ Script = "Update-AllPackages.ps1";     Desc = "Update packages (Winget, apt, pip)"; Admin = $true }
    repair   = @{ Script = "Repair-WindowsHealth.ps1";   Desc = "Windows health repair (DISM, SFC)";  Admin = $true }
    security = @{ Script = "Harden-Security.ps1";        Desc = "Security audit and hardening";       Admin = $true }
    network  = @{ Script = "Fix-NetworkStack.ps1";       Desc = "Network diagnostics and fix";        Admin = $false }
    wsl      = @{ Script = "Optimize-WSL.ps1";           Desc = "WSL2 optimization";                  Admin = $true }
    wslgpu   = @{ Script = "Fix-WSLGPU.ps1";              Desc = "WSL2 GPU passthrough diag/fix";      Admin = $true }
    tasks    = @{ Script = "Install-ScheduledTasks.ps1";  Desc = "Scheduled tasks manager";           Admin = $true }
    setup    = @{ Script = "Setup.ps1";                  Desc = "Configuration wizard";                Admin = $false }
}

# ============================================================
# Helper: Invoke a toolkit script
# ============================================================
function Invoke-ToolkitScript {
    param(
        [string]$ScriptName,
        [string[]]$Arguments,
        [bool]$RequiresAdmin
    )
    $scriptPath = Join-Path $WST_ROOT $ScriptName

    if (-not (Test-Path $scriptPath)) {
        Write-Bad "Script not found: $ScriptName"
        return 1
    }

    $isAdmin = Test-IsAdmin

    if ($RequiresAdmin -and -not $isAdmin) {
        Write-Info "This command requires Administrator privileges. Elevating..."
        $argString = "-ExecutionPolicy Bypass -NoExit -File `"$scriptPath`""
        if ($Arguments) { $argString += " $($Arguments -join ' ')" }
        Start-Process powershell -ArgumentList $argString -Verb RunAs -Wait
        return $LASTEXITCODE
    }

    # Run directly in current session
    $argString = $Arguments -join ' '
    $expression = "& `"$scriptPath`" $argString"
    Invoke-Expression $expression
    return $LASTEXITCODE
}

# ============================================================
# Built-in commands
# ============================================================
function Show-Help {
    Write-Host ""
    Write-Host "  Windows System Toolkit v$WST_VERSION" -ForegroundColor Magenta
    Write-Host "  =============================================================" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    .\wst.ps1 <command> [options]" -ForegroundColor White
    Write-Host "    .\wst.ps1                        " -NoNewline; Write-Host "launch interactive menu" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  COMMANDS:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Diagnostics (no admin needed):" -ForegroundColor Cyan
    Write-Host "      monitor                        " -NoNewline; Write-Host "system health dashboard" -ForegroundColor Gray
    Write-Host "      network                        " -NoNewline; Write-Host "network stack diagnostics" -ForegroundColor Gray
    Write-Host "      diag                           " -NoNewline; Write-Host "run all diagnostics at once" -ForegroundColor Gray
    Write-Host "      status                         " -NoNewline; Write-Host "quick system overview" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Maintenance (admin auto-elevated):" -ForegroundColor Cyan
    Write-Host "      update                         " -NoNewline; Write-Host "update Winget, apt, pip packages" -ForegroundColor Gray
    Write-Host "      repair                         " -NoNewline; Write-Host "DISM, SFC, cleanup, Defender" -ForegroundColor Gray
    Write-Host "      security                       " -NoNewline; Write-Host "security audit and hardening" -ForegroundColor Gray
    Write-Host "      wsl                            " -NoNewline; Write-Host "WSL2 optimization" -ForegroundColor Gray
    Write-Host "      wslgpu                         " -NoNewline; Write-Host "WSL2 GPU passthrough diag and fix" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Administration:" -ForegroundColor Cyan
    Write-Host "      tasks                          " -NoNewline; Write-Host "manage scheduled tasks" -ForegroundColor Gray
    Write-Host "      setup                          " -NoNewline; Write-Host "configure toolkit for your system" -ForegroundColor Gray
    Write-Host "      logs [-Days N]                 " -NoNewline; Write-Host "view recent log files" -ForegroundColor Gray
    Write-Host "      help                           " -NoNewline; Write-Host "show this help message" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  EXAMPLES:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    .\wst.ps1 monitor                " -NoNewline; Write-Host "check system health" -ForegroundColor Gray
    Write-Host "    .\wst.ps1 update -DryRun         " -NoNewline; Write-Host "preview updates" -ForegroundColor Gray
    Write-Host "    .\wst.ps1 repair -QuickOnly      " -NoNewline; Write-Host "fast cleanup, skip DISM/SFC" -ForegroundColor Gray
    Write-Host "    .\wst.ps1 network -FixAll        " -NoNewline; Write-Host "auto-fix network issues" -ForegroundColor Gray
    Write-Host "    .\wst.ps1 security -ReportOnly   " -NoNewline; Write-Host "audit without changing anything" -ForegroundColor Gray
    Write-Host "    .\wst.ps1 diag                   " -NoNewline; Write-Host "full checkup in one shot" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  OPTIONS:" -ForegroundColor Yellow
    Write-Host "    -Auto           skip prompts (for scheduled tasks)" -ForegroundColor Gray
    Write-Host "    -DryRun         preview without changes (update)" -ForegroundColor Gray
    Write-Host "    -QuickOnly      skip slow steps (repair)" -ForegroundColor Gray
    Write-Host "    -ReportOnly     audit only, no fixes (security, network)" -ForegroundColor Gray
    Write-Host "    -FixAll         apply all fixes (network)" -ForegroundColor Gray
    Write-Host "    -Detailed       show extra info (security)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Use Get-Help .\wst.ps1 -Full for complete documentation." -ForegroundColor Gray
    Write-Host ""
}

function Show-Status {
    Write-Host ""
    Write-Host "  Windows System Toolkit v$WST_VERSION" -ForegroundColor Magenta
    Write-Host "  =============================================================" -ForegroundColor Gray
    Write-Host ""

    # System info
    Write-Host "  SYSTEM" -ForegroundColor Yellow
    Write-Host "    Computer:  $env:COMPUTERNAME" -ForegroundColor White
    $isAdmin = Test-IsAdmin
    $adminText = if ($isAdmin) { "Yes" } else { "No" }
    $adminColor = if ($isAdmin) { "Green" } else { "Yellow" }
    Write-Host "    Admin:     " -NoNewline; Write-Host $adminText -ForegroundColor $adminColor
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
        Write-Host "    CPU:       $($cpu.Name)" -ForegroundColor White
    } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $pctUsed = [math]::Round((($totalRAM - $freeRAM) / $totalRAM) * 100)
        $ramColor = if ($pctUsed -gt 85) { "Red" } elseif ($pctUsed -gt 70) { "Yellow" } else { "Green" }
        Write-Host "    RAM:       ${freeRAM}GB free / ${totalRAM}GB (" -NoNewline
        Write-Host "${pctUsed}% used" -ForegroundColor $ramColor -NoNewline
        Write-Host ")" -ForegroundColor White
    } catch { }

    # Disk
    Write-Host ""
    Write-Host "  DISKS" -ForegroundColor Yellow
    try {
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter
        foreach ($vol in $volumes) {
            $pctFree = [math]::Round(($vol.SizeRemaining / $vol.Size) * 100)
            $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
            $diskColor = if ($pctFree -lt 5) { "Red" } elseif ($pctFree -lt 15) { "Yellow" } else { "Green" }
            Write-Host "    $($vol.DriveLetter):  " -NoNewline
            Write-Host "${freeGB}GB free ($pctFree%)" -ForegroundColor $diskColor -NoNewline
            if ($vol.FileSystemLabel) { Write-Host "  [$($vol.FileSystemLabel)]" -ForegroundColor Gray -NoNewline }
            Write-Host ""
        }
    } catch { }

    # Network
    Write-Host ""
    Write-Host "  NETWORK" -ForegroundColor Yellow
    try {
        $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
        foreach ($prof in $profiles) {
            $conn = $prof.IPv4Connectivity
            $connColor = switch ($conn) {
                "Internet"     { "Green" }
                "LocalNetwork" { "Yellow" }
                default        { "Gray" }
            }
            Write-Host "    $($prof.InterfaceAlias):  " -NoNewline
            Write-Host $conn -ForegroundColor $connColor
        }
    } catch {
        Write-Host "    Unable to check" -ForegroundColor Gray
    }

    # Config
    Write-Host ""
    Write-Host "  CONFIG" -ForegroundColor Yellow
    $profilePath = Join-Path $WST_ROOT "config\system-profile.json"
    if (Test-Path $profilePath) {
        $profileAge = [math]::Round(((Get-Date) - (Get-Item $profilePath).LastWriteTime).TotalDays)
        Write-Host "    Profile:   " -NoNewline; Write-Host "Configured" -ForegroundColor Green -NoNewline
        Write-Host " (${profileAge}d ago)" -ForegroundColor Gray
    } else {
        Write-Host "    Profile:   " -NoNewline; Write-Host "Not configured" -ForegroundColor Red -NoNewline
        Write-Host "  run: .\wst.ps1 setup" -ForegroundColor Yellow
    }

    # Last logs
    $logRoot = Join-Path $WST_ROOT "logs"
    if (Test-Path $logRoot) {
        $lastLog = Get-ChildItem $logRoot -Recurse -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($lastLog) {
            $lastRunAge = [math]::Round(((Get-Date) - $lastLog.LastWriteTime).TotalHours, 1)
            Write-Host "    Last run:  $($lastLog.BaseName) (${lastRunAge}h ago)" -ForegroundColor White
        }
    }

    # Scheduled tasks
    Write-Host ""
    Write-Host "  SCHEDULED TASKS" -ForegroundColor Yellow
    $taskNames = @("WST-UpdatePackages", "WST-RepairHealth", "WST-SecurityAudit", "WST-HealthMonitor")
    $anyInstalled = $false
    foreach ($tn in $taskNames) {
        $task = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
        if ($task) {
            $anyInstalled = $true
            $stateColor = switch ($task.State) {
                "Ready"    { "Green" }
                "Running"  { "Cyan" }
                "Disabled" { "Yellow" }
                default    { "Gray" }
            }
            $info = Get-ScheduledTaskInfo -TaskName $tn -ErrorAction SilentlyContinue
            $lastRun = if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) {
                $info.LastRunTime.ToString("yyyy-MM-dd HH:mm")
            } else { "Never" }
            Write-Host "    $tn  " -NoNewline
            Write-Host "$($task.State)" -ForegroundColor $stateColor -NoNewline
            Write-Host "  Last: $lastRun" -ForegroundColor Gray
        }
    }
    if (-not $anyInstalled) {
        Write-Host "    None installed.  " -NoNewline -ForegroundColor Gray
        Write-Host "Run: .\wst.ps1 tasks -Action Install" -ForegroundColor Yellow
    }
    Write-Host ""
}

function Show-Logs {
    param([int]$Days = 7)
    $logRoot = Join-Path $WST_ROOT "logs"

    Write-Host ""
    Write-Host "  Recent Logs (last $Days days)" -ForegroundColor Yellow
    Write-Host "  =============================================================" -ForegroundColor Gray
    Write-Host ""

    if (-not (Test-Path $logRoot)) {
        Write-Host "    No logs found. Run a command first to generate logs." -ForegroundColor Gray
        Write-Host ""
        return
    }

    $cutoff = (Get-Date).AddDays(-$Days)
    $logs = Get-ChildItem $logRoot -Recurse -Filter "*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 20

    if ($logs.Count -eq 0) {
        Write-Host "    No logs in the last $Days days." -ForegroundColor Gray
        Write-Host ""
        return
    }

    Write-Host ("    {0,-18} {1,-35} {2,7} {3,7}" -f "Date", "Script", "Errors", "Warns") -ForegroundColor Cyan
    Write-Host "    $("-" * 70)" -ForegroundColor Gray

    foreach ($log in $logs) {
        $errorCount = @(Select-String '^\[-\]' $log.FullName -ErrorAction SilentlyContinue).Count
        $warnCount = @(Select-String '^\[!\]' $log.FullName -ErrorAction SilentlyContinue).Count
        $dateStr = $log.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        $nameStr = $log.BaseName

        $lineColor = if ($errorCount -gt 0) { "Red" } elseif ($warnCount -gt 0) { "Yellow" } else { "Green" }
        Write-Host ("    {0,-18} {1,-35} {2,7} {3,7}" -f $dateStr, $nameStr, $errorCount, $warnCount) -ForegroundColor $lineColor
    }

    Write-Host ""
    Write-Host "    Log directory: $logRoot" -ForegroundColor Gray
    Write-Host ""
}

function Invoke-AllDiagnostics {
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host "    FULL DIAGNOSTICS SUITE" -ForegroundColor Magenta
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host ""

    Write-Host "  [1/3] System Health Monitor" -ForegroundColor Yellow
    Write-Host "  $("-" * 50)" -ForegroundColor Gray
    Invoke-ToolkitScript -ScriptName "Monitor-SystemHealth.ps1" -Arguments @("-Auto") -RequiresAdmin $false

    Write-Host ""
    Write-Host "  [2/3] Network Stack Diagnostics" -ForegroundColor Yellow
    Write-Host "  $("-" * 50)" -ForegroundColor Gray
    Invoke-ToolkitScript -ScriptName "Fix-NetworkStack.ps1" -Arguments @("-ReportOnly") -RequiresAdmin $false

    Write-Host ""
    Write-Host "  [3/3] Security Audit" -ForegroundColor Yellow
    Write-Host "  $("-" * 50)" -ForegroundColor Gray
    Invoke-ToolkitScript -ScriptName "Harden-Security.ps1" -Arguments @("-ReportOnly") -RequiresAdmin $true

    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host "    All diagnostics complete. Run '.\wst.ps1 logs' to review." -ForegroundColor Magenta
    Write-Host "  =============================================================" -ForegroundColor Magenta
    Write-Host ""
}

function Show-InteractiveMenu {
    # First-run check
    $profilePath = Join-Path $WST_ROOT "config\system-profile.json"
    if (-not (Test-Path $profilePath)) {
        Write-Host ""
        Write-Host "  =============================================================" -ForegroundColor Magenta
        Write-Host "    Welcome to Windows System Toolkit!" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "    First-time setup: detecting your hardware..." -ForegroundColor Yellow
        Write-Host "  =============================================================" -ForegroundColor Magenta
        Write-Host ""
        Invoke-ToolkitScript -ScriptName "Setup.ps1" -Arguments @() -RequiresAdmin $false
        Write-Host ""
        Write-Host "  Setup complete! Showing main menu..." -ForegroundColor Green
        Start-Sleep -Seconds 2
    }

    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Magenta
        Write-Host "  |     WINDOWS SYSTEM TOOLKIT  v$WST_VERSION                        |" -ForegroundColor Magenta
        Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Magenta
        Write-Host ""

        # Quick status line
        $isAdmin = Test-IsAdmin
        $adminTag = if ($isAdmin) { "[Admin]" } else { "[User]" }
        $adminColor = if ($isAdmin) { "Green" } else { "Yellow" }
        $configTag = if (Test-Path $profilePath) { "Configured" } else { "Not configured" }
        $configColor = if (Test-Path $profilePath) { "Green" } else { "Red" }
        Write-Host "    " -NoNewline
        Write-Host $adminTag -ForegroundColor $adminColor -NoNewline
        Write-Host "  Config: " -NoNewline -ForegroundColor Gray
        Write-Host $configTag -ForegroundColor $configColor -NoNewline
        Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Gray
        Write-Host ""

        Write-Host "    Diagnostics" -ForegroundColor Cyan
        Write-Host "      [1]  Monitor System Health" -ForegroundColor White
        Write-Host "      [2]  Network Diagnostics" -ForegroundColor White
        Write-Host "      [3]  Run All Diagnostics" -ForegroundColor White
        Write-Host ""
        Write-Host "    Maintenance" -ForegroundColor Cyan
        Write-Host "      [4]  Update All Packages" -ForegroundColor White
        Write-Host "      [5]  Repair Windows Health" -ForegroundColor White
        Write-Host ""
        Write-Host "    Security & Config" -ForegroundColor Cyan
        Write-Host "      [6]  Security Audit" -ForegroundColor White
        Write-Host "      [7]  Optimize WSL2" -ForegroundColor White
        Write-Host "      [8]  Scheduled Tasks" -ForegroundColor White
        Write-Host "      [9]  Setup Wizard" -ForegroundColor White
        Write-Host ""
        Write-Host "    Tools" -ForegroundColor Cyan
        Write-Host "      [G]  WSL2 GPU Passthrough Fix" -ForegroundColor White
        Write-Host "      [S]  System Status" -ForegroundColor White
        Write-Host "      [L]  View Logs" -ForegroundColor White
        Write-Host "      [0]  Exit" -ForegroundColor White
        Write-Host ""

        $choice = Read-Host "    Select"

        switch ($choice) {
            "1" { Invoke-ToolkitScript "Monitor-SystemHealth.ps1" @() $false }
            "2" { Invoke-ToolkitScript "Fix-NetworkStack.ps1" @() $false }
            "3" { Invoke-AllDiagnostics }
            "4" { Invoke-ToolkitScript "Update-AllPackages.ps1" @() $true }
            "5" { Invoke-ToolkitScript "Repair-WindowsHealth.ps1" @() $true }
            "6" { Invoke-ToolkitScript "Harden-Security.ps1" @() $true }
            "7" { Invoke-ToolkitScript "Optimize-WSL.ps1" @() $true }
            "8" { Invoke-ToolkitScript "Install-ScheduledTasks.ps1" @() $true }
            "9" { Invoke-ToolkitScript "Setup.ps1" @() $false }
            { $_ -eq "G" -or $_ -eq "g" } { Invoke-ToolkitScript "Fix-WSLGPU.ps1" @() $true }
            { $_ -eq "S" -or $_ -eq "s" } { Show-Status }
            { $_ -eq "L" -or $_ -eq "l" } { Show-Logs }
            "0" { Write-Host ""; Write-Host "  Goodbye!" -ForegroundColor Magenta; Write-Host ""; return }
            default {
                Write-Host ""
                Write-Host "    Invalid option: '$choice'" -ForegroundColor Red
            }
        }

        if ($choice -ne "0") {
            Write-Host ""
            Write-Host "  Press any key to return to menu..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}

# ============================================================
# Main dispatch
# ============================================================
if (-not $Command) {
    Show-InteractiveMenu
    exit 0
}

switch ($Command.ToLower()) {
    "help"     { Show-Help; exit 0 }
    "status"   { Show-Status; exit 0 }
    "logs"     {
        $days = 7
        if ($PassArgs -and $PassArgs.Count -ge 2) {
            for ($i = 0; $i -lt $PassArgs.Count; $i++) {
                if ($PassArgs[$i] -eq "-Days" -and ($i + 1) -lt $PassArgs.Count) {
                    $days = [int]$PassArgs[$i + 1]
                }
            }
        }
        Show-Logs -Days $days
        exit 0
    }
    "diag"     { Invoke-AllDiagnostics; exit 0 }
    default {
        if ($commands.Contains($Command.ToLower())) {
            $cmd = $commands[$Command.ToLower()]
            $exitCode = Invoke-ToolkitScript -ScriptName $cmd.Script -Arguments $PassArgs -RequiresAdmin $cmd.Admin
            exit $exitCode
        } else {
            Write-Host ""
            Write-Host "  Unknown command: '$Command'" -ForegroundColor Red
            Write-Host "  Run '.\wst.ps1 help' for available commands." -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }
    }
}
