# Architecture

TS Phone separates scientific state, conversation history, and transport state:

1. The TSPi workspace owns scientific research state.
2. Each Pi session JSONL owns its conversation history.
3. TS Phone owns authentication, live bridge registration, bounded event
   journals, command fencing, and transient recovery state.
4. TS Phone `management.json` owns display names, model/access preferences, and
   project/session lifecycle state. It contains neither scientific records nor
   conversation messages.

The phone API has no field for an arbitrary filesystem path, process command,
environment override, or raw Pi RPC record. Natural-language messages can still
contain sensitive or operational text. When `TS_PHONE_TSPI` is configured, the
Host starts and stops only the fixed TSPi Worker entrypoint. That launcher owns
workspace bootstrap, the Root Agent lock, Pi RPC mode, and the package-owned
ts-phone-bridge extension.

~~~text
Flutter -> HTTPS/SSE -> TS Phone Host -> WorkerSupervisor -> TSPi/Pi
                                  \---- Unix socket <---- Bridge
~~~

## Release Ownership

TS Phone owns its source, server/mobile versions, protocol schemas, tests, and
`ts-phone-component-release/2` builder. Android releases are built from a
private source capture; the signed APK embeds that source snapshot, and a
sidecar attestation binds the snapshot, version, build, ABI, filename, size,
and digest. The component builder parses the protocol documents and verifies
their version identities, lifecycle payload closure, event bindings, running
snapshot identity, and fenced Abort contract. The component archive contains
the built broker, control entrypoint, those validated protocol documents,
operational references, attestation, and one production-signed arm64 APK. It
does not select a live TSPi release.

TSPi owns the complete `tspi-package-release/2` assembly and install
transaction. `ts_web` remains embedded in its Agent component because it reads
the research kernel's workspace projection. The suite manifest freezes the
Agent component, Phone component, Web contract, server entry, signed APK, and
protocol versions into one compatible set. TSPi independently verifies the
APK signature, pinned certificate, package metadata, embedded source snapshot,
and attestation rather than trusting producer fields. One suite `current`
pointer backs all four installed launchers.

Configuration, Bearer tokens, bridge secrets, Pi sessions, research
workspaces, service units, and process state are installation-owned and remain
outside immutable releases. Package installation selects content but never
starts a service or installs an APK onto a device.

## Workspace And Session Ownership

`management.json` is an owner-only, atomically replaced Host document. A
managed project records its display name, lifecycle state, revision, timestamps,
and managed sessions. A managed session records its display name, optional model
preference, access mode, lifecycle state, revision, and timestamps. Numeric
workspace/session IDs remain routing identities; renaming never changes a
filesystem path or Pi session identity.

Both reads and writes enforce a 1 MiB UTF-8 limit. An over-capacity change fails
before creating a temporary file and preserves the previous disk and memory
snapshot.

The lifecycle is `active`, `archived`, or `trashed`. `sessionCount` and
`liveSessionCount` include only active sessions, using the same lifecycle
filter as the ordinary session list. Archive, trash, and restore update these
counts at the Host. Recently Deleted has no background expiry: data remains
until explicit restoration or permanent deletion. Session deletion quarantines
only its validated Pi JSONL. Project
deletion quarantines the complete workspace and first runs TSPi's read-only
scientific preflight. Active Workers, remote calculations, pending approvals,
unresolved remote effects, or unverifiable operational state block deletion.
This includes a manually started Root Agent that has never connected a Bridge.
The Host verifies the absolute workspace path in the private TSPi reply.

Before moving a project to Recently Deleted or purging project/session files,
the Host opens `--lifecycle-guard`. TSPi acquires the same Root Agent lock used
by interactive launches, reports a bounded preflight, and holds the lock until
Host stdin closes. The Host blocks new Bridge registration during that
operation and checks guard liveness before filesystem/metadata changes. Idle
Host-owned Workers can be stopped; external Controllers are never stopped by
these actions. The ordinary preflight endpoint is read-only and never reserves
the workspace. Both operations require `TS_PHONE_TSPI` to be configured.

