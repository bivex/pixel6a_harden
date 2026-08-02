# Pixel Automation & Security Hardening Framework (`pixel_setup`)

A Staff-Grade, production-ready DevSecOps automation and security hardening framework for **Google Pixel** and **Android** devices using **Ansible** and **POSIX shell scripts**.

---

## 🔑 Key Architectural Highlights

* **Single Source of Truth Configuration**: `config/default_settings.yml` is parsed dynamically by both Ansible playbooks and POSIX shell scripts (`scripts/parse_config.py`).
* **Shell Injection Safety**: Environment variable generation uses Python's `shlex.quote()` to ensure safe evaluation (`eval "$(...)`) regardless of YAML values.
* **Active Post-Write & Rollback Verification**: Every setting applied via `settings put` (both setup/harden and rollback) is verified immediately via `settings get` to guarantee write execution.
* **Pre-Flight Key Support & Unsupported Key Handling**: Checks if keys exist on the target ROM/framework before writing, preventing false positive `[PASS]` reports on custom or vendor ROMs.
* **Hardened & Integrity-Protected Backups**: Automatically restricts backup file permissions (`chmod 700/600`), saves managed setting baselines (`managed_keys.txt`), generates `checksums.sha256`, and enforces SHA-256 integrity verification before `make rollback` to prevent tampered or corrupted rollbacks.
* **Hardware & Runtime Attestation Inspection**: `make info` and pre-flight checks inspect SELinux enforcement (`getenforce`), Verified Boot state (`ro.boot.verifiedbootstate`), Bootloader lock state (`ro.boot.flash.locked`), Build & Debug profile (`ro.debuggable`), and Root / `su` binary presence.
* **Dedicated Audit Mode (`make audit`)**: Inspects device compliance against the security baseline without making any state changes.
* **SDK_INT & Capability Awareness**: Detects target Android API levels (`ro.build.version.sdk`) and checks key support before execution.
* **Lock Screen Prerequisite Auditing**: Checks for configured lock screen PINs/patterns and warns if lock screen policies are inactive.
* **Local Git Hooks & Unit Testing**: Local git pre-commit hook support (`make install-hooks`), static shell check (`make lint`), and comprehensive Python unit test suite with subprocess mocks and end-to-end bash eval injection testing (`tests/test_config.py`).

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
│   ├── setup.yml                  # Ansible setup playbook (Experimental Alternative)
│   └── harden.yml                 # Ansible security hardening playbook (Experimental Alternative)
├── scripts/
│   ├── parse_config.py            # PyYAML parser with shlex shell-quoting (--env/--json exports)
│   ├── managed_keys.sh            # Shared Single Source of Truth managed keys array
│   ├── info.sh                    # Multi-device SDK_INT & lock status inspection script
│   ├── setup.sh                   # POSIX setup script with active setting verification & auto-backup
│   ├── harden.sh                  # POSIX hardening, audit & lockdown script
│   ├── backup.sh                  # Automated managed & forensic setting backup script
│   ├── rollback.sh                # Targeted setting rollback script with metadata affinity checks
│   └── install_hooks.sh           # Local git pre-commit hook installer
├── tests/
│   └── test_config.py             # Python unit test suite with subprocess & end-to-end bash eval mocks
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

3. **Lockdown & ADB Rollback Unavailability Warning (`make lockdown`)**:
   * Running `make lockdown` or configuring `disable_adb_debugging: 1` disables the ADB daemon on the target device.
   * **ADB-based rollback (`make rollback`) requires an active ADB connection and cannot connect once ADB is disabled.** Ensure you have tested your configuration before applying final lockdown.

4. **Execution Paths**:
   * The **POSIX shell scripts** (`make setup`, `make harden`, `make rollback`, `make audit`) serve as the primary Staff-Grade execution engine, providing active post-write verification, pre-flight lock screen checks, SDK gating, and device affinity validation.
   * The **Ansible playbooks** (`make setup-ansible`, `make harden-ansible`) are maintained as an experimental alternative for Ansible-centric environments.

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
| `disable_developer_options` | `0` | `1` (on lockdown) | Disables Developer Options menu |
| `disable_adb_debugging` | `0` | `1` (on lockdown) | Disables ADB USB debugging interface |
