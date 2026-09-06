"""Build a deterministic TS Phone component archive and release manifest."""

from __future__ import annotations

import gzip
import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


SCHEMA_VERSION = "ts-phone-component-release/2"
PROTOCOL_SCHEMA_VERSION = "ts-phone-protocol-set/1"
MOBILE_BUILD_ATTESTATION_SCHEMA_VERSION = "ts-phone-mobile-build-attestation/1"
SOURCE_SNAPSHOT_SCHEMA_VERSION = "ts-phone-source-snapshot/1"
MANIFEST_NAME = "ts-phone-component-release.json"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_OBJECT_ID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
RELEASE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,159}$")
MOBILE_VERSION = re.compile(r"^([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$")
SERVER_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
MOBILE_APK_ABIS = {"arm64-v8a", "armeabi-v7a", "x86_64"}
ANDROID_RELEASE_ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
ANDROID_PACKAGE_NAME = "xyz.iawnix.ts_phone"
ANDROID_ABI_VERSION_CODE_OFFSETS = {"armeabi-v7a": 1000, "arm64-v8a": 2000, "x86_64": 4000}
EXPECTED_ANDROID_CERTIFICATE_SHA256 = "41998c3f13ee6a2b5e370b3ded25de4dc2af4e0de7172dbcc33e63bfa9fdc19f"
REQUIRED_SOURCE_PATHS = {
    b"package.json",
    b"apps/mobile/pubspec.yaml",
    b"apps/mobile/lib/app_identity.dart",
    b"deploy/release_builder.py",
    b"packages/protocol/versions.json",
}
EMBEDDED_SOURCE_SNAPSHOT_PATHS = {
    "apk": "assets/ts-phone-source-snapshot.json",
    "aab": "base/assets/ts-phone-source-snapshot.json",
}
MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES = 16 * 1024
MAX_COMPONENT_BOUND_MEMBER_BYTES = 512 * 1024 * 1024
MAX_COMPONENT_ARCHIVE_BYTES = MAX_COMPONENT_BOUND_MEMBER_BYTES
MAX_COMPONENT_EXPANDED_BYTES = 1024 * 1024 * 1024
MAX_RUNTIME_METADATA_BYTES = 64 * 1024 * 1024
EXPECTED_PROTOCOLS = {
    "schema_version": PROTOCOL_SCHEMA_VERSION,
    "api": "ts-phone-api/4",
    "events": "ts-phone-events/3",
    "bridge": "ts-phone-bridge/3",
}
EXPECTED_PROTOCOL_SCHEMA_IDS = {
    "bridge": "https://tsphone.iawnix.xyz/schema/bridge-v3.json",
    "events": "https://tsphone.iawnix.xyz/schema/events-v3.json",
}
LIFECYCLE_EVENT_TYPES = frozenset({"agent_start", "agent_settled"})
LIFECYCLE_ORIGINS = frozenset({"local", "extension", "phone", "unknown"})
LIFECYCLE_FIELDS = frozenset({"type", "origin", "turnId", "agentRunId"})
BOUNDED_ID_PATTERN = "^[A-Za-z0-9._:-]{1,160}$"
EVENT_ENVELOPE_FIELDS = frozenset(
    {
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
    }
)
BRIDGE_ENVELOPE_FIELDS = frozenset(
    {"protocolVersion", "type", "workspaceId", "sessionId", "instanceEpoch"}
)
COMPONENT_FIXED_FILE_MODES = {
    "VERSION": 0o644,
    "README.md": 0o644,
    "package.json": 0o644,
    "services/server/package.json": 0o644,
    "bin/ts-phone-ctl": 0o755,
    "bin/ts-phone-server": 0o755,
    "deploy/server.env.example": 0o644,
    "packages/protocol/versions.json": 0o644,
    "packages/protocol/bridge.schema.json": 0o644,
    "packages/protocol/events.schema.json": 0o644,
    "packages/protocol/openapi.yaml": 0o644,
    "docs/architecture.md": 0o644,
    "docs/deployment.md": 0o644,
    "docs/recovery.md": 0o644,
    "docs/security.md": 0o644,
}
REQUIRED_COMPONENT_FILES = frozenset(
    {
        *COMPONENT_FIXED_FILE_MODES,
        "services/server/dist/index.js",
        "services/server/dist/cli.js",
    }
)
FORBIDDEN_COMPONENT_PARTS = frozenset(
    {".git", ".gradle", ".runtime", "build", "node_modules", "tests", "test"}
)
FORBIDDEN_COMPONENT_FILES = frozenset({"deploy/systemd/ts-phone.service"})
FORBIDDEN_COMPONENT_SUFFIXES = frozenset({".jks", ".keystore", ".p12", ".pyc", ".pyo"})


class ComponentReleaseError(RuntimeError):
    """Raised when a TS Phone component cannot be released safely."""


def build_component_release(
    root: Path,
    output_dir: Path,
    *,
    mobile_apk: Path | None = None,
    apksigner: Path,
    allow_dirty: bool = False,
) -> dict[str, Any]:
    root = root.resolve()
    output_dir = output_dir.resolve()
    with tempfile.TemporaryDirectory(prefix="ts-phone-release-inputs.") as staging_name:
        staging = Path(staging_name)
        captured_root = staging / "source"
        source = capture_source_tree(root, captured_root, allow_dirty=allow_dirty)
        server_version = read_server_version(captured_root)
        mobile_name, mobile_build = read_mobile_version(
            captured_root / "apps" / "mobile" / "pubspec.yaml"
        )
        protocols = validate_protocol_documents(captured_root, server_version)

        apk = (mobile_apk or default_mobile_apk(root, mobile_name, mobile_build)).resolve()
        expected_apk_name = f"ts-phone-v{mobile_name}-build{mobile_build}-arm64-v8a-release.apk"
        if apk.name != expected_apk_name:
            raise ComponentReleaseError(f"mobile APK must be named {expected_apk_name}")
        attestation_path = mobile_build_attestation_path(apk)
        staged_apk = copy_release_input(apk, staging / apk.name, 0o600)
        staged_attestation = copy_release_input(
            attestation_path,
            staging / attestation_path.name,
            0o600,
        )
        validate_mobile_build_attestation(
            staged_attestation,
            staged_apk,
            expected_source=source,
            expected_mobile_version=mobile_name,
            expected_mobile_build=mobile_build,
            expected_format="apk",
            expected_abi="arm64-v8a",
        )
        certificate_sha256 = verify_apk(apksigner.resolve(), staged_apk)
        verify_apk_metadata(
            apksigner.resolve().with_name("aapt"),
            staged_apk,
            mobile_name,
            mobile_build,
            "arm64-v8a",
        )

        capture_node_dependencies(root, captured_root)
        run_checked(["npm", "run", "typecheck"], captured_root)
        run_checked(["npm", "test"], captured_root)
        clean_server_build_output(captured_root)
        run_checked(["npm", "run", "build"], captured_root)
        if not source["dirty"]:
            verify_clean_captured_source_tree(root, captured_root, source)

        records = release_records(captured_root, staged_apk, staged_attestation)
        staged_records = stage_release_records(records, staging / "archive-inputs")
        output_dir.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            prefix=".ts-phone-component.",
            suffix=".tgz",
            dir=output_dir,
            delete=False,
        ) as handle:
            temporary_archive = Path(handle.name)
        try:
            write_component_archive(staged_records, temporary_archive)
            archive_sha256 = sha256_file(temporary_archive)
            source_identity_sha256 = canonical_object_sha256(source)
            release_id = (
                f"{server_version}-mobile-{mobile_name}-build{mobile_build}-"
                f"source-{source_identity_sha256[:16]}-"
                f"sha256-{archive_sha256[:16]}"
            )
            if not RELEASE_ID.fullmatch(release_id):
                raise ComponentReleaseError("generated release_id exceeds the supported format or length")
            archive_name = f"ts-phone-component-{release_id}.tgz"
            archive_path = output_dir / archive_name
            if archive_path.exists():
                if not archive_path.is_file() or archive_path.is_symlink():
                    raise ComponentReleaseError(f"existing component archive is unsafe: {archive_path}")
                if sha256_file(archive_path) != archive_sha256:
                    raise ComponentReleaseError(f"existing component archive has different content: {archive_path}")
                temporary_archive.unlink()
            else:
                os.replace(temporary_archive, archive_path)
            archive_size = archive_path.stat().st_size
        finally:
            if temporary_archive.exists():
                temporary_archive.unlink()

        staged_by_name = {relative.as_posix(): path for relative, path, _ in staged_records}
        server_entry_relative = "services/server/dist/index.js"
        apk_relative = f"artifacts/{staged_apk.name}"
        attestation_relative = f"artifacts/{staged_attestation.name}"
        server_descriptor = file_descriptor(staged_by_name[server_entry_relative], server_entry_relative)
        mobile_descriptor = file_descriptor(staged_by_name[apk_relative], apk_relative)
        attestation_descriptor = file_descriptor(staged_by_name[attestation_relative], attestation_relative)

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "release_id": release_id,
        "component": {
            "name": "ts-phone",
            "server_version": server_version,
            "mobile_version": mobile_name,
            "mobile_build": mobile_build,
        },
        "protocols": {key: protocols[key] for key in ("api", "events", "bridge")},
        "server_entry": server_descriptor,
        "mobile_artifact": {
            **mobile_descriptor,
            "abi": "arm64-v8a",
            "certificate_sha256": certificate_sha256,
        },
        "mobile_build_attestation": attestation_descriptor,
        "archive": {
            "filename": archive_name,
            "sha256": archive_sha256,
            "size_bytes": archive_size,
        },
        "source": source,
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    validate_component_manifest(manifest)
    validate_component_archive(manifest, archive_path)
    manifest_path = output_dir / MANIFEST_NAME
    atomic_write_json(manifest_path, manifest)
    return {
        "ok": True,
        "archive": str(archive_path),
        "manifest": str(manifest_path),
        "release_id": release_id,
        "sha256": archive_sha256,
        "size_bytes": archive_size,
        "component": manifest["component"],
        "protocols": manifest["protocols"],
    }


