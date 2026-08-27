from __future__ import annotations

import hashlib
import json
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path, PurePosixPath


DEPLOY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEPLOY))

from release_builder import (  # noqa: E402
    ComponentReleaseError,
    EXPECTED_PROTOCOLS,
    read_mobile_version,
    read_server_version,
    safe_relative,
    validate_component_manifest,
    write_component_archive,
)


class ReleaseBuilderTests(unittest.TestCase):
    def test_component_archive_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "first.txt"
            second = root / "second.txt"
            first.write_text("alpha\n", encoding="utf-8")
            second.write_text("beta\n", encoding="utf-8")
            records = [
                (PurePosixPath("bin/first"), first, 0o755),
                (PurePosixPath("data/second.txt"), second, 0o644),
            ]
            archive_one = root / "one.tgz"
            archive_two = root / "two.tgz"
            write_component_archive(records, archive_one)
            write_component_archive(reversed(records), archive_two)
            self.assertEqual(_sha256(archive_one), _sha256(archive_two))
            with tarfile.open(archive_one, "r:gz") as archive:
                names = [member.name for member in archive.getmembers()]
            self.assertIn("component/bin/first", names)
            self.assertIn("component/data/second.txt", names)

    def test_mobile_version_requires_name_and_positive_build(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "pubspec.yaml"
            path.write_text("name: ts_phone\nversion: 0.8.5+27\n", encoding="utf-8")
            self.assertEqual(read_mobile_version(path), ("0.8.5", 27))
            path.write_text("name: ts_phone\nversion: 0.8.5+0\n", encoding="utf-8")
            with self.assertRaises(ComponentReleaseError):
                read_mobile_version(path)

    def test_server_version_binds_root_workspace_and_version_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "services" / "server").mkdir(parents=True)
            (root / "package.json").write_text(
                '{"name":"ts-phone","version":"0.4.1"}\n', encoding="utf-8"
            )
            server_package = root / "services" / "server" / "package.json"
            server_package.write_text(
                '{"name":"@iawnix/ts-phone-server","version":"0.4.1"}\n', encoding="utf-8"
            )
            (root / "VERSION").write_text("0.4.1\n", encoding="utf-8")

            self.assertEqual(read_server_version(root), "0.4.1")

            server_package.write_text(
                '{"name":"@iawnix/ts-phone-server","version":"0.4.2"}\n', encoding="utf-8"
            )
            with self.assertRaisesRegex(ComponentReleaseError, "server package.version"):
                read_server_version(root)

    def test_manifest_binds_versions_and_archive_digest(self) -> None:
        digest = "a" * 64
        release_id = f"0.4.1-mobile-0.8.5-build27-sha256-{digest[:16]}"
        manifest = {
            "schema_version": "ts-phone-component-release/1",
            "release_id": release_id,
            "component": {
                "name": "ts-phone",
                "server_version": "0.4.1",
                "mobile_version": "0.8.5",
                "mobile_build": 27,
            },
            "protocols": {key: EXPECTED_PROTOCOLS[key] for key in ("api", "events", "bridge")},
            "server_entry": {"path": "services/server/dist/index.js", "sha256": "b" * 64, "size_bytes": 1},
            "mobile_artifact": {
                "path": "artifacts/ts-phone-v0.8.5-build27-arm64-v8a-release.apk",
                "sha256": "c" * 64,
                "size_bytes": 2,
                "abi": "arm64-v8a",
                "certificate_sha256": "d" * 64,
            },
            "archive": {
                "filename": f"ts-phone-component-{release_id}.tgz",
                "sha256": digest,
                "size_bytes": 3,
            },
            "source": {"git_commit": "deadbeef", "dirty": False},
            "created_at_utc": "2026-08-27T00:00:00+00:00",
        }
        self.assertIs(validate_component_manifest(manifest), manifest)
        manifest["component"]["mobile_build"] = 28
        with self.assertRaises(ComponentReleaseError):
            validate_component_manifest(manifest)

    def test_archive_path_rejects_parent_traversal(self) -> None:
        with self.assertRaises(ComponentReleaseError):
            safe_relative("../secret")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    unittest.main()
