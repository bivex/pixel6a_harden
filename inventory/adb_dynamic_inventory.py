#!/usr/bin/env python3
"""
Dynamic Ansible Inventory for ADB Devices.
Discovers all currently connected and authorized ADB devices.
"""
import json
import subprocess
import sys

def get_adb_devices():
    try:
        output = subprocess.check_output(["adb", "devices"], text=True)
    except Exception as e:
        return []

    devices = []
    for line in output.strip().splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])
    return devices

def main():
    devices = get_adb_devices()
    inventory = {
        "_meta": {
            "hostvars": {}
        },
        "pixel_devices": {
            "hosts": devices,
            "vars": {
                "ansible_connection": "community.general.adb"
            }
        }
    }

    for dev in devices:
        inventory["_meta"]["hostvars"][dev] = {
            "adb_target": dev
        }

    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        print(json.dumps(inventory, indent=2))
    else:
        print(json.dumps({"_meta": {"hostvars": {}}}))

if __name__ == "__main__":
    main()
