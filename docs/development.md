# Development

Use Flutter 3.44.0 (Dart 3.12), Python 3.10+, Git and the committed pub lock.
Android release builds additionally require JDK 17, SDK platform 36 and
build-tools 36.0.0. Node is needed only by the ResearchAgent interop fixture;
this repository is not an npm package.

## Independent checks

`tool/iterate.sh dev` runs from a Git checkout. It snapshots tracked and
non-ignored source into a new private directory, sets temporary/cache paths,
then runs Python release-tool tests, locked pub resolution, Dart format,
Flutter analyze and all independent `*_test.dart` files. The Host interop file
is deliberately run by the separate suite below. No server is started by this
independent suite. Detailed logs remain local and are not uploaded.

On this workstation, use the private SDK and existing offline cache:

```bash
export TS_PHONE_TEST_ROOT=/home/iaw/project/TSPi/local_debug/ts-phone
export FLUTTER_BIN=/home/iaw/project/TSPi/local_debug/deps/flutter/3.44.0/bin/flutter
export PUB_CACHE=/home/iaw/project/TSPi/local_debug/deps/flutter-pub
export TS_PHONE_OFFLINE=1
./tool/iterate.sh dev
```

If these dependencies are absent, prepare a Flutter SDK copy and package cache
under `/home/iaw/project/TSPi/local_debug/` first. Installed software under
`/home/iaw/soft` can be copied as a seed; do not run test SDK/cache writes there.
On another workstation set `TS_PHONE_TEST_ROOT`, `FLUTTER_BIN` and `PUB_CACHE`
to private local locations. CI uses ephemeral runner directories and does not
upload test artifacts, logs or caches.

## Real Host/Pi interoperability

From the TSPi checkout, after preparing its deterministic test environment:

```bash
python3 tools/test/runner.py phone \
  --phone-source /home/iaw/project/ts-phone \
  --flutter-root /home/iaw/project/TSPi/local_debug/deps/flutter/3.44.0 \
  --pub-cache /home/iaw/project/TSPi/local_debug/deps/flutter-pub
```

This uses real Dart transport, a real local ResearchAgent Host/Pi worker, fake
credentials and a deterministic local model. The runner captures both source
trees, isolates networking and cleans up owned processes. Follow TSPi's test
instructions rather than launching the fixture manually. Tests and evidence
must remain under its `local_debug/`; do not upload that content.

Neither suite is an installed Android/iOS device test. Record device acceptance
separately, including app build, server version, pairing, session creation,
messaging, reconnection, model selection and monitor controls.
