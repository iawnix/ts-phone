#!/usr/bin/env bash
set -Eeuo pipefail
readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
case "${1:-dev}" in
  dev)
    [[ $# -le 1 ]] || { echo 'dev accepts no options' >&2; exit 2; }
    exec python3 "$ROOT/tool/check.py"
    ;;
  release)
    shift
    python3 "$ROOT/tool/check.py"
    exec "$ROOT/apps/mobile/tool/build_release_android.sh" "$@"
    ;;
  candidate)
    [[ $# -eq 1 ]] || { echo 'candidate accepts no options' >&2; exit 2; }
    python3 "$ROOT/tool/check.py"
    exec "$ROOT/apps/mobile/tool/build_release_android.sh" --allow-dirty
    ;;
  -h|--help)
    echo 'Usage: tool/iterate.sh dev | candidate | release [--allow-dirty]'
    ;;
  *) echo 'Unknown mode; use --help.' >&2; exit 2 ;;
esac
