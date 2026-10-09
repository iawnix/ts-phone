# TS Phone Mobile

Flutter client for Android and iOS. The app stores its Bearer token in Android
Keystore-backed secure storage or the iOS Keychain. It connects to a TSPi
Relay with `research-agent-link.v1`; the Relay forwards the `research-agent-host/2` NDJSON byte
stream to the outbound-connected Host. The app rejects remote plain HTTP and
never starts or embeds a TS Phone server.

## Conversations

Cold start opens a searchable conversation list with a project picker. Pi owns durable
sessions, transcripts and execution; Host routes session operations by workspace
and session ID. The phone keeps connection settings, UI state, and the last
selected session. `HostGateway` maps the public JSON RPC to existing chat views.

Opening an offline writable session requests `session/resume`; an existing
live session is attached, while older read-only history remains read-only.
Draft text stays local until input is accepted. A lost response remains
uncertain; manual retry uses the same `client_message_id` for Host deduplication.

The chat header contains Back, a bounded session title, session details, status
and local transcript navigation. Tool output remains in the transcript.
Status and composer notices explain disconnection without hiding the draft.

The composer shows the current model and a picker above the system keyboard.
The picker calls `models/list` and `model/select` for the selected session.
Provider credentials stay on the Host. Input and interrupt requests are handed
to Pi through its native Harness worker.

The Host returns complete snapshots through `session/read` and `session/attach`,
then publishes `session/event` notifications. Reconnection always reattaches;
event IDs do not promise historical delta replay.
The client keeps a bounded in-memory display cache for drafts and scroll
positions and discards it when the connection identity changes. Only the last
selected session identifier is saved in secure storage. Backgrounding the app
retains the current screen and draft, while reconnecting explicitly reattaches
to the selected Session.

Unnamed sessions use their first user question when available, otherwise a date
or untitled label. Technical IDs remain in details. Transcript entries are
rendered as published by Pi; failed and stopped generations remain distinct.
Deleting a session permanently removes it and its history; confirmation explicitly
states that it cannot be undone.

The home project selector and session sidebar include task monitors. The monitor page
shows calculation status and pending delivery count, refreshes on app resume,
and uses `monitor/enable` / `monitor/disable` to control existing registrations.

## Validate

```bash
/home/iaw/soft/flutter/bin/flutter pub get
/home/iaw/soft/flutter/bin/flutter analyze
/home/iaw/soft/flutter/bin/flutter test
```

The conversation UI tests cover English/Chinese, light/dark, phone/tablet,
2x text, keyboard insets, home navigation, creation and retained drafts. These tests render fixtures; they do not replace verification on a physical phone.

## Build Android

```bash
tool/setup_release_signing.sh
tool/build_release_android.sh
```

The signing setup is idempotent. It stores the private keystore and password
outside the repository under `/home/iaw/.config/ts-phone/android-signing/`.
Back up both files together; losing them prevents future in-place updates of the
production app.

The release builder produces one APK per supported ABI plus a Play-compatible
AAB as one content-addressed set under `dist/android-releases/`, then atomically
switches `dist/android-current`. It verifies archive identity, APK v2
signatures and metadata, the AAB signature, and the single signer fingerprint.
Use the `arm64-v8a` APK for current
64-bit Android phones. Do not produce or distribute a separate debug APK.

An existing debug/profile installation uses a different signer and cannot be
updated in place. Uninstall it before the first release installation; Android
will delete that installation's local token and settings.

iOS source and AppIcon assets are included, but an installable iOS archive must
be built and signed on macOS with an Apple development team and provisioning
profile.
