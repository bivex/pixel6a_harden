#!/usr/bin/env bash
# Single Source of Truth for pixel_setup managed setting keys.
# Sourced by backup.sh and rollback.sh.

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
  "global adb_wifi_enabled"
  "global usb_mass_storage_enabled"
  "global verifier_verify_adb_installs"
  "global development_settings_enabled"
  "global adb_enabled"
  "secure ui_night_mode"
  "secure lockscreen.power_button_instantly_locks"
  "secure lock_screen_lock_after_timeout"
  "secure lock_screen_allow_private_notifications"
  "secure trust_agents_extend_unlock"
  "secure install_non_market_apps"
)
