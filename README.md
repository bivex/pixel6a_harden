# System Specification: Android Automation & Security Hardening Framework (`pixel_setup`)

**Document Standard:** ISO/IEC/IEEE 26514:2022 Compliant Technical Documentation  
**System Identifier:** PS-FWK-2026.1  
**Classification:** Technical Specification & Operational Guide  

---

## 1. Scope and Purpose

This document specifies the architecture, configuration interfaces, and operational procedures for the `pixel_setup` automation framework. The framework provides automated initialization, state enforcement, and security hardening for Android mobile devices (specifically Google Pixel series) via Android Debug Bridge (ADB) protocols and Ansible configuration management.

Primary objectives:
* Standardize mobile device operating system parameters across single or multiple connected hardware endpoints.
* Enforce security hardening baselines (screen lock policies, anti-tracking controls, package verification).
* Provide dynamic device discovery without hardcoded persistent device serial numbers or credentials.

---

## 2. Architecture and Repository Structure

The framework is organized into modular components adhering to standard separation of concerns:

```text
pixel_setup/
├── config/
│   └── default_settings.yml       # Centralized configuration parameters
├── inventory/
│   ├── adb_dynamic_inventory.py   # Executable inventory script for dynamic ADB discovery
│   └── hosts.ini                  # Static inventory configuration template
├── playbooks/
│   ├── setup.yml                  # Ansible playbook for standard device configuration
│   └── harden.yml                 # Ansible playbook for security baseline enforcement
├── scripts/
│   ├── setup.sh                   # Standalone POSIX shell script for standard setup
│   └── harden.sh                  # Standalone POSIX shell script for security hardening
├── .gitignore                     # Version control exclusions file
├── Makefile                       # Command execution entrypoints
├── requirements.yml               # Ansible Galaxy collection dependencies
└── README.md                      # ISO-compliant technical documentation
```

---

## 3. Prerequisites and System Dependencies

### 3.1 Host System Requirements

* **Operating System:** POSIX-compliant system (macOS, Linux, BSD).
* **Android Debug Bridge (ADB):** Platform tools version 34.0.0 or higher.
* **Python Runtime:** Python 3.8 or higher (required for dynamic inventory execution).
* **Ansible Core (Optional):** Version 2.15 or higher (required for Ansible playbook execution).

### 3.2 Target Device Requirements

* **Device State:** Powered on, connected via USB or TCP/IP ADB.
* **Developer Options:** USB Debugging enabled (`adb_enabled = 1`).
* **Authorization:** Host public key accepted on target endpoint.

---

## 4. Configuration Specification

System configuration parameters are centrally defined in `config/default_settings.yml`.

### 4.1 Parameter Reference

| Parameter Name | Data Type | Standard Baseline | Hardened Baseline | Description |
| :--- | :--- | :--- | :--- | :--- |
| `screen_timeout_ms` | Integer | `600000` (10 min) | `30000` (30 sec) | Display inactivity lock timeout in milliseconds. |
| `stay_awake_plugged` | Integer | `7` (AC/USB/Wireless) | `0` (Disabled) | Controls whether display remains illuminated while charging. |
| `dark_mode_code` | Integer | `2` (Enabled) | `2` (Enabled) | UI night mode state setting. |
| `animation_scale_fast` | String | `"0.5"` | `"0.5"` | Window, transition, and animator duration scale multiplier. |
| `private_notifications_hidden` | Integer | N/A | `0` (Hidden) | Hides sensitive notification content on locked screen. |
| `power_button_instantly_locks` | Integer | N/A | `1` (Enabled) | Forces immediate device locking upon power button engagement. |
| `wifi_scan_always_enabled` | Integer | N/A | `0` (Disabled) | Disables background Wi-Fi location scanning. |
| `ble_scan_always_enabled` | Integer | N/A | `0` (Disabled) | Disables background Bluetooth LE location scanning. |
| `allow_unknown_sources` | Integer | N/A | `0` (Blocked) | Restricts package installation from non-market sources. |
| `verify_adb_installs` | Integer | N/A | `1` (Enabled) | Enforces package verification on sideloaded applications. |

---

## 5. Operational Procedures

### 5.1 Device Inspection Procedure

To audit connected target endpoints prior to task execution:

```bash
make info
```

### 5.2 Standard Device Setup

Executes baseline UI optimizations, display timeouts, and network interfaces.

#### Option A: Standalone Execution (POSIX Shell)
```bash
./scripts/setup.sh
# or via Makefile:
make setup
```

#### Option B: Ansible Automation
```bash
ansible-playbook -i inventory/adb_dynamic_inventory.py playbooks/setup.yml
# or via Makefile:
make setup-ansible
```

### 5.3 Security Hardening Baseline Enforcement

Enforces strict access controls, lock screen policies, and privacy controls.

#### Option A: Standalone Execution (POSIX Shell)
```bash
./scripts/harden.sh
# or via Makefile:
make harden
```

#### Option B: Ansible Automation
```bash
ansible-playbook -i inventory/adb_dynamic_inventory.py playbooks/harden.yml
# or via Makefile:
make harden-ansible
```

---

## 6. Multi-Device and Environmental Controls

### 6.1 Dynamic Discovery Mechanism

The framework automatically discovers all connected and authorized ADB endpoints. No explicit hardware serial numbers are required in static configuration files.

### 6.2 Explicit Endpoint Targeting

To restrict execution to a single specific device among multiple connected targets, export the `ANDROID_SERIAL` environment variable:

```bash
export ANDROID_SERIAL="24231JEGR15843"
make harden
```

---

## 7. Compliance and Verification

All execution scripts return standard POSIX exit status codes (`0` for success, non-zero for failure). Command execution logs emit structured `[INFO]`, `[SUCCESS]`, and `[ERROR]` status indicators for integration with automated CI/CD pipelines.
