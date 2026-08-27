"""Build a deterministic TS Phone component archive and release manifest."""

from __future__ import annotations

import gzip
import hashlib
import io
import json
import os
import re
import subprocess
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


SCHEMA_VERSION = "ts-phone-component-release/1"
PROTOCOL_SCHEMA_VERSION = "ts-phone-protocol-set/1"
MANIFEST_NAME = "ts-phone-component-release.json"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MOBILE_VERSION = re.compile(r"^([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$")
SERVER_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
EXPECTED_PROTOCOLS = {
    "schema_version": PROTOCOL_SCHEMA_VERSION,
    "api": "ts-phone-api/3",
    "events": "ts-phone-events/3",
    "bridge": "ts-phone-bridge/2",
}


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
    git_commit, dirty = git_state(root)
    if dirty and not allow_dirty:
        raise ComponentReleaseError(
            "component releases require a clean Git checkout; use --allow-dirty only for local validation"
        )

    server_version = read_server_version(root)

    mobile_name, mobile_build = read_mobile_version(root / "apps" / "mobile" / "pubspec.yaml")
    protocols = read_object(root / "packages" / "protocol" / "versions.json", "protocol versions")
    if protocols != EXPECTED_PROTOCOLS:
        raise ComponentReleaseError("protocol versions do not match the supported TS Phone contract set")

    run_checked(["npm", "run", "typecheck"], root)
    run_checked(["npm", "test"], root)
    run_checked(["npm", "run", "build"], root)

    apk = (mobile_apk or default_mobile_apk(root, mobile_name, mobile_build)).resolve()
    require_regular_file(apk)
    expected_apk_name = f"ts-phone-v{mobile_name}-build{mobile_build}-arm64-v8a-release.apk"
    if apk.name != expected_apk_name:
        raise ComponentReleaseError(f"mobile APK must be named {expected_apk_name}")
    certificate_sha256 = verify_apk(apksigner.resolve(), apk)

    records = release_records(root, apk)
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=".ts-phone-component.", suffix=".tgz", dir=output_dir, delete=False) as handle:
        temporary_archive = Path(handle.name)
    try:
        write_component_archive(records, temporary_archive)
        archive_sha256 = sha256_file(temporary_archive)
        release_id = (
            f"{server_version}-mobile-{mobile_name}-build{mobile_build}-"
            f"sha256-{archive_sha256[:16]}"
        )
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

    server_entry = root / "services" / "server" / "dist" / "index.js"
    server_entry_relative = "services/server/dist/index.js"
    apk_relative = f"artifacts/{apk.name}"
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
        "server_entry": file_descriptor(server_entry, server_entry_relative),
        "mobile_artifact": {
            **file_descriptor(apk, apk_relative),
            "abi": "arm64-v8a",
            "certificate_sha256": certificate_sha256,
        },
        "archive": {
            "filename": archive_name,
            "sha256": archive_sha256,
            "size_bytes": archive_size,
        },
        "source": {"git_commit": git_commit, "dirty": dirty},
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    validate_component_manifest(manifest)
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


