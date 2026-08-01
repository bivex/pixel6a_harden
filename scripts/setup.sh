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

echo "[INFO] Starting Standard Device Initialization Sequence"
echo "[INFO] Target Device Count: ${#DEVICES[@]}"
echo "[INFO] Target Devices: ${DEVICES[*]}"

for DEVICE in "${DEVICES[@]}"; do
  echo "[INFO] Processing Target Device: [${DEVICE}]"
  MODEL=$(adb -s "${DEVICE}" shell getprop ro.product.model 2>/dev/null || echo "Unknown")
  BRAND=$(adb -s "${DEVICE}" shell getprop ro.product.brand 2>/dev/null || echo "Unknown")
  ANDROID_VER=$(adb -s "${DEVICE}" shell getprop ro.build.version.release 2>/dev/null || echo "Unknown")

  echo "[INFO] Device Parameters: ${BRAND} ${MODEL} (Android ${ANDROID_VER})"

  echo "[INFO] Executing Step 1/5: Setting Screen Timeout (600000 ms)..."
  adb -s "${DEVICE}" shell settings put system screen_off_timeout 600000 || true

  echo "[INFO] Executing Step 2/5: Setting Stay Awake on Charger..."
  adb -s "${DEVICE}" shell settings put global stay_on_while_plugged_in 7 || true

  echo "[INFO] Executing Step 3/5: Enabling UI Night Mode (Dark Theme)..."
  adb -s "${DEVICE}" shell settings put secure ui_night_mode 2 || true

  echo "[INFO] Executing Step 4/5: Setting Animation Duration Scale (0.5x)..."
  adb -s "${DEVICE}" shell settings put global window_animation_scale 0.5 || true
  adb -s "${DEVICE}" shell settings put global transition_animation_scale 0.5 || true
  adb -s "${DEVICE}" shell settings put global animator_duration_scale 0.5 || true

  echo "[INFO] Executing Step 5/5: Enabling Wireless Interface (Wi-Fi)..."
  adb -s "${DEVICE}" shell svc wifi enable || true

  echo "[SUCCESS] Configuration applied to target device: [${DEVICE}]"
done

echo "[SUCCESS] Standard initialization sequence completed successfully."
