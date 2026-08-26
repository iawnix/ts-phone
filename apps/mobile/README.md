# TS Phone Mobile

Flutter client for Android and iOS. The app stores its Bearer token in Android
Keystore-backed secure storage or the iOS Keychain, rejects remote plain HTTP,
and refuses redirects on authenticated HTTP and SSE requests.

## Validate

```bash
/home/iaw/soft/flutter/bin/flutter pub get
/home/iaw/soft/flutter/bin/flutter analyze
/home/iaw/soft/flutter/bin/flutter test
```

## Build Android

```bash
tool/setup_release_signing.sh
tool/build_release_android.sh
```

The signing setup is idempotent. It stores the private keystore and password
outside the repository under `/home/iaw/.config/ts-phone/android-signing/`.
Back up both files together; losing them prevents future in-place updates of the
production app.

The release builder produces one APK per supported ABI plus a Play-compatible
AAB under `dist/`. It verifies archive identity, APK v2 signatures, the AAB
signature, and the signer fingerprint. Use the `arm64-v8a` APK for current
64-bit Android phones. Do not produce or distribute a separate debug APK.

An existing debug/profile installation uses a different signer and cannot be
updated in place. Uninstall it before the first release installation; Android
will delete that installation's local token and settings.

iOS source and AppIcon assets are included, but an installable iOS archive must
be built and signed on macOS with an Apple development team and provisioning
profile.
