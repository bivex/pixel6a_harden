#!/usr/bin/env bash
set -eo pipefail

# 1. Ensure ADB executable is available
if ! command -v adb >/dev/null 2>&1; then
  echo "[ERROR] ADB command-line tool is not installed or not available in PATH."
  exit 1
fi

# 2. Determine target device list
if [ -n "${ANDROID_SERIAL}" ]; then
  DEVICES=("${ANDROID_SERIAL}")
else
  mapfile -t DEVICES < <(adb devices | awk '$2=="device"{print $1}')
fi

if [ ${#DEVICES[@]} -eq 0 ]; then
  echo "[ERROR] No connected and authorized ADB target devices found."
  exit 1
fi

echo "[INFO] Starting Security Hardening Sequence"
echo "[INFO] Target Device Count: ${#DEVICES[@]}"
echo "[INFO] Target Devices: ${DEVICES[*]}"

for DEVICE in "${DEVICES[@]}"; do
  echo "[INFO] Hardening Target Device: [${DEVICE}]"
  MODEL=$(adb -s "${DEVICE}" shell getprop ro.product.model 2>/dev/null || echo "Unknown")
  BRAND=$(adb -s "${DEVICE}" shell getprop ro.product.brand 2>/dev/null || echo "Unknown")
  ANDROID_VER=$(adb -s "${DEVICE}" shell getprop ro.build.version.release 2>/dev/null || echo "Unknown")

  echo "[INFO] Device Parameters: ${BRAND} ${MODEL} (Android ${ANDROID_VER})"

  echo "[INFO] Executing Step 1/7: Enforcing Lock Screen Controls (30s timeout, stay awake disabled, instant lock)..."
  adb -s "${DEVICE}" shell settings put system screen_off_timeout 30000 || true
  adb -s "${DEVICE}" shell settings put global stay_on_while_plugged_in 0 || true
  adb -s "${DEVICE}" shell settings put secure lockscreen.power_button_instantly_locks 1 || true

  echo "[INFO] Executing Step 2/7: Hiding Sensitive Lock Screen Notifications..."
  adb -s "${DEVICE}" shell settings put secure lock_screen_allow_private_notifications 0 || true

  echo "[INFO] Executing Step 3/7: Enabling Password Input Masking (Anti-Shoulder Surfing)..."
  adb -s "${DEVICE}" shell settings put system show_password 0 || true

  echo "[INFO] Executing Step 4/7: Disabling Background Cellular Modem & Smart Lock Extensions..."
  adb -s "${DEVICE}" shell settings put global mobile_data_always_on 0 || true
  adb -s "${DEVICE}" shell settings put secure trust_agents_extend_unlock 0 || true

  echo "[INFO] Executing Step 5/7: Disabling Background Location Scanning (Wi-Fi & Bluetooth LE)..."
  adb -s "${DEVICE}" shell settings put global wifi_scan_always_enabled 0 || true
  adb -s "${DEVICE}" shell settings put global ble_scan_always_enabled 0 || true

  echo "[INFO] Executing Step 6/7: Restricting Package Sources & Enforcing App Verification..."
  adb -s "${DEVICE}" shell settings put secure install_non_market_apps 0 || true
  adb -s "${DEVICE}" shell settings put global verifier_verify_adb_installs 1 || true

  echo "[INFO] Executing Step 7/7: Disabling Wireless Radios (Bluetooth & NFC)..."
  adb -s "${DEVICE}" shell svc bluetooth disable || true
  adb -s "${DEVICE}" shell svc nfc disable 2>/dev/null || true

  echo "[SUCCESS] Security hardening controls applied to target device: [${DEVICE}]"
done

echo "[SUCCESS] Security hardening sequence completed successfully."
