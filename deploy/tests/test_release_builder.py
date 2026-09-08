from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path, PurePosixPath
from unittest import mock


DEPLOY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEPLOY))

from release_builder import (  # noqa: E402
    ComponentReleaseError,
    EXPECTED_ANDROID_CERTIFICATE_SHA256,
    EXPECTED_PROTOCOLS,
    MAX_COMPONENT_ARCHIVE_BYTES,
    MAX_COMPONENT_BOUND_MEMBER_BYTES,
    REQUIRED_COMPONENT_FILES,
    build_component_release,
    canonical_object_sha256,
    capture_node_dependencies,
    capture_source_tree,
    file_descriptor,
    publish_android_release_set,
    read_mobile_version,
    read_server_version,
    release_records,
    safe_relative,
    source_snapshot,
    validate_component_archive,
    validate_component_file_inventory,
    validate_component_manifest,
    validate_mobile_build_attestation,
    validate_apk_badging,
    validate_protocol_documents,
    verify_apk,
    verify_clean_captured_source_tree,
    write_mobile_build_attestation,
    write_component_archive,
)


class ReleaseBuilderTests(unittest.TestCase):
    def test_android_capture_rejects_mismatched_identity_before_build(self) -> None:
        spec = importlib.util.spec_from_file_location(
            "mobile_build_attestation", DEPLOY / "mobile-build-attestation.py"
        )
        assert spec is not None and spec.loader is not None
        cli = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cli)
        with tempfile.TemporaryDirectory() as temporary:
            captured = Path(temporary) / "source"
            output = Path(temporary) / "snapshot.json"
            with (
                mock.patch.object(cli, "capture_source_tree", return_value={}),
                mock.patch.object(cli, "read_mobile_version", side_effect=ComponentReleaseError("app identity mismatch")) as validate,
                mock.patch.object(cli, "atomic_write_json") as publish,
                mock.patch("sys.stderr"),
            ):
                status = cli.main(["capture", "--destination", str(captured), "--output", str(output)])
                self.assertEqual(status, 1)
                validate.assert_called_once_with(captured / "apps" / "mobile" / "pubspec.yaml")
                publish.assert_not_called()

    def test_component_archive_limit_matches_the_package_member_limit(self) -> None:
        self.assertEqual(MAX_COMPONENT_ARCHIVE_BYTES, MAX_COMPONENT_BOUND_MEMBER_BYTES)

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
            (path.parent / "lib").mkdir()
            path.write_text("name: ts_phone\nversion: 0.8.5+27\n", encoding="utf-8")
            identity = path.parent / "lib" / "app_identity.dart"
            identity.write_text(
                "const String tsPhoneAppVersion = '0.8.5';\n"
                "const String tsPhoneAppBuild = '27';\n",
                encoding="utf-8",
            )
            self.assertEqual(read_mobile_version(path), ("0.8.5", 27))
            identity.write_text(
                "const String tsPhoneAppVersion = '0.8.4';\n"
                "const String tsPhoneAppBuild = '27';\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ComponentReleaseError, "app identity"):
                read_mobile_version(path)
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
            package_lock_path = root / "package-lock.json"
            package_lock = {
                "name": "ts-phone",
                "version": "0.4.1",
                "packages": {
                    "": {"version": "0.4.1"},
                    "services/server": {"version": "0.4.1"},
                },
            }
            package_lock_path.write_text(
                json.dumps(
                    package_lock
                ),
                encoding="utf-8",
            )
            (root / "services" / "server" / "src").mkdir()
            types_path = root / "services" / "server" / "src" / "types.ts"
            types_path.write_text('export const SERVICE_VERSION = "0.4.1" as const;\n', encoding="utf-8")
            (root / "packages" / "protocol").mkdir(parents=True)
            openapi_path = root / "packages" / "protocol" / "openapi.yaml"
            openapi_path.write_text(
                "openapi: 3.1.0\ninfo:\n  title: TS Phone API\n  version: 0.4.1\npaths: {}\n",
                encoding="utf-8",
            )

            self.assertEqual(read_server_version(root), "0.4.1")

            server_package.write_text(
                '{"name":"@iawnix/ts-phone-server","version":"0.4.2"}\n', encoding="utf-8"
            )
            with self.assertRaisesRegex(ComponentReleaseError, "server package.version"):
                read_server_version(root)
            server_package.write_text(
                '{"name":"@iawnix/ts-phone-server","version":"0.4.1"}\n', encoding="utf-8"
            )

            package_lock["packages"]["services/server"]["version"] = "0.4.2"
            package_lock_path.write_text(json.dumps(package_lock), encoding="utf-8")
            with self.assertRaisesRegex(ComponentReleaseError, "server workspace version"):
                read_server_version(root)
            package_lock["packages"]["services/server"]["version"] = "0.4.1"
            package_lock_path.write_text(json.dumps(package_lock), encoding="utf-8")

            types_path.write_text('export const SERVICE_VERSION = "0.4.2" as const;\n', encoding="utf-8")
            with self.assertRaisesRegex(ComponentReleaseError, "SERVICE_VERSION"):
                read_server_version(root)
            types_path.write_text('export const SERVICE_VERSION = "0.4.1" as const;\n', encoding="utf-8")

            openapi_path.write_text(
                "openapi: 3.1.0\ninfo:\n  title: TS Phone API\n  version: 0.4.2\npaths: {}\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ComponentReleaseError, "OpenAPI info.version"):
                read_server_version(root)

    def test_manifest_binds_versions_and_archive_digest(self) -> None:
        digest = "a" * 64
        source = {
            "schema_version": "ts-phone-source-snapshot/1",
            "git_commit": "e" * 40,
            "dirty": False,
            "sha256": "f" * 64,
        }
        release_id = (
            f"0.4.1-mobile-0.8.5-build27-source-{canonical_object_sha256(source)[:16]}-"
            f"sha256-{digest[:16]}"
        )
        manifest = {
            "schema_version": "ts-phone-component-release/2",
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
                "certificate_sha256": EXPECTED_ANDROID_CERTIFICATE_SHA256,
            },
            "mobile_build_attestation": {
                "path": "artifacts/ts-phone-v0.8.5-build27-arm64-v8a-release.apk.attestation.json",
                "sha256": "e" * 64,
                "size_bytes": 3,
            },
            "archive": {
                "filename": f"ts-phone-component-{release_id}.tgz",
                "sha256": digest,
                "size_bytes": 3,
            },
            "source": source,
            "created_at_utc": "2026-08-27T00:00:00+00:00",
        }
        self.assertIs(validate_component_manifest(manifest), manifest)
        manifest["source"]["git_commit"] = "a" * 40
        with self.assertRaisesRegex(ComponentReleaseError, "release_id"):
            validate_component_manifest(manifest)
        manifest["source"]["git_commit"] = "e" * 40
        manifest["component"]["mobile_build"] = 28
        with self.assertRaises(ComponentReleaseError):
            validate_component_manifest(manifest)
        manifest["component"]["mobile_build"] = 27
        manifest["mobile_artifact"]["path"] = "artifacts/renamed-release.apk"
        manifest["mobile_build_attestation"]["path"] = "artifacts/renamed-release.apk.attestation.json"
        with self.assertRaisesRegex(ComponentReleaseError, "mobile_artifact.path"):
            validate_component_manifest(manifest)

    def test_manifest_rejects_overlong_release_id(self) -> None:
        with self.assertRaisesRegex(ComponentReleaseError, "release_id exceeds"):
            validate_component_manifest(
                {
                    "schema_version": "ts-phone-component-release/2",
                    "release_id": "a" * 161,
                    "component": {
                        "name": "ts-phone",
                        "server_version": "0.4.1",
                        "mobile_version": "0.8.5",
                        "mobile_build": 27,
                    },
                    "protocols": {key: EXPECTED_PROTOCOLS[key] for key in ("api", "events", "bridge")},
                    "server_entry": {
                        "path": "services/server/dist/index.js",
                        "sha256": "a" * 64,
                        "size_bytes": 1,
                    },
                    "mobile_artifact": {
                        "path": "artifacts/ts-phone-v0.8.5-build27-arm64-v8a-release.apk",
                        "sha256": "b" * 64,
                        "size_bytes": 1,
                        "abi": "arm64-v8a",
                        "certificate_sha256": EXPECTED_ANDROID_CERTIFICATE_SHA256,
                    },
                    "mobile_build_attestation": {
                        "path": (
                            "artifacts/ts-phone-v0.8.5-build27-arm64-v8a-release.apk.attestation.json"
                        ),
                        "sha256": "c" * 64,
                        "size_bytes": 1,
                    },
                    "archive": {
                        "filename": f"ts-phone-component-{'a' * 161}.tgz",
                        "sha256": "d" * 64,
                        "size_bytes": 1,
                    },
                    "source": {
                        "schema_version": "ts-phone-source-snapshot/1",
                        "git_commit": "e" * 40,
                        "dirty": False,
                        "sha256": "f" * 64,
                    },
                    "created_at_utc": "2026-09-06T00:00:00+00:00",
                }
            )

    def test_archive_path_rejects_parent_traversal(self) -> None:
        with self.assertRaises(ComponentReleaseError):
            safe_relative("../secret")

    def test_apk_badging_binds_package_version_abi_and_release_mode(self) -> None:
        valid = (
            "package: name='xyz.iawnix.ts_phone' versionCode='2027' versionName='0.8.5'\n"
            "native-code: 'arm64-v8a'\n"
        )
        validate_apk_badging(valid, "0.8.5", 27, "arm64-v8a")
        with self.assertRaisesRegex(ComponentReleaseError, "package name"):
            validate_apk_badging(valid.replace("0.8.5", "0.8.4"), "0.8.5", 27, "arm64-v8a")
        with self.assertRaisesRegex(ComponentReleaseError, "must not be debuggable"):
            validate_apk_badging(f"{valid}application-debuggable\n", "0.8.5", 27, "arm64-v8a")

    def test_apk_verification_requires_exactly_one_pinned_signer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            apksigner = root / "apksigner"
            apk = root / "release.apk"
            apksigner.write_text("tool\n", encoding="utf-8")
            apk.write_bytes(b"apk")
            prefix = "Verified using v2 scheme (APK Signature Scheme v2): true\n"
            pinned = (
                "Signer #1 certificate SHA-256 digest: "
                f"{EXPECTED_ANDROID_CERTIFICATE_SHA256}\n"
            )
            with mock.patch(
                "release_builder.subprocess.run",
                return_value=subprocess.CompletedProcess([], 0, prefix + pinned, ""),
            ):
                self.assertEqual(
                    verify_apk(apksigner, apk),
                    EXPECTED_ANDROID_CERTIFICATE_SHA256,
                )

            extra = "Signer #2 certificate SHA-256 digest: " + "0" * 64 + "\n"
            with mock.patch(
                "release_builder.subprocess.run",
                return_value=subprocess.CompletedProcess([], 0, prefix + pinned + extra, ""),
            ):
                with self.assertRaisesRegex(ComponentReleaseError, "release certificate"):
                    verify_apk(apksigner, apk)

    def test_component_archive_binds_source_attestation_and_events_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = {
                "schema_version": "ts-phone-source-snapshot/1",
                "git_commit": "1" * 40,
                "dirty": False,
                "sha256": "2" * 64,
            }
            apk, attestation = _create_component_inputs(root, source)
            records = release_records(root, apk, attestation)
            archive_path = root / "component.tgz"
            write_component_archive(records, archive_path)
            with tarfile.open(archive_path, "r:gz") as archive:
                self.assertIn(
                    "component/packages/protocol/events.schema.json",
                    {member.name for member in archive.getmembers()},
                )

            archive_sha256 = _sha256(archive_path)
            release_id = (
                f"0.4.1-mobile-0.8.5-build27-source-{canonical_object_sha256(source)[:16]}-"
                f"sha256-{archive_sha256[:16]}"
            )
            release_archive = root / f"ts-phone-component-{release_id}.tgz"
            archive_path.rename(release_archive)
            manifest = _component_manifest(source, apk, attestation, release_archive, release_id)
            self.assertIs(validate_component_archive(manifest, release_archive), manifest)

            forged_source = {**source, "git_commit": "3" * 40}
            forged_release_id = (
                f"0.4.1-mobile-0.8.5-build27-source-{canonical_object_sha256(forged_source)[:16]}-"
                f"sha256-{archive_sha256[:16]}"
            )
            forged_archive = root / f"ts-phone-component-{forged_release_id}.tgz"
            shutil.copyfile(release_archive, forged_archive)
            forged_manifest = _component_manifest(
                forged_source,
                apk,
                attestation,
                forged_archive,
                forged_release_id,
            )
            with self.assertRaisesRegex(ComponentReleaseError, "current source snapshot"):
                validate_component_archive(forged_manifest, forged_archive)

    def test_archive_validation_parses_the_same_bytes_it_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = {
                "schema_version": "ts-phone-source-snapshot/1",
                "git_commit": "1" * 40,
                "dirty": False,
                "sha256": "2" * 64,
            }
            apk, attestation = _create_component_inputs(root, source)
            archive_path = root / "component.tgz"
            write_component_archive(release_records(root, apk, attestation), archive_path)
            archive_sha256 = _sha256(archive_path)
            release_id = (
                f"0.4.1-mobile-0.8.5-build27-source-{canonical_object_sha256(source)[:16]}-"
                f"sha256-{archive_sha256[:16]}"
            )
            release_archive = root / f"ts-phone-component-{release_id}.tgz"
            archive_path.rename(release_archive)
            manifest = _component_manifest(source, apk, attestation, release_archive, release_id)
            replaced = False

            def hash_and_replace(value: bytes) -> str:
                nonlocal replaced
                if not replaced:
                    replaced = True
                    release_archive.write_bytes(b"replacement after hashing")
                return hashlib.sha256(value).hexdigest()

            with mock.patch("release_builder.sha256_bytes", side_effect=hash_and_replace):
                self.assertIs(validate_component_archive(manifest, release_archive), manifest)
            self.assertTrue(replaced)

    def test_component_release_rejects_missing_attestation_before_build_checks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            apk = root / "dist" / "ts-phone-v0.8.5-build27-arm64-v8a-release.apk"
            apk.parent.mkdir()
            apk.write_bytes(b"old apk")
            snapshot = {
                "schema_version": "ts-phone-source-snapshot/1",
                "git_commit": "a" * 40,
                "dirty": False,
                "sha256": "b" * 64,
            }

            def read_release_object(path: Path, label: str) -> dict[str, object]:
                if label == "protocol versions":
                    return EXPECTED_PROTOCOLS
                raise ComponentReleaseError(f"required file is missing or unsafe: {path}")

            with (
                mock.patch("release_builder.capture_source_tree", return_value=snapshot),
                mock.patch("release_builder.read_server_version", return_value="0.4.1"),
                mock.patch("release_builder.read_mobile_version", return_value=("0.8.5", 27)),
                mock.patch("release_builder.read_object", side_effect=read_release_object),
                mock.patch("release_builder.run_checked") as run_checked,
            ):
                with self.assertRaisesRegex(ComponentReleaseError, "missing or unsafe"):
                    build_component_release(
                        root,
                        root / "output",
                        mobile_apk=apk,
                        apksigner=root / "apksigner",
                    )
            run_checked.assert_not_called()

    def test_component_release_builds_server_from_captured_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "repository"
            root.mkdir()
            apk = _create_release_repository(root)
            commands: list[list[str]] = []
            command_roots: list[Path] = []

            def run_in_capture(command: list[str], command_root: Path) -> None:
                commands.append(command)
                command_roots.append(command_root)
                if command == ["npm", "run", "build"]:
                    server_dist = command_root / "services" / "server" / "dist"
                    server_dist.mkdir(parents=True)
                    (server_dist / "index.js").write_text("export {};\n", encoding="utf-8")
                    (server_dist / "cli.js").write_text("export {};\n", encoding="utf-8")

            with (
                mock.patch("release_builder.run_checked", side_effect=run_in_capture),
                mock.patch(
                    "release_builder.verify_apk",
                    return_value=EXPECTED_ANDROID_CERTIFICATE_SHA256,
                ),
                mock.patch("release_builder.verify_apk_metadata"),
            ):
                result = build_component_release(
                    root,
                    base / "output",
                    mobile_apk=apk,
                    apksigner=base / "apksigner",
                )

            self.assertTrue(result["ok"])
            self.assertTrue(Path(result["archive"]).is_file())
            self.assertEqual(
                commands,
                [
                    ["npm", "run", "typecheck"],
                    ["npm", "test"],
                    ["npm", "run", "build"],
                ],
            )
            self.assertEqual(len(set(command_roots)), 1)
            self.assertTrue(all(command_root != root for command_root in command_roots))
            self.assertFalse((root / "services" / "server" / "dist").exists())

            with tarfile.open(result["archive"], "r:gz") as archive:
                archived = {member.name for member in archive.getmembers() if member.isfile()}
            self.assertIn("component/services/server/dist/index.js", archived)
            self.assertIn("component/services/server/dist/cli.js", archived)

    def test_component_inventory_matches_runtime_policy(self) -> None:
        expected = {
            "VERSION",
            "README.md",
            "package.json",
            "services/server/package.json",
            "services/server/dist/index.js",
            "services/server/dist/cli.js",
            "bin/ts-phone-ctl",
            "bin/ts-phone-server",
            "deploy/server.env.example",
            "packages/protocol/versions.json",
            "packages/protocol/bridge.schema.json",
            "packages/protocol/events.schema.json",
            "packages/protocol/openapi.yaml",
            "docs/architecture.md",
            "docs/deployment.md",
            "docs/recovery.md",
            "docs/security.md",
        }
        self.assertEqual(REQUIRED_COMPONENT_FILES, expected)
        files = {
            *expected,
            "artifacts/ts-phone.apk",
            "artifacts/ts-phone.apk.attestation.json",
        }
        validate_component_file_inventory(
            files,
            mobile_artifact_path="artifacts/ts-phone.apk",
            mobile_attestation_path="artifacts/ts-phone.apk.attestation.json",
        )
        with self.assertRaisesRegex(ComponentReleaseError, "missing runtime files"):
            validate_component_file_inventory(
                files - {"services/server/dist/cli.js"},
                mobile_artifact_path="artifacts/ts-phone.apk",
                mobile_attestation_path="artifacts/ts-phone.apk.attestation.json",
            )
        with self.assertRaisesRegex(ComponentReleaseError, "development-only"):
            validate_component_file_inventory(
                files | {"services/server/dist/test/fixture.js"},
                mobile_artifact_path="artifacts/ts-phone.apk",
                mobile_attestation_path="artifacts/ts-phone.apk.attestation.json",
            )

    def test_mobile_attestation_rejects_stale_source_commit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = _create_mobile_repository(root)
            original_source = source_snapshot(root)
            attestation_path = write_mobile_build_attestation(
                root,
                artifact,
                artifact_format="apk",
                abi="arm64-v8a",
                expected_source=original_source,
            )

            source_file = root / "apps" / "mobile" / "lib" / "main.dart"
            source_file.write_text("void main() { print('changed'); }\n", encoding="utf-8")
            _git(root, "add", "apps/mobile/lib/main.dart")
            _git(root, "commit", "-qm", "change source")
            current_source = source_snapshot(root)

            with self.assertRaisesRegex(ComponentReleaseError, "current source snapshot"):
                validate_mobile_build_attestation(
                    attestation_path,
                    artifact,
                    expected_source=current_source,
                    expected_mobile_version="0.8.5",
                    expected_mobile_build=27,
                    expected_format="apk",
                    expected_abi="arm64-v8a",
                )

    def test_old_mobile_artifact_cannot_be_reattested_for_new_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = _create_mobile_repository(root)
            source_file = root / "apps" / "mobile" / "lib" / "main.dart"
            source_file.write_text("void main() { print('new source'); }\n", encoding="utf-8")
            _git(root, "add", "apps/mobile/lib/main.dart")
            _git(root, "commit", "-qm", "new source")

            with self.assertRaisesRegex(ComponentReleaseError, "embed the captured source snapshot"):
                write_mobile_build_attestation(
                    root,
                    artifact,
                    artifact_format="apk",
                    abi="arm64-v8a",
                    expected_source=source_snapshot(root),
                )

    def test_mobile_attestation_rejects_modified_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = _create_mobile_repository(root)
            snapshot = source_snapshot(root)
            attestation_path = write_mobile_build_attestation(
                root,
                artifact,
                artifact_format="apk",
                abi="arm64-v8a",
                expected_source=snapshot,
            )
            with artifact.open("ab") as handle:
                handle.write(b"replacement bytes")

            with self.assertRaisesRegex(ComponentReleaseError, "digest or size"):
                validate_mobile_build_attestation(
                    attestation_path,
                    artifact,
                    expected_source=snapshot,
                    expected_mobile_version="0.8.5",
                    expected_mobile_build=27,
                    expected_format="apk",
                    expected_abi="arm64-v8a",
                )

    def test_source_snapshot_tracks_dirty_worktree_content(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _create_mobile_repository(root)
            clean = source_snapshot(root)
            self.assertFalse(clean["dirty"])

            source_file = root / "apps" / "mobile" / "lib" / "main.dart"
            source_file.write_text("void main() { print('dirty'); }\n", encoding="utf-8")
            dirty = source_snapshot(root)
            self.assertTrue(dirty["dirty"])
            self.assertEqual(dirty["git_commit"], clean["git_commit"])
            self.assertNotEqual(dirty["sha256"], clean["sha256"])

    def test_source_snapshot_rejects_hidden_index_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _create_mobile_repository(root)
            _git(root, "update-index", "--skip-worktree", "apps/mobile/lib/main.dart")

            with self.assertRaisesRegex(ComponentReleaseError, "source index"):
                source_snapshot(root)

    def test_captured_source_is_independent_of_later_worktree_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "repository"
            root.mkdir()
            _create_mobile_repository(root)
            captured_root = base / "captured"

            snapshot = capture_source_tree(root, captured_root)
            captured_main = captured_root / "apps" / "mobile" / "lib" / "main.dart"
            self.assertEqual(captured_main.read_text(encoding="utf-8"), "void main() {}\n")

            (root / "apps" / "mobile" / "lib" / "main.dart").write_text(
                "void main() { print('later'); }\n",
                encoding="utf-8",
            )
            self.assertEqual(captured_main.read_text(encoding="utf-8"), "void main() {}\n")
            self.assertFalse(snapshot["dirty"])
            verify_clean_captured_source_tree(root, captured_root, snapshot)

            captured_main.write_text("void main() { print('mutated capture'); }\n", encoding="utf-8")
            with self.assertRaisesRegex(ComponentReleaseError, "changed during"):
                verify_clean_captured_source_tree(root, captured_root, snapshot)

    def test_clean_source_capture_rejects_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _create_mobile_repository(root)
            linked = root / "apps" / "mobile" / "lib" / "linked.dart"
            linked.symlink_to("main.dart")

            with self.assertRaisesRegex(ComponentReleaseError, "must not contain symlinks"):
                source_snapshot(root)

    def test_android_release_script_pins_identity_and_requires_strict_aab_verification(self) -> None:
        script = (
            Path(__file__).resolve().parents[2]
            / "apps"
            / "mobile"
            / "tool"
            / "build_release_android.sh"
        ).read_text(encoding="utf-8")
        self.assertIn(f'RELEASE_CERTIFICATE_SHA256="{EXPECTED_ANDROID_CERTIFICATE_SHA256}"', script)
        self.assertIn('"$JARSIGNER" -verify -strict -verbose', script)
        self.assertIn('"$bundle_status" -eq 0 || "$bundle_status" -eq 4', script)

    def test_current_protocol_documents_bind_lifecycle_and_versions(self) -> None:
        root = DEPLOY.parent
        version = read_server_version(root)
        read_mobile_version(root / "apps" / "mobile" / "pubspec.yaml")
        self.assertEqual(validate_protocol_documents(root, version), EXPECTED_PROTOCOLS)
        events = json.loads((root / "packages" / "protocol" / "events.schema.json").read_text(encoding="utf-8"))
        lifecycle = events["$defs"]["agentRunEvent"]
        self.assertEqual(set(lifecycle["required"]), {"type", "origin", "turnId", "agentRunId"})
        self.assertFalse(lifecycle["additionalProperties"])
        branch_types = {
            branch["then"]["properties"]["payload"]["allOf"][1]["properties"]["type"]["const"]
            for branch in events["allOf"]
            if branch.get("if", {}).get("properties", {}).get("type", {}).get("const") in {"agent_start", "agent_settled"}
        }
        self.assertEqual(branch_types, {"agent_start", "agent_settled"})

    def test_protocol_validation_rejects_an_empty_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _write_protocol_documents(root)
            (root / "packages" / "protocol" / "events.schema.json").write_text("{}\n", encoding="utf-8")
            with self.assertRaisesRegex(ComponentReleaseError, "events protocol schema"):
                validate_protocol_documents(root, "0.4.1")

    def test_protocol_validation_rejects_a_semantically_empty_bridge_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _write_protocol_documents(root)
            bridge_path = root / "packages" / "protocol" / "bridge.schema.json"
            bridge_path.write_text(
                json.dumps(
                    {
                        "$schema": "https://json-schema.org/draft/2020-12/schema",
                        "$id": "https://tsphone.iawnix.xyz/schema/bridge-v3.json",
                        "properties": {"protocolVersion": {"const": "ts-phone-bridge/3"}},
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ComponentReleaseError, "bridge protocol schema"):
                validate_protocol_documents(root, "0.4.1")

    def test_protocol_validation_rejects_a_misbound_lifecycle_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _write_protocol_documents(root)
            events_path = root / "packages" / "protocol" / "events.schema.json"
            events = json.loads(events_path.read_text(encoding="utf-8"))
            events["allOf"][0]["then"]["properties"]["payload"]["allOf"][1]["properties"]["type"][
                "const"
            ] = "agent_settled"
            events_path.write_text(json.dumps(events) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ComponentReleaseError, "misbinds agent_start"):
                validate_protocol_documents(root, "0.4.1")

    def test_android_release_set_switches_only_after_complete_staging(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "first"
            _write_android_release_set(first, marker="first")
            current = publish_android_release_set(first, root / "dist", "0.8.5", 27)
            first_target = current.resolve()

            incomplete = root / "incomplete"
            _write_android_release_set(incomplete, marker="incomplete")
            (incomplete / "ts-phone-v0.8.5-build27-release.aab").unlink()
            with self.assertRaisesRegex(ComponentReleaseError, "inventory is incomplete"):
                publish_android_release_set(incomplete, root / "dist", "0.8.5", 27)
            self.assertEqual(current.resolve(), first_target)

            second = root / "second"
            _write_android_release_set(second, marker="second")
            publish_android_release_set(second, root / "dist", "0.8.5", 27)
            self.assertNotEqual(current.resolve(), first_target)
            self.assertTrue(first_target.is_dir())

    def test_dependency_capture_preserves_internal_links_and_rejects_external_links(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "repository"
            captured = base / "captured"
            (root / "node_modules" / ".bin").mkdir(parents=True)
            (root / "node_modules" / "tool" / "bin").mkdir(parents=True)
            (root / "node_modules" / "tool" / "bin" / "tool.js").write_text(
                "export {};\n",
                encoding="utf-8",
            )
            (root / "node_modules" / ".bin" / "tool").symlink_to("../tool/bin/tool.js")
            captured.mkdir()

            capture_node_dependencies(root, captured)
            copied_link = captured / "node_modules" / ".bin" / "tool"
            self.assertTrue(copied_link.is_symlink())
            self.assertEqual(copied_link.resolve(), captured / "node_modules" / "tool" / "bin" / "tool.js")

            shutil.rmtree(captured / "node_modules")
            (root / "node_modules" / "outside").symlink_to(base / "outside")
            with self.assertRaisesRegex(ComponentReleaseError, "escapes"):
                capture_node_dependencies(root, captured)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _create_mobile_repository(root: Path) -> Path:
    mobile = root / "apps" / "mobile"
    (mobile / "lib").mkdir(parents=True)
    (mobile / "pubspec.yaml").write_text("name: ts_phone\nversion: 0.8.5+27\n", encoding="utf-8")
    (mobile / "lib" / "app_identity.dart").write_text(
        "const String tsPhoneAppVersion = '0.8.5';\n"
        "const String tsPhoneAppBuild = '27';\n",
        encoding="utf-8",
    )
    (root / "package.json").write_text('{"name":"ts-phone"}\n', encoding="utf-8")
    (root / "deploy").mkdir()
    (root / "deploy" / "release_builder.py").write_text("# fixture\n", encoding="utf-8")
    (root / "packages" / "protocol").mkdir(parents=True)
    (root / "packages" / "protocol" / "versions.json").write_text("{}\n", encoding="utf-8")
    (mobile / "lib" / "main.dart").write_text("void main() {}\n", encoding="utf-8")
    (root / ".gitignore").write_text("dist/\n", encoding="utf-8")
    _git(root, "init", "-q")
    _git(root, "config", "user.name", "TS Phone Test")
    _git(root, "config", "user.email", "ts-phone-test@example.invalid")
    _git(root, "add", ".")
    _git(root, "commit", "-qm", "initial")

    artifact = root / "dist" / "ts-phone-v0.8.5-build27-arm64-v8a-release.apk"
    artifact.parent.mkdir()
    embedded_source = source_snapshot(root)
    with zipfile.ZipFile(artifact, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "assets/ts-phone-source-snapshot.json",
            json.dumps(embedded_source, sort_keys=True),
        )
        archive.writestr("assets/fixture.txt", "signed apk fixture")
    return artifact


def _create_release_repository(root: Path) -> Path:
    files = {
        ".gitignore": "node_modules/\ndist/\nbuild/\n",
        "VERSION": "0.4.1\n",
        "README.md": "TS Phone\n",
        "package.json": '{"name":"ts-phone","version":"0.4.1"}\n',
        "package-lock.json": json.dumps(
            {
                "name": "ts-phone",
                "version": "0.4.1",
                "packages": {
                    "": {"version": "0.4.1"},
                    "services/server": {"version": "0.4.1"},
                },
            }
        ),
        "services/server/package.json": '{"name":"@iawnix/ts-phone-server","version":"0.4.1"}\n',
        "services/server/src/types.ts": 'export const SERVICE_VERSION = "0.4.1" as const;\n',
        "bin/ts-phone-ctl": "#!/bin/sh\n",
        "bin/ts-phone-server": "#!/bin/sh\n",
        "deploy/release_builder.py": "# fixture\n",
        "deploy/server.env.example": "TS_PHONE_HOST=127.0.0.1\n",
        "docs/architecture.md": "architecture\n",
        "docs/deployment.md": "deployment\n",
        "docs/recovery.md": "recovery\n",
        "docs/security.md": "security\n",
        "apps/mobile/pubspec.yaml": "name: ts_phone\nversion: 0.8.5+27\n",
        "apps/mobile/lib/app_identity.dart": (
            "const String tsPhoneAppVersion = '0.8.5';\n"
            "const String tsPhoneAppBuild = '27';\n"
        ),
    }
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    _write_protocol_documents(root)
    (root / "node_modules" / "fixture").mkdir(parents=True)
    (root / "node_modules" / "fixture" / "index.js").write_text("export {};\n", encoding="utf-8")
    _git(root, "init", "-q")
    _git(root, "config", "user.name", "TS Phone Test")
    _git(root, "config", "user.email", "ts-phone-test@example.invalid")
    _git(root, "add", ".")
    _git(root, "commit", "-qm", "initial")

    source = source_snapshot(root)
    artifact = root / "dist" / "ts-phone-v0.8.5-build27-arm64-v8a-release.apk"
    artifact.parent.mkdir()
    with zipfile.ZipFile(artifact, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("assets/ts-phone-source-snapshot.json", json.dumps(source, sort_keys=True))
        archive.writestr("assets/fixture.txt", "signed apk fixture")
    write_mobile_build_attestation(
        root,
        artifact,
        artifact_format="apk",
        abi="arm64-v8a",
        expected_source=source,
    )
    return artifact


def _create_component_inputs(root: Path, source: dict[str, object]) -> tuple[Path, Path]:
    fixed = {
        "VERSION": "0.4.1\n",
        "README.md": "TS Phone\n",
        "package.json": '{"name":"ts-phone","version":"0.4.1"}\n',
        "services/server/package.json": '{"name":"@iawnix/ts-phone-server","version":"0.4.1"}\n',
        "bin/ts-phone-ctl": "#!/bin/sh\n",
        "bin/ts-phone-server": "#!/bin/sh\n",
        "deploy/server.env.example": "TS_PHONE_HOST=127.0.0.1\n",
        "docs/architecture.md": "architecture\n",
        "docs/deployment.md": "deployment\n",
        "docs/recovery.md": "recovery\n",
        "docs/security.md": "security\n",
        "services/server/dist/index.js": "export {};\n",
        "services/server/dist/cli.js": "export {};\n",
    }
    for relative, content in fixed.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    _write_protocol_documents(root)

    apk = root / "ts-phone-v0.8.5-build27-arm64-v8a-release.apk"
    with zipfile.ZipFile(apk, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("assets/ts-phone-source-snapshot.json", json.dumps(source, sort_keys=True))
        archive.writestr("assets/fixture.txt", "apk")
    attestation = apk.with_name(f"{apk.name}.attestation.json")
    attestation.write_text(
        json.dumps(
            {
                "schema_version": "ts-phone-mobile-build-attestation/1",
                "source": source,
                "mobile": {"version": "0.8.5", "build": 27},
                "target": {"format": "apk", "abi": "arm64-v8a"},
                "artifact": {
                    "filename": apk.name,
                    "sha256": _sha256(apk),
                    "size_bytes": apk.stat().st_size,
                },
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    return apk, attestation


def _write_protocol_documents(root: Path, server_version: str = "0.4.1") -> None:
    protocol_root = root / "packages" / "protocol"
    protocol_root.mkdir(parents=True, exist_ok=True)
    lifecycle = {
        "type": "object",
        "required": ["type", "origin", "turnId", "agentRunId"],
        "properties": {
            "type": {"enum": ["agent_start", "agent_settled"]},
            "origin": {"enum": ["local", "extension", "phone", "terminal", "host", "unknown"]},
            "turnId": {"type": "string", "pattern": "^[A-Za-z0-9._:-]{1,160}$"},
            "agentRunId": {"type": "string", "pattern": "^[A-Za-z0-9._:-]{1,160}$"},
        },
        "additionalProperties": False,
    }

    def lifecycle_branch(event_type: str, *, bridge_record: bool) -> dict[str, object]:
        condition_properties = {
            "type": {"const": "event.publish" if bridge_record else event_type}
        }
        condition_required = ["type"]
        if bridge_record:
            condition_properties["eventType"] = {"const": event_type}
            condition_required.append("eventType")
        then: dict[str, object] = {
            "properties": {
                "payload": {
                    "allOf": [
                        {"$ref": "#/$defs/agentRunEvent"},
                        {"properties": {"type": {"const": event_type}}},
                    ]
                }
            }
        }
        if bridge_record:
            then["required"] = ["payload"]
        return {
            "if": {"properties": condition_properties, "required": condition_required},
            "then": then,
        }

    bridge = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://tsphone.iawnix.xyz/schema/bridge-v3.json",
        "type": "object",
        "required": ["protocolVersion", "type", "workspaceId", "sessionId", "instanceEpoch"],
        "properties": {
            "protocolVersion": {"const": "ts-phone-bridge/3"},
            "type": {},
            "workspaceId": {},
            "sessionId": {},
            "instanceEpoch": {},
        },
        "additionalProperties": True,
        "allOf": [
            {
                "if": {"properties": {"type": {"const": "command.abort"}}, "required": ["type"]},
                "then": {"required": ["agentRunId"]},
            },
            lifecycle_branch("agent_start", bridge_record=True),
            lifecycle_branch("agent_settled", bridge_record=True),
        ],
        "$defs": {
            "agentRunEvent": lifecycle,
            "sessionSnapshot": {
                "type": "object",
                "required": ["sessionId", "isStreaming", "messages"],
                "properties": {
                    "sessionId": {},
                    "isStreaming": {},
                    "messages": {},
                    "agentRunId": {
                        "type": "string",
                        "pattern": "^[A-Za-z0-9._:-]{1,160}$",
                    },
                },
                "additionalProperties": False,
                "allOf": [
                    {
                        "if": {
                            "properties": {"isStreaming": {"const": True}},
                            "required": ["isStreaming"],
                        },
                        "then": {"required": ["agentRunId"]},
                        "else": {"not": {"required": ["agentRunId"]}},
                    }
                ],
            },
        },
    }
    events = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://tsphone.iawnix.xyz/schema/events-v3.json",
        "type": "object",
        "required": [
            "protocolVersion",
            "id",
            "workspaceId",
            "sessionId",
            "sessionRevision",
            "instanceEpoch",
            "sessionGeneration",
            "type",
            "payload",
            "at",
        ],
        "properties": {
            "protocolVersion": {"const": "ts-phone-events/3"},
            "id": {},
            "workspaceId": {},
            "sessionId": {},
            "sessionRevision": {},
            "instanceEpoch": {},
            "sessionGeneration": {},
            "type": {},
            "payload": {},
            "at": {},
        },
        "additionalProperties": False,
        "allOf": [
            lifecycle_branch("agent_start", bridge_record=False),
            lifecycle_branch("agent_settled", bridge_record=False),
        ],
        "$defs": {"agentRunEvent": lifecycle},
    }
    (protocol_root / "versions.json").write_text(json.dumps(EXPECTED_PROTOCOLS) + "\n", encoding="utf-8")
    (protocol_root / "bridge.schema.json").write_text(json.dumps(bridge) + "\n", encoding="utf-8")
    (protocol_root / "events.schema.json").write_text(json.dumps(events) + "\n", encoding="utf-8")
    (protocol_root / "openapi.yaml").write_text(
        "openapi: 3.1.0\n"
        "info:\n"
        "  title: TS Phone API\n"
        f"  version: {server_version}\n"
        "paths:\n"
        "  /api/v4/version:\n"
        "    get:\n"
        "      responses: {}\n"
        "components:\n"
        "  schemas:\n"
        "    Health:\n"
        "      properties:\n"
        "        version: { const: ts-phone-api/4 }\n",
        encoding="utf-8",
    )


def _write_android_release_set(root: Path, *, marker: str) -> None:
    root.mkdir(parents=True)
    prefix = "ts-phone-v0.8.5-build27"
    names = [
        *(
            name
            for abi in ("arm64-v8a", "armeabi-v7a", "x86_64")
            for name in (
                f"{prefix}-{abi}-release.apk",
                f"{prefix}-{abi}-release.apk.attestation.json",
            )
        ),
        f"{prefix}-release.aab",
        f"{prefix}-release.aab.attestation.json",
    ]
    for name in names:
        (root / name).write_text(f"{marker}:{name}\n", encoding="utf-8")


def _component_manifest(
    source: dict[str, object],
    apk: Path,
    attestation: Path,
    archive: Path,
    release_id: str,
) -> dict[str, object]:
    return {
        "schema_version": "ts-phone-component-release/2",
        "release_id": release_id,
        "component": {
            "name": "ts-phone",
            "server_version": "0.4.1",
            "mobile_version": "0.8.5",
            "mobile_build": 27,
        },
        "protocols": {key: EXPECTED_PROTOCOLS[key] for key in ("api", "events", "bridge")},
        "server_entry": file_descriptor(
            apk.parent / "services" / "server" / "dist" / "index.js",
            "services/server/dist/index.js",
        ),
        "mobile_artifact": {
            **file_descriptor(apk, f"artifacts/{apk.name}"),
            "abi": "arm64-v8a",
            "certificate_sha256": EXPECTED_ANDROID_CERTIFICATE_SHA256,
        },
        "mobile_build_attestation": file_descriptor(
            attestation,
            f"artifacts/{attestation.name}",
        ),
        "archive": {
            "filename": archive.name,
            "sha256": _sha256(archive),
            "size_bytes": archive.stat().st_size,
        },
        "source": source,
        "created_at_utc": "2026-09-06T00:00:00+00:00",
    }


def _git(root: Path, *arguments: str) -> None:
    subprocess.run(
        ["git", *arguments],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


if __name__ == "__main__":
    unittest.main()
