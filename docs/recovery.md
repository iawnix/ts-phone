# Recovery

CoRAgent Host/Pi owns durable sessions and transcripts. A phone restart,
network loss, or app update does not remove server state.

After a Link disconnect the app marks the view offline and retains the current
transcript and draft. Reconnection uses `initialize` with
`coragent-host/2`, reloads sessions and calls `session/attach` to obtain
a fresh snapshot before enabling input. An uncertain input is never retried
automatically; a manual retry retains its original message identity.

If a session is unavailable, select another session or create one. If Host is
offline, check the CoRAgent installation and its managed service, or open
`coragent --workspace <name>`. If authorization was revoked, the Host
identity changed, or the legacy protocol was upgraded, run
`coragent phone pair` and pair again. Do not edit token prefixes.

CoRAgent 0.19.0 stores Pi durable session data in its installation state,
not in a phone database. Follow the server's backup/recovery documentation;
leaving the terminal or phone does not cancel a running server-side task.

Android normally rejects APK downgrades. Prefer publishing a corrected build
with a higher build number; installing an older APK may require uninstalling
first, which deletes local settings and device authorization. The AAB is a store
upload artifact, not a directly installable rollback package. Old protocol
versions also require a compatible server; server workspace data remains separate.
