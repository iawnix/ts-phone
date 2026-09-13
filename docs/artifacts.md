# Build Artifacts

## Current Source And Downloads

Mobile `0.18.3+48` opens a work home with recent conversations and projects,
with explicit navigation, a session sidebar and a single expanding text
composer. Cold start requests summary lists only. History opens without starting a
Worker, requests the latest 50 items first, and retains the explicit load-all
action. Recent previews, scroll positions and drafts are bounded in-memory
display state, not command authority. See `architecture.md` for cache limits.
Menus, typography, settings rows and technical details use one visual hierarchy.
Empty assistant records have explicit output notices; consecutive activity
records fold without hiding failures or removing history.

History navigation now supersedes stale page replies and cancels the old HTTP
event stream without blocking the tail read. Long output uses bounded previews
and a separate full-output page; render failures remain reported but occupy a
bounded visible error row. Project and conversation lifecycle lists are separate,
with explicit current, archived, and recently deleted selections.

The composer selects a model for future messages, even while generating or
viewing inactive history. The model-list path now has exactly one API prefix.
Host `0.9.1` serves the Phone app and the TSPi
`0.15.0` thin terminal through the same authenticated session APIs, including
bounded approval and prompt-receipt queries. Provider credentials remain with
the Worker. Terminal detach does not stop generation or remote calculations.
The patch distinguishes guard validation from an incomplete installation upgrade;
it no longer advises broadening process-access permissions. Installed Host and
terminal entrypoints share the same private configuration reader.

It keeps pending prompt receipts across page navigation, reuses the
original request identity for an explicit uncertain retry, and preserves newer
draft edits when a late response arrives. Native back and the toolbar share
the same route stack; back from an approval panel defers the decision. Model
storage failures now have a distinct diagnostic instead of appearing as missing
models or credentials. Host deployment must include the selected Pi directory's
narrow write permission; see `deployment.md`.

Normal conversations no longer require Continue or a read-only/research mode
choice. Send persists a request in the Host workspace queue; several clients
can read and submit while only one turn executes per workspace. The request
list supports cancellation before dispatch and explicit acknowledgement after
inspecting an uncertain outcome. Restart never replays in-flight requests.
Server `0.9.1` checks launch identity and model readiness, transfers only idle
Host-owned execution, and refuses to stop busy or external runtimes. TSPi
`0.15.0` acquires exact-session writer guards before Pi opens history. Activation
preserves drafts and uses a separate 90-second wait budget. Activation receipts
are bounded in-memory state; command.queue receipts are separate durable state.
API v4, Events v3, and Bridge v3 remain unchanged; queue use is capability-negotiated.

