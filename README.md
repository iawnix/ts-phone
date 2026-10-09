# TS Phone

[简体中文](README.zh-CN.md) · [Download Android](https://github.com/iawnix/ts-phone/releases/latest) · [Changelog](CHANGELOG.md)

TS Phone is the Android/iOS Flutter client for
[ResearchAgent](https://github.com/iawnix/TSPi). Use the same research workspaces
and sessions as your terminal, send messages, select models, inspect tool
output, and manage task monitors. Execution and durable session history stay
on the ResearchAgent server.

## Install and connect

1. Download the **arm64-v8a release APK** from the latest GitHub release for a
   typical Android phone. The release also contains armeabi-v7a and x86_64 APKs,
   an AAB for store distribution, source attestations and `SHA256SUMS`.
2. Install ResearchAgent and enable Phone access through a trusted HTTPS Link
   Relay. On the server, run:

   ```bash
   research-agent --workspace reaction-a
   research-agent phone pair
   ```

3. Enter the Relay URL, eight-character pairing code and device name in the app.
   The code expires after five minutes and works once.

The current client targets ResearchAgent **0.18.0** and the
`research-agent-host/2` / `research-agent-link.v1` contracts. Upgrading from the
old TSPi protocol requires a new app and **re-pairing**; old `tspd_` credentials
cannot be reused. Compatibility follows these contracts, not matching app and
server version numbers. See each release's notes for its supported server.

Android is the published binary target. iOS source is maintained, but requires
macOS, an Apple signing team and provisioning; no signed iOS download is provided.

## Architecture

```text
TS Phone -- WSS --> ResearchAgent Link Relay <-- WSS -- ResearchAgent Host
                                                              |
                                                        Pi Harness
                                                              |
                                                   workspace / terminal
```

The phone uses the Host API for workspaces, sessions, models and monitors.
It stores device authorization in platform secure storage. Provider credentials,
execution and session storage stay on the server. A reconnect obtains a fresh
snapshot; manual retries preserve the original message ID. Use a trusted Relay:
WSS encrypts each connection, but the Relay can observe forwarded traffic.

## Development

Use Flutter **3.44.0**, Python **3.10+**, and the committed `pubspec.lock`.
JDK 17 and Android SDK 36 are additionally needed for Android releases.

```bash
python3 tool/version.py check
./tool/iterate.sh dev
```

The helper checks version consistency and runs release-tool tests, Dart format,
Flutter analysis and independent mobile tests in a private source copy. Configure
SDK/cache locations first as described in [development](docs/development.md).
Real Host/Pi interoperability uses the separate local ResearchAgent test runner.
Automated tests do not constitute physical-device acceptance.

## Repository and releases

| Path | Responsibility |
| --- | --- |
| `apps/mobile/lib/` | Flutter UI, Host client and local settings |
| `apps/mobile/test/` | Widget/unit tests and opt-in Host integration |
| `apps/mobile/tool/` | Android signing, build verification and source attestations |
| `tool/` | Version management and development checks |
| `.github/workflows/` | Pull-request checks and tagged Android releases |
| `docs/` | Architecture, development, versioning, deployment and recovery |

`apps/mobile/pubspec.yaml` is the **single version source**. To prepare a release:

```bash
python3 tool/version.py set 0.19.1+62   # example: next compatible fix
# Add the matching CHANGELOG.md entry, validate, and commit.
python3 tool/version.py tag
```

Build numbers always increase. Tags use `ts-phone-v<version>+<build>` and published
assets are never overwritten. See [versioning](docs/versioning.md) and
[release operations](docs/deployment.md). This repository contains only the mobile
client; ResearchAgent Host and Link Relay are maintained in the TSPi repository.

Additional references: [architecture](docs/architecture.md),
[artifacts](docs/artifacts.md), [security](docs/security.md),
[recovery](docs/recovery.md), and [contributor conventions](AGENTS.md).
