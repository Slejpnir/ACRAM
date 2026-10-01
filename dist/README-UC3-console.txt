ACRAM UC3 / Telco 3PC console

Run ACRAM-UC3.cmd from this dist folder, or call it by its full path from a console.
The launcher publishes the initial component and aggregate risks to the existing
UC3 ADI risk contexts, processes an existing BACON transaction followed by an
existing ATC transaction, and publishes changed risks. It then remains connected
to receive further BACON and ATC transactions. It does not create contexts or
submit BACON/ATC input transactions.

The final aggregate summary starts its follow-up field with:
  possible malware is present in the DuT
The existing follow-up text follows that phrase. This final summary preserves
the latest verified risk values, including when ATC does not change them.

Configuration: config_Telco3PC_console.json. The referenced UC3 credential file
supplies the existing ADI endpoint and output contexts. Keep ACRAM_UC3.exe,
ACRAM_UC3.ctf, uc3_adi_console.py, python, python-libs, smartqc, contextchain,
configuration, input data, topology, and risk models together in dist.
MATLAB Runtime R2025b (Windows x64) is required.

Risk calculations, transaction receipts, and console logs are saved in a new
uc3-console-runs subfolder on every launch. Graph image export and dashboard
publishing are disabled for this console configuration.

Stop with Ctrl+C, or create the exact stop file printed when monitoring starts.
From another PowerShell console: New-Item -ItemType File -Path '<printed stop path>'

Options:
  ACRAM-UC3.cmd --check        Check local prerequisites without connecting to ADI.
  ACRAM-UC3.cmd --offline      Calculate risks without publishing or monitoring.
  ACRAM-UC3.cmd --listen-only  Publish initial risks and listen; skip stored inputs.
  ACRAM-UC3.cmd --help         Show launcher usage.

ACRAM_PYTHON can select another 64-bit Python 3.12 executable. MATLAB_RUNTIME_ROOT
can select a nonstandard MATLAB Runtime R2025b installation.

Start-UC3.cmd continues to open the existing desktop GUI.

Stored transaction selection:
  uc3StoredTransactions.bacon selects the supplied BACON example by its ID.
  uc3StoredTransactions.atc is empty, so the latest stored ATC event is used.
  Set either value to a transaction ID to select another existing event, or
  leave it empty to select the latest event in that tool's existing context.
  An unavailable input stops startup before initial risk publication.
  The received ATC context schema is not itself an anomaly transaction.

BACON/ATC events whose IPs do not match a configured device use the existing
networkAnomalyTargetObjectName setting (Gateway). Calculated risks may remain
unchanged even when the combined anomaly indicator changes; only actual risk
changes are published after the initial baseline.

The portable ZIP excludes credentials. Keep your existing ws_credentials_tim.json
beside the launcher, or point credentialsFileName at your existing file.
