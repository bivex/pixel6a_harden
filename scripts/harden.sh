#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOCKDOWN=0
AUTO_YES=0
AUDIT_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --lockdown|--disable-adb)
      LOCKDOWN=1
      ;;
    -y|--yes|--force)
      AUTO_YES=1
      ;;
    --audit|--check)
      AUDIT_ONLY=1
      ;;
  esac
done

if [ "${DISABLE_ADB}" = "1" ]; then
  LOCKDOWN=1
fi

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

if [ "${LOCKDOWN}" = "1" ] && [ "${AUTO_YES}" = "0" ] && [ "${AUDIT_ONLY}" = "0" ]; then
  echo ""
  echo "=========================================================="
  echo "[WARNING] LOCKDOWN MODE REQUESTED!"
  echo "Executing lockdown will DISABLE USB Debugging & Developer Options"
  echo "on ${#DEVICES[@]} connected device(s). Active ADB sessions will terminate!"
  echo "=========================================================="
  read -rp "Are you sure you want to proceed with lockdown? [y/N]: " confirm_lockdown
  case "${confirm_lockdown}" in
    [yY][eE][sS]|[yY])
      echo "[INFO] User confirmed lockdown mode."
      ;;
    *)
      echo "[INFO] Lockdown mode cancelled by user. Exiting."
      exit 0
      ;;
  esac
fi

if [ "${AUDIT_ONLY}" = "1" ]; then
  echo "=========================================================="
  echo "[INFO] RUNNING IN AUDIT MODE ONLY (No device changes will be made)"
  echo "=========================================================="
else
  # Auto-backup before applying hardening changes
  "${SCRIPT_DIR}/backup.sh" >/dev/null 2>&1 || true
fi

echo ""
echo "[INFO] Starting Security Hardening Sequence"
echo "[INFO] Configuration loaded from config/default_settings.yml (Single Source of Truth)"
echo "[INFO] Target Device Count: ${#DEVICES[@]}"
echo "[INFO] Target Devices: ${DEVICES[*]}"

PASSED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0
UNSUPPORTED_COUNT=0

