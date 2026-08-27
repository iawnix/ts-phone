#!/usr/bin/env python3
"""CLI for building a validated TS Phone component release."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from release_builder import ComponentReleaseError, build_component_release


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APKSIGNER = Path(
    os.environ.get(
        "TS_PHONE_APKSIGNER",
        "/home/iaw/soft/android/sdk/build-tools/36.0.0/apksigner",
    )
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build a validated TS Phone component release.")
    parser.add_argument("--output-dir", default="dist/component", help="Directory for the archive and manifest.")
    parser.add_argument("--mobile-apk", help="Validated arm64 APK; defaults to the current mobile version under dist/.")
    parser.add_argument("--apksigner", default=str(DEFAULT_APKSIGNER), help="Android apksigner executable.")
    parser.add_argument("--allow-dirty", action="store_true", help="Allow a dirty checkout for local validation only.")
    parser.add_argument("--json", action="store_true", help="Print machine-readable output.")
    args = parser.parse_args(argv)
    output_dir = Path(args.output_dir).expanduser()
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    try:
        result = build_component_release(
            ROOT,
            output_dir,
            mobile_apk=Path(args.mobile_apk).expanduser() if args.mobile_apk else None,
            apksigner=Path(args.apksigner).expanduser(),
            allow_dirty=args.allow_dirty,
        )
    except (ComponentReleaseError, json.JSONDecodeError, OSError) as error:
        print(f"TS Phone component release failed: {error}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"release: {result['release_id']}")
        print(f"archive: {result['archive']}")
        print(f"manifest: {result['manifest']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
