# TS Phone

TS Phone is the Android and iOS companion for the TSPi transition-state
research runtime. It exposes only registered TSPi workspaces through an
authenticated HTTPS API and synchronizes each visible Pi session over SSE.

Version 0.5.0 restores every validated workspace-local Pi session after a
service restart and projects its authoritative Pi JSONL as a structured,
paginated research timeline. Conversation messages, deterministic research
operations, subagent runs, failures, Turn boundaries, and Pi branches share one
read model without creating a second conversation database. Raw custom records,
thinking, provider metadata, and unapproved fields never cross the server
boundary.

Mobile version 0.9.1 distinguishes live, observer, recovery, history-only, and
historical-branch views. Histories up to 2000 projected items load completely by
default; larger sessions show loaded/total progress and support one-page or
load-all retrieval while preserving the visible scroll anchor. The current Pi
branch remains interactive when its Bridge is live, while earlier branches are
explicitly read-only. Servers that do not advertise `history.timeline` continue
to use the compatible `/messages` path. The command-style conversation header,
adaptive iOS-style composer, node-based workspace identity, compact workspace
status, measured latency and last-sync metadata, restrained glass hierarchy,
terminal/code presentation, on-demand connection diagnostics, and the TSPi
character brand mark remain shared by the Chinese and English UI. API v3,
Events v3, and Bridge v2 remain wire-compatible.

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

## Component Release

TS Phone remains an independent source repository, but production TSPi
distribution uses it as a versioned component rather than a second installation
authority. Build the production-signed arm64 APK first, then create the
deterministic component archive:

~~~bash
python3 deploy/build-component-release.py \
  --output-dir dist/component \
  --json
~~~

The builder runs server typecheck, tests, and build; verifies the APK v2
signature and signer certificate; and writes
`ts-phone-component-release/1`. The manifest binds server `0.5.0`, mobile
`0.9.1+29`, API v3, Events v3, Bridge v2, the server entry, APK, source commit,
and deterministic archive digest.

The TSPi repository consumes this manifest with `build_package.py` and
produces the complete Agent + embedded Web + Phone TSPi Package. Its suite
installer selects one compatible set under `.pi/packages/tspi/current` and
installs `TSPi`, `TSWeb`, `TSPhoneCtl`, and `TSPhoneServer` launchers. It does
not start the broker or install the APK onto a phone.

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

Complete deployments are selected by the TSPi Package, not by a second Phone
`current` pointer. Server version 0.5.0 is compatible with TSPi 0.11.0 and the
API v3-compatible 0.9.1 mobile client. API v3 and Bridge v2 remain intentional
compatibility breaks from older releases.

See docs/deployment.md before changing the running service. Configuration,
tokens, service activation, FRP, HTTPS, and device installation remain outside
immutable Package releases. `deploy/install-local.sh` is retained for
standalone component development and legacy deployments only; do not use its
`/home/iaw/soft/ts-phone/current` pointer as a second production authority next
to a suite-managed installation.
