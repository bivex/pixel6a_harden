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

EXPLICIT_BACKUP="${1:-}"

if [ -n "${EXPLICIT_BACKUP}" ] && [ ${#DEVICES[@]} -gt 1 ] && [ -z "${ANDROID_SERIAL}" ]; then
  echo "[ERROR] An explicit backup path was specified ('${EXPLICIT_BACKUP}'), but multiple ADB devices are connected (${#DEVICES[@]} devices)."
  echo "[ERROR] An explicit backup path can only be applied to a single target device."
  echo "[ERROR] Please set ANDROID_SERIAL=<serial> to select a device, or omit the backup path for per-device default backups."
  exit 1
fi

if [ -f "${SCRIPT_DIR}/managed_keys.sh" ]; then
  # shellcheck source=scripts/managed_keys.sh
  source "${SCRIPT_DIR}/managed_keys.sh"
else
  echo "[ERROR] Shared managed keys file '${SCRIPT_DIR}/managed_keys.sh' not found."
  exit 1
fi

echo "[INFO] Starting Automatic Settings Rollback Procedure..."

verify_backup_integrity() {
  local target_dir="$1"
  local checksum_file="${target_dir}/checksums.sha256"

  if [ ! -f "${checksum_file}" ]; then
    echo "[WARN] No SHA-256 checksum file found at ${checksum_file}. Proceeding without hash verification."
    return 0
  fi

  echo "[INFO] Verifying SHA-256 checksums for backup integrity..."
  local valid=true

  if command -v sha256sum >/dev/null 2>&1; then
    (cd "${target_dir}" && sha256sum -c checksums.sha256 >/dev/null 2>&1) || valid=false
  elif command -v shasum >/dev/null 2>&1; then
    (cd "${target_dir}" && shasum -a 256 -c checksums.sha256 >/dev/null 2>&1) || valid=false
  else
    python3 -c '
import os, hashlib, sys
bdir = "'"${target_dir}"'"
cfile = os.path.join(bdir, "checksums.sha256")
for line in open(cfile, encoding="utf-8"):
    parts = line.strip().split()
    if len(parts) == 2:
        expected, fname = parts[0], parts[1]
        fpath = os.path.join(bdir, fname)
        if os.path.exists(fpath):
            actual = hashlib.sha256(open(fpath, "rb").read()).hexdigest()
            if actual != expected:
                sys.exit(1)
sys.exit(0)
' || valid=false
  fi

  if [ "${valid}" = false ]; then
    echo "[ERROR] Backup integrity verification FAILED at ${target_dir}!"
    echo "[ERROR] Backup files appear to be modified or corrupted. Aborting rollback."
    return 1
  fi

  echo "[PASS] SHA-256 backup integrity verified successfully."
  return 0
}

restore_managed_keys() {
  local device="$1"
  local target_dir="$2"
  local managed_file="${target_dir}/managed_keys.txt"

  if [ -f "${managed_file}" ]; then
    echo "[INFO] Restoring managed settings baseline from ${managed_file} for device [${device}]..."
    local restored=0
    local verified=0
    local failed=0

    while IFS= read -r line || [ -n "${line}" ]; do
      line=$(echo "${line}" | tr -d '\r\n')
      [ -z "${line}" ] && continue
      [[ "${line}" == "#"* ]] && continue

      local ns="${line%% *}"
      local keyval="${line#* }"
      [[ "${keyval}" != *"="* ]] && continue
      local key="${keyval%%=*}"
      local val="${keyval#*=}"

      if [ "${val}" = "null" ] || [ -z "${val}" ] || [ "${val}" = "setting do not exist" ]; then
        adb -s "${device}" shell settings delete "${ns}" "${key}" >/dev/null 2>&1 || true
      else
        adb -s "${device}" shell settings put "${ns}" "${key}" "${val}" >/dev/null 2>&1 || true
      fi
      ((restored++)) || true

      # Post-write rollback verification
      local current_val
      current_val=$(adb -s "${device}" shell settings get "${ns}" "${key}" 2>/dev/null | tr -d '\r\n')
      if [ "${val}" = "null" ] || [ -z "${val}" ]; then
        if [ "${current_val}" = "null" ] || [ -z "${current_val}" ]; then
          ((verified++)) || true
        else
          ((failed++)) || true
        fi
      else
        if [ "${current_val}" = "${val}" ]; then
          ((verified++)) || true
        else
          echo "[WARN] Setting '${key}' rollback verification mismatch (expected '${val}', got '${current_val}')"
          ((failed++)) || true
        fi
      fi
    done < "${managed_file}"

    echo "[PASS] Restored and verified ${verified}/${restored} managed setting(s) for device [${device}]."
  else
    echo "[WARN] Managed keys baseline missing: ${managed_file}. Using targeted fallback from namespace dumps."
    local restored=0
    local verified=0

    for item in "${MANAGED_KEYS[@]}"; do
      local ns="${item%% *}"
      local key="${item#* }"
      local file="${target_dir}/${ns}.txt"
      if [ -f "${file}" ]; then
        local match
        match=$(grep -E "^${key}=" "${file}" | head -n 1 || true)
        if [ -n "${match}" ]; then
          local val="${match#*=}"
          val=$(echo "${val}" | tr -d '\r\n')
          if [ "${val}" = "null" ] || [ -z "${val}" ]; then
            adb -s "${device}" shell settings delete "${ns}" "${key}" >/dev/null 2>&1 || true
          else
            adb -s "${device}" shell settings put "${ns}" "${key}" "${val}" >/dev/null 2>&1 || true
          fi
          ((restored++)) || true

          local current_val
          current_val=$(adb -s "${device}" shell settings get "${ns}" "${key}" 2>/dev/null | tr -d '\r\n')
          if [ "${current_val}" = "${val}" ]; then
            ((verified++)) || true
          fi
        fi
      fi
    done
    echo "[PASS] Restored and verified ${verified}/${restored} managed setting(s) from legacy dumps for device [${device}]."
  fi
}

for DEVICE in "${DEVICES[@]}"; do
  if [ -n "${EXPLICIT_BACKUP}" ]; then
    TARGET_BACKUP="${EXPLICIT_BACKUP}"
  else
    TARGET_BACKUP="${BACKUP_DIR}/${DEVICE}/latest"
  fi

  if [ ! -d "${TARGET_BACKUP}" ]; then
    echo "[ERROR] No backup directory found for device [${DEVICE}] at: ${TARGET_BACKUP}"
    echo "[ERROR] Run 'make backup' first to create a baseline backup."
    continue
  fi

  if [ -f "${TARGET_BACKUP}/metadata.ini" ]; then
    SAVED_DEVICE=$(grep -E '^device=' "${TARGET_BACKUP}/metadata.ini" | cut -d= -f2 | tr -d '\r\n' || echo "")
    if [ -n "${SAVED_DEVICE}" ] && [ "${SAVED_DEVICE}" != "${DEVICE}" ]; then
      echo "[ERROR] Backup device mismatch for target device [${DEVICE}]!"
      echo "[ERROR] Backup metadata specifies device [${SAVED_DEVICE}], but target device is [${DEVICE}]."
      echo "[ERROR] Aborting rollback on device [${DEVICE}] to prevent cross-device setting corruption."
      continue
    fi
  fi

  if ! verify_backup_integrity "${TARGET_BACKUP}"; then
    continue
  fi

  echo "=========================================================="
  echo "[INFO] Rolling back device [${DEVICE}] using backup: ${TARGET_BACKUP}"
  echo "=========================================================="

  restore_managed_keys "${DEVICE}" "${TARGET_BACKUP}"

  echo "[SUCCESS] Rollback completed for device [${DEVICE}]."
done

echo "[SUCCESS] Rollback operation complete."
