# Security

CoRHub is intentionally unable to act as a server. The only network
transport is an authenticated ResearchAgent Link WebSocket to a trusted Relay.

- Device credentials are kept in platform secure storage and never entered or
  displayed as long-lived text in the app.
- Every connection sends `Authorization: Bearer <token>` and the
  `research-agent-link.v1` subprotocol.
- Pairing codes expire after five minutes and work once. A revoked device is
  disconnected immediately.
- The Host validates `research-agent-host/2` initialization and routes requests by explicit
  workspace/session identity.
- The phone validates JSON RPC responses, UTF-8 framing, event cursors and
  session identities before presenting updates.
- A failed or timed-out request is not replayed automatically.
- Offline history is presentation-only; write actions require a fresh server
  snapshot.

The local Unix socket is private to the ResearchAgent service user and is not exposed by the
phone. Workspace locks, Pi credentials, skills, extensions, and scientific
software are server-side concerns governed by the ResearchAgent installation.

WSS protects Phone-to-Relay and Host-to-Relay traffic. Link 1 does not add
application-level end-to-end encryption, so the Relay operator can observe the
forwarded Host byte stream. Use a trusted Relay or a private network.