def release_records(root: Path, apk: Path, attestation: Path) -> list[tuple[PurePosixPath, Path, int]]:
    records: list[tuple[PurePosixPath, Path, int]] = []
    for name, mode in COMPONENT_FIXED_FILE_MODES.items():
        relative = safe_relative(name)
        records.append((relative, require_regular_file(root.joinpath(*relative.parts)), mode))

    dist_root = root / "services" / "server" / "dist"
    if not dist_root.is_dir() or dist_root.is_symlink():
        raise ComponentReleaseError(f"server build output is missing or unsafe: {dist_root}")
    dist_files = [path for path in sorted(dist_root.rglob("*")) if path.is_file() or path.is_symlink()]
    if not dist_files:
        raise ComponentReleaseError("server build output is empty")
    for source in dist_files:
        require_regular_file(source)
        relative = source.relative_to(root).as_posix()
        records.append((safe_relative(relative), source, 0o644))

    records.append((safe_relative(f"artifacts/{apk.name}"), require_regular_file(apk), 0o644))
    records.append(
        (
            safe_relative(f"artifacts/{attestation.name}"),
            require_regular_file(attestation),
            0o644,
        )
    )
    names = [name.as_posix() for name, _, _ in records]
    if len(names) != len(set(names)):
        raise ComponentReleaseError("component archive contains duplicate target paths")
    validate_component_file_inventory(
        set(names),
        mobile_artifact_path=f"artifacts/{apk.name}",
        mobile_attestation_path=f"artifacts/{attestation.name}",
    )
    return sorted(records, key=lambda item: item[0].as_posix())


def clean_server_build_output(root: Path) -> None:
    dist_root = root.resolve() / "services" / "server" / "dist"
    if not dist_root.exists() and not dist_root.is_symlink():
        return
    if not dist_root.is_dir() or dist_root.is_symlink():
        raise ComponentReleaseError(f"server build output is unsafe: {dist_root}")
    shutil.rmtree(dist_root)


def capture_node_dependencies(root: Path, captured_root: Path) -> None:
    repository_root = root.resolve()
    source = repository_root / "node_modules"
    destination = captured_root.resolve() / "node_modules"
    if not source.is_dir() or source.is_symlink():
        raise ComponentReleaseError(f"Node dependencies are missing or unsafe: {source}")
    if destination.exists() or destination.is_symlink():
        raise ComponentReleaseError(f"captured Node dependency path already exists: {destination}")
    for entry in source.rglob("*"):
        if not entry.is_symlink():
            continue
        target = Path(os.readlink(entry))
        if target.is_absolute() or not (entry.parent / target).resolve().is_relative_to(repository_root):
            raise ComponentReleaseError(f"Node dependency link escapes the source repository: {entry}")
    shutil.copytree(source, destination, symlinks=True)


def stage_release_records(
    records: Iterable[tuple[PurePosixPath, Path, int]],
    staging_root: Path,
) -> list[tuple[PurePosixPath, Path, int]]:
    if staging_root.exists() or staging_root.is_symlink():
        raise ComponentReleaseError(f"archive input staging path already exists: {staging_root}")
    staging_root.mkdir(mode=0o700)
    staged: list[tuple[PurePosixPath, Path, int]] = []
    for relative, source, mode in sorted(records, key=lambda item: item[0].as_posix()):
        destination = staging_root.joinpath(*relative.parts)
        destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        staged.append((relative, copy_release_input(source, destination, mode), mode))
    return staged


def write_component_archive(records: Iterable[tuple[PurePosixPath, Path, int]], destination: Path) -> None:
    prepared = sorted(records, key=lambda item: item[0].as_posix())
    directories = {PurePosixPath("component")}
    for relative, _, _ in prepared:
        safe_relative(relative.as_posix())
        parent = PurePosixPath("component") / relative.parent
        while parent.parts:
            directories.add(parent)
            if parent == PurePosixPath("component"):
                break
            parent = parent.parent

    with destination.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for directory in sorted(directories, key=lambda item: (len(item.parts), item.as_posix())):
                    info = normalized_tar_info(directory.as_posix() + "/", mode=0o755, size=0)
                    info.type = tarfile.DIRTYPE
                    archive.addfile(info)
                for relative, source, mode in prepared:
                    content = source.read_bytes()
                    member_name = (PurePosixPath("component") / relative).as_posix()
                    info = normalized_tar_info(member_name, mode=mode, size=len(content))
                    archive.addfile(info, io.BytesIO(content))


