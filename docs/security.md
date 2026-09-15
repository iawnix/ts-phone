# Security

TS Phone is intentionally unable to act as a server. The only network
transport is an authenticated Pi Radius WebSocket to an App Server selected by
its UUID.

- Radius credentials are kept in platform secure storage.
- Every connection sends `Authorization: Bearer <token>` and the
  `pi-session-relay.client.v1` subprotocol.
- The App Server validates the protocol v8 hello and binds requests to the
  advertised server/session target.
- Frame lengths, CBOR values, service identifiers, and attachment identities
  are validated before they reach the UI.
- A failed or timed-out request is not replayed automatically.
- Offline history is presentation-only; write actions require a fresh server
  snapshot.

The local Unix socket is private to the TSPi user and is not exposed by the
phone. Workspace locks, Pi credentials, skills, extensions, and scientific
software are server-side concerns governed by the TSPi installation.
