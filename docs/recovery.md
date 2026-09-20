# Recovery

Pi App Server is authoritative for sessions and transcripts. A phone restart,
network loss, or app update does not remove server state.

When the TSPi Link WebSocket closes, TS Phone marks the live view offline and
keeps completed messages and unsent drafts on screen. The next refresh opens a
new v8 connection, performs `hello`, reloads the session directory, attaches
the selected session, and hydrates a complete transcript snapshot before
re-enabling prompts. No prompt is retried automatically.

If a session disappears from `pi.session-directory`, select another session or
create one from the App Server. If the Host is offline, open a workspace with
`TSPi --workspace <name>` or restart `ts-app-server-tspi.service`, then retry.
If device authorization was revoked or the Host identity changed, create a new
code with `TSPi phone pair` and pair the phone again.

For a local terminal, exiting the TSPi client only detaches that client. Stop
the App Server explicitly when maintenance is required. Pi JSONL files under
the workspace `.pi` directory remain the recovery source.
