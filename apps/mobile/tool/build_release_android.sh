#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly MOBILE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly SOURCE_ROOT="$(cd -- "${MOBILE_ROOT}/../.." && pwd -P)"
readonly DEFAULT_SIGNING_DIR="/home/iaw/.config/ts-phone/android-signing"
readonly SIGNING_DIR="${TS_PHONE_SIGNING_DIR:-$DEFAULT_SIGNING_DIR}"
readonly KEYSTORE="${SIGNING_DIR}/ts-phone-release.p12"
readonly PASSWORD_FILE="${SIGNING_DIR}/keystore.pass"
readonly FLUTTER_BIN="/home/iaw/soft/flutter/bin/flutter"
readonly ANDROID_SDK="/home/iaw/soft/android/sdk"
readonly BUILD_TOOLS="${ANDROID_SDK}/build-tools/36.0.0"
readonly JAVA_HOME_PATH="/home/iaw/soft/jdk21-local/usr/lib/jvm/java-21-openjdk-amd64"
readonly JARSIGNER="${JAVA_HOME_PATH}/bin/jarsigner"
readonly KEYTOOL="${JAVA_HOME_PATH}/bin/keytool"

die() {
    printf 'Error[ts-phone-release]: %s\n' "$*" >&2
    exit 1
}

for command_name in awk cmp grep install; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "required command not found: ${command_name}"
done

for required_file in "$KEYSTORE" "$PASSWORD_FILE" "$FLUTTER_BIN" \
    "${BUILD_TOOLS}/aapt" "${BUILD_TOOLS}/apksigner" "$JARSIGNER" \
    "$KEYTOOL"; do
    [[ -f "$required_file" && ! -L "$required_file" ]] ||
        die "required file is missing or unsafe: ${required_file}"
done

mobile_version=$(awk '$1 == "version:" { print $2; exit }' "${MOBILE_ROOT}/pubspec.yaml")
[[ "$mobile_version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$ ]] ||
    die "invalid mobile version: ${mobile_version}"
readonly VERSION_NAME="${BASH_REMATCH[1]}"
readonly BUILD_NUMBER="${BASH_REMATCH[2]}"
readonly ARTIFACT_PREFIX="ts-phone-v${VERSION_NAME}-build${BUILD_NUMBER}"

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

export TS_PHONE_SIGNING_DIR="$SIGNING_DIR"
export JAVA_HOME="$JAVA_HOME_PATH"
export ANDROID_HOME="$ANDROID_SDK"
export ANDROID_SDK_ROOT="$ANDROID_SDK"
export GRADLE_USER_HOME="${SOURCE_ROOT}/.gradle"
export PUB_CACHE="${SOURCE_ROOT}/.pub-cache"

cd -- "$MOBILE_ROOT"
"$FLUTTER_BIN" build apk --release --split-per-abi
"$FLUTTER_BIN" build appbundle --release

install -d -m 0755 "${SOURCE_ROOT}/dist"
declare -A apk_sources=(
    [arm64-v8a]="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    [armeabi-v7a]="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
    [x86_64]="build/app/outputs/flutter-apk/app-x86_64-release.apk"
)

for abi in arm64-v8a armeabi-v7a x86_64; do
    source_apk="${apk_sources[$abi]}"
    target_apk="${SOURCE_ROOT}/dist/${ARTIFACT_PREFIX}-${abi}-release.apk"
    [[ -f "$source_apk" ]] || die "Flutter output is missing: ${source_apk}"
    install -m 0644 "$source_apk" "$target_apk"
    cmp -s "$source_apk" "$target_apk" || die "archived APK differs: ${abi}"
    apk_verification=$(
        "${BUILD_TOOLS}/apksigner" verify --verbose --print-certs "$target_apk"
    )
    grep -Fq 'Verified using v2 scheme (APK Signature Scheme v2): true' \
        <<<"$apk_verification" || die "APK v2 signature is missing: ${abi}"
    apk_certificate=$(awk -F': ' \
        '/Signer #1 certificate SHA-256 digest:/{print $2; exit}' \
        <<<"$apk_verification")
    [[ "$apk_certificate" == "$expected_certificate" ]] ||
        die "APK signer does not match the release certificate: ${abi}"
done

source_bundle="build/app/outputs/bundle/release/app-release.aab"
target_bundle="${SOURCE_ROOT}/dist/${ARTIFACT_PREFIX}-release.aab"
[[ -f "$source_bundle" ]] || die "Flutter output is missing: ${source_bundle}"
install -m 0644 "$source_bundle" "$target_bundle"
cmp -s "$source_bundle" "$target_bundle" || die "archived AAB differs"
"$JARSIGNER" -verify "$target_bundle" >/dev/null
bundle_certificate=$(
    "$KEYTOOL" -printcert -jarfile "$target_bundle" |
        awk -F': ' '/SHA256:/{print $2; exit}'
)
bundle_certificate="${bundle_certificate//:/}"
bundle_certificate="${bundle_certificate,,}"
[[ "$bundle_certificate" == "$expected_certificate" ]] ||
    die "AAB signer does not match the release certificate"

printf 'Info[ts-phone-release]: release artifacts archived under %s/dist\n' "$SOURCE_ROOT"
