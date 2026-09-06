# Build Artifacts

The records below describe the last published Android release, 0.12.1+36. It
uses API v3 and Bridge v2. The current source tree has advanced to 0.13.0+37,
API v4, and Bridge v3; no new signed artifact or digest is recorded here yet.
Do not relabel the 0.12.1 APK as a current-source build.

## TSPi Component Release

The distributable Phone input to a complete TSPi Package is built with:

~~~bash
python3 deploy/build-component-release.py --output-dir dist/component --json
~~~

It produces one deterministic `ts-phone-component-*.tgz` plus
`ts-phone-component-release.json`. The manifest binds the server and mobile
versions, API/Events/Bridge protocols, built server entry, arm64 APK digest and
signer certificate, complete source snapshot, mobile build attestation, and
component archive digest. The signed APK contains the same source snapshot, so
an old artifact cannot be relabeled for a newer checkout. Other split APKs and
the AAB remain standalone mobile artifacts; each receives its own attestation,
while the suite includes only the production arm64 APK named by the component
manifest. The source-tree
systemd unit is not included because live service configuration belongs to the
installation, not to an immutable component release.

## Android Release

- App: TS Phone
- App version: 0.12.1
- Build number: 36
- Package: xyz.iawnix.ts_phone
- Minimum Android SDK: 24
- Target Android SDK: 36
- Compile Android SDK: 36
- Build mode: Flutter release, AOT compiled, R8 and resource shrinking enabled
- APKs: split by arm64-v8a, armeabi-v7a, and x86_64
- AAB: all three Android ABIs with separated native symbol tables
- Languages: English and Chinese; system, English, or Chinese preference
- Input: text-only application composer with editable local drafts and explicit
  send; system-keyboard dictation remains available as ordinary text input
- UI: semantic light and dark surfaces, bounded liquid-glass navigation and
  transient controls over a continuous conversation canvas, opaque evidence
  and settings surfaces, high-contrast transparency fallback, content-first
  conversation controls, navigation-owned historical-session lock state,
  promptable live observers with read-only tools, compact expandable tool
  disclosures, folder-based workspace identity,
  separate TS Phone and TSPi runtime status, measured latency/last-sync
  metadata, active-first session
  ordering, inline code chips, terminal blocks, full-width stateful connection
  diagnostics, an adaptive Settings hierarchy with endpoint details, an
  authoritative session detail sheet, stable live composer and stop action,
  structured Turn/activity rails, Pi branch selection, automatic complete
  history up to 2000 items, explicit load-all for larger sessions, bounded
  synchronization, direct navigation between the start and latest message,
  Reduce Motion, narrow-screen and large-text support, and the TSPi character
  brand mark
- Authoritative branding source:
  apps/mobile/assets/branding/ts-phone-logo-source.png
- Derived app assets: ts-phone-icon.png, ts-phone-mark.png, and
  ts-phone-mark-monochrome.png
- Legacy SVG files are design references only and are not release inputs; see
  apps/mobile/assets/branding/README.md
- Android icons: legacy five-density, adaptive foreground, and Android 13
  monochrome themed icon
- Icon generator: apps/mobile/tool/generate_app_icons.sh
- Signing: TS Phone release certificate; APK Signature Scheme v2 and signed AAB
- Certificate SHA-256: 41998c3f13ee6a2b5e370b3ded25de4dc2af4e0de7172dbcc33e63bfa9fdc19f
- Certificate subject: CN=TS Phone Release, O=iawnix, C=CN

| Artifact | ABI / purpose | Version code | Size (bytes) | SHA-256 |
| --- | --- | ---: | ---: | --- |
| `ts-phone-v0.12.1-build36-arm64-v8a-release.apk` | arm64-v8a phones | 2036 | 21396055 | `99aa5d6699be10d3d21bf6ad33dfbe0da6bf802daf4f463a004a33fae19c7677` |
| `ts-phone-v0.12.1-build36-armeabi-v7a-release.apk` | 32-bit ARM phones | 1036 | 19152821 | `31210086e476c8bf6e9946f335c7210db15c7f9b27d5a0d5f41eff7666efe7ff` |
| `ts-phone-v0.12.1-build36-x86_64-release.apk` | x86_64 emulator/device | 4036 | 22853174 | `c07f4ca9e45b211dddce6cff2b37540a7a4b519a9e58283e333f843034d2490e` |
| `ts-phone-v0.12.1-build36-release.aab` | Store bundle | 36 | 58175794 | `f27876fdaab383c07415dafbd7ea3d226b1afeed371de3cbcd7fb469d3986add` |

Flutter adds an ABI-specific prefix to split APK version codes. All artifacts
still represent app version `0.12.1+36`. The APK manifests are not debuggable.
They request only `android.permission.INTERNET` and Android's package-scoped
dynamic-receiver permission. No microphone, Bluetooth, or speech-recognition
declaration is present.

Validation commands:

~~~bash
apps/mobile/tool/build_release_android.sh
/home/iaw/soft/android/sdk/build-tools/36.0.0/aapt dump badging dist/android-current/ts-phone-v0.12.1-build36-arm64-v8a-release.apk
/home/iaw/soft/android/sdk/build-tools/36.0.0/aapt dump permissions dist/android-current/ts-phone-v0.12.1-build36-arm64-v8a-release.apk
/home/iaw/soft/android/sdk/build-tools/36.0.0/apksigner verify --verbose --print-certs dist/android-current/ts-phone-v0.12.1-build36-arm64-v8a-release.apk
/home/iaw/soft/jdk21-local/usr/lib/jvm/java-21-openjdk-amd64/bin/jarsigner -verify dist/android-current/ts-phone-v0.12.1-build36-release.aab
sha256sum dist/android-current/ts-phone-v0.12.1-build36-*
~~~

The generated Flutter outputs and archived artifacts were compared byte for
byte. New builds publish one content-addressed directory and atomically update
`dist/android-current`; an existing same-version release is never overwritten.
Install the `arm64-v8a` APK on typical current Android phones. A previous
debug/profile installation must be uninstalled first because its signing
certificate differs; uninstalling clears its local token and settings.

The APK manifest reports version `0.12.1` and the expected ABI-prefixed version
code. All split APKs passed v2 signature verification. The AAB is signed by the
same release certificate and `jarsigner -verify` exited successfully; JDK 21
reported the expected self-signed/no-timestamp warnings and JarInputStream
consistency warnings for the Android bundle layout. Standalone `bundletool
validate` was not run because only Gradle's non-executable bundletool library
jar is available locally. The Gradle `bundleRelease` task completed normally.

The previous production-signed `0.8.2`, `0.8.3`, `0.8.4`, `0.8.5`, `0.9.0`,
`0.9.1`, `0.9.2`, `0.9.3`, `0.10.0`, `0.10.1`, `0.11.0`, and `0.12.0`
artifacts remain in `dist/` for rollback. No debug or profile artifact was
produced for `0.12.1`.

## iOS

The Flutter iOS source and AppIcon assets are present. No IPA was produced on
this Linux host. An installable build requires macOS, an Apple development team,
a signing certificate, and a provisioning profile.
