#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
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
  dev        Run only the checks affected by local source changes. No build or
             deployment is performed.
  candidate  Run the complete source checks and build one arm64 release APK.
             The APK is a local candidate and is not attested or published.
  release    Build the signed APK set, AAB, attestations, and TS Phone
             component archive. Add --install to activate the server.

Options:
  --all          In dev mode, check both server and mobile components.
  --allow-dirty  Pass the local-validation exception to release builders.
  --install      In release mode, run deploy/install-local.sh --start after
                 all artifacts have been built. Cannot be combined with
                 --allow-dirty.
  -h, --help     Show this help.

Examples:
  tool/iterate.sh dev
  tool/iterate.sh dev --all
  tool/iterate.sh candidate
  tool/iterate.sh release --install
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

run_step() {
    local label=$1
    shift
    local started=$SECONDS
    log "${label}"
    "$@"
    log "${label} completed in $((SECONDS - started))s"
}

run_in_root() {
    local label=$1
    shift
    run_step "$label" bash -c 'cd -- "$1" && shift && exec "$@"' bash "$ROOT" "$@"
}

run_mobile() {
    local label=$1
    shift
    run_step "$label" bash -c 'cd -- "$1" && shift && exec "$@"' bash "$ROOT/apps/mobile" "$@"
}

server_fast_checks() {
    run_in_root "server typecheck" npm run typecheck
    run_in_root "server fast tests" npm run test:fast
}

server_full_checks() {
    run_in_root "server typecheck" npm run typecheck
    run_in_root "server full tests" npm test
}

mobile_checks() {
    [[ -x "$DART_BIN" ]] || die "Dart is missing: $DART_BIN"
    [[ -x "$FLUTTER_BIN" ]] || die "Flutter is missing: $FLUTTER_BIN"
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
        die "candidate release signing is unavailable; run apps/mobile/tool/setup_release_signing.sh or set TS_PHONE_SIGNING_DIR"
    export TS_PHONE_SIGNING_DIR="$signing_dir"
    run_mobile "candidate arm64 release APK" "$FLUTTER_BIN" build apk --release --target-platform android-arm64
    log "candidate APK: $ROOT/apps/mobile/build/app/outputs/flutter-apk/app-release.apk"
}

changed_components() {
    local path
    local server=false
    local mobile=false
    local tooling=false
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        case "$path" in
            services/server/*|packages/protocol/*|package.json|package-lock.json|tsconfig*.json)
                server=true
                ;;
            apps/mobile/*)
                mobile=true
                ;;
            deploy/*|tool/*|.github/*)
                tooling=true
                ;;
        esac
    done < <(
        {
            git -C "$ROOT" diff --name-only --diff-filter=ACMRTUXB HEAD
            git -C "$ROOT" ls-files --others --exclude-standard
        } | sort -u
    )
    printf '%s %s %s\n' "$server" "$mobile" "$tooling"
}

dev_mode() {
    local all=false
    while (($#)); do
        case "$1" in
            --all) all=true ;;
            *) die "unknown dev option: $1" ;;
        esac
        shift
    done

    local server mobile tooling
    read -r server mobile tooling < <(changed_components)
    if [[ "$all" == true ]]; then
        server=true
        mobile=true
    elif [[ "$server" == false && "$mobile" == false && "$tooling" == false ]]; then
        log "no source changes detected; use --all to run both component checks"
        return 0
    fi

    [[ "$server" == true ]] && server_fast_checks
    [[ "$tooling" == true ]] && run_in_root "release-tool tests" npm run test:release
    [[ "$mobile" == true ]] && mobile_checks
}

candidate_mode() {
    server_full_checks
    run_in_root "release-tool tests" npm run test:release
    run_in_root "server production build" npm run build
    mobile_checks
    candidate_mobile_build
}

release_mode() {
    local allow_dirty=false
    local install=false
    while (($#)); do
        case "$1" in
            --allow-dirty) allow_dirty=true ;;
            --install) install=true ;;
            *) die "unknown release option: $1" ;;
        esac
        shift
    done
    [[ "$install" != true || "$allow_dirty" != true ]] ||
        die "--install cannot be combined with --allow-dirty"

    run_in_root "release-tool tests" npm run test:release
    local android_args=()
    local component_args=()
    if [[ "$allow_dirty" == true ]]; then
        android_args+=(--allow-dirty)
        component_args+=(--allow-dirty)
    fi
    run_in_root "signed Android release set" apps/mobile/tool/build_release_android.sh "${android_args[@]}"
    run_in_root "validated TS Phone component archive" python3 deploy/build-component-release.py \
        --output-dir dist/component --json "${component_args[@]}"
    if [[ "$install" == true ]]; then
        run_in_root "activate server release" deploy/install-local.sh --start
    else
        log "artifacts built; server was not activated (use release --install during the upgrade window)"
    fi
}

require_command bash
require_command git
require_command npm
require_command python3

[[ -d "$ROOT/.git" ]] || die "not a Git checkout: $ROOT"

mode=${1:-}
[[ -n "$mode" ]] || { usage; exit 2; }
shift
case "$mode" in
    dev) dev_mode "$@" ;;
    candidate) (($# == 0)) || die "candidate accepts no options"; candidate_mode ;;
    release) release_mode "$@" ;;
    -h|--help) usage ;;
    *) die "unknown mode: $mode" ;;
esac
