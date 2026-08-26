# Deployment

Production traffic follows this path:

~~~text
Flutter -> HTTPS :443 -> Aliyun Nginx -> 127.0.0.1:22113 (frps)
                                      -> encrypted FRP tunnel
                                      -> 127.0.0.1:22113 (TS Phone)
~~~

The application and FRP data ports remain on loopback. The Aliyun security
group must not expose 22113; only Nginx 443 is public. FRP's control port should
be restricted to known clients.

Server version 0.4.1 restores validated disk sessions and serves bounded
read-only history without a live Bridge. Mobile version 0.8.5 displays that
history, prioritizes active sessions, and switches to live capabilities when
the same Bridge reconnects.
Mobile and server release numbers are independent; compatibility is governed by
the protocol versions in this table:

| Component | Required version | Contract |
| --- | ---: | --- |
| TS Phone server | 0.4.1 | API v3, Events v3, Bridge v2, offline disk history |
| TSPi package | 0.11.0 | Bridge v2 and controller/observer launch policy |
| Mobile app | 0.8.5+27 | API v3, zh/en UI, text-only app composer |

Do not mix the old Bridge v1 or API v2 components with this set.

## 1. Validate TS Phone

~~~bash
cd /home/iaw/Codex/Project/2026-08-14/ts-phone
env NPM_CONFIG_CACHE=.npm-cache npm ci
npm run typecheck
npm test
npm run build
TS_PHONE_SMOKE_PORT=23113 npm run smoke
~~~

Validate Flutter from apps/mobile:

~~~bash
/home/iaw/soft/flutter/bin/dart format --output=none --set-exit-if-changed lib test
/home/iaw/soft/flutter/bin/flutter analyze
/home/iaw/soft/flutter/bin/flutter test
tool/build_release_android.sh
~~~

## 2. Validate And Build TSPi

Run these commands in the authored TSPi checkout, not the active installed
release:

~~~bash
cd /home/iaw/Codex/Project/2026-06-13/transition-state-workflow-refactor
npm run typecheck
python3 scripts/check_package.py
python3 -m pytest -q
python3 scripts/build_release.py --output-dir dist --json
~~~

A production release build requires a clean committed checkout. The
--allow-dirty option is only for local smoke validation and must not be
distributed.

## 3. Stage TS Phone Without Activation

The installer creates an immutable release under
/home/iaw/soft/ts-phone/<version>/. Without --start it does not change current,
the user unit, or the running service.

~~~bash
cd /home/iaw/Codex/Project/2026-08-14/ts-phone
bash deploy/install-local.sh
~~~

The release can be staged while the old service is running.

## 4. Coordinated Activation

Wait until all active research turns finish. Do not terminate a running
scientific turn merely to upgrade transport.

1. Exit every TSPi process currently using phone mode.
2. Install the validated TSPi 0.11.0 release with its generated manifest and
   archive. The installer atomically changes the package current pointer.
3. Activate and restart TS Phone 0.4.1:

~~~bash
bash deploy/install-local.sh --start
systemctl --user status ts-phone.service --no-pager
curl --fail --silent --show-error http://127.0.0.1:22113/healthz
~~~

4. Start the desired workspace controller from the TSPi installation:

~~~bash
cd /home/iaw/TS-pi-agent
./TSPi --workspace ts_006 --phone
~~~

5. Run the same command in another terminal only when an observer is desired.
6. On a typical 64-bit Android phone, install
   `dist/ts-phone-v0.8.5-build27-arm64-v8a-release.apk` and reconnect.

The production certificate differs from earlier debug/profile builds. Android
cannot update those test builds in place: uninstall the old app before the first
production install, then reconnect with the server URL and Bearer token. This
clears the old app's local token and settings. Later production releases can
update this release in place as long as the release keystore is preserved.

The installer preserves the existing server.env, auth.token, and bridge.secret.
With --start it restarts an already running service and requires the exact
ts-phone-api/3 health response. It rolls the current link back when activation
or health validation fails.

For boot without an interactive login, an administrator can enable lingering
once:

~~~bash
loginctl enable-linger iaw
~~~

Display the Bearer token only on the local machine:

~~~bash
/home/iaw/.local/bin/ts-phone-ctl token
~~~

## 5. FRP

Reuse the versioned FRP service and shared config under
/home/iaw/soft/frp/config/frpc.toml. Do not install a second FRP unit.

~~~toml
[[proxies]]
name = "ts_phone_server"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22113
remotePort = 22113
transport.useEncryption = true
~~~

The Aliyun FRP server must use proxyBindAddr = "127.0.0.1". The FRP token and
TS Phone Bearer token are different credentials.

## 6. HTTPS

The public origin is https://tsphone.iawnix.xyz. Nginx must disable proxy
buffering for /api/ so SSE deltas arrive immediately.

~~~bash
curl --fail --silent --show-error https://tsphone.iawnix.xyz/healthz
~~~

Nginx access logs must not include authorization headers, bodies, prompts,
responses, or tool output.

## 7. Functional Validation

In the app, verify:

1. The workspace shows one controller after the first TSPi launch.
2. A second launch appears as an observer rather than replacing the controller.
3. Prompts sent to each session appear only in that session.
4. CLI input appears in the matching phone session.
5. Observer read tools work and write-capable tools are blocked.
6. Controller phone-origin tools run without a phone approval prompt.
7. Disconnecting one session does not affect the other session.
8. A stale revision causes resynchronization instead of command delivery.
9. Stop a session and verify its history remains readable but cannot send.
10. Restart TS Phone and verify persisted sessions return before TSPi starts.

Use harmless read-only prompts for the first transport checks.

## Rollback

Rollback to the previous compatible TS Phone set:

1. Exit TSPi phone sessions after any active turn finishes.
2. Restore the previous TS Phone current link and restart the service.
3. Keep TSPi 0.11.0 unless it was changed independently.
4. Reinstall the retained production-signed 0.7.2+19 arm64 mobile build if
   needed.
5. Start phone sessions and verify API v3 plus Bridge v2 connectivity.

Keep at least one verified release of each component until authenticated local
and public checks pass.
