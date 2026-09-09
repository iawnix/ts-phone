# Recovery

Pi session JSONL is the authoritative conversation record. TS Phone reads a
bounded projection from disk for an offline session and maintains a separate
live snapshot and event journal while its Bridge is connected. The event
journal is a replay aid, not a second conversation database.

If one session disconnects while idle, only that session becomes offline. Other
controller or observer sessions in the same workspace remain connected.

If a bridge disconnects while its Pi agent is running, that session enters
recovery_required and the command outcome is treated as ambiguous. Do not retry
the prompt automatically. Inspect that session TUI and its recovered Pi
messages, then restart it deliberately.

A bridge reconnect changes sessionRevision. Mobile clients must discard the old
stream cursor, fetch the new session snapshot, and wait for the new SSE stream
before enabling prompt, abort, or approval actions.

SSE history is intentionally bounded. A fresh connection, or a reconnect whose
`Last-Event-ID` has fallen outside that window, receives the latest session
snapshot before newer events. Clients must treat that snapshot as a replacement
of the live view and continue from its event ID; they must not replay the
missing prompt or infer delivery from a cursor gap.

An abort conflict is not an ambiguous command outcome. `agent_not_running`
means the observed run already settled; `agent_run_stale` means another run is
now active. In both cases refresh the session snapshot and do not retry the old
abort. Only a timeout or disconnect without an acknowledgement remains
ambiguous.

An offline broker record remains visible only while its workspace-local Pi
session JSONL still exists. Deleting that history removes the disconnected
record on the next workspace/session refresh. Deleting the workspace removes all
of its broker records. The mobile workspace and session lists refresh whenever
the app returns to the foreground; while they remain open, pull to refresh or
use the refresh action.

Opening offline history does not start a Worker. With `command.queue`, Send
persists a request and the Host starts the conversation when its workspace is
idle. No Continue or mode selection is needed. Older bridge-only Hosts retain
explicit activation; offline history on those Hosts cannot accept a prompt,
abort or approval. The latest 50 items load first.
Use the visible page or load-all controls for older history; the loaded/total counter distinguishes a partial client view
from missing server history. A matching Bridge reconnect resets the session
revision and replaces the disk-only capability state with its live controller
or observer state.

Pi branches are recovered from the JSONL parent graph. The current leaf can
receive queued requests without a live Worker. Selecting another leaf intentionally makes
the composer read-only; switch back to the active branch before sending.

Project and conversation names, access/model preferences, lifecycle states, and
management revisions are recovered from owner-only `management.json`. Active,
Archived, and Recently Deleted are explicit views. Recently Deleted is not
automatically emptied; restore an item or permanently delete it from the app.

Permanent deletion first moves the target to a same-filesystem quarantine. If
metadata removal or quarantine deletion fails, the Host attempts to restore the
remaining files at the original path, exact management snapshot, and terminal
command receipts. Recursive
removal is irreversible; inspect remaining files after any purge failure, even
if metadata has been restored to Recently Deleted. A
`purge_recovery_failed` response means compensation itself was incomplete: stop
the Host, preserve `.ts-phone-purge-*` paths, `management.json` and `commands.json`,
and reconcile them before restarting. A process interruption during permanent
deletion also requires inspection. Do not create a replacement project with the same ID.

Reconciliation never deletes files and never removes a live bridge. If any
session history is malformed or unreadable, cleanup stops and retains existing
broker records so storage damage cannot be mistaken for an intentional delete.

The app can continue an offline managed session when `TS_PHONE_TSPI` is
configured. The ordinary terminal attaches to the same Host with:

~~~bash
./TSPi --workspace <workspace> --phone
~~~

This opens a client, not another Pi process. If an external process holds the
workspace Root lock, queued work waits; inspect and close that process normally
after it settles. Native diagnostics use `--standalone --phone`; add
`--phone-access observer` only for an explicitly restricted separate assistant.

The app can continue an existing session without a terminal when Session Host
and the guard-compatible launcher are installed. The dispatcher transfers only
idle Host-owned execution to the next queued conversation. External CLIs, pending
inputs, active runs and uncertain Workers block switching. A failed new start
does not restart a source that was explicitly stopped. History is retained.
If compatibility checks fail before the source is stopped, the existing runtime
remains usable. If stopping the source is uncertain, that source requires
recovery and the target is not started. These failures are not equivalent.

