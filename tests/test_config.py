#!/usr/bin/env python3
"""
Staff-Grade Unit Test Suite for pixel_setup framework.
Tests configuration parsing, PyYAML fallback, and dynamic inventory generation.
"""
import unittest
import os
import sys
import tempfile

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

class TestDynamicInventory(unittest.TestCase):
    def test_get_adb_devices_type(self):
        devices = adb_dynamic_inventory.get_adb_devices()
        self.assertIsInstance(devices, list)

if __name__ == "__main__":
    unittest.main()
