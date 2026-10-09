#!/usr/bin/env python3
"""Run independent client checks in an isolated local source copy."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    private = Path(os.environ.get("TS_PHONE_TEST_ROOT", "/home/iaw/project/TSPi/local_debug/ts-phone")).resolve()
    private.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="check-", dir=private))
    env = os.environ.copy()
    for name in ("TMPDIR", "XDG_CACHE_HOME", "XDG_CONFIG_HOME"):
        path = run / name.lower()
        path.mkdir()
        env[name] = str(path)
    env.update(PYTHONDONTWRITEBYTECODE="1", FLUTTER_SUPPRESS_ANALYTICS="true", CI="true")
    env["PUB_CACHE"] = os.environ.get("PUB_CACHE", str(private / "pub-cache"))
    env["GRADLE_USER_HOME"] = str(private / "gradle")
    flutter = os.environ.get("FLUTTER_BIN") or shutil.which("flutter")
    if not flutter:
        print("Set FLUTTER_BIN to a private test Flutter 3.44.0 SDK (see docs/development.md).", file=sys.stderr)
        return 1
    flutter = str(Path(flutter).resolve())
    dart = str(Path(flutter).with_name("dart"))
    source = run / "source"
    names = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT).split(b"\0")
    for name in sorted(set(names)):
        if not name:
            continue
        relative = Path(os.fsdecode(name))
        if "local_debug" in relative.parts:
            raise ValueError("private data must not enter a source snapshot")
        origin = ROOT / relative
        if origin.is_symlink():
            raise ValueError(f"source symlinks are not supported: {relative}")
        if not origin.is_file():
            continue
        target = source / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, target)
    mobile = source / "apps/mobile"
    tests = sorted(str(p.relative_to(mobile)) for p in (mobile / "test").glob("*_test.dart") if p.name != "host_interop_test.dart")
    steps = [
        ("version", [sys.executable, str(ROOT / "tool/version.py"), "check"], ROOT),
        ("release-tools", [sys.executable, "-m", "unittest", "discover", "-s", "tool/tests", "-v"], source),
        ("dependencies", [flutter, "pub", "get", "--enforce-lockfile", *(["--offline"] if env.get("TS_PHONE_OFFLINE") == "1" else [])], mobile),
        ("format", [dart, "format", "--output=none", "--set-exit-if-changed", "lib", "test"], mobile),
        ("analyze", [flutter, "analyze", "--no-pub"], mobile),
        ("mobile", [flutter, "test", "--no-pub", "--concurrency=4", *tests], mobile),
    ]
    for label, command, cwd in steps:
        with (run / f"{label}.log").open("w") as log:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
        print(f"{label}: {'PASS' if result.returncode == 0 else 'FAIL'}", flush=True)
        if result.returncode:
            print(f"Detailed evidence stays in {run}; no logs are uploaded.", file=sys.stderr)
            return result.returncode
    print(f"Independent checks passed ({len(tests)} Flutter test files). Host/Pi interop is a separate suite.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
