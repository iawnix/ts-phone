# TS Phone Mobile

Flutter client for Android and iOS. The app stores its Bearer token in Android
Keystore-backed secure storage or the iOS Keychain. It connects directly to a
Pi native App Server through the Radius session-relay WebSocket protocol,
rejects remote plain HTTP, and never starts or embeds a TS Phone server.

## Conversations

Cold start opens the single configured App Server's session directory. The
server owns durable sessions, transcripts, model configuration, and the Root
Agent; the phone keeps only connection settings, UI state, and the last selected
session. Creating, attaching, removing, prompting, following up, aborting, and
selecting a model all call Pi native services over the same connection.

Opening history never starts a second worker. A session is ready when the App
Server reports a live attachment. Draft text stays local until a prompt is
accepted by that attached session, and a lost connection is surfaced as an
uncertain result rather than silently retried.

The chat header contains Back, a bounded session title, App Server status and
More. Running activity stays in the transcript, not above the keyboard.

The composer shows the current model and a picker above the system keyboard.
The picker reads the native `pi.models` catalog and selection is sent to the
attached Session; credentials never leave the App Server. A request already
running keeps the model it started with and remains visible in the replicated
transcript. Pi's `AgentController` is the only prompt/abort authority; there is
no phone-side queue, approval broker, REST API, SSE stream, or bridge protocol.

The App Server publishes a complete active transcript through `pi.transcript`.
The client keeps a bounded in-memory display cache for drafts and scroll
positions and discards it when the connection identity changes. Only the last
selected session identifier is saved in secure storage. Backgrounding the app
retains the current screen and draft, while reconnecting explicitly reattaches
to the selected Session.

Unnamed sessions use their first user question when available, otherwise a date
or untitled label. Technical IDs remain in details. Transcript entries are
rendered as published by Pi; failed and stopped generations remain distinct.
The phone never deletes transcript records.

## Validate

```bash
/home/iaw/soft/flutter/bin/flutter pub get
/home/iaw/soft/flutter/bin/flutter analyze
/home/iaw/soft/flutter/bin/flutter test
```

The conversation UI tests cover English/Chinese, light/dark, phone/tablet,
2x text, keyboard insets, home navigation, creation and retained drafts. To
capture their rendered fixtures, set `TS_PHONE_CAPTURE_UI=1`,
`TS_PHONE_PREVIEW_FONT` to a CJK font file and `TS_PHONE_PREVIEW_ICONS` to the
Flutter SDK's `MaterialIcons-Regular.otf`, then run
`flutter test test/conversation_shell_test.dart`. PNGs are written under
`build/conversation-previews/`. These are fixture screenshots, not a claim of
verification on a physical phone.

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
