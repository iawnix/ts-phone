<p align="center">
  <img src="apps/mobile/assets/branding/ts-phone-mark.png" alt="TS Phone logo" width="104">
</p>

# TS Phone

[简体中文](README.zh-CN.md)

TS Phone is the mobile companion for [TSPi](https://github.com/iawnix/TSPi). It
connects a phone to TSPi workspaces, Pi conversations, and research activity
through an authenticated host service.

The repository contains the Flutter Android client, the TypeScript host broker,
shared Phone protocols, and the release tooling used by the TSPi component
installer.

## Features

- Browse projects, conversations, branches, and persisted session history.
- Create, rename, archive, restore, and delete projects and conversations.
- Follow messages, tool calls, research activity, failures, and run status over SSE.
- Send messages from a phone or terminal through one workspace queue.
- Select the model for new and queued messages and see the active model reported by the Bridge.
- Use English or Chinese, light or dark themes, large text, and reduced motion.
- Reconnect to the same conversation from the terminal, browser, or phone.

## Architecture

```text
Flutter app
    |
    | HTTPS + SSE
    v
reverse proxy
    |
    | loopback HTTP
    v
TS Phone broker
    |                 |
    | starts Worker   | authenticated Unix socket
    v                 v
TSPi/Pi process <-> TSPi Bridge
```

TSPi stores scientific state and Pi session files. The Phone broker manages
authentication, project and session metadata, live event delivery, queued
requests, and the lifecycle of TSPi Workers. Pi JSONL remains the conversation
history while the broker stores pending requests and delivery receipts.

Several clients can view a project at the same time. Messages run in arrival
order, with one Agent turn active per workspace; independent workspaces run in
parallel.

## Installation

The TSPi installer deploys the Phone broker from GitHub and configures its
service. The Android client is distributed as a signed GitHub Release asset.
Download the matching release from
[iawnix/ts-phone/releases](https://github.com/iawnix/ts-phone/releases) and
install the `arm64-v8a` APK on current Android phones.

The host installation needs Node.js and npm. Flutter and the Android SDK are
required for mobile development and maintainer release builds only.

See the TSPi [installation guide](https://github.com/iawnix/TSPi/blob/main/docs/INSTALLATION.md)
for the complete host setup. See [Build artifacts](docs/artifacts.md) for APK
versions, checksums, component archives, and release verification.

## Run the broker from source

Install dependencies from the repository root:

```bash
git clone https://github.com/iawnix/ts-phone.git
cd ts-phone
npm ci
```

Configure the host paths and start the broker:

```bash
export TS_PHONE_WORKSPACES=/absolute/path/to/tspi/workspaces
export TS_PHONE_TSPI=/absolute/path/to/tspi/TSPi
export TS_PHONE_STATE_DIR=/absolute/path/to/ts-phone-dev/state
export TS_PHONE_BRIDGE_SOCKET=/absolute/path/to/ts-phone-dev/run/bridge.sock
export TS_PHONE_BRIDGE_SECRET_FILE=/absolute/path/to/ts-phone-dev/state/bridge.secret
npm run dev
```

The broker creates API and Bridge credentials in the configured state directory
on first startup. Run the health check and print the local API token with:

```bash
curl http://127.0.0.1:22113/healthz
TS_PHONE_STATE_DIR=/absolute/path/to/ts-phone-dev/state npm run ctl -- token
```

For remote phone access, place an HTTPS reverse proxy in front of the loopback
broker and enter its URL and API token in the app. The host and TSPi process
should run as the same Unix user so they can access the Bridge socket.

An installed TSPi uses the Host-backed terminal client by default. The `--phone`
alias opens the same conversation service. See the TSPi
[terminal guide](https://github.com/iawnix/TSPi/blob/main/docs/TERMINAL.md) for
workspace and session commands.

## Run the Android client from source

```bash
cd apps/mobile
flutter pub get
flutter devices
flutter run -d DEVICE_ID
```

Enter the broker's HTTPS URL and API token in the app. Android release users
should install the signed APK from GitHub Releases instead of building the app.

## Development checks

Run broker and release checks from the repository root:

```bash
npm run typecheck
npm test
npm run test:release
npm run build
TS_PHONE_SMOKE_PORT=23113 npm run smoke
```

Run mobile checks from `apps/mobile`:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

The iteration commands provide shorter feedback loops:

```bash
npm run iterate:dev
npm run iterate:candidate
npm run iterate:release
```

`candidate` builds a local arm64 APK. `release` builds the three ABI APKs, an
AAB, source attestations, and the validated TS Phone component archive.

## Android releases

The `TS Phone Android Release` workflow runs for tags such as
`ts-phone-v0.18.3+48` and can also be started manually for a release tag. It
publishes signed APKs, the AAB, source attestations, and the component archive
to the GitHub Release page.

Maintainers configure the signing secrets described in
[Build artifacts](docs/artifacts.md), then push a tag matching the mobile
version in `apps/mobile/pubspec.yaml`.

## Security

The API token grants control of the configured TSPi installation: project and
session management, Worker starts, prompts, lifecycle actions, and deletion.
Store it as a private credential and use HTTPS for connections outside the host.

Conversation projections can include visible text, tool arguments, and tool
results. Keep credentials out of conversations, screenshots, logs, and source
control. The full trust model is documented in [Security](docs/security.md).

## Platform status

| Component | Version / support |
| --- | --- |
| Host | 0.9.1; API v4, Events v3, Bridge v3, `terminal.attach` |
| Android | App 0.18.3+48; Android 7.0 or newer |
| TSPi | 0.15.0; terminal attach, exact-session Workers, and lifecycle guards |
| iOS | Flutter source included; release builds require macOS and Apple signing |

## Documentation

- [Architecture](docs/architecture.md)
- [Security](docs/security.md)
- [Deployment](docs/deployment.md)
- [Recovery](docs/recovery.md)
- [Build artifacts](docs/artifacts.md)
