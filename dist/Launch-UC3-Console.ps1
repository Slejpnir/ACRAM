param([string]$Mode = '')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
try {
    if ($Mode -in @('--help', '-h')) {
        Write-Host 'Usage: ACRAM-UC3.cmd [--check | --offline | --listen-only]'
        Write-Host 'Publishes initial risks, processes existing BACON then ATC transactions, and keeps listening.'
        Write-Host '--listen-only publishes initial risks and listens without processing stored inputs.'
        Write-Host '--check validates local prerequisites without connecting to ADI.'
        Write-Host '--offline checks local risk calculation with publishing and monitoring disabled.'
        Write-Host 'Press Ctrl+C or create the printed stop file to stop monitoring.'
        exit 0
    }
    if ($Mode -and $Mode -notin @('--check', '--offline', '--listen-only')) {
        throw 'Unknown option. Use --help for supported options.'
    }
    $uc3Python = $env:ACRAM_PYTHON
    if (-not $uc3Python) { $uc3Python = Join-Path $PSScriptRoot 'python\python.exe' }
    if (-not (Test-Path -LiteralPath $uc3Python -PathType Leaf)) {
        throw 'Python runtime is missing. Keep the complete python folder beside ACRAM-UC3.cmd.'
    }
    Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
    $uc3PythonVersion = & $uc3Python -c 'import sys,struct; print(''%d.%d/%d'' % (sys.version_info.major,sys.version_info.minor,struct.calcsize(''P'')*8))'
    if ($LASTEXITCODE -ne 0 -or $uc3PythonVersion -ne '3.12/64') {
        throw 'UC3 requires 64-bit Python 3.12.'
    }
    $env:ACRAM_PYTHON = $uc3Python
    $env:ACRAM_WORKDIR = $PSScriptRoot
    $env:PYTHONPATH = "$PSScriptRoot;$PSScriptRoot\python-libs"
    $env:PYTHONDONTWRITEBYTECODE = '1'
    $env:PATH = "$(Split-Path -Parent $uc3Python);$env:PATH"
    $uc3RuntimeFound = $false
    $uc3RuntimeRoots = @($env:MATLAB_RUNTIME_ROOT, 'C:\Program Files\MATLAB\MATLAB Runtime\R2025b', 'C:\Program Files\MATLAB Runtime\R2025b', 'C:\Program Files\MATLAB\R2025b')
    foreach ($uc3RuntimeRoot in $uc3RuntimeRoots) {
        if ($uc3RuntimeRoot -and (Test-Path -LiteralPath "$uc3RuntimeRoot\runtime\win64\mclmcrrt25_2.dll")) {
            $env:PATH = "$uc3RuntimeRoot\runtime\win64;$env:PATH"
            $uc3RuntimeFound = $true
            break
        }
    }
    if (-not $uc3RuntimeFound) { throw 'Install MATLAB Runtime R2025b (Windows x64), or set MATLAB_RUNTIME_ROOT.' }
    foreach ($uc3Required in @('ACRAM_UC3.exe', 'ACRAM_UC3.ctf', 'config_Telco3PC_console.json', 'uc3_adi_console.py', 'fiz_OAB.fis')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $uc3Required) -PathType Leaf)) {
            throw "Required UC3 file is missing: $uc3Required"
        }
    }
    & $uc3Python -c 'import smartqc, contextchain, websocket, uc3_adi_console'
    if ($LASTEXITCODE -ne 0) { throw 'UC3 Python dependencies could not be loaded.' }
    if ($Mode -eq '--check') {
        Write-Host 'UC3 local prerequisites passed.'
        exit 0
    }
    $uc3Executable = Join-Path $PSScriptRoot 'ACRAM_UC3.exe'
    if ($Mode) { & $uc3Executable $Mode } else { & $uc3Executable }
    exit $LASTEXITCODE
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
