#!/usr/bin/env bash

set -Eeuo pipefail
umask 077
export LC_ALL=C

readonly MOBILE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly SOURCE_ROOT="$(cd -- "${MOBILE_ROOT}/../.." && pwd -P)"
readonly DEFAULT_SIGNING_DIR="/home/iaw/.config/ts-phone/android-signing"
readonly SIGNING_DIR="${TS_PHONE_SIGNING_DIR:-$DEFAULT_SIGNING_DIR}"
readonly KEYSTORE="${SIGNING_DIR}/ts-phone-release.p12"
readonly PASSWORD_FILE="${SIGNING_DIR}/keystore.pass"
readonly FLUTTER_BIN="${TS_PHONE_FLUTTER:-${FLUTTER_BIN:-/home/iaw/soft/flutter/bin/flutter}}"
readonly ANDROID_SDK="${TS_PHONE_ANDROID_SDK:-${ANDROID_HOME:-/home/iaw/soft/android/sdk}}"
readonly BUILD_TOOLS="${TS_PHONE_BUILD_TOOLS:-${ANDROID_SDK}/build-tools/36.0.0}"
readonly JAVA_HOME_PATH="${TS_PHONE_JAVA_HOME:-${JAVA_HOME:-/home/iaw/soft/jdk21-local/usr/lib/jvm/java-21-openjdk-amd64}}"
readonly JARSIGNER="${TS_PHONE_JARSIGNER:-${JAVA_HOME_PATH}/bin/jarsigner}"
readonly KEYTOOL="${TS_PHONE_KEYTOOL:-${JAVA_HOME_PATH}/bin/keytool}"
readonly CAPTURE_BOOTSTRAP="${SOURCE_ROOT}/apps/mobile/tool/mobile-build-attestation.py"
readonly RELEASE_CERTIFICATE_SHA256="${TS_PHONE_RELEASE_CERTIFICATE_SHA256:-41998c3f13ee6a2b5e370b3ded25de4dc2af4e0de7172dbcc33e63bfa9fdc19f}"

die() {
    printf 'Error[ts-phone-release]: %s\n' "$*" >&2
    exit 1
}

capture_arguments=()
case "$#" in
    0) ;;
    1)
        [[ "$1" == "--allow-dirty" ]] || die "usage: build_release_android.sh [--allow-dirty]"
        capture_arguments+=("--allow-dirty")
        ;;
    *) die "usage: build_release_android.sh [--allow-dirty]" ;;
esac

for command_name in awk cmp grep install mktemp python3 rm tr; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "required command not found: ${command_name}"
done

for required_file in "$KEYSTORE" "$PASSWORD_FILE" "$FLUTTER_BIN" \
    "${BUILD_TOOLS}/aapt" "${BUILD_TOOLS}/apksigner" "$JARSIGNER" \
    "$KEYTOOL" "$CAPTURE_BOOTSTRAP"; do
    [[ -f "$required_file" && ! -L "$required_file" ]] ||
        die "required file is missing or unsafe: ${required_file}"
done

expected_certificate=$(
    "$KEYTOOL" -list -v \
        -keystore "$KEYSTORE" \
        -storetype PKCS12 \
        -alias ts-phone-release \
        -storepass:file "$PASSWORD_FILE" |
        awk -F': ' '/SHA256:/{print $2; exit}'
)
expected_certificate="${expected_certificate//:/}"
expected_certificate="${expected_certificate,,}"
[[ "$expected_certificate" =~ ^[0-9a-f]{64}$ ]] ||
    die "could not read the release certificate fingerprint"
[[ "$expected_certificate" == "$RELEASE_CERTIFICATE_SHA256" ]] ||
    die "configured keystore is not the pinned TS Phone release identity"

export TS_PHONE_SIGNING_DIR="$SIGNING_DIR"
export JAVA_HOME="$JAVA_HOME_PATH"
export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export GRADLE_USER_HOME="${SOURCE_ROOT}/.gradle"
export PUB_CACHE="${SOURCE_ROOT}/.pub-cache"

