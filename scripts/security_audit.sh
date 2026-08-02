#!/usr/bin/env bash
# Deep Security Audit module for pixel_setup.
# Read-only (advisory) inspection of Android runtime security posture.
# Sourced by scripts/info.sh — defines functions only, no top-level side effects.
#
# Design contract:
#   * ADVISORY ONLY — every finding prints [OK]/[WARNING]/[CRITICAL WARNING]/[NOTICE]
#     and never alters exit status. The caller stays exit 0 even when issues are found.
#   * AUDIT ONLY — never disables Accessibility services, never revokes Device Admins,
#     never modifies device state. Reporting destructive changes is a human decision.
#   * FAULT-TOLERANT — every adb/getprop/grep is guarded so a single failing probe
#     (e.g. a ROM without a key, an empty grep) cannot abort the caller's `set -eo pipefail`.
#
# Config env vars (provided by parse_config.py --env, all optional w/ built-in defaults):
#   CFG_AUDIT_SECURITY_PATCH_MAX_AGE_DAYS  default 120
#   CFG_AUDIT_STRICT_LOCK_QUALITY          default 0  (1 = pattern/biometric-weak insufficient)
#   CFG_AUDIT_ACCESSIBILITY_ALLOWLIST      default "" (space-separated "trusted" package names)
#   CFG_AUDIT_DEVICE_ADMIN_ALLOWLIST       default "" (space-separated expected admin/owner pkgs)

# Marker so callers can detect a successful source.
SECURITY_AUDIT_LOADED=1

# Pure helper: maps a lockscreen.password_type code (AOSP DevicePolicyManager
# PASSWORD_QUALITY_* constant) to a human-readable label. Unit-testable without a device.
password_quality_label() {
  case "$1" in
    0|""|"null"|"None") printf 'NONE';;
    32768)     printf 'BIOMETRIC_WEAK';;
    65536)     printf 'PATTERN';;
    131072)    printf 'PIN_NUMERIC';;
    196608)    printf 'PIN_NUMERIC_COMPLEX';;
    262144)    printf 'PASSWORD_ALPHABETIC';;
    327680)    printf 'PASSWORD_ALPHANUMERIC';;
    393216)    printf 'PASSWORD_COMPLEX';;
    524288)    printf 'BIOMETRIC_STRONG';;
    *)         printf 'UNKNOWN(%s)' "$1";;
  esac
}

# Returns 0 if package $1 is present in space-separated allowlist $2.
_pkg_allowed() {
  local pkg="$1" allowlist="$2"
  case " ${allowlist} " in
    *" ${pkg} "*) return 0 ;;
  esac
  return 1
}

# Extract unique package names from "ComponentInfo{pkg/cls}" tokens found on stdin.
# Input: any text (e.g. `dumpsys device_policy` output). Lines without a ComponentInfo
# token are dropped; only the leading package (before '/' or '}') is emitted.
_pkglist_from_cinfo() {
  grep -oE 'ComponentInfo\{[^}]+\}' 2>/dev/null \
    | sed -E 's#ComponentInfo\{([^/}]+).*#\1#' 2>/dev/null \
    | grep -E '^[A-Za-z0-9_.]+$' 2>/dev/null || true
}

