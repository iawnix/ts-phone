"""Mobile-only release and source-attestation primitives.

The runtime lives in TSPi. This module deliberately contains no server,
bridge, protocol archive, or deployment code.
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


class ComponentReleaseError(RuntimeError):
    """Raised when a mobile release cannot be verified safely."""


SOURCE_SNAPSHOT_SCHEMA_VERSION = "ts-phone-source-snapshot/2"
MOBILE_BUILD_ATTESTATION_SCHEMA_VERSION = "ts-phone-mobile-build-attestation/2"
ANDROID_PACKAGE_NAME = "xyz.iawnix.ts_phone"
MOBILE_VERSION = re.compile(r"^([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$")
SEMANTIC_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
GIT_OBJECT_ID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MOBILE_APK_ABIS = {"arm64-v8a", "armeabi-v7a", "x86_64"}
ANDROID_RELEASE_ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
ANDROID_ABI_VERSION_CODE_OFFSETS = {"armeabi-v7a": 1000, "arm64-v8a": 2000, "x86_64": 4000}
DEFAULT_ANDROID_CERTIFICATE_SHA256 = "41998c3f13ee6a2b5e370b3ded25de4dc2af4e0de7172dbcc33e63bfa9fdc19f"
EXPECTED_ANDROID_CERTIFICATE_SHA256 = os.environ.get(
    "TS_PHONE_RELEASE_CERTIFICATE_SHA256", DEFAULT_ANDROID_CERTIFICATE_SHA256
).replace(":", "").lower()
if not SHA256.fullmatch(EXPECTED_ANDROID_CERTIFICATE_SHA256):
    raise ValueError("TS_PHONE_RELEASE_CERTIFICATE_SHA256 must be a 64-character SHA-256 fingerprint")

REQUIRED_SOURCE_PATHS = {
    b"package.json",
    b"apps/mobile/pubspec.yaml",
    b"apps/mobile/lib/app_identity.dart",
    b"apps/mobile/tool/mobile-build-attestation.py",
    b"apps/mobile/tool/release_builder.py",
}
EMBEDDED_SOURCE_SNAPSHOT_PATHS = {
    "apk": "assets/ts-phone-source-snapshot.json",
    "aab": "base/assets/ts-phone-source-snapshot.json",
}
MAX_ARTIFACT_BYTES = 512 * 1024 * 1024
MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES = 16 * 1024


def source_snapshot(root: Path) -> dict[str, Any]:
    snapshot, _ = inspect_source(root)
    return snapshot


def capture_source_tree(root: Path, destination: Path, *, allow_dirty: bool = False) -> dict[str, Any]:
    root = root.resolve()
    destination = destination.resolve()
    if destination.is_relative_to(root):
        raise ComponentReleaseError("captured source destination must be outside the source repository")
    snapshot, relative_names = inspect_source(root)
    if snapshot["dirty"] and not allow_dirty:
        raise ComponentReleaseError("release builds require a clean Git checkout; use --allow-dirty for local validation")
    if destination.exists() or destination.is_symlink():
        raise ComponentReleaseError(f"captured source destination already exists: {destination}")
    destination.mkdir(mode=0o700, parents=True)
    if snapshot["dirty"]:
        copy_source_entries(root, destination, relative_names)
    else:
        export_git_source(root, destination, snapshot["git_commit"], relative_names)
    captured = snapshot_from_tree(destination, relative_names, git_commit=snapshot["git_commit"], dirty=snapshot["dirty"])
    if captured != snapshot:
        raise ComponentReleaseError("source changed while it was being captured")
    return captured


def inspect_source(root: Path) -> tuple[dict[str, Any], list[bytes]]:
    root = root.resolve()
    top_level = run_git(root, ["rev-parse", "--show-toplevel"], "locate source repository")
    if Path(os.fsdecode(top_level).strip()).resolve() != root:
        raise ComponentReleaseError("source root must be the top level of the TS Phone Git repository")
    git_commit = run_git(root, ["rev-parse", "--verify", "HEAD"], "read source commit").decode("ascii").strip()
    if not GIT_OBJECT_ID.fullmatch(git_commit):
        raise ComponentReleaseError("source commit is not a full Git object ID")
    flags = run_git(root, ["ls-files", "-v", "-z"], "inspect source index flags")
    if any(entry and not entry.startswith(b"H ") for entry in flags.split(b"\0")):
        raise ComponentReleaseError("source index contains assume-unchanged, skip-worktree, or unresolved entries")
    listed = run_git(root, ["ls-files", "--cached", "--others", "--exclude-standard", "-z"], "list source files")
    relative_names = sorted({name for name in listed.split(b"\0") if name})
    missing = sorted(REQUIRED_SOURCE_PATHS.difference(relative_names))
    if missing:
        raise ComponentReleaseError("source repository is missing required paths: " + ", ".join(os.fsdecode(name) for name in missing))
    status = run_git(root, ["status", "--porcelain=v1", "-z", "--untracked-files=normal"], "read source status")
    return snapshot_from_tree(root, relative_names, git_commit=git_commit, dirty=bool(status)), relative_names


def snapshot_from_tree(root: Path, relative_names: Iterable[bytes], *, git_commit: str, dirty: bool) -> dict[str, Any]:
    digest = hashlib.sha256()
    digest.update(SOURCE_SNAPSHOT_SCHEMA_VERSION.encode("ascii") + b"\0")
    for raw_name in relative_names:
        relative = safe_relative(os.fsdecode(raw_name))
        path = root.joinpath(*relative.parts)
        if path.is_symlink():
            raise ComponentReleaseError(f"release source must not contain symlinks: {relative}")
        if path.is_file():
            mode = 0o111 if path.stat().st_mode & 0o111 else 0
            content = path.read_bytes()
            kind = f"file:{mode:03o}".encode("ascii")
        elif not path.exists():
            kind, content = b"missing", b""
        else:
            raise ComponentReleaseError(f"source entry is not a regular file: {relative}")
        update_framed_digest(digest, raw_name)
        update_framed_digest(digest, kind)
        update_framed_digest(digest, content)
    return {"schema_version": SOURCE_SNAPSHOT_SCHEMA_VERSION, "git_commit": git_commit, "dirty": dirty, "sha256": digest.hexdigest()}


def copy_source_entries(root: Path, destination: Path, relative_names: Iterable[bytes]) -> None:
    for raw_name in relative_names:
        relative = safe_relative(os.fsdecode(raw_name))
        source = root.joinpath(*relative.parts)
        if not source.exists():
            continue
        target = destination.joinpath(*relative.parts)
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.copyfile(require_regular_file(source), target)
        os.chmod(target, 0o755 if source.stat().st_mode & 0o111 else 0o644)


def export_git_source(root: Path, destination: Path, git_commit: str, expected_names: Iterable[bytes]) -> None:
    encoded = run_git(root, ["archive", "--format=tar", git_commit], "capture committed source")
    extracted: set[bytes] = set()
    try:
        with tarfile.open(fileobj=io.BytesIO(encoded), mode="r:") as archive:
            for member in archive.getmembers():
                relative = safe_relative(member.name.rstrip("/"))
                target = destination.joinpath(*relative.parts)
                if member.isdir():
                    target.mkdir(mode=0o700, parents=True, exist_ok=True)
                    continue
                if not member.isfile():
                    raise ComponentReleaseError(f"committed source contains a non-file: {relative}")
                raw_name = os.fsencode(relative.as_posix())
                if raw_name in extracted:
                    raise ComponentReleaseError(f"committed source contains a duplicate path: {relative}")
                extracted.add(raw_name)
                stream = archive.extractfile(member)
                if stream is None:
                    raise ComponentReleaseError(f"committed source cannot be read: {relative}")
                with stream:
                    content = stream.read(member.size + 1)
                if len(content) != member.size:
                    raise ComponentReleaseError(f"committed source has an invalid size: {relative}")
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                target.write_bytes(content)
                os.chmod(target, 0o755 if member.mode & 0o111 else 0o644)
    except (OSError, tarfile.TarError) as error:
        raise ComponentReleaseError(f"could not capture committed source: {error}") from error
    if extracted != set(expected_names):
        raise ComponentReleaseError("committed source archive does not match the source inventory")


def verify_clean_captured_source_tree(repository_root: Path, captured_root: Path, expected_source: object) -> None:
    expected = validate_source_snapshot(expected_source)
    if expected["dirty"]:
        raise ComponentReleaseError("only a clean captured source can be verified from a Git commit")
    listed = run_git(repository_root.resolve(), ["ls-tree", "-r", "--name-only", "-z", expected["git_commit"]], "read captured source inventory")
    names = sorted({name for name in listed.split(b"\0") if name})
    actual = snapshot_from_tree(captured_root.resolve(), names, git_commit=expected["git_commit"], dirty=False)
    if actual != expected:
        raise ComponentReleaseError("captured source changed during the release build")


def validate_source_snapshot(value: object) -> dict[str, Any]:
    snapshot = exact_object(value, "source snapshot", {"schema_version", "git_commit", "dirty", "sha256"})
    if snapshot["schema_version"] != SOURCE_SNAPSHOT_SCHEMA_VERSION:
        raise ComponentReleaseError("source snapshot schema version is unsupported")
    if not GIT_OBJECT_ID.fullmatch(require_string(snapshot["git_commit"], "source snapshot git_commit")):
        raise ComponentReleaseError("source snapshot git_commit must be a full Git object ID")
    if not isinstance(snapshot["dirty"], bool):
        raise ComponentReleaseError("source snapshot dirty must be boolean")
    if not SHA256.fullmatch(require_string(snapshot["sha256"], "source snapshot sha256")):
        raise ComponentReleaseError("source snapshot sha256 must be lowercase SHA-256")
    return snapshot


def write_mobile_build_attestation_from_captured_source(source_root: Path, artifact: Path, *, artifact_format: str, abi: str, expected_source: object) -> Path:
    source = validate_source_snapshot(expected_source)
    artifact_content = read_regular_file_snapshot(artifact.resolve(), "mobile build artifact", max_bytes=MAX_ARTIFACT_BYTES)
    if read_embedded_source_snapshot_bytes(artifact_content, artifact_format) != source:
        raise ComponentReleaseError("mobile artifact does not embed the captured source snapshot")
    version, build = read_mobile_version(source_root.resolve() / "apps/mobile/pubspec.yaml")
    expected_name = mobile_artifact_name(version, build, artifact_format, abi)
    if artifact.name != expected_name:
        raise ComponentReleaseError(f"mobile artifact must be named {expected_name}")
    attestation = {
        "schema_version": MOBILE_BUILD_ATTESTATION_SCHEMA_VERSION,
        "source": source,
        "mobile": {"version": version, "build": build},
        "target": {"format": artifact_format, "abi": abi},
        "artifact": {"filename": artifact.name, "sha256": sha256_bytes(artifact_content), "size_bytes": len(artifact_content)},
    }
    validate_mobile_build_attestation_payload(attestation, artifact_name=artifact.name, artifact_content=artifact_content, expected_source=source, expected_mobile_version=version, expected_mobile_build=build, expected_format=artifact_format, expected_abi=abi)
    destination = mobile_build_attestation_path(artifact)
    atomic_write_json(destination, attestation)
    return destination


def validate_mobile_build_attestation(value_or_path: object, artifact: Path, *, expected_source: object, expected_mobile_version: str, expected_mobile_build: int, expected_format: str, expected_abi: str) -> dict[str, Any]:
    artifact_content = read_regular_file_snapshot(artifact.resolve(), "mobile build artifact", max_bytes=MAX_ARTIFACT_BYTES)
    value = read_object(value_or_path, "mobile build attestation") if isinstance(value_or_path, Path) else value_or_path
    return validate_mobile_build_attestation_payload(value, artifact_name=artifact.name, artifact_content=artifact_content, expected_source=expected_source, expected_mobile_version=expected_mobile_version, expected_mobile_build=expected_mobile_build, expected_format=expected_format, expected_abi=expected_abi)


def validate_mobile_build_attestation_payload(value: object, *, artifact_name: str, artifact_content: bytes, expected_source: object, expected_mobile_version: str, expected_mobile_build: int, expected_format: str, expected_abi: str) -> dict[str, Any]:
    attestation = exact_object(value, "mobile build attestation", {"schema_version", "source", "mobile", "target", "artifact"})
    if attestation["schema_version"] != MOBILE_BUILD_ATTESTATION_SCHEMA_VERSION:
        raise ComponentReleaseError("mobile build attestation schema version is unsupported")
    source = validate_source_snapshot(attestation["source"])
    if source != validate_source_snapshot(expected_source):
        raise ComponentReleaseError("mobile build attestation does not match the current source snapshot")
    mobile = exact_object(attestation["mobile"], "mobile build", {"version", "build"})
    version = require_string(mobile["version"], "mobile build version")
    build = mobile["build"]
    if not SEMANTIC_VERSION.fullmatch(version) or not isinstance(build, int) or isinstance(build, bool) or build <= 0:
        raise ComponentReleaseError("mobile build version or number is invalid")
    if version != expected_mobile_version or build != expected_mobile_build:
        raise ComponentReleaseError("mobile build identity does not match the current version")
    target = exact_object(attestation["target"], "mobile build target", {"format", "abi"})
    if target != {"format": expected_format, "abi": expected_abi}:
        raise ComponentReleaseError("mobile build target does not match the requested artifact")
    if artifact_name != mobile_artifact_name(expected_mobile_version, expected_mobile_build, expected_format, expected_abi):
        raise ComponentReleaseError("mobile artifact filename is invalid")
    if read_embedded_source_snapshot_bytes(artifact_content, expected_format) != source:
        raise ComponentReleaseError("embedded source snapshot does not match its attestation")
    descriptor = exact_object(attestation["artifact"], "mobile build artifact", {"filename", "sha256", "size_bytes"})
    if descriptor["filename"] != artifact_name or descriptor["size_bytes"] != len(artifact_content) or descriptor["sha256"] != sha256_bytes(artifact_content):
        raise ComponentReleaseError("mobile build artifact digest or size does not match")
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


def read_embedded_source_snapshot_bytes(artifact_content: bytes, artifact_format: str) -> dict[str, Any]:
    member_name = EMBEDDED_SOURCE_SNAPSHOT_PATHS.get(artifact_format)
    if member_name is None:
        raise ComponentReleaseError(f"unsupported mobile artifact format: {artifact_format}")
    try:
        with zipfile.ZipFile(io.BytesIO(artifact_content)) as archive:
            matches = [entry for entry in archive.infolist() if entry.filename == member_name]
            if len(matches) != 1 or matches[0].is_dir() or matches[0].file_size > MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES:
                raise ComponentReleaseError("mobile artifact must contain exactly one bounded source snapshot")
            with archive.open(matches[0]) as handle:
                encoded = handle.read(MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES + 1)
    except (OSError, RuntimeError, zipfile.BadZipFile, zipfile.LargeZipFile) as error:
        raise ComponentReleaseError(f"could not read mobile artifact source snapshot: {error}") from error
    if len(encoded) > MAX_EMBEDDED_SOURCE_SNAPSHOT_BYTES:
        raise ComponentReleaseError("mobile artifact source snapshot exceeds the size limit")
    try:
        return validate_source_snapshot(json.loads(encoded.decode("utf-8")))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ComponentReleaseError("mobile artifact source snapshot is not valid UTF-8 JSON") from error


def verify_apk_metadata(aapt: Path, apk: Path, mobile_version: str, mobile_build: int, abi: str) -> None:
    require_regular_file(aapt)
    completed = subprocess.run([str(aapt), "dump", "badging", str(require_regular_file(apk))], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.returncode != 0:
        raise ComponentReleaseError(completed.stderr.strip() or "APK metadata verification failed")
    validate_apk_badging(completed.stdout, mobile_version, mobile_build, abi)


def validate_apk_badging(value: str, mobile_version: str, mobile_build: int, abi: str) -> None:
    package = re.search(r"(?m)^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", value)
    if package is None or abi not in ANDROID_ABI_VERSION_CODE_OFFSETS:
        raise ComponentReleaseError("APK package metadata is unavailable or ABI is unsupported")
    if package.group(1) != ANDROID_PACKAGE_NAME or package.group(2) != str(ANDROID_ABI_VERSION_CODE_OFFSETS[abi] + mobile_build) or package.group(3) != mobile_version:
        raise ComponentReleaseError("APK package name, version name, or version code is invalid")
    native = re.search(r"(?m)^native-code:\s*(.+)$", value)
    native_abis = re.findall(r"'([^']+)'", native.group(1)) if native else []
    if native_abis != [abi]:
        raise ComponentReleaseError("APK native ABI does not match the release target")
    if re.search(r"(?m)^application-debuggable(?:\s|$)", value):
        raise ComponentReleaseError("APK must not be debuggable")


def read_mobile_version(path: Path) -> tuple[str, int]:
    text = require_regular_file(path).read_text(encoding="utf-8")
    match = re.search(r"(?m)^version:\s*([^\s#]+)\s*$", text)
    if match is None or MOBILE_VERSION.fullmatch(match.group(1)) is None:
        raise ComponentReleaseError("invalid mobile pubspec version")
    version, build = MOBILE_VERSION.fullmatch(match.group(1)).groups()  # type: ignore[union-attr]
    identity = require_regular_file(path.parent / "lib/app_identity.dart").read_text(encoding="utf-8")
    if re.findall(r"(?m)^const String tsPhoneAppVersion = '([^']+)';$", identity) != [version] or re.findall(r"(?m)^const String tsPhoneAppBuild = '([^']+)';$", identity) != [build]:
        raise ComponentReleaseError("mobile app identity version or build does not match pubspec")
    return version, int(build)


def publish_android_release_set(artifact_root: Path, output_root: Path, mobile_version: str, mobile_build: int) -> Path:
    source = artifact_root.expanduser().resolve()
    destination = output_root.expanduser().resolve()
    if not SEMANTIC_VERSION.fullmatch(mobile_version) or not isinstance(mobile_build, int) or mobile_build <= 0 or source.is_symlink() or not source.is_dir():
        raise ComponentReleaseError("Android release metadata or staging directory is invalid")
    prefix = f"ts-phone-v{mobile_version}-build{mobile_build}"
    expected = {f"{prefix}-{abi}-release.apk" for abi in ANDROID_RELEASE_ABIS} | {f"{prefix}-{abi}-release.apk.attestation.json" for abi in ANDROID_RELEASE_ABIS} | {f"{prefix}-release.aab", f"{prefix}-release.aab.attestation.json"}
    actual = {path.name for path in source.iterdir() if path.is_file() and not path.is_symlink()}
    if actual != expected:
        raise ComponentReleaseError(f"Android release staging inventory mismatch: missing={sorted(expected - actual)}, extra={sorted(actual - expected)}")
    digest = hashlib.sha256()
    digest.update(b"ts-phone-android-release-set/2\0")
    for name in sorted(expected):
        update_framed_digest(digest, name.encode())
        update_framed_digest(digest, read_regular_file_snapshot(source / name, name, max_bytes=MAX_ARTIFACT_BYTES))
    release_name = f"{prefix}-sha256-{digest.hexdigest()[:16]}"
    destination.mkdir(mode=0o755, parents=True, exist_ok=True)
    releases = destination / "android-releases"
    releases.mkdir(mode=0o755, exist_ok=True)
    staged = Path(tempfile.mkdtemp(prefix=".android-release.", dir=releases))
    target = releases / release_name
    try:
        for name in sorted(expected):
            copy_release_input(source / name, staged / name, 0o644)
        staged.chmod(0o755)
        if target.exists() or target.is_symlink():
            if target.is_symlink() or not target.is_dir():
                raise ComponentReleaseError(f"existing Android release target is unsafe: {target}")
            compare_release_directories(staged, target, expected)
            shutil.rmtree(staged)
        else:
            os.replace(staged, target)
        switch_android_current(destination, target)
    finally:
        if staged.exists() and not staged.is_symlink():
            shutil.rmtree(staged)
    return destination / "android-current"


def compare_release_directories(first: Path, second: Path, expected: set[str]) -> None:
    if {path.name for path in second.iterdir()} != expected:
        raise ComponentReleaseError(f"existing Android release inventory is invalid: {second}")
    for name in expected:
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
        if temporary.exists() or temporary.is_symlink():
            temporary.unlink()


def run_git(root: Path, arguments: list[str], action: str) -> bytes:
    completed = subprocess.run(["git", *arguments], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise ComponentReleaseError(detail or f"could not {action}")
    return completed.stdout


def update_framed_digest(digest: Any, value: bytes) -> None:
    digest.update(len(value).to_bytes(8, byteorder="big", signed=False))
    digest.update(value)


def read_object(path: Path, label: str) -> dict[str, Any]:
    value = json.loads(require_regular_file(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ComponentReleaseError(f"{label} must contain an object")
    return value


def exact_object(value: object, label: str, keys: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ComponentReleaseError(f"{label} must contain exactly: {', '.join(sorted(keys))}")
    return value


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ComponentReleaseError(f"{label} must be a non-empty string")
    return value


def safe_relative(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or any(part in ("", ".") for part in path.parts):
        raise ComponentReleaseError(f"unsafe relative path: {value}")
    return path


def require_regular_file(path: Path) -> Path:
    if path.is_symlink() or not path.is_file():
        raise ComponentReleaseError(f"required regular file is missing or unsafe: {path}")
    return path


def read_regular_file_snapshot(path: Path, label: str, *, max_bytes: int) -> bytes:
    source = require_regular_file(path)
    if source.stat().st_size > max_bytes:
        raise ComponentReleaseError(f"{label} exceeds the size limit")
    return source.read_bytes()


def copy_release_input(source: Path, destination: Path, mode: int) -> Path:
    source = require_regular_file(source)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    os.chmod(destination, mode)
    return destination


def sha256_file(path: Path) -> str:
    return sha256_bytes(read_regular_file_snapshot(path, "file", max_bytes=MAX_ARTIFACT_BYTES))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
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
