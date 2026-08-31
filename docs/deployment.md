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

Server version 0.5.0 restores validated disk sessions and serves both the
compatible message history and a capability-advertised structured research
timeline. Mobile version 0.9.1 displays bounded TS activities and Pi branches,
loads histories up to 2000 items automatically, and switches to live
capabilities when the matching Bridge reconnects.
Mobile and server release numbers are independent; compatibility is governed by
the protocol versions in this table:

| Component | Required version | Contract |
| --- | ---: | --- |
| TS Phone server | 0.5.0 | API v3, Events v3, Bridge v2, structured timeline |
| TSPi package | 0.11.0 | Bridge v2 and controller/observer launch policy |
| Mobile app | 0.9.1+29 | API v3, zh/en UI, timeline branches and activities |

Do not mix the old Bridge v1 or API v2 components with this set.

## 1. Build The TS Phone Component

~~~bash
cd /home/iaw/Codex/Project/2026-08-14/ts-phone
env NPM_CONFIG_CACHE=.npm-cache npm ci
npm run test:release
npm run typecheck
npm test
npm run build
TS_PHONE_SMOKE_PORT=23113 npm run smoke
~~~

Validate Flutter from `apps/mobile`:

~~~bash
cd apps/mobile
/home/iaw/soft/flutter/bin/dart format --output=none --set-exit-if-changed lib test
/home/iaw/soft/flutter/bin/flutter analyze
/home/iaw/soft/flutter/bin/flutter test
tool/build_release_android.sh
cd ../..
python3 deploy/build-component-release.py \
  --output-dir dist/component \
  --json
~~~

The component builder repeats the server typecheck, tests, and build, verifies
the production arm64 APK's v2 signature and certificate, and writes a
deterministic archive plus `ts-phone-component-release.json`. Production builds
require a clean committed checkout. `--allow-dirty` is only for local probes.

## 2. Build The Complete TSPi Package

Run these commands in the authored TSPi checkout, not the active installed
release:

~~~bash
cd /home/iaw/Codex/Project/2026-06-13/TSPi
npm run typecheck
python3 scripts/check_package.py
python3 -m pytest -q
python3 scripts/build_package.py \
  --phone-manifest /home/iaw/Codex/Project/2026-08-14/ts-phone/dist/component/ts-phone-component-release.json \
  --output-dir dist/package \
  --json
~~~

The suite builder creates the Agent component internally, verifies Agent, Web,
and Phone compatibility, and produces one `tspi-package-release/1` manifest and
one content-addressed archive. Both source commits and both component IDs are
bound into that result.

## 3. Install The Package Without Service Activation

Install the complete component set into the TSPi root, then refresh its isolated
Agent runtime:

~~~bash
cd /home/iaw/Codex/Project/2026-06-13/TSPi
python3 scripts/install_package.py \
  --manifest dist/package/tspi-package-release.json \
  --install-root /home/iaw/TS-pi-agent \
  --json

AGENT_ROOT=/home/iaw/TS-pi-agent/.pi/packages/tspi/current/agent
python3 "$AGENT_ROOT/scripts/install_env.py" \
  --package-root "$AGENT_ROOT" \
  --runtime-home /home/iaw/TS-pi-agent/.agents/runtime/transition-state-workflow \
  --env-root /home/iaw/TS-pi-agent/.agents/envs/transition-state-workflow \
  --conda-root /path/to/miniforge3 \
  --with-render \
  --json

readlink -f /home/iaw/TS-pi-agent/.pi/packages/tspi/current
/home/iaw/TS-pi-agent/TSPi --help
/home/iaw/TS-pi-agent/TSWeb --help
/home/iaw/TS-pi-agent/TSPhoneCtl --help
/home/iaw/TS-pi-agent/TSPhoneServer --help
~~~

The Package install atomically selects one Agent, Web, Phone server, and APK set.
It does not start or restart the broker, alter its token/configuration, or push
the APK to a device. Existing TSPi and Phone processes retain the code they
already loaded. A Web process using the stable `TSWeb` entrypoint restarts only
after the selected Agent runtime is ready.

## 4. Coordinated Activation

Wait until all active research turns finish. Do not terminate a running
scientific turn merely to upgrade transport.

1. Confirm the selected Package and managed Agent runtime passed the checks
   above.
2. Preserve `/home/iaw/.config/ts-phone/server.env`, `auth.token`, and
   `bridge.secret` outside the release.
3. Make the user service invoke the suite-owned stable launcher. For the
   standard installation, its effective service settings must include:

~~~ini
[Service]
WorkingDirectory=/home/iaw/TS-pi-agent
EnvironmentFile=/home/iaw/.config/ts-phone/server.env
ExecStart=
ExecStart=/home/iaw/TS-pi-agent/TSPhoneServer
~~~

4. Reload and restart the broker, then verify the exact API contract:

~~~bash
systemctl --user daemon-reload
systemctl --user restart ts-phone.service
systemctl --user status ts-phone.service --no-pager
curl --fail --silent --show-error http://127.0.0.1:22113/healthz
~~~

5. Exit and restart each phone-mode TSPi process only after its active turn has
   finished, then start the desired workspace controller:

~~~bash
cd /home/iaw/TS-pi-agent
./TSPi --workspace ts_006 --phone
~~~

6. Run the same command in another terminal only when an observer is desired.
7. On a typical 64-bit Android phone, install the APK at the suite manifest's
   `components.phone.mobile_artifact.path` under
   `.pi/packages/tspi/current/phone/`, then reconnect.

The production certificate differs from earlier debug/profile builds. Android
cannot update those test builds in place: uninstall the old app before the first
production install, then reconnect with the server URL and Bearer token. This
clears the old app's local token and settings. Later production releases can
update this release in place as long as the release keystore is preserved.

The suite installer intentionally does not own service rollback because a
service restart is an external effect. If health validation fails, stop the
activation and select the previous complete Package; do not mix the new Agent
with the old Phone component. `deploy/install-local.sh` and the source-tree unit
are standalone development/legacy tools and must not establish a second
production `current` pointer beside the suite.

For boot without an interactive login, an administrator can enable lingering
once:

~~~bash
loginctl enable-linger iaw
~~~

Display the Bearer token only on the local machine:

~~~bash
/home/iaw/TS-pi-agent/TSPhoneCtl token
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
11. Open a research session with TS activities and verify its loaded count
    reaches the total count when the total is at most 2000.
12. Select a historical Pi branch and verify the composer becomes read-only,
    then return to the current branch and verify sending is restored.

Use harmless read-only prompts for the first transport checks.

## Rollback

Rollback to the previous complete TSPi Package:

1. Exit TSPi phone sessions after any active turn finishes.
2. Run `install_package.py` with the retained previous suite manifest and
   archive.
3. Refresh that selected Agent runtime, restart the suite-owned Phone service,
   and verify health.
4. Reinstall the previous manifest-bound arm64 APK if mobile compatibility
   changed.
5. Start phone sessions and verify the selected API and Bridge protocols.

Keep at least one verified complete Package archive and manifest until
authenticated local and public checks pass. Component archives alone are not a
supported production rollback selector.
