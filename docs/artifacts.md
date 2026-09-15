# Release artifacts

The mobile release pipeline produces one immutable Android artifact set:

```text
dist/android-current/
  ts-phone-v<version>-build<build>-arm64-v8a-release.apk
  ts-phone-v<version>-build<build>-armeabi-v7a-release.apk
  ts-phone-v<version>-build<build>-x86_64-release.apk
  ts-phone-v<version>-build<build>-release.aab
  *.attestation.json
```

`apps/mobile/tool/mobile-build-attestation.py` captures the exact Git source,
embeds that snapshot in each artifact, and verifies the Flutter package name,
version code, ABI, non-debuggable flag, and release certificate. The release
set is content-addressed and switched into place atomically.

The artifact contains only the Flutter client. It does not bundle a TS Phone
server, protocol package, Node runtime, systemd unit, reverse proxy, or Pi
credentials. App Server releases are produced independently by TSPi and are
selected by the TSPi installation's package pointer.

To inspect a source attestation:

```bash
python3 apps/mobile/tool/mobile-build-attestation.py verify-source \
  --repository-root . \
  --source-root /private/captured/source \
  --source-snapshot /private/captured/source-snapshot.json
```