Permanent deletion spans the Host metadata file and filesystem, so it cannot be
a single filesystem transaction. The Host serializes mutations, renames the
target to a same-filesystem quarantine, removes its management record, and only
then deletes the quarantine. If deletion fails, it attempts to restore the
remaining target and exact prior management snapshot. Recursive removal can
already have removed files, so a failed purge requires inspection before retry.
Incomplete compensation is surfaced as
`purge_recovery_failed` and requires operator inspection; it is never reported
as a successful deletion.

A workspace record owns a map keyed by sessionId. Every session record has its
own optional persisted-history reference, optional bridge connection, snapshot,
event journal, prompt deduplication map, approval set, runtime state, and
session revision.

~~~text
WorkspaceRecord
└── sessions[sessionId]
    ├── accessMode: controller | observer
    ├── PersistedSession
    ├── BridgeConnection
    ├── SessionSnapshot
    ├── EventJournal
    ├── prompt deduplication
    ├── approvals
    └── runtime state
~~~

Exactly one live controller is allowed per workspace. A Host-started controller
acquires the Root Agent file lock and opens the requested Pi session ID in RPC
mode. A requested observer never acquires that write lock. Manually invoked
`TSPi --phone` retains the lock-contention fallback to an independent observer.

Observers are not passive mirrors. They can receive phone or local prompts and
use a strict read-only tool allowlist. They cannot modify the scientific
workspace, submit computation, render, report, notify, or invoke shell. This
allows parallel inspection while keeping a single writer.

## Identity And Fencing

The session routing identity is:

~~~text
workspaceId + sessionId + sessionRevision
~~~

Abort adds a Bridge-issued `agentRunId`. The broker exposes it as
`activeAgentRunId` in session and snapshot state, requires the phone to return
the exact value, and forwards the same value unchanged to the Bridge. The
Bridge compares it again immediately before calling Pi's abort operation. This
second fence prevents a delayed request for a completed run from stopping its
successor in the same session revision.

The local bridge additionally binds instanceEpoch and sessionGeneration. Bridge
events carry a monotonically increasing sequence. The broker rejects:

- a second live connection for the same sessionId;
- a second live controller for the same workspace;
- records whose workspace, session, instance, generation, or sequence changed;
- prompt, abort, or approval commands with a stale sessionRevision;
- abort commands while idle or for a different active agent run.

A bridge reconnect resets that session journal and creates a new revision.
Mobile clients stop applying the old stream, fetch an authoritative snapshot,
and reconnect using the new checkpoint before enabling input again.

## Synchronization

### Prompt Readiness And Receipts

A connected socket is not model readiness. Session summaries and snapshot/state
events expose `promptProblem` when the model is unavailable, its authentication
is unconfigured, or the local model check fails. These states omit
`command.prompt` and reject message submission with a model-specific 409, not a
Phone-token authentication error. No provider key or raw error body is exposed.

For Host-owned Workers, prompt dispatch uses the private Pi RPC stdin/stdout
transport. Only the response with the matching request ID and `command=prompt`
acknowledges preflight. Native `input` precedes preflight and is not a delivery
receipt. After success the Host publishes one correlated phone input with
`preflightAccepted=true` and the original `clientMessageId`. Retries with that
same ID reuse the command result. Timeouts/disconnects remain ambiguous and
never trigger automatic resend. Worker extension errors are consumed and
published as safe `runtime.error` codes instead of discarded stdout.

Manually started TUI sessions retain the extension bridge command path, whose
acknowledgement means dispatch, not completed preflight. The Bridge checks model
readiness before dispatch; clients do not treat its early input event as proof
that a later failed request succeeded. Assistant failure/abort state survives
message projection without exposing provider error bodies.

Every session has an independent bounded event journal. SSE reconnects replay
events after Last-Event-ID. Slow clients are disconnected before unbounded
buffer growth and can recover from the session snapshot.

Pi session JSONL remains authoritative. At reconciliation time, validated disk
sessions are added to the broker map even without a Bridge. The compatible
`/messages` endpoint returns conversation-only pages. A capability-advertised
`/timeline` endpoint projects the same validated branch into messages plus
bounded research activities, Turn ownership, branch summaries, and aggregate
counts. Neither endpoint creates or updates a second conversation store.

