.PHONY: deps info setup harden lockdown audit backup rollback test wifi-connect wifi-disconnect usb

# Install required Ansible galaxy collection
deps:
	ansible-galaxy collection install -r requirements.yml

# Fast check all connected ADB devices info and SDK_INT API levels
info:
	./scripts/info.sh

# Run standard setup via shell script (idempotent with auto-backup)
setup:
	./scripts/setup.sh

# Run security hardening via shell script (idempotent with auto-backup)
harden:
	./scripts/harden.sh

# Run audit mode only (does NOT modify device settings)
audit:
	./scripts/harden.sh --audit

# Run automated backup of all device settings
backup:
	./scripts/backup.sh

# Rollback device settings from latest backup
rollback:
	./scripts/rollback.sh

# Run automated unit test suite
test:
	python3 tests/test_config.py

# Run full security hardening AND disable ADB Debugging & Developer Options
lockdown:
	./scripts/harden.sh --lockdown -y

# Run standard setup via Ansible with Dynamic ADB Inventory
setup-ansible:
	ansible-playbook -i inventory/adb_dynamic_inventory.py playbooks/setup.yml

# Run security hardening via Ansible with Dynamic ADB Inventory
harden-ansible:
	ansible-playbook -i inventory/adb_dynamic_inventory.py playbooks/harden.yml

# Helper to enable ADB over Wi-Fi (SECURITY WARNING: Network ADB is unauthenticated!)
wifi-connect:
	@echo "[WARNING] Enabling ADB over TCP/IP port 5555 opens unauthenticated network access!"
	@echo "[WARNING] Ensure your local Wi-Fi network is secure, and run 'make usb' when finished."
	adb tcpip 5555

# Helper to reset ADB interface to USB-only mode
wifi-disconnect usb:
	@echo "Resetting ADB interface to USB mode..."
	adb usb
