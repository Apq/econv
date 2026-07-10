@echo off
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0release.ps1" %*
pause
