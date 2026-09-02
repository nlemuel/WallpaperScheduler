@echo off
setlocal
set "SCRIPT=%~dp0Set-Wallpaper.ps1"
if not exist "%SCRIPT%" exit /b 2
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %ERRORLEVEL%
