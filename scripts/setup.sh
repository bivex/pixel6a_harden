#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v adb >/dev/null 2>&1; then
  echo "[ERROR] ADB command-line tool is not installed or not available in PATH."
  exit 1
fi

if [ -f "${SCRIPT_DIR}/parse_config.py" ]; then
  eval "$("${SCRIPT_DIR}/parse_config.py" --env)"
else
  echo "[ERROR] Configuration parser '${SCRIPT_DIR}/parse_config.py' not found."
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

echo "[INFO] Starting Standard Device Initialization Sequence"
echo "[INFO] Configuration loaded from config/default_settings.yml (Single Source of Truth)"
echo "[INFO] Target Device Count: ${#DEVICES[@]}"
echo "[INFO] Target Devices: ${DEVICES[*]}"

# Trigger auto-backup before modifying settings
"${SCRIPT_DIR}/backup.sh" >/dev/null 2>&1 || true

apply_idempotent_setting() {
  local device="$1"
  local type="$2"       # system | global | secure
  local key="$3"
  local target_val="$4"
  local step_desc="$5"

  local current_val
  current_val=$(adb -s "${device}" shell settings get "${type}" "${key}" 2>/dev/null | tr -d '\r\n')

  if [ "${current_val}" = "${target_val}" ]; then
    echo "[SKIP] ${step_desc} - Already compliant (${key} = ${target_val})"
    return 0
  fi

  echo "[INFO] ${step_desc} (Current: '${current_val}', Target: '${target_val}')..."
  if ! adb -s "${device}" shell settings put "${type}" "${key}" "${target_val}" >/dev/null 2>&1; then
    echo "[FAIL]  - Failed to write setting '${key}' on device [${device}]"
    return 1
  fi

  local verified_val
  verified_val=$(adb -s "${device}" shell settings get "${type}" "${key}" 2>/dev/null | tr -d '\r\n')

  if [ "${verified_val}" = "${target_val}" ]; then
    echo "[PASS]  - Verified ${key} = ${verified_val}"
    return 0
  else
    echo "[WARN]  - Setting ${key} expected '${target_val}', got '${verified_val}'"
    return 1
  fi
}

OVERALL_SUCCESS=true

for DEVICE in "${DEVICES[@]}"; do
  echo ""
  echo "[INFO] Processing Target Device: [${DEVICE}]"
  MODEL=$(adb -s "${DEVICE}" shell getprop ro.product.model 2>/dev/null || echo "Unknown")
  BRAND=$(adb -s "${DEVICE}" shell getprop ro.product.brand 2>/dev/null || echo "Unknown")
  ANDROID_VER=$(adb -s "${DEVICE}" shell getprop ro.build.version.release 2>/dev/null || echo "Unknown")
  SDK_INT=$(adb -s "${DEVICE}" shell getprop ro.build.version.sdk 2>/dev/null || echo "0")
  LOCK_TYPE=$(adb -s "${DEVICE}" shell settings get secure lockscreen.password_type 2>/dev/null || echo "0")

  echo "[INFO] Device Parameters: ${BRAND} ${MODEL} (Android ${ANDROID_VER}, SDK_INT API Level ${SDK_INT})"

  if [ "${LOCK_TYPE}" = "0" ] || [ "${LOCK_TYPE}" = "null" ]; then
    echo "[WARNING] Device [${DEVICE}] does not have a PIN/Pattern lock screen configured!"
    echo "[WARNING] Please configure a lock screen PIN/Pattern in Android Settings for full security."
  fi

  PASSED_COUNT=0
  SKIPPED_COUNT=0
  FAILED_COUNT=0

  # Step 1: Screen Timeout
  res=$(apply_idempotent_setting "${DEVICE}" "system" "screen_off_timeout" "${CFG_SCREEN_TIMEOUT_MS}" "Step 1/5: Setting Screen Timeout (${CFG_SCREEN_TIMEOUT_MS} ms)" || echo "FAIL")
  echo "${res}"
  if [[ "${res}" == *"[SKIP]"* ]]; then ((SKIPPED_COUNT++)); elif [[ "${res}" == *"[PASS]"* ]]; then ((PASSED_COUNT++)); else ((FAILED_COUNT++)); fi

  # Step 2: Stay Awake
  res=$(apply_idempotent_setting "${DEVICE}" "global" "stay_on_while_plugged_in" "${CFG_STAY_AWAKE_PLUGGED_STANDARD}" "Step 2/5: Setting Stay Awake on Charger" || echo "FAIL")
  echo "${res}"
  if [[ "${res}" == *"[SKIP]"* ]]; then ((SKIPPED_COUNT++)); elif [[ "${res}" == *"[PASS]"* ]]; then ((PASSED_COUNT++)); else ((FAILED_COUNT++)); fi

  # Step 3: Dark Mode
  res=$(apply_idempotent_setting "${DEVICE}" "secure" "ui_night_mode" "${CFG_DARK_MODE_CODE}" "Step 3/5: Setting UI Night Mode" || echo "FAIL")
  echo "${res}"
  if [[ "${res}" == *"[SKIP]"* ]]; then ((SKIPPED_COUNT++)); elif [[ "${res}" == *"[PASS]"* ]]; then ((PASSED_COUNT++)); else ((FAILED_COUNT++)); fi

  # Step 4: Animation Scales
  echo "[INFO] Step 4/5: Configuring Animation Duration Scales (${CFG_ANIMATION_SCALE_FAST}x)..."
  for anim_key in window_animation_scale transition_animation_scale animator_duration_scale; do
    res=$(apply_idempotent_setting "${DEVICE}" "global" "${anim_key}" "${CFG_ANIMATION_SCALE_FAST}" "  - Setting ${anim_key}" || echo "FAIL")
    echo "${res}"
    if [[ "${res}" == *"[SKIP]"* ]]; then ((SKIPPED_COUNT++)); elif [[ "${res}" == *"[PASS]"* ]]; then ((PASSED_COUNT++)); else ((FAILED_COUNT++)); fi
  done

  # Step 5: Wi-Fi
  echo "[INFO] Step 5/5: Enabling Wireless Interface (Wi-Fi)..."
  if adb -s "${DEVICE}" shell svc wifi enable >/dev/null 2>&1; then
    echo "[PASS]  - Wi-Fi interface enabled"
    ((PASSED_COUNT++))
  else
    echo "[FAIL]  - Failed to enable Wi-Fi interface"
    ((FAILED_COUNT++))
  fi

  echo "--------------------------------------------------------"
  echo "[SUMMARY] Device [${DEVICE}] Setup Results: ${PASSED_COUNT} Passed, ${SKIPPED_COUNT} Skipped (Idempotent), ${FAILED_COUNT} Failed"

  if [ ${FAILED_COUNT} -gt 0 ]; then
    OVERALL_SUCCESS=false
  fi
done

echo ""
if [ "${OVERALL_SUCCESS}" = true ]; then
  echo "[SUCCESS] Standard initialization sequence completed successfully across all target devices."
  exit 0
else
  echo "[ERROR] Standard initialization completed with errors on one or more devices."
  exit 1
fi
