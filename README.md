# TS Phone

TS Phone is the Flutter client for a TSPi Pi App Server Host. It does not
contain a shared Host, worker supervisor, REST API, SSE broker, or local
bridge. One Host owns the installed workspace directory; the App Server is the
single owner of sessions, transcript history, model state, and workspace locks.

## Runtime model

```text
TS Phone -- outbound WSS --> TSPi Relay <-- outbound WSS -- TSPi Host
                                                        |
                                                  Pi App Server
                                                        |
                                           workspace / local terminal
```

Open a workspace with the TSPi launcher; it starts the installation Host when
needed:

```bash
./TSPi --workspace reaction-a
```

Run `TSPi phone pair` on that installation, then enter the printed TSPi Relay
URL and eight-character code in the app. The app redeems the one-time code for
its own revocable device authorization. It carries Pi protocol v8 over the
`tspi-link.v1` WebSocket subprotocol, lists projects through
`tspi.workspace-directory`, and creates sessions with a bound `workspaceId`.

## Repository layout

- `apps/mobile` — Flutter Android/iOS application.
- `apps/mobile/lib/data/tspi_link_pairing.dart` — one-time device pairing.
- `apps/mobile/lib/data/pi_app_server_client.dart` — TSPi Link transport, Pi v8 framing, and Chord
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

The device token is used only for the TSPi Link WebSocket and is stored by the
mobile platform's secure storage. It is never shown in the connection UI. App
Server session state remains on the server workspace; the phone keeps only UI
preferences and a recent session selection.

See [docs/architecture.md](docs/architecture.md) for the protocol and
ownership details and [docs/deployment.md](docs/deployment.md) for Android
release operations.
