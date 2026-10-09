# Release artifacts

The mobile release pipeline produces one immutable Android artifact set:

```text
dist/android-current/
  corhub-v<version>-build<build>-arm64-v8a-release.apk
  corhub-v<version>-build<build>-armeabi-v7a-release.apk
  corhub-v<version>-build<build>-x86_64-release.apk
  corhub-v<version>-build<build>-release.aab
  *.attestation.json
  SHA256SUMS  # added by the GitHub publication workflow
```

`apps/mobile/tool/mobile-build-attestation.py` captures the exact Git source,
embeds the source identity manifest (commit/digest, not source files) in each artifact, and verifies the Flutter package name,
version code, ABI, non-debuggable flag, and release certificate. The release
set is content-addressed and switched into place atomically.

The artifact contains only the Flutter client. It does not bundle a CoRHub
server, protocol package, Node runtime, systemd unit, reverse proxy, or Pi
credentials. Host releases are produced independently by ResearchAgent and are
selected by the ResearchAgent installation's package pointer.

To inspect a source attestation:

```bash
python3 apps/mobile/tool/mobile-build-attestation.py verify-source \
  --repository-root . \
  --source-root /private/captured/source \
  --source-snapshot /private/captured/source-snapshot.json
```
