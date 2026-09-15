# Recovery

Pi App Server is authoritative for sessions and transcripts. A phone restart,
network loss, or app update does not remove server state.

When the Radius WebSocket closes, TS Phone marks the live view offline and
keeps completed messages and unsent drafts on screen. The next refresh opens a
new v8 connection, performs `hello`, reloads the session directory, attaches
the selected session, and hydrates a complete transcript snapshot before
re-enabling prompts. No prompt is retried automatically.

If a session disappears from `pi.session-directory`, select another session or
create one from the App Server. If the App Server is offline, start it for the
workspace with `TSPi --app-server --workspace <name>` and then retry the phone
connection. A changed server UUID means the phone is pointed at a different
workspace installation; update the connection settings deliberately.

For a local terminal, exiting the TSPi client only detaches that client. Stop
the App Server explicitly when maintenance is required. Pi JSONL files under
the workspace `.pi` directory remain the recovery source.
