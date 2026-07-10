@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_PATH=%~f0"
set "TARGET_DIR=%~dp0"
if "%TARGET_DIR:~-1%"=="\" set "TARGET_DIR=%TARGET_DIR:~0,-1%"

if /I "%~1"=="--dry-run" (
    echo Target directory: "%TARGET_DIR%"
    echo Dry run: system PATH was not changed.
    exit /b 0
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    echo Administrator privileges are required. Requesting elevation...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SCRIPT_PATH -Verb RunAs -WorkingDirectory $env:TARGET_DIR"
    if errorlevel 1 (
        echo Failed to request administrator privileges.
        pause
        exit /b 1
    )
    exit /b 0
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$target=$env:TARGET_DIR.TrimEnd('\'); $machinePath=[Environment]::GetEnvironmentVariable('Path','Machine'); $entries=@($machinePath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); if ($entries | Where-Object { $_.TrimEnd('\') -ieq $target }) { Write-Host ('Already present in system PATH: {0}' -f $target); exit 0 }; $newPath=(@($entries)+$target) -join ';'; [Environment]::SetEnvironmentVariable('Path',$newPath,'Machine'); Write-Host ('Added to system PATH: {0}' -f $target)"
if errorlevel 1 (
    echo Failed to update the system PATH.
    pause
    exit /b 1
)

echo Open a new terminal for the updated PATH to take effect.
pause
exit /b 0
