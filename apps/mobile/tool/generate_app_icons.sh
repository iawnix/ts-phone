#!/usr/bin/env bash
set -Eeuo pipefail
readonly TOOL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${CORHUB_PYTHON:-python3}" "$TOOL_ROOT/generate_app_icons.py"