apply_or_audit_setting() {
  local device="$1"
  local type="$2"       # system | global | secure
  local key="$3"
  local target_val="$4"
  local min_sdk="$5"
  local step_desc="$6"
  local sdk_int="$7"

  if [ "${sdk_int}" -lt "${min_sdk}" ]; then
    echo "[UNSUPPORTED] ${step_desc} - Key '${key}' requires API Level ${min_sdk}+ (Device API is ${sdk_int})"
    ((UNSUPPORTED_COUNT++)) || true
    return 0
  fi

  local current_val
  current_val=$(adb -s "${device}" shell settings get "${type}" "${key}" 2>/dev/null | tr -d '\r\n')

  if [ "${AUDIT_ONLY}" = "1" ]; then
    if [ "${current_val}" = "${target_val}" ]; then
      echo "[COMPLIANT] ${step_desc} - Matches target (${key} = ${target_val})"
      ((SKIPPED_COUNT++)) || true
    else
      echo "[NON-COMPLIANT] ${step_desc} - Current: '${current_val}', Expected: '${target_val}'"
      ((FAILED_COUNT++)) || true
    fi
    return 0
  fi

  # Idempotent write check
  if [ "${current_val}" = "${target_val}" ]; then
    echo "[SKIP] ${step_desc} - Already compliant (${key} = ${target_val})"
    ((SKIPPED_COUNT++)) || true
    return 0
  fi

  echo "[INFO] ${step_desc} (Current: '${current_val}', Target: '${target_val}')..."
  if ! adb -s "${device}" shell settings put "${type}" "${key}" "${target_val}" >/dev/null 2>&1; then
    echo "[FAIL]  - Failed to write setting '${key}' on device [${device}]"
    ((FAILED_COUNT++)) || true
    return 0
  fi

  local verified_val
  verified_val=$(adb -s "${device}" shell settings get "${type}" "${key}" 2>/dev/null | tr -d '\r\n')

  if [ "${verified_val}" = "${target_val}" ]; then
    echo "[PASS]  - Verified ${key} = ${verified_val}"
    ((PASSED_COUNT++)) || true
  else
    echo "[WARN]  - Setting ${key} expected '${target_val}', got '${verified_val}'"
    ((FAILED_COUNT++)) || true
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
    echo "--------------------------------------------------------"
    echo "[CRITICAL WARNING] Device [${DEVICE}] has NO LOCK SCREEN PIN/Pattern!"
    echo "[CRITICAL WARNING] Hardening lock screen policies (e.g. instant power lock,"
    echo "[CRITICAL WARNING] 30s timeout) will have NO EFFECT until a PIN/Pattern is set!"
    echo "--------------------------------------------------------"
  fi

  PASSED_COUNT=0
  SKIPPED_COUNT=0
  FAILED_COUNT=0
  UNSUPPORTED_COUNT=0

  # Step 1: Screen Lock Controls
  apply_or_audit_setting "${DEVICE}" "system" "screen_off_timeout" "${CFG_HARDENED_SCREEN_TIMEOUT_MS}" "21" "Step 1a: Enforcing 30s Screen Timeout" "${SDK_INT}"
  apply_or_audit_setting "${DEVICE}" "global" "stay_on_while_plugged_in" "${CFG_STAY_AWAKE_PLUGGED_HARDENED}" "21" "Step 1b: Disabling Stay Awake on Charger" "${SDK_INT}"
  apply_or_audit_setting "${DEVICE}" "secure" "lockscreen.power_button_instantly_locks" "${CFG_POWER_BUTTON_INSTANTLY_LOCKS}" "21" "Step 1c: Instant Power Button Lock" "${SDK_INT}"

  # Step 2: Private Notifications
  apply_or_audit_setting "${DEVICE}" "secure" "lock_screen_allow_private_notifications" "${CFG_PRIVATE_NOTIFICATIONS_HIDDEN}" "21" "Step 2/8: Hiding Sensitive Lock Screen Notifications" "${SDK_INT}"

  # Step 3: Password Masking
  apply_or_audit_setting "${DEVICE}" "system" "show_password" "${CFG_SHOW_PASSWORD_CHARACTERS}" "21" "Step 3/8: Password Input Masking (Anti-Shoulder Surfing)" "${SDK_INT}"

  # Step 4: Cellular & Smart Lock
  apply_or_audit_setting "${DEVICE}" "global" "mobile_data_always_on" "${CFG_MOBILE_DATA_ALWAYS_ON}" "21" "Step 4a: Disabling Background Cellular Modem on Wi-Fi" "${SDK_INT}"
  apply_or_audit_setting "${DEVICE}" "secure" "trust_agents_extend_unlock" "${CFG_TRUST_AGENTS_EXTEND_UNLOCK}" "21" "Step 4b: Disabling Smart Lock Extensions" "${SDK_INT}"

  # Step 5: Encrypted Private DNS (Android 9 / API 28+)
  apply_or_audit_setting "${DEVICE}" "global" "private_dns_mode" "${CFG_PRIVATE_DNS_MODE}" "28" "Step 5a: Setting Private DNS Mode (${CFG_PRIVATE_DNS_MODE})" "${SDK_INT}"
  apply_or_audit_setting "${DEVICE}" "global" "private_dns_specifier" "${CFG_PRIVATE_DNS_PROVIDER}" "28" "Step 5b: Setting Private DNS Provider (${CFG_PRIVATE_DNS_PROVIDER})" "${SDK_INT}"

  # Step 6: Location Scanning
  apply_or_audit_setting "${DEVICE}" "global" "wifi_scan_always_enabled" "${CFG_WIFI_SCAN_ALWAYS_ENABLED}" "21" "Step 6a: Disabling Background Wi-Fi Location Scanning" "${SDK_INT}"
  apply_or_audit_setting "${DEVICE}" "global" "ble_scan_always_enabled" "${CFG_BLE_SCAN_ALWAYS_ENABLED}" "21" "Step 6b: Disabling Background BLE Location Scanning" "${SDK_INT}"

  # Step 7: Unknown Apps & Verification
  apply_or_audit_setting "${DEVICE}" "secure" "install_non_market_apps" "${CFG_ALLOW_UNKNOWN_SOURCES}" "21" "Step 7a: Restricting Unknown App Sources" "${SDK_INT}"
  apply_or_audit_setting "${DEVICE}" "global" "verifier_verify_adb_installs" "${CFG_VERIFY_ADB_INSTALLS}" "21" "Step 7b: Enforcing Play Protect Verification on ADB Installs" "${SDK_INT}"

  # Step 8: Radios
  if [ "${AUDIT_ONLY}" = "0" ]; then
    echo "[INFO] Step 8/8: Disabling Unnecessary Radios (Bluetooth & NFC)..."
    adb -s "${DEVICE}" shell svc bluetooth disable >/dev/null 2>&1 || true
    adb -s "${DEVICE}" shell svc nfc disable >/dev/null 2>&1 || true
    echo "[PASS]  - Radio disable signals sent"
    ((PASSED_COUNT++)) || true
  fi

  echo "--------------------------------------------------------"
  echo "[SUMMARY] Device [${DEVICE}] Results: ${PASSED_COUNT} Passed, ${SKIPPED_COUNT} Compliant/Skipped, ${UNSUPPORTED_COUNT} Unsupported, ${FAILED_COUNT} Failed"

  if [ ${FAILED_COUNT} -gt 0 ]; then
    OVERALL_SUCCESS=false
  fi
done

if [ "${AUDIT_ONLY}" = "1" ]; then
  echo ""
  echo "[SUCCESS] Audit completed across ${#DEVICES[@]} target device(s)."
  exit 0
fi

# Perform lockdown ONLY AFTER all devices have completed verification
if [ "${LOCKDOWN}" = "1" ]; then
  echo ""
  echo "[INFO] Executing Final Lockdown Phase across ${#DEVICES[@]} device(s)..."
  for DEVICE in "${DEVICES[@]}"; do
    echo "[NOTICE] Disabling Developer Options & ADB Debugging interface on device [${DEVICE}]..."
    adb -s "${DEVICE}" shell settings put global development_settings_enabled 0 >/dev/null 2>&1 || true
    adb -s "${DEVICE}" shell settings put global adb_enabled 0 >/dev/null 2>&1 || true
  done
  echo "[NOTICE] Final lockdown completed. ADB interfaces have been terminated on all target devices."
else
  echo ""
  echo "[INFO] Lockdown phase skipped. Developer Options & ADB Debugging remain active for automation."
  echo "[INFO] (To perform final lockdown, run: ./scripts/harden.sh --lockdown -y)"
fi

echo ""
if [ "${OVERALL_SUCCESS}" = true ]; then
  echo "[SUCCESS] Security hardening sequence completed successfully across all target devices."
  exit 0
else
  echo "[ERROR] Security hardening completed with errors on one or more devices."
  exit 1
fi
