#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${PROJECT_ROOT}/backups"

if ! command -v adb >/dev/null 2>&1; then
  echo "[ERROR] adb CLI tool not found in PATH."
  exit 1
fi

if [ -n "${ANDROID_SERIAL}" ]; then
  DEVICES=("${ANDROID_SERIAL}")
else
  mapfile -t DEVICES < <(adb devices | awk '$2=="device"{print $1}')
fi

if [ ${#DEVICES[@]} -eq 0 ]; then
  echo "[ERROR] No connected and authorized ADB target devices found."
  exit 1
fi

echo "[INFO] Starting Automatic Settings Rollback Procedure..."

restore_namespace() {
  local device="$1"
  local namespace="$2"
  local file="$3"

  if [ ! -f "${file}" ]; then
    echo "[WARN] Backup file not found for ${namespace}: ${file}"
    return 0
  fi

  echo "[INFO] Restoring ${namespace} settings from ${file} for device [${device}]..."
  local restored=0

  while IFS= read -r line || [ -n "${line}" ]; do
    line=$(echo "${line}" | tr -d '\r\n')
    if [ -z "${line}" ] || [[ "${line}" != *"="* ]]; then
      continue
    fi
    local key="${line%%=*}"
    local val="${line#*=}"

    adb -s "${device}" shell settings put "${namespace}" "${key}" "${val}" >/dev/null 2>&1 || true
    ((restored++)) || true
  done < "${file}" || true

  echo "[PASS] Restored ${restored} ${namespace} settings."
}

for DEVICE in "${DEVICES[@]}"; do
  TARGET_BACKUP="${1:-${BACKUP_DIR}/${DEVICE}/latest}"

  if [ ! -d "${TARGET_BACKUP}" ]; then
    echo "[ERROR] No backup directory found for device [${DEVICE}] at: ${TARGET_BACKUP}"
    echo "[ERROR] Run 'make backup' first to create a baseline backup."
    continue
  fi

  echo "=========================================================="
  echo "[INFO] Rolling back device [${DEVICE}] using backup: ${TARGET_BACKUP}"
  echo "=========================================================="

  restore_namespace "${DEVICE}" "system" "${TARGET_BACKUP}/system.txt"
  restore_namespace "${DEVICE}" "global" "${TARGET_BACKUP}/global.txt"
  restore_namespace "${DEVICE}" "secure" "${TARGET_BACKUP}/secure.txt"

  echo "[SUCCESS] Rollback completed for device [${DEVICE}]."
done

echo "[SUCCESS] Rollback operation complete."
