<p align="center">
  <img src="apps/mobile/assets/branding/ts-phone-mark.png" alt="TS Phone logo" width="104">
</p>

# TS Phone

TS Phone is the mobile companion for [TSPi](https://github.com/iawnix/TSPi).
It lets you browse transition-state research workspaces, follow Pi sessions,
and continue a live conversation from your phone.

This repository contains the Flutter app, a small TypeScript broker, the shared
protocol definitions, and component release tooling. TS Phone runs alongside
TSPi; it is not a general-purpose Pi client or a research runtime by itself.

## What it does

- Browse live and persisted Pi sessions, including earlier conversation branches.
- Follow messages, tool calls, research activity, failures, and run status over SSE.
- See the active model and Pi's context-window estimate when the Bridge reports them.
- Use an English or Chinese interface with light and dark themes, large text, and reduced motion.

## How it fits together

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
    |
    | authenticated Unix socket
    v
TSPi Bridge <-> Pi session
```

TSPi owns the research workspace, Pi processes, and session files. The broker
handles phone authentication, routing, live events, and persisted history. It
does not start Pi or keep a second conversation database.

A workspace can have one live controller and multiple observers. TSPi owns the
single-writer lock and observer tool policy. The broker takes the session mode
from its local Bridge and refuses a second controller.

| Mode | Session | Tool access |
| --- | --- | --- |
| Controller | The workspace's main live Pi session | The same registered tools as a local controller turn |
| Observer | An independent Pi session | TSPi's allowlisted read and inspection tools |

## Requirements

- Node.js 22.19 or newer and npm for the broker
- Flutter 3.44 or newer with Dart `>=3.12.0 <4.0.0` for mobile development
- A compatible TSPi installation; source version 0.12.0 uses Bridge v3
- An HTTPS origin reachable from the phone for remote use

The broker listens only on `127.0.0.1` or `::1`. A reverse proxy must terminate
TLS because the mobile app rejects plain HTTP for non-loopback addresses.
Stopping generation is fenced by both the current session revision and the
exact Bridge-issued agent run ID, so a delayed phone request cannot stop a
newer run.

## Run from source

Install dependencies and start the broker from the repository root:

```bash
git clone https://github.com/iawnix/ts-phone.git
cd ts-phone
npm ci

export TS_PHONE_WORKSPACES=/absolute/path/to/tspi/workspaces
export TS_PHONE_STATE_DIR=/absolute/path/to/ts-phone-dev/state
export TS_PHONE_BRIDGE_SOCKET=/absolute/path/to/ts-phone-dev/run/bridge.sock
export TS_PHONE_BRIDGE_SECRET_FILE=/absolute/path/to/ts-phone-dev/state/bridge.secret
npm run dev
```

These paths must be absolute, and `TS_PHONE_WORKSPACES` must already be a real,
non-symlink directory. First startup creates separate API and Bridge credentials
at the configured paths with owner-only permissions.

In another terminal, check the service and read the API token locally:

```bash
curl http://127.0.0.1:22113/healthz
TS_PHONE_STATE_DIR=/absolute/path/to/ts-phone-dev/state npm run ctl -- token
```

Start a phone-enabled TSPi session with the same Bridge socket and secret:

```bash
TS_PHONE_BRIDGE_SOCKET=/absolute/path/to/ts-phone-dev/run/bridge.sock \
TS_PHONE_BRIDGE_SECRET_FILE=/absolute/path/to/ts-phone-dev/state/bridge.secret \
  /path/to/tspi/TSPi --workspace WORKSPACE --phone
```

Run the broker and TSPi as the same Unix user so both can access the protected
socket and secret.

Run the mobile app on a connected development device:

```bash
cd apps/mobile
flutter pub get
flutter devices
flutter run -d DEVICE_ID
```

This starts the client UI. Completing an end-to-end connection also requires an
HTTPS origin reachable from the device. Enter that origin and the API token in
the app; the broker stays on loopback, as described in the
[deployment guide](docs/deployment.md).

Production installation uses the TSPi Package, which ships compatible versions
of the research runtime, broker, Web explorer, and Android app.

## Development checks

Run the broker checks from the repository root:

```bash
npm run typecheck
npm test
npm run test:release
npm run build
TS_PHONE_SMOKE_PORT=23113 npm run smoke
```

Run the mobile checks from `apps/mobile`:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Android signing and component packaging are maintainer workflows documented in
[Build artifacts](docs/artifacts.md).

## Security

Treat the API token as remote controller access. It can read session history
and submit prompts. In controller mode, phone turns have the same registered
tool authority as local controller turns. Use an observer for read-only tools.

The projection drops thinking and raw provider records, but it is not a secret
redaction layer. Visible text, tool arguments, and tool results can still
contain sensitive information. Do not put credentials in conversations,
screenshots, logs, or source control.

Read the [security model](docs/security.md) before making the service reachable
from another device.

## Platform status

| Component | Current status |
| --- | --- |
| Broker | 0.6.0; API v4, Events v3, Bridge v3 |
| Android | App 0.13.0+37; verified production-signed release; Android 7.0 or newer |
| TSPi compatibility | TSPi 0.12.0; API v4 and Bridge v3 |
| iOS | Flutter source is included; no IPA is produced on Linux. Building requires macOS and Apple signing. |

## Documentation

- [Architecture](docs/architecture.md): ownership, sessions, synchronization, and recovery boundaries
- [Security](docs/security.md): trust model, credentials, projection, and remote-control risks
- [Deployment](docs/deployment.md): TSPi Package integration, service activation, HTTPS, and rollback
- [Recovery](docs/recovery.md): reconnects, offline history, and ambiguous commands
- [Build artifacts](docs/artifacts.md): Android releases and component archives

## License

This repository does not currently include a license. Until one is added,
normal copyright restrictions apply.
