#!/usr/bin/env bash
set -euo pipefail
APP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for scenario in scenario-video-20260927 uc1-scenario-video-20260927; do
  launcher="$APP_ROOT/$scenario/tools/Record-UC1-Scenario.sh"
  if [[ -f "$launcher" ]]; then exec bash "$launcher" "$@"; fi
done
printf 'Scenario tools are missing under %s. Install the UC1 scenario package first.\n' "$APP_ROOT" >&2
exit 1
