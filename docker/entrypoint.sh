#!/bin/sh
set -eu

: "${ACRAM_WORKDIR:=/var/lib/acram}"
: "${ACRAM_CONFIG:=/etc/acram/config.json}"
: "${ACRAM_CREDENTIALS_FILE:=/etc/acram/credentials.json}"
: "${ACRAM_CREDENTIALS_FILENAME:=ws_credentials_tim.json}"
: "${ACRAM_READY_FILE:=/tmp/acram/ready}"
: "${ACRAM_STOP_FILE:=/tmp/acram/stop}"
: "${MCR_CACHE_ROOT:=/var/cache/mcr}"

child_pid=""

terminate_websocket() {
    pid_file="${ACRAM_WORKDIR}/smartqc_pid.txt"
    if [ ! -s "${pid_file}" ]; then
        return
    fi

    websocket_pid="$(cat "${pid_file}" 2>/dev/null || true)"
    case "${websocket_pid}" in
        *[!0-9]*|"") return ;;
    esac

    if kill -0 "${websocket_pid}" 2>/dev/null; then
        kill -TERM "${websocket_pid}" 2>/dev/null || true
    fi
}

request_shutdown() {
    echo "[entrypoint] shutdown requested"
    mkdir -p "$(dirname "${ACRAM_STOP_FILE}")"
    : > "${ACRAM_STOP_FILE}"

    attempts=0
    while [ -n "${child_pid}" ] \
        && kill -0 "${child_pid}" 2>/dev/null \
        && [ "${attempts}" -lt 45 ]; do
        sleep 1
        attempts=$((attempts + 1))
    done

    terminate_websocket
    if [ -n "${child_pid}" ] && kill -0 "${child_pid}" 2>/dev/null; then
        kill -TERM "${child_pid}" 2>/dev/null || true
    fi
}

trap request_shutdown TERM INT

if [ ! -r "${ACRAM_CONFIG}" ]; then
    echo "[entrypoint] missing configuration: ${ACRAM_CONFIG}" >&2
    exit 64
fi
if [ ! -r "${ACRAM_CREDENTIALS_FILE}" ]; then
    echo "[entrypoint] missing ADI credentials: ${ACRAM_CREDENTIALS_FILE}" >&2
    exit 65
fi
if [ "$#" -eq 0 ] || [ ! -x "$1" ]; then
    echo "[entrypoint] compiled ACRAM executable is missing or not executable" >&2
    exit 66
fi

mkdir -p \
    "${ACRAM_WORKDIR}" \
    "${ACRAM_WORKDIR}/home" \
    "${MCR_CACHE_ROOT}" \
    "$(dirname "${ACRAM_READY_FILE}")" \
    "$(dirname "${ACRAM_STOP_FILE}")"

# Refresh immutable application assets while preserving generated output.
cp -a /opt/acram/resources/. "${ACRAM_WORKDIR}/"

# The application resolves this scenario-specific filename relative to pwd.
# Keep only a symlink on the PVC; the Secret value remains in its read-only
# Kubernetes volume and is never copied into persistent storage.
ln -sfn "${ACRAM_CREDENTIALS_FILE}" \
    "${ACRAM_WORKDIR}/${ACRAM_CREDENTIALS_FILENAME}"

rm -f "${ACRAM_READY_FILE}" "${ACRAM_STOP_FILE}"
cd "${ACRAM_WORKDIR}"

echo "[entrypoint] launching ACRAM"
"$@" "${ACRAM_CONFIG}" &
child_pid=$!

set +e
wait "${child_pid}"
exit_code=$?
set -e

terminate_websocket
rm -f "${ACRAM_READY_FILE}"
exit "${exit_code}"
