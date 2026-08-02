#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${PROJECT_ROOT}/backups"

if ! command -v adb >/dev/null 2>&1; then
  echo "[ERROR] adb command-line tool is not installed or not available in PATH."
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

echo "=== Connected ADB Device Information (${#DEVICES[@]} device(s) found) ==="

for DEVICE in "${DEVICES[@]}"; do
  echo ""
  echo "--- Device Serial: [${DEVICE}] ---"
  MODEL=$(adb -s "${DEVICE}" shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  BRAND=$(adb -s "${DEVICE}" shell getprop ro.product.brand 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  ANDROID_VER=$(adb -s "${DEVICE}" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  SDK_INT=$(adb -s "${DEVICE}" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r\n' || echo "0")
  BATTERY=$(adb -s "${DEVICE}" shell dumpsys battery 2>/dev/null | grep "level:" | awk '{print $2}' | tr -d '\r\n' || echo "Unknown")
  LOCK_TYPE=$(adb -s "${DEVICE}" shell settings get secure lockscreen.password_type 2>/dev/null | tr -d '\r\n' || echo "0")

  echo "Brand & Model: ${BRAND} ${MODEL}"
  echo "Android Release: ${ANDROID_VER} (API Level / SDK_INT: ${SDK_INT})"
  echo "Battery Level: ${BATTERY}%"

  if [ "${LOCK_TYPE}" = "0" ] || [ "${LOCK_TYPE}" = "null" ] || [ -z "${LOCK_TYPE}" ]; then
    echo "Lock Screen PIN Status: [WARNING] NO LOCK PIN/PATTERN DETECTED!"
  else
    echo "Lock Screen PIN Status: [OK] Configured (Type Code: ${LOCK_TYPE})"
  fi

  LATEST_BACKUP="${BACKUP_DIR}/${DEVICE}/latest"
  if [ -d "${LATEST_BACKUP}" ]; then
    if [ -f "${LATEST_BACKUP}/managed_keys.txt" ]; then
      echo "Backup Baseline: [OK] Managed baseline available at backups/${DEVICE}/latest"
    else
      echo "Backup Baseline: [OK] Legacy baseline available at backups/${DEVICE}/latest"
    fi
  else
    echo "Backup Baseline: [NOTICE] No backup found. Run 'make backup' to save baseline."
  fi
done
echo "=========================================================="
