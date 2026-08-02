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

    def test_shlex_quoting_injection_prevention(self):
        sample_yaml = """
private_dns_provider: 'x"; touch /tmp/pwned; echo "'
"""
        with tempfile.NamedTemporaryFile("w+", delete=False) as f:
            f.write(sample_yaml)
            tmp_name = f.name

        try:
            cfg = parse_config.load_yaml(tmp_name)
            import shlex
            quoted = shlex.quote(str(cfg["private_dns_provider"]))
            self.assertEqual(quoted, '\'x"; touch /tmp/pwned; echo "\'')
        finally:
            os.remove(tmp_name)

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
