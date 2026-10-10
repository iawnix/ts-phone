#!/usr/bin/env python3
"""Publish a verified Android set through a draft; never alter a public release."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
import version

ROOT = Path(__file__).resolve().parents[1]


def gh(*args: str) -> str:
    return subprocess.check_output(["gh", *args], cwd=ROOT, text=True)


def release_for_tag(repository: str, tag: str):
    pages = json.loads(gh("api", "--paginate", "--slurp", f"repos/{repository}/releases?per_page=100"))
    return next((release for page in pages for release in page if release["tag_name"] == tag), None)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(stream.read()).hexdigest()


def inventory(directory: Path, value: str) -> list[Path]:
    semver, build = value.split("+")
    prefix = f"corhub-v{semver}-build{build}"
    binaries = [f"{prefix}-{abi}-release.apk" for abi in ("arm64-v8a", "armeabi-v7a", "x86_64")] + [f"{prefix}-release.aab"]
    expected = set(binaries) | {name + ".attestation.json" for name in binaries}
    if {path.name for path in directory.iterdir()} != expected | {"SHA256SUMS"}:
        raise ValueError("release must contain exactly 3 APKs, 1 AAB, their attestations, and SHA256SUMS")
    paths = [directory / name for name in sorted(expected)]
    if any(path.is_symlink() or not path.is_file() for path in [*paths, directory / "SHA256SUMS"]):
        raise ValueError("release assets must be regular files")
    checksums = "".join(f"{sha256(path)}  {path.name}\n" for path in paths)
    if (directory / "SHA256SUMS").read_text() != checksums:
        raise ValueError("SHA256SUMS does not match the release assets")
    for name in binaries:
        descriptor = json.loads((directory / (name + ".attestation.json")).read_text())
        if descriptor["source"]["dirty"] or descriptor["source"]["git_commit"] != version.git(ROOT, "rev-parse", "HEAD"):
            raise ValueError("artifact must attest the clean tagged source")
        if descriptor["mobile"] != {"version": semver, "build": int(build)}:
            raise ValueError("artifact version does not match release")
        if descriptor["artifact"] != {"filename": name, "sha256": sha256(directory / name), "size_bytes": (directory / name).stat().st_size}:
            raise ValueError("artifact differs from its attestation")
    return paths + [directory / "SHA256SUMS"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--check", action="store_true", help="Check tag and remote release before building")
    args = parser.parse_args()
    try:
        value = version.check(ROOT, tag=args.tag, release=True)
        repository = os.environ["GITHUB_REPOSITORY"]
        release = release_for_tag(repository, args.tag)
        if release is not None and not release["draft"]:
            raise ValueError("this release is already public; prepare a new version instead of replacing it")
        if args.check:
            print("Release tag and unpublished state verified.")
            return 0
        directory = ROOT / "dist/android-current"
        if "local_debug" in directory.resolve().parts:
            raise ValueError("private local artifacts must not be uploaded")
        assets = inventory(directory, value)
        notes = ROOT / "dist/release-notes.md"
        notes.write_text(version.notes(ROOT, value))
        if release is None:
            gh("release", "create", args.tag, "--repo", repository, "--verify-tag", "--draft", "--title", f"CoRHub v{value}", "--notes-file", str(notes))
        else:
            gh("release", "edit", args.tag, "--repo", repository, "--title", f"CoRHub v{value}", "--notes-file", str(notes))
            # Only unpublished drafts can be repaired by a rerun.
            for asset in release["assets"]:
                gh("release", "delete-asset", args.tag, asset["name"], "--repo", repository, "--yes")
        gh("release", "upload", args.tag, "--repo", repository, *(str(path) for path in assets))
        uploaded = release_for_tag(repository, args.tag)
        expected = {path.name: (path.stat().st_size, "sha256:" + sha256(path)) for path in assets}
        actual = {asset["name"]: (asset["size"], asset["digest"]) for asset in uploaded["assets"]}
        if actual != expected or not uploaded["draft"]:
            raise ValueError("uploaded draft inventory/digests differ; leaving draft unpublished")
        gh("release", "edit", args.tag, "--repo", repository, "--draft=false", "--latest")
        print(uploaded["html_url"])
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release publication failed: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
