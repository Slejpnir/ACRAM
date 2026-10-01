"""Package the compiled UC3 console and its bundled runtime, without credentials."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
RELEASE = DIST / "uc3-console-20260927"
RELEASE.mkdir(parents=True, exist_ok=True)

names = ["ACRAM-UC3.cmd", "Launch-UC3-Console.ps1", "README-UC3-console.txt",
         "ACRAM_UC3.exe", "ACRAM_UC3.ctf", "config_Telco3PC_console.json",
         "uc3_adi_console.py", "python-runtime-info.json", "ws_credentials.example.json",
         "Telco_sbom.json", "network_telco3PC.xml", "telco_3PC_OAF.csv", "telco_3PC_SAB.csv"]
files = [DIST / name for name in names]
files += sorted(DIST.glob("fiz_*_new.mat"))
files += [DIST / "fiz_OAB.fis"]
for folder in ("python", "python-libs", "contextchain", "smartqc"):
    files += [path for path in sorted((DIST / folder).rglob("*"))
              if path.is_file() and "__pycache__" not in path.parts
              and ".git" not in path.parts and path.suffix not in {".pyc", ".pyo"}]
assert all(path.is_file() for path in files), "Portable UC3 files are missing."
assert not any(path.name.startswith("ws_credentials") and path.name != "ws_credentials.example.json" for path in files)

sources = ["acram_uc3_console_main.m", "build_uc3_console.m", "real_time_monitor.m",
           "adi_input_contexts.m", "adi_subscription_filters.m", "adi_transaction_source.m",
           "create_transaction.m", "SmartQCWebSocketClient.m", "uc3_adi_console.py"]
info = {
    "application": "ACRAM UC3 BACON/ATC console", "version": "0.0.4",
    "builtAtUtc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "platform": "Windows x64", "matlabRelease": "R2025b", "python": "bundled 3.12.10 x64",
    "entryPoint": "ACRAM-UC3.cmd", "config": "config_Telco3PC_console.json",
    "inputMode": "existing stored BACON and ATC transactions, then live reception",
    "finalFollowUpPrefix": "possible malware is present in the DuT",
    "createsContexts": False, "createsInputTransactions": False, "credentialsInArchive": False,
    "validation": ["UC3 MATLAB BACON/ATC regression passed with eight captured risk publications and no network calls",
                   "Existing UC1 SBOM/UAM regression passed",
                   "25 Python helper tests passed without network access, including the final follow-up summary",
                   "Compiled UC3 offline calculation and local prerequisite check passed",
                   "Portable ZIP ran offline from a separate folder containing spaces"],
    "bundledDependencyPatch": "magic/magic.py compares the -1 result by value to avoid a Python SyntaxWarning.",
    "liveAdiValidation": "Not performed: configured UC3 endpoint is unreachable from the build machine.",
    "sourceSha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sources},
}
info_path = DIST / "uc3-console-build-info.json"
info_path.write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
files.append(info_path)
files = sorted(set(files), key=lambda path: path.relative_to(DIST).as_posix())
manifest_text = "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(DIST).as_posix()}\n" for path in files)
(RELEASE / "SHA256SUMS.txt").write_bytes(manifest_text.encode("utf-8"))

archive = RELEASE / "ACRAM-UC3-Console-Windows-R2025b-20260927.zip"
temporary = archive.with_suffix(".zip.tmp")
with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, strict_timestamps=False) as output:
    for path in files:
        output.write(path, "ACRAM-UC3/" + path.relative_to(DIST).as_posix())
    output.writestr("ACRAM-UC3/SHA256SUMS.txt", manifest_text)
with zipfile.ZipFile(temporary) as packaged:
    assert packaged.testzip() is None
temporary.replace(archive)
(archive.with_suffix(".zip.sha256")).write_text(
    hashlib.sha256(archive.read_bytes()).hexdigest() + "  " + archive.name + "\n", encoding="utf-8")

# Keep the existing dist manifest valid for files updated by this release;
# avoid sweeping unrelated Linux releases or captured runs into that manifest.
manifest = DIST / "SHA256SUMS.txt"
existing = {line.split("  ", 1)[1] for line in manifest.read_text(encoding="utf-8-sig").splitlines() if "  " in line}
existing.update(path.relative_to(DIST).as_posix() for path in files)
manifest.write_bytes("".join(f"{hashlib.sha256((DIST / name).read_bytes()).hexdigest()}  {name}\n"
                             for name in sorted(existing) if (DIST / name).is_file()).encode("utf-8"))
print(f"Packaged {len(files)} runtime files: {archive}")
