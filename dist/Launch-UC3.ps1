param([string]$Mode = '')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
try {
    $uc3Python = $env:ACRAM_PYTHON
    if (-not $uc3Python) {
        $uc3Python = Join-Path $PSScriptRoot 'python\python.exe'
    }
    if (-not (Test-Path -LiteralPath $uc3Python -PathType Leaf)) {
        throw 'Python runtime is missing. Keep the complete python folder beside Start-UC3.cmd. ACRAM_PYTHON may override it with a 64-bit Python 3.12 executable.'
    }
    # Keep another installed Python's home from overriding the bundled runtime.
    Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
    Write-Host "UC3 Python: $uc3Python"
    $uc3PythonVersion = & $uc3Python -c 'import sys,struct; print(''%d.%d/%d'' % (sys.version_info.major, sys.version_info.minor, struct.calcsize(''P'')*8))'
    if ($uc3PythonVersion -ne '3.12/64') { throw 'This package requires 64-bit Python 3.12.' }
    $env:ACRAM_PYTHON = $uc3Python
    $env:PYTHONPATH = "$PSScriptRoot;$PSScriptRoot\python-libs"
    $env:PYTHONDONTWRITEBYTECODE = '1'
    $env:PATH = "$(Split-Path -Parent $uc3Python);$env:PATH"
    $uc3RuntimeRoots = @($env:MATLAB_RUNTIME_ROOT, 'C:\Program Files\MATLAB\MATLAB Runtime\R2025b', 'C:\Program Files\MATLAB Runtime\R2025b', 'C:\Program Files\MATLAB\R2025b')
    foreach ($uc3RuntimeRoot in $uc3RuntimeRoots) {
        if ($uc3RuntimeRoot -and (Test-Path -LiteralPath "$uc3RuntimeRoot\runtime\win64\mclmcrrt25_2.dll")) {
            $env:PATH = "$uc3RuntimeRoot\runtime\win64;$env:PATH"
            break
        }
    }
    & $uc3Python -c 'import smartqc, contextchain, websocket'
    if ($LASTEXITCODE -ne 0) { throw 'UC3 Python dependencies could not be loaded.' }
    if ($Mode -and $Mode -notin @('--smoke-test', '--ui-smoke-test')) { throw 'Unknown launch option.' }
    $uc3Start = @{ FilePath = "$PSScriptRoot\ACRAM.exe"; WorkingDirectory = $PSScriptRoot; PassThru = $true; Wait = $true }
    if ($Mode) {
        $uc3Start.ArgumentList = $Mode
        $uc3Start.WindowStyle = 'Hidden'
    }
    $uc3Process = Start-Process @uc3Start
    if ($uc3Process.ExitCode -ne 0) { throw "ACRAM exited with code $($uc3Process.ExitCode)." }
    exit 0
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