def validate_component_archive(value: object, archive_path: Path) -> dict[str, Any]:
    manifest = validate_component_manifest(value)
    archive_path = archive_path.resolve()
    archive_descriptor = manifest["archive"]
    if archive_descriptor["filename"] != archive_path.name:
        raise ComponentReleaseError("component archive filename does not match its manifest")
    archive_content = read_regular_file_snapshot(
        archive_path,
        "component archive",
        max_bytes=MAX_COMPONENT_ARCHIVE_BYTES,
    )
    if (
        archive_descriptor["size_bytes"] != len(archive_content)
        or archive_descriptor["sha256"] != sha256_bytes(archive_content)
    ):
        raise ComponentReleaseError("component archive digest or size does not match its manifest")

    try:
        with tarfile.open(fileobj=io.BytesIO(archive_content), mode="r:gz") as archive:
            files = inspect_component_archive_members(archive)
            validate_component_file_inventory(
                files,
                mobile_artifact_path=manifest["mobile_artifact"]["path"],
                mobile_attestation_path=manifest["mobile_build_attestation"]["path"],
            )
            validate_archived_runtime_metadata(archive, manifest)
            server_content = read_bound_archive_member(archive, manifest["server_entry"], "server entry")
            mobile_content = read_bound_archive_member(archive, manifest["mobile_artifact"], "mobile artifact")
            attestation_content = read_bound_archive_member(
                archive,
                manifest["mobile_build_attestation"],
                "mobile build attestation",
                max_bytes=MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES,
            )
    except (OSError, tarfile.TarError) as error:
        raise ComponentReleaseError(f"could not validate component archive: {error}") from error
    if not server_content:
        raise ComponentReleaseError("component archive server entry is empty")

    try:
        attestation = json.loads(attestation_content.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ComponentReleaseError("archived mobile build attestation is not valid UTF-8 JSON") from error
    component = manifest["component"]
    mobile = manifest["mobile_artifact"]
    validate_mobile_build_attestation_payload(
        attestation,
        artifact_name=Path(mobile["path"]).name,
        artifact_content=mobile_content,
        expected_source=manifest["source"],
        expected_mobile_version=component["mobile_version"],
        expected_mobile_build=component["mobile_build"],
        expected_format="apk",
        expected_abi=mobile["abi"],
    )
    return manifest


def validate_archived_runtime_metadata(archive: tarfile.TarFile, manifest: dict[str, Any]) -> None:
    component = manifest["component"]
    server_version = component["server_version"]
    try:
        version = read_named_archive_member(archive, "VERSION", "VERSION").decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise ComponentReleaseError("component archive VERSION is not UTF-8") from error
    if version != server_version:
        raise ComponentReleaseError("component archive VERSION does not match the server version")
    package = decode_json_object(
        read_named_archive_member(archive, "package.json", "package.json"),
        "component archive package.json",
    )
    if package.get("name") != "ts-phone" or package.get("version") != server_version:
        raise ComponentReleaseError("component archive package identity does not match the server version")
    server_package = decode_json_object(
        read_named_archive_member(archive, "services/server/package.json", "server package.json"),
        "component archive server package.json",
    )
    if (
        server_package.get("name") != "@iawnix/ts-phone-server"
        or server_package.get("version") != server_version
    ):
        raise ComponentReleaseError("component archive server package identity does not match")
    for name in ("bin/ts-phone-ctl", "bin/ts-phone-server"):
        member = named_archive_member(archive, name, name)
        if not member.mode & 0o111:
            raise ComponentReleaseError(f"component archive entrypoint is not executable: {name}")
    validate_protocol_payloads(
        read_named_archive_member(archive, "packages/protocol/versions.json", "protocol versions"),
        read_named_archive_member(archive, "packages/protocol/bridge.schema.json", "bridge schema"),
        read_named_archive_member(archive, "packages/protocol/events.schema.json", "events schema"),
        read_named_archive_member(archive, "packages/protocol/openapi.yaml", "OpenAPI document"),
        server_version,
    )


def named_archive_member(archive: tarfile.TarFile, relative: str, label: str) -> tarfile.TarInfo:
    expected = (PurePosixPath("component") / safe_relative(relative)).as_posix()
    matches = [member for member in archive.getmembers() if member.name == expected]
    if len(matches) != 1 or not matches[0].isfile():
        raise ComponentReleaseError(f"component archive must contain exactly one regular {label}")
    return matches[0]


def read_named_archive_member(archive: tarfile.TarFile, relative: str, label: str) -> bytes:
    member = named_archive_member(archive, relative, label)
    if member.size < 0 or member.size > MAX_RUNTIME_METADATA_BYTES:
        raise ComponentReleaseError(f"component archive {label} exceeds the size limit")
    extracted = archive.extractfile(member)
    if extracted is None:
        raise ComponentReleaseError(f"component archive {label} cannot be read")
    with extracted:
        content = extracted.read(member.size + 1)
    if len(content) != member.size:
        raise ComponentReleaseError(f"component archive {label} size is invalid")
    return content


def decode_json_object(content: bytes, label: str) -> dict[str, Any]:
    try:
        value = json.loads(content.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ComponentReleaseError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise ComponentReleaseError(f"{label} must contain an object")
    return value


def inspect_component_archive_members(archive: tarfile.TarFile) -> set[str]:
    files: set[str] = set()
    seen: set[str] = set()
    expanded_size = 0
    for member in archive.getmembers():
        raw = PurePosixPath(member.name)
        if raw.is_absolute() or not raw.parts or raw.parts[0] != "component" or ".." in raw.parts:
            raise ComponentReleaseError(f"component archive member escapes its root: {member.name}")
        relative = PurePosixPath(*raw.parts[1:])
        if not relative.parts:
            if not member.isdir():
                raise ComponentReleaseError("component archive root must be a directory")
            continue
        name = relative.as_posix()
        if name in seen:
            raise ComponentReleaseError(f"component archive contains duplicate member: {name}")
        seen.add(name)
        if not member.isdir() and not member.isfile():
            raise ComponentReleaseError(f"component archive contains unsupported member type: {name}")
        if member.size < 0 or member.size > MAX_COMPONENT_BOUND_MEMBER_BYTES:
            raise ComponentReleaseError(f"component archive member exceeds the size limit: {name}")
        expanded_size += member.size
        if expanded_size > MAX_COMPONENT_EXPANDED_BYTES:
            raise ComponentReleaseError("component archive expands beyond the size limit")
        if member.isfile():
            files.add(name)
    return files


def validate_component_file_inventory(
    files: set[str],
    *,
    mobile_artifact_path: str,
    mobile_attestation_path: str,
) -> None:
    required = {
        *REQUIRED_COMPONENT_FILES,
        safe_relative(mobile_artifact_path).as_posix(),
        safe_relative(mobile_attestation_path).as_posix(),
    }
    missing = sorted(required - files)
    if missing:
        raise ComponentReleaseError(f"component archive is missing runtime files: {', '.join(missing)}")
    for name in files:
        relative = safe_relative(name)
        if name in FORBIDDEN_COMPONENT_FILES:
            raise ComponentReleaseError(f"component archive contains installation-owned content: {name}")
        if FORBIDDEN_COMPONENT_PARTS.intersection(relative.parts):
            raise ComponentReleaseError(f"component archive contains development-only content: {name}")
        if relative.name.startswith(".env") or relative.suffix in FORBIDDEN_COMPONENT_SUFFIXES:
            raise ComponentReleaseError(f"component archive contains forbidden runtime content: {name}")


def read_bound_archive_member(
    archive: tarfile.TarFile,
    descriptor: dict[str, Any],
    label: str,
    *,
    max_bytes: int = MAX_COMPONENT_BOUND_MEMBER_BYTES,
) -> bytes:
    member_name = (PurePosixPath("component") / safe_relative(descriptor["path"])).as_posix()
    matches = [member for member in archive.getmembers() if member.name == member_name]
    if len(matches) != 1 or not matches[0].isfile():
        raise ComponentReleaseError(f"component archive must contain exactly one regular {label}")
    member = matches[0]
    if member.size > max_bytes:
        raise ComponentReleaseError(f"component archive {label} exceeds the size limit")
    if member.size != descriptor["size_bytes"]:
        raise ComponentReleaseError(f"component archive {label} size does not match its manifest")
    extracted = archive.extractfile(member)
    if extracted is None:
        raise ComponentReleaseError(f"component archive {label} cannot be read")
    with extracted:
        content = extracted.read(member.size + 1)
    if len(content) != member.size or sha256_bytes(content) != descriptor["sha256"]:
        raise ComponentReleaseError(f"component archive {label} digest or size does not match its manifest")
    return content


def normalized_tar_info(name: str, *, mode: int, size: int) -> tarfile.TarInfo:
    info = tarfile.TarInfo(name)
    info.mode = mode
    info.size = size
    info.mtime = 0
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    return info


def validate_component_manifest(value: object) -> dict[str, Any]:
    expected = {
        "schema_version",
        "release_id",
        "component",
        "protocols",
        "server_entry",
        "mobile_artifact",
        "mobile_build_attestation",
        "archive",
        "source",
        "created_at_utc",
    }
    if not isinstance(value, dict) or set(value) != expected or value.get("schema_version") != SCHEMA_VERSION:
        raise ComponentReleaseError("invalid TS Phone component release manifest schema")
    component = exact_object(
        value.get("component"),
        "component",
        {"name", "server_version", "mobile_version", "mobile_build"},
    )
    if component.get("name") != "ts-phone":
        raise ComponentReleaseError("component.name must be ts-phone")
    server_version = require_string(component.get("server_version"), "component.server_version")
    mobile_version = require_string(component.get("mobile_version"), "component.mobile_version")
    mobile_build = component.get("mobile_build")
    if not SERVER_VERSION.fullmatch(server_version) or not SERVER_VERSION.fullmatch(mobile_version):
        raise ComponentReleaseError("component versions must use semantic x.y.z form")
    if not isinstance(mobile_build, int) or isinstance(mobile_build, bool) or mobile_build <= 0:
        raise ComponentReleaseError("component.mobile_build must be a positive integer")
    protocols = exact_object(value.get("protocols"), "protocols", {"api", "events", "bridge"})
    if protocols != {key: EXPECTED_PROTOCOLS[key] for key in protocols}:
        raise ComponentReleaseError("component protocol set is unsupported")
    server_entry = validate_file_descriptor(value.get("server_entry"), "server_entry")
    if server_entry["path"] != "services/server/dist/index.js":
        raise ComponentReleaseError("server_entry.path is invalid")
    mobile = exact_object(
        value.get("mobile_artifact"),
        "mobile_artifact",
        {"path", "sha256", "size_bytes", "abi", "certificate_sha256"},
    )
    validate_file_descriptor({key: mobile[key] for key in ("path", "sha256", "size_bytes")}, "mobile_artifact")
    if (
        mobile.get("abi") != "arm64-v8a"
        or mobile.get("certificate_sha256") != EXPECTED_ANDROID_CERTIFICATE_SHA256
    ):
        raise ComponentReleaseError("mobile artifact ABI or signing certificate is invalid")
    expected_mobile_path = f"artifacts/{mobile_artifact_name(mobile_version, mobile_build, 'apk', mobile['abi'])}"
    if mobile["path"] != expected_mobile_path:
        raise ComponentReleaseError("mobile_artifact.path does not match component version and build")
    attestation = validate_file_descriptor(value.get("mobile_build_attestation"), "mobile_build_attestation")
    if attestation["path"] != f"{mobile['path']}.attestation.json":
        raise ComponentReleaseError("mobile_build_attestation.path does not match mobile_artifact.path")
    archive = validate_file_descriptor(value.get("archive"), "archive", filename_key="filename")
    source = validate_source_snapshot(value.get("source"))
    release_id = require_string(value.get("release_id"), "release_id")
    if not RELEASE_ID.fullmatch(release_id):
        raise ComponentReleaseError("release_id exceeds the supported format or length")
    expected_release = (
        f"{server_version}-mobile-{mobile_version}-build{mobile_build}-"
        f"source-{canonical_object_sha256(source)[:16]}-"
        f"sha256-{archive['sha256'][:16]}"
    )
    if release_id != expected_release:
        raise ComponentReleaseError("release_id does not match component versions and archive digest")
    if archive["filename"] != f"ts-phone-component-{release_id}.tgz":
        raise ComponentReleaseError("archive.filename does not match release_id")
    require_string(value.get("created_at_utc"), "created_at_utc")
    return value


def validate_file_descriptor(value: object, label: str, *, filename_key: str = "path") -> dict[str, Any]:
    descriptor = exact_object(value, label, {filename_key, "sha256", "size_bytes"})
    name = require_string(descriptor.get(filename_key), f"{label}.{filename_key}")
    if filename_key == "path":
        safe_relative(name)
    elif Path(name).name != name:
        raise ComponentReleaseError(f"{label}.{filename_key} must be a basename")
    digest = require_string(descriptor.get("sha256"), f"{label}.sha256")
    if not SHA256.fullmatch(digest):
        raise ComponentReleaseError(f"{label}.sha256 must be a lowercase SHA-256 digest")
    size = descriptor.get("size_bytes")
    if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
        raise ComponentReleaseError(f"{label}.size_bytes must be a positive integer")
    return descriptor


def source_snapshot(root: Path) -> dict[str, Any]:
    """Hash tracked and non-ignored source; Git-ignored build outputs are excluded."""
    snapshot, _ = inspect_source(root)
    return snapshot


def capture_source_tree(root: Path, destination: Path, *, allow_dirty: bool = False) -> dict[str, Any]:
    """Capture the exact source tree used by a release build into private staging."""
    root = root.resolve()
    destination = destination.resolve()
    if destination.is_relative_to(root):
        raise ComponentReleaseError("captured source destination must be outside the source repository")
    snapshot, relative_names = inspect_source(root)
    if snapshot["dirty"] and not allow_dirty:
        raise ComponentReleaseError(
            "component releases require a clean Git checkout; use --allow-dirty only for local validation"
        )
    if destination.exists() or destination.is_symlink():
        raise ComponentReleaseError(f"captured source destination already exists: {destination}")
    destination.mkdir(mode=0o700, parents=True)

    if snapshot["dirty"]:
        copy_source_entries(root, destination, relative_names)
    else:
        export_git_source(root, destination, snapshot["git_commit"], relative_names)

    captured = snapshot_from_tree(
        destination,
        relative_names,
        git_commit=snapshot["git_commit"],
        dirty=snapshot["dirty"],
    )
    if captured != snapshot:
        raise ComponentReleaseError("source changed while it was being captured for the release build")
    return captured


def verify_clean_captured_source_tree(
    repository_root: Path,
    captured_root: Path,
    expected_source: object,
) -> None:
    expected = validate_source_snapshot(expected_source)
    if expected["dirty"]:
        raise ComponentReleaseError("only a clean captured source can be verified from a Git commit")
    listed = run_git(
        repository_root.resolve(),
        ["ls-tree", "-r", "--name-only", "-z", expected["git_commit"]],
        "read captured source inventory",
    )
    relative_names = sorted({name for name in listed.split(b"\0") if name})
    actual = snapshot_from_tree(
        captured_root.resolve(),
        relative_names,
        git_commit=expected["git_commit"],
        dirty=False,
    )
    if actual != expected:
        raise ComponentReleaseError("captured source changed during the release build")


def inspect_source(root: Path) -> tuple[dict[str, Any], list[bytes]]:
    root = root.resolve()
    top_level = run_git(root, ["rev-parse", "--show-toplevel"], "locate source repository")
    repository_root = Path(os.fsdecode(top_level).strip()).resolve()
    if repository_root != root:
        raise ComponentReleaseError("source root must be the top level of the TS Phone Git repository")
    revision = run_git(root, ["rev-parse", "--verify", "HEAD"], "read source commit")
    git_commit = revision.decode("ascii", errors="strict").strip()
    if not GIT_OBJECT_ID.fullmatch(git_commit):
        raise ComponentReleaseError("source commit is not a full Git object ID")

    tracked_flags = run_git(root, ["ls-files", "-v", "-z"], "inspect source index flags")
    unsafe_flags = [entry for entry in tracked_flags.split(b"\0") if entry and not entry.startswith(b"H ")]
    if unsafe_flags:
        raise ComponentReleaseError("source index contains assume-unchanged, skip-worktree, or unresolved entries")

    listed = run_git(
        root,
        ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        "list source files",
    )
    relative_names = sorted({name for name in listed.split(b"\0") if name})
    missing_required = sorted(REQUIRED_SOURCE_PATHS.difference(relative_names))
    if missing_required:
        missing = ", ".join(os.fsdecode(name) for name in missing_required)
        raise ComponentReleaseError(f"source repository is missing required paths: {missing}")
    status = run_git(
        root,
        ["status", "--porcelain=v1", "-z", "--untracked-files=normal"],
        "read source status",
    )
    return (
        snapshot_from_tree(
            root,
            relative_names,
            git_commit=git_commit,
            dirty=bool(status),
        ),
        relative_names,
    )


def snapshot_from_tree(
    root: Path,
    relative_names: Iterable[bytes],
    *,
    git_commit: str,
    dirty: bool,
) -> dict[str, Any]:
    digest = hashlib.sha256()
    digest.update(SOURCE_SNAPSHOT_SCHEMA_VERSION.encode("ascii") + b"\0")
    for raw_name in relative_names:
        relative = safe_relative(os.fsdecode(raw_name))
        source = root.joinpath(*relative.parts)
        if source.is_symlink():
            raise ComponentReleaseError(f"release source must not contain symlinks: {relative}")
        if source.is_file():
            executable = 0o111 if source.stat().st_mode & 0o111 else 0
            kind = f"file:{executable:03o}".encode("ascii")
            content = source.read_bytes()
        elif not source.exists():
            kind = b"missing"
            content = b""
        else:
            raise ComponentReleaseError(f"source entry is not a regular file: {relative}")
        update_framed_digest(digest, raw_name)
        update_framed_digest(digest, kind)
        update_framed_digest(digest, content)
    return {
        "schema_version": SOURCE_SNAPSHOT_SCHEMA_VERSION,
        "git_commit": git_commit,
        "dirty": dirty,
        "sha256": digest.hexdigest(),
    }


def copy_source_entries(root: Path, destination: Path, relative_names: Iterable[bytes]) -> None:
    for raw_name in relative_names:
        relative = safe_relative(os.fsdecode(raw_name))
        source = root.joinpath(*relative.parts)
        if source.is_symlink():
            raise ComponentReleaseError(f"release source must not contain symlinks: {relative}")
        if not source.exists():
            continue
        source = require_regular_file(source)
        target = destination.joinpath(*relative.parts)
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        os.chmod(target, 0o755 if source.stat().st_mode & 0o111 else 0o644)


def export_git_source(
    root: Path,
    destination: Path,
    git_commit: str,
    expected_names: Iterable[bytes],
) -> None:
    encoded = run_git(root, ["archive", "--format=tar", git_commit], "capture committed source")
    extracted_names: set[bytes] = set()
    try:
        with tarfile.open(fileobj=io.BytesIO(encoded), mode="r:") as archive:
            for member in archive.getmembers():
                relative = safe_relative(member.name.rstrip("/"))
                target = destination.joinpath(*relative.parts)
                if member.isdir():
                    target.mkdir(mode=0o700, parents=True, exist_ok=True)
                    continue
                if not member.isfile():
                    raise ComponentReleaseError(f"committed release source contains a non-file: {relative}")
                raw_name = os.fsencode(relative.as_posix())
                if raw_name in extracted_names:
                    raise ComponentReleaseError(f"committed release source contains a duplicate path: {relative}")
                extracted_names.add(raw_name)
                extracted = archive.extractfile(member)
                if extracted is None:
                    raise ComponentReleaseError(f"committed release source cannot be read: {relative}")
                with extracted:
                    content = extracted.read(member.size + 1)
                if len(content) != member.size:
                    raise ComponentReleaseError(f"committed release source has an invalid size: {relative}")
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                with target.open("xb") as handle:
                    handle.write(content)
                os.chmod(target, 0o755 if member.mode & 0o111 else 0o644)
    except (OSError, tarfile.TarError) as error:
        raise ComponentReleaseError(f"could not capture committed release source: {error}") from error
    if extracted_names != set(expected_names):
        raise ComponentReleaseError("committed source archive does not match the release source inventory")


def validate_source_snapshot(value: object) -> dict[str, Any]:
    snapshot = exact_object(
        value,
        "source snapshot",
        {"schema_version", "git_commit", "dirty", "sha256"},
    )
    if snapshot.get("schema_version") != SOURCE_SNAPSHOT_SCHEMA_VERSION:
        raise ComponentReleaseError("source snapshot schema version is unsupported")
    commit = require_string(snapshot.get("git_commit"), "source snapshot git_commit")
    if not GIT_OBJECT_ID.fullmatch(commit):
        raise ComponentReleaseError("source snapshot git_commit must be a full Git object ID")
    if not isinstance(snapshot.get("dirty"), bool):
        raise ComponentReleaseError("source snapshot dirty must be boolean")
    digest = require_string(snapshot.get("sha256"), "source snapshot sha256")
    if not SHA256.fullmatch(digest):
        raise ComponentReleaseError("source snapshot sha256 must be a lowercase SHA-256 digest")
    return snapshot


def write_mobile_build_attestation(
    root: Path,
    artifact: Path,
    *,
    artifact_format: str,
    abi: str,
    expected_source: object,
) -> Path:
    """Bind an artifact to a live source tree after confirming it is unchanged."""
    expected = validate_source_snapshot(expected_source)
    current = source_snapshot(root)
    if current != expected:
        raise ComponentReleaseError("source changed while building Android release artifacts")
    return write_mobile_build_attestation_from_captured_source(
        root,
        artifact,
        artifact_format=artifact_format,
        abi=abi,
        expected_source=current,
    )


def write_mobile_build_attestation_from_captured_source(
    source_root: Path,
    artifact: Path,
    *,
    artifact_format: str,
    abi: str,
    expected_source: object,
) -> Path:
    """Bind an artifact to an already captured, private build source tree."""
    source = validate_source_snapshot(expected_source)
    artifact = artifact.resolve()
    artifact_content = read_regular_file_snapshot(
        artifact,
        "mobile build artifact",
        max_bytes=MAX_COMPONENT_BOUND_MEMBER_BYTES,
    )
    embedded = read_embedded_source_snapshot_bytes(artifact_content, artifact_format)
    if embedded != source:
        raise ComponentReleaseError("mobile artifact does not embed the captured source snapshot")

    mobile_version, mobile_build = read_mobile_version(
        source_root.resolve() / "apps" / "mobile" / "pubspec.yaml"
    )
    expected_name = mobile_artifact_name(mobile_version, mobile_build, artifact_format, abi)
    if artifact.name != expected_name:
        raise ComponentReleaseError(f"mobile artifact must be named {expected_name}")

    attestation = {
        "schema_version": MOBILE_BUILD_ATTESTATION_SCHEMA_VERSION,
        "source": source,
        "mobile": {"version": mobile_version, "build": mobile_build},
        "target": {"format": artifact_format, "abi": abi},
        "artifact": {
            "filename": artifact.name,
            "sha256": sha256_bytes(artifact_content),
            "size_bytes": len(artifact_content),
        },
    }
    validate_mobile_build_attestation_payload(
        attestation,
        artifact_name=artifact.name,
        artifact_content=artifact_content,
        expected_source=source,
        expected_mobile_version=mobile_version,
        expected_mobile_build=mobile_build,
        expected_format=artifact_format,
        expected_abi=abi,
    )
    destination = mobile_build_attestation_path(artifact)
    atomic_write_json(destination, attestation)
    return destination


def validate_mobile_build_attestation(
    value_or_path: object,
    artifact: Path,
    *,
    expected_source: object,
    expected_mobile_version: str,
    expected_mobile_build: int,
    expected_format: str,
    expected_abi: str,
) -> dict[str, Any]:
    artifact = artifact.resolve()
    artifact_content = read_regular_file_snapshot(
        artifact,
        "mobile build artifact",
        max_bytes=MAX_COMPONENT_BOUND_MEMBER_BYTES,
    )
    if isinstance(value_or_path, Path):
        value: object = read_object(value_or_path, "mobile build attestation")
    else:
        value = value_or_path
    return validate_mobile_build_attestation_payload(
        value,
        artifact_name=artifact.name,
        artifact_content=artifact_content,
        expected_source=expected_source,
        expected_mobile_version=expected_mobile_version,
        expected_mobile_build=expected_mobile_build,
        expected_format=expected_format,
        expected_abi=expected_abi,
    )


def validate_mobile_build_attestation_payload(
    value: object,
    *,
    artifact_name: str,
    artifact_content: bytes,
    expected_source: object,
    expected_mobile_version: str,
    expected_mobile_build: int,
    expected_format: str,
    expected_abi: str,
) -> dict[str, Any]:
    attestation = exact_object(
        value,
        "mobile build attestation",
        {"schema_version", "source", "mobile", "target", "artifact"},
    )
    if attestation.get("schema_version") != MOBILE_BUILD_ATTESTATION_SCHEMA_VERSION:
        raise ComponentReleaseError("mobile build attestation schema version is unsupported")

    source = validate_source_snapshot(attestation.get("source"))
    if source != validate_source_snapshot(expected_source):
        raise ComponentReleaseError("mobile build attestation does not match the current source snapshot")

    mobile = exact_object(attestation.get("mobile"), "mobile build", {"version", "build"})
    mobile_version = require_string(mobile.get("version"), "mobile build version")
    mobile_build = mobile.get("build")
    if not SERVER_VERSION.fullmatch(mobile_version):
        raise ComponentReleaseError("mobile build version must use semantic x.y.z form")
    if not isinstance(mobile_build, int) or isinstance(mobile_build, bool) or mobile_build <= 0:
        raise ComponentReleaseError("mobile build number must be a positive integer")
    if mobile.get("version") != expected_mobile_version or mobile.get("build") != expected_mobile_build:
        raise ComponentReleaseError("mobile build attestation version does not match the current mobile version")

    target = exact_object(attestation.get("target"), "mobile build target", {"format", "abi"})
    if target != {"format": expected_format, "abi": expected_abi}:
        raise ComponentReleaseError("mobile build attestation target does not match the requested artifact")
    expected_name = mobile_artifact_name(
        expected_mobile_version,
        expected_mobile_build,
        expected_format,
        expected_abi,
    )
    if artifact_name != expected_name:
        raise ComponentReleaseError(f"mobile artifact must be named {expected_name}")
    embedded = read_embedded_source_snapshot_bytes(artifact_content, expected_format)
    if embedded != source:
        raise ComponentReleaseError("mobile artifact embedded source snapshot does not match its attestation")

    descriptor = validate_file_descriptor(
        attestation.get("artifact"),
        "mobile build artifact",
        filename_key="filename",
    )
    if descriptor["filename"] != artifact_name:
        raise ComponentReleaseError("mobile build attestation names a different artifact")
    if descriptor["size_bytes"] != len(artifact_content) or descriptor["sha256"] != sha256_bytes(artifact_content):
        raise ComponentReleaseError("mobile build attestation artifact digest or size does not match")
    return attestation


def mobile_artifact_name(version: str, build: int, artifact_format: str, abi: str) -> str:
    prefix = f"ts-phone-v{version}-build{build}"
    if artifact_format == "apk" and abi in MOBILE_APK_ABIS:
        return f"{prefix}-{abi}-release.apk"
    if artifact_format == "aab" and abi == "universal":
        return f"{prefix}-release.aab"
    raise ComponentReleaseError(f"unsupported mobile build target: {artifact_format}/{abi}")


def mobile_build_attestation_path(artifact: Path) -> Path:
    return artifact.with_name(f"{artifact.name}.attestation.json")


def read_embedded_source_snapshot(artifact: Path, artifact_format: str) -> dict[str, Any]:
    return read_embedded_source_snapshot_bytes(
        read_regular_file_snapshot(
            artifact.resolve(),
            "mobile build artifact",
            max_bytes=MAX_COMPONENT_BOUND_MEMBER_BYTES,
        ),
        artifact_format,
    )


def read_embedded_source_snapshot_bytes(artifact_content: bytes, artifact_format: str) -> dict[str, Any]:
    member_name = EMBEDDED_SOURCE_SNAPSHOT_PATHS.get(artifact_format)
    if member_name is None:
        raise ComponentReleaseError(f"unsupported mobile artifact format: {artifact_format}")
    try:
        with zipfile.ZipFile(io.BytesIO(artifact_content)) as archive:
            matches = [entry for entry in archive.infolist() if entry.filename == member_name]
            if len(matches) != 1 or matches[0].is_dir():
                raise ComponentReleaseError("mobile artifact must contain exactly one source snapshot")
            if matches[0].file_size > MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES:
                raise ComponentReleaseError("mobile artifact source snapshot exceeds the size limit")
            with archive.open(matches[0]) as handle:
                encoded = handle.read(MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES + 1)
    except (OSError, RuntimeError, zipfile.BadZipFile, zipfile.LargeZipFile) as error:
        raise ComponentReleaseError(f"could not read mobile artifact source snapshot: {error}") from error
    if len(encoded) > MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES:
        raise ComponentReleaseError("mobile artifact source snapshot exceeds the size limit")
    try:
        value = json.loads(encoded.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ComponentReleaseError("mobile artifact source snapshot is not valid UTF-8 JSON") from error
    return validate_source_snapshot(value)


def run_git(root: Path, arguments: list[str], action: str) -> bytes:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise ComponentReleaseError(detail or f"could not {action}")
    return completed.stdout


def update_framed_digest(digest: Any, value: bytes) -> None:
    digest.update(len(value).to_bytes(8, byteorder="big", signed=False))
    digest.update(value)


def verify_apk(apksigner: Path, apk: Path) -> str:
    require_regular_file(apksigner)
    completed = subprocess.run(
        [str(apksigner), "verify", "--verbose", "--print-certs", str(apk)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise ComponentReleaseError(completed.stderr.strip() or "APK signature verification failed")
    if "Verified using v2 scheme (APK Signature Scheme v2): true" not in completed.stdout:
        raise ComponentReleaseError("APK does not carry a verified v2 signature")
    certificates = [
        digest.lower()
        for digest in re.findall(
            r"(?m)^Signer #[0-9]+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})\s*$",
            completed.stdout,
        )
    ]
    if not certificates:
        raise ComponentReleaseError("APK signer certificate digest is unavailable")
    if certificates != [EXPECTED_ANDROID_CERTIFICATE_SHA256]:
        raise ComponentReleaseError("APK signer does not match the TS Phone release certificate")
    return certificates[0]


def verify_apk_metadata(
    aapt: Path,
    apk: Path,
    mobile_version: str,
    mobile_build: int,
    abi: str,
) -> None:
    require_regular_file(aapt)
    completed = subprocess.run(
        [str(aapt), "dump", "badging", str(require_regular_file(apk))],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise ComponentReleaseError(completed.stderr.strip() or "APK metadata verification failed")
    validate_apk_badging(completed.stdout, mobile_version, mobile_build, abi)


def validate_apk_badging(value: str, mobile_version: str, mobile_build: int, abi: str) -> None:
    package = re.search(
        r"(?m)^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'",
        value,
    )
    if package is None:
        raise ComponentReleaseError("APK package metadata is unavailable")
    version_code_offset = ANDROID_ABI_VERSION_CODE_OFFSETS.get(abi)
    if version_code_offset is None:
        raise ComponentReleaseError(f"unsupported APK ABI: {abi}")
    expected_version_code = version_code_offset + mobile_build
    if (
        package.group(1) != ANDROID_PACKAGE_NAME
        or package.group(2) != str(expected_version_code)
        or package.group(3) != mobile_version
    ):
        raise ComponentReleaseError("APK package name, version name, or version code is invalid")
    native_code = re.search(r"(?m)^native-code:\s*(.+)$", value)
    native_abis = re.findall(r"'([^']+)'", native_code.group(1)) if native_code is not None else []
    if native_abis != [abi]:
        raise ComponentReleaseError("APK native ABI does not match the release target")
    if re.search(r"(?m)^application-debuggable(?:\s|$)", value):
        raise ComponentReleaseError("APK must not be debuggable")


def read_mobile_version(path: Path) -> tuple[str, int]:
    text = require_regular_file(path).read_text(encoding="utf-8")
    match = re.search(r"(?m)^version:\s*([^\s#]+)\s*$", text)
    if match is None:
        raise ComponentReleaseError("mobile pubspec has no version")
    parsed = MOBILE_VERSION.fullmatch(match.group(1))
    if parsed is None:
        raise ComponentReleaseError(f"invalid mobile version: {match.group(1)}")
    mobile_version = parsed.group(1)
    mobile_build = int(parsed.group(2))

    identity_text = require_regular_file(path.parent / "lib" / "app_identity.dart").read_text(encoding="utf-8")
    identity_versions = re.findall(
        r"(?m)^const String tsPhoneAppVersion = '([0-9]+\.[0-9]+\.[0-9]+)';$",
        identity_text,
    )
    identity_builds = re.findall(
        r"(?m)^const String tsPhoneAppBuild = '([1-9][0-9]*)';$",
        identity_text,
    )
    if identity_versions != [mobile_version] or identity_builds != [str(mobile_build)]:
        raise ComponentReleaseError("mobile app identity version or build does not match pubspec")
    return mobile_version, mobile_build


def read_server_version(root: Path) -> str:
    package = read_object(root / "package.json", "package.json")
    if package.get("name") != "ts-phone":
        raise ComponentReleaseError("package.name must be ts-phone")
    server_version = require_string(package.get("version"), "package.version")
    if not SERVER_VERSION.fullmatch(server_version):
        raise ComponentReleaseError(f"invalid server version: {server_version}")

    server_package = read_object(root / "services" / "server" / "package.json", "server package.json")
    if server_package.get("name") != "@iawnix/ts-phone-server":
        raise ComponentReleaseError("server package.name must be @iawnix/ts-phone-server")
    if server_package.get("version") != server_version:
        raise ComponentReleaseError("server package.version does not match package.version")

    package_lock = read_object(root / "package-lock.json", "package-lock.json")
    if package_lock.get("name") != "ts-phone" or package_lock.get("version") != server_version:
        raise ComponentReleaseError("package-lock root name or version does not match package.version")
    lock_packages = package_lock.get("packages")
    if not isinstance(lock_packages, dict):
        raise ComponentReleaseError("package-lock packages must contain an object")
    lock_root = lock_packages.get("")
    lock_server = lock_packages.get("services/server")
    if not isinstance(lock_root, dict) or lock_root.get("version") != server_version:
        raise ComponentReleaseError("package-lock root workspace version does not match package.version")
    if not isinstance(lock_server, dict) or lock_server.get("version") != server_version:
        raise ComponentReleaseError("package-lock server workspace version does not match package.version")

    version_file = require_regular_file(root / "VERSION")
    if version_file.read_text(encoding="utf-8").strip() != server_version:
        raise ComponentReleaseError("VERSION does not match package.version")

    types_text = require_regular_file(root / "services" / "server" / "src" / "types.ts").read_text(
        encoding="utf-8"
    )
    service_versions = re.findall(
        r'(?m)^export const SERVICE_VERSION = "([0-9]+\.[0-9]+\.[0-9]+)" as const;$',
        types_text,
    )
    if service_versions != [server_version]:
        raise ComponentReleaseError("SERVICE_VERSION does not match package.version")

    openapi_version = read_openapi_info_version(root / "packages" / "protocol" / "openapi.yaml")
    if openapi_version != server_version:
        raise ComponentReleaseError("OpenAPI info.version does not match package.version")
    return server_version


def validate_protocol_documents(root: Path, server_version: str) -> dict[str, str]:
    protocol_root = root.resolve() / "packages" / "protocol"
    return validate_protocol_payloads(
        require_regular_file(protocol_root / "versions.json").read_bytes(),
        require_regular_file(protocol_root / "bridge.schema.json").read_bytes(),
        require_regular_file(protocol_root / "events.schema.json").read_bytes(),
        require_regular_file(protocol_root / "openapi.yaml").read_bytes(),
        server_version,
    )


def validate_protocol_payloads(
    versions_content: bytes,
    bridge_content: bytes,
    events_content: bytes,
    openapi_content: bytes,
    server_version: str,
) -> dict[str, str]:
    protocols = decode_json_object(versions_content, "protocol versions")
    if protocols != EXPECTED_PROTOCOLS:
        raise ComponentReleaseError("protocol versions do not match the supported TS Phone contract set")

    documents = {
        "bridge": decode_json_object(bridge_content, "bridge protocol schema"),
        "events": decode_json_object(events_content, "events protocol schema"),
    }
    for key, document in documents.items():
        if document.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
            raise ComponentReleaseError(f"{key} protocol schema must use JSON Schema Draft 2020-12")
        if document.get("$id") != EXPECTED_PROTOCOL_SCHEMA_IDS[key]:
            raise ComponentReleaseError(f"{key} protocol schema ID does not match its declared version")
        properties = document.get("properties")
        protocol_version = properties.get("protocolVersion") if isinstance(properties, dict) else None
        if not isinstance(protocol_version, dict) or protocol_version.get("const") != protocols[key]:
            raise ComponentReleaseError(f"{key} protocol schema does not bind its declared version")

    validate_events_protocol_schema(documents["events"])
    validate_bridge_protocol_schema(documents["bridge"])

    validate_openapi_payload(openapi_content, server_version, protocols["api"])
    return protocols


def validate_events_protocol_schema(document: dict[str, Any]) -> None:
    validate_object_schema(
        document,
        "events protocol schema",
        required=EVENT_ENVELOPE_FIELDS,
        additional_properties=False,
    )
    validate_lifecycle_definition(document, "events")
    validate_lifecycle_bindings(document, "events", bridge=False)


def validate_bridge_protocol_schema(document: dict[str, Any]) -> None:
    validate_object_schema(
        document,
        "bridge protocol schema",
        required=BRIDGE_ENVELOPE_FIELDS,
        additional_properties=True,
    )
    validate_lifecycle_definition(document, "bridge")
    validate_lifecycle_bindings(document, "bridge", bridge=True)

    abort_branch = find_conditional_branch(document, type_const="command.abort")
    if abort_branch is None or "agentRunId" not in schema_required(abort_branch.get("then")):
        raise ComponentReleaseError("bridge protocol schema does not bind abort to an agent run")

    definitions = document.get("$defs")
    snapshot = definitions.get("sessionSnapshot") if isinstance(definitions, dict) else None
    if not isinstance(snapshot, dict):
        raise ComponentReleaseError("bridge protocol schema is missing the session snapshot")
    validate_object_schema(
        snapshot,
        "bridge session snapshot",
        required=frozenset({"sessionId", "isStreaming", "messages"}),
        additional_properties=False,
    )
    snapshot_properties = snapshot.get("properties")
    if not isinstance(snapshot_properties, dict) or snapshot_properties.get("agentRunId") != {
        "type": "string",
        "pattern": BOUNDED_ID_PATTERN,
    }:
        raise ComponentReleaseError("bridge session snapshot does not define a bounded agentRunId")
    streaming_branch = find_conditional_branch(snapshot, property_name="isStreaming", property_const=True)
    if streaming_branch is None:
        raise ComponentReleaseError("bridge session snapshot does not bind streaming state to an agent run")
    if "agentRunId" not in schema_required(streaming_branch.get("then")):
        raise ComponentReleaseError("bridge session snapshot does not require agentRunId while streaming")
    otherwise = streaming_branch.get("else")
    if not isinstance(otherwise, dict) or otherwise.get("not") != {"required": ["agentRunId"]}:
        raise ComponentReleaseError("bridge session snapshot permits agentRunId while idle")


def validate_object_schema(
    schema: object,
    label: str,
    *,
    required: frozenset[str],
    additional_properties: bool,
) -> None:
    if not isinstance(schema, dict) or schema.get("type") != "object":
        raise ComponentReleaseError(f"{label} must define an object")
    if schema_required(schema) != required:
        raise ComponentReleaseError(f"{label} does not require its exact envelope fields")
    if schema.get("additionalProperties") is not additional_properties:
        raise ComponentReleaseError(f"{label} has an invalid unknown-field policy")
    properties = schema.get("properties")
    if not isinstance(properties, dict) or not required.issubset(properties):
        raise ComponentReleaseError(f"{label} is missing required property definitions")


def validate_lifecycle_definition(document: dict[str, Any], label: str) -> None:
    definitions = document.get("$defs")
    lifecycle = definitions.get("agentRunEvent") if isinstance(definitions, dict) else None
    if not isinstance(lifecycle, dict) or lifecycle.get("type") != "object":
        raise ComponentReleaseError(f"{label} protocol schema is missing the lifecycle payload definition")
    if schema_required(lifecycle) != LIFECYCLE_FIELDS:
        raise ComponentReleaseError(f"{label} protocol schema does not bind lifecycle event identity")
    properties = lifecycle.get("properties")
    if not isinstance(properties, dict) or set(properties) != LIFECYCLE_FIELDS:
        raise ComponentReleaseError(f"{label} protocol schema has invalid lifecycle event fields")
    if lifecycle.get("additionalProperties") is not False:
        raise ComponentReleaseError(f"{label} lifecycle payload must reject unknown fields")
    type_schema = properties.get("type")
    origin_schema = properties.get("origin")
    if not isinstance(type_schema, dict) or string_set(type_schema.get("enum")) != LIFECYCLE_EVENT_TYPES:
        raise ComponentReleaseError(f"{label} lifecycle payload has invalid event types")
    if not isinstance(origin_schema, dict) or string_set(origin_schema.get("enum")) != LIFECYCLE_ORIGINS:
        raise ComponentReleaseError(f"{label} lifecycle payload has invalid origins")
    bounded_id = {"type": "string", "pattern": BOUNDED_ID_PATTERN}
    if properties["turnId"] != bounded_id or properties["agentRunId"] != bounded_id:
        raise ComponentReleaseError(f"{label} lifecycle payload has invalid bounded identifiers")


def validate_lifecycle_bindings(
    document: dict[str, Any],
    label: str,
    *,
    bridge: bool,
) -> None:
    bindings: set[str] = set()
    for event_type in LIFECYCLE_EVENT_TYPES:
        branch = find_conditional_branch(
            document,
            type_const="event.publish" if bridge else event_type,
            property_name="eventType" if bridge else None,
            property_const=event_type if bridge else None,
        )
        if branch is None:
            raise ComponentReleaseError(f"{label} protocol schema does not bind {event_type}")
        condition_required = schema_required(branch.get("if"))
        expected_condition = {"type", "eventType"} if bridge else {"type"}
        if not expected_condition.issubset(condition_required):
            raise ComponentReleaseError(f"{label} protocol schema has an incomplete {event_type} condition")
        then = branch.get("then")
        if not isinstance(then, dict):
            raise ComponentReleaseError(f"{label} protocol schema has an invalid {event_type} branch")
        if bridge and "payload" not in schema_required(then):
            raise ComponentReleaseError(f"{label} protocol schema does not require {event_type} payload")
        then_properties = then.get("properties")
        payload = then_properties.get("payload") if isinstance(then_properties, dict) else None
        all_of = payload.get("allOf") if isinstance(payload, dict) else None
        if not isinstance(all_of, list):
            raise ComponentReleaseError(f"{label} protocol schema has an invalid {event_type} payload")
        references = [item.get("$ref") for item in all_of if isinstance(item, dict) and "$ref" in item]
        inner_types = [inner_type for item in all_of if (inner_type := schema_inner_type(item)) is not None]
        if references != ["#/$defs/agentRunEvent"] or inner_types != [event_type]:
            raise ComponentReleaseError(f"{label} protocol schema misbinds {event_type} payload")
        bindings.add(event_type)
    if bindings != LIFECYCLE_EVENT_TYPES:
        raise ComponentReleaseError(f"{label} protocol schema lifecycle bindings are incomplete")


def find_conditional_branch(
    document: dict[str, Any],
    *,
    type_const: object | None = None,
    property_name: str | None = None,
    property_const: object | None = None,
) -> dict[str, Any] | None:
    branches = document.get("allOf")
    if not isinstance(branches, list):
        return None
    matches: list[dict[str, Any]] = []
    for branch in branches:
        if not isinstance(branch, dict):
            continue
        condition = branch.get("if")
        properties = condition.get("properties") if isinstance(condition, dict) else None
        if not isinstance(properties, dict):
            continue
        if type_const is not None:
            type_schema = properties.get("type")
            if not isinstance(type_schema, dict) or type_schema.get("const") != type_const:
                continue
        if property_name is not None:
            property_schema = properties.get(property_name)
            if not isinstance(property_schema, dict) or property_schema.get("const") != property_const:
                continue
        matches.append(branch)
    if len(matches) > 1:
        raise ComponentReleaseError("protocol schema contains duplicate conditional bindings")
    return matches[0] if matches else None


def schema_required(schema: object) -> frozenset[str]:
    if not isinstance(schema, dict):
        return frozenset()
    required = schema.get("required")
    if (
        not isinstance(required, list)
        or any(not isinstance(value, str) for value in required)
        or len(required) != len(set(required))
    ):
        return frozenset()
    return frozenset(required)


def string_set(value: object) -> frozenset[str]:
    if (
        not isinstance(value, list)
        or any(not isinstance(item, str) for item in value)
        or len(value) != len(set(value))
    ):
        return frozenset()
    return frozenset(value)


def schema_inner_type(schema: object) -> object | None:
    if not isinstance(schema, dict):
        return None
    properties = schema.get("properties")
    type_schema = properties.get("type") if isinstance(properties, dict) else None
    return type_schema.get("const") if isinstance(type_schema, dict) else None


def validate_openapi_contract(path: Path, server_version: str, api_version: str) -> None:
    validate_openapi_payload(require_regular_file(path).read_bytes(), server_version, api_version)


def validate_openapi_payload(content: bytes, server_version: str, api_version: str) -> None:
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ComponentReleaseError("OpenAPI document is not UTF-8") from error
    lines = text.splitlines()
    if sum(line.strip() == "openapi: 3.1.0" for line in lines) != 1:
        raise ComponentReleaseError("OpenAPI document must declare OpenAPI 3.1.0 exactly once")
    if openapi_info_versions(lines) != [server_version]:
        raise ComponentReleaseError("OpenAPI info.version does not match package.version")
    if sum(re.fullmatch(r"  /api/v4/version:\s*", line) is not None for line in lines) != 1:
        raise ComponentReleaseError("OpenAPI document does not define the version endpoint")
    api_constants = [
        match.group(1)
        for line in lines
        if (match := re.fullmatch(r"\s*version:\s*\{\s*const:\s*([^}\s]+)\s*}\s*", line)) is not None
    ]
    if api_constants != [api_version]:
        raise ComponentReleaseError("OpenAPI health contract does not bind the declared API version")


def openapi_info_versions(lines: list[str]) -> list[str]:
    in_info = False
    versions: list[str] = []
    for line in lines:
        if line and not line[0].isspace():
            if in_info:
                break
            in_info = line.strip() == "info:"
            continue
        if in_info:
            match = re.fullmatch(r"  version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*", line)
            if match is not None:
                versions.append(match.group(1))
    return versions


def read_openapi_info_version(path: Path) -> str:
    lines = require_regular_file(path).read_text(encoding="utf-8").splitlines()
    in_info = False
    versions: list[str] = []
    for line in lines:
        if line and not line[0].isspace():
            if in_info:
                break
            in_info = line.strip() == "info:"
            continue
        if in_info:
            match = re.fullmatch(r"  version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*", line)
            if match is not None:
                versions.append(match.group(1))
    if len(versions) != 1:
        raise ComponentReleaseError("OpenAPI info must contain exactly one semantic version")
    return versions[0]


def default_mobile_apk(root: Path, mobile_name: str, mobile_build: int) -> Path:
    return root / "dist" / "android-current" / mobile_artifact_name(
        mobile_name,
        mobile_build,
        "apk",
        "arm64-v8a",
    )


def publish_android_release_set(
    artifact_root: Path,
    output_root: Path,
    mobile_version: str,
    mobile_build: int,
) -> Path:
    source = artifact_root.expanduser().resolve()
    destination_root = output_root.expanduser().resolve()
    if not SERVER_VERSION.fullmatch(mobile_version):
        raise ComponentReleaseError("Android release version must use semantic x.y.z form")
    if not isinstance(mobile_build, int) or isinstance(mobile_build, bool) or mobile_build <= 0:
        raise ComponentReleaseError("Android release build must be a positive integer")
    if source.is_symlink() or not source.is_dir():
        raise ComponentReleaseError(f"Android release staging directory is missing or unsafe: {source}")

    prefix = f"ts-phone-v{mobile_version}-build{mobile_build}"
    expected_names = {
        *(
            name
            for abi in ANDROID_RELEASE_ABIS
            for name in (
                f"{prefix}-{abi}-release.apk",
                f"{prefix}-{abi}-release.apk.attestation.json",
            )
        ),
        f"{prefix}-release.aab",
        f"{prefix}-release.aab.attestation.json",
    }
    actual_names: set[str] = set()
    for path in source.iterdir():
        if path.is_symlink() or not path.is_file():
            raise ComponentReleaseError(f"Android release staging contains an unsafe entry: {path.name}")
        actual_names.add(path.name)
    if actual_names != expected_names:
        missing = sorted(expected_names - actual_names)
        extra = sorted(actual_names - expected_names)
        details = []
        if missing:
            details.append(f"missing: {', '.join(missing)}")
        if extra:
            details.append(f"extra: {', '.join(extra)}")
        raise ComponentReleaseError(f"Android release staging inventory is incomplete ({'; '.join(details)})")

    payload_digest = hashlib.sha256()
    payload_digest.update(b"ts-phone-android-release-set/1\0")
    for name in sorted(expected_names):
        content = read_regular_file_snapshot(
            source / name,
            f"Android release artifact {name}",
            max_bytes=MAX_COMPONENT_BOUND_MEMBER_BYTES,
        )
        update_framed_digest(payload_digest, name.encode("utf-8"))
        update_framed_digest(payload_digest, content)
    release_name = f"{prefix}-sha256-{payload_digest.hexdigest()[:16]}"

    destination_root.mkdir(mode=0o755, parents=True, exist_ok=True)
    if destination_root.is_symlink() or not destination_root.is_dir():
        raise ComponentReleaseError(f"Android release output directory is unsafe: {destination_root}")
    releases_root = destination_root / "android-releases"
    releases_root.mkdir(mode=0o755, exist_ok=True)
    if releases_root.is_symlink() or not releases_root.is_dir():
        raise ComponentReleaseError(f"Android release store is unsafe: {releases_root}")
    staged = Path(tempfile.mkdtemp(prefix=".android-release.", dir=releases_root))
    release_root = releases_root / release_name
    try:
        for name in sorted(expected_names):
            copy_release_input(source / name, staged / name, 0o644)
        staged.chmod(0o755)
        if release_root.exists() or release_root.is_symlink():
            if release_root.is_symlink() or not release_root.is_dir():
                raise ComponentReleaseError(f"existing Android release target is unsafe: {release_root}")
            compare_release_directories(staged, release_root, expected_names)
            shutil.rmtree(staged)
        else:
            os.replace(staged, release_root)
        switch_android_current(destination_root, release_root)
    finally:
        if staged.exists() and not staged.is_symlink():
            shutil.rmtree(staged)
    return destination_root / "android-current"


def compare_release_directories(first: Path, second: Path, expected_names: set[str]) -> None:
    second_names = {
        path.name
        for path in second.iterdir()
        if path.is_file() and not path.is_symlink()
    }
    if second_names != expected_names or any(path.is_symlink() or not path.is_file() for path in second.iterdir()):
        raise ComponentReleaseError(f"existing Android release inventory is invalid: {second}")
    for name in sorted(expected_names):
        if sha256_file(first / name) != sha256_file(second / name):
            raise ComponentReleaseError(f"existing Android release content differs: {name}")


def switch_android_current(output_root: Path, release_root: Path) -> None:
    current = output_root / "android-current"
    if current.exists() and not current.is_symlink():
        raise ComponentReleaseError(f"Android current pointer is not a symbolic link: {current}")
    descriptor, temporary_name = tempfile.mkstemp(prefix=".android-current.", dir=output_root)
    os.close(descriptor)
    os.unlink(temporary_name)
    temporary = Path(temporary_name)
    try:
        temporary.symlink_to(release_root.relative_to(output_root))
        os.replace(temporary, current)
    finally:
        if temporary.is_symlink() or temporary.exists():
            temporary.unlink()


def run_checked(command: list[str], root: Path) -> None:
    completed = subprocess.run(
        command, cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"command failed: {' '.join(command)}"
        raise ComponentReleaseError(detail)


def read_object(path: Path, label: str) -> dict[str, Any]:
    value = json.loads(require_regular_file(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ComponentReleaseError(f"{label} must contain an object")
    return value


def file_descriptor(path: Path, relative: str) -> dict[str, Any]:
    source = require_regular_file(path)
    return {
        "path": safe_relative(relative).as_posix(),
        "sha256": sha256_file(source),
        "size_bytes": source.stat().st_size,
    }


def copy_release_input(source: Path, destination: Path, mode: int) -> Path:
    source = require_regular_file(source)
    if destination.exists() or destination.is_symlink():
        raise ComponentReleaseError(f"staged release input already exists: {destination}")
    shutil.copyfile(source, destination)
    os.chmod(destination, mode)
    return require_regular_file(destination)


def safe_relative(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or ".." in path.parts or "." in path.parts:
        raise ComponentReleaseError(f"unsafe component archive path: {value}")
    return path


def require_regular_file(path: Path) -> Path:
    if not path.is_file() or path.is_symlink():
        raise ComponentReleaseError(f"required file is missing or unsafe: {path}")
    return path


def read_regular_file_snapshot(path: Path, label: str, *, max_bytes: int) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ComponentReleaseError(f"could not open {label}: {error}") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise ComponentReleaseError(f"{label} is not a regular file")
        if metadata.st_size > max_bytes:
            raise ComponentReleaseError(f"{label} exceeds the size limit")
        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            content = handle.read(max_bytes + 1)
    finally:
        os.close(descriptor)
    if len(content) > max_bytes:
        raise ComponentReleaseError(f"{label} exceeds the size limit")
    return content


def exact_object(value: object, label: str, keys: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ComponentReleaseError(f"{label} must contain exactly: {', '.join(sorted(keys))}")
    return value


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ComponentReleaseError(f"{label} must be a non-empty string")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_object_sha256(value: dict[str, Any]) -> str:
    encoded = json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
