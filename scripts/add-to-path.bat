@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "TARGET_DIR=%~dp0"
if "%TARGET_DIR:~-1%"=="\" set "TARGET_DIR=%TARGET_DIR:~0,-1%"

set "DRY_RUN=0"
set "INTERACTIVE=1"

:arg_loop
if "%~1"=="" goto arg_done
if /I "%~1"=="--dry-run" set "DRY_RUN=1"
if /I "%~1"=="--non-interactive" set "INTERACTIVE=0"
shift
goto arg_loop
:arg_done

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$target=$env:TARGET_DIR.TrimEnd('\'); $dryRun=$env:DRY_RUN -eq '1'; $isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); function Add-PathEntry([string]$scope,[string]$label) { $current=[Environment]::GetEnvironmentVariable('Path',$scope); $entries=@($current -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); if ($entries | Where-Object { $_.TrimEnd('\') -ieq $target }) { Write-Host ('Already present in {0} PATH: {1}' -f $label,$target); return }; if ($dryRun) { Write-Host ('Would add to {0} PATH: {1}' -f $label,$target); return }; [Environment]::SetEnvironmentVariable('Path',((@($entries)+$target) -join ';'),$scope); Write-Host ('Added to {0} PATH: {1}' -f $label,$target) }; Add-PathEntry 'User' 'user'; if ($isAdmin) { Add-PathEntry 'Machine' 'system' } else { Write-Host 'Not running as administrator; system PATH was not changed.' }; if ($dryRun) { Write-Host 'Dry run: no PATH values were changed.' }"
set "PS_EXIT=%errorlevel%"

if not "%PS_EXIT%"=="0" (
    echo Failed to update PATH.
    if "%INTERACTIVE%"=="1" pause
    exit /b 1
)

if "%DRY_RUN%"=="1" exit /b 0

echo Open a new terminal for the updated PATH values to take effect.
if "%INTERACTIVE%"=="1" pause
exit /b 0
