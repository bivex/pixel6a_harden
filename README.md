# Pixel Automation & Security Hardening Framework (`pixel_setup`)

A Staff-Grade, production-ready DevSecOps automation and security hardening framework for **Google Pixel** and **Android** devices using **Ansible** and **POSIX shell scripts**.

---

## 🔑 Key Architectural Highlights

* **Single Source of Truth Configuration**: `config/default_settings.yml` is parsed dynamically by both Ansible playbooks and POSIX shell scripts (`scripts/parse_config.py`).
* **Shell Injection Safety**: Environment variable generation uses Python's `shlex.quote()` to ensure safe evaluation (`eval "$(...)`) regardless of YAML values.
* **Active Setting Verification**: Every setting applied via `settings put` is verified immediately via `settings get` to prevent false positive reports.
* **Idempotency**: All operations check existing device state before writing. Compliant settings are reported as `[SKIP]` without redundant mutations.
* **Automated Surgical Backup & Rollback**: Automatically saves managed setting baselines (`managed_keys.txt`) and full forensic dumps to `backups/` (excluded from git via `.gitignore`). Full targeted rollback is available via `make rollback` with per-device isolation.
* **Dedicated Audit Mode (`make audit`)**: Inspects device compliance against the security baseline without making any state changes.
* **SDK_INT & Capability Awareness**: Detects target Android API levels (`ro.build.version.sdk`) and checks key support before execution.
* **Lock Screen Prerequisite Auditing**: Checks for configured lock screen PINs/patterns and warns if lock screen policies are inactive.
* **Local Git Hooks & Unit Testing**: Local git pre-commit hook support (`make install-hooks`), static shell check (`make lint`), and comprehensive Python unit test suite with `unittest.mock` (`tests/test_config.py`).

---

## 📁 Repository Structure

```text
pixel_setup/
├── config/
│   └── default_settings.yml       # Single Source of Truth configuration file
├── inventory/
│   ├── adb_dynamic_inventory.py   # Dynamic Ansible inventory script
│   └── hosts.ini                  # Static inventory configuration template
├── playbooks/
│   ├── setup.yml                  # Ansible setup playbook
│   └── harden.yml                 # Ansible security hardening playbook
├── scripts/
│   ├── parse_config.py            # PyYAML parser with shlex shell-quoting (--env/--json exports)
│   ├── info.sh                    # Multi-device SDK_INT & lock status inspection script
│   ├── setup.sh                   # POSIX setup script with active setting verification & auto-backup
│   ├── harden.sh                  # POSIX hardening, audit & lockdown script
│   ├── backup.sh                  # Automated managed & forensic setting backup script
│   ├── rollback.sh                # Targeted setting rollback script with multi-device checks
│   └── install_hooks.sh           # Local git pre-commit hook installer
├── tests/
│   └── test_config.py             # Python unit test suite with subprocess mocking
├── .github/
│   └── workflows/
│       └── ci.yml                 # GitHub Actions CI workflow
├── .gitignore                     # Git exclusions (excludes local backups/)
├── Makefile                       # Unified operational shortcuts
├── requirements.yml               # Ansible Galaxy dependencies
└── README.md                      # Technical documentation
```

---

## ⚠️ Important Prerequisites & Security Warnings

1. **Lock Screen PIN/Pattern Prerequisite**:
   * Android system settings such as `screen_off_timeout` and `lockscreen.power_button_instantly_locks` **only take effect if a screen lock PIN, Pattern, or Password is set on the device**.
   * ADB cannot programmatically create a screen lock PIN/Password. You **must** configure a PIN/Pattern manually in *Android Settings -> Security & Privacy*.

2. **Network ADB Security Warning (`make wifi-connect`)**:
   * Running `adb tcpip 5555` opens an unauthenticated network ADB port on the target device.
   * Only use network ADB on trusted, isolated Wi-Fi networks. Run `make usb` or reboot the device when finished to revert to USB-only mode.

---

## 🚀 Operational Instructions

### 1. Inspect Connected Devices & SDK Levels

```bash
make info
```

### 2. Audit Device Compliance Without Making Changes

```bash
make audit
```

### 3. Create Baseline Settings Backup

```bash
make backup
```

### 4. Standard Device Setup (Idempotent + Auto-Backup)

```bash
make setup
```

### 5. Security Hardening Baseline (Idempotent + Auto-Backup)

```bash
make harden
```

### 6. Restore Device Settings From Backup

```bash
make rollback
```

### 7. Install Local Git Pre-Commit Hook

```bash
make install-hooks
```

### 8. Run Unit Tests & Linting

```bash
make test
make lint
```

### 9. Final Device Lockdown (Disables Developer Options & ADB)

```bash
make lockdown
```

---

## 🛠 Configuration Reference (`config/default_settings.yml`)

| Parameter | Standard Baseline | Hardened Baseline | Description |
| :--- | :--- | :--- | :--- |
| `screen_timeout_ms` | `600000` (10 min) | `30000` (30 sec) | Display inactivity timeout in milliseconds |
| `stay_awake_plugged_hardened` | `7` (Enabled) | `0` (Disabled) | Controls whether screen stays on while charging |
| `dark_mode_code` | `2` (Enabled) | `2` (Enabled) | Forces UI Night Mode (Dark Theme) |
| `animation_scale_fast` | `"0.5"` | `"0.5"` | UI animation duration multiplier |
| `private_notifications_hidden` | N/A | `0` (Hidden) | Hides sensitive notification content on lock screen |
| `power_button_instantly_locks` | N/A | `1` (Enabled) | Forces instant lock when power button is pressed |
| `show_password_characters` | N/A | `0` (Hidden) | Hides password characters as typed (anti-shoulder surfing) |
| `mobile_data_always_on` | N/A | `0` (Disabled) | Disables background cellular modem when connected to Wi-Fi |
| `trust_agents_extend_unlock` | N/A | `0` (Disabled) | Disables Smart Lock unlock extension agents |
| `private_dns_mode` | N/A | `"hostname"` | Strict Encrypted Private DNS over TLS |
| `private_dns_provider` | N/A | `"dns.adguard-dns.com"` | Encrypted DNS provider hostname |
| `wifi_scan_always_enabled` | N/A | `0` (Disabled) | Blocks background Wi-Fi location scanning |
| `ble_scan_always_enabled` | N/A | `0` (Disabled) | Blocks background Bluetooth LE location scanning |
| `allow_unknown_sources` | N/A | `0` (Blocked) | Restricts non-market package installations |
| `verify_adb_installs` | N/A | `1` (Enabled) | Enforces Play Protect scanning on sideloaded apps |