build_root=$(mktemp -d -t ts-phone-android-build.XXXXXXXX)
[[ -d "$build_root" && ! -L "$build_root" ]] ||
    die "could not create a private Android build directory"
cleanup() {
    if [[ -n "${build_root:-}" && -d "$build_root" && ! -L "$build_root" ]]; then
        rm -rf -- "$build_root"
    fi
}
trap cleanup EXIT
readonly CAPTURED_SOURCE_ROOT="${build_root}/source"
readonly CAPTURED_MOBILE_ROOT="${CAPTURED_SOURCE_ROOT}/apps/mobile"
readonly SOURCE_SNAPSHOT_FILE="${build_root}/source-snapshot.json"
readonly SOURCE_ASSET_DIR="${CAPTURED_MOBILE_ROOT}/android/app/src/main/assets"
readonly SOURCE_ASSET="${SOURCE_ASSET_DIR}/ts-phone-source-snapshot.json"
readonly PRIVATE_ARTIFACT_DIR="${build_root}/artifacts"

python3 "$CAPTURE_BOOTSTRAP" capture \
    --destination "$CAPTURED_SOURCE_ROOT" \
    --output "$SOURCE_SNAPSHOT_FILE" \
    "${capture_arguments[@]}" >/dev/null
readonly CAPTURED_ATTESTATION_TOOL="${CAPTURED_SOURCE_ROOT}/apps/mobile/tool/mobile-build-attestation.py"
[[ -f "$CAPTURED_ATTESTATION_TOOL" && ! -L "$CAPTURED_ATTESTATION_TOOL" ]] ||
    die "captured build attestation tool is missing or unsafe"

