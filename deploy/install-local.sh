#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly SOURCE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly VERSION_FILE="${SOURCE_ROOT}/VERSION"
readonly MOBILE_VERSION_FILE="${SOURCE_ROOT}/apps/mobile/pubspec.yaml"
readonly INSTALL_ROOT="/home/iaw/soft/ts-phone"
readonly CONFIG_DIR="/home/iaw/.config/ts-phone"
readonly STATE_DIR="/home/iaw/.local/state/ts-phone"
readonly USER_BIN_DIR="/home/iaw/.local/bin"
readonly USER_UNIT_DIR="/home/iaw/.config/systemd/user"

log() {
    printf 'Info[ts-phone]: %s\n' "$*"
}

die() {
    printf 'Error[ts-phone]: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: install-local.sh [--start]

Install the built TS Phone release into /home/iaw/soft/ts-phone. Without
--start, only the immutable release is staged and the active service is not
changed. --start activates the release, restarts the service, and checks its
API version. Existing server.env and auth.token files are preserved.
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

atomic_link() {
    local target=$1
    local link_path=$2
    local temporary_link="${link_path}.new.$$"

    unlink -- "$temporary_link" 2>/dev/null || true
    ln -s -- "$target" "$temporary_link"
    mv -Tf -- "$temporary_link" "$link_path"
}

start_service=false
while (($#)); do
    case "$1" in
        --start)
            start_service=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
    shift
done

for command_name in awk basename cat chmod date find id install ln mktemp mv node readlink rm rsync sha256sum sleep systemctl tr unlink; do
    require_command "$command_name"
done

[[ -f "$VERSION_FILE" && ! -L "$VERSION_FILE" ]] || die "VERSION is missing or unsafe"
version=$(tr -d '[:space:]' <"$VERSION_FILE")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid VERSION: ${version}"
[[ -f "$MOBILE_VERSION_FILE" && ! -L "$MOBILE_VERSION_FILE" ]] || die "mobile pubspec is missing or unsafe"
mobile_version=$(awk '$1 == "version:" { print $2; exit }' "$MOBILE_VERSION_FILE")
[[ "$mobile_version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$ ]] ||
    die "invalid mobile version: ${mobile_version}"
mobile_name="${BASH_REMATCH[1]}"
mobile_build="${BASH_REMATCH[2]}"

readonly RELEASE_DIR="${INSTALL_ROOT}/${version}"
readonly APP_DIR="${RELEASE_DIR}/app"
readonly CURRENT_LINK="${INSTALL_ROOT}/current"
readonly SERVER_ENTRY="${SOURCE_ROOT}/services/server/dist/index.js"
readonly CTL_ENTRY="${SOURCE_ROOT}/bin/ts-phone-ctl"
readonly UNIT_SOURCE="${SOURCE_ROOT}/deploy/systemd/ts-phone.service"
readonly ENV_SOURCE="${SOURCE_ROOT}/deploy/server.env.example"
readonly APK_SOURCE="${SOURCE_ROOT}/dist/ts-phone-v${mobile_name}-build${mobile_build}-arm64-v8a-release.apk"

for required_file in "$SERVER_ENTRY" "$CTL_ENTRY" "$UNIT_SOURCE" "$ENV_SOURCE"; do
    [[ -f "$required_file" && ! -L "$required_file" ]] || die "required release file is missing or unsafe: ${required_file}"
done
node --check "$SERVER_ENTRY"

install -d -m 0755 "$INSTALL_ROOT"
staging_dir=
cleanup() {
    if [[ -n "$staging_dir" && -d "$staging_dir" && "$staging_dir" == "$INSTALL_ROOT"/.staging.* ]]; then
        rm -rf -- "$staging_dir"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [[ -e "$RELEASE_DIR" || -L "$RELEASE_DIR" ]]; then
    [[ -d "$APP_DIR" && ! -L "$RELEASE_DIR" ]] || die "existing release path is invalid: ${RELEASE_DIR}"
    [[ -f "${APP_DIR}/VERSION" && ! -L "${APP_DIR}/VERSION" ]] || die "existing release VERSION is unsafe"
    [[ "$(tr -d '[:space:]' <"${APP_DIR}/VERSION")" == "$version" ]] || die "existing release VERSION mismatch"
    log "using existing immutable release ${version}"
else
    staging_dir=$(mktemp -d "${INSTALL_ROOT}/.staging.${version}.XXXXXX")
    install -d -m 0755 \
        "${staging_dir}/app/bin" \
        "${staging_dir}/app/services/server/dist" \
        "${staging_dir}/app/docs" \
        "${staging_dir}/src/ts-phone" \
        "${staging_dir}/artifacts"

    rsync -a \
        --exclude='/.git/' \
        --exclude='/.gradle/' \
        --exclude='/.gradle-home/' \
        --exclude='/.npm-cache/' \
        --exclude='/.pub-cache/' \
        --exclude='/node_modules/' \
        --exclude='/dist/' \
        --exclude='/services/server/dist/' \
        --exclude='/apps/mobile/.dart_tool/' \
        --exclude='/apps/mobile/build/' \
        --exclude='/apps/mobile/android/local.properties' \
        --exclude='/apps/mobile/android/key.properties' \
        --exclude='/apps/mobile/ios/Flutter/ephemeral/' \
        --exclude='*.env' \
        --exclude='*.jks' \
        --exclude='*.keystore' \
        "${SOURCE_ROOT}/" "${staging_dir}/src/ts-phone/"

    rsync -a "${SOURCE_ROOT}/services/server/dist/" "${staging_dir}/app/services/server/dist/"
    rsync -a "${SOURCE_ROOT}/docs/" "${staging_dir}/app/docs/"
    install -m 0755 "$CTL_ENTRY" "${staging_dir}/app/bin/ts-phone-ctl"
    install -m 0644 "$VERSION_FILE" "${staging_dir}/app/VERSION"
    install -m 0644 "${SOURCE_ROOT}/README.md" "${staging_dir}/app/README.md"
    install -m 0644 "${SOURCE_ROOT}/package.json" "${staging_dir}/app/package.json"

    apk_line="- Android APK: not included"
    if [[ -f "$APK_SOURCE" && ! -L "$APK_SOURCE" ]]; then
        install -m 0644 "$APK_SOURCE" "${staging_dir}/artifacts/$(basename -- "$APK_SOURCE")"
        apk_sha256=$(sha256sum "$APK_SOURCE" | awk '{print $1}')
        apk_line="- Android APK SHA-256: ${apk_sha256}"
    fi
    server_sha256=$(sha256sum "$SERVER_ENTRY" | awk '{print $1}')

    cat >"${staging_dir}/README.md" <<EOF
# TS Phone ${version}

- Installed: $(date -Iseconds)
- Purpose: versioned TS Phone service and production-signed Android artifact
- Source snapshot: src/ts-phone
- Runtime root: app
- Server entry SHA-256: ${server_sha256}
${apk_line}

The stable entrypoint is /home/iaw/soft/ts-phone/current. Runtime configuration
and secrets are external under /home/iaw/.config/ts-phone and
/home/iaw/.local/state/ts-phone. Keep the previous release until local and
public authenticated API checks pass.
EOF
    chmod -R go-w "$staging_dir"
    mv -- "$staging_dir" "$RELEASE_DIR"
    staging_dir=
    log "installed immutable release ${version}"
fi

if [[ "$start_service" != true ]]; then
    log "staged release ${version}; active service and current link were not changed"
    log "run install-local.sh --start during the coordinated upgrade window"
    exit 0
fi

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    user_runtime_dir="/run/user/$(id -u)"
    [[ -d "$user_runtime_dir" && -O "$user_runtime_dir" ]] ||
        die "user runtime directory is unavailable: ${user_runtime_dir}"
    export XDG_RUNTIME_DIR="$user_runtime_dir"
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    user_bus="${XDG_RUNTIME_DIR}/bus"
    [[ -S "$user_bus" && -O "$user_bus" ]] ||
        die "user systemd bus is unavailable: ${user_bus}"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${user_bus}"
fi

if [[ -e "$CURRENT_LINK" && ! -L "$CURRENT_LINK" ]]; then
    die "refusing to replace non-symlink current path: ${CURRENT_LINK}"
fi
old_current_exists=false
old_current_target=
if [[ -L "$CURRENT_LINK" ]]; then
    old_current_exists=true
    old_current_target=$(readlink "$CURRENT_LINK")
fi
atomic_link "${version}/app" "$CURRENT_LINK"

install -d -m 0700 "$CONFIG_DIR" "$STATE_DIR"
for shared_dir in "$USER_BIN_DIR" "$USER_UNIT_DIR"; do
    if [[ -e "$shared_dir" || -L "$shared_dir" ]]; then
        [[ -d "$shared_dir" && ! -L "$shared_dir" ]] || die "shared install directory is unsafe: ${shared_dir}"
    else
        install -d -m 0700 "$shared_dir"
    fi
done
if [[ -e "${CONFIG_DIR}/server.env" || -L "${CONFIG_DIR}/server.env" ]]; then
    [[ -f "${CONFIG_DIR}/server.env" && ! -L "${CONFIG_DIR}/server.env" ]] || die "existing server.env is unsafe"
    chmod 0600 "${CONFIG_DIR}/server.env"
    log "preserved existing server.env"
else
    install -m 0600 "$ENV_SOURCE" "${CONFIG_DIR}/server.env"
    log "installed default server.env"
fi

ctl_link="${USER_BIN_DIR}/ts-phone-ctl"
if [[ -e "$ctl_link" && ! -L "$ctl_link" ]]; then
    die "refusing to replace non-symlink control path: ${ctl_link}"
fi
atomic_link "${CURRENT_LINK}/bin/ts-phone-ctl" "$ctl_link"
install -m 0644 "$UNIT_SOURCE" "${USER_UNIT_DIR}/ts-phone.service"
systemctl --user daemon-reload
log "installed release, control link, configuration, and user unit"

rollback_current() {
    if [[ "$old_current_exists" == true ]]; then
        atomic_link "$old_current_target" "$CURRENT_LINK"
        systemctl --user restart ts-phone.service || true
    else
        systemctl --user disable --now ts-phone.service >/dev/null 2>&1 || true
    fi
}

check_v3_health() {
    node --input-type=module --eval '
const response = await fetch("http://127.0.0.1:22113/healthz", {
  redirect: "error",
  signal: AbortSignal.timeout(5_000),
});
const body = await response.json();
if (!response.ok || body?.ok !== true || body?.service !== "ts-phone" || body?.version !== "ts-phone-api/3") {
  process.exit(1);
}
'
}

if ! systemctl --user enable ts-phone.service ||
   ! systemctl --user restart ts-phone.service; then
    rollback_current
    die "service failed to start; previous current link was restored when available"
fi
sleep 2
if ! systemctl --user is-active --quiet ts-phone.service ||
   ! check_v3_health; then
    rollback_current
    die "service v0.3 health check failed; previous current link was restored when available"
fi
log "ts-phone.service is active and ts-phone-api/3 health passed"
