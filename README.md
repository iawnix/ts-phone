# TS Phone

TS Phone is the Android and iOS companion for the TSPi transition-state
research runtime. It exposes only registered TSPi workspaces through an
authenticated HTTPS API and synchronizes each visible Pi session over SSE.

Version 0.4.1 restores every validated workspace-local Pi session after a
service restart and serves its bounded message history even when no Bridge is
running. Disk history is read-only: prompt and abort commands still require the
matching live Bridge and revision fence.

Mobile version 0.8.5 distinguishes live, observer, recovery, and history-only
sessions. It prioritizes active sessions, loads offline history, keeps sending
disabled, refreshes the snapshot after app resume, and switches to the
Bridge-reported access mode when the same session reconnects. Long timelines
offer direct navigation between the session start and latest message. The
command-style conversation header, adaptive iOS-style composer, node-based
workspace identity, compact workspace status, measured latency and last-sync
metadata, restrained glass hierarchy,
terminal/code presentation, on-demand connection diagnostics, and the TSPi
character brand mark are shared by the Chinese and English UI. API v3, Events
v3, and Bridge v2 are unchanged.

## Session Model

~~~text
one workspace
├── controller: Root Agent lock owner, read/write tools, canonical continued Pi session
└── observers: independent Pi sessions, read-only tools, no Root Agent lock
~~~

The first TSPi process for a workspace becomes the controller. A later phone
launch detects the held Root Agent lock and starts an independent observer
instead of reusing the controller session. Observers can chat and inspect the
workspace, but their tool policy blocks writes, computation, rendering,
reporting, notification, shell, and all unknown tools.

The mobile navigation is:

~~~text
research workspaces -> sessions -> chat
~~~

Each command carries a session revision. A reconnect or session replacement
changes that revision, so stale phone commands fail with
session_resync_required instead of reaching a different Pi process.

## Security Boundary

- The server binds to 127.0.0.1:22113.
- Public traffic reaches it only through HTTPS, Nginx, and the existing FRP
  tunnel.
- API and SSE requests require a high-entropy Bearer token, except healthz.
- The local TSPi bridge uses a separate mode-0600 Unix socket capability.
- The phone API accepts natural-language messages, never filesystem paths,
  shell commands, environment variables, process controls, or raw Pi RPC.
- TS Phone does not request microphone access or capture audio. Dictation
  supplied by the system keyboard remains ordinary editable text.
- One live controller is enforced by both the TSPi Root Agent lock and the
  broker registration policy.
- Prompts, events, deduplication, and recovery state are scoped by workspaceId
  plus sessionId.

See docs/security.md for the full trust model.

## Development

~~~bash
npm install
npm run typecheck
npm test
npm run build
TS_PHONE_SMOKE_PORT=23113 npm run smoke
~~~

Validate the Flutter client from apps/mobile:

~~~bash
/home/iaw/soft/flutter/bin/dart format --output=none --set-exit-if-changed lib test
/home/iaw/soft/flutter/bin/flutter analyze
/home/iaw/soft/flutter/bin/flutter test
~~~

The local Bearer token is created under the configured state directory. Read it
only on this machine:

~~~bash
npm run ctl -- token
~~~

Start the controller for a workspace:

~~~bash
cd /home/iaw/TS-pi-agent
./TSPi --workspace ts_006 --phone
~~~

Run the same command again in another terminal to start an observer while the
controller lock is held.

## Deployment

Validated TS Phone releases are installed under
/home/iaw/soft/ts-phone/<version>/ and selected through
/home/iaw/soft/ts-phone/current. Server version 0.4.1 is compatible with TSPi
0.11.0 and the API v3-compatible 0.8.5 mobile client. API v3 and Bridge v2
remain intentional compatibility breaks from older releases.

See docs/deployment.md before changing the running service. The installer
preserves existing configuration and tokens and does not print secrets.
