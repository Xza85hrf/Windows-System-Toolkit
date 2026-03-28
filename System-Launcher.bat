@echo off
REM Windows System Toolkit - Batch Launcher
REM Launches the unified CLI (wst.ps1) for double-click convenience.
REM For full CLI usage, run: powershell .\wst.ps1 help

powershell -ExecutionPolicy Bypass -NoExit -File "%~dp0wst.ps1" %*
