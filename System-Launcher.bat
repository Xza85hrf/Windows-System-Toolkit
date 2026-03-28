@echo off
setlocal enabledelayedexpansion
title Windows System Toolkit v2.0.0

:MENU
cls
echo.
echo   =============================================================
echo     WINDOWS SYSTEM TOOLKIT v2.0.0
echo     System Maintenance ^& Automation
echo   =============================================================
echo.
echo   [1] Monitor System Health
echo   [2] Update All Packages          (Admin)
echo   [3] Repair Windows Health         (Admin)
echo   [4] Security Audit ^& Hardening   (Admin)
echo   [5] Optimize WSL2                 (Admin)
echo   [6] Install Scheduled Tasks       (Admin)
echo   [7] Fix Network Stack             (Admin for fixes)
echo   [8] Run All Diagnostics           (Monitor + Network + Security)
echo   [9] Setup Wizard
echo.
echo   [S] View Scheduled Task Status
echo   [L] View Recent Logs
echo   [0] Exit
echo.
set /p "choice=  Select option: "

if "%choice%"=="1" goto OPT1
if "%choice%"=="2" goto OPT2
if "%choice%"=="3" goto OPT3
if "%choice%"=="4" goto OPT4
if "%choice%"=="5" goto OPT5
if "%choice%"=="6" goto OPT6
if "%choice%"=="7" goto OPT7
if "%choice%"=="8" goto OPT8
if "%choice%"=="9" goto OPT9
if /i "%choice%"=="S" goto OPTS
if /i "%choice%"=="L" goto OPTL
if "%choice%"=="0" goto EXIT
goto MENU

:OPT1
powershell -ExecutionPolicy Bypass -File "%~dp0Monitor-SystemHealth.ps1"
goto PAUSE_MENU

:OPT2
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Update-AllPackages.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

:OPT3
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Repair-WindowsHealth.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

:OPT4
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Harden-Security.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

:OPT5
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Optimize-WSL.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

:OPT6
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Install-ScheduledTasks.ps1\"' -Verb RunAs -Wait"
goto PAUSE_MENU

:OPT7
powershell -ExecutionPolicy Bypass -File "%~dp0Fix-NetworkStack.ps1"
goto PAUSE_MENU

:OPT8
echo.
echo   Running all diagnostics...
echo   =========================
echo.
echo   --- System Health Monitor ---
powershell -ExecutionPolicy Bypass -File "%~dp0Monitor-SystemHealth.ps1" -Auto
echo.
echo   --- Network Stack Diagnostics ---
powershell -ExecutionPolicy Bypass -File "%~dp0Fix-NetworkStack.ps1" -ReportOnly
echo.
echo   --- Security Audit ---
powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0Harden-Security.ps1\" -ReportOnly' -Verb RunAs -Wait"
echo.
echo   All diagnostics complete.
goto PAUSE_MENU

:OPT9
powershell -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
goto PAUSE_MENU

:OPTS
echo.
echo Checking scheduled tasks...
echo.
schtasks /query /tn "WST-UpdatePackages" 2>nul || echo Task not found: WST-UpdatePackages
schtasks /query /tn "WST-RepairHealth" 2>nul || echo Task not found: WST-RepairHealth
schtasks /query /tn "WST-SecurityAudit" 2>nul || echo Task not found: WST-SecurityAudit
schtasks /query /tn "WST-HealthMonitor" 2>nul || echo Task not found: WST-HealthMonitor
goto PAUSE_MENU

:OPTL
if not exist "%~dp0logs" (
    echo Logs folder not found: %~dp0logs
) else (
    echo.
    echo Recent log files:
    dir /b /o-d /s "%~dp0logs\*.log" 2>nul
    echo.
    set /p open=Open logs folder in Explorer? (Y/N):
    if /i "!open!"=="Y" explorer "%~dp0logs"
)
goto PAUSE_MENU

:PAUSE_MENU
echo.
echo Press any key to return to menu...
pause >nul
goto MENU

:EXIT
echo.
echo Goodbye
exit /b 0
