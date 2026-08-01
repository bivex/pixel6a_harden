.PHONY: deps info setup harden setup-ansible harden-ansible wifi-connect

# Install required Ansible galaxy collection
deps:
	ansible-galaxy collection install -r requirements.yml

# Fast check device info via ADB shell
info:
	@echo "Checking connected ADB device info..."
	@adb shell "echo 'Model:' \$$(getprop ro.product.model); echo 'Brand:' \$$(getprop ro.product.brand); echo 'Android:' \$$(getprop ro.build.version.release); echo 'Battery:' \$$(dumpsys battery | grep level)"

# Run standard setup via shell script (supports 1 or many connected devices)
setup:
	./scripts/setup.sh

# Run security hardening via shell script (supports 1 or many connected devices)
harden:
	./scripts/harden.sh

# Run standard setup via Ansible with Dynamic ADB Inventory
setup-ansible:
	ansible-playbook -i inventory/adb_dynamic_inventory.py playbooks/setup.yml

# Run security hardening via Ansible with Dynamic ADB Inventory
harden-ansible:
	ansible-playbook -i inventory/adb_dynamic_inventory.py playbooks/harden.yml

# Helper to enable ADB over Wi-Fi
wifi-connect:
	@echo "Enabling ADB over TCP/IP port 5555..."
	adb tcpip 5555
