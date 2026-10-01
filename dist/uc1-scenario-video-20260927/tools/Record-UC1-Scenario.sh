#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'HELP'
Usage: ACRAM-UC1.sh [--check | --offline | --help]

Default: publish initial risks, then process SBOM and UAM risk updates in UC1 ADI.
Inputs are generated for 3 users and 9 configured devices. Submitted
transactions are verified by read-back. Console output is shown live.

  --check    Check local prerequisites only; no MATLAB run or ADI requests.
  --offline  Exercise the same risk calculations without ADI transactions.
  --help     Show this help.

Every run saves its console log and results in a new directory.
After the sequence, the ADI listener stays active. Press Ctrl+C to stop,
or create the stop file printed when monitoring starts.
Requires the installed MATLAB R2025a and Python 3 on UC1.
HELP
}
MODE=live
CHECK_ONLY=0
if (( $# > 1 )); then usage >&2; exit 2; fi
case "${1:-}" in
  '') ;;
  --check) CHECK_ONLY=1 ;;
  --offline) MODE=offline ;;
  --help|-h) usage; exit 0 ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac
TOOLS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd -- "$TOOLS_DIR/../.." && pwd)"
PYTHON_EXE="${ACRAM_PYTHON:-/usr/bin/python3}"
MATLAB_EXE="${MATLAB_EXE:-$HOME/R2025a/bin/matlab}"
for required in "$PYTHON_EXE" "$MATLAB_EXE"; do
  if [[ ! -x "$required" ]]; then printf 'Required executable not found: %s\n' "$required" >&2; exit 1; fi
done
for required in "$TOOLS_DIR/run_uc1_scenario.m" "$TOOLS_DIR/capture_console.py" "$TOOLS_DIR/scenario_adi.py" "$APP_ROOT/config_antonov_2025.json" "$APP_ROOT/real_time_monitor.m"; do
  if [[ ! -f "$required" ]]; then printf 'Required file not found: %s\n' "$required" >&2; exit 1; fi
done
export ACRAM_PYTHON="$PYTHON_EXE"
export PYTHONPATH="$APP_ROOT:$TOOLS_DIR${PYTHONPATH:+:$PYTHONPATH}"
cd -- "$APP_ROOT"
if [[ "$MODE" == live ]]; then
  "$PYTHON_EXE" -c 'import contextchain, smartqc, websocket'
fi
if (( CHECK_ONLY )); then
  printf 'Prerequisites: OK\nApplication: %s\nMATLAB: %s\nNo MATLAB process or ADI request was started.\n' "$APP_ROOT" "$MATLAB_EXE"
  exit 0
fi
umask 077
RECORDING_ROOT="$(mktemp -d "$(dirname -- "$TOOLS_DIR")/console-run-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
export ACRAM_SCENARIO_APP_ROOT="$APP_ROOT"
export ACRAM_SCENARIO_TOOLS="$TOOLS_DIR"
export ACRAM_SCENARIO_OUTPUT="$RECORDING_ROOT/run"
export ACRAM_SCENARIO_MODE="$MODE"
status=0
"$PYTHON_EXE" -u "$TOOLS_DIR/capture_console.py" --output "$RECORDING_ROOT/console.jsonl" -- \
  "$MATLAB_EXE" -batch "addpath(getenv('ACRAM_SCENARIO_TOOLS')); run_uc1_scenario(getenv('ACRAM_SCENARIO_APP_ROOT'),getenv('ACRAM_SCENARIO_OUTPUT'),getenv('ACRAM_SCENARIO_MODE'))" || status=$?
exit "$status"
