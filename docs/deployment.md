# Deployment

TS Phone is deployed as a signed Flutter application. The runtime it connects
to is the Pi App Server shipped by TSPi; this repository has no server daemon
to install or expose.

## Pi App Server prerequisites

On the machine that owns the TSPi installation, enable TSPi Link during
installation and start the installation Host by opening a workspace:

```bash
./TSPi --workspace reaction-a
```

The Host ID and Link credential are stored below `.pi/app-server-host/`. The
Host opens an outbound WSS connection to the configured TSPi Relay; the App
Server remains on its private Unix socket and needs no public HTTP port.

Create a Phone pairing on the Host:

```bash
./TSPi phone pair
```

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

- the TSPi Relay origin (`https://...`);
- the eight-character, single-use pairing code;
- a device name shown by `TSPi phone devices`.

The app redeems the code for a Host ID, Device ID, and device token, then stores
them in platform secure storage. Re-pairing replaces that connection identity;
revoke an old identity with `TSPi phone revoke <device-id>`.

## Updates and rollback

Android releases are immutable. Install a previous APK/AAB from the GitHub
release if a rollback is required. App Server sessions and workspace data are
not part of the mobile artifact and are unaffected by an app update.
