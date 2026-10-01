#!/bin/sh
set -eu

: "${ACRAM_READY_FILE:=/tmp/acram/ready}"
: "${ACRAM_WORKDIR:=/var/lib/acram}"
: "${ACRAM_HEALTH_MODE:=marker}"

test -s "${ACRAM_READY_FILE}"

if [ "${1:-runtime}" = "startup" ] || [ "${ACRAM_HEALTH_MODE}" = "marker" ]; then
    exit 0
fi

if [ "${ACRAM_HEALTH_MODE}" != "websocket" ]; then
    echo "unsupported ACRAM_HEALTH_MODE: ${ACRAM_HEALTH_MODE}" >&2
    exit 2
fi

pid_file="${ACRAM_WORKDIR}/smartqc_pid.txt"
test -s "${pid_file}"
websocket_pid="$(cat "${pid_file}")"

case "${websocket_pid}" in
    *[!0-9]*|"") exit 1 ;;
esac

kill -0 "${websocket_pid}" 2>/dev/null
