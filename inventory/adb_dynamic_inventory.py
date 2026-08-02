#!/usr/bin/env python3
"""
Dynamic Ansible Inventory for ADB Devices.
Discovers all currently connected and authorized ADB devices.
Prints diagnostic messages to stderr on errors.
"""
import json
import subprocess
import sys

def get_adb_devices():
    try:
        proc = subprocess.run(["adb", "devices"], capture_output=True, text=True, check=True)
        output = proc.stdout
    except FileNotFoundError:
        print("[ERROR] adb CLI tool not found in PATH.", file=sys.stderr)
        return []
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] adb devices command failed with code {e.returncode}: {e.stderr}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"[ERROR] Unexpected error while fetching adb devices: {e}", file=sys.stderr)
        return []

    devices = []
    for line in output.strip().splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            serial, state = parts[0], parts[1]
            if state == "device":
                devices.append(serial)
            else:
                print(f"[WARNING] Skipping device {serial} in state '{state}' (unauthorized or offline)", file=sys.stderr)
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
        print(json.dumps(inventory))

if __name__ == "__main__":
    main()
