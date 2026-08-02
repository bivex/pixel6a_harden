#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${PROJECT_ROOT}/backups"

mkdir -p "${BACKUP_DIR}"

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

if [ -f "${SCRIPT_DIR}/managed_keys.sh" ]; then
  # shellcheck source=scripts/managed_keys.sh
  source "${SCRIPT_DIR}/managed_keys.sh"
else
  echo "[ERROR] Shared managed keys file '${SCRIPT_DIR}/managed_keys.sh' not found."
  exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
echo "[INFO] Starting Automated Settings Backup for ${#DEVICES[@]} device(s)..."

for DEVICE in "${DEVICES[@]}"; do
  DEVICE_BACKUP_DIR="${BACKUP_DIR}/${DEVICE}/${TIMESTAMP}"
  mkdir -p "${DEVICE_BACKUP_DIR}"

  echo "[INFO] Backing up device [${DEVICE}] settings to: ${DEVICE_BACKUP_DIR}"

  # Save full namespace dumps for audit/forensics
  adb -s "${DEVICE}" shell settings list system > "${DEVICE_BACKUP_DIR}/system.txt" 2>/dev/null || true
  adb -s "${DEVICE}" shell settings list global > "${DEVICE_BACKUP_DIR}/global.txt" 2>/dev/null || true
  adb -s "${DEVICE}" shell settings list secure > "${DEVICE_BACKUP_DIR}/secure.txt" 2>/dev/null || true

  # Save targeted managed settings for surgical rollback
  MANAGED_FILE="${DEVICE_BACKUP_DIR}/managed_keys.txt"
  : > "${MANAGED_FILE}"
  for item in "${MANAGED_KEYS[@]}"; do
    ns="${item%% *}"
    key="${item#* }"
    val=$(adb -s "${DEVICE}" shell settings get "${ns}" "${key}" 2>/dev/null | tr -d '\r\n' || echo "null")
    echo "${ns} ${key}=${val}" >> "${MANAGED_FILE}"
  done

  MODEL=$(adb -s "${DEVICE}" shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  SDK_VER=$(adb -s "${DEVICE}" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  echo "device=${DEVICE}" > "${DEVICE_BACKUP_DIR}/metadata.ini"
  echo "model=${MODEL}" >> "${DEVICE_BACKUP_DIR}/metadata.ini"
  echo "sdk_int=${SDK_VER}" >> "${DEVICE_BACKUP_DIR}/metadata.ini"
  echo "timestamp=${TIMESTAMP}" >> "${DEVICE_BACKUP_DIR}/metadata.ini"

  LATEST_LINK="${BACKUP_DIR}/${DEVICE}/latest"
  rm -f "${LATEST_LINK}"
  ln -s "${DEVICE_BACKUP_DIR}" "${LATEST_LINK}" 2>/dev/null || true

  echo "[SUCCESS] Backup completed for device [${DEVICE}]."
done

echo "[SUCCESS] All backups stored in: ${BACKUP_DIR}"
