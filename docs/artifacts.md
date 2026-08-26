# Build Artifacts

## Android Release

- App: TS Phone
- App version: 0.8.5
- Build number: 27
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
  composer, bounded synchronization, direct navigation between the start and
  latest message, adaptive approval panels, large-text support, and the TSPi
  character brand mark
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
| `ts-phone-v0.8.5-build27-arm64-v8a-release.apk` | arm64-v8a phones | 2027 | 21066319 | `70092e69c17540e483b6133c28f754e7d12ee18d6b9f57d0b83cb2114221eed0` |
| `ts-phone-v0.8.5-build27-armeabi-v7a-release.apk` | 32-bit ARM phones | 1027 | 18757553 | `361bac28fdd595bf2dcf5ba38cfbd078cecf7f75b4b292fefe42f813cc6f4a66` |
| `ts-phone-v0.8.5-build27-x86_64-release.apk` | x86_64 emulator/device | 4027 | 22523438 | `a05b8d178690f1d3d9607da60495b239dfc60d1b43d6cc96cbb4375595c9e1fb` |
| `ts-phone-v0.8.5-build27-release.aab` | Store bundle | 27 | 57172759 | `4f62e9bf7a84f6191e8726b4ba3a134d601738c97ae11680c3826bec00ae60d6` |

Flutter adds an ABI-specific prefix to split APK version codes. All artifacts
still represent app version `0.8.5+27`. The APK manifests are not debuggable.
They request only `android.permission.INTERNET` and Android's package-scoped
dynamic-receiver permission. No microphone, Bluetooth, or speech-recognition
declaration is present.

Validation commands:

~~~bash
apps/mobile/tool/build_release_android.sh
/home/iaw/soft/android/sdk/build-tools/36.0.0/aapt dump badging dist/ts-phone-v0.8.5-build27-arm64-v8a-release.apk
/home/iaw/soft/android/sdk/build-tools/36.0.0/aapt dump permissions dist/ts-phone-v0.8.5-build27-arm64-v8a-release.apk
/home/iaw/soft/android/sdk/build-tools/36.0.0/apksigner verify --verbose --print-certs dist/ts-phone-v0.8.5-build27-arm64-v8a-release.apk
/home/iaw/soft/jdk21-local/usr/lib/jvm/java-21-openjdk-amd64/bin/jarsigner -verify dist/ts-phone-v0.8.5-build27-release.aab
sha256sum dist/ts-phone-v0.8.5-build27-*
~~~

The generated Flutter outputs and archived artifacts were compared byte for
byte. Install the `arm64-v8a` APK on typical current Android phones. A previous
debug/profile installation must be uninstalled first because its signing
certificate differs; uninstalling clears its local token and settings.

The APK manifest reports version `0.8.5` and the expected ABI-prefixed version
code. All split APKs passed v2 signature verification. The AAB is signed by the
same release certificate and `jarsigner -verify` exited successfully; JDK 21
reported the expected self-signed/no-timestamp warnings and JarInputStream
consistency warnings for the Android bundle layout. Standalone `bundletool
validate` was not run because only Gradle's non-executable bundletool library
jar is available locally. The Gradle `bundleRelease` task completed normally.

The previous production-signed `0.8.2`, `0.8.3`, and `0.8.4` artifacts remain
in `dist/` for rollback. No debug or profile artifact was produced for `0.8.5`.

## iOS

The Flutter iOS source and AppIcon assets are present. No IPA was produced on
this Linux host. An installable build requires macOS, an Apple development team,
a signing certificate, and a provisioning profile.
