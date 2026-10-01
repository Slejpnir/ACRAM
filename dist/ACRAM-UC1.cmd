@echo off
setlocal
set "SCENARIO_OPTION="
if not "%~2"=="" goto usage_error
if "%~1"=="" goto run
if "%~1"=="--check" set "SCENARIO_OPTION=--check"
if "%~1"=="--offline" set "SCENARIO_OPTION=--offline"
if "%~1"=="--help" goto usage
if "%~1"=="-h" goto usage
if not defined SCENARIO_OPTION goto usage_error
:run
where ssh.exe >nul 2>nul
if errorlevel 1 (
  echo Windows OpenSSH client is required.
  exit /b 1
)
echo Connecting to UC1. Enter your UC1 SSH password when prompted.
ssh.exe -t -p 22 wrcve@192.168.77.90 "bash /home/wrcve/TELEMETRY/dist/ACRAM-UC1.sh %SCENARIO_OPTION%"
exit /b %ERRORLEVEL%
:usage_error
echo Invalid arguments.
call :usage
exit /b 2
:usage
echo Usage: ACRAM-UC1.cmd [--check ^| --offline ^| --help]
echo Default: connect to UC1 and run the real ADI demonstration in this console.
echo --check checks prerequisites only. --offline runs without ADI transactions.
exit /b 0
