# TS Phone

TS Phone is the Flutter client for a Pi App Server. It does not contain a
shared Host, worker supervisor, REST API, SSE broker, or local bridge. A Pi App
Server is the single owner of sessions, transcript history, model state, and
the workspace lock.

## Runtime model

```text
                         Pi Radius
                             |
                         WebSocket
                             |
TS Phone (Flutter) ---- Pi App Server ---- local TSPi terminal
                             |
                         workspace
```

Run one App Server for each workspace with the TSPi launcher:

```bash
./TSPi --app-server --workspace reaction-a
```

The local terminal attaches to that server automatically:

```bash
./TSPi --workspace reaction-a
```

The phone connects to the same server through Pi Radius. Configure the Radius
gateway, the App Server UUID, and the bearer token in the app's connection
screen. The phone speaks Pi protocol v8 over the
`pi-session-relay.client.v1` WebSocket subprotocol; it does not talk to a
TS Phone service.

## Repository layout

- `apps/mobile` — Flutter Android/iOS application.
- `apps/mobile/lib/data/pi_app_server_client.dart` — Pi v8 framing and Chord
  service client.
- `apps/mobile/lib/data/app_server_gateway.dart` — native session and
  transcript projection used by the UI.
- `apps/mobile/tool/build_release_android.sh` — signed APK/AAB build with
  source attestations.
- `apps/mobile/tool/mobile-build-attestation.py` — reproducible source and
  artifact attestation.

There is intentionally no Node server package or TS Phone protocol package in
this repository. The App Server implementation lives in the TSPi package.

## Development

Install Flutter 3.44 (or a compatible stable release), then run:

```bash
cd apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

The root helper runs the same checks:

```bash
./tool/iterate.sh dev
```

`candidate` builds a local arm64 APK and `release` builds the signed Android
release set. Release builds include a source snapshot in every artifact and
publish only Android files under `dist/android-current`.

## Security boundary

The bearer token is used only for the Radius WebSocket. It is stored by the
mobile platform's secure storage and is never sent to a local process. App
Server session state remains on the server workspace; the phone keeps only UI
preferences and a recent session selection.

See [docs/architecture.md](docs/architecture.md) for the protocol and
ownership details and [docs/deployment.md](docs/deployment.md) for Android
release operations.
