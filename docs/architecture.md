# Architecture

TS Phone is a thin presentation client. Pi App Server is the runtime and the
only session owner. There is one App Server process per TSPi workspace.

## Ownership

The App Server owns:

- the session directory and session creation/removal;
- Pi JSONL transcript history and live agent state;
- prompt, follow-up, abort, and model-selection operations;
- the workspace Root lock and the App Server identity;
- local Unix-socket and Radius relay endpoints.

TS Phone owns only connection settings, presentation state, and a recent
session preference. It does not maintain a second event journal, queue,
workspace registry, or transcript database.

## Transports

The local TSPi terminal and TS Phone use the same Pi App Server protocol:

```text
TSPi terminal -- Unix socket --> App Server <-- Pi Radius WebSocket -- TS Phone
```

The phone connects to:

```text
wss://<radius>/v1/session-relays/<server-id>/connect
```

with `Authorization: Bearer <token>` and the
`pi-session-relay.client.v1` subprotocol. Frames contain a four-byte
big-endian length followed by a CBOR value. The first value is the Pi protocol
v8 `hello` message. Requests and responses use Pi's native service catalog;
Chord subscriptions carry transcript, model, and session-directory state.

## Session lifecycle

1. TSPi starts the App Server with a workspace path and creates its stable UUID
   under `.pi/app-server/server-id`.
2. The App Server opens or creates Pi sessions below its private session
   directory and publishes `pi.session-directory`.
3. A terminal or phone attaches a session with
   `pi.session-management.attach`.
4. The client subscribes to `pi.transcript`, renders the snapshot, and applies
   ordered Chord updates.
5. Prompt, follow-up, abort, and model changes are sent to
   `pi.agent-controller` or `pi.models` for that attached session.
6. Detaching a client does not stop the App Server or delete its history.

There is no activation mode, controller/observer split, phone worker, or
shared Host process. Concurrency is enforced by the App Server's workspace
lock and by Pi's session operations.

## Failure handling

The client treats a closed Radius channel as a transport failure. A later
operation creates a fresh connection and repeats `hello`; pending requests are
failed and subscriptions are rebuilt from a new snapshot. The client never
replays a prompt automatically, so an uncertain user message remains visible
for review.

An invalid server UUID, token, frame, or protocol version is reported as an
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