# run_security_audit <device> <sdk_int>
# Prints the "Deep Security Audit" block for one device. Always advisory; returns 0.
run_security_audit() {
  local device="$1"
  local sdk_int="$2"

  local max_age="${CFG_AUDIT_SECURITY_PATCH_MAX_AGE_DAYS:-120}"
  local strict_lock="${CFG_AUDIT_STRICT_LOCK_QUALITY:-0}"
  local acc_allow="${CFG_AUDIT_ACCESSIBILITY_ALLOWLIST:-}"
  local admin_allow="${CFG_AUDIT_DEVICE_ADMIN_ALLOWLIST:-}"
  local nl_allow="${CFG_AUDIT_NOTIFICATION_LISTENER_ALLOWLIST:-}"
  local autofill_allow="${CFG_AUDIT_AUTOFILL_ALLOWLIST:-}"
  local sms_allow="${CFG_AUDIT_SMS_DEFAULT_ALLOWLIST:-}"
  local assistant_allow="${CFG_AUDIT_ASSISTANT_ALLOWLIST:-}"

  echo "--------------------------------------------------------"
  echo "Deep Security Audit (advisory) for [${device}]"

  # --- 1. Unknown app sources (per-user) ---
  local users_raw user_ids u unkn
  users_raw=$(adb -s "${device}" shell pm list users 2>/dev/null | tr -d '\r' || true)
  user_ids=$(printf '%s\n' "${users_raw}" | grep -oE 'User [0-9]+:' | grep -oE '[0-9]+' | sort -u || true)
  [ -z "${user_ids}" ] && user_ids="0"
  local unsafe_sources=0
  for u in ${user_ids}; do
    if [ "${u}" = "0" ]; then
      unkn=$(adb -s "${device}" shell settings get secure install_non_market_apps 2>/dev/null | tr -d '\r\n' || true)
    else
      unkn=$(adb -s "${device}" shell settings --user "${u}" get secure install_non_market_apps 2>/dev/null | tr -d '\r\n' || true)
    fi
    if [ "${unkn}" = "1" ]; then
      echo "  Unknown Sources: [WARNING] user ${u} allows unknown-app installs (install_non_market_apps=1)"
      unsafe_sources=1
    fi
  done
  if [ "${unsafe_sources}" = "0" ]; then
    echo "  Unknown Sources: [OK] No user has unknown-app installs enabled"
  fi
  echo "  Unknown Sources: [NOTICE] Android 8+ (API 26+) uses per-app unknown-source prompts; setting is advisory"

  # --- 2. Lock screen credential quality ---
  # Modern Android (11+) no longer populates the legacy Settings.Secure
  # lockscreen.password_type key. Prefer dumpsys lock_settings CredentialType
  # (authoritative), then fall back to the legacy numeric code (older ROMs),
  # then to cmd lock_settings get-disabled.
  local ls_dump cred_type lock_type salt label gd lock_enrolled
  ls_dump=$(adb -s "${device}" shell dumpsys lock_settings 2>/dev/null | tr -d '\r' || true)
  cred_type=$(printf '%s\n%s\n' "${ls_dump}" | grep -E 'CredentialType:' | head -1 | awk '{print $2}' || true)
  lock_type=$(adb -s "${device}" shell settings get secure lockscreen.password_type 2>/dev/null | tr -d '\r\n' || true)
  salt=$(adb -s "${device}" shell settings get secure lockscreen.password_salt 2>/dev/null | tr -d '\r\n' || true)
  label=$(password_quality_label "${lock_type}")
  lock_enrolled=0

  # dumpsys emits CredentialType in UPPER CASE (PIN/PATTERN/PASSWORD/NONE); normalize.
  local ct
  ct=$(printf '%s' "${cred_type}" | tr '[:upper:]' '[:lower:]' 2>/dev/null || true)
  if [ -n "${ct}" ] && [ "${ct}" != "none" ]; then
    # Authoritative modern source resolved the credential type.
    lock_enrolled=1
    case "${ct}" in
      pin)
        echo "  Lock Quality: [OK] PIN configured — NOTE: PIN length is NOT verifiable via ADB"
        ;;
      pattern)
        if [ "${strict_lock}" = "1" ]; then
          echo "  Lock Quality: [WARNING] Pattern only — strict policy prefers PIN/password"
        else
          echo "  Lock Quality: [OK] Pattern configured"
        fi
        ;;
      password)
        echo "  Lock Quality: [OK] Strong credential configured (Password)"
        ;;
      *)
        echo "  Lock Quality: [OK] Credential configured (CredentialType=${cred_type})"
        ;;
    esac
  else
    # Fall back to the legacy numeric type, or declare no lock.
    case "${lock_type}" in
      0|""|"null"|"None")
        gd=$(adb -s "${device}" shell cmd lock_settings get-disabled 2>/dev/null | tr -d '\r\n' || true)
        if [ "${gd}" = "true" ]; then
          echo "  Lock Quality: [CRITICAL WARNING] Lock screen set to None (no credential)"
        else
          echo "  Lock Quality: [CRITICAL WARNING] NO lock screen credential detected"
        fi
        ;;
      32768)
        lock_enrolled=1
        echo "  Lock Quality: [WARNING] Weak biometric only (BIOMETRIC_WEAK) — pair with a PIN/password"
        ;;
      65536)
        lock_enrolled=1
        if [ "${strict_lock}" = "1" ]; then
          echo "  Lock Quality: [WARNING] Pattern only (PATTERN) — strict policy prefers PIN/password"
        else
          echo "  Lock Quality: [OK] Pattern configured (PATTERN)"
        fi
        ;;
      131072|196608)
        lock_enrolled=1
        echo "  Lock Quality: [OK] PIN configured (${label}) — NOTE: PIN length is NOT verifiable via ADB"
        ;;
      262144|327680|393216|524288)
        lock_enrolled=1
        echo "  Lock Quality: [OK] Strong credential configured (${label})"
        ;;
      *)
        echo "  Lock Quality: [NOTICE] Unrecognized password_type='${lock_type}' (${label})"
        ;;
    esac
    # Salt corroboration only when a real legacy credential type is reported.
    case "${lock_type}" in
      0|""|"null"|"None") : ;;
      *)
        if [ -z "${salt}" ] || [ "${salt}" = "0" ] || [ "${salt}" = "null" ] || [ "${salt}" = "None" ]; then
          echo "  Lock Quality: [WARNING] password_type set but salt empty — credential may not be enrolled"
        fi
        ;;
    esac
  fi

  # --- 3. Accessibility services (prime malware abuse vector) ---
  local acc_services entry pkg remaining total_acc unsafe_acc
  acc_services=$(adb -s "${device}" shell settings get secure enabled_accessibility_services 2>/dev/null | tr -d '\r\n' || true)
  total_acc=0
  unsafe_acc=""
  if [ -n "${acc_services}" ] && [ "${acc_services}" != "null" ]; then
    # Services are colon-separated "pkg/cls" entries; split portably (no bash arrays).
    remaining="${acc_services}"
    while [ -n "${remaining}" ]; do
      entry="${remaining%%:*}"
      case "${remaining}" in
        *:*) remaining="${remaining#*:}" ;;
        *)   remaining="" ;;
      esac
      [ -z "${entry}" ] && continue
      total_acc=$((total_acc + 1))
      pkg="${entry%%/*}"        # keep package (before any '/')
      pkg="${pkg%%\{*}"        # tolerate "ComponentInfo{pkg" form
      if [ -n "${pkg}" ] && ! _pkg_allowed "${pkg}" "${acc_allow}"; then
        unsafe_acc="${unsafe_acc}${unsafe_acc:+ }${pkg}"
      fi
    done
  fi
  if [ "${total_acc}" -eq 0 ]; then
    echo "  Accessibility Services: [OK] No accessibility services enabled"
  elif [ -n "${unsafe_acc}" ]; then
    echo "  Accessibility Services: [WARNING] Non-allowlisted service(s) active: ${unsafe_acc}"
  else
    echo "  Accessibility Services: [OK] ${total_acc} enabled service(s) all on allowlist"
  fi

  # --- 4. Device Admin / Device Policy Controller (DPC) ---
  local dp do_block do_pkg po_lines raw_admins admin_pkgs p
  dp=$(adb -s "${device}" shell dumpsys device_policy 2>/dev/null | tr -d '\r' || true)
  # Device Owner: the ComponentInfo{pkg} sits on/near the "Device Owner" line.
  do_block=$(printf '%s\n%s\n' "${dp}" | grep -iA4 'device owner' 2>/dev/null || true)
  do_pkg=$(printf '%s\n%s\n' "${do_block}" | _pkglist_from_cinfo | head -1 || true)
  po_lines=$(printf '%s\n%s\n' "${dp}" | grep -icE 'profile owner' 2>/dev/null || true)
  po_lines="${po_lines:-0}"
  raw_admins=$(printf '%s\n%s\n' "${dp}" | _pkglist_from_cinfo | sort -u 2>/dev/null || true)
  admin_pkgs=""
  while IFS= read -r p; do
    [ -n "${p}" ] && admin_pkgs="${admin_pkgs}${admin_pkgs:+ }${p}"
  done <<< "${raw_admins}"
  if [ -n "${do_pkg}" ]; then
    if _pkg_allowed "${do_pkg}" "${admin_allow}"; then
      echo "  Device Policy: [OK] Device Owner present and allowlisted (${do_pkg})"
    else
      echo "  Device Policy: [WARNING] Unexpected Device Owner detected (${do_pkg}) — verify this is intended (e.g. MDM)"
    fi
  else
    echo "  Device Policy: [OK] No Device Owner (typical for personal devices)"
  fi
  if [ "${po_lines:-0}" -gt 0 ]; then
    echo "  Device Policy: [NOTICE] ${po_lines} Profile Owner record(s) present (work/managed profile)"
  fi
  if [ -n "${admin_pkgs}" ]; then
    local unexpected_admins=""
    for p in ${admin_pkgs}; do
      if ! _pkg_allowed "${p}" "${admin_allow}"; then
        unexpected_admins="${unexpected_admins}${unexpected_admins:+ }${p}"
      fi
    done
    if [ -n "${unexpected_admins}" ]; then
      echo "  Device Policy: [WARNING] Active Device Admin(s) not on allowlist: ${unexpected_admins}"
    else
      echo "  Device Policy: [OK] Active Device Admin(s) all allowlisted: ${admin_pkgs}"
    fi
  else
    echo "  Device Policy: [OK] No active Device Admin components"
  fi

  # --- 5. Security patch freshness + boot-time lock ---
  local patch age_days lock_disabled
  patch=$(adb -s "${device}" shell getprop ro.build.version.security_patch 2>/dev/null | tr -d '\r\n' || true)
  if printf '%s' "${patch}" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    age_days=$(python3 -c 'import sys,datetime; p=datetime.datetime.strptime(sys.argv[1],"%Y-%m-%d").date(); print((datetime.date.today()-p).days)' "${patch}" 2>/dev/null || true)
    if [ -n "${age_days}" ] && [ "${age_days}" -gt "${max_age}" ] 2>/dev/null; then
      echo "  Security Patch: [WARNING] Patch ${patch} is ${age_days} days old (threshold: ${max_age} days)"
    elif [ -n "${age_days}" ]; then
      echo "  Security Patch: [OK] ${patch} (${age_days} days old, within ${max_age}-day threshold)"
    else
      echo "  Security Patch: [NOTICE] Patch string '${patch}' present but age could not be computed"
    fi
  else
    echo "  Security Patch: [NOTICE] No parseable security patch date (got '${patch}')"
  fi
  lock_disabled=$(adb -s "${device}" shell settings get secure lockscreen.disabled 2>/dev/null | tr -d '\r\n' || true)
  if [ "${lock_disabled}" = "1" ]; then
    echo "  Boot-Time Lock: [WARNING] lockscreen.disabled=1 — credential may be bypassed at boot"
  elif [ "${lock_enrolled}" = "1" ]; then
    echo "  Boot-Time Lock: [OK] Credential required at boot (Direct Boot); tied to lock-screen enrollment"
  else
    echo "  Boot-Time Lock: [WARNING] No credential enrolled — device boots without unlock (Direct Boot unprotected)"
  fi

  # --- 6. USB default mode ---
  local adb_en usb_cfg
  adb_en=$(adb -s "${device}" shell settings get global adb_enabled 2>/dev/null | tr -d '\r\n' || true)
  usb_cfg=$(adb -s "${device}" shell getprop persist.sys.usb.config 2>/dev/null | tr -d '\r\n' || true)
  if [ "${adb_en}" = "1" ]; then
    echo "  USB Mode: [NOTICE] USB Debugging ENABLED (adb_enabled=1) — data/debug mode; run 'make lockdown' for charge-only posture"
  elif printf '%s' "${usb_cfg}" | grep -qi 'adb'; then
    echo "  USB Mode: [NOTICE] USB default config includes 'adb' (${usb_cfg})"
  else
    echo "  USB Mode: [OK] ADB disabled; USB defaults to charge/file-transfer-on-prompt ('${usb_cfg}')"
  fi

  # --- 7. Wireless debugging (distinct network ADB surface, API 30+) ---
  local adb_wifi
  adb_wifi=$(adb -s "${device}" shell settings get global adb_wifi_enabled 2>/dev/null | tr -d '\r\n' || true)
  case "${adb_wifi}" in
    1) echo "  Wireless Debugging: [WARNING] ENABLED (adb_wifi_enabled=1) — exposes an unauthenticated ADB port on the network" ;;
    0) echo "  Wireless Debugging: [OK] Disabled" ;;
    *) echo "  Wireless Debugging: [NOTICE] state unknown ('${adb_wifi}'); not supported on this Android version" ;;
  esac

  # --- 8. Notification listeners (read ALL notifications incl. 2FA) ---
  local nl nl_entry nl_pkg nl_remaining nl_total nl_unsafe
  nl=$(adb -s "${device}" shell settings get secure enabled_notification_listeners 2>/dev/null | tr -d '\r\n' || true)
  nl_total=0
  nl_unsafe=""
  if [ -n "${nl}" ] && [ "${nl}" != "null" ]; then
    nl_remaining="${nl}"
    while [ -n "${nl_remaining}" ]; do
      nl_entry="${nl_remaining%%:*}"
      case "${nl_remaining}" in *:*) nl_remaining="${nl_remaining#*:}" ;; *) nl_remaining="" ;; esac
      [ -z "${nl_entry}" ] && continue
      nl_total=$((nl_total + 1))
      nl_pkg="${nl_entry%%/*}"
      nl_pkg="${nl_pkg%%\{*}"
      if [ -n "${nl_pkg}" ] && ! _pkg_allowed "${nl_pkg}" "${nl_allow}"; then
        nl_unsafe="${nl_unsafe}${nl_unsafe:+ }${nl_pkg}"
      fi
    done
  fi
  if [ "${nl_total}" -eq 0 ]; then
    echo "  Notification Listeners: [OK] No notification listeners enabled"
  elif [ -n "${nl_unsafe}" ]; then
    echo "  Notification Listeners: [WARNING] Non-allowlisted listener(s) active: ${nl_unsafe}"
  else
    echo "  Notification Listeners: [OK] ${nl_total} listener(s) all on allowlist"
  fi

  # --- 9. Autofill service (reads everything typed) ---
  local af af_pkg
  af=$(adb -s "${device}" shell settings get secure autofill_service 2>/dev/null | tr -d '\r\n' || true)
  if [ -z "${af}" ] || [ "${af}" = "null" ]; then
    echo "  Autofill Service: [OK] No autofill service set"
  else
    af_pkg="${af%%/*}"
    af_pkg="${af_pkg%%\{*}"
    if [ -n "${af_pkg}" ] && _pkg_allowed "${af_pkg}" "${autofill_allow}"; then
      echo "  Autofill Service: [OK] Allowlisted (${af_pkg})"
    else
      echo "  Autofill Service: [WARNING] Non-allowlisted autofill service: ${af_pkg}"
    fi
  fi

  # --- 10. Default SMS app (2FA interception) ---
  local sms_pkg
  sms_pkg=$(adb -s "${device}" shell settings get secure sms_default_application 2>/dev/null | tr -d '\r\n' || true)
  if [ -z "${sms_pkg}" ] || [ "${sms_pkg}" = "null" ]; then
    echo "  Default SMS App: [OK] System default"
  elif _pkg_allowed "${sms_pkg}" "${sms_allow}"; then
    echo "  Default SMS App: [OK] Allowlisted (${sms_pkg})"
  else
    echo "  Default SMS App: [WARNING] Non-allowlisted default SMS app: ${sms_pkg}"
  fi

  # --- 11. Default assistant (sees screen/voice) ---
  local asst_pkg
  asst_pkg=$(adb -s "${device}" shell settings get secure assistant 2>/dev/null | tr -d '\r\n' || true)
  [ -z "${asst_pkg}" ] || [ "${asst_pkg}" = "null" ] && \
    asst_pkg=$(adb -s "${device}" shell settings get secure voice_interaction_service 2>/dev/null | tr -d '\r\n' || true)
  if [ -z "${asst_pkg}" ] || [ "${asst_pkg}" = "null" ]; then
    echo "  Default Assistant: [OK] System default"
  elif _pkg_allowed "${asst_pkg}" "${assistant_allow}"; then
    echo "  Default Assistant: [OK] Allowlisted (${asst_pkg})"
  else
    echo "  Default Assistant: [WARNING] Non-allowlisted assistant: ${asst_pkg}"
  fi

  # --- 12. Lock-after-timeout (delay screen-off -> credential required) ---
  local lat lat_sec
  lat=$(adb -s "${device}" shell settings get secure lock_screen_lock_after_timeout 2>/dev/null | tr -d '\r\n' || true)
  if [ -z "${lat}" ] || [ "${lat}" = "null" ]; then
    echo "  Lock-After-Timeout: [NOTICE] unset (system default delay before credential is required)"
  elif printf '%s' "${lat}" | grep -qE '^[0-9]+$'; then
    lat_sec=$((lat / 1000))
    if [ "${lat}" -gt 30000 ]; then
      echo "  Lock-After-Timeout: [WARNING] ${lat_sec}s (${lat}ms) — credential reachable for >30s after screen-off"
    else
      echo "  Lock-After-Timeout: [OK] ${lat_sec}s (${lat}ms) after screen-off"
    fi
  else
    echo "  Lock-After-Timeout: [NOTICE] unparseable value '${lat}'"
  fi

  # --- 13. Play Protect / package verification ---
  local pve uae
  pve=$(adb -s "${device}" shell settings get global package_verifier_enable 2>/dev/null | tr -d '\r\n' || true)
  uae=$(adb -s "${device}" shell settings get global upload_apk_enable 2>/dev/null | tr -d '\r\n' || true)
  case "${pve}" in
    0) echo "  Package Verification: [WARNING] DISABLED (package_verifier_enable=0) — apps not verified on install" ;;
    1|""|"null") echo "  Package Verification: [OK] Enabled (default)" ;;
    *) echo "  Package Verification: [NOTICE] state '${pve}'" ;;
  esac
  case "${uae}" in
    0) echo "  Play Protect Upload: [NOTICE] upload_apk_enable=0 — unknown apps not shared with Google for scanning" ;;
    1|""|"null") echo "  Play Protect Upload: [OK] Enabled (default)" ;;
    *) echo "  Play Protect Upload: [NOTICE] state '${uae}'" ;;
  esac

  # --- 14. Storage encryption (FBE) ---
  local ctype cstate
  ctype=$(adb -s "${device}" shell getprop ro.crypto.type 2>/dev/null | tr -d '\r\n' || true)
  cstate=$(adb -s "${device}" shell getprop ro.crypto.state 2>/dev/null | tr -d '\r\n' || true)
  case "${cstate}" in
    encrypted) echo "  Storage Encryption: [OK] Encrypted (ro.crypto.type=${ctype:-unknown})" ;;
    unencrypted) echo "  Storage Encryption: [CRITICAL WARNING] Storage NOT encrypted" ;;
    *) echo "  Storage Encryption: [NOTICE] state '${cstate}' (type='${ctype}')" ;;
  esac

  echo "--------------------------------------------------------"
  return 0
}
