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
  BATTERY=$(adb -s "${DEVICE}" shell dumpsys battery 2>/dev/null | awk '$1=="level:"{print $2}' | tr -d '\r\n' || echo "Unknown")
  LOCK_TYPE=$(adb -s "${DEVICE}" shell settings get secure lockscreen.password_type 2>/dev/null | tr -d '\r\n' || echo "0")

  # Hardware Attestation & Security Parameters
  SELINUX=$(adb -s "${DEVICE}" shell getenforce 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  VERIFIED_BOOT=$(adb -s "${DEVICE}" shell getprop ro.boot.verifiedbootstate 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  BOOTLOADER_LOCKED=$(adb -s "${DEVICE}" shell getprop ro.boot.flash.locked 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  BUILD_TYPE=$(adb -s "${DEVICE}" shell getprop ro.build.type 2>/dev/null | tr -d '\r\n' || echo "Unknown")
  DEBUGGABLE=$(adb -s "${DEVICE}" shell getprop ro.debuggable 2>/dev/null | tr -d '\r\n' || echo "0")
  SU_BINARY=$(adb -s "${DEVICE}" shell "which su || ls /system/bin/su /system/xbin/su" 2>/dev/null | tr -d '\r\n' || echo "")

  echo "Brand & Model: ${BRAND} ${MODEL}"
  echo "Android Release: ${ANDROID_VER} (API Level / SDK_INT: ${SDK_INT})"
  echo "Battery Level: ${BATTERY}%"

  # Security & Attestation Profile Reporting
  if [ "${SELINUX}" = "Enforcing" ]; then
    echo "SELinux Enforcement: [OK] Enforcing Mode"
  else
    echo "SELinux Enforcement: [CRITICAL WARNING] Mode: ${SELINUX} (Expected: Enforcing)"
  fi

  if [ "${VERIFIED_BOOT}" = "green" ]; then
    echo "Verified Boot State: [OK] Green (Locked & Clean System Integrity)"
  else
    echo "Verified Boot State: [WARNING] State: '${VERIFIED_BOOT}' (Expected: green)"
  fi

  if [ "${BOOTLOADER_LOCKED}" = "1" ]; then
    echo "Bootloader State: [OK] Locked (ro.boot.flash.locked = 1)"
  else
    echo "Bootloader State: [WARNING] Unlocked Bootloader detected! (ro.boot.flash.locked = ${BOOTLOADER_LOCKED})"
  fi

  if [ "${DEBUGGABLE}" = "0" ] && [ "${BUILD_TYPE}" = "user" ]; then
    echo "Build & Debug Profile: [OK] Production User Build (debuggable=0)"
  else
    echo "Build & Debug Profile: [WARNING] Non-production build detected (type=${BUILD_TYPE}, debuggable=${DEBUGGABLE})"
  fi

  if [ -n "${SU_BINARY}" ] && [[ "${SU_BINARY}" != *"no su"* ]]; then
    echo "Root Status: [CRITICAL WARNING] Root / su binary detected at: ${SU_BINARY}"
  else
    echo "Root Status: [OK] No root / su binary detected"
  fi

  if [ "${LOCK_TYPE}" = "0" ] || [ "${LOCK_TYPE}" = "null" ] || [ -z "${LOCK_TYPE}" ]; then
    echo "Lock Screen PIN Status: [WARNING] NO LOCK PIN/PATTERN DETECTED!"
  else
    echo "Lock Screen PIN Status: [OK] Configured (Type Code: ${LOCK_TYPE})"
  fi

  LATEST_BACKUP="${BACKUP_DIR}/${DEVICE}/latest"
  if [ -d "${LATEST_BACKUP}" ]; then
    if [ -f "${LATEST_BACKUP}/checksums.sha256" ]; then
      echo "Backup Baseline: [OK] Managed baseline with SHA-256 integrity checksums at backups/${DEVICE}/latest"
    elif [ -f "${LATEST_BACKUP}/managed_keys.txt" ]; then
      echo "Backup Baseline: [OK] Managed baseline available at backups/${DEVICE}/latest"
    else
      echo "Backup Baseline: [OK] Legacy baseline available at backups/${DEVICE}/latest"
    fi
  else
    echo "Backup Baseline: [NOTICE] No backup found. Run 'make backup' to save baseline."
  fi
done
echo "=========================================================="
