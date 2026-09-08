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

Offline history can be read and manually refreshed, but it cannot accept a
prompt, abort request, or approval response. Opening history does not start a
Worker. Use Continue research to request Controller for the same session; any local draft
still requires an explicit send after activation. The latest 50 items load first.
Use the visible page or load-all controls for older history; the loaded/total counter distinguishes a partial client view
from missing server history. A matching Bridge reconnect resets the session
revision and replaces the disk-only capability state with its live controller
or observer state.

Pi branches are recovered from the JSONL parent graph. The current leaf can be
interactive only with a live Bridge. Selecting another leaf intentionally makes
the composer read-only; switch back to the active branch before sending.

Project and conversation names, access/model preferences, lifecycle states, and
management revisions are recovered from owner-only `management.json`. Active,
Archived, and Recently Deleted are explicit views. Recently Deleted is not
automatically emptied; restore an item or permanently delete it from the app.

Permanent deletion first moves the target to a same-filesystem quarantine. If
metadata removal or quarantine deletion fails, the Host attempts to restore the
remaining files at the original path and exact management snapshot. Recursive
removal is irreversible; inspect remaining files after any purge failure, even
if metadata has been restored to Recently Deleted. A
`purge_recovery_failed` response means compensation itself was incomplete: stop
the Host, preserve `.ts-phone-purge-*` paths and `management.json`, and reconcile
both before restarting. Do not create a replacement project with the same ID.

Reconciliation never deletes files and never removes a live bridge. If any
session history is malformed or unreadable, cleanup stops and retains existing
broker records so storage damage cannot be mistaken for an intentional delete.

The app can activate an offline managed session when `TS_PHONE_TSPI` is
configured. For manual recovery, restart a controller with:

~~~bash
./TSPi --workspace <workspace> --phone
~~~

If another process holds the workspace Root lock or the same session writer
guard, this command fails without downgrading access. Open its conversation or
close that process after the run settles. An explicit
`--phone --phone-access observer` opens a separate read-only assistant.

The app can continue an existing session without a terminal when Session Host
and the guard-compatible launcher are installed. An idle mode/session switch
requires confirmation of the current source revision. External CLIs, pending
inputs, active runs and uncertain Workers block switching. A failed new start
does not restart a source that was explicitly stopped. History is retained.
If compatibility checks fail before the source is stopped, the existing runtime
remains usable. If stopping the source is uncertain, that source requires
recovery and the target is not started. These failures are not equivalent.

`session_guard_upgrade_required` or `session_writer_unverified` requires a
matching TSPi installation and restart of affected unguarded writers, not an
edited `management.json`. `model_auth_missing` concerns host model credentials,
not the Phone token. `worker_cleanup_uncertain` requires inspection of the owned
process before another startup. Never unlink occupied guard files.

`session_writer_active` means a real writer or lifecycle guard blocks startup;
close the owning runtime after it settles. `session_writer_inspection_failed`
means the launcher could not verify a candidate writer through Linux `/proc`.
Check the Host's process visibility and permissions; refreshing the app alone
does not repair that preflight. Unrelated system services are excluded by their
command line before private process state is read. Do not grant the entire Host
root access or disable writer checks. `session_guard_invalid` requires inspection
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
Phone prompt receipts remain bounded and in memory: a Host restart cannot
prove an unconfirmed command's delivery. Durable receipts and orphan adoption
are not implemented. Normal Host shutdown stops its Workers, not external CLIs.
