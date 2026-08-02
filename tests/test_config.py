#!/usr/bin/env python3
"""
Staff-Grade Unit Test Suite for pixel_setup framework.
Tests configuration parsing, PyYAML fallback, shell quoting safety,
and dynamic ADB inventory generation using subprocess mocks.
"""
import unittest
from unittest.mock import patch, MagicMock
import os
import sys
import tempfile
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
SCRIPTS_DIR = os.path.join(PROJECT_ROOT, "scripts")
INVENTORY_DIR = os.path.join(PROJECT_ROOT, "inventory")

sys.path.insert(0, SCRIPTS_DIR)
sys.path.insert(0, INVENTORY_DIR)

import parse_config
import adb_dynamic_inventory

class TestConfigParser(unittest.TestCase):
    def test_config_file_exists(self):
        config_path = os.path.join(PROJECT_ROOT, "config", "default_settings.yml")
        self.assertTrue(os.path.exists(config_path), "default_settings.yml must exist")

    def test_load_yaml(self):
        config_path = os.path.join(PROJECT_ROOT, "config", "default_settings.yml")
        cfg = parse_config.load_yaml(config_path)
        self.assertIn("screen_timeout_ms", cfg)
        self.assertIn("private_dns_provider", cfg)
        self.assertEqual(cfg["private_dns_provider"], "dns.adguard-dns.com")

    def test_fallback_parser_with_tempfile(self):
        sample_yaml = """
# Test YAML comment
screen_timeout_ms: 30000
private_dns_mode: "hostname"
is_active: true
"""
        with tempfile.NamedTemporaryFile("w+", delete=False) as f:
            f.write(sample_yaml)
            tmp_name = f.name

        try:
            parsed = parse_config.load_yaml(tmp_name)
            self.assertEqual(parsed["screen_timeout_ms"], 30000)
            self.assertEqual(parsed["private_dns_mode"], "hostname")
            self.assertTrue(parsed["is_active"])
        finally:
            os.remove(tmp_name)

    def test_shlex_quoting_end_to_end_bash_eval(self):
        canary_path = os.path.join(tempfile.gettempdir(), f"pwned_canary_{os.getpid()}")
        if os.path.exists(canary_path):
            os.remove(canary_path)

        malicious_payload = f'x"; touch {canary_path}; echo "'
        sample_yaml = f"""
private_dns_provider: '{malicious_payload}'
"""
        with tempfile.NamedTemporaryFile("w+", delete=False) as f:
            f.write(sample_yaml)
            tmp_yaml_path = f.name

        try:
            import shlex
            import io
            from contextlib import redirect_stdout
            
            with patch("parse_config.load_yaml", return_value={"private_dns_provider": malicious_payload}):
                buf = io.StringIO()
                orig_argv = sys.argv
                try:
                    sys.argv = ["parse_config.py", "--env"]
                    with redirect_stdout(buf):
                        parse_config.main()
                finally:
                    sys.argv = orig_argv
                env_output = buf.getvalue()

            bash_cmd = f'{env_output}\necho "$CFG_PRIVATE_DNS_PROVIDER"'
            bash_proc = subprocess.run(
                ["bash", "-c", bash_cmd],
                capture_output=True,
                text=True,
                check=True
            )

            # 1. Assert canary file was NOT created (no command injection occurred)
            self.assertFalse(os.path.exists(canary_path), "Security failure: Command injection payload executed!")

            # 2. Assert bash evaluated variable holds literal payload
            self.assertEqual(bash_proc.stdout.strip(), malicious_payload)
        finally:
            if os.path.exists(tmp_yaml_path):
                os.remove(tmp_yaml_path)
            if os.path.exists(canary_path):
                os.remove(canary_path)

class TestDynamicInventory(unittest.TestCase):
    @patch("subprocess.run")
    def test_get_adb_devices_single_device(self, mock_run):
        mock_proc = MagicMock()
        mock_proc.stdout = "List of devices attached\nemulator-5554\tdevice\n"
        mock_run.return_value = mock_proc

        devices = adb_dynamic_inventory.get_adb_devices()
        self.assertEqual(devices, ["emulator-5554"])
        mock_run.assert_called_once_with(["adb", "devices"], capture_output=True, text=True, check=True)

    @patch("subprocess.run")
    def test_get_adb_devices_multiple_devices(self, mock_run):
        mock_proc = MagicMock()
        mock_proc.stdout = "List of devices attached\n123456789\tdevice\n987654321\tdevice\n"
        mock_run.return_value = mock_proc

        devices = adb_dynamic_inventory.get_adb_devices()
        self.assertEqual(devices, ["123456789", "987654321"])

    @patch("subprocess.run")
    def test_get_adb_devices_filters_unauthorized_and_offline(self, mock_run):
        mock_proc = MagicMock()
        mock_proc.stdout = (
            "List of devices attached\n"
            "device1\tdevice\n"
            "device2\tunauthorized\n"
            "device3\toffline\n"
            "device4\trecovery\n"
        )
        mock_run.return_value = mock_proc

        devices = adb_dynamic_inventory.get_adb_devices()
        self.assertEqual(devices, ["device1"])

    @patch("subprocess.run")
    def test_get_adb_devices_empty(self, mock_run):
        mock_proc = MagicMock()
        mock_proc.stdout = "List of devices attached\n\n"
        mock_run.return_value = mock_proc

        devices = adb_dynamic_inventory.get_adb_devices()
        self.assertEqual(devices, [])

    @patch("subprocess.run")
    def test_get_adb_devices_file_not_found(self, mock_run):
        mock_run.side_effect = FileNotFoundError("adb binary missing")
        devices = adb_dynamic_inventory.get_adb_devices()
        self.assertEqual(devices, [])

    @patch("subprocess.run")
    def test_get_adb_devices_called_process_error(self, mock_run):
        mock_run.side_effect = subprocess.CalledProcessError(1, ["adb", "devices"], stderr="daemon failed to start")
        devices = adb_dynamic_inventory.get_adb_devices()
        self.assertEqual(devices, [])

if __name__ == "__main__":
    unittest.main()
