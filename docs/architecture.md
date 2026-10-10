# Architecture

CoRHub is a presentation client of `coragent-host/2`. Pi sessions own their execution, conversation and durable history. Host owns workspace routing,
session discovery and routing to the native Pi Harness worker. Task monitoring
belongs to the server and continues independently of the phone screen.

```text
CoRHub -> Relay -> Host -> Pi Harness worker -> durable Pi session
                       +-> workspace task monitors
```

## Transport and requests

The existing pairing flow provides a revocable device token. The phone connects
to `wss://<relay>/v1/link` with `Authorization: Bearer <device-token>` and the
`coragent-link.v1` subprotocol. WebSocket binary messages carry UTF-8 NDJSON, without
CBOR, length prefixes, Chord service patches or Pi protocol-v8 handshakes.
The decoder handles split UTF-8 characters and multiple lines per frame.

```json
{"id":"phone-1","method":"initialize","params":{"protocol":"coragent-host/2"}}
{"id":"phone-1","result":{"protocol":"coragent-host/2","epoch":"host-epoch","capabilities":[]}}
{"id":"phone-2","method":"session/attach","params":{"workspace_id":"ts_001","session_id":"session-1"}}
```

Responses contain `id` and either `result` or `error:{code,message,retryable}`.
Notifications contain `method` and `params`. `workspace/list` / `workspace/create`
manage projects. `session/list`, `session/create`, `session/resume`,
`session/read`, `session/attach`, and `session/remove` use explicit workspace
identity. Models use `models/list` and `model/select`. All app entry points use `HostGateway`. The retired Pi protocol-v8 adapter,
phone approvals and structured branch/activity timelines have been removed.

## State and reconnection

`session/read` and `session/attach` return `{session,snapshot,cursor:{epoch,sequence}}`.
`session/event` carries workspace/session identity plus the same snapshot and
cursor. A client buffers early events while attach is in flight,
applies the returned snapshot, then applies only later events from that epoch.
Events for other workspace/session pairs are ignored. The current design does
not claim a durable delta replay cursor.

A broken connection fails pending requests and causes the existing chat
controller to reconnect. A new `initialize` and `session/attach` obtain fresh
state. Session revision tracks workspace/session identity, so a Host epoch
change does not discard an uncertain outbox receipt. Read-only and offline
state disable input. Opening an offline writable session explicitly requests
resume; a live session is reused.

## Input and controls

`input/send` includes `workspace_id`, `session_id`, `request_id`,
`client_message_id`, `text`, `mode:"auto"`, and `source:"phone"`. Host/Pi chooses
whether to start immediately or queue behind current work. The transport never
retries a mutation automatically. A user retry retains the same outbox message
ID, including after an uncertain response; Host must deduplicate it. Snapshot
receipts may associate an observed user message index with its client ID.

`turn/interrupt` includes the active turn ID. Model choice is session-scoped and sends `model:{provider,id}`.
Pi extension dialogs remain in the terminal. The phone renders Host transcript
messages and tool output; it has no approval UI or branch timeline.
Streaming Markdown updates are throttled and bounded to a 6,000-character
preview; the completed reply remains available in full.

Home keeps a stable place below chat in the navigation stack. A project picker,
searchable lazy session list and task monitors share the selected workspace.
Important session notices and the composer sit outside the scrolling transcript.

## Monitors

`monitor/list` returns registrations with `monitor_id`, enabled state, task
observation state and delivery status. The project monitor page displays these
values and calls `monitor/enable` / `monitor/disable` with workspace and monitor
identity. Registrations are created by computation submission on the server.
Pausing monitoring does not cancel the computation. Refresh and app foreground
entry read current state; no phone timer executes monitoring jobs.

## Ownership

The phone stores connection credentials in platform secure storage and retains
UI preferences and an in-memory outbox. It does not own a second session
database, provider login, agent loop, workspace registry or monitor scheduler.
