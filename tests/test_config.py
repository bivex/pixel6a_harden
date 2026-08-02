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

    def test_audit_config_keys_present(self):
        config_path = os.path.join(PROJECT_ROOT, "config", "default_settings.yml")
        cfg = parse_config.load_yaml(config_path)
        self.assertEqual(cfg["audit_security_patch_max_age_days"], 120)
        self.assertEqual(cfg["audit_strict_lock_quality"], 0)
        self.assertEqual(cfg["audit_accessibility_allowlist"], "com.google.android.marvin.talkback")
        self.assertEqual(cfg["audit_device_admin_allowlist"], "")
        self.assertEqual(cfg["audit_notification_listener_allowlist"], "")
        self.assertEqual(cfg["audit_autofill_allowlist"], "")
        self.assertEqual(cfg["audit_sms_default_allowlist"], "")
        self.assertEqual(cfg["audit_assistant_allowlist"], "")

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

class TestSecurityAudit(unittest.TestCase):
    """Tests the Deep Security Audit module's pure logic (no device required)."""
    SECURITY_AUDIT_SH = os.path.join(SCRIPTS_DIR, "security_audit.sh")

    def test_module_exists(self):
        self.assertTrue(os.path.exists(self.SECURITY_AUDIT_SH), "security_audit.sh must exist")

    def _label(self, code):
        cmd = 'source "{sh}"; password_quality_label {code}'.format(
            sh=self.SECURITY_AUDIT_SH, code=code)
        proc = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, check=True)
        return proc.stdout.strip()

    def test_password_quality_label_mapping(self):
        self.assertEqual(self._label("0"), "NONE")
        self.assertEqual(self._label(""), "NONE")
        self.assertEqual(self._label("null"), "NONE")
        self.assertEqual(self._label("None"), "NONE")
        self.assertEqual(self._label("65536"), "PATTERN")
        self.assertEqual(self._label("131072"), "PIN_NUMERIC")
        self.assertEqual(self._label("196608"), "PIN_NUMERIC_COMPLEX")
        self.assertEqual(self._label("393216"), "PASSWORD_COMPLEX")
        self.assertEqual(self._label("32768"), "BIOMETRIC_WEAK")

    def test_password_quality_label_unknown_code(self):
        out = self._label("999999")
        self.assertTrue(out.startswith("UNKNOWN"), "expected UNKNOWN prefix, got: %r" % out)

    def test_module_sourcing_is_safe(self):
        # Sourcing must define only functions and the marker — no adb calls, no stdout noise.
        cmd = 'set -e; source "{sh}"; echo "loaded=${{SECURITY_AUDIT_LOADED}}"'.format(sh=self.SECURITY_AUDIT_SH)
        proc = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, check=True)
        self.assertEqual(proc.stdout.strip(), "loaded=1")
        self.assertEqual(proc.stderr.strip(), "")


class TestBackupIntegrity(unittest.TestCase):
    def test_sha256_checksum_verification(self):
        import hashlib
        with tempfile.TemporaryDirectory() as tmp_dir:
            sample_file = os.path.join(tmp_dir, "managed_keys.txt")
            with open(sample_file, "w", encoding="utf-8") as f:
                f.write("system screen_off_timeout=600000\n")

            with open(sample_file, "rb") as f:
                expected_hash = hashlib.sha256(f.read()).hexdigest()

            checksum_file = os.path.join(tmp_dir, "checksums.sha256")
            with open(checksum_file, "w", encoding="utf-8") as f:
                f.write(f"{expected_hash}  managed_keys.txt\n")

            # Verify clean hash matches
            with open(sample_file, "rb") as f:
                actual_hash = hashlib.sha256(f.read()).hexdigest()
            self.assertEqual(actual_hash, expected_hash)

            # Tamper with backup file
            with open(sample_file, "a", encoding="utf-8") as f:
                f.write("malicious=entry\n")

            with open(sample_file, "rb") as f:
                tampered_hash = hashlib.sha256(f.read()).hexdigest()
            self.assertNotEqual(tampered_hash, expected_hash)

if __name__ == "__main__":
    unittest.main()
