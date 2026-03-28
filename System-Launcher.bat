@echo off
setlocal enabledelayedexpansion
title Windows System Toolkit v2.0.0
color 0F

REM ============================================================
REM First-run detection
REM ============================================================
if not exist "%~dp0config\system-profile.json" (
    cls
    echo.
    echo   =============================================================
    echo.
    echo     Welcome to Windows System Toolkit!
    echo.
    echo     This appears to be your first run.
    echo     The Setup Wizard will now auto-detect your hardware
    echo     and configure the toolkit for your system.
    echo.
    echo   =============================================================
    echo.
    pause
    powershell -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
    echo.
    echo   Setup complete! Launching main menu...
    timeout /t 2 >nul
)

:MENU
cls
echo.
echo   +-------------------------------------------------------------+
echo   ^|                                                             ^|
echo   ^|         WINDOWS SYSTEM TOOLKIT  v2.0.0                     ^|
echo   ^|         System Maintenance ^& Automation                    ^|
echo   ^|                                                             ^|
echo   +-------------------------------------------------------------+
echo.

REM Show config status
if exist "%~dp0config\system-profile.json" (
    echo   Status: Configured
) else (
    echo   Status: NOT CONFIGURED - run [S] Setup Wizard first
)

REM Show last log date
set "LASTLOG="
for /f "delims=" %%D in ('dir /b /o-d "%~dp0logs" 2^>nul ^| findstr /r "^[0-9]"') do (
    if not defined LASTLOG set "LASTLOG=%%D"
)
if defined LASTLOG (
    echo   Last run: !LASTLOG!
) else (
    echo   Last run: Never
)
echo.
echo   ------- Monitoring ^& Diagnostics ----------------------------
echo.
echo     [1]  Monitor System Health             no admin needed
echo     [2]  Fix Network Stack                 no admin needed
echo     [3]  Run All Diagnostics               quick full checkup
echo.
echo   ------- Maintenance ^& Updates --------------------------------
echo.
echo     [4]  Update All Packages               admin required
echo     [5]  Repair Windows Health              admin required
echo.
echo   ------- Security ^& Optimization ------------------------------
echo.
echo     [6]  Security Audit ^& Hardening        admin required
echo     [7]  Optimize WSL2                      admin required
echo.
echo   ------- Administration ----------------------------------------
echo.
echo     [8]  Scheduled Tasks Manager            admin required
echo     [S]  Setup Wizard                       reconfigure system
echo     [L]  View Recent Logs
echo     [T]  View Scheduled Task Status
echo.
echo     [0]  Exit
echo.
set /p "choice=  Select [0-8, S, L, T]: "

if "%choice%"=="1" goto OPT_MONITOR
if "%choice%"=="2" goto OPT_NETWORK
if "%choice%"=="3" goto OPT_DIAG_ALL
if "%choice%"=="4" goto OPT_UPDATE
if "%choice%"=="5" goto OPT_REPAIR
if "%choice%"=="6" goto OPT_SECURITY
if "%choice%"=="7" goto OPT_WSL
if "%choice%"=="8" goto OPT_TASKS
if /i "%choice%"=="S" goto OPT_SETUP
if /i "%choice%"=="L" goto OPT_LOGS
if /i "%choice%"=="T" goto OPT_TASK_STATUS
if "%choice%"=="0" goto EXIT
echo.
echo   Invalid option. Press any key to try again...
pause >nul
goto MENU

REM ============================================================
REM Monitoring & Diagnostics (no admin needed)
REM ============================================================

:OPT_MONITOR
powershell -ExecutionPolicy Bypass -File "%~dp0Monitor-SystemHealth.ps1"
goto PAUSE_MENU

:OPT_NETWORK
powershell -ExecutionPolicy Bypass -File "%~dp0Fix-NetworkStack.ps1"
goto PAUSE_MENU

:OPT_DIAG_ALL
cls
echo.
echo   =============================================================
echo     Running Full Diagnostics Suite
echo   =============================================================
echo.
echo   [1/3] System Health Monitor
echo   ---------------------------------------------------------
powershell -ExecutionPolicy Bypass -File "%~dp0Monitor-SystemHealth.ps1" -Auto
echo.
echo   [2/3] Network Stack Diagnostics
echo   ---------------------------------------------------------
powershell -ExecutionPolicy Bypass -File "%~dp0Fix-NetworkStack.ps1" -ReportOnly
echo.
echo   [3/3] Security Audit (requires admin elevation)
echo   ---------------------------------------------------------
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Harden-Security.ps1\" -ReportOnly' -Verb RunAs -Wait"
echo.
echo   =============================================================
echo     All diagnostics complete. Check logs for details.
echo   =============================================================
goto PAUSE_MENU

REM ============================================================
REM Maintenance & Updates (admin required)
REM ============================================================

:OPT_UPDATE
echo.
echo   This will elevate to Administrator...
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Update-AllPackages.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

:OPT_REPAIR
echo.
echo   This will elevate to Administrator...
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Repair-WindowsHealth.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

REM ============================================================
REM Security & Optimization (admin required)
REM ============================================================

:OPT_SECURITY
echo.
echo   This will elevate to Administrator...
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Harden-Security.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

:OPT_WSL
echo.
echo   This will elevate to Administrator...
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Optimize-WSL.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

REM ============================================================
REM Administration
REM ============================================================

:OPT_TASKS
echo.
echo   This will elevate to Administrator...
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Install-ScheduledTasks.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

:OPT_SETUP
powershell -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
goto PAUSE_MENU

:OPT_TASK_STATUS
echo.
echo   Scheduled Task Status
echo   ---------------------------------------------------------
echo.
for %%T in (WST-UpdatePackages WST-RepairHealth WST-SecurityAudit WST-HealthMonitor) do (
    schtasks /query /tn "%%T" /fo LIST 2>nul | findstr /i "TaskName Status" || echo   %%T: Not installed
    echo.
)
echo   Tip: Run [8] Scheduled Tasks Manager to install or manage tasks.
goto PAUSE_MENU

:OPT_LOGS
if not exist "%~dp0logs" (
    echo.
    echo   No logs found. Run a script first to generate logs.
    goto PAUSE_MENU
)
echo.
echo   Recent Logs (last 7 days)
echo   ---------------------------------------------------------
echo.
powershell -NoProfile -Command "Get-ChildItem '%~dp0logs' -Recurse -Filter '*.log' | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } | Sort-Object LastWriteTime -Descending | Select-Object -First 15 | ForEach-Object { $errors = @(Select-String '^\[-\]' $_.FullName).Count; $warns = @(Select-String '^\[!\]' $_.FullName).Count; Write-Host ('  {0}  {1,-35} Errors:{2} Warnings:{3}' -f ($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')), $_.BaseName, $errors, $warns) }"
echo.
set /p "openlog=  Open logs folder in Explorer? (Y/N): "
if /i "!openlog!"=="Y" explorer "%~dp0logs"
goto PAUSE_MENU

:PAUSE_MENU
echo.
echo   Press any key to return to menu...
pause >nul
goto MENU

:EXIT
echo.
echo   Goodbye!
exit /b 0