def release_records(root: Path, apk: Path) -> list[tuple[PurePosixPath, Path, int]]:
    fixed = {
        "VERSION": root / "VERSION",
        "README.md": root / "README.md",
        "package.json": root / "package.json",
        "services/server/package.json": root / "services" / "server" / "package.json",
        "bin/ts-phone-ctl": root / "bin" / "ts-phone-ctl",
        "bin/ts-phone-server": root / "bin" / "ts-phone-server",
        "deploy/server.env.example": root / "deploy" / "server.env.example",
        "packages/protocol/versions.json": root / "packages" / "protocol" / "versions.json",
        "packages/protocol/bridge.schema.json": root / "packages" / "protocol" / "bridge.schema.json",
        "packages/protocol/events.schema.json": root / "packages" / "protocol" / "events.schema.json",
        "packages/protocol/openapi.yaml": root / "packages" / "protocol" / "openapi.yaml",
        "docs/architecture.md": root / "docs" / "architecture.md",
        "docs/deployment.md": root / "docs" / "deployment.md",
        "docs/recovery.md": root / "docs" / "recovery.md",
        "docs/security.md": root / "docs" / "security.md",
    }
    records: list[tuple[PurePosixPath, Path, int]] = []
    for name, source in fixed.items():
        path = require_regular_file(source)
        mode = 0o755 if name in {"bin/ts-phone-ctl", "bin/ts-phone-server"} else 0o644
        records.append((safe_relative(name), path, mode))

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
    names = [name.as_posix() for name, _, _ in records]
    if len(names) != len(set(names)):
        raise ComponentReleaseError("component archive contains duplicate target paths")
    return sorted(records, key=lambda item: item[0].as_posix())


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
                    info = normalized_tar_info((PurePosixPath("component") / relative).as_posix(), mode=mode, size=len(content))
                    archive.addfile(info, io.BytesIO(content))


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
        "archive",
        "source",
        "created_at_utc",
    }
    if not isinstance(value, dict) or set(value) != expected or value.get("schema_version") != SCHEMA_VERSION:
        raise ComponentReleaseError("invalid TS Phone component release manifest schema")
    component = exact_object(value.get("component"), "component", {"name", "server_version", "mobile_version", "mobile_build"})
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
    if mobile.get("abi") != "arm64-v8a" or not SHA256.fullmatch(require_string(mobile.get("certificate_sha256"), "certificate_sha256")):
        raise ComponentReleaseError("mobile artifact ABI or signing certificate is invalid")
    archive = validate_file_descriptor(value.get("archive"), "archive", filename_key="filename")
    release_id = require_string(value.get("release_id"), "release_id")
    expected_release = (
        f"{server_version}-mobile-{mobile_version}-build{mobile_build}-"
        f"sha256-{archive['sha256'][:16]}"
    )
    if release_id != expected_release:
        raise ComponentReleaseError("release_id does not match component versions and archive digest")
    if archive["filename"] != f"ts-phone-component-{release_id}.tgz":
        raise ComponentReleaseError("archive.filename does not match release_id")
    source = exact_object(value.get("source"), "source", {"git_commit", "dirty"})
    if source.get("git_commit") is not None:
        require_string(source.get("git_commit"), "source.git_commit")
    if not isinstance(source.get("dirty"), bool):
        raise ComponentReleaseError("source.dirty must be boolean")
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
    match = re.search(r"Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F]{64})", completed.stdout)
    if match is None:
        raise ComponentReleaseError("APK signer certificate digest is unavailable")
    return match.group(1).lower()


def read_mobile_version(path: Path) -> tuple[str, int]:
    text = require_regular_file(path).read_text(encoding="utf-8")
    match = re.search(r"(?m)^version:\s*([^\s#]+)\s*$", text)
    if match is None:
        raise ComponentReleaseError("mobile pubspec has no version")
    parsed = MOBILE_VERSION.fullmatch(match.group(1))
    if parsed is None:
        raise ComponentReleaseError(f"invalid mobile version: {match.group(1)}")
    return parsed.group(1), int(parsed.group(2))


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

    version_file = require_regular_file(root / "VERSION")
    if version_file.read_text(encoding="utf-8").strip() != server_version:
        raise ComponentReleaseError("VERSION does not match package.version")
    return server_version


def default_mobile_apk(root: Path, mobile_name: str, mobile_build: int) -> Path:
    return root / "dist" / f"ts-phone-v{mobile_name}-build{mobile_build}-arm64-v8a-release.apk"


def git_state(root: Path) -> tuple[str | None, bool]:
    revision = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False
    )
    status = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=normal"],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    commit = revision.stdout.strip() if revision.returncode == 0 else None
    return commit, status.returncode != 0 or bool(status.stdout.strip())


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
    return {"path": safe_relative(relative).as_posix(), "sha256": sha256_file(source), "size_bytes": source.stat().st_size}


def safe_relative(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or ".." in path.parts or "." in path.parts:
        raise ComponentReleaseError(f"unsafe component archive path: {value}")
    return path


def require_regular_file(path: Path) -> Path:
    if not path.is_file() or path.is_symlink():
        raise ComponentReleaseError(f"required file is missing or unsafe: {path}")
    return path


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
