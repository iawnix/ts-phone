# Architecture

TS Phone is a presentation client of `tspi-host/1`. Ordinary Pi sessions own
their execution, conversation and JSONL history. Host owns workspace routing,
session discovery and the bridge to each running Pi session. Task monitoring
belongs to the server and continues independently of the phone screen.

```text
TS Phone -> Relay -> Host -> Pi session bridge -> ordinary Pi session
                       +-> workspace task monitors
```

## Transport and requests

The existing pairing flow provides a revocable device token. The phone connects
to `wss://<relay>/v1/link` with `Authorization: Bearer <device-token>` and the
`tspi-link.v1` subprotocol. WebSocket binary messages carry UTF-8 NDJSON, without
CBOR, length prefixes, Chord service patches or Pi protocol-v8 handshakes.
The decoder handles split UTF-8 characters and multiple lines per frame.

```json
{"id":"phone-1","method":"initialize","params":{"protocol":"tspi-host/1"}}
{"id":"phone-1","result":{"protocol":"tspi-host/1","epoch":"host-epoch","capabilities":[]}}
{"id":"phone-2","method":"session/attach","params":{"workspace_id":"ts_001","session_id":"session-1"}}
```

Responses contain `id` and either `result` or `error:{code,message,retryable}`.
Notifications contain `method` and `params`. `workspace/list` / `workspace/create`
manage projects. `session/list`, `session/create`, `session/resume`,
`session/read`, `session/attach`, and `session/remove` use explicit workspace
identity. Models use `models/list` and `model/select`. The legacy Pi protocol-v8
adapter remains available only for compatibility; default app entry points
instantiate `HostGateway`.

## State and reconnection

`session/read` and `session/attach` return `{session,snapshot,epoch,sequence}`.
`session/event` carries workspace/session identity plus the same snapshot,
epoch and sequence. A client buffers early events while attach is in flight,
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

`turn/interrupt` includes the active turn ID. Model choice is session-scoped.
Pi extension dialogs not exposed by Host stay in the terminal; the phone does
not invent approval authority.

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