`session_guard_upgrade_required` requires the matching Package installer to
finish guard enrollment after old TSPi writers have exited. Do not edit the
installation record or `management.json` to bypass it. `session_writer_unverified`
means a Bridge could not prove its exact process identity and held guards; it is
not an instruction to upgrade an otherwise valid history. `model_auth_missing` concerns host model credentials,
not the Phone token. `model_storage_unavailable` means that Pi cannot access or
lock its credential/cache storage; check the service's `ReadWritePaths` against
the actual `PI_CODING_AGENT_DIR` (default `~/.pi/agent`). Reading these files also
requires a writable lock directory. `model_check_failed` is a different local
configuration/refresh failure. None of these means that the model generated an
empty answer. `worker_cleanup_uncertain` requires inspection of the owned
process before another startup. Never unlink occupied guard files.

Returning from a chat does not cancel or resend a pending prompt. The mobile
session keeps its request ID and receipt until the request completes. Confirmed
rejections restore the submitted draft only if it has not been edited since;
uncertain requests remain separate from the draft. An explicit retry first
synchronizes and reuses the original ID and session revision. This in-memory
state survives page navigation, not app process termination. Host queue receipts
survive both. An absent receipt never authorizes automatic resend.

Back from an approval panel defers the decision. Use **Pending approvals** in
the chat to reopen it; only the explicit approve/reject controls send a decision.

`session_writer_active` means a real writer or lifecycle guard blocks startup;
close the owning runtime after it settles. Normal guarded startup no longer
scans unrelated Pi processes or their private environment. A remaining
`session_writer_inspection_failed` from an older installation requires the
Package repair and installation diagnostics, not closing other projects or
granting the Host broader privileges. Legacy process inspection is an installer
upgrade check, outside normal activation. `session_guard_invalid` requires inspection
of the session history and owner-only guard files, not their deletion.
These failures occur before model execution. The service journal records the
safe code under `worker_start_failed`; the API and journal do not expose raw
launcher/provider stderr.

`worker_start_failed`, `worker_start_timeout`, and `worker_start_interrupted`
mean the requested runtime did not reach readiness. Refresh the session state
before a new activation; no draft has been sent by activation. Raw Worker stderr
is not forwarded to the Phone API.
An `activation_outcome_unknown` client error instead means the response was not
received. The Host may still finish activation. Refresh authoritative state;
do not infer failure, create another session, or automatically replay the request.

Guard checks use Linux `/proc` and owner-only installation operational state.
Stop/reopen replaces managed in-process new/resume/fork. Reopening preserves
the original Pi context and does not copy history or replay prompts/jobs.
Legacy direct prompt receipts remain bounded and in memory. Queue receipts are
durable; orphan process adoption is not implemented. Normal Host shutdown stops
its Workers, not external CLIs.

## Queued Requests

The request list shows waiting, starting, running and interrupted requests.
Waiting requests may be cancelled. Stopping generation is a separate action;
neither cancels remote jobs. Requests run even after the submitting client
disconnects. A next-turn model selection updates future admissions and retargets
requests that are still queued for that conversation. Requests already starting,
running or marked unknown keep the model recorded at execution time.

A lost admission response is reconciled through the exact message ID. Only
`durable:true` confirms the Host saved a queue request; missing data or a legacy
unknown receipt does not. An explicit retry keeps the same message ID and body.

Automatic Pi retries remain part of the same running request. If retries are
exhausted, a confirmed provider failure appears as Failed with a model-service
reason, and the next queued request may run. Upstream HTTP 503 is distinct from
missing local API credentials and from an uncertain delivery. Already executed
tools remain recorded even when the final response fails; check those results
before asking the Agent to repeat work. A failed receipt is not replayed by
reusing its ID. A deliberate new send receives a new ID.

After Host restart, never-started requests remain queued. Requests previously
starting/running become `unknown`; later work in that workspace pauses. Inspect
the Pi history and relevant outputs, confirm the uncertain Worker has stopped,
then use Confirm review in the request list or `/queue` in the terminal.
Acknowledgement releases later requests without repeating the interrupted
request or recording it as successful. Other workspaces remain independent.

`queue_storage_unavailable` requires repairing the private Host state store;
dispatch is suspended. Preserve `commands.json` while inspecting disk space,
ownership and permissions. `queue_capacity_exceeded` means the 32 unfinished
requests, 10,000 receipts or 16 MiB store limit was reached. Waiting requests can
be cancelled to release unfinished capacity; restarting does not erase durable
receipts. There is no automatic history eviction or receipt-reset action.
Explicit permanent deletion of a conversation or project removes its terminal
receipts along with the resource; archiving or moving to Recently Deleted does not.
