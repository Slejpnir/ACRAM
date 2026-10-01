ACRAM UC3 / Telco 3PC - run directly from dist

For the BACON/ATC console workflow, run ACRAM-UC3.cmd.
See README-UC3-console.txt for stored-event selection and console options.

Double-click Start-UC3.cmd in this folder, then press Run in the ACRAM console.
The selected configuration is config_Telco3PC.json. Your existing UC3 credentials
are in ws_credentials_tim.json beside the executable.

This folder contains the app, compiled archive, bundled Python 3.12, Python
packages, UC3 configuration, topology, input data, and risk models. No files in
the dated release folders or the project source folder are needed to launch.
The launcher sets the working directory to this folder even if started elsewhere.
Generated risk CSV/JSON, graphs, and normal application logs are written here.
Use Stop before closing the console to stop live monitoring.

Start-UC3.cmd is the supported entry point. Keep ACRAM.exe, ACRAM.ctf, python,
python-libs, smartqc, contextchain and the config/data files together.
No separate Python installation or Windows PATH change is needed.
MATLAB Runtime R2025b (Windows x64) must be installed on the target computer.
https://www.mathworks.com/products/compiler/matlab-runtime.html

Advanced settings:
ACRAM_PYTHON may override the bundled interpreter with another 64-bit Python 3.12.
Leave it unset to use dist/python/python.exe. MATLAB_RUNTIME_ROOT may specify a
nonstandard R2025b Runtime installation root.

Existing dated builds and Linux deployment artifacts are retained in their
subfolders. They are not used by this launcher.
Live ADI and dashboard behavior is unchanged. Verification runs use publishing
and monitoring disabled; live UC3 connectivity is not tested automatically.

Bundled Python license: python/LICENSE.txt
Bundled Python provenance: python-runtime-info.json
https://www.python.org/downloads/release/python-31210/
