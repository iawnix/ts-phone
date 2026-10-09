#!/usr/bin/env bash
# Compatibility entry point; tool paths come from the environment, not this file.
set -Eeuo pipefail
readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$ROOT/tool/iterate.sh" release "$@"
