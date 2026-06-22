# ACRAM TELEMETRY Risk Evaluation

ACRAM is a MATLAB-based access-control risk assessment tool developed for the
TELEMETRY scenarios. It combines access-control configuration, object and
subject behaviour, CVE/SBOM information, network context, and anomaly indicators
to produce component-level and aggregated risk outputs.

## What The Tool Does

- Calculates access-control risk for user-device pairs.
- Updates risk from SBOM/CVE transactions.
- Updates anomaly-related indicators from telemetry sources such as ATC, NAD,
  RAD, I4RI, BACON/BECON, and UAM.
- Exports component-level and aggregated risk JSON transactions.
- Can publish risk updates to ADI and refresh the local risk GUI.
- Can export risk graphs for changed user-device pairs.

## Main Entry Points

Run the enhanced workflow from MATLAB:

```matlab
EvaluateRisk_main_enhanced("config_Telco3PC.json")
```

Other commonly used configurations include:

```matlab
EvaluateRisk_main_enhanced("config_Nokia_robot_CVE_2025.json")
EvaluateRisk_main_enhanced("config_antonov_2025.json")
```

Run smoke tests:

```matlab
test_framework('clear');
test_framework('run_all');
```

Reset or stop the real-time monitor:

```matlab
real_time_monitor('reset')
real_time_monitor('stop')
```

## Configuration

Configuration is stored in `config*.json` files. A configuration defines:

- subjects: users or processes being assessed;
- objects: devices, services, or data assets;
- ACL entries: user-object permissions and authentication level;
- network file: topology used for level-of-influence calculation;
- OAF/SAB files: object and subject behaviour inputs;
- SBOM/CVE handling mode;
- ADI credentials file name;
- real-time mode and WebSocket settings.

Credentials are not committed. Use `ws_credentials.example.json` as a template
and create a local credentials file such as `ws_credentials_nokia.json`.

## Outputs

ACRAM produces two JSON output types.

### Component-Level Output

Component output describes risk for one assessed component or device. It
contains:

- `subject`: assessed component or device;
- `per-user-risk-levels`: risk for each user-device pair;
- `value`: maximum risk for that component;
- `severity`: `GREEN`, `YELLOW`, `ORANGE`, or `RED`;
- `timestamp`: assessment time;
- `input-indicators`: telemetry transactions used for the update;
- `follow-up-actions`: recommendations for the highest-risk pair.

### Aggregated Output

Aggregated output describes system-level access-control risk. It contains:

- `value`: aggregated system risk;
- `severity`: `GREEN`, `YELLOW`, `ORANGE`, or `RED`;
- `timestamp`: aggregation time;
- `most_risky_user_device_pairs`: pairs above the reporting threshold;
- `follow_up_actions`: telemetry indicators that affected the aggregated risk.

Generated output files are ignored by Git because they may contain transaction
IDs, context IDs, public keys, or local scenario data.

## Integration

- ADI is the primary data bus for receiving indicators and publishing risk
  updates.
- SBOM transactions update the CVE list for the affected object.
- Anomaly transactions update object anomaly behaviour inputs.
- The TELEMETRY dashboard and downstream tools such as Trust Analyzer can
  consume the exported JSON.

## Repository Hygiene

The repository intentionally excludes:

- local ADI credential files;
- wallet files and VPN profiles;
- generated ACRAM JSON outputs;
- logs, snapshots, caches, and temporary graph exports;
- backup files such as `*.bak` and MATLAB autosave files;
- deploy/build output folders;
- large archives, installers, Office documents, and bundled binary packages.

Configuration files may still contain lab topology details such as device names,
IP addresses, network XML files, and ADI credential file names. Review or
replace those values before publishing a public repository if the topology
itself should remain private.

Before publishing, check what will be committed:

```powershell
git status --short
```

Then create the initial commit:

```powershell
git add .
git commit -m "Initial commit"
```

Add a GitHub remote and push:

```powershell
git remote add origin https://github.com/<owner>/<repo>.git
git push -u origin master
```

If you rename the branch to `main`:

```powershell
git branch -M main
git push -u origin main
```
