from __future__ import annotations

import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import sys

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


version = load("version", ROOT / "tool/version.py")
builder = load("builder", ROOT / "apps/mobile/tool/release_builder.py")
sys.path.insert(0, str(ROOT / "tool"))
publisher = load("publisher", ROOT / "tool/publish_release.py")


class ReleasePolicyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "apps/mobile/lib").mkdir(parents=True)
        (self.root / "apps/mobile/pubspec.yaml").write_text("name: corhub\nversion: 0.18.9+60\n")
        (self.root / "apps/mobile/lib/app_identity.dart").write_text(version.identity("0.18.9+60"))
        self.git("init", "-q")
        self.git("config", "user.name", "Local Test")
        self.git("config", "user.email", "test@example.invalid")
        self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.PIPE, text=True)

    def commit(self):
        self.git("add", ".")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "fixture")

    def test_update_keeps_android_and_settings_versions_together(self):
        version.set_version(self.root, "0.19.0+61")
        self.assertEqual(version.check(self.root), "0.19.0+61")
        self.assertEqual(builder.read_mobile_version(self.root / "apps/mobile/pubspec.yaml"), ("0.19.0", 61))

    def test_rejects_build_reuse_reset_version_rollback_and_abi_overlap(self):
        for value in ("0.19.0+60", "1.0.0+1", "0.18.8+61", "0.19.0+1000", "0.19.00+61"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                version.set_version(self.root, value)
        self.assertEqual(version.current(self.root), "0.18.9+60")

    def test_checks_against_release_tags_not_only_working_version(self):
        self.git("tag", "corhub-v0.19.0+70")
        with self.assertRaises(ValueError):
            version.set_version(self.root, "0.19.0+61")

    def test_legacy_tags_still_prevent_build_reuse_and_version_rollback(self):
        self.git("tag", "ts-phone-v0.19.0+70")
        with self.assertRaises(ValueError):
            version.check(self.root)
        for value in ("0.19.1+70", "0.18.9+71"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                version.set_version(self.root, value)
        version.set_version(self.root, "0.19.1+71")
        self.assertEqual(version.check(self.root, tag="corhub-v0.19.1+71"), "0.19.1+71")

    def test_rebrand_cannot_republish_a_legacy_build_under_a_new_tag(self):
        self.git("tag", "ts-phone-v0.18.9+60")
        self.assertEqual(version.check(self.root), "0.18.9+60")
        (self.root / "CHANGELOG.md").write_text("# Changelog\n\n## 0.18.9+60\n\nRebrand.\n")
        self.commit()
        self.git("tag", "corhub-v0.18.9+60")
        with self.assertRaises(ValueError):
            version.check(self.root, tag="corhub-v0.18.9+60", release=True)

    def test_new_releases_require_the_corhub_prefix(self):
        with self.assertRaises(ValueError):
            version.check(self.root, tag="ts-phone-v0.18.9+60")

    def test_rejects_stale_identity_and_incorrect_tag(self):
        with self.assertRaises(ValueError):
            version.check(self.root, tag="corhub-v0.18.3+48")
        (self.root / "apps/mobile/lib/app_identity.dart").write_text(version.identity("0.18.8+59"))
        with self.assertRaises(ValueError):
            version.check(self.root)

    def test_release_requires_changelog_clean_tree_and_exact_tag_commit(self):
        tag = "corhub-v0.18.9+60"
        (self.root / "CHANGELOG.md").write_text("# Changelog\n\n## 0.18.9+60\n\nTest release.\n")
        self.commit()
        self.git("tag", tag)
        self.assertEqual(version.check(self.root, tag=tag, release=True), "0.18.9+60")
        (self.root / "extra").write_text("dirty")
        with self.assertRaises(ValueError):
            version.check(self.root, tag=tag, release=True)
        self.commit()
        with self.assertRaises(ValueError):
            version.check(self.root, tag=tag, release=True)

    def test_release_notes_do_not_include_other_versions(self):
        (self.root / "CHANGELOG.md").write_text("# Changelog\n\n## 0.19.0+61\n\nNew.\n\n## 0.18.9+60\n\nOld.\n")
        self.assertEqual(version.notes(self.root, "0.19.0+61"), "New.\n")
        with self.assertRaises(ValueError):
            version.notes(self.root, "0.20.0+62")

    def test_capture_rejects_force_added_private_files(self):
        for relative in ("local_debug/private.txt", "nested/local_debug/token", "signing/key.p12", ".env.production"):
            with self.subTest(relative=relative), self.assertRaises(builder.ComponentReleaseError):
                builder.snapshot_from_tree(self.root, [os.fsencode(relative)], git_commit="a" * 40, dirty=True)

    def test_published_release_is_refused_before_any_mutation(self):
        with patch.object(sys, "argv", ["publish_release.py", "--tag", "corhub-v0.19.0+61"]), patch.dict(os.environ, {"GITHUB_REPOSITORY": "example/test"}), patch.object(publisher.version, "check", return_value="0.19.0+61"), patch.object(publisher, "release_for_tag", return_value={"draft": False}), patch.object(publisher, "gh") as gh, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                publisher.main()
            gh.assert_not_called()

    def test_publication_rejects_missing_extra_or_corrupted_assets(self):
        directory = self.root / "assets"
        directory.mkdir()
        names = [builder.mobile_artifact_name("0.19.0", 61, "apk", abi) for abi in builder.ANDROID_RELEASE_ABIS]
        names.append(builder.mobile_artifact_name("0.19.0", 61, "aab", "universal"))
        for name in names:
            binary = directory / name
            binary.write_bytes(b"deterministic fake artifact")
            (directory / (name + ".attestation.json")).write_text(json.dumps({
                "source": {"dirty": False, "git_commit": "a" * 40},
                "mobile": {"version": "0.19.0", "build": 61},
                "artifact": {"filename": name, "sha256": publisher.sha256(binary), "size_bytes": binary.stat().st_size},
            }))
        paths = sorted(directory.iterdir())
        (directory / "SHA256SUMS").write_text("".join(f"{publisher.sha256(path)}  {path.name}\n" for path in paths))
        with patch.object(publisher.version, "git", return_value="a" * 40):
            self.assertEqual(len(publisher.inventory(directory, "0.19.0+61")), 9)
            (directory / "unexpected.log").write_text("private")
            with self.assertRaises(ValueError):
                publisher.inventory(directory, "0.19.0+61")
            (directory / "unexpected.log").unlink()
            (directory / names[0]).write_bytes(b"corrupt")
            with self.assertRaises(ValueError):
                publisher.inventory(directory, "0.19.0+61")
            (directory / names[0]).unlink()
            with self.assertRaises(ValueError):
                publisher.inventory(directory, "0.19.0+61")


if __name__ == "__main__":
    unittest.main()
