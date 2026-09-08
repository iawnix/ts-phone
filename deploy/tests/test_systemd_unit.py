from __future__ import annotations

import configparser
import unittest
from pathlib import Path


UNIT = Path(__file__).resolve().parents[1] / "systemd" / "ts-phone.service"


class SystemdUnitTests(unittest.TestCase):
    def test_pi_storage_uses_user_home_without_disabling_home_protection(self) -> None:
        source = UNIT.read_text(encoding="utf-8")
        unit = configparser.ConfigParser(interpolation=None, strict=False)
        unit.read_string(source)

        self.assertEqual(unit["Service"]["ProtectHome"], "read-only")
        self.assertIn("\nReadWritePaths=-%h/.pi/agent\n", source)
        self.assertNotRegex(source, r"(?m)^ReadWritePaths=.*(?:/home/|~|\$HOME).*\.pi/agent$")
        self.assertNotRegex(source, r"(?m)^ReadWritePaths=-?%h/?$")


if __name__ == "__main__":
    unittest.main()