mobile_version=$(awk '$1 == "version:" { print $2; exit }' "${CAPTURED_MOBILE_ROOT}/pubspec.yaml")
[[ "$mobile_version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$ ]] ||
    die "invalid mobile version: ${mobile_version}"
readonly VERSION_NAME="${BASH_REMATCH[1]}"
readonly BUILD_NUMBER="${BASH_REMATCH[2]}"
readonly ARTIFACT_PREFIX="ts-phone-v${VERSION_NAME}-build${BUILD_NUMBER}"

# The generated asset is outside its own digest, but inside the private source
# tree that is the only input passed to Flutter.
[[ ! -e "$SOURCE_ASSET" && ! -L "$SOURCE_ASSET" ]] ||
    die "generated source snapshot path already exists: ${SOURCE_ASSET}"
install -d -m 0700 "$SOURCE_ASSET_DIR"
install -m 0600 "$SOURCE_SNAPSHOT_FILE" "$SOURCE_ASSET"

cd -- "$CAPTURED_MOBILE_ROOT"
"$FLUTTER_BIN" build apk --release --split-per-abi
"$FLUTTER_BIN" build appbundle --release
rm -f -- "$SOURCE_ASSET"
python3 "$CAPTURED_ATTESTATION_TOOL" verify-source \
    --repository-root "$SOURCE_ROOT" \
    --source-root "$CAPTURED_SOURCE_ROOT" \
    --source-snapshot "$SOURCE_SNAPSHOT_FILE" >/dev/null

install -d -m 0755 "${SOURCE_ROOT}/dist"
install -d -m 0700 "$PRIVATE_ARTIFACT_DIR"
declare -A apk_sources=(
    [arm64-v8a]="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    [armeabi-v7a]="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
    [x86_64]="build/app/outputs/flutter-apk/app-x86_64-release.apk"
)

for abi in arm64-v8a armeabi-v7a x86_64; do
    source_apk="${apk_sources[$abi]}"
    private_apk="${PRIVATE_ARTIFACT_DIR}/${ARTIFACT_PREFIX}-${abi}-release.apk"
    [[ -f "$source_apk" ]] || die "Flutter output is missing: ${source_apk}"
    install -m 0600 "$source_apk" "$private_apk"
    cmp -s "$source_apk" "$private_apk" || die "staged APK differs: ${abi}"
    apk_verification=$(
        "${BUILD_TOOLS}/apksigner" verify --verbose --print-certs "$private_apk"
    )
    grep -Fq 'Verified using v2 scheme (APK Signature Scheme v2): true' \
        <<<"$apk_verification" || die "APK v2 signature is missing: ${abi}"
    mapfile -t apk_certificates < <(
        awk -F': ' '/Signer #[0-9]+ certificate SHA-256 digest:/{print $2}' \
            <<<"$apk_verification" |
            tr -d ':' |
            tr '[:upper:]' '[:lower:]'
    )
    [[ "${#apk_certificates[@]}" -eq 1 && \
        "${apk_certificates[0]}" == "$RELEASE_CERTIFICATE_SHA256" ]] ||
        die "APK signer does not match the release certificate: ${abi}"
    python3 "$CAPTURED_ATTESTATION_TOOL" verify-apk \
        --artifact "$private_apk" \
        --aapt "${BUILD_TOOLS}/aapt" \
        --version "$VERSION_NAME" \
        --build "$BUILD_NUMBER" \
        --abi "$abi" >/dev/null
    python3 "$CAPTURED_ATTESTATION_TOOL" attest \
        --artifact "$private_apk" \
        --format apk \
        --abi "$abi" \
        --source-root "$CAPTURED_SOURCE_ROOT" \
        --source-snapshot "$SOURCE_SNAPSHOT_FILE" >/dev/null
done

source_bundle="build/app/outputs/bundle/release/app-release.aab"
private_bundle="${PRIVATE_ARTIFACT_DIR}/${ARTIFACT_PREFIX}-release.aab"
[[ -f "$source_bundle" ]] || die "Flutter output is missing: ${source_bundle}"
install -m 0600 "$source_bundle" "$private_bundle"
cmp -s "$source_bundle" "$private_bundle" || die "staged AAB differs"
if bundle_verification=$("$JARSIGNER" -verify -strict -verbose "$private_bundle" 2>&1); then
    bundle_status=0
else
    bundle_status=$?
fi
# Exit 4 is the expected self-signed certificate-chain error. Unsigned entries
# add status 16 and therefore cannot pass this allowlist.
[[ "$bundle_status" -eq 0 || "$bundle_status" -eq 4 ]] ||
    die "AAB strict signature verification failed with status ${bundle_status}"
grep -Fq 'jar verified' <<<"$bundle_verification" ||
    die "AAB signature verification did not confirm the archive"
mapfile -t bundle_certificates < <(
    "$KEYTOOL" -printcert -jarfile "$private_bundle" |
        awk -F': ' '/SHA256:/{print $2}' |
        tr -d ':' |
        tr '[:upper:]' '[:lower:]'
)
[[ "${#bundle_certificates[@]}" -eq 1 && \
    "${bundle_certificates[0]}" == "$RELEASE_CERTIFICATE_SHA256" ]] ||
    die "AAB signer does not match the release certificate"
python3 "$CAPTURED_ATTESTATION_TOOL" attest \
    --artifact "$private_bundle" \
    --format aab \
    --abi universal \
    --source-root "$CAPTURED_SOURCE_ROOT" \
    --source-snapshot "$SOURCE_SNAPSHOT_FILE" >/dev/null
published_root=$(python3 "$CAPTURED_ATTESTATION_TOOL" publish \
    --artifact-root "$PRIVATE_ARTIFACT_DIR" \
    --output-root "${SOURCE_ROOT}/dist" \
    --version "$VERSION_NAME" \
    --build "$BUILD_NUMBER")

printf 'Info[ts-phone-release]: release artifacts and source attestations published at %s\n' "$published_root"
