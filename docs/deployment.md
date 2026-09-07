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

Server version 0.7.0 adds persistent project/session management and guarded
Worker activation and deletion. Mobile version 0.14.0 adds matching management
screens, localized lifecycle views, and an accessible connection icon. Existing
history, research timelines, active model, and context usage remain available.
Mobile and server release numbers are independent; compatibility is governed by
the protocol versions in this table:

| Component | Required version | Contract |
| --- | ---: | --- |
| TS Phone server | 0.7.0 | API v4, Events v3, Bridge v3, persistent management and lifecycle guards |
| TSPi package | 0.13.0 | Bridge v3, exact session Workers, preflight/2 and guard/1 |
| Mobile app | 0.16.0+41 | API v4, work home, explicit conversation navigation and sidebar |

This is the source compatibility set for this change; it does not assert that
production has been upgraded. Previous installed releases remain recorded in
`artifacts.md`. Each release is bound to its manifest's protocol set.

App 0.16.0 opens a work home, not the previous conversation. Recent entries use
summary requests only; project/session management remains in lists and menus.
Explicitly opened history does not activate a Worker and loads
the latest 50 items first. Continue conversation is an explicit action that
preserves drafts and never sends them automatically. Settings retain full-label
choice sheets and show the actual Host version. An older Host can
still serve API v4 history while lacking the new creation endpoints; a successful
health check alone is not proof that project/session management is installed.

Keep `TS_PHONE_TSPI` pointed at the stable installation launcher, for example
`/home/iaw/TS-pi-agent/TSPi`, not its resolved release target. TSPi uses the invoked
launcher's directory as the installation root. The Host validates the real target
without replacing that entrypoint when starting Workers or lifecycle checks.

## 1. Build The TS Phone Component

~~~bash
cd /home/iaw/Codex/Project/2026-08-14/ts-phone
env NPM_CONFIG_CACHE=.npm-cache npm ci
npm run test:release
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

The component builder owns the server typecheck, tests, and production build,
all from a private capture of the committed source. Android source capture
checks that the Settings identity matches `pubspec.yaml` before invoking Gradle.
The Android build embeds
that source identity in each signed artifact and writes a matching attestation.
It validates the complete APK/AAB set in private staging, publishes it under a
content-addressed `dist/android-releases/` directory, and only then atomically
switches `dist/android-current`. A failed build never changes the current set.
The component builder verifies the production arm64 APK's Signature Scheme v2
record, pinned certificate, package name, version, build code, ABI, embedded
source identity, and attestation before writing a deterministic archive plus
`ts-phone-component-release.json`. Production builds require a clean committed
checkout. `--allow-dirty` is only for local probes.

The AAB boundary is intentionally narrower. The build verifies strict JAR
signature integrity, exactly one pinned signer, its embedded source identity,
and its attestation, but it does not independently decode the AAB binary
manifest to confirm application ID and version. Run a pinned `bundletool`
validation before store upload. The script also selects fixed local Flutter,
Android SDK, and JDK paths but does not attest those tool binaries, so source
provenance is reproducible while bit-for-bit cross-machine output is not yet a
release claim.

## 2. Build The Complete TSPi Package

Run these commands in the authored TSPi checkout, not the active installed
release:

~~~bash
cd /home/iaw/Codex/Project/2026-06-13/TSPi
export TSPI_ANDROID_BUILD_TOOLS=/home/iaw/soft/android/sdk/build-tools/36.0.0
python3 scripts/test_source.py \
  --conda-root /home/iaw/soft/conda/2026.03.05 \
  --with-render \
  -- -q
npm run typecheck
python3 scripts/build_package.py \
  --phone-manifest /home/iaw/Codex/Project/2026-08-14/ts-phone/dist/component/ts-phone-component-release.json \
  --output-dir dist/package \
  --json
~~~

The suite builder creates the Agent component internally, independently
verifies the Phone APK and attestation, checks Agent, Web, and Phone
compatibility, and produces one `tspi-package-release/2` manifest and one
content-addressed archive. Both source identities and both component IDs are
bound into that result.

## 3. Install The Package Without Service Activation

Install the complete component set into the TSPi root. Runtime preparation and
the scientific capability probe complete before the release is selected:

~~~bash
cd /home/iaw/Codex/Project/2026-06-13/TSPi
python3 scripts/install_package.py \
  --manifest dist/package/tspi-package-release.json \
  --install-root /home/iaw/TS-pi-agent \
  --conda-root /home/iaw/soft/conda/2026.03.05 \
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
   Set `TS_PHONE_TSPI=/home/iaw/TS-pi-agent/TSPi`; without it the Host remains a
   read-only session browser and cannot activate managed sessions.
3. Make the user service invoke the suite-owned stable launcher. For the
   standard installation, its effective service settings must include:

~~~ini
[Service]
WorkingDirectory=/home/iaw/TS-pi-agent
EnvironmentFile=/home/iaw/.config/ts-phone/server.env
ExecStart=
ExecStart=/home/iaw/TS-pi-agent/TSPhoneServer
ReadWritePaths=/home/iaw/.local/state/ts-phone
ReadWritePaths=/home/iaw/TS-pi-agent/workspaces
ReadWritePaths=-/home/iaw/TS-pi-agent/.pi/runtime-cache
ReadWritePaths=-/home/iaw/TS-pi-agent/.agents/runtime
ReadWritePaths=-/home/iaw/TS-pi-agent/.agents/envs
~~~

`ProtectHome=read-only` applies to TSPi child processes too. The explicit paths
above are required for workspace/Pi sessions and the managed Python/cache state.
Keep all other Home paths read-only. If a notification provider must refresh a
credential, add only that provider's private state directory through a local
systemd drop-in; do not make the whole skill, config tree, or Home writable.

4. Reload and restart the broker, then verify the exact API contract:

~~~bash
systemctl --user daemon-reload
systemctl --user restart ts-phone.service
systemctl --user status ts-phone.service --no-pager
curl --fail --silent --show-error http://127.0.0.1:22113/healthz
~~~

5. Exit legacy phone-mode TSPi processes only after their active turn has
   finished. The app can then activate a managed controller through the Host.
   Manual startup remains available for diagnostics:

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
11. Open a research session with TS activities and verify the first request
    loads at most 50 items without starting a Worker. Verify older pages remain
    accessible and load-all reaches the total count.
12. Select a historical Pi branch and verify the composer becomes read-only,
    then return to the current branch and verify sending is restored.
13. Create and rename a project and conversation, then archive and restore both.
14. Move a project with no remote work to Recently Deleted, restart the Host,
    restore it, and confirm its scientific state and Pi history are unchanged.
15. Verify a project with an active Worker or unresolved remote effect cannot be
    moved to Recently Deleted. Permanently delete only a disposable test project
    after entering its exact ID.

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
