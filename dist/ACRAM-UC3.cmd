@echo off
if not "%~2"=="" (
    echo Use ACRAM-UC3.cmd --help for supported options.
    exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-UC3-Console.ps1" -Mode "%~1"
exit /b %errorlevel%
