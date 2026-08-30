# Build Artifacts

## TSPi Component Release

The distributable Phone input to a complete TSPi Package is built with:

~~~bash
python3 deploy/build-component-release.py --output-dir dist/component --json
~~~

It produces one deterministic `ts-phone-component-*.tgz` plus
`ts-phone-component-release.json`. The manifest binds the server and mobile
versions, API/Events/Bridge protocols, built server entry, arm64 APK digest and
signer certificate, source commit, and component archive digest. Other split
APKs and the AAB remain standalone mobile artifacts; the suite includes only
the production arm64 APK named by the component manifest. The source-tree
systemd unit is not included because live service configuration belongs to the
installation, not to an immutable component release.

## Android Release

- App: TS Phone
- App version: 0.9.0
- Build number: 28
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
- UI: iOS gray and professional dark surfaces, blue-green state badges,
  folder-based workspace identity, compact non-repeating workspace status,
  measured latency/last-sync metadata, active-first session ordering,
  command-style session context, inline code chips, terminal blocks, on-demand
  connection diagnostics, offline read-only timelines without a redundant
  history banner, dynamic controller/observer takeover, adaptive iOS-style
  composer, structured Turn/activity rows, Pi branch selection, automatic
  complete history up to 2000 items, explicit load-all for larger sessions,
  bounded synchronization, direct navigation between the start and latest
  message, adaptive approval panels, large-text support, and the TSPi character
  brand mark
- Branding source: apps/mobile/assets/branding/ts-phone-logo-source.png
- Derived app assets: ts-phone-icon.png, ts-phone-mark.png, and
  ts-phone-mark-monochrome.png
- Android icons: legacy five-density, adaptive foreground, and Android 13
  monochrome themed icon
- Icon generator: apps/mobile/tool/generate_app_icons.sh
- Signing: TS Phone release certificate; APK Signature Scheme v2 and signed AAB
- Certificate SHA-256: 41998c3f13ee6a2b5e370b3ded25de4dc2af4e0de7172dbcc33e63bfa9fdc19f
- Certificate subject: CN=TS Phone Release, O=iawnix, C=CN

| Artifact | ABI / purpose | Version code | Size (bytes) | SHA-256 |
| --- | --- | ---: | ---: | --- |
| `ts-phone-v0.9.0-build28-arm64-v8a-release.apk` | arm64-v8a phones | 2028 | 21198295 | `fd3f4530472839f310200df10a529ada0964a6c90a3c3eadb5d55c1e0f77f7b7` |
| `ts-phone-v0.9.0-build28-armeabi-v7a-release.apk` | 32-bit ARM phones | 1028 | 18922297 | `16323205359fa5c15c1e85976ec35c8f689179bc03ad1ff367b53f1d63659631` |
| `ts-phone-v0.9.0-build28-x86_64-release.apk` | x86_64 emulator/device | 4028 | 22655414 | `c6d8a7a60433eece576409d62b882634dba3436417295402a09dd5962485166b` |
| `ts-phone-v0.9.0-build28-release.aab` | Store bundle | 28 | 57547044 | `e490f0dd5517a5db4635e00020e3215ee682dccb2ec43d692d3a400878379634` |

Flutter adds an ABI-specific prefix to split APK version codes. All artifacts
still represent app version `0.9.0+28`. The APK manifests are not debuggable.
They request only `android.permission.INTERNET` and Android's package-scoped
dynamic-receiver permission. No microphone, Bluetooth, or speech-recognition
declaration is present.

Validation commands:

~~~bash
apps/mobile/tool/build_release_android.sh
/home/iaw/soft/android/sdk/build-tools/36.0.0/aapt dump badging dist/ts-phone-v0.9.0-build28-arm64-v8a-release.apk
/home/iaw/soft/android/sdk/build-tools/36.0.0/aapt dump permissions dist/ts-phone-v0.9.0-build28-arm64-v8a-release.apk
/home/iaw/soft/android/sdk/build-tools/36.0.0/apksigner verify --verbose --print-certs dist/ts-phone-v0.9.0-build28-arm64-v8a-release.apk
/home/iaw/soft/jdk21-local/usr/lib/jvm/java-21-openjdk-amd64/bin/jarsigner -verify dist/ts-phone-v0.9.0-build28-release.aab
sha256sum dist/ts-phone-v0.9.0-build28-*
~~~

The generated Flutter outputs and archived artifacts were compared byte for
byte. Install the `arm64-v8a` APK on typical current Android phones. A previous
debug/profile installation must be uninstalled first because its signing
certificate differs; uninstalling clears its local token and settings.

The APK manifest reports version `0.9.0` and the expected ABI-prefixed version
code. All split APKs passed v2 signature verification. The AAB is signed by the
same release certificate and `jarsigner -verify` exited successfully; JDK 21
reported the expected self-signed/no-timestamp warnings and JarInputStream
consistency warnings for the Android bundle layout. Standalone `bundletool
validate` was not run because only Gradle's non-executable bundletool library
jar is available locally. The Gradle `bundleRelease` task completed normally.

The previous production-signed `0.8.2`, `0.8.3`, `0.8.4`, and `0.8.5`
artifacts remain in `dist/` for rollback. No debug or profile artifact was
produced for `0.9.0`.

## iOS

The Flutter iOS source and AppIcon assets are present. No IPA was produced on
this Linux host. An installable build requires macOS, an Apple development team,
a signing certificate, and a provisioning profile.
