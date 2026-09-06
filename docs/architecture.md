# Architecture

TS Phone separates scientific state, conversation history, and transport state:

1. The TSPi workspace owns scientific research state.
2. Each Pi session JSONL owns its conversation history.
3. TS Phone owns authentication, live bridge registration, bounded event
   journals, command fencing, and transient recovery state.

The phone API has no dedicated field for a filesystem path, process command,
environment override, or raw Pi RPC record. Natural-language messages can still
contain sensitive or operational text. The server never starts Pi. The TSPi
launcher starts each visible Pi process and loads the package-owned
ts-phone-bridge extension.

~~~text
Flutter -> HTTPS/SSE -> TS Phone broker -> Unix socket -> visible TSPi/Pi
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

Exactly one live controller is allowed per workspace. The controller holds the
Root Agent file lock and starts Pi with continue, preserving the canonical
working session. If a phone launch finds that lock held, it starts a new Pi
session without continue and registers as an observer.

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
without receiving raw JSONL. Histories with at most 2000 timeline items load
automatically; larger histories expose progress and explicit one-page or
load-all actions. The threshold is client policy, while pagination and byte
limits remain server-enforced mechanism.

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
