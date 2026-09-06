#!/usr/bin/env python3
"""Capture source identity and attest TS Phone Android build artifacts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from release_builder import (
    ComponentReleaseError,
    atomic_write_json,
    capture_source_tree,
    publish_android_release_set,
    read_mobile_version,
    read_object,
    read_server_version,
    validate_source_snapshot,
    verify_apk_metadata,
    verify_clean_captured_source_tree,
    write_mobile_build_attestation_from_captured_source,
)


ROOT = Path(__file__).resolve().parents[1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    capture_parser = commands.add_parser("capture", help="Capture immutable source for an Android release build.")
    capture_parser.add_argument("--destination", required=True, help="New private directory for captured source.")
    capture_parser.add_argument("--output", required=True, help="Path for the source snapshot JSON.")
    capture_parser.add_argument("--allow-dirty", action="store_true", help="Allow dirty source for local validation.")

    verify_parser = commands.add_parser("verify-source", help="Verify captured source after the Android build.")
    verify_parser.add_argument("--repository-root", required=True, help="Git repository that owns the snapshot.")
    verify_parser.add_argument("--source-root", required=True, help="Captured source directory used for the build.")
    verify_parser.add_argument("--source-snapshot", required=True, help="Snapshot JSON produced by capture.")

    attest_parser = commands.add_parser("attest", help="Bind one built artifact to a captured source snapshot.")
    attest_parser.add_argument("--artifact", required=True, help="Built APK or AAB path.")
    attest_parser.add_argument("--format", required=True, choices=("apk", "aab"), dest="artifact_format")
    attest_parser.add_argument("--abi", required=True, help="APK ABI, or universal for an AAB.")
    attest_parser.add_argument("--source-root", required=True, help="Captured source directory used for the build.")
    attest_parser.add_argument(
        "--source-snapshot",
        required=True,
        help="Snapshot JSON captured immediately before the Android build.",
    )

    apk_parser = commands.add_parser("verify-apk", help="Verify APK package, version, build, and ABI metadata.")
    apk_parser.add_argument("--artifact", required=True, help="APK to inspect.")
    apk_parser.add_argument("--aapt", required=True, help="Android aapt executable.")
    apk_parser.add_argument("--version", required=True, help="Expected semantic version.")
    apk_parser.add_argument("--build", required=True, type=int, help="Expected Flutter build number.")
    apk_parser.add_argument("--abi", required=True, help="Expected APK ABI.")

    publish_parser = commands.add_parser("publish", help="Atomically publish a complete Android release set.")
    publish_parser.add_argument("--artifact-root", required=True, help="Private directory containing all artifacts.")
    publish_parser.add_argument("--output-root", required=True, help="Repository release output directory.")
    publish_parser.add_argument("--version", required=True, help="Expected semantic version.")
    publish_parser.add_argument("--build", required=True, type=int, help="Expected Flutter build number.")

    args = parser.parse_args(argv)
    try:
        if args.command == "capture":
            destination = Path(args.output).expanduser().resolve()
            destination.parent.mkdir(parents=True, exist_ok=True)
            captured_source = Path(args.destination).expanduser().resolve()
            snapshot = capture_source_tree(
                ROOT,
                captured_source,
                allow_dirty=args.allow_dirty,
            )
            # Fail before Gradle if the Settings identity and Android version
            # differ. Validate the same captured source that will be built.
            read_mobile_version(captured_source / "apps" / "mobile" / "pubspec.yaml")
            read_server_version(captured_source)
            atomic_write_json(destination, snapshot)
        elif args.command == "verify-source":
            expected_source = read_object(
                Path(args.source_snapshot).expanduser().resolve(),
                "captured source snapshot",
            )
            source = validate_source_snapshot(expected_source)
            if not source["dirty"]:
                verify_clean_captured_source_tree(
                    Path(args.repository_root).expanduser().resolve(),
                    Path(args.source_root).expanduser().resolve(),
                    source,
                )
            destination = Path(args.source_root).expanduser().resolve()
        elif args.command == "attest":
            expected_source = read_object(
                Path(args.source_snapshot).expanduser().resolve(),
                "captured source snapshot",
            )
            destination = write_mobile_build_attestation_from_captured_source(
                Path(args.source_root).expanduser().resolve(),
                Path(args.artifact).expanduser(),
                artifact_format=args.artifact_format,
                abi=args.abi,
                expected_source=expected_source,
            )
        elif args.command == "verify-apk":
            verify_apk_metadata(
                Path(args.aapt).expanduser().resolve(),
                Path(args.artifact).expanduser().resolve(),
                args.version,
                args.build,
                args.abi,
            )
            destination = Path(args.artifact).expanduser().resolve()
        else:
            destination = publish_android_release_set(
                Path(args.artifact_root).expanduser().resolve(),
                Path(args.output_root).expanduser().resolve(),
                args.version,
                args.build,
            )
    except (ComponentReleaseError, json.JSONDecodeError, OSError, UnicodeError) as error:
        print(f"TS Phone mobile build attestation failed: {error}", file=sys.stderr)
        return 1

    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
