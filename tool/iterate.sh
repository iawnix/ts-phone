#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly MOBILE_ROOT="$ROOT/apps/mobile"
readonly FLUTTER_BIN="${FLUTTER_BIN:-/home/iaw/soft/flutter/bin/flutter}"
readonly DART_BIN="${DART_BIN:-/home/iaw/soft/flutter/bin/dart}"
readonly ANDROID_SDK="${ANDROID_SDK:-/home/iaw/soft/android/sdk}"
readonly JAVA_HOME_PATH="${JAVA_HOME_PATH:-/home/iaw/soft/jdk21-local/usr/lib/jvm/java-21-openjdk-amd64}"
readonly DEFAULT_SIGNING_DIR="/home/iaw/.config/ts-phone/android-signing"

die() {
    printf 'Error[ts-phone-iterate]: %s\n' "$*" >&2
    exit 1
}

log() {
    printf 'Info[ts-phone-iterate]: %s\n' "$*"
}

usage() {
    cat <<'EOF'
Usage: tool/iterate.sh MODE [OPTIONS]

Modes:
  dev        Format, analyze, and test the Flutter client.
  candidate  Run the complete client checks and build one arm64 APK.
  release    Run the checks and build the signed Android release set.

Options:
  --allow-dirty  Allow a local dirty checkout for release attestation.
  -h, --help     Show this help.

Examples:
  tool/iterate.sh dev
  tool/iterate.sh candidate
  tool/iterate.sh release
  tool/iterate.sh release --allow-dirty
EOF
}

run_step() {
    local label=$1
    shift
    local started=$SECONDS
    log "$label"
    "$@"
    log "$label completed in $((SECONDS - started))s"
}

run_mobile() {
    local label=$1
    shift
    run_step "$label" bash -c 'cd -- "$1" && shift && exec "$@"' bash "$MOBILE_ROOT" "$@"
}

require_tools() {
    [[ -x "$DART_BIN" ]] || die "Dart is missing: $DART_BIN"
    [[ -x "$FLUTTER_BIN" ]] || die "Flutter is missing: $FLUTTER_BIN"
}

mobile_checks() {
    require_tools
    run_mobile "mobile format check" "$DART_BIN" format --output=none --set-exit-if-changed lib test
    run_mobile "mobile analyzer" "$FLUTTER_BIN" analyze
    run_mobile "mobile tests" "$FLUTTER_BIN" test
}

configure_flutter_environment() {
    export JAVA_HOME="$JAVA_HOME_PATH"
    export ANDROID_HOME="$ANDROID_SDK"
    export ANDROID_SDK_ROOT="$ANDROID_SDK"
    export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$ROOT/.gradle}"
    export PUB_CACHE="${PUB_CACHE:-$ROOT/.pub-cache}"
    [[ -x "$JAVA_HOME_PATH/bin/java" ]] || die "JDK is missing: $JAVA_HOME_PATH"
    [[ -d "$ANDROID_SDK" ]] || die "Android SDK is missing: $ANDROID_SDK"
}

candidate_mobile_build() {
    configure_flutter_environment
    local signing_dir="${TS_PHONE_SIGNING_DIR:-$DEFAULT_SIGNING_DIR}"
    [[ -f "$signing_dir/ts-phone-release.p12" && -f "$signing_dir/keystore.pass" ]] ||
        die "candidate signing is unavailable; run apps/mobile/tool/setup_release_signing.sh or set TS_PHONE_SIGNING_DIR"
    export TS_PHONE_SIGNING_DIR="$signing_dir"
    run_mobile "candidate arm64 release APK" "$FLUTTER_BIN" build apk --release --target-platform android-arm64
    log "candidate APK: $MOBILE_ROOT/build/app/outputs/flutter-apk/app-release.apk"
}

release_mode() {
    local allow_dirty=false
    while (($#)); do
        case "$1" in
            --allow-dirty) allow_dirty=true ;;
            *) die "unknown release option: $1" ;;
        esac
        shift
    done
    mobile_checks
    configure_flutter_environment
    local build_args=()
    [[ "$allow_dirty" == true ]] && build_args+=(--allow-dirty)
    run_step "signed Android release set" "$ROOT/apps/mobile/tool/build_release_android.sh" "${build_args[@]}"
}

mode=${1:-}
[[ -n "$mode" ]] || { usage; exit 2; }
shift
case "$mode" in
    dev)
        (($# == 0)) || die "dev accepts no options"
        mobile_checks
        ;;
    candidate)
        (($# == 0)) || die "candidate accepts no options"
        mobile_checks
        candidate_mobile_build
        ;;
    release) release_mode "$@" ;;
    -h|--help) usage ;;
    *) die "unknown mode: $mode" ;;
esac
