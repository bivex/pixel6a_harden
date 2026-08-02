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

MANAGED_KEYS=(
  "system screen_off_timeout"
  "system show_password"
  "global stay_on_while_plugged_in"
  "global window_animation_scale"
  "global transition_animation_scale"
  "global animator_duration_scale"
  "global mobile_data_always_on"
  "global private_dns_mode"
  "global private_dns_specifier"
  "global wifi_scan_always_enabled"
  "global ble_scan_always_enabled"
  "global verifier_verify_adb_installs"
  "global development_settings_enabled"
  "global adb_enabled"
  "secure ui_night_mode"
  "secure lockscreen.power_button_instantly_locks"
  "secure lock_screen_allow_private_notifications"
  "secure trust_agents_extend_unlock"
  "secure install_non_market_apps"
)

echo "[INFO] Starting Automatic Settings Rollback Procedure..."

restore_managed_keys() {
  local device="$1"
  local target_dir="$2"
  local managed_file="${target_dir}/managed_keys.txt"

  if [ -f "${managed_file}" ]; then
    echo "[INFO] Restoring managed settings baseline from ${managed_file} for device [${device}]..."
    local restored=0

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
    done < "${managed_file}"

    echo "[PASS] Restored ${restored} managed setting(s) for device [${device}]."
  else
    echo "[WARN] Managed keys baseline missing: ${managed_file}. Using targeted fallback from namespace dumps."
    local restored=0
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
        fi
      fi
    done
    echo "[PASS] Restored ${restored} managed setting(s) from legacy dumps for device [${device}]."
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

  echo "=========================================================="
  echo "[INFO] Rolling back device [${DEVICE}] using backup: ${TARGET_BACKUP}"
  echo "=========================================================="

  restore_managed_keys "${DEVICE}" "${TARGET_BACKUP}"

  echo "[SUCCESS] Rollback completed for device [${DEVICE}]."
done

echo "[SUCCESS] Rollback operation complete."
