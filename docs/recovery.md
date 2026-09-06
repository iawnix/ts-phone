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
prompt, abort request, or approval response. Timeline histories up to 2000
items are restored automatically. For larger sessions, use the visible page or
load-all controls; the loaded/total counter distinguishes a partial client view
from missing server history. A matching Bridge reconnect resets the session
revision and replaces the disk-only capability state with its live controller
or observer state.

Pi branches are recovered from the JSONL parent graph. The current leaf can be
interactive only with a live Bridge. Selecting another leaf intentionally makes
the composer read-only; switch back to the active branch before sending.

Reconciliation never deletes files and never removes a live bridge. If any
session history is malformed or unreadable, cleanup stops and retains existing
broker records so storage damage cannot be mistaken for an intentional delete.

Restart a controller with:

~~~bash
./TSPi --workspace <workspace> --phone
~~~

If another process still holds the workspace Root Agent lock, this command
starts a new observer instead. Stop the actual controller first when controller
recovery is intended.
