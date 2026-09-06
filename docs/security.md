# Security Model

TS Phone is a remote control surface for TSPi, not a low-trust chat relay.

## Network Boundary

- Bind TS Phone to loopback only.
- Keep the FRP proxy data port on loopback at both ends.
- Expose only Nginx HTTPS port 443 publicly.
- Authenticate every API and SSE request except healthz.
- Disable Nginx buffering for SSE.
- Do not log authorization headers, request bodies, prompts, responses, or tool
  output.

The server rejects a non-loopback TS_PHONE_HOST at startup. Aliyun terminates
TLS and can inspect request content; this topology is not end-to-end encrypted
against a compromised Aliyun host.

## Remote Input Boundary

The phone API does not accept arbitrary filesystem paths, shell commands,
environment variables, model credentials, or raw Pi RPC. It does expose fixed
project/session lifecycle actions. With `TS_PHONE_TSPI` configured, a valid
Bearer token can create a workspace directory, start or stop Host-owned TSPi
Workers, archive or trash resources, and request permanent deletion.

The Host validates names, IDs, lifecycle revisions, and the fixed TSPi
entrypoint; these checks do not make the token low privilege. A valid token can
read projected conversations, start a controller, and submit prompts. Protect it
as a high-value credential.

Controller sessions give phone-origin turns the same Tool authority as local
TUI turns. Registered tools, including write, shell, compute, render, report,
notification, and newly added tools, run without a separate phone approval.
The Bearer token must therefore be treated as remote controller access, not as
a low-privilege chat credential.

Observer sessions apply a stricter policy to every turn, including local TUI
input. Only read, grep, find, ls, ts_workspace_context, and
ts_remote_inspect are allowed. All other tools fail closed. The broker also
rejects any approval request from an observer.

Permanent project deletion additionally requires an exact-ID confirmation and
a current TSPi preflight showing no active Worker, remote calculation, pending
approval, or unresolved remote effect. Any preflight or operational-integrity
failure blocks the action. A manually launched Root Agent also blocks deletion,
even without a Bridge connection. Host mutations retain TSPi's writer lock
through quarantine and deletion, verify the resolved workspace path, and reject
new Bridge registrations while guarded. Permanent session deletion removes only the validated
Pi JSONL history; it does not remove scientific workspace data. Recently Deleted
is retained until an explicit restore or permanent delete action, with no
automatic cleanup timer.

## Multi-Session Boundary

The TSPi launcher and broker enforce complementary controls:

- the Root Agent file lock permits one controller process per workspace;
- lock contention in phone mode creates an independent observer Pi session;
- the broker permits one live controller and multiple observers;
- the broker can start only its configured absolute TSPi executable and passes
  structured workspace/session/model/access arguments rather than a command;
- duplicate live registration of the same sessionId is rejected;
- command and event identity includes workspaceId and sessionId;
- mutable commands also require the current sessionRevision;
- abort additionally requires the current Bridge-issued agentRunId, checked by
  both broker and Bridge immediately before Pi is interrupted;
- commands are bound to the exact connection, generation, session, and
  revision.

Access mode is asserted by the local TSPi bridge. The local service account is
inside the trust boundary: a malicious process running as that same Unix user
can access workspace files and local capabilities independently of TS Phone.

## Disk History Boundary

The service indexes only regular `.pi/sessions/*.jsonl` files whose structured
session header contains the expected session ID and the exact registered
workspace root. It rejects symbolic links, files above 64 MiB, unsafe parent
directories, malformed records, and mismatched headers. Reads use
`O_NOFOLLOW`; raw JSONL lines are never returned.

The same message projection boundary is applied to Bridge and disk messages. It
exposes only selected user, assistant, tool-call, and tool-result display fields
and drops thinking and model-provider internals. Structured TS custom records
pass through a separate allowlisted activity projector: only category, status,
bounded labels, node references, duration/token totals, retry status, and a
bounded reference may be returned. Raw custom payloads, action digests,
provider data, and unknown nested fields are not serialized to the phone. This
is not a general secret-redaction layer: visible text, tool arguments, and tool
results may still contain sensitive content.

Individual text and references are bounded, and every response page is capped
at 500 items and six MiB. Pagination and branch selection accept only stable
eight-character Pi entry IDs found exactly once in the validated graph;
unknown, duplicate, and non-leaf branch cursors are rejected. An inactive
branch response never advertises command capabilities. The Bearer token can
still read projected offline history, so it remains a high-value credential
even when no TSPi process is running.

## Local Capabilities

The bridge socket lives under XDG_RUNTIME_DIR/ts-phone/bridge.sock. Its parent
is mode 0700 and the socket is mode 0600. Registration requires a separate
mode-0600 bridge.secret. The public Bearer token is never accepted as a local
bridge capability.

The shared Bearer token is stored by the app in Android Keystore-backed storage
or the iOS Keychain. Possession grants the complete phone API. Current limits:

- credentials are shared rather than per-device;
- there is no per-device revocation or expiry;
- failed-auth auditing and rate limiting are not yet implemented.

Because controller Tool calls do not require a second confirmation, disclosure
of the shared Bearer token can lead to full controller actions in every live
controller session. Observer sessions remain the appropriate mode for
read-only access.

Rotate auth.token and re-pair all devices after suspected disclosure. Never put
tokens in Nginx, FRP, screenshots, shell history, chat, or source control.

## Mobile Content

The Markdown renderer does not fetch remote images automatically. External
images and links open only after an explicit tap, only over HTTPS, and never
receive the TS Phone Bearer token.

This is a user-consent boundary, not network isolation. An HTTPS hostname can
still resolve to a private or link-local address, and the current mobile HTTP
stack does not pin a validated DNS answer through the TLS connection. The
preview therefore shows the destination host before loading; do not open image
links from untrusted model output. Private-address blocking should only be
claimed after the client owns DNS resolution, socket selection, redirects, and
TLS hostname verification as one tested path.

TS Phone does not request microphone access and does not record, persist,
upload, or proxy audio. A system keyboard may independently provide dictation;
the resulting text enters the same editable composer and crosses the normal
authenticated API boundary only after the user taps Send.

Production APKs and AABs use the private TS Phone release keystore stored
outside this repository. The release build verifies both signature integrity
and that every artifact matches that keystore's SHA-256 certificate
fingerprint. The keystore and password must be backed up together and must never
enter this repository, logs, or distribution artifacts.

Debug/profile builds use a different signer. Android therefore requires the old
test installation to be removed before installing the first production build;
that removal also clears its locally stored token and settings.
