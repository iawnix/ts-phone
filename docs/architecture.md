# Architecture

TS Phone is a thin presentation client. The TSPi Host owns one Pi App Server
for the installation and exposes all validated workspaces below its workspace
root. The phone never becomes a session owner.

## Ownership

The App Server owns:

- the session directory and session creation/removal;
- Pi JSONL transcript history and live agent state;
- prompt, follow-up, abort, and model-selection operations;
- the workspace directory, Root locks, and the App Server identity;
- the local Unix-socket endpoint used by TSPi clients and the Link connector.

TS Phone owns only connection settings, presentation state, and a recent
session preference. It does not maintain a second event journal, queue,
workspace registry, or transcript database.

## Transports

The local TSPi terminal and TS Phone use the same Pi App Server protocol:

```text
TSPi terminal -- Unix socket --> App Server <-- Unix socket -- Link connector
                                                              |
                                                       outbound WSS
                                                              |
TS Phone ---------- outbound WSS ----------> TSPi Relay <-----+
```

The phone connects to:

```text
wss://<relay>/v1/link
```

with `Authorization: Bearer <device-token>` and the `tspi-link.v1`
subprotocol. The Relay uses the token to route the connection to its enrolled
Host and forwards bytes without parsing the App Server protocol. Frames contain a four-byte
big-endian length followed by a CBOR value. The first value is the Pi protocol
v8 `hello` message. Requests and responses use Pi's native service catalog;
Chord subscriptions carry transcript, model, and session-directory state.

## Session lifecycle

1. TSPi starts the installation Host and creates its stable UUID under
   `.pi/app-server-host/server-id`.
2. The Host publishes `tspi.workspace-directory`; the phone lists projects or
   creates one through its `list`/`create` members.
3. The phone creates a Pi session through `pi.session-management.create` with
   a `workspaceId`; the Host resolves and validates the workspace cwd.
4. The App Server opens or restores Pi sessions below its private session
   directory and publishes `pi.session-directory`.
5. A terminal or phone attaches a session with
   `pi.session-management.attach`.
6. The client subscribes to `pi.transcript`, renders the snapshot, and applies
   ordered Chord updates.
7. Prompt, follow-up, abort, and model changes are sent to
   `pi.agent-controller` or `pi.models` for that attached session.
8. Detaching a client does not stop the App Server or delete its history.

There is no activation mode, controller/observer split, phone worker, or
shared Host process. Concurrency is enforced by the App Server's workspace
lock and by Pi's session operations.

## Failure handling

The client treats a closed Link channel as a transport failure. A later
operation creates a fresh connection and repeats `hello`; pending requests are
failed and subscriptions are rebuilt from a new snapshot. The client never
replays a prompt automatically, so an uncertain user message remains visible
for review.

An invalid Host UUID, device authorization, frame, or protocol version is reported as an
incompatible connection. A server-side rejection is surfaced with its native
error code. History already rendered on the phone remains available offline,
but write controls stay disabled until a fresh transcript snapshot is received.

## Extensibility

Scientific skills are loaded by the TSPi App Server's native Worker. The native
Worker exposes guarded TSPi tools directly; optional Pi workflow extensions are
not injected in this mode. TS Phone never injects prompts or extensions and
does not need to know which skills are installed. The `sys_prompt` inspection
tool is therefore an App Server capability, not a mobile-side compatibility
API.
