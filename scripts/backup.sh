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

  chmod 700 "${BACKUP_DIR}" "${DEVICE_BACKUP_DIR}"

  # Generate SHA-256 checksums file for backup integrity verification
  CHECKSUM_FILE="${DEVICE_BACKUP_DIR}/checksums.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "${DEVICE_BACKUP_DIR}" && sha256sum system.txt global.txt secure.txt managed_keys.txt metadata.ini > "${CHECKSUM_FILE}" 2>/dev/null) || true
  elif command -v shasum >/dev/null 2>&1; then
    (cd "${DEVICE_BACKUP_DIR}" && shasum -a 256 system.txt global.txt secure.txt managed_keys.txt metadata.ini > "${CHECKSUM_FILE}" 2>/dev/null) || true
  else
    python3 -c '
import os, hashlib
bdir = "'"${DEVICE_BACKUP_DIR}"'"
files = ["system.txt", "global.txt", "secure.txt", "managed_keys.txt", "metadata.ini"]
with open(os.path.join(bdir, "checksums.sha256"), "w", encoding="utf-8") as out:
    for fname in files:
        fpath = os.path.join(bdir, fname)
        if os.path.exists(fpath):
            h = hashlib.sha256(open(fpath, "rb").read()).hexdigest()
            out.write(f"{h}  {fname}\n")
' || true
  fi

  # Restrict backup files to owner read/write only (chmod 600)
  chmod 600 "${DEVICE_BACKUP_DIR}"/* 2>/dev/null || true

  LATEST_LINK="${BACKUP_DIR}/${DEVICE}/latest"
  rm -f "${LATEST_LINK}"
  ln -s "${DEVICE_BACKUP_DIR}" "${LATEST_LINK}" 2>/dev/null || true

  echo "[PASS] Permissions hardened (chmod 700/600) and SHA-256 checksums generated."
  echo "[SUCCESS] Backup completed for device [${DEVICE}]."
done

echo "[SUCCESS] All backups stored in: ${BACKUP_DIR}"
