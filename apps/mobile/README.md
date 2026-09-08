# TS Phone Mobile

Flutter client for Android and iOS. The app stores its Bearer token in Android
Keystore-backed secure storage or the iOS Keychain, rejects remote plain HTTP,
and refuses redirects on authenticated HTTP and SSE requests.

## Conversations

Cold start opens a work home with recent conversations and projects. It reads
summary lists only; selecting a project opens its conversation list, even when
there is just one conversation. The sidebar switches conversations in the
current project and returns home. Archive and recently deleted are list menus;
Settings is on the home toolbar. The sidebar stays visible on wide screens.
New conversations use the Host default model and belong to the current
workspace. Advanced creation can select another model explicitly.

Opening history is read-only and does not start a Pi Worker. **Continue
conversation** explicitly activates an offline managed session. Draft text stays
editable while activation is pending; it is never sent automatically. Sending
and stopping still require a current server-confirmed session and event stream.

The chat header contains Back, a bounded title, workspace/status and More.
Tap the title for the full name, rename and runtime details. More contains
the sidebar, message synchronization and jump-to-start; new conversations live
in the sidebar/list. Running activity stays in the timeline, not above the keyboard.

The composer shows the current model and a picker above the system keyboard.
Only idle Host-managed Controllers advertise model switching. Changes wait for
Pi's exact receipt, preserve the draft/selection, and never change global Pi
defaults. Pending messages, running work and approvals block switching. A lost
receipt requires state reconciliation before sending; the app does not retry
the change automatically. External CLI sessions show their model without a
working switch control. The picker reads the Host's available-model catalog;
credentials remain on the Host. Advanced creation uses the same picker.

History starts with the latest 50 items. Earlier pages load on demand, with the
existing explicit load-all action available for an audit. A bounded in-memory
display cache preserves recently viewed history, drafts and scroll positions
within the app; it is discarded when the connection identity changes. Only the
last selected project/session identifiers are saved in secure storage.
The last selection ranks first on home but is never opened automatically.
Briefly backgrounding the app retains the current screen and draft.

Unnamed histories use their first user question when a bounded server preview
is available, otherwise a date or an untitled label. Technical IDs remain in
details. Consecutive activity-only records fold into an expandable summary;
failed and stopped generation remain visible and distinct. Empty assistant
records no longer render a logo-only reply. No history records are deleted.

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