Download the signed Android APK from the matching
[GitHub Release](https://github.com/iawnix/ts-phone/releases). Install the
`arm64-v8a` APK on most current phones; use `armeabi-v7a` or `x86_64` only for
devices with those ABIs. The release includes the APK SHA-256 digest and its
source attestation. The APK version must match the Phone server component used
by TSPi.

Maintainers build with `apps/mobile/tool/build_release_android.sh` and publish
through `.github/workflows/android-release.yml`. Local artifacts are published
under `dist/android-releases/` and selected by `dist/android-current`; local
builds do not create a GitHub Release.

## Historical Release Record

The records below describe Android release 0.13.0+37, built on 2026-09-06 from
commit `cbeed20645327abc19ec4dfdab867ba940f61ea7`. Its source snapshot SHA-256 is
`806a92797f308c726b0a7f5f47bba3ddecb39e515ee384d6bab71d7bf2550475`.
The release uses API v4, Events v3, and Bridge v3.

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

The recorded Phone component release is
`0.6.0-mobile-0.13.0-build37-source-78a142e947b7491d-sha256-c0755b995c836f01`.
Its archive is 10,493,644 bytes with SHA-256
`c0755b995c836f01c5f04c0e03d303a04857b2c482b8317afccc37d0cd77daba`.
It is included in TSPi Package
`0.12.0-sha256-350faa25d47c9e28`, whose 11,258,016-byte archive has SHA-256
`350faa25d47c9e28f7930eaf3bf3d45e018d728aa1944770cb6d86d9b4a9d7e3`.

## Android Release

Production releases contain the signed APKs, AAB, per-artifact source
attestations, and the validated `ts-phone-component-*.tgz` archive. A release
tag has the form `ts-phone-v<mobile-version>`, for example
`ts-phone-v0.18.3+48`. The workflow checks that tag against
`apps/mobile/pubspec.yaml` before uploading the assets.

- App: TS Phone
- App version: 0.13.0
- Build number: 37
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
- UI: neutral light and dark surfaces, opaque evidence and settings surfaces,
  high-contrast transparency fallback, content-first
  conversation controls, navigation-owned historical-session lock state,
  promptable live observers with read-only tools, compact expandable tool
  disclosures, folder-based workspace identity,
  separate TS Phone and TSPi runtime status, measured latency/last-sync
  metadata, active-first session
  ordering, inline code chips, terminal blocks, full-width stateful connection
  diagnostics, an adaptive Settings hierarchy with endpoint details, an
  authoritative session detail sheet, stable live composer and stop action,
  structured Turn/activity rails, Pi branch selection, automatic history loading
  up to 2000 timeline items, explicit large-history load-all, bounded
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
| `ts-phone-v0.13.0-build37-arm64-v8a-release.apk` | arm64-v8a phones | 2037 | 21527493 | `68d6d6319d89e03834164e3676dca45e6810dc1aad626f9d286cafd302e2df18` |
| `ts-phone-v0.13.0-build37-armeabi-v7a-release.apk` | 32-bit ARM phones | 1037 | 19300647 | `367ac628b7f8f6bd45ca6271542c7ecc04633df5820e26b7fccb552507a1f88f` |
| `ts-phone-v0.13.0-build37-x86_64-release.apk` | x86_64 emulator/device | 4037 | 23050148 | `1fe6f9c28e2e2426be4373ced61046f3954eecb1ce001c8f99d982c9c43e389c` |
| `ts-phone-v0.13.0-build37-release.aab` | Store bundle | 37 | 58545915 | `eda16c8266ff92bfd49fd2cf5651a885b2c929a8b88f3064dbbeea823c7f6ba9` |

Flutter adds an ABI-specific prefix to split APK version codes. All artifacts
still represent app version `0.13.0+37`. The APK manifests are not debuggable.
They request only `android.permission.INTERNET` and Android's package-scoped
dynamic-receiver permission. No microphone, Bluetooth, or speech-recognition
declaration is present.

Validation commands:

~~~bash
apps/mobile/tool/build_release_android.sh
/home/iaw/soft/android/sdk/build-tools/36.0.0/aapt dump badging dist/android-current/ts-phone-v0.13.0-build37-arm64-v8a-release.apk
/home/iaw/soft/android/sdk/build-tools/36.0.0/aapt dump permissions dist/android-current/ts-phone-v0.13.0-build37-arm64-v8a-release.apk
/home/iaw/soft/android/sdk/build-tools/36.0.0/apksigner verify --verbose --print-certs dist/android-current/ts-phone-v0.13.0-build37-arm64-v8a-release.apk
/home/iaw/soft/jdk21-local/usr/lib/jvm/java-21-openjdk-amd64/bin/jarsigner -verify dist/android-current/ts-phone-v0.13.0-build37-release.aab
sha256sum dist/android-current/ts-phone-v0.13.0-build37-*
~~~

The generated Flutter outputs and archived artifacts were compared byte for
byte. New builds publish one content-addressed directory and atomically update
`dist/android-current`; an existing same-version release is never overwritten.
Install the `arm64-v8a` APK on typical current Android phones. A previous
debug/profile installation must be uninstalled first because its signing
certificate differs; uninstalling clears its local token and settings.

The APK manifest reports version `0.13.0` and the expected ABI-prefixed version
code. All split APKs passed v2 signature verification. The AAB is signed by the
same release certificate and passed the release script's strict `jarsigner`
policy; JDK 21 reported the expected self-signed/no-timestamp warnings and
JarInputStream consistency warnings for the Android bundle layout. Standalone `bundletool
validate` was not run because only Gradle's non-executable bundletool library
jar is available locally. The Gradle `bundleRelease` task completed normally.

The previous production-signed `0.8.2`, `0.8.3`, `0.8.4`, `0.8.5`, `0.9.0`,
`0.9.1`, `0.9.2`, `0.9.3`, `0.10.0`, `0.10.1`, `0.11.0`, `0.12.0`, and
`0.12.1` artifacts remain in `dist/` for rollback. No debug or profile artifact
was produced for `0.13.0`.

## iOS

The Flutter iOS source and AppIcon assets are present. No IPA was produced on
this Linux host. An installable build requires macOS, an Apple development team,
a signing certificate, and a provisioning profile.
