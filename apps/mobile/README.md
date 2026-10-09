# TS Phone Mobile

Flutter client for Android and iOS. The app stores its Bearer token in Android
Keystore-backed secure storage or the iOS Keychain. It connects to a ResearchAgent Link
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

## Develop and release

Use the repository [development guide](../../docs/development.md),
[version policy](../../docs/versioning.md), and
[release operations](../../docs/deployment.md). The repository root README is
the installation entry point. Tests run from private source snapshots.

Android releases use the existing production certificate and package identity;
never generate a replacement key for production. GitHub publishes APKs for
three ABIs plus the AAB, attestations and SHA-256 checksums. A debug installation
has a different signer and must be removed before installing a production APK.
Uninstalling deletes its local settings and token.

iOS requires a macOS signing environment and is not a published binary target.
