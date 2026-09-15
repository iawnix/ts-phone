# Deployment

TS Phone is deployed as a signed Flutter application. The runtime it connects
to is the Pi App Server shipped by TSPi; this repository has no server daemon
to install or expose.

## Pi App Server prerequisites

On the machine that owns a research workspace, install TSPi and start one App
Server for that workspace:

```bash
./TSPi --app-server --workspace reaction-a
```

The App Server's UUID is stored in
`workspaces/reaction-a/.pi/app-server/server-id`. Configure Pi Radius to relay
that server and issue a bearer token with access to the relay. The App Server
must be reachable by the Radius service; the local terminal uses its private
Unix socket and never needs a public HTTP port.

## Android build

Create or provision the release keystore in the private signing directory,
then run:

```bash
TS_PHONE_SIGNING_DIR=/secure/ts-phone-signing \
  apps/mobile/tool/build_release_android.sh
```

The script captures the Git source, embeds its snapshot in each APK/AAB,
builds split APKs and an app bundle, verifies package/version/ABI metadata and
the pinned certificate, and publishes a content-addressed set below
`dist/android-current`. Use `--allow-dirty` only for a local candidate.

The CI workflow `.github/workflows/android-release.yml` performs the same
checks for a `ts-phone-v<version>+<build>` tag and uploads only Android
artifacts to the GitHub release. No Node dependencies, server archive, systemd
unit, reverse proxy, or FRP configuration is involved.

## Mobile configuration

At first launch the user supplies:

- the Radius origin (`https://...`);
- the App Server UUID (lowercase UUIDv4);
- the Radius bearer token.

The app stores these values in platform secure storage. It derives the relay
WebSocket URL and sends the token as an Authorization header. Changing any of
the three values creates a new client connection; the old connection is
closed before the new session directory is loaded.

## Updates and rollback

Android releases are immutable. Install a previous APK/AAB from the GitHub
release if a rollback is required. App Server sessions and workspace data are
not part of the mobile artifact and are unaffected by an app update.
