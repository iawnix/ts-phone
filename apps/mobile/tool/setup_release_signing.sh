#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly DEFAULT_SIGNING_DIR="/home/iaw/.config/ts-phone/android-signing"
readonly SIGNING_DIR="${TS_PHONE_SIGNING_DIR:-$DEFAULT_SIGNING_DIR}"
readonly KEYSTORE="${SIGNING_DIR}/ts-phone-release.p12"
readonly PASSWORD_FILE="${SIGNING_DIR}/keystore.pass"
readonly KEY_ALIAS="ts-phone-release"

die() {
    printf 'Error[ts-phone-signing]: %s\n' "$*" >&2
    exit 1
}

for command_name in chmod install keytool openssl; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "required command not found: ${command_name}"
done

if [[ -e "$KEYSTORE" || -e "$PASSWORD_FILE" ]]; then
    [[ -f "$KEYSTORE" && ! -L "$KEYSTORE" ]] ||
        die "refusing partial or unsafe signing state: ${KEYSTORE}"
    [[ -f "$PASSWORD_FILE" && ! -L "$PASSWORD_FILE" ]] ||
        die "refusing partial or unsafe signing state: ${PASSWORD_FILE}"
    chmod 0600 "$KEYSTORE" "$PASSWORD_FILE"
    keytool -list \
        -keystore "$KEYSTORE" \
        -storepass:file "$PASSWORD_FILE" \
        -alias "$KEY_ALIAS" >/dev/null
    printf 'Info[ts-phone-signing]: existing release key is valid at %s\n' "$KEYSTORE"
    exit 0
fi

install -d -m 0700 "$SIGNING_DIR"
openssl rand -hex -out "$PASSWORD_FILE" 32
chmod 0600 "$PASSWORD_FILE"
keytool -genkeypair \
    -keystore "$KEYSTORE" \
    -storetype PKCS12 \
    -storepass:file "$PASSWORD_FILE" \
    -keypass:file "$PASSWORD_FILE" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 4096 \
    -sigalg SHA256withRSA \
    -validity 9125 \
    -dname "CN=TS Phone Release, O=iawnix, C=CN"
chmod 0600 "$KEYSTORE"

keytool -list \
    -keystore "$KEYSTORE" \
    -storepass:file "$PASSWORD_FILE" \
    -alias "$KEY_ALIAS" >/dev/null
printf 'Info[ts-phone-signing]: created release key at %s\n' "$KEYSTORE"
printf 'Info[ts-phone-signing]: back up the keystore and password file together\n'