Each response page returns at most 500 projected items and six MiB. Stable Pi
entry IDs form an opaque `before` cursor, so the phone can prepend older pages
without receiving raw JSONL. With `history.seek`, `edge=start` selects the first
page of the requested branch; `after` pages forward. These three position
parameters are mutually exclusive. `hasMore`/`nextBefore` describe earlier
content; `hasLater`/`nextAfter` describe later content. Limits apply in both
directions, including the first page. An omitted position selects the tail.
The phone requests the latest 50 items before
connecting the event stream. Earlier pages load only on demand; explicit
load-all remains available. Page size is client policy, while pagination and
byte limits remain server-enforced mechanism.

Jump to start replaces the visible window with one first-page request, not a
download of the whole session. Later pages load explicitly. Live content never
fills gaps in that history window or takes over its scroll position. Jump to
latest reads a fresh tail checkpoint before resuming live following. Failed
navigation retains the previous window; an in-flight result for an obsolete
session revision cannot replace it.

Prepending history preserves the visible message position. The page uses the
list's extent for the initial offset and corrects it against the same rendered
message, so lazy layout estimates do not shift the text being read. Assistant
failure and abortion records remain visible even when their text is empty.

The registry caches parsed session graphs for up to eight files and 32 MiB of
source data. Every lookup opens the file with the existing safety checks and
matches device, inode, size, modification time and change time. Rewrites,
appends, replacements and removal invalidate the cached graph; pages still use
the requested branch and stable entry cursor. The cache is not durable storage.

Cold start reads project and session summaries without selecting a conversation
or requesting its messages. Home retains at most five recent rows and limits
summary request concurrency to three. Selecting a project always opens its
list; selecting a conversation is the only entry into its history.

The registry derives unnamed session titles from user text in the first 64 KiB
of a session file, capped at 80 Unicode code points. Explicit management and
live session names take priority. Assistant, tool, image and reasoning content
are excluded. This is a list label, not an active-branch summary. Titles fall
back to dates on the client when no bounded preview is available. Up to 256
previews are cached with the same stat-version checks as the graph cache; a
file's modification time supplies the history list's update time.

The conversation shell owns project/session selection, not Pi activation.
Reading a conversation never boots a Worker. Activation is an explicit action
inside the conversation, independent of history rendering. The app saves only
the last selection identifiers in secure storage. Recent display previews and
drafts remain in an eight-entry in-memory cache scoped to connection, workspace
and session. Previews are revision-bound and limited to 1000 combined display
items and 512 Ki characters per view. A preview cannot enable send or abort;
fresh snapshots and event-stream identity remain the authority.

Message projection preserves an optional display-only `outputState` for empty,
not-displayed, failed and aborted assistant output. It does not expose raw
provider errors or private reasoning. The UI groups consecutive activity-only
records within a turn, preserving order, failure visibility and expansion back
to each record. Stopped output is not relabeled as failed. These presentation
choices do not change Pi JSONL, evidence or scientific state.

The last appended Pi leaf is the active branch. Other leaves remain selectable
for audit, but a timeline response for an inactive branch omits prompt and abort
capabilities. The Flutter client consequently treats that view as read-only.
Live event messages are temporary UI entries; once equivalent stable JSONL
entries appear, the client reconciles them one-for-one instead of showing both.
Completed live messages advance the snapshot checkpoint before agent
settlement, so a long tool turn does not make already completed output
disappear.

Workspace and session listing also reconciles transient broker state with that
authoritative storage. A workspace missing from the configured root is removed
with all of its broker records. A disconnected session is removed only when a
complete, structured scan confirms that its Pi session header is absent. Live
connections are never removed by this scan, and unreadable or malformed history
causes reconciliation to fail open instead of guessing that data was deleted.

Phone prompts carry clientMessageId. Deduplication is scoped to one session and
bounded in memory. Ambiguous commands are never retried automatically.
